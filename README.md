# Modular GPGPU Audio Effects Chain

This repository proposes a modular GPU audio effect chain with dynamic GPU audio effect plugin loading on MacOS/Metal. It's a demo/proof-of-concept that implements its stated goals, but might be extended in the future.

The scenario is we have two audio processing modules:
- Synthesis, Hammond Module: Simple Organ emulation with parallel additive tonewheel synthesis
- Effect, Leslie Module: currently just at tremolo (see `leslie.metal`).

Both modules run via GPU compute. The key is the synthesis and effect modules can be written by two teams, and only the interface between them is declared; the effects can be considered black boxes. At the same time we'd like to keep buffers on the GPU where possible, especially for discrete GPU systems. For shared memory systems the overhead is of course less, unless we're moving to and from DAW buffers in a `ProcessBlock`-like call.

Note: If something looks like a bug in the driver Swift code it likely is; this is a migration from an experiment written in Objective-C to Swift. I'm still learning Swift and wasn't great at ObjC before, so please feel free to contact about any errors.

## Usage

### Build and run
```bash
make run
```

### Enumerate audio modules
```bash
./modular-audio --list-modules
```

## Details
- `make all` - Build everything including dynamic modules (or just `make`)
- `make clean` - Remove all build artifacts and output files
- `make clean-build` - Clean and rebuild everything from scratch
- `make run` - Build and execute the modular audio program
- `make test` - Build, run, and verify wav was generated
- `make test-dynamic` - Test dynamic module loading functionality

Note that `make clean && make run` will run the project in dynamic mode; to do this the dynamic metal libraries are marked as a dependency of the main target but do not need to be; the goal is to have different modules built by different teams or even companies.

## Build Artifacts
- `modular-audio` - Executable
- `*.metallib` - Compiled effect Metal compute shaders
- `*.dylib`, - Compiled effect CPU code
- `*.json` - Interface descriptions
- `modular_output.wav` - Generated stereo audio output

## References

Apple documentation: Metal Dynamic Libraries: https://developer.apple.com/documentation/metal/metal-dynamic-libraries
