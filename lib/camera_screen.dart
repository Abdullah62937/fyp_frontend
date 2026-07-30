import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:fyp/api_service.dart';
import 'package:fyp/tts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {

  // ── Camera ──────────────────────────────────────────────
  CameraController? _ctrl;
  List<CameraDescription> _cameras = [];
  int _camIdx = 0;
  bool _loading = true;
  String _status = 'Starting...';

  // ── Detection loop ─────────────────────────────────────
  Timer? _timer;
  bool _detecting = false;
  bool _busy = false; // only one capture/request at a time
  int _detectionSession = 0; // discards stale responses after stop/flip

  // ── Results ─────────────────────────────────────────────
  String _word = '';
  final List<String> _sentence = [];
  String? _lastLetter;
  double _conf = 0.0;

  // A prediction is committed only after it stays stable for multiple
  // server responses. The latch prevents a held sign from being appended
  // repeatedly; moving away from the sign arms the same letter again.
  String? _candidateLetter;
  int _candidateHits = 0;
  String? _latchedLetter;
  int _missedPredictions = 0;

  // ── TTS + Animation ─────────────────────────────────────
  final TtsService _tts = TtsService();
  late final AnimationController _ring;

  // ── Config ──────────────────────────────────────────────
  static const double _CONF_MIN = 0.72;
  static const double _HIGH_CONFIDENCE = 0.90;
  static const int _STABLE_HITS_WITH_CONFIDENCE = 2;
  static const int _STABLE_HITS_WITHOUT_CONFIDENCE = 2;
  static const int _NEXT_CAPTURE_DELAY_MS = 180;

  // ════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ring = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
    _init();
  }

  Future<void> _init() async {
    await _tts.init();
    final perm = await Permission.camera.request();
    if (!perm.isGranted) {
      _setStatus('Camera permission denied');
      return;
    }
    _cameras = await availableCameras();
    if (_cameras.isEmpty) { _setStatus('No camera found'); return; }

    // ✅ Front camera default
    _camIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front);
    if (_camIdx < 0) _camIdx = 0;

    await _startCamera(_camIdx);
  }

  Future<void> _startCamera(int idx) async {
    if (!mounted) return;
    if (mounted) setState(() => _loading = true);

    // Pehle purana controller safely dispose karo
    final old = _ctrl;
    _ctrl = null;
    try { await old?.dispose(); } catch (_) {}

    if (!mounted) return;

    final cam = CameraController(
      _cameras[idx],
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await cam.initialize();
      if (!mounted) {
        cam.dispose(); // widget gone — controller bhi dispose karo
        return;
      }
      _ctrl = cam;
      _setStatus('Ready');
    } catch (e) {
      if (mounted) _setStatus('Camera error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Detection loop ───────────────────────────────────────
  void _toggleDetect() {
    if (_detecting) {
      _stopDetect();
      if (mounted) setState(() {});
    } else {
      _startDetect();
    }
  }

  void _startDetect() {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    _detectionSession++;
    _resetPredictionTracker(clearLatch: true);
    if (mounted) {
      setState(() {
        _detecting = true;
        _status = 'Detecting...';
      });
    }
    // Start immediately. The next capture is scheduled only after the
    // current server request finishes, so there is no extra 1.2 second wait.
    _scheduleNextCapture(Duration.zero);
  }

  void _scheduleNextCapture([Duration? delay]) {
    _timer?.cancel();
    if (!_detecting || !mounted) return;
    _timer = Timer(
      delay ?? const Duration(milliseconds: _NEXT_CAPTURE_DELAY_MS),
      _capture,
    );
  }

  void _stopDetect() {
    _timer?.cancel();
    _timer = null;
    _detecting = false;
    _detectionSession++;
    _status = 'Stopped';
    _resetPredictionTracker(clearLatch: true);
  }

  Future<void> _capture() async {
    if (!mounted || !_detecting) return;
    final controller = _ctrl;
    if (_busy || controller == null || !controller.value.isInitialized) {
      _scheduleNextCapture();
      return;
    }
    if (controller.value.isTakingPicture) {
      _scheduleNextCapture();
      return;
    }

    _busy = true;
    final session = _detectionSession;
    XFile? picture;
    try {
      picture = await controller.takePicture();
      final result = await ApiService.predictClip(File(picture.path));
      if (!mounted || !_detecting || session != _detectionSession) return;
      _handlePrediction(result);
    } catch (e) {
      if (mounted && _detecting) {
        _registerMiss('Capture error — retrying', countAsRelease: false);
      }
    } finally {
      if (picture != null) {
        try {
          await File(picture.path).delete();
        } catch (_) {}
      }
      _busy = false;
      if (_detecting && session == _detectionSession) _scheduleNextCapture();
    }
  }

  void _handlePrediction(PredictionResult? result) {
    final letter = result?.word?.trim().toUpperCase() ?? '';
    final confidence = result?.confidence ?? 0.0;
    final hasConfidence = result?.hasConfidence ?? false;

    if (letter.isEmpty) {
      final message = result?.message ?? 'No clear sign — move hand and retry';
      final transportProblem = result == null ||
          RegExp(r'timeout|server|connection|http|error', caseSensitive: false)
              .hasMatch(message);
      _registerMiss(message, countAsRelease: !transportProblem);
      return;
    }

    if (hasConfidence && confidence < _CONF_MIN) {
      _registerMiss(
        'Low confidence: $letter (${(confidence * 100).toStringAsFixed(0)}%)',
      );
      return;
    }

    _missedPredictions = 0;
    if (_candidateLetter == letter) {
      _candidateHits++;
    } else {
      _candidateLetter = letter;
      _candidateHits = 1;
    }

    final requiredHits = hasConfidence && confidence >= _HIGH_CONFIDENCE
        ? 1
        : hasConfidence
            ? _STABLE_HITS_WITH_CONFIDENCE
            : _STABLE_HITS_WITHOUT_CONFIDENCE;

    if (_candidateHits < requiredHits) {
      if (mounted) {
        setState(() {
          _conf = confidence;
          final suffix = hasConfidence
              ? ' • ${(confidence * 100).toStringAsFixed(0)}%'
              : '';
          _status = 'Checking $letter ($_candidateHits/$requiredHits)$suffix';
        });
      }
      return;
    }

    // Do not append the same letter continuously while the user holds it.
    if (_latchedLetter == letter) {
      if (mounted) {
        setState(() => _status = 'Move hand before repeating $letter');
      }
      _candidateHits = 0;
      return;
    }

    if (mounted) {
      setState(() {
        _word += letter;
        _conf = confidence;
        _lastLetter = letter;
        _latchedLetter = letter;
        _candidateLetter = null;
        _candidateHits = 0;
        _status = hasConfidence
            ? 'Got: $letter (${(confidence * 100).toStringAsFixed(0)}%)'
            : 'Got: $letter (verified)';
      });
    }
  }

  void _registerMiss(String status, {bool countAsRelease = true}) {
    if (countAsRelease) _missedPredictions++;
    _candidateLetter = null;
    _candidateHits = 0;
    // Require a real, sustained gap. A single noisy frame or server timeout
    // must not re-arm a held sign and create a duplicate character.
    if (_missedPredictions >= 2) _latchedLetter = null;
    if (mounted) setState(() => _status = status);
  }

  void _resetPredictionTracker({required bool clearLatch}) {
    _candidateLetter = null;
    _candidateHits = 0;
    _missedPredictions = 0;
    if (clearLatch) _latchedLetter = null;
  }

  // ── Word / sentence helpers ──────────────────────────────
  void _addSpace() {
    if (_word.isEmpty) return;
    if (mounted) setState(() {
      _sentence.add(_word);
      _word = '';
      _lastLetter = null;
      _resetPredictionTracker(clearLatch: true);
    });
    _tts.speak(_sentence.last);
  }

  void _backspace() {
    if (mounted) setState(() {
      if (_word.isNotEmpty) {
        _word = _word.substring(0, _word.length - 1);
      } else if (_sentence.isNotEmpty) {
        _word = _sentence.removeLast();
      }
    });
  }

  void _clear() {
    _resetPredictionTracker(clearLatch: true);
    if (mounted) {
      setState(() {
        _sentence.clear();
        _word = '';
        _lastLetter = null;
        _conf = 0;
      });
    }
  }

  void _speak() {
    final all = [..._sentence, if (_word.isNotEmpty) _word].join(' ');
    if (all.isNotEmpty) _tts.speak(all);
  }

  void _setStatus(String s) {
    if (mounted) setState(() { _status = s; _loading = false; });
  }

  // ── Flip camera ──────────────────────────────────────────
  Future<void> _flip() async {
    if (_cameras.length < 2) return;
    final wasDetecting = _detecting;
    if (_detecting) _stopDetect();
    _camIdx = (_camIdx + 1) % _cameras.length;
    await _startCamera(_camIdx);
    if (wasDetecting) _startDetect();
  }

  // ── Lifecycle ────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive) {
      _stopDetect();
      final c = _ctrl;
      _ctrl = null;
      try { c?.dispose(); } catch (_) {}
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
    // Controller ko last mein dispose karo
    final c = _ctrl;
    _ctrl = null;
    try { c?.dispose(); } catch (_) {}
    super.dispose();
  }

  // ════════════════════════════════════════════════════════
  // UI
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
        child: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: 14),
            Text(_status, style: const TextStyle(color: Colors.white70)),
          ],
        )),
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
            Container(width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _detecting ? Colors.greenAccent : Colors.grey)),
            const SizedBox(width: 8),
            Text(_detecting ? 'LIVE' : 'IDLE',
              style: const TextStyle(color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w600, letterSpacing: 1)),
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
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ── Text box ──
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TEXT', style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 11, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                RichText(text: TextSpan(
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  children: [
                    TextSpan(text: _sentence.isEmpty ? '' : '${_sentence.join(' ')} ',
                      style: const TextStyle(color: Colors.white)),
                    TextSpan(text: _word,
                      style: const TextStyle(color: AppColors.accent)),
                    if (_sentence.isEmpty && _word.isEmpty)
                      const TextSpan(text: '—',
                        style: TextStyle(color: Colors.white24)),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 8),
            Text(_status,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.5)),
            const SizedBox(height: 16),
            // ── Buttons row ──
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _iconBtn(Icons.backspace_outlined,   'Back',  _backspace),
              _iconBtn(Icons.space_bar_rounded,    'Space', _addSpace),
              _iconBtn(Icons.delete_outline_rounded,'Clear', _clear),
              _iconBtn(Icons.volume_up_rounded,    'Speak', _speak),
            ]),
            const SizedBox(height: 16),
            // ── Main button ──
            GestureDetector(
              onTap: _toggleDetect,
              child: Container(
                height: 58, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _detecting
                    ? [AppColors.danger, const Color(0xFFFF8A5B)]
                    : [AppColors.accent, AppColors.accent2]),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(
                    color: (_detecting ? AppColors.danger : AppColors.accent)
                      .withOpacity(0.45),
                    blurRadius: 20, offset: const Offset(0, 6))],
                ),
                child: Center(child: _detecting
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      RotationTransition(turns: _ring,
                        child: const Icon(Icons.autorenew_rounded,
                          color: Colors.white, size: 22)),
                      const SizedBox(width: 10),
                      const Text('Stop', style: TextStyle(color: Colors.white,
                        fontSize: 16, fontWeight: FontWeight.w700)),
                    ])
                  : const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                      SizedBox(width: 6),
                      Text('Start Detection', style: TextStyle(color: Colors.white,
                        fontSize: 16, fontWeight: FontWeight.w700)),
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
    GestureDetector(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 50, height: 50,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10), shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.15))),
        child: Icon(icon, color: Colors.white, size: 22)),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
    ]));

  Widget _glassBtn(IconData icon, VoidCallback onTap) => ClipOval(
    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Material(color: Colors.black.withOpacity(0.35), shape: const CircleBorder(),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 24))))));

  Widget _glassPill(Widget child) => ClipRRect(
    borderRadius: BorderRadius.circular(30),
    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: Colors.black.withOpacity(0.35),
        child: child)));
}