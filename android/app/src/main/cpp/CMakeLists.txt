cmake_minimum_required(VERSION 3.22.1)
project("native_audio")

include(FetchContent)

# Oboe for low-latency audio
FetchContent_Declare(
    oboe
    GIT_REPOSITORY https://github.com/google/oboe
    GIT_TAG        1.9.3
)
FetchContent_MakeAvailable(oboe)

# RNNoise source (used as source files)
FetchContent_Declare(
    rnnoise
    GIT_REPOSITORY https://gitlab.xiph.org/xiph/rnnoise.git
    GIT_TAG        master
)
FetchContent_GetProperties(rnnoise)
if(NOT rnnoise_POPULATED)
    FetchContent_Populate(rnnoise)
endif()

# RNNoise isolated library (to prevent prefix leaking into global namespace)
add_library(rnnoise_local STATIC
    ${rnnoise_SOURCE_DIR}/src/denoise.c
    ${rnnoise_SOURCE_DIR}/src/rnn.c
    ${rnnoise_SOURCE_DIR}/src/rnn_data.c
    ${rnnoise_SOURCE_DIR}/src/pitch.c
    ${rnnoise_SOURCE_DIR}/src/celt_lpc.c
    ${rnnoise_SOURCE_DIR}/src/kiss_fft.c
)
target_compile_definitions(rnnoise_local PRIVATE 
    RANDOM_PREFIX=rnnoise 
    OUTSIDE_SPEEX 
    FLOATING_POINT 
    EXPORT=
)
target_include_directories(rnnoise_local PUBLIC 
    ${rnnoise_SOURCE_DIR}/include
    ${rnnoise_SOURCE_DIR}/src
)

# Manually Link the TFLite JNI library (Copied from cache)
add_library(tflite_jni SHARED IMPORTED)
set_target_properties(tflite_jni PROPERTIES IMPORTED_LOCATION 
    ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libtensorflowlite_jni.so)

# Main Native Audio Engine
add_library(native_audio SHARED
    native_audio.cpp
    audio_engine.cpp
    dtln_processor.cpp
)

target_include_directories(native_audio PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${rnnoise_SOURCE_DIR}/include
    ${rnnoise_SOURCE_DIR}/src
)

target_link_libraries(native_audio
    oboe
    tflite_jni
    rnnoise_local
    log
    android
)
