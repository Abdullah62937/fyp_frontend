# GestureVoice 🤟🔊

**Real-time sign language to voice** — a Flutter app that watches sign gestures through the camera and turns them into spoken sentences.

GestureVoice supports two prediction modes:
- **Alphabet mode** — records a short video clip and sends it to a backend model that predicts a single sign/letter.
- **Word → Sentence mode** — extracts MediaPipe pose + hand keypoints on-device and streams them frame-by-frame to a backend model, building full sentences over time.

Predicted words are shown on screen and spoken aloud using text-to-speech.

---

## ✨ Features

- **Home screen** — animated gradient UI with a pulsing start button, entry points to Camera mode, Word → Sentence mode, Learn, and About.
- **Camera screen** — full-screen live camera preview with a glass-style top bar (back / status / flip camera) and a bottom panel showing the live sentence, last predicted word + confidence, and **Clear / Capture Sign / Speak** controls.
- **Word → Sentence screen** — on-device keypoint extraction streamed to the backend for continuous word prediction, assembled into sentences.
- **Learn screen** — reference guide of signs with icons and instructions.
- **About screen** — information about the app and project.
- **Text-to-speech** — speaks the recognized word/sentence aloud.
- **Model warm-up** — both backend APIs are "pinged" on app start so the first real prediction isn't slowed down by a cold start.

---

## 📁 Project structure

```
lib/
├── main.dart                     # App entry point + theme
├── home_screen.dart              # Landing screen / navigation hub
├── camera_screen.dart            # Alphabet mode: record clip → predict → speak
├── word_to_sentence_screen.dart  # Word mode: on-device keypoints → predict → sentence
├── keypoint_extractor.dart       # MediaPipe pose/hand keypoint extraction helper
├── api_service.dart              # Backend client for alphabet/clip prediction
├── word_api_service.dart         # Backend client for word/sentence prediction
├── tts_service.dart              # Text-to-speech wrapper (flutter_tts)
├── learnscreen.dart              # "Learn Signs" reference screen
├── aboutscreen.dart              # About screen
├── MI Placeholder.dart           # ML model preloader
├── SETUP.md                      # Setup notes for the camera/alphabet flow
└── WORD_TO_SENTENCE_SETUP.md     # Setup notes for the on-device keypoint flow
```

---

## 🛠 Requirements

- [Flutter SDK](https://flutter.dev) (stable channel)
- Android Studio / Xcode for building to a device or emulator
- A physical device is recommended for testing the camera and keypoint-extraction flows

---

## 🚀 Getting started

1. **Clone / copy this `lib/` folder** into a Flutter project (create one with `flutter create fyp` if you don't already have one — the package name used throughout the code is `fyp`).

2. **Install dependencies:**
   ```bash
   flutter pub add camera http flutter_tts permission_handler
   ```
   For the Word → Sentence mode, also add (see `WORD_TO_SENTENCE_SETUP.md` for details):
   ```yaml
   dependencies:
     hand_landmarker: ^3.0.0
     flutter_pose_detection: ^0.4.1
   ```
   Then:
   ```bash
   flutter pub get
   ```

3. **Configure Android permissions** — in `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.CAMERA"/>
   <uses-permission android:name="android.permission.INTERNET"/>
   ```
   Set `minSdkVersion 31` or higher in `android/app/build.gradle` (required by `flutter_pose_detection`), and JDK 17+ for the build.

4. **Configure iOS permissions** — in `ios/Runner/Info.plist`:
   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Sign detection ke liye camera chahiye.</string>
   ```

5. **Run the app:**
   ```bash
   flutter run
   ```

Full setup details, including backend API contract, keypoint feature order, and known device-specific quirks, are documented in `lib/SETUP.md` and `lib/WORD_TO_SENTENCE_SETUP.md`.

---

## 🔌 Backend

The app talks to two separate prediction backends (both hosted, base URLs configured in `api_service.dart` and `word_api_service.dart`):

| Mode | Endpoint | Input | Output |
|---|---|---|---|
| Alphabet | `/predict` | short video clip (multipart) | `{ "word": "...", "confidence": 0.9 }` |
| Word → Sentence | `/predict_frame` | 258-value keypoint array per frame (JSON) | `{ "prediction": "...", "confidence": ..., "buffer_fill": ..., "ready": true }` |

If you're running your own backend locally instead of the hosted one, update the `baseUrl` in each service file:
- Android emulator → laptop: `http://10.0.2.2:8000`
- Real phone (same Wi-Fi): `http://<laptop-IP>:8000`

---

## ⚙️ Tuning

- **Clip length** (alphabet mode): adjust `Duration(milliseconds: 2000)` in `camera_screen.dart`.
- **Camera resolution**: if the preview looks corrupted on some devices, change `ResolutionPreset.high` to `medium`/`low`.
- **Frame send rate** (word mode): adjust `_SEND_INTERVAL_MS` in `word_to_sentence_screen.dart` to balance backend load vs. prediction latency.

---

## 📝 Notes

- Text on screen is bilingual (Urdu/English) in places, reflecting the project's dev notes — feel free to localize further.
- The Word → Sentence flow relies on hand handedness being *guessed* from pose wrist positions, since `hand_landmarker` doesn't report handedness directly — see `WORD_TO_SENTENCE_SETUP.md` if predictions seem mirrored/swapped.