# tools/assets

| Arquivo | Função |
|---|---|
| `budgets.json` | Orçamentos por categoria + licenças/origens permitidas |
| `blender/export_glb.py` | .blend → GLB com checagem de orçamento (Blender ou módulo bpy) |
| `blender/make_sample_crate.py` | Gera o asset de teste `caixote_exemplo_01` |
| `validate_glb.py` | Valida GLB (tris, materiais, texturas, ossos, extensões) — stdlib |
| `catalog.py` | Gerencia `assets_catalog.json` e gera `LICENSES.json` — stdlib |
| `tests/test_pipeline.py` | Testes (`python3 -m unittest discover -s tools/assets/tests`) |

Guia completo: `docs/assets/PIPELINE.md`.
