//
//  AudioStreamer.swift
//  audio
//
//  Created by James Booth (Sonoma) on 16/08/2024.
//

import Foundation
import AVFoundation

class AudioStreamer {
    private var audioEngine: AVAudioEngine
    private var format: AVAudioFormat
    private var playerNode: AVAudioPlayerNode
    private var isPlaying: Bool = false
    
    // New properties for buffer management and time tracking
    private var buffers: [AVAudioPCMBuffer] = []
    private var currentSegmentDuration: TimeInterval = 0
    
    // Think we can yeet this guy here?
    private var currentPlaybackPosition: TimeInterval = 0
    
    init?() {
        let audioEngine = AudioManager.shared.getAudioEngine()
        
        // Define the PCM format: 32-bit float, 44.1kHz, mono
        let sampleRate: Double = 44100.0
        let channels: AVAudioChannelCount = 1
        
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: channels,
                                         interleaved: false) else {
            return nil
        }
        
        self.format = format
        self.audioEngine = audioEngine
        self.playerNode = AVAudioPlayerNode()
        
        // Attach player node to the engine
        audioEngine.attach(playerNode)
        
        // Connect player node to the main mixer node
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        
        // Initialize new properties
        self.buffers = []
        self.currentSegmentDuration = 0
        self.currentPlaybackPosition = 0
    }

    func streamPCMChunk(_ floatPCMData: Data, isFirst: Bool) -> Double {
        let methodStartTime = Date()
        
        func log(_ message: String) {
            let timeDiff = Date().millisecondsSince1970 - methodStartTime.millisecondsSince1970
            print("[\(timeDiff)ms] \(message)")
        }
        
        if isFirst {
            resetBuffers()
        }
        
        guard let buffer = createPCMBuffer(from: floatPCMData) else {
             log("WARNING: Failed to create PCM buffer")
            return timeNow()
        }
        
        buffers.append(buffer)
        
        currentSegmentDuration += Double(buffer.frameLength) / format.sampleRate
        
        playerNode.scheduleBuffer(buffer) {
            self.currentPlaybackPosition += Double(buffer.frameLength) / self.format.sampleRate
        }
        
        var startedPlayingTime: Double = timeNow()
        
        if isFirst {
            do {
                try AudioManager.shared.startAudioEngine()
                playerNode.play()
                log("Player node playback initiated")
                
                startedPlayingTime = timeNow()
                
                isPlaying = true
            } catch {
                 log("Error starting audio engine: \(error)")
            }
        }
        
        return startedPlayingTime
    }
    
    private func createPCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        // Calculate the frame count
        let frameCount = data.count / MemoryLayout<Float>.size
        
        // Create a buffer with the correct frame count and format
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        
        buffer.frameLength = buffer.frameCapacity
        
        // Copy the data into the buffer
        data.withUnsafeBytes { (floatBytes: UnsafeRawBufferPointer) in
            if let floatBufferPointer = floatBytes.baseAddress?.assumingMemoryBound(to: Float.self) {
                buffer.floatChannelData?.pointee.update(from: floatBufferPointer, count: Int(buffer.frameLength))
            }
        }
        
        return buffer
    }
    
    private func resetBuffers() {
        buffers.removeAll()
        currentSegmentDuration = 0
        currentPlaybackPosition = 0
        playerNode.reset()
    }
    
    func seekTo(time: TimeInterval) throws -> Double {
        guard time >= 0 && time < currentSegmentDuration else {
            throw AudioStreamerError.invalidSeekTime
        }
        
        playerNode.stop()
        
        var accumulatedTime: TimeInterval = 0
        var bufferIndex = 0
        var frameOffset: AVAudioFrameCount = 0
        
        for (index, buffer) in buffers.enumerated() {
            let bufferDuration = Double(buffer.frameLength) / format.sampleRate
            if accumulatedTime + bufferDuration > time {
                bufferIndex = index
                frameOffset = AVAudioFrameCount((time - accumulatedTime) * format.sampleRate)
                break
            }
            accumulatedTime += bufferDuration
        }
        
        playerNode.reset()
        
        for i in bufferIndex..<buffers.count {
            let buffer = buffers[i]
            if i == bufferIndex {
                if frameOffset < buffer.frameLength {
                    let remainingFrames = buffer.frameLength - frameOffset
                    let remainingBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: remainingFrames)!
                    remainingBuffer.frameLength = remainingFrames
                    
                    // Copy the remaining audio data
                    for channel in 0..<Int(buffer.format.channelCount) {
                        let src = buffer.floatChannelData![channel].advanced(by: Int(frameOffset))
                        let dst = remainingBuffer.floatChannelData![channel]
                        dst.update(from: src, count: Int(remainingFrames))
                    }
                    
                    playerNode.scheduleBuffer(remainingBuffer)
                }
            } else {
                playerNode.scheduleBuffer(buffer)
            }
        }
        
        currentPlaybackPosition = time
        
        var resumedPlayingTime: Double = timeNow()
        
        do {
            try AudioManager.shared.startAudioEngine()
            playerNode.play()
            resumedPlayingTime = timeNow()
            isPlaying = true
        } catch {
            print("Error starting audio engine: \(error)")
            throw AudioStreamerError.audioEngineStartFailed
        }
        
        return resumedPlayingTime
    }
    
    func pause() {
        if isPlaying {
            playerNode.pause()
            isPlaying = false
        }
    }
    
    func stopAndClear() {
        playerNode.stop()
        isPlaying = false
        resetBuffers()
        print("Audio playback stopped and buffers cleared")
    }
}

enum AudioStreamerError: Error {
    case invalidSeekTime
    case audioEngineStartFailed
}

func timeNow() -> Double {
    return Date().timeIntervalSince1970 * 1000
}

extension Date {
    var millisecondsSince1970: Int64 {
        return Int64((self.timeIntervalSince1970 * 1000.0).rounded())
    }
}
