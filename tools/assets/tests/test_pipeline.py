"""Testes das ferramentas de assets (só biblioteca padrão).

Uso: python3 -m unittest discover -s tools/assets/tests -v
"""

import json
import os
import struct
import sys
import tempfile
import unittest

AQUI = os.path.dirname(__file__)
sys.path.insert(0, os.path.abspath(os.path.join(AQUI, "..")))
import catalog  # noqa: E402
import validate_glb  # noqa: E402


def cfg():
    with open(validate_glb.ORCAMENTOS, encoding="utf-8") as f:
        return json.load(f)


def glb_minimo(tris=1, extensoes=None, materiais=0):
    """Monta um GLB válido em memória com `tris` triângulos não indexados."""
    n_vert = tris * 3
    binario = b"\x00" * (n_vert * 12)
    gltf = {
        "asset": {"version": "2.0"},
        "buffers": [{"byteLength": len(binario)}],
        "bufferViews": [{"buffer": 0, "byteLength": len(binario)}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": n_vert, "type": "VEC3"}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        "nodes": [{"name": "obj", "mesh": 0}],
        "materials": [{"name": f"m{i}"} for i in range(materiais)],
    }
    if extensoes:
        gltf["extensionsUsed"] = extensoes
    js = json.dumps(gltf).encode()
    js += b" " * (-len(js) % 4)
    corpo = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(binario), b"BIN\x00") + binario
    return struct.pack("<4sII", b"glTF", 2, 12 + len(corpo)) + corpo


class TestValidateGlb(unittest.TestCase):
    def _validar(self, dados, categoria="baus_coletaveis"):
        with tempfile.NamedTemporaryFile(suffix=".glb", delete=False) as f:
            f.write(dados)
        try:
            return validate_glb.validar(f.name, categoria, cfg())
        finally:
            os.unlink(f.name)

    def test_glb_dentro_do_orcamento(self):
        erros, _, st = self._validar(glb_minimo(tris=10, materiais=1))
        self.assertEqual(erros, [])
        self.assertEqual(st["tris"], 10)

    def test_excesso_de_triangulos(self):
        erros, _, _ = self._validar(glb_minimo(tris=900))
        self.assertTrue(any("triângulos" in e for e in erros))

    def test_excesso_de_materiais(self):
        erros, _, _ = self._validar(glb_minimo(materiais=3))
        self.assertTrue(any("materiais" in e for e in erros))

    def test_draco_rejeitado(self):
        erros, _, _ = self._validar(glb_minimo(extensoes=["KHR_draco_mesh_compression"]))
        self.assertTrue(any("não suportadas" in e for e in erros))

    def test_arquivo_invalido(self):
        erros, _, _ = self._validar(b"nao e um glb de verdade")
        self.assertTrue(erros)

    def test_tamanho_png(self):
        png = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\x0dIHDR" + struct.pack(">II", 256, 128)
        self.assertEqual(validate_glb.tamanho_imagem(png), (256, 128))


class TestCatalogo(unittest.TestCase):
    def _item(self, **kw):
        base = dict(id="teste_01", nome="Teste", categoria="cenario", origem="original",
                    autor="Equipe", licenca="Original", url_origem="", atribuicao="",
                    arquivo_fonte="", arquivo_exportado="", estado="planejado")
        base.update(kw)
        return base

    def test_item_original_valido(self):
        self.assertEqual(catalog.validar_item(self._item(), cfg(), set()), [])

    def test_origem_proprietaria_rejeitada(self):
        erros = catalog.validar_item(self._item(origem="extraido_jogo_comercial"), cfg(), set())
        self.assertTrue(any("origem" in e for e in erros))

    def test_licenca_desconhecida_rejeitada(self):
        erros = catalog.validar_item(self._item(licenca="Proprietaria"), cfg(), set())
        self.assertTrue(any("licença" in e for e in erros))

    def test_cc_by_exige_url_e_atribuicao(self):
        erros = catalog.validar_item(self._item(origem="terceiros_licenciado", licenca="CC-BY-4.0"), cfg(), set())
        self.assertTrue(any("url_origem" in e for e in erros))
        self.assertTrue(any("atribuição" in e for e in erros))

    def test_exportado_exige_glb(self):
        erros = catalog.validar_item(self._item(estado="exportado", arquivo_exportado="game/assets/cenario/nao_existe.glb"),
                                     cfg(), set())
        self.assertTrue(any("arquivo_exportado" in e for e in erros))

    def test_id_duplicado_e_invalido(self):
        ids = {"teste_01"}
        self.assertTrue(any("duplicado" in e for e in catalog.validar_item(self._item(), cfg(), ids)))
        self.assertTrue(any("inválido" in e for e in catalog.validar_item(self._item(id="Teste-X"), cfg(), set())))


if __name__ == "__main__":
    unittest.main()
