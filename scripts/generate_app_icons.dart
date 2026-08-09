import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final srcFile = File('/home/ngudoliswoga/camera/assets/icon.png');
  if (!srcFile.existsSync()) {
    print('Source icon not found!');
    return;
  }

  final bytes = srcFile.readAsBytesSync();
  final image = img.decodePng(bytes);
  if (image == null) return;

  final sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  final resDir = Directory('/home/ngudoliswoga/camera/android/app/src/main/res');

  sizes.forEach((folder, size) {
    final resized = img.copyResize(image, width: size, height: size);
    final targetDir = Directory('${resDir.path}/$folder');
    if (!targetDir.existsSync()) targetDir.createSync(recursive: true);
    final targetFile = File('${targetDir.path}/ic_launcher.png');
    targetFile.writeAsBytesSync(img.encodePng(resized));
    print('Generated ${targetFile.path} (${size}x${size})');
  });
}
