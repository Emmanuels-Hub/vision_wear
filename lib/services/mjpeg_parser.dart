import 'dart:typed_data';

/// Incremental parser for `multipart/x-mixed-replace` MJPEG streams.
///
/// Chunks arrive from the socket at arbitrary boundaries, so the parser keeps
/// a rolling buffer and emits a frame only once its full body has landed.
///
/// It reads `Content-Length` from each part header rather than scanning for the
/// multipart boundary in the body. Boundary scanning is what makes naive MJPEG
/// readers corrupt frames: JPEG payloads are binary and can legitimately
/// contain the boundary bytes. If a part ever arrives without a
/// `Content-Length`, the parser falls back to scanning for the JPEG end-of-image
/// marker.
class MjpegParser {
  MjpegParser({this.maxFrameBytes = 512 * 1024});

  /// Guards against a desynchronised stream growing the buffer without bound.
  final int maxFrameBytes;

  static const List<int> _headerTerminator = [13, 10, 13, 10]; // \r\n\r\n
  static const int _jpegSoi0 = 0xFF;
  static const int _jpegSoi1 = 0xD8;
  static const int _jpegEoi1 = 0xD9;

  final BytesBuilder _buffer = BytesBuilder(copy: true);
  Uint8List _pending = Uint8List(0);

  int? _expectedLength;
  bool _inBody = false;

  /// Feeds a chunk and returns every complete frame it completed.
  ///
  /// Returns a list because a single large socket read can carry more than one
  /// frame, and dropping the extras would silently halve the frame rate.
  List<Uint8List> addChunk(List<int> chunk) {
    _buffer.add(chunk);
    _pending = _buffer.takeBytes();
    // takeBytes() drains the builder, so anything left unconsumed below is put
    // back before returning.

    final frames = <Uint8List>[];
    var offset = 0;

    while (true) {
      if (!_inBody) {
        final headerEnd = _indexOf(_pending, _headerTerminator, offset);
        if (headerEnd < 0) break;

        final headerBytes = _pending.sublist(offset, headerEnd);
        _expectedLength = _parseContentLength(headerBytes);
        offset = headerEnd + _headerTerminator.length;
        _inBody = true;
      }

      final available = _pending.length - offset;

      if (_expectedLength != null) {
        if (available < _expectedLength!) break;
        final frame = Uint8List.sublistView(
          _pending,
          offset,
          offset + _expectedLength!,
        );
        if (_looksLikeJpeg(frame)) {
          frames.add(Uint8List.fromList(frame));
        }
        offset += _expectedLength!;
        _expectedLength = null;
        _inBody = false;
      } else {
        // No Content-Length on this part: scan for the JPEG end marker.
        final eoi = _indexOfJpegEoi(_pending, offset);
        if (eoi < 0) break;
        final frame = Uint8List.sublistView(_pending, offset, eoi + 2);
        if (_looksLikeJpeg(frame)) {
          frames.add(Uint8List.fromList(frame));
        }
        offset = eoi + 2;
        _inBody = false;
      }
    }

    final remaining = _pending.length - offset;
    if (remaining > 0) {
      if (remaining > maxFrameBytes) {
        // Desynchronised beyond recovery. Drop everything and resync on the
        // next header rather than growing forever.
        reset();
      } else {
        _buffer.add(Uint8List.sublistView(_pending, offset));
      }
    }
    _pending = Uint8List(0);

    return frames;
  }

  void reset() {
    _buffer.clear();
    _pending = Uint8List(0);
    _expectedLength = null;
    _inBody = false;
  }

  static bool _looksLikeJpeg(Uint8List data) =>
      data.length > 4 && data[0] == _jpegSoi0 && data[1] == _jpegSoi1;

  static int? _parseContentLength(Uint8List headerBytes) {
    // Headers are ASCII; decoding byte-wise avoids a UTF-8 failure if a stray
    // binary byte lands in the header region of a desynchronised stream.
    final text = String.fromCharCodes(headerBytes).toLowerCase();
    final match = RegExp(r'content-length:\s*(\d+)').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static int _indexOf(Uint8List haystack, List<int> needle, int start) {
    final limit = haystack.length - needle.length;
    outer:
    for (var i = start; i <= limit; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static int _indexOfJpegEoi(Uint8List data, int start) {
    for (var i = start; i < data.length - 1; i++) {
      if (data[i] == _jpegSoi0 && data[i + 1] == _jpegEoi1) return i;
    }
    return -1;
  }
}
