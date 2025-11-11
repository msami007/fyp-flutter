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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  IOWebSocketChannel? _channel;
  bool _isStreaming = false;
  String _status = "Ready to stream";
  Timer? _sendTimer;
  late String _pcmPath;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  final String _serverUrl = "ws://127.0.0.1:5000/stream/live";

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(_animationController);
  }

  Future<void> startStreaming() async {
    if (!await _recorder.hasPermission()) {
      setState(() => _status = "Microphone permission denied");
      _showSnackBar("Please grant microphone permission", Colors.orange);
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
      _status = "Connecting to server...";
    });

    _channel = IOWebSocketChannel.connect(Uri.parse(_serverUrl));
    _channel!.stream.listen(
          (msg) => setState(() => _status = msg),
      onDone: () => setState(() => _status = "Connection closed"),
      onError: (e) => setState(() => _status = "Connection error"),
    );

    // Send file chunks every 400ms
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

    setState(() => _status = "Live streaming audio...");
    _showSnackBar("Streaming started successfully", const Color(0xFF4CAF50));
  }

  Future<void> stopStreaming() async {
    try {
      await _recorder.stop();
      _sendTimer?.cancel();
      _channel?.sink.close();
    } catch (_) {}
    setState(() {
      _isStreaming = false;
      _status = "Streaming stopped";
    });
    _showSnackBar("Streaming stopped", const Color(0xFFE91E63));
  }

  void _showSnackBar(String message, Color color) {
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

  @override
  void dispose() {
    _sendTimer?.cancel();
    _recorder.dispose();
    _channel?.sink.close();
    _animationController.dispose();
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
            // Simple sound waves icon
            Icon(
              Icons.graphic_eq_rounded,
              color: const Color(0xFF6C63FF),
              size: 24,
            ),
            const SizedBox(width: 12),
            const Text(
              "HearWise",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 8),
            // Live indicator dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _isStreaming ? const Color(0xFF4CAF50) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isStreaming ? const Color(0xFF4CAF50) : Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2139),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () {
                // Settings action
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2139),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.circle,
                        color: Color(0xFF6C63FF),
                        size: 16,
                      ),
                      SizedBox(width: 12),
                      Text(
                        "Stream Status",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _status,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isStreaming ? const Color(0xFF4CAF50) : Colors.white.withOpacity(0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Main Streaming Button
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isStreaming ? _pulseAnimation.value : 1.0,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _isStreaming
                          ? const LinearGradient(
                        colors: [Color(0xFFE91E63), Color(0xFFF44336)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                          : const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF4A44B5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isStreaming ? const Color(0xFFE91E63) : const Color(0xFF6C63FF)).withOpacity(0.4),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _isStreaming ? stopStreaming : startStreaming,
                        borderRadius: BorderRadius.circular(100),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isStreaming ? Icons.stop_rounded : Icons.mic_rounded,
                              size: 50,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isStreaming ? "STOP" : "START",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Text(
                              _isStreaming ? "Streaming" : "Stream",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const Spacer(),

            // Info Cards
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    icon: Icons.volume_up_rounded,
                    title: "Audio Quality",
                    value: "16kHz PCM",
                    color: const Color(0xFF2196F3),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildInfoCard(
                    icon: Icons.speed_rounded,
                    title: "Latency",
                    value: "Real-time",
                    color: const Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Server Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2139),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF6C63FF).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.cloud_upload_rounded,
                      color: Color(0xFF6C63FF),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Server Connection",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _serverUrl,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isStreaming ? const Color(0xFF4CAF50).withOpacity(0.2) : const Color(0xFFE91E63).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isStreaming ? const Color(0xFF4CAF50).withOpacity(0.5) : const Color(0xFFE91E63).withOpacity(0.5),
                      ),
                    ),
                    child: Text(
                      _isStreaming ? "LIVE" : "OFFLINE",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _isStreaming ? const Color(0xFF4CAF50) : const Color(0xFFE91E63),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}