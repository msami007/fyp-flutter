import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../data/services/HearingProfileService.dart';
import 'hearing_result_screen.dart';

class HearingTestScreen extends StatefulWidget {
  final String userId;
  const HearingTestScreen({super.key, required this.userId});

  @override
  State<HearingTestScreen> createState() => _HearingTestScreenState();
}

class _HearingTestScreenState extends State<HearingTestScreen> {
  final AudioPlayer _player = AudioPlayer();
  final List<int> _frequencies = [
    125, 250, 375, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 7000, 8000
  ];

  int _currentIndex = 0;
  String _currentEar = "left";
  double _volume = 0.3;
  bool _testing = false;
  bool _finished = false;

  Map<String, Map<int, double>> _results = {"left": {}, "right": {}};

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.stop);
    _startTest();
  }

  Future<void> _startTest() async {
    setState(() {
      _testing = true;
      _currentEar = "left";
      _currentIndex = 0;
      _results = {"left": {}, "right": {}};
      _volume = 0.3;
    });
    await _playTone();
  }

  Future<void> _playTone() async {
    final freq = _frequencies[_currentIndex];
    final filePath = 'audio/$freq.wav';

    try {
      await _player.stop();
      await _player.setVolume(_volume);

      // 🎧 Pan sound: -1.0 = left ear, 1.0 = right ear
      final panValue = _currentEar == "left" ? -1.0 : 1.0;
      await _player.setBalance(panValue);

      await _player.play(AssetSource(filePath));
    } catch (e) {
      debugPrint("⚠️ Failed to play $filePath: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error playing $freq Hz tone")),
      );
    }
  }

  Future<void> _heardSound() async {
    final freq = _frequencies[_currentIndex];
    _results[_currentEar]![freq] = _volume;

    await _nextStep();
  }

  Future<void> _cantHear() async {
    final freq = _frequencies[_currentIndex];
    _results[_currentEar]![freq] = 1.0; // record as max volume (no response)
    await _nextStep();
  }

  Future<void> _nextStep() async {
    if (_currentEar == "left") {
      setState(() => _currentEar = "right");
    } else {
      if (_currentIndex < _frequencies.length - 1) {
        setState(() {
          _currentEar = "left";
          _currentIndex++;
        });
      } else {
        setState(() => _finished = true);
        await _saveProfile();
        return;
      }
    }

    _volume = 0.3;
    await _playTone();
  }

  Future<void> _increaseVolume() async {
    if (_volume >= 1.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Max volume reached — marking as no response.")),
      );
      await _cantHear();
      return;
    }

    setState(() {
      _volume = min(_volume + 0.1, 1.0);
    });
    await _playTone();
  }

  Future<void> _saveProfile() async {
    final profile = {
      "leftEarGain": _results["left"]!.values.isNotEmpty
          ? _results["left"]!.values.reduce((a, b) => a + b) / _results["left"]!.length
          : 1.0,
      "rightEarGain": _results["right"]!.values.isNotEmpty
          ? _results["right"]!.values.reduce((a, b) => a + b) / _results["right"]!.length
          : 1.0,
      "frequencyMap": {
        ..._results["left"]!.map((k, v) => MapEntry("L_$k", v)),
        ..._results["right"]!.map((k, v) => MapEntry("R_$k", v)),
      },
    };

    await HearingProfileService().createProfile(widget.userId, profile);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HearingResultScreen(profile: profile),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return const Scaffold(
        body: Center(child: Text("Saving profile...")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Hearing Test")),
      body: Center(
        child: !_testing
            ? ElevatedButton(
          onPressed: _startTest,
          child: const Text("Start Hearing Test"),
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Ear: ${_currentEar.toUpperCase()}",
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text(
              "Frequency: ${_frequencies[_currentIndex]} Hz",
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            Text("Volume: ${(_volume * 100).toInt()}%"),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _heardSound,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green),
              child: const Text("✅ I can hear it"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _increaseVolume,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent),
              child: const Text("🔊 Increase Volume"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _cantHear,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent),
              child: const Text("❌ Can't Hear This Frequency"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
