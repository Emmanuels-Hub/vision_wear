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
                      leading: Icon(
                        Icons.format_quote,
                        color: context.appColors.accent,
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
              children: [
                ListTile(
                  leading: Icon(Icons.circle, color: context.appColors.accent),
                  title: Text('Button 1 (GPIO 13): Mode Button'),
                  subtitle: Text(
                    'Tap: cycle Object Detection → OCR → Navigation\n'
                    'Hold: repeat the current mode out loud',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.circle, color: context.appColors.accent),
                  title: Text('Button 2 (GPIO 14): Action Button'),
                  subtitle: Text(
                    'Tap: run the action for the current mode\n'
                    '• Object Detection: start or pause obstacle scanning\n'
                    '• Read Text: capture the view and read the text aloud\n'
                    'Hold: start or stop vision assistance',
                  ),
                ),
                SizedBox(height: 8),
                ListTile(
                  leading: Icon(Icons.info, color: context.colors.primary),
                  title: Text('Quick Feedback'),
                  subtitle: Text(
                    '• Short flash: action triggered\n'
                    '• Long flash: mode changed\n'
                    '• Longest flash: button held\n'
                    'Speech confirms every selection.',
                  ),
                ),
              ],
            ),
            _HelpSection(
              title: 'ESP32-CAM Setup',
              icon: Icons.memory,
              children: [
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
                  text:
                      'Open the app — it finds the camera automatically, no IP '
                      'address needed',
                ),
                _HelpStep(
                  number: 7,
                  text:
                      'Optional: on the Camera Connection screen, send the '
                      'camera your home WiFi details. It will join that '
                      'network so your phone keeps its internet connection '
                      'while still seeing the camera.',
                ),
              ],
            ),
            _HelpSection(
              title: 'How Detection Works',
              icon: Icons.psychology,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.center_focus_strong,
                    color: context.colors.primary,
                  ),
                  title: Text(
                    'Objects in the center of view are reported as "ahead"',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: context.colors.primary),
                  title: Text(
                    'Left and right zones help you navigate around obstacles',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.warning, color: context.appColors.warning),
                  title: Text(
                    'Large nearby objects trigger urgent voice and haptic alerts',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.timer, color: context.appColors.accent),
                  title: Text(
                    'Alerts are spaced to avoid overwhelming you with speech',
                  ),
                ),
              ],
            ),
            _HelpSection(
              title: 'Tips for Best Results',
              icon: Icons.tips_and_updates,
              children: [
                ListTile(
                  leading: Icon(Icons.check, color: context.appColors.accent),
                  title: Text('Mount the camera at chest or forehead height'),
                ),
                ListTile(
                  leading: Icon(Icons.check, color: context.appColors.accent),
                  title: Text('Ensure good lighting for accurate detection'),
                ),
                ListTile(
                  leading: Icon(Icons.check, color: context.appColors.accent),
                  title: Text(
                    'Use headphones to hear alerts clearly in noisy areas',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.check, color: context.appColors.accent),
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
                Icon(icon, color: context.appColors.accent),
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
        backgroundColor: context.colors.primary,
        child: Text('$number', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(text),
      dense: true,
    );
  }
}
