# Vision Wear

AI-powered eyewear assistant that connects to an ESP32-CAM module for real-time computer vision, obstacle detection, and voice-guided navigation for visually impaired users.

## Features

- **ESP32-CAM integration** — one long-lived MJPEG connection for low-latency live frames, with `/capture` polling as a fallback
- **Automatic discovery** — the app finds the camera by UDP beacon; no IP address to type
- **Automatic reconnection** — a stall watchdog plus capped backoff rebuild the link without user action
- **Dual-mode WiFi** — the camera serves its own access point *and* can join your home WiFi, so your phone keeps internet
- **On-device object detection** — YOLO identifies people, vehicles, obstacles, and hazards
- **Spatial awareness** — reports object position (left, center, right, near, far)
- **Voice announcements** — text-to-speech with priority for critical hazards
- **Haptic feedback** — vibration patterns for immediate dangers
- **Voice commands** — hands-free control ("start vision", "describe scene", "scan obstacles")
- **Two physical buttons** — mode and action, with tap and hold gestures
- **Phone camera fallback** — test without hardware using the device camera
- **Accessibility-first UI** — large buttons, high contrast, screen reader support

## Quick Start

### 1. Flash ESP32-CAM Firmware

1. Install [Arduino IDE](https://www.arduino.cc/en/software) with ESP32 board support
2. Open `firmware/esp32_cam/VisionWear_Camera.ino`
3. Select board: **AI Thinker ESP32-CAM**
4. Set partition: **Huge APP (3MB No OTA)**
5. Enable **PSRAM** in board settings
6. Flash the module

### 2. Wire the Buttons

Each button connects between its GPIO pin and GND. The firmware enables the
internal pull-ups, so no external resistors are needed.

| Button | Pin | Tap | Hold |
|---|---|---|---|
| Mode | GPIO 13 | Cycle Object Detection → OCR → Navigation | Re-announce the current mode |
| Action | GPIO 14 | Run the current mode's action | Start / stop vision |

### 3. Connect

1. Power on the ESP32-CAM
2. On your phone, join WiFi **VisionWear-CAM** (password: `visionwear`)
3. Open the app — it discovers the camera and connects on its own

### 4. Keep your internet connection (recommended)

The camera's own access point has no internet. On the **Camera Connection**
screen, enter your home WiFi (or phone hotspot) name and password and tap
**Send to camera**. The board stores the credentials and joins that network
while continuing to serve its own AP, so your phone can stay on a network with
internet and still reach the camera.

### 5. Run the App

```bash
flutter pub get
```

```bash
flutter run
```

### Testing Without ESP32

Enable **Use phone camera** on the Camera Connection screen.

## Voice Commands

| Command | Action |
|---------|--------|
| "Start vision" | Begin live detection |
| "Stop vision" | Pause detection |
| "Describe scene" | Hear current surroundings |
| "Scan obstacles" | Report hazards on your path |
| "Change mode" | Cycle to the next mode |
| "Repeat" | Repeat last announcement |
| "Open settings" | Go to settings |
| "Help" | Open help screen |

## Project Structure

```
lib/
├── core/           # Theme, constants
├── models/         # Data models
├── services/       # Camera link, discovery, MJPEG, ML, speech, haptics
├── providers/      # State management
├── screens/        # UI screens
└── widgets/        # Reusable components
firmware/
└── esp32_cam/      # ESP32-CAM Arduino sketch
test/
└── mjpeg_parser_test.dart
```

## ESP32 API

The firmware runs three HTTP server instances. `esp_http_server` handles one
request at a time per instance, so the blocking stream and the long-polled
event endpoint each get their own; otherwise they would starve `/capture` and
`/status`.

| Port | Endpoint | Description |
|---|---|---|
| 80 | `GET /` | Info page |
| 80 | `GET /capture` | Single JPEG frame |
| 80 | `GET /status` | Device + network status JSON |
| 80 | `GET /health` | Cheap liveness probe (does not touch the camera) |
| 80 | `GET /mode?set=N` | Set mode 0–2 from the app |
| 80 | `GET /wifi?ssid=..&pass=..` | Provision station credentials (saved to NVS) |
| 80 | `GET /wifi/clear` | Forget station credentials |
| 81 | `GET /stream` | MJPEG multipart stream (primary frame transport) |
| 82 | `GET /events?wait=25000` | Button events, long-poll |

**Discovery:** the board broadcasts a JSON beacon to UDP port `4210` on both
its AP and station subnets every 1.5 s.

## Requirements

- Flutter SDK 3.10 or newer
- Android 6.0+ (Android is the only supported target; the Windows, macOS and
  Linux runners have been removed)
- ESP32-CAM (AI-Thinker) with PSRAM
- WiFi connectivity between phone and ESP32

## App Icon

The launcher icon is generated from `assets/logo.png`. Because that logo is a
wide banner and launcher icons must be square, `assets/icon/` holds two derived
square images: a full-bleed icon and an inset adaptive-icon foreground (Android
masks the outer edge of the foreground, so the logo sits inside the safe zone).

After changing the logo, regenerate with:

```bash
dart run flutter_launcher_icons
```

## Release Checklist

Two items are deliberately left unset and **block a Play Store upload**:

- [ ] **Application ID** — still `com.example.vision_wear` in
      `android/app/build.gradle.kts`. Google Play rejects `com.example.*`, and
      the ID can never be changed after the first upload.
- [ ] **Release signing** — release builds currently fall through to the debug
      key. Generate a keystore and create `android/key.properties`
      (see `android/key.properties.example`); the Gradle config picks it up
      automatically once the file exists.

Also verify before shipping:

- [ ] Run the **release** build on a physical device. R8 shrinking is enabled,
      and the ML runtimes resolve classes reflectively — `proguard-rules.pro`
      covers them, but this is the most likely source of a release-only crash.
- [ ] Bump `version:` in `pubspec.yaml`.

## Safety Notice

Vision Wear is a navigation **assistant**, not a replacement for a white cane, guide dog, or human guide. Always use multiple methods for safe mobility.

## License

MIT
