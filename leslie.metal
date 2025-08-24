#include <metal_stdlib>
using namespace metal;

#include "audio_utils.metal"

// NOTE: This is not a real Leslie effect; it's currently a tremolo!
// Does not affect the intent of the demo, but we need to rename or preferably
// Implement a real Leslie simulation via fractional delay lines

struct LeslieParams {
    float sampleRate;
    uint sampleCount;
    float hornSpeed;  // Hz
    float drumSpeed;  // Hz
    float time;       // for LFO
    float wetMix;
};

// TODO: not complete, simulates a tremolo
float applyDoppler(float input, float dopplerAmount, float phase) {
    float pitchShift = 1.0 + dopplerAmount * 0.004;
    float phaseModulation = fast_sin(phase * 4.0) * 0.001;
    return input * (pitchShift + phaseModulation);
}

kernel void leslie_effect(device const LeslieParams& params [[buffer(0)]],
                         device const float* inputBuffer [[buffer(1)]],
                         device float* outputBufferL [[buffer(2)]],
                         device float* outputBufferR [[buffer(3)]],
                         uint gid [[thread_position_in_grid]]) {
    
    if (gid >= params.sampleCount) {
        return;
    }
    
    float input = inputBuffer[gid];
    float time = (float(gid) / params.sampleRate) + params.time;

    // TODO: actual Leslie; this is a sort of additive tremolo (or a trem with fast and slow signal)
    // 70/30 mix of slow and fast LFO.
    float bassSignal = input * 0.7;
    float trebleSignal = input * 0.3;

    // Add two tremolo signals, and scale the input
    float hornPhase = 2.0 * M_PI_F * params.hornSpeed * time;
    float hornTremolo = 0.5 + 0.45 * fast_sin(hornPhase);
    float hornDoppler = fast_sin(hornPhase + M_PI_F * 0.5) * 1.0;
    float drumPhase = 2.0 * M_PI_F * params.drumSpeed * time;
    float drumTremolo = 0.5 + 0.35 * fast_sin(drumPhase);
    float drumDoppler = fast_sin(drumPhase + M_PI_F * 0.25) * 0.8;
    float hornProcessed = applyDoppler(trebleSignal, hornDoppler, hornPhase) * hornTremolo;
    float drumProcessed = applyDoppler(bassSignal, drumDoppler, drumPhase) * drumTremolo;

    // Mix
    float2 hornPan = panMono2stereo(hornProcessed, fast_cos(hornPhase) * 0.9);
    float2 drumPan = panMono2stereo(drumProcessed, fast_cos(drumPhase) * 0.9);
    float wetL = hornPan.x + drumPan.x;
    float wetR = hornPan.y + drumPan.y;
    float drySignal = input * (1.0 - params.wetMix);

    // and output
    outputBufferL[gid] = drySignal + wetL * params.wetMix;
    outputBufferR[gid] = drySignal + wetR * params.wetMix;
}