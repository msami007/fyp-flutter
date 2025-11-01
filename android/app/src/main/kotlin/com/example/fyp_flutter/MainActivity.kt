package com.example.fyp_flutter

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.fyp_flutter/audio_route"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
                call, result ->
            if (call.method == "getActiveAudioDevice") {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)

                var activeDevice = "Unknown"
                for (device in devices) {
                    if (device.isSink) {
                        when (device.type) {
                            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> activeDevice = "Bluetooth (A2DP)"
                            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> activeDevice = "Bluetooth (SCO)"
                            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> activeDevice = "Phone Speaker"
                            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> activeDevice = "Wired Headphones"
                            AudioDeviceInfo.TYPE_WIRED_HEADSET -> activeDevice = "Wired Headset"
                            else -> activeDevice = device.productName?.toString() ?: "Unknown"
                        }
                        break
                    }
                }
                result.success(activeDevice)
            } else {
                result.notImplemented()
            }
        }
    }
}
