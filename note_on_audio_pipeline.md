Starting from my Python backend:
```Python
if data.get("audio"):
    audio_data_base64 = data["audio"]
    float_audio = base_64_pcm_to_float(audio_data_base64)

    logger.debug("🔗 Received audio data from ElevenLabs...")

    alignment_data = data.get("normalizedAlignment")

    modified_alignment = insert_latex_triggers(alignment_data, room_id)

    if not first_chunk_received:
        first_chunk_received = True
        safe_socketio_emit(self.socketio, 'voice_start', {'interjection': interjection}, namespace=namespace, room=room_id)
        safe_socketio_emit(self.socketio, 'voice_aligned', {'audio': float_audio, 'alignment': modified_alignment, 'first_chunk': True, 'message_id': message_id}, namespace=namespace, room=room_id)
    else:
        safe_socketio_emit(self.socketio, 'voice_aligned', {'audio': float_audio, 'alignment': modified_alignment, 'first_chunk': False, 'message_id': message_id}, namespace=namespace, room=room_id)
```

where
```Python
def base_64_pcm_to_float(audio_data_base64, to_list = True):
    if to_list:
        return (np.frombuffer(base64.b64decode(audio_data_base64), dtype=np.int16).astype(np.float32) / 32768.0).tolist()
    else:
        return np.frombuffer(base64.b64decode(audio_data_base64), dtype=np.int16).astype(np.float32) / 32768.0
```

Which is fed through my ts side:
```typescript
const { startedPlayingTime } = await AudioStreamer.handleAudioChunk({ data: chunk.audio, isFirst: true });
```

and then recieved in a Swift Capacitor plugin:
```Swift
    @objc func handleAudioChunk(_ call: CAPPluginCall) {
        guard let audioStreamer = audioStreamer else {
            call.reject("AudioStreamer not initialized")
            return
        }
        
        guard let audioArray = call.getArray("data") as? [Float32] else {
            call.reject("Invalid audio data")
            return
        }
        
        streamingMode = true
        
        let isFirst = call.getBool("isFirst") ?? false
        
        let audioData = Data(bytes: audioArray, count: audioArray.count * MemoryLayout<Float32>.stride)
        
        let startedPlayingTime = audioStreamer.streamPCMChunk(audioData, isFirst: isFirst)
        
        call.resolve(["startedPlayingTime": startedPlayingTime])
    }
```

The rest is then handled in the `AudioStreamer` class.
