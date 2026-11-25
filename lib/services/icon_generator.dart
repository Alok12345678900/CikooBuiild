import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Membuat semua ukuran icon Android dari satu gambar (PNG / JPG / WebP).
class IconGenerator {
  static const Map<String, int> legacySizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  static const Map<String, int> foregroundSizes = {
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
  };

  /// Hasil: legacy_<density>, round_<density>, fg_<density> → bytes PNG.
  static Future<Map<String, Uint8List>> generate(Uint8List source) async {
    final codec = await ui.instantiateImageCodec(source);
    final frame = await codec.getNextFrame();
    final original = frame.image;

    // Potong jadi persegi (maks 1024 px) lebih dulu agar hasil kecil tetap tajam.
    final side = math.min(math.min(original.width, original.height), 1024);
    final square = await _draw(original, side);

    final out = <String, Uint8List>{};
    for (final e in legacySizes.entries) {
      out['legacy_${e.key}'] = await _png(await _draw(square, e.value));
      out['round_${e.key}'] = await _png(await _draw(square, e.value, circle: true));
    }
    for (final e in foregroundSizes.entries) {
      // Konten di zona aman adaptive icon (66 dari 108 dp).
      out['fg_${e.key}'] = await _png(await _draw(square, e.value, scale: 0.66));
    }

    original.dispose();
    square.dispose();
    return out;
  }

  static Future<ui.Image> _draw(
    ui.Image img,
    int size, {
    double scale = 1.0,
    bool circle = false,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..filterQuality = ui.FilterQuality.medium
      ..isAntiAlias = true;

    final side = math.min(img.width, img.height).toDouble();
    final src = ui.Rect.fromLTWH((img.width - side) / 2, (img.height - side) / 2, side, side);
    final dstSide = size * scale;
    final off = (size - dstSide) / 2;
    final dst = ui.Rect.fromLTWH(off, off, dstSide, dstSide);

    if (circle) {
      canvas.clipPath(ui.Path()..addOval(dst));
    }
    canvas.drawImageRect(img, src, dst, paint);
    return recorder.endRecording().toImage(size, size);
  }

  static Future<Uint8List> _png(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    image.dispose();
    return bytes;
  }
}
