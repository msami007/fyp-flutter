import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Manages download, storage, and lifecycle of AI model files.
class ModelManagerService {
  static final ModelManagerService _instance = ModelManagerService._internal();
  factory ModelManagerService() => _instance;
  ModelManagerService._internal();

  // ── Whisper model metadata ──
  static const Map<String, Map<String, dynamic>> whisperModels = {
    'tiny': {
      'filename': 'ggml-tiny.bin',
      'size': 75,        // MB
      'url': 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin',
      'urdu': '⚠️ Basic',
      'english': '🟡 Okay',
    },
    'base': {
      'filename': 'ggml-base.bin',
      'size': 142,
      'url': 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
      'urdu': '🟡 Okay',
      'english': '✅ Good',
    },
    'small': {
      'filename': 'ggml-small.bin',
      'size': 466,
      'url': 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
      'urdu': '✅ Good',
      'english': '✅ Good',
    },
    'medium': {
      'filename': 'ggml-medium.bin',
      'size': 1500,
      'url': 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin',
      'urdu': '✅ Very Good',
      'english': '✅ Excellent',
    },
  };

  /// Get the models directory path
  Future<String> get modelsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/hearwise_models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// Check if a specific Whisper model is downloaded
  Future<bool> isModelDownloaded(String modelName) async {
    final dir = await modelsDir;
    final filename = whisperModels[modelName]?['filename'] ?? '';
    final file = File('$dir/$filename');
    return file.exists();
  }

  /// Get the path to a downloaded Whisper model
  Future<String?> getModelPath(String modelName) async {
    final dir = await modelsDir;
    final filename = whisperModels[modelName]?['filename'] ?? '';
    final file = File('$dir/$filename');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  /// Get the currently active Whisper model name (saved in prefs)
  Future<String> getActiveWhisperModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('active_whisper_model') ?? 'tiny';
  }

  /// Set the active Whisper model
  Future<void> setActiveWhisperModel(String modelName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_whisper_model', modelName);
  }

  /// Get the active model file path, returns null if not downloaded
  Future<String?> getActiveModelPath() async {
    final active = await getActiveWhisperModel();
    return getModelPath(active);
  }

  /// Download a Whisper model with progress callback
  /// [onProgress] receives a value between 0.0 and 1.0
  Future<void> downloadModel(
    String modelName, {
    Function(double progress)? onProgress,
  }) async {
    final modelInfo = whisperModels[modelName];
    if (modelInfo == null) throw Exception('Unknown model: $modelName');

    final dir = await modelsDir;
    final filePath = '$dir/${modelInfo['filename']}';
    final tempPath = '$filePath.tmp';

    try {
      final request = http.Request('GET', Uri.parse(modelInfo['url']));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to download model: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final file = File(tempPath);
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(receivedBytes / totalBytes);
        }
      }

      await sink.close();

      // Rename temp file to final path
      await File(tempPath).rename(filePath);

      debugPrint('✅ Model $modelName downloaded to $filePath');
    } catch (e) {
      // Clean up temp file on error
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  /// Delete a downloaded Whisper model
  Future<void> deleteModel(String modelName) async {
    final path = await getModelPath(modelName);
    if (path != null) {
      await File(path).delete();
      debugPrint('🗑️ Deleted model: $modelName');

      // If this was the active model, fall back to tiny
      final active = await getActiveWhisperModel();
      if (active == modelName) {
        await setActiveWhisperModel('tiny');
      }
    }
  }

  /// Get a list of all downloaded models with their info
  Future<List<Map<String, dynamic>>> getDownloadedModels() async {
    final result = <Map<String, dynamic>>[];
    for (final entry in whisperModels.entries) {
      final downloaded = await isModelDownloaded(entry.key);
      result.add({
        'name': entry.key,
        'downloaded': downloaded,
        ...entry.value,
      });
    }
    return result;
  }

  /// Get total disk usage of all downloaded models
  Future<int> getTotalModelSize() async {
    final dir = await modelsDir;
    final modelsDirectory = Directory(dir);
    if (!await modelsDirectory.exists()) return 0;

    int totalSize = 0;
    await for (final entity in modelsDirectory.list()) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }
}
