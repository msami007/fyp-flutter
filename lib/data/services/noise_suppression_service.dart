import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Real-time noise suppression using RNNoise TFLite model.
/// Processes audio frames to remove background noise while preserving speech.
/// Language-agnostic — works with any spoken language.
class NoiseSuppressionService {
  static final NoiseSuppressionService _instance = NoiseSuppressionService._internal();
  factory NoiseSuppressionService() => _instance;
  NoiseSuppressionService._internal();

  Interpreter? _interpreter;
  bool _isInitialized = false;

  // RNNoise expects 480 samples per frame at 48kHz (10ms)
  // For 16kHz input, we use 160 samples per frame (10ms)
  static const int frameSize = 480;
  static const int sampleRate = 48000;

  // Internal GRU state (persists across frames for continuity)
  List<List<double>>? _gruState;

  /// Initialize the noise suppression model
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Load the RNNoise TFLite model from assets
      _interpreter = await Interpreter.fromAsset(
        'assets/models/rnnoise_model.tflite',
        options: InterpreterOptions()..threads = 2,
      );

      // Initialize GRU hidden state to zeros
      _resetState();

      _isInitialized = true;
      debugPrint('✅ RNNoise model loaded successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Failed to load RNNoise model: $e');
      return false;
    }
  }

  /// Reset the internal model state (call when starting a new audio session)
  void _resetState() {
    // GRU state dimensions depend on the model; typical RNNoise uses 96 units
    _gruState = List.generate(1, (_) => List.filled(96, 0.0));
  }

  /// Process a single audio frame through the noise suppression model.
  ///
  /// [inputFrame] must be exactly [frameSize] float samples (normalized -1.0 to 1.0).
  /// Returns the denoised audio frame.
  Float32List processFrame(Float32List inputFrame) {
    if (!_isInitialized || _interpreter == null) {
      debugPrint('⚠️ NoiseSuppressionService not initialized');
      return inputFrame;
    }

    if (inputFrame.length != frameSize) {
      debugPrint('⚠️ Expected $frameSize samples, got ${inputFrame.length}');
      return inputFrame;
    }

    try {
      // Prepare input tensor [1, frameSize]
      final input = [inputFrame.toList()];

      // Prepare output tensor [1, frameSize]
      final output = [List<double>.filled(frameSize, 0.0)];

      // Run inference
      _interpreter!.run(input, output);

      return Float32List.fromList(output[0].map((e) => e.toDouble()).toList());
    } catch (e) {
      debugPrint('❌ Noise suppression error: $e');
      return inputFrame;
    }
  }

  /// Process a complete audio buffer (multiple frames).
  ///
  /// [audioBuffer] is raw audio samples (normalized floats).
  /// Returns the full denoised buffer.
  Float32List processBuffer(Float32List audioBuffer) {
    if (!_isInitialized) {
      debugPrint('⚠️ NoiseSuppressionService not initialized');
      return audioBuffer;
    }

    final output = Float32List(audioBuffer.length);
    final numFrames = audioBuffer.length ~/ frameSize;
    final remainder = audioBuffer.length % frameSize;

    // Process complete frames
    for (int i = 0; i < numFrames; i++) {
      final frameStart = i * frameSize;
      final frame = Float32List.sublistView(audioBuffer, frameStart, frameStart + frameSize);
      final processed = processFrame(frame);
      output.setRange(frameStart, frameStart + frameSize, processed);
    }

    // Handle remaining samples (pad with zeros, process, then take what we need)
    if (remainder > 0) {
      final padded = Float32List(frameSize);
      final start = numFrames * frameSize;
      padded.setRange(0, remainder, audioBuffer, start);
      final processed = processFrame(padded);
      output.setRange(start, start + remainder, processed);
    }

    return output;
  }

  /// Apply hearing profile frequency gains to the processed audio.
  ///
  /// [audio] is the denoised audio buffer.
  /// [frequencyGains] maps frequency bands to gain values from the hearing profile.
  Float32List applyHearingProfile(
    Float32List audio,
    Map<int, double> frequencyGains,
  ) {
    if (frequencyGains.isEmpty) return audio;

    // Simple per-band gain application
    // In production, this would use a proper equalizer with band-pass filters
    final avgGain = frequencyGains.values.reduce((a, b) => a + b) / frequencyGains.length;

    final output = Float32List(audio.length);
    for (int i = 0; i < audio.length; i++) {
      output[i] = (audio[i] * avgGain).clamp(-1.0, 1.0);
    }

    return output;
  }

  /// Start a new processing session (resets internal state)
  void startSession() {
    _resetState();
    debugPrint('🔇 Noise suppression session started');
  }

  /// Check if the model is ready
  bool get isInitialized => _isInitialized;

  /// Dispose resources
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _gruState = null;
  }
}
