import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'HearingProfileService.dart';

/// Applies frequency-specific equalization based on the user's hearing profile.
///
/// Uses FFT to split audio into frequency bands, apply per-band gain
/// based on hearing test thresholds, then IFFT to reconstruct.
class AudioEnhancementService {
  static final AudioEnhancementService _instance =
      AudioEnhancementService._internal();
  factory AudioEnhancementService() => _instance;
  AudioEnhancementService._internal();

  /// Sample rate of audio_io (fixed at 48kHz)
  static const int sampleRate = 48000;

  /// FFT frame size — must be power of 2
  static const int frameSize = 1024;

  /// Half the frame (number of unique frequency bins)
  static const int halfFrame = frameSize ~/ 2;

  /// Maximum boost factor (e.g., 4.0 = up to 4x amplification)
  static const double maxBoost = 4.0;

  /// Whether enhancement is active
  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  /// Whether a hearing profile is loaded
  bool _profileLoaded = false;
  bool get profileLoaded => _profileLoaded;

  /// Gain multipliers per FFT bin (length = halfFrame)
  late Float64List _gainCurve;

  /// Overlap-add buffer for smooth output
  final Float64List _overlapBuffer = Float64List(frameSize);

  /// Previous leftover samples that didn't fill a full frame
  List<double> _leftover = [];

  /// Hearing profile frequencies (Hz) and their threshold values
  final List<int> _testFrequencies = [
    125, 250, 375, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 7000, 8000
  ];

  /// Initialize with the user's hearing profile.
  /// Call this before starting live assist.
  Future<bool> initialize() async {
    _gainCurve = Float64List(halfFrame);
    for (int i = 0; i < halfFrame; i++) {
      _gainCurve[i] = 1.0; // default: no boost
    }

    final profile = await HearingProfileService().getLocalProfile();
    if (profile == null) {
      debugPrint('⚠️ No hearing profile found — enhancement will be flat');
      _profileLoaded = false;
      return false;
    }

    _loadProfile(profile);
    _profileLoaded = true;
    debugPrint('✅ AudioEnhancementService initialized with hearing profile');
    return true;
  }

  /// Build the gain curve from the hearing profile's frequency map.
  void _loadProfile(Map<String, dynamic> profile) {
    final freqMap = profile['frequencyMap'] as Map<String, dynamic>?;
    if (freqMap == null) return;

    // Average left and right thresholds per frequency
    final Map<int, double> avgThresholds = {};
    for (final freq in _testFrequencies) {
      final leftKey = 'L_$freq';
      final rightKey = 'R_$freq';
      final leftVal = (freqMap[leftKey] as num?)?.toDouble() ?? 1.0;
      final rightVal = (freqMap[rightKey] as num?)?.toDouble() ?? 1.0;
      avgThresholds[freq] = (leftVal + rightVal) / 2.0;
    }

    // Build gain curve: interpolate between test frequencies
    for (int bin = 0; bin < halfFrame; bin++) {
      final freq = bin * sampleRate / frameSize; // frequency of this bin

      // Find the two nearest test frequencies
      double gain = 1.0;
      if (freq <= _testFrequencies.first) {
        gain = _thresholdToGain(avgThresholds[_testFrequencies.first]!);
      } else if (freq >= _testFrequencies.last) {
        gain = _thresholdToGain(avgThresholds[_testFrequencies.last]!);
      } else {
        // Linear interpolation between neighboring test frequencies
        for (int i = 0; i < _testFrequencies.length - 1; i++) {
          if (freq >= _testFrequencies[i] && freq <= _testFrequencies[i + 1]) {
            final f1 = _testFrequencies[i].toDouble();
            final f2 = _testFrequencies[i + 1].toDouble();
            final g1 = _thresholdToGain(avgThresholds[_testFrequencies[i]]!);
            final g2 = _thresholdToGain(avgThresholds[_testFrequencies[i + 1]]!);
            final t = (freq - f1) / (f2 - f1);
            gain = g1 + t * (g2 - g1);
            break;
          }
        }
      }

      _gainCurve[bin] = gain;
    }

    debugPrint('📊 Gain curve built: min=${_gainCurve.reduce(min).toStringAsFixed(2)}, '
        'max=${_gainCurve.reduce(max).toStringAsFixed(2)}');
  }

  /// Convert a hearing threshold (0.0–1.0) to a gain multiplier.
  /// Lower threshold = user hears poorly = needs more boost.
  double _thresholdToGain(double threshold) {
    // threshold: 1.0 = perfect hearing, 0.0 = can't hear
    // gain:     1.0 = no boost,        maxBoost = maximum amplification
    return 1.0 + (1.0 - threshold.clamp(0.0, 1.0)) * (maxBoost - 1.0);
  }

  /// Enable/disable enhancement
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    debugPrint(enabled ? '🔊 Enhancement ENABLED' : '🔇 Enhancement DISABLED');
  }

  /// Process a chunk of audio samples (List<double> from audio_io).
  /// Returns enhanced audio ready for output.
  List<double> processAudio(List<double> input) {
    if (!_isEnabled || !_profileLoaded) return input;

    // Accumulate samples
    _leftover.addAll(input);

    final List<double> output = [];

    // Process full frames
    while (_leftover.length >= frameSize) {
      final frame = Float64List.fromList(_leftover.sublist(0, frameSize));
      _leftover = _leftover.sublist(frameSize ~/ 2); // 50% overlap

      // Apply Hann window
      _applyWindow(frame);

      // FFT
      final fftResult = _fft(frame);

      // Apply gain curve in frequency domain
      for (int i = 0; i < halfFrame; i++) {
        fftResult[i * 2] *= _gainCurve[i];       // real part
        fftResult[i * 2 + 1] *= _gainCurve[i];   // imaginary part
      }
      // Mirror for negative frequencies
      for (int i = 1; i < halfFrame; i++) {
        fftResult[(frameSize - i) * 2] = fftResult[i * 2];
        fftResult[(frameSize - i) * 2 + 1] = -fftResult[i * 2 + 1];
      }

      // IFFT
      final enhanced = _ifft(fftResult);

      // Overlap-add
      for (int i = 0; i < frameSize; i++) {
        if (i < halfFrame) {
          enhanced[i] += _overlapBuffer[i + halfFrame];
        }
      }

      // Save overlap for next frame
      for (int i = 0; i < frameSize; i++) {
        _overlapBuffer[i] = enhanced[i];
      }

      // Output the first half (non-overlapping part)
      for (int i = 0; i < halfFrame; i++) {
        output.add(enhanced[i].clamp(-1.0, 1.0));
      }
    }

    return output.isEmpty ? input : output;
  }

  /// Apply Hann window to a frame
  void _applyWindow(Float64List frame) {
    for (int i = 0; i < frame.length; i++) {
      frame[i] *= 0.5 * (1.0 - cos(2.0 * pi * i / (frame.length - 1)));
    }
  }

  /// Simple in-place FFT (Cooley-Tukey, radix-2)
  Float64List _fft(Float64List real) {
    final n = real.length;
    final data = Float64List(n * 2); // interleaved [re, im, re, im, ...]
    for (int i = 0; i < n; i++) {
      data[i * 2] = real[i];
      data[i * 2 + 1] = 0.0;
    }
    _fftInPlace(data, false);
    return data;
  }

  /// Simple IFFT
  Float64List _ifft(Float64List data) {
    _fftInPlace(data, true);
    final n = data.length ~/ 2;
    final result = Float64List(n);
    for (int i = 0; i < n; i++) {
      result[i] = data[i * 2] / n;
    }
    return result;
  }

  /// Cooley-Tukey radix-2 FFT in-place on interleaved complex data
  void _fftInPlace(Float64List data, bool inverse) {
    final n = data.length ~/ 2;
    if (n <= 1) return;

    // Bit-reversal permutation
    int j = 0;
    for (int i = 0; i < n; i++) {
      if (i < j) {
        // Swap real parts
        final tmpR = data[i * 2];
        final tmpI = data[i * 2 + 1];
        data[i * 2] = data[j * 2];
        data[i * 2 + 1] = data[j * 2 + 1];
        data[j * 2] = tmpR;
        data[j * 2 + 1] = tmpI;
      }
      int m = n >> 1;
      while (m >= 1 && j >= m) {
        j -= m;
        m >>= 1;
      }
      j += m;
    }

    // FFT butterfly
    for (int size = 2; size <= n; size *= 2) {
      final halfSize = size ~/ 2;
      final angle = (inverse ? 2.0 : -2.0) * pi / size;

      for (int i = 0; i < n; i += size) {
        for (int k = 0; k < halfSize; k++) {
          final wR = cos(angle * k);
          final wI = sin(angle * k);

          final evenIdx = (i + k) * 2;
          final oddIdx = (i + k + halfSize) * 2;

          final tR = wR * data[oddIdx] - wI * data[oddIdx + 1];
          final tI = wR * data[oddIdx + 1] + wI * data[oddIdx];

          data[oddIdx] = data[evenIdx] - tR;
          data[oddIdx + 1] = data[evenIdx + 1] - tI;
          data[evenIdx] += tR;
          data[evenIdx + 1] += tI;
        }
      }
    }
  }

  /// Reset internal buffers
  void reset() {
    _leftover.clear();
    _overlapBuffer.fillRange(0, _overlapBuffer.length, 0.0);
  }

  void dispose() {
    _isEnabled = false;
    _leftover.clear();
  }
}
