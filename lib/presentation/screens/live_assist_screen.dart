import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_io/audio_io.dart';
import 'package:audio_session/audio_session.dart';
import '../../data/services/audio_enhancement_service.dart';
import '../../data/services/HearingProfileService.dart';

class LiveAssistScreen extends StatefulWidget {
  const LiveAssistScreen({super.key});

  @override
  State<LiveAssistScreen> createState() => _LiveAssistScreenState();
}

class _LiveAssistScreenState extends State<LiveAssistScreen>
    with SingleTickerProviderStateMixin {
  static const _audioChannel = MethodChannel('com.fyp_flutter/audio_route');

  final AudioEnhancementService _enhancement = AudioEnhancementService();
  late AudioIo _audioIo;
  StreamSubscription? _audioSub;
  StreamSubscription<Set<AudioDevice>>? _devicesSub;

  bool _isRunning = false;
  bool _isInitializing = true;
  bool _enhancementOn = true;
  bool _hasProfile = false;
  bool _hasHeadphones = false;
  String _profileInfo = '';
  double _inputLevel = 0.0;
  double _outputLevel = 0.0;
  final List<double> _spectrumBars = List.filled(16, 0.0);

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isInitializing = true);
    _audioIo = AudioIo.instance;

    final profileOk = await _enhancement.initialize();
    _hasProfile = profileOk;

    if (profileOk) {
      final profile = await HearingProfileService().getLocalProfile();
      if (profile != null) {
        final leftGain = (profile['leftEarGain'] as num?)?.toStringAsFixed(2) ?? '?';
        final rightGain = (profile['rightEarGain'] as num?)?.toStringAsFixed(2) ?? '?';
        _profileInfo = 'L: $leftGain  R: $rightGain';
      }
    }

    _enhancement.setEnabled(_enhancementOn);

    // ── Setup Audio Session & Headphone Detection ──
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      
      // Initial state
      final devices = await session.getDevices();
      _checkHeadphones(devices);

      // Listen for plug/unplug events
      _devicesSub = session.devicesStream.listen((devs) {
        _checkHeadphones(devs);
      });
    } catch (e) {
      debugPrint('Error setting up audio session: $e');
    }

    setState(() => _isInitializing = false);
  }

  void _checkHeadphones(Set<AudioDevice> devices) {
    if (!mounted) return;
    
    // Look for any connected output device that is a headset/earpiece
    final hasH = devices.any((d) => 
      d.isOutput && (
        d.type == AudioDeviceType.wiredHeadset ||
        d.type == AudioDeviceType.wiredHeadphones ||
        d.type == AudioDeviceType.bluetoothA2dp ||
        d.type == AudioDeviceType.bluetoothSco ||
        d.type == AudioDeviceType.bluetoothLe ||
        d.type == AudioDeviceType.usbAudio ||
        d.type == AudioDeviceType.hearingAid
      )
    );

    setState(() {
      _hasHeadphones = hasH;
      // Auto-stop if headphones are removed while running
      if (!_hasHeadphones && _isRunning) {
        _stopAssist();
        _showSnackBar('🎧 Earbuds disconnected. Live Assist stopped to prevent feedback.', Colors.redAccent);
      }
    });
  }

  Future<void> _startAssist() async {
    try {
      // Enable hardware AEC + NS and route mic through BT headset
      try {
        await _audioChannel.invokeMethod('enableLiveAssistAudio');
        debugPrint('✅ Native audio routing enabled (MODE_IN_COMMUNICATION + BT SCO)');
      } catch (e) {
        debugPrint('⚠️ Native audio routing failed: $e');
      }

      try {
        await _audioIo.requestLatency(AudioIoLatency.Realtime);
      } on MissingPluginException catch (_) {
        debugPrint('requestLatency not implemented on this platform, skipping');
      }

      await _audioIo.start();

      _enhancement.reset();
      _enhancement.setEnabled(_enhancementOn);

      _audioSub = _audioIo.input.listen((audioData) {
        // Calculate input level
        double sumSq = 0;
        for (final s in audioData) {
          sumSq += s * s;
        }
        final rms = sqrt(sumSq / audioData.length);

        // Process through enhancement
        final enhanced = _enhancementOn && _hasProfile
            ? _enhancement.processAudio(audioData)
            : audioData;

        // Calculate output level
        double outSumSq = 0;
        for (final s in enhanced) {
          outSumSq += s * s;
        }
        final outRms = sqrt(outSumSq / enhanced.length);

        // Update spectrum visualization (simple 16-band)
        final bandSize = enhanced.length ~/ 16;
        for (int b = 0; b < 16 && b * bandSize < enhanced.length; b++) {
          double bandEnergy = 0;
          final start = b * bandSize;
          final end = min(start + bandSize, enhanced.length);
          for (int i = start; i < end; i++) {
            bandEnergy += enhanced[i].abs();
          }
          _spectrumBars[b] = (bandEnergy / (end - start)).clamp(0.0, 1.0);
        }

        // Send to output
        _audioIo.output.add(enhanced);

        // Update UI periodically (not every frame)
        if (mounted) {
          setState(() {
            _inputLevel = (rms * 5).clamp(0.0, 1.0);
            _outputLevel = (outRms * 5).clamp(0.0, 1.0);
          });
        }
      });

      setState(() => _isRunning = true);
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        _showSnackBar('Please grant microphone permission', Colors.orange);
      } else {
        _showSnackBar('Audio error: ${e.message}', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    }
  }

  Future<void> _stopAssist() async {
    _audioSub?.cancel();
    _audioSub = null;
    try {
      await _audioIo.stop();
    } catch (_) {}

    // Disable native audio routing (reset MODE + stop BT SCO)
    try {
      await _audioChannel.invokeMethod('disableLiveAssistAudio');
      debugPrint('✅ Native audio routing disabled');
    } catch (e) {
      debugPrint('⚠️ Native audio routing disable failed: $e');
    }

    _enhancement.reset();
    if (mounted) {
      setState(() {
        _isRunning = false;
        _inputLevel = 0;
        _outputLevel = 0;
        _spectrumBars.fillRange(0, _spectrumBars.length, 0.0);
      });
    }
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _stopAssist();
    _devicesSub?.cancel();
    _pulseController.dispose();
    _enhancement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Live Assist",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ── Profile Status Card ──
              _buildProfileCard(),

              const SizedBox(height: 20),

              // ── Spectrum Visualization ──
              Expanded(child: _buildSpectrumView()),

              const SizedBox(height: 16),

              // ── Level Meters ──
              _buildLevelMeters(),

              const SizedBox(height: 20),

              // ── Enhancement Toggle ──
              _buildEnhancementToggle(),

              const SizedBox(height: 20),

              // ── Start/Stop Button ──
              _buildMainButton(),

              const SizedBox(height: 8),

              Text(
                _isRunning
                    ? 'Audio is being enhanced in real-time'
                    : 'Tap Start to begin hearing assistance',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hasProfile
              ? const Color(0xFF4CAF50).withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (_hasProfile
                      ? const Color(0xFF4CAF50)
                      : Colors.orange)
                  .withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _hasProfile ? Icons.hearing_rounded : Icons.hearing_disabled,
              color: _hasProfile ? const Color(0xFF4CAF50) : Colors.orange,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasProfile ? 'Hearing Profile Loaded' : 'No Hearing Profile',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _hasProfile
                      ? 'Gain: $_profileInfo'
                      : 'Take a hearing test first for personalized enhancement',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpectrumView() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.equalizer, color: Color(0xFF6C63FF), size: 18),
              const SizedBox(width: 8),
              Text(
                'Frequency Spectrum',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_isRunning)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) => Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        const Color(0xFF4CAF50),
                        const Color(0xFF4CAF50).withOpacity(0.3),
                        _pulseController.value,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(16, (i) {
                final height = _isRunning ? _spectrumBars[i] : 0.05;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      height: double.infinity,
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: height.clamp(0.05, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                const Color(0xFF6C63FF),
                                Color.lerp(
                                  const Color(0xFF6C63FF),
                                  const Color(0xFFE91E63),
                                  height,
                                )!,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('125 Hz',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 10)),
              Text('4 kHz',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 10)),
              Text('8 kHz',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.3), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLevelMeters() {
    return Row(
      children: [
        Expanded(child: _buildLevelBar('INPUT', _inputLevel, const Color(0xFF6C63FF))),
        const SizedBox(width: 12),
        Expanded(child: _buildLevelBar('OUTPUT', _outputLevel, const Color(0xFF4CAF50))),
      ],
    );
  }

  Widget _buildLevelBar(String label, double level, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: level,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancementToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_fix_high,
            color: _enhancementOn
                ? const Color(0xFF6C63FF)
                : Colors.white.withOpacity(0.4),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Profile Enhancement',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            value: _enhancementOn,
            onChanged: _hasProfile
                ? (val) {
                    setState(() => _enhancementOn = val);
                    _enhancement.setEnabled(val);
                  }
                : null,
            activeColor: const Color(0xFF6C63FF),
            inactiveTrackColor: Colors.white.withOpacity(0.1),
          ),
        ],
      ),
    );
  }

  Widget _buildMainButton() {
    if (_isInitializing) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF6C63FF),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (!_hasHeadphones) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.headphones_outlined, color: Colors.redAccent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Connect Bluetooth earbuds or wired headphones to use Live Assist without feedback echo.',
                style: TextStyle(
                  color: Colors.red.shade200, 
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isRunning ? _stopAssist : _startAssist,
        icon: Icon(_isRunning ? Icons.stop_rounded : Icons.hearing_rounded,
            size: 24),
        label: Text(
          _isRunning ? 'Stop Assist' : 'Start Live Assist',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isRunning
              ? const Color(0xFFE91E63)
              : const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
    );
  }
}
