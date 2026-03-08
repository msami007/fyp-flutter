import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../data/services/noise_suppression_service.dart';
import '../../data/services/voice_isolation_service.dart';
import '../../data/services/transcription_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isPlaying = false;
  String _status = "Ready to record";
  Timer? _recordingTimer;
  String? _currentRecordingPath;
  List<FileSystemEntity> _recordings = [];
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  // ── AI Processing Toggles ──
  final NoiseSuppressionService _noiseSuppression = NoiseSuppressionService();
  final VoiceIsolationService _voiceIsolation = VoiceIsolationService();
  final TranscriptionService _transcription = TranscriptionService();
  bool _enhanceEnabled = false;
  bool _isolateEnabled = false;
  bool _transcribeEnabled = false;
  String _liveTranscript = '';
  bool _aiModelsLoaded = false;

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

    // Set up audio player state listener
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecordings();
      _initAIModels();
    });
  }

  Future<void> _initAIModels() async {
    try {
      final ns = await _noiseSuppression.initialize();
      final vi = await _voiceIsolation.initialize();
      final tr = await _transcription.initialize();
      _aiModelsLoaded = ns || vi || tr;
      if (mounted) setState(() {});
      debugPrint('AI models loaded: NS=$ns, VI=$vi, TR=$tr');
    } catch (e) {
      debugPrint('AI model init error: $e');
    }
  }

  Future<String?> _getRecordingDirectory() async {
    try {
      if (Platform.isAndroid) {
        // For Android, try to get the Downloads folder
        final directory = Directory('/storage/emulated/0/Download/HearWise');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        return directory.path;
      } else if (Platform.isIOS) {
        // For iOS, use Documents directory
        final directory = await getApplicationDocumentsDirectory();
        final hearwiseDir = Directory('${directory.path}/HearWise');
        if (!await hearwiseDir.exists()) {
          await hearwiseDir.create(recursive: true);
        }
        return hearwiseDir.path;
      }
    } catch (e) {
      debugPrint('Error creating directory: $e');
    }

    // Fallback to temporary directory
    final dir = await getTemporaryDirectory();
    return dir.path;
  }

  Future<void> _loadRecordings() async {
    try {
      final dirPath = await _getRecordingDirectory();
      if (dirPath != null) {
        final directory = Directory(dirPath);
        if (await directory.exists()) {
          // Load both PCM and WAV files
          final files = directory.listSync().where((file) =>
          file.path.endsWith('.pcm') || file.path.endsWith('.wav')).toList();
          // Sort by most recent first
          files.sort((a, b) {
            return b.statSync().modified.compareTo(a.statSync().modified);
          });

          if (mounted) {
            setState(() {
              _recordings = files;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading recordings: $e');
    }
  }

  Future<bool> requestPermissions() async {
    try {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.microphone,
        if (Platform.isAndroid) Permission.storage,
      ].request();

      return statuses[Permission.microphone]?.isGranted ?? false;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  // Convert PCM to WAV format
  Future<String?> convertPcmToWav(String pcmPath) async {
    try {
      final pcmFile = File(pcmPath);
      if (!await pcmFile.exists()) return null;

      final wavPath = pcmPath.replaceAll('.pcm', '.wav');
      final wavFile = File(wavPath);

      // Read PCM data
      final pcmData = await pcmFile.readAsBytes();

      // WAV header parameters (16kHz, 16-bit, mono)
      final int sampleRate = 16000;
      final int bitsPerSample = 16;
      final int numChannels = 1;
      final int byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
      final int blockAlign = numChannels * bitsPerSample ~/ 8;
      final int dataSize = pcmData.length;
      final int totalSize = 44 + dataSize; // 44 bytes header + data

      // Create WAV header
      final header = ByteData(44);

      // "RIFF" chunk descriptor
      header.setUint8(0, 'R'.codeUnitAt(0));
      header.setUint8(1, 'I'.codeUnitAt(0));
      header.setUint8(2, 'F'.codeUnitAt(0));
      header.setUint8(3, 'F'.codeUnitAt(0));
      header.setUint32(4, totalSize - 8, Endian.little); // File size - 8

      // "WAVE" format
      header.setUint8(8, 'W'.codeUnitAt(0));
      header.setUint8(9, 'A'.codeUnitAt(0));
      header.setUint8(10, 'V'.codeUnitAt(0));
      header.setUint8(11, 'E'.codeUnitAt(0));

      // "fmt " subchunk
      header.setUint8(12, 'f'.codeUnitAt(0));
      header.setUint8(13, 'm'.codeUnitAt(0));
      header.setUint8(14, 't'.codeUnitAt(0));
      header.setUint8(15, ' '.codeUnitAt(0));
      header.setUint32(16, 16, Endian.little); // Subchunk1 size (16 for PCM)
      header.setUint16(20, 1, Endian.little); // Audio format (1 = PCM)
      header.setUint16(22, numChannels, Endian.little); // Number of channels
      header.setUint32(24, sampleRate, Endian.little); // Sample rate
      header.setUint32(28, byteRate, Endian.little); // Byte rate
      header.setUint16(32, blockAlign, Endian.little); // Block align
      header.setUint16(34, bitsPerSample, Endian.little); // Bits per sample

      // "data" subchunk
      header.setUint8(36, 'd'.codeUnitAt(0));
      header.setUint8(37, 'a'.codeUnitAt(0));
      header.setUint8(38, 't'.codeUnitAt(0));
      header.setUint8(39, 'a'.codeUnitAt(0));
      header.setUint32(40, dataSize, Endian.little); // Data size

      // Write header and PCM data to WAV file
      await wavFile.writeAsBytes(header.buffer.asUint8List());
      await wavFile.writeAsBytes(pcmData, mode: FileMode.append);

      return wavPath;
    } catch (e) {
      debugPrint('Error converting to WAV: $e');
      return null;
    }
  }

  Future<void> startRecording() async {
    final hasPermission = await requestPermissions();

    if (!hasPermission) {
      if (mounted) {
        setState(() => _status = "Microphone permission denied");
        _showSnackBar("Please grant microphone permission", Colors.orange);
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        setState(() => _status = "Microphone permission denied");
        _showSnackBar("Please grant microphone permission", Colors.orange);
      }
      return;
    }

    final dirPath = await _getRecordingDirectory();
    if (dirPath == null) {
      _showSnackBar("Could not access storage", Colors.red);
      return;
    }

    // Create a valid filename without special characters
    final now = DateTime.now();
    final timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    final recordingPath = '$dirPath/recording_$timestamp.pcm';

    _currentRecordingPath = recordingPath;

    try {
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          // Built-in Android audio processing based on toggles
          noiseSuppress: _enhanceEnabled || _isolateEnabled,
          echoCancel: _isolateEnabled,
          autoGain: _enhanceEnabled || _isolateEnabled,
        ),
        path: recordingPath,
      );

      if (mounted) {
        setState(() {
          _isRecording = true;
          _status = "Recording audio...";
        });
      }

      // Update recording status periodically
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!_isRecording || _currentRecordingPath == null) return;

        try {
          final file = File(_currentRecordingPath!);
          if (await file.exists()) {
            final size = await file.length();
            if (mounted) {
              setState(() {
                _status = "Recording... ${(size / 1024).toStringAsFixed(1)} KB";
              });
            }
          }
        } catch (e) {
          debugPrint('Error checking file size: $e');
        }
      });

      _showSnackBar("Recording started", const Color(0xFF4CAF50));
    } catch (e) {
      debugPrint('Error starting recording: $e');
      _showSnackBar("Error starting recording: $e", Colors.red);

      if (mounted) {
        setState(() {
          _status = "Recording failed";
        });
      }
    }
  }

  Future<void> stopRecording() async {
    try {
      await _recorder.stop();
      _recordingTimer?.cancel();

      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          final size = await file.length();

          // Ask if user wants to convert to WAV
          if (mounted) {
            _showConversionDialog(_currentRecordingPath!);
          }

          _showSnackBar(
              "Recording saved!\n${(size / 1024).toStringAsFixed(1)} KB",
              const Color(0xFF2196F3)
          );
        }
      }

      // Refresh the recordings list
      await _loadRecordings();
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _showSnackBar("Error stopping recording: $e", Colors.red);
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _status = "Recording saved";
      });
    }
  }

  void _showConversionDialog(String pcmPath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2139),
        title: const Text(
          'Convert to WAV?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Would you like to convert this recording to WAV format for easier playback?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
            ),
            onPressed: () async {
              Navigator.pop(context);
              _showSnackBar("Converting to WAV...", Colors.orange);
              final wavPath = await convertPcmToWav(pcmPath);
              if (wavPath != null && mounted) {
                _showSnackBar("Converted to WAV successfully", const Color(0xFF4CAF50));
                await _loadRecordings();
              }
            },
            child: const Text('Convert', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> playRecording(String path) async {
    try {
      // If it's PCM, we need to convert first
      if (path.endsWith('.pcm')) {
        _showSnackBar("Converting PCM to WAV for playback...", Colors.orange);
        final wavPath = await convertPcmToWav(path);
        if (wavPath != null) {
          await _audioPlayer.play(DeviceFileSource(wavPath));
        } else {
          _showSnackBar("Could not convert PCM file", Colors.red);
        }
      } else {
        // Play WAV directly
        await _audioPlayer.play(DeviceFileSource(path));
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      _showSnackBar("Error playing audio", Colors.red);
    }
  }

  Future<void> stopPlayback() async {
    await _audioPlayer.stop();
  }

  void _showRecordingDetails(FileSystemEntity file) {
    try {
      final fileStat = file.statSync();
      final size = fileStat.size / 1024; // KB
      final modified = fileStat.modified;
      final fileName = file.path.split('/').last;
      final isPcm = file.path.endsWith('.pcm');

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E2139),
          title: Text(
            fileName,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Format:', isPcm ? 'PCM (Raw)' : 'WAV'),
                const SizedBox(height: 8),
                _buildDetailRow('Size:', '${size.toStringAsFixed(2)} KB'),
                const SizedBox(height: 8),
                _buildDetailRow('Sample Rate:', '16 kHz'),
                const SizedBox(height: 8),
                _buildDetailRow('Channels:', 'Mono'),
                const SizedBox(height: 8),
                _buildDetailRow('Bit Depth:', '16-bit'),
                const SizedBox(height: 8),
                _buildDetailRow('Location:', file.path),
                const SizedBox(height: 8),
                _buildDetailRow('Modified:', '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} ${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}'),
              ],
            ),
          ),
          actions: [
            if (isPcm)
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  _showSnackBar("Converting to WAV...", Colors.orange);
                  final wavPath = await convertPcmToWav(file.path);
                  if (wavPath != null && mounted) {
                    _showSnackBar("Converted to WAV successfully", const Color(0xFF4CAF50));
                    await _loadRecordings();
                  }
                },
                child: const Text('Convert to WAV', style: TextStyle(color: Color(0xFF6C63FF))),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.white60)),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error showing details: $e');
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildToggleChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF6C63FF).withOpacity(0.25)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF6C63FF).withOpacity(0.6)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20,
                  color: isActive ? const Color(0xFF6C63FF) : Colors.white.withOpacity(0.5)),
              const SizedBox(height: 4),
              Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? const Color(0xFF6C63FF) : Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    _animationController.dispose();
    _noiseSuppression.dispose();
    _voiceIsolation.dispose();
    _transcription.dispose();
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _isRecording ? const Color(0xFF4CAF50) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isRecording ? const Color(0xFF4CAF50) : Colors.white.withOpacity(0.3),
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
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              onPressed: _loadRecordings,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Status Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
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
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF6C63FF),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Recording Status",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isRecording ? const Color(0xFF4CAF50) : Colors.white.withOpacity(0.8),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── AI Processing Toggles ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2139),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'AI Processing',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _aiModelsLoaded
                                ? const Color(0xFF4CAF50).withOpacity(0.2)
                                : Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _aiModelsLoaded ? 'Models Ready' : 'Loading...',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _aiModelsLoaded ? const Color(0xFF4CAF50) : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildToggleChip(
                          icon: Icons.noise_aware,
                          label: 'Enhance',
                          isActive: _enhanceEnabled,
                          onTap: () {
                            setState(() {
                              _enhanceEnabled = !_enhanceEnabled;
                            });
                            _noiseSuppression.setEnabled(_enhanceEnabled);
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildToggleChip(
                          icon: Icons.record_voice_over,
                          label: 'Isolate',
                          isActive: _isolateEnabled,
                          onTap: () {
                            setState(() {
                              _isolateEnabled = !_isolateEnabled;
                            });
                            _voiceIsolation.setEnabled(_isolateEnabled);
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildToggleChip(
                          icon: Icons.subtitles,
                          label: 'Transcribe',
                          isActive: _transcribeEnabled,
                          onTap: () {
                            setState(() => _transcribeEnabled = !_transcribeEnabled);
                          },
                        ),
                      ],
                    ),
                    if (_transcribeEnabled && _liveTranscript.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _liveTranscript,
                          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Main Recording Button
              Center(
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isRecording ? _pulseAnimation.value : 1.0,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _isRecording
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
                              color: (_isRecording ? const Color(0xFFE91E63) : const Color(0xFF6C63FF)).withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isRecording ? stopRecording : startRecording,
                            borderRadius: BorderRadius.circular(100),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                                  size: 36,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _isRecording ? "STOP" : "START",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
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
              ),

              const SizedBox(height: 24),

              // Recordings List
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Recent Recordings",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '${_recordings.length} files',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _recordings.isEmpty
                          ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.mic_none_rounded,
                              size: 48,
                              color: Colors.white.withOpacity(0.2),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "No recordings yet",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Tap START to begin recording",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                          : ListView.builder(
                        itemCount: _recordings.length,
                        itemBuilder: (context, index) {
                          final file = _recordings[index];
                          final fileName = file.path.split('/').last;
                          final isPcm = file.path.endsWith('.pcm');
                          try {
                            final fileStat = file.statSync();
                            final size = fileStat.size / 1024;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2139),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (isPcm ? Colors.orange : const Color(0xFF6C63FF)).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isPcm ? Icons.audio_file_rounded : Icons.music_note_rounded,
                                    color: isPcm ? Colors.orange : const Color(0xFF6C63FF),
                                    size: 20,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        fileName.length > 22
                                            ? '${fileName.substring(0, 20)}...'
                                            : fileName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (isPcm)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'PCM',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  '${size.toStringAsFixed(1)} KB',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.4),
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        _isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                        color: _isPlaying ? Colors.red : const Color(0xFF4CAF50),
                                        size: 24,
                                      ),
                                      onPressed: () async {
                                        if (_isPlaying) {
                                          await stopPlayback();
                                        } else {
                                          await playRecording(file.path);
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.info_outline_rounded,
                                        color: Color(0xFF6C63FF),
                                        size: 20,
                                      ),
                                      onPressed: () => _showRecordingDetails(file),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          } catch (e) {
                            return const SizedBox.shrink();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}