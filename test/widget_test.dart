import 'package:flutter_test/flutter_test.dart';

import 'package:vision_wear/core/constants.dart';

void main() {
  test('app constants are defined', () {
    expect(AppConstants.appName, 'Vision Wear');
    expect(AppConstants.defaultEsp32Ip, isNotEmpty);
  });
}
