import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:fyp/MI%20Placeholder.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';
import 'package:fyp/word_api_service.dart';
import 'package:fyp/keypoint_extractor.dart';
import 'package:fyp/tts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart';

/// Word → Sentence screen (on-device keypoint extraction version).
///
/// Pipeline per camera frame:
///   CameraImage → [hand_landmarker] → hands (cached)
///                → [flutter_pose_detection] → pose (awaited)
///   → KeypointExtractor.build() → 258 floats
///   → rolling 30-frame window → WordApiService.predictSequence() → word
///
/// ⚡ PERF FIX (see below): prediction network calls used to run
/// *inside* the per-frame handler with `_isProcessingFrame` held true
/// the whole time, which completely stalled camera-frame processing
/// until the server responded. Now, once a window of frames is full,
/// we snapshot it, clear the buffer, and fire the prediction off in
/// the background — so the next window starts collecting immediately
/// instead of waiting for the network round-trip.
///
/// ⚠️ Needs on-device testing/tuning — see notes in keypoint_extractor.dart
/// about the left/right hand guess and feature order assumptions.
class WordToSentenceScreen extends StatefulWidget {
  const WordToSentenceScreen({super.key});
  @override
  State<WordToSentenceScreen> createState() => _WordToSentenceScreenState();
}

class _WordToSentenceScreenState extends State<WordToSentenceScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // ── Camera ──────────────────────────────────────────────
  CameraController? _ctrl;
  List<CameraDescription> _cameras = [];
  int _camIdx = 0;
  bool _loading = true;
  String _status = 'Starting...';

  // ── ML plugins ──────────────────────────────────────────
  HandLandmarkerPlugin? _handPlugin;
  NpuPoseDetector? _poseDetector;
  List<Hand> _latestHands = [];
  bool _isProcessingFrame = false;

  // ── Detection state ─────────────────────────────────────
  bool _detecting = false;
  bool _sending = false;
  int _detectionSession = 0;
  int _noHandFrames = 0;
  int _framesSincePrediction = 0;
  bool _hasSubmittedInitialWindow = false;
  List<List<double>>? _pendingSequence;
  int? _pendingSequenceSession;
  DateTime _lastCapture = DateTime.fromMillisecondsSinceEpoch(0);
  // How often we grab a frame's keypoints (on-device only, no network —
  // cheap). Actual collection speed is limited by on-device landmark
  // processing; this value only prevents unnecessary frame backlog.
  static const int _CAPTURE_INTERVAL_MS = 35;
  final List<List<double>> _frameBuffer = [];
  static const int _SEQUENCE_LEN = 30;

  // The backend model still requires 30 frames, but after the first complete
  // window we predict again every few NEW frames instead of throwing all 30
  // frames away and starting from zero. This makes follow-up predictions feel
  // close to real time while preserving the exact model input shape.
  static const int _PREDICTION_STRIDE = 6;

  // ⚡ PERF: pose detection (NPU inference) is the slowest step per frame
  // — often 100-300ms. Running it on every single frame is what makes
  // collecting 30 frames feel so slow. Body pose doesn't change nearly
  // as fast as hand shapes do, so we run the (expensive) pose model
  // every fourth usable frame and reuse the previous pose result in between.
  // Hands are still detected fresh for every processed frame.
  int _frameCounter = 0;
  dynamic _cachedPoseResult;
  static const int _POSE_EVERY_N_FRAMES = 4;

  // Light landmark smoothing removes camera/detector jitter without flattening
  // the actual sign motion. It is reset as soon as the hand disappears.
  List<double>? _smoothedKeypoints;
  static const double _SMOOTHING_CURRENT_WEIGHT = 0.72;

  // ── Results ─────────────────────────────────────────────
  final List<String> _sentence = [];
  double _bufferFill = 0.0;
  String? _candidateWord;
  int _candidateWordHits = 0;
  DateTime _candidateUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _latchedWord;

  static const double _CONF_MIN = 0.75;
  static const double _HIGH_CONFIDENCE = 0.96;
  static const int _STABLE_WORD_HITS = 2;
  static const int _RELEASE_FRAMES = 3;

  final TtsService _tts = TtsService();
  late final AnimationController _ring;

  // ════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ring = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
    WordApiService.warmUp();
    _init();
  }

  // Set once hand + pose models are fully loaded and ready to use.
  bool _pluginsReady = false;

  Future<void> _init() async {
    // ⚡ KEY FIX: ML models are (usually) already loaded by MlPreloader,
    // kicked off in the background from HomeScreen the moment the app
    // opened. We just grab those instances here instead of loading them
    // from scratch. If for some reason they're not ready yet (e.g. user
    // navigated here super fast), MlPreloader.preload() just returns the
    // same in-flight future — no duplicate loading happens.
    //
    // TTS init + ML preload-completion both run in the background while
    // we go straight for camera permission + camera controller init, so
    // the preview shows up as soon as the camera itself is ready.
    final ttsFuture = _tts.init();
    final pluginsFuture = _initPlugins();

    final perm = await Permission.camera.request();
    if (!perm.isGranted) {
      _setStatus('Camera permission denied');
      return;
    }
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      _setStatus('No camera found');
      return;
    }
    _camIdx =
        _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    if (_camIdx < 0) _camIdx = 0;

    // Camera preview appears now — doesn't wait on TTS/plugins below.
    await _startCamera(_camIdx);

    // Make sure TTS + ML plugins are done loading too (usually they're
    // already done, since HomeScreen kicked off the ML preload well
    // before the user even tapped into this screen).
    await Future.wait([ttsFuture, pluginsFuture]);
  }

  Future<void> _initPlugins() async {
    try {
      await MlPreloader.preload();
      _handPlugin = MlPreloader.handPlugin;
      _poseDetector = MlPreloader.poseDetector;
      _pluginsReady = _handPlugin != null && _poseDetector != null;
      if (mounted) setState(() {});
    } catch (e) {
      _pluginsReady = false;
      debugPrint('ML model initialisation error: $e');
      if (mounted) {
        _setStatus('AI models failed to load — reopen this screen to retry');
      }
    }
  }

  Future<void> _startCamera(int idx) async {
    if (!mounted) return;
    setState(() => _loading = true);

    final old = _ctrl;
    _ctrl = null;
    try {
      await old?.stopImageStream();
    } catch (_) {}
    try {
      await old?.dispose();
    } catch (_) {}
    if (!mounted) return;

    final cam = CameraController(
      _cameras[idx],
      // Medium gives enough detail for landmarks while avoiding the heavy
      // per-frame cost of high-resolution YUV pose processing.
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await cam.initialize();
      if (!mounted) {
        cam.dispose();
        return;
      }
      _ctrl = cam;
      _setStatus('Ready');
    } catch (e) {
      if (mounted) _setStatus('Camera error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Detection toggle ─────────────────────────────────────
  Future<void> _toggleDetect() async {
    if (_detecting) {
      await _stopDetect();
    } else {
      await _startDetect();
    }
  }

  Future<void> _startDetect() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    if (!_pluginsReady) {
      _setStatus('Still loading AI models… try again in a sec');
      return;
    }
    _detectionSession++;
    _frameBuffer.clear();
    _frameCounter = 0;
    _cachedPoseResult = null;
    _smoothedKeypoints = null;
    _noHandFrames = 0;
    _framesSincePrediction = 0;
    _hasSubmittedInitialWindow = false;
    _pendingSequence = null;
    _pendingSequenceSession = null;
    _candidateWord = null;
    _candidateWordHits = 0;
    _latchedWord = null;
    if (!mounted) return;
    setState(() {
      _detecting = true;
      _status = 'Detecting...';
      _bufferFill = 0.0;
    });
    await _ctrl!.startImageStream(_onCameraFrame);
  }

  Future<void> _stopDetect() async {
    _detectionSession++;
    try {
      await _ctrl?.stopImageStream();
    } catch (_) {}
    _frameBuffer.clear();
    _pendingSequence = null;
    _pendingSequenceSession = null;
    _framesSincePrediction = 0;
    _hasSubmittedInitialWindow = false;
    _smoothedKeypoints = null;
    _candidateWord = null;
    _candidateWordHits = 0;
    _latchedWord = null;
    if (mounted) {
      setState(() {
        _detecting = false;
        _bufferFill = 0.0;
        _status = 'Stopped';
      });
    }
  }

  // ── Per-frame pipeline ────────────────────────────────────
  Future<void> _onCameraFrame(CameraImage image) async {
    if (!_detecting ||
        _isProcessingFrame ||
        _handPlugin == null ||
        _poseDetector == null) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastCapture).inMilliseconds <
        _CAPTURE_INTERVAL_MS) {
      return;
    }

    _isProcessingFrame = true;
    _lastCapture = now;
    try {
      final controller = _ctrl;
      if (controller == null || !controller.value.isInitialized) return;
      final rotation = controller.description.sensorOrientation;

      try {
        _latestHands = _handPlugin!.detect(image, rotation);
      } catch (e) {
        _latestHands = [];
        debugPrint('hand detect error: $e');
      }

      // Never fill the sequence with zero-hand frames. Apart from improving
      // accuracy, this skips expensive pose inference while nobody is signing.
      if (!KeypointExtractor.hasUsableHands(_latestHands)) {
        _noHandFrames++;
        _smoothedKeypoints = null;

        if (_noHandFrames >= _RELEASE_FRAMES) {
          _latchedWord = null;
          _candidateWord = null;
          _candidateWordHits = 0;
          _frameBuffer.clear();
          _pendingSequence = null;
          _pendingSequenceSession = null;
          _framesSincePrediction = 0;
          _hasSubmittedInitialWindow = false;
          if (mounted && _noHandFrames == _RELEASE_FRAMES) {
            setState(() {
              _bufferFill = 0.0;
              _status = 'Show your hand clearly inside the frame';
            });
          }
        }
        return;
      }
      _noHandFrames = 0;

      // After accepting a word, wait for a brief hand release before starting
      // the next sequence. This avoids transition frames being classified as
      // an unrelated extra word and also stops unnecessary network requests.
      if (_latchedWord != null) return;

      _frameCounter++;
      if (_frameCounter % _POSE_EVERY_N_FRAMES == 0 ||
          _cachedPoseResult == null) {
        try {
          final planes = image.planes
              .map((plane) => {
                    'bytes': plane.bytes,
                    'bytesPerRow': plane.bytesPerRow,
                    'bytesPerPixel': plane.bytesPerPixel,
                  })
              .toList();
          _cachedPoseResult = await _poseDetector!.processFrame(
            planes: planes,
            width: image.width,
            height: image.height,
            format: 'yuv420',
            rotation: rotation,
          );
        } catch (e) {
          debugPrint('pose detect error: $e');
        }
      }

      final rawKeypoints = KeypointExtractor.build(
        poseResult: _cachedPoseResult,
        hands: _latestHands,
      );
      if (rawKeypoints.length != KeypointExtractor.expectedVectorLength) return;

      final keypoints = _smoothKeypoints(rawKeypoints);
      _frameBuffer.add(keypoints);
      if (_frameBuffer.length > _SEQUENCE_LEN) {
        _frameBuffer.removeAt(0);
      }

      if (_frameBuffer.length == _SEQUENCE_LEN) {
        _framesSincePrediction++;
      }

      // Updating the complete screen on every ML frame is expensive. Refresh
      // progress every three frames while keeping capture processing continuous.
      if (mounted &&
          (_frameBuffer.length == 1 ||
              _frameBuffer.length % 3 == 0 ||
              _frameBuffer.length == _SEQUENCE_LEN)) {
        setState(() {
          _bufferFill = _frameBuffer.length / _SEQUENCE_LEN;
          if (_frameBuffer.length < _SEQUENCE_LEN) {
            _status = 'Collecting… ${_frameBuffer.length}/$_SEQUENCE_LEN';
          } else if (!_sending) {
            _status = 'Live prediction active';
          }
        });
      }

      final shouldPredict = _frameBuffer.length == _SEQUENCE_LEN &&
          (!_hasSubmittedInitialWindow ||
              _framesSincePrediction >= _PREDICTION_STRIDE);
      if (shouldPredict) {
        _hasSubmittedInitialWindow = true;
        _framesSincePrediction = 0;
        final snapshot = _frameBuffer
            .map((frame) => List<double>.from(frame))
            .toList(growable: false);
        _queuePrediction(snapshot, _detectionSession);
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  List<double> _smoothKeypoints(List<double> current) {
    final previous = _smoothedKeypoints;
    if (previous == null || previous.length != current.length) {
      final initial = List<double>.from(current, growable: false);
      _smoothedKeypoints = initial;
      return initial;
    }

    final smoothed = List<double>.generate(
      current.length,
      (index) => current[index] * _SMOOTHING_CURRENT_WEIGHT +
          previous[index] * (1.0 - _SMOOTHING_CURRENT_WEIGHT),
      growable: false,
    );
    _smoothedKeypoints = smoothed;
    return smoothed;
  }

  void _queuePrediction(List<List<double>> sequence, int session) {
    if (_sending) {
      // Keep only the newest complete window. Old queued windows become stale
      // very quickly during live signing and reduce both speed and accuracy.
      _pendingSequence = sequence;
      _pendingSequenceSession = session;
      return;
    }

    if (mounted) {
      setState(() => _status = 'Predicting… keep signing naturally');
    }
    unawaited(_sendPredictionInBackground(sequence, session));
  }

  // Network inference runs separately so camera-frame processing continues.
  Future<void> _sendPredictionInBackground(
    List<List<double>> sequence,
    int session,
  ) async {
    _sending = true;
    try {
      final result = await WordApiService.predictSequence(sequence);
      if (!mounted ||
          !_detecting ||
          session != _detectionSession ||
          result == null) {
        return;
      }

      if (result.error != null) {
        setState(() => _status = result.error!);
        return;
      }

      final word = result.prediction?.trim();
      if (word == null || word.isEmpty || result.confidence < _CONF_MIN) {
        if (DateTime.now().difference(_candidateUpdatedAt) >
            const Duration(seconds: 2)) {
          _candidateWord = null;
          _candidateWordHits = 0;
        }
        setState(() => _status =
            'No clear sign (${(result.confidence * 100).toStringAsFixed(0)}%) — keep signing');
        return;
      }

      _handleWordPrediction(word, result.confidence);
    } finally {
      _sending = false;

      final next = _pendingSequence;
      final nextSession = _pendingSequenceSession;
      _pendingSequence = null;
      _pendingSequenceSession = null;
      if (next != null &&
          nextSession != null &&
          _latchedWord == null &&
          mounted &&
          _detecting &&
          nextSession == _detectionSession) {
        // Start the freshest queued prediction immediately; do not wait for the
        // next camera callback or resend older intermediate windows.
        _queuePrediction(next, nextSession);
      }
    }
  }

  void _handleWordPrediction(String word, double confidence) {
    final key = word.toLowerCase();

    // Once a word is accepted, ignore all further labels from that held
    // gesture. Sliding windows naturally contain many of the same frames and
    // can otherwise append a different false label during the transition.
    if (_latchedWord != null) {
      _candidateWord = null;
      _candidateWordHits = 0;
      if (mounted) {
        setState(() => _status = 'Release hands briefly for the next word');
      }
      return;
    }

    final now = DateTime.now();
    final candidateIsFresh =
        now.difference(_candidateUpdatedAt) <= const Duration(seconds: 2);
    if (candidateIsFresh && _candidateWord?.toLowerCase() == key) {
      _candidateWordHits++;
    } else {
      _candidateWord = word;
      _candidateWordHits = 1;
    }
    _candidateUpdatedAt = now;

    // Very strong predictions are accepted immediately. Borderline but valid
    // predictions need a second overlapping window to agree. Because windows
    // advance by only a few frames, confirmation is much faster than before.
    final confirmed = confidence >= _HIGH_CONFIDENCE ||
        _candidateWordHits >= _STABLE_WORD_HITS;
    if (!confirmed) {
      if (mounted) {
        setState(() => _status =
            'Confirming “$word” ($_candidateWordHits/$_STABLE_WORD_HITS) • ${(confidence * 100).toStringAsFixed(0)}%');
      }
      return;
    }

    _candidateWord = null;
    _candidateWordHits = 0;
    _latchedWord = key;
    if (mounted) {
      setState(() {
        _sentence.add(word);
        _status = 'Got: $word (${(confidence * 100).toStringAsFixed(0)}%)';
      });
    }
    _tts.speak(word);
  }

  // ── Sentence helpers ─────────────────────────────────────
  void _backspace() {
    if (mounted) {
      setState(() {
        if (_sentence.isNotEmpty) _sentence.removeLast();
      });
    }
  }

  void _clear() {
    _frameBuffer.clear();
    _pendingSequence = null;
    _pendingSequenceSession = null;
    _framesSincePrediction = 0;
    _hasSubmittedInitialWindow = false;
    _smoothedKeypoints = null;
    _candidateWord = null;
    _candidateWordHits = 0;
    _latchedWord = null;
    if (mounted) {
      setState(() {
        _sentence.clear();
        _bufferFill = 0.0;
      });
    }
  }

  void _speak() {
    final all = _sentence.join(' ');
    if (all.isNotEmpty) _tts.speak(all);
  }

  void _setStatus(String s) {
    if (mounted) {
      setState(() {
        _status = s;
        _loading = false;
      });
    }
  }

  Future<void> _flip() async {
    if (_cameras.length < 2) return;
    final wasDetecting = _detecting;
    if (_detecting) await _stopDetect();
    _camIdx = (_camIdx + 1) % _cameras.length;
    await _startCamera(_camIdx);
    if (wasDetecting) await _startDetect();
  }

  // ── Lifecycle ────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive) {
      _stopDetect();
      final c = _ctrl;
      _ctrl = null;
      try {
        c?.dispose();
      } catch (_) {}
    } else if (s == AppLifecycleState.resumed) {
      if (mounted) _startCamera(_camIdx);
    }
  }

  @override
  void dispose() {
    _stopDetect();
    WidgetsBinding.instance.removeObserver(this);
    _ring.dispose();
    _tts.dispose();
    // Note: _handPlugin / _poseDetector are NOT disposed here — they're
    // shared, app-lifetime instances owned by MlPreloader now (see
    // ml_preloader.dart), not owned by this screen. Disposing them here
    // would break the next visit to this screen.
    final c = _ctrl;
    _ctrl = null;
    try {
      c?.dispose();
    } catch (_) {}
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  // UI (same look as before)
  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        _cameraPreview(),
        _topBar(),
        _bottomPanel(),
      ]),
    );
  }

  Widget _cameraPreview() {
    if (_loading || _ctrl == null || !_ctrl!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: AppColors.accent2),
          const SizedBox(height: 14),
          Text(_status, style: const TextStyle(color: Colors.white70)),
        ])),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _ctrl!.value.previewSize!.height,
          height: _ctrl!.value.previewSize!.width,
          child: CameraPreview(_ctrl!),
        ),
      ),
    );
  }

  Widget _topBar() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _glassBtn(Icons.arrow_back_rounded, () => Navigator.pop(context)),
              _glassPill(Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _detecting ? Colors.greenAccent : Colors.grey)),
                const SizedBox(width: 8),
                Text(_detecting ? 'LIVE' : 'IDLE',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
              ])),
              _glassBtn(Icons.flip_camera_ios_rounded, _flip),
            ],
          ),
        ),
      );

  Widget _bottomPanel() => Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 72),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SENTENCE',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 11,
                                letterSpacing: 1.5)),
                        const SizedBox(height: 4),
                        Text(
                          _sentence.isEmpty ? '—' : _sentence.join(' '),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color:
                                _sentence.isEmpty ? Colors.white24 : Colors.white,
                          ),
                        ),
                      ]),
                ),
                const SizedBox(height: 8),
                // Buffer-fill progress (0 → 30 frames collected)
                if (_detecting)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _bufferFill,
                      minHeight: 5,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.accent2),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(_status,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6), fontSize: 12.5)),
                const SizedBox(height: 16),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _iconBtn(Icons.backspace_outlined, 'Back', _backspace),
                      _iconBtn(Icons.delete_outline_rounded, 'Clear', _clear),
                      _iconBtn(Icons.volume_up_rounded, 'Speak', _speak),
                    ]),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _toggleDetect,
                  child: Container(
                    height: 58,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: _detecting
                          ? [AppColors.danger, const Color(0xFFFF8A5B)]
                          : [AppColors.accent2, const Color(0xFF26C6DA)]),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                            color: (_detecting
                                    ? AppColors.danger
                                    : AppColors.accent2)
                                .withOpacity(0.45),
                            blurRadius: 20,
                            offset: const Offset(0, 6))
                      ],
                    ),
                    child: Center(
                      child: _detecting
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              RotationTransition(
                                  turns: _ring,
                                  child: const Icon(Icons.autorenew_rounded,
                                      color: Colors.white, size: 22)),
                              const SizedBox(width: 10),
                              const Text('Stop',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                            ])
                          : const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 26),
                              SizedBox(width: 6),
                              Text('Start Detection',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                            ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.15))),
                child: Icon(icon, color: Colors.white, size: 22)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
          ]));

  Widget _glassBtn(IconData icon, VoidCallback onTap) => ClipOval(
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Material(
              color: Colors.black.withOpacity(0.35),
              shape: const CircleBorder(),
              child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(icon, color: Colors.white, size: 24))))));

  Widget _glassPill(Widget child) => ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.black.withOpacity(0.35),
              child: child)));
}