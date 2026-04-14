package com.example.fyp_flutter

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.fyp_flutter/audio_route"
    private var audioManager: AudioManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
                call, result ->
            when (call.method) {
                "getActiveAudioDevice" -> {
                    val am = audioManager!!
                    val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
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
                }

                "enableLiveAssistAudio" -> {
                    try {
                        val am = audioManager!!

                        // Set audio mode to voice communication — this:
                        // 1. Routes audio through earpiece/headset instead of speaker
                        // 2. Enables hardware AEC and NS on the mic input
                        // 3. Activates Bluetooth SCO if BT headset is connected
                        am.mode = AudioManager.MODE_IN_COMMUNICATION

                        // Enable speakerphone OFF to force headset routing
                        am.isSpeakerphoneOn = false

                        // If Bluetooth headset is connected, start SCO to use its mic
                        if (hasBluetoothDevice(am)) {
                            am.startBluetoothSco()
                            am.isBluetoothScoOn = true
                        }

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }

                "disableLiveAssistAudio" -> {
                    try {
                        val am = audioManager!!

                        // Stop Bluetooth SCO
                        if (am.isBluetoothScoOn) {
                            am.isBluetoothScoOn = false
                            am.stopBluetoothSco()
                        }

                        // Reset audio mode back to normal
                        am.mode = AudioManager.MODE_NORMAL
                        am.isSpeakerphoneOn = false

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun hasBluetoothDevice(am: AudioManager): Boolean {
        val devices = am.getDevices(AudioManager.GET_DEVICES_ALL)
        return devices.any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET)
        }
    }
}
