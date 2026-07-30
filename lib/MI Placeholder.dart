import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

/// Preloads the hand + pose ML models once, as early as possible (call
/// from HomeScreen's initState), and keeps them around for the whole app
/// session. WordToSentenceScreen then just grabs the already-loaded
/// instances instead of creating + initializing them from scratch every
/// time the user navigates there — cutting out the biggest chunk of the
/// "click → screen ready" delay.
class MlPreloader {
  MlPreloader._();

  static HandLandmarkerPlugin? handPlugin;
  static NpuPoseDetector? poseDetector;

  static bool get isReady => handPlugin != null && poseDetector != null;

  // Guards against kicking off loading twice (e.g. if the user bounces
  // back to HomeScreen and it calls preload() again).
  static Future<void>? _loadingFuture;

  /// Call this once, early — e.g. in HomeScreen.initState(). Safe to call
  /// multiple times; subsequent calls just return the same in-flight (or
  /// already-completed) future.
  static Future<void> preload() {
    return _loadingFuture ??= _load();
  }

  static Future<void> _load() async {
    try {
      handPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.65,
        delegate: HandLandmarkerDelegate.gpu,
      );
      poseDetector = NpuPoseDetector(config: PoseDetectorConfig.realtime());
      await poseDetector!.initialize();
    } catch (_) {
      // Do not keep a permanently failed preload future. A later screen visit
      // can retry model initialisation after a temporary GPU/NPU failure.
      handPlugin?.dispose();
      poseDetector?.dispose();
      handPlugin = null;
      poseDetector = null;
      _loadingFuture = null;
      rethrow;
    }
  }

  /// If you ever need to fully release the models (e.g. very low memory
  /// scenarios), call this. Not needed in normal app lifecycle.
  static void dispose() {
    handPlugin?.dispose();
    poseDetector?.dispose();
    handPlugin = null;
    poseDetector = null;
    _loadingFuture = null;
  }
}
