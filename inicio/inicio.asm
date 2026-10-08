; ============================================================================
;  Maisus - inicio.asm
;  Gerenciador de boot - segundo estagio
;
;  Carregado por inimin.mai da ISO (/inicio/inicio.mai) para BASE:0x0000.
;  Convencao de entrada: CS=IP=BASE, DS=BASE, ES=0x0000.
;
;  missao: escrever o titulo na segunda linha, as tres opcoes do menu na quarta,
;          quinta e sexta linhas (uma em baixo da outra, com dois caracteres de
;          margem a esquerda), um '*' na coluna 0 da quarta linha - a marca do
;          menu, que as setas para cima e para baixo vao mudando de linha, antes
;          e depois do relogio parar - e, na penultima, a mensagem que diz como
;          se usa o ecra - a frase toda de uma vez, e depois o numero dos
;          segundos a descer no meio dela, de 4 a 0. Quem nao mexer nas teclas
;          ve o relogio chegar a zero e o nucleo arrancar sem mais perguntas;
;          quem aperta o enter arranca logo o nucleo, sem esperar pelo relogio; e
;          quem mexer numa seta ve a parte da frase que fala do relogio
;          desaparecer do ecra e o arranque passar a esperar pelo enter.
;
;          As teclas deste ecra sao lidas pelo driver de teclado e nao pela
;          BIOS. O driver (/drivers/teclado.dr) e carregado e ligado logo depois
;          de o ecra estar escrito e antes da contagem comecar: fica com a IRQ1,
;          le os scancodes da porta do controlador e guarda-os num buffer
;          proprio, e a le_tecla (em baixo) so lhe pede a proxima tecla. Por
;          isso a carga do driver e feita cedo, por carregar_teclado, e a
;          caminhada ja nao a repete: encontra o driver no sitio e ligado.
;
;          O enter decide pela linha em que a marca esta: na primeira
;          ("MaisSus Beta") arranca o nucleo, na segunda ("Recuperacao")
;          carrega o recu.mai da ISO e salta para ele, e na terceira ("sair") nao
;          ha nada a fazer. A escolha fica escrita na area de dados (escolha) e
;          e lida no fim da caminhada, porque a escolha acontece antes dela.
;          A seguir carrega da ISO o nucleo
;          (/nucleo/0.12.2026), o driver de video (/drivers/video.dr) e a
;          interface (/interface/face.grain) e as tres imagens que ela executa a
;          seguir, por esta ordem - a barra inferior (/interface/barinf.grain),
;          a barra superior (/interface/barsup.grain) e o menu
;          (/interface/menu.grain) - o logo (/imagens/logo.img), o decodificador
;          (/imagens/decod.img) e a propria recuperacao (/inicio/recu.mai), e
;          entregar o controlo ao nucleo ou a recuperacao, conforme a escolha.
;  saida: nucleo (0.12.2026) ou recuperacao (recu.mai)
;
;  O nucleo entra sem levar nada na mao: os dois ficheiros ja estao na memoria
;  nos sitios onde ele vai buscar (as constantes de nucleo.asm). A espera de 4
;  segundos e a descida do numero, nao uma espera a mais depois dela: o controlo
;  so passa ao nucleo com a frase no ecra e o numero a zero, com a frase sem a
;  parte do relogio se quem parou o relogio foi uma seta, ou sem esperar pelo zero
;  se quem arrancou foi o enter.
; ============================================================================

BITS 16

; O sector 0 carrega este ficheiro em 0xA000 (linear) com o segmento 0x0A00 e
; salta para 0x0000:0xA000 - ou seja, entra aqui com CS = 0 e a correr sobre
; enderecos lineares, que e porque o ORG e o BASE. O BASE e por isso um
; endereco LINEAR e nunca um segmento: para o meter num registo de segmento
; divide-se por 16 (SEG_BASE), como se faz com o driver de teclado.
BASE       equ 0xA000          ; endereco linear deste sector em memoria
ORG BASE
SEG_BASE   equ BASE >> 4       ; o segmento que aponta para este sector (0x0A00)

SEG_VIDEO  equ 0xB800          ; inicio do buffer de texto
COLS       equ 80              ; colunas do modo 80x25 (centrar o titulo)
LINHA_TIT  equ 1              ; linha onde o titulo e escrito (0 = a primeira)
LINHA_MENU equ 3              ; linha da primeira opcao do menu (a quarta)
MENU_COL   equ 2              ; coluna das opcoes: dois caracteres de margem
LINHA_MSG  equ 23             ; penultima linha (o 80x25 tem 25 linhas, 0 a 24)
ATRIB      equ 0x0E            ; amarelo claro sobre preto
SETA_CIMA  equ 0x18            ; seta para cima na fonte do BIOS (CP437)
SETA_BAIXO equ 0x19            ; seta para baixo na fonte do BIOS (CP437)

; As duas setas das teclas. Sao teclas especiais - nao tem ASCII nenhum - e por
; isso o driver as entrega pelo scancode e nao por um caracter. As setas do
; teclado numerico sao teclas alargadas (o prefixo E0) mas o scancode e o mesmo:
; o driver tira o prefixo e deixa-o a parte, no TEC_I_PREF, por isso as duas
; setas chegam aqui com o mesmo numero.
;
; Os numeros sao os do teclado (0x48 a seta para cima, 0x50 a de baixo) e quem
; os le e a le_tecla, que pergunta ao driver; o driver le-os do registo de dados
; do controlador (notas em drivers/teclado.asm).
TECLA_CIMA  equ 0x48            ; scancode da seta para cima
TECLA_BAIXO equ 0x50            ; scancode da seta para baixo
TECLA_ENTER equ 0x1C            ; scancode do enter (o do teclado numerico e E0 1C)

; As tres respostas de le_tecla (o rotulo da rotina esta em baixo): o que a
; tecla lida era. E uma resposta e nao uma tecla porque o que o arranque faz com
; ela depende do sitio em que se esta - uma seta durante a contagem para o
; relogio e, depois de o relogio ter parado, mexe na marca; o enter arranca o
; nucleo nos dois tempos, desde que a marca esteja na primeira opcao.
RES_NADA   equ 0                ; nao ha tecla, ou ha uma que aqui nao faz nada
RES_SETA   equ 1                ; uma das duas setas (mexeu na marca, ou tentou)
RES_ENTER  equ 2                ; o enter

; Uma linha do buffer de texto, em bytes: COLS celulas de 2 bytes cada. E o
; passo que a marca do menu da a cada tecla (uma linha de ecra para cima ou
; para baixo) e o que define MARCA_TOPO e MARCA_FIM.
BYTES_LINHA equ COLS * 2

; A marca do menu: um '*' na coluna 0 da primeira das tres linhas das opcoes
; (LINHA_MENU, a quarta linha), a duas colunas do texto - a margem MENU_COL e do
; texto das opcoes e a marca fica a esquerda dela. Cada constante e a celula da
; linha em bytes, que e o que o codigo carrega em DI.
;
; A marca nao passa de MARCA_TOPO a MARCA_FIM: as setas que a movem sao as do
; menu e o menu tem tres linhas, uma por opcao. Nao e uma regra escrita no
; codigo das setas e sim uma consequencia das duas celulas - mudar o menu e
; mudar estas duas contas, e nao o resto.
MARCA_LIN   equ LINHA_MENU * BYTES_LINHA         ; onde a marca nasce
MARCA_TOPO  equ MARCA_LIN                       ; nem uma linha para cima
MARCA_FIM   equ (LINHA_MENU + 2) * BYTES_LINHA   ; nem uma linha para baixo

; A segunda linha do menu, a de "Recuperacao", e a unica celula do ecra que tem
; um nome: e a linha em que a marca esta quando o enter arranca a recuperacao
; em vez do nucleo (ver a espera_enter). Vive aqui, e nao escrita a mao na
; espera_enter, porque e uma celula do ecra como as outras duas e a conta e a
; mesma: MARCA_LIN mais uma linha de BYTES_LINHA bytes.
;
; Porque a segunda e nao a terceira: "Recuperacao" e a unica das tres opcoes que
; tem o que fazer - a primeira arranca o nucleo e a terceira, "sair", ainda nao
; faz nada. Um nome para a celula do meio deixa isso escrito no sitio onde a
; celula esta, e nao espalhado pelo codigo que a le.
MARCA_REC   equ MARCA_LIN + BYTES_LINHA          ; "Recuperacao", a segunda

; Endereco LINEAR onde o nucleo e carregado, e o segmento correspondente.
; Sao dois numeros diferentes e confundir-los e o erro classico do modo real:
; o segmento 0xC00 cobre 0xC000, mas o segmento 0xC000 cobre 0xC0000 (768 KiB).
; O nucleo carrega com NUC_SEG:0x0000 e o codigo dele e ligado para NUC_SEG.
NUC_LIN    equ 0xC000          ; endereco linear do nucleo
NUC_SEG    equ NUC_LIN >> 4    ; 0xC00

; Endereco LINEAR onde o driver de video e carregado, e o segmento
; correspondente. Sao dois numeros diferentes e confundir-los e o erro classico
; do modo real: o segmento 0xE00 cobre 0xE000, mas o segmento 0xE000 cobre
; 0xE0000 (896 KiB). O driver chama-se a si mesmo pelo segmento 0xE00, e por isso
; que a imagem dele e ligada para esse segmento.
DRV_LIN    equ 0xE000          ; endereco linear do driver
DRV_SEG    equ DRV_LIN >> 4    ; 0xE00

; Endereco LINEAR onde o driver de teclado e carregado, e o segmento
; correspondente. Fica a seguir ao menu da interface (0x50000) e muito longe da
; janela do video (0xA0000), para nao calhar dentro de nenhum dos dois.
; O driver e pequeno e vive quieto: e chamado pelo inicio.mai e, no passo
; seguinte, pelo nucleo - nenhum dos dois o move de sitio.
TEC_LIN    equ 0x60000         ; endereco linear do driver de teclado
TEC_SEG    equ TEC_LIN >> 4    ; 0x6000

; O cabecalho do driver de teclado, e o contrato com que se fala com ele
; (teclado.asm tem as mesmas definicoes, campo a campo):
;   offset 0  dword  assinatura 'TEC1'
;   offset 4  word   versao do contrato (2)
;   offset 6  word   reservado
; A entrada e logo a seguir ao cabecalho, nos 8 bytes, como no video.dr.
TEC_ASSIN   equ 0x31434554      ; 'T','E','C','1' por ordem de bytes
TEC_VERSAO  equ 2               ; a versao do contrato que este sector fala
TEC_INI     equ 8               ; a entrada do driver (ver o cabecalho)
TEC_CMD_INI equ 0               ; inicializar: instalar o handler e ligar o teclado
TEC_CMD_LER equ 1               ; tirar a proxima tecla do buffer

; A estrutura que o driver preenche (os mesmos numeros em teclado.asm):
TEC_I_ASSIN  equ 0x00           ; a assinatura, que o driver confirma
TEC_I_VERSAO equ 0x04           ; a versao: 0xFFFF ate o driver a escrever
TEC_I_FLAGS  equ 0x06           ; bit 0: o driver ainda tem teclas no buffer
TEC_I_ESTADO equ 0x08           ; o registo de estado lido em 0x64 (CMD_INI)
TEC_I_TECLA  equ 0x09           ; o scancode da ultima tecla lida (CMD_LER)
TEC_I_PREF   equ 0x0A           ; o prefixo dela: 0 normal, 0xE0 alargada
TEC_I_MODS   equ 0x0B           ; os modificadores (shift, ctrl, alt)

; O driver de rato segue a mesma regra do teclado, tres segmentos acima (o
; teclado em 0x6000, o logo em 0x7000 e o decodificador em 0x8000), no primeiro
; sitio livre a seguir a eles. E carregado pelo inicio.mai como os outros; quem
; o executa e o nucleo, depois de o video estar configurado.
MOU_LIN    equ 0x90000         ; endereco linear do driver de rato
MOU_SEG    equ MOU_LIN >> 4    ; 0x9000

; O cabecalho do driver de rato (as mesmas definicoes em mouse.asm):
;   offset 0  dword  assinatura 'MOU1'
;   offset 4  word   versao do contrato (1)
;   offset 6  word   reservado
; A entrada e logo a seguir ao cabecalho, nos 8 bytes, como nos outros drivers.
MOU_ASSIN   equ 0x31554F4D      ; 'M','O','U','1' por ordem de bytes
MOU_VERSAO  equ 1               ; a versao do contrato que este driver fala
MOU_INI     equ 8               ; a entrada do driver (ver o cabecalho)
MOU_CMD_INI equ 0               ; o unico comando por enquanto: inicializar

; A barra inferior segue a mesma regra, dois segmentos acima da interface: o
; face.grain vive em 0x2000:0x0000 e a barra em 0x3000:0x0000, por isso nenhum
; dos dois pode estar a ser executado de cima do outro. Os dois sitios estao na
; memoria convencional livre (abaixo de 0xA000), longe do framebuffer, que num
; modo VESA vive bem acima de 1 MiB.
;
; O numero e o endereco LINEAR, como o do nucleo e o do driver: o segmento de
; destino e o linear dividido por 16 (0x30000 >> 4 = 0x3000). Escrever 0x3000
; aqui punha a barra em 0x3000:0x0000, isto e, no linear 0x3000, e o face.grain
; saltava para um segmento vazio.
BAR_LIN    equ 0x30000         ; endereco linear da barra
BAR_SEG    equ BAR_LIN >> 4    ; 0x3000 - o segmento que o face.grain salta

; A barra superior segue a mesma regra, mas precisa do seu proprio sitio: o
; face.grain salta para a barra inferior e e o barinf.grain que salta para a
; superior - uma imagem nao pode estar a ser executada de cima da outra. Fica em
; 0x4000:0x0000 (linear 0x40000), dois segmentos acima da barra inferior e tres
; acima da interface.
; Os sitios de toda a corrente (a interface, as duas barras e o menu) estao na
; memoria convencional livre (abaixo de 0xA000), longe do framebuffer, que num
; modo VESA vive bem acima de 1 MiB.
SUP_LIN    equ 0x40000         ; endereco linear da barra superior
SUP_SEG    equ SUP_LIN >> 4    ; 0x4000 - o segmento que o barinf.grain salta

; O menu e a ultima imagem da cadeia e segue a mesma regra: e o barsup.grain que
; salta para ele, e e o menu que devolve o controlo ao face.grain, que fica no
; ciclo da bolinha do rato. Vive em 0x5000:0x0000 (linear 0x50000), dois
; segmentos acima da barra superior. Nenhuma das quatro imagens se sobrepoe a
; outra, e nenhuma toca no framebuffer.
MEN_LIN    equ 0x50000         ; endereco linear do menu
MEN_SEG    equ MEN_LIN >> 4    ; 0x5000 - o segmento que o barsup.grain salta

; ---------------------------------------------------------------------------
; A recuperacao (inicio/recuperacao.asm -> inicio/recu.mai) segue a mesma regra
; de endereco fixo, mas nao na mesma escala: vive em REC_SEG:0x0000, isto e no
; linear 0x9000, e nao em 0x9000:0x0000 como as imagens da corrente.
;
; A razao de ser o unico sitio abaixo de 0xA000 e a memoria que o sector 0 e o
; proprio inicio.mai ja ocupam. O mapa e este:
;
;     0x0500-0x0BFF   janela classica da BIOS
;     0x7BFF          a pilha deste sector
;     0x7C00-0x7FFF   o sector 0 (inimin.mai), que ja entregou o controlo
;     0x8000-0x87FF   BUF, o sector de trabalho da caminhada pela ISO
;     0x9000-0x9FFF   a recuperacao (esta)          <- o que sobra
;     0xA000-0xB7FF   o inicio.mai, este sector
;     0xB800-0xBFFF   o buffer de texto
;
; O sector 0 carrega este ficheiro em 0xA000 com ESTAGIO_SET sectores, e o
; inicio.mai carrega os outros ficheiros de endereco fixo na memoria
; convencional - por isso nenhum dos dois pode ser mudado de sitio sem mexer no
; outro. E o que obriga a recuperacao a um sitio tao baixo: ela e a unica imagem
; que nao pode ir para a serie 0x2xxxx-0x8xxxx (que e onde vivem o nucleo, os
; drivers, a interface e as imagens), porque essa serie esta toda em cima, e o
; que fica abaixo do inicio.mai e a janela de video e o sector 0.
;
; O REC_SET e o maximo de sectores que se leem num ficheiro. Dois sectores
; (4 KiB) chegam de sobra para um ecra de texto interativo e deixam a imagem
; (702 bytes hoje) longe do limite - a mesma razao do decodificador (DEC_SET): a
; margem existe para o inicio.mai poder carregar sectores inteiros sem o resto
; do sector ter de ser initialization data.
REC_LIN    equ 0x9000          ; endereco linear da recuperacao
REC_SEG    equ REC_LIN >> 4    ; 0x0900 - o segmento que este sector salta
REC_SET    equ 2              ; sectores maxima do recu.mai (2 x 2048 = 4 KiB)

; O cabecalho do recu.mai, e o contrato com que se fala com ele. E o mesmo
; formato dos outros (video.dr, teclado.dr, face.grain, e as duas barras e o
; menu): assinatura de 4 bytes, versao, reservado, e a entrada logo a seguir.
; A recuperacao valida a assinatura a si propria (como o menu faz), portanto
; aqui chega para a procurar e a carregar.
REC_ASSIN  equ 0x31434552      ; 'R','E','C','1' por ordem de bytes
REC_VERSAO equ 1               ; a versao do contrato que este sector fala
REC_INI    equ 8               ; a entrada da recuperacao (ver o cabecalho)

; A escolha do menu: o que o enter arranca. Vive em memoria e nao num registo
; porque e lida muito depois de ser escrita - a escolha acontece na espera do
; enter, e a leitura acontece no fim da caminhada pela ISO, com o DS ja a zero
; (a variable esta em DS:0 e o "cmp" tem de ser feito com o DS certo, por isso
; a escolha tambem e lida depois do "mov ds, 0"). Um registo nao sobrevivia a
; toda a caminhada, que muda quase todos os registos. Ver a nota do "escolha"
; junto da rotina espera_enter.
ESC_NUCLEO   equ 0             ; arrancar o nucleo (a primeira opcao)
ESC_RECUP    equ 1             ; arrancar a recuperacao (a segunda opcao)

; ---------------------------------------------------------------------------
; A imagem do logo e o decodificador que a desenha seguem a mesma regra das
; imagens da interface: cada um no seu segmento, porque sao ambos executados (ou
; lidos) de cima do sitio onde estao, e nenhum pode estar em cima do outro.
;
; O logo (imagens/logo.img) vive em 0x7000:0x0000 (linear 0x70000). O que fica
; abaixo e o driver de teclado (0x60000) e o que fica acima e o decodificador
; (0x80000), pelo que nenhum dos tres se sobrepoe ao outro nem ao framebuffer
; (0xA0000 nos modos classicos, muito acima num modo VESA).
;
; O ficheiro .img e o que o conversor_de_imagens.py escreve a partir de
; imagens/image.png, e o Build.sh nao o corre: a conversao e a mao, para que o
; que vai para dentro da ISO seja sempre o que a pessoa escolheu ver (ver o
; "logo.img em falta" no Build.sh). O tamanho maximo e de 64 sectors (128 KiB),
; que e o que o decodificador aceita ler num segmento; um logo de 320x200 em
; 8 bits por pixel ocupa 32 sectores (65.040 bytes com a paleta e o cabecalho).
IMG_LIN    equ 0x70000         ; endereco linear do ficheiro .img do logo
IMG_SEG    equ IMG_LIN >> 4    ; 0x7000 - o segmento onde o .img e lido
IMG_SET    equ 64             ; sectores maxima do .img (64 x 2048 = 128 KiB)

; O decodificador (imagens/decod.img) e o codigo que o nucleo salta para
; desenhar a imagem no ecra. Fica em 0x8000:0x0000 (linear 0x80000), dois
; segmentos acima do .img (que e o ficheiro que ele vai ler), e o codigo em si
; so ocupa 879 bytes - o resto dos 12 KiB sao a margem que o "times" do fim do
; ficheiro reserva, para o inicio.mai poder carregar sectores inteiros sem que
; o que nao foi usado tenha de ser initialization data.
DEC_LIN    equ 0x80000         ; endereco linear do decodificador
DEC_SEG    equ DEC_LIN >> 4    ; 0x8000 - o segmento de onde o nucleo salta
DEC_SET    equ 12             ; sectores maxima do decodificador (12 KiB)

; O nome da pasta onde vivem os dois ficheiros, e os dois nomes, estao na
; area de dados no fim deste ficheiro (DIR_IMAGENS, FIC_LOGO e FIC_DEC) - o
; codigo e os dados tem de ficar depois do "start", e aqui so ha "equ". As
; constantes do comprimento vao la em baixo com cada nome (DIR_IM, FIC_LOGO_N e
; FIC_DEC_N), porque e so com o "db" ja escrito que o comprimento se conta -
; ver a nota das contas de comprimento junto ao primeiro nome.

BLOCO      equ 2048           ; bytes por sector logico (ISO9660 / El Torito)
PVD_LBA    equ 16             ; a norma obriga o 1.o descritor a estar aqui
PVD_TIPO   equ 1              ; tipo 1 = volume descriptor primario
MAX_DESCR  equ 16             ; quantos descritores se procuram no maximo
NUC_SET    equ 16             ; sectores maxima do nucleo (16 x 2048 = 32 KiB)
DRV_SET    equ 2              ; sectores maxima do driver (2 x 2048 = 4 KiB)
TEC_SET    equ 2              ; sectores maxima do driver de teclado (4 KiB)
MOU_SET    equ 2              ; sectores maxima do driver de rato (4 KiB)
BAR_SET    equ 4              ; sectores maxima da barra (4 x 2048 = 8 KiB)
SUP_SET    equ 4              ; sectores maxima da barra superior (4 x 2048 = 8 KiB)
MEN_SET    equ 4              ; sectores maxima do menu (4 x 2048 = 8 KiB)
N_UNIDADES equ 3              ; unidades na tabela de tentativas do sector 0

; Quanto tempo o numero do build fica no ecra antes de o controlo passar ao
; nucleo (em microssegundos).
ESPERA_US  equ 4000000        ; 4 segundos

; A espera de ESPERA_US e spentada em passos: cada passo e uma espera de
; PASSO_US, e a cada PASSOS_SEG passos o numero dos segundos desce um degrau.
; Sao DEGRAUS degraus ate ao zero - 4, 3, 2, 1 - e portanto DEGRAUS * PASSOS_SEG
; passos no total, que dao as mesmas ESPERA_US de sempre. As contas sao feitas em
; tempo de montagem e nao ha relogio nenhum a correr: o passo() e a unica coisa
; que espera, e o numero desce porque cada PASSOS_SEG passos passou um segundo.
DEGRAUS     equ 4              ; degraus do numero: 4 -> 3 -> 2 -> 1 -> 0
PASSOS_SEG  equ 15             ; passos por degrau (~1 s); cabe num byte
PASSO_TOTAL equ DEGRAUS * PASSOS_SEG      ; passos no total: 60
PASSO_US    equ ESPERA_US / PASSO_TOTAL   ; microssegundos por passo: 66666,
                                         ; que e o que cabe em CX:DX

; o descritor traz o tipo no byte 0 e a assinatura "CD001" nos bytes 1-5.
; Sao comparados 4 desses 5 bytes, lidos como dword a partir do offset 1:
; 43 44 30 30 ('C','D','0','0') em ordem de bytes = 0x30304443
SIG_CD001  equ 0x30304443

; Sector ISO de trabalho (o mesmo endereco para o PVD e para os dois
; directorios, por isso so se define uma vez).
BUF        equ 0x8000          ; livre: o sector 0 vive em 0x7C00-0x8000

; ---------------------------------------------------------------------------
; A pilha nao pode estar em 0xB800-0xC000: essa e a janela do buffer de texto e
; empilhar la vai para o ecra. Fica em 0x7BFF, abaixo do sector 0 (0x7C00) e
; acima da janela classica da BIOS (0x0500-0x0BFF).
; ---------------------------------------------------------------------------
PILHA      equ 0x7BFF

; ---------------------------------------------------------------------------
start:
    cld

    ; pilha propria: a do primeiro estagio ja nao serve
    xor ax, ax
    mov ss, ax
    mov sp, PILHA

    ; --- modo video: 80x25 texto, cor sobre preto -------------------------
    mov ax, 0x0003
    int 0x10

    ; --- escreve o titulo centrado na segunda linha ------------------------
    ; escreve-se diretamente no buffer de texto: cada celula ocupa 2 bytes
    ; (caracter + atributo). Nao se usa a INT 10h AH=13h porque a implementacao
    ; dessa funcao varia entre BIOS e aqui nao devolve nada.
    ;
    ; A linha e um offset de COLS * 2 bytes no mesmo buffer: a primeira linha
    ; comeca em 0, a segunda em 160. LINHA_TIT diz qual e a que se usa, para o
    ; titulo descer ou subir sem se mexer na conta do centro.
    ;
    ; Centrar e aritmetica de ensamblador, nao um dia a menos de ecra: as
    ; colunas que sobram dividem-se por dois e o que sobra da divisa fica a
    ; esquerda, por isso um titulo de comprimento impar fica um caracter mais
    ; para a esquerda. A conta e feita em tempo de montagem a partir de
    ; TITULO_N, por isso o titulo pode mudar de comprimento sem se tocar aqui.
    mov ax, SEG_VIDEO
    mov es, ax
    mov di, (LINHA_TIT * COLS + (COLS - TITULO_N) / 2) * 2  ; celula inicial
    mov cx, TITULO_N
    mov si, TITULO - BASE     ; DS=BASE, por isso SI e o deslocamento no segmento
.escreve:
    lodsb
    mov ah, ATRIB
    stosw                     ; caracter + atributo; avanca 2 bytes em DI
    xor ax, ax
    loop .escreve

; --- as tres opcoes do menu, a partir da quarta linha, uma em baixo da outra -
    ; Ao contrario do titulo e da frase, um menu nao se centra: vive a esquerda,
    ; com dois caracteres de margem (MENU_COL) para nao encostar a beira do ecra, e
    ; le-se de cima para baixo. Por isso nao ha aqui conta nenhuma de centro - cada
    ; linha e so um offset de COLS * 2 bytes mais a margem, e LINHA_MENU diz qual e
    ; a primeira delas.
    ;
    ; Sao tres linhas fixas, cada uma com o seu laco, e nao um laco sobre uma
    ; tabela de destinos: para tres opcoes que nao mudam, escrever as tres e mais
    ; claro do que um laco que tem de ir buscar sitio e texto ao mesmo tempo.
    ; O corpo de cada laco e o mesmo do titulo, acima.
    mov di, (LINHA_MENU * COLS + MENU_COL) * 2     ; a margem, na quarta linha
    mov si, MENU_1 - BASE
    mov cx, MENU_1_N
.escreve_m1:
    lodsb
    mov ah, ATRIB
    stosw
    loop .escreve_m1
    mov di, ((LINHA_MENU + 1) * COLS + MENU_COL) * 2  ; a mesma margem, uma linha abaixo
    mov si, MENU_2 - BASE
    mov cx, MENU_2_N
.escreve_m2:
    lodsb
    mov ah, ATRIB
    stosw
    loop .escreve_m2
    mov di, ((LINHA_MENU + 2) * COLS + MENU_COL) * 2  ; e na seguinte
    mov si, MENU_3 - BASE
    mov cx, MENU_3_N
.escreve_m3:
    lodsb
    mov ah, ATRIB
    stosw
    loop .escreve_m3

; --- o driver de teclado: /drivers/teclado.dr, antes da contagem ------------
;   O driver tem de estar carregado e ligado antes de a le_tecla comecar a
;   perguntar por teclas: e ele, e nao a BIOS, que as le. A carga e a mesma da
;   caminhada (ficheiro_teclado), mas feita aqui, com o DS e o ES da caminhada
;   postos e repostos em volta (ver a nota do bloco da caminhada). Se o driver
;   nao entrar, o arranque para no ecra de erro, como por qualquer ficheiro em
;   falta.
    call carregar_teclado
    jc  falha

; --- a mensagem da penultima linha, toda no ecra de uma vez ---------------
    ; O titulo sozinho dizia o que arrancava, mas nao o que se espera aqui: esta
    ; e a unica altura em que se pode escolher teclas. A frase entra de uma vez,
    ; inteira e centrada, e so depois e que o numero dos segundos - que esta
    ; escrito no meio dela - comeca a descer no sitio, de 4 a 0.
    ;
    ; A frase vai toda num instante, e nao letra a letra, por uma razao pratica:
    ; escrita aos bocados so ficava completa no fim da espera, no mesmo instante
    ; em que o nucleo arranca, e nao havia tempo nenhum para a ler. Assim ela esta
    ; la desde o principio e fica la a ser lida durante os 4 segundos todos,
    ; enquanto o numero desce por cima dela.
    ;
    ; O numero vive em BH e os passos que faltam em BL. Nao vale a pena guardalos
    ; em memoria - ver a nota no fim dos dados deste sector - e assim nao ha
    ; estado nenhum escondido no sector: o que o ecra mostra esta nos registros.
    mov bx, '4' << 8 | PASSOS_SEG  ; BH = o numero, BL = passos ate ao proximo
    mov ax, SEG_VIDEO                ;        degrau
    mov es, ax
    mov di, (LINHA_MSG * COLS + MSG_COL) * 2
    mov si, MSG_ESP - BASE  ; a frase, ate ao numero
    mov cx, MSG_ESP_N
.escreve_esp:
    lodsb
    mov ah, ATRIB
    stosw                     ; caracter + atributo; avanca 2 bytes em DI
    loop .escreve_esp
    mov ax, ATRIB << 8 | '4'  ; aqui DI ja aponta para a celula do numero:
    stosw                     ; escreve-se entre as duas metades da frase
    mov si, MSG_SEG - BASE
    mov cx, MSG_SEG_N         ; e escreve a parte que vem depois do numero
.escreve_seg:
    lodsb
    mov ah, ATRIB
    stosw
    loop .escreve_seg

; --- a marca do menu: o '*' da coluna 0, na quarta linha -------------------
    ; A marca e a unica coisa deste ecra que se mexe: enquanto o numero dos
    ; segundos desce, as setas para cima e para baixo mudam-lhe a linha, dentro
    ; das tres linhas do menu (e so dentro delas - ver MARCA_TOPO e MARCA_FIM).
    ;
    ; Nasce na primeira das tres, na coluna 0, e escreve-se uma vez so. Mexer
    ; nela e mexer no '*', nunca na linha: o texto das opcoes nao muda, e
    ; reescreve-lo a cada tecla seria trabalho a mais para o mesmo efeito (ver
    ; a le_tecla, em baixo).
    ;
    ; A linha da marca vive em DI e nao em memoria: e o unico registo que o
    ; passo() nao mexe (ver a nota do passo()), e assim o ecra e os registos
    ; continuam a ser a mesma coisa - como o numero dos segundos, que tambem
    ; nao precisa de memoria nenhuma.
    mov ax, SEG_VIDEO
    mov es, ax                ; o ecra; o mesmo ES que o passo() usa
    mov di, MARCA_LIN         ; a celula onde a marca nasce
    mov cl, '*'
    call celula

    ; --- a espera de ESPERA_US, so que a medir o numero ----------------------
    ;   Um passo e uma espera de PASSO_US; a cada PASSOS_SEG passos o numero
    ;   desce um degrau: 4, 3, 2, 1, 0. Sao DEGRAUS * PASSOS_SEG passos no
    ;   total, que dao as mesmas ESPERA_US de sempre - quem manda no arranque e o
    ;   zero no ecra, e nao uma contagem de voltas. A BIOS arredonda cada espera
    ;   para o relogio dela, para mais ou para menos, e por isso que isto e um
    ;   "enquanto o numero nao for zero" e nao um numero fixo de passos.
    ;
    ;   A le_tecla entra uma vez por passo, entre uma espera e a seguinte: e
    ;   o que pergunta as teclas sem acrescentar tempo nenhum a espera (ela nao
    ;   espera - ver a nota dela), e da para mexer na marca as vezes que a
    ;   pessoa quiser durante os 4 segundos todos.
    ;
    ;   As tres respostas, e o que se faz com cada uma. Uma seta (RES_SETA) sai
    ;   do laco para o .parou: o relogio acaba ali - mesmo que a marca nao tenha
    ;   mexido por estar no limite, porque o que parou o relogio foi a mao da
    ;   pessoa e nao a marca. O enter (RES_ENTER) arranca o nucleo sem esperar
    ;   pelo zero, que e o que a frase do ecra promete desde o principio. E nada
    ;   (RES_NADA) e o passo seguinte: o relogio desce mais um degrau e, sem
    ;   teclas, chega a zero - e ai tambem arranca.
    ;
    ;   O enter e aceite aqui pelas mesmas razoes que o e no espera_enter: so na
    ;   primeira opcao. Durante a contagem isso e automatico - a marca comeca no
    ;   topo e a primeira seta que a pessoa aperta ja manda o laco para o .parou,
    ;   de modo que so esta no topo quem nao mexeu em nada. A comparacao fica
    ;   aqui na mesma para os dois lacos terem uma regra so, e para nenhum deles
    ;   poder discordar sobre o que o enter arranca.
.conta:
    cmp bh, '0'
    jbe pronto                 ; ja a zero: o nucleo pode arrancar
    call le_tecla              ; uma tecla? E o que ela e
    cmp al, RES_ENTER
    je  .enter                 ; o enter: o nucleo arranca, sem esperar pelo zero
    cmp al, RES_SETA
    je  .parou                 ; uma seta: o relogio acaba aqui
    call passo
    jmp .conta
.enter:
    cmp di, MARCA_TOPO         ; a regra e a do espera_enter: so na primeira
    je  pronto                 ; opcao e que o enter arranca o nucleo (na
    jmp .conta                 ; contagem, e sempre o caso)

; --- a pessoa mexeu: o relogio para e o enter manda no arranque -------------
    ; Sai-se do laco da espera, mas nao se para o arranque: o que muda e quem
    ; decide. Ate aqui quem mandava era o relogio (o zero no ecra); agora e a
    ; pessoa, e o enter - a tecla que a frase do ecra esta a dizer desde o
    ; principio.
    ;
    ; O enter e a outra saida do laco, e sai por cima: quem o aperta durante a
    ; contagem vai direitinho ao "pronto", sem passar por aqui e sem esperar
    ; pelo zero. Nao se apaga a parte do relogio da frase nesse caso: ela era
    ; verdadeira ate ao enter, e o nucleo que em segundos vai tar por cima do
    ; ecra todo.
    ;
    ; A ordem das duas coisas e a que se ve: primeiro a frase deixa de prometer
    ; o relogio (e o numero vai com ela), so depois e que o arranque espera. Se
    ; fosse ao contrario, o ecra ficava a mentir durante o tempo que se ficava
    ; a esperar pela tecla seguinte.
.parou:
    call apaga_relogio         ; ", ou espere N segundos" deixa de ser verdade
    call espera_enter          ; e o enter passa a ser o que arranca o nucleo
    jmp  pronto                ; com o enter dado, e a mesma coisa que a espera
                              ; do relogio faz: o nucleo arranca

; ---------------------------------------------------------------------------
; le_tecla: uma tecla do driver, o que ela e, e a marca no sitio
;   entrada: nada
;   saida:   AL = RES_NADA | RES_SETA | RES_ENTER
;
;   E o unico sitio do arranque que le teclas, e por isso que quem chama nao tem
;   de saber nada sobre a forma como elas chegam: pergunta o que houve e decide.
;   Sao dois os lacos que a chamam, e cada um decide a sua coisa com a mesma
;   resposta - o .conta, uma vez por passo enquanto o relogio corre, e o
;   espera_enter, sem parar, depois de o relogio ter parado.
;
;   Nao espera nada e nao obriga a nada: pergunta ao driver se ha uma tecla
;   guardada e, se houver, tira-a e diz o que e. Chamar isto sem nenhuma tecla a
;   espera e o mesmo que nao chamar, e por isso que o laco da espera a chama uma
;   vez por passo, sem cerimonia.
;
;   Uma seta e o que mexe na marca, e o enter e o que o arranque atende. Qualquer
;   outra tecla e tirada do buffer e largada: nao ha nada a fazer com ela, e
;   tira-la e o que impede que fique la a tapar a cabeca da fila.
;
;   Quem guarda as teclas e o driver, nao este sector nem a BIOS: quando uma
;   tecla chega, o handler da IRQ1 do driver le o registo de dados do
;   controlador (0x60) e guarda-a num buffer proprio (notas em teclado.asm); o
;   comando CMD_LER e que a vai buscar. Duas coisas daqui resultam:
;     - as interrupcoes tem de estar ligadas, e estao durante a espera, porque
;       e o handler do driver que enche o buffer (e a INT 15h AH=86h precisa do
;       timer da BIOS - ver a nota do passo());
;     - o driver tem de estar carregado e ligado antes da contagem, e esta:
;       carregar_teclado corre no fim do ecra escrito e antes do .conta.
;
;   A chamada ao driver e um "call" de segmento, como as outras, com o ES e o
;   BX a apontarem para a TEC_INFO deste sector e o CX no comando CMD_LER. A
;   resposta vem no CF: CF=1 e "nao ha tecla nenhuma" e e o mesmo que a BIOS
;   respondia que nao; CF=0 e ha tecla, e ela esta na TEC_INFO.
;
;   O scancode vem no TEC_I_TECLA e o prefixo no TEC_I_PREF. O driver ja separou
;   os dois: uma tecla alargada - o prefixo E0 do teclado - deixa o 0xE0 no
;   TEC_I_PREF e o scancode onde ele esta sempre, por isso as setas do teclado
;   normal e as do teclado numerico chegam aqui com o mesmo numero e as
;   comparacoes de baixo sao uma so. E o que a BIOS fazia, so que agora e o
;   driver a faze-lo, e com o scancode sempre no mesmo sitio.
;
;   O enter chega com o scancode 0x1C (o do teclado numerico e o mesmo, com o
;   E0 que o driver ja tirou): e por isso que ha uma comparacao so para ele.
;
;   O driver entra com o seu proprio DS e repoe-o antes de sair, e escreve so na
;   TEC_INFO que lhe e passada. Os registos que aqui interessam - o BX (o
;   relogio) e o DI (a linha da marca) - nao sao tocados por ele. O "push" e o
;   "pop" do ES continuam a ser precisos, porque o ES tem de voltar a ser o do
;   ecra depois de ter sido o da TEC_INFO.
;
;   A resposta e o AL, e nao o CF, porque sao tres respostas e nao duas: quem
;   chama precisa de distinguir o enter da seta. O AL e posto no fim de cada
;   ramo de saida e nunca a meio do caminho - o desenho da marca passa por um
;   "mov ax" que poe o AL a zero, e um "mov al" posto antes das comparacoes dos
;   limites chegava ao fim a dizer a coisa errada.
;
;   Dos registos, os dois lacos precisam do BX (o relogio) e do DI (a linha da
;   marca) depois da chamada: os dois entram e sao devolvidos. O DX sai com o
;   caminho da seta, que e o que o desenho da marca usa, e o resto - AX, CX e
;   SI - e do trabalho das teclas e pode ser dado como lhe apetece.
; ---------------------------------------------------------------------------
le_tecla:
    push bx                  ; o relogio da espera, a salvo do driver
    push di                  ; e a linha da marca
    push ds
    push es
    mov ax, SEG_BASE         ; ES:BX = a TEC_INFO deste sector
    mov es, ax
    mov bx, TEC_INFO - BASE
    mov cx, TEC_CMD_LER
    call TEC_SEG:TEC_INI      ; CF=0: a tecla veio; CF=1: nao ha nenhuma
    jc  .fim
    mov al, es:[bx + TEC_I_TECLA]   ; o scancode, ja sem o prefixo
    mov ah, es:[bx + TEC_I_PREF]    ; o prefixo (0xE0 nas teclas alargadas)
    pop es
    pop ds
    pop di
    pop bx
    cmp al, TECLA_CIMA       ; as duas setas mexem na marca
    je  .cima
    cmp al, TECLA_BAIXO
    je  .baixo
    cmp al, TECLA_ENTER      ; o enter: o scancode e o mesmo com ou sem o E0
    je  .enter
    jmp  .nada               ; outra tecla: e o mesmo que nao haver tecla nenhuma
.cima:
    mov dx, -BYTES_LINHA     ; o caminho e a linha de cima
    jmp .seta
.baixo:
    mov dx, BYTES_LINHA      ; o caminho e a linha de baixo
.seta:
    mov si, di               ; o destino da marca: e a unica coisa que se compara,
    add si, dx               ; e assim ha uma verificacao so para os dois lados
    cmp si, MARCA_TOPO
    jb  .seta_lida           ; acima da primeira linha do menu: nao ha para
    cmp si, MARCA_FIM        ; onde levar a marca
    ja  .seta_lida           ; e o mesmo abaixo da ultima
    mov ax, SEG_VIDEO        ; o ecra (o driver nao promete nada sobre o ES;
    mov es, ax               ; aqui ele volta a ser o do ecra, que e o que
    push di                  ; o desenho da marca usa)
    mov cl, ' '               ; um espaco por cima do '*' apaga a marca sem
    call celula              ; deixar buraco nenhum (o atributo e o mesmo)
    pop di
    add di, dx                ; a linha da seta
    mov cl, '*'
    call celula              ; e a marca aparece la
.seta_lida:
    mov al, RES_SETA         ; RES_SETA mesmo que a marca nao tenha mexido por
    ret                      ; estar no limite: o que parou o relogio foi a mao
                             ; da pessoa e nao a marca, e quem decide isso e o
                             ; laco que recebeu a resposta
.enter:
    mov al, RES_ENTER        ; o enter nao mexe em nada: quem decide o que ele
    ret                      ; arranca e o laco que o recebeu
.fim:
    pop es                  ; nao havia tecla: o que ficou na pilha volta ao
    pop ds                  ; sitio e a resposta e o RES_NADA
    pop di
    pop bx
.nada:
    xor al, al               ; RES_NADA, tanto nao havia tecla como a tecla era
    ret                      ; outra: nenhuma das duas coisas mexe no relogio

; ---------------------------------------------------------------------------
; celula: um caracter, no ecra
;   entrada: DI = o deslocamento da celula (um par, como todas as celulas sao),
;            CL = o caracter, ES = o segmento do buffer de texto (0xB800)
;   saida: nada, a nao ser o CH - que aqui nao e de ninguem
;
;   Uma celula do modo 80x25 sao dois bytes: o caracter e o atributo, que e a
;   cor de fundo e de letra. Escreve-se o word inteiro de uma vez, com a cor no
;   CH e o caracter no CL - e a razao de a rotina sertao curta: e a unica
;   conta do ecra (2 bytes por celula) escrita num sitio so, e nao repetida em
;   cada escreve.
;
;   E a mesma conta que o resto do sector usa nas contas de montagem - o titulo,
;   o menu e a frase escrevem com o "stosw", que faz a mesma coisa a partir do
;   AX. Aqui o caracter vem no CL (e o AL e do trabalho da tecla, nao se mexe) e
;   o atributo e sempre o mesmo (ATRIB), por isso nao ha loop nem conta: e uma
;   celula, escreve-se uma vez.
; ---------------------------------------------------------------------------
celula:
    mov ch, ATRIB         ; a cor de sempre, a mesma do ecra todo
    mov word [es:di], cx ; a celula e o par (caracter, atributo) de uma vez
    ret

; ---------------------------------------------------------------------------
; apaga_relogio: a parte da frase que e do relogio sai do ecra
;   A frase do ecra de arranque sao duas coisas metidas uma na outra: o que se
;   pode fazer ("Mova com as teclas ^ e v e aperte enter") e o que acontece se
;   nao se mexer em nada (", ou espere N segundos"). A segunda deixa de ser
;   verdade no instante em que a pessoa mexe nas teclas - o relogio parou - e
;   por isso que desaparece do ecra em vez de ficar la a prometer um numero que
;   ja nao conta para nada.
;
;   Sao MSG_REL_N celulas a partir da coluna MSG_REL_COL, que e a virgula: o
;   numero esta no meio delas e vai com o resto, sem tratamento em separado.
;   O atributo e o de sempre (o de todo o ecra deste sector), por isso o que
;   fica e um bocado de preto a seguir a frase - e nao um buraco de outra cor,
;   que era o que aconteceria se se apagasse o caracter e o atributo ficasse.
;
;   O DI e guardado e posto de volta porque e a linha da marca (ver a nota do
;   passo): esta rotina corre entre o momento em que a pessoa mexe numa seta e o
;   momento em que as setas passam a mexer na marca sozinhas, e se o DI saisse
;   daqui a apontar para o fim da frase apagada, a le_tecla passaria a
;   calcular o destino da marca a partir dai - fora do menu, sempre - e nenhuma
;   seta mexeria em nada. O que se perdia nao era a marca no ecra: era o sitio
;   onde ela esta, e nenhuma tecla tornava a mostrar aquilo.
; ---------------------------------------------------------------------------
apaga_relogio:
    push di                  ; a linha da marca: o registo que esta espera tem de
    mov ax, SEG_VIDEO        ; ver tal e qual
    mov es, ax
    mov di, (LINHA_MSG * COLS + MSG_REL_COL) * 2
    mov cx, MSG_REL_N
    mov ax, ATRIB << 8 | ' ' ; a celula do ecra vazio: espaco com a cor de
    rep stosw                  ; sempre - e o "stosw" e o mesmo do texto de cima
    pop di
    ret

; ---------------------------------------------------------------------------
; espera_enter: ate que a pessoa aperte enter na opcao que tem o que fazer
;   saida: o byte [escolha] fica a dizer o que o enter arranca (ESC_NUCLEO ou
;          ESC_RECUP). Nem o CF nem o AL dizem nada, e nao sao pedidos.
;
;   E a segunda metade da regra do arranque: o relogio manda enquanto ninguem
;   mexe nas teclas, e depois de mexer manda o enter. Ate aqui o enter era a
;   tecla mais lenta do mundo (ninguem a apertava a tempo do relogio); agora e a
;   que decide - e decide uma de duas coisas, conforme a linha em que a marca
;   esta.
;
;   As teclas nao sao lidas aqui: e a le_tecla que as le, e este laco so decide
;   o que fazer com o que ela respondeu. Por isso e que as setas continuam a mexer
;   na marca depois de o relogio ter parado sem ninguem ter de as tratar duas
;   vezes - e o que faz a frase que ficou no ecra continuar a ser verdadeira,
;   "Mova com as teclas ^ e v e aperte enter". Qualquer outra tecla e o que era
;   durante a contagem: nada.
;
;   Nao se espera com o "hlt": o "hlt" so acorda com uma IRQ e a unica IRQ de que
;   se pode depender aqui e a do timer da BIOS, que nao e negocio nosso. O laco
;   fica a perguntar, que e o mesmo que ficar a espera.
;
;   O enter decide pela linha em que a marca esta, e ha duas linhas com o que
;   fazer: a primeira, "MaisSus Beta", arranca o nucleo; a segunda,
;   "Recuperacao", carrega o recu.mai desta ISO e salta para ele. A terceira,
;   "sair", ainda nao tem o que fazer e o enter e lido sem acontecer nada visivel.
;
;   Porque a escolha ir para memoria e nao num registo: quem a le esta muito
;   depois de quem a escreve. A escolha acontece aqui, antes da caminhada pela
;   ISO; a leitura acontece no fim da caminhada, e a caminhada muda quase todos
;   os registos que um laco de teclado usaria (o AX e o resultado da comparacao
;   de nomes, o CX e o contador de sectores, o SI e o nome). Um registo nao
;   sobrevivia a isso. O byte vive na area de dados deste sector, e o DS so passa
;   a zero depois do "pronto" (ver a nota do bloco da caminhada): por isso o
;   "mov byte [escolha]" daqui e o "cmp byte [escolha]" de la sao o mesmo
;   endereco com DS = BASE e com DS = 0, e sao o mesmo endereco LINEAR - o unico
;   que sobrevive a mudanca de segmento.
;
;   O que nao pode e o enter ficar no buffer da BIOS quando nao e aceite: ai
;   ficava a tapar a cabeca da fila sem ninguem o tirar, e nenhuma tecla depois
;   dele - nem uma seta para a marca mexer de lado - chegava a ser lida. E por
;   isso que a le_tecla tira sempre a tecla que leu, aceite ou nao, e so depois
;   e que se decide o que se faz com ela.
;
;   O relogio nao precisa da mesma regra, e por uma razao que vale a pena deixar
;   escrita: ele so chega a zero com a marca no topo, porque a primeira seta que
;   a pessoa aperta ja o para (ver o .conta). Quem deixa o relogio chegar ao fim
;   nao mexeu na marca, e a marca comeca no topo - ou seja, o arranque
;   automatico e o arranque pelo enter sao sempre a mesma opcao, sem nenhum sitio
;   onde um dos dois ter de chegar ao outro. Por isso o ramo do relogio (o .conta,
;   que salta para o "pronto" com o zero) nao escreve a escolha: o [escolha] ja
;   nasce a ESC_NUCLEO na area de dados, que e a opcao que o relogio arranca.
; ---------------------------------------------------------------------------
espera_enter:
    call le_tecla          ; uma tecla? E o que ela e - e a seta, se foi uma
    cmp al, RES_ENTER      ; seta, ja mexeu na marca
    je  .enter
    jmp espera_enter       ; nada, ou uma seta ja tratada: pergunta outra vez
.enter:
    cmp di, MARCA_TOPO     ; a primeira opcao: "MaisSus Beta", o nucleo
    je  .nucleo
    cmp di, MARCA_REC      ; a segunda opcao: "Recuperacao", o recu.mai
    je  .recuperacao
    jmp espera_enter       ; a terceira, "sair": ainda nao ha nada que fazer
.nucleo:
    mov cl, ESC_NUCLEO
    jmp .guarda
.recuperacao:
    mov cl, ESC_RECUP
;   A escolha e escrita com o DS a zero, e nao com o DS do sector (BASE), porque
;   e com o DS a zero que ela vai ser lida - e o endereco de um "mov byte [mem]"
;   e DS mais o deslocamento, nao o deslocamento. Escrever aqui com o DS do
;   sector punha a escolha em BASE + deslocamento, e a leitura, quatro mil e
;   poucos sectores mais tarde, ia buscar a outro sitio: os dois ficavam a falar de
;   coisas diferentes e o enter arrancava o nucleo sempre, sem dar sinal nenhum.
;
;   O sinal nenhum e o que torna isto um bug tao discreto. A escolha ja nasce a
;   ESC_NUCLEO na area de dados - e ai o endereco linear e o mesmo nos dois
;   moments, porque o byte esta mesmo na posicao que o DS do sector soma - e por
;   isso que o arranque pelo relogio, que nunca escreve a escolha, funcionava e
;   o enter com o nucleo tambem. So a escolha que se afasta do valor inicial
;   (a recuperacao) ficava escrita no sitio errado. Um "mov byte [escolha], 1" e
;   um "cmp byte [escolha], 1" que leem-se iguais e nao sao: e o DS que os
;   separa, e o DS nao se ve no codigo.
;
;   Por isso o DS e trocado aqui e reposto antes do "ret": quem chama e o .parou,
;   que vai direito para o "pronto", e o "pronto" monta o DS a zero de novo. O
;   "xor ax, ax" antes do DS e para o valor vir de um sitio unico - e o AX e
;   reposto tambem, pelo mesmo motivo.
;
;   Nao ha outra forma de escrever: um "escolha" em outro sitio nao serve, porque
;   a leitura e feita com o DS a zero por causa da caminhada (achar_ficheiro e
;   carregar_ficheiro comparam os nomes com o DS a zero), e a area de dados deste
;   sector e o unico sitio que os dois momentos alcancam em sintonia.
.guarda:
    push ds
    push ax
    xor ax, ax
    mov ds, ax            ; o mesmo DS que a leitura vai ter
    mov [escolha], cl
    pop ax
    pop ds
    ret
;   propria BIOS, e mexer nele durante o arranque e mexer no relogio que nos esta
;   a medir. A INT 15h/86 e um servico documentado (AT e posteriores, incluindo a
;   SeaBIOS do QEMU): devolve quando o tempo passou e cabe numa unica instrucao.
;
;   As interrupcoes ficam ligadas durante a espera: a implementacao deste servico
;   pode usar a IRQ do timer, e uma espera com IF=0 seria um alvo movel. E e por
;   isso que a BIOS tambem continua a receber teclas durante a espera (e por isso
;   que a le_tecla, que e chamada a volta do passo, as consegue ler - ver a
;   nota dela).
;
;   A conta e feita em passos e nao em microssegundos porque o total nao cabe em
;   16 bits: 4 segundos sao 4000000, e o que se guarda e so o que falta para o
;   proximo degrau - PASSOS_SEG passos em BL, que cabem num byte.
;
;   O passo() e chamado so pelo laco .conta, de baixo, que enquanto espera nao
;   precisa de nada: por isso e que ele pode dar AX, CX, DX e BP como lhe
;   apetece, e porque e que a celula do numero se escreve com BP e nao com DI -
;   assim nao ha nada para guardar em volta da chamada, e a pilha deste sector -
;   a 0x7BFF, a mesma onde a BIOS vai meter o codigo do servico - fica fora do
;   assunto.
;
;   O DI e a unica excepcao: o passo() nao lhe toca, porque e onde vive a linha
;   da marca do menu e a marca muda de linha a cada tecla durante a espera. E
;   esse o unico registo de que o laco .conta precisa depois da chamada.
;
;   O passo() esta aqui, entre o laco .conta e a etiqueta pronto, e so se chega a
;   ele por "call": o .conta salta-o com o "jbe pronto" quando a contagem acaba.
;   Se o codigo do ecra o atravessasse em queda, o nucleo arrancava com um degrau
;   a menos.
; ---------------------------------------------------------------------------
passo:
    mov cx, PASSO_US >> 16
    mov dx, PASSO_US & 0xFFFF
    mov ah, 0x86
    int 0x15
    dec bl
    jnz .fim
    dec bh                    ; 4 -> 3 -> 2 -> 1 -> 0
    mov bp, (LINHA_MSG * COLS + SEG_COL) * 2
    mov byte [es:bp], bh      ; reescreve o numero na mesma celula: o
    mov byte [es:bp + 1], ATRIB  ; caracter e o atributo de sempre
    mov bl, PASSOS_SEG
.fim:
    ret

; O passo(), a le_tecla e a celula sao de fora: so se chega a eles por
; "call", e o "jbe pronto" de .conta salta os tres de uma vez quando a contagem
; chega a zero. E por isso que esta etiqueta nao tem ponto - logo a seguir ao
; bloco do passo(), um ".pronto" aqui passaria a ser do passo() e nao de mais
; acima.
pronto:

; ---------------------------------------------------------------------------
; A partir daqui comeca a caminhada pela ISO9660, a mesma que o sector 0 faz.
; Este codigo e de proposito uma copia do de inicio_minimo.asm: o sector 0 tem
; 510 bytes e nao ha espaco para as duas coisas, e nao se pode dar ao sector 0 a
; responsabilidade de carregar o nucleo. A duplicacao e o preco de o sector 0
; ter de ser um sector so. Quando este sector grow, a duplicacao deve morrer.
;
; Aqui DS passa a 0: os enderecos do volume sao lineares e a INT 13h le o DAP em
; DS:SI. O texto do ecra ja foi escrito antes desta mudanca, por isso o
; deslocamento relativo a BASE so era preciso na seccao de cima.
; ---------------------------------------------------------------------------
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; unidade de arranque: o DL com que a BIOS arrancou este sector morreu
    ; quando o sector 0 passou o controlo. Nao se pode perguntar a BIOS outra
    ; vez, por isso tenta-se a lista de unidades provaveis por ordem: primeiro o
    ; CD (0xE0), depois o primeiro disco rigido (0x80), depois o floppy A:
    mov byte [unidade], 0

    ; --- o nucleo: /nucleo/<numero do build> ------------------------------
    ; O nome do ficheiro e o proprio numero do build, e a versao do nucleo e
    ; uma constante deste ficheiro: mudar o build e mudar esta string.
    call ficheiro_nucleo
    jc  falha

    ; --- o driver de video: /drivers/video.dr ------------------------------
    call ficheiro_driver
    jc  falha

    ; --- o driver de teclado: /drivers/teclado.dr --------------------------
    ; Ja esta carregado e ligado: carregar_teclado correu antes da contagem,
    ; para as teclas do ecra serem lidas por ele e nao pela BIOS. Nao se volta a
    ; carregar aqui - seria reescrever o codigo do handler com ele ja instalado,
    ; e uma tecla a chegar a meio da carga corria codigo pela metade.

    ; --- o driver de rato: /drivers/mouse.dr -------------------------------
    ;   Carrega-se mas nao se chama aqui: quem o executa e o nucleo, ja com o
    ;   video configurado e um ecra onde a bolinha do rato faz sentido. O
    ;   inicio.mai so o poe na memoria, como faz ao video.dr.
    call ficheiro_mouse
    jc  falha

    ; O driver de teclado ja foi chamado (CMD_INI) por carregar_teclado, antes
    ; da contagem, e a versao da TEC_INFO ja foi confirmada la: aqui so resta
    ; deixar o ES como a caminhada o encontrou, porque cada ficheiro poe o seu.
    xor ax, ax
    mov es, ax

    ; --- a interface: /interface/face.grain ------------------------------
    call ficheiro_interface
    jc  falha

    ; --- a barra inferior: /interface/barinf.grain --------------------------
    ; A barra vai na mesma caminhada que a interface e na mesma pasta da ISO,
    ; mas para outro sitio da memoria: o face.grain salta para ela depois de
    ; pintar o ecra, e nenhum dos dois pode estar a ser executado de cima do
    ; outro.
    call ficheiro_barra
    jc  falha

    ; --- a barra superior: /interface/barsup.grain --------------------------
    ; A barra superior vai pelo mesmo caminho da inferior, com o seu proprio
    ; segmento: o face.grain salta primeiro para barinf.grain (que pinta a base
    ; do ecra) e o barinf.grain salta depois para barsup.grain (que pinta o topo).
    call ficheiro_sup
    jc  falha

    ; --- o menu: /interface/menu.grain --------------------------------------
    ; O menu e a ultima imagem da cadeia: o barsup.grain salta para ele depois de
    ; pintar a barra de cima, e e o menu que desenha o rectangulo cinzento e
    ; devolve o controlo ao face.grain (que fica no ciclo da bolinha).
    call ficheiro_menu
    jc  falha

    ; --- a imagem do logo: /imagens/logo.img --------------------------------
    ; O ficheiro .img que o conversor_de_imagens.py escreveu a partir de
    ; imagens/image.png. Vai para o seu proprio segmento (0x7000:0x0000) porque
    ; o decodificador o vai ler de la, e porque nenhum dos dois pode estar a ser
    ; executado de cima do outro.
    call ficheiro_imagem
    jc  falha

    ; --- o decodificador: /imagens/decod.img --------------------------------
    ; O codigo que o nucleo salta para desenhar a imagem no ecra. Vai para
    ; 0x8000:0x0000, dois segmentos acima da imagem.
    call ficheiro_decodificador
    jc  falha

    ; --- a recuperacao: /inicio/recu.mai -------------------------------------
    ; A imagem da segunda opcao do menu. Vai na cadeia como todos os outros
    ; ficheiros, e para o seu segmento (0x0900:0x0000), e nao e uma excepcao ao
    ; caminho: e o mesmo procurar-a, mete-la no sitio e seguir.
    ;
    ; Fica nesta cadeia, e nao depois da escolha, por uma razao que e a ordem
    ; do arranque e nao uma preferencia: a escolha acontece ANTES da caminhada
    ; (o menu e lido e o enter e apertado enquanto o DS ainda e BASE), e a
    ; caminhada so comeca depois do ecra estar escrito. Nao ha sitio depois da
    ; escolha onde se possa carregar um ficheiro da ISO sem voltar a trocar o DS
    ; e repor o contexto - e repor o contexto aqui, no meio de uma cadeia de
    ; "call ficheiro_*" que ja passou, seria mais codigo e mais sitio para
    ; dar errado do que a propria imagem ocupa (702 bytes).
    ;
    ; O preco e que a recuperacao e carregada mesmo quando ninguem escolheu a
    ; recuperacao - o mesmo preco que o nucleo paga quando se sai, e que a
    ; interface paga no arranque normal. E o mesmo para todos: nesta fase do
    ; projecto carrega-se tudo e salta-se para o que foi escolhido.
    call ficheiro_recuperacao
    jc  falha

; ---------------------------------------------------------------------------
; entregar o controlo: ao nucleo ou a recuperacao
; ---------------------------------------------------------------------------
    ; A escolha do menu, escrita pelo espera_enter (ver a nota dela). E lida aqui
    ; com o DS a zero - e e por isso que a espera_enter tambem escreve com o DS a
    ; zero: e o unico DS em que os dois moments alcancam o mesmo endereco linear
    ; (ver a nota do "escolha" na area de dados).
    cmp byte [escolha], ESC_RECUP
    je  .recuperacao

    ; as interrupcoes ficam ligadas antes da passagem: com IF=0 o "hlt" do
    ; nucleo pararia o CPU para sempre (em modo real so o acorda um NMI)
    sti

    ; o nucleo entra com CS=IP=NUC_SEG:0x0000 (ou seja, linear 0xC000) e uma
    ; pilha limpa
    xor ax, ax
    mov ss, ax
    mov sp, PILHA
    mov ax, NUC_SEG
    mov ds, ax
    mov es, ax
    jmp NUC_SEG:0x0000

    ; --- a recuperacao: /inicio/recu.mai -------------------------------------
.recuperacao:
    ; A entrada e a mesma do nucleo e com o mesmo sentido: o sector salta para a
    ; imagem, o CS e o IP sao a entrada e o DS e o ES passam a ser o segmento da
    ; imagem (e nao este sector, nem o zero em que a caminhada os deixou).
    ; Quem entra e o nucleo de uma imagem e o DS = o seu segmento, porque os
    ; rotulos dela sao deslocamentos dentro da imagem - o ORG 0 do recu.mai.
    ;
    ; A pilha e reposta como no nucleo (mesma pilha, mesmo motivo: o "hlt" da
    ; recuperacao precisa de uma pilha que nao esteja a servir a BIOS, e a
    ; caminhada pela ISO deixou a pilha no sitio - reposta e nao porque se
    ; perchesse suja, mas para que as duas passagens sejam iguais).
    ;
    ; O DS e posto ANTES do ES porque a recuperacao le a sua propria assinatura
    ; logo a entrar (o "cmp dword [ASSIN]" do start) e a assinatura esta no
    ; segmento da imagem. E a mesma razao pela qual o nucleo e ligado para o
    ; segmento dele.
    ;
    ; O "sti" e o mesmo de cima e pelo mesmo motivo: o "hlt" no fim da
    ; recuperacao, com IF=0, parava o CPU para sempre. E o "hlt" e a unica coisa
    ; que a recuperacao faz depois de pintar o ecra.
    sti
    xor ax, ax
    mov ss, ax
    mov sp, PILHA
    mov ax, REC_SEG
    mov ds, ax                  ; a assinatura da imagem e lida daqui em diante
    mov es, ax
    jmp REC_SEG:REC_INI

; ---------------------------------------------------------------------------
; ficheiro_nucleo: procura /nucleo/<build> no volume e carrega-o em NUC_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
; ---------------------------------------------------------------------------
ficheiro_nucleo:
    mov si, DIR_NUCLEO
    mov cx, DIR_NUCLEO_N
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_NUCLEO
    mov cx, FIC_N
    call achar_ficheiro
    jc  .falha
    mov ax, NUC_SEG
    mov [dest_seg], ax
    mov word [max_set], NUC_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_interface: procura /interface/face.grain no volume e carrega-o em memoria
;   saida: CF=1 se nao encontrar ou se a leitura falhar
; ---------------------------------------------------------------------------
ficheiro_interface:
    mov si, DIR_INTERFACE
    mov cx, DIR_I
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_INTERFACE
    mov cx, FIC_I
    call achar_ficheiro
    jc  .falha
    mov ax, 0x2000                ; face.grain fica em 0x2000:0x0000 (linear 0x20000)
    mov [dest_seg], ax
    mov word [max_set], 16        ; espaco de sobra: a interface e de 1 sector
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_barra: procura /interface/barinf.grain no volume e carrega-o em BAR_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
;
;   O nome procurado e o mesmo ficheiro que o Build.sh graftou na ISO; e o
;   face.grain que verifica a assinatura da imagem carregada antes de saltar
;   para ela, por isso aqui basta achar o ficheiro e coloca-lo no sitio.
; ---------------------------------------------------------------------------
ficheiro_barra:
    mov si, DIR_INTERFACE
    mov cx, DIR_I
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_BARRA
    mov cx, FIC_B
    call achar_ficheiro
    jc  .falha
    mov ax, BAR_SEG
    mov [dest_seg], ax
    mov word [max_set], BAR_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_sup: procura /interface/barsup.grain no volume e carrega-o em SUP_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
;
;   E uma copia de ficheiro_barra com outro nome e outro segmento: as duas
;   barras sao pintadas pelo mesmo codigo (o mesmo formato de cabecalho, a mesma
;   assinatura e a mesma altura) e so muda o sitio do ecra que cada uma pinta -
;   a de baixo a base, a de cima o topo. Ficarem em segmentos diferentes e
;   obrigatorio: a corrente salta de uma para a outra (o face.grain salta para a
;   inferior, a inferior para a superior) e uma imagem carregada por cima da
;   outra estragaria a que estivesse a correr.
;
;   O nome procurado e o mesmo ficheiro que o Build.sh graftou na ISO; e cada
;   imagem que verifica a assinatura de si propria antes de pintar, por isso aqui
;   basta achar o ficheiro e coloca-lo no sitio.
; ---------------------------------------------------------------------------
ficheiro_sup:
    mov si, DIR_INTERFACE
    mov cx, DIR_I
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_SUP
    mov cx, FIC_S
    call achar_ficheiro
    jc  .falha
    mov ax, SUP_SEG
    mov [dest_seg], ax
    mov word [max_set], SUP_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_menu: procura /interface/menu.grain no volume e carrega-o em MEN_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
;
;   E uma copia de ficheiro_sup com outro nome e outro segmento: o menu e a
;   ultima imagem da corrente (face -> barra inferior -> barra superior -> menu)
;   e devolve o controlo ao face.grain. Nao pode estar em cima de nenhuma das
;   outras: cada uma e executada de cima do segmento onde esta a correr.
;
;   O nome procurado e o mesmo ficheiro que o Build.sh graftou na ISO; e o
;   menu.grain que verifica a assinatura da propria imagem antes de pintar, por
;   isso aqui basta achar o ficheiro e coloca-lo no sitio.
; ---------------------------------------------------------------------------
ficheiro_menu:
    mov si, DIR_INTERFACE
    mov cx, DIR_I
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_MENU
    mov cx, FIC_MENU_N
    call achar_ficheiro
    jc  .falha
    mov ax, MEN_SEG
    mov [dest_seg], ax
    mov word [max_set], MEN_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_recuperacao: procura /inicio/recu.mai e carrega-o em REC_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
;
;   E uma copia das rotinas de ficheiro da mesma maneira que o menu e uma copia
;   das das barras: o caminho pela ISO e um so e e o mesmo para todos os
;   ficheiros (procurar a pasta, ler o directorio, achar o nome, meter o
;   segmento e o maximo e cair no carregar_ficheiro), por isso cada ficheiro e
;   uma copia com o nome e o segmento trocados. Uma tabela de Rotulos
;   desapareceria as copias, mas exigiria um laco com tres registos de estado
;   vivo ao mesmo tempo, e o codigo a perder de cada ficheiro (o nome, o
;   segmento e o maximo, mais o directorio) e mais do que o laco custa.
;
;   A diferenca real em relacao a todas as outras: esta imagem NAO e executada
;   de dentro da corrente do arranque. A corrente salta dela (face -> barra
;   inferior -> barra superior -> menu) e cada imagem e executada de cima do
;   segmento onde esta a correr; a recuperacao salta daqui, deste sector, e
;   nao de dentro de outra imagem. Por isso o ficheiro e procurado na pasta do
;   inicio (DIR_INICIO, a mesma onde vive este sector) e nao em interface/.
;
;   Tal como as imagens da interface, e a propria imagem que valida a
;   assinatura antes de pintar o ecra (ver recuperacao.asm), por isso aqui
;   basta achar o ficheiro e coloca-lo no sitio.
; ---------------------------------------------------------------------------
ficheiro_recuperacao:
    mov si, DIR_INICIO
    mov cx, DIR_IN
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_REC
    mov cx, FIC_REC_N
    call achar_ficheiro
    jc  .falha
    mov ax, REC_SEG
    mov [dest_seg], ax
    mov word [max_set], REC_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_imagem: procura /imagens/logo.img no volume e carrega-o em IMG_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
;
;   O ficheiro e o .img do conversor_de_imagens.py (o cabecalho 'IMG1', a paleta
;   e os indices de pixel, ver o formato em decodificador_de_imagem.asm). O
;   inicio.mai nao sabe nada do formato: so acha o ficheiro e coloca-o no sitio,
;   porque quem le o cabecalho e mede a imagem e o nucleo (mostrar_logo) e quem
;   a desenha e o decodificador. Se o ficheiro nao for um .img, quem descobre
;   e o nucleo - e ele que cai no texto da versao.
;
;   O ficheiro e grande (um logo de 320x200 em 8 bits sao 32 sectores), por isso
;   o IMG_SET e o mais generoso dos dois. Nao ha espaco para mais: o que vem a
;   seguir em 0x90000 e a memoria do BIOS, que nao se pode ocupar.
; ---------------------------------------------------------------------------
ficheiro_imagem:
    mov si, DIR_IMAGENS
    mov cx, DIR_IM
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_LOGO
    mov cx, FIC_LOGO_N
    call achar_ficheiro
    jc  .falha
    mov ax, IMG_SEG
    mov [dest_seg], ax
    mov word [max_set], IMG_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_decodificador: procura /imagens/decod.img e carrega-o em DEC_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
;
;   E o mesmo caminho de ficheiro_imagem (mesma pasta, mesma caminhada) com
;   outro nome e outro sitio: o .img e o ficheiro que o decodificador le e o
;   decod.img e o codigo que o le. Por isso que fiquem em segmentos diferentes e
;   a um de distancia um do outro - o decodificador vai estar a correr de um
;   enquanto le o outro.
;
;   O decodificador e pequeno (menos de 1 KiB de codigo); o DEC_SET e a margem
;   que o "times" do fim do ficheiro reserva, para o inicio.mai poder carregar
;   sectores inteiros. O nucleo verifica a assinatura antes de saltar (ver
;   decodificador_carregado, em nucleo.asm), por isso aqui basta o carregar.
; ---------------------------------------------------------------------------
ficheiro_decodificador:
    mov si, DIR_IMAGENS
    mov cx, DIR_IM
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_DEC
    mov cx, FIC_DEC_N
    call achar_ficheiro
    jc  .falha
    mov ax, DEC_SEG
    mov [dest_seg], ax
    mov word [max_set], DEC_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_driver: procura /drivers/video.dr no volume e carrega-o em DRV_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
; ---------------------------------------------------------------------------
ficheiro_driver:
    mov si, DIR_MOTOR
    mov cx, DIR_M
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_MOTOR
    mov cx, FIC_M
    call achar_ficheiro
    jc  .falha
    mov ax, DRV_SEG
    mov [dest_seg], ax
    mov word [max_set], DRV_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_teclado: procura /drivers/teclado.dr no volume e carrega-o em TEC_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
;
;   E o video.dr outra vez, com outro nome e outro sitio de destino: os dois
;   drivers vivem na mesma pasta da ISO e chegam pelo mesmo caminho, por isso
;   so mudam as duas linhas do meio - o nome que se procura e o segmento para
;   onde se carrega. O codigo e o mesmo para nao haver duas caminhadas pela ISO
;   que divergem uma da outra quando a ISO mudar.
; ---------------------------------------------------------------------------
ficheiro_teclado:
    mov si, DIR_MOTOR
    mov cx, DIR_M
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_TECLADO
    mov cx, FIC_T
    call achar_ficheiro
    jc  .falha
    mov ax, TEC_SEG
    mov [dest_seg], ax
    mov word [max_set], TEC_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; carregar_teclado: poe o teclado.dr na memoria e chama-o (CMD_INI), cedo
;   entrada: DS = BASE e ES = o ecra (como no ecra de arranque)
;   saida:   CF=0 se o driver esta carregado e respondeu; CF=1 se falhou
;
;   Esta e a carga que a caminhada fazia ao teclado.dr, tirada de la e posta
;   aqui para correr antes da contagem: e a unica altura em que o driver tem de
;   estar ligado antes de a caminhada comecar, porque sao as teclas do ecra de
;   arranque que ele passa a ler.
;
;   O DS e o ES da caminhada (0) sao postos em volta da chamada a
;   ficheiro_teclado, porque e com eles que as rotinas da ISO trabalham: os
;   rotulos deste sector tem um endereco absoluto e so com o DS a zero e que
;   caem no sitio (ver a nota do bloco da caminhada). O DS e o ES de quem
;   chamou sao repostos no fim, e por isso a rotina deixa o ecra como o achou.
;
;   A seguir a carga, o vaivem da TEC_INFO e o mesmo que a caminhada fazia:
;   escrever a assinatura e o 0xFFFF, chamar o driver com o ES:BX e confirmar
;   que a versao mudou. A confirmacao fica aqui, cedo: a caminhada, mais tarde,
;   so encontra o driver ja feito.
; ---------------------------------------------------------------------------
carregar_teclado:
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov byte [unidade], 0            ; a ISO comeca na primeira unidade
    call ficheiro_teclado
    jc  .sai_mal

    ; --- a TEC_INFO e a chamada ao driver ---------------------------------
    mov ax, SEG_BASE                 ; ES:BX = a TEC_INFO deste sector
    mov es, ax
    mov bx, TEC_INFO - BASE
    mov dword es:[bx + TEC_I_ASSIN], TEC_ASSIN
    mov word es:[bx + TEC_I_VERSAO], 0xFFFF  ; "ainda nao ha ninguem aqui"
    mov cx, TEC_CMD_INI
    call TEC_SEG:TEC_INI
    cmp word es:[bx + TEC_I_VERSAO], TEC_VERSAO
    je  .sai_bem

.sai_mal:
    pop es
    pop ds
    stc
    ret
.sai_bem:
    pop es
    pop ds
    clc
    ret

; ---------------------------------------------------------------------------
; ficheiro_mouse: procura /drivers/mouse.dr no volume e carrega-o em MOU_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
;
;   E o teclado outra vez, com outro nome e outro destino: a pasta da ISO e a
;   mesma (drivers/), o codigo e o mesmo, so mudam as duas linhas do meio. A
;   entrada e escolhida pelo nucleo, que e quem executa o driver depois de o
;   video estar configurado.
; ---------------------------------------------------------------------------
ficheiro_mouse:
    mov si, DIR_MOTOR
    mov cx, DIR_M
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_RATO
    mov cx, FIC_R
    call achar_ficheiro
    jc  .falha
    mov ax, MOU_SEG
    mov [dest_seg], ax
    mov word [max_set], MOU_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; abrir_raiz: procura um directorio no directorio raiz do volume
;   entrada: SI = o nome do directorio, CX = o comprimento do nome
;   saida:   BP = o endereco do registo encontrado no BUF | CF=1 se nao existe
;
;   Chama ler_pvd porque o extent do directorio raiz esta dentro do descritor
;   de volume, e o BUF ja foi entretanto reescrito por outras leituras.
;
;   O par SI/CX com o nome e guardado em memoria antes das leituras: tanto
;   ler_pvd como ler mexem em SI e em CX, e procura_reg precisa de os receber
;   intactos. Sem este provisoio o nome procurado era o endereco do DAP com o
;   comprimento 1, e o directorio nunca era encontrado.
; ---------------------------------------------------------------------------
abrir_raiz:
    mov [nome_proc], si
    mov [nome_tam], cx

    call ler_pvd
    jc  .falha

    ; o extent do directorio raiz esta no offset 158 do descritor
    mov cx, 1               ; 1 sector de 512 = 2048 bytes = 1 bloco ISO
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    mov bp, BUF + 158
    call ler
    jc  .falha

    ; agora o directorio raiz esta no BUF: procura-se la dentro o nome
    mov bp, BUF
    mov bx, BLOCO           ; bytes por percorrer ate ao fim do bloco
    mov si, [nome_proc]
    mov cx, [nome_tam]
    jmp procura_reg         ; devolve BP (o registo) e o CF
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ler_directorio: le para o BUF o directorio cujo registo esta em BP
;   saida: CF=1 se a leitura falhar
; ---------------------------------------------------------------------------
ler_directorio:
    mov cx, 1
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    add bp, 2               ; o extent do directorio esta no offset 2 do registo
    call ler
    ret

; ---------------------------------------------------------------------------
; achar_ficheiro: procura um ficheiro no directorio que esta no BUF
;   entrada: SI = o nome, CX = o comprimento do nome
;   saida:   BP = o endereco do registo | CF=1 se nao existe
; ---------------------------------------------------------------------------
achar_ficheiro:
    mov bp, BUF
    mov bx, BLOCO
    jmp procura_reg

; ---------------------------------------------------------------------------
; procura_reg: percorre o directorio que esta no BUF a procura de um registo
;             cujo identificador (offset 32) seja igual a [SI], com [CX] bytes
;   entrada: BP = inicio do bloco, BX = quantos bytes ha para percorrer,
;            SI = o nome procurado, CX = o comprimento do nome
;   saida:   BP = o endereco do registo | CF=1 se nao existe
;
;   O nome procurado e o comprimento sao copiados para duas variaveis porque o
;   laco precisa deles outra vez a cada registo, e a comparacao dos bytes leva
;   o CX a zero.
; ---------------------------------------------------------------------------
procura_reg:
    mov [nome_proc], si
    mov [nome_tam], cx
.loop:
    test bx, bx
    jz  .nao                ; sem mais registros
    cmp byte [bp], 0
    jz  .nao                ; terminador de sector
    mov cl, [nome_tam]
    cmp byte [bp + 32], cl ; o identificador tem o comprimento certo?
    je  .achou
.proximo:
    mov al, [bp]            ; comprimento do registro
    xor ah, ah              ; AX = comprimento (so AL foi escrito)
    add bp, ax
    sub bx, ax
    jmp .loop
.achou:
    push si
    push bx
    mov si, bp
    add si, 33              ; identificador do registro
    mov di, [nome_proc]
    mov cx, [nome_tam]
.compara:
    mov al, [si]
    cmp al, [di]
    jne .desistir
    inc si
    inc di
    loop .compara
    pop bx
    pop si
    clc
    ret
.desistir:
    pop bx
    pop si
    jmp .proximo
.nao:
    stc
    ret

; ---------------------------------------------------------------------------
; carregar_ficheiro: carrega em [dest_seg]:0x0000 o ficheiro do registo em BP
;   entrada: BP = o registo do directorio (offset 10 = tamanho em bytes,
;            offset 2 = extent), [dest_seg] = o segmento de destino,
;            [max_set] = quantos sectores se podem ler
;   saida:   CF=1 se a leitura falhar
; ---------------------------------------------------------------------------
carregar_ficheiro:
    mov bx, [bp + 10]       ; tamanho do ficheiro em bytes (LE)
    add bx, BLOCO - 1       ; arredonda para cima
    shr bx, 11              ; bytes / 2048 = sectores
    cmp bx, [max_set]
    jbe .ok
    mov bx, [max_set]       ; corta ao maximo permitido
.ok:
    test bx, bx             ; o teste tem de ser sobre BX, nao sobre as flags
    jz  falha               ; do cmp de cima: um ficheiro com um numero exacto
                            ; de sectores (BX == max_set) punha ZF=1 e falhava
    mov cx, bx
    xor bx, bx
    mov ax, [dest_seg]
    mov es, ax
    add bp, 2                ; o extent do ficheiro esta no offset 2 do registo
    call ler
    jc  falha
    ret

; ---------------------------------------------------------------------------
; ler_pvd: procura o descritor de volume primario e le-o para o BUF
;   saida: CF=1 se nao aparecer em MAX_DESCR sectores
; ---------------------------------------------------------------------------
ler_pvd:
    mov dword [lba], PVD_LBA
    mov byte [descr_restam], MAX_DESCR
.procurar:
    mov cx, 1               ; 1 sector de 512 = 2048 bytes = 1 bloco ISO
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    lea bp, [lba]           ; 32 bits, pouco endian
    call ler
    jc  .falha
    cmp byte [BUF], PVD_TIPO
    jne .proximo            ; sector sem um descritor de volume: ignora
    cmp dword [BUF + 1], SIG_CD001
    ret                     ; sao iguais, portanto o "cmp" deixou CF=0
.proximo:
    inc dword [lba]
    dec byte [descr_restam]
    jnz .procurar
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ler: le sectores da ISO com a INT 13h extendida (AH=42h)
;   entrada: BP = endereco do LBA de 32 bits | ES:BX = destino
;            CX = n. de sectores
;   saida:   CF=1 se falhou em todas as unidades
; ---------------------------------------------------------------------------
ler:
    mov word [dap_cnt], cx  ; o pacote tem de estar montado antes de tentar
    mov [dap_off], bx
    mov ax, es
    mov [dap_seg], ax
    mov ax, [bp]
    mov [dap_lba], ax
    mov ax, [bp + 2]
    mov [dap_lba + 2], ax
.tentar:
    mov cx, [dap_cnt]
    xor bh, bh
    mov bl, [unidade]
    mov dl, [bx + unidades]
    mov ax, [dap_seg]
    mov es, ax
    mov si, DAP
    mov ax, 0x4200
    int 0x13
    jnc .fim
    inc byte [unidade]
    cmp byte [unidade], N_UNIDADES
    jb .tentar
    stc
.fim:
    ret

; ---------------------------------------------------------------------------
; se a caminhada pela ISO falhar, o ecra fica vermelho e paramos
; (aqui as interrupcoes ainda estao ligadas: o "hlt" precisa delas)
; ---------------------------------------------------------------------------
falha:
    mov ax, SEG_VIDEO
    mov es, ax
    xor di, di
    xor ax, ax
    mov ah, 0x10            ; fundo vermelho
    mov cx, 80 * 25
    rep stosw
falha_parado:
    hlt
    jmp falha_parado

; ---------------------------------------------------------------------------
; area de dados
; ---------------------------------------------------------------------------
unidade:     db 0x00          ; indice da unidade a tentar (ver a tabela)
unidades:    db 0xE0, 0x80, 0x00  ; CD, primeiro HD, floppy A:
lba:         dd 0x00000000
descr_restam: db 0x00

; O que o enter arrancou no menu (ESC_NUCLEO ou ESC_RECUP). Vive na area de
; dados porque e lida muito depois de ser escrita - a escolha acontece no menu,
; antes da caminhada pela ISO, e a caminhada muda quase todos os registos (ver
; a nota da espera_enter, que e o sitio onde a escolha e escrita).
;
; E lida E escrita com o DS a zero, para que o endereco linear seja o mesmo nos
; dois momentos. Com o DS do sector (BASE), um "mov byte [escolha]" apontaria para
; BASE mais o deslocamento e a leitura, feita com o DS a zero, para o
; deslocamento - dois sitios diferentes, e o bug ver a nota da espera_enter.
; Por isso a espera_enter troca o DS antes de escrever.
;
; Nasce a ESC_NUCLEO porque o ramo do relogio - que salta para o "pronto" sem
; passar pela espera_enter - arranca o nucleo e nao escreve nada aqui. E este
; valor inicial, e nao a espera_enter, que e a primeira coisa que a leitura ve, e
; por isso que ele tem de estar no sitio certo: um ESC_RECUP aqui mudaria o
; arranque pelo relogio sem ninguem ter pedido.
escolha:     db ESC_NUCLEO    ; ESC_NUCLEO = 0, ESC_RECUP = 1

; A estrutura que este sector passa ao driver de teclado, e que o driver
; preenche (ver os numeros dos campos nas constantes, TEC_I_*). Vive aqui, e
; nao no meio da caminhada, para o driver escrever nela sem o sector ter de
; guardar o endereco do lado dele.
TEC_INFO:    dd 0x00000000         ; a assinatura; este sector escreve 'TEC1'
             dw 0xFFFF             ; a versao: 0xFFFF = o driver ainda nao falou
             dw 0x0000             ; TI_FLAGS: bit 0 = "ha tecla no buffer"
             db 0x00               ; TI_ESTADO: o estado lido em 0x64 (CMD_INI)
             db 0x00               ; TI_TECLA: o scancode da ultima tecla (CMD_LER)
             db 0x00               ; TI_PREF: o prefixo dela (0 ou 0xE0)
             db 0x00               ; TI_MODS: os modificadores (shift/ctrl/alt)

nome_proc:   dw 0x0000        ; o nome que procura_reg esta a procurar
nome_tam:    dw 0x0000
dest_seg:    dw 0x0000        ; segmento de destino de carregar_ficheiro
max_set:     dw 0x0000        ; sectores maxima de carregar_ficheiro

; ---------------------------------------------------------------------------
; Os nomes que a caminhada procura na ISO, e os seus comprimentos.
;
; Os nomes sao procurados byte a byte no directorio (achar_ficheiro), pelo que
; tem de ser o nome exacto e sem ";1" - e o que o nivel 4 da ISO da (ver NIVEL_ISO
; no Build.sh). O nivel da ISO e parte do contrato e nao uma opcao estetica.
;
; O COMPRIMENTO de cada nome e a parte que convem nao escrever a mao. A
; comparacao e byte a byte sobre o numero dado aqui (o CX que vai para o
; procura_reg), e um numero a mais le o byte seguinte - que e o zero do fim da
; string, ou pior, o byte de dados ao lado - e um numero a menos acaba a
; comparacao antes do fim e aceita um prefixo como se fosse o ficheiro certo.
; Nenhum dos dois erros se ve: o procura_reg simplesmente nao acha, e o
; arranque cai no ecra de falha sem dizer porque.
;
; E o que aconteceu com o nome do nucleo quando o build passou de 0.9.2026 para
; 0.12.2026: o "0.10" tem uma letra a mais do que o "0.9", o comprimento ficou
; um a menos, e a procura do nucleo deixava de bater com o ficheiro que o
; Build.sh acabara de meter na ISO. Por isso todos os comprimentos aqui sao
; contados pelo assembler ($ menos o rotulo menos o zero final) e nao escritos:
; nao ha nenhum numero para manter em sintonia com o nome ao lado.
;
;FIC_<N> e DIR_<N> sao o comprimento do nome; o - 1 e o zero final, que o
; procura_reg nao compara (ele compara so o nome).
; ---------------------------------------------------------------------------
DIR_NUCLEO:  db "nucleo", 0          ; 7 bytes
DIR_NUCLEO_N equ $ - DIR_NUCLEO - 1  ; "nucleo"

; O nome do nucleo e o numero do build, que e o mesmo na ISO e no repositorio
; (Build.sh grava o nucleo com este nome). E por isso que os dois tem de mudar
; juntos: um build novo muda o FIC_NUCLEO aqui e o BUILD la, senao o inicio.mai
; procura um ficheiro que o Build.sh nao poe na ISO.
FIC_NUCLEO:  db "0.12.2026", 0        ; 10 bytes
FIC_N        equ $ - FIC_NUCLEO - 1  ; "0.12.2026"

DIR_MOTOR:   db "drivers", 0          ; 8 bytes
DIR_M        equ $ - DIR_MOTOR - 1    ; "drivers"
FIC_MOTOR:   db "video.dr", 0         ; 9 bytes
FIC_M        equ $ - FIC_MOTOR - 1    ; "video.dr"

FIC_TECLADO: db "teclado.dr", 0       ; 11 bytes
FIC_T        equ $ - FIC_TECLADO - 1  ; "teclado.dr"

FIC_RATO:    db "mouse.dr", 0         ; 9 bytes
FIC_R        equ $ - FIC_RATO - 1     ; "mouse.dr"

DIR_INTERFACE: db "interface", 0       ; 10 bytes
DIR_I        equ $ - DIR_INTERFACE - 1  ; "interface"
FIC_INTERFACE: db "face.grain", 0      ; 11 bytes
FIC_I        equ $ - FIC_INTERFACE - 1  ; "face.grain"

FIC_BARRA:   db "barinf.grain", 0      ; 13 bytes
FIC_B        equ $ - FIC_BARRA - 1    ; "barinf.grain"

FIC_SUP:     db "barsup.grain", 0      ; 13 bytes
FIC_S        equ $ - FIC_SUP - 1       ; "barsup.grain"

FIC_MENU:    db "menu.grain", 0        ; 12 bytes
FIC_MENU_N   equ $ - FIC_MENU - 1      ; "menu.grain"

; ---------------------------------------------------------------------------
; A recuperacao (inicio/recu.mai, ver REC_LIN no inicio deste ficheiro).
;
; Vive na pasta do inicio - e nao em interface/ nem em imagens/ - por ser uma
; imagem que este sector salta, e nao uma imagem que outra imagem salte. A pasta
; e a do sector 0 que o carregou, que e o mesmo ficheiro que este sector.
;
; E o mesmo nome que o Build.sh graftou na ISO (FONTE_REC/NOME_REC), e o
; comprimento e contado pelo assembler como os de cima (ver a nota dos nomes).
; ---------------------------------------------------------------------------
DIR_INICIO:  db "inicio", 0           ; 7 bytes
DIR_IN       equ $ - DIR_INICIO - 1  ; "inicio"
FIC_REC:     db "recu.mai", 0         ; 9 bytes
FIC_REC_N    equ $ - FIC_REC - 1      ; "recu.mai"

; ---------------------------------------------------------------------------
; A pasta da imagem e os dois ficheiros que vivem nela (ver IMG_LIN e DEC_LIN no
; inicio deste ficheiro). A pasta e uma a parte porque nenhum dos dois ficheiros
; e um driver nem parte da interface: o logo.img e um ficheiro de dados (o
; ficheiro que o conversor_de_imagens.py escreveu a partir de image.png) e o
; decod.img e o codigo que o nucleo salta para o desenhar no ecra.
;
; Os tres nomes - a pasta e os dois ficheiros - estao aqui porque sao os
; tres que o inicio.mai vai buscar ao directorio de imagens/. Os comprimentos
; que os codigos vao buscar a outro sitio do ficheiro (DIR_IM, FIC_LOGO_N e
; FIC_DEC_N, ver a nota la em cima) sao calculados aqui, ao lado do "db" a que
; pertencem, porque e so aqui que o assembler sabe o comprimento.
; ---------------------------------------------------------------------------
DIR_IMAGENS: db "imagens", 0          ; 8 bytes
DIR_IM       equ $ - DIR_IMAGENS - 1  ; "imagens"
FIC_LOGO:    db "logo.img", 0         ; 9 bytes
FIC_LOGO_N   equ $ - FIC_LOGO - 1     ; "logo.img"
FIC_DEC:     db "decod.img", 0        ; 10 bytes
FIC_DEC_N    equ $ - FIC_DEC - 1      ; "decod.img"

DAP:
DAP_size:    db 0x10
DAP_res:     db 0x00
dap_cnt:     dw 0x0000
dap_off:     dw 0x0000
dap_seg:     dw 0x0000
dap_lba:     dq 0x0000000000000000

SEG_BUF      equ BUF >> 4

; O titulo da segunda linha (ver LINHA_TIT). Nao e o numero do build: o ecra
; deste estagio diz o que esta a arrancar, e o numero da versao e coisa do
; nucleo, que o escreve no ecra dele (VERSAO, em nucleo.asm).
; Sem acentos de proposito: nao ha codepage nenhuma em todo o projecto, e a
; fonte do BIOS pode ser CP437 ou CP850.
TITULO:      db "Gerenciador de inicializacao"
TITULO_N     equ $ - TITULO

; ---------------------------------------------------------------------------
; As tres opcoes do menu, uma em baixo da outra a partir da quarta linha (ver
; LINHA_MENU), todas com a mesma margem de dois caracteres (MENU_COL). Nao sao
; centradas: um menu vive a esquerda e le-se de cima para baixo.
;
; Sao so as tres. Nao sao centradas: um menu vive a esquerda e le-se de cima
; para baixo, e e por isso que a marca do menu ('*', coluna 0, na primeira das
; tres linhas) diz qual delas e a da vez sem nada no texto: sao as setas que
; mudam a linha da marca, e nao o texto que muda. O que a marca escolhe ainda
; nao e nada - a escolha em si e coisa do ecra do nucleo, que vem a seguir.
; Sem acentos, como o titulo.
MENU_1:      db "MaiSus Beta"
MENU_1_N     equ $ - MENU_1

MENU_2:      db "Recuperacao"
MENU_2_N     equ $ - MENU_2

MENU_3:      db "sair"
MENU_3_N     equ $ - MENU_3

; ---------------------------------------------------------------------------
; A mensagem da penultima linha. Entra de uma vez, inteira, e depois o numero
; dos segundos desce no sitio, de 4 a 0, ate o nucleo arrancar.
;
; A frase esta partida em tres para o numero ficar no meio: o que vem antes
; (MSG_ESP), o numero - uma celula so, reescrita a cada degrau - e o que vem
; depois (MSG_SEG). E o que permite mexer no numero a cada segundo sem tocar no
; resto; reescrever a frase inteira seria trabalho a mais para o mesmo efeito.
;
; A frase e ainda partida em MSG_ESP2 e MSG_ESP3 porque e no fim de MSG_ESP2
; que a frase deixa de falar do que se pode fazer e passa a falar do relogio: se
; a pessoa mexer nas teclas, o apaga_relogio tira a partir da virgula (que e o
; primeiro caracter de MSG_ESP3) e o ecra fica so com "Mova com as teclas ^ e v
; e aperte enter". O que fica e o que se apaga e assim uma coisa boa: se a frase
; nao estivesse partida assim, o que se apaga seria uma celula a mais de conta e
; o que o apaga_relogio levaria junto era o "e aperte enter" - que foi
; exatamente o que aconteceu, porque a conta dizia MSG_ESP2 + 1 e a virgula esta
; 15 caracteres depois de MSG_ESP2. O sitio onde a frase acaba e um rotulo
; (MSG_ESP3) e nao uma conta, que e o que faz este sitio sobreviver a mudancas
; na frase.
;
; As setas sao SETA_CIMA e SETA_BAIXO: os bytes 0x18 e 0x19 da fonte do BIOS, que
; e a fonte do modo texto (CP437) e e a que desenha estas duas setas. Nao se
; escreve a seta como caractere normal porque em ASCII nao existe seta - sao tres
; bytes e aparecia "?".
; ---------------------------------------------------------------------------
MSG_ESP:     db "Mova com as teclas ", SETA_CIMA, " e ", SETA_BAIXO
MSG_ESP2:    db " e aperte enter"                 ; as quatro partes sao uma frase
MSG_ESP3:    db ", ou espere "                    ; so - e e uma so no ecra
MSG_ESP_N    equ $ - MSG_ESP                      ; porque sao escritas coladas,
MSG_SEG:     db " segundos"                       ; sem nada pelo meio
MSG_SEG_N    equ $ - MSG_SEG

; Centrar a frase e a mesma conta do titulo, (COLS - TITULO_N) / 2, com o numero
; dos segundos a contar como um caracter. MSG_COL e a coluna onde a frase
; comeca; SEG_COL e a coluna da celula do numero, que e a que o passo()
; reescreve. Se o texto mudar de comprimento so estas duas contas mudam.
MSG_N        equ MSG_ESP_N + 1 + MSG_SEG_N   ; a frase toda, com o numero
MSG_COL      equ (COLS - MSG_N) / 2          ; celula inicial da frase
SEG_COL      equ MSG_COL + MSG_ESP_N         ; celula do numero dos segundos

; A parte da frase que pertence ao relogio - ", ou espere <N> segundos" - e o
; que o apaga_relogio tira do ecra quando a pessoa mexe nas teclas. Vao da
; virgula (o primeiro caracter de MSG_ESP3) ate ao fim de " segundos", com o
; numero dos segundos pelo meio. Sao 22 celulas - a frase e partida em quatro
; pedacos e o relogio e o ultimo - e a conta e a distancia entre as pontas: a
; celula onde acaba (a ultima de " segundos", que e a celula do numero mais
; MSG_SEG_N) menos a celula onde comeca, mais uma para a contar toda.
; A coluna sai da conta da frase: MSG_ESP3 - MSG_ESP e o comprimento do que vem
; antes da virgula, e MSG_COL e onde a frase comeca.
MSG_REL_INI equ MSG_ESP3                         ; a virgula: o inicio do relogio
MSG_REL_COL equ MSG_COL + MSG_REL_INI - MSG_ESP  ; a coluna dela no ecra
MSG_REL_N   equ SEG_COL + MSG_SEG_N - MSG_REL_COL + 1  ; as celulas todas

; O numero dos segundos e os passos que faltam para o proximo segundo nao ficam
; aqui: vivem em BH e BL. Sao duas coisas que a animacao tem sempre a mao - o
; numero e o que esta no ecra, os passos e o relogio do passo() - e nao dados
; que valha a pena guardar. Meter a contagem aqui em baixo obrigava a repor
; BH/BL em volta da INT 15h, e a pilha deste sector e a 0x7BFF, a mesma onde a
; BIOS vai meter o codigo do servico.

; ---------------------------------------------------------------------------
; Este estagio e carregado em 3 sectores (6 KiB, de 0xA000 a 0xB7FF, ate ao
; comeco do buffer de texto). O "times" faz o nasm falhar se o codigo passar
; dai: sem ele o inicio_minimo.asm carregava este ficheiro a meio e o nucleo
; arrancava de um codigo truncado.
; ---------------------------------------------------------------------------
    times 0x1800 - ($ - $$) db 0x00