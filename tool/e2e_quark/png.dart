import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// Encodes an 8-bit RGB image as PNG. [rgb] holds width * height * 3 bytes.
///
/// The seed step generates its photos with this instead of ImageMagick, so
/// the harness needs nothing beyond the Dart SDK to build a household.
Uint8List encodePng(int width, int height, Uint8List rgb) {
  if (rgb.length != width * height * 3) {
    throw ArgumentError(
      'expected ${width * height * 3} bytes, got ${rgb.length}',
    );
  }
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    raw.add(Uint8List.sublistView(rgb, y * width * 3, (y + 1) * width * 3));
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(_chunk('IDAT', ZLibEncoder(level: 6).convert(raw.takeBytes())))
    ..add(_chunk('IEND', const []));
  return out.takeBytes();
}

/// A deterministic 640 x 480 gradient whose hue depends on [index].
Uint8List seedPhoto(int index, {int width = 640, int height = 480}) {
  final rgb = Uint8List(width * height * 3);
  final r0 = (index * 37) % 256;
  final g0 = (index * 91) % 256;
  final b0 = (index * 53) % 256;
  var i = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final t = (x * 255) ~/ (width - 1);
      final u = (y * 255) ~/ (height - 1);
      rgb[i++] = (r0 + t) % 256;
      rgb[i++] = (g0 + u) % 256;
      rgb[i++] = (b0 + 255 - t) % 256;
    }
  }
  return encodePng(width, height, rgb);
}

List<int> _chunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  return [
    ...length.buffer.asUint8List(),
    ...typeBytes,
    ...data,
    ...crc.buffer.asUint8List(),
  ];
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xffffffff;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xff] ^ (c >> 8);
  }
  return c ^ 0xffffffff;
}
