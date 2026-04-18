import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'HearingProfileService.dart';
import 'audio_model_service.dart';

enum EnhancementMode {
  standard, // Biquad EQ + Noise Reduction
  dtln,     // AI Noise Suppression
  rnn,      // AI Voice Isolation
  krisp,    // AI + Spectral Post-Processing (High Quality)
}

/// Lightweight audio enhancement using IIR biquad filters.
///
/// Uses peak EQ filters centered at hearing test frequencies, each
/// boosting its target band based on the user's hearing profile.
/// Processes samples instantly with zero buffering latency.
class AudioEnhancementService {
  static final AudioEnhancementService _instance =
      AudioEnhancementService._internal();
  factory AudioEnhancementService() => _instance;
  AudioEnhancementService._internal();

  static const _channel = MethodChannel('com.fyp_flutter/audio_route');
  final AudioModelService _modelService = AudioModelService();

  /// audio_io delivers 48kHz mono audio — all filters must use this rate.
  static const int sampleRate = 48000;

  /// AI models (DTLN/RNN) expect 16kHz input; ratio = 48000 / 16000 = 3
  static const int _resampleRatio = 3;

  /// AI model block size (most DTLN/RNN models use 512 samples at 16kHz)
  static const int _modelBlockSize = 512;

  /// Maximum boost in dB (12 dB ≈ 4x amplitude)
  static const double maxBoostDb = 12.0;

  // ── Noise Gate (smooth) ──
  double _gateThreshold = 0.008;
  final double _gateAttack = 0.001;   // Fast attack (let signal through quickly)
  final double _gateRelease = 0.05;   // Slow release (don't chop tails)
  double _envelope = 0.0;

  // ── Noise Reduction for Standard mode ──
  double _noiseEstimate = 0.005;
  final double _noiseTrackAlpha = 0.995;   // Slow noise floor tracking
  double _nrSmoothGain = 1.0;       // Smoothed NR gain

  // ── Spectral Suppression Params (Krisp-level) ──
  double _noiseFloor = 0.005;
  final double _spectralAlpha = 0.98;   // Noise floor estimation speed
  double _gainSmooth = 0.9;      // Smoothing of the suppression gain
  double _prevSpectralGain = 1.0; // Previous gain for smoothing (FIX: was missing)

  EnhancementMode _mode = EnhancementMode.standard;
  EnhancementMode get mode => _mode;

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  bool _profileLoaded = false;
  bool get profileLoaded => _profileLoaded;

  /// Biquad filter states for each frequency band (Independent for each ear)
  final List<_BiquadFilter> _leftFilters = [];
  final List<_BiquadFilter> _rightFilters = [];

  /// Overall output gain (prevents clipping)
  double _outputGain = 0.8;
  
  /// Noise suppression strength (0.0 to 1.0)
  double _suppressionLevel = 0.5;

  /// Independent Ear Gains
  double _leftGain = 1.0;
  double _rightGain = 1.0;

  /// Fine-tuning (Tone) - 0.0 is High/Clarity, 1.0 is Low/Fullness (Google style)
  double _tone = 0.5;

  // Filters for tone
  _BiquadFilter? _lowShelf;
  _BiquadFilter? _highShelf;

  final List<int> _testFrequencies = [
    125, 250, 375, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 7000, 8000
  ];

  // ── AI Model Buffer Accumulator ──
  // Collects incoming samples until we have enough for one model block
  final List<double> _aiInputBuffer = [];
  final List<double> _aiOutputBuffer = [];

  /// Initialize with the user's hearing profile.
  Future<bool> initialize() async {
    _leftFilters.clear();
    _rightFilters.clear();
    _aiInputBuffer.clear();
    _aiOutputBuffer.clear();

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

    // Initialize Native DynamicsProcessing
    try {
      await _channel.invokeMethod('initDynamicsProcessing', {'sessionId': 0});
      await _updateNativeDsp();
    } catch (e) {
      debugPrint('⚠️ Native DynamicsProcessing init failed: $e');
    }

    debugPrint('✅ AudioEnhancementService initialized (48kHz, Biquad + Native DynamicsProcessing)');
    return true;
  }

  void _loadProfile(Map<String, dynamic> profile) {
    final freqMap = profile['frequencyMap'] as Map<String, dynamic>?;
    if (freqMap == null) return;

    _leftFilters.clear();
    _rightFilters.clear();

    for (final freq in _testFrequencies) {
      final leftKey = 'L_$freq';
      final rightKey = 'R_$freq';
      final leftVal = (freqMap[leftKey] as num?)?.toDouble() ?? 1.0;
      final rightVal = (freqMap[rightKey] as num?)?.toDouble() ?? 1.0;

      // Left Ear Filters
      final leftBoostDb = (1.0 - leftVal.clamp(0.0, 1.0)) * maxBoostDb;
      if (leftBoostDb > 0.5) {
        _leftFilters.add(_BiquadFilter.peakEQ(
          sampleRate: sampleRate.toDouble(),
          frequency: freq.toDouble(),
          gainDb: leftBoostDb,
          q: 1.2,
        ));
      }

      // Right Ear Filters
      final rightBoostDb = (1.0 - rightVal.clamp(0.0, 1.0)) * maxBoostDb;
      if (rightBoostDb > 0.5) {
        _rightFilters.add(_BiquadFilter.peakEQ(
          sampleRate: sampleRate.toDouble(),
          frequency: freq.toDouble(),
          gainDb: rightBoostDb,
          q: 1.2,
        ));
      }
    }

    debugPrint('📊 Created ${_leftFilters.length}L / ${_rightFilters.length}R filters @ ${sampleRate}Hz');
  }

  void setMode(EnhancementMode mode) {
    _mode = mode;
    _leftFilters.clear();
    _rightFilters.clear();
    _aiInputBuffer.clear();
    _aiOutputBuffer.clear();
    debugPrint('🎛️ Enhancement mode set to: $mode');
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    debugPrint(enabled ? '🔊 Enhancement ENABLED' : '🔇 Enhancement DISABLED');
  }

  void setBoost(double level) {
    _leftGain = level.clamp(0.1, 2.0);
    _rightGain = level.clamp(0.1, 2.0);
  }

  void setLeftGain(double level) {
    _leftGain = level.clamp(0.0, 2.0);
    _updateNativeDsp();
  }

  void setRightGain(double level) {
    _rightGain = level.clamp(0.0, 2.0);
    _updateNativeDsp();
  }

  void setTone(double val) {
    _tone = val.clamp(0.0, 1.0);
    // Tone 0.0: High boost (Clarity)
    // Tone 1.0: Low boost (Fullness)
    _highShelf = _BiquadFilter.highShelf(
      sampleRate: sampleRate.toDouble(),
      frequency: 4000,
      gainDb: (1.0 - _tone) * 12.0, // Up to 12dB boost at 4kHz+
    );
    _lowShelf = _BiquadFilter.lowShelf(
      sampleRate: sampleRate.toDouble(),
      frequency: 300,
      gainDb: _tone * 12.0, // Up to 12dB boost below 300Hz
    );
    _updateNativeDsp();
  }

  void setSuppression(double level) {
    _suppressionLevel = level.clamp(0.0, 1.0);
    // Adjust spectral suppression params based on this level
    _gainSmooth = 0.7 + (0.2 * _suppressionLevel);
    // Adjust noise gate threshold based on suppression
    _gateThreshold = 0.003 + (0.015 * _suppressionLevel);
    _updateNativeDsp();
  }

  Future<void> _updateNativeDsp() async {
    try {
      await _channel.invokeMethod('updateDynamicsProcessing', {
        'leftGain': _leftGain,
        'rightGain': _rightGain,
        'tone': _tone,
        'suppression': _suppressionLevel,
      });
    } catch (_) {}
  }

  Float64List processAudio(List<double> input, {bool isLeft = true}) {
    if (!_isEnabled) return input is Float64List ? input : Float64List.fromList(input);

    switch (_mode) {
      case EnhancementMode.dtln:
        return _processAiMode(input, _modelService.processDtln, isLeft: isLeft);
      case EnhancementMode.rnn:
        return _processAiMode(input, _modelService.processRnn, isLeft: isLeft);
      case EnhancementMode.krisp:
        final aiOut = _processAiMode(input, _modelService.processDtln, isLeft: isLeft);
        return _processSpectralSubtraction(aiOut);
      case EnhancementMode.standard:
        return _processBiquad(input, isLeft: isLeft);
    }
  }

  Float64List _processBiquad(List<double> input, {required bool isLeft}) {
    final output = Float64List(input.length);

    // Copy input to output
    if (input is Float64List) {
      output.setAll(0, input);
    } else {
      for (int i = 0; i < input.length; i++) {
        output[i] = input[i];
      }
    }

    // Apply biquad EQ filters (hearing profile boost) if available
    final earFilters = isLeft ? _leftFilters : _rightFilters;
    if (_profileLoaded && earFilters.isNotEmpty) {
      for (final filter in earFilters) {
        for (int i = 0; i < output.length; i++) {
          output[i] = filter.process(output[i]);
        }
      }
    }

    // Apply tone filters
    if (_highShelf != null) {
      for (int i = 0; i < output.length; i++) {
        output[i] = _highShelf!.process(output[i]);
      }
    }
    if (_lowShelf != null) {
      for (int i = 0; i < output.length; i++) {
        output[i] = _lowShelf!.process(output[i]);
      }
    }

    // ── Noise Reduction (time-domain) ──
    // This actually reduces noise using the suppression slider
    for (int i = 0; i < output.length; i++) {
      final absSample = output[i].abs();

      // Track noise floor (slow update during quiet parts)
      if (absSample < _noiseEstimate * 3.0) {
        _noiseEstimate = _noiseTrackAlpha * _noiseEstimate +
            (1.0 - _noiseTrackAlpha) * absSample;
      }

      // Calculate instantaneous SNR
      final snr = absSample / (_noiseEstimate + 1e-8);

      // Compute noise reduction gain based on SNR and suppression level
      // Higher suppression = more aggressive gating of noise
      final nrThreshold = 1.5 + (4.0 * _suppressionLevel);
      double targetGain;
      if (snr > nrThreshold) {
        targetGain = 1.0; // Signal is well above noise — pass through
      } else {
        // Soft transition: smoothly reduce gain as SNR drops
        targetGain = (snr / nrThreshold).clamp(0.05, 1.0);
        // Apply suppression strength
        targetGain = 1.0 - _suppressionLevel * (1.0 - targetGain);
      }

      // Smooth the gain to avoid artifacts (attack/release)
      final smoothRate = targetGain > _nrSmoothGain ? 0.1 : 0.02;
      _nrSmoothGain = _nrSmoothGain + smoothRate * (targetGain - _nrSmoothGain);

      output[i] *= _nrSmoothGain;
    }

    // ── Smooth Noise Gate (prevents low-level hiss) ──
    for (int i = 0; i < output.length; i++) {
      final absSample = output[i].abs();

      // Envelope follower with separate attack/release
      if (absSample > _envelope) {
        _envelope += _gateAttack * (absSample - _envelope);
      } else {
        _envelope += _gateRelease * (absSample - _envelope);
      }

      // Smooth gain ramp (no hard on/off that causes pulsing)
      final gateGain = (_envelope / (_gateThreshold + 1e-8)).clamp(0.0, 1.0);
      output[i] *= gateGain;

      // Apply independent output gain + soft clip
      final gain = isLeft ? _leftGain : _rightGain;
      output[i] = _softClip(output[i] * gain);
    }

    return output;
  }

  /// Process through AI model with proper resampling and block buffering.
  ///
  /// audio_io gives 48kHz chunks of variable size.
  /// AI models need 16kHz blocks of exactly [_modelBlockSize] samples.
  /// We downsample 3x, buffer until we have 512 samples, run the model,
  /// then upsample 3x back to 48kHz.
  Float64List _processAiMode(List<double> input, Float32List Function(Float32List) modelFn, {required bool isLeft}) {
    // 1. Downsample 48kHz → 16kHz
    final downsampled = _downsample3x(input);

    // 2. Add to accumulator
    _aiInputBuffer.addAll(downsampled);

    // 3. Process complete blocks
    while (_aiInputBuffer.length >= _modelBlockSize) {
      final block = Float32List(_modelBlockSize);
      for (int i = 0; i < _modelBlockSize; i++) {
        block[i] = _aiInputBuffer[i].toDouble();
      }
      _aiInputBuffer.removeRange(0, _modelBlockSize);

      // Run through AI model with error handling
      Float32List processed;
      try {
        processed = modelFn(block);
      } catch (e) {
        debugPrint('⚠️ AI model error: $e — passing through');
        processed = block; // Graceful fallback
      }

      // Collect output at 16kHz
      for (int i = 0; i < processed.length; i++) {
        _aiOutputBuffer.add(processed[i].toDouble());
      }
    }

    // 4. Upsample back to 48kHz (take only what we need for this chunk)
    final neededAt16k = input.length ~/ _resampleRatio;
    if (_aiOutputBuffer.length < neededAt16k) {
      // Not enough processed data yet — return silence to avoid glitch
      // This only happens for the first chunk while buffer fills
      return Float64List(input.length);
    }

    final toUpsample = _aiOutputBuffer.sublist(0, neededAt16k);
    _aiOutputBuffer.removeRange(0, neededAt16k);

    final upsampled = _upsample3x(toUpsample);

    // 5. Apply independent output gain + soft clip
    final output = Float64List(input.length);
    final gain = isLeft ? _leftGain : _rightGain;
    for (int i = 0; i < input.length && i < upsampled.length; i++) {
      output[i] = _softClip(upsampled[i] * gain);
    }
    return output;
  }

  /// Downsample by 3x (48kHz → 16kHz) using simple averaging
  List<double> _downsample3x(List<double> input) {
    final outLen = input.length ~/ _resampleRatio;
    final result = List<double>.filled(outLen, 0.0);
    for (int i = 0; i < outLen; i++) {
      final idx = i * _resampleRatio;
      double sum = 0.0;
      int count = 0;
      for (int j = 0; j < _resampleRatio && idx + j < input.length; j++) {
        sum += input[idx + j];
        count++;
      }
      result[i] = sum / count;
    }
    return result;
  }

  /// Upsample by 3x (16kHz → 48kHz) using linear interpolation
  List<double> _upsample3x(List<double> input) {
    final outLen = input.length * _resampleRatio;
    final result = List<double>.filled(outLen, 0.0);
    for (int i = 0; i < input.length; i++) {
      final nextVal = (i + 1 < input.length) ? input[i + 1] : input[i];
      for (int j = 0; j < _resampleRatio; j++) {
        final t = j / _resampleRatio;
        result[i * _resampleRatio + j] = input[i] * (1.0 - t) + nextVal * t;
      }
    }
    return result;
  }

  /// Soft clipping using tanh — prevents harsh digital distortion
  double _softClip(double x) {
    if (x.abs() < 0.8) return x;
    final sign = x.sign;
    final val = x.abs();
    return sign * (0.8 + 0.2 * _tanh((val - 0.8) / 0.2));
  }

  double _tanh(double x) {
    if (x > 20) return 1.0;
    if (x < -20) return -1.0;
    final exp2x = exp(2 * x);
    return (exp2x - 1) / (exp2x + 1);
  }

  /// Advanced Spectral Post-Processor (Wiener-inspired).
  /// Further cleans up AI artifacts for a "Krisp" finish.
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
        final alpha = 0.5 + (2.5 * _suppressionLevel); 
        double gain = (snr * snr) / (snr * snr + alpha);
        
        // 4. Smooth the gain changes (FIX: was a no-op before!)
        gain = _gainSmooth * _prevSpectralGain + (1.0 - _gainSmooth) * gain;
        _prevSpectralGain = gain;

        // 5. Apply gain with a floor
        final finalGain = gain.clamp(0.02 + (0.1 * (1.0 - _suppressionLevel)), 1.0);
        output[i] = input[i] * finalGain;
    }
    
    return output;
  }

  void reset() {
    _envelope = 0.0;
    _noiseEstimate = 0.005;
    _nrSmoothGain = 1.0;
    _noiseFloor = 0.005;
    _prevSpectralGain = 1.0;
    _aiInputBuffer.clear();
    _aiOutputBuffer.clear();
    for (final f in _leftFilters) f.reset();
    for (final f in _rightFilters) f.reset();
  }

  void dispose() {
    _isEnabled = false;
    _leftFilters.clear();
    _rightFilters.clear();
    _aiInputBuffer.clear();
    _aiOutputBuffer.clear();
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

  _BiquadFilter.lowShelf({
    required double sampleRate,
    required double frequency,
    required double gainDb,
  }) : this.frequency = frequency, this.gainDb = gainDb {
    final A = pow(10.0, gainDb / 40.0).toDouble();
    final w0 = 2.0 * pi * frequency / sampleRate;
    final cosW0 = cos(w0);
    final sinW0 = sin(w0);
    final alpha = sinW0 / 2.0 * sqrt((A + 1.0 / A) * (1.0 / 1.0 - 1.0) + 2.0); // Q = 1.0 simplified

    final a0 = (A + 1.0) + (A - 1.0) * cosW0 + 2.0 * sqrt(A) * alpha;
    _b0 = (A * ((A + 1.0) - (A - 1.0) * cosW0 + 2.0 * sqrt(A) * alpha)) / a0;
    _b1 = (2.0 * A * ((A - 1.0) - (A + 1.0) * cosW0)) / a0;
    _b2 = (A * ((A + 1.0) - (A - 1.0) * cosW0 - 2.0 * sqrt(A) * alpha)) / a0;
    _a1 = (-2.0 * ((A - 1.0) + (A + 1.0) * cosW0)) / a0;
    _a2 = ((A + 1.0) + (A - 1.0) * cosW0 - 2.0 * sqrt(A) * alpha) / a0;
  }

  _BiquadFilter.highShelf({
    required double sampleRate,
    required double frequency,
    required double gainDb,
  }) : this.frequency = frequency, this.gainDb = gainDb {
    final A = pow(10.0, gainDb / 40.0).toDouble();
    final w0 = 2.0 * pi * frequency / sampleRate;
    final cosW0 = cos(w0);
    final sinW0 = sin(w0);
    final alpha = sinW0 / 2.0 * sqrt((A + 1.0 / A) * (1.0 / 1.0 - 1.0) + 2.0);

    final a0 = (A + 1.0) - (A - 1.0) * cosW0 + 2.0 * sqrt(A) * alpha;
    _b0 = (A * ((A + 1.0) + (A - 1.0) * cosW0 + 2.0 * sqrt(A) * alpha)) / a0;
    _b1 = (-2.0 * A * ((A - 1.0) + (A + 1.0) * cosW0)) / a0;
    _b2 = (A * ((A + 1.0) + (A - 1.0) * cosW0 - 2.0 * sqrt(A) * alpha)) / a0;
    _a1 = (2.0 * ((A - 1.0) - (A + 1.0) * cosW0)) / a0;
    _a2 = ((A + 1.0) - (A - 1.0) * cosW0 - 2.0 * sqrt(A) * alpha) / a0;
  }

  void reset() {
    _x1 = _x2 = _y1 = _y2 = 0;
  }
}
