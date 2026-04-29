import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/services/bluetooth_service.dart';

class ConnectDeviceScreen extends StatefulWidget {
  const ConnectDeviceScreen({super.key});

  @override
  State<ConnectDeviceScreen> createState() => _ConnectDeviceScreenState();
}

class _ConnectDeviceScreenState extends State<ConnectDeviceScreen> with WidgetsBindingObserver {
  final BluetoothServiceManager _btService = BluetoothServiceManager();
  String _deviceName = "Detecting audio device...";
  bool _initialized = false;
  bool _isSpeakerMode = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAudioSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDevice();
    }
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

    try {
      // Try to get the actual Bluetooth device name
      final name = await _btService.initAudioSession();

      // If the name is generic (like phone name), try to get more specific device info
      if (name == "Phone Speaker" || name.contains("Detecting") || name.contains("Unknown")) {
        setState(() {
          _deviceName = "Scanning for devices...";
        });

        // Simulate scanning
        await Future.delayed(const Duration(seconds: 2));

        // In a real app, you'd get the actual connected device name
        // For now, show the name from the service
        setState(() {
          _deviceName = name;
        });
      } else {
        setState(() {
          _deviceName = name;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing device: $e');
      setState(() {
        _deviceName = "No device found";
      });
    } finally {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _isSpeakerMode = !_isSpeakerMode);

    if (_isSpeakerMode) {
      setState(() {
        _deviceName = "Phone Speaker";
      });
    } else {
      setState(() {
        _deviceName = "Switching to Bluetooth...";
      });
      await _refreshDevice();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "AUDIO OUTPUT",
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
              onPressed: _showHelpDialog,
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
              // Bluetooth Status Warning (example)
              if (!_isSpeakerMode && _deviceName.contains("No device") || _deviceName.contains("Error")) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "No Bluetooth device detected. Please check your connection.",
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

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
                                const Color(0xFF4CAF50).withOpacity(0.8),
                                const Color(0xFF2E7D32),
                              ]
                                  : (_deviceName.contains("No device") || _deviceName.contains("Error")
                                  ? [
                                Colors.grey.withOpacity(0.5),
                                Colors.grey.withOpacity(0.3),
                              ]
                                  : [
                                const Color(0xFF6C63FF).withOpacity(0.8),
                                const Color(0xFF4A44B5),
                              ]),
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isSpeakerMode
                                    ? const Color(0xFF4CAF50)
                                    : (_deviceName.contains("No device") || _deviceName.contains("Error")
                                    ? Colors.grey
                                    : const Color(0xFF6C63FF)
                                )).withOpacity(0.4),
                                blurRadius: 15,
                                spreadRadius: 3,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isSpeakerMode
                                ? Icons.volume_up_rounded
                                : (_deviceName.contains("No device") || _deviceName.contains("Error")
                                ? Icons.bluetooth_disabled_rounded
                                : Icons.bluetooth_rounded),
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
                            color: _isSpeakerMode
                                ? const Color(0xFF4CAF50)
                                : (_deviceName.contains("No device") || _deviceName.contains("Error")
                                ? Colors.grey
                                : const Color(0xFF6C63FF)),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isSpeakerMode
                                ? "SPEAKER MODE"
                                : (_deviceName.contains("No device") || _deviceName.contains("Error")
                                ? "NO DEVICE"
                                : "DEVICE CONNECTED"),
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
                          _isSpeakerMode ? "Current Output" : "Connected Device",
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
                    if (!_isSpeakerMode && !_deviceName.contains("No device") && !_deviceName.contains("Error"))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF6C63FF).withOpacity(0.2),
                              const Color(0xFF4A44B5).withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF6C63FF).withOpacity(0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.bluetooth_rounded,
                              size: 18,
                              color: Color(0xFF6C63FF),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "BLUETOOTH AUDIO",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF6C63FF),
                                letterSpacing: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Connection Quality Indicator
                    if (!_isSpeakerMode && !_deviceName.contains("No device") && !_deviceName.contains("Error")) ...[
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
                              color: const Color(0xFF4CAF50),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Connected",
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
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.8)),
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
                                _isSpeakerMode ? Icons.bluetooth_rounded : Icons.volume_up_rounded,
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
                                "Make sure your Bluetooth device is:\n"
                                    "• Turned on and paired with your phone\n"
                                    "• Within range (less than 10 meters)\n"
                                    "• Selected as audio output in phone settings\n\n"
                                    "If your device doesn't appear, try refreshing or check your Bluetooth settings.",
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
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2139),
        title: const Text(
          "Audio Output Help",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "How it works:",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "• Speaker Mode: Audio plays through your phone's speakers\n"
                  "• Bluetooth Mode: Audio plays through connected Bluetooth device\n\n"
                  "To connect a Bluetooth device:\n"
                  "1. Enable Bluetooth on your phone\n"
                  "2. Pair your device in phone settings\n"
                  "3. Return to this screen and tap Refresh\n"
                  "4. The device name should appear above",
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Got it",
              style: TextStyle(color: Color(0xFF6C63FF)),
            ),
          ),
        ],
      ),
    );
  }
}