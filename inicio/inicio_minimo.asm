; ============================================================================
;  Maisus - inicio_minimo.asm
;  Setor 0 (MBR) - Carregado pela BIOS em 0x7C00
;
;  missao: limpar o ecra e deixar preto. Nada mais. Nada de texto.
;  saida: inimin.mai
; ============================================================================

BITS 16
ORG 0x7C00                    ; a BIOS carrega o boot sector neste endereco

VIDEO_STATUS equ 0x3DA        ; porta de estado (tambem desbloqueia a CRTC)
VIDEO_PORTA  equ 0x3D4        ; porta de indice do controlador de video
VIDEO_DADOS  equ 0x3DF        ; porta de dados do controlador de video

VIDEO_BASE   equ 0xB800       ; inicio do buffer de texto
COLUNAS     equ 80
LINHAS      equ 25
TOTAL       equ COLUNAS * LINHAS

PREENCHER    equ 0x0100       ; int 10h AH=06: BH=01 usar BL como atributo
PRETO        equ 0x00         ; BL=00 -> fundo preto

; ---------------------------------------------------------------------------
start:
    cld                     ; strings em direccao crescente

    ; pilha: a BIOS nao garante nenhuma
    xor ax, ax
    mov ss, ax
    mov sp, 0x7C00

    ; --- 1. modo video: 80x25 texto, cor sobre preto ------------------------
    mov ax, 0x0003
    int 0x10

    ; --- 2. limpa o ecra todo, forcando o atributo de BL --------------------
    mov ax, 0x0600          ; AH=06 limpar ecra, AL=00 = ecra inteiro
    mov bx, PREENCHER | PRETO
    int 0x10

    ; --- 3. escreve 0x0000 (caracter + atributo) nas 2000 celulas ------------
    ; rep stosw escreve AX em ES:DI - este e o metodo correcto.
    ; (NAO usar rep outsw: tira o valor de AX, nao da memoria)
    mov ax, VIDEO_BASE
    mov es, ax
    xor di, di
    xor ax, ax              ; caracter 0 + atributo 0 = preto
    mov cx, TOTAL
    rep stosw
    xor ax, ax
    mov es, ax              ; devolve ES ao segmento de dados

    ; --- 4. cursor para o canto (0,0) --------------------------------------
    mov ah, 0x02
    xor bh, bh
    xor dx, dx
    int 0x10

    ; --- 5. desliga o cursor ------------------------------------------------
    ; os registos 0x0A/0x0B da CRTC sao protegidos: e preciso travar o
    ; contador de endereco do cursor pela porta 0x3DA (bit 5) antes de escrever.
    ; NOTA: 0x3DA > 255 e in/out de 8 bits so aceitam porta imm8 -> usar DX.
    ; (usar "in al, 0x3DA" faz o NASM truncar para 0xDA = porta paralela!)
    mov dx, VIDEO_STATUS
    in  al, dx
    or  al, 0x20
    out dx, al

    mov dx, VIDEO_PORTA
    mov al, 0x0A            ; registo Cursor Start
    out dx, al
    mov dx, VIDEO_DADOS
    mov al, 0xFF            ; bit 5 = cursor desactivado
    out dx, al

; ---------------------------------------------------------------------------
; ainda nao ha SO nem segundo estagio: ficar aqui
; ---------------------------------------------------------------------------
parado:
    hlt
    jmp parado

; ---------------------------------------------------------------------------
; tabela de particoes: 4 entradas de 16 bytes, todas vazias
; ---------------------------------------------------------------------------
times 510 - ($ - $$) db 0x00
dw 0xAA55                      ; assinatura de boot sector
