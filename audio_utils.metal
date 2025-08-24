#include <metal_stdlib>
using namespace metal;

// Utility functions used across moduls

inline float lerp(float a, float b, float t) {
    return a + t * (b - a);
}

inline float soft_clip(float sample, float threshold = 0.8) {
    if (abs(sample) < threshold) {
        return sample;
    }
    
    float sign = sample < 0.0 ? -1.0 : 1.0;
    float abs_sample = abs(sample);
    return sign * (threshold + (1.0 - threshold) * (1.0 - exp(-(abs_sample - threshold))));
}

inline float lowpass_coefficient(float cutoff_hz, float sample_rate) {
    float omega = 2.0 * M_PI_F * cutoff_hz / sample_rate;
    return 1.0 - exp(-omega);
}

inline float highpass_coefficient(float cutoff_hz, float sample_rate) {
    float omega = 2.0 * M_PI_F * cutoff_hz / sample_rate;
    return exp(-omega);
}

inline float db2lin(float db) {
    return pow(10.0, db / 20.0);
}

inline float lin2db(float linear) {
    return 20.0 * log10(max(linear, 1e-10));
}

inline float applyRampedGain(float sample, float current_gain, float target_gain, float ramp_rate) {
    float new_gain = lerp(current_gain, target_gain, ramp_rate);
    return sample * new_gain;
}

inline float delayReadLerp(device const float* delay_buffer, int buffer_size, float read_pos) {
    int int_pos = (int)read_pos;
    float frac = read_pos - int_pos;
    int pos0 = int_pos % buffer_size;
    int pos1 = (int_pos + 1) % buffer_size;
    return lerp(delay_buffer[pos0], delay_buffer[pos1], frac);
}

// CLEANUP: we can simply inline this in the one place it's used. At least get a better name.
inline float2 panMono2stereo(float mono_sample, float pan_position) {
    // pan_position: -1.0 (full left) to +1.0 (full right)
    float angle = (pan_position + 1.0) * M_PI_F / 4.0; // 0 to PI/2
    return float2(mono_sample * cos(angle), mono_sample * sin(angle));
}

// For uniform sinf across future platforms

// (currently MacOS only though)
inline float fast_sin(float x) {
    // Wrap x to [-PI, PI] range
    while (x > M_PI_F) x -= 2.0 * M_PI_F;
    while (x < -M_PI_F) x += 2.0 * M_PI_F;

    float x2 = x * x;
    return x * (1.0 - x2 / 6.0 * (1.0 - x2 / 20.0));
}

inline float fast_cos(float x) {
    return fast_sin(x + M_PI_F / 2.0);
}

struct BiquadCoeffs {
    float b0, b1, b2;
    float a1, a2;
};

inline float processBiquad(float input, 
                           thread float* x1, thread float* x2,
                           thread float* y1, thread float* y2,
                           BiquadCoeffs coeffs) {
    float output = coeffs.b0 * input 
        + coeffs.b1 * (*x1) 
        + coeffs.b2 * (*x2)
        - coeffs.a1 * (*y1) 
        - coeffs.a2 * (*y2);

    *x2 = *x1;
    *x1 = input;
    *y2 = *y1;
    *y1 = output;

    return output;
}

inline BiquadCoeffs buildLowpass(float freq, float q, float sample_rate) {
    float omega = 2.0 * M_PI_F * freq / sample_rate;
    float sin_omega = sin(omega);
    float cos_omega = cos(omega);
    float alpha = sin_omega / (2.0 * q);
    
    float norm = 1.0 / (1.0 + alpha);
    
    BiquadCoeffs coeffs;
    coeffs.b0 = (1.0 - cos_omega) * 0.5 * norm;
    coeffs.b1 = (1.0 - cos_omega) * norm;
    coeffs.b2 = (1.0 - cos_omega) * 0.5 * norm;
    coeffs.a1 = -2.0 * cos_omega * norm;
    coeffs.a2 = (1.0 - alpha) * norm;
    
    return coeffs;
}

inline BiquadCoeffs buildHighpass(float freq, float q, float sample_rate) {
    float omega = 2.0 * M_PI_F * freq / sample_rate;
    float sin_omega = sin(omega);
    float cos_omega = cos(omega);
    float alpha = sin_omega / (2.0 * q);
    
    float norm = 1.0 / (1.0 + alpha);
    
    BiquadCoeffs coeffs;
    coeffs.b0 = (1.0 + cos_omega) * 0.5 * norm;
    coeffs.b1 = -(1.0 + cos_omega) * norm;
    coeffs.b2 = (1.0 + cos_omega) * 0.5 * norm;
    coeffs.a1 = -2.0 * cos_omega * norm;
    coeffs.a2 = (1.0 - alpha) * norm;
    
    return coeffs;
}