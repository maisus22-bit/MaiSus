; ============================================================================
;  Maisus - nucleo.asm
;  Nucleo (kernel) - build 0.5.2026
;
;  Carregado por inicio.mai da ISO (/nucleo/0.5.2026) para SEG_NUC:0x0000.
;  O inicio.mai carrega tambem o driver de video (/drivers/video.dr) para
;  SEG_DRV:DRV_INI (0x0008, depois do cabecalho de 8 bytes).
;  Convencao de entrada: CS=IP=0xC000, DS=ES=0xC000, pilha limpa em PILHA.
;
;  missao: escrever o numero do build, esperar 4 segundos, chamar o driver de
;          video para ele ver as informacoes do dispositivo, escolher a maior
;          resolucao que o driver reportou, mandar-lhe aplicar esse modo e
;          escrever no ecra de video a prova de que correu.
;  saida: nada - o ecra fica com a mensagem e o CPU espera
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
; no ecra, esta fica outros 4. So depois dela e que o driver de video e chamado.
; ---------------------------------------------------------------------------
ESPERA_US  equ 4000000         ; 4 segundos em microssegundos

; O driver assina o primeiro DWORD do seu codigo com 'VID1'. E assim que o
; nucleo sabe que o inicio.mai conseguiu carregar o driver sem ter de saber o
; tamanho do que carregou.
ASSIN_DRIVER equ 0x31444956     ; 'V','I','D','1' por ordem de bytes

CMD_DETETAR equ 0              ; o driver olha para o dispositivo de video
CMD_APLICAR equ 1              ; o driver poe o video no modo escolhido

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
    mov ax, 0x0003
    int 0x10

    ; --- limpa o ecra inteiro ---------------------------------------------
    ; AX=0600 limpa o ecra todo. Com BH=01 a BIOS usa BL como atributo de
    ; preenchimento; com BH=00 o preenchimento fica com o atributo ja presente
    ; no ecra, que nao apaga nada. Por isso BH=01 e BL=00.
    mov ax, 0x0600
    mov bx, 0x0100
    int 0x10

    ; --- cursor para o canto (0,0) ----------------------------------------
    mov ah, 0x02
    xor bh, bh
    xor dx, dx
    int 0x10

    ; --- escreve o numero do build na primeira linha -----------------------
    ; escreve-se directamente no buffer de texto: cada celula ocupa 2 bytes
    ; (caracter + atributo). Nao se usa a INT 10h AH=13h porque a implementacao
    ; dessa funcao varia entre BIOS e aqui nao devolve nada.
    mov si, VERSAO
    mov bl, ATRIB
    call escreve_txt

    ; --- espera 4 segundos -------------------------------------------------
    ;   INT 15h AH=86h  CX:DX = microssegundos a esperar (CX = metade alta)
    mov cx, ESPERA_US >> 16
    mov dx, ESPERA_US & 0xFFFF
    mov ah, 0x86
    int 0x15

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

    ; --- de preto a limpo, e a mensagem ------------------------------------
    call limpar_video
    call mensagem

    ; --- espera 4 segundos apos mostrar "video.dr configurado com sucesso" -----
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
; sem_driver / sem_modos / driver_falhou: ecra vermelho e a explicacao. O
; nucleo nao se mexe num ecra de video: e texto que ainda esta em modo texto,
; por isso escreve-se no buffer de texto como sempre.
; ---------------------------------------------------------------------------
sem_driver:
    mov si, MSG_SEM_DRIVER
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
;   numero de bits por pixel - cada byte vale, e preto e zero.
; ---------------------------------------------------------------------------
limpar_video:
    mov ax, [CONTRATO + VI_FBSEG]
    mov es, ax
    mov di, [CONTRATO + VI_FBOFF]
    mov cx, [CONTRATO + VI_BYTESLIN]
    test cx, cx
    jz  .fim
    mov dx, [CONTRATO + VI_ALT]
    test dx, dx
    jz  .fim
    xor al, al
.linha:
    rep stosb
    dec dx
    jnz .linha
.fim:
    ret

; ---------------------------------------------------------------------------
; mensagem: escreve a prova no ecra de video, no canto superior esquerdo
;   A escala dos glifos segue a resolucao: em 320x200 vao 1:1 (36 caracteres
;   * 8 = 288 pixels, cabem nos 320) e a partir dai multiplicam-se para se lerem
;   a distancia. escala = largura / 320, nunca menos que 1.
; ---------------------------------------------------------------------------
mensagem:
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
    jnz .escala_ok
    mov ax, 1
.escala_ok:
    mov [escala], ax

    ; --- canto superior esquerdo -------------------------------------------
    ; A mensagem e um carimbo de estado, nao um cartaz: fica encostada ao canto
    ; (0,0) em vez de centrada, e assim nao depende da resolucao nem ocupa o
    ; meio do ecra.
    mov word [px], 0
    mov word [py], 0

    ; --- escrever ----------------------------------------------------------
    mov si, MENSAGEM
    mov cx, TXT_N
    call escrever_txt
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

VERSAO:   db "0.5.2026", 0         ; o zero do fim e obrigatorio: escreve_txt
                                   ; so para quando o encontra, e logo a seguir
                                   ; esta a MENSAGEM (sem zero, escrevia as duas)

MENSAGEM: db "video.dr foi configurado com sucesso", 0
TXT_N     equ $ - MENSAGEM - 1 ; 36 caracteres (sem o zero do fim)

MSG_SEM_DRIVER:   db "video.dr nao esta carregado", 0
MSG_SEM_MODOS:    db "video.dr nao viu nenhum modo util", 0
MSG_DRIVER_FALHOU: db "video.dr falhou a mudar de modo", 0

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
; O VIDEO_INFO vem a seguir, a zeros. O inicio.mai carrega sectores inteiros, e
; esta imagem tem tres (6 KiB a partir de 0xC000, ate 0xD7FF): o driver
; escreve na estrutura dentro do que foi carregado, e o nucleo nao depende de
; RAM qualquer que esteja a seguir.
; ---------------------------------------------------------------------------
    times CONTRATO - ($ - $$) db 0x90
CONTRATO_INICIO:
    times CONTRATO_N db 0x00
