; ============================================================================
;  Maisus - interface.asm
;  Interface grafica minimal - face.grain
;
;  Compilado para face.grain e colocado em interface/face.grain dentro da ISO.
;  O nucleo carrega-o e, depois de escrever "video.dr foi configurado com
;  sucesso" e esperar 4 segundos, entrega-lhe o controlo.
;
;  missao: pintar o ecra todo de azul clarinho, usando a configuracao de video
;          que o nucleo ja deixou no contrato VIDEO_INFO. Nao se volta a mexer
;          na BIOS nem se assume um modo: le-se o framebuffer, a resolucao e os
;          bits por pixel do contrato e pinta-se dentro desses limites.
;          Acabado o azul, salta para a barra inferior (barinf.grain), que o
;          inicio.mai tambem carregou da ISO.
;
;  entrada: CS=IP=0x2000:0x0000, contrato em 0xC00:0x0E00
;  saida: nada - o ecra fica azul com a barra em baixo e o CPU espera
; ============================================================================

BITS 16

; A imagem e carregada em 0x2000:0x0000: o ORG=0 faz todos os rotulos valerem o
; deslocamento dentro da imagem, que e o que CS=0x2000 espera.
ORG 0x0000

; --- o contrato VIDEO_INFO (igual ao de nucleo.asm e drivers/video.asm) -----
SEG_IMG     equ 0x2000         ; segmento onde esta esta imagem (a interface)
SEG_NUC     equ 0xC00          ; segmento do nucleo
CONTRATO    equ 0x0E00         ; offset do VIDEO_INFO dentro do nucleo
VI_LARG     equ 0x16
VI_ALT      equ 0x18
VI_BPP      equ 0x1A
VI_BYTESLIN equ 0x1C
VI_FBSEG    equ 0x1E
VI_FBOFF    equ 0x20

; ---------------------------------------------------------------------------
; A barra inferior: /interface/barinf.grain, que o inicio.mai carregou da ISO
; para BAR_SEG:0x0000 (linear 0x30000, dois segmentos acima desta imagem).
;
; A imagem traz um cabecalho de 8 bytes - a assinatura 'B','A','R','1' e a
; versao do desenho - e a entrada do codigo e depois dele, a BAR_INI = 8. A
; conta e a mesma que o nucleo faz com o driver (DRV_INI em nucleo.asm), por
; isso que os dois valores estao escritos a mao nos dois lados.
;
; A assinatura e conferida antes do salto: sem ela, um ficheiro em falta ou
; truncado daria um salto para o meio do nada e o CPU ficaria a executar zeros
; sem dar conta. Nao ha mensagem de erro - o nucleo ja passou a fase de texto
; e nao ha fonte aqui - pelo que a falha e silenciosa: o ecra fica azul e o
; CPU espera.
; ---------------------------------------------------------------------------
SEG_BAR     equ 0x3000         ; segmento da barra (linear 0x30000)
BAR_ASSIN   equ 0x0000         ; a assinatura esta no primeiro dword da imagem
BAR_INI     equ 0x0008         ; entrada da barra: depois do cabecalho
ASSIN_BAR   equ 0x31524142     ; 'B','A','R','1' por ordem de bytes

; --- o azul clarinho, por formato de pixel ---------------------------------
; O tom escolhido e o azul clarinho (162,210,255). Em 8 bits nao basta escolher
; o indice: a paleta por omissao tem o indice 9 num azul forte, por isso a
; propria paleta e reprogramada (por_paleta) antes de encher.
; 8 bits: indice 9, com a entrada 9 da paleta posta no tom escolhido.
; 16 bits: RGB565 de (162,210,255).
; 24 bits: B, G, R (a ordem classica do VESA 24bpp).
; 32 bits: 0x00RRGGBB de (162,210,255).
COR8        equ 0x09
COR8_R      equ 40              ; vermelho 0-63 (162/255)
COR8_G      equ 52              ; verde    0-63 (210/255)
COR8_B      equ 63              ; azul     0-63 (255/255)
COR16       equ 0xA69F
COR24_B     equ 0xFF
COR24_G     equ 0xD2
COR24_R     equ 0xA2
COR32       equ 0x00A2D2FF

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

    mov es, [fbseg]
    mov di, [fboff]

    ; guards: sem geometria nao ha nada para pintar
    cmp word [byteslin], 0
    je  .parado
    cmp word [altura], 0
    je  .parado

    ; --- escolher o formato pelo bits por pixel ----------------------------
    mov ax, [bpp]
    cmp ax, 16
    je  .dezasseis
    cmp ax, 24
    je  .vintequatro
    cmp ax, 32
    je  .trintaedois
    ; 8 bits (e qualquer valor desconhecido) cai no preenchimento por byte
    jmp .oito

.oito:
    call por_paleta
    mov al, COR8
    call pintar_byte
    jmp .barra
.dezasseis:
    call pintar_word
    jmp .barra
.vintequatro:
    call pintar_24
    jmp .barra
.trintaedois:
    call pintar_dword

.barra:
    ; --- o ecra esta azul: entregar o controlo a barra inferior ---------------
    ; A barra foi carregada pelo inicio.mai e so precisa da assinatura certa
    ; para se poder confiar nela. Confirmada, o controlo passa para
    ; SEG_BAR:BAR_INI; sem assinatura, cai-se no ".parado" de sempre e o ecra
    ; fica azul sem barra.
    ;
    ; O ".barra" e um rotulo de converencia, e nao uma linha solta depois do
    ; ".trintaedois": os quatro caminhos de pintura tem de cair aqui. Com o
    ; codigo a seguir-se ao ".trintaedois", so o modo de 32 bits chegava a esta
    ; parte - os outros tres saltavam directamente para o ".parado" e a barra
    ; nunca era executada.
    mov ax, SEG_BAR
    mov es, ax
    cmp dword [es:BAR_ASSIN], ASSIN_BAR
    jne .parado
    jmp SEG_BAR:BAR_INI

.parado:
    hlt
    jmp .parado

; ---------------------------------------------------------------------------
; por_paleta: poe a entrada COR8 da paleta no azul clarinho escolhido.
;   Escreve-se directamente no RAMDAC da VGA (0x3C8 = indice, 0x3C9 = R, G, B),
;   e nao pela INT 10h AX=1010h: o SeaBIOS do QEMU nao implementa essa
;   funcao, e o pedido era ignorado sem erro. Depois do indice, o RAMDAC espera
;   as tres componentes por esta ordem: vermelho, verde, azul (0 a 63).
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
; pintar_byte: enche o framebuffer com a cor da AL, um byte por pixel
;   O ES:DI ja aponta para o canto do framebuffer. O ecra pinta-se linha a
;   linha. Quando o DI da a volta ao segmento (qualquer linha maior que 64 KiB
;   faz isso), o ES avanca 0x1000: o framebuffer VESA e linear e pode passar
;   da janela de um segmento.
; ---------------------------------------------------------------------------
pintar_byte:
    mov [cor], al
    mov dx, [altura]
.linha:
    mov bp, di
    mov cx, [byteslin]
    mov al, [cor]
    cld
    rep stosb
    cmp di, bp                         ; o DI deu a volta?
    ja  .segue
    mov ax, es
    add ax, 0x1000
    mov es, ax
.segue:
    dec dx
    jnz .linha
    ret

; ---------------------------------------------------------------------------
; pintar_word: 16 bits por pixel - dois bytes iguais por pixel nao chegam,
;   porque o valor da cor pode ter os dois bytes diferentes. Enche-se com
;   rep stosw: AX = a cor, e o numero de palavras e byteslin / 2.
; ---------------------------------------------------------------------------
pintar_word:
    mov ax, COR16
    mov [cor], ax
    mov dx, [altura]
.linha:
    mov bp, di
    mov cx, [byteslin]
    shr cx, 1
    mov ax, [cor]
    cld
    rep stosw
    cmp di, bp
    ja  .segue
    mov ax, es
    add ax, 0x1000
    mov es, ax
.segue:
    dec dx
    jnz .linha
    ret

; ---------------------------------------------------------------------------
; pintar_dword: 32 bits por pixel - uma dword por pixel, rep stosd
; ---------------------------------------------------------------------------
pintar_dword:
    mov eax, COR32
    mov [cor32], eax
    mov dx, [altura]
.linha:
    mov bp, di
    mov cx, [byteslin]
    shr cx, 2
    mov eax, [cor32]
    cld
    rep stosd
    cmp di, bp
    ja  .segue
    mov ax, es
    add ax, 0x1000
    mov es, ax
.segue:
    dec dx
    jnz .linha
    ret

; ---------------------------------------------------------------------------
; pintar_24: 24 bits por pixel - nao ha rep stos de 3 bytes, por isso
;   escreve-se pixel a pixel (B, G, R). O numero de pixels da linha e
;   byteslin / 3.
; ---------------------------------------------------------------------------
pintar_24:
    mov word [linha_atual], 0
.linha:
    mov ax, [linha_atual]
    cmp ax, [altura]
    jae .fim
    mov bp, di
    ; CX = byteslin / 3 = pixels da linha
    mov ax, [byteslin]
    xor dx, dx
    mov bx, 3
    div bx
    mov cx, ax
    test cx, cx
    jz  .segue
.pixel:
    mov al, COR24_B
    stosb
    mov al, COR24_G
    stosb
    mov al, COR24_R
    stosb
    dec cx
    jnz .pixel
.segue:
    cmp di, bp
    ja  .sem_wrap
    mov ax, es
    add ax, 0x1000
    mov es, ax
.sem_wrap:
    inc word [linha_atual]
    jmp .linha
.fim:
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
cor:         dw 0
cor32:       dd 0
linha_atual: dw 0
