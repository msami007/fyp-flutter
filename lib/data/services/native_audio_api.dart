import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef StartAudioNative = Void Function();
typedef StartAudio = void Function();

typedef StopAudioNative = Void Function();
typedef StopAudio = void Function();

typedef SetGainsNative = Void Function(Float left, Float right);
typedef SetGains = void Function(double left, double right);

typedef SetAllEqNative = Void Function(Pointer<Float> gains);
typedef SetAllEq = void Function(Pointer<Float> gains);

class NativeAudioApi {
  static final DynamicLibrary _lib = _loadLib();

  static DynamicLibrary _loadLib() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libnative_audio.so');
    }
    throw UnsupportedError('Platform not supported');
  }

  static final StartAudio startAudio = _lib
      .lookup<NativeFunction<StartAudioNative>>('start_audio')
      .asFunction();

  static final StopAudio stopAudio = _lib
      .lookup<NativeFunction<StopAudioNative>>('stop_audio')
      .asFunction();

  static final SetGains setGains = _lib
      .lookup<NativeFunction<SetGainsNative>>('set_gains')
      .asFunction();

  static final SetAllEq setAllEq = _lib
      .lookup<NativeFunction<SetAllEqNative>>('set_all_eq')
      .asFunction();

  static final void Function(double) setSuppression = _lib
      .lookup<NativeFunction<Void Function(Float)>>('set_suppression')
      .asFunction();

  static final void Function(double) setTone = _lib
      .lookup<NativeFunction<Void Function(Float)>>('set_tone')
      .asFunction();

  static final bool Function(Pointer<Void>, int, Pointer<Void>, int)
      loadDtlnModels = _lib
          .lookup<
              NativeFunction<
                  Bool Function(
                      Pointer<Void>, Int64, Pointer<Void>, Int64)>>('load_dtln_models')
          .asFunction();

  static final void Function(int) setProcessingMode = _lib
      .lookup<NativeFunction<Void Function(Int32)>>('set_processing_mode')
      .asFunction();

  static final double Function() getInputLevel = _lib
      .lookup<NativeFunction<Float Function()>>('get_input_level')
      .asFunction();

  static final double Function() getOutputLevel = _lib
      .lookup<NativeFunction<Float Function()>>('get_output_level')
      .asFunction();

  // ── Caption audio (processed output for STT) ──

  static final int Function(Pointer<Float>, int) _getCaptionData = _lib
      .lookup<NativeFunction<Int32 Function(Pointer<Float>, Int32)>>('get_caption_data')
      .asFunction();

  static final int Function() getCaptionAvailable = _lib
      .lookup<NativeFunction<Int32 Function()>>('get_caption_available')
      .asFunction();

  /// Pull processed audio from C++ engine, downsample 48kHz→16kHz,
  /// and return as PCM16 bytes suitable for Vosk.
  static Uint8List? pullCaptionPcm16() {
    final available = getCaptionAvailable();
    if (available < 144) return null; // Need at least 144 samples (48 at 16kHz)

    // Pull up to 4800 frames (~100ms at 48kHz)
    final maxPull = available.clamp(0, 4800);
    final buf = calloc<Float>(maxPull);
    final got = _getCaptionData(buf, maxPull);

    if (got == 0) {
      calloc.free(buf);
      return null;
    }

    // Downsample 48kHz → 16kHz (take every 3rd sample with averaging)
    final out16k = got ~/ 3;
    final pcm16Bytes = ByteData(out16k * 2); // 2 bytes per sample (Int16)
    for (int i = 0; i < out16k; i++) {
      final idx = i * 3;
      double sum = buf[idx];
      if (idx + 1 < got) sum += buf[idx + 1];
      if (idx + 2 < got) sum += buf[idx + 2];
      final avg = sum / 3.0;

      // Float → Int16
      int sample = (avg * 32767.0).round().clamp(-32768, 32767);
      pcm16Bytes.setInt16(i * 2, sample, Endian.little);
    }

    calloc.free(buf);
    return pcm16Bytes.buffer.asUint8List();
  }

  /// Helper to update EQ from a List
  static void updateEq(List<double> gainsDb) {
    final pointer = calloc<Float>(13);
    for (int i = 0; i < 13; i++) {
      pointer[i] = gainsDb[i];
    }
    setAllEq(pointer);
    calloc.free(pointer);
  }
}

