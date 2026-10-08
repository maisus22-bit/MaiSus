; ============================================================================
;  Maisus - barra_superior.asm
;  Barra superior - barsup.grain
;
;  Compilado para barsup.grain e colocado em interface/barsup.grain dentro da
;  ISO. O inicio.mai carrega-o em SUP_LIN (0x4000:0x0000) e o barinf.grain salta
;  para a entrada depois de pintar a base do ecra.
;
;  missao: pintar uma barra branca de ALT_BARRA pixels no topo do ecra, usando a
;          configuracao de video que o nucleo ja deixou no contrato VIDEO_INFO.
;          Nao se volta a mexer na BIOS nem se assume um modo: le-se o
;          framebuffer, a resolucao e os bits por pixel do contrato e pinta-se
;          dentro desses limites.
;          Pintado o topo, o controlo passa para o menu (menu.grain), que desenha
;          o rectangulo cinzento e devolve o controlo ao face.grain. Ver
;          "proxima".
;
;          A imagem e tambem dona do painel branco: a entrada "branco" (o
;          deslocamento vai no cabecalho, em 0x0006) pinta de branco a metade de
;          cima do ecra e devolve o controlo por RETF. E a interface que a chama,
;          com CALL FAR, quando se clica na barra de cima; fechar o painel e
;          reconstruir o ecra pela interface (ver tratar_barra_superior em
;          interface.asm). Tal como a metade cinzenta e do menu.grain, a metade
;          branca e desta imagem e nao da interface.
;
;          Esta imagem desenha ainda o relogio do canto direito da barra (a preto,
;          "HH:MM:SS"), lendo a hora ao RTC. Quem o manda desenhar e o arranque e
;          o ciclo da bolinha da interface, pelo mesmo "branco": o pedido vai em
;          AL, como os pedidos do menu. Ver "O relogio da barra de cima", abaixo.
;          Com a metade branca aberta, o canto esquerdo mostra a data do RTC
;          ("DD/MM/YYYY"), na mesma fonte e na mesma altura do relogio. A data
;          desenha-se quando o painel e pintado (PEDIDO_PAINEL) - nao muda de
;          segundo para segundo e nao precisa de ser acertada a cada volta, ao
;          contrario do relogio (PEDIDO_RELOGIO). Ver "A data do canto esquerdo".
;
;  entrada: CS=IP=0x4000:BAR_INI, contrato em 0xC00:0x0E00
;  saida: nada - a barra superior nao fecha o arranque: ela salta para o menu;
;         a entrada "branco" devolve o controlo ao chamador com RETF
;
;  O nome do binario e abreviado (barsup) porque a ISO9660 nao distingue maiusculas
;  de minusculas e um nome mais longo acabaria truncado a 15 caracteres.
; ============================================================================

BITS 16

; A imagem e carregada em 0x4000:0x0000: o ORG=0 faz todos os rotulos valerem o
; deslocamento dentro da imagem, que e o que CS=0x4000 espera.
ORG 0x0000

; --- o contrato VIDEO_INFO (igual ao de nucleo.asm e drivers/video.asm) -----
SEG_IMG     equ 0x4000         ; segmento onde esta esta imagem (a barra)
SEG_NUC     equ 0xC00          ; segmento do nucleo
CONTRATO    equ 0x0E00         ; offset do VIDEO_INFO dentro do nucleo
VI_LARG     equ 0x16
VI_ALT      equ 0x18
VI_BPP      equ 0x1A
VI_BYTESLIN equ 0x1C
VI_FBSEG    equ 0x1E
VI_FBOFF    equ 0x20

; --- o menu, para onde o controlo vai no fim ---------------------------------
; O inicio.mai carregou-o em MEN_LIN (0x5000:0x0000), um segmento acima desta
; imagem, e e ele que pinta o rectangulo cinzento e devolve o controlo ao
; face.grain. O cabecalho
; e a entrada sao os mesmos que os desta imagem - 8 bytes de cabecalho e a
; entrada depois -, so muda a assinatura ('M','E','N','1' em vez de 'B','A','R','1').
SEG_MEN     equ 0x5000         ; segmento do menu (linear 0x50000)
MEN_INI     equ 0x0008         ; entrada do menu: depois do cabecalho

; --- a interface, para onde o controlo vai no fim ---------------------------
; O menu ja nao salta para o face.grain: e esta barra que o chama (para ele
; pintar o rectangulo) e so depois passa o controlo a interface. E a interface
; que fica com o CPU no ciclo da bolinha, com a bandeira "desenhado" ja posta.
SEG_FACE    equ 0x2000         ; segmento da interface (linear 0x20000)
FACE_INI    equ 0x0000         ; entrada da interface: ja pintada, cai no ciclo

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
; A barra: uma faixa branca encostada ao topo do ecra, da margem esquerda ate a
; margem direita. A altura e fixa em pixels e nao em fraccao do ecra: e uma barra
; de sistema, nao uma division da tela, e 16 pixels e uma medida que se le ao
; mesmo lado em qualquer resolucao. Numa resolucao mais baixa do que a barra, o
; ecra fica branco todo.
; ---------------------------------------------------------------------------
ALT_BARRA   equ 16              ; pixels de altura da barra

; --- o relogio da barra de cima ---------------------------------------------
; A hora vem do RTC (portos 0x70/0x71) e e desenhada a preto no canto direito
; da barra branca, com uma fonte propria de digitos de R_LARG x R_ALT pixels.
; O codigo todo esta no bloco "O relogio da barra de cima", mais abaixo; estes
; numeros sao as medidas que os rotulos de la e os pintores usam.
;
; A entrada "branco" desta imagem (ver 0x0006 no cabecalho) tem dois pedidos em
; AL, como o menu: PEDIDO_PAINEL pinta a metade branca (e o relogio por cima);
; PEDIDO_RELOGIO acerta so o relogio, e e o que a interface pede a cada volta do
; ciclo da bolinha. Os dois valores estao escritos a mao nos dois lados
; (interface.asm, PEDIDO_PAINEL / PEDIDO_RELOGIO) - como a entrada do menu.
R_ALT        equ 7              ; altura de cada digito
R_LARG       equ 5              ; largura de cada digito
R_PASSO      equ 6              ; R_LARG mais uma coluna de espaco
R_N          equ 8              ; "HH:MM:SS"
R_MARGEM     equ 3              ; folga entre o relogio e a margem direita
R_TOTAL      equ R_N * R_PASSO - 1
R_TOPO       equ (ALT_BARRA - R_ALT) / 2
PEDIDO_PAINEL  equ 0
PEDIDO_RELOGIO equ 1

; --- a data do canto esquerdo do painel --------------------------------------
; Com a metade branca aberta, o canto esquerdo mostra a data do RTC em
; "DD/MM/YYYY", na mesma fonte do relogio: os glifos 0 a 9 e o 11 para a "/"
; (o 10 e o ":" do relogio). Vai na mesma altura do relogio (R_TOPO) e com a
; mesma folga a margem (R_MARGEM), agora do lado esquerdo.
D_N        equ 10             ; "DD/MM/YYYY"
D_PASSO    equ R_PASSO        ; o mesmo passo dos digitos do relogio
D_TOTAL    equ D_N * D_PASSO - 1
D_MARGEM   equ R_MARGEM       ; a mesma folga, do lado esquerdo
D_BARRA    equ 11             ; o indice do glifo "/" (o 10 e o ":")

; --- a MOUSE_INFO do nucleo (igual a interface.asm, menu.asm e mouse.asm) ----
; So se le a posicao: e para o relogio nao ser redesenhado por baixo da bolinha.
MOUSE_INFO  equ 0x1200
MI_X        equ 0x06
MI_Y        equ 0x08
DOT_R       equ 3              ; raio da bolinha (ver interface.asm)

; ---------------------------------------------------------------------------
; Cabecalho da imagem (8 bytes). A propria imagem le a assinatura no primeiro
; dword quando arranca: e a prova de que o inicio.mai carregou mesmo a barra e nao
; lixo. A entrada principal e por isso depois do cabecalho, e quem salta para a
; barra tem a mesma conta (BAR_INI_OUT = 8 em barra_inferrior.asm).
;
; O quarto campo do cabecalho (offset 6) nao e reservado: guarda o deslocamento
; da entrada "branco", a que a interface chama para pintar a metade branca. E o
; mesmo truque de mapas que os outros: um unico sitio escreve o numero (aqui) e
; outro le-o (interface.asm, BRANCO_INI = 6), e nenhum dos lados o calcula a mao.
; ---------------------------------------------------------------------------
ASSIN:
    dd ASSINATURA               ; 'B','A','R','1'
    dw VERSAO_IMAGEM            ; versao do desenho desta imagem
    dw branco - $$              ; reservado: deslocamento da entrada "branco"
BAR_INI equ $ - $$             ; deslocamento da entrada dentro da imagem

ASSINATURA   equ 0x31524142     ; 'B','A','R','1' por ordem de bytes
VERSAO_IMAGEM equ 2              ; 2: o painel ganhou a data no canto esquerdo

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
    ; continua na mesma para o menu - uma imagem estragada custa-se a ela propria
    ; e nunca tira as outras ao ecra, que e o que se quer das barras.
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
    ; por isso: o menu vai ler este mesmo contrato, e nao ha nada a pintar sem
    ; ele - o menu devolve na mesma o controlo ao face.grain
    cmp word [byteslin], 0
    je  proxima
    cmp word [altura], 0
    je  proxima
    cmp word [largura], 0
    je  proxima

    ; --- a primeira linha da barra: y = 0 (topo) ----------------------------
    ; A barra encosta ao topo do ecra, por isso a primeira linha e sempre a
    ; zero e nao ha nada a acertar - ao contrario da barra inferior, que tem de
    ; descobrir a que distancia da base a barra comeca.
    xor ax, ax
    mov [y0], ax

    ; --- quantos bytes ocupa um pixel ---------------------------------------
    mov ax, [bpp]
    shr ax, 3                        ; 1, 2 ou 3; 4 nos 32 bits
    mov [bpp8], al

    ; --- quantas linhas se pintam ------------------------------------------
    ; A barra tem ALT_BARRA linhas. O painel branco ("branco") reusa estes
    ; mesmos pintores e so muda este numero - y0 e [linhas] - por isso a
    ; contagem fica numa variavel e nao escrita a mao dentro do laco.
    mov word [linhas], ALT_BARRA

    ; --- escolher o formato pelo bits por pixel ----------------------------
    cmp byte [bpp8], 1
    je  .oito
    cmp byte [bpp8], 2
    je  .dezasseis
    cmp byte [bpp8], 3
    je  .vintequatro
    ; 32 bits (e qualquer valor desconhecido) cai no preenchimento por dword
    call pintar_dword
    jmp proxima

.oito:
    call por_paleta
    call pintar_byte
    jmp proxima
.dezasseis:
    call pintar_word
    jmp proxima
.vintequatro:
    call pintar_24

; ---------------------------------------------------------------------------
; proxima: o topo esta pintado, agora e a vez do menu e depois da interface
;   Chama-se o menu (menu.grain, no segmento seguinte, 0x5000) para ele pintar
;   o rectangulo cinzento da margem direita; ao contrario das outras passagens
;   da corrente esta e um CALL FAR, e nao um salto: o menu devolve o controlo
;   aqui, e so entao se passa a interface (0x2000), onde o CPU fica no ciclo da
;   bolinha. E por isso que o menu tem de viver noutro segmento: o codigo dele
;   nao pode estar a ser executado por cima deste.
;
;   Nao ha condicao nenhuma aqui: nem a assinatura do menu nem o que ele traz
;   dentro sao conferidos por quem o chama. Cada imagem valida-se a si propria
;   quando arranca e devolve logo o controlo se a sua assinatura nao estiver la,
;   pelo que a corrente nunca fica a meio. Mesmo sem o menu, a interface recebe
;   o controlo e o ecra continua vivo.
;
;   As interrupcoes ficam ligadas antes da passagem: o "hlt" do ciclo da
;   bolinha, com IF=0, pararia o CPU para sempre (em modo real so o acorda um
;   NMI).
; ---------------------------------------------------------------------------
proxima:
    sti
    ; a barra esta branca: desenha ja o relogio no canto direito, para ele
    ; aparecer no primeiro instante e nao so no primeiro pedido da interface.
    ; Sem geometria (a assinatura faltou ou o contrato nao deu) o pintar_relogio
    ; encolhe-se e nao escreve nada.
    call ler_relogio
    call pintar_relogio
    mov al, 1                        ; via do arranque: o menu pinta o rectangulo
    call SEG_MEN:MEN_INI             ; e devolve o controlo com RETF
    jmp SEG_FACE:FACE_INI

; ---------------------------------------------------------------------------
; por_paleta: poe a entrada COR8 da paleta no branco escolhido.
;   Escreve-se directamente no RAMDAC da VGA (0x3C8 = indice, 0x3C9 = R, G, B),
;   e nao pela INT 10h AX=1010h: o SeaBIOS do QEMU nao implementa essa funcao,
;   e o pedido era ignorado sem erro. Depois do indice, o RAMDAC espera as tres
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
    mov ax, [linhas]
    cmp word [k_linha], ax
    jb  .linha
    ret

; ---------------------------------------------------------------------------
; pintar_word: 16 bits por pixel
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
    mov ax, [linhas]
    cmp word [k_linha], ax
    jb  .linha
    ret

; ---------------------------------------------------------------------------
; pintar_dword: 32 bits por pixel
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
    mov ax, [linhas]
    cmp word [k_linha], ax
    jb  .linha
    ret

; ---------------------------------------------------------------------------
; pintar_24: 24 bits por pixel
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
    mov ax, [linhas]
    cmp word [k_linha], ax
    jb  .linha
    ret

; ---------------------------------------------------------------------------
; branco: entrada do painel branco, chamada pela interface com CALL FAR.
;   Pinta de branco a metade de cima do ecra (y de 0 a altura/2, toda a
;   largura), por cima do que la esteja. E esta imagem - a barra de cima - que
;   e dona do painel; a interface so entrega o clique e reconstroi o ecra para
;   o fechar (ver tratar_barra_superior em interface.asm).
;
;   Le outra vez o contrato e revalida a assinatura, para nao depender de o
;   start ja ter corrido. Guarda o contexto que mexe e devolve por RETF, como
;   o menu: e a interface que fica com o CPU no ciclo da bolinha.
; ---------------------------------------------------------------------------
branco:
    push ds
    push es
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    push ax                       ; guarda o pedido (AL) antes de mexer no AX
    mov ax, SEG_IMG
    mov ds, ax
    pop ax                        ; AL = pedido: PEDIDO_PAINEL ou PEDIDO_RELOGIO

    cmp al, PEDIDO_RELOGIO
    je .relogio

    ; --- PEDIDO_PAINEL: pintar a metade de cima a branco --------------------
    cmp dword [ASSIN], ASSINATURA
    jne .sai

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
    shr ax, 3
    mov [bpp8], al

    cmp word [byteslin], 0
    je  .sai
    cmp word [altura], 0
    je  .sai
    cmp word [largura], 0
    je  .sai

    xor ax, ax
    mov [y0], ax                     ; o painel comeca no topo do ecra
    mov ax, [altura]
    shr ax, 1                        ; metade da altura
    mov [linhas], ax

    cmp byte [bpp8], 1
    je  .oito
    cmp byte [bpp8], 2
    je  .dezasseis
    cmp byte [bpp8], 3
    je  .vintequatro
    call pintar_dword
    jmp .pinta_relogio
.oito:
    call por_paleta
    call pintar_byte
    jmp .pinta_relogio
.dezasseis:
    call pintar_word
    jmp .pinta_relogio
.vintequatro:
    call pintar_24

.pinta_relogio:
    ; o painel cobriu a barra toda, o relogio incluido: volta a desenha-lo
    call ler_relogio
    call pintar_relogio
    ; ...e a data do canto esquerdo: o painel acabou de ser pintado de branco,
    ; por isso nao ha restos a apagar - escreve-se por cima
    call ler_data
    call pintar_data
    jmp .sai

    ; --- PEDIDO_RELOGIO: so acertar o relogio (ciclo da bolinha) ------------
    ; Redesenha quando a hora muda. Nunca por cima da bolinha: escrever por
    ; baixo dela deixava um resto vermelho, porque a interface guarda o fundo
    ; que estava debaixo do disco e o repoe mais tarde.
.relogio:
    call ler_relogio
    cmp byte [r_posto], 0
    je .rel_desenha
    mov al, [r_h]
    cmp al, [r_ult_h]
    jne .rel_desenha
    mov al, [r_m]
    cmp al, [r_ult_m]
    jne .rel_desenha
    mov al, [r_s]
    cmp al, [r_ult_s]
    je .sai
.rel_desenha:
    call ponteiro_no_relogio
    jc .sai
    call pintar_relogio
.sai:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop es
    pop ds
    retf

; ===========================================================================
; O relogio da barra de cima
;
;   A hora vem do RTC (os portos 0x70/0x71, o mesmo relogio que a BIOS le) e e
;   desenhada a preto no canto direito da barra branca, com uma fonte propria de
;   digitos de R_LARG x R_ALT pixels. Nao se pede nada a BIOS: leem-se os
;   registos do RTC e trata-se o BCD, o formato binario e as 12/24 horas, para a
;   hora ficar certa em qualquer das combinacoes.
;
;   O desenho e por pixels, com um end_pixel proprio (ponto_xy), porque o
;   relogio nao e uma faixa: sao glifos espalhados pela barra. Como e pequeno,
;   apaga-se a faixa toda (limpar_relogio) e voltam a desenhar-se os oito
;   caracteres - e o que impede um "8" de deixar restos quando passa a "1".
;
;   Quem pede o desenho e a entrada "branco" (ver acima) e o arranque (proxima).
; ===========================================================================

; ---------------------------------------------------------------------------
; ler_relogio: le a hora do RTC para r_h, r_m e r_s, ja em numero (nao em BCD)
;   O RTC guarda a hora em BCD por omissao, mas o registo B pode dizer que esta
;   em binario e/ou em 12 horas - os dois casos sao tratados.
; ---------------------------------------------------------------------------
ler_relogio:
    push ax
    push bx
    push cx
    push dx

    ; espera que o RTC termine a actualizacao (registo 0x0A, bit 7 UIP=0):
    ; ler a meio de uma actualizacao dava uma hora a saltar de um segundo
    mov cx, 0xFFFF
.uip:
    mov al, 0x0A
    out 0x70, al
    in al, 0x71
    test al, 0x80
    jz .lido
    loop .uip
.lido:
    mov al, 0x00                  ; segundos
    out 0x70, al
    in al, 0x71
    mov [r_s], al
    mov al, 0x02                  ; minutos
    out 0x70, al
    in al, 0x71
    mov [r_m], al
    mov al, 0x04                  ; horas
    out 0x70, al
    in al, 0x71
    mov [r_h], al

    mov al, 0x0B                  ; registo B: BCD/binario e 12/24h
    out 0x70, al
    in al, 0x71
    mov bl, al

    ; --- horas --------------------------------------------------------------
    mov al, [r_h]
    mov [r_pm], al                ; guarda o bruto: em 12h o bit 7 e o PM
    and al, 0x7F
    test bl, 0x04                 ; 1 = binario
    jnz .h_bin
    call bcd_bin
.h_bin:
    test bl, 0x02                 ; 1 = 24 horas
    jnz .h_pronto
    test byte [r_pm], 0x80        ; 12 horas: o bit 7 diz se e PM
    jz .h_am
    cmp al, 12
    je .h_pronto
    add al, 12
    jmp .h_pronto
.h_am:
    cmp al, 12
    jne .h_pronto
    xor al, al
.h_pronto:
    mov [r_h], al

    mov al, [r_m]                 ; minutos
    test bl, 0x04
    jnz .m_pronto
    call bcd_bin
.m_pronto:
    mov [r_m], al

    mov al, [r_s]                 ; segundos
    test bl, 0x04
    jnz .s_pronto
    call bcd_bin
.s_pronto:
    mov [r_s], al

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; bcd_bin: AL (um numero em BCD) -> AL (o numero). So muda o AX.
; ---------------------------------------------------------------------------
bcd_bin:
    push bx
    push cx
    mov bl, al
    and al, 0x0F                  ; unidades
    mov ch, al
    mov al, bl
    mov cl, 4
    shr al, cl                    ; dezenas
    mov cl, 10
    mul cl                        ; AX = dezenas * 10
    add al, ch                    ; + unidades
    pop cx
    pop bx
    ret

; ---------------------------------------------------------------------------
; tens_ones: AL (0 a 59) -> AL = dezenas, AH = unidades (para os glifos)
; ---------------------------------------------------------------------------
tens_ones:
    push bx
    mov bl, 10
    xor ah, ah
    div bl
    pop bx
    ret

; ---------------------------------------------------------------------------
; ler_data: le a data do RTC para d_dia, d_mes, d_cent e d_ano, ja em numero
;   O RTC guarda a data em BCD por omissao, como a hora (registo 0x0B diz se e
;   binario), e e tratado da mesma maneira que o ler_relogio. O seculo vem do
;   registo 0x32 (20 em "20xx"); o 0x07 e o dia, o 0x08 o mes e o 0x09 o ano.
; ---------------------------------------------------------------------------
ler_data:
    push ax
    push bx
    push cx
    push dx

    ; espera o fim da actualizacao, como o ler_relogio (registo 0x0A, UIP)
    mov cx, 0xFFFF
.uip:
    mov al, 0x0A
    out 0x70, al
    in al, 0x71
    test al, 0x80
    jz .lido
    loop .uip
.lido:
    mov al, 0x07                  ; dia do mes
    out 0x70, al
    in al, 0x71
    mov [d_dia], al
    mov al, 0x08                  ; mes
    out 0x70, al
    in al, 0x71
    mov [d_mes], al
    mov al, 0x32                  ; seculo
    out 0x70, al
    in al, 0x71
    mov [d_cent], al
    mov al, 0x09                  ; ano dentro do seculo
    out 0x70, al
    in al, 0x71
    mov [d_ano], al

    mov al, 0x0B                  ; registo B: BCD/binario
    out 0x70, al
    in al, 0x71
    mov bl, al

    mov al, [d_dia]
    test bl, 0x04                 ; 1 = binario
    jnz .dia_pronto
    call bcd_bin
.dia_pronto:
    mov [d_dia], al
    mov al, [d_mes]
    test bl, 0x04
    jnz .mes_pronto
    call bcd_bin
.mes_pronto:
    mov [d_mes], al
    mov al, [d_cent]
    test bl, 0x04
    jnz .cent_pronto
    call bcd_bin
.cent_pronto:
    mov [d_cent], al
    mov al, [d_ano]
    test bl, 0x04
    jnz .ano_pronto
    call bcd_bin
.ano_pronto:
    mov [d_ano], al

    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; por_hora: converte r_h/r_m/r_s nos indices dos glifos de "HH:MM:SS" em r_buf
;   O 10 e o indice do dois-pontos; os digitos sao 0 a 9.
; ---------------------------------------------------------------------------
por_hora:
    push ax
    push bx
    push cx
    mov al, [r_h]
    call tens_ones
    mov [r_buf + 0], al
    mov [r_buf + 1], ah
    mov byte [r_buf + 2], 10
    mov al, [r_m]
    call tens_ones
    mov [r_buf + 3], al
    mov [r_buf + 4], ah
    mov byte [r_buf + 5], 10
    mov al, [r_s]
    call tens_ones
    mov [r_buf + 6], al
    mov [r_buf + 7], ah
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; por_data: converte d_dia/d_mes/d_cent/d_ano nos indices dos glifos de
;   "DD/MM/YYYY" em d_buf. O 11 e a "/"; os digitos sao 0 a 9.
; ---------------------------------------------------------------------------
por_data:
    push ax
    mov al, [d_dia]
    call tens_ones
    mov [d_buf + 0], al
    mov [d_buf + 1], ah
    mov byte [d_buf + 2], D_BARRA
    mov al, [d_mes]
    call tens_ones
    mov [d_buf + 3], al
    mov [d_buf + 4], ah
    mov byte [d_buf + 5], D_BARRA
    mov al, [d_cent]
    call tens_ones
    mov [d_buf + 6], al
    mov [d_buf + 7], ah
    mov al, [d_ano]
    call tens_ones
    mov [d_buf + 8], al
    mov [d_buf + 9], ah
    pop ax
    ret

; ---------------------------------------------------------------------------
; pintar_relogio: desenha a hora que esta em r_h/r_m/r_s sobre a barra
;   Calcula a coluna do canto esquerdo a partir da largura (encostado a margem
;   direita) e so desenha se houver espaco; apaga a faixa e volta a escrever os
;   oito caracteres. Guarda a hora desenhada, para o pedido seguinte saber se
;   mudou. Sem geometria nao escreve nada.
; ---------------------------------------------------------------------------
pintar_relogio:
    cmp word [byteslin], 0
    je .fim
    cmp byte [bpp8], 0
    je .fim
    mov ax, [largura]
    cmp ax, R_TOTAL + R_MARGEM
    jb .fim
    sub ax, R_TOTAL + R_MARGEM
    mov [r_x], ax

    call por_hora
    call limpar_relogio
    call pintar_digitos

    mov al, [r_h]
    mov [r_ult_h], al
    mov al, [r_m]
    mov [r_ult_m], al
    mov al, [r_s]
    mov [r_ult_s], al
    mov byte [r_posto], 1
.fim:
    ret

; ---------------------------------------------------------------------------
; limpar_relogio: apaga a faixa do relogio (branco) antes de redesenhar
; ---------------------------------------------------------------------------
limpar_relogio:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov word [r_j], R_TOPO
.linha:
    mov bx, [r_x]
    mov dx, bx
    add dx, R_TOTAL
.col:
    mov si, [r_j]
    call ponto_xy
    call por_branco
    inc bx
    cmp bx, dx
    jb .col
    inc word [r_j]
    mov ax, R_TOPO + R_ALT
    cmp word [r_j], ax
    jb .linha
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; pintar_digitos: escreve os R_N glifos de r_buf a partir de r_x
; ---------------------------------------------------------------------------
pintar_digitos:
    push ax
    push bx
    push di
    mov bx, [r_x]
    mov di, r_buf
    mov cx, R_N
    call pintar_glifos
    pop di
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; pintar_glifos: escreve CX glifos (os indices em DI) a partir da coluna BX
;   O si de cada glifo vem de desenha_caractere, que preserva os registos; por
;   isso o laco pode usar BX (coluna), DI (glifo) e CX (contagem) a solta.
; ---------------------------------------------------------------------------
pintar_glifos:
    push ax
    push bx
    push cx
    push di
.prox:
    mov al, [di]
    mov si, R_TOPO
    call desenha_caractere
    add bx, R_PASSO
    inc di
    dec cx
    jnz .prox
    pop di
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; pintar_data: desenha a data que esta em d_dia/d_mes/d_cent/d_ano no canto
;   esquerdo, na mesma altura do relogio. O painel acaba de ser pintado de
;   branco, por isso nao ha restos a apagar: escreve-se por cima. Sem
;   geometria nao escreve nada.
; ---------------------------------------------------------------------------
pintar_data:
    cmp word [byteslin], 0
    je .fim
    cmp byte [bpp8], 0
    je .fim
    mov ax, [largura]
    cmp ax, D_TOTAL + D_MARGEM
    jb .fim
    call por_data
    mov bx, D_MARGEM
    mov di, d_buf
    mov cx, D_N
    call pintar_glifos
.fim:
    ret

; ---------------------------------------------------------------------------
; desenha_caractere: um glifo da fonte
;   entrada: BX = coluna, SI = linha de topo, AL = indice do glifo
;   Cada glifo sao R_ALT bytes, um por linha, com o bit 4 na coluna 0 (a da
;   esquerda); o "shl" de cada passo poe a coluna seguinte no bit 4.
; ---------------------------------------------------------------------------
desenha_caractere:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov [c_x], bx
    mov [c_y], si
    xor ah, ah
    mov cx, R_ALT
    mul cx                        ; AX = indice * R_ALT
    mov di, fonte
    add di, ax
    mov [c_fonte], di             ; o ponto_xy devolve o pixel no DI: o
    mov bp, R_ALT                 ; apontador da linha do glifo fica em memoria,
.linha:                           ; senao o primeiro pixel perdia-o
    mov bx, [c_fonte]
    mov dl, [bx]
    inc word [c_fonte]
    mov bx, [c_x]
    mov cx, R_LARG
.col:
    test dl, 0x10
    jz .salta
    mov si, [c_y]
    call ponto_xy
    call por_preto
.salta:
    shl dl, 1
    inc bx
    dec cx
    jnz .col
    inc word [c_y]
    dec bp
    jnz .linha
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; ponteiro_no_relogio: a bolinha do rato esta por cima do relogio?
;   saida: CF=1 se sim (o relogio adia o desenho), CF=0 se pode desenhar.
;   A folga e DOT_R, o raio do disco, para a zona testada cobrir a bolinha toda.
; ---------------------------------------------------------------------------
ponteiro_no_relogio:
    mov ax, [largura]
    cmp ax, R_TOTAL + R_MARGEM
    jb .livre
    sub ax, R_TOTAL + R_MARGEM    ; r_x
    mov bx, ax
    sub bx, DOT_R
    jb .livre                     ; relogio encostado a esquerda: deixa desenhar
    push es
    mov ax, SEG_NUC
    mov es, ax
    mov ax, [es:MOUSE_INFO + MI_X]
    mov dx, [es:MOUSE_INFO + MI_Y]
    pop es
    cmp dx, ALT_BARRA + DOT_R
    jae .livre                    ; abaixo do relogio
    cmp ax, bx
    jb .livre                     ; a esquerda do relogio
    stc
    ret
.livre:
    clc
    ret

; ---------------------------------------------------------------------------
; ponto_xy: ES:DI = o pixel (BX = coluna, SI = linha) do framebuffer
;   Mesma conta do end_pixel da interface: linear = y * byteslin + x * bpp8
;   + fboff, com a parte alta a virar segmento. Preserva BX, SI, CX, DX e BP.
; ---------------------------------------------------------------------------
ponto_xy:
    push ax
    push cx
    push dx
    push si
    push bp
    mov ax, si
    mov cx, [byteslin]
    mul cx                        ; DX:AX = y * byteslin
    mov si, ax
    mov bp, dx
    mov ax, bx
    xor cx, cx
    mov cl, [bpp8]
    mul cx                        ; DX:AX = x * bpp8
    add ax, si
    adc dx, bp
    add ax, [fboff]
    adc dx, 0
    mov di, ax
    shl dx, 12
    mov ax, [fbseg]
    add ax, dx
    mov es, ax
    pop bp
    pop si
    pop dx
    pop cx
    pop ax
    ret

; ---------------------------------------------------------------------------
; por_preto: um pixel preto em ES:DI. O preto e zero nos quatro formatos.
; ---------------------------------------------------------------------------
por_preto:
    cmp byte [bpp8], 1
    je .oito
    cmp byte [bpp8], 2
    je .dezasseis
    cmp byte [bpp8], 3
    je .vintequatro
    mov dword [es:di], 0
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
; por_branco: um pixel branco em ES:DI, no formato do modo (ver COR8/COR16/...)
; ---------------------------------------------------------------------------
por_branco:
    cmp byte [bpp8], 1
    je .oito
    cmp byte [bpp8], 2
    je .dezasseis
    cmp byte [bpp8], 3
    je .vintequatro
    mov eax, COR32
    mov [es:di], eax
    ret
.oito:
    mov byte [es:di], COR8
    ret
.dezasseis:
    mov word [es:di], COR16
    ret
.vintequatro:
    mov byte [es:di], COR24_B
    mov byte [es:di + 1], COR24_G
    mov byte [es:di + 2], COR24_R
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
linhas:      dw 0              ; quantas linhas se pintam (a barra ou o painel)
k_linha:     dw 0              ; a linha que se esta a pintar
cor:         dw 0
cor32:       dd 0

; --- o estado do relogio ----------------------------------------------------
r_h:         db 0              ; hora, minutos e segundos, ja em numero
r_m:         db 0
r_s:         db 0
r_ult_h:     db 0              ; a ultima hora que se desenhou (para nao
r_ult_m:     db 0              ; redesenhar o mesmo segundo)
r_ult_s:     db 0
r_posto:     db 0              ; 1 depois de o relogio estar no ecra
r_pm:        db 0              ; as horas em bruto (o bit 7 e o PM, em 12h)
r_x:         dw 0              ; coluna do canto esquerdo do relogio
r_j:         dw 0              ; a linha do relogio que se esta a apagar
c_x:         dw 0              ; canto esquerdo do glifo a desenhar
c_y:         dw 0              ; linha de topo do glifo a desenhar
c_fonte:     dw 0              ; apontador para a linha do glifo (o DI e do ponto_xy)
r_buf:       times R_N db 0    ; os indices dos glifos de "HH:MM:SS"

; --- o estado da data ---------------------------------------------------------
d_dia:       db 0              ; dia do mes (1-31), ja em numero
d_mes:       db 0              ; mes (1-12)
d_cent:      db 0              ; seculo (0x32), 20 em "20xx"
d_ano:       db 0              ; ano dentro do seculo (0.09)
d_buf:       times D_N db 0    ; os indices dos glifos de "DD/MM/YYYY"

; --- os glifos do relogio ---------------------------------------------------
; Cada glifo sao R_ALT bytes, um por linha, com o bit 4 na coluna da esquerda
; (coluna 0) e o bit 0 na da direita (coluna 4). O R_ALT e o numero total de
; linhas do glifo; a ultima linha da moldura fica a zero nos digitos que nao a
; usam. O 10.o glifo e o ":".
fonte:
    db 0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E   ; 0
    db 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E   ; 1
    db 0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F   ; 2
    db 0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E   ; 3
    db 0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02   ; 4
    db 0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E   ; 5
    db 0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E   ; 6
    db 0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08   ; 7
    db 0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E   ; 8
    db 0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C   ; 9
    db 0x00, 0x04, 0x04, 0x00, 0x04, 0x04, 0x00   ; :
    db 0x01, 0x02, 0x04, 0x08, 0x10, 0x00, 0x00   ; /
