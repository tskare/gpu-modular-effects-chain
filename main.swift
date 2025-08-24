import Metal
import Foundation

func main() {
    let arguments = CommandLine.arguments
    
    if arguments.contains("--list-modules") {
        listModules()
        return
    }
    
    do {
        print("Modular GPU plugin chain demo")
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Metal is not supported on this device")
            exit(1)
        }
        print("Metal device: \(device.name)")
        
        print("Getting available modules...")
        let moduleManager = try ModuleManager(device: device)
        let availableModules = moduleManager.getAvailableModules()
        print("Available modules: \(availableModules.count)")
        for module in availableModules {
            print("  - \(module.name) v\(module.version) - \(module.description)")
        }
        
        if availableModules.isEmpty {
            print("ERROR: No modules found; please ensure .metallib and .json files are present")
            exit(1)
        }
        
        // Create processing chain; static in the current version.
        // Later we may want to add EQ that can be placed pre or post, and load config from disk.
        print("Creating processing chain... (Hammond -> Leslie)")
        let processingChain = try moduleManager.createProcessingChain(moduleNames: ["Hammond", "Leslie"])
        let sampleRate: Float = 48000.0
        let duration: Float = 4.0  // Seconds
        let sampleCount = Int(sampleRate * duration)        
        try processingChain.prepare(sampleRate: sampleRate, maxSampleCount: sampleCount)

        print("Creating input buffer...")
        // Hammond is a generator, so input is ignored
        // TODO: feed it MIDI or more complex control data.
        // Currently plays an Amaj chord with an A in the bass.
        let bufferSize = sampleCount * MemoryLayout<Float>.size
        guard let dummyInputBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            print("ERROR: Could not create input buffer")
            exit(1)
        }
        
        memset(dummyInputBuffer.contents(), 0, bufferSize)
        print("Input buffer created (\(bufferSize) bytes)")
        
        print("Synthesizing audio through chain...")
        
        let outputBuffers = try processingChain.process(inputBuffer: dummyInputBuffer, 
                                                       sampleCount: sampleCount, 
                                                       sampleRate: sampleRate)
        
        print("Saving \(outputBuffers.count) output buffers")

        if outputBuffers.count >= 2 {
            let leftPointer = outputBuffers[0].contents().bindMemory(to: Float.self, capacity: sampleCount)
            let rightPointer = outputBuffers[1].contents().bindMemory(to: Float.self, capacity: sampleCount)
            let leftChannel = Array(UnsafeBufferPointer(start: leftPointer, count: sampleCount))
            let rightChannel = Array(UnsafeBufferPointer(start: rightPointer, count: sampleCount))
            
            let wavWriter = WAVWriter()
            try wavWriter.writeWAVFileStereo(leftSamples: leftChannel, rightSamples: rightChannel, 
                                            sampleRate: Int(sampleRate), filename: "modular_output.wav")
            print("Saved first 2 channels as modular_output.wav (stereo)")
            
        } else if outputBuffers.count == 1 {
            let outputPointer = outputBuffers[0].contents().bindMemory(to: Float.self, capacity: sampleCount)
            let audioSamples = Array(UnsafeBufferPointer(start: outputPointer, count: sampleCount))
            
            let wavWriter = WAVWriter()
            try wavWriter.writeWAVFile(samples: audioSamples, sampleRate: Int(sampleRate), filename: "modular_output.wav")
            print("Saved singular channel as modular_output.wav (mono)")
        }

        print("Resulting chain was:")
        for (index, moduleInfo) in processingChain.getModuleInfo().enumerated() {
            print("   \(index + 1). \(moduleInfo.name) (\(moduleInfo.inputChannels)→\(moduleInfo.outputChannels) channels)")
        }
        
    } catch {
        print("ERROR: \(error)")
        exit(1)
    }
}

func listModules() {
    do {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: MTLCreateSystemDefaultDevice() failed")
            exit(1)
        }
        
        let moduleManager = try ModuleManager(device: device)
        let modules = moduleManager.getAvailableModules()
        
        print("Available Audio Modules:")
        if modules.isEmpty {
            print("No modules found.")
            return
        }
        for module in modules {
            print("\n\(module.name) v\(module.version)")
            print("   Description: \(module.description)")
            print("   Author: \(module.author)")
            print("   I/O: \(module.inputChannels) -> \(module.outputChannels) channels")
            print("   Library: \(module.metalLibrary)")
            
            if !module.parameters.isEmpty {
                print("   Parameters:")
                for (_, param) in module.parameters {
                    let range = param.minValue != nil && param.maxValue != nil ? 
                        " [\(param.minValue!)...\(param.maxValue!)]" : ""
                    print("     \(param.name) (\(param.type)): \(param.defaultValue)\(range)")
                }
            }
        }

        print("\n")
    } catch {
        print("ERROR listing modules: \(error)")
        exit(1)
    }
}

main()
