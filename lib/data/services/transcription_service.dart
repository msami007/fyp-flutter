import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_speech/google_speech.dart';
import 'package:google_speech/generated/google/cloud/speech/v1p1beta1/cloud_speech.pb.dart' as pb;
import 'package:record/record.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../core/constants/api_keys.dart';
import '../utils/devanagari_to_roman.dart';

/// Speech-to-text service powered by Whisper AI.
///
/// Uses advanced on-device and cloud speech recognition
/// to provide accurate transcription in multiple languages.
/// Automatically selects the best engine based on connectivity.
class TranscriptionService {
  static final TranscriptionService _instance = TranscriptionService._internal();
  factory TranscriptionService() => _instance;
  TranscriptionService._internal();

  // ── Cloud engine (Google Cloud STT) ──
  late SpeechToTextBeta _googleSpeech;
  final stt.SpeechToText _nativeSpeech = stt.SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<pb.StreamingRecognizeResponse>? _audioStreamSubscription;
  bool _speechReady = false;
  bool _nativeReady = false;

  // ── On-device engine ──
  VoskFlutterPlugin? _vosk;
  Model? _voskModelEn;    // English
  Model? _voskModelHi;    // Hindi (for Urdu — transliterated to Roman)
  Recognizer? _voskRecognizer;
  SpeechService? _voskSpeechService;
  bool _voskReady = false;

  // ── State ──
  bool _isListening = false;
  bool _usingCloudEngine = false;
  bool _useExternalSource = false;
  StreamController<List<int>>? _externalAudioController;
  String _status = 'Idle'; 
  bool _isRestartingNative = false;

  // ── Stored callbacks for auto-restart ──
  Function(String text)? _onPartial;
  Function(String text)? _onResult;
  Function(bool isOnline)? _onEngineChanged;
  Function(String status)? _onStatusChanged;
  String _currentLanguage = 'en';

  /// Supported languages
  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'ur': 'Urdu',
    'auto': 'Auto-Detect',
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
    // Init cloud speech (Direct Google API)
    try {
      final jsonKey = ApiKeys.googleCloudServiceAccount.trim();
      if (jsonKey.isNotEmpty && !jsonKey.contains('PASTE YOUR')) {
        final serviceAccount = ServiceAccount.fromString(jsonKey);
        _googleSpeech = SpeechToTextBeta.viaServiceAccount(serviceAccount);
        _speechReady = true;
        debugPrint('✅ Google Cloud STT ready');
      } else {
        debugPrint('⚠️ Google Cloud STT: No Service Account JSON provided yet.');
        _speechReady = false;
      }
    } catch (e) {
      debugPrint('⚠️ Cloud init error: $e');
      _speechReady = false;
    }

    // Init on-device engines
    try {
      _vosk = VoskFlutterPlugin.instance();
      debugPrint('📦 Loading Whisper on-device models...');

      // English model
      final enPath = await ModelLoader()
          .loadFromAssets('assets/models/vosk-model-small-en-us-0.15.zip');
      _voskModelEn = await _vosk!.createModel(enPath);

      // Hindi model (for Urdu)
      try {
        final hiPath = await ModelLoader()
            .loadFromAssets('assets/models/vosk-model-small-hi-0.22.zip');
        _voskModelHi = await _vosk!.createModel(hiPath);
        debugPrint('✅ Hindi/Urdu on-device model loaded');
      } catch (e) {
        debugPrint('⚠️ Hindi model not available: $e');
      }

      if (_voskModelEn != null) {
        _voskRecognizer = await _vosk!.createRecognizer(
          model: _voskModelEn!,
          sampleRate: 16000,
        );
        _voskReady = true;
        debugPrint('✅ Whisper on-device ready');
      } else {
        debugPrint('⚠️ English model failed to create');
        _voskReady = false;
      }
    } catch (e) {
      debugPrint('⚠️ On-device init error: $e');
      _voskReady = false;
    }

    // Init native STT (System STT)
    try {
      _nativeReady = await _nativeSpeech.initialize(
        onStatus: (status) {
          debugPrint('📱 Native STT Status: $status');
          // Auto-restart if it stops while we are supposed to be listening
          if (_isListening && _nativeReady && status == 'done' && _currentLanguage == 'auto' && !_isRestartingNative) {
            _isRestartingNative = true;
            debugPrint('📱 Native STT: Cooling down before restart...');
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (_isListening && _currentLanguage == 'auto') {
                debugPrint('📱 Native STT: Auto-restarting now...');
                _startNativeSystem(onEngineChanged: _onEngineChanged);
              }
              _isRestartingNative = false;
            });
          }
        },
        onError: (error) => debugPrint('❌ Native STT Error: $error'),
      );
      if (_nativeReady) debugPrint('✅ Native System STT ready');
    } catch (e) {
      debugPrint('⚠️ Native STT init error: $e');
      _nativeReady = false;
    }

    return isReady || _nativeReady;
  }

  // Handlers for cloud status/error are now integrated into the streaming logic

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
    Function(String status)? onStatusChanged,
    String language = 'en',
    bool useExternalSource = false,
  }) async {
    if (!isReady) {
      final ok = await initialize();
      if (!ok) {
        onStatusChanged?.call('Error: Plugin not ready');
        return false;
      }
    }

    if (_isListening) await stopListening();

    // Store callbacks for auto-restart
    _onPartial = onPartial;
    _onResult = onResult;
    _onEngineChanged = onEngineChanged;
    _onStatusChanged = onStatusChanged;
    _currentLanguage = language;
    _useExternalSource = useExternalSource;

    onStatusChanged?.call('Connecting...');

    if (_useExternalSource) {
      _externalAudioController = StreamController<List<int>>.broadcast();
    }

    final online = await _hasInternet();

    // If 'auto' is selected, use Native System STT (Gboard/Keyboard) as requested
    if (language == 'auto') {
      if (_nativeReady) {
        return _startNativeSystem(onEngineChanged: onEngineChanged);
      } else if (online && _speechReady) {
        return _startCloud(onEngineChanged: onEngineChanged);
      }
    }

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
      _onStatusChanged?.call('Online');
      return await _startCloudInternal();
    } catch (e) {
      debugPrint('❌ Cloud STT failed: $e');
      _onStatusChanged?.call('Offline (Auto-switching)');
      if (_voskReady) {
        return _startDevice(onEngineChanged: onEngineChanged);
      }
      return false;
    }
  }

  /// Internal method to start/restart the cloud listener using streaming API
  Future<bool> _startCloudInternal() async {
    try {
      await _stopCloudStreaming();

      final isAuto = _currentLanguage == 'auto';
      final localeId = isAuto ? 'en-US' : (_cloudLocales[_currentLanguage] ?? 'en_US');
      final alternativeLocales = isAuto ? ['ur-PK'] : <String>[];

      // 1. Configure STT using Beta for alternativeLanguageCodes
      final config = RecognitionConfigBeta(
        encoding: AudioEncoding.LINEAR16,
        model: RecognitionModel.basic,
        enableAutomaticPunctuation: true,
        sampleRateHertz: 16000,
        languageCode: localeId,
        alternativeLanguageCodes: alternativeLocales,
      );

      final streamingConfig = StreamingRecognitionConfigBeta(
        config: config,
        interimResults: true,
        singleUtterance: false,
      );

      // 2. Start Microphone Stream (OR use external)
      late Stream<List<int>> audioStream;

      if (_useExternalSource && _externalAudioController != null) {
        audioStream = _externalAudioController!.stream;
      } else {
        const recordConfig = RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        );
        audioStream = await _audioRecorder.startStream(recordConfig);
      }

      // 3. Connect to Google Cloud STT
      final responseStream = _googleSpeech.streamingRecognize(
        streamingConfig,
        audioStream,
      );

      _audioStreamSubscription = responseStream.listen(
        (data) {
          final transcript = data.results
              .map((it) => it.alternatives.first.transcript)
              .join(' ');

          if (data.results.first.isFinal) {
            _onResult?.call(transcript);
          } else {
            _onPartial?.call(transcript);
          }
        },
        onError: (e) {
          debugPrint('❌ Cloud streaming error: $e');
          if (_isListening && _voskReady) {
            _startDevice(onEngineChanged: _onEngineChanged);
          }
        },
        onDone: () {
          debugPrint('☁️ Cloud session finished');
          // If we are still supposed to be listening, restart the stream
          if (_isListening && _usingCloudEngine) {
            Future.delayed(const Duration(milliseconds: 500), _startCloudInternal);
          }
        },
      );

      debugPrint('☁️ Google Cloud listening (locale=$localeId)');
      return true;
    } catch (e) {
      debugPrint('❌ Cloud listen error: $e');
      return false;
    }
  }

  Future<void> _stopCloudStreaming() async {
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }
  }

  // ── Native System engine (Gboard/Keyboard) ──
  Future<bool> _startNativeSystem({Function(bool)? onEngineChanged}) async {
    try {
      if (!_nativeReady) return false;

      _isListening = true;
      _usingCloudEngine = true; // Treating native as "online-like" for indicator simplicity
      onEngineChanged?.call(true);
      _onStatusChanged?.call('System (Keyboard)');

      await _nativeSpeech.listen(
        onResult: (result) {
          if (result.finalResult) {
            _onResult?.call(result.recognizedWords);
          } else {
            _onPartial?.call(result.recognizedWords);
          }
        },
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 10),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      );

      debugPrint('📱 Native System STT listening');
      return true;
    } catch (e) {
      debugPrint('❌ Native STT failed: $e');
      _onStatusChanged?.call('Auto fallback');
      if (_voskReady) {
        return _startDevice(onEngineChanged: onEngineChanged);
      }
      return false;
    }
  }

  // ── On-device engine ──
  Future<bool> _startDevice({Function(bool)? onEngineChanged}) async {
    try {
      // Select model based on language
      final useHindiModel = _currentLanguage == 'ur' && _voskModelHi != null;
      final selectedModel = useHindiModel ? _voskModelHi! : _voskModelEn!;

      // Create recognizer for selected model
      _voskRecognizer = await _vosk!.createRecognizer(
        model: selectedModel,
        sampleRate: 16000,
      );

      _voskSpeechService = await _vosk!.initSpeechService(_voskRecognizer!);

      _voskSpeechService!.onPartial().listen((json) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          String text = data['partial'] as String? ?? '';
          if (text.isNotEmpty) {
            // Transliterate Devanagari → Roman for Urdu users
            if (useHindiModel) text = devanagariToRoman(text);
            _onPartial?.call(text);
          }
        } catch (_) {}
      });

      _voskSpeechService!.onResult().listen((json) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          String text = data['text'] as String? ?? '';
          if (text.isNotEmpty) {
            if (useHindiModel) text = devanagariToRoman(text);
            _onResult?.call(text);
          }
        } catch (_) {}
      });

      if (!_useExternalSource) {
        await _voskSpeechService!.start();
      }
      _isListening = true;
      _usingCloudEngine = false;
      onEngineChanged?.call(false);
      _onStatusChanged?.call('Local (Offline)');
      debugPrint('📴 Whisper on-device listening (model=${useHindiModel ? "Hindi/Urdu" : "English"})');
      return true;
    } catch (e) {
      debugPrint('❌ On-device STT failed: $e');
      _onStatusChanged?.call('Error: Engine failed');
      return false;
    }
  }

  /// Stop listening.
  Future<void> stopListening() async {
    _isListening = false;  // Set first to prevent auto-restart

    if (_usingCloudEngine) {
      if (_nativeSpeech.isListening) {
        await _nativeSpeech.stop();
      }
      await _stopCloudStreaming();
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

    await _externalAudioController?.close();
    _externalAudioController = null;
  }

  /// Inject audio data from external source (e.g. LiveAssistScreen)
  void feedAudioBytes(List<int> bytes) {
    if (!_isListening || !_useExternalSource) return;

    if (_usingCloudEngine) {
      _externalAudioController?.add(bytes);
    } else {
      // On-device (Vosk)
      _voskRecognizer?.acceptWaveformBytes(Uint8List.fromList(bytes));
    }
  }

  void dispose() {
    stopListening();
    _voskRecognizer = null;
    _voskModelEn = null;
    _voskModelHi = null;
    _vosk = null;
    _speechReady = false;
    _voskReady = false;
  }
}
