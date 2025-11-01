import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BluetoothServiceManager {
  static final platform = MethodChannel("com.fyp_flutter/audio_route");
  static final BluetoothServiceManager _instance = BluetoothServiceManager._internal();
  factory BluetoothServiceManager() => _instance;
  BluetoothServiceManager._internal();

  /// Initialize and automatically route audio to Bluetooth if available
  Future<String> initAudioSession() async {
    final session = await AudioSession.instance;

    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
      AVAudioSessionCategoryOptions.allowBluetooth |
      AVAudioSessionCategoryOptions.defaultToSpeaker,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,
    ));

    // ✅ Activate session
    await session.setActive(true);

    // ✅ Get list of audio devices
    final devices = await session.getDevices();

    // ✅ Select a Bluetooth-capable device
    final bluetoothDevice = devices.firstWhere(
          (d) =>
      d.name.toLowerCase().contains("bluetooth") ||
          d.name.toLowerCase().contains("wave") ||
          d.name.toLowerCase().contains("buds") ||
          d.name.toLowerCase().contains("ear"),
      orElse: () => devices.first,
    );

    debugPrint("🎧 Auto-selected output device: ${bluetoothDevice.name}");

    return bluetoothDevice.name; // ✅ return it for UI display
  }

  /// Optional: get active route directly from platform
  Future<String> getActiveOutput() async {
    try {
      final deviceName = await platform.invokeMethod<String>("getActiveAudioDevice");
      return deviceName ?? "Unknown";
    } catch (e) {
      return "Error: $e";
    }
  }
}
