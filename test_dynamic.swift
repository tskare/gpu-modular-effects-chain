import Metal
import Foundation

func testDynamicLoading() {
    print("Testing dynamic module loading...")
    
    guard let device = MTLCreateSystemDefaultDevice() else {
        print("ERROR: Metal not supported")
        exit(1)
    }
    
    do {
        let moduleManager = try ModuleManager(device: device)
        print("ModuleManager created")
        
        let modules = moduleManager.getAvailableModules()
        print("Found \(modules.count) modules")
        
        for module in modules {
            print("\(module.name) v\(module.version)")
        }
        
        if !modules.isEmpty {
            let firstModule = modules[0]
            print("Testing creation of \(firstModule.name)...")
            
            let instance = try moduleManager.createModule(name: firstModule.name)
            print("Successfully created \(firstModule.name) instance")
            print("   Info: \(instance.info.name) v\(instance.info.version)")
        }
        
    } catch {
        print("ERROR: \(error)")
        exit(1)
    }
    
    print("ModuleManager was able to spin up and load all available modules!")
}

@main
struct TestDynamic {
    static func main() {
        testDynamicLoading()
    }
}