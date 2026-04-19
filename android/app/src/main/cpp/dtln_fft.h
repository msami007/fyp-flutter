#ifndef DTLN_FFT_H
#define DTLN_FFT_H

#include <stdlib.h>
#include <math.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float r;
    float i;
} dtln_fft_cpx;

typedef struct dtln_fft_state* dtln_fft_cfg;

dtln_fft_cfg dtln_fft_alloc(int nfft, int inverse_fft, void* mem, size_t* lenmem);
void dtln_fft(dtln_fft_cfg cfg, const dtln_fft_cpx* fin, dtln_fft_cpx* fout);
void dtln_fft_free(dtln_fft_cfg cfg);

#ifdef __cplusplus
}
#endif

#endif
