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
;          dentro desses limites. Por cima da barra ja pintada desenham-se os
;          botoes: a casa e a seta curvada, cada um centrado no seu quarto do
;          ecra e afastados das bordas (ver CASA e SETA, no fim do ficheiro).
;          Pintada a base, o controlo passa para a barra superior (barsup.grain),
;          que pinta o topo e salta para o menu (menu.grain), que desenha o
;          rectangulo e devolve o controlo ao face.grain. Ver "proxima".
;
;  entrada: CS=IP=0x3000:BAR_INI, contrato em 0xC00:0x0E00
;  saida: nada - a barra inferior nao fecha o arranque: ela salta para a de cima
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

; --- a barra superior, para onde o controlo vai no fim ------------------------
; O inicio.mai carregou-a em SUP_LIN (0x4000:0x0000), um segmento acima desta
; imagem, e e ela que pinta o topo do ecra antes de saltar para o menu. Nenhuma
; das duas se pode estar a executar de cima da outra: e por isso que cada uma
; vive no seu segmento.
SEG_SUP     equ 0x4000         ; segmento da barra superior (linear 0x40000)
BAR_INI_OUT equ 0x0008         ; entrada da outra barra: depois do cabecalho

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

; --- os botoes da barra: a casa (esquerda) e a seta (direita) ---------------
; Sao carimbos de LARG_CARIMBO x ALT_CARIMBO pixels (14 x 12), que cabem na
; altura da barra com folga em cima e em baixo. Nao ficam encostados as bordas:
; cada um e centrado no seu quarto do ecra (a casa a 1/4 da largura, a seta a
; 3/4), o que os deixa simetricos e bem afastados das margens.
;
; Quem clica nos botoes e a interface: e ela que fica no ciclo da bolinha e le a
; MOUSE_INFO (o botao esquerdo e o bit0 do MI_BOTAO, no nucleo), testa o clique
; contra estes dois rectangulos (ver tratar_botoes, em interface.asm) e
; reconstroi o ecra inicial. Como ha um ecra so - a area de trabalho - os dois
; botoes fazem o mesmo, por agora:
;     - casa:  volta ao ecra inicial (o primeiro da pilha de historico);
;     - seta:  volta ao ecra anterior (tira um do topo da pilha);
; e por isso a mesma reconstrucao serve aos dois. Quando houver historico a
; serio, a casa continua a ir ao inicio e a seta desce um ecra.
ALT_CARIMBO  equ 12            ; altura de cada botao
LARG_CARIMBO equ 14            ; largura de cada botao

; ---------------------------------------------------------------------------
; Cabecalho da imagem (8 bytes). A propria imagem le a assinatura no primeiro
; dword quando arranca: e a prova de que o inicio.mai carregou mesmo a barra e nao
; lixo. A entrada e por isso depois do cabecalho, e quem salta para a barra tem a
; mesma conta (BAR_INI_OUT = 8 em interface.asm).
; ---------------------------------------------------------------------------
ASSIN:
    dd ASSINATURA               ; 'B','A','R','1'
    dw VERSAO_IMAGEM            ; versao do desenho desta imagem
    dw 0x0000                   ; reservado
BAR_INI equ $ - $$             ; deslocamento da entrada dentro da imagem

ASSINATURA   equ 0x31524142     ; 'B','A','R','1' por ordem de bytes
VERSAO_IMAGEM equ 2             ; 2: botao de seta curvada na ponta direita

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x7BFF
    sti

    ; --- DS = o nosso segmento (as variaveis sao locais) -------------------
    mov ax, SEG_IMG
    mov ds, ax

    ; --- esta imagem e mesmo a barra? ---------------------------------------
    ; E a propria imagem que se valida, e nao quem a salta: quem salta para uma
    ; imagem sem cabecalho saltaria para o meio do nada e o CPU executaria zeros
    ; sem dar conta. Com a assinatura errada nao se pinta nada, mas a corrente
    ; continua na mesma para a barra de cima - uma imagem estragada custa-se a ela
    ; propria e nunca tira as outras ao ecra, que e o que se quer das barras.
    cmp dword [ASSIN], ASSINATURA
    jne proxima

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

    ; guards: sem geometria nao ha barra para pintar aqui. A corrente nao para
    ; por isso: a barra de cima e o menu vao ler este mesmo contrato, e nao ha
    ; nada a pintar em nenhum dos lados sem ele - o menu devolve na mesma o
    ; controlo ao face.grain, que decide se ha bolinha a desenhar
    cmp word [byteslin], 0
    je  proxima
    cmp word [altura], 0
    je  proxima
    cmp word [largura], 0
    je  proxima

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
    call pintar_botoes
    jmp proxima

.oito:
    call por_paleta
    call pintar_byte
    call pintar_botoes
    jmp proxima
.dezasseis:
    call pintar_word
    call pintar_botoes
    jmp proxima
.vintequatro:
    call pintar_24
    call pintar_botoes

; ---------------------------------------------------------------------------
; proxima: a base esta pintada, agora e a vez da barra superior
;   O salto e longe e nao volta: e por isso que a barra superior (barsup.grain)
;   vive no segmento seguinte (0x4000) e nao pode estar a ser executada de
;   cima desta imagem. Ela pinta o topo e salta para o menu (menu.grain), que
;   desenha o rectangulo cinzento e devolve o controlo ao face.grain (0x2000),
;   onde o CPU fica no ciclo da bolinha.
;
;   Nao ha condicao nenhuma aqui: nem a assinatura da barra de cima nem a do
;   menu sao conferidas por quem salta. Cada imagem valida-se a si propria
;   quando arranca e salta logo para a seguinte se a sua assinatura nao estiver
;   la, pelo que a corrente nunca fica a meio. Uma imagem em falta custa-se a
;   ela propria e as outras continuam a aparecer no ecra.
;
;   As interrupcoes ficam ligadas antes da passagem: o "hlt" do ciclo da
;   bolinha, com IF=0, pararia o CPU para sempre (em modo real so o acorda um
;   NMI).
; ---------------------------------------------------------------------------
proxima:
    sti
    jmp SEG_SUP:BAR_INI_OUT

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
; pintar_botoes: desenha os dois botoes da barra
;   Cada botao fica centrado no seu quarto do ecra: a casa a 1/4 da largura e a
;   seta a 3/4. Ficam simetricos e afastados das bordas. Se o ecra for demasiado
;   estreito para um deles, o "jb" apanha o resultado negativo e esse nao sai.
;   Ambos os carimbos tem LARG_CARIMBO x ALT_CARIMBO pixels.
; ---------------------------------------------------------------------------
pintar_botoes:
    ; casa, centrada a 1/4 da largura
    mov ax, [largura]
    shr ax, 2                     ; largura / 4
    sub ax, LARG_CARIMBO / 2
    jb .seta                      ; ecra estreito: salta a casa
    mov bx, ax
    mov si, CASA
    call pintar_carimbo

.seta:
    ; seta, centrada a 3/4 da largura
    mov ax, [largura]
    mov bx, 3
    mul bx                        ; DX:AX = 3 * largura
    shr ax, 2                     ; (3 * largura) / 4
    sub ax, LARG_CARIMBO / 2
    jb .fim
    mov bx, ax
    mov si, SETA
    call pintar_carimbo
.fim:
    ret

; ---------------------------------------------------------------------------
; pintar_carimbo: pinta um carimbo (icone) sobre a barra ja branca
;   entrada: SI = carimbo (ALT_CARIMBO palavras, bit 0 = pixel da esquerda),
;            BX = coluna do canto esquerdo do carimbo
;
;   A linha da barra a pintar reaproveita o "inicio_linha" (o mesmo que o
;   preenchimento usa): poe-se a linha em k_linha e chama-se; o DI ja vai a
;   zero e depois avanca-se ate a coluna do carimbo. A cor e o preto do indice
;   0, que ninguem reprograma (as barras mexem no 15, a interface no 9, o menu
;   no 7 e a bolinha no 4).
; ---------------------------------------------------------------------------
pintar_carimbo:
    mov [carimbo_x], bx
    mov word [carimbo_r], 0
.r_loop:
    mov ax, [carimbo_r]
    add ax, (ALT_BARRA - ALT_CARIMBO) / 2
    mov [k_linha], ax
    call inicio_linha             ; ES:DI = x=0 da linha y = y0 + k_linha
    mov ax, [carimbo_x]
    xor dx, dx
    mov dl, [bpp8]
    mul dx                        ; AX = carimbo_x * bpp8
    add di, ax                    ; DI = primeiro pixel do carimbo

    mov bx, [carimbo_r]
    add bx, bx                    ; cada linha do carimbo e uma word
    mov dx, [si + bx]             ; bit c = coluna c (bit 0 = esquerda)
    mov cx, LARG_CARIMBO
.col:
    test dx, 1
    jz .pula
    call por_preto
.pula:
    mov al, [bpp8]
    xor ah, ah
    add di, ax                    ; avanca um pixel, pintado ou nao
    shr dx, 1
    dec cx
    jnz .col
    inc word [carimbo_r]
    cmp word [carimbo_r], ALT_CARIMBO
    jb .r_loop
    ret

; ---------------------------------------------------------------------------
; por_preto: escreve um pixel preto em ES:DI, no formato do modo
;   Nao mexe no DI - quem chama e que avanca, para os pixels que a mascara nao
;   acende contarem na mesma como posicao. O preto e zero nos quatro formatos.
; ---------------------------------------------------------------------------
por_preto:
    cmp byte [bpp8], 1
    je .oito
    cmp byte [bpp8], 2
    je .dezasseis
    cmp byte [bpp8], 3
    je .vintequatro
    mov eax, 0
    mov [es:di], eax
    ret
.oito:
    mov byte [es:di], 0
    ret
.dezasseis:
    mov word [es:di], 0
    ret
.vintequatro:
    mov byte [es:di], 0
    mov byte [es:di + 1], 0
    mov byte [es:di + 2], 0
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

; --- os carimbos dos botoes -------------------------------------------------
; Cada carimbo sao 12 linhas x 14 colunas, uma word por linha: o bit 0 e o
; pixel mais a esquerda e o bit 13 o mais a direita.
;
; A casa (canto esquerdo), com o telhado triangular, as paredes e a porta
; (o "##" do meio):
;
;     ......##......
;     .....####.....
;     ....######....
;     ...########...
;     ..##########..
;     .############.
;     ##############
;     .##........##.
;     .##...##...##.
;     .##...##...##.
;     .##...##...##.
;     .############.
;
CASA:
    dw 0x00C0
    dw 0x01E0
    dw 0x03F0
    dw 0x07F8
    dw 0x0FFC
    dw 0x1FFE
    dw 0x3FFF
    dw 0x1806
    dw 0x18C6
    dw 0x18C6
    dw 0x18C6
    dw 0x1FFE

; A seta curvada (canto direito): a cabeca e o triangulo da esquerda e a cauda
; (o "oooo") sai da base a curvar para baixo e para a direita.
;
;     .....##.......
;     ....###.......
;     ...####.......
;     ..#####.......
;     .######.......
;     ######Xoooo...
;     ######Xooooo..
;     .#####Xoooooo.
;     ..#####...oooo
;     ...####....ooo
;     ....###.....oo
;     .....##......o
;
SETA:
    dw 0x0060
    dw 0x0070
    dw 0x0078
    dw 0x007C
    dw 0x007E
    dw 0x07FF
    dw 0x0FFF
    dw 0x1FFE
    dw 0x3C7C
    dw 0x3878
    dw 0x3070
    dw 0x2060
carimbo_x:   dw 0              ; coluna do canto esquerdo do carimbo
carimbo_r:   dw 0              ; linha do carimbo a pintar (0 a ALT_CARIMBO-1)