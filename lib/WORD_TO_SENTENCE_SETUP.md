# Word → Sentence: on-device keypoint extraction setup

This version computes MediaPipe pose+hand keypoints ON THE PHONE (instead of
sending images to the backend), because the backend now expects a 258-number
keypoint array (see /predict_frame in main.py).

## 1. Add to pubspec.yaml

```yaml
dependencies:
  hand_landmarker: ^3.0.0
  flutter_pose_detection: ^0.4.1
```

Then `flutter pub get`.

## 2. Android setup (flutter_pose_detection needs API 31+)

In `android/app/build.gradle`:
```gradle
android {
    defaultConfig {
        minSdkVersion 31   // was probably 21 or 23 before — check your device supports Android 12+
    }
}
```

`hand_landmarker` also needs JDK 17+ to build — check your `android/build.gradle`
/ Flutter's Java version if the build fails with a JDK-related error.

## 3. Things you MUST test on a real device (I can't run this myself)

- **Left/right hand assignment**: `keypoint_extractor.dart` guesses which
  detected hand is "left" vs "right" using the pose wrists, since
  `hand_landmarker` doesn't report handedness. If predictions are wrong/random,
  this is the first thing to suspect — try the swap noted in that file.
- **Feature order**: currently `[pose(132), left_hand(63), right_hand(63)]`.
  This matches the classic MediaPipe-Holistic tutorial layout that this
  backend's model is clearly based on — but if your friend's training script
  used a different order, predictions will be garbage. Ask them to confirm,
  or share the `extract_keypoints()` function from their training code.
- **`visibility` field name**: `flutter_pose_detection`'s landmark object is
  expected to expose a `visibility` field (per its own docs: "33 landmarks
  (x, y, z, visibility, presence)" on Android) — if the actual field is named
  differently, `keypoint_extractor.dart` will throw/always send 0 for it.
  Check via IDE autocomplete on `PoseLandmark` after `pub get`.
- **Send rate**: `_SEND_INTERVAL_MS = 150` in word_to_sentence_screen.dart —
  tune this. Too fast overloads the Railway backend; too slow makes the
  30-frame buffer take a long time to fill (each /predict_frame call = 1
  frame in the server's rolling buffer of 30).

## 4. Fallback

If this on-device approach proves too unstable, the fastest fix remains
asking the backend owner to add an image-accepting convenience endpoint
(see `backend_endpoint_suggestion.py`) that reuses their own extraction
function server-side — no client-side MediaPipe needed at all.
