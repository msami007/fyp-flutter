import 'package:flutter/foundation.dart';

/// Audio enhancement service using Android/iOS built-in noise suppression.
///
/// Uses the device's hardware-accelerated NoiseSuppressor and
/// AutomaticGainControl via the record package's RecordConfig parameters.
/// No TFLite models needed — works on all modern Android devices.
class NoiseSuppressionService {
  static final NoiseSuppressionService _instance = NoiseSuppressionService._internal();
  factory NoiseSuppressionService() => _instance;
  NoiseSuppressionService._internal();

  bool _isEnabled = false;
  bool _isInitialized = true; // Always ready — uses built-in hardware

  /// Initialize the service
  Future<bool> initialize() async {
    _isInitialized = true;
    debugPrint('✅ Noise suppression ready (built-in Android NoiseSuppressor)');
    return true;
  }

  /// Enable/disable noise suppression
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    debugPrint(enabled
        ? '🔇 Noise suppression ENABLED'
        : '🔊 Noise suppression DISABLED');
  }

  /// Start a new session
  void startSession() {
    _isEnabled = true;
    debugPrint('🔇 Noise suppression session started');
  }

  /// Whether noise suppression is enabled
  bool get isEnabled => _isEnabled;

  /// Whether the service is ready (always true for built-in)
  bool get isInitialized => _isInitialized;

  /// Dispose
  void dispose() {
    _isEnabled = false;
  }
}
