# Teste em hardware real

Objetivo: medir como o Ventania roda no **seu PC fraco** e no **seu celular**,
para calibrar perfis gráficos e orçamentos antes do gameplay (Etapa 2).

## 1. Instalar

| Plataforma | Arquivo | Como abrir |
|---|---|---|
| Windows 10/11 (64 bits) | `Ventania-0.1.1-windows.zip` | Extraia e abra `Ventania.exe`. O Windows pode avisar "aplicativo não reconhecido": clique em **Mais informações → Executar assim mesmo** (o executável não tem assinatura digital). |
| Linux (64 bits) | `Ventania-0.1.1-linux.zip` | Extraia, rode `chmod +x ventania.x86_64` e depois `./ventania.x86_64`. |
| Android | ainda não disponível | Veja a seção 5. |

Requisito gráfico: OpenGL 3.3 (PC) ou OpenGL ES 3.0 (celular). Quase qualquer
GPU integrada a partir de 2012 atende.

## 2. Rodar o teste de desempenho

1. No menu, abra **Vitrine e teste de desempenho**.
2. Deixe em **Perfil: Desempenho** e **Densidade: 1×1** e toque em **Iniciar teste (20 s)**. Não mexa no aparelho durante o teste.
3. Ao terminar, toque em **Copiar resultado** e cole aqui na conversa.
4. Repita com:
   - **Perfil: Equilibrado**, Densidade 1×1;
   - **Perfil: Qualidade**, Densidade 1×1;
   - o perfil que rodou melhor, com **Densidade 2×2** e depois **3×3**. Isso simula uma área com muito mais construções.

Os resultados também ficam salvos (JSON + CSV, frame a frame) em:
- Windows: `%APPDATA%\Godot\app_userdata\Ventania\benchmarks\`
- Linux: `~/.local/share/godot/app_userdata/Ventania/benchmarks/`

## 3. O que observar

- O teste roda **sem limite de FPS e sem vsync** (as suas configurações são restauradas no fim), para medir a folga real. Se no Linux o resultado parar exatamente em 60, o driver está forçando o vsync: rode `vblank_mode=0 ./ventania.x86_64`.
- **FPS médio** e **1% pior**. O "1% pior" mostra os engasgos. A meta é de 30 FPS ou mais no celular e 60 FPS no PC, com "1% pior" acima de 20.
- Se esquentar muito ou travar, anote depois de quanto tempo.
- Se algo aparecer errado (cores, peças faltando, texto cortado), tire uma captura de tela.

## 4. Testar a conexão com o meta-servidor (opcional)

No PC que vai ser o "servidor", com Python 3.11+:

```bash
cd backend
```

```bash
python3 -m meta_server
```

No jogo, vá em **Configurações → Servidor**, digite `http://IP-DO-PC:8080`
(ex.: `http://192.168.0.10:8080`) e toque em **Testar conexão**. O IP do PC
aparece em `ipconfig` (Windows) ou `ip addr` (Linux). Pode ser preciso liberar
a porta 8080 no firewall.

## 5. Android

O preset de exportação já está pronto (`game/export_presets.cfg`, arquiteturas
arm64-v8a e armeabi-v7a, para cobrir celulares de 32 bits). Para gerar o APK falta o
**Android SDK**, que exige aceitar a licença do Google. Há duas opções:

- **No seu PC:** instale o Godot 4.7.2 e o Android SDK (command-line tools, com `build-tools` e `platform-tools`), configure em *Editor → Editor Settings → Export → Android* e exporte o preset "Android".
- **Nesta sessão do Claude:** autorize explicitamente a instalação do SDK com aceite da licença do Google, e o APK é gerado aqui.
