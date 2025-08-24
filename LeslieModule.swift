import Metal
import Foundation

// Leslie speaker module conforming to AudioModule protocol
class LeslieModule: BaseAudioModule {
    private let computePipelineState: MTLComputePipelineState
    private var currentTime: Float = 0.0
    
    required init(device: MTLDevice, libraryURL: URL) throws {
        // Load Metal library and create pipeline state first
        let library = try device.makeLibrary(URL: libraryURL)
        
        guard let function = library.makeFunction(name: "leslie_effect") else {
            throw ModuleError.functionNotFound("leslie_effect")
        }
        
        self.computePipelineState = try device.makeComputePipelineState(function: function)
        
        // Initialize base class after setting pipeline state
        try super.init(device: device, libraryURL: libraryURL)
        
        // Dynamic libraries are now set up and will be used for shared functions in Metal shaders
    }
    
    override func process(inputBuffer: MTLBuffer, 
                         sampleCount: Int, 
                         sampleRate: Float,
                         parameters: [String: Float]) throws -> [MTLBuffer] {
        
        let bufferSize = sampleCount * MemoryLayout<Float>.size
        
        // Create stereo output buffers
        guard let outputBufferL = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let outputBufferR = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw ModuleError.processingFailed("Could not create output buffers")
        }
        
        // Extract Leslie parameters
        let hornSpeed = getLeslieSpeed(parameters: parameters, component: "horn")
        let drumSpeed = getLeslieSpeed(parameters: parameters, component: "drum")
        let wetMix = parameters["wet_mix"] ?? 0.85
        
        // Create Leslie parameters
        var leslieParams = LeslieParams(
            sampleRate: sampleRate,
            sampleCount: UInt32(sampleCount),
            hornSpeed: hornSpeed,
            drumSpeed: drumSpeed,
            time: currentTime,
            wetMix: wetMix
        )
        
        guard let paramsBuffer = device.makeBuffer(bytes: &leslieParams, 
                                                  length: MemoryLayout<LeslieParams>.size, 
                                                  options: .storageModeShared) else {
            throw ModuleError.processingFailed("Could not create params buffer")
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ModuleError.processingFailed("Could not create command buffer or encoder")
        }
        
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setBuffer(paramsBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(inputBuffer, offset: 0, index: 1)  // Direct GPU buffer input
        computeEncoder.setBuffer(outputBufferL, offset: 0, index: 2)
        computeEncoder.setBuffer(outputBufferR, offset: 0, index: 3)
        
        let threadsPerThreadgroup = MTLSize(width: 256, height: 1, depth: 1)
        let threadgroupsPerGrid = MTLSize(
            width: (sampleCount + 255) / 256,
            height: 1,
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Update time for continuous rotation
        currentTime += Float(sampleCount) / sampleRate
        
        return [outputBufferL, outputBufferR]  // Leslie outputs stereo
    }
    
    override func reset() {
        super.reset()
        currentTime = 0.0
    }
    
    private func getLeslieSpeed(parameters: [String: Float], component: String) -> Float {
        let speed = parameters["\(component)_speed"] ?? 1.0  // 0 = slow, 1 = fast
        
        if component == "horn" {
            return speed > 0.5 ? 6.75 : 0.767  // Fast: 6.75 Hz, Slow: 0.767 Hz
        } else {  // drum
            return speed > 0.5 ? 6.583 : 0.633  // Fast: 6.583 Hz, Slow: 0.633 Hz
        }
    }
}

// Leslie parameters structure
private struct LeslieParams {
    let sampleRate: Float
    let sampleCount: UInt32
    let hornSpeed: Float
    let drumSpeed: Float
    let time: Float
    let wetMix: Float
}

// NOTE: This function is exported for dynamic loading
@_cdecl("createLeslieModule")
public func createLeslieModule(devicePtr: UnsafeMutableRawPointer, libraryPath: UnsafeMutablePointer<CChar>) -> UnsafeMutableRawPointer? {
    
    // Convert C parameters back to Swift types
    let device = Unmanaged<MTLDevice>.fromOpaque(devicePtr).takeUnretainedValue()
    let libraryString = String(cString: libraryPath)
    let libraryURL = URL(fileURLWithPath: libraryString)
    
    do {
        let module = try LeslieModule(device: device, libraryURL: libraryURL)
        return Unmanaged.passRetained(module).toOpaque()
    } catch {
        print("ERROR: Leslie module creation failed: \(error)")
        return nil
    }
}

// Helper function to destroy module instance
@_cdecl("destroyLeslieModule")
public func destroyLeslieModule(modulePtr: UnsafeMutableRawPointer) {
    Unmanaged<LeslieModule>.fromOpaque(modulePtr).release()
}