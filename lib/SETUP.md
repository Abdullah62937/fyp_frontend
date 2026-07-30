# GestureVoice — Flutter UI (camera integrated)

Attractive single-flow app: **Home → Camera → sign capture → API → sentence + voice.**

## 1. Files
Apne Flutter project ke `lib/` me ye structure rakho:
```
lib/
├── main.dart
├── screens/
│   ├── home_screen.dart
│   └── camera_screen.dart
└── services/
    ├── api_service.dart
    └── tts_service.dart
```

## 2. Dependencies
Project folder me:
```bash
flutter pub add camera http flutter_tts permission_handler
```

## 3. Apni API connect karo
`lib/services/api_service.dart` me 3 TODO:
1. `baseUrl` → apne server ka address
   - Android **emulator** se laptop server: `http://10.0.2.2:8000`
   - **Real phone** (same wifi): `http://<laptop-IP>:8000`  (e.g. `http://192.168.1.10:8000`)
2. multipart field name (`'file'`)
3. response keys (`word`, `confidence`)

> App ek ~2 second ka **video clip** record karke server ko bhejti hai. Server par
> ek `/predict` endpoint hona chahiye jo clip leke `{ "word": "...", "confidence": 0.9 }`
> return kare (tumhare VideoMAE ya landmark model se).

## 4. Android permissions
`android/app/src/main/AndroidManifest.xml` me `<application>` ke upar:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.INTERNET"/>
```
`android/app/build.gradle` me `minSdkVersion 21` (ya zyada).
> Agar HTTP (https nahi) use kar rahe ho to `<application>` tag me ye add karo:
> `android:usesCleartextTraffic="true"`

## 5. iOS permissions
`ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Sign detection ke liye camera chahiye.</string>
```

## 6. Run
```bash
flutter pub get
flutter run
```

## UI features
- **Home**: gradient + glow + pulsing start button (FYP-attractive).
- **Camera**: full-screen live preview, glass top bar (back / status / flip camera).
- **Bottom glass panel**: live SENTENCE box, last word + confidence, aur 3 buttons:
  **Clear**, **Capture Sign** (record + predict), **Speak** (poora sentence bole).
- Predicted word automatically sentence me add hota hai aur bol bhi deta hai.

## Tuning
- Clip length: `camera_screen.dart` me `Duration(milliseconds: 2000)` badlo.
- Agar preview green/corrupt aaye (kuch devices): `ResolutionPreset.high` ko `medium`/`low` karo.
