import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _HelpSection(
              title: 'Voice Commands',
              icon: Icons.mic,
              children: AppConstants.voiceCommands
                  .map(
                    (cmd) => ListTile(
                      leading: const Icon(
                        Icons.format_quote,
                        color: AppTheme.accent,
                        size: 20,
                      ),
                      title: Text('"$cmd"'),
                      dense: true,
                    ),
                  )
                  .toList(),
            ),
            _HelpSection(
              title: 'Physical Button Controls (2-Button Interface)',
              icon: Icons.touch_app,
              children: const [
                ListTile(
                  leading: Icon(Icons.circle, color: AppTheme.accent),
                  title: Text('Button 1 (GPIO 13): Mode Button'),
                  subtitle: Text(
                    'Press to cycle through Object Detection → OCR → Navigation modes',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.circle, color: AppTheme.accent),
                  title: Text('Button 2 (GPIO 14): Action Button'),
                  subtitle: Text(
                    'Press to perform action based on current mode:\n• Object Detection: "What is in front of me?"\n• OCR: Capture and read text\n• Navigation: Navigation assistance',
                  ),
                ),
                SizedBox(height: 8),
                ListTile(
                  leading: Icon(Icons.info, color: AppTheme.primary),
                  title: Text('Quick Feedback:'),
                  subtitle: Text(
                    '• Single flash: Mode changed\n• Double click: Action triggered\n• Voice feedback confirms your selection',
                  ),
                ),
              ],
            ),
            _HelpSection(
              title: 'ESP32-CAM Setup',
              icon: Icons.memory,
              children: const [
                _HelpStep(
                  number: 1,
                  text: 'Install Arduino IDE and ESP32 board support',
                ),
                _HelpStep(
                  number: 2,
                  text: 'Open firmware/esp32_cam/VisionWear_Camera.ino',
                ),
                _HelpStep(
                  number: 3,
                  text: 'Select "AI Thinker ESP32-CAM" board and flash',
                ),
                _HelpStep(
                  number: 4,
                  text:
                      'Wire buttons: Button 1 to GPIO13, Button 2 to GPIO14 (both to GND)',
                ),
                _HelpStep(
                  number: 5,
                  text:
                      'Connect to WiFi "VisionWear-CAM" (password: visionwear)',
                ),
                _HelpStep(
                  number: 6,
                  text: 'In the app, set IP to 192.168.4.1 and connect',
                ),
              ],
            ),
            _HelpSection(
              title: 'How Detection Works',
              icon: Icons.psychology,
              children: const [
                ListTile(
                  leading: Icon(
                    Icons.center_focus_strong,
                    color: AppTheme.primary,
                  ),
                  title: Text(
                    'Objects in the center of view are reported as "ahead"',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: AppTheme.primary),
                  title: Text(
                    'Left and right zones help you navigate around obstacles',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.warning, color: AppTheme.warning),
                  title: Text(
                    'Large nearby objects trigger urgent voice and haptic alerts',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.timer, color: AppTheme.accent),
                  title: Text(
                    'Alerts are spaced to avoid overwhelming you with speech',
                  ),
                ),
              ],
            ),
            _HelpSection(
              title: 'Tips for Best Results',
              icon: Icons.tips_and_updates,
              children: const [
                ListTile(
                  leading: Icon(Icons.check, color: AppTheme.accent),
                  title: Text('Mount the camera at chest or forehead height'),
                ),
                ListTile(
                  leading: Icon(Icons.check, color: AppTheme.accent),
                  title: Text('Ensure good lighting for accurate detection'),
                ),
                ListTile(
                  leading: Icon(Icons.check, color: AppTheme.accent),
                  title: Text(
                    'Use headphones to hear alerts clearly in noisy areas',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check, color: AppTheme.accent),
                  title: Text(
                    'This app assists navigation — always use a cane or guide dog too',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: AppTheme.primary,
        child: Text('$number', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(text),
      dense: true,
    );
  }
}
