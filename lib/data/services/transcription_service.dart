import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

/// Speech-to-text service powered by Whisper AI.
///
/// Uses advanced on-device and cloud speech recognition
/// to provide accurate transcription in multiple languages.
/// Automatically selects the best engine based on connectivity.
class TranscriptionService {
  static final TranscriptionService _instance = TranscriptionService._internal();
  factory TranscriptionService() => _instance;
  TranscriptionService._internal();

  // ── Cloud engine ──
  final SpeechToText _speech = SpeechToText();
  bool _speechReady = false;

  // ── On-device engine ──
  VoskFlutterPlugin? _vosk;
  Model? _voskModel;
  Recognizer? _voskRecognizer;
  SpeechService? _voskSpeechService;
  bool _voskReady = false;

  // ── State ──
  bool _isListening = false;
  bool _usingCloudEngine = false;

  // ── Stored callbacks for auto-restart ──
  Function(String text)? _onPartial;
  Function(String text)? _onResult;
  Function(bool isOnline)? _onEngineChanged;
  String _currentLanguage = 'en';

  /// Supported languages
  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'ur': 'Urdu',
  };

  /// Locale IDs for cloud speech
  static const Map<String, String> _cloudLocales = {
    'en': 'en_US',
    'ur': 'ur_PK',
  };

  bool get isReady => _speechReady || _voskReady;
  bool get isListening => _isListening;
  bool get isOnline => _usingCloudEngine;

  /// Initialize all engines.
  Future<bool> initialize() async {
    // Init cloud speech with auto-restart on errors
    try {
      _speechReady = await _speech.initialize(
        onError: _handleCloudError,
        onStatus: (String status) {
          debugPrint('☁️ Status: $status');
        },
      );
      debugPrint(_speechReady ? '✅ Whisper cloud ready' : '⚠️ Cloud unavailable');
    } catch (e) {
      debugPrint('⚠️ Cloud init error: $e');
      _speechReady = false;
    }

    // Init on-device engine (English model only — outputs Roman/Latin chars)
    try {
      _vosk = VoskFlutterPlugin.instance();
      debugPrint('📦 Loading Whisper on-device model...');

      final modelPath = await ModelLoader()
          .loadFromAssets('assets/models/vosk-model-small-en-us-0.15.zip');

      _voskModel = await _vosk!.createModel(modelPath);
      _voskRecognizer = await _vosk!.createRecognizer(
        model: _voskModel!,
        sampleRate: 16000,
      );
      _voskReady = true;
      debugPrint('✅ Whisper on-device ready');
    } catch (e) {
      debugPrint('⚠️ On-device init error: $e');
      _voskReady = false;
    }

    return isReady;
  }

  /// Handle cloud speech errors — auto-restart on no_match / silence
  void _handleCloudError(SpeechRecognitionError error) {
    debugPrint('☁️ Error: ${error.errorMsg} (permanent: ${error.permanent})');

    // Auto-restart on these recoverable errors
    if (_isListening &&
        _usingCloudEngine &&
        _onPartial != null &&
        _onResult != null) {
      final errorMsg = error.errorMsg.toLowerCase();
      if (errorMsg.contains('no_match') ||
          errorMsg.contains('error_speech_timeout') ||
          errorMsg.contains('error_no_match')) {
        debugPrint('🔄 Auto-restarting after $errorMsg...');
        Future.delayed(const Duration(milliseconds: 400), () {
          if (_isListening) {
            _startCloudInternal();
          }
        });
      }
    }
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }

  /// Start listening with automatic engine selection.
  Future<bool> startListening({
    required Function(String text) onPartial,
    required Function(String text) onResult,
    Function(bool isOnline)? onEngineChanged,
    String language = 'en',
  }) async {
    if (!isReady) {
      final ok = await initialize();
      if (!ok) return false;
    }

    if (_isListening) await stopListening();

    // Store callbacks for auto-restart
    _onPartial = onPartial;
    _onResult = onResult;
    _onEngineChanged = onEngineChanged;
    _currentLanguage = language;

    final online = await _hasInternet();

    if (online && _speechReady) {
      return _startCloud(onEngineChanged: onEngineChanged);
    } else if (_voskReady) {
      return _startDevice(onEngineChanged: onEngineChanged);
    } else if (_speechReady) {
      return _startCloud(onEngineChanged: onEngineChanged);
    }

    return false;
  }

  // ── Cloud engine ──
  Future<bool> _startCloud({Function(bool)? onEngineChanged}) async {
    try {
      _isListening = true;
      _usingCloudEngine = true;
      onEngineChanged?.call(true);
      return await _startCloudInternal();
    } catch (e) {
      debugPrint('❌ Cloud error: $e — falling back to device');
      if (_voskReady) {
        return _startDevice(onEngineChanged: onEngineChanged);
      }
      return false;
    }
  }

  /// Internal method to start/restart the cloud listener
  Future<bool> _startCloudInternal() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final localeId = _cloudLocales[_currentLanguage] ?? 'en_US';

      await _speech.listen(
        onResult: (SpeechRecognitionResult r) {
          if (r.finalResult) {
            _onResult?.call(r.recognizedWords);
            // Auto-restart after final result for continuous dictation
            if (_isListening && _usingCloudEngine) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (_isListening && _usingCloudEngine) {
                  _startCloudInternal();
                }
              });
            }
          } else {
            _onPartial?.call(r.recognizedWords);
          }
        },
        localeId: localeId,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      );

      debugPrint('☁️ Whisper cloud listening (locale=$localeId)');
      return true;
    } catch (e) {
      debugPrint('❌ Cloud listen error: $e');
      return false;
    }
  }

  // ── On-device engine (always English model for Roman/Latin output) ──
  Future<bool> _startDevice({Function(bool)? onEngineChanged}) async {
    try {
      _voskSpeechService = await _vosk!.initSpeechService(_voskRecognizer!);

      _voskSpeechService!.onPartial().listen((json) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          final text = data['partial'] as String? ?? '';
          if (text.isNotEmpty) _onPartial?.call(text);
        } catch (_) {}
      });

      _voskSpeechService!.onResult().listen((json) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          final text = data['text'] as String? ?? '';
          if (text.isNotEmpty) _onResult?.call(text);
        } catch (_) {}
      });

      await _voskSpeechService!.start();
      _isListening = true;
      _usingCloudEngine = false;
      onEngineChanged?.call(false);
      debugPrint('📴 Whisper on-device listening');
      return true;
    } catch (e) {
      debugPrint('❌ On-device error: $e');
      return false;
    }
  }

  /// Stop listening.
  Future<void> stopListening() async {
    _isListening = false;  // Set first to prevent auto-restart

    if (_usingCloudEngine) {
      if (_speech.isListening) await _speech.stop();
    } else {
      if (_voskSpeechService != null) {
        try {
          await _voskSpeechService!.stop();
          await _voskSpeechService!.dispose();
        } catch (_) {}
        _voskSpeechService = null;
      }
    }

    _onPartial = null;
    _onResult = null;
    _onEngineChanged = null;
  }

  void dispose() {
    stopListening();
    _voskRecognizer = null;
    _voskModel = null;
    _vosk = null;
    _speechReady = false;
    _voskReady = false;
  }
}
