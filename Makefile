EXECUTABLE = modular-audio
SWIFT_FILES = main.swift WAVWriter.swift AudioModule.swift ModuleManager.swift HammondModule.swift LeslieModule.swift
METAL_FILES = hammond.metal leslie.metal audio_utils.metal
METAL_LIBS = hammond.metallib leslie.metallib audio_utils.metallib
MODULE_DESCRIPTORS = hammond.json leslie.json
DYNAMIC_LIBS = hammond.dylib leslie.dylib

# Default target builds everything including dynamic modules
all: $(EXECUTABLE) dynamic-modules

# Build shared utility Metal library (static for now)
audio_utils.metallib: audio_utils.metal
	@echo "Building shared utility Metal library..."
	xcrun -sdk macosx metal -gline-tables-only -frecord-sources -o $@ $<

# Build module Metal libraries (static with included utilities)
hammond.metallib: hammond.metal
	@echo "Building Hammond Metal library..."
	xcrun -sdk macosx metal -gline-tables-only -frecord-sources -o $@ $<

leslie.metallib: leslie.metal
	@echo "Building Leslie Metal library..."
	xcrun -sdk macosx metal -gline-tables-only -frecord-sources -o $@ $<

# Build dynamic modules
dynamic-modules: $(DYNAMIC_LIBS)

# Build Hammond dynamic module
hammond.dylib: HammondModule.swift AudioModule.swift hammond.metallib
	@echo "Building Hammond dynamic module..."
	swiftc -emit-library -o $@ HammondModule.swift AudioModule.swift -framework Metal -framework Foundation -Xlinker -install_name -Xlinker @rpath/$@

# Build Leslie dynamic module  
leslie.dylib: LeslieModule.swift AudioModule.swift leslie.metallib
	@echo "Building Leslie dynamic module..."
	swiftc -emit-library -o $@ LeslieModule.swift AudioModule.swift -framework Metal -framework Foundation -Xlinker -install_name -Xlinker @rpath/$@

# Build Swift executable (now without the module sources since they're in dylibs)
$(EXECUTABLE): main.swift WAVWriter.swift AudioModule.swift ModuleManager.swift $(METAL_LIBS) $(MODULE_DESCRIPTORS)
	swiftc -o $@ main.swift WAVWriter.swift AudioModule.swift ModuleManager.swift -framework Metal -framework Foundation

# Run the program
run: $(EXECUTABLE) dynamic-modules
	./$(EXECUTABLE)

# Clean build artifacts
clean:
	rm -f $(EXECUTABLE) $(METAL_LIBS) $(DYNAMIC_LIBS) modular_output.wav hammond_amaj.wav hammond_leslie_amaj.wav hammond_dmaj7.wav hammond_leslie_dmaj7.wav output.wav hammond-organ hammond-leslie

# Clean and rebuild everything
clean-build: clean all

# Test target
test: run
	@if [ -f modular_output.wav ]; then \
		echo "Modular audio processing successful"; \
		ls -la modular_output.wav; \
	else \
		echo "Modular output WAV file not found"; \
		exit 1; \
	fi

# Show available modules
modules: $(EXECUTABLE)
	@echo "Scanning for available modules..."
	@./$(EXECUTABLE) --list-modules 2>/dev/null || echo "No modules found or executable not built"

# Build only static executable (for development/debugging)
static: main.swift WAVWriter.swift AudioModule.swift ModuleManager.swift HammondModule.swift LeslieModule.swift $(METAL_LIBS) $(MODULE_DESCRIPTORS)
	@echo "Building static executable (no dynamic modules)..."
	swiftc -o $(EXECUTABLE) main.swift WAVWriter.swift AudioModule.swift ModuleManager.swift HammondModule.swift LeslieModule.swift -framework Metal -framework Foundation


# Test dynamic loading specifically
test-dynamic: $(EXECUTABLE) dynamic-modules
	@echo "Testing dynamic module loading..."
	@./$(EXECUTABLE) --list-modules || echo "Dynamic module test failed"

# Show module information
info:
	@echo "System build info:"
	@echo "   Static executable: $(EXECUTABLE)"
	@echo "   Dynamic modules: $(DYNAMIC_LIBS)"
	@echo "   Metal libraries: $(METAL_LIBS)"
	@echo "   Descriptors: $(MODULE_DESCRIPTORS)"

.PHONY: all run clean clean-build test dynamic-modules static test-dynamic info