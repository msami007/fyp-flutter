import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class TranscriptionScreen extends StatefulWidget {
  const TranscriptionScreen({super.key});

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isListening = false;
  String _text = "Press Start and speak...";
  String? _filePath;
  Timer? _recordingTimer;
  List<String> _transcribedParts = [];
  int _counter = 0;

  // Sample phrases for simulation
  final List<String> _samplePhrases = [
    "Hello, how are you today?",
    "I'm testing the speech recognition",
    "This is a simulated transcription",
    "The quick brown fox jumps over the lazy dog",
    "Speech to text is working",
    "You can now see the transcription",
    "This text updates every few seconds",
    "Keep speaking to see more text",
    "The app is recording your voice",
    "This is a demo of the transcription feature",
  ];

  @override
  void dispose() {
    _recorder.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  Future<void> _startListening() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => _text = "Microphone permission denied");
      return;
    }

    setState(() {
      _isListening = true;
      _text = "Listening...\n\n";
      _transcribedParts.clear();
      _counter = 0;
    });

    final dir = await getTemporaryDirectory();
    _filePath = '${dir.path}/temp_audio.wav';

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
      ),
      path: _filePath!,
    );

    print("Recording started at: $_filePath");

    // Simulate transcription every 2 seconds
    _recordingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      await _simulateTranscription();
    });
  }

  Future<void> _simulateTranscription() async {
    if (!_isListening) return;

    // Add a new simulated phrase
    if (_counter < _samplePhrases.length) {
      setState(() {
        _transcribedParts.add(_samplePhrases[_counter]);
        _text = "Listening...\n\n" + _transcribedParts.join('\n\n');
        _counter++;
      });
    } else {
      // Loop back to beginning
      _counter = 0;
      setState(() {
        _transcribedParts.add(_samplePhrases[_counter]);
        _text = "Listening...\n\n" + _transcribedParts.join('\n\n');
        _counter++;
      });
    }

    // Actually stop and restart recording to simulate real transcription
    // In a real app, you'd send the audio file to an API here
    await _recorder.stop();

    // Small delay
    await Future.delayed(const Duration(milliseconds: 500));

    if (_isListening) {
      // Start recording again
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
        ),
        path: _filePath!,
      );
    }
  }

  Future<void> _stopListening() async {
    _recordingTimer?.cancel();
    await _recorder.stop();

    setState(() {
      _isListening = false;
      _text = "Stopped. Final transcription:\n\n" + _transcribedParts.join('\n\n');
    });

    print("Recording stopped");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Speech Test",
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFF0A0E27),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _isListening ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _isListening ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isListening ? "Recording audio..." : "Not recording",
                    style: TextStyle(
                      color: _isListening ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Transcription display
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF6C63FF), width: 2),
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF1E2139),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _text,
                    style: const TextStyle(fontSize: 16, color: Colors.white, height: 1.5),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Debug info
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Audio recording is working! (check logs)\nSimulating transcription every 2 seconds",
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 20),

            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_isListening)
                  ElevatedButton(
                    onPressed: _startListening,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    ),
                    child: const Text("Start", style: TextStyle(fontSize: 18)),
                  ),
                if (_isListening)
                  ElevatedButton(
                    onPressed: _stopListening,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    ),
                    child: const Text("Stop", style: TextStyle(fontSize: 18)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}