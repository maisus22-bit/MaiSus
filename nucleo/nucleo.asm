; ============================================================================
;  Maisus - nucleo.asm
;  Nucleo (kernel) - build 0.12.2026
;
;  Carregado por inicio.mai da ISO (/nucleo/0.12.2026) para SEG_NUC:0x0000.
;  O inicio.mai carrega tambem os dois drivers: o de video (/drivers/video.dr)
;  para SEG_DRV:DRV_INI e o de teclado (/drivers/teclado.dr) para SEG_TEC:TEC_INI
;  (nos dois, 0x0008: depois do cabecalho de 8 bytes).
;  Convencao de entrada: CS=IP=0xC000, DS=ES=0xC000, pilha limpa em PILHA.
;
;  missao: logo a entrar, configurar o driver de teclado e chamar o driver de
;          video para ele ver as informacoes do dispositivo, escolher a maior
;          resolucao que o driver reportou e mandar-lhe aplicar esse modo; a
;          seguir escrever no ecra de video, com os glifos da fonte do nucleo, o
;          numero do build, esperar 4 segundos, limpar o ecra e escrever quatro
;          linhas - o titulo ("MaiSus Beta v0.1 Build 0.12.2026") na primeira e
;          as provas de que os tres drivers correram nas restantes (a do rato
;          so aparece se ele respondeu).
;  saida: nada - o ecra fica com as quatro linhas e o CPU espera
;
;  O nucleo e que escreve no ecra, e nao o driver: o driver so diz como e o
;  dispositivo (que modos ha, qual e o maior) e poe o video nesse modo. A
;  divisao esta escrita nas duas pontas: aqui e em drivers/video.asm.
; ============================================================================

BITS 16

; Endereco LINEAR onde o inicio.mai carrega este ficheiro, e o segmento
; correspondente. Sao dois numeros diferentes: o segmento SEG_BASE cobre
; 0xC000, mas o segmento 0xC000 cobriria 0xC0000 (768 KiB).
;
; Nao ha ORG: em -f bin o org tells nasm somar a origem a todos os rotulos, e
; um rotulo de dados que vale 0xC2B1 nao e o deslocamento 0x02B1 que o DS=0xC00
; espera. Todos os rotulos deste ficheiro sao deslocamentos dentro de SEG_BASE,
; e nao ha necessidade de nenhuma correccao pelo endereco linear.
SEG_BASE   equ 0xC000 >> 4    ; 0xC00 - o segmento deste codigo

; O driver de video: o inicio.mai carrega-o em DRV_LIN e o nucleo chama-o em
; SEG_DRV:DRV_INI. DRV_OFF e o quanto falta de DRV_LIN ate o fim do segmento do
; nucleo, e portanto o deslocamento do driver dentro do DS do nucleo - e o que
; permite ao nucleo ir le a assinatura sem trocar de segmento.
DRV_LIN    equ 0xE000          ; inicio do driver, em DRV_SEG:0x0000
SEG_DRV    equ DRV_LIN >> 4   ; 0xE00 - o segmento do driver
DRV_INI    equ 0x0008         ; o driver comeca com um cabecalho de 8 bytes
DRV_OFF    equ DRV_LIN - (SEG_BASE << 4)   ; 0x2000 - o driver visto de DS

; O driver de teclado segue as mesmas regras - carregado pelo inicio.mai da ISO,
; chamado de SEG_TEC:TEC_INI, com o cabecalho de 8 bytes e o regresso por "retf"
; -, mas ao contrario do video NAO ha TEC_OFF: o driver esta em 0x60000 e a
; distancia ate o segmento do nucleo sao 0x54000 bytes, que ja nao cabem num
; deslocamento de 16 bits. Por isso o nucleo tem de meter o DS no segmento do
; driver para lhe ir ler a assinatura, em vez de a ler com o DS de sempre.
TEC_LIN    equ 0x60000         ; inicio do driver, em SEG_TEC:0x0000
SEG_TEC    equ TEC_LIN >> 4    ; 0x6000 - o segmento do driver
TEC_INI    equ 0x0008          ; a entrada, depois do cabecalho de 8 bytes

; O driver do rato segue as mesmas regras do teclado: carregado pelo inicio.mai
; da ISO, chamado de SEG_MOU:MOU_INI, com o cabecalho de 8 bytes e regresso por
; "retf". O 0x90000 fica acima do teclado (0x60000), do logo (0x70000) e do
; decodificador (0x80000), que sao os sitios ja ocupados - o mapa no Build.sh
; mostra-o lado a lado com os outros e acusa se uma imagem crescer para cima da
; seguinte.
MOU_LIN    equ 0x90000         ; inicio do driver de rato, em SEG_MOU:0x0000
SEG_MOU    equ MOU_LIN >> 4    ; 0x9000 - o segmento do driver
MOU_INI    equ 0x0008          ; a entrada, depois do cabecalho de 8 bytes

SEG_VIDEO  equ 0xB800          ; inicio do buffer de texto
ATRIB      equ 0x0E            ; amarelo claro sobre preto
VERMELHO   equ 0x0010          ; atributo 0x10 no AX: fundo vermelho
COLUNAS    equ 80
LINHAS     equ 25
TOTAL_CELULAS equ COLUNAS * LINHAS

; ---------------------------------------------------------------------------
; A pilha nao pode estar em 0xB800-0xC000: essa e a janela do buffer de texto e
; empilhar la vai para o ecra. Fica em 0xB7FF, mesmo sitio onde o inicio.mai a
; deixou - que ja morreu e nao volta a correr.
; ---------------------------------------------------------------------------
PILHA      equ 0xB7FF

; ---------------------------------------------------------------------------
; A espera de 4 segundos e pedida a BIOS com a INT 15h AH=86h, que espera
; CX:DX microssegundos. Nao se programou o PIT para isso de proposito:
;
;   - o PIT do contador 0 ja esta ao servico da IRQ do timer da propria BIOS,
;     mexer nele durante o arranque e mexer no relogio que esta a medir-nos;
;   - a INT 15h/86 e um servico documentado (AT e posteriores, incluindo a
;     SeaBIOS do QEMU), devolve quando passou, e cabe numa unica instrucao.
;
; So se cairia em esperar a mao se a BIOS nao tivesse esse servico: nesse caso
; entrava um laco sobre a INT 1Ah AH=00h, que devolve os tiques desde a meia-noite.
;
; As interrupcoes ficam ligadas durante a espera: a implementacao deste servico
; pode usar a IRQ do timer, e uma espera com IF=0 seria um alvo movel.
;
; Esta espera e a do nucleo, depois de escrever o numero do build: o inicio.asm
; ja fez a dele antes de entregar o controlo, e a mensagem dele fica 4 segundos
; no ecra, esta fica outros 4 - e sao esses 4 segundos que dao a ler o numero
; do build antes de o ecra ser limpo para a prova. A segunda espera, no fim, e a
; que deixa a prova no ecra antes de a interface pintar o mesmo ecra por cima.
; ---------------------------------------------------------------------------
ESPERA_US  equ 4000000         ; 4 segundos em microssegundos

; O driver assina o primeiro DWORD do seu codigo com 'VID1'. E assim que o
; nucleo sabe que o inicio.mai conseguiu carregar o driver sem ter de saber o
; tamanho do que carregou.
ASSIN_DRIVER equ 0x31444956     ; 'V','I','D','1' por ordem de bytes

CMD_DETETAR equ 0              ; o driver olha para o dispositivo de video
CMD_APLICAR equ 1              ; o driver poe o video no modo escolhido

; O teclado assina o primeiro DWORD do seu codigo com 'TEC1', pelo mesmo motivo
; que o video: e assim que o nucleo sabe que o inicio.mai carregou um driver de
; teclado sem ter de saber o tamanho do que carregou.
ASSIN_TECLADO equ 0x31434554    ; 'T','E','C','1' por ordem de bytes
CMD_TEC_INI   equ 0             ; inicializar: instalar o handler e ligar o teclado
VERSAO_TECLADO equ 2            ; a versao do contrato que o teclado.dr fala

; ---------------------------------------------------------------------------
; O decodificador de imagem (imagens/decod.img) segue o mesmo padrao dos dois
; drivers: carregado pelo inicio.mai da ISO, chamado de SEG_DEC:DEC_INI, com um
; cabecalho de 8 bytes e regresso por "retf".
;
; Ao Contrary do video.dr e do teclado.dr, este codigo nao fala com um
; dispositivo: fala com o ecra. O nucleo e que sabe o ecra (leu-o do VIDEO_INFO
; do video.dr) e e que encolhe a imagem quando ela nao cabe - o decodificador
; so desenha o rectangulo que lhe derem, no sitio que lhe derem. A razao e uma
; so: o ecra e uma coisa do video.dr, e quem encolhe a imagem precisa de saber
; as medidas do ecra e do pixel (o bytes por pixel decide o quanto se pode
; encolher sem distorcer), o que ja esta tudo no VIDEO_INFO.
;
; O ficheiro .img (imagens/logo.img) e lido pelo decodificador, nao pelo
; nucleo, e vive em IMG_SEG - dois segmentos abaixo do codigo (ver DEC_LIN).
; O nucleo le-lhe o cabecalho para saber as medidas, e e o que encolhe.
; ---------------------------------------------------------------------------
DEC_LIN     equ 0x80000         ; inicio do decodificador, em SEG_DEC:0x0000
SEG_DEC     equ DEC_LIN >> 4    ; 0x8000 - o segmento do codigo
DEC_INI     equ 0x0008          ; a entrada, depois do cabecalho de 8 bytes

IMG_LIN     equ 0x70000         ; o ficheiro .img, em IMG_SEG:0x0000
IMG_SEG     equ IMG_LIN >> 4    ; 0x7000 - o segmento do ficheiro de dados

; O decodificador assina o primeiro DWORD do seu codigo com 'IMG1' - o mesmo
; 'IMG1' com que o ficheiro .img comeca, porque e a mesma familia de coisa (a
; assinatura e a do codigo que le o ficheiro, nao a do ficheiro: quem verifica
; o codigo e o nucleo, e quem verifica o ficheiro e o proprio codigo). E por
; isso que o nucleo sabe se o inicio.mai conseguiu carregar o codigo sem ter de
; saber o tamanho do que carregou.
ASSIN_DECOD equ 0x31474D49      ; 'I','M','G','1' por ordem de bytes
CMD_DESENHAR equ 0              ; desenhar a imagem no rectangulo do contrato
CMD_REPOR    equ 1              ; repor a paleta que o ecra tinha antes do desenho

; O formato do ficheiro .img (16 bytes de cabecalho, ver o conversor e o
; decodificador: o cabecalho em imagens/conversor_de_imagens.py e o leitor em
; imagens/decodificador_de_imagem.asm). O nucleo le estes campos para saber as
; medidas da imagem antes de a desenhar.
IMG_ASSIN   equ 0x00           ; dword 'IMG1'
IMG_VERSAO  equ 0x04           ; versao do formato (1)
IMG_LARG    equ 0x06           ; largura da imagem, em pixels
IMG_ALT     equ 0x08           ; altura da imagem, em pixels
IMG_CORES   equ 0x0A           ; quantas cores a paleta tem
IMG_PIX     equ 0x0C           ; onde os pixels comecam no ficheiro
IMG_PAL     equ 0x10           ; a paleta: 256 entradas de { db r, db g, db b, db 0 }
TAM_IMG_CAB equ 16             ; o tamanho do cabecalho

; ---------------------------------------------------------------------------
; IMG_INFO: a estrutura com que o nucleo e o decodificador falam. A definicao
; completa esta em imagens/decodificador_de_imagem.asm, com os comentarios: aqui
; ficam os deslocamentos, que sao o contrato e nao podem mudar de um lado so.
;
;   II_ASSIN    dd 'IMG1'    o nucleo escreve, o codigo confirma
;   II_VERSAO   dw          versao do contrato (0xFFFF antes da chamada)
;   II_COMANDO  dw          o comando (CMD_DESENHAR ou CMD_REPOR)
;   II_ERRO     dw          o codigo do erro, se o comando falhou
;   II_CMDS     dw          quantos comandos o codigo ja recebeu
;   II_LARG     dw          largura do ecra
;   II_ALT      dw          altura do ecra
;   II_BPP      dw          bits por pixel (8, 16 ou 32)
;   II_BYTESLIN dw          bytes por linha do ecra
;   II_FBSEG    dw          segmento do framebuffer
;   II_FBOFF    dw          offset do framebuffer no segmento
;   II_X        dw          coluna do canto superior esquerdo
;   II_Y        dw          linha do canto superior esquerdo
;   II_DLARG    dw          largura a desenhar (ja encolhida)
;   II_DALT     dw          altura a desenhar (ja encolhida)
;   II_IMG_SEG  dw          segmento onde esta o ficheiro .img
;   II_PIXELS   dd          quantos pixels foram escritos
;   II_PARC     dw          reservado
;
; O nucleo escreve a IMG_INFO antes de chamar o codigo, e o codigo escreve o
; II_ERRO e o II_PIXELS. E a mesma troca do VIDEO_INFO, pelo mesmo motivo: os
; dois lados ficam com enderecos normais em vez de um deles precisar de saber
; onde esta o segmento do outro.
;
; A estrutura vive num sitio fixo, como o VIDEO_INFO, porque e o codigo que a
; vai ler e a ler pelo segmento que o nucleo lhe da (IMG_INFO em DS, com o
; decodificador a correr noutro segmento). O sitio e logo a seguir ao VIDEO_INFO
; (0x0E00 + CONTRATO_N), e o nucleo carrega sectores inteiros: por isso fica
; arredondada para cima ao sector seguinte, para nao calhar a meio do codigo
; que o inicio.mai leu e nao escreveste.
; ---------------------------------------------------------------------------
II_ASSIN    equ 0x00
II_VERSAO   equ 0x04
II_COMANDO  equ 0x06
II_ERRO     equ 0x08
II_CMDS     equ 0x0A
II_LARG     equ 0x0C
II_ALT      equ 0x0E
II_BPP      equ 0x10
II_BYTESLIN equ 0x12
II_FBSEG    equ 0x14
II_FBOFF    equ 0x16
II_X        equ 0x18
II_Y        equ 0x1A
II_DLARG    equ 0x1C
II_DALT     equ 0x1E
II_IMG_SEG  equ 0x20
II_PIXELS   equ 0x22
II_PARC     equ 0x26
IMG_INFO_N  equ 0x28           ; 40 bytes - o que o decodificador copia

; O sitio fixo da IMG_INFO. Fica depois do VIDEO_INFO (que acaba em 0x0E00 +
; CONTRATO_N = 0x10A8) e antes do fim do sector em que o inicio.mai leu o
; nucleo: o "times" do fim do ficheiro faz o nasm falhar se as tres coisas nao
; couberem em 0x1800 (3 sectores), que e o que o NUC_SET do inicio.mai le.
IMG_INFO   equ 0x1100

; O sitio fixo da MOUSE_INFO, pela mesma razao da IMG_INFO: e o handler do
; driver que a le e escreve, e o handler so a alcanca por uma constante. Fica
; logo depois da IMG_INFO (que acaba em 0x1100 + 0x28 = 0x1128), arredondada
; para cima ao endereco redondo seguinte (0x1200), dentro dos 0x1800 que o
; NUC_SET do inicio.mai le. E a ultima estrutura fixa: o que vier depois dela
; so cabe se o "times" do fim do ficheiro continuar a passar.
MOUSE_INFO equ 0x1200

; ---------------------------------------------------------------------------
; VIDEO_INFO: a estrutura com que o nucleo e o driver falam. A definicao
; completa esta em drivers/video.asm, com os comentarios: aqui ficam os
; deslocamentos, que sao o contrato e nao podem mudar de um lado so.
;
;   VI_ASSIN    db 'VID1'    o nucleo escreve, o driver confirma
;   VI_VERSAO   dw          versao do contrato
;   VI_VBE      dw          1 se ha VESA BIOS Extension
;   VI_VBE_VER  dw          versao do VBE
;   VI_CAPS     dw          capacidades do VBE
;   VI_MEM      dd          memoria de video, em bytes
;   VI_NMODOS   dw          quantos modos o driver registou
;   VI_MODO     dw          o modo escolhido (o nucleo escreve)
;   VI_TIPO     dw          0 = classico (AX=modo) | 1 = VESA (AX=4F02h)
;   VI_LARG     dw          largura do modo aplicado
;   VI_ALT      dw          altura do modo aplicado
;   VI_BPP      dw          bits por pixel
;   VI_BYTESLIN dw          bytes por linha
;   VI_FBSEG    dw          segmento do framebuffer
;   VI_FBOFF    dw          offset do framebuffer no segmento
;   VI_COR      dd          valor de pixel do texto
;   VI_FLAGS    dw          bit 0: o driver usou a tabela de reserva
;
; A tabela de modos segue VI_TAB: MAX_MODOS entradas de TAM_ENTRADA bytes,
; cada uma { dw modo; dw tipo; dw largura; dw altura; dw bits por pixel }.
; O nucleo escreve primeiro a assinatura, para o driver saber que a estrutura
; esta la; o resto o driver preenche.
; ---------------------------------------------------------------------------
VI_ASSIN    equ 0x00
VI_VERSAO   equ 0x04
VI_VBE      equ 0x06
VI_NMODOS   equ 0x10
VI_MODO     equ 0x12
VI_TIPO     equ 0x14
VI_LARG     equ 0x16
VI_ALT      equ 0x18
VI_BPP      equ 0x1A
VI_BYTESLIN equ 0x1C
VI_FBSEG    equ 0x1E
VI_FBOFF    equ 0x20
VI_COR      equ 0x22
VI_TAB      equ 0x28
ENT_MODO    equ 0
ENT_TIPO    equ 2
ENT_LARG    equ 4
ENT_ALT     equ 6
ENT_BPP     equ 8

TAM_ENTRADA equ 10
MAX_MODOS   equ 64
CONTRATO_N  equ VI_TAB + MAX_MODOS * TAM_ENTRADA

; A estrutura vive num sitio fixo (0x0E00, depois do codigo e da fonte) e nao
; "depois do codigo", porque o driver escreve nela com o segmento do nucleo: um
; endereco fixo deixa os dois lados com enderecos normais. O codigo, os dados e
; a fonte tem de caber antes do VIDEO_INFO - o "times" no fim do ficheiro faz o
; nasm falhar se deixarem de caber.
CONTRATO   equ 0x0E00

; ---------------------------------------------------------------------------
; TEC_INFO: a estrutura com que o nucleo e o driver de teclado falam. A
; definicao completa esta em drivers/teclado.asm, com os comentarios: aqui ficam
; os deslocamentos, que sao o contrato e nao podem mudar de um lado so.
;
;   TI_ASSIN    db 'TEC1'    o nucleo escreve, o driver confirma
;   TI_VERSAO   dw          versao do contrato (0xFFFF antes da chamada)
;   TI_FLAGS    dw          bit 0: ha tecla no buffer (posto pelo CMD_LER)
;   TI_ESTADO   db          o registo de estado do controlador (porta 0x64)
;   TI_TECLA    db          o scancode da ultima tecla lida (sem o prefixo)
;   TI_PREF     db          o prefixo da ultima tecla: 0 normal, 0xE0 alargada
;   TI_MODS     db          os modificadores: bit0 shift, bit1 ctrl, bit2 alt
;
; O nucleo escreve a assinatura e o 0xFFFF antes de chamar, e o driver escreve o
; numero da versao e confirma a assinatura. A versao e a prova de que o driver
; entrou: postas pelo nucleo, so o driver as pode trocar por um numero.
;
; Esta estrutura, ao contrario do VIDEO_INFO, nao precisa de um sitio fixo: e
; pequena, cabe com o resto dos dados (ver TEC_INFO no fim do ficheiro), e o
; driver escreve nela pelo segmento e pelo deslocamento que o nucleo lhe da -
; como faz com o VIDEO_INFO.
;
; O nucleo so usa a assinatura e a versao (chama o CMD_TEC_INI e confirma que o
; driver la esta); os campos das teclas ficam para quem quiser ler uma tecla
; pelo CMD_LER.
; ---------------------------------------------------------------------------
TI_ASSIN   equ 0x00
TI_VERSAO  equ 0x04
TI_FLAGS   equ 0x06
TI_ESTADO  equ 0x08
TI_TECLA   equ 0x09
TI_PREF    equ 0x0A
TI_MODS    equ 0x0B
TEC_INFO_N equ 12

; ---------------------------------------------------------------------------
; MOUSE_INFO: a estrutura com que o nucleo e o driver de rato falam. A
; definicao completa esta em drivers/mouse.asm, com os comentarios: aqui ficam
; os deslocamentos, que sao o contrato e nao podem mudar de um lado so.
;
;   MI_ASSIN    db 'MOU1'    o nucleo escreve, o driver confirma
;   MI_VERSAO   dw          versao do contrato (0xFFFF antes da chamada)
;   MI_X        dw          coluna do ponteiro (o handler do driver mantem)
;   MI_Y        dw          linha do ponteiro (o handler do driver mantem)
;   MI_BOTAO    db          botoes do rato (bit0 esquerdo, bit1 direito, bit2 meio)
;   MI_PARC     db          reservado
;
; Ao contrario da TEC_INFO, a MOUSE_INFO vive num sitio fixo (MOUSE_INFO, logo
; depois da IMG_INFO): e o handler do driver, que corre fora de qualquer
; chamada - a partir de uma interrupcao -, que a vai ler e escrever, e para
; isso so pode alcanca-la por uma constante. O nucleo escreve a assinatura, a
; versao a 0xFFFF e a posicao no centro do ecra; o driver confirma a
; assinatura, escreve a versao e fica com o endereco guardado para o handler.
;
; A assinatura e o 'MOU1' do drivers/mouse.asm, pelo mesmo motivo do 'TEC1': e
; o que separa "o driver entrou" de "o driver nao esta la".
; ---------------------------------------------------------------------------
MI_ASSIN   equ 0x00
MI_VERSAO  equ 0x04
MI_X       equ 0x06
MI_Y       equ 0x08
MI_BOTAO   equ 0x0A
MI_PARC    equ 0x0B
MOUSE_INFO_N equ 12

ASSIN_MOUSE   equ 0x31554F4D   ; 'M','O','U','1' por ordem de bytes
CMD_MOU_INI   equ 0             ; o unico comando: inicializar
VERSAO_MOUSE  equ 1            ; a versao do contrato que o mouse.dr fala

LARG_REF   equ 320             ; largura de referencia para a escala dos glifos

; ---------------------------------------------------------------------------
; A fonte
;   O nucleo traz a sua, de 8x16, com os caracteres de 0x20 a 0x7F. Nao pede
;   nenhuma a BIOS: a INT 10h AX=1130h responde com um endereco que so tem
;   sentido enquanto o video esta em modo texto - e o driver muda-o logo a
;   seguir -, e nem todas as implementacoes enchem la um glifo a serio. Um
;   nucleo que escreve num ecra de video nao pode depender de um ponteiro que
;   deixa de valer no passo seguinte, traz a fonte com ele.
;
;   Cada glifo sao 16 bytes, uma linha de 8 pixels por byte, com o pixel da
;   esquerda no bit mais alto. Um caracter fora da gama da fonte desenha-se em
;   branco (GLIFO_VAZIO).
; ---------------------------------------------------------------------------
GLIFO_W     equ 8              ; pixels de largura de um glifo
GLIFO_H     equ 16             ; pixels de altura de um glifo
GLIFO_N     equ GLIFO_H        ; bytes por glifo: 8 pixels = 1 byte por linha
FONTE_C1    equ 0x20           ; primeiro caracter da fonte: o espaco
N_FONTE     equ 0x60           ; caracteres de 0x20 a 0x7F

; ---------------------------------------------------------------------------
start:
    cld

    ; pilha propria
    xor ax, ax
    mov ss, ax
    mov sp, PILHA

    ; --- modo video: 80x25 texto, cor sobre preto -------------------------
    ; O driver e chamado logo a seguir e muda o video para um modo de video. O
    ; modo texto so e preciso ate la, e para os ecras de erro: sao texto que
    ; ainda esta em modo texto e vao para o buffer de texto (ver erro).
    mov ax, 0x0003
    int 0x10

    ; --- limpa o ecra inteiro ---------------------------------------------
    ; AX=0600 limpa o ecra todo. Com BH=01 a BIOS usa BL como atributo de
    ; preenchimento; com BH=00 o preenchimento fica com o atributo ja presente
    ; no ecra, que nao apaga nada. Por isso BH=01 e BL=00.
    mov ax, 0x0600
    mov bx, 0x0100
    int 0x10

    ; --- esconde o cursor --------------------------------------------------
    ; O nucleo escreve os glifos no framebuffer, um a um, e nao usa o cursor da
    ; BIOS: o cursor nao escreve nada disso e, depois da mudanca de modo, nem
    ; sequer tem um ecra de texto onde desenhar-se. Esconde-se pondo-o fora do
    ; ecra (a linha 32 de um ecra de 25 e o truque para a BIOS o desligar).
    ; Sem isto o cursor pisca no canto durante os ecras de erro, em cima da
    ; primeira letra da mensagem.
    mov cx, 0x2020
    mov ah, 0x01
    int 0x10

    ; --- o driver de teclado, antes do de video ----------------------------
    ; A ordem e a que e por uma razao pratica: enquanto o video esta em modo
    ; texto, um driver que falhe mostra o ecra vermelho, e depois da mudanca de
    ; modo o ecra de erro ja nao existe (o texto de erro vai para o buffer de
    ; texto, que ninguem esta a ver). O teclado nao depende do video, por isso
    ; nao ha razao nenhuma para esperar por ele - a prova de que correu sai
    ; depois, com a do video, quando ja ha ecra de video para a escrever.
    ;
    ; Sao duas perguntas, porque sao duas falhas diferentes: o inicio.mai
    ; chegou a carregar um teclado.dr, e o driver chegou a responder. A segunda
    ; so se pode fazer depois da primeira - um driver que nao esta la nao tem
    ; a quem chamar - e e a que o driver do teclado, nas suas notas, diz que
    ; e a fatal: um teclado que cala o bico nao e o que faz o arranque parar.
    call teclado_carregado
    jc  sem_teclado
    call configurar_teclado
    jc  teclado_mudo

    ; --- o inicio.mai carregou o decodificador e o ficheiro .img? ----------
    ; As duas perguntas sao feitas aqui, antes do video, e nao sao fatais: um
    ; arranque sem logo e um arranque a que falta uma imagem no ecra, nao um
    ; arranque partido. E por isso que a falha so se ve depois - quando ja ha
    ; ecra de video, o nucleo escreve o numero do build no lugar do logo e
    ; segue (ver mostrar_logo). O que nao pode ser e o contrario: um logo
    ; desenhado a meio e um ecra com lixo em cima.
    ;
    ; O decodificador e o codigo que chama; o ficheiro .img e o que ele vai
    ; ler. Sao duas perguntas porque sao dois ficheiros diferentes, e porque o
    ; nucleo le o cabecalho de um deles (as medidas da imagem, que sao o que
    ; lhe da para decidir o tamanho) - se esse nao for um .img, nao ha o que
    ; desenhar, por mais bem que o codigo esteja carregado.
    ; A flag e a resposta: CF=1 e "o inicio.mai nao conseguiu carregar o
    ; codigo" (falha), CF=0 e "esta la". O "mov" nao mexe nas flags, por isso
    ; o CF que o "call" deixou ainda vale no "jc" - o mesmo vaivem do
    ; teclado_carregado.
    call decodificador_carregado
    mov byte [dec_codigo], 0
    jc  .sem_dec                 ; sem codigo: o mostrar_logo escreve o build
    mov byte [dec_codigo], 1     ; com codigo: o mostrar_logo desenha
.sem_dec:

    ; --- o inicio.mai conseguiu carregar o driver? -------------------------
    cmp dword [DRV_OFF], ASSIN_DRIVER
    jne  sem_driver

    ; --- o driver ve o dispositivo de video -------------------------------
    ; O driver entra em SEG_DRV:DRV_INI com ES:BX a apontar para o VIDEO_INFO e
    ; CX = CMD_DETETAR. Ele escreve o relatorio na estrutura e devolve CF=0.
    mov dword [CONTRATO + VI_ASSIN], ASSIN_DRIVER
    mov cx, CMD_DETETAR
    call chamar_driver
    jc  driver_falhou

    ; --- o nucleo escolhe a maior resolucao que o driver viu ---------------
    call escolher_modo
    jc  sem_modos

    ; --- e manda-lhe aplicar esse modo ------------------------------------
    mov cx, CMD_APLICAR
    call chamar_driver
    jc  driver_falhou

    ; --- de preto a limpo, e a escala dos glifos --------------------------
    ; A partir daqui ja ha framebuffer: o driver devolveu VI_FBSEG, VI_FBOFF,
    ; VI_BYTESLIN e a geometria, e o texto pode sair com a fonte do nucleo.
    call limpar_video
    call calcular_escala

    ; --- o driver do rato: ligar o rato e o handler da IRQ12 ---------------
    ;   Ao contrario do teclado, o rato e ligado depois do video por uma razao
    ;   pratica: o driver nao desenha nada e o handler dele limita o ponteiro
    ;   as medidas do VIDEO_INFO, que so estao completas depois de o modo ser
    ;   aplicado. Ligar o rato antes deixaria o handler a limitar contra as
    ;   medidas do modo de texto, que ja nao existem.
    ;
    ;   As duas falhas nao sao fatais, ao contrario das do teclado e do video:
    ;   sem rato o arranque continua, apenas sem a bolinha a mexer-se. O que se
    ;   faz nos dois casos e centrar a posicao inicial, para a interface ter
    ;   uma MOUSE_INFO coerente (a bolinha aparece parada no centro). A
    ;   assinatura e a versao a 0xFFFF dizem ao driver quem manda a estrutura,
    ;   como no teclado.
    ;
    ;   Ao contrario das outras provas, a falha do rato tem de ficar registada
    ;   e nao so ignorada: a linha do rato no ecra la para a frente so se
    ;   escreve com a flag rato_ok a 1, que e posta aqui em cima - um arranque
    ;   sem rato continua, mas o ecra nao vai dizer que o mouse.dr configurou.
    call mouse_carregado
    jc  .sem_rato               ; sem ficheiro nenhum: a flag fica a zero
    call configurar_mouse
    jc  .sem_rato               ; o driver nao respondeu: a flag fica a zero
    mov byte [rato_ok], 1       ; so aqui o mouse.dr respondeu mesmo
.sem_rato:
    call centrar_mouse

    ; --- o logo, desenhado pelo decodificador de imagem --------------------
    ; Onde antes estava o numero do build, desenhado com a fonte, esta agora a
    ; imagem do logo (imagens/logo.img). O nucleo e que decide o tamanho dela
    ; (ver mostrar_logo): se ela for maior do que o ecra encolhe, se for menor
    ; fica como esta - uma imagem pequena nao e razao para a esticar -, e o que
    ; sobra do ecra fica preto dos dois lados.
    ;
    ; A chamada e uma coisa a serio (com um contrato dos dois lados) e nao um
    ; "or com o ficheiro": e o mesmo que o nucleo faz com os dois drivers, e a
    ; razao e a mesma - quem sabe o ecra, quem o encolhe e quem decide o que
    ; acontece quando a imagem nao presta e o nucleo escreve o numero do build.
    call mostrar_logo

    ; --- espera 4 segundos -------------------------------------------------
    ;   INT 15h AH=86h  CX:DX = microssegundos a esperar (CX = metade alta)
    mov cx, ESPERA_US >> 16
    mov dx, ESPERA_US & 0xFFFF
    mov ah, 0x86
    int 0x15

    ; --- a paleta do ecra outra vez ----------------------------------------
    ; O decodificador poe a paleta da imagem no registo de cores do ecra - e
    ; o que faz o logo ter as suas cores em vez das de um ecra de texto. O
    ; registo e do ecra e nao do codigo, por isso a paleta fica la quando o
    ; desenho acaba, e quem a repoe e o nucleo: depois da espera e antes de
    ; limpar o ecra, porque o titulo que vem a seguir e do nucleo e usa os
    ; indices que o video.dr deixou (o 0 preto, o 7 o cinza do texto) - com a
    ; paleta da imagem no sitio o titulo saia todo com as cores de um pixel
    ; qualquer do logo.
    call repor_paleta_imagem

    ; --- limpa o ecra de todo, e escreve o titulo e as provas ---------------
    ; O ecra fica com quatro linhas: o titulo na 0 e as tres provas nas linhas
    ; 1, 2 e 3, encostadas umas as outras. Nao e o titulo sozinho como antes: com o
    ; numero do build a desaparecer na limpeza, o ecra deixava de dizer que
    ; versao era esta, e o titulo e o que repoe essa informacao - por cima das
    ; provas de que os drivers correram, que e o que interessa dizer sobre
    ; o arranque. As tres provas sao da mesma forma e pelo mesmo motivo: cada
    ; driver e chamado a serio pelo nucleo, e o que escreve e o que o driver
    ; deixou na estrutura.
    ;
    ; A do rato e a unica condicionada: ela aparece so se rato_ok estiver a 1,
    ; porque falhar o rato nao para o arranque (ver "o driver do rato" acima) e
    ; uma linha a dizer "configurado com sucesso" num rato que nem respondeu era
    ; uma mentira no ecra. Se o rato falhou, a linha 3 fica simplesmente por
    ; escrever - o titulo e as outras duas provas continuam la.
    call limpar_video
    mov si, VERSAO_LONG
    mov cx, VERSAO_LONG_N
    xor dx, dx                ; linha 0: MaiSus Beta v0.1 Build 0.12.2026
    call linha
    mov si, MENSAGEM
    mov cx, TXT_N
    mov dx, 1                 ; linha 1: video.dr configurado com sucesso
    call linha
    mov si, MENSAGEM_TECLADO
    mov cx, TXT_TECLADO_N
    mov dx, 2                 ; linha 2: teclado.dr configurado com sucesso
    call linha
    cmp byte [rato_ok], 0     ; a prova do rato so sai se ele respondeu
    je  .sem_rato_no_ecra
    mov si, MENSAGEM_RATO
    mov cx, TXT_RATO_N
    mov dx, 3                 ; linha 3: mouse.dr configurado com sucesso
    call linha
.sem_rato_no_ecra:

    ; --- espera 4 segundos apos mostrar as provas --------------------------
    mov cx, ESPERA_US >> 16
    mov dx, ESPERA_US & 0xFFFF
    mov ah, 0x86
    int 0x15

    ; --- passa o controle para face.grain (interface.asm compilado) ------------
    ; face.grain foi carregado por inicio.asm em 0x20000 (segmento 0x2000)
    push 0x2000
    push 0x0000
    retf

; ---------------------------------------------------------------------------
; sem_driver / sem_modos / driver_falhou / sem_teclado / teclado_mudo: ecra
; vermelho e a explicacao. O nucleo nao se mexe num ecra de video: e texto que
; ainda esta em modo texto, por isso escreve-se no buffer de texto como sempre.
; E por isso que o teclado e configurado antes do video: um driver de teclado
; que falhe depois da mudanca de modo deixaria o nucleo parado sem ninguem ver
; porque.
; ---------------------------------------------------------------------------
sem_driver:
    mov si, MSG_SEM_DRIVER
    jmp erro
sem_teclado:
    mov si, MSG_SEM_TECLADO
    jmp erro
teclado_mudo:
    mov si, MSG_TEC_MUDO
    jmp erro
sem_modos:
    mov si, MSG_SEM_MODOS
    jmp erro
driver_falhou:
    mov si, MSG_DRIVER_FALHOU
erro:
    mov ax, SEG_VIDEO
    mov es, ax
    xor di, di
    mov cx, TOTAL_CELULAS
    mov ax, VERMELHO                  ; caracter 0 sobre fundo vermelho
    rep stosw
    mov bl, ATRIB
    call escreve_txt
parado:
    hlt
    jmp parado

; ---------------------------------------------------------------------------
; teclado_carregado: o inicio.mai carregou mesmo um teclado.dr?
;   entrada: nada
;   saida:   CF=0 se a assinatura do cabecalho do driver esta la
;
;   A assinatura le-se com o DS no segmento do driver. O video le a dele em
;   DRV_OFF, um deslocamento dentro do segmento do nucleo, e nao precisa de
;   trocar nada: o driver esta a 0x2000 bytes de distancia. O teclado esta a
;   0x54000, que ja nao cabe num deslocamento de 16 bits: um "mov al, [x]" com
;   x de 0x54000 fica com os 16 bytes de baixo (0x4000) e lia o sitio errado -
;   o nasm avisa, mas um aviso nao impede o codigo de ser gerado. Por isso aqui
;   o DS muda, e volta a mudar antes de sair.
; ---------------------------------------------------------------------------
teclado_carregado:
    mov ax, SEG_TEC
    mov ds, ax
    cmp dword [0], ASSIN_TECLADO  ; 'T','E','C','1' no inicio do driver
    mov ax, SEG_BASE               ; o DS ja e do nucleo de volta: sao dois
    mov ds, ax                     ; "mov" e nao mexem nas flags, por isso o
    jc  .mal                       ; CF do "cmp" ainda aqui diz o que disse
    clc
    ret
.mal:
    stc
    ret

; ---------------------------------------------------------------------------
; configurar_teclado: chama o driver de teclado e confirma que ele entrou
;   entrada: nada
;   saida:   CF=0 se o driver entrou
;
;   A convencao e a mesma que o inicio.mai usa e a mesma que o nucleo usa com o
;   video: o driver entra em SEG_TEC:TEC_INI com o TEC_INFO do nucleo em ES:BX
;   e o comando em CX, e sai por "retf". O driver tem estado proprio (o buffer
;   das teclas e o handler da IRQ1) e por isso poe o seu DS e repoe-o antes de
;   sair, como o driver do rato; nao ha aqui o vaivem de DS que o chamar_driver
;   faz, porque e o proprio driver que o faz.
;
;   A versao que o nucleo deixa a 0xFFFF antes da chamada tem de ter vindo do
;   driver: e o que separa "o driver nao entrou" de "o driver entrou e o
;   teclado cala o bico", que sao coisas diferentes. No primeiro caso o
;   arranque para; no segundo, o arranque continua e o que nao funciona e o
;   teclado - mas como o nucleo ainda nao le teclas, para e assim mesmo.
;
;   Nao se desliga a IRQ do teclado (o "cli") em torno da chamada: o driver
;   desliga-a ele proprio enquanto instala o handler da IRQ1 e fala com o
;   controlador, e volta a liga-la antes de sair (ver drivers/teclado.asm). A
;   chamada entra com as interrupcoes ligadas, como as outras.
; ---------------------------------------------------------------------------
configurar_teclado:
    mov dword [TEC_INFO + TI_ASSIN], ASSIN_TECLADO   ; o driver so escreve
    mov word [TEC_INFO + TI_VERSAO], 0xFFFF          ; depois disto, se confirmar
    mov ax, SEG_BASE
    mov es, ax                        ; ES:BX = o TEC_INFO
    mov bx, TEC_INFO
    mov cx, CMD_TEC_INI
    call SEG_TEC:TEC_INI

    cmp word [TEC_INFO + TI_VERSAO], VERSAO_TECLADO  ; o numero so pode ter
    jne .mal                                          ; vindo do driver
    clc
    ret
.mal:
    stc
    ret

; ---------------------------------------------------------------------------
; mouse_carregado: o inicio.mai carregou mesmo o mouse.dr?
;   entrada: nada
;   saida:   CF=0 se a assinatura do cabecalho do driver esta la
;
;   E o teclado_carregado outra vez, com outro ficheiro e outra assinatura: o
;   'MOU1' nos primeiros bytes do mouse.dr e a prova de que o inicio.mai o
;   carregou. O 0x90000 tambem nao cabe num deslocamento de 16 bits (a distancia
;   ate o segmento do nucleo sao 0x84000 bytes), por isso o DS vai ao segmento
;   do driver para a leitura e volta logo a seguir - o mesmo vaivem de dois
;   "mov", com o "cmp" pelo meio a nao mexer nas flags.
; ---------------------------------------------------------------------------
mouse_carregado:
    mov ax, SEG_MOU
    mov ds, ax
    cmp dword [0], ASSIN_MOUSE    ; 'M','O','U','1' no inicio do driver
    mov ax, SEG_BASE              ; o DS ja e do nucleo de volta
    mov ds, ax
    jc  .mal
    clc
    ret
.mal:
    stc
    ret

; ---------------------------------------------------------------------------
; configurar_mouse: chama o driver do rato e confirma que ele entrou
;   entrada: nada
;   saida:   CF=0 se o driver entrou
;
;   A convencao e a mesma do teclado: o driver entra em SEG_MOU:MOU_INI com a
;   MOUSE_INFO do nucleo em ES:BX e o comando em CX, e sai por "retf". O DS
;   que o driver deixa como esta e reposto por ele proprio (ver drivers/mouse.asm):
;   ao contrario do teclado, o driver do rato tem estado proprio e tem de o
;   por num segmento, mas devolve o DS de quem o chamou antes do "retf".
;
;   A versao que o nucleo deixa a 0xFFFF antes da chamada tem de ter vindo do
;   driver: e ela que prova que o driver entrou. A posicao inicial (o centro do
;   ecra) e posta depois, por centrar_mouse, porque so faz sentido com o
;   VIDEO_INFO ja preenchido.
; ---------------------------------------------------------------------------
configurar_mouse:
    mov dword [MOUSE_INFO + MI_ASSIN], ASSIN_MOUSE   ; o driver so escreve
    mov word [MOUSE_INFO + MI_VERSAO], 0xFFFF        ; depois disto, se confirmar
    mov ax, SEG_BASE
    mov es, ax                        ; ES:BX = a MOUSE_INFO
    mov bx, MOUSE_INFO
    mov cx, CMD_MOU_INI
    call SEG_MOU:MOU_INI

    cmp word [MOUSE_INFO + MI_VERSAO], VERSAO_MOUSE  ; o numero so pode ter
    jne .mal                                          ; vindo do driver
    clc
    ret
.mal:
    stc
    ret

; ---------------------------------------------------------------------------
; centrar_mouse: poe o ponteiro no centro do ecra (a posicao de arranque)
;   entrada: nada (o VIDEO_INFO ja preenchido)
;   saida:   nada
;
;   Chama-se com ou sem driver: sem driver a posicao fica no centro e a
;   bolinha fica parada (o handler nunca a muda). E a unica escrita da posicao
;   pelo nucleo - a partir daqui quem manda no ponteiro e o handler do rato.
; ---------------------------------------------------------------------------
centrar_mouse:
    mov ax, [CONTRATO + VI_LARG]
    shr ax, 1
    mov [MOUSE_INFO + MI_X], ax
    mov ax, [CONTRATO + VI_ALT]
    shr ax, 1
    mov [MOUSE_INFO + MI_Y], ax
    mov byte [MOUSE_INFO + MI_BOTAO], 0
    ret

; ---------------------------------------------------------------------------
; decodificador_carregado: o inicio.mai carregou mesmo o decod.img?
;   entrada: nada
;   saida:   CF=0 se a assinatura do cabecalho do codigo esta la
;
;   E o teclado_carregado outra vez, com outro ficheiro e outra assinatura: o
;   'IMG1' nos primeiros bytes do decod.img e a prova de que o inicio.mai o
;   carregou, sem o nucleo ter de saber o tamanho do que carregou.
;
;   O DS muda para o segmento do codigo para a leitura, como no teclado: o
;   decod.img esta em 0x80000 e a distancia ate o segmento do nucleo sao
;   0x14000 bytes, que ja nao cabem num deslocamento de 16 bits (0x4000 seria
;   lido em vez de 0x14000, e o nasm avisa mas nao impede). O "cmp" nao mexe nas
;   flags, por isso o CF que o "cmp" deixou ainda vale quando o DS ja voltou -
;   e o mesmo vaivem de dois "mov" do teclado_carregado.
;
;   A diferenca para o teclado: este nao e fatal. Se nao houver codigo, o
;   nucleo escreve o numero do build no lugar do logo e o arranque continua
;   (ver mostrar_logo).
; ---------------------------------------------------------------------------
decodificador_carregado:
    mov ax, SEG_DEC
    mov ds, ax
    cmp dword [0], ASSIN_DECOD   ; 'I','M','G','1' no inicio do codigo
    mov ax, SEG_BASE             ; o DS ja e o do nucleo de volta
    mov ds, ax
    jc  .mal
    clc
    ret
.mal:
    stc
    ret

; ---------------------------------------------------------------------------
; mostrar_logo: desenha a imagem do logo no ecra, encolhendo-a se nao couber
;   entrada: nada
;   saida:   nada (falha nao e fatal: escreve o numero do build no lugar)
;
;   -------------------------------------------------------------------------
;   O QUE FAZ, E POR QUE ORDEM
;
;   Sao tres perguntas, e a ordem delas e a ordem em que fazem sentido:
;
;     1. ha codigo para desenhar? (a assinatura do decod.img)
;     2. ha imagem para desenhar? (o cabecalho do logo.img: a assinatura 'IMG1'
;        e a versao do formato, e as medidas - que sem elas nao ha o que
;        encolher)
;     3. o ecra presta? (um modo de video com 0 de largura, ou com um
;        numero de bits por pixel que o codigo nao sabe escrever)
;
;   A 3 e a ultima de proposito: e a que se descobre o ecra (o VIDEO_INFO, que o
;   video.dr preencheu), e o ecra e que existe antes das outras duas: sem ecra
;   nao ha nem codigo nem imagem que valham. E o II_ERRO que o codigo devolve
;   diz sempre a primeira coisa que nao prestava, nao a ultima que se chegou a
;   ver (ver desenhar, no decodificador).
;
;   -------------------------------------------------------------------------
;   O ENCOLHIMENTO, E POR QUE E O NUCLEO QUE O FAZ
;
;   O nucleo e que sabe o ecra (leu VI_LARG, VI_ALT, VI_BPP e VI_BYTESLIN do
;   VIDEO_INFO) e e que le as medidas da imagem (do cabecalho do .img). O
;   decodificador so sabe o rectangulo que lhe derem: e o mesmo que o video.dr,
;   que recebe do nucleo o modo a aplicar em vez de o escolher.
;
;   A razao e a menor das duas (pela largura e pela altura) e nunca maior do que
;   1: uma imagem menor do que o ecra fica do tamanho que tem, porque esticar
;   um logo de 248x200 num ecra de 320x200 da uma imagem grande e pior, e nao e
;   o que se quer. O que sobra do ecra fica preto dos dois lados e de cima e de
;   baixo - o ecra ja foi limpo para preto (limpar_video, antes desta chamada),
;   por isso as margens sao de graca: nao ha nada para pintar de preto.
;
;   A razao e a menor das duas porque e ela que mantem a proporcao: encolher so
;   um lado e esticar o outro, e o rectangulo tem de ter a mesma forma que a
;   imagem.
;
;   O canto e o que sobra dividido por dois, em numero inteiro: sobra de um
;   pixel vai para a margem de baixo e da direita (arredondar para baixo em
;   ambos os lados e o que mantem a imagem centrada a um pixel de precisao, e
;   num ecra de largura impar o pixel a mais e no lado certo porque o canto
;   tambem e inteiro).
;
;   -------------------------------------------------------------------------
;   AS CONTAS, E POR QUE SAO DE 32 BITS
;
;   O encolhimento e uma divisao e nao uma fracao: a imagem e 248x200 e o ecra
;   e 320x200 (a razao e 1,0), mas com um ecra de 640x480 e a mesma imagem a
;   razao seria 0,54 - e uma fracao nao cabe em 16 bits. Por isso o nucleo faz
;   o encolhimento com o produto de 32 bits e uma divisao, a mesma coisa que o
;   codigo faz quando escolhe a coluna e a linha da origem de cada pixel (ver
;   desenhar_ecra, no decodificador).
;
;   A razao, em vez de ser escrita como fracao, entra pelo outro lado da divisao:
;
;     DLARG = i_larg * ecra_larg / i_alt
;     DALT  = i_alt  * ecra_alt  / i_larg
;
;   O primeiro e a largura da imagem multiplicada pela do ecra a dividir pela
;   altura da imagem - que e o mesmo que i_larg * (ecra_larg / i_alt), a razao
;   pela largura. O segundo e o mesmo pelo outro lado. E o mesmo que o codigo faz
;   com cada pixel: a coluna de origem e cx * i_larg / dlarg, e a linha de
;   origem e y * i_alt / dalt.
;
;   Os dois produtos sao de 32 bits porque sao o produto de dois words (248 * 640
;   da 158.720, que ja passou dos 64 Ki): so nos 16 bits de baixo o rectangulo
;   ficava pequeno demais. E o "div" divide DX:AX por CX - o DX e a parte de
;   cima do dividendo, e por isso que o produto vai para a memoria antes de ser
;   dividido (o DX do "mul" e o divisor logo a seguir nao podem ser o mesmo
;   registo).
;
;
;   -------------------------------------------------------------------------
;   O FALHAR
;
;   Nao e fatal e nao escreve no ecra de erro: o ecra ja e um ecra de video e
;   nao ha texto onde escrever, e a imagem e uma coisa de que se pode fazer
;   bem sem. O que se escreve e o numero do build (VERSAO), que e o que estava
;   no ecra antes de a imagem existir, com os glifos do nucleo - o mesmo
;   desenho de sempre (a mesma chamada linha, a mesma fonte). E por isso que a
;   rotina termina com o numero do build de qualquer maneira: quando o logo
;   entra, o numero do build so fica no titulo de baixo, com a versao toda.
;
;   E o que a prova de que correu fica no II_PIXELS: quantos pixels o codigo
;   escreveu. Um zero com CF=0 seria um rectangulo de 0x0, que o codigo
;   recusa, por isso II_PIXELS a zero e a prova de que a imagem nao foi
;   desenhada - mesmo sem o CF, que a chamada de segmento perde.
; ---------------------------------------------------------------------------
mostrar_logo:
    ; --- 1. ha codigo? ---------------------------------------------------
    cmp byte [dec_codigo], 0
    je  .sem_logo

    ; --- 2. o .img e mesmo um .img, e que medidas tem? --------------------
    ; A leitura e com o DS no segmento do ficheiro (0x70000 - dois segmentos
    ; abaixo do codigo, e a distancia ate o nucleo tambem nao cabe em 16 bits,
    ; pelo mesmo motivo que no teclado e no decodificador).
    ;
    ; E o nucleo que le este cabecalho, e nao o codigo: sao as medidas que o
    ; nucleo precisa para calcular o encolhimento (o codigo recebe o
    ; rectangulo ja calculado e nao precisa de as saber).
    ;
    ; O DS volta ao segmento do nucleo ANTES de gravar as medidas, e ate antes
    ; de qualquer salto para .sem_logo. Duas razoes, e as duasImportam:
    ;
    ;   - um "mov [img_larg], ax" com o DS ainda no ficheiro escreveria as
    ;     medidas em cima da paleta do logo.img (o "img_larg" e um deslocamento
    ;     dentro do segmento do nucleo, e quem decide o segmento de um "[...]" e
    ;     o DS, nao o nome do campo). O nucleo ficava com as medidas a zero e o
    ;     logo.img ficava com a paleta estragada - e nenhum dos dois se queixava.
    ;   - o .sem_logo escreve o numero do build com o "linha", que escreve no
    ;     ecra com o DS do nucleo. Um salto para la com o DS no ficheiro ia
    ;     pintar os glifos em cima do logo.img em vez do ecra.
    ;
    ; Por isso o DS e reposto em todos os caminhos (ate no da falha), e as duas
    ; medidas vao para o AX e o BX - sao registos que nao servem para o
    ; "mov ds", por isso podem ser levados para o sitio antes de o trocar.
    mov ax, IMG_SEG
    mov ds, ax
    cmp dword [IMG_ASSIN], ASSIN_DECOD   ; o 'IMG1' do ficheiro
    jne  .cabecalho_mau
    cmp word [IMG_VERSAO], 1            ; a versao do formato que o codigo sabe
    jne  .cabecalho_mau
    mov ax, [IMG_LARG]                  ; a largura da imagem
    mov bx, [IMG_ALT]                   ; a altura da imagem
    mov cx, SEG_BASE                    ; o DS ja e o do nucleo
    mov ds, cx
    jmp .cabecalho_bo
.cabecalho_mau:
    mov cx, SEG_BASE                    ; o DS tem de voltar, mesmo a falhar
    mov ds, cx
    jmp .sem_logo
.cabecalho_bo:
    mov [img_larg], ax                  ; a largura da imagem, no sitio
    mov [img_alt], bx                   ; a altura da imagem, no sitio

    ; --- a imagem tem medidas que prestam? --------------------------------
    ; Zero em qualquer dimensao e um ficheiro que nao tem imagem nenhuma; e
    ; nem o codigo nem o nucleo podem fazer nada com isso.
    cmp word [img_larg], 0
    je  .sem_logo
    cmp word [img_alt], 0
    je  .sem_logo

    ; --- 3. o ecra presta? -----------------------------------------------
    ; Sem ecra nao ha onde desenhar. Um ecra de largura ou altura zero e um
    ; driver que nao preencheu o VIDEO_INFO (o que nao devia acontecer depois de
    ; CMD_APLICAR ter corrido bem, mas umecra e o que e).
    cmp word [CONTRATO + VI_LARG], 0
    je  .sem_logo
    cmp word [CONTRATO + VI_ALT], 0
    je  .sem_logo

    ; O codigo sabe escrever em 8, 16 e 32 bits por pixel (ver escrever_pixel
    ; e o laco de colunas, no decodificador). Outro numero de bits - 1, 4, 24
    ; - e um modo que este codigo nao sabe escrever, e esticar um pixel a uma
    ; palavra sem a outra metade escrita e a maneira de encher o ecra de lixo.
    ; E o nucleo que recusa e nao o codigo: e o nucleo que sabe que o codigo
    ; nao sabe.
    mov ax, [CONTRATO + VI_BPP]
    cmp ax, 8
    je  .bpp_presta
    cmp ax, 16
    je  .bpp_presta
    cmp ax, 32
    je  .bpp_presta
    jmp .sem_logo
.bpp_presta:

    ; --- o canto superior esquerdo do ecra (para o rectangulo) -------------
    ; Copia a geometria toda do VIDEO_INFO para a IMG_INFO, campo a campo. Sao
    ; os "mov" um a um porque o VIDEO_INFO e a IMG_INFO nao sao a mesma
    ; estrutura com um deslocamento diferente: o VIDEO_INFO tem a tabela de
    ; modos no meio (VI_TAB) e a IMG_INFO nao, e por isso os campos que vem
    ; depois da tabela estao a distancias diferentes nos dois lados. Um "rep
    ; movsw" a partir da tabela errada punha o rectangulo em sitio nenhum.
    mov ax, [CONTRATO + VI_LARG]
    mov [IMG_INFO + II_LARG], ax
    mov ax, [CONTRATO + VI_ALT]
    mov [IMG_INFO + II_ALT], ax
    mov ax, [CONTRATO + VI_BPP]
    mov [IMG_INFO + II_BPP], ax
    mov ax, [CONTRATO + VI_BYTESLIN]
    mov [IMG_INFO + II_BYTESLIN], ax
    mov ax, [CONTRATO + VI_FBSEG]
    mov [IMG_INFO + II_FBSEG], ax
    mov ax, [CONTRATO + VI_FBOFF]
    mov [IMG_INFO + II_FBOFF], ax

    ; --- o encolhimento ---------------------------------------------------
    ; As duas contas do comentario de cima, uma para cada lado:
    ;
    ;     dlarg = i_larg * ecra_larg / i_alt
    ;     dalt  = i_alt  * ecra_alt  / i_larg
    ;
    ; Cada uma e o produto de 32 bits de dois words seguido de uma divisao de
    ; 32 bits. O produto vai para a memoria antes de ser dividido porque o "div"
    ; divide DX:AX por CX e o DX e a parte de cima do dividendo - o DX do "mul"
    ; e o CX do "div" nao podem ser o mesmo registo, e ir a memoria e o que
    ; resolve isso sem um segundo sitio de 32 bits.
    ;
    ; Sao as mesmas contas que o codigo faz com cada pixel (a coluna de origem
    ; e cx * i_larg / dlarg), por isso que o rectangulo e o codigo dao a mesma
    ; imagem: o codigo nao encolhe nada, so repete o pixel certo da imagem no
    ; pixel certo do rectangulo.
    ;
    ; DLARG: a largura da imagem pela largura do ecra, a dividir pela altura
    ; da imagem.
    mov ax, [img_larg]
    mul word [CONTRATO + VI_LARG]     ; DX:AX = i_larg * ecra_larg
    mov [prod], ax
    mov [prod + 2], dx
    mov cx, [img_alt]                 ; o divisor: a altura da imagem
    xor dx, dx                        ; o DX do "mul" e do dividendo agora nao
    mov ax, [prod]                    ; e o mesmo: e o produto inteiro
    div cx                            ; AX = dlarg
    mov [rect_larg], ax
    ; DALT: a altura da imagem pela altura do ecra, a dividir pela largura da
    ; imagem.
    mov ax, [img_alt]
    mul word [CONTRATO + VI_ALT]      ; DX:AX = i_alt * ecra_alt
    mov [prod], ax
    mov [prod + 2], dx
    mov cx, [img_larg]                ; o divisor: a largura da imagem
    xor dx, dx
    mov ax, [prod]
    div cx                            ; AX = dalt
    mov [rect_alt], ax

    ; --- o rectangulo e o menor dos dois ----------------------------------
    ; E o que mantem a proporcao: se so um dos lados mandasse, o outro ficaria
    ; esticado (ou espremido) e a imagem saia de outra forma. Com os dois lados
    ; calculados pelo mesmo factor, o menor e o que cabe e o outro sobra - que
    ; e a margem preta.
    ;
    ; Sao comparacoes de valores sem sinal ("jb", nao "jbe"): um produto de 32
    ; bits pode passar dos 32767 e a comparacao com sinal daria um rectangulo
    ; "menor" que o outro quando e maior - que e o ecra inteiro virado do avesso.
    ; As medidas sao positivas e cabem em 16 bits (o codigo recusa o resto), por
    ; isso o bit de sinal nunca esta posto e o "jb" sem sinal e o certo.
    mov ax, [rect_larg]
    mov bx, [rect_alt]
    cmp ax, bx
    jbe .largura_boa
    mov [rect_larg], bx               ; a altura mandava: a largura encolhe
    jmp .sem_esticar
.largura_boa:
    cmp bx, ax
    jbe .sem_esticar
    mov [rect_alt], ax                ; a largura mandava: a altura encolhe

.sem_esticar:
    ; --- nunca maior do que a imagem --------------------------------------
    ; A razao nao passa de 1: um logo de 248x200 num ecra de 320x200 fica de
    ; 248x200, com 36 pixels de margem preta de cada lado, em vez de ir
    ; esticado para 320. Esticar nao e encolher, e um logo esticado e pior do
    ; que um logo pequeno - e o ecra nao fica preto dos dois lados, que e o
    ; que se quer ver.
    ;
    ; O "cmp" com o minimo e o duplo: e o que faz o rectangulo ficar com a
    ; forma da imagem mesmo quando o ecra e muito maior do que ela (a razao e
    ; maior que 1 nos dois lados e o minimo e a imagem duas vezes).
    mov ax, [img_larg]
    cmp ax, [rect_larg]
    jbe .largura_ja_presta
    mov [rect_larg], ax               ; a imagem e menor: fica do tamanho dela
.largura_ja_presta:
    mov ax, [img_alt]
    cmp ax, [rect_alt]
    jbe .altura_ja_presta
    mov [rect_alt], ax                ; a imagem e menor: fica do tamanho dela
.altura_ja_presta:

    ; --- um rectangulo de 0 pixels e um rectangulo de 1 ---------------------
    ; O produto e a divisao dao zero quando a imagem e muito maior do que o
    ; ecra (uma imagem de 1000 de lado num ecra de 4 daria 4 * 4 / 1000 = 0), e
    ; o codigo recusa um rectangulo de 0 - o que faria o nucleo cair no numero
    ; do build. Um pixel e melhor do que nada: e a imagem encolhida ate ao
    ; limite, e e o que o codigo aceita.
    cmp word [rect_larg], 0
    jne .largura_ok
    mov word [rect_larg], 1
.largura_ok:
    cmp word [rect_alt], 0
    jne .altura_ok
    mov word [rect_alt], 1
.altura_ok:
    ; --- o canto: o que sobra dividido por dois ----------------------------
    ; (ecra_larg - rect_larg) / 2 na horizontal, (ecra_alt - rect_alt) / 2 na
    ; vertical. Sao as margens pretas, e sao a unica coisa que o encolhimento
    ; produz para alem do rectangulo: o ecra ja foi limpo para preto (o
    ; limpar_video, antes desta chamada), por isso nao ha nada a pintar - as
    ; margens sao o que sobrou do ecra, que ja era preto.
    ;
    ; A subtracao e a do ecra MENOS o rectangulo: o rectangulo cabe (o codigo
    ; recusa se nao couber, e o nucleo so encolhe) e por isso a subtracao nao
    ; vai a negativo - o "sub" com o resultado negativo daria 0xFFFF e uma
    ; margem de 32.765 pixels, que e o ecra inteiro fora do sitio. Por isso o
    ; "jb" (a subtracao com emprestimo) salta para o caso "cabe": um rectangulo
    ; maior do que o ecra e um rectangulo do ecra, que e o melhor que se pode
    ; fazer com ele (e o codigo que o recusa).
    mov ax, [CONTRATO + VI_LARG]
    sub ax, [rect_larg]
    jb  .largura_no_cabe
    shr ax, 1                        ; (ecra_larg - rect_larg) / 2
    mov [IMG_INFO + II_X], ax        ; a coluna do canto
    jmp .altura_canto
.largura_no_cabe:
    xor ax, ax                        ; o rectangulo nao cabe: canto 0
    mov [IMG_INFO + II_X], ax
.altura_canto:
    mov ax, [CONTRATO + VI_ALT]
    sub ax, [rect_alt]
    jb  .altura_no_cabe
    shr ax, 1                        ; (ecra_alt - rect_alt) / 2
    mov [IMG_INFO + II_Y], ax        ; a linha do canto
    jmp .contrato_pronto
.altura_no_cabe:
    xor ax, ax
    mov [IMG_INFO + II_Y], ax

.contrato_pronto:
    ; --- o rectangulo, no contrato ----------------------------------------
    mov ax, [rect_larg]
    mov [IMG_INFO + II_DLARG], ax    ; a largura a desenhar (ja encolhida)
    mov ax, [rect_alt]
    mov [IMG_INFO + II_DALT], ax     ; a altura a desenhar (ja encolhida)
    mov ax, IMG_SEG
    mov [IMG_INFO + II_IMG_SEG], ax  ; onde esta o ficheiro .img
    mov word [IMG_INFO + II_PIXELS], 0
    mov word [IMG_INFO + II_PIXELS + 2], 0   ; a prova de que nao se desenhou

    ; --- o comando: a assinatura, a versao, o erro e o comando --------------
    ; O nucleo escreve a assinatura (o codigo confirma) e deixa a versao a
    ; 0xFFFF antes da chamada - como faz com o TEC_INFO, para o codigo trocar
    ; o 0xFFFF por um numero e a prova de que entrou ser esse numero vir do
    ; codigo. O II_ERRO vai a zero (o codigo escreve o codigo do erro se
    ; falhar), o II_CMDS a zero tambem (a conta e do codigo) e o II_COMANDO e
    ; o unico comando por enquanto.
    mov dword [IMG_INFO + II_ASSIN], ASSIN_DECOD
    mov word [IMG_INFO + II_VERSAO], 0xFFFF
    mov word [IMG_INFO + II_ERRO], 0
    mov word [IMG_INFO + II_COMANDO], CMD_DESENHAR
    mov word [IMG_INFO + II_CMDS], 0        ; a conta e do codigo, que a
                                            ; incrementa a cada comando

    ; --- a chamada: o codigo entra com o IMG_INFO em ES:BX -----------------
    ; A convencao e a mesma dos dois drivers: o codigo entra em SEG_DEC:DEC_INI
    ; com o IMG_INFO do nucleo em ES:BX, o comando em CX, e sai por "retf". O
    ; codigo copia o contrato para a memoria dele e passa o desenho inteiro a
    ; ler de la, para nao ficar com o ES a mudar a cada pixel (ver o inicio do
    ; decodificador), e e por isso que o ES e a origem e o DS o destino do
    ; "rep movsb" da entrada - como no video.dr.
    ;
    ; O ES tem de ser posto aqui, e nao aproveitado do que la estava: o nucleo
    ; usa o ES para varias coisas (o VIDEO_INFO, a fonte) e o que se sabe e o
    ; ultimo a ter mexido nele. Um ES de 0xA000 (o framebuffer) fazia o
    ; decodificador ler o contrato de dentro do ecra, achar que o "IMG1" nao
    ; estava la, e responder com o erro para dentro do framebuffer - o nucleo
    ; ficava sem resposta nenhuma e sem dar erro, porque a resposta foi para o
    ; sitio errado.
    ;
    ; E o DS do codigo, para que ele tenha onde correr: quem salta para
    ; SEG_DEC tem o DS no segmento de quem saltou (o nucleo) e as instrucoes do
    ; codigo leem os seus proprios dados por "[...]" - que e o DS.
    mov ax, SEG_BASE
    mov es, ax                        ; ES:BX = a IMG_INFO do nucleo
    mov bx, IMG_INFO
    mov ax, SEG_DEC
    mov ds, ax                         ; o DS e o do codigo, a partir de agora
    mov cx, CMD_DESENHAR
    call SEG_DEC:DEC_INI

    ; --- o DS tem de voltar antes de ler a resposta -------------------------
    ; O codigo ficou com o DS no segmento dele (e com o ES no do nucleo), e o
    ; nucleo continua a viver dos seus dados. E o mesmo vaivem de dois "mov" que
    ; o chamar_driver faz, e pelo mesmo motivo: um "cmp [IMG_INFO + ...]" com o
    ; DS no codigo lia o sitio errado - e o .sem_logo depois escrevia os glifos
    ; no segmento do codigo em vez do ecra.
    mov ax, SEG_BASE
    mov ds, ax
    mov ax, SEG_BASE
    mov es, ax                        ; o ES tambem: o nucleo e que fica

    ; --- o codigo entrou? --------------------------------------------------
    ; A versao: o nucleo deixou a 0xFFFF e so o codigo a pode trocar por um
    ; numero. E a prova de que o codigo chegou a correr, e nao de que respondeu
    ; bem - o II_ERRO e o II_PIXELS sao o resto da resposta, e o II_PIXELS a
    ; zero e o que diz que nao se desenhou nada.
    cmp word [IMG_INFO + II_VERSAO], 1
    jne  .sem_logo

    ; --- e desenhou alguma coisa? -------------------------------------------
    ; O II_PIXELS e o rectangulo inteiro (dlarg * dalt) quando desenhou, e
    ; zero quando nao desenhou. Um zero e o que o codigo escreve em caso de
    ; erro, e um rectangulo de 0 pixels nao e uma imagem - e o que o faz o
    ; nucleo cair no numero do build.
    cmp dword [IMG_INFO + II_PIXELS], 0
    je  .sem_logo

    ; --- deu certo: o ecra esta com o logo --------------------------------
    ; E o fim. O numero do build fica no titulo de baixo (VERSAO_LONG), que e
    ; a versao toda - e o que se ve a seguir, quando o nucleo escreve as tres
    ; linhas sobre o ecra limpo.
    ret

; ---------------------------------------------------------------------------
; .sem_logo: nao ha codigo, nao ha imagem, ou o ecra nao presta. O nucleo
; escreve o numero do build no ecra - o mesmo texto, com a mesma fonte e a
; mesma chamada que estava la antes de a imagem existir.
;
; E o unico sitio onde o numero do build e desenhado com a fonte do nucleo:
; o resto do nucleo escreve o titulo inteiro (VERSAO_LONG) nas tres linhas do
; ecra, com o numero incluido. Aqui o numero esta sozinho, porque e o que
; estava no ecra antes de a imagem existir e porque e o unico texto que ainda
; faz sentido sem a imagem.
; ---------------------------------------------------------------------------
.sem_logo:
    mov si, VERSAO
    mov cx, VERSAO_N
    xor dx, dx                ; linha 0, a primeira
    call linha
    ret

; ---------------------------------------------------------------------------
; repor_paleta_imagem: manda o decodificador repor a paleta do ecra
;   entrada: nada
;   saida:   nada
;
;   E o outro comando do decodificador (CMD_REPOR), com a mesma chamada de
;   segmento, a mesma IMG_INFO e o mesmo vaivem de segmentos que o mostrar_logo
;   faz para o CMD_DESENHAR. Sem codigo carregado nao ha o que repor - a paleta
;   nunca foi trocada - e por isso que o dec_codigo e perguntado primeiro.
;
;   O II_ERRO que o comando deixa na IMG_INFO nao e olhado: o CMD_REPOR nao
;   falha (ver o comando no decodificador), e o titulo que vem logo a seguir
;   fica com as cores do video.dr de qualquer maneira.
; ---------------------------------------------------------------------------
repor_paleta_imagem:
    cmp byte [dec_codigo], 0
    je  .sem_codigo
    mov word [IMG_INFO + II_COMANDO], CMD_REPOR
    mov ax, SEG_BASE
    mov es, ax                        ; ES:BX = a IMG_INFO do nucleo
    mov bx, IMG_INFO
    mov ax, SEG_DEC
    mov ds, ax                        ; o DS e o do codigo, a partir de agora
    mov cx, CMD_REPOR
    call SEG_DEC:DEC_INI
    mov ax, SEG_BASE
    mov ds, ax                        ; o nucleo e que continua a ler os
    mov es, ax                        ; seus dados - o mesmo que no mostrar_logo
.sem_codigo:
    ret

; ---------------------------------------------------------------------------
; chama o driver de video
;   entrada: CX = comando (CMD_DETETAR ou CMD_APLICAR)
;   saida:   CF=0 se o driver correu bem
;   O driver entra com o seu segmento em DS e com o VIDEO_INFO em ES:BX, e
;   pode estragar ES, CX, DX, SI e DI. O DS e reposto aqui porque o nucleo
;   continua a viver dos seus dados.
; ---------------------------------------------------------------------------
chamar_driver:
    mov ax, SEG_DRV
    mov ds, ax
    mov ax, SEG_BASE
    mov es, ax                        ; ES:BX = o VIDEO_INFO
    mov bx, CONTRATO
    call SEG_DRV:DRV_INI
    push ax
    mov ax, SEG_BASE
    mov ds, ax
    pop ax
    ret

; ---------------------------------------------------------------------------
; escolher_modo: percorre a tabela do VIDEO_INFO e fica com a resolucao maior
;   entrada: VI_NMODOS = quantos modos o driver registou
;   saida:   VI_MODO / VI_TIPO com o modo escolhido | CF=1 se a tabela estiver
;            vazia
;
;   O produto largura * altura e de 32 bits: em ecras grandes o produto passa
;   de 64 Ki e comparar so os 16 bits de baixo daria o modo errado sem dar por
;   isso. Em caso de empate (mesma resolucao) ganha o que tem mais bits por
;   pixel.
; ---------------------------------------------------------------------------
escolher_modo:
    mov cx, [CONTRATO + VI_NMODOS]
    test cx, cx
    jz  .nenhum
    dec cx                             ; o primeiro e o ponto de partida

    mov si, CONTRATO + VI_TAB
    mov ax, [si + ENT_LARG]
    mov dx, [si + ENT_ALT]
    mul dx                             ; DX:AX = altura * largura
    mov [melhor_hi], dx
    mov [melhor_lo], ax
    mov ax, [si + ENT_BPP]
    mov [melhor_bpp], ax
    mov ax, [si + ENT_MODO]
    mov [melhor_modo], ax
    mov ax, [si + ENT_TIPO]
    mov [melhor_tipo], ax

    add si, TAM_ENTRADA
    test cx, cx
    jz  .escolhido
.outro:
    push cx
    mov ax, [si + ENT_LARG]
    mov dx, [si + ENT_ALT]
    mul dx                             ; DX:AX = altura * largura deste modo
    cmp dx, [melhor_hi]                ; e maior que o melhor de sempre?
    ja  .novo
    jb  .seguinte
    cmp ax, [melhor_lo]
    ja  .novo
    jb  .seguinte
    ; empate em resolucao: decide o numero de bits por pixel
    push ax
    mov ax, [si + ENT_BPP]
    cmp ax, [melhor_bpp]
    pop ax
    jbe .seguinte
.novo:
    mov [melhor_hi], dx
    mov [melhor_lo], ax
    mov ax, [si + ENT_BPP]
    mov [melhor_bpp], ax
    mov ax, [si + ENT_MODO]
    mov [melhor_modo], ax
    mov ax, [si + ENT_TIPO]
    mov [melhor_tipo], ax
.seguinte:
    add si, TAM_ENTRADA
    pop cx
    loop .outro

.escolhido:
    mov ax, [melhor_modo]
    mov [CONTRATO + VI_MODO], ax
    mov ax, [melhor_tipo]
    mov [CONTRATO + VI_TIPO], ax
    clc
    ret
.nenhum:
    stc
    ret

; ---------------------------------------------------------------------------
; limpar_video: pinta o framebuffer todo a preto
;   O driver devolveu a geometria (VI_FBSEG, VI_FBOFF, VI_BYTESLIN, VI_ALT), e
;   isso chega: limpa-se linha a linha com "rep stosb", que serve para qualquer
;   numero de bits por pixel - cada byte vale, e preto e zero. Nao ha "add di,
;   byteslin" no fim de cada linha porque o framebuffer e seguido: o proprio
;   "stosb" avanca o DI e a proxima linha ja fica a seguir.
;
;   O numero de bytes por linha vai no BX e nao no CX porque o "rep stosb"
;   gasta o CX: deixo-lo no CX, a primeira linha era limpa e as restantes
;   VI_ALT - 1 nao escreviam nada, porque o CX ja estava a zero. Como o
;   framebuffer e limpo logo a seguir a mudar de modo, nunca se notou - ate
;   a limpeza ter passado a ser preciso para esconder o numero do build.
; ---------------------------------------------------------------------------
limpar_video:
    mov ax, [CONTRATO + VI_FBSEG]
    mov es, ax
    mov di, [CONTRATO + VI_FBOFF]
    mov bx, [CONTRATO + VI_BYTESLIN]
    test bx, bx
    jz  .fim
    mov dx, [CONTRATO + VI_ALT]
    test dx, dx
    jz  .fim
    xor al, al
.linha:
    mov cx, bx                      ; "rep stosb" conta o CX ate zero
    rep stosb
    dec dx
    jnz .linha
.fim:
    ret

; ---------------------------------------------------------------------------
; calcular_escala: o factor de ampliacao dos glifos, em funcao da resolucao
;   saida: [escala] = largura / 320, nunca menos que 1
;   A escala segue a resolucao porque o glifo e de 8x16 pixels fixos: em
;   320x200 vao 1:1 (36 caracteres * 8 = 288 pixels, cabem nos 320) e a partir
;   dai multiplicam-se para se lerem a distancia.
; ---------------------------------------------------------------------------
calcular_escala:
    ; AX = largura / 320. O "div" divide DX:AX pelo divisor, por isso o divisor
    ; nao pode estar no DX: com 320 nos dois sitios o dividendo DX:AX e
    ; 320*65536+320, o quociente nao cabe em 16 bits e a divisao estoura (#DE),
    ; que no modo real deixa o CPU a repetir a instrucao para sempre. O divisor
    ; vai para o BX e o DX, que e a metade alta do dividendo, e posto a zero.
    xor dx, dx
    mov ax, [CONTRATO + VI_LARG]
    mov bx, LARG_REF
    div bx                            ; AX = largura / 320, DX = resto
    test ax, ax
    jnz .pronto
    mov ax, 1                         ; nunca menos que 1: o glifo encolhe, nao cresce
.pronto:
    mov [escala], ax
    ret

; ---------------------------------------------------------------------------
; linha: escreve uma linha de texto no ecra de video com os glifos da fonte
;   entrada: SI = o texto, CX = quantos caracteres, DL = o numero da linha
;   (0 = a primeira). O texto nao leva zero de fim: quem escreve e
;   escrever_txt, que conta os caracteres em CX.
;
;   DL e a linha de glifos e nao a de caracteres: a altura de um glifo e
;   GLIFO_H pixels vezes a escala, por isso a linha 1 comeca logo abaixo da
;   linha 0 em qualquer resolucao, e nao 16 pixels abaixo.
;
;   O texto e um carimbo de estado, nao um cartaz: as linhas ficam encostadas
;   ao canto (0,0) em vez de centradas, e assim nao dependem da resolucao nem
;   ocupam o meio do ecra.
; ---------------------------------------------------------------------------
linha:
    ; py = linha * GLIFO_H * escala. O primeiro "mul" e por GLIFO_H e o segundo
    ; pela escala. O produto cabe em 16 bits: mesmo na escala maxima (1920/320 =
    ; 6) e 6*16 = 96, e py e um offset dentro do framebuffer.
    ;
    ; A multiplicacao vai pelo BP e nao pelo CX porque o CX e o numero de
    ; caracteres: escrever_txt comeca por guardar o SI e o CX em [txt] e [txt_n]
    ; e e dai que vai buscar quantos caracteres ha de desenhar. Se a conta usasse
    ; o CX, o "call" seguinte receberia GLIFO_H (16) em vez do comprimento do
    ; texto, e o desenho passava a seguir pelo texto todo. O BP nao e problema:
    ; escrever_txt mete-lhe zero no principio de cada glifo.
    movzx ax, dl
    mov bp, GLIFO_H
    mul bp                            ; DX:AX = linha * GLIFO_H
    mul word [escala]                 ; DX:AX = linha * GLIFO_H * escala
    mov [py], ax

    ; px = 0: todas as linhas comecam na margem esquerda
    xor ax, ax
    mov [px], ax

    call escrever_txt                 ; o SI e o CX chegam aqui como entraram
    ret

; ---------------------------------------------------------------------------
; escrever_txt: escreve um texto no framebuffer com os glifos 8x16 da BIOS
;   entrada: SI = o texto, CX = quantos caracteres
;            px/py = o canto superior esquerdo em pixels (o canto do ecra)
;   O desenho e um glifo de cada vez: os 16 bytes do caracter vao para [glifo],
;   e cada pixel aceso pinta um bloco de "escala" x "escala" da cor do
;   VIDEO_INFO.
; ---------------------------------------------------------------------------
escrever_txt:
    mov [txt], si
    mov [txt_n], cx
    test cx, cx
    jz  .fim
    mov si, [txt]
    mov bx, [txt_n]
.cada:
    lodsb
    mov [glifo_n], al
    call buscar_glifo
    mov bp, 0                         ; linha dentro do glifo (0 a GLIFO_H-1)
.linha:
    mov ah, 0x80                      ; mascara: comeca pelo bit da esquerda
    mov dx, 0                         ; coluna dentro do glifo (0 a GLIFO_W-1)
.px:
    ; O DS: na leitura abaixo e obrigatorio. Em 16 bits, um endereco com o BP
    ; como base usa o SS por omissao, e o SS do nucleo e 0: sem o prefixo isto
    ; lia a tabela de vectores em vez do glifo, e o desenho saia com o padrao
    ; errado (os bits vinham da memoria baixa, nao da fonte).
    mov al, [ds:glifo + bp]           ; o byte da linha, com os 8 pixels
    test al, ah
    jz  .fim_px
    call bloco
.fim_px:
    shr ah, 1
    inc dx
    cmp dx, GLIFO_W
    jb  .px
    inc bp
    cmp bp, GLIFO_H
    jb  .linha

    ; Avanca o cursor para o caracter seguinte: um glifo ocupa GLIFO_W * escala
    ; pixels de largura. Sem este avanco todos os caracteres ficavam desenhados
    ; uns por cima dos outros, sempre no mesmo canto.
    mov ax, GLIFO_W
    mul word [escala]
    add [px], ax

    dec bx
    jnz .cada
.fim:
    ret

; ---------------------------------------------------------------------------
; buscar_glifo: copia para [glifo] os GLIFO_N bytes do caracter em [glifo_n]
;   A fonte esta no proprio nucleo, com os caracteres de FONTE_C1 a FONTE_C1 +
;   N_FONTE - 1. Qualquer caracter fora dessa gama desenha-se em branco, a
;   partir de GLIFO_VAZIO.
;
;   SI e DI saem daqui como entraram: quem chama usa o SI para percorrer o
;   texto, e um "rep movs*" deixa-os a apontar para o fim do que copiou.
; ---------------------------------------------------------------------------
buscar_glifo:
    push si
    push di
    xor si, si
    mov al, [glifo_n]
    sub al, FONTE_C1                 ; a fonte comeca no espaco
    jb  .fora
    cmp al, N_FONTE
    ja  .fora
    mov ah, 0
    shl ax, 4                        ; GLIFO_N bytes por caracter
    add si, ax
    add si, FONTE
    jmp .copiar
.fora:
    mov si, GLIFO_VAZIO
.copiar:
    mov ax, SEG_BASE
    mov es, ax                        ; ES = a fonte, DS = o destino (o glifo)
    mov di, glifo
    mov cx, GLIFO_N / 2               ; GLIFO_N bytes = GLIFO_N / 2 palavras
    rep movsw
    pop di
    pop si
    ret

; ---------------------------------------------------------------------------
; bloco: pinta um bloco de "escala" x "escala" pixels, na cor do VIDEO_INFO
;   O pixel e o que esta na coluna DX e na linha BP do glifo que se esta a
;   desenhar. O endereco de um pixel e VI_FBOFF + y * bytes_por_linha + x, e o
;   numero de bits por pixel decide se se escreve um byte, uma palavra ou uma
;   dword.
; ---------------------------------------------------------------------------
bloco:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    ; --- onde fica o canto do bloco ---------------------------------------
    ; O "mul" multiplica sempre o AX pelo operando: o que tem de estar no AX
    ; e o y (a linha), porque o endereco e y * bytes_por_linha + x. Com o x no
    ; AX saia x * bytes_por_linha, que atirava o texto para uma coluna vertical
    ; errada. O x fica no CX ate o somar (o CX so volta a ser usado mais abaixo,
    ; para a largura do bloco, e nessa altura ja pode perder este valor).
    mov ax, [px]
    add ax, dx                       ; x = px + coluna
    mov cx, ax                       ; guarda o x
    mov ax, [py]
    add ax, bp                       ; y = py + linha
    mov dx, [CONTRATO + VI_BYTESLIN]
    mul dx                           ; DX:AX = y * bytes por linha
    add ax, cx                       ; + x
    adc dx, 0
    add ax, [CONTRATO + VI_FBOFF]
    adc dx, 0
    mov di, ax                       ; deslocamento do pixel no segmento

    ; --- bytes por pixel ---------------------------------------------------
    mov ax, [CONTRATO + VI_BPP]
    shr ax, 3                        ; 1, 2 ou 4
    mov [bpp8], ax

    ; --- quantos bytes ocupa uma linha do bloco ----------------------------
    mov ax, [escala]                 ; largura do bloco, em pixels
    mul word [bpp8]
    mov si, ax                       ; SI = bytes por linha do bloco

    ; --- pintar ------------------------------------------------------------
    mov ax, [CONTRATO + VI_FBSEG]
    mov es, ax
    mov dx, [escala]                 ; linhas do bloco
    mov cx, [escala]                 ; colunas do bloco
    cmp byte [bpp8], 1
    je  .oito
    cmp byte [bpp8], 2
    je  .dezasseis
; trinta e dois
    mov eax, [CONTRATO + VI_COR]
.vertical32:
    push cx
    rep stosd
    pop cx
    add di, [CONTRATO + VI_BYTESLIN]
    sub di, si
    dec dx
    jnz .vertical32
    jmp .fim
.dezasseis:
    mov ax, [CONTRATO + VI_COR]
.vertical16:
    push cx
    rep stosw
    pop cx
    add di, [CONTRATO + VI_BYTESLIN]
    sub di, si
    dec dx
    jnz .vertical16
    jmp .fim
.oito:
    mov al, [CONTRATO + VI_COR]
.vertical8:
    push cx
    rep stosb
    pop cx
    add di, [CONTRATO + VI_BYTESLIN]
    sub di, si
    dec dx
    jnz .vertical8
.fim:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; escreve_txt: escreve uma string terminada em zero no buffer de texto
;   entrada: SI = a string (relativa a SEG_BASE), BL = o atributo da celula
; ---------------------------------------------------------------------------
escreve_txt:
    push ax
    push bx
    push di
    push si
    mov ax, SEG_VIDEO
    mov es, ax
    xor di, di                       ; celula (0,0) = inicio do ecra
.loop:
    lodsb
    test al, al
    jz  .fim
    mov ah, bl
    stosw                            ; caracter + atributo; avanca 2 bytes em DI
    jmp .loop
.fim:
    pop si
    pop di
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; area de dados
; ---------------------------------------------------------------------------
txt:        dw 0
txt_n:      dw 0
glifo_n:    db 0
escala:     dw 1
px:         dw 0
py:         dw 0
bpp8:       dw 0
melhor_hi:  dw 0
melhor_lo:  dw 0
melhor_bpp: dw 0
melhor_modo: dw 0
melhor_tipo: dw 0
glifo:      times GLIFO_N db 0x00  ; o caracter que se esta a desenhar
GLIFO_VAZIO: times GLIFO_N db 0x00 ; o glifo de um caracter fora da fonte

; As quatro linhas do ecra de video sao desenhadas com a fonte, por escrever_txt
; contar os caracteres em CX: nenhuma das quatro strings precisa de zero de fim,
; e o comprimento vai em vez dele. As mensagens de erro vao para o buffer de
; texto, que e escreve_txt, e essas sim levam o zero.

; O titulo da segunda tela traz o numero do build no fim, e a primeira tela
; mostra esse mesmo numero a seco. Sao os mesmos caracteres, lidos de dois
; jeitos: por isso VERSAO nao e uma string propria, e um ponteiro para o numero
; do build - que esta escrito uma vez so, e nenhum dos dois pode ficar atras do
; outro. Sao os mesmos tres sitios de sempre que tem de concordar: aqui, a
; variavel BUILD do Build.sh e o nome do ficheiro que o inicio.mai procura na
; ISO (FIC_NUCLEO, em inicio.asm).
;
; O numero do build e o titulo sao o mesmo texto lido de dois jeitos, e e
; por isso que nenhum dos dois e uma string independente: o numero vive no seu
; proprio rotulo (VERSAO_NUM) e o titulo e o prefixo colado ao mesmo numero.
; O titulo escreve-se com um "linha" que pede um numero de caracteres, e por isso
; tem de ser um texto seguido - os 32 caracteres todos, sem nenhum intervalo no
; meio. A cauda e o numero a seco, lido do mesmo sitio, e nenhum dos dois pode
; ficar atras do outro.
;
; Porque a conta nao e escrita a mao: o build passou de 0.9.2026 (oito
; caracteres) para 0.12.2026 (nove), e um VERSAO_N escrito a mao que nao se
; ajustasse apontava a cauda para dentro da palavra "Build" - o titulo saia-se
; bem e o numero do build aparecia cortado. Pior ainda, um VERSAO_LONG a que
; faltasse o numero nao dava sinal nenhum: o titulo ficava um bocado mais curto
; e o ecra parecia o de sempre. Daqui a contagem ser toda feita pelo assembler:
; VERSAO_NUM_N e o comprimento do numero, VERSAO_LONG_N o do titulo, e VERSAO
; aponta para o fim do titulo menos o numero - que e exatamente onde o numero
; comeca.
;
; O numero do build e escrito UMA vez, na %define, e as duas "db" abaixo
; expandem-no. Nao e "escrever a string duas vezes" (que e o que ia dar a
; cambiar um build so numa das e o ecra dizer um numero e o ficheiro na ISO
; trazer outro), e e a unica forma de o repetir em dois sitios: um "db" com o
; nome de um rotulo por argumento NAO copia a string - escreve o byte que esta
; nesse endereco. Com "db VERSAO_NUM" o titulo acabava em "Build 0" e mais
; nada, sem nenhum aviso do nasm: e o que aconteceu da primeira vez que este
; bloco foi escrito.
%define VERSAO_LIT "0.12.2026"    ; o numero do build, escrito uma vez so
VERSAO_NUM:    db VERSAO_LIT
VERSAO_NUM_N   equ $ - VERSAO_NUM            ; 9 caracteres
VERSAO_LONG:   db "MaiSus Beta v0.1 Build ", VERSAO_LIT
                                                ; o titulo: o prefixo e o numero,
                                                ; colados (32 caracteres seguidos)
VERSAO_LONG_N  equ $ - VERSAO_LONG            ; 32 caracteres
VERSAO_N       equ VERSAO_NUM_N              ; a cauda do titulo: o numero
VERSAO:        equ VERSAO_LONG + VERSAO_LONG_N - VERSAO_NUM_N
                                                ; o numero, dentro do titulo
                                                ; (ver a nota de cima)

MENSAGEM: db "video.dr configurado com sucesso"
TXT_N     equ $ - MENSAGEM           ; 32 caracteres

; A prova do teclado e a mesma frase com o nome do driver trocado: e o que se
; escreve na terceira linha quando o teclado.dr respondeu na TEC_INFO.
MENSAGEM_TECLADO: db "teclado.dr configurado com sucesso"
TXT_TECLADO_N     equ $ - MENSAGEM_TECLADO     ; 35 caracteres

; A prova do rato e a mesma frase com o nome do driver trocado, e e a unica das
; tres que nao e escrita sempre: quem a escreve pergunta rato_ok primeiro, por
; causa das falhas do rato que nao param o arranque (ver "o driver do rato").
MENSAGEM_RATO: db "mouse.dr configurado com sucesso"
TXT_RATO_N     equ $ - MENSAGEM_RATO           ; 32 caracteres

MSG_SEM_DRIVER:   db "video.dr nao esta carregado", 0
MSG_SEM_MODOS:    db "video.dr nao viu nenhum modo util", 0
MSG_DRIVER_FALHOU: db "video.dr falhou a mudar de modo", 0
MSG_SEM_TECLADO:  db "teclado.dr nao esta carregado", 0
MSG_TEC_MUDO:     db "teclado.dr nao respondeu", 0

; ---------------------------------------------------------------------------
; TEC_INFO: a estrutura que o nucleo da ao driver de teclado (ver os
; deslocamentos TI_* no inicio deste ficheiro). Vai a zeros, como o VIDEO_INFO,
; e nao precisa de sitio fixo: o driver escreve nela pelo ES:BX que o nucleo
; lhe da. O nucleo escreve a assinatura e o 0xFFFF da versao antes de chamar.
; ---------------------------------------------------------------------------
TEC_INFO:
    times TEC_INFO_N db 0x00

; ---------------------------------------------------------------------------
; Os dados do mostrar_logo. Sao os resultados da medicao do ecra (VI_LARG,
; VI_ALT) e da leitura do cabecalho do .img, e as duas medidas do rectangulo
; final - o que o nucleo calculou e que vai dar ao decodificador.
;
; Nao precisam de sitio fixo (ao contrario do VIDEO_INFO e do IMG_INFO): e o
; nucleo que os escreve e o nucleo que os le, e nao ha ninguem de fora a le-los.
; Vivem aqui no fim dos dados, ao lado da TEC_INFO, pela mesma razao.
;
; O "prod" e o sitio de 32 bits de que o encolhimento precisa: o "mul" escreve
; o produto em DX:AX e o "div" divide DX:AX por CX, e o DX nao pode ser as duas
; coisas ao mesmo tempo. Passar por memoria e o que resolve o problema sem um
; segundo par de registos de 32 bits (que o 8086 nao tem).
; ---------------------------------------------------------------------------
dec_codigo:  db 0x00            ; 1 se o decod.img foi carregado (ver
                                ; decodificador_carregado)
dec_codigo_P db 0x00            ; preenchimento: as palavras do nucleo nao
                                ; podem ficar a meio (ver "cmp word")
img_larg:    dw 0x0000          ; a largura da imagem (do cabecalho do .img)
img_alt:     dw 0x0000          ; a altura da imagem
rect_larg:   dw 0x0000          ; a largura do rectangulo, ja encolhida
rect_alt:    dw 0x0000          ; a altura do rectangulo, ja encolhida
prod:        dd 0x00000000      ; o produto de 32 bits do encolhimento
rato_ok:     db 0x00            ; 1 se o mouse.dr respondeu mesmo (ver "o
                                ; driver do rato"): e o que a linha 3 do ecra
                                ; pergunta antes de se escrever. Um byte a serio,
                                ; lido com "cmp byte" - por isso pode vir aqui
                                ; depois dos "dw" e dos "dd", sem arrastar
                                ; preenchimento para os manter alinhados.

; ---------------------------------------------------------------------------
; FONTE: os glifos de 8x16 dos caracteres de FONTE_C1 (0x20) a FONTE_C1 +
; N_FONTE - 1 (0x7F). Cada glifo tem 16 bytes, uma por linha, com o pixel da
; esquerda no bit 7.
;
; Fonte: Lat15-VGA16, de /usr/share/consolefonts, em formato PSF: cada glifo
; tem 16 bytes de 8 pixels. A fonte original poe o pixel da esquerda no bit 0
; e esta inverte cada byte para ficar com ela no bit 7, como o desenho le.
; ---------------------------------------------------------------------------
FONTE:
%include "fonte.inc"

; ---------------------------------------------------------------------------
; O codigo, os dados e a fonte tem de caber antes do VIDEO_INFO (CONTRATO). O
; "times" faz o nasm falhar se um dia deixarem de caber, em vez de o driver
; escrever por cima do codigo.
;
; O VIDEO_INFO vem a seguir, a zeros, e a IMG_INFO depois dele (ver IMG_INFO no
; inicio deste ficheiro). O inicio.mai carrega sectores inteiros, e esta imagem
; tem tres (6 KiB a partir de 0xC000, ate 0xD7FF): as duas estruturas estao
; dentro do que foi carregado, e o nucleo nao depende de RAM qualquer que esteja
; a seguir.
; ---------------------------------------------------------------------------
    times CONTRATO - ($ - $$) db 0x90
CONTRATO_INICIO:
    times CONTRATO_N db 0x00

; A IMG_INFO a zeros, como o VIDEO_INFO: o nucleo preenche tudo o que o codigo
; precisa antes de o chamar, e o que o codigo escreve (o II_VERSAO, o II_ERRO e
; o II_PIXELS) e resposta a essa chamada, nao estado que se leia antes dela.
; ---------------------------------------------------------------------------
    times IMG_INFO - ($ - $$) db 0x00
IMG_INFO_INICIO:
    times IMG_INFO_N db 0x00

; A MOUSE_INFO a zeros, como as outras: o nucleo escreve a assinatura, a versao
; a 0xFFFF e a posicao no centro do ecra; o driver confirma a assinatura,
; escreve a versao e o handler dele passa a manter a posicao e os botoes.
; ---------------------------------------------------------------------------
    times MOUSE_INFO - ($ - $$) db 0x00
MOUSE_INFO_INICIO:
    times MOUSE_INFO_N db 0x00

; ---------------------------------------------------------------------------
; O codigo inteiro tem de caber antes do fim do terceiro sector (0x1800), que e
; o que o NUC_SET do inicio.mai le: o inicio.mai carrega sectores inteiros, e o
; que ele nao leu e lixo. Um codigo que chegue a 0x1800 e o nucleo a escrever por
; cima do que o inicio.mai nao carregou - e o sintoma seria um crash quando o
; nucleo chegasse la, muito depois do sitio que o encolheu.
;
; E o mesmo limite para o codigo que para o decodificador (o "times" no fim do
; decodificador_de_imagem.asm): os dois sao carregados a sectores inteiros e os
; dois escrevem no que o outro nao escreveu.
; ---------------------------------------------------------------------------
    times 0x1800 - ($ - $$) db 0x90