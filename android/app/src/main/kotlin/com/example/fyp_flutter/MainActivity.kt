package com.example.fyp_flutter

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.DynamicsProcessing.*
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.fyp_flutter/audio_route"
    private var audioManager: AudioManager? = null
    private var dynamicsProcessing: DynamicsProcessing? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
                call, result ->
            when (call.method) {
                "initDynamicsProcessing" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: 0
                    initDynamicsProcessing(sessionId)
                    result.success(true)
                }
                "updateDynamicsProcessing" -> {
                    val leftGain = call.argument<Double>("leftGain")?.toFloat() ?: 1.0f
                    val rightGain = call.argument<Double>("rightGain")?.toFloat() ?: 1.0f
                    val tone = call.argument<Double>("tone")?.toFloat() ?: 0.5f
                    val suppression = call.argument<Double>("suppression")?.toFloat() ?: 0.5f
                    updateDynamicsProcessing(leftGain, rightGain, tone, suppression)
                    result.success(true)
                }
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
                        val outDevices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        val isHearingAid = outDevices.any { it.type == AudioDeviceInfo.TYPE_HEARING_AID }
                        if (isHearingAid) {
                            am.mode = AudioManager.MODE_NORMAL
                        } else {
                            am.mode = AudioManager.MODE_IN_COMMUNICATION
                            am.isSpeakerphoneOn = false
                            try {
                                am.setParameters("noise_suppression=on")
                                am.setParameters("mic_mode=voice_focus")
                                am.setParameters("vc_ns_mode=auto")
                            } catch (e: Exception) {}
                            if (hasBluetoothDevice(am)) {
                                if (am.isBluetoothScoAvailableOffCall) {
                                    am.startBluetoothSco()
                                    am.isBluetoothScoOn = true
                                }
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }
                "disableLiveAssistAudio" -> {
                    try {
                        if (dynamicsProcessing != null) {
                            dynamicsProcessing?.enabled = false
                            dynamicsProcessing?.release()
                            dynamicsProcessing = null
                        }
                        val am = audioManager!!
                        if (am.isBluetoothScoOn) {
                            am.isBluetoothScoOn = false
                            am.stopBluetoothSco()
                        }
                        am.mode = AudioManager.MODE_NORMAL
                        am.isSpeakerphoneOn = false
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }
            }
        }
    }

    private fun initDynamicsProcessing(sessionId: Int) {
        if (dynamicsProcessing != null) {
            dynamicsProcessing?.release()
        }

        val builder = Config.Builder(
            VARIANT_FAVOR_FREQUENCY_RESOLUTION,
            2, // Stereo (Left/Right)
            true, // PreEQ
            8,    // bands
            true, // MultiBandCompressor
            8,    // bands
            true, // PostEQ
            8,    // bands
            true  // Limiter
        )

        dynamicsProcessing = DynamicsProcessing(0, sessionId, builder.build())
        dynamicsProcessing?.enabled = true
    }

    private fun updateDynamicsProcessing(leftGain: Float, rightGain: Float, tone: Float, suppression: Float) {
        val dp = dynamicsProcessing ?: return
        
        // 1. Set Per-Channel Gain (Post-processing)
        // DynamicsProcessing handles this via Config, so we'll rely on Dart-side gain for L/R balance.
        
        // 2. Tone Adjustment (PostEQ)
        // ... existing logic ...
        // Clarity (High boost) vs Fullness (Low boost)
        val postEq = dp.getPostEqByChannelIndex(0) // Map to first channel (we'll treat as both for simplicity if mono)
        
        // Simple 3-band tone control
        val lowGain = tone * 12f // 0.0 -> 0dB, 1.0 -> 12dB
        val highGain = (1.0f - tone) * 12f // 0.0 -> 12dB, 1.0 -> 0dB
        
        for (i in 0 until postEq.bandCount) {
            val band = postEq.getBand(i)
            if (band.cutoffFrequency < 500) {
                band.gain = lowGain
            } else if (band.cutoffFrequency > 3000) {
                band.gain = highGain
            } else {
                band.gain = 0f
            }
            postEq.setBand(i, band)
        }
        dp.setPostEqAllChannelsTo(postEq)

        // 3. Limiter (Safety)
        val limiter = dp.getLimiterByChannelIndex(0)
        limiter.threshold = -1.0f // -1dB threshold
        limiter.ratio = 10f
        dp.setLimiterAllChannelsTo(limiter)
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
