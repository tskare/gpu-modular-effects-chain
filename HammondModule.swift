import Metal
import Foundation

class HammondModule: BaseAudioModule {
    private let hammondPipelineState: MTLComputePipelineState
    private let keyclickPipelineState: MTLComputePipelineState
    
    private static let noteFrequencies: [String: Float] = [
        "C3": 130.81,
        "D3": 146.83,
        "E3": 164.81,
        "F#3": 185.00,
        "G3": 196.00,
        "A3": 220.00,
        "B3": 246.94,
        "C4": 261.63,
        "C#4": 277.18,
        "D4": 293.66,
        "E4": 329.63,
        "F4": 349.23,
        "F#4": 369.99,
        "G4": 392.00,
        "A4": 440.00,
        "B4": 493.88
    ]
    
    required init(device: MTLDevice, libraryURL: URL) throws {
        let library = try device.makeLibrary(URL: libraryURL)
        
        guard let hammondFunction = library.makeFunction(name: "hammond_synthesis") else {
            throw ModuleError.functionNotFound("hammond_synthesis")
        }
        
        guard let keyclickFunction = library.makeFunction(name: "hammond_keyclick") else {
            throw ModuleError.functionNotFound("hammond_keyclick")
        }
        
        self.hammondPipelineState = try device.makeComputePipelineState(function: hammondFunction)
        self.keyclickPipelineState = try device.makeComputePipelineState(function: keyclickFunction)
        
        try super.init(device: device, libraryURL: libraryURL)
        
    }
    
    override func process(inputBuffer: MTLBuffer, 
                         sampleCount: Int, 
                         sampleRate: Float,
                         parameters: [String: Float]) throws -> [MTLBuffer] {
        
        // Hammond generates audio, hardcoded input chord.
        // No input audio signal.
        let bufferSize = sampleCount * MemoryLayout<Float>.size
        
        guard let outputBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw ModuleError.processingFailed("Could not create output buffer")
        }
        
        memset(outputBuffer.contents(), 0, bufferSize)
        
        let chordNotes = createAMajorChord(parameters: parameters)
        
        var hammondParams = HammondParams(
            sampleRate: sampleRate,
            sampleCount: UInt32(sampleCount),
            numActiveNotes: UInt32(chordNotes.count)
        )
        
        guard let paramsBuffer = device.makeBuffer(bytes: &hammondParams, 
                                                  length: MemoryLayout<HammondParams>.size, 
                                                  options: .storageModeShared) else {
            throw ModuleError.processingFailed("Fatal: error creating &hammondParams")
        }
        
        // CLEANUP: Still learning Swift... cleaner way to do this? And below.
        var metalNotes: [(Float, (Float, Float, Float, Float, Float, Float, Float, Float, Float), Float)] = []
        for note in chordNotes {
            metalNotes.append((note.frequency, note.drawbarsTuple, note.amplitude))
        }
        
        guard let notesBuffer = device.makeBuffer(bytes: &metalNotes, 
                                                 length: metalNotes.count * MemoryLayout<(Float, (Float, Float, Float, Float, Float, Float, Float, Float, Float), Float)>.size, 
                                                 options: .storageModeShared) else {
            throw ModuleError.processingFailed("Fatal: error creating &metalNotes")
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ModuleError.processingFailed("Fatal: error in makeCommadnBuffer for commands")
        }
        
        guard let hammondEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ModuleError.processingFailed("Fatal: error in makeCommandBuffer for hammond")
        }
        
        hammondEncoder.setComputePipelineState(hammondPipelineState)
        hammondEncoder.setBuffer(paramsBuffer, offset: 0, index: 0)
        hammondEncoder.setBuffer(notesBuffer, offset: 0, index: 1)
        hammondEncoder.setBuffer(outputBuffer, offset: 0, index: 2)

        let threadsPerThreadgroup = MTLSize(width: 32, height: 1, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (sampleCount + 31) / 32,
            height: chordNotes.count,
            depth: 1
        )
        
        hammondEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        hammondEncoder.endEncoding()
        
        // Key click
        // TODO: note this is a no-op; check the .Metal file
        // but we want to experiment launching two kernels on the same data.
        guard let keyclickEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ModuleError.processingFailed("Could not create keyclick encoder")
        }
        
        keyclickEncoder.setComputePipelineState(keyclickPipelineState)
        keyclickEncoder.setBuffer(paramsBuffer, offset: 0, index: 0)
        keyclickEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
        let keyclickThreadsPerGroup = MTLSize(width: 256, height: 1, depth: 1)
        let keyclickThreadgroups = MTLSize(
            width: (sampleCount + 255) / 256,
            height: 1,
            depth: 1
        )
        
        keyclickEncoder.dispatchThreadgroups(keyclickThreadgroups, threadsPerThreadgroup: keyclickThreadsPerGroup)
        keyclickEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return [outputBuffer]  // organ outputs mono
    }
    
    private func createAMajorChord(parameters: [String: Float]) -> [NoteInfo] {
        let drawbar16 = parameters["drawbar_16"] ?? 6.0
        let drawbar513 = parameters["drawbar_513"] ?? 4.0
        let drawbar8 = parameters["drawbar_8"] ?? 8.0
        let drawbar4 = parameters["drawbar_4"] ?? 7.0
        let drawbar223 = parameters["drawbar_223"] ?? 3.0
        let drawbar2 = parameters["drawbar_2"] ?? 2.0
        let drawbar135 = parameters["drawbar_135"] ?? 1.0
        let drawbar113 = parameters["drawbar_113"] ?? 1.0
        let drawbar1 = parameters["drawbar_1"] ?? 0.0
        
        let amplitude = parameters["amplitude"] ?? 0.8
        
        return [
            NoteInfo(frequency: HammondModule.noteFrequencies["A3"]! / 2.0,
                    drawbars: [8, 0, 6, 0, 0, 0, 0, 0, 0],
                    amplitude: amplitude * 0.7),
            NoteInfo(frequency: HammondModule.noteFrequencies["A3"]!,
                    drawbars: [drawbar16, drawbar513, drawbar8, drawbar4, drawbar223, drawbar2, drawbar135, drawbar113, drawbar1],
                    amplitude: amplitude),
            NoteInfo(frequency: HammondModule.noteFrequencies["C#4"]!,
                    drawbars: [drawbar16*0.5, drawbar513*0.5, drawbar8, drawbar4*0.8, drawbar223*0.6, drawbar2*0.5, drawbar135*0.4, drawbar113*0.3, drawbar1*0.2],
                    amplitude: amplitude * 0.8),
            NoteInfo(frequency: HammondModule.noteFrequencies["E4"]!,
                    drawbars: [drawbar16*0.2, drawbar513*0.2, drawbar8, drawbar4*0.6, drawbar223*0.5, drawbar2*0.6, drawbar135*0.5, drawbar113*0.4, drawbar1*0.3],
                    amplitude: amplitude * 0.6)
        ]
    }
}

private struct NoteInfo {
    let frequency: Float
    let drawbars: [Float]
    let amplitude: Float
    
    init(frequency: Float, drawbars: [Float], amplitude: Float = 1.0) {
        self.frequency = frequency
        self.amplitude = amplitude
        
        let normalizedDrawbars = Array(drawbars.prefix(9)) + Array(repeating: 0.0, count: max(0, 9 - drawbars.count))
        self.drawbars = normalizedDrawbars
    }
    
    var drawbarsTuple: (Float, Float, Float, Float, Float, Float, Float, Float, Float) {
        return (
            drawbars[0], drawbars[1], drawbars[2],
            drawbars[3], drawbars[4], drawbars[5],
            drawbars[6], drawbars[7], drawbars[8]
        )
    }
}

private struct HammondParams {
    let sampleRate: Float
    let sampleCount: UInt32
    let numActiveNotes: UInt32
}

@_cdecl("createHammondModule")
public func createHammondModule(devicePtr: UnsafeMutableRawPointer, libraryPath: UnsafeMutablePointer<CChar>) -> UnsafeMutableRawPointer? {
    let device = Unmanaged<MTLDevice>.fromOpaque(devicePtr).takeUnretainedValue()
    let libraryString = String(cString: libraryPath)
    let libraryURL = URL(fileURLWithPath: libraryString)
    
    do {
        let module = try HammondModule(device: device, libraryURL: libraryURL)
        return Unmanaged.passRetained(module).toOpaque()
    } catch {
        print("ERROR: Hammond module creation failed: \(error)")
        return nil
    }
}

@_cdecl("destroyHammondModule")
public func destroyHammondModule(modulePtr: UnsafeMutableRawPointer) {
    Unmanaged<HammondModule>.fromOpaque(modulePtr).release()
}