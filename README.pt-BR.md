<p align="center"><img src="docs/icon.png" width="96" alt="Ícone do PulseDock"></p>

<h1 align="center">PulseDock para macOS</h1>

<p align="center">
  Monitor de sistema moderno para o Mac: CPU, memória, disco, GPU, rede e bateria ao vivo na barra de menus e num widget flutuante de Liquid Glass —
  além de <b>Liberar memória</b> e <b>Limpeza de disco</b> com um clique.<br>
  <a href="README.md">English</a> · <b>Português</b>
</p>

<p align="center">
  <a href="https://github.com/filipembcruz/pulsedock-mac/releases/latest/download/PulseDock.dmg"><b>⬇ Baixar PulseDock.dmg</b></a>
  &nbsp;·&nbsp; macOS 14 Sonoma ou mais novo · Apple silicon e Intel (universal) · grátis e open source (MIT)
</p>

Versão para Mac do [PulseDock para Windows](https://github.com/filipembcruz/pulsedock). Feito em Swift + SwiftUI, com o visual
Liquid Glass do macOS 26 / 27 (no macOS 14–15 usa materiais translúcidos).

## Instalar

1. Baixe o [`PulseDock.dmg`](https://github.com/filipembcruz/pulsedock-mac/releases/latest/download/PulseDock.dmg) do Release mais recente.
2. Abra e arraste o **PulseDock** para **Aplicativos**.
3. **Primeira abertura:** o app tem assinatura ad-hoc (não é notarizado — isso exige conta paga de desenvolvedor Apple), então o macOS bloqueia o duplo clique na primeira vez.
   Clique com o botão direito no PulseDock → **Abrir** → **Abrir**. No macOS 15+, se não houver botão Abrir: *Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim*.
   Prefere o Terminal? Rode `xattr -dr com.apple.quarantine /Applications/PulseDock.app`. Se aparecer *Operation not permitted*, o Terminal precisa de *Ajustes do Sistema → Privacidade e Segurança → Gerenciamento de Apps*; o botão **Abrir Mesmo Assim** é mais simples.
4. Procure o **ícone de pulso** na barra de menus. O widget aparece no canto superior direito.

**Compilar você mesmo** (precisa do Xcode 26 ou das Command Line Tools): `./scripts/install.sh` compila, instala em /Applications e abre.

## Recursos

**Tudo o que o PulseDock para Windows tem**
- **Num relance:** CPU (total, por núcleo, carga média), memória (usada/total, pressão, swap), disco (leitura/escrita, atividade, espaço livre), GPU (uso e memória de cada GPU), rede (download/upload com gráfico) e bateria e estado térmico.
- **Descubra o que está pesando:** clique em CPU, Memória ou Disco para ver os apps mais pesados e **encerrá-los**, com confirmação. Processos do sistema são protegidos.
- **Três layouts:** compacto (padrão), completo e faixa horizontal — troque no ⤢ ou no menu ⋯.
- **Três modos:** flutuante (sempre na frente), na mesa (atrás das janelas) ou só na barra de menus.
- **Coloque onde quiser:** fixe em qualquer um dos 4 cantos, arraste para qualquer lugar (encaixa no canto ao soltar perto), trave a posição, escolha o monitor e a distância da borda.
- **Inicia com o Mac:** *Abrir ao iniciar sessão* vem ligado por padrão (troque no menu **⋯** ou em *Ajustes → Geral*).
- **Extras:** ignorar cliques (segure **⌥ Option** para interagir), ocultar quando um app estiver em tela cheia, opacidade e intervalo de atualização, mostrar/ocultar cada métrica.
- **Idiomas:** inglês (padrão) e português. Troque quando quiser no menu **⋯** do widget → *Language/Idioma*, ou em *Ajustes → Geral*. *Automático* segue o idioma do macOS.

**Novidades no Mac**
- **Liberar memória:** página dedicada à RAM — composição (apps, fixa, comprimida, cache), pressão e os apps que mais consomem memória *agrupados por app* (Chrome + todos os helpers = uma linha). Marque vários e **Encerrar N selecionados** num clique, ou force o encerramento de um app travado.
- **Processos:** tabela no estilo Monitor de Atividade — ordene por memória, CPU ou disco, busque, agrupe por app, botão direito para encerrar / forçar / mostrar no Finder.
- **Limpeza de disco:** um botão **Analisar** e um **Limpar** para:
  - Caches de apps · Logs e relatórios de falha · arquivos temporários antigos · anexos baixados do Mail
  - DerivedData do Xcode · caches do Simulador · suporte a dispositivos antigos · caches do npm / Yarn / Gradle / pip
  - Instaladores antigos (.dmg, .pkg, .zip, .xip) em Downloads · a Lixeira
  - **Arquivos grandes** (> 500 MB) na sua pasta pessoal, para revisar e mandar para a Lixeira um a um

  Cada categoria mostra o tamanho e se é *Seguro* (dados recriáveis, apagados) ou *Revisar* (seus arquivos, vão para a Lixeira e dá para desfazer).
- **Item na barra de menus** com CPU / memória / rede e um popover de vidro: medidores, apps que mais usam memória com ✕ rápido e atalhos para Liberar memória e Limpeza.

## Como usar

| Para… | Faça isto |
|---|---|
| Abrir o app completo | Ícone da barra de menus → **Abrir PulseDock**, ou clique numa linha do widget |
| Liberar memória | Popover → **Liberar memória**, marque os apps → **Encerrar selecionados** |
| Limpar o disco | Popover → **Limpeza** → **Analisar** → **Limpar** |
| Trocar layout, modo ou canto, travar, sair | **⋯** no widget, ou botão direito nele |
| Mover o widget | Arraste. Solte perto de um canto para encaixar |
| Perdeu o widget? | Botão direito no ícone da barra de menus → **Voltar o widget para o canto** |

## Permissões e privacidade

- Sem acesso à rede, sem telemetria. Tudo é lido localmente por APIs públicas do macOS (estatísticas Mach, `libproc`, IOKit).
- Só **os seus processos** podem ser listados e fechados — o macOS não deixa um app encerrar processos do sistema, e o PulseDock ainda recusa uma lista protegida (WindowServer, Finder, Dock, loginwindow…).
- Algumas pastas da limpeza (Mail, Lixeira, Downloads) são protegidas pelo macOS. A primeira análise pode pedir acesso; para resultados completos conceda **Acesso Total ao Disco** (*Ajustes do Sistema → Privacidade e Segurança*). O link **Conceder acesso…** abre esse painel.
- Temperatura de CPU/GPU exige interfaces privadas da Apple; por isso o PulseDock mostra o **estado térmico** oficial.

## Compilar a partir do código

```bash
git clone https://github.com/filipembcruz/pulsedock-mac
cd pulsedock-mac
./scripts/build-app.sh        # → dist/PulseDock.app, PulseDock.dmg, PulseDock.zip
./scripts/install.sh          # compila para este Mac e instala em /Applications
```

Cada push na `main` compila o app universal no GitHub Actions (runner `macos-26`) e publica um Release com o `.dmg` e o `.zip`.

**Traduções:** todo o texto da interface está em `Sources/PulseDock/Services/L10n.swift`, em pares inglês/português.

## Licença

MIT
