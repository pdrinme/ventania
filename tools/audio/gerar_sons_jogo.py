#!/usr/bin/env python3
"""Gera os efeitos sonoros do jogo por síntese (WAV mono 16 bits, 22 kHz). Só stdlib.
Sons originais do projeto (ruído filtrado + osciladores + envelopes).

Uso: python3 tools/audio/gerar_sons_jogo.py  ->  game/assets/audio/jogo/*.wav
"""
import math
import os
import random
import struct
import wave

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SAIDA = os.path.join(RAIZ, "game", "assets", "audio", "jogo")
TAXA = 22050
rnd = random.Random(42)


def env_exp(t, ataque, decaimento):
    return min(1.0, t / max(ataque, 1e-4)) * math.exp(-t / decaimento)


def ruido_filtrado(n, corte):
    """Ruído branco num passa-baixa de 1 polo (corte em Hz)."""
    a = math.exp(-2 * math.pi * corte / TAXA)
    y, out = 0.0, []
    for _ in range(n):
        y = (1 - a) * rnd.uniform(-1, 1) + a * y
        out.append(y)
    pico = max(abs(v) for v in out) or 1.0
    return [v / pico for v in out]


def mix(*faixas):
    n = max(len(f) for f in faixas)
    return [sum(f[i] for f in faixas if i < len(f)) for i in range(n)]


def tiro(dur, corte, grave_hz, grave_vol, decaimento, estalo=0.6):
    n = int(TAXA * dur)
    r = ruido_filtrado(n, corte)
    out = []
    for i in range(n):
        t = i / TAXA
        g = math.sin(2 * math.pi * grave_hz * t * (1 - 0.5 * t / dur)) * grave_vol * math.exp(-t / (decaimento * 1.4))
        out.append((r[i] * estalo + g) * env_exp(t, 0.0015, decaimento))
    return out


def clique(freq, dur=0.03, vol=0.5):
    n = int(TAXA * dur)
    r = ruido_filtrado(n, 6000)
    return [(r[i] * 0.6 + math.sin(2 * math.pi * freq * i / TAXA) * 0.5) * vol * math.exp(-(i / TAXA) / (dur * 0.25)) for i in range(n)]


def silencio(dur):
    return [0.0] * int(TAXA * dur)


def tom(freqs, dur, vol=0.4, decai=None, onda="sin"):
    n = int(TAXA * dur)
    out = []
    for i in range(n):
        t = i / TAXA
        f = freqs[0] + (freqs[-1] - freqs[0]) * (i / n)
        fase = 2 * math.pi * f * t
        s = math.sin(fase) if onda == "sin" else (2 / math.pi) * math.asin(math.sin(fase))
        e = min(1.0, t / 0.004) * (math.exp(-t / decai) if decai else (1 - i / n))
        out.append(s * e * vol)
    return out


def salvar(nome, amostras, vol=0.85):
    os.makedirs(SAIDA, exist_ok=True)
    pico = max(abs(v) for v in amostras) or 1.0
    with wave.open(os.path.join(SAIDA, nome + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TAXA)
        w.writeframes(b"".join(struct.pack("<h", int(v / pico * vol * 32767)) for v in amostras))
    print("SOM:", nome)


# disparos por categoria
salvar("tiro_pistola", tiro(0.22, 5200, 140, 0.5, 0.045))
salvar("tiro_rifle", tiro(0.30, 4200, 95, 0.8, 0.06))
salvar("tiro_smg", tiro(0.16, 6000, 160, 0.4, 0.03))
salvar("tiro_espingarda", tiro(0.55, 2600, 70, 1.2, 0.11, estalo=0.9))
salvar("tiro_precisao", mix(tiro(0.9, 3400, 55, 1.4, 0.16, estalo=1.0), [0.0] * int(TAXA * 0.12) + [v * 0.25 for v in tiro(0.6, 1500, 40, 0.6, 0.2)]))
salvar("sem_municao", clique(1800, 0.05, 0.6), vol=0.5)
# recarga: soltar carregador, encaixar, armar
salvar("recarga_inicio", mix(clique(900, 0.05), silencio(0.0)), vol=0.6)
salvar("recarga_fim", clique(1400, 0.04) + silencio(0.06) + clique(700, 0.06, 0.7), vol=0.7)
salvar("cartucho", clique(1100, 0.05), vol=0.55)
salvar("bomba", clique(500, 0.07, 0.8) + silencio(0.05) + clique(800, 0.06, 0.8), vol=0.7)
salvar("sacar", ruido_filtrado(int(TAXA * 0.12), 3000)[:int(TAXA * 0.12)] and
       [v * math.exp(-(i / TAXA) / 0.04) * 0.5 for i, v in enumerate(ruido_filtrado(int(TAXA * 0.12), 3000))] + clique(1200, 0.03, 0.4), vol=0.5)
# baú: destrava + rangido curto + tilintar ascendente
destrava = clique(600, 0.06, 0.9) + silencio(0.03)
rangido = [math.sin(2 * math.pi * (180 + 60 * math.sin(i / TAXA * 30)) * i / TAXA) * 0.35 * (1 - i / (TAXA * 0.25)) for i in range(int(TAXA * 0.25))]
brilho = []
for k, f in enumerate([880, 1175, 1568, 2093]):
    brilho = mix(brilho, silencio(0.07 * k) + tom([f, f * 1.01], 0.5, 0.3, decai=0.18))
salvar("bau_abrir", destrava + mix(rangido, silencio(0.08) + brilho), vol=0.75)
salvar("loot_pop", tom([500, 900], 0.09, 0.4, decai=0.05), vol=0.5)
salvar("pegar", tom([700, 1050], 0.08, 0.5, decai=0.05) + tom([1050, 1400], 0.08, 0.4, decai=0.05), vol=0.6)
# acertos
salvar("acerto", tom([2200, 2000], 0.05, 0.5, decai=0.02, onda="tri"), vol=0.5)
salvar("acerto_cabeca", tom([2600, 2600], 0.05, 0.5, decai=0.03) + tom([3300, 3300], 0.09, 0.5, decai=0.04), vol=0.55)
salvar("dano", mix(ruido_filtrado(int(TAXA * 0.12), 900), tom([180, 120], 0.12, 0.6)), vol=0.6)
# consumíveis
salvar("escudo_ok", tom([600, 1200], 0.25, 0.4, decai=0.12) + tom([1200, 1600], 0.18, 0.3, decai=0.1), vol=0.6)
salvar("cura_ok", tom([520, 780], 0.2, 0.4, decai=0.1) + tom([780, 1040], 0.2, 0.35, decai=0.1), vol=0.6)
salvar("gole", tom([300, 200], 0.08, 0.4, decai=0.04), vol=0.4)
salvar("atadura", [v * 0.6 for v in ruido_filtrado(int(TAXA * 0.15), 2500)], vol=0.35)
salvar("aterrissar", mix(ruido_filtrado(int(TAXA * 0.1), 600), tom([90, 60], 0.1, 0.8)), vol=0.45)
# picareta: corte de ar, impactos por material e sacar
def whoosh(dur, f0, f1, vol=0.6):
    n = int(TAXA * dur)
    out, y = [], 0.0
    for i in range(n):
        t = i / TAXA
        corte = f0 + (f1 - f0) * math.sin(math.pi * t / dur)
        a = math.exp(-2 * math.pi * corte / TAXA)
        y = (1 - a) * rnd.uniform(-1, 1) + a * y
        out.append(y * math.sin(math.pi * t / dur) ** 1.5 * vol)
    return out


def batida(dur, corte, grave, decai, ressoa=None):
    n = int(TAXA * dur)
    r = ruido_filtrado(n, corte)
    out = []
    for i in range(n):
        t = i / TAXA
        s = r[i] * math.exp(-t / (decai * 0.4)) + math.sin(2 * math.pi * grave * t) * 0.8 * math.exp(-t / decai)
        if ressoa:
            s += sum(math.sin(2 * math.pi * f * t) for f in ressoa) * 0.18 * math.exp(-t / (decai * 3.5))
        out.append(s * min(1.0, t / 0.001))
    return out


salvar("golpe_ar", whoosh(0.22, 300, 2200), vol=0.5)
salvar("golpe_madeira", batida(0.25, 1400, 150, 0.05), vol=0.8)
salvar("golpe_pedra", mix(batida(0.22, 4200, 220, 0.03), ruido_filtrado(int(TAXA * 0.2), 2500)[:int(TAXA * 0.2)] and
       [v * math.exp(-(i / TAXA) / 0.06) * 0.4 for i, v in enumerate(ruido_filtrado(int(TAXA * 0.2), 2500))]), vol=0.75)
salvar("golpe_metal", batida(0.6, 6000, 420, 0.04, ressoa=[1870, 2630, 3410]), vol=0.7)
salvar("golpe_terra", batida(0.18, 700, 90, 0.04), vol=0.6)
salvar("picareta_sacar", whoosh(0.16, 500, 1600, 0.4) + clique(900, 0.04, 0.5), vol=0.5)
# inventário
salvar("largar", tom([600, 380], 0.1, 0.45, decai=0.05), vol=0.5)
salvar("inv_erro", tom([330, 300], 0.09, 0.45, onda="tri") + silencio(0.03) + tom([300, 260], 0.11, 0.45, onda="tri"), vol=0.45)
salvar("inv_mover", clique(1500, 0.03, 0.5) + tom([900, 1100], 0.05, 0.3, decai=0.03), vol=0.45)
