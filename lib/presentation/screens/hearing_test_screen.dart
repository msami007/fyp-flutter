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

class _HearingTestScreenState extends State<HearingTestScreen> with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final List<int> _frequencies = [
    250, 500, 1000, 2000, 4000, 8000
  ];

  int _currentIndex = 0;
  String _currentEar = "left";
  double _volume = 0.3;
  bool _testing = false;
  bool _finished = false;
  late AnimationController _pulseController;

  Map<String, Map<int, double>> _results = {"left": {}, "right": {}};

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.stop);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
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

      final panValue = _currentEar == "left" ? -1.0 : 1.0;
      await _player.setBalance(panValue);

      await _player.play(AssetSource(filePath));
    } catch (e) {
      debugPrint("⚠️ Failed to play $filePath: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error playing $freq Hz tone"),
          behavior: SnackBarBehavior.floating,
        ),
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
    _results[_currentEar]![freq] = 1.0;
    await _nextStep();
  }

  Future<void> _nextStep() async {
    if (_currentIndex < _frequencies.length - 1) {
      // Still more frequencies for the current ear
      setState(() {
        _currentIndex++;
      });
    } else {
      // Finished all frequencies for the current ear
      if (_currentEar == "left") {
        // Switch to the right ear and reset frequency index
        setState(() {
          _currentEar = "right";
          _currentIndex = 0;
        });
      } else {
        // Finished both ears
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
        const SnackBar(
          content: Text("Max volume reached — marking as no response."),
          behavior: SnackBarBehavior.floating,
        ),
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

  double get _progress {
    int currentStep = (_currentEar == "left" ? 0 : _frequencies.length) + _currentIndex;
    return currentStep / (_frequencies.length * 2);
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E27),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                color: Color(0xFF6C63FF),
                strokeWidth: 3,
              ),
              const SizedBox(height: 24),
              Text(
                "Analyzing your results...",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "HEARING TEST",
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
      ),
      body: SafeArea(
        child: !_testing ? _buildStartScreen() : _buildTestScreen(),
      ),
    );
  }

  Widget _buildStartScreen() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6C63FF).withOpacity(0.3),
                  const Color(0xFF3F3D56).withOpacity(0.3),
                ],
              ),
            ),
            child: const Icon(
              Icons.headset_rounded,
              size: 64,
              color: Color(0xFF6C63FF),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            "Ready for Your\nHearing Test?",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Find a quiet place and put on your headphones.\nWe'll test both ears across different frequencies.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.7),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _startTest,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                "Start Test",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestScreen() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Progress section with additional info
            _buildProgressSection(),

            const SizedBox(height: 20),

            // Main test visualization area
            _buildTestVisualization(),

            const SizedBox(height: 20),

            // Frequency and volume info
            _buildFrequencyInfo(),

            const SizedBox(height: 20),

            // Compact action buttons
            _buildCompactActionButtons(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
                  minHeight: 8,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              "${(_progress * 100).toInt()}%",
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6C63FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Test Progress",
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              "${_currentIndex + 1} of ${_frequencies.length} frequencies",
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTestVisualization() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Ear indicator with animation
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Outer pulse ring
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF6C63FF).withOpacity(0.2 * _pulseController.value),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                  // Middle ring
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF6C63FF).withOpacity(0.4 * _pulseController.value),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                  // Main ear indicator
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1E2139),
                      border: Border.all(
                        color: const Color(0xFF6C63FF),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C63FF).withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.hearing_rounded,
                      size: 48,
                      color: const Color(0xFF6C63FF),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // Ear label with instructions
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF6C63FF).withOpacity(0.5),
                  ),
                ),
                child: Text(
                  "LISTENING WITH ${_currentEar.toUpperCase()} EAR",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6C63FF),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Focus on the tone in your ${_currentEar} ear",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFrequencyInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoItem(
                icon: Icons.graphic_eq_rounded,
                label: "Frequency",
                value: "${_frequencies[_currentIndex]} Hz",
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.1),
              ),
              _buildInfoItem(
                icon: Icons.volume_up_rounded,
                label: "Volume Level",
                value: "${(_volume * 100).toInt()}%",
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Volume visualization
          Container(
            height: 8,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: (_volume * 100).round(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF4A44B5)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Expanded(
                  flex: 100 - (_volume * 100).round(),
                  child: const SizedBox(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: const Color(0xFF6C63FF),
          size: 20,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactActionButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Can't Hear Button
          _buildCompactButton(
            icon: Icons.close_rounded,
            label: "Can't Hear",
            color: const Color(0xFFE91E63),
            onPressed: _cantHear,
          ),

          // Vertical divider
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withOpacity(0.1),
          ),

          // Increase Volume Button
          _buildCompactButton(
            icon: Icons.volume_up_rounded,
            label: "Louder",
            color: const Color(0xFF2196F3),
            onPressed: _increaseVolume,
          ),

          // Vertical divider
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withOpacity(0.1),
          ),

          // Can Hear Button
          _buildCompactButton(
            icon: Icons.check_rounded,
            label: "Can Hear",
            color: const Color(0xFF4CAF50),
            onPressed: _heardSound,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _player.dispose();
    super.dispose();
  }
}