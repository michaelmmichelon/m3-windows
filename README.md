# M3 Windows

> **Versão 0.3.** Validada instalando o Windows 11 25H2 Home (pt-BR) do zero numa VM. Ainda não testada em PC físico.

Windows 11 **oficial** com instalação automática e otimização para **desempenho**: jogos, gravação e dia a dia, sem bloatware, propaganda nem IA empurrada.

O M3 Windows **não é uma ISO modificada**. Você usa a ISO oficial da Microsoft e a sua licença; o projeto entra com dois arquivos:

| Arquivo | O que faz |
|---|---|
| `autounattend.xml` | Instala em português com teclado ABNT2, pula conta Microsoft, telas de privacidade e de rede, e cria sua conta local |
| `m3\m3-otimizar.ps1` | Roda sozinho no primeiro login: limpa, otimiza e aplica o visual M3. Também pode ser usado num Windows já instalado |

Por isso tudo funciona: anti-cheat (Valorant, CoD, FACEIT), drivers, Game Pass, Adobe, OBS.

## O que a otimização faz

| Área | Ajuste |
|---|---|
| Limpeza | Remove Copilot, Clipchamp, Notícias, Clima, Dicas, Office Hub, Paciência, Teams, Outlook novo, Mapas, Vincular ao Celular, Filmes e TV, To Do, Power Automate, Hub de Feedback. **Mantém** Loja, Xbox/Game Pass, Fotos, Calculadora, Bloco de Notas, Paint, Terminal, Ferramenta de Captura |
| IA | Copilot e Recall desligados por política (também no Edge) |
| Propaganda | Sem sugestões no Iniciar, apps instalados sozinhos, Bing na busca, Widgets, dicas na tela de bloqueio, "vamos terminar de configurar" |
| Privacidade | Telemetria no mínimo permitido (serviço DiagTrack desligado), sem ID de anúncios, sem histórico de atividades |
| Energia | Desktop: plano **Desempenho Máximo**. Notebook: **Melhor desempenho na tomada**, Equilibrado na bateria |
| Jogos | Modo de Jogo, agendamento de GPU por hardware, otimização de jogos em janela, sem gravação em segundo plano da Game Bar, sem aceleração do mouse |
| Inicialização | Programas de inicialização sem o atraso de ~10 s do Windows |
| Windows Update | Continua automático, mas **não reinicia sozinho** com você logado |
| Visual | Tema escuro, destaque ciano M3 `#12C0EC`, papel de parede e tela de bloqueio M3 |
| Praticidade | Extensões de arquivo visíveis, Explorador abre em "Este Computador", menu de contexto clássico, "Finalizar tarefa" no clique direito da barra |
| Iniciar e barra | Sem atalhos patrocinados (WhatsApp, LinkedIn, Adobe Express, Outlook). Fixados do M3: Explorador, Edge, Loja, Configurações, Xbox, Terminal, Fotos, Calculadora, Bloco de Notas, Paint e Ferramenta de Captura; na barra, Explorador, Edge, Loja, Xbox e Terminal (instalação do zero) |
| Conta | Conta local; o login automático usado na instalação é desligado depois do primeiro reinício. Contas criadas depois também recebem o M3 |
| Edge | Continua instalado, mas não abre escondido com o Windows nem fica rodando depois de fechado; sem barra lateral, ofertas de compras e assistente de boas-vindas (o Edge passa a mostrar "gerenciado pela organização" por usar políticas) |

**Fica ligado:** Windows Defender, Windows Update, firewall e as proteções do kernel.

**Opcional (perguntado na preparação):**
- Remover o OneDrive.
- Desligar a **Integridade de Memória (VBS/HVCI)**: costuma dar alguns % de FPS em certos jogos, mas tira uma camada de proteção contra drivers maliciosos. Padrão: **ligada**.

## Instalar do zero

1. Baixe a ISO oficial do **Windows 11 em Português (Brasil)** em https://www.microsoft.com/pt-br/software-download/windows11.
2. Grave no pendrive (8 GB+) com o **Rufus** ou a **Ferramenta de Criação de Mídia**.
   No Rufus, na janela **"Personalização do Windows"**, **desmarque tudo**: quem cuida disso é o M3.
3. Baixe este projeto (botão **Code → Download ZIP**), extraia e rode no PowerShell:

   ```bash
   powershell -ExecutionPolicy Bypass -File .\gerar-pendrive.ps1
   ```

   Ele pergunta a letra do pendrive, seu usuário, senha, nome do PC e as opções.
4. Inicie o PC pelo pendrive. Você só escolhe a **edição** e o **disco**; o resto é automático. No primeiro login a otimização roda (uns 2 minutos) e o PC reinicia.
5. Depois de instalar, **apague** o `autounattend.xml` e a pasta `m3` do pendrive (a senha fica neles codificada, não criptografada).

> ⚠️ Escolha o disco com cuidado na instalação. Para dual boot, instale numa partição livre.

## Instalar numa máquina virtual (Proxmox, Hyper-V, VirtualBox)

Na VM não tem pendrive: o M3 vai numa **ISO pequena** (0,5 MB) que entra como **segundo CD**. O instalador do Windows acha o `autounattend.xml` nela sozinho.

```bash
powershell -ExecutionPolicy Bypass -File .\gerar-pendrive.ps1 -Destino .\saida\m3-windows-vm.iso
```

No **Proxmox**:

| Aba | Configuração |
|---|---|
| OS | ISO do Windows 11 pt-BR, tipo **Microsoft Windows 11/2022/2025** |
| System | Máquina **q35**, BIOS **OVMF (UEFI)**, EFI Storage com "Pre-Enroll keys", **Add TPM** v2.0 |
| Disks | **SATA**, 64 GB (VirtIO SCSI exige carregar o driver do virtio-win na instalação) |
| CPU | Tipo **host**, 4 núcleos |
| Memory | 8 GB |
| Network | **Intel E1000E** (funciona sem driver) |

Depois de criar: Hardware → Add → **CD/DVD Drive** → a `m3-windows-vm.iso`. Inicie, aperte uma tecla em "Press any key to boot from CD" e siga como no PC. Envie a ISO ao Proxmox pelo painel: storage → ISO Images → Upload.

## Medir o desempenho (antes × depois)

O `m3\m3-medir.ps1` mede o que o M3 reduz, com o PC parado:
- RAM em uso e memória comprometida;
- processos, threads e serviços;
- CPU parada;
- tarefas agendadas e programas na inicialização;
- apps instalados, disco usado e tempo de boot.

1. Faça duas VMs iguais: uma com o Windows puro, outra com o M3 Windows.
2. Ligue cada uma, espere **5 minutos parada** e rode como administrador:

   ```bash
   powershell -ExecutionPolicy Bypass -File C:\ProgramData\M3Windows\m3-medir.ps1
   ```

   No M3 Windows o script já está em `C:\ProgramData\M3Windows`. No Windows puro, coloque a ISO do M3 no CD da VM e rode de `D:\m3\m3-medir.ps1`.
3. Cada medição vira um `.json` em `C:\Users\Public\Documents`. Junte os dois arquivos num PC e compare:

   ```bash
   powershell -ExecutionPolicy Bypass -File .\m3\m3-medir.ps1 -Comparar puro.json m3.json
   ```

Em VM não dá para medir FPS (não há placa de vídeo de verdade); isso fica para o PC.

## Otimizar um Windows já instalado

Baixe o projeto e rode como administrador:

```bash
powershell -ExecutionPolicy Bypass -File .\m3\m3-otimizar.ps1
```

Antes de mudar qualquer coisa, ele cria o ponto de restauração **"Antes do M3 Windows"** (para desfazer: Painel de Controle → Recuperação → Abrir Restauração do Sistema). O registro do que foi feito fica em `C:\ProgramData\M3Windows\otimizar.log`.

## Apps e driver de vídeo

Na preparação do pendrive você escolhe os apps (Enter instala os marcados com `*`):

| # | App | Padrão |
|---|---|---|
| 1 | Steam | * |
| 2 | Discord | * |
| 3 | OBS Studio | * |
| 4 | 7-Zip | * |
| 5 | Epic Games Launcher | |
| 6 | Google Chrome | |
| 7 | Firefox (português) | |
| 8 | VLC | |

Eles são instalados pelo **winget**, sempre a versão oficial e atual, no **login depois do primeiro reinício**. Uma janela mostra o andamento. Se não houver internet, a janela pede para conectar e espera até 10 minutos; se continuar sem, tenta de novo no próximo login.

**Driver de vídeo:**

| Placa | O que o M3 faz |
|---|---|
| Intel | Instala o *Intel Driver & Support Assistant*, que mantém o driver atualizado. |
| NVIDIA | Coloca na área de trabalho o atalho **Driver de vídeo NVIDIA**, para a página oficial do NVIDIA App. O driver da NVIDIA não está no winget. |
| AMD | Coloca na área de trabalho o atalho **Driver de vídeo AMD**, para a página oficial do Adrenalin. O driver da AMD não está no winget. |

Enquanto o driver oficial não é instalado, o Windows Update instala um driver básico.

Para adicionar apps à lista, edite `m3/apps-catalogo.txt` (o id sai de `winget search <nome>`). Num Windows já instalado: `powershell -ExecutionPolicy Bypass -File .\m3\m3-apps.ps1`.

## O M3 se mantém sozinho

Depois de aplicado, os arquivos ficam em `C:\ProgramData\M3Windows` (só administradores alteram) e o M3 cuida de duas situações:

- **Conta nova no PC:** no primeiro login dela, assim que a área de trabalho abre, o M3 aplica as configurações da conta (tema, jogos, mouse, barra, privacidade) e refaz a barra de tarefas. O Iniciar já vem com os mesmos fixados da conta de quem instalou o M3, sem atalhos patrocinados. Roda uma vez por conta e não fica rodando depois.
- **Atualização grande do Windows** (ex.: 25H2 → 26H2): esse tipo de atualização traz de volta apps e configurações. A tarefa `\M3\M3 Windows - reaplicar` roda 2 min depois do boot, confere a versão do Windows e sai na hora se nada mudou. Se mudou, reaplica o M3 (registro em `reaplicar.log`) e cada conta recebe as configurações de novo no próximo login.

As atualizações mensais não disparam nada.

## Estrutura

```
gerar-pendrive.ps1            prepara o pendrive (ou uma pasta) com os arquivos abaixo
modelo/autounattend.xml       modelo da instalação automática
modelo/criar-usuario.ps1      cria a conta local na instalação (pelo SID, funciona em qualquer idioma)
m3/preparar-instalacao.ps1    antes do primeiro login: tira apps da imagem e define os fixados
m3/m3-otimizar.ps1            otimização (primeiro login ou manual)
m3/apps-remover.txt           lista de apps removidos (edite para manter algum)
m3/LayoutModification.*       fixados do Iniciar (.json) e da barra de tarefas (.xml)
m3/wallpaper-m3.png           papel de parede e tela de bloqueio
m3/m3-medir.ps1               medição de desempenho (antes × depois)
ferramentas/validar.ps1       confere sintaxe/codificação dos scripts antes de gerar
ferramentas/testar-vm.sh      VM de teste (QEMU no WSL, UEFI + TPM 2.0)
ferramentas/vm/               digitar, capturar a tela e conduzir a instalação na VM de teste
marca/                        logo M3 TECH
```

Para manter um app que o M3 remove (ex.: Vincular ao Celular), apague a linha dele em `m3/apps-remover.txt` antes de gerar o pendrive.

## Testar numa máquina virtual

No WSL (Arch) com KVM, a mesma VM usada no desenvolvimento:

```bash
powershell -ExecutionPolicy Bypass -File .\gerar-pendrive.ps1 -Destino .\saida\pendrive
```

```bash
wsl -d archlinux -u root -- bash /mnt/c/PROJETOS/m3-windows/ferramentas/testar-vm.sh "/mnt/d/caminho/Win11_25H2_BrazilianPortuguese_x64.iso"
```

Aperte uma tecla quando aparecer "Press any key to boot from CD". A tela fica na janela do WSLg (ou no VNC `localhost:5901`).

> Na VM dentro do WSL (virtualização aninhada) o QEMU às vezes pausa com `KVM: entry failed, hardware error 0x0` num reinício. Isso é limitação do ambiente de teste, não do M3. Para continuar: `echo system_reset | socat - UNIX-CONNECT:/var/tmp/m3win-vm/monitor.sock`.

## Projeto irmão

[M3 SO](https://github.com/michaelmmichelon/m3-so): a mesma ideia em Linux (Arch + CachyOS + KDE).
