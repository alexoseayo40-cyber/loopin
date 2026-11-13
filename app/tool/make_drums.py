# Loopin — genera assets/drums a partir de Virtuosity Drums (CC0)
# Uso: python3 tool/make_drums.py <virtuosity_drums/Samples> assets/drums  (necesita ffmpeg y numpy)
# SPDX-License-Identifier: GPL-3.0-or-later
import subprocess, sys, wave, numpy as np
SRC = sys.argv[1]; OUT = sys.argv[2]
SR = 48000

def load(path):
    raw = subprocess.run(['ffmpeg','-v','error','-i',path,'-f','f32le','-ac','1','-ar',str(SR),'-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)

def mix(parts):
    sigs = [(load(f'{SRC}/{p}'), g) for p, g in parts]
    n = max(len(s) for s, _ in sigs)
    out = np.zeros(n)
    for s, g in sigs: out[:len(s)] += s * g
    return out

def shape(x, length, fade):
    # Empieza 1 ms antes del ataque; corta a `length` s con fundido de `fade` s
    thr = 0.02 * np.max(np.abs(x))
    on = int(np.argmax(np.abs(x) > thr))
    x = x[max(0, on - SR // 1000):]
    n = min(len(x), int(length * SR))
    x = x[:n].copy()
    f = min(n, int(fade * SR))
    x[n - f:] *= np.cos(np.linspace(0, np.pi / 2, f)) ** 2
    x[:24] *= np.linspace(0, 1, 24)  # sin chasquido al empezar
    return x

def kit(mic_close, piece, name):
    m = lambda mic: f'{mic}/{piece}/{mic}_{name}.flac'
    parts = [(m('oh'), 0.8), (m('room'), 0.25)]
    if mic_close: parts.insert(0, (m(mic_close), 1.0))
    return mix(parts)

P = {}
P['kick'] = (shape(kit('kickmic', 'kick', 'kick_snoff_vl3_rr1'), 0.7, 0.25), 1.0)
loud = shape(kit('snaremic', 'snare', 'snare_center_vl28'), 0.7, 0.3)
soft = shape(kit('snaremic', 'snare', 'snare_center_vl14'), 0.5, 0.25)
P['snare'] = (loud, 0.9); P['snare_soft'] = (soft, ('snare', loud))
P['xstick'] = (shape(kit('snaremic', 'snare', 'snare_crossstick_vl12'), 0.4, 0.2), 0.6)
hl = shape(kit(None, 'hh', 'hh_closed_vl3_rr1'), 0.3, 0.15)
hs = shape(kit(None, 'hh', 'hh_closed_vl2_rr1'), 0.3, 0.15)
P['hat'] = (hl, 0.5); P['hat_soft'] = (hs, ('hat', hl))
P['hat_open'] = (shape(kit(None, 'hh', 'hh_open_vl3_rr1'), 1.0, 0.5), 0.45)
P['ride'] = (shape(kit(None, 'ride', 'ride_ride_vl2_rr1'), 1.6, 1.0), 0.45)
P['crash'] = (shape(kit(None, 'crash', 'crash_crash_vl2_rr1'), 2.5, 1.5), 0.6)
cl = mix([('perc/mid/claves/Claves1_Hit_v2_rr1_Mid.wav', 1.0),
          ('perc/close/claves/Claves1_Hit_v2_rr1_Close.wav', 0.6)])
P['sticks'] = (shape(cl, 0.25, 0.12), 0.7)

gains = {}
for k, (x, tgt) in P.items():
    if isinstance(tgt, tuple):
        continue
    gains[k] = tgt / np.max(np.abs(x))
for k, (x, tgt) in P.items():
    g = gains[tgt[0]] if isinstance(tgt, tuple) else gains[k]
    y = np.clip(x * g, -1, 1)
    pcm = np.round(y * 32767).astype('<i2')
    with wave.open(f'{OUT}/{k}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    print(f'{k:10s} {len(y)/SR:5.2f} s  pico {np.max(np.abs(y)):.2f}  {len(pcm.tobytes())//1024} KB')
