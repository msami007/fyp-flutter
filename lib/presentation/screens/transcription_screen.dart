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
              _activeEngineName = 'WHISPER';
            } else if (status.contains('Online')) {
              _activeEngineName = 'WHISPER';
            } else {
              _activeEngineName = 'WHISPER';
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

    final TextEditingController nameController = TextEditingController(
      text: 'Transcript ${DateTime.now().day}/${DateTime.now().month} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}'
    );

    final String? result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2139),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Save Transcription', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Give your transcript a name for easy search later.', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                hintText: 'Enter name...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save Transcript', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;

    await _historyService.saveConversation(
      title: result.trim(),
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

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "TRANSCRIPTION",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        ),
        actions: [
          if (transcript.isNotEmpty && !_isListening)
            IconButton(
              icon: const Icon(Icons.save_alt_rounded, color: Color(0xFF6C63FF)),
              onPressed: _saveToHistory,
              tooltip: 'Save Transcript',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  children: [
                    // ── Transcript Container ──
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF131932),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: Colors.white.withOpacity(0.03)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(32),
                            physics: const BouncingScrollPhysics(),
                            child: transcript.isNotEmpty
                                ? SelectableText.rich(
                                    TextSpan(children: [
                                      if (_finalParts.isNotEmpty)
                                        TextSpan(
                                          text: '${_finalParts.join(' ')} ',
                                          style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.6, fontWeight: FontWeight.w400),
                                        ),
                                      if (_currentPartial.isNotEmpty)
                                        TextSpan(
                                          text: _currentPartial,
                                          style: TextStyle(
                                            color: const Color(0xFF6C63FF).withOpacity(0.8),
                                            fontSize: 20, height: 1.6,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                    ]),
                                  )
                                : Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.waves_rounded, color: Colors.white.withOpacity(0.05), size: 64),
                                        const SizedBox(height: 24),
                                        Text(
                                          _isListening ? 'LISTENING...' : 'TAP MIC TO START',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.1),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Control Panel ──
                    _buildControlPanel(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131932),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: _isListening ? Colors.redAccent : (_isInitializing ? Colors.orange : Colors.green),
              shape: BoxShape.circle,
              boxShadow: [
                if (_isListening)
                  BoxShadow(color: Colors.redAccent.withOpacity(0.4), blurRadius: 8, spreadRadius: 2),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isListening ? _formatTime(_recordingSeconds).toUpperCase() : (_isInitializing ? 'INITIALIZING' : 'READY'),
              style: TextStyle(
                color: _isListening ? Colors.redAccent : Colors.white.withOpacity(0.4),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildLanguagePicker(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: Color(0xFF6C63FF), size: 10),
                SizedBox(width: 4),
                Text(
                  'WHISPER',
                  style: TextStyle(color: Color(0xFF6C63FF), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Column(
      children: [
        GestureDetector(
          onTap: (_isInitializing || !_transcription.isReady)
              ? null
              : _isListening ? _stopListening : _startListening,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: _isListening ? Colors.redAccent.withOpacity(0.1) : const Color(0xFF6C63FF),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_isListening ? Colors.redAccent : const Color(0xFF6C63FF)).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: _isListening ? Colors.redAccent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Center(
              child: _isInitializing
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Icon(
                      _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _isListening ? 'STOP SESSION' : 'START RECORDING',
          style: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildLanguagePicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedLang,
          dropdownColor: const Color(0xFF131932),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF6C63FF), size: 14),
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          onChanged: (val) => setState(() => _selectedLang = val ?? 'en'),
          items: TranscriptionService.supportedLanguages.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.toUpperCase())))
              .toList(),
        ),
      ),
    );
  }
}