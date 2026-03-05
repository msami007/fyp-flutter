import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'package:path_provider/path_provider.dart';
import 'model_manager_service.dart';

/// Local speech-to-text transcription using Whisper (whisper.cpp).
/// Runs entirely on-device — no internet required after model download.
class TranscriptionService {
  static final TranscriptionService _instance = TranscriptionService._internal();
  factory TranscriptionService() => _instance;
  TranscriptionService._internal();

  final ModelManagerService _modelManager = ModelManagerService();
  Whisper? _whisper;
  String? _loadedModelName;

  /// Supported languages for transcription
  static const Map<String, String> supportedLanguages = {
    'auto': 'Auto Detect',
    'en': 'English',
    'ur': 'Urdu',
    'pa': 'Punjabi',
    'hi': 'Hindi',
    'ar': 'Arabic',
  };

  /// Map our model names to WhisperModel enum values
  static const Map<String, WhisperModel> _modelMap = {
    'tiny': WhisperModel.tiny,
    'base': WhisperModel.base,
    'small': WhisperModel.small,
    'medium': WhisperModel.medium,
  };

  /// Initialize Whisper with the currently active model.
  /// Must be called before transcribing.
  Future<bool> initialize() async {
    try {
      final activeModel = await _modelManager.getActiveWhisperModel();

      // Only re-initialize if model changed
      if (_whisper != null && _loadedModelName == activeModel) {
        return true;
      }

      final whisperModel = _modelMap[activeModel] ?? WhisperModel.tiny;
      final modelsDir = await _modelManager.modelsDir;

      _whisper = Whisper(
        model: whisperModel,
        modelDir: modelsDir,
      );
      _loadedModelName = activeModel;

      debugPrint('✅ Whisper initialized with "$activeModel" model');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to initialize Whisper: $e');
      return false;
    }
  }

  /// Transcribe an audio file to text.
  ///
  /// [audioPath] must be a WAV file (16kHz, mono, 16-bit PCM).
  /// [language] is one of the keys from [supportedLanguages], or 'auto'.
  /// Returns a [TranscriptionResult] with text and segments.
  Future<TranscriptionResult> transcribe({
    required String audioPath,
    String language = 'auto',
  }) async {
    if (_whisper == null) {
      final initialized = await initialize();
      if (!initialized) {
        return TranscriptionResult(
          text: '[Error: Whisper model not available]',
          segments: [],
          language: language,
        );
      }
    }

    try {
      final result = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: audioPath,
          language: language == 'auto' ? 'auto' : language,
          isTranslate: false,
          isNoTimestamps: false,
          threads: 4,
        ),
      );

      final segments = result.segments ?? [];

      return TranscriptionResult(
        text: result.text.trim(),
        segments: segments
            .map((s) => TranscriptionSegment(
                  text: s.text.trim(),
                  startMs: s.fromTs.inMilliseconds,
                  endMs: s.toTs.inMilliseconds,
                ))
            .toList(),
        language: language,
      );
    } catch (e) {
      debugPrint('❌ Transcription error: $e');
      return TranscriptionResult(
        text: '[Error: $e]',
        segments: [],
        language: language,
      );
    }
  }

  /// Transcribe from a PCM buffer by first saving to a temp WAV file.
  Future<TranscriptionResult> transcribeFromPCM({
    required List<int> pcmData,
    int sampleRate = 16000,
    String language = 'auto',
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/whisper_input_${DateTime.now().millisecondsSinceEpoch}.wav');

    try {
      // Write PCM data as WAV
      await _writeWavFile(tempFile, pcmData, sampleRate);

      // Transcribe
      final result = await transcribe(
        audioPath: tempFile.path,
        language: language,
      );

      return result;
    } finally {
      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// Write PCM data to a WAV file
  Future<void> _writeWavFile(File file, List<int> pcmData, int sampleRate) async {
    final numChannels = 1;
    final bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final blockAlign = numChannels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little);  // PCM format
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final bytes = <int>[
      ...header.buffer.asUint8List(),
      ...pcmData,
    ];

    await file.writeAsBytes(bytes);
  }

  /// Get info about the currently loaded model
  String? get loadedModelName => _loadedModelName;

  /// Dispose resources
  void dispose() {
    _whisper = null;
    _loadedModelName = null;
  }
}

/// Result of a transcription operation
class TranscriptionResult {
  final String text;
  final List<TranscriptionSegment> segments;
  final String language;

  TranscriptionResult({
    required this.text,
    required this.segments,
    required this.language,
  });
}

/// A segment within a transcription, with timing info
class TranscriptionSegment {
  final String text;
  final int startMs;
  final int endMs;

  TranscriptionSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
  });
}
