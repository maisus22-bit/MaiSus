; ============================================================================
;  Maisus - barra_inferrior.asm
;  Barra inferior - barinf.grain
;
;  Compilado para barinf.grain e colocado em interface/barinf.grain dentro da
;  ISO. O inicio.mai carrega-o em BAR_LIN (0x3000:0x0000) e o face.grain salta
;  para a entrada depois de pintar o ecra.
;
;  missao: pintar uma barra branca de ALT_BARRA pixels na base do ecra, usando a
;          configuracao de video que o nucleo ja deixou no contrato VIDEO_INFO.
;          Nao se volta a mexer na BIOS nem se assume um modo: le-se o
;          framebuffer, a resolucao e os bits por pixel do contrato e pinta-se
;          dentro desses limites.
;
;  entrada: CS=IP=0x3000:BAR_INI, contrato em 0xC00:0x0E00
;  saida: nada - o ecra fica com a barra e o CPU espera
;
;  O nome do binario e abreviado (barinf) porque a ISO9660 nao distingue maiusculas
;  de minusculas e um nome mais longo acabaria truncado a 15 caracteres.
; ============================================================================

BITS 16

; A imagem e carregada em 0x3000:0x0000: o ORG=0 faz todos os rotulos valerem o
; deslocamento dentro da imagem, que e o que CS=0x3000 espera.
ORG 0x0000

; --- o contrato VIDEO_INFO (igual ao de nucleo.asm e drivers/video.asm) -----
SEG_IMG     equ 0x3000         ; segmento onde esta esta imagem (a barra)
SEG_NUC     equ 0xC00          ; segmento do nucleo
CONTRATO    equ 0x0E00         ; offset do VIDEO_INFO dentro do nucleo
VI_LARG     equ 0x16
VI_ALT      equ 0x18
VI_BPP      equ 0x1A
VI_BYTESLIN equ 0x1C
VI_FBSEG    equ 0x1E
VI_FBOFF    equ 0x20

; --- o branco, por formato de pixel -----------------------------------------
; O branco e (255,255,255). Em 8 bits nao basta escolher o indice: a paleta por
; omissao tem o indice 15 num branco, mas o driver poe no 7 um cinza, e a
; propria paleta e reprogramada (por_paleta) antes de encher, como a interface
; faz com o azul.
; 8 bits: indice 15, com a entrada 15 da paleta posta no tom escolhido.
; 16 bits: RGB565 de (255,255,255) = todos os bits a um.
; 24 bits: B, G, R (a ordem classica do VESA 24bpp).
; 32 bits: 0x00RRGGBB de (255,255,255).
COR8        equ 0x0F
COR8_R      equ 63              ; vermelho 0-63 (255/255)
COR8_G      equ 63              ; verde    0-63 (255/255)
COR8_B      equ 63              ; azul     0-63 (255/255)
COR16       equ 0xFFFF
COR24_B     equ 0xFF
COR24_G     equ 0xFF
COR24_R     equ 0xFF
COR32       equ 0x00FFFFFF

; ---------------------------------------------------------------------------
; A barra: uma faixa branca encostada a base do ecra, da margem esquerda ate a
; margem direita. A altura e fixa em pixels e nao em fraccao do ecra: e uma barra
; de sistema, nao uma division da tela, e 16 pixels e uma medida que se le ao
; mesmo lado em qualquer resolucao. Numa resolucao mais baixa do que a barra, o
; ecra fica branco todo.
; ---------------------------------------------------------------------------
ALT_BARRA   equ 16              ; pixels de altura da barra

; ---------------------------------------------------------------------------
; Cabecalho da imagem (8 bytes). O face.grain le a assinatura no primeiro dword
; antes de saltar: e a prova de que o inicio.mai carregou mesmo a barra e nao
; lixo. A entrada e por isso depois do cabecalho, e o face.grain tem a mesma
; conta (BAR_INI = 8 em interface.asm).
; ---------------------------------------------------------------------------
    dd ASSINATURA               ; 'B','A','R','1'
    dw VERSAO_IMAGEM            ; versao do desenho desta imagem
    dw 0x0000                   ; reservado
BAR_INI equ $ - $$             ; deslocamento da entrada dentro da imagem

ASSINATURA   equ 0x31524142     ; 'B','A','R','1' por ordem de bytes
VERSAO_IMAGEM equ 1

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x7BFF
    sti

    ; --- DS = o nosso segmento (as variaveis sao locais) -------------------
    mov ax, SEG_IMG
    mov ds, ax

    ; --- ler a configuracao de video do contrato ---------------------------
    ; O contrato vive no segmento do nucleo, por isso le-se por ES e guarda-se
    ; nas variaveis locais (que vivem neste segmento, o do DS).
    mov ax, SEG_NUC
    mov es, ax
    mov ax, [es:CONTRATO + VI_LARG]
    mov [largura], ax
    mov ax, [es:CONTRATO + VI_ALT]
    mov [altura], ax
    mov ax, [es:CONTRATO + VI_BYTESLIN]
    mov [byteslin], ax
    mov ax, [es:CONTRATO + VI_FBSEG]
    mov [fbseg], ax
    mov ax, [es:CONTRATO + VI_FBOFF]
    mov [fboff], ax
    mov ax, [es:CONTRATO + VI_BPP]
    mov [bpp], ax

    ; guards: sem geometria nao ha barra para pintar
    cmp word [byteslin], 0
    je  .parado
    cmp word [altura], 0
    je  .parado
    cmp word [largura], 0
    je  .parado

    ; --- a primeira linha da barra: y = altura - ALT_BARRA ------------------
    ; Um ecra mais baixo do que a barra fica branco todo: e melhor um ecra todo
    ; branco do que um ecra sem barra nenhuma, e o "jae" comeca por zero.
    mov ax, [altura]
    sub ax, ALT_BARRA
    jae .y_pronto
    xor ax, ax
.y_pronto:
    mov [y0], ax

    ; --- quantos bytes ocupa um pixel ---------------------------------------
    mov ax, [bpp]
    shr ax, 3                        ; 1, 2 ou 3; 4 nos 32 bits
    mov [bpp8], al

    ; --- escolher o formato pelo bits por pixel ----------------------------
    cmp byte [bpp8], 1
    je  .oito
    cmp byte [bpp8], 2
    je  .dezasseis
    cmp byte [bpp8], 3
    je  .vintequatro
    ; 32 bits (e qualquer valor desconhecido) cai no preenchimento por dword
    call pintar_dword
    jmp .parado

.oito:
    call por_paleta
    call pintar_byte
    jmp .parado
.dezasseis:
    call pintar_word
    jmp .parado
.vintequatro:
    call pintar_24

.parado:
    hlt
    jmp .parado

; ---------------------------------------------------------------------------
; por_paleta: poe a entrada COR8 da paleta no branco escolhido.
;   Escreve-se directamente no RAMDAC da VGA (0x3C8 = indice, 0x3C9 = R, G, B),
;   e nao pela INT 10h AX=1010h: o SeaBIOS do QEMU nao implementa essa funcao, e
;   o pedido era ignorado sem erro. Depois do indice, o RAMDAC espera as tres
;   componentes por esta ordem: vermelho, verde, azul (0 a 63).
; ---------------------------------------------------------------------------
por_paleta:
    push ax
    push dx
    mov dx, 0x3C8
    mov al, COR8
    out dx, al
    inc dx
    mov al, COR8_R
    out dx, al
    mov al, COR8_G
    out dx, al
    mov al, COR8_B
    out dx, al
    pop dx
    pop ax
    ret

; ---------------------------------------------------------------------------
; inicio_linha: poe ES:DI no primeiro pixel da linha [k_linha] da barra
;   O endereco de um pixel e fboff + y * bytes_por_linha, e o produto e de 32
;   bits: num ecra grande uma linha ja passa do fim de um segmento. Por isso o
;   offset e separado em duas partes - a alta entra no segmento, de 0x1000 em
;   0x1000, e a baixa fica no DI - em vez de se arriscar a dar a volta dentro do
;   segmento, como o preenchimento do ecra inteiro faz.
;
;   O "shl ax, 12" multiplica a parte alta por 0x1000, que e o que um segmento
;   de 64 KiB vale. A parte alta so transbordaria o AX num framebuffer de mais de
;   4 GiB, coisa que nao cabe na memoria do QEMU.
; ---------------------------------------------------------------------------
inicio_linha:
    mov ax, [y0]
    add ax, [k_linha]                 ; y = y0 + k
    mov cx, [byteslin]
    mul cx                            ; DX:AX = y * bytes por linha
    add ax, [fboff]
    adc dx, 0                         ; DX:AX = fboff + y * bytes por linha
    mov bx, dx                        ; a parte alta e precisa depois do DI
    mov di, ax
    mov ax, bx
    shl ax, 12                        ; 0x1000 por cada 64 KiB de offset
    add ax, [fbseg]
    mov es, ax
    ret

; ---------------------------------------------------------------------------
; pintar_byte: ALT_BARRA linhas a branco, um byte por pixel
;   Uma linha da barra sao [byteslin] bytes: a barra vai de um lado ao outro do
;   ecra, e nos 8 bits um pixel e um byte.
; ---------------------------------------------------------------------------
pintar_byte:
    mov word [k_linha], 0
.linha:
    call inicio_linha
    mov al, COR8
    mov cx, [byteslin]
    cld
    rep stosb
    inc word [k_linha]
    cmp word [k_linha], ALT_BARRA
    jb  .linha
    ret

; ---------------------------------------------------------------------------
; pintar_word: 16 bits por pixel - dois bytes iguais por pixel nao chegam,
;   porque o valor da cor pode ter os dois bytes diferentes. Enche-se com
;   rep stosw: AX = a cor, e o numero de palavras e byteslin / 2.
; ---------------------------------------------------------------------------
pintar_word:
    mov ax, COR16
    mov [cor], ax
    mov word [k_linha], 0
.linha:
    call inicio_linha
    mov cx, [byteslin]
    shr cx, 1
    mov ax, [cor]
    cld
    rep stosw
    inc word [k_linha]
    cmp word [k_linha], ALT_BARRA
    jb  .linha
    ret

; ---------------------------------------------------------------------------
; pintar_dword: 32 bits por pixel - uma dword por pixel, rep stosd
; ---------------------------------------------------------------------------
pintar_dword:
    mov eax, COR32
    mov [cor32], eax
    mov word [k_linha], 0
.linha:
    call inicio_linha
    mov cx, [byteslin]
    shr cx, 2
    mov eax, [cor32]
    cld
    rep stosd
    inc word [k_linha]
    cmp word [k_linha], ALT_BARRA
    jb  .linha
    ret

; ---------------------------------------------------------------------------
; pintar_24: 24 bits por pixel - nao ha rep stos de 3 bytes, por isso escreve-se
;   pixel a pixel (B, G, R). O numero de pixels da linha e byteslin / 3.
; ---------------------------------------------------------------------------
pintar_24:
    mov word [k_linha], 0
.linha:
    call inicio_linha
    mov ax, [byteslin]
    xor dx, dx
    mov bx, 3
    div bx                            ; AX = byteslin / 3 = pixels da linha
    mov cx, ax
    test cx, cx
    jz  .fim_linha
.pixel:
    mov al, COR24_B
    stosb
    mov al, COR24_G
    stosb
    mov al, COR24_R
    stosb
    dec cx
    jnz .pixel
.fim_linha:
    inc word [k_linha]
    cmp word [k_linha], ALT_BARRA
    jb  .linha
    ret

; ---------------------------------------------------------------------------
; area de dados
; ---------------------------------------------------------------------------
largura:     dw 0
altura:      dw 0
byteslin:    dw 0
fbseg:       dw 0
fboff:       dw 0
bpp:         dw 0
bpp8:        db 0
y0:          dw 0              ; a primeira linha da barra
k_linha:     dw 0              ; a linha que se esta a pintar
cor:         dw 0
cor32:       dd 0
