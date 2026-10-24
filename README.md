# Código Azul

Jogo cooperativo para dois jogadores feito pala equipe THN no **Godot 4.7.2**. A dupla precisa preparar uma cidade para enfrentar uma tempestade: um jogador explora a cidade em 3D e instala os equipamentos, enquanto o outro opera a central de controle em 2D e passa as informações necessárias.

O tema do jogo homenageia mulheres importantes da ciência: **Ada Lovelace, Marie Curie, Katherine Johnson, Rosalind Franklin e Chien-Shiung Wu**.

---

## Informações rápidas

| Item | Descrição |
| --- | --- |
| Gênero | Cooperativo, quebra-cabeça, tempo real |
| Jogadores | 2 (um na Cidade e um na Central) |
| Plataforma do executável | Windows 64 bits |
| Versão do código | Godot 4.7.2 (GDScript) |
| Conexão | Internet obrigatória (salas e sincronização online) |
| Resolução | 1920 x 1080 (o jogo abre em tela cheia) |
| Objetivo | Sobreviver ao maior número de rodadas possível |

---

## Como abrir o jogo pelo executável

1. Extraia o arquivo `.zip` (se o executável tiver vindo compactado). Não execute o jogo de dentro do `.zip`.
2. Dê **dois cliques no arquivo `.exe`**.
3. O jogo abre direto na tela inicial, em tela cheia.
4. Como o jogo é para duas pessoas, cada jogador deve abrir uma cópia do executável:
   - em **dois computadores diferentes** (recomendado); ou
   - no mesmo computador, abrindo o `.exe` duas vezes e alternando com `Alt+Tab`.
5. Para fechar o jogo, use `Alt+F4`.

> **Aviso do Windows:** o executável não possui assinatura digital, então o Windows pode exibir a mensagem "O Windows protegeu o computador". Clique em **Mais informações > Executar assim mesmo**.

> **Internet:** o executável precisa de conexão com a internet para listar/criar salas e sincronizar os dois jogadores.

### Entrando em uma partida

1. Um jogador cria a sala pelo botão de criar sala (o nome da sala é opcional).
2. O outro jogador clica em **Atualizar salas** e entra na mesma sala.
3. **Cada jogador precisa digitar seu nome** antes de entrar. O nome é obrigatório e fica salvo no banco para o ranking.
4. Um jogador escolhe **CIDADE** e o outro escolhe **CENTRAL**.
5. Quando os dois papéis estiverem ocupados, a partida começa automaticamente.

---

## Como abrir o jogo pelo Godot (código-fonte)

### 1. Instale o Godot

Baixe o **Godot 4.7.2 – versão Standard** (não é necessário o .NET) no site oficial:

- https://godotengine.org/download

### 2. Abra o projeto

1. Extraia a pasta do código-fonte em um local de sua preferência.
2. Abra o Godot.
3. Na tela de projetos, clique em **Import** (Importar).
4. Navegue até a pasta do projeto e selecione o arquivo **`project.godot`**.
5. Clique em **Import & Edit** (Importar e Editar).
6. Na primeira abertura, o Godot importará os assets. Aguarde até terminar.

### 3. Execute o jogo

1. Pressione **F5** (ou clique no botão ▶ no canto superior direito).
2. A cena inicial é `scenes/TelaInicial.tscn`.
3. Para parar a execução, pressione **F8** (ou o botão ■).

> Não é necessário abrir cenas individuais com F6. Use **F5** para rodar o jogo completo, pois a partida depende das cenas de sala, cidade e central.

### 4. Testar com dois jogadores

Para testar sozinho no computador, abra duas instâncias do jogo:

- **Opção mais simples:** exporte o executável (veja a seção abaixo) e abra o `.exe` duas vezes.
- **Pelo editor:** se a versão do Godot tiver o recurso, use **Debug > Run Multiple Instances > Run 2 Instances**.
- **Com dois computadores:** rode o projeto/executável em cada máquina, usando a mesma sala.

Em qualquer caso, crie uma sala em uma instância, entre nela na outra e escolha papéis diferentes (CIDADE e CENTRAL).

---

## Controles

### Jogador da CIDADE (Ada)

| Ação | Controle |
| --- | --- |
| Andar | `W`, `A`, `S`, `D` ou setas direcionais |
| Interagir / instalar equipamento | `E` |
| Entrar ou sair do abrigo | `E` perto da porta do abrigo |
| Resolver os minigames | Mouse |
| Sair de um minigame | Botão **Sair** (não perde vida e não conclui o objetivo) |

A câmera acompanha o jogador automaticamente. O personagem sobe pequenos degraus sozinho.

### Jogador da CENTRAL (Grace)

| Ação | Controle |
| --- | --- |
| Abrir post-its / manual | Mouse |
| Fechar pop-ups | Clique em qualquer lugar |
| Restaurar a energia no apagão | Clique repetidamente no botão do gerador |
| Acompanhar o tempo e as vidas | Visor e barra de vida na tela |

---

## Como jogar

### Papéis

- **CIDADE – Ada:** percorre a cidade, localiza os equipamentos e resolve os desafios de instalação. É ela quem vê os objetivos no mapa 3D e aperta `E` para interagir.
- **CENTRAL – Grace:** acompanha o minimapa, vê a posição de Ada e os pontos de instalação, e consulta os post-its com as informações das cientistas. Também controla a energia durante os apagões.

A comunicação entre os dois é essencial: **a Central tem as informações e a Cidade tem acesso aos desafios**.

### Rodada

1. No início da rodada, a Cidade recebe uma lista de objetivos espalhados pela cidade.
2. Ada vai até cada equipamento e aperta `E` para abrir o minigame.
3. O minigame mostra o nome de uma cientista e um adesivo que indica qual informação será necessária.
4. Grace procura essa informação nos post-its e fala para Ada.
5. Ada responde corretamente para concluir a instalação.

Ao concluir todos os objetivos antes do tempo acabar, a rodada termina e a próxima começa com **mais objetivos e mais tempo**.

### Minigames

| Equipamento | Desafio |
| --- | --- |
| **Antena** | Digitar a informação correta no campo de texto e clicar em **Confirmar**. |
| **Bueiro** | Observar os dois adesivos e clicar nas duas válvulas cujas placas correspondem às informações pedidas, na ordem dos adesivos. |
| **Pluviômetro** | Clicar na dica que contém a informação correta. O equipamento sobe ou desce até a altura escolhida. |

- Acertar conclui o objetivo.
- Errar **custa 1 vida** e sorteia um novo desafio.
- O botão **Sair** fecha o minigame **sem perder vida** e **sem concluir o objetivo**.

### Vidas e derrota

- A dupla começa com **5 vidas**.
- Cada erro em um minigame consome 1 vida.
- Se as vidas chegarem a **0**, ou se o tempo da rodada acabar, a partida termina na tela de derrota.
- Não existe tela de vitória: o objetivo é sobreviver ao maior número de rodadas possível. O **Ranking** da tela inicial mostra as salas ordenadas pela quantidade de rodadas alcançadas.

### Eventos

- **Chuva de granizo:** a Central é avisada **30 segundos antes**. Quando o granizo começa, a Cidade mostra o alerta "Chuva de granizo! Vá para o abrigo!". Quem estiver fora do abrigo perde 1 vida a cada 2 segundos durante a chuva. Existem **dois abrigos** no mapa, marcados com o ícone de guarda-chuva no minimapa da Central. Basta chegar perto da porta e apertar `E` para entrar ou sair.
- **Apagão:** a tela da Central escurece. Clique várias vezes seguidas no botão do **gerador** para restaurar a energia.

### Valores atuais das rodadas

Os valores ficam em `scripts/global.gd` e em `scripts/geracaoMundo/pontos.gd`:

- Primeira rodada: **5 objetivos** e **4 minutos**.
- Cada rodada seguinte: **+3 objetivos** e **+30 segundos**.
- Vidas: **5**.

Esses valores podem ser ajustados nesses scripts para deixar o jogo mais fácil ou mais difícil.

---

## Estrutura do projeto

```
Codigo-Azul/
├── project.godot          # Configuração do projeto (cena inicial, autoloads, inputs)
├── export_presets.cfg     # Presets de exportação (Windows e macOS)
├── README.md
├── assets/                # Sprites, ícones e imagens
├── fonts/                 # Fonte ByteBounce
├── sounds/                # Efeitos sonoros
├── shaders/               # Shader do sonar usado na Central
├── scenes/
│   ├── TelaInicial.tscn   # Cena inicial (salas, tutorial, ranking)
│   ├── SalaDeEspera.tscn  # Espera pelos dois jogadores
│   ├── tutorial.tscn
│   ├── ranking.tscn
│   ├── derrota.tscn
│   ├── cidade/            # Cidade 3D, jogador, HUD, contagem
│   ├── central/           # Central 2D, mapa, manual, post-its
│   └── minigames/         # Antena, bueiro e pluviômetro
└── scripts/
	├── global.gd          # Estado global (sala, vidas, tempo, eventos)
	├── conectSupa.gd      # Conexão em tempo real com o Supabase
	├── banco.gd           # Persistência no banco
	├── transicao.gd       # Transições com fade entre cenas
	├── telaInicial.gd     # Salas, tutorial e ranking
	├── salaDeEspera.gd    # Início automático da partida
	├── centralSync.gd     # Sincronização da Central com a Cidade
	├── cidade/            # Movimento, câmera e HUD da cidade
	├── central/           # Minimapa, post-its, manual e energia
	├── geracaoMundo/      # Geração procedural da cidade e objetivos
	├── minigames/         # Lógica dos três minigames
	└── informacoesMulheres.gd  # Dados das cientistas e textos dos post-its
```

### Principais sistemas

- **Geração procedural:** a cidade 3D é montada por blocos (`scripts/geracaoMundo/`). A Cidade gera o mapa e o publica; a Central lê o mesmo mapa para desenhar o minimapa.
- **Objetivos:** ficam em `Global.pontos_position` e são sincronizados com o banco. Cada objetivo tem posição, estado e tipo (antena, bueiro ou pluviômetro).
- **Sincronização online:** as salas, o mapa, os objetivos, o tempo, os eventos, os abrigos e as posições dos jogadores são sincronizados pelo Supabase; a Central usa um canal em tempo real para receber novidades.
- **Minigames:** as respostas vêm de `scripts/informacoesMulheres.gd` (ano, mês, dia, feito, ano da morte e área de cada cientista).

---

## Tecnologias

- **Godot 4.7.2** com renderização **Forward+**;
- **GDScript**;
- **Jolt Physics** para a física 3D;
- **Supabase** (REST + Realtime) para salas e sincronização;
- Cenas 2D e 3D combinadas no mesmo projeto;
- Shader personalizado para o efeito de sonar no minimapa.

---

## Solução de problemas

| Problema | Solução |
| --- | --- |
| O Godot diz que o projeto foi criado em uma versão mais nova | Instale o Godot **4.7.2** (ou mais recente, se compatível) e abra novamente. |
| A lista de salas não carrega | Verifique a internet e clique em **Atualizar salas**. |
| O outro jogador não aparece na sala | Confirme se os dois digitaram o nome, escolheram papéis diferentes e estão na mesma sala. |
| A partida não começa | É necessário um jogador na CIDADE e outro na CENTRAL. |
| O Windows bloqueia o executável | Clique em **Mais informações > Executar assim mesmo**. |
| O jogo abre em tela cheia e não sei fechar | Use `Alt+F4` (ou `Alt+Tab` para alternar entre as janelas). |
| Erros de conexão com o Supabase no console | O jogo precisa de internet; verifique firewall/proxy da rede. |
| O projeto não abre no Godot | Confirme que selecionou o arquivo `project.godot` e que a pasta foi extraída por completo. |
| Sons não tocam | Verifique o volume do Windows e se o jogo não está silenciado. |

---

## Créditos

- **Projeto:** Código Azul — trabalho escolar.
- **Equipe:** [preencher com os nomes dos integrantes]
- **Engine:** Godot Engine 4.7.2.
- **Fonte:** ByteBounce.
- **Tema:** mulheres pioneiras da ciência e prevenção de desastres naturais.
