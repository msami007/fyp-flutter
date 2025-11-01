import 'package:flutter/material.dart';
import '../../data/services/bluetooth_service.dart';

class ConnectDeviceScreen extends StatefulWidget {
  const ConnectDeviceScreen({super.key});

  @override
  State<ConnectDeviceScreen> createState() => _ConnectDeviceScreenState();
}

class _ConnectDeviceScreenState extends State<ConnectDeviceScreen> {
  final BluetoothServiceManager _btService = BluetoothServiceManager();
  String _deviceName = "Detecting audio device...";
  bool _initialized = false;
  bool _isSpeakerMode = false;

  @override
  void initState() {
    super.initState();
    _initializeAudioSession();
  }

  Future<void> _initializeAudioSession() async {
    try {
      final name = await _btService.initAudioSession(); // ✅ now returns selected name
      setState(() {
        _deviceName = name;
        _initialized = true;
      });
    } catch (e) {
      setState(() {
        _deviceName = "Error initializing audio: $e";
        _initialized = true;
      });
    }
  }

  Future<void> _refreshDevice() async {
    final name = await _btService.initAudioSession(); // re-run detection
    setState(() => _deviceName = name);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _isSpeakerMode = !_isSpeakerMode);
    if (_isSpeakerMode) {
      setState(() => _deviceName = "Phone Speaker");
    } else {
      final name = await _btService.initAudioSession();
      setState(() => _deviceName = name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Audio Output")),
      body: Center(
        child: _initialized
            ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.headphones, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 20),
              const Text(
                "Current Output Device:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                _deviceName,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _refreshDevice,
                icon: const Icon(Icons.refresh),
                label: const Text("Refresh Device"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _toggleSpeaker,
                icon:
                Icon(_isSpeakerMode ? Icons.volume_up : Icons.headphones),
                label:
                Text(_isSpeakerMode ? "Use Bluetooth" : "Use Speaker"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: _isSpeakerMode
                      ? Colors.orangeAccent
                      : Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                "Tip: Pair or switch Bluetooth devices from your phone’s settings.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ],
          ),
        )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
