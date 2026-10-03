; ============================================================================
;  Maisus - inicio.asm
;  Gerenciador de boot - segundo estagio
;
;  Carregado por inimin.mai da ISO (/INICIO/INICIO.MAI) para BASE:0x0000.
;  Convencao de entrada: CS=IP=BASE, DS=BASE, ES=0x0000.
;
;  missao: escrever a versao do build e ficar a espera
;  saida: inicio.mai
; ============================================================================

BITS 16

BASE       equ 0xA000          ; segmento onde inimin.mai carrega este ficheiro
ORG BASE

SEG_VIDEO  equ 0xB800          ; inicio do buffer de texto
ATRIB      equ 0x0E            ; amarelo claro sobre preto

; ---------------------------------------------------------------------------
start:
    cld

    ; pilha propria: a do primeiro estagio ja nao serve
    xor ax, ax
    mov ss, ax
    mov sp, 0xBFFF

    ; --- modo video: 80x25 texto, cor sobre preto -------------------------
    mov ax, 0x0003
    int 0x10

    ; --- escreve a versao na primeira linha --------------------------------
    ; escreve-se directamente no buffer de texto: cada celula ocupa 2 bytes
    ; (caracter + atributo). Nao se usa a INT 10h AH=13h porque a implementacao
    ; dessa funcao varia entre BIOS e aqui nao devolve nada.
    mov ax, SEG_VIDEO
    mov es, ax
    xor di, di                ; celula (0,0) = inicio do ecra
    mov cx, VERSAO_N
    mov si, VERSAO - BASE     ; DS=BASE, por isso SI e o deslocamento no segmento
.escreve:
    lodsb
    mov ah, ATRIB
    stosw                     ; caracter + atributo; avanca 2 bytes em DI
    xor ax, ax
    loop .escreve
    mov ax, SEG_VIDEO
    mov es, ax                ; devolve ES ao segmento do buffer de texto

; ---------------------------------------------------------------------------
; ainda nao ha SO: a versao fica no ecra e o CPU espera
; ---------------------------------------------------------------------------
parado:
    hlt
    jmp parado

; ---------------------------------------------------------------------------
; o texto fica no fim do ficheiro (nao ha padding: este estagio cresce)
; ---------------------------------------------------------------------------
VERSAO:   db "MaiSus v0.1 Build 0.2.2026"
VERSAO_N  equ $ - VERSAO       ; tem de vir DEPOIS da string (o $ e o endereco actual)