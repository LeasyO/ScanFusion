# ScanFusion 2.0 — guia completo (só Windows + iPhone)

O que mudou em relação à versão anterior:

- **Quatro modos de captura:** Objeto, Ambiente (planta DXF), Malha + nuvem de pontos e Trena.
- **Sem reinstalar a cada 7 dias:** a renovação passa a ser automática, feita pelo próprio iPhone.
- **Envio automático para o PC** pelo iCloud Drive.
- **Atalho no Botão de Ação**, nas Siri e no app Atalhos.
- **Tema preto e dourado.**

---

## 1. Subir o projeto no GitHub (substitui o anterior)

Os arquivos antigos conflitam com os novos, então comece do zero:

1. No GitHub, abra o repositório `ScanFusion` antigo › **Settings** › role até o fim › **Delete this repository**.
2. Crie de novo: **+ › New repository** › nome `ScanFusion` › **Public** › **Create repository**.
3. Clique em **uploading an existing file**.
4. Extraia o `ScanFusion.zip`. Abra a pasta extraída, selecione **tudo o que está dentro dela** e arraste para a página. São estes itens: `.github`, `ScanFusion`, `Support`, `scripts`, `docs`, `project.yml` e este LEIA-ME.
5. Clique em **Commit changes**.
6. Na aba **Actions**, espere o ✅. Leva de 5 a 10 minutos.

Cada compilação publica sozinha uma Release chamada **latest** com o `ScanFusion.ipa`. Ela publica também a **fonte do SideStore**:

```
https://github.com/SEU-USUARIO/ScanFusion/releases/download/latest/source.json
```

Troque `SEU-USUARIO` pelo seu nome no GitHub.

> **Se a pasta `.github` não subir:** clique em **Add file › Create new file**, digite `.github/workflows/build.yml`, cole o conteúdo desse arquivo e salve.
>
> **Se ficar ❌ vermelho:** abra a execução e baixe o artefato `ScanFusion-ipa`, que inclui o `build.log`. Me mande as linhas que começam com `error:`.

---

## 2. Instalar sem renovar à mão — SideStore (grátis, recomendado)

O SideStore é uma loja instalada no próprio iPhone. Ela assina e renova os apps sem precisar do PC. Ele só é usado **uma vez**, na configuração.

**No PC (uma vez):**

1. Siga o guia oficial em **docs.sidestore.io**. A instalação inicial pelo Windows é feita com o programa indicado lá (hoje o **iloader**).
2. Ele instala o SideStore no iPhone e cria o "arquivo de pareamento". Use o mesmo Apple ID de antes.

**No iPhone:**

1. Na App Store, instale o **LocalDevVPN**. É ele que permite ao SideStore renovar os apps sem o PC.
2. Abra o SideStore › **Fontes** › **+** › cole o link `source.json` do passo 1.
3. Instale o **ScanFusion** por essa fonte.
4. Ative a renovação automática no app Atalhos:
   - **Automação › Nova automação › Hora do dia**, por exemplo todo dia às 3h › **Executar imediatamente**.
   - Ações, nesta ordem: **Conectar LocalDevVPN** › **SideStore: Atualizar todos os apps** (com "Mostrar ao executar" desligado) › **Esperar 30 s** › **Desconectar VPN**.
5. Ajustes › Privacidade e Segurança › **Modo de Desenvolvedor** › ativar, se pedir.

Daqui em diante, toda vez que o código mudar no GitHub, a atualização aparece no SideStore. O atalho diário renova a assinatura sozinho, e você não liga mais o iPhone no PC.

**Limites do Apple ID gratuito:** no máximo 3 apps assinados ao mesmo tempo (SideStore e ScanFusion contam 2) e 10 novos IDs de app por semana.

### Alternativa paga: TestFlight (zero manutenção)

Com o **Apple Developer Program** (US$ 99 por ano), o próprio GitHub envia cada versão para o **TestFlight**. Você instala pelo app TestFlight, sem SideStore, sem VPN e sem renovar nada, e cada build vale 90 dias. Tudo pode ser configurado pelo navegador no Windows:

1. **developer.apple.com › Certificates, IDs & Profiles › Identifiers › +**: crie o App ID `com.seunome.scanfusion`.
2. **appstoreconnect.apple.com › Apps › +**: crie o app com esse ID.
3. **Users and Access › Integrations › App Store Connect API**: crie uma chave com acesso **Admin** e baixe o `.p8`.
4. No GitHub, abra **Settings › Secrets and variables › Actions** e crie estes segredos:
   - `ASC_KEY_ID`: ID da chave
   - `ASC_ISSUER_ID`: Issuer ID
   - `ASC_KEY_P8`: conteúdo inteiro do arquivo `.p8`, aberto no Bloco de Notas
   - `APPLE_TEAM_ID`: Team ID, que aparece em developer.apple.com › Membership
   - `BUNDLE_ID`: `com.seunome.scanfusion`
5. Rode o workflow de novo. O job **testflight** sai do modo "pulado" e envia o app.
6. No App Store Connect, abra **TestFlight › Testes internos** e adicione você mesmo. Depois instale pelo app TestFlight.

### Outras opções externas, para referência

- **Sideloadly** (o que você já conhece): funciona, mas exige o PC a cada 7 dias. Ele tem renovação automática por Wi-Fi, desde que o PC esteja ligado.
- **AltStore + AltServer no Windows**: renova pelo Wi-Fi com o PC ligado na mesma rede.
- **Lojas alternativas no Brasil (iOS 26.5 em diante)**: a Apple liberou lojas de terceiros no país. Mesmo assim, o desenvolvedor precisa da conta paga para ter o app autenticado pela Apple, então para uso pessoal o TestFlight é mais simples.
- **Serviços pagos de certificado** (assinatura por UDID): evite. A Apple revoga esses certificados com frequência e você entrega seu aparelho a terceiros.

---

## 3. Envio automático para o PC (iCloud)

1. No Windows, instale o **iCloud para Windows** pela Microsoft Store, entre com seu Apple ID e ative o **iCloud Drive**. Aparece a pasta `iCloud Drive` no Explorador.
2. No iPhone, abra o app **Arquivos › iCloud Drive** e crie a pasta **ScanFusion**.
3. No ScanFusion, vá em **Ajustes › Envio automático para o PC › Escolher pasta no iCloud Drive** e selecione essa pasta.

A partir daí, cada scan é copiado para lá sozinho e aparece no PC em `iCloud Drive\ScanFusion\`. Depois é só abrir no Fusion.

---

## 4. Atalho no Botão de Ação do iPhone 15 Pro Max

Abra **Ajustes › Botão de Ação › Atalho** e escolha **ScanFusion › Escanear objeto** (ou ambiente, LiDAR ou trena). Um toque no botão abre o app direto na captura. Pela Siri também funciona: *"Escanear objeto no ScanFusion"*.

---

## 5. Os modos e o que cada um gera

| Modo | Para quê | Arquivos |
|---|---|---|
| **I. Objeto** | Peças e itens com detalhe (fotogrametria + LiDAR) | STL, OBJ, STL leve para o Fusion, USDZ e as fotos |
| **II. Ambiente** | Cômodos: paredes, portas, janelas e móveis | **Planta DXF em mm com cotas**, STL/OBJ, USDZ, JSON |
| **III. Malha e nuvem** | Coisas grandes: moto, fachada, terreno | STL/OBJ, **nuvem colorida PLY + PTS**, opcional separado por paredes/piso/teto |
| **IV. Trena** | Distâncias, desnível, perímetro e área | CSV (Excel) e DXF com a poligonal cotada |

**Padrão de exportação:** milímetros com Z para cima. O arquivo abre no Fusion na escala e na posição certas. Isso pode ser mudado em Ajustes.

### Levar para os programas

- **Fusion, malha:** Inserir › Inserir malha › STL ou OBJ, em milímetros. Para transformar em sólido editável, use o arquivo `_fusion-leve.stl` e, na aba Malha, **Converter malha**.
- **Fusion, planta:** Inserir › Inserir DXF.
- **Revit:** Inserir › Importar CAD com o DXF. Para a nuvem de pontos, abra o `.pts` no **Autodesk ReCap**, salve em `.rcp` e use Inserir › Nuvem de pontos.
- **AutoCAD:** abra o DXF direto. As camadas são PAREDES, PORTAS, JANELAS, ABERTURAS, MOBILIARIO, PISO e COTAS.
- **Qualidade máxima de objeto:** as fotos ficam em `Scans/<nome>/Fotos`. Copie essa pasta para o PC e processe no **RealityScan** da Epic (gratuito no Windows) para obter mais detalhe do que o iPhone consegue gerar.

### Dicas de captura

- O LiDAR do iPhone é mais preciso **até uns 3 m**. Chegue perto do que importa.
- Mova o celular devagar. Superfícies brilhantes, transparentes ou pretas demais falham.
- **Objeto:** dê uma volta, depois outra mais alta e, se der, vire a peça.
- **Ambiente:** acenda as luzes e passe a câmera pelos cantos, pelo piso e pelo teto.

---

## Estrutura

```
.github/workflows/build.yml   compila, publica Release + fonte SideStore, TestFlight opcional
project.yml                   projeto Xcode gerado na nuvem (XcodeGen)
Support/                      Info.plist e manifesto de privacidade
scripts/make_source.py        gera a fonte do SideStore
docs/icon.png                 ícone usado na fonte
ScanFusion/Core/              tema, ajustes, motor de malha/nuvem/DXF, armazenamento, iCloud
ScanFusion/Modes/             Objeto, Ambiente, LiDAR, Trena
ScanFusion/UI/                início, biblioteca, ajustes, resultado
```

Para mudar as cores, edite só `ScanFusion/Core/Theme.swift`.
