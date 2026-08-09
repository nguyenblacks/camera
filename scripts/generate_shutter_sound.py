import wave
import math
import struct
import random
import os

def generate_shutter_sound(filename="assets/sounds/shutter.wav", sample_rate=44100):
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    duration = 0.12  # 120 milliseconds total
    num_samples = int(sample_rate * duration)
    
    samples = []
    
    for i in range(num_samples):
        t = i / sample_rate
        
        # Envelope: sharp attack, quick decay
        if t < 0.005:
            env = t / 0.005
        elif t < 0.04:
            env = 1.0 - (t - 0.005) / 0.035 * 0.7
        elif t < 0.05: # Secondary mechanical rebound click
            env = 0.8
        else:
            env = 0.8 * (1.0 - (t - 0.05) / 0.07)
        
        env = max(0.0, env)
        
        # White noise component (mechanical shutter click)
        noise = (random.random() * 2.0 - 1.0)
        
        # Tonal components (metallic aperture blades click)
        f1 = 1200.0 * math.exp(-t * 30.0)
        f2 = 2400.0 * math.exp(-t * 40.0)
        tone = math.sin(2.0 * math.pi * f1 * t) * 0.4 + math.sin(2.0 * math.pi * f2 * t) * 0.3
        
        # Combine noise and tone
        sample_val = (noise * 0.6 + tone * 0.4) * env * 0.8
        
        # Convert to 16-bit PCM integer
        pcm_val = int(sample_val * 32767)
        pcm_val = max(-32768, min(32767, pcm_val))
        samples.append(pcm_val)
        
    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)  # Mono
        wav_file.setsampwidth(2)  # 16-bit PCM
        wav_file.setframerate(sample_rate)
        
        for sample in samples:
            data = struct.pack('<h', sample)
            wav_file.writeframesraw(data)

    print(f"Generated shutter sound at {filename}")

if __name__ == "__main__":
    generate_shutter_sound()
