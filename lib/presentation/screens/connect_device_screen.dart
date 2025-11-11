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
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _initializeAudioSession();
  }

  Future<void> _initializeAudioSession() async {
    try {
      final name = await _btService.initAudioSession();
      setState(() {
        _deviceName = name;
        _initialized = true;
      });
    } catch (e) {
      setState(() {
        _deviceName = "Error initializing audio";
        _initialized = true;
      });
    }
  }

  Future<void> _refreshDevice() async {
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(milliseconds: 500));
    final name = await _btService.initAudioSession();
    setState(() {
      _deviceName = name;
      _isRefreshing = false;
    });
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _isSpeakerMode = !_isSpeakerMode);
    if (_isSpeakerMode) {
      setState(() => _deviceName = "Phone Speaker");
    } else {
      setState(() => _deviceName = "Detecting audio device...");
      final name = await _btService.initAudioSession();
      setState(() => _deviceName = name);
    }
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
              Icons.volume_up_rounded,
              color: const Color(0xFF6C63FF),
              size: 24,
            ),
            const SizedBox(width: 12),
            const Text(
              "Audio Output",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.5,
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
              icon: const Icon(Icons.help_outline, color: Colors.white),
              onPressed: () {
                // Help action
              },
            ),
          ),
        ],
      ),
      body: _initialized
          ? SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                (kToolbarHeight + MediaQuery.of(context).padding.top + 48),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main Device Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2139),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.15),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Status Indicator
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!_isSpeakerMode)
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF6C63FF).withOpacity(0.1),
                            ),
                          ),
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isSpeakerMode
                                  ? [
                                Color(0xFF4CAF50).withOpacity(0.8), // Green for speaker
                                Color(0xFF2E7D32),
                              ]
                                  : [
                                const Color(0xFF6C63FF).withOpacity(0.8),
                                const Color(0xFF4A44B5),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isSpeakerMode
                                    ? const Color(0xFF4CAF50) // Green
                                    : const Color(0xFF6C63FF)
                                ).withOpacity(0.4),
                                blurRadius: 15,
                                spreadRadius: 3,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isSpeakerMode ? Icons.volume_up_rounded : Icons.headphones_rounded,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Device Status Label
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: _isSpeakerMode ? const Color(0xFF4CAF50) : const Color(0xFF6C63FF),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "ACTIVE OUTPUT",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withOpacity(0.7),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Device Name
                    Column(
                      children: [
                        Text(
                          _deviceName,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Connected Device",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.6),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Mode Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isSpeakerMode
                              ? [
                            const Color(0xFF4CAF50).withOpacity(0.2), // Green
                            const Color(0xFF2E7D32).withOpacity(0.1),
                          ]
                              : [
                            const Color(0xFF6C63FF).withOpacity(0.2),
                            const Color(0xFF4A44B5).withOpacity(0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isSpeakerMode
                              ? const Color(0xFF4CAF50).withOpacity(0.4) // Green
                              : const Color(0xFF6C63FF).withOpacity(0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isSpeakerMode ? Icons.volume_up_rounded : Icons.bluetooth_rounded,
                            size: 18,
                            color: _isSpeakerMode ? const Color(0xFF4CAF50) : const Color(0xFF6C63FF),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isSpeakerMode ? "SPEAKER MODE" : "BLUETOOTH MODE",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _isSpeakerMode ? const Color(0xFF4CAF50) : const Color(0xFF6C63FF),
                              letterSpacing: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Connection Quality Indicator
                    if (!_isSpeakerMode) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.signal_cellular_alt_rounded,
                              size: 16,
                              color: const Color(0xFF4CAF50), // Green for good connection
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Strong Connection",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Control Buttons
              Column(
                children: [
                  // Refresh Button
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF4A44B5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C63FF).withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _isRefreshing ? null : _refreshDevice,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isRefreshing)
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.8)),
                                  ),
                                )
                              else
                                const Icon(Icons.refresh_rounded, color: Colors.white),
                              const SizedBox(width: 12),
                              Text(
                                _isRefreshing ? "Scanning..." : "Refresh Device",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Toggle Mode Button
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2139),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _toggleSpeaker,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isSpeakerMode ? Icons.headphones_rounded : Icons.volume_up_rounded,
                                color: _isSpeakerMode ? const Color(0xFF6C63FF) : const Color(0xFF4CAF50),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _isSpeakerMode ? "Switch to Bluetooth" : "Switch to Speaker",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Help Text
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2139),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF6C63FF).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFF6C63FF),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Device Connection Tips",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Pair or switch Bluetooth devices from your phone's settings. Make sure your device is in pairing mode and within range.",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.6),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      )
          : const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(Color(0xFF6C63FF)),
        ),
      ),
    );
  }
}