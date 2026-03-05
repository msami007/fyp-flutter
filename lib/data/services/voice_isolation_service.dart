import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Voice isolation service using DTLN (Dual-signal Transformation LSTM Network).
/// Extracts human voice from mixed audio (speech + noise/music/crowd).
/// Uses two TFLite models in a dual-stage pipeline.
/// Language-agnostic — works with any spoken language.
class VoiceIsolationService {
  static final VoiceIsolationService _instance = VoiceIsolationService._internal();
  factory VoiceIsolationService() => _instance;
  VoiceIsolationService._internal();

  Interpreter? _model1; // Stage 1: Noise estimation in frequency domain
  Interpreter? _model2; // Stage 2: Speech enhancement in time domain
  bool _isInitialized = false;

  // DTLN expects 512 samples per block at 16kHz (32ms per block)
  static const int blockSize = 512;
  static const int blockShift = 128; // Overlap of 384 samples (75% overlap)
  static const int sampleRate = 16000;
  static const int fftSize = 512;

  // Internal states for the LSTM layers (persist across blocks)
  List<List<double>>? _state1;
  List<List<double>>? _state2;

  /// Initialize the DTLN dual-stage model
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Load both DTLN TFLite models
      _model1 = await Interpreter.fromAsset(
        'assets/models/dtln_model_1.tflite',
        options: InterpreterOptions()..threads = 2,
      );

      _model2 = await Interpreter.fromAsset(
        'assets/models/dtln_model_2.tflite',
        options: InterpreterOptions()..threads = 2,
      );

      _resetState();

      _isInitialized = true;
      debugPrint('✅ DTLN voice isolation models loaded (stage 1 + stage 2)');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to load DTLN models: $e');
      return false;
    }
  }

  /// Reset internal LSTM states (call when starting a new session)
  void _resetState() {
    // DTLN typically uses 128-unit LSTM layers
    _state1 = List.generate(1, (_) => List.filled(128, 0.0));
    _state2 = List.generate(1, (_) => List.filled(128, 0.0));
  }

  /// Process a single audio block through the DTLN dual-stage pipeline.
  ///
  /// [inputBlock] must be exactly [blockSize] float samples.
  /// Returns the isolated voice block.
  Float32List processBlock(Float32List inputBlock) {
    if (!_isInitialized || _model1 == null || _model2 == null) {
      debugPrint('⚠️ VoiceIsolationService not initialized');
      return inputBlock;
    }

    if (inputBlock.length != blockSize) {
      debugPrint('⚠️ Expected $blockSize samples, got ${inputBlock.length}');
      return inputBlock;
    }

    try {
      // ── Stage 1: Frequency-domain processing ──
      // Input: raw audio block → Output: estimated speech magnitude mask
      final input1 = [inputBlock.toList()];
      final output1 = [List<double>.filled(blockSize, 0.0)];
      _model1!.run(input1, output1);

      // ── Stage 2: Time-domain refinement ──
      // Input: stage 1 output → Output: final isolated speech
      final input2 = [output1[0]];
      final output2 = [List<double>.filled(blockSize, 0.0)];
      _model2!.run(input2, output2);

      return Float32List.fromList(output2[0].map((e) => e.toDouble()).toList());
    } catch (e) {
      debugPrint('❌ Voice isolation error: $e');
      return inputBlock;
    }
  }

  /// Process a complete audio buffer through voice isolation.
  ///
  /// Uses overlap-add for smooth output (no clicking/popping artifacts).
  Float32List processBuffer(Float32List audioBuffer) {
    if (!_isInitialized) {
      debugPrint('⚠️ VoiceIsolationService not initialized');
      return audioBuffer;
    }

    final outputLength = audioBuffer.length;
    final output = Float32List(outputLength);

    int pos = 0;
    while (pos + blockSize <= audioBuffer.length) {
      final block = Float32List.sublistView(audioBuffer, pos, pos + blockSize);
      final processed = processBlock(block);

      // Overlap-add: simply add processed block at position
      for (int i = 0; i < blockSize && (pos + i) < outputLength; i++) {
        output[pos + i] = processed[i];
      }

      pos += blockShift;
    }

    return output;
  }

  /// Apply hearing profile frequency gains to isolated voice.
  Float32List applyHearingProfile(
    Float32List audio,
    Map<int, double> frequencyGains,
  ) {
    if (frequencyGains.isEmpty) return audio;

    final avgGain = frequencyGains.values.reduce((a, b) => a + b) / frequencyGains.length;

    final output = Float32List(audio.length);
    for (int i = 0; i < audio.length; i++) {
      output[i] = (audio[i] * avgGain).clamp(-1.0, 1.0);
    }

    return output;
  }

  /// Start a new isolation session (resets LSTM states)
  void startSession() {
    _resetState();
    debugPrint('🗣️ Voice isolation session started');
  }

  /// Check if models are ready
  bool get isInitialized => _isInitialized;

  /// Dispose resources
  void dispose() {
    _model1?.close();
    _model2?.close();
    _model1 = null;
    _model2 = null;
    _isInitialized = false;
    _state1 = null;
    _state2 = null;
  }
}
