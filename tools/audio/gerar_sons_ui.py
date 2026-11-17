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

# Etapa 12: sons do lobby e da progressão
def silencio(dur):
    return [0.0] * int(TAXA * dur)


def acorde(freqs, dur, vol=0.22):
    partes = [tom([f, f], dur, vol=vol / len(freqs) * 1.6, onda="tri") for f in freqs]
    return [sum(p[i] for p in partes) for i in range(len(partes[0]))]


# moeda: dois "plins" agudos (compra na loja)
salvar("compra", tom([1318, 1318], 0.06, vol=0.25) + tom([1975, 1975], 0.16, vol=0.25))
# subir de nível: arpejo maior ascendente (dó-mi-sol-dó)
salvar("nivel", tom([523, 523], 0.08, onda="tri") + tom([659, 659], 0.08, onda="tri")
       + tom([784, 784], 0.08, onda="tri") + acorde([1046, 1318, 1568], 0.35))
# recompensa / desbloqueio: brilho que sobe
salvar("recompensa", tom([1200, 2400], 0.18, vol=0.2) + tom([2400, 2600], 0.12, vol=0.12))
# partida encontrada: fanfarra curta
salvar("partida", acorde([392, 494, 587], 0.12) + silencio(0.03) + acorde([523, 659, 784], 0.3))
# notificação (convite, pedido de amizade)
salvar("notificacao", tom([988, 988], 0.07, onda="tri") + silencio(0.04) + tom([1318, 1318], 0.11, onda="tri"))
