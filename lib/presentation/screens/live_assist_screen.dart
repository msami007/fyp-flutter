import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/services/audio_enhancement_service.dart';
import '../../data/services/native_audio_api.dart';
import '../../data/services/HearingProfileService.dart';
import '../../data/services/transcription_service.dart';
import '../../data/services/conversation_history_service.dart';

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

  // ── Live Caption State ──
  final TranscriptionService _transcription = TranscriptionService();
  final ConversationHistoryService _historyService = ConversationHistoryService();
  bool _showCaptions = false;
  String _selectedLang = 'en'; // Default to English
  String _captionText = '';
  String _partialText = '';
  final List<String> _captionHistory = [];
  final ScrollController _captionScrollController = ScrollController();
  Timer? _captionTimer;

  bool _isCaptionLoading = false;
  bool _isCaptionCollapsed = false;
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

  Future<void> _startCaptionPipeline() async {
    await _transcription.startListening(
      onPartial: (text) {
        if (!mounted) return;
        setState(() => _partialText = text);
        _scrollCaptionsToBottom();
      },
      onResult: (text) {
        if (!mounted || text.isEmpty) return;
        setState(() {
          _captionHistory.add(text);
          if (_captionHistory.length > 20) _captionHistory.removeAt(0);
          _captionText = _captionHistory.join('\n');
          _partialText = '';
        });
        _scrollCaptionsToBottom();
      },
      onStatusChanged: (status) {
        if (!mounted) return;
        debugPrint('🎤 Caption: $status');
        if (status.contains('listening')) {
          setState(() => _isCaptionLoading = false);
        }
      },
      language: _selectedLang,
      useExternalSource: true,
    );

    // Poll processed audio from C++ every 100ms and feed to Vosk
    _captionTimer?.cancel();
    _captionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final bytes = NativeAudioApi.pullCaptionPcm16();
      if (bytes != null && bytes.isNotEmpty) {
        _transcription.feedAudioBytes(bytes);
      }
    });
    debugPrint('✅ Caption pipeline started (processed audio → Vosk)');
  }

  Future<void> _stopCaptionPipeline() async {
    _captionTimer?.cancel();
    _captionTimer = null;
    await _transcription.stopListening();
    debugPrint('⏹️ Caption pipeline stopped');
  }

  Future<void> _toggleCaptions() async {
    setState(() {
      _showCaptions = !_showCaptions;
      if (_showCaptions) {
        _isCaptionCollapsed = false; // Always expand when first turned on
        _isCaptionLoading = true;
      }
    });
    
    if (_showCaptions && _isRunning) {
      await _startCaptionPipeline();
      _showSnackBar('Live Captions ON', const Color(0xFF6C63FF));
    } else {
      await _stopCaptionPipeline();
      _isCaptionLoading = false;
      _showSnackBar('Live Captions OFF', Colors.grey);
    }
  }

  void _scrollCaptionsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_captionScrollController.hasClients) {
        _captionScrollController.animateTo(
          _captionScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
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
        // Auto-start captions if toggle is on
        if (_showCaptions) _startCaptionPipeline();
      } else {
        _showSnackBar("Microphone access denied", Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar("System Error: $e", Colors.redAccent);
    }
  }

  Future<void> _stopAssist({bool silent = false}) async {
    try {
      NativeAudioApi.stopAudio();
      _levelTimer?.cancel();
      _pulseController.stop();
      // Stop captions when audio stops
      await _stopCaptionPipeline();
      
      final String fullTranscript = _captionText.isNotEmpty 
          ? _captionText + (_partialText.isNotEmpty ? '\n$_partialText' : '')
          : _partialText;

      if (!silent && mounted) {
        setState(() {
          _isRunning = false;
          _inputLevel = 0;
          _outputLevel = 0;
          _partialText = '';
        });

        if (_showCaptions && fullTranscript.trim().isNotEmpty) {
          _promptToSaveTranscription(fullTranscript.trim());
        }
      } else {
        _isRunning = false;
      }
    } catch (e) {
      debugPrint("Stop Error: $e");
    }
  }

  Future<void> _promptToSaveTranscription(String transcript) async {
    final bool? save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2139),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Save Live Captions?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Would you like to save the captions generated during this session, or discard them?',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Discard', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (save == true && mounted) {
      final TextEditingController nameController = TextEditingController(
        text: 'Assist Transcript ${DateTime.now().day}/${DateTime.now().month} ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}'
      );

      final String? result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E2139),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Save Transcription', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Give your transcript a name for easy search later.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  hintText: 'Enter name...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, nameController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Save Transcript', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (result != null && result.trim().isNotEmpty && mounted) {
        await _historyService.saveConversation(
          title: result.trim(),
          transcript: transcript,
          language: _selectedLang,
          durationSeconds: 0,
          modelUsed: 'whisper',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Saved to history ✓"),
              backgroundColor: const Color(0xFF4CAF50),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        
        setState(() {
          _captionHistory.clear();
          _captionText = '';
        });
      }
    } else {
      // Discarded or Cancelled
      setState(() {
        _captionHistory.clear();
        _captionText = '';
      });
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
    _stopAssist(silent: true);
    _devicesSub?.cancel();
    _pulseController.dispose();
    _enhancement.dispose();
    _levelTimer?.cancel();
    _captionScrollController.dispose();
    super.dispose();
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        backgroundColor: color.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        width: 200,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "LIVE ASSIST",
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
        actions: [
          if (_hasHeadphones && !_isHearingAid)
            IconButton(
              onPressed: () => setState(() => _useEarbudMic = !_useEarbudMic),
              icon: Icon(
                _useEarbudMic ? Icons.bluetooth_audio_rounded : Icons.phone_android_rounded,
                color: _useEarbudMic ? const Color(0xFF6C63FF) : Colors.white38,
              ),
              tooltip: 'Mic Source',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  children: [
                    _buildCompactDiagnosticHeader(),
                    const SizedBox(height: 24),
                    
                    _buildMainActionButton(),
                    const SizedBox(height: 32),
                    
                    _buildSectionTitle('ENHANCEMENT ENGINE'),
                    const SizedBox(height: 16),
                    _buildEnhancementEngineCard(),
                    
                    const SizedBox(height: 32),
                    _buildSectionTitle('PERFORMANCE TUNING'),
                    const SizedBox(height: 16),
                    _buildUnifiedControlsCard(),
                    
                    if (_isHearingAid) ...[
                      const SizedBox(height: 24),
                      _buildAshaIndicator(),
                    ],
                    
                    if (_showCaptions) const SizedBox(height: 200),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            if (_showCaptions && _isRunning) _buildCaptionOverlay(),
          ],
        ),
      ),
      floatingActionButton: (!_showCaptions && _isRunning) ? FloatingActionButton(
        onPressed: _toggleCaptions,
        backgroundColor: const Color(0xFF6C63FF),
        child: const Icon(Icons.closed_caption_rounded, color: Colors.white),
      ) : null,
    );
  }

  Widget _buildCompactDiagnosticHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF131932),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.03)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _hasProfile ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                color: _hasProfile ? const Color(0xFF4CAF50) : Colors.orange,
                size: 16,
              ),
              const SizedBox(width: 10),
              Text(
                _hasProfile ? 'Clinical Profile: Active' : 'Profile: Uncalibrated',
                style: TextStyle(
                  color: _hasProfile ? const Color(0xFF4CAF50) : Colors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (_hasProfile)
                Text(
                  _profileInfo,
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCompactMeter("IN", _inputLevel, Colors.cyanAccent),
          const SizedBox(height: 12),
          _buildCompactMeter("OUT", _outputLevel, const Color(0xFF6C63FF)),
        ],
      ),
    );
  }

  Widget _buildUnifiedControlsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131932),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          // Boost Section (The vertical sliders)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Channel Boost', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                _buildLinkToggle(),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildVerticalSlider('LEFT', _leftBoost, Colors.cyanAccent, (val) {
                setState(() { _leftBoost = val; if (_linkEars) _rightBoost = val; });
                _enhancement.setLeftGain(_leftBoost);
                if (_linkEars) _enhancement.setRightGain(_rightBoost);
              }),
              _buildVerticalSlider('RIGHT', _rightBoost, const Color(0xFF6C63FF), (val) {
                setState(() { _rightBoost = val; if (_linkEars) _leftBoost = val; });
                _enhancement.setRightGain(_rightBoost);
                if (_linkEars) _enhancement.setLeftGain(_leftBoost);
              }),
            ],
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Divider(color: Colors.white10),
          ),
          
          // Sliders Section
          _buildMasterSliderRow('Volume', _masterVolume, 0.0, 5.0, Icons.volume_up_rounded, const Color(0xFF4CAF50), (val) {
            setState(() => _masterVolume = val);
            _enhancement.setMasterVolume(val);
          }),
          _buildMasterSliderRow('Clarity', _tone, 0.0, 1.0, Icons.graphic_eq_rounded, Colors.orangeAccent, (val) {
            setState(() => _tone = val);
            _enhancement.setTone(val);
          }),
          _buildMasterSliderRow('Suppression', _suppressionLevel, 0.0, 1.0, Icons.waves_rounded, Colors.cyanAccent, (val) {
            setState(() => _suppressionLevel = val);
            _enhancement.setSuppression(val);
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLinkToggle() {
    return GestureDetector(
      onTap: () => setState(() => _linkEars = !_linkEars),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _linkEars ? const Color(0xFF6C63FF).withOpacity(0.1) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(_linkEars ? Icons.link_rounded : Icons.link_off_rounded, color: _linkEars ? const Color(0xFF6C63FF) : Colors.white24, size: 14),
            const SizedBox(width: 6),
            Text(
              _linkEars ? 'LINKED' : 'INDEPENDENT',
              style: TextStyle(color: _linkEars ? const Color(0xFF6C63FF) : Colors.white24, fontSize: 9, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterSliderRow(String label, double value, double min, double max, IconData icon, Color color, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color.withOpacity(0.5), size: 14),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(
                '${((value - min) / (max - min) * 100).toInt()}%',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: color,
              inactiveTrackColor: color.withOpacity(0.05),
              thumbColor: Colors.white,
              overlayColor: color.withOpacity(0.1),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMeter(String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, fontWeight: FontWeight.w900),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.05),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 30,
          child: Text(
            '${(value * 100).toInt()}%',
            textAlign: TextAlign.end,
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildMainActionButton() {
    if (_isInitializing) return const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
    
    if (!_hasHeadphones) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
        ),
        child: const Row(
          children: [
            Icon(Icons.headset_off_rounded, color: Colors.redAccent),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Connect earbuds to start assist',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _isRunning ? _stopAssist : _startAssist,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: _isRunning ? Colors.redAccent : const Color(0xFF6C63FF),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: (_isRunning ? Colors.black : const Color(0xFF6C63FF)).withOpacity(_isRunning ? 0.2 : 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isRunning ? Icons.stop_circle_rounded : Icons.play_circle_filled_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              _isRunning ? 'STOP ASSISTANCE' : 'START LIVE ASSIST',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancementEngineCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF131932),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6C63FF), size: 20),
              const SizedBox(width: 12),
              const Text(
                'AI Processing',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: _enhancementOn,
                  onChanged: (val) {
                    setState(() => _enhancementOn = val);
                    _enhancement.setEnabled(val);
                  },
                  activeColor: const Color(0xFF6C63FF),
                ),
              ),
            ],
          ),
          if (_enhancementOn) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildModeButton('STANDARD', EnhancementMode.standard)),
                const SizedBox(width: 8),
                Expanded(child: _buildModeButton('DTLN', EnhancementMode.dtln)),
                const SizedBox(width: 8),
                Expanded(child: _buildModeButton('RNN', EnhancementMode.rnn)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeButton(String label, EnhancementMode mode) {
    final isSelected = _enhancement.mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _enhancement.setMode(mode)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF).withOpacity(0.2) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.transparent,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF6C63FF) : Colors.white24,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAshaIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.2)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hearing_rounded, color: Color(0xFF4CAF50), size: 18),
          SizedBox(width: 12),
          Text(
            'HEARING AID ACTIVE',
            style: TextStyle(color: Color(0xFF4CAF50), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptionOverlay() {
    final screenHeight = MediaQuery.of(context).size.height;
    final expandedHeight = screenHeight / 3;
    
    String placeholder = _isCaptionLoading ? 'Setting up Whisper...' : 'Listening...';
    final displayText = _captionText.isNotEmpty || _partialText.isNotEmpty
        ? '$_captionText${_captionText.isNotEmpty && _partialText.isNotEmpty ? '\n' : ''}$_partialText'
        : placeholder;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: double.infinity,
      height: _isCaptionCollapsed ? 80 : expandedHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117).withOpacity(0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, -10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header / Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFF6C63FF).withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(
                    _isCaptionLoading ? Icons.sync_rounded : Icons.closed_caption_rounded, 
                    color: const Color(0xFF6C63FF), 
                    size: 14
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isCaptionLoading ? 'PREPARING...' : 'LIVE CAPTIONS',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                
                if (!_isCaptionCollapsed) ...[
                  _buildLanguageDropdown(),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _captionHistory.clear();
                        _captionText = '';
                        _partialText = '';
                      });
                    },
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white38, size: 20),
                    tooltip: 'Clear',
                  ),
                ],
                
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _isCaptionCollapsed = !_isCaptionCollapsed),
                  icon: Icon(
                    _isCaptionCollapsed ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white60,
                  ),
                ),
                
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _toggleCaptions,
                  icon: const Icon(Icons.close_rounded, color: Colors.white24, size: 20),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          
          // Transcription Text Area
          if (!_isCaptionCollapsed)
            Flexible(
              child: SingleChildScrollView(
                controller: _captionScrollController,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    displayText,
                    style: TextStyle(
                      color: (_captionText.isEmpty && _partialText.isEmpty) || _isCaptionLoading
                          ? Colors.white.withOpacity(0.3)
                          : Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      height: 1.6,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.3),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildVerticalSlider(String label, double value, Color color, ValueChanged<double> onChanged) {
    return Column(
      children: [
        Container(
          height: 180,
          width: 60,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      activeTrackColor: color,
                      inactiveTrackColor: color.withOpacity(0.1),
                      thumbColor: Colors.white,
                      overlayColor: color.withOpacity(0.1),
                    ),
                    child: Slider(value: value, min: 0.0, max: 10.0, onChanged: onChanged),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9, fontWeight: FontWeight.w900),
        ),
        Text(
          value.toStringAsFixed(1),
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildLanguageDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedLang,
          dropdownColor: const Color(0xFF131932),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: Colors.white24),
          style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 11, fontWeight: FontWeight.bold),
          onChanged: (String? newValue) async {
            if (newValue != null) {
              setState(() => _selectedLang = newValue);
              if (_isRunning && _showCaptions) {
                await _stopCaptionPipeline();
                await _startCaptionPipeline();
              }
            }
          },
          items: TranscriptionService.supportedLanguages.entries.map((e) {
            return DropdownMenuItem<String>(
              value: e.key,
              child: Text(e.value.toUpperCase()),
            );
          }).toList(),
        ),
      ),
    );
  }
}
