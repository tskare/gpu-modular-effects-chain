import Foundation

// CLEANUP: is there a Foundation or system class to do this?
class WAVWriter {
    func writeWAVFile(channels: [[Float]], sampleRate: Int, filename: String) throws {
        guard !channels.isEmpty else { return }
        
        let numChannels = channels.count
        let numSamples = channels[0].count
        let bytesPerSample = 2
        let dataSize = numSamples * bytesPerSample * numChannels
        let fileSize = 36 + dataSize
        
        var data = Data()
        
        // WAV Header
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)
        
        // Format chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt32(sampleRate * numChannels * bytesPerSample).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(numChannels * bytesPerSample).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) })
        
        // Data chunk
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })
        
        // Interleaved samples
        for i in 0..<numSamples {
            for channel in channels {
                let clampedSample = max(-1.0, min(1.0, channel[i]))
                let intSample = Int16(clampedSample * Float(Int16.max))
                data.append(withUnsafeBytes(of: intSample.littleEndian) { Data($0) })
            }
        }
        
        try data.write(to: URL(fileURLWithPath: filename))
    }
    
    // Convenience method, write mono
    func writeWAVFile(samples: [Float], sampleRate: Int, filename: String) throws {
        try writeWAVFile(channels: [samples], sampleRate: sampleRate, filename: filename)
    }
    
    // Convenience method, write stereo
    func writeWAVFileStereo(leftSamples: [Float], rightSamples: [Float], sampleRate: Int, filename: String) throws {
        try writeWAVFile(channels: [leftSamples, rightSamples], sampleRate: sampleRate, filename: filename)
    }
}