# Vision Wear

AI-powered eyewear assistant that connects to an ESP32-CAM module for real-time computer vision, obstacle detection, and voice-guided navigation for visually impaired users.

## Features

- **ESP32-CAM integration** — Connects via WiFi to capture live frames from smart eyewear
- **On-device object detection** — Google ML Kit identifies people, vehicles, obstacles, and hazards
- **Spatial awareness** — Reports object position (left, center, right, near, far)
- **Voice announcements** — Text-to-speech alerts with priority for critical hazards
- **Haptic feedback** — Vibration patterns for immediate dangers
- **Voice commands** — Hands-free control ("start vision", "describe scene", "scan obstacles")
- **Phone camera fallback** — Test without hardware using the device camera
- **Accessibility-first UI** — Large buttons, high contrast, screen reader support

## Quick Start

### 1. Flash ESP32-CAM Firmware

1. Install [Arduino IDE](https://www.arduino.cc/en/software) with ESP32 board support
2. Open `firmware/esp32_cam/VisionWear_Camera.ino`
3. Select board: **AI Thinker ESP32-CAM**
4. Set partition: **Huge APP (3MB No OTA)**
5. Enable **PSRAM** in board settings
6. Flash the module

### 2. Connect Hardware

1. Power on the ESP32-CAM
2. On your phone, connect to WiFi: **VisionWear-CAM** (password: `visionwear`)
3. Default camera IP: `192.168.4.1`

### 3. Run the App

```bash
flutter pub get
flutter run
```

In the app: **Camera Connection** → enter IP `192.168.4.1` → **Save & Connect** → **Start Vision**

### Testing Without ESP32

Enable **Use phone camera** in Settings or Camera Connection screen.

## Voice Commands

| Command | Action |
|---------|--------|
| "Start vision" | Begin live detection |
| "Stop vision" | Pause detection |
| "Describe scene" | Hear current surroundings |
| "Scan obstacles" | Report hazards on your path |
| "Repeat" | Repeat last announcement |
| "Open settings" | Go to settings |
| "Help" | Open help screen |

## Project Structure

```
lib/
├── core/           # Theme, constants
├── models/         # Data models
├── services/       # Camera, ML, speech, haptics
├── providers/      # State management
├── screens/        # UI screens
└── widgets/        # Reusable components
firmware/
└── esp32_cam/      # ESP32-CAM Arduino sketch
```

## ESP32 Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /capture` | Single JPEG frame (used by app) |
| `GET /stream` | MJPEG live stream (port 81) |
| `GET /status` | Device status JSON |
| `GET /` | Info page |

## Requirements

- Flutter SDK ^3.11.5
- Android 6.0+ or iOS 13.0+
- ESP32-CAM (AI-Thinker) for eyewear camera module
- WiFi connection between phone and ESP32

## Safety Notice

Vision Wear is a navigation **assistant**, not a replacement for a white cane, guide dog, or human guide. Always use multiple methods for safe mobility.

## License

MIT
