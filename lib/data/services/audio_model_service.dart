import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Service to run TFLite models (DTLN and RNN) for audio processing.
class AudioModelService {
  static final AudioModelService _instance = AudioModelService._internal();
  factory AudioModelService() => _instance;
  AudioModelService._internal();

  Interpreter? _dtlnInterpreter;
  Interpreter? _rnnInterpreter;
  bool _isDtlnLoaded = false;
  bool _isRnnLoaded = false;

  bool get isDtlnReady => _isDtlnLoaded;
  bool get isRnnReady => _isRnnLoaded;

  /// Load DTLN model from assets
  Future<void> loadDtln() async {
    try {
      _dtlnInterpreter = await Interpreter.fromAsset('assets/models/dtln_model.tflite');
      _isDtlnLoaded = true;
      debugPrint('✅ DTLN model loaded');
    } catch (e) {
      debugPrint('❌ Failed to load DTLN model: $e');
      _isDtlnLoaded = false;
    }
  }

  /// Load RNN model from assets
  Future<void> loadRnn() async {
    try {
      _rnnInterpreter = await Interpreter.fromAsset('assets/models/rnn_noise.tflite');
      _isRnnLoaded = true;
      debugPrint('✅ RNN model loaded');
    } catch (e) {
      debugPrint('❌ Failed to load RNN model: $e');
      _isRnnLoaded = false;
    }
  }

  /// Process a fixed-size block of 16kHz audio through DTLN.
  /// Input must be exactly the expected block size (e.g., 512 samples).
  Float32List processDtln(Float32List input) {
    if (_dtlnInterpreter == null) return input;

    try {
      // Reshape input for TFLite [1, block_size]
      var inputReshaped = input.reshape([1, input.length]);
      var outputBuffer = List.generate(1, (_) => Float32List(input.length));

      _dtlnInterpreter!.run(inputReshaped, outputBuffer);

      // Flatten back to Float32List
      return Float32List.fromList(
        outputBuffer[0].map((e) => (e as num).toDouble()).toList(),
      );
    } catch (e) {
      debugPrint('⚠️ DTLN inference error: $e — returning input unchanged');
      return input;
    }
  }

  /// Process a fixed-size block of 16kHz audio through RNN.
  Float32List processRnn(Float32List input) {
    if (_rnnInterpreter == null) return input;

    try {
      var inputReshaped = input.reshape([1, input.length]);
      var outputBuffer = List.generate(1, (_) => Float32List(input.length));

      _rnnInterpreter!.run(inputReshaped, outputBuffer);

      return Float32List.fromList(
        outputBuffer[0].map((e) => (e as num).toDouble()).toList(),
      );
    } catch (e) {
      debugPrint('⚠️ RNN inference error: $e — returning input unchanged');
      return input;
    }
  }

  void dispose() {
    _dtlnInterpreter?.close();
    _rnnInterpreter?.close();
    _isDtlnLoaded = false;
    _isRnnLoaded = false;
  }
}
