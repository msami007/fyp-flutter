// ignore_for_file: avoid_print
//
// Run this script after cloning the repo:
//   dart run tool/download_models.dart
//
// It downloads the Vosk speech recognition models required for offline
// transcription. These files are excluded from git (see .gitignore).

import 'dart:io';

const models = {
  'vosk-model-small-en-us-0.15.zip':
      'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip',
  'vosk-model-small-hi-0.22.zip':
      'https://alphacephei.com/vosk/models/vosk-model-small-hi-0.22.zip',
  'dtln_1.tflite':
      'https://github.com/breizhn/DTLN/raw/master/pretrained_model/model_1.tflite',
  'dtln_2.tflite':
      'https://github.com/breizhn/DTLN/raw/master/pretrained_model/model_2.tflite',
};

Future<void> main() async {
  final modelsDir = Directory('assets/models');
  if (!modelsDir.existsSync()) {
    modelsDir.createSync(recursive: true);
    print('📁 Created assets/models/');
  }

  for (final entry in models.entries) {
    final file = File('${modelsDir.path}/${entry.key}');

    if (file.existsSync()) {
      final sizeMB = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
      print('✅ ${entry.key} already exists (${sizeMB} MB) — skipping');
      continue;
    }

    print('⬇️  Downloading ${entry.key}...');
    final stopwatch = Stopwatch()..start();

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(entry.value));
      final response = await request.close();

      if (response.statusCode != 200) {
        print('❌ Failed: HTTP ${response.statusCode}');
        continue;
      }

      final sink = file.openWrite();
      int downloaded = 0;
      final contentLength = response.contentLength;

      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          final pct = (downloaded / contentLength * 100).toInt();
          stdout.write('\r   $pct% (${(downloaded / 1024 / 1024).toStringAsFixed(1)} MB)');
        }
      }

      await sink.close();
      client.close();
      stopwatch.stop();

      final sizeMB = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
      print('\r✅ ${entry.key} — ${sizeMB} MB in ${stopwatch.elapsed.inSeconds}s');
    } catch (e) {
      print('❌ Error downloading ${entry.key}: $e');
      if (file.existsSync()) file.deleteSync();
    }
  }

  print('\n🎉 Done! You can now run: flutter build apk --debug');
}
