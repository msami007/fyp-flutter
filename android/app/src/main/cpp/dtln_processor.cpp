#include "dtln_processor.h"
#include <cmath>
#include <cstring>
#include <algorithm>

DTLNProcessor::DTLNProcessor() {
    mStates1.resize(512, 0.0f);
    mStates2.resize(512, 0.0f);
    
    // We use RNNoise's FFT implementation which is already in the build
    // Arguments are: nfft, inverse, mem, lenmem, arch
    mFftCfg = rnn_fft_alloc(512, nullptr, nullptr, 0);
    mIfftCfg = rnn_fft_alloc(512, nullptr, nullptr, 0); 
}

DTLNProcessor::~DTLNProcessor() {
    if (mInterpreter1) TfLiteInterpreterDelete(mInterpreter1);
    if (mModel1) TfLiteModelDelete(mModel1);
    if (mInterpreter2) TfLiteInterpreterDelete(mInterpreter2);
    if (mModel2) TfLiteModelDelete(mModel2);
    
    // rnn_fft_free takes (cfg, arch)
    if (mFftCfg) rnn_fft_free(mFftCfg, 0);
    if (mIfftCfg) rnn_fft_free(mIfftCfg, 0);
}

bool DTLNProcessor::init(const uint8_t* model1_data, size_t model1_size,
                         const uint8_t* model2_data, size_t model2_size) {
    mModel1 = TfLiteModelCreate(model1_data, model1_size);
    if (!mModel1) return false;

    TfLiteInterpreterOptions* options = TfLiteInterpreterOptionsCreate();
    TfLiteInterpreterOptionsSetNumThreads(options, 2);
    
    mInterpreter1 = TfLiteInterpreterCreate(mModel1, options);
    TfLiteInterpreterOptionsDelete(options);
    
    if (!mInterpreter1 || TfLiteInterpreterAllocateTensors(mInterpreter1) != kTfLiteOk) {
        return false;
    }

    mModel2 = TfLiteModelCreate(model2_data, model2_size);
    if (!mModel2) return false;

    options = TfLiteInterpreterOptionsCreate();
    TfLiteInterpreterOptionsSetNumThreads(options, 2);
    mInterpreter2 = TfLiteInterpreterCreate(mModel2, options);
    TfLiteInterpreterOptionsDelete(options);

    if (!mInterpreter2 || TfLiteInterpreterAllocateTensors(mInterpreter2) != kTfLiteOk) {
        return false;
    }

    return true;
}

void DTLNProcessor::process(const float* input, float* output) {
    // 1. Shift buffer and add new input
    memmove(mInBuf, mInBuf + 128, (512 - 128) * sizeof(float));
    memcpy(mInBuf + (512 - 128), input, 128 * sizeof(float));

    // 2. Windowing (Sine window)
    float windowed[512];
    for (int i = 0; i < 512; ++i) {
        windowed[i] = mInBuf[i] * sinf(M_PI * (i + 0.5f) / 512.0f);
    }

    // 3. FFT
    kiss_fft_cpx cpxIn[512];
    kiss_fft_cpx cpxOut[512];
    for (int i = 0; i < 512; ++i) {
        cpxIn[i].r = windowed[i];
        cpxIn[i].i = 0;
    }
    rnn_fft(mFftCfg, cpxIn, cpxOut, 0);

    // RNNoise FFT scales by 1/N. We undo this so the AI gets normal magnitudes.
    for (int i = 0; i < 512; ++i) {
        cpxOut[i].r *= 512.0f;
        cpxOut[i].i *= 512.0f;
    }

    // 4. Magnitude and Phase
    float magnitude[257];
    float phase[257];
    for (int i = 0; i < 257; ++i) {
        magnitude[i] = sqrtf(cpxOut[i].r * cpxOut[i].r + cpxOut[i].i * cpxOut[i].i);
        phase[i] = atan2f(cpxOut[i].i, cpxOut[i].r);
    }

    // 5. Model 1 Inference (Magnitude -> Mask)
    TfLiteTensor* input1 = TfLiteInterpreterGetInputTensor(mInterpreter1, 0);
    TfLiteTensor* state1_in = TfLiteInterpreterGetInputTensor(mInterpreter1, 1);
    
    memcpy(TfLiteTensorData(input1), magnitude, 257 * sizeof(float));
    memcpy(TfLiteTensorData(state1_in), mStates1.data(), 512 * sizeof(float));

    TfLiteInterpreterInvoke(mInterpreter1);

    const TfLiteTensor* output1 = TfLiteInterpreterGetOutputTensor(mInterpreter1, 0);
    const TfLiteTensor* state1_out = TfLiteInterpreterGetOutputTensor(mInterpreter1, 1);

    memcpy(mStates1.data(), TfLiteTensorData(const_cast<TfLiteTensor*>(state1_out)), 512 * sizeof(float));

    const float* mask = (const float*)TfLiteTensorData(const_cast<TfLiteTensor*>(output1));

    // 6. Apply Mask
    for (int i = 0; i < 257; ++i) {
        cpxOut[i].r *= mask[i];
        cpxOut[i].i *= mask[i];
    }

    // 7. Inverse FFT to get back to time domain (sort of, this is the complex output for Model 2)
    // DTLN Model 2 takes the IFFT of the masked complex spectrum
    // We recreate full spectrum for IFFT
    for (int i = 1; i < 255; ++i) {
        cpxOut[512 - i].r = cpxOut[i].r;
        cpxOut[512 - i].i = -cpxOut[i].i;
    }
    
    rnn_ifft(mIfftCfg, cpxOut, cpxIn, 0);
    
    // 8. Model 2 Inference (Time Domain -> Denoised)
    TfLiteTensor* input2 = TfLiteInterpreterGetInputTensor(mInterpreter2, 0);
    TfLiteTensor* state2_in = TfLiteInterpreterGetInputTensor(mInterpreter2, 1);

    for (int i = 0; i < 512; ++i) ((float*)TfLiteTensorData(input2))[i] = cpxIn[i].r / 512.0f;
    memcpy(TfLiteTensorData(state2_in), mStates2.data(), 512 * sizeof(float));

    TfLiteInterpreterInvoke(mInterpreter2);

    const TfLiteTensor* output2 = TfLiteInterpreterGetOutputTensor(mInterpreter2, 0);
    const TfLiteTensor* state2_out = TfLiteInterpreterGetOutputTensor(mInterpreter2, 1);

    memcpy(mStates2.data(), TfLiteTensorData(const_cast<TfLiteTensor*>(state2_out)), 512 * sizeof(float));

    const float* denoised = (const float*)TfLiteTensorData(const_cast<TfLiteTensor*>(output2));

    // 9. Overlap-Add
    for (int i = 0; i < 512; ++i) {
        mOutBuf[i] += denoised[i] * sinf(M_PI * (i + 0.5f) / 512.0f);
    }

    // New output is the first 128 samples
    // Correct the amplitude scaling from overlap-add of 4 sine windows (sum-of-squares = 2.0)
    for (int i = 0; i < 128; ++i) {
        output[i] = mOutBuf[i] * 0.5f;
    }

    // Shift output buffer
    memmove(mOutBuf, mOutBuf + 128, (512 - 128) * sizeof(float));
    memset(mOutBuf + (512 - 128), 0, 128 * sizeof(float));
}
