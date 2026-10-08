# ULTRA

Sistema de ficheiros do Maisus.

> Documento de desenho. Descreve **o que o ULTRA é e porque existe**.
> Não é um relatório do que já está feito — quase nada está. Serve para não
> perder as decisões (e os porquês) quando daqui a uns meses recomeçarmos.

---

## 1. O ULTRA é, numa frase

**Um volume ISO9660 válido cujas entradas de directório carregam, nos bytes
reservados de "System Use", registos meus.**

Ou seja: ULTRA = ISO9660 (ECMA-119) como base inalterada + uma camada de
extensão minha, escrita no espaço que a norma deixa deliberadamente livre.

Não é um formato novo. É um descendente.

---

## 2. Porque é que esta via e não um formato novo

Quando se propõe "o nosso sistema de ficheiros", o instinto é desenhar um
formato de raiz. É a decisão mais cara que se pode tomar num SO, porque um
formato é um compromisso com dados de utilizadores: qualquer erro de layout
que escrevas num disco fica lá para sempre, e ninguém mais te vai actualizar.

O caminho do ULTRA evita esse compromisso quase todo, por três razões.

**Primeira: o leitor já existe, e está debugado.** O nosso primeiro estágio
(`inicio/inicio_minimo.asm`) já percorre uma árvore ISO9660 real — volume
descriptor, directório raiz, subdirectório, ficheiro — para encontrar o
segundo estágio dentro da ISO de arranque. Funciona, foi verificado byte a
byte em QEMU. Se o ULTRA for ISO9660 + extensão, o driver do ULTRA não é um
driver novo: é **o mesmo código mais um leitor de registos extra**. Um bug
corrigido há dois meses está corrigido nos dois sítios.

**Segunda: ganhamos um oráculo de testes externo, de graça.** Este é o
argumento forte e o mais ignorado. Se o `formata` do Maisus escrever um
disco ULTRA, então esse disco tem de passar:

- `isoinfo -d -i imagem.img` — lista o volume e o directório raiz
- `xorriso -indev imagem.img -report_el_torito plain`
- `mount -o loop,ro imagem.img /mnt` — monta e lê a árvore de directórios
- `mount -t iso9660 /dev/sda1` — depois de instalado, sem loop

Ou seja: **a implementação de referência da base é o Linux, e está instalada
na tua máquina.** Não és tu a validar o teu código contra ti próprio. Com um
formato inventado, essa rede desaparece e ficas com um formatador e um leitor
que podem estar ambos errados *à mesma maneira*, passando os testes todos.

**Terceira: o ISO9660 não distingue CD de disco.** É a mesma estrutura nos
dois meios. Isto resolve um problema que ainda não chegou mas que viria: a
divergência entre "o que arrancou da ISO" e "o que foi instalado no
disco". Com o ULTRA não há divergência possível — é literalmente o mesmo
formato. O que arranca da ISO é uma cópia byte-a-byte do que vai para o HD.

E há um quarto efeito, mais prático que técnico: **resgate**. Se o Maisus não
arrancar, o utilizador (ou tu, a depurar) copia os ficheiros para fora com
`cp`. Isso vale muito mais do que parece num SO jovem.

---

## 3. O que herdamos do ISO9660 (e é bom)

O ISO9660 tem cinco decisões de desenho que são genuinamente boas e que o
ULTRA mantém tal e qual:

| Decisão | Porquê vale a pena |
|---|---|
| **Directório é um ficheiro** cujo conteúdo são entradas | Um único `abrir(caminho)` recursivo. Sem tabelas de inode, sem índices, sem cache de metadados, sem estado a manter consistente entre estruturas. |
| **Ficheiro = lista de extents** (não "bloco inicial + tamanho") | Fragmentação não custa nada. Um ficheiro não-contíguo é exactamente igual a um contíguo para quem o lê. |
| **Entrada auto-delimitada**: byte 0 = comprimento da entrada; byte 0 = 0 = fim do bloco | Percorrer um directório é saltar de comprimento em comprimento. Não é preciso conhecer o tamanho de nenhum campo para saber onde está a próxima entrada. Isto é a propriedade mais elegante do formato. |
| **Endereçamento por extent (LBA)**, nunca CHS | |
| **Um único volume descriptor** no início do volume, com tudo o que é global | |

A entrada de directório ISO9660 fica assim (posições em bytes, dentro do
directório):

```
 0   comprimento da entrada (0 = fim do bloco)
 1   comprimento dos atributos estendidos
 2   extent, 32 bits LE          <- LBA do primeiro bloco
10   comprimento dos dados, LE   <- em bytes
18   data e hora de gravação (7 bytes)
25   flags (bit 1 = é directório)
26   tamanho da unidade de ficheiro
27   salto de intercalação
28   número de sequência do volume, 16 bits LE
32   comprimento do identificador
33   identificador (8.3, ou 31 chars no nível 2)
 ..  byte de paridade se o identificador tiver comprimento ímpar
 ..  SYSTEM USE AREA  <- o espaço onde o ULTRA vive
```

---

## 4. O que é que o ULTRA acrescenta

A norma ISO9660 é deliberadamente incompleta: deixa por definir os últimos
bytes de cada entrada de directório — a *System Use Area*. É aí que vivem o
Rock Ridge, o Joliet e o El Torito. É esse o espaço onde o ULTRA escreve.

Já é exactamente o que outros fizeram:

- **Rock Ridge / RRIP** (SUSP) — nomes POSIX, permissões, `uid`/`gid`,
  links simbólicos, numeração de dispositivo. É o que o Linux lê.
- **Joliet** — nomes em Unicode (UCS-2), até 64 caracteres.
- **El Torito** — registos de arranque (CD apenas).

O ULTRA faz o mesmo pela base: escreve ali os seus próprios registos, com
identificadores de 2 bytes escolhidos por mim, na forma que a SUSP usa
(cada registo: 2 bytes de assinatura, 1 de comprimento, 1 de versão, dados;
avançar para o limite par seguinte).

Estratégia que recomendo: escrever **Rock Ridge ao mesmo tempo** que os
registos ULTRA. Rock Ridge custa quase nada e é o que faz o `mount` do Linux
mostrar os nomes a sério. Assim o volume é, para toda a gente a sério,
"ISO9660 + Rock Ridge", e para o Maisus é "ISO9660 + Rock Ridge + ULTRA". Um
superset honesto.

### 4.1 As duas razões que justificam um ULTRA próprio

Sem estas, o ULTRA seria Rock Ridge em português e valia a pena eliminá-lo.

**Razão A — o ISO9660 foi desenhado para mídia write-once.** Os CD-R só se
acendem. Consequência directa no formato: *modificar* um ficheiro não é
sobrescrever, é **alocar extents novos** e apontar a entrada para eles. O
espaço antigo fica órfão e é perdido, para sempre, sem forma de o
reclaimar — a norma não tem qualquer mecanismo de espaço livre. Numa
mídia de escrita única isso é irrelevante. Num disco de acesso aleatório é
absurdo.

O ULTRA pode, sem sair da norma, ter uma política de alocação diferente:
sobrescrever no lugar enquanto houver espaço, e ter um mecanismo de
*recolha de espaço* (livre + reclamar) para o resto.

**Razão B — não há consistência.** A norma não tem journal. Uma instalação
a meio, um sector sobrescrito pelo RAID, uma falha de corrente: o volume fica
incoerente e não há forma de o recuperar. Nenhum nível de "System Use"
resolve isto sem mexer no motor de alocação. É o problema estrutural, e é o
único que justifica um formato próprio.

**Candidatos a registos ULTRA** (por decidir, não decidido):

- integridade por bloco (soma de verificação por extent, verificada na leitura)
- length / tamanho lógico vs. físico, para ficheiros esparsos
- marcação de blocos sujos, para escusa de reescrita
- referência a um log de transacções (journal)
- instantaneous / snapshot de um subdirectório

**Regra de ouro:** só se escreve um registo ULTRA quando existe uma
funcionalidade do kernel que o usa. Reservar a área desde o dia 1; não a
encher de campos por mnemónica.

---

## 5. Estrutura no disco

O formato é o ISO9660, portanto a estrutura é a do ISO9660. Bloco lógico de
**2048 bytes** — é fixo pela norma, não é escolha nossa (ver §7).

```
LBA 0        boot sector / MBR          (não faz parte do volume ISO)
LBA 2048     volume descriptor primário
LBA 2049     system area (zeros)
LBA 2050     bootstrap: directório raiz
             ... conteúdo dos directórios e dados dos ficheiros ...
```

Quando instalado num disco duro, o desenho é o de uma **ISO híbrida**, que é
o que o Ubuntu já faz numa pen USB: tabela de partições no MBR, partição 1
começando a 1 MiB (LBA 2048, alinhada), e lá dentro o volume ISO9660 inteiro.

```
LBA 0        MBR: tabela de partições + loader do Maisus
LBA 1..2047  reservado (alinhamento)
LBA 2048+    volume ISO9660 (com as extensões ULTRA)
```

Isto resolve os dois mundos de uma vez:

- a BIOS lê o MBR e carrega o loader (o ISO9660 não é arrancável pela BIOS
  num disco — El Torito é só para CD);
- o Linux monta `/dev/sda1` como `iso9660` normal.

E o loader, uma vez carregado, lê o volume com o mesmo leitor que lê a ISO
de arranque. **Zero código específico de disco.**

---

## 6. Nomes

A base fica com o nome estrito da norma (8.3 maiúsculo no nível 1, até 31
caracteres no nível 2). O nome "a sério" — com minúsculas, acentuação,
comprimento variável — vai nos registos de System Use:

- para o Maisus: registos ULTRA (UTF-8, comprimento a definir — 32 ou 64)
- para o Linux: registos NM do Rock Ridge, se e quando for escrito

Ou seja, quem só conhece a norma lê `/INICIO/INICIO.MAI;1`; quem conhece as
extensões lê `inicio/inicio.mai`.

Há um ponto a tener em atenção: para o volume ser útil a ferramentas que só
sabem ISO9660 puro (o `cp` de um live-CD antigo, por exemplo), o nome da
base tem de ser razoável. Convenção sensata: manter o nome 8.3 sempre
derivável do nome verdadeiro, para o caso de alguém montar o disco num
leitor minimalista.

---

## 7. Limites herdados (a parte honesta)

Isto é o preço de "ser reconhecido", e é real e permanente:

- **Blocos de 2048 bytes, para sempre.** É a fricção ×4 com a INT 13h
  (que lê 512 bytes). Todo o driver fala em *blocos*, e só uma função no
  fundo converte blocos → sectores de 512. Está isolado, mas está lá. Num
  disco SSD, 2048 bytes não é alinhado à página de 4 KiB — mais uma razão
  para o nível de journaling e alocação ser bem pensado.
- **A norma está congelada.** Não se pode corrigir a base, só acrescentar.
  Um erro nosso na base é nosso para sempre.
- **Sem hard links, sem reflinks, sem ficheiros esparsos** (salvo se o
  ULTRA inventar isso nos seus registos).
- **Directórios por varrimento linear.** Entrada a entrada, sem índice. Com
  50 ficheiros, óptimo. Com 5000 num directório, lento. Aceitável na v1; o
  formato não impede um índice em registros ULTRA mais tarde.
- **Volume limitado nos primeiros níveis da norma** (o nível 3 remove
  praticamente esse limite).

---

## 8. Cadeia de ferramentas

O ULTRA obriga a uma ferramenta de host, e ela é tão importante como o
formato.

```
Build.sh ──► ISO9660 ──► arranque                    (já funciona)

          formata (no Maisus)  ──► disco ULTRA
          mkultra (no host)    ──► imagem .img
                                   ▲
                                   └── oráculo de testes:
                                       isoinfo, xorriso, mount -o loop
```

Regra de processo que evito muito dinheiro: **especificar o formato em bytes
neste documento primeiro, escrever o `mkultra.py` depois, e só então o
leitor ULTRA.** Se o leitor for escrito primeiro, o leitor e o formatador
partilham a mesma interpretação errada e os testes passam todos.

E: **ler antes de escrever.** Escrever um sistema de ficheiros é o triplo do
trabalho. A v1 do ULTRA é só-leitura; o `formata` vem depois de haver um
leitor validado contra uma imagem independente.

---

## 9. Relação com o código actual

O que já existe e fica:

| Ficheiro | Papel hoje | Papel amanhã |
|---|---|---|
| `inicio/inicio_minimo.asm` | primeiro estágio: limpa o ecrã, caminha a ISO9660, carrega o segundo estágio | **base do driver ULTRA.** Anuncia a assinatura ULTRA e salta para o modo kernel |
| `inicio/inicio.asm` | segundo estágio: escreve a versão do build e pára | onde vive o leitor de registos ULTRA e, mais tarde, o `formata` |
| `Build.sh` | monta a ISO e arranca o QEMU | idem, mais uma rota para gerar imagens ULTRA de teste |

**A resolução do "não quero ficar preso a uma ISO9660" muda de forma.** Não é
suportar vários sistemas de ficheiros em paralelo — é ser descendente de um
só. Uma linhagem em vez de cinco. O `ler()` do primeiro estágio já é
independente do tipo de meio (só fala INT 13h com um DAP); a camada de
directórios é que era ISO9660 — e é essa camada que o ULTRA reaproveita em
vez de duplicar.

---

## 10. Em aberto (decidir antes de escrever código)

1. **Nível ISO9660.** Nível 2 (31 caracteres, 8 níveis) é o mínimo
   sensato. Nível 3 alarga nomes e levels.
2. **Registos ULTRA da v1.** Provavelmente integridade por bloco, e nada
   mais. Journal só quando o kernel precisar dele.
3. **Política de alocação.** Sobrescrever no lugar (contra a norma, a favor do
   disco) versus seguir a norma e alocar sempre extents novos. É a decisão
   de desenho mais consequente de todas, e é a razão de ser do ULTRA.
4. **Tamanho do nome verdadeiro.** 32 ou 64 bytes.
5. **Rock Ridge na v1?** Provavelmente não — só quando o `mount` do Linux
   deixar de mostrar os nomes 8.3.

---

## 11. Uma frase para repetir quando a dúvida vier

> O ULTRA não substitui o ISO9660: **é** um ISO9660. Por isso nunca vamos
> ficar presos a um sistema de ficheiros, e por isso o que o Maisus escreve
> num disco é sempre legível por outra gente.