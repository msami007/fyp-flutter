import 'dart:math';
import 'dart:typed_data';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'HearingProfileService.dart';
import 'native_audio_api.dart';

enum EnhancementMode {
  standard, // Biquad EQ + Noise Reduction
  dtln,     // AI Noise Suppression
  rnn,      // AI Voice Isolation
  krisp,    // AI + Spectral Post-Processing (High Quality)
}

/// Lightweight audio enhancement using IIR biquad filters.
class AudioEnhancementService {
  static final AudioEnhancementService _instance =
      AudioEnhancementService._internal();
  factory AudioEnhancementService() => _instance;
  AudioEnhancementService._internal();

  static const _channel = MethodChannel('com.fyp_flutter/audio_route');

  static const int sampleRate = 48000;

  EnhancementMode _mode = EnhancementMode.standard;
  EnhancementMode get mode => _mode;

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  bool _profileLoaded = false;
  bool get profileLoaded => _profileLoaded;

  /// Independent Ear Gains
  double _leftGain = 1.0;
  double _rightGain = 1.0;

  /// Overall Master Volume
  double _masterVolume = 1.0;

  /// Fine-tuning (Tone)
  double _tone = 0.5;

  /// Noise suppression strength (0.0 to 1.0)
  double _suppressionLevel = 0.5;

  final List<int> _testFrequencies = [
    125, 250, 375, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 7000, 8000
  ];

  static const double maxBoostDb = 12.0;

  /// Initialize and load models into memory for the native engine.
  Future<bool> initialize() async {
    final profile = await HearingProfileService().getLocalProfile();
    if (profile != null) {
      _loadProfile(profile);
      _profileLoaded = true;
    }

    // Load DTLN models for Native Engine
    try {
      final ByteData m1 = await rootBundle.load('assets/models/dtln_1.tflite');
      final Uint8List d1 = m1.buffer.asUint8List();
      final ByteData m2 = await rootBundle.load('assets/models/dtln_2.tflite');
      final Uint8List d2 = m2.buffer.asUint8List();

      final Pointer<Uint8> p1 = calloc<Uint8>(d1.length);
      p1.asTypedList(d1.length).setAll(0, d1);
      final Pointer<Uint8> p2 = calloc<Uint8>(d2.length);
      p2.asTypedList(d2.length).setAll(0, d2);

      final ok = NativeAudioApi.loadDtlnModels(p1.cast(), d1.length, p2.cast(), d2.length);
      debugPrint(ok ? '✅ DTLN models loaded into Native Engine' : '❌ Native DTLN load failed');
    } catch (e) {
      debugPrint('⚠️ DTLN asset load error: $e');
    }

    debugPrint('✅ AudioEnhancementService initialized');
    return true;
  }

  void _loadProfile(Map<String, dynamic> profile) {
    final freqMap = profile['frequencyMap'] as Map<String, dynamic>?;
    if (freqMap == null) return;

    final List<double> nativeGains = List.filled(13, 0.0);
    for (int i = 0; i < _testFrequencies.length; i++) {
      final freq = _testFrequencies[i];
      final leftVal = (freqMap['L_$freq'] as num?)?.toDouble() ?? 1.0;
      final rightVal = (freqMap['R_$freq'] as num?)?.toDouble() ?? 1.0;
      final avgLoss = 1.0 - ((leftVal + rightVal) / 2.0).clamp(0.0, 1.0);
      nativeGains[i] = avgLoss * maxBoostDb;
    }
    NativeAudioApi.updateEq(nativeGains);
  }

  void setMode(EnhancementMode mode) {
    _mode = mode;
    // Update Native Engine: 0 for RNN (RNNoise), 1 for DTLN
    NativeAudioApi.setProcessingMode(mode == EnhancementMode.dtln ? 1 : 0);
    debugPrint('🎛️ Enhancement mode set to: $mode');
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    _updateNativeDsp();
  }

  void setLeftGain(double level) {
    _leftGain = level.clamp(0.0, 10.0);
    _updateNativeDsp();
  }

  void setRightGain(double level) {
    _rightGain = level.clamp(0.0, 10.0);
    _updateNativeDsp();
  }

  void setTone(double val) {
    _tone = val.clamp(0.0, 1.0);
    _updateNativeDsp();
  }

  void setMasterVolume(double level) {
    _masterVolume = level.clamp(0.0, 10.0);
    _updateNativeDsp();
  }

  void setSuppression(double level) {
    _suppressionLevel = level.clamp(0.0, 1.0);
    _updateNativeDsp();
  }

  Future<void> _updateNativeDsp() async {
    if (_isEnabled) {
      NativeAudioApi.setGains(_leftGain * _masterVolume, _rightGain * _masterVolume);
      NativeAudioApi.setSuppression(_suppressionLevel);
      NativeAudioApi.setTone(_tone);
      NativeAudioApi.setProcessingMode(_mode == EnhancementMode.dtln ? 1 : (_mode == EnhancementMode.rnn ? 0 : -1));
    } else {
      NativeAudioApi.setGains(1.0, 1.0);
      NativeAudioApi.setSuppression(0.0);
      NativeAudioApi.setTone(0.5);
      NativeAudioApi.setProcessingMode(-1);
    }
  }

  void dispose() {
    _isEnabled = false;
  }
}
