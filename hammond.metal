#include <metal_stdlib>
using namespace metal;

#include "audio_utils.metal"

struct HammondParams {
    float sampleRate;
    uint sampleCount;
    uint numActiveNotes;
};

struct NoteInfo {
    float frequency;
    float drawbars[9];
    float amplitude;
};

// TODO: check these against official data or the literature.
// CLEANUP: Did we use 8 somewhere?
// Likely the real-world ones aren't perfect?
constant float HARMONIC_RATIOS[9] = {
    0.5,
    1.5,
    1.0,
    2.0,
    3.0,
    4.0,
    5.0,
    6.0,
    8.0
};

float calculateTonewheelFreq(float noteFreq, uint harmonicIndex) {
    return noteFreq * HARMONIC_RATIOS[harmonicIndex];
}

kernel void hammond_synthesis(device const HammondParams& params [[buffer(0)]],
                             device const NoteInfo* notes [[buffer(1)]],
                             device float* outputBuffer [[buffer(2)]],
                             uint2 gid [[thread_position_in_grid]]) {
    
    uint sampleIdx = gid.x;
    uint noteIdx = gid.y;
    
    if (sampleIdx >= params.sampleCount || noteIdx >= params.numActiveNotes) {
        return;
    }
    
    float time = float(sampleIdx) / params.sampleRate;
    float sample = 0.0;
    
    NoteInfo note = notes[noteIdx];
    
    // Generate all harmonics for this note
    // Essentially additive synthesis.
    for (uint h = 0; h < 9; h++) {
        float drawbarLevel = note.drawbars[h] / 8.0;  // 8 steps -- CLEANUP: document that!
        if (drawbarLevel > 0.0) {
            float tonewheelFreq = calculateTonewheelFreq(note.frequency, h);
            float phase = 2.0 * M_PI_F * tonewheelFreq * time;
            
            // Add slight phasing so things aren't perfect. Note we'll pass signal to a leslie too.
            float jitter = fast_sin(time * 0.1 + float(h)) * 0.001;
            phase += jitter;
            
            // Synthesize this drawbar.
            float tonewheelOutput = fast_sin(phase);
            
            // optionally add a little octave regardless of setting (optional; fills it out)
            // CLEANUP: remove or uncomment
            //tonewheelOutput += 0.05 * fast_sin(2.0 * phase);
            
            sample += tonewheelOutput * drawbarLevel * note.amplitude;
        }
    }

    // Clip to add some grit
    sample = soft_clip(sample, 0.9);
    
    // Atomic add to output buffer for multiple notes
    atomic_fetch_add_explicit((device atomic<float>*)&outputBuffer[sampleIdx],
        sample, memory_order_relaxed);
}

kernel void hammond_keyclick(device const HammondParams& params [[buffer(0)]],
                           device float* outputBuffer [[buffer(1)]],
                           uint gid [[thread_position_in_grid]]) {
    
    if (gid >= params.sampleCount) {
        return;
    }
    
    // TODO: if/when this becomes a full instrument, we would support adjustable percussion...
    // quick win for a playable instrument.
}
