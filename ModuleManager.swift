import Metal
import Foundation

// Module manager for dynamic loading and chaining of Metal compute
// shader files and their drivers.

// Module registry data
private struct ModuleEntry {
    let info: ModuleInfo
    let libraryURL: URL
    let dynamicLibraryHandle: UnsafeMutableRawPointer?
    let factoryFunction: ModuleFactoryFunction?
    let metalDynamicLibrary: MTLDynamicLibrary?
}

class ModuleManager {
    private let device: MTLDevice
    private var moduleRegistry: [String: ModuleEntry] = [:]
    private let modulesDirectory: URL
    private let supportsDynamicLibraries: Bool
    private var sharedDynamicLibrary: MTLDynamicLibrary?
    
    // 'modules' subdir is preferred but we can load modules from the cwd as well.
    init(device: MTLDevice, modulesDirectory: String = "modules") throws {
        self.device = device
        self.modulesDirectory = URL(fileURLWithPath: modulesDirectory)
        
        self.supportsDynamicLibraries = device.supportsDynamicLibraries
        print("Metal Dynamic Libraries support: \(supportsDynamicLibraries ? "Supported" : "Not supported")")
        
        if supportsDynamicLibraries {
            try loadSharedUtilityLibrary()
        }
        
        try scanForModules()
    }
    
    // Skip shared utility library loading for now - each module includes utilities directly
    private func loadSharedUtilityLibrary() throws {
        print("Skipping shared Metal utility library (modules currently inline from util header directly)")
    }
    
    private func scanForModules() throws {
        guard FileManager.default.fileExists(atPath: modulesDirectory.path) else {
            print("INFO: Modules directory not found, falling back to current directory")
            try scanCurrentDirectory()
            return
        }
        
        let contents = try FileManager.default.contentsOfDirectory(at: modulesDirectory,
                                                                  includingPropertiesForKeys: nil,
                                                                  options: .skipsHiddenFiles)
        
        for moduleDir in contents where moduleDir.hasDirectoryPath {
            try loadModuleFromDirectory(moduleDir)
        }
    }
    
    private func scanCurrentDirectory() throws {
        let currentDir = URL(fileURLWithPath: ".")
        let contents = try FileManager.default.contentsOfDirectory(at: currentDir,
                                                                  includingPropertiesForKeys: nil,
                                                                  options: .skipsHiddenFiles)
        
        let jsonFiles = contents.filter { $0.pathExtension == "json" }
        
        for jsonFile in jsonFiles {
            do {
                let data = try Data(contentsOf: jsonFile)
                let moduleInfo = try JSONDecoder().decode(ModuleInfo.self, from: data)
                
                let metallibURL = jsonFile.deletingPathExtension().appendingPathExtension("metallib")
                
                if FileManager.default.fileExists(atPath: metallibURL.path) {
                    try registerModule(info: moduleInfo, libraryURL: metallibURL)
                    print("Discovered module: \(moduleInfo.name) v\(moduleInfo.version)")
                }
            } catch {
                continue
            }
        }
    }
    
    private func loadModuleFromDirectory(_ moduleDir: URL) throws {
        let jsonFiles = try FileManager.default.contentsOfDirectory(at: moduleDir,
                                                                   includingPropertiesForKeys: nil,
                                                                   options: .skipsHiddenFiles)
            .filter { $0.pathExtension == "json" }
        
        guard let jsonFile = jsonFiles.first else {
            print("WARNING: No module descriptor found in \(moduleDir.lastPathComponent)")
            return
        }
        
        let data = try Data(contentsOf: jsonFile)
        let moduleInfo = try JSONDecoder().decode(ModuleInfo.self, from: data)
        
        let libraryURL = moduleDir.appendingPathComponent(moduleInfo.metalLibrary)
        
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            throw ModuleError.libraryLoadFailed("Metal library not found: \(libraryURL.path)")
        }
        
        try registerModule(info: moduleInfo, libraryURL: libraryURL)
        print("Loaded module: \(moduleInfo.name) v\(moduleInfo.version) : \(moduleInfo.description)")
    }
    
    private func registerModule(info: ModuleInfo, libraryURL: URL) throws {
        var dynamicLibraryHandle: UnsafeMutableRawPointer? = nil
        var factoryFunction: ModuleFactoryFunction? = nil
        let metalDynamicLibrary: MTLDynamicLibrary? = nil

        // Try to load dynamic library (either specified or derived from metalLibrary)
        let dynamicLibraryPath = info.libraryFile
        let dynamicLibraryURL = libraryURL.deletingLastPathComponent().appendingPathComponent(dynamicLibraryPath)

        if FileManager.default.fileExists(atPath: dynamicLibraryURL.path) {
            print("Loading Swift dynamic library: \(dynamicLibraryURL.path)")
            
            guard let handle = dlopen(dynamicLibraryURL.path, RTLD_LAZY) else {
                let error = String(cString: dlerror())
                throw ModuleError.libraryLoadFailed("Failed to load dynamic library \(dynamicLibraryURL.path): \(error)")
            }
            
            dynamicLibraryHandle = handle
            
            // Get module-specific factory function
            // We could use a uniform interface name method, but we need to have a unique name in the registry
            // (IIUC at least) so it might be easiest to uniquify based on filename and factory method.
            let factoryFunctionName = "create\(info.name)Module"
            guard let symbol = dlsym(handle, factoryFunctionName) else {
                let error = String(cString: dlerror())
                dlclose(handle)
                throw ModuleError.functionNotFound("Factory function '\(factoryFunctionName)' not found: \(error)")
            }
            
            factoryFunction = unsafeBitCast(symbol, to: ModuleFactoryFunction.self)
            print("Found factory function: \(factoryFunctionName)")
        }
        
        if factoryFunction == nil {
            print("WARNING: No CPU dynamic library found for \(info.name), falling back to static linking")
        }
        
        let entry = ModuleEntry(
            info: info,
            libraryURL: libraryURL,
            dynamicLibraryHandle: dynamicLibraryHandle,
            factoryFunction: factoryFunction,
            metalDynamicLibrary: metalDynamicLibrary
        )
        moduleRegistry[info.name] = entry
    }
    
    func createModule(name: String) throws -> AudioModule {
        guard let entry = moduleRegistry[name] else {
            throw ModuleError.initializationFailed("Module not found: \(name)")
        }
        
        if let factoryFunction = entry.factoryFunction {
            let devicePtr = Unmanaged.passUnretained(device).toOpaque()
            let libraryPath = entry.libraryURL.path
            
            return try libraryPath.withCString { pathPtr in
                guard let modulePtr = factoryFunction(devicePtr, UnsafeMutablePointer(mutating: pathPtr)) else {
                    throw ModuleError.initializationFailed("Dynamic factory failed for module: \(name)")
                }
                
                let anyObject = Unmanaged<AnyObject>.fromOpaque(modulePtr).takeRetainedValue()
                
                print("Successfully loaded dynamic module '\(name)' of type: \(type(of: anyObject))")
                
                // Swift treats same class from different modules as different types
                // Factory function guarantees correct type despite this limitation
                let module = unsafeBitCast(anyObject, to: BaseAudioModule.self)
                
                module.setMetalDynamicLibrary(entry.metalDynamicLibrary)
                module.setSharedUtilityLibrary(sharedDynamicLibrary)
                
                return module
            }
        }
        
        throw ModuleError.initializationFailed("Failed to load module '\(name)' dynamically and no static fallback available")
    }
    
    func getAvailableModules() -> [ModuleInfo] {
        return moduleRegistry.values.map { $0.info }
    }
    
    func getMetalDynamicLibrary(for moduleName: String) -> MTLDynamicLibrary? {
        return moduleRegistry[moduleName]?.metalDynamicLibrary
    }
    
    func getSharedUtilityLibrary() -> MTLDynamicLibrary? {
        return sharedDynamicLibrary
    }
    
    func createProcessingChain(moduleNames: [String]) throws -> ProcessingChain {
        var modules: [AudioModule] = []
        
        for name in moduleNames {
            let module = try createModule(name: name)
            modules.append(module)
        }
        
        return ProcessingChain(modules: modules)
    }
    
    deinit {
        for entry in moduleRegistry.values {
            if let handle = entry.dynamicLibraryHandle {
                dlclose(handle)
            }
        }
    }
}

class ProcessingChain {
    private let modules: [AudioModule]
    
    init(modules: [AudioModule]) {
        self.modules = modules
    }
    
    func process(inputBuffer: MTLBuffer, 
                sampleCount: Int, 
                sampleRate: Float) throws -> [MTLBuffer] {
        
        guard !modules.isEmpty else {
            return [inputBuffer]  // no-op if no modules
        }
        
        var currentBuffers = [inputBuffer]
        
        for module in modules {
            guard let inputBuffer = currentBuffers.first else {
                throw ModuleError.processingFailed("No input buffer for module")
            }
            
            let parameters = module.getParameters()
            currentBuffers = try module.process(inputBuffer: inputBuffer,
                                              sampleCount: sampleCount,
                                              sampleRate: sampleRate,
                                              parameters: parameters)
        }
        
        return currentBuffers
    }
    
    func prepare(sampleRate: Float, maxSampleCount: Int) throws {
        print("Checking for matching buffer sizes across the chain...")
        
        for (index, module) in modules.enumerated() {
            let requiredSize = module.getRequiredBufferSize(maxSampleCount: maxSampleCount)
            let maxOutputs = module.getMaxOutputBuffers()
            
            print("   Module \(index + 1) (\(module.info.name)): requires \(requiredSize) bytes, outputs \(maxOutputs) buffers")
            
            if index > 0 {
                let prevModule = modules[index - 1]
                let prevOutputs = prevModule.getMaxOutputBuffers()
                
                if module.info.inputChannels > 0 && prevOutputs < module.info.inputChannels {
                    print("WARNING: Module '\(module.info.name)' expects \(module.info.inputChannels) input channels, but previous module in chain '\(prevModule.info.name)' outputs \(prevOutputs)")
                }
            }
            
            try module.prepare(sampleRate: sampleRate, maxSampleCount: maxSampleCount)
        }

        print("Buffer wiring-up complete")
    }
    
    func reset() {
        for module in modules {
            module.reset()
        }
    }
    
    func getModuleInfo() -> [ModuleInfo] {
        return modules.map { $0.info }
    }
}