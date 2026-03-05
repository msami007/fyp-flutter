import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/services/transcription_service.dart';
import '../../data/services/conversation_history_service.dart';
import '../../data/services/model_manager_service.dart';

class TranscriptionScreen extends StatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  final TranscriptionService _transcriptionService = TranscriptionService();
  final ConversationHistoryService _historyService = ConversationHistoryService();
  final ModelManagerService _modelManager = ModelManagerService();
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isProcessing = false;
  String _currentLanguage = 'auto';
  String _transcribedText = '';
  String _activeModel = 'tiny';
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  String? _currentRecordingPath;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _activeModel = await _modelManager.getActiveWhisperModel();
    final initialized = await _transcriptionService.initialize();
    if (!initialized && mounted) {
      _showSnackBar('Whisper model not found. Please download in Settings.', Colors.orange);
    }
    if (mounted) setState(() {});
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      _showSnackBar('Microphone permission required', Colors.orange);
      return;
    }

    final dir = await getTemporaryDirectory();
    _currentRecordingPath = '${dir.path}/transcription_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      ),
      path: _currentRecordingPath!,
    );

    setState(() {
      _isRecording = true;
      _recordingDuration = 0;
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordingDuration++);
    });

    _showSnackBar('Recording started... Speak now', const Color(0xFF4CAF50));
  }

  Future<void> _stopAndTranscribe() async {
    _recordingTimer?.cancel();
    await _recorder.stop();

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });

    if (_currentRecordingPath == null) {
      setState(() => _isProcessing = false);
      return;
    }

    try {
      final result = await _transcriptionService.transcribe(
        audioPath: _currentRecordingPath!,
        language: _currentLanguage,
      );

      setState(() {
        if (_transcribedText.isNotEmpty && result.text.isNotEmpty) {
          _transcribedText += '\n${result.text}';
        } else {
          _transcribedText = result.text;
        }
        _isProcessing = false;
      });

      // Auto-scroll to bottom
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showSnackBar('Transcription failed: $e', Colors.red);
    }

    // Clean up temp file
    try {
      final file = File(_currentRecordingPath!);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _saveToHistory() async {
    if (_transcribedText.isEmpty) {
      _showSnackBar('Nothing to save', Colors.orange);
      return;
    }

    final title = 'Transcript ${DateTime.now().day}/${DateTime.now().month} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}';

    await _historyService.saveConversation(
      title: title,
      transcript: _transcribedText,
      language: _currentLanguage,
      durationSeconds: _recordingDuration,
      modelUsed: _activeModel,
    );

    _showSnackBar('Saved to conversation history ✓', const Color(0xFF4CAF50));
  }

  void _clearText() {
    setState(() {
      _transcribedText = '';
      _recordingDuration = 0;
    });
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.subtitles_rounded, color: Color(0xFF6C63FF), size: 24),
            const SizedBox(width: 12),
            const Text("Live Transcription",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_transcribedText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              onPressed: _saveToHistory,
              tooltip: 'Save to history',
            ),
          if (_transcribedText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _clearText,
              tooltip: 'Clear text',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Language & Model Info ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2139),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  // Language picker
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Language", style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
                        const SizedBox(height: 4),
                        DropdownButton<String>(
                          value: _currentLanguage,
                          dropdownColor: const Color(0xFF1E2139),
                          isExpanded: true,
                          underline: const SizedBox(),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          items: TranscriptionService.supportedLanguages.entries
                              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: _isRecording ? null : (val) {
                            setState(() => _currentLanguage = val ?? 'auto');
                          },
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(width: 16),
                  // Model info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Model", style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
                        const SizedBox(height: 8),
                        Text(
                          'Whisper $_activeModel',
                          style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Transcribed Text Area ──
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2139),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: _transcribedText.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.mic_none_rounded, size: 48, color: Colors.white.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            Text(
                              _isProcessing ? 'Processing audio...' : 'Tap the mic button to start',
                              style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.5)),
                            ),
                            if (_isProcessing) ...[
                              const SizedBox(height: 16),
                              const CircularProgressIndicator(color: Color(0xFF6C63FF), strokeWidth: 3),
                            ],
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        controller: _scrollController,
                        child: Text(
                          _transcribedText,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            height: 1.6,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Recording Controls ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2139),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Duration
                  if (_isRecording)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE91E63).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(color: Color(0xFFE91E63), shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(_recordingDuration),
                            style: const TextStyle(color: Color(0xFFE91E63), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),

                  if (_isRecording) const SizedBox(width: 20),

                  // Record/Stop Button
                  GestureDetector(
                    onTap: _isProcessing
                        ? null
                        : (_isRecording ? _stopAndTranscribe : _startRecording),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _isRecording
                              ? [const Color(0xFFE91E63), const Color(0xFFF44336)]
                              : [const Color(0xFF6C63FF), const Color(0xFF4A44B5)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? const Color(0xFFE91E63) : const Color(0xFF6C63FF)).withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),

                  if (!_isRecording && _transcribedText.isNotEmpty) ...[
                    const SizedBox(width: 20),
                    // Save button
                    GestureDetector(
                      onTap: _saveToHistory,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.5)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.save_rounded, color: Color(0xFF4CAF50), size: 18),
                            SizedBox(width: 8),
                            Text('Save', style: TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
