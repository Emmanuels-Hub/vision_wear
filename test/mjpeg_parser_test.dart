import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vision_wear/services/mjpeg_parser.dart';

/// Minimal valid-looking JPEG: SOI ... EOI.
Uint8List fakeJpeg(int payloadLength, {int fill = 0x42}) {
  final bytes = Uint8List(payloadLength + 4);
  bytes[0] = 0xFF;
  bytes[1] = 0xD8;
  for (var i = 2; i < payloadLength + 2; i++) {
    bytes[i] = fill;
  }
  bytes[payloadLength + 2] = 0xFF;
  bytes[payloadLength + 3] = 0xD9;
  return bytes;
}

List<int> multipart(Uint8List jpeg, {bool withContentLength = true}) {
  final header = StringBuffer()
    ..write('\r\n--visionwearframe\r\n')
    ..write('Content-Type: image/jpeg\r\n');
  if (withContentLength) {
    header.write('Content-Length: ${jpeg.length}\r\n');
  }
  header.write('X-Timestamp: 12345\r\n\r\n');
  return [...header.toString().codeUnits, ...jpeg];
}

void main() {
  group('MjpegParser', () {
    test('emits a frame once the full body has arrived', () {
      final parser = MjpegParser();
      final jpeg = fakeJpeg(64);

      final frames = parser.addChunk(multipart(jpeg));

      expect(frames, hasLength(1));
      expect(frames.first, equals(jpeg));
    });

    test('does not emit until the body is complete', () {
      final parser = MjpegParser();
      final jpeg = fakeJpeg(100);
      final part = multipart(jpeg);

      // Split mid-body, which is what a real socket read does.
      final firstHalf = part.sublist(0, part.length - 40);
      final secondHalf = part.sublist(part.length - 40);

      expect(parser.addChunk(firstHalf), isEmpty);

      final frames = parser.addChunk(secondHalf);
      expect(frames, hasLength(1));
      expect(frames.first, equals(jpeg));
    });

    test('handles a header split across two chunks', () {
      final parser = MjpegParser();
      final jpeg = fakeJpeg(32);
      final part = multipart(jpeg);

      expect(parser.addChunk(part.sublist(0, 10)), isEmpty);
      final frames = parser.addChunk(part.sublist(10));

      expect(frames, hasLength(1));
      expect(frames.first, equals(jpeg));
    });

    test('emits every frame when one read carries several', () {
      final parser = MjpegParser();
      final a = fakeJpeg(16, fill: 0x11);
      final b = fakeJpeg(24, fill: 0x22);
      final c = fakeJpeg(8, fill: 0x33);

      final frames = parser.addChunk([
        ...multipart(a),
        ...multipart(b),
        ...multipart(c),
      ]);

      expect(frames, hasLength(3));
      expect(frames[0], equals(a));
      expect(frames[1], equals(b));
      expect(frames[2], equals(c));
    });

    test('a body containing the boundary bytes is not truncated', () {
      // This is the case that breaks boundary-scanning parsers: the JPEG
      // payload legitimately contains the multipart boundary as binary data.
      final boundary = '\r\n--visionwearframe\r\n'.codeUnits;
      final payload = <int>[
        0xFF, 0xD8,
        ...boundary,
        ...boundary,
        0xFF, 0xD9,
      ];
      final jpeg = Uint8List.fromList(payload);

      final parser = MjpegParser();
      final frames = parser.addChunk(multipart(jpeg));

      expect(frames, hasLength(1));
      expect(frames.first.length, equals(jpeg.length));
      expect(frames.first, equals(jpeg));
    });

    test('falls back to the JPEG end marker without a Content-Length', () {
      final parser = MjpegParser();
      final jpeg = fakeJpeg(48);

      final frames = parser.addChunk(
        multipart(jpeg, withContentLength: false),
      );

      expect(frames, hasLength(1));
      expect(frames.first, equals(jpeg));
    });

    test('drops non-JPEG payloads instead of emitting garbage', () {
      final parser = MjpegParser();
      final notJpeg = Uint8List.fromList(List.filled(20, 0x00));

      final frames = parser.addChunk(multipart(notJpeg));

      expect(frames, isEmpty);
    });

    test('recovers after a reset mid-stream', () {
      final parser = MjpegParser();
      final jpeg = fakeJpeg(40);
      final part = multipart(jpeg);

      parser.addChunk(part.sublist(0, part.length - 10));
      parser.reset();

      final frames = parser.addChunk(multipart(jpeg));
      expect(frames, hasLength(1));
      expect(frames.first, equals(jpeg));
    });

    test('does not grow without bound on a desynchronised stream', () {
      final parser = MjpegParser(maxFrameBytes: 1024);

      // Pure noise with no header terminator: nothing can ever be parsed.
      for (var i = 0; i < 10; i++) {
        final frames = parser.addChunk(List.filled(512, 0x7F));
        expect(frames, isEmpty);
      }

      // After the reset triggered by the size cap, a clean part still parses.
      final jpeg = fakeJpeg(24);
      final frames = parser.addChunk(multipart(jpeg));
      expect(frames, hasLength(1));
      expect(frames.first, equals(jpeg));
    });
  });
}
