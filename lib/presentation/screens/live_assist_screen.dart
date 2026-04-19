import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/services/audio_enhancement_service.dart';
import '../../data/services/native_audio_api.dart';
import '../../data/services/HearingProfileService.dart';

class LiveAssistScreen extends StatefulWidget {
  const LiveAssistScreen({super.key});

  @override
  State<LiveAssistScreen> createState() => _LiveAssistScreenState();
}

class _LiveAssistScreenState extends State<LiveAssistScreen>
    with SingleTickerProviderStateMixin {
  
  final AudioEnhancementService _enhancement = AudioEnhancementService();
  StreamSubscription<Set<AudioDevice>>? _devicesSub;

  bool _isRunning = false;
  bool _enhancementOn = true;
  bool _hasProfile = false;
  bool _hasHeadphones = false;
  bool _isInitializing = false;
  String _profileInfo = '';
  double _inputLevel = 0.0;
  double _outputLevel = 0.0;
  
  bool _isHearingAid = false;
  bool _useEarbudMic = true;
  String _earbudName = 'Earbud Mic';
  String _phoneName = 'Phone Mic';
  double _leftBoost = 1.0;
  double _rightBoost = 1.0;
  double _masterVolume = 1.0;
  double _tone = 0.5;
  double _suppressionLevel = 0.5;
  bool _linkEars = true;

  late AnimationController _pulseController;
  Timer? _levelTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _isInitializing = true);
    
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _showSnackBar('🎙️ Microphone permission is required.', Colors.orange);
      setState(() => _isInitializing = false);
      return;
    }

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

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      final devices = await session.getDevices();
      _checkHeadphones(devices);
      _devicesSub = session.devicesStream.listen(_checkHeadphones);
    } catch (e) {
      debugPrint('Error setting up audio session: $e');
    }

    setState(() => _isInitializing = false);
  }

  void _checkHeadphones(Set<AudioDevice> devices) {
    if (!mounted) return;
    
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

    final isHA = devices.any((d) => d.isOutput && d.type == AudioDeviceType.hearingAid);
    
    String tempEarbudName = 'Earbud Mic';
    String tempPhoneName = 'Phone Mic';
    for (var d in devices) {
      if (d.isInput) {
        if (d.type == AudioDeviceType.bluetoothSco || d.type == AudioDeviceType.wiredHeadset || d.type == AudioDeviceType.bluetoothA2dp) {
          tempEarbudName = d.name;
        } else if (d.type == AudioDeviceType.builtInMic || d.type == AudioDeviceType.telephony) {
          tempPhoneName = d.name;
        }
      }
    }

    setState(() {
      _hasHeadphones = hasH;
      _isHearingAid = isHA;
      _earbudName = tempEarbudName;
      _phoneName = tempPhoneName;
      if (!_hasHeadphones && _isRunning) {
        _stopAssist();
        _showSnackBar('🎧 Earbuds disconnected. Stopped to prevent feedback.', Colors.redAccent);
      }
    });
  }

  Future<void> _startAssist() async {
    try {
      if (await Permission.microphone.request().isGranted) {
        NativeAudioApi.startAudio(); 
        setState(() => _isRunning = true);
        _startLevelTimer();
        _pulseController.repeat(reverse: true);
        _showSnackBar("Live Assist Started", const Color(0xFF4CAF50));
      } else {
        _showSnackBar("Microphone access denied", Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar("System Error: $e", Colors.redAccent);
    }
  }

  void _stopAssist() {
    try {
      NativeAudioApi.stopAudio();
      _levelTimer?.cancel();
      _pulseController.stop();
      setState(() {
        _isRunning = false;
        _inputLevel = 0;
        _outputLevel = 0;
      });
    } catch (e) {
      debugPrint("Stop Error: $e");
    }
  }

  void _startLevelTimer() {
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_isRunning) {
        setState(() {
          _inputLevel = NativeAudioApi.getInputLevel();
          _outputLevel = NativeAudioApi.getOutputLevel();
        });
      }
    });
  }

  @override
  void dispose() {
    _stopAssist();
    _devicesSub?.cancel();
    _pulseController.dispose();
    _enhancement.dispose();
    _levelTimer?.cancel();
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
              _buildProfileCard(),
              const SizedBox(height: 24),
              _buildLevelMeters(),
              const SizedBox(height: 24),
              _buildEnhancementToggle(),
              const SizedBox(height: 20),
              _buildMainButton(),
              const SizedBox(height: 12),
              Text(
                _isRunning
                    ? 'Audio is being enhanced in real-time'
                    : 'Tap Start to begin hearing assistance',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              _buildSoundAmplifierControls(),
              if (_isHearingAid) ...[
                const SizedBox(height: 12),
                _buildAshaIndicator(),
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

  Widget _buildLevelMeters() {
    return Column(
      children: [
        _buildProgressBar("MIC INPUT", _inputLevel, Colors.cyanAccent),
        const SizedBox(height: 16),
        _buildProgressBar("AMP OUTPUT", _outputLevel, Colors.greenAccent),
      ],
    );
  }

  Widget _buildProgressBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            Text('${(value * 100).toInt()}%', style: TextStyle(color: color.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            backgroundColor: Colors.white.withOpacity(0.05),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _hasProfile ? const Color(0xFF4CAF50).withOpacity(0.3) : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _hasProfile ? Icons.hearing_rounded : Icons.hearing_disabled,
            color: _hasProfile ? const Color(0xFF4CAF50) : Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasProfile ? 'Hearing Profile Loaded' : 'No Hearing Profile',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                ),
                Text(
                  _hasProfile ? 'Gain: $_profileInfo' : 'Take a hearing test first',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundAmplifierControls() {
    return Column(
      children: [
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
                  Switch(
                    value: _linkEars,
                    onChanged: (val) => setState(() => _linkEars = val),
                    activeColor: Colors.blueAccent,
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildVerticalGainSlider('L', _leftBoost, Colors.blueAccent, (val) {
                    setState(() { _leftBoost = val; if (_linkEars) _rightBoost = val; });
                    _enhancement.setLeftGain(_leftBoost);
                    if (_linkEars) _enhancement.setRightGain(_rightBoost);
                  }),
                  _buildVerticalGainSlider('R', _rightBoost, Colors.cyanAccent, (val) {
                    setState(() { _rightBoost = val; if (_linkEars) _leftBoost = val; });
                    _enhancement.setRightGain(_rightBoost);
                    if (_linkEars) _enhancement.setLeftGain(_leftBoost);
                  }),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildControlCard(
          icon: Icons.volume_up_rounded,
          label: 'Master Volume',
          child: Slider(
            value: _masterVolume,
            min: 0.0,
            max: 5.0,
            onChanged: (val) { setState(() => _masterVolume = val); _enhancement.setMasterVolume(val); },
            activeColor: Colors.deepOrangeAccent,
          ),
        ),
        const SizedBox(height: 20),
        _buildControlCard(
          icon: Icons.tune_rounded,
          label: 'Fine-tuning',
          child: Slider(
            value: _tone,
            onChanged: (val) { setState(() => _tone = val); _enhancement.setTone(val); },
            activeColor: Colors.indigoAccent,
          ),
        ),
        const SizedBox(height: 20),
        _buildControlCard(
          icon: Icons.waves_rounded,
          label: 'Noise reduction',
          child: Slider(
            value: _suppressionLevel,
            onChanged: (val) { setState(() => _suppressionLevel = val); _enhancement.setSuppression(val); },
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
          height: 160,
          child: RotatedBox( quarterTurns: 3, child: Slider(value: value, min: 0.0, max: 10.0, activeColor: color, onChanged: onChanged)),
        ),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildControlCard({required IconData icon, required String label, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF1E2139), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: Colors.blueAccent, size: 20), const SizedBox(width: 12), Text(label, style: const TextStyle(color: Colors.white, fontSize: 14))]),
          child,
        ],
      ),
    );
  }

  Widget _buildEnhancementToggle() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF1E2139), borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              const Icon(Icons.auto_fix_high, color: Color(0xFF6C63FF)),
              const SizedBox(width: 12),
              const Expanded(child: Text('Live Enhancement', style: TextStyle(color: Colors.white))),
              Switch(value: _enhancementOn, onChanged: (val) { setState(() => _enhancementOn = val); _enhancement.setEnabled(val); }, activeColor: const Color(0xFF6C63FF)),
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
                const SizedBox(width: 12),
                _buildModeTab('DTLN', EnhancementMode.dtln, Icons.waves_rounded),
                const SizedBox(width: 12),
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
      onTap: () => setState(() => _enhancement.setMode(mode)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: isSelected ? const Color(0xFF6C63FF) : const Color(0xFF1E2139), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [Icon(icon, size: 16, color: Colors.white), const SizedBox(width: 8), Text(label, style: const TextStyle(color: Colors.white))]),
      ),
    );
  }

  Widget _buildMainButton() {
    if (_isInitializing) return const Center(child: CircularProgressIndicator());
    if (!_hasHeadphones) return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Text('Connect headphones to begin', style: TextStyle(color: Colors.redAccent)));
    
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isRunning ? _stopAssist : _startAssist,
        icon: Icon(_isRunning ? Icons.stop_rounded : Icons.hearing_rounded),
        label: Text(_isRunning ? 'Stop Assist' : 'Start Live Assist'),
        style: ElevatedButton.styleFrom(backgroundColor: _isRunning ? Colors.redAccent : const Color(0xFF6C63FF), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
    );
  }

  Widget _buildAshaIndicator() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: const Row(children: [Icon(Icons.hearing, color: Colors.green, size: 16), SizedBox(width: 8), Text('Hearing Aid Connected', style: TextStyle(color: Colors.green, fontSize: 12))]),
    );
  }

  Widget _buildMicSourceSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E2139), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(_useEarbudMic ? Icons.bluetooth_audio : Icons.phone_android, color: const Color(0xFF6C63FF)),
          const SizedBox(width: 12),
          Expanded(child: Text('Use ${_useEarbudMic ? _earbudName : _phoneName}', style: const TextStyle(color: Colors.white))),
          Switch(value: _useEarbudMic, onChanged: (val) => setState(() => _useEarbudMic = val), activeColor: const Color(0xFF6C63FF)),
        ],
      ),
    );
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }
}
