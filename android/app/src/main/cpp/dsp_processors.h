#ifndef DSP_PROCESSORS_H
#define DSP_PROCESSORS_H

#include <vector>
#include <cmath>
#include <algorithm>

// Simple Biquad Filter for EQ
class BiquadFilter {
public:
    enum Type { Peak, LowShelf, HighShelf };

    BiquadFilter() : mB0(1), mB1(0), mB2(0), mA1(0), mA2(0), mX1(0), mX2(0), mY1(0), mY2(0) {}

    void configure(Type type, float sampleRate, float freq, float gainDb, float Q = 1.0f) {
        float A = powf(10.0f, gainDb / 40.0f);
        float w0 = 2.0f * M_PI * freq / sampleRate;
        float cosW0 = cosf(w0);
        float sinW0 = sinf(w0);
        float alpha = sinW0 / (2.0f * Q);

        float a0;
        if (type == Peak) {
            a0 = 1.0f + alpha / A;
            mB0 = (1.0f + alpha * A) / a0;
            mB1 = -2.0f * cosW0 / a0;
            mB2 = (1.0f - alpha * A) / a0;
            mA1 = -2.0f * cosW0 / a0;
            mA2 = (1.0f - alpha / A) / a0;
        } else if (type == LowShelf) {
            float sqrtA = sqrtf(A);
            a0 = (A + 1) + (A - 1) * cosW0 + 2 * sqrtA * alpha;
            mB0 = A * ((A + 1) - (A - 1) * cosW0 + 2 * sqrtA * alpha) / a0;
            mB1 = 2 * A * ((A - 1) - (A + 1) * cosW0) / a0;
            mB2 = A * ((A + 1) - (A - 1) * cosW0 - 2 * sqrtA * alpha) / a0;
            mA1 = -2 * ((A - 1) + (A + 1) * cosW0) / a0;
            mA2 = ((A + 1) + (A - 1) * cosW0 - 2 * sqrtA * alpha) / a0;
        } else if (type == HighShelf) {
            float sqrtA = sqrtf(A);
            a0 = (A + 1) - (A - 1) * cosW0 + 2 * sqrtA * alpha;
            mB0 = A * ((A + 1) + (A - 1) * cosW0 + 2 * sqrtA * alpha) / a0;
            mB1 = -2 * A * ((A - 1) + (A + 1) * cosW0) / a0;
            mB2 = A * ((A + 1) - (A - 1) * cosW0 - 2 * sqrtA * alpha) / a0;
            mA1 = 2 * ((A - 1) - (A + 1) * cosW0) / a0;
            mA2 = ((A + 1) - (A - 1) * cosW0 - 2 * sqrtA * alpha) / a0;
        }
    }

    float process(float x) {
        float y = mB0 * x + mB1 * mX1 + mB2 * mX2 - mA1 * mY1 - mA2 * mY2;
        mX2 = mX1; mX1 = x;
        mY2 = mY1; mY1 = y;
        return y;
    }

    void reset() {
        mX1 = mX2 = mY1 = mY2 = 0;
    }

private:
    float mB0, mB1, mB2, mA1, mA2;
    float mX1, mX2, mY1, mY2;
};

// 13-band EQ
class MultiBandEQ {
public:
    MultiBandEQ(float sampleRate) : mSampleRate(sampleRate) {
        const float freqs[] = {125, 250, 375, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 7000, 8000};
        for (int i = 0; i < 13; ++i) {
            mFilters[i].configure(BiquadFilter::Peak, mSampleRate, freqs[i], 0.0f, 1.2f);
        }
    }

    void setBandGain(int band, float gainDb) {
        if (band >= 0 && band < 13) {
            const float freqs[] = {125, 250, 375, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 7000, 8000};
            mFilters[band].configure(BiquadFilter::Peak, mSampleRate, freqs[band], gainDb, 1.2f);
        }
    }

    float process(float x) {
        for (int i = 0; i < 13; ++i) {
            x = mFilters[i].process(x);
        }
        return x;
    }

private:
    float mSampleRate;
    BiquadFilter mFilters[13];
};

// Dynamic Range Compressor
class DynamicRangeCompressor {
public:
    DynamicRangeCompressor(float sampleRate) 
        : mThresholdDb(-20.0f), mRatio(4.0f), mAttackMs(5.0f), mReleaseMs(50.0f), 
          mEnvelope(0.0f), mSampleRate(sampleRate) {}

    float process(float x) {
        float absX = fabsf(x);
        float inputDb = 20.0f * log10f(absX + 1e-9f);
        
        // Envelope follower
        float target = (inputDb > mThresholdDb) ? 1.0f : 0.0f;
        float factor = (target > mEnvelope) ? 
            expf(-1.0f / (mAttackMs * mSampleRate * 0.001f)) : 
            expf(-1.0f / (mReleaseMs * mSampleRate * 0.001f));
        mEnvelope = factor * mEnvelope + (1.0f - factor) * target;

        float gain = 1.0f;
        if (inputDb > mThresholdDb) {
            float overThreshold = inputDb - mThresholdDb;
            float reduction = overThreshold * (1.0f - 1.0f / mRatio);
            gain = powf(10.0f, -reduction * mEnvelope / 20.0f);
        }
        
        // Apply Make-up Gain (+12dB) to restore loudness
        return x * gain * 4.0f;
    }

private:
    float mThresholdDb, mRatio, mAttackMs, mReleaseMs;
    float mEnvelope, mSampleRate;
};

// Per-ear Gain and Soft Clipping
class GainProcessor {
public:
    GainProcessor() : mLeftGain(1.0f), mRightGain(1.0f) {}

    void setGains(float l, float r) {
        mLeftGain = l;
        mRightGain = r;
    }

    void process(float& l, float& r) {
        l *= mLeftGain;
        r *= mRightGain;
        l = softClip(l);
        r = softClip(r);
    }

private:
    float mLeftGain, mRightGain;
    float softClip(float x) {
        // High-headroom soft clipping (threshold 0.9)
        if (x > 0.9f) return 0.9f + 0.1f * tanhf((x - 0.9f) / 0.1f);
        if (x < -0.9f) return -0.9f + 0.1f * tanhf((x + 0.9f) / 0.1f);
        return x;
    }
};

// Tilt Filter for Tone Control
class TiltFilter {
public:
    TiltFilter(float sampleRate) : mSampleRate(sampleRate) {
        mLowShelf.configure(BiquadFilter::LowShelf, mSampleRate, 300.0f, 0.0f);
        mHighShelf.configure(BiquadFilter::HighShelf, mSampleRate, 3000.0f, 0.0f);
    }

    void setTone(float tone) {
        // tone 0.0 -> Clarity (High boost, Low cut)
        // tone 1.0 -> Fullness (Low boost, High cut)
        float lowGain = (tone - 0.5f) * 12.0f;
        float highGain = (0.5f - tone) * 12.0f;
        mLowShelf.configure(BiquadFilter::LowShelf, mSampleRate, 300.0f, lowGain);
        mHighShelf.configure(BiquadFilter::HighShelf, mSampleRate, 3000.0f, highGain);
    }

    float process(float x) {
        return mHighShelf.process(mLowShelf.process(x));
    }

private:
    float mSampleRate;
    BiquadFilter mLowShelf;
    BiquadFilter mHighShelf;
};

#endif // DSP_PROCESSORS_H
