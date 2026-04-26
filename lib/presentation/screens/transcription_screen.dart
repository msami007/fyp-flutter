import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/services/transcription_service.dart';
import '../../data/services/conversation_history_service.dart';

class TranscriptionScreen extends StatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  final TranscriptionService _transcription = TranscriptionService();
  final ConversationHistoryService _historyService = ConversationHistoryService();

  bool _isListening = false;
  bool _isInitializing = false;
  String _currentPartial = '';
  final List<String> _finalParts = [];
  int _recordingSeconds = 0;
  Timer? _timer;
  String _selectedLang = 'en';
  String _statusMessage = 'Ready. Tap Start to begin.';
  bool _isUsingOnlineEngine = false;
  String _activeEngineName = 'WHISPER';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isInitializing = true);
    final ok = await _transcription.initialize();
    if (!mounted) return;
    setState(() {
      _isInitializing = false;
      _statusMessage = ok
          ? 'Ready. Tap Start to begin.'
          : '⚠️ Whisper model failed to load.';
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _transcription.stopListening();
    super.dispose();
  }

  String get _fullTranscript {
    final parts = [..._finalParts];
    if (_currentPartial.isNotEmpty) parts.add(_currentPartial);
    return parts.join(' ');
  }

  Future<void> _startListening() async {
    setState(() {
      _isListening = true;
      _currentPartial = '';
      _finalParts.clear();
      _recordingSeconds = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordingSeconds++);
    });

    final ok = await _transcription.startListening(
      language: _selectedLang,
      onEngineChanged: (isOnline) {
        if (mounted) setState(() => _isUsingOnlineEngine = isOnline);
      },
      onStatusChanged: (status) {
        if (mounted) {
          setState(() {
            _statusMessage = status;
            if (status.contains('System')) {
              _activeEngineName = 'SYSTEM STT';
            } else if (status.contains('Online')) {
              _activeEngineName = 'GOOGLE CLOUD';
            } else {
              _activeEngineName = 'OFFLINE VOSK';
            }
          });
        }
      },
      onPartial: (text) {
        if (mounted) setState(() => _currentPartial = text);
      },
      onResult: (text) {
        if (!mounted) return;
        setState(() {
          if (text.isNotEmpty) _finalParts.add(text);
          _currentPartial = '';
        });
      },
    );

    if (!ok && mounted) {
      _timer?.cancel();
      setState(() {
        _isListening = false;
        _statusMessage = '❌ Could not start Whisper.';
      });
    }
  }

  Future<void> _stopListening() async {
    _timer?.cancel();
    await _transcription.stopListening();
    if (!mounted) return;
    if (_currentPartial.isNotEmpty) {
      _finalParts.add(_currentPartial);
      _currentPartial = '';
    }
    setState(() => _isListening = false);
  }

  Future<void> _saveToHistory() async {
    final transcript = _fullTranscript;
    if (transcript.isEmpty) return;

    final now = DateTime.now();
    final title = 'Transcript ${now.day}/${now.month} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    await _historyService.saveConversation(
      title: title,
      transcript: transcript,
      language: _selectedLang,
      durationSeconds: _recordingSeconds,
      modelUsed: 'whisper',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Saved to history ✓"),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  String _formatTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final transcript = _fullTranscript;
    final langName = TranscriptionService.supportedLanguages[_selectedLang] ?? 'English';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Whisper Transcription", style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          if (transcript.isNotEmpty && !_isListening)
            IconButton(
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              onPressed: _saveToHistory,
              tooltip: 'Save',
            ),
        ],
      ),
      backgroundColor: const Color(0xFF0A0E27),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ── Top bar ──
              Row(
                children: [
                  // Status
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isListening
                          ? Colors.red.withOpacity(0.2)
                          : _isInitializing
                              ? Colors.orange.withOpacity(0.15)
                              : Colors.grey.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: _isListening ? Colors.red
                                : _isInitializing ? Colors.orange : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isListening ? _formatTime(_recordingSeconds)
                              : _isInitializing ? 'Loading...' : 'Ready',
                          style: TextStyle(
                            color: _isListening ? Colors.red
                                : _isInitializing ? Colors.orange : Colors.grey,
                            fontWeight: FontWeight.w600, fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Language selector
                  if (!_isListening)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2139),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedLang,
                        dropdownColor: const Color(0xFF1E2139),
                        underline: const SizedBox(),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: TranscriptionService.supportedLanguages.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (val) {
                          setState(() => _selectedLang = val ?? 'en');
                        },
                      ),
                    ),
                  // Engine indicator
                  if (_isListening)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isUsingOnlineEngine 
                            ? Colors.green.withOpacity(0.15) 
                            : Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _activeEngineName == 'GOOGLE CLOUD' ? Icons.cloud_done_rounded : Icons.phone_android_rounded, 
                            size: 14, 
                            color: _activeEngineName == 'GOOGLE CLOUD' ? Colors.green : Colors.blueAccent
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _activeEngineName,
                            style: TextStyle(
                              color: _activeEngineName == 'GOOGLE CLOUD' ? Colors.green : Colors.blueAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Transcript area ──
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2139),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
                  ),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: transcript.isNotEmpty
                        ? SelectableText.rich(
                            TextSpan(children: [
                              if (_finalParts.isNotEmpty)
                                TextSpan(
                                  text: '${_finalParts.join(' ')} ',
                                  style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                                ),
                              if (_currentPartial.isNotEmpty)
                                TextSpan(
                                  text: _currentPartial,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 16, height: 1.6,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ]),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isInitializing) ...[
                                const CircularProgressIndicator(
                                  color: Color(0xFF6C63FF), strokeWidth: 2.5,
                                ),
                                const SizedBox(height: 16),
                              ],
                              Text(
                                _isListening ? 'Listening... speak now.' : _statusMessage,
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16, height: 1.6),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Whisper AI · $langName',
                style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11),
              ),

              const SizedBox(height: 16),

              // ── Buttons ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: (_isInitializing || !_transcription.isReady)
                        ? null
                        : _isListening ? _stopListening : _startListening,
                    icon: Icon(_isListening ? Icons.stop_rounded : Icons.mic_rounded),
                    label: Text(_isListening ? 'Stop' : 'Start', style: const TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isListening ? const Color(0xFFE91E63) : const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  if (!_isListening && transcript.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _saveToHistory,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}