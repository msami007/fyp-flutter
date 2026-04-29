#include "audio_engine.h"
#include <android/log.h>

#define TAG "AudioEngine"

AudioEngine::AudioEngine() {
    mGainProcessor = std::make_unique<GainProcessor>();
    mEQProcessor = std::make_unique<MultiBandEQ>(48000.0f);
    mDRC = std::make_unique<DynamicRangeCompressor>(48000.0f);
    mToneProcessor = std::make_unique<TiltFilter>(48000.0f);
    mDTLNProcessor = std::make_unique<DTLNProcessor>();
    mDenoiseState = rnnoise_create(NULL);
}

AudioEngine::~AudioEngine() {
    stop();
    if (mDenoiseState) rnnoise_destroy(mDenoiseState);
}

bool AudioEngine::loadDTLNModels(const void* m1, size_t s1, const void* m2, size_t s2) {
    if (!mDTLNProcessor) return false;
    return mDTLNProcessor->init(static_cast<const uint8_t*>(m1), s1, static_cast<const uint8_t*>(m2), s2);
}

bool AudioEngine::start() {
    oboe::AudioStreamBuilder builder;
    builder.setDirection(oboe::Direction::Input)
           ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
           ->setSharingMode(oboe::SharingMode::Exclusive)
           ->setFormat(oboe::AudioFormat::Float)
           ->setChannelCount(oboe::ChannelCount::Mono)
           ->setSampleRate(48000)
           ->setDataCallback(this)
           ->setInputPreset(oboe::InputPreset::VoiceCommunication);

    oboe::Result result = builder.openStream(mInputStream);
    if (result != oboe::Result::OK) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "Failed to open input stream: %s", oboe::convertToText(result));
        return false;
    }

    builder.setDirection(oboe::Direction::Output)
           ->setDataCallback(this)
           ->setSampleRate(48000)
           ->setChannelCount(oboe::ChannelCount::Stereo);

    result = builder.openStream(mOutputStream);
    if (result != oboe::Result::OK) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "Failed to open output stream: %s", oboe::convertToText(result));
        return false;
    }

    mReadIndex = 0;
    mWriteIndex = 0;
    mDenoiseIndex = 0;
    mCaptionReadIndex = 0;
    mCaptionWriteIndex = 0;
    memset(mRingBuffer, 0, sizeof(mRingBuffer));
    memset(mDenoiseBuffer, 0, sizeof(mDenoiseBuffer));
    memset(mCaptionBuffer, 0, sizeof(mCaptionBuffer));

    float sampleRate = mOutputStream->getSampleRate();
    mEQProcessor = std::make_unique<MultiBandEQ>(sampleRate);
    mDRC = std::make_unique<DynamicRangeCompressor>(sampleRate);
    mToneProcessor = std::make_unique<TiltFilter>(sampleRate);

    mInputStream->requestStart();
    mOutputStream->requestStart();
    return true;
}

void AudioEngine::stop() {
    if (mInputStream) mInputStream->stop();
    if (mOutputStream) mOutputStream->stop();
    if (mInputStream) mInputStream->close();
    if (mOutputStream) mOutputStream->close();
    mInputStream.reset();
    mOutputStream.reset();
}

void AudioEngine::setGain(float left, float right) {
    mGainProcessor->setGains(left, right);
}

void AudioEngine::setEQ(const float* gains, int count) {
    for (int i = 0; i < count && i < 13; ++i) {
        mEQProcessor->setBandGain(i, gains[i]);
    }
}

void AudioEngine::setSuppression(float level) {
    mSuppressionLevel = level;
    // suppression level maps to a noise floor reduction 
}

void AudioEngine::setTone(float tone) {
    mToneProcessor->setTone(tone);
}

void AudioEngine::setProcessingMode(int mode) {
    mProcessingMode = mode;
    // Mode 0: RNN (Standard)
    // Mode 1: DTLN (High Suppression)
    if (mode == 1) {
        // DTLN tends to be very quiet, so we ensure suppression isn't cutting too much
        mSuppressionLevel = std::max(mSuppressionLevel, 0.4f);
    }
}

void AudioEngine::writeToBuffer(const float* data, int numFrames) {
    for (int i = 0; i < numFrames; ++i) {
        mRingBuffer[mWriteIndex] = data[i];
        mWriteIndex = (mWriteIndex + 1) % kBufferCapacity;
    }
}

int AudioEngine::readFromBuffer(float* data, int numFrames) {
    int available = (mWriteIndex - mReadIndex + kBufferCapacity) % kBufferCapacity;
    
    // DRIFT CORRECTION: If buffer is too full (> 30ms), skip to recent samples
    if (available > 1440) {
        mReadIndex = (mWriteIndex - 480 + kBufferCapacity) % kBufferCapacity;
        available = 480;
    }

    int toRead = std::min(numFrames, available);
    for (int i = 0; i < toRead; ++i) {
        data[i] = mRingBuffer[mReadIndex];
        mReadIndex = (mReadIndex + 1) % kBufferCapacity;
    }
    return toRead;
}

oboe::DataCallbackResult AudioEngine::onAudioReady(
    oboe::AudioStream *audioStream,
    void *audioData,
    int32_t numFrames) {

    float *data = static_cast<float *>(audioData);

    if (audioStream->getDirection() == oboe::Direction::Input) {
        float maxPeak = 0.0f;
        
        if (mProcessingMode == 0) {
            // --- RNN (48kHz) ---
            for (int i = 0; i < numFrames; ++i) {
                float absVal = fabsf(data[i]);
                if (absVal > maxPeak) maxPeak = absVal;

                mDenoiseBuffer[mDenoiseIndex++] = data[i];
                if (mDenoiseIndex >= 480) {
                    if (mDenoiseState) {
                        float vad = rnnoise_process_frame(mDenoiseState, mDenoiseBuffer, mDenoiseBuffer);
                        // Less aggressive suppression curve to avoid "muffling"
                        if (vad < mSuppressionLevel) {
                            float softSuppression = 0.3f + (0.7f * vad / (mSuppressionLevel + 0.0001f));
                            for (int j=0; j<480; ++j) mDenoiseBuffer[j] *= softSuppression;
                        }
                    }
                    writeToBuffer(mDenoiseBuffer, 480);
                    mDenoiseIndex = 0;
                }
            }
        } else if (mProcessingMode == 1) {
            // --- DTLN (16kHz internal) ---
            for (int i = 0; i < numFrames; ++i) {
                float absVal = fabsf(data[i]);
                if (absVal > maxPeak) maxPeak = absVal;

                // Downsample 48k -> 16k (Moving Average Low-Pass)
                mDownsampleSum += data[i];
                if (mResamplePhase == 2) {
                    m16kBuffer[m16kIndex++] = mDownsampleSum / 3.0f;
                    mDownsampleSum = 0.0f;
                    
                    if (m16kIndex >= 128) {
                        float dtlnOut[128];
                        mDTLNProcessor->process(m16kBuffer, dtlnOut);
                        
                        // Upsample 16k -> 48k (Linear Interpolation)
                        float upsampled[384];
                        float lastSample = mPrevDtlnOut;
                        for (int j=0; j<128; ++j) {
                            float current = dtlnOut[j];
                            upsampled[j*3]   = (lastSample * 2.0f + current) / 3.0f;
                            upsampled[j*3+1] = (lastSample + current * 2.0f) / 3.0f;
                            upsampled[j*3+2] = current;
                            lastSample = current;
                        }
                        mPrevDtlnOut = lastSample;
                        
                        writeToBuffer(upsampled, 384);
                        m16kIndex = 0;
                    }
                }
                mResamplePhase = (mResamplePhase + 1) % 3;
            }
        } else {
            // --- BYPASS MODE (-1) ---
            for (int i = 0; i < numFrames; ++i) {
                float absVal = fabsf(data[i]);
                if (absVal > maxPeak) maxPeak = absVal;
            }
            writeToBuffer(data, numFrames);
        }
        mInputLevel = mInputLevel * 0.8f + maxPeak * 0.2f;
        return oboe::DataCallbackResult::Continue;
    }

    // --- OUTPUT CALLBACK ---
    int32_t channelCount = audioStream->getChannelCount();
    std::vector<float> input(numFrames, 0.0f);
    readFromBuffer(input.data(), numFrames);

    float maxOutPeak = 0.0f;
    for (int32_t i = 0; i < numFrames; ++i) {
        float sample = input[i];

        // 1. Tone (Tilt)
        sample = mToneProcessor->process(sample);
        // 2. EQ
        sample = mEQProcessor->process(sample);
        // 3. DRC
        sample = mDRC->process(sample);
        // 4. Stereo Balance
        float left = sample;
        float right = sample;
        mGainProcessor->process(left, right);

        // Copy mono mix to caption buffer for STT
        float mono = (left + right) * 0.5f;
        writeToCaptionBuffer(mono);

        float peak = std::max(fabsf(left), fabsf(right));
        if (peak > maxOutPeak) maxOutPeak = peak;

        // Write to output stream
        if (channelCount == 2) {
            data[i * 2] = left;
            data[i * 2 + 1] = right;
        } else {
            data[i] = (left + right) * 0.5f;
        }
    }
    // Smooth peak tracking
    mOutputLevel = mOutputLevel * 0.8f + maxOutPeak * 0.2f;

    return oboe::DataCallbackResult::Continue;
}

void AudioEngine::writeToCaptionBuffer(float sample) {
    mCaptionBuffer[mCaptionWriteIndex] = sample;
    mCaptionWriteIndex = (mCaptionWriteIndex + 1) % kCaptionCapacity;
}

int AudioEngine::getCaptionAvailable() {
    return (mCaptionWriteIndex - mCaptionReadIndex + kCaptionCapacity) % kCaptionCapacity;
}

int AudioEngine::getCaptionData(float* out, int maxFrames) {
    int available = getCaptionAvailable();
    int toRead = std::min(maxFrames, available);
    for (int i = 0; i < toRead; ++i) {
        out[i] = mCaptionBuffer[mCaptionReadIndex];
        mCaptionReadIndex = (mCaptionReadIndex + 1) % kCaptionCapacity;
    }
    return toRead;
}
