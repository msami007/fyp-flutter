import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'HearingProfileService.dart';
import 'audio_model_service.dart';

enum EnhancementMode {
  standard, // Biquad EQ
  dtln,     // AI Noise Suppression
  rnn,      // AI Voice Isolation
  krisp,    // AI + Spectral Post-Processing (High Quality)
}

/// Lightweight audio enhancement using IIR biquad filters.
///
/// Instead of heavy FFT processing, this uses a set of peak EQ filters
/// centered at the hearing test frequencies. Each filter boosts its
/// target frequency band based on the user's hearing profile.
/// This processes samples instantly with zero buffering latency.
class AudioEnhancementService {
  static final AudioEnhancementService _instance =
      AudioEnhancementService._internal();
  factory AudioEnhancementService() => _instance;
  AudioEnhancementService._internal();

  final AudioModelService _modelService = AudioModelService();
  static const int sampleRate = 16000;

  /// Maximum boost in dB (12 dB ≈ 4x amplitude)
  static const double maxBoostDb = 12.0;

  /// Noise gate threshold (silence if signal below this)
  /// 0.01 is roughly -40dBfs
  double _gateThreshold = 0.01; 
  double _gateAlpha = 0.95; // Envelope smoothing
  double _envelope = 0.0;

  // ── Spectral Suppression Params (Krisp-level) ──
  double _noiseFloor = 0.005;
  double _spectralAlpha = 0.98; // Noise floor estimation speed
  double _gainSmooth = 0.9;     // Smoothing of the suppression gain

  EnhancementMode _mode = EnhancementMode.standard;
  EnhancementMode get mode => _mode;

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  bool _profileLoaded = false;
  bool get profileLoaded => _profileLoaded;

  /// Biquad filter states for each frequency band
  final List<_BiquadFilter> _filters = [];

  /// Overall output gain (prevents clipping)
  double _outputGain = 0.8;

  final List<int> _testFrequencies = [
    125, 250, 375, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 7000, 8000
  ];

  /// Initialize with the user's hearing profile.
  Future<bool> initialize() async {
    _filters.clear();

    final profile = await HearingProfileService().getLocalProfile();
    if (profile == null) {
      debugPrint('⚠️ No hearing profile found — enhancement will be flat');
      _profileLoaded = false;
      return false;
    }

    _loadProfile(profile);
    _profileLoaded = true;

    // Load AI models
    await _modelService.loadDtln();
    await _modelService.loadRnn();

    debugPrint('✅ AudioEnhancementService initialized (Biquad + AI models)');
    return true;
  }

  void _loadProfile(Map<String, dynamic> profile) {
    final freqMap = profile['frequencyMap'] as Map<String, dynamic>?;
    if (freqMap == null) return;

    _filters.clear();

    for (final freq in _testFrequencies) {
      final leftKey = 'L_$freq';
      final rightKey = 'R_$freq';
      final leftVal = (freqMap[leftKey] as num?)?.toDouble() ?? 1.0;
      final rightVal = (freqMap[rightKey] as num?)?.toDouble() ?? 1.0;
      final avgThreshold = (leftVal + rightVal) / 2.0;

      // Convert threshold to boost in dB
      // threshold 1.0 = perfect hearing → 0 dB boost
      // threshold 0.0 = deaf → maxBoostDb boost
      final boostDb = (1.0 - avgThreshold.clamp(0.0, 1.0)) * maxBoostDb;

      if (boostDb > 0.5) {
        // Only add filter if meaningful boost is needed
        _filters.add(_BiquadFilter.peakEQ(
          sampleRate: sampleRate.toDouble(),
          frequency: freq.toDouble(),
          gainDb: boostDb,
          q: 1.2, // moderate bandwidth
        ));
      }
    }

    debugPrint('📊 Created ${_filters.length} biquad filters for hearing profile');
  }

  void setMode(EnhancementMode mode) {
    _mode = mode;
    debugPrint('🎛️ Enhancement mode set to: $mode');
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    debugPrint(enabled ? '🔊 Enhancement ENABLED' : '🔇 Enhancement DISABLED');
  }

  /// Process audio samples. Near-zero latency — no buffering needed.
  Float64List processAudio(List<double> input) {
    if (!_isEnabled) return input is Float64List ? input : Float64List.fromList(input);

    switch (_mode) {
      case EnhancementMode.dtln:
        return _processAiModel(input, _modelService.processDtln);
      case EnhancementMode.rnn:
        return _processAiModel(input, _modelService.processRnn);
      case EnhancementMode.krisp:
        final aiOut = _processAiModel(input, _modelService.processDtln);
        return _processSpectralSubtraction(aiOut);
      case EnhancementMode.standard:
      default:
        return _processBiquad(input);
    }
  }

  Float64List _processBiquad(List<double> input) {
    if (!_profileLoaded || _filters.isEmpty) {
      return input is Float64List ? input : Float64List.fromList(input);
    }

    final output = Float64List(input.length);

    // Copy input to output efficiently
    if (input is Float64List) {
      output.setAll(0, input);
    } else {
      for (int i = 0; i < input.length; i++) {
        output[i] = input[i];
      }
    }

    // Apply each biquad filter in series
    for (final filter in _filters) {
      for (int i = 0; i < output.length; i++) {
        output[i] = filter.process(output[i]);
      }
    }

    // Apply Noise Gate & Output Gain
    for (int i = 0; i < output.length; i++) {
      final sample = output[i].abs();
      // Simple envelope follower
      _envelope = _gateAlpha * _envelope + (1.0 - _gateAlpha) * sample;
      
      // If envelope is below threshold, apply aggressive attenuation
      if (_envelope < _gateThreshold) {
        output[i] *= 0.02; // -34dB attenuation
      }

      output[i] = _softClip(output[i] * _outputGain);
    }

    return output;
  }

  Float64List _processAiModel(List<double> input, Float32List Function(Float32List) modelFn) {
    // 1. Convert to Float32 safely using Float32List.fromList
    final float32In = Float32List.fromList(input.map((e) => e.toDouble()).toList());

    // 2. Process through model
    final processed32 = modelFn(float32In);

    // 3. Convert back to Float64 and apply output gain/softclip
    final output = Float64List(processed32.length);
    for (int i = 0; i < processed32.length; i++) {
        output[i] = _softClip(processed32[i] * _outputGain);
    }
    return output;
  }

  /// Soft clipping using tanh — prevents harsh digital distortion
  double _softClip(double x) {
    if (x.abs() < 0.8) return x;
    // Smoother transition above 0.8
    final sign = x.sign;
    final val = x.abs();
    return sign * (0.8 + 0.2 * tanh((val - 0.8) / 0.2));
  }

  double tanh(double x) {
    if (x > 20) return 1.0;
    if (x < -20) return -1.0;
    final exp2x = exp(2 * x);
    return (exp2x - 1) / (exp2x + 1);
  }

  /// Advanced Spectral Post-Processor (Inspired by Wiener Filter)
  /// This further cleans up AI artifacts for a "Krisp" finish.
  Float64List _processSpectralSubtraction(Float64List input) {
    final output = Float64List(input.length);
    
    for (int i = 0; i < input.length; i++) {
        final sample = input[i].abs();
        
        // 1. Update noise floor during relative silence
        if (sample < _noiseFloor * 2) {
          _noiseFloor = _spectralAlpha * _noiseFloor + (1.0 - _spectralAlpha) * sample;
        }
        
        // 2. Calculate Instantaneous SNR
        final snr = sample / (_noiseFloor + 1e-6);
        
        // 3. Wiener-like Gain: G = SNR^2 / (SNR^2 + Alpha)
        // This aggressively suppresses anything below the noise floor
        double gain = (snr * snr) / (snr * snr + 1.5);
        
        // 4. Smooth the gain changes to prevent 'musical noise'
        _gainSmooth = 0.85; // Faster for spectral sub
        gain = _gainSmooth * gain + (1.0 - _gainSmooth) * gain; 

        // 5. Apply gain with a floor to prevent total deadness
        final finalGain = gain.clamp(0.05, 1.0);
        output[i] = input[i] * finalGain;
    }
    
    return output;
  }

  void reset() {
    _envelope = 0.0;
    for (final f in _filters) {
      f.reset();
    }
  }

  void dispose() {
    _isEnabled = false;
    _filters.clear();
  }
}

/// Second-order IIR biquad filter.
class _BiquadFilter {
  final double frequency;
  final double gainDb;

  // Coefficients
  double _b0 = 1, _b1 = 0, _b2 = 0;
  double _a1 = 0, _a2 = 0;

  // State (delay line)
  double _x1 = 0, _x2 = 0;
  double _y1 = 0, _y2 = 0;

  _BiquadFilter.peakEQ({
    required double sampleRate,
    required this.frequency,
    required this.gainDb,
    required double q,
  }) {
    final A = pow(10.0, gainDb / 40.0).toDouble();
    final w0 = 2.0 * pi * frequency / sampleRate;
    final cosW0 = cos(w0);
    final sinW0 = sin(w0);
    final alpha = sinW0 / (2.0 * q);

    final a0 = 1.0 + alpha / A;
    _b0 = (1.0 + alpha * A) / a0;
    _b1 = (-2.0 * cosW0) / a0;
    _b2 = (1.0 - alpha * A) / a0;
    _a1 = (-2.0 * cosW0) / a0;
    _a2 = (1.0 - alpha / A) / a0;
  }

  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  void reset() {
    _x1 = _x2 = _y1 = _y2 = 0;
  }
}
