import Metal
import Foundation

// Hypothetical module definition
// Some is user-facing, plugin-like: developer, version, etc.
// Other stuff is internal, such as inputChannels, outputChannels, bufferHints.
struct ModuleInfo: Codable {
    let name: String
    let version: String
    let description: String
    let author: String
    let metalLibrary: String
    let dynamicLibrary: String?  // Optional - assumed file name matches metalLibrary if not specified
    let inputChannels: Int
    let outputChannels: Int
    let parameters: [String: ParameterInfo]
    let bufferHints: BufferHints?
    let capabilities: ModuleCapabilities?

    var libraryFile: String {
        return dynamicLibrary ?? metalLibrary.replacingOccurrences(of: ".metallib", with: ".dylib")
    }
}

struct BufferHints: Codable {
    let preferredBufferSize: Int?
    let maxBufferSize: Int?
    let supportsBatchProcessing: Bool?
}

// Module capabilities and constraints
struct ModuleCapabilities: Codable {
    let isGenerator: Bool  // true if module generates audio (ignores input)
    let isEffect: Bool     // true if module processes input
    let supportsStereo: Bool
    let supportsVariableChannels: Bool
    let minSampleRate: Float?
    let maxSampleRate: Float?
    let tags: [String]? // free-form
}

struct ParameterInfo: Codable {
    let name: String
    let type: String  // {float, int, bool, future: enum, future: string}
    let defaultValue: Float
    let minValue: Float?
    let maxValue: Float?
    let enumValues: [String]?
}

// Protocol that all audio processing modules must implement
protocol AudioModule: AnyObject {
    var info: ModuleInfo { get }
    var device: MTLDevice { get }
    
    init(device: MTLDevice, libraryURL: URL) throws
    
    // Core processing method - GPU buffer in, GPU buffer(s) out
    func process(inputBuffer: MTLBuffer, 
                sampleCount: Int, 
                sampleRate: Float,
                parameters: [String: Float]) throws -> [MTLBuffer]
    
    // Get current parameter values
    func getParameters() -> [String: Float]
    
    // Set parameter values
    func setParameter(name: String, value: Float) throws
    
    // Buffer size requirements (for optimization and memory management)
    func getRequiredBufferSize(maxSampleCount: Int) -> Int
    func getMaxOutputBuffers() -> Int
    
    // Module lifecycle
    func prepare(sampleRate: Float, maxSampleCount: Int) throws
    func reset()
}

// C-compatible function signature for module factory
// Each dynamic module must export a function with this signature
typealias ModuleFactoryFunction = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<CChar>) -> UnsafeMutableRawPointer?


// Base class providing common functionality  
class BaseAudioModule: AudioModule {
    let info: ModuleInfo
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    private var parameters: [String: Float] = [:]
    
    // Metal dynamic library support
    private var metalDynamicLibrary: MTLDynamicLibrary?
    private var sharedUtilityLibrary: MTLDynamicLibrary?
    
    required init(device: MTLDevice, libraryURL: URL) throws {
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            throw ModuleError.initializationFailed("Could not create command queue")
        }
        self.commandQueue = commandQueue
        
        // Load module info from JSON file
        let infoURL = libraryURL.deletingPathExtension().appendingPathExtension("json")
        let infoData = try Data(contentsOf: infoURL)
        self.info = try JSONDecoder().decode(ModuleInfo.self, from: infoData)
        
        // Initialize parameters with default values
        for (key, paramInfo) in info.parameters {
            parameters[key] = paramInfo.defaultValue
        }
    }
    
    // Default implementations
    func process(inputBuffer: MTLBuffer, 
                sampleCount: Int, 
                sampleRate: Float,
                parameters: [String: Float]) throws -> [MTLBuffer] {
        fatalError("Subclasses must implement process()")
    }
    
    func getParameters() -> [String: Float] {
        return parameters
    }
    
    func setParameter(name: String, value: Float) throws {
        guard let paramInfo = info.parameters[name] else {
            throw ModuleError.invalidParameter("Unknown parameter: \(name)")
        }
        
        // Validate parameter bounds
        if let min = paramInfo.minValue, value < min {
            throw ModuleError.invalidParameter("Value \(value) below minimum \(min) for parameter \(name)")
        }
        if let max = paramInfo.maxValue, value > max {
            throw ModuleError.invalidParameter("Value \(value) above maximum \(max) for parameter \(name)")
        }
        
        parameters[name] = value
    }
    
    func getRequiredBufferSize(maxSampleCount: Int) -> Int {
        return maxSampleCount * MemoryLayout<Float>.size
    }
    
    func getMaxOutputBuffers() -> Int {
        return info.outputChannels
    }
    
    func prepare(sampleRate: Float, maxSampleCount: Int) throws {
        // Default implementation - subclasses can override
    }
    
    func reset() {
        // Default implementation - subclasses can override
    }
    
    // Metal Dynamic Library Support
    func setMetalDynamicLibrary(_ library: MTLDynamicLibrary?) {
        self.metalDynamicLibrary = library
    }
    
    func setSharedUtilityLibrary(_ library: MTLDynamicLibrary?) {
        self.sharedUtilityLibrary = library
    }
    
    func getMetalDynamicLibrary() -> MTLDynamicLibrary? {
        return metalDynamicLibrary
    }
    
    func getSharedUtilityLibrary() -> MTLDynamicLibrary? {
        return sharedUtilityLibrary
    }
    
}

// Module-specific errors
enum ModuleError: Error {
    case initializationFailed(String)
    case processingFailed(String)
    case invalidParameter(String)
    case libraryLoadFailed(String)
    case functionNotFound(String)
}