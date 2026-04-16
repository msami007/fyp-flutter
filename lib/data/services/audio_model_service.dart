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

  /// Process a block of audio through DTLN
  /// Expected block size depends on the model (e.g., 512 samples)
  Float32List processDtln(Float32List input) {
    if (_dtlnInterpreter == null) return input;

    // Reshape input for TFLite [1, block_size]
    var inputReshaped = input.reshape([1, input.length]);
    var outputReshaped = Float32List(input.length).reshape([1, input.length]);

    _dtlnInterpreter!.run(inputReshaped, outputReshaped);

    // Flatten back to Float32List
    return Float32List.fromList(outputReshaped[0] as List<double>);
  }

  /// Process a block of audio through RNN
  Float32List processRnn(Float32List input) {
    if (_rnnInterpreter == null) return input;

    var inputReshaped = input.reshape([1, input.length]);
    var outputReshaped = Float32List(input.length).reshape([1, input.length]);

    _rnnInterpreter!.run(inputReshaped, outputReshaped);

    return Float32List.fromList(outputReshaped[0] as List<double>);
  }

  void dispose() {
    _dtlnInterpreter?.close();
    _rnnInterpreter?.close();
    _isDtlnLoaded = false;
    _isRnnLoaded = false;
  }
}
