"""Valida as temporadas do passe de batalha (Etapa 10) antes de publicar.

Confere: campos, datas (e sobreposição entre temporadas), níveis 1..N sem
buracos, uma recompensa por nível, itens existentes no catálogo, sem repetir
nem dar o que já é de todo mundo, trajes com visual no jogo, desafios válidos.
Mostra o resumo: Faíscas, itens por raridade e a estimativa de horas até o
nível máximo (meta do GAME_DESIGN: 25–30 h).

Uso: python3 tools/validar_temporada.py [backend/config/seasons/t1.json ...]
     (sem argumentos: todas as temporadas de backend/config/seasons/)
Saída 0 = tudo válido; 1 = algum erro.
"""
import glob
import json
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# no repositório o meta-servidor fica em backend/; no pacote do servidor, em meta/
BACKEND = next((os.path.join(RAIZ, d) for d in ("backend", "meta") if os.path.isdir(os.path.join(RAIZ, d, "meta_server"))),
               os.path.join(RAIZ, "backend"))
sys.path.insert(0, BACKEND)
from meta_server.progressao import COSMETICOS_JOGO, _ler, carregar_config, estimar_horas, validar_temporada  # noqa: E402


def main() -> int:
    arquivos = sys.argv[1:] or sorted(glob.glob(os.path.join(BACKEND, "config", "seasons", "*.json")))
    try:
        cfg = carregar_config()            # catálogo, missões e as temporadas publicadas
    except ValueError as e:
        print("ERRO na configuração publicada:", e)
        return 1
    visuais = _ler(COSMETICOS_JOGO) if os.path.exists(COSMETICOS_JOGO) else None
    temporadas = [json.load(open(a, encoding="utf-8")) for a in arquivos]
    outras = {t["id"]: t for t in cfg["temporadas"]}
    for t in temporadas:
        outras[t.get("id")] = t
    falhas = 0
    for a, t in zip(arquivos, temporadas):
        erros = validar_temporada(t, cfg, list(outras.values()), visuais)
        print(f"== {os.path.relpath(a, RAIZ)}: {t.get('nome', '?')}")
        if erros:
            falhas += 1
            for e in erros:
                print("   ERRO:", e)
            continue
        rec = t["recompensas"]
        faiscas = sum(r.get("faiscas", 0) for r in rec) + sum(d.get("faiscas", 0) for d in t.get("desafios", []))
        por_raridade = {}
        for r in rec:
            if "item" in r:
                item = cfg["catalogo"][r["item"]]
                por_raridade.setdefault(item["raridade"], []).append(f"{item['nome']} (nível {r['nivel']})")
        est = estimar_horas(t, cfg)
        print(f"   {len(rec)} níveis × {t['xp_por_nivel']} XP · {t['inicio'][:10]} → {t['fim'][:10]} ({est['semanas']} semanas)")
        print(f"   Faíscas no passe e nos desafios: {faiscas}")
        for rar, itens in por_raridade.items():
            print(f"   {rar}: {', '.join(itens)}")
        print(f"   {len(t.get('desafios', []))} desafios da temporada ({est['xp_desafios']} XP)")
        print(f"   estimativa: {est['horas']} h jogando até o nível {len(rec)} "
              f"(+{est['xp_missoes']} XP de missões na temporada)")
        if not (20 <= est["horas"] <= 35):
            print("   AVISO: fora da faixa de 25–30 h do GAME_DESIGN (ajuste xp_por_nivel)")
        print("   OK")
    print(f"{len(temporadas)} temporada(s), {falhas} com erro.")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
