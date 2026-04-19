#ifndef DTLN_PROCESSOR_H
#define DTLN_PROCESSOR_H

#include <vector>
#include <memory>
#include "tflite_c_api.h"
#include "kiss_fft.h"

class DTLNProcessor {
public:
    DTLNProcessor();
    ~DTLNProcessor();

    bool init(const uint8_t* model1_data, size_t model1_size,
              const uint8_t* model2_data, size_t model2_size);

    void process(const float* input, float* output);

private:
    TfLiteModel* mModel1 = nullptr;
    TfLiteInterpreter* mInterpreter1 = nullptr;
    TfLiteModel* mModel2 = nullptr;
    TfLiteInterpreter* mInterpreter2 = nullptr;

    // Use the RNNoise-prefixed FFT types
    kiss_fft_state* mFftCfg = nullptr;
    kiss_fft_state* mIfftCfg = nullptr;

    std::vector<float> mStates1;
    std::vector<float> mStates2;
    float mInBuf[512] = {0};
    float mOutBuf[512] = {0};

    void runInference();
};

#endif
