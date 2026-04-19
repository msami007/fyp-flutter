import 'dart:ffi';
import 'dart:io';
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
