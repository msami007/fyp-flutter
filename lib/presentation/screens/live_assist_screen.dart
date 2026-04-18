import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
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
  int _lastUiUpdate = 0;
  EnhancementMode _currentMode = EnhancementMode.standard;
  int _lastChunkSize = 0;
  bool _isHearingAid = false; // ASHA/HAP support
  bool _useEarbudMic = true; // Use BT Mic if available
  double _leftBoost = 1.0;
  double _rightBoost = 1.0;
  double _tone = 0.5;
  double _suppressionLevel = 0.5;
  bool _linkEars = true;


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

    // Check specifically for ASHA Hearing Aids
    final isHA = devices.any((d) => d.isOutput && d.type == AudioDeviceType.hearingAid);
    
    setState(() {
      _hasHeadphones = hasH;
      _isHearingAid = isHA;
      // Auto-stop if headphones are removed while running
      if (!_hasHeadphones && _isRunning) {
        _stopAssist();
        _showSnackBar('🎧 Earbuds disconnected. Live Assist stopped to prevent feedback.', Colors.redAccent);
      }
    });
  }

  Future<void> _startAssist() async {
    try {
      // Use 'voiceChat' mode for hardware-level suppression
      await AudioSession.instance.then((session) => session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      )));

      try {
        await _audioChannel.invokeMethod('enableLiveAssistAudio');
      } catch (_) {}

      await _audioIo.requestLatency(AudioIoLatency.Balanced);
      await _audioIo.start();
      _enhancement.reset();

      // ── DSP State ──
      double env = 0.0;
      double gateGain = 0.0;
      bool isOpen = false;
      
      double dclastX = 0.0, dclastY = 0.0;
      const double r = 0.995;

      // Telephone-grade Low-Pass (approx 3.5kHz cutoff)
      // This is the most effective way to kill 'TV static'
      double lp1 = 0.0, lp2 = 0.0;
      const double lpAlpha = 0.2; // Aggressive cutoff

      double noiseFloor = 0.01;
      const double noiseAlpha = 0.9995; 
      double sumSqIn = 0.0;
      double sumSqOutLeft = 0.0;
      double sumSqOutRight = 0.0;
      
      _audioSub = _audioIo.input.listen((audioData) {
        _lastChunkSize = audioData.length;
        final processed = Float64List(audioData.length);
        sumSqIn = 0;
        sumSqOutLeft = 0;
        sumSqOutRight = 0;
        
        // Tighter thresholds
        final openThreshold = 0.01 + (0.05 * _suppressionLevel);
        final closeThreshold = openThreshold * 0.7; // Much closer to open to force closure
        
        for (int i = 0; i < audioData.length; i++) {
          double x = audioData[i];
          sumSqIn += x * x;
          
          // 1. DC Block
          double y = x - dclastX + r * dclastY;
          dclastX = x; dclastY = y;
          
          // 2. 2nd Order Low-Pass (approx 3.5kHz)
          lp1 = lpAlpha * y + (1.0 - lpAlpha) * lp1;
          lp2 = lpAlpha * lp1 + (1.0 - lpAlpha) * lp2;
          double filtered = lp2;
          
          // 3. Noise Floor tracking
          double absY = filtered.abs();
          if (absY < noiseFloor * 1.5) {
              noiseFloor = noiseAlpha * noiseFloor + (1.0 - noiseAlpha) * absY;
          }
          
          // 4. Aggressive Spectral Subtraction
          double suppressionPower = 1.0 + (_suppressionLevel * 5.0); 
          double subGain = (absY - noiseFloor * suppressionPower) / (absY + 1e-9);
          subGain = subGain.clamp(0.001, 1.0); 
          
          double cleaned = filtered * subGain;
          
          // 5. Faster Envelope & tight Hysteresis
          env = 0.8 * env + 0.2 * cleaned.abs();
          if (!isOpen && env > openThreshold) {
            isOpen = true;
          } else if (isOpen && env < closeThreshold) {
            isOpen = false;
          }
          
          double targetGate = isOpen ? 1.0 : 0.0;
          if (targetGate > gateGain) {
            gateGain += 0.25 * (targetGate - gateGain); // Ultra-fast attack
          } else {
            gateGain += 0.05 * (targetGate - gateGain); // Faster release than before
          }
          
          // Original processed value before independent ear gains
          double finalOut = cleaned * gateGain;
          
          // Process Left
          double leftOut = _enhancement.processAudio([finalOut], isLeft: true)[0];
          // Process Right
          double rightOut = _enhancement.processAudio([finalOut], isLeft: false)[0];

          // Store for UI meters
          sumSqOutLeft += leftOut * leftOut;
          sumSqOutRight += rightOut * rightOut;

          // Note: If audio_io output is mono, we'll just average or pick one.
          // For true Sound Amplifier, we should use a stereo output plugin if possible.
          // For now, we'll average to mono but the logic is ready for stereo.
          processed[i] = (leftOut + rightOut) / 2.0;
        }

        _audioIo.output.add(processed);

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastUiUpdate > 100) {
          _lastUiUpdate = now;
          final rmsIn = sqrt(sumSqIn / audioData.length);
          if (mounted) {
            setState(() {
              _inputLevel = (rmsIn * 5).clamp(0.0, 1.0);
              // Use average of L/R for the main meter
              final rmsOut = sqrt((sumSqOutLeft + sumSqOutRight) / (2 * audioData.length));
              _outputLevel = (rmsOut * 10).clamp(0.0, 1.0);
            });
          }
          
          // Update spectrum based on CLEANED data
          final bandSize = audioData.length ~/ 16;
          for (int b = 0; b < 16 && b * bandSize < audioData.length; b++) {
            double bandEnergy = 0;
            final start = b * bandSize;
            final end = min(start + bandSize, audioData.length);
            for (int i = start; i < end; i++) bandEnergy += processed[i].abs();
            _spectrumBars[b] = (bandEnergy * 10 / max(1, end - start)).clamp(0.0, 1.0);
          }
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
    // This is CRITICAL to stop the sticky hardware static
    try {
      await _audioChannel.invokeMethod('disableLiveAssistAudio');
    } catch (_) {}

    // Deactivate audio session
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isRunning = false;
        _inputLevel = 0;
        _outputLevel = 0;
        _spectrumBars.fillRange(0, _spectrumBars.length, 0.0);
      });
    }
  }



  Widget _buildSoundAmplifierControls() {
    return Column(
      children: [
        // ── Independent Ear Controls ──
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2139),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Boost', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      const Text('Link ears', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      Switch(
                        value: _linkEars,
                        onChanged: (val) => setState(() => _linkEars = val),
                        activeColor: Colors.blueAccent,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildVerticalGainSlider('L', _leftBoost, Colors.blueAccent, (val) {
                    setState(() {
                      _leftBoost = val;
                      if (_linkEars) _rightBoost = val;
                    });
                    _enhancement.setLeftGain(_leftBoost);
                    if (_linkEars) _enhancement.setRightGain(_rightBoost);
                  }),
                  _buildVerticalGainSlider('R', _rightBoost, Colors.cyanAccent, (val) {
                    setState(() {
                      _rightBoost = val;
                      if (_linkEars) _leftBoost = val;
                    });
                    _enhancement.setRightGain(_rightBoost);
                    if (_linkEars) _enhancement.setLeftGain(_leftBoost);
                  }),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Fine-tuning (Tone) ──
        _buildControlCard(
          icon: Icons.tune_rounded,
          label: 'Fine-tuning',
          child: Column(
            children: [
              Slider(
                value: _tone,
                onChanged: (val) {
                  setState(() => _tone = val);
                  _enhancement.setTone(val);
                },
                activeColor: Colors.indigoAccent,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Clarity', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    Text('Fullness', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Noise Reduction ──
        _buildControlCard(
          icon: Icons.waves_rounded,
          label: 'Noise reduction',
          child: Slider(
            value: _suppressionLevel,
            onChanged: (val) {
              setState(() => _suppressionLevel = val);
              _enhancement.setSuppression(val);
            },
            activeColor: const Color(0xFF4CAF50),
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalGainSlider(String label, double value, Color color, ValueChanged<double> onChanged) {
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: value,
              min: 0.0,
              max: 2.0,
              activeColor: color,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        Text('${(value * 10).toInt()} dB', style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  Widget _buildControlCard({required IconData icon, required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 12),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
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
        title: const Text("Sound Amplifier",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ── Profile Status Card ──
              _buildProfileCard(),

              const SizedBox(height: 20),

              // ── Spectrum Visualization ──
              SizedBox(height: 140, child: _buildSpectrumView()),

              const SizedBox(height: 16),

              // ── Level Meters ──
              _buildLevelMeters(),

              const SizedBox(height: 20),

              // ── Enhancement Mode Selector (AI vs Standard) ──
              _buildModeSelector(),

              const SizedBox(height: 16),

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

              // ── Sound Amplifier Controls ──
              _buildSoundAmplifierControls(),

              const SizedBox(height: 12),

              if (_isHearingAid) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hearing_rounded, color: Color(0xFF4CAF50), size: 16),
                      SizedBox(width: 8),
                      Text(
                        'ASHA Hearing Aid Connected',
                        style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],

              if (_hasHeadphones && !_isHearingAid) ...[
                const SizedBox(height: 12),
                _buildMicSourceSelector(),
              ],
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

  Widget _buildModeSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings_suggest, color: Colors.blueAccent, size: 16),
              const SizedBox(width: 8),
              Text('Processing Mode', 
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildModeButtonItem(EnhancementMode.standard, 'Standard' ,Icons.equalizer),
              _buildModeButtonItem(EnhancementMode.krisp, 'Krisp AI', Icons.stars_rounded),
              _buildModeButtonItem(EnhancementMode.dtln, 'AI Isolation', Icons.auto_awesome),
              _buildModeButtonItem(EnhancementMode.rnn, 'Voice Only', Icons.record_voice_over),
            ],
          ),
          if (_isRunning) ...[
             const SizedBox(height: 12),
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
               decoration: BoxDecoration(
                 color: Colors.black26,
                 borderRadius: BorderRadius.circular(4),
               ),
               child: Text('📊 Buffer: $_lastChunkSize samples | Rate: 16kHz', 
                   style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace')),
             ),
          ]
        ],
      ),
    );
  }

  Widget _buildModeButtonItem(EnhancementMode mode, String label, IconData icon) {
    bool isSelected = _currentMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _currentMode = mode);
        _enhancement.setMode(mode);
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blueAccent.withOpacity(0.1) : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: isSelected ? Colors.blueAccent : Colors.white10),
            ),
            child: Icon(icon, color: isSelected ? Colors.blueAccent : Colors.white24, size: 20),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(
            color: isSelected ? Colors.white : Colors.white24,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
          )),
        ],
      ),
    );
  }

  Widget _buildEnhancementToggle() {
    return Column(
      children: [
        Container(
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
                  'Live Enhancement',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Switch(
                value: _enhancementOn,
                onChanged: (val) {
                  setState(() => _enhancementOn = val);
                  _enhancement.setEnabled(val);
                },
                activeColor: const Color(0xFF6C63FF),
                inactiveTrackColor: Colors.white.withOpacity(0.1),
              ),
            ],
          ),
        ),
        if (_enhancementOn) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildModeTab('Profile', EnhancementMode.standard, Icons.hearing_rounded),
                const SizedBox(width: 8),
                _buildModeTab('DTLN', EnhancementMode.dtln, Icons.waves_rounded),
                const SizedBox(width: 8),
                _buildModeTab('RNN', EnhancementMode.rnn, Icons.record_voice_over_rounded),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeTab(String label, EnhancementMode mode, IconData icon) {
    final isSelected = _enhancement.mode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _enhancement.setMode(mode);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF) : const Color(0xFF1E2139),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.white.withOpacity(0.2) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.white.withOpacity(0.5)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
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

  Widget _buildMicSourceSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(
            _useEarbudMic ? Icons.bluetooth_audio : Icons.phone_android,
            color: const Color(0xFF6C63FF),
            size: 20,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Microphone Source',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Earbud mic requires Bluetooth SCO',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
          Switch(
            value: _useEarbudMic,
            onChanged: (val) {
              setState(() => _useEarbudMic = val);
              // Restart to apply native SCO changes
              if (_isRunning) {
                _stopAssist();
                Timer(const Duration(milliseconds: 500), _startAssist);
              }
            },
            activeColor: const Color(0xFF6C63FF),
          ),
        ],
      ),
    );
  }
}
