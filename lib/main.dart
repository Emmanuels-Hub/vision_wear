import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/theme/app_theme.dart';
import 'models/app_settings.dart';
import 'providers/settings_provider.dart';
import 'providers/vision_provider.dart';
import 'screens/splash_screen.dart';
import 'services/esp32_camera_service.dart';
import 'services/haptic_service.dart';
import 'services/object_detection_service.dart';
import 'services/ocr_service.dart';
import 'services/obstacle_analyzer.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';
import 'services/speech_service.dart';
import 'services/voice_command_service.dart';

void main() {
  // runZonedGuarded plus the Flutter error hooks stop a single unhandled async
  // error from taking the app down mid-walk, which for this user is a safety
  // issue rather than a cosmetic one.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('Flutter error: ${details.exception}');
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Uncaught platform error: $error');
        return true;
      };

      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

      final settingsService = SettingsService();
      final settings = await settingsService.load();

      final cameraService = Esp32CameraService();
      final detectionService = ObjectDetectionService();
      final obstacleAnalyzer = ObstacleAnalyzer();
      final speechService = SpeechService();
      final hapticService = HapticService();
      final voiceCommandService = VoiceCommandService();
      final ocrService = OcrService();

      cameraService.updateSettings(settings);

      // Awaited: enumerating voices and picking a non-robotic one has to finish
      // before the first utterance, otherwise the app greets the user in the
      // engine's default voice and only switches later.
      await speechService.initialize();
      await speechService.updateSettings(settings);

      runApp(
        VisionWearApp(
          settingsService: settingsService,
          initialSettings: settings,
          cameraService: cameraService,
          detectionService: detectionService,
          obstacleAnalyzer: obstacleAnalyzer,
          speechService: speechService,
          hapticService: hapticService,
          voiceCommandService: voiceCommandService,
          ocrService: ocrService,
        ),
      );

      // Requested after the first frame so the permission dialog appears over
      // the splash screen instead of a white window.
      unawaited(PermissionService.requestVisionPermissions());
    },
    (error, stack) {
      debugPrint('Uncaught zone error: $error\n$stack');
    },
  );
}

class VisionWearApp extends StatelessWidget {
  const VisionWearApp({
    super.key,
    required this.settingsService,
    required this.initialSettings,
    required this.cameraService,
    required this.detectionService,
    required this.obstacleAnalyzer,
    required this.speechService,
    required this.hapticService,
    required this.voiceCommandService,
    required this.ocrService,
  });

  final SettingsService settingsService;
  final AppSettings initialSettings;
  final Esp32CameraService cameraService;
  final ObjectDetectionService detectionService;
  final ObstacleAnalyzer obstacleAnalyzer;
  final SpeechService speechService;
  final HapticService hapticService;
  final VoiceCommandService voiceCommandService;
  final OcrService ocrService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(settingsService)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) {
            final provider = VisionProvider(
              cameraService: cameraService,
              detectionService: detectionService,
              obstacleAnalyzer: obstacleAnalyzer,
              speechService: speechService,
              hapticService: hapticService,
              voiceCommandService: voiceCommandService,
              ocrService: ocrService,
            );
            provider.updateSettings(initialSettings);
            // Loading the YOLO model takes a few seconds. Kick it off at
            // startup so the first frame is not wasted waiting for it — the
            // old build never called this at all, so detection silently
            // returned nothing for every frame.
            unawaited(provider.initializeDetection());
            return provider;
          },
        ),
      ],
      // Watches only themeMode, so changing an unrelated setting does not
      // rebuild the whole app.
      child: Selector<SettingsProvider, ThemeMode>(
        selector: (_, settings) => settings.themeMode,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
