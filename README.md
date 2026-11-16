# M3 Windows

> 🚧 **Versão 0.1, em teste.** Ainda não foi validada numa instalação completa; use primeiro numa máquina virtual.

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

## Otimizar um Windows já instalado

Baixe o projeto e rode como administrador:

```bash
powershell -ExecutionPolicy Bypass -File .\m3\m3-otimizar.ps1
```

Antes de mudar qualquer coisa, ele cria o ponto de restauração **"Antes do M3 Windows"** (para desfazer: Painel de Controle → Recuperação → Abrir Restauração do Sistema). O registro do que foi feito fica em `C:\ProgramData\M3Windows\otimizar.log`.

Depois de grandes atualizações do Windows (as versões anuais), vale rodar de novo: alguns apps e configurações podem voltar.

## Estrutura

```
gerar-pendrive.ps1        prepara o pendrive (ou uma pasta) com os arquivos abaixo
modelo/autounattend.xml   modelo da instalação automática
modelo/criar-usuario.ps1  cria a conta local na instalação (pelo SID, funciona em qualquer idioma)
m3/m3-otimizar.ps1        otimização (primeiro login ou manual)
m3/wallpaper-m3.png       papel de parede e tela de bloqueio
marca/                    logo M3 TECH
```

## Projeto irmão

[M3 SO](https://github.com/michaelmmichelon/m3-so): a mesma ideia em Linux (Arch + CachyOS + KDE).
