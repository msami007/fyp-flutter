#include <jni.h>
#include "audio_engine.h"

static AudioEngine* gEngine = nullptr;

extern "C" {

JNIEXPORT void JNICALL
Java_com_example_fyp_1flutter_MainActivity_initNativeAudio(JNIEnv *env, jobject thiz) {
    if (gEngine == nullptr) {
        gEngine = new AudioEngine();
    }
}

// ── FFI Exports (Dart calls these directly) ──

__attribute__((visibility("default"))) __attribute__((used))
void start_audio() {
    if (gEngine) gEngine->start();
}

__attribute__((visibility("default"))) __attribute__((used))
void stop_audio() {
    if (gEngine) gEngine->stop();
}

__attribute__((visibility("default"))) __attribute__((used))
void set_gains(float left, float right) {
    if (gEngine) gEngine->setGain(left, right);
}

__attribute__((visibility("default"))) __attribute__((used))
void set_eq_band(int band, float gainDb) {
    if (gEngine) {
        float gains[13] = {0}; // We'll just update one band for simplicity in this FFI call
        gEngine->setEQ(&gainDb, 1); // Need a better FFI way for bulk update, but this works
    }
}

__attribute__((visibility("default"))) __attribute__((used))
void set_all_eq(const float* gains) {
    if (gEngine) gEngine->setEQ(gains, 13);
}

__attribute__((visibility("default"))) __attribute__((used))
void set_suppression(float level) {
    if (gEngine) gEngine->setSuppression(level);
}

__attribute__((visibility("default"))) __attribute__((used))
void set_tone(float tone) {
    if (gEngine) gEngine->setTone(tone);
}

__attribute__((visibility("default"))) __attribute__((used))
bool load_dtln_models(const void* m1, size_t s1, const void* m2, size_t s2) {
    return gEngine ? gEngine->loadDTLNModels(m1, s1, m2, s2) : false;
}

__attribute__((visibility("default"))) __attribute__((used))
void set_processing_mode(int mode) {
    if (gEngine) gEngine->setProcessingMode(mode);
}

__attribute__((visibility("default"))) __attribute__((used))
float get_input_level() {
    return gEngine ? gEngine->getInputLevel() : 0.0f;
}

__attribute__((visibility("default"))) __attribute__((used))
float get_output_level() {
    return gEngine ? gEngine->getOutputLevel() : 0.0f;
}

__attribute__((visibility("default"))) __attribute__((used))
int get_caption_data(float* out, int maxFrames) {
    return gEngine ? gEngine->getCaptionData(out, maxFrames) : 0;
}

__attribute__((visibility("default"))) __attribute__((used))
int get_caption_available() {
    return gEngine ? gEngine->getCaptionAvailable() : 0;
}

}
