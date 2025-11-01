import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  IOWebSocketChannel? _channel;
  bool _isStreaming = false;
  String _status = "Idle";
  Timer? _sendTimer;
  late String _pcmPath;

  final String _serverUrl = "ws://127.0.0.1:5000/stream/live";

  Future<void> startStreaming() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _status = "Mic permission denied");
      return;
    }

    final dir = await getTemporaryDirectory();
    _pcmPath = '${dir.path}/live_audio.pcm';

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _pcmPath,
    );

    setState(() {
      _isStreaming = true;
      _status = "Connecting...";
    });

    _channel = IOWebSocketChannel.connect(Uri.parse(_serverUrl));
    _channel!.stream.listen(
          (msg) => setState(() => _status = msg),
      onDone: () => setState(() => _status = "Connection closed"),
      onError: (e) => setState(() => _status = "Error: $e"),
    );

    // Send file chunks every 500ms
    int lastSentSize = 0;

    _sendTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (!_isStreaming) return;

      final file = File(_pcmPath);
      if (!await file.exists()) return;

      final totalSize = await file.length();
      if (totalSize <= lastSentSize) return;

      // Read only the newly written part
      final raf = file.openSync(mode: FileMode.read);
      raf.setPositionSync(lastSentSize);
      final newBytes = raf.readSync(totalSize - lastSentSize);
      raf.closeSync();

      lastSentSize = totalSize;
      if (newBytes.isNotEmpty) {
        _channel?.sink.add(Uint8List.fromList(newBytes));
      }
    });


    setState(() => _status = "Streaming...");
  }

  Future<void> stopStreaming() async {
    try {
      await _recorder.stop();
      _sendTimer?.cancel();
      _channel?.sink.close();
    } catch (_) {}
    setState(() {
      _isStreaming = false;
      _status = "Stopped";
    });
  }

  @override
  void dispose() {
    _sendTimer?.cancel(); // safely cancels if it's null
    _recorder.dispose();
    _channel?.sink.close();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("HearWise")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Status: $_status"),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isStreaming ? stopStreaming : startStreaming,
              child: Text(_isStreaming ? "Stop Streaming" : "Start Streaming"),
            ),
          ],
        ),
      ),
    );
  }
}
