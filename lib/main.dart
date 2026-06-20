import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/settings_provider.dart';
import 'providers/vision_provider.dart';
import 'screens/splash_screen.dart';
import 'services/esp32_camera_service.dart';
import 'services/haptic_service.dart';
import 'services/object_detection_service.dart';
import 'services/obstacle_analyzer.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';
import 'services/speech_service.dart';
import 'services/voice_command_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await PermissionService.requestVisionPermissions();

  final settingsService = SettingsService();
  final cameraService = Esp32CameraService();
  final detectionService = ObjectDetectionService();
  final obstacleAnalyzer = ObstacleAnalyzer();
  final speechService = SpeechService();
  final hapticService = HapticService();
  final voiceCommandService = VoiceCommandService();

  final settings = await settingsService.load();
  speechService.updateSettings(settings);

  runApp(
    VisionWearApp(
      settingsService: settingsService,
      cameraService: cameraService,
      detectionService: detectionService,
      obstacleAnalyzer: obstacleAnalyzer,
      speechService: speechService,
      hapticService: hapticService,
      voiceCommandService: voiceCommandService,
    ),
  );
}

class VisionWearApp extends StatelessWidget {
  const VisionWearApp({
    super.key,
    required this.settingsService,
    required this.cameraService,
    required this.detectionService,
    required this.obstacleAnalyzer,
    required this.speechService,
    required this.hapticService,
    required this.voiceCommandService,
  });

  final SettingsService settingsService;
  final Esp32CameraService cameraService;
  final ObjectDetectionService detectionService;
  final ObstacleAnalyzer obstacleAnalyzer;
  final SpeechService speechService;
  final HapticService hapticService;
  final VoiceCommandService voiceCommandService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(settingsService)..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => VisionProvider(
            cameraService: cameraService,
            detectionService: detectionService,
            obstacleAnalyzer: obstacleAnalyzer,
            speechService: speechService,
            hapticService: hapticService,
            voiceCommandService: voiceCommandService,
          ),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
