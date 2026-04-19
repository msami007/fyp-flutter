#ifndef AUDIO_ENGINE_H
#define AUDIO_ENGINE_H

#include <oboe/Oboe.h>
#include <memory>
#include <vector>
#include <atomic>
#include "dsp_processors.h"
#include "dtln_processor.h"

extern "C" {
#include "rnnoise.h"
}

class AudioEngine : public oboe::AudioStreamDataCallback {
public:
    AudioEngine();
    virtual ~AudioEngine();

    bool start();
    void stop();

    void setGain(float left, float right);
    void setEQ(const float* gains, int count);
    void setSuppression(float level);
    void setTone(float tone);
    void setProcessingMode(int mode);

    bool loadDTLNModels(const void* m1, size_t s1, const void* m2, size_t s2);

    float getInputLevel() { return mInputLevel.load(); }
    float getOutputLevel() { return mOutputLevel.load(); }

    // Oboe callback
    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream *audioStream,
        void *audioData,
        int32_t numFrames) override;

private:
    std::shared_ptr<oboe::AudioStream> mInputStream;
    std::shared_ptr<oboe::AudioStream> mOutputStream;

    std::atomic<float> mInputLevel{0.0f};
    std::atomic<float> mOutputLevel{0.0f};

    // Processing Engines
    std::unique_ptr<DTLNProcessor> mDTLNProcessor;
    int mProcessingMode = 0; // 0: RNN, 1: DTLN

    // DSP Components
    std::unique_ptr<GainProcessor> mGainProcessor;
    std::unique_ptr<MultiBandEQ> mEQProcessor;
    std::unique_ptr<DynamicRangeCompressor> mDRC;
    std::unique_ptr<TiltFilter> mToneProcessor;
    
    DenoiseState* mDenoiseState = nullptr;
    float mSuppressionLevel = 0.5f;

    // Internal Buffering
    float mDenoiseBuffer[480];
    int mDenoiseIndex = 0;

    // DTLN Buffering (16kHz)
    float m16kBuffer[512];
    int m16kIndex = 0;
    int mResamplePhase = 0;
    float mDownsampleSum = 0.0f;
    float mPrevDtlnOut = 0.0f;

    // Ring Buffer for sync
    static const int kBufferCapacity = 2048; 
    float mRingBuffer[kBufferCapacity];
    int mReadIndex = 0;
    int mWriteIndex = 0;
    
    void writeToBuffer(const float* data, int numFrames);
    int readFromBuffer(float* data, int numFrames);
};

#endif // AUDIO_ENGINE_H
