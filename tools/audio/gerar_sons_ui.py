#!/usr/bin/env python3
"""Gera os sons de interface (WAV mono 16 bits, 22 kHz) por síntese simples. Só stdlib.
Sons originais do projeto. Uso: python3 tools/audio/gerar_sons_ui.py
"""
import math
import os
import struct
import wave

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SAIDA = os.path.join(RAIZ, "game", "assets", "audio", "ui")
TAXA = 22050


def tom(freqs, dur, vol=0.35, ataque=0.005, onda="sine"):
    n = int(TAXA * dur)
    out = []
    for i in range(n):
        t = i / TAXA
        f = freqs[0] + (freqs[-1] - freqs[0]) * (i / n)  # glissando linear
        fase = 2 * math.pi * f * t
        s = math.sin(fase) if onda == "sine" else (2 / math.pi) * math.asin(math.sin(fase))
        env = min(1.0, t / ataque) * math.exp(-5.0 * t / dur)
        out.append(s * env * vol)
    return out


def salvar(nome, amostras):
    os.makedirs(SAIDA, exist_ok=True)
    with wave.open(os.path.join(SAIDA, nome + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TAXA)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in amostras))
    print("SOM:", nome)


salvar("clique", tom([880, 1320], 0.07, onda="tri"))
salvar("foco", tom([1200, 1250], 0.035, vol=0.18))
salvar("voltar", tom([660, 440], 0.09, onda="tri"))
salvar("confirmar", tom([660, 990], 0.06, onda="tri") + tom([990, 1480], 0.1, onda="tri"))
