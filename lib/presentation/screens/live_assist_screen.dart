import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_io/audio_io.dart';
import 'package:audio_session/audio_session.dart';
import '../../data/services/audio_enhancement_service.dart';
import '../../data/services/HearingProfileService.dart';
import '../../data/services/transcription_service.dart';

class LiveAssistScreen extends StatefulWidget {
  const LiveAssistScreen({super.key});

  @override
  State<LiveAssistScreen> createState() => _LiveAssistScreenState();
}

class _LiveAssistScreenState extends State<LiveAssistScreen>
    with SingleTickerProviderStateMixin {
  static const _audioChannel = MethodChannel('com.fyp_flutter/audio_route');

  final AudioEnhancementService _enhancement = AudioEnhancementService();
  final TranscriptionService _transcription = TranscriptionService();
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
  bool _captionOn = false;
  String _transcript = 'Live captions will appear here...';
  String _captionStatus = 'Idle';
  String _captionLang = 'en'; // 'en' or 'ur'

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
      // Enable hardware AEC + NS and route mic through BT headset
      try {
        await _audioChannel.invokeMethod('enableLiveAssistAudio');
        debugPrint('✅ Native audio routing enabled (MODE_IN_COMMUNICATION + BT SCO)');
      } catch (e) {
        debugPrint('⚠️ Native audio routing failed: $e');
      }

      // Optimization: If using Bluetooth Buds (not ASHA), wait 1s for SCO to stabilize
      if (_hasHeadphones && !_isHearingAid) {
        debugPrint('⏳ Waiting for Bluetooth SCO synchronization...');
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      await _audioIo.start();

      _enhancement.reset();
      _enhancement.setEnabled(_enhancementOn);

      _audioSub = _audioIo.input.listen((audioData) {
        final startTime = DateTime.now().millisecondsSinceEpoch;
        _lastChunkSize = audioData.length;

        // 1. Process through enhancement
        final enhanced = _enhancementOn && _hasProfile
            ? _enhancement.processAudio(audioData)
            : audioData;

        // 2. Feed to transcription if enabled
        if (_captionOn) {
          final pcm = Int16List(audioData.length);
          for (int i = 0; i < audioData.length; i++) {
            pcm[i] = (audioData[i] * 32767).toInt().clamp(-32768, 32767);
          }
          _transcription.feedAudioBytes(pcm.buffer.asUint8List());
        }

        // 3. Send to output immediately
        _audioIo.output.add(enhanced);

        final endTime = DateTime.now().millisecondsSinceEpoch;
        final dspTime = endTime - startTime;
        if (dspTime > 15) {
          debugPrint('⚠️ High DSP Latency: ${dspTime}ms for ${audioData.length} samples');
        }

        // 3. UI Updates (THROTTLED to ~10fps)
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastUiUpdate > 100) {
          _lastUiUpdate = now;

          // Calculate input level (RMS)
          double sumSq = 0;
          for (final s in audioData) {
            sumSq += s * s;
          }
          final rms = sqrt(sumSq / audioData.length);

          // Calculate output level (RMS)
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
            _spectrumBars[b] = (bandEnergy / max(1, end - start)).clamp(0.0, 1.0);
          }

          if (mounted) {
            setState(() {
              _inputLevel = (rms * 10).clamp(0.0, 1.0);
              _outputLevel = (outRms * 10).clamp(0.0, 1.0);
            });
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

    if (_captionOn) {
      await _transcription.stopListening();
    }

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

  Future<void> _toggleCaption(bool enabled) async {
    if (enabled) {
      final ok = await _transcription.startListening(
        useExternalSource: true,
        language: _captionLang,
        onStatusChanged: (status) {
          if (mounted) setState(() => _captionStatus = status);
        },
        onPartial: (text) {
          if (mounted) setState(() => _transcript = text);
        },
        onResult: (text) {
          if (mounted) setState(() => _transcript = text);
        },
      );
      if (ok) {
        setState(() => _captionOn = true);
      } else {
        _showSnackBar('Failed to start transcription', Colors.orange);
      }
    } else {
      await _transcription.stopListening();
      setState(() {
        _captionOn = false;
        _captionStatus = 'Idle';
        _transcript = 'Live captions will appear here...';
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

              if (_isHearingAid) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hearing, color: Colors.blueAccent, size: 14),
                      SizedBox(width: 8),
                      Text('Direct Hearing Aid Stream Active (ASHA/HAP)', 
                          style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],

              if (_hasHeadphones && !_isHearingAid) ...[
                const SizedBox(height: 12),
                _buildMicSourceSelector(),
              ],

              const SizedBox(height: 16),
              _buildCaptionToggle(),

              if (_captionOn) ...[
                const SizedBox(height: 12),
                _buildLanguageSelector(),
                const SizedBox(height: 12),
                _buildTranscriptArea(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLangChip('English', 'en'),
        const SizedBox(width: 12),
        _buildLangChip('Urdu', 'ur'),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Status: $_captionStatus',
            style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildLangChip(String label, String code) {
    bool isSelected = _captionLang == code;
    return GestureDetector(
      onTap: () {
        if (_captionLang == code) return;
        setState(() => _captionLang = code);
        if (_captionOn) {
          _toggleCaption(false).then((_) => _toggleCaption(true));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF6C63FF) : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white38,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCaptionToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2139),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.subtitles_rounded,
            color: _captionOn ? const Color(0xFF4CAF50) : Colors.white54,
            size: 20,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Live Caption',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Switch(
            value: _captionOn,
            onChanged: _isRunning ? (val) => _toggleCaption(val) : null,
            activeColor: const Color(0xFF4CAF50),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptArea() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120, maxHeight: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: Text(
          _transcript,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
            height: 1.5,
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
