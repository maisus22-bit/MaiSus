; ============================================================================
;  Maisus - nucleo.asm
;  Nucleo (kernel) - build 0.3.2026
;
;  Carregado por inicio.mai da ISO (/nucleo/0.3.2026) para SEG_NUC:0x0000.
;  Convencao de entrada: CS=IP=0xC000, DS=ES=0xC000, pilha limpa em PILHA.
;
;  missao: limpar o ecra e escrever o numero do build no canto superior esquerdo.
;  saida: nada ainda - para aqui
; ============================================================================

BITS 16

; Endereco LINEAR onde o inicio.mai carrega este ficheiro, e o segmento
; correspondente. Sao dois numeros diferentes: o segmento SEG_BASE cobre
; 0xC000, mas o segmento 0xC000 cobriria 0xC0000 (768 KiB). O ORG tem de ser o
; endereco linear e o DS tem de ser o segmento.
SEG_BASE   equ 0xC000 >> 4    ; 0xC00 - o segmento deste codigo
ORG SEG_BASE << 4             ; 0xC000 - o endereco linear

SEG_VIDEO  equ 0xB800          ; inicio do buffer de texto
ATRIB      equ 0x0E            ; amarelo claro sobre preto

; ---------------------------------------------------------------------------
; A pilha nao pode estar em 0xB800-0xC000: essa e a janela do buffer de texto e
; empilhar la vai para o ecra. Fica em 0xB7FF, mesmo sitio onde o inicio.mai a
; deixou - que ja morreu e nao volta a correr.
; ---------------------------------------------------------------------------
PILHA      equ 0xB7FF

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
    mov ax, SEG_BASE
    mov ds, ax                ; DS=SEG_BASE, por isso SI e o deslocamento
    mov ax, SEG_VIDEO
    mov es, ax
    xor di, di                ; celula (0,0) = inicio do ecra
    mov cx, VERSAO_N
    mov si, VERSAO - (SEG_BASE << 4)
.escreve:
    lodsb
    mov ah, ATRIB
    stosw                     ; caracter + atributo; avanca 2 bytes em DI
    xor ax, ax
    loop .escreve

; ---------------------------------------------------------------------------
; ainda nao ha SO: o build fica no ecra e o CPU espera
; ---------------------------------------------------------------------------
parado:
    hlt
    jmp parado

; ---------------------------------------------------------------------------
; o texto fica no fim do ficheiro (nao ha padding: o nucleo cresce)
; ---------------------------------------------------------------------------
VERSAO:   db "0.3.2026"
VERSAO_N  equ $ - VERSAO       ; tem de vir DEPOIS da string (o $ e o endereco actual)