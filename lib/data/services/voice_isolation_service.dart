import 'package:flutter/foundation.dart';

/// Voice isolation service using Android/iOS built-in audio processing.
///
/// Combines noise suppression + echo cancellation + auto gain control
/// to enhance voice clarity. Uses the device's hardware-accelerated 
/// audio processing via the record package's RecordConfig parameters.
/// No TFLite models needed — works on all modern Android devices.
class VoiceIsolationService {
  static final VoiceIsolationService _instance = VoiceIsolationService._internal();
  factory VoiceIsolationService() => _instance;
  VoiceIsolationService._internal();

  bool _isEnabled = false;
  bool _isInitialized = true; // Always ready — uses built-in hardware

  /// Initialize the service
  Future<bool> initialize() async {
    _isInitialized = true;
    debugPrint('✅ Voice isolation ready (built-in noise suppress + echo cancel + auto gain)');
    return true;
  }

  /// Enable/disable voice isolation
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    debugPrint(enabled
        ? '🗣️ Voice isolation ENABLED'
        : '🔊 Voice isolation DISABLED');
  }

  /// Start a new session
  void startSession() {
    _isEnabled = true;
    debugPrint('🗣️ Voice isolation session started');
  }

  /// Whether isolation is enabled
  bool get isEnabled => _isEnabled;

  /// Whether the service is ready (always true for built-in)
  bool get isInitialized => _isInitialized;

  /// Dispose
  void dispose() {
    _isEnabled = false;
  }
}
