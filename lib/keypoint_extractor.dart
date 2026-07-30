import 'dart:math' as math;
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

/// Builds the 258-value vector expected by the word model:
/// pose 33 x (x,y,z,visibility) + left hand 21 x (x,y,z)
/// + right hand 21 x (x,y,z).
class KeypointExtractor {
  static const int poseLandmarkCount = 33;
  static const int handLandmarkCount = 21;
  static const int expectedVectorLength = 258;

  static List<double> build({
    dynamic poseResult,
    List<Hand>? hands,
    bool swapHandOrder = false,
  }) {
    final pose = _flattenPose(poseResult);

    dynamic leftWrist;
    dynamic rightWrist;
    try {
      if (poseResult?.hasPoses == true) {
        leftWrist =
            poseResult!.firstPose!.getLandmark(LandmarkType.leftWrist);
        rightWrist =
            poseResult!.firstPose!.getLandmark(LandmarkType.rightWrist);
      }
    } catch (_) {
      leftWrist = null;
      rightWrist = null;
    }

    final assigned = _assignHands(hands, leftWrist, rightWrist);
    final left = _flattenHand(assigned.left);
    final right = _flattenHand(assigned.right);

    final vector = swapHandOrder
        ? <double>[...pose, ...right, ...left]
        : <double>[...pose, ...left, ...right];

    // Never send NaN/Infinity to JSON or the backend model.
    for (var i = 0; i < vector.length; i++) {
      if (!vector[i].isFinite) vector[i] = 0.0;
    }
    return vector;
  }

  static bool hasUsableHands(List<Hand>? hands) {
    if (hands == null || hands.isEmpty) return false;
    return hands.any((hand) => hand.landmarks.length >= handLandmarkCount);
  }

  static List<double> _flattenPose(dynamic result) {
    final output = List<double>.filled(poseLandmarkCount * 4, 0.0);
    try {
      if (result == null || result.hasPoses != true) return output;
      final pose = result.firstPose;
      if (pose == null) return output;

      for (var i = 0; i < poseLandmarkCount; i++) {
        final landmark = pose.landmarks.length > i ? pose.landmarks[i] : null;
        if (landmark == null) continue;
        output[i * 4] = _safe(landmark.x);
        output[i * 4 + 1] = _safe(landmark.y);
        output[i * 4 + 2] = _safe(landmark.z);
        output[i * 4 + 3] = _safe(landmark.visibility ?? 0.0);
      }
    } catch (_) {
      // Keep zero padding if a plugin version exposes a different shape.
    }
    return output;
  }

  static List<double> _flattenHand(Hand? hand) {
    final output = List<double>.filled(handLandmarkCount * 3, 0.0);
    if (hand == null) return output;

    for (var i = 0;
        i < handLandmarkCount && i < hand.landmarks.length;
        i++) {
      final landmark = hand.landmarks[i];
      output[i * 3] = _safe(landmark.x);
      output[i * 3 + 1] = _safe(landmark.y);
      output[i * 3 + 2] = _safe(landmark.z);
    }
    return output;
  }

  static _AssignedHands _assignHands(
    List<Hand>? detectedHands,
    dynamic leftWrist,
    dynamic rightWrist,
  ) {
    final hands = (detectedHands ?? <Hand>[])
        .where((hand) => hand.landmarks.isNotEmpty)
        .take(2)
        .toList();

    if (hands.isEmpty) return const _AssignedHands(null, null);

    if (hands.length == 1) {
      final hand = hands.first;
      if (leftWrist != null && rightWrist != null) {
        final wrist = hand.landmarks.first;
        final distanceToLeft =
            _dist(wrist.x, wrist.y, leftWrist.x, leftWrist.y);
        final distanceToRight =
            _dist(wrist.x, wrist.y, rightWrist.x, rightWrist.y);
        return distanceToLeft <= distanceToRight
            ? _AssignedHands(hand, null)
            : _AssignedHands(null, hand);
      }
      // With no pose reference, preserve the common dominant-hand fallback.
      return _AssignedHands(null, hand);
    }

    final first = hands[0];
    final second = hands[1];

    if (leftWrist != null && rightWrist != null) {
      final firstWrist = first.landmarks.first;
      final secondWrist = second.landmarks.first;

      // Choose the globally best two-hand assignment. The old per-hand loop
      // could assign both detections to the same side and silently lose one.
      final normalCost =
          _dist(firstWrist.x, firstWrist.y, leftWrist.x, leftWrist.y) +
              _dist(secondWrist.x, secondWrist.y, rightWrist.x, rightWrist.y);
      final swappedCost =
          _dist(secondWrist.x, secondWrist.y, leftWrist.x, leftWrist.y) +
              _dist(firstWrist.x, firstWrist.y, rightWrist.x, rightWrist.y);

      return normalCost <= swappedCost
          ? _AssignedHands(first, second)
          : _AssignedHands(second, first);
    }

    // Pose is temporarily unavailable: use stable frame x-order instead of
    // allowing hand order to change based on detector return order.
    final sorted = <Hand>[first, second]
      ..sort((a, b) =>
          a.landmarks.first.x.compareTo(b.landmarks.first.x));
    return _AssignedHands(sorted.first, sorted.last);
  }

  static double _safe(dynamic value) {
    if (value is! num) return 0.0;
    final number = value.toDouble();
    return number.isFinite ? number : 0.0;
  }

  static double _dist(double x1, double y1, double x2, double y2) {
    final dx = x1 - x2;
    final dy = y1 - y2;
    return math.sqrt(dx * dx + dy * dy);
  }
}

class _AssignedHands {
  final Hand? left;
  final Hand? right;

  const _AssignedHands(this.left, this.right);
}
