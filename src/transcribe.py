#!/usr/bin/env python3
"""zhiyin — One-shot transcription: WAV → SenseVoice → clipboard → paste"""

import os
os.chdir("/tmp")

import sys
import time
import wave
import subprocess
import re
import numpy as np

ZHIYIN_DIR = os.environ.get("ZHIYIN_DIR", os.path.expanduser("~/.zhiyin"))
MODEL_DIR = os.path.join(ZHIYIN_DIR, "models", "sensevoice")
WAV_FILE = os.path.join(ZHIYIN_DIR, "recording.wav")

# Read config
def read_config():
    conf = {}
    conf_file = os.path.join(ZHIYIN_DIR, "zhiyin.conf")
    if os.path.exists(conf_file):
        for line in open(conf_file):
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            conf[k.strip()] = v.strip()
    return conf

def main():
    config = read_config()
    language = config.get("LANGUAGE", "zh")
    num_threads = int(config.get("NUM_THREADS", "4"))
    paste_method = config.get("PASTE_METHOD", "cmdv")

    if not os.path.exists(WAV_FILE) or os.path.getsize(WAV_FILE) < 1000:
        print("no_audio")
        return

    # Convert to 16kHz mono (sox may record at 48kHz)
    wav_16k = WAV_FILE + ".16k.wav"
    subprocess.run(
        ["sox", WAV_FILE, "-r", "16000", "-c", "1", "-b", "16", wav_16k],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    if os.path.exists(wav_16k):
        os.replace(wav_16k, WAV_FILE)

    # Load model & transcribe
    t0 = time.time()
    import sherpa_onnx

    recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
        model=os.path.join(MODEL_DIR, "model.int8.onnx"),
        tokens=os.path.join(MODEL_DIR, "tokens.txt"),
        use_itn=True,
        num_threads=num_threads,
        language=language,
    )

    with wave.open(WAV_FILE, 'rb') as wf:
        sr = wf.getframerate()
        samples = np.frombuffer(wf.readframes(wf.getnframes()), dtype=np.int16)
        samples = samples.astype(np.float32) / 32768.0

    stream = recognizer.create_stream()
    stream.accept_waveform(sr, samples)
    recognizer.decode_stream(stream)

    text = stream.result.text.strip()
    elapsed = time.time() - t0

    # Clean SenseVoice tags
    text = re.sub(r'<\|[^|]*\|>', '', text)
    text = re.sub(r'[\[\]【】]', '', text)
    text = text.strip()

    # Cleanup WAV
    if os.path.exists(WAV_FILE):
        os.remove(WAV_FILE)

    if not text or len(text) <= 1:
        print("no_speech")
        return

    # Output result (Swift app handles clipboard + paste)
    print(f"ok|{elapsed:.3f}|{text}")


if __name__ == "__main__":
    main()
