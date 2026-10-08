; ============================================================================
;  Maisus - menu.asm
;  Menu - menu.grain
;
;  Compilado para menu.grain e colocado em interface/menu.grain dentro da ISO.
;  O inicio.mai carrega-o em MEN_LIN (0x5000:0x0000) e o barsup.grain chama-o
;  (CALL FAR) depois de pintar a barra de cima.
;
;  missao: pintar um rectangulo cinzento encostado a margem direita do ecra e
;          centrado na vertical, usando a configuracao de video que o nucleo ja
;          deixou no contrato VIDEO_INFO. Nao se volta a mexer na BIOS nem se
;          assume um modo: le-se o framebuffer, a resolucao e os bits por pixel
;          do contrato e pinta-se dentro desses limites.
;          Quando o botao esquerdo do rato desce dentro do rectangulo, esta
;          imagem pinta tambem a metade direita da area de trabalho a cinzento -
;          e ela, e nao a interface, que desenha esse painel.
;          A mesma entrada e chamada pelo ciclo da bolinha da interface a cada
;          pedido do rato (a interface so entrega o pedido e le o AL de volta);
;          o menu devolve o controlo com RETF, sem tocar no contexto de quem o
;          chamou. Quem desenha o ponteiro continua a ser o face.grain.
;
;  entrada: CS=IP=0x5000:MENU_INI, contrato em 0xC00:0x0E00; AL traz o pedido
;           (1 arranque/reconstrucao, 0 ciclo da bolinha, 2 so a metade - ver
;           a nota "A entrada da imagem" mais abaixo)
;  saida: AL=1 se pintou a metade cinzenta (o ecra mudou), AL=0 se nao mexeu em
;         nada; o rectangulo do menu fica sempre pintado quando a imagem e valida
;
;  Por enquanto o rectangulo e a metade cinzenta: nenhuma palavra, nenhum item,
;  nenhuma escolha.
;
;  O nome do binario e curto (menu) porque a ISO9660 nao distingue maiusculas de
;  minusculas e um nome mais longo acabaria truncado a 15 caracteres.
; ============================================================================

BITS 16

; A imagem e carregada em 0x5000:0x0000: o ORG=0 faz todos os rotulos valerem o
; deslocamento dentro da imagem, que e o que CS=0x5000 espera.
ORG 0x0000

; --- o contrato VIDEO_INFO (igual ao de nucleo.asm e drivers/video.asm) -----
SEG_IMG     equ 0x5000         ; segmento onde esta esta imagem (o menu)
SEG_NUC     equ 0xC00          ; segmento do nucleo
CONTRATO    equ 0x0E00         ; offset do VIDEO_INFO dentro do nucleo
VI_LARG     equ 0x16
VI_ALT      equ 0x18
VI_BPP      equ 0x1A
VI_BYTESLIN equ 0x1C
VI_FBSEG    equ 0x1E
VI_FBOFF    equ 0x20

; --- a MOUSE_INFO do nucleo (igual a nucleo.asm e drivers/mouse.asm) ---------
; O menu le-a para saber onde esta o ponteiro e se o botao esquerdo acabou de
; descer. E a mesma estrutura que o ciclo da bolinha da interface le; a unica
; diferenca e que aqui nao se desenha nada com ela, decide-se um clique.
; O estado dos botoes tem o bit0 no esquerdo, bit1 no direito e bit2 no meio.
MOUSE_INFO  equ 0x1200
MI_X        equ 0x06
MI_Y        equ 0x08
MI_BOTAO    equ 0x0A

; ---------------------------------------------------------------------------
; Cabecalho da imagem (8 bytes). A propria imagem le a assinatura no primeiro
; dword quando arranca: e a prova de que o inicio.mai carregou mesmo o menu e nao
; lixo. Sem ela nao se pinta o rectangulo, mas o controlo volta na mesma ao
; face.grain, que e quem fica com o CPU no ciclo da bolinha.
; A entrada e por isso depois do cabecalho, e quem salta para o menu tem a mesma
; conta (MEN_INI = 8 em barra_superior.asm).
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
ASSIN:
    dd ASSINATURA               ; 'M','E','N','1'
    dw VERSAO_IMAGEM            ; versao do desenho desta imagem
    dw 0x0000                   ; reservado
MENU_INI equ $ - $$            ; deslocamento da entrada dentro da imagem

ASSINATURA   equ 0x314E454D     ; 'M','E','N','1' por ordem de bytes
VERSAO_IMAGEM equ 1

; ---------------------------------------------------------------------------
; O rectangulo: o painel encosta a margem direita - a ultima coluna do ecra e a
; ultima coluna do rectangulo - e fica centrado na vertical: a sobra de altura
; metade por cima e metade por baixo.
;
; A medida e um limite, nao um valor fixo: o painel nunca passa de LARG_MENU x
; ALT_MENU (como as barras nunca passam de ALT_BARRA de altura, que e uma medida
; que se le ao mesmo lado em qualquer ecra) e nunca passa de metade do ecra em
; cada direccao. O limite e pequeno de proposito - e um painel, nao uma seccao do
; ecra - e num ecra em que ele nem chegue a metade, manda o limite:
;
;     1280x1024 -> 25 x 30, encostado a direita, centrado
;      320x200  -> 25 x 30, encostado a direita, centrado
;
; Se o limite fixo for maior do que o ecra inteiro, o rectangulo encolhe ao que
; couber em vez de sair do ecra: comeca no canto (x0 e y0 a zero) e as linhas que
; nao cabem nao sao pintadas. E melhor um rectangulo mais pequeno do que pixels
; desenhados fora do framebuffer, que num ecra VESA nao existem e iriam mexer em
; memoria alheia.
; ---------------------------------------------------------------------------
LARG_MENU   equ 25              ; pixels de largura do rectangulo
ALT_MENU    equ 30              ; pixels de altura do rectangulo

; --- a altura das barras ----------------------------------------------------
; A area de trabalho e o ecra entre as duas barras, e cada barra tem ALT_BARRA
; de altura (ver barra_inferrior.asm / barra_superior.asm). O painel cinzento
; nao pisa as barras: enche so a area de trabalho, de uma barra a outra.
ALT_BARRA   equ 16

; --- o cinzento, por formato de pixel ---------------------------------------
; O cinzento e (128,128,128). Em 8 bits nao basta escolher o indice: o indice 7
; da paleta e um cinza, mas nao o tom escolhido, e por isso que a propria paleta
; e reprogramada (por_paleta) antes de pintar, como as barras e a interface fazem
; com o branco e com o azul.
; 8 bits: indice 7, com a entrada 7 da paleta posta no tom escolhido.
; 16 bits: RGB565 de (128,128,128).
; 24 bits: B, G, R (a ordem classica do VESA 24bpp).
; 32 bits: 0x00RRGGBB de (128,128,128).
COR8        equ 0x07
COR8_R      equ 32              ; vermelho 0-63 (128 * 63 / 255)
COR8_G      equ 32              ; verde    0-63 (128 * 63 / 255)
COR8_B      equ 32              ; azul     0-63 (128 * 63 / 255)
COR16       equ 0x8410          ; RGB565: 16 << 11 | 32 << 5 | 16
COR24_B     equ 0x80
COR24_G     equ 0x80
COR24_R     equ 0x80
COR32       equ 0x00808080

; ---------------------------------------------------------------------------
; A entrada da imagem (MENU_INI = 8) e chamada por CALL FAR, sempre, com um
; pedido em AL:
;
;   AL=1  via do arranque/reconstrucao: pinta o rectangulo do menu. E o barsup
;         que a usa, no arranque e sempre que a interface reconstroi o ecra
;         (botoes da barra de baixo): o rectangulo tem de voltar ao ecra.
;   AL=0  via do ciclo da bolinha (a interface chama a cada pedido do rato): NAO
;         se repinta o rectangulo - ele ja esta no ecra - e so se decide o
;         clique. Repintar aqui apagava a bolinha sempre que ela passasse por
;         cima do menu, e a interface nao sabia que lhe faltava o fundo (era o
;         sintoma de a bolinha desaparecer sobre o menu fechado).
;   AL=2  troca de painel vinda da interface: pinta so a metade cinzenta. A
;         interface reconstroi primeiro o ecra (o que fecha a metade branca) e
;         chama isto a seguir: o rectangulo ja voltou com a corrente e so falta
;         a metade. O clique que originou a troca ja foi consumido, por isso nao
;         se decide nada aqui.
;
; Se o clique abriu o painel, a metade cinzenta e pintada por esta imagem (e ela
; que desenha o painel) e devolve-se AL=1, para a interface voltar a assentar a
; bolinha; senao AL=0. Guarda todo o contexto que mexe - o DS e o ES sao
; trocados por dentro e o chamador espera-os de volta - e devolve por RETF. Os
; "pop" do fim nao tocam no AL, por isso o resultado sobrevive ate ao RETF.
; ---------------------------------------------------------------------------
menu:
    push ds
    push es
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ax                      ; guarda o pedido (AL) antes de mexer no AX

    ; --- DS = o nosso segmento (as variaveis sao locais) -------------------
    mov ax, SEG_IMG
    mov ds, ax
    pop ax                       ; AL = pedido: 1 repinta, 0 so decide o clique
    mov [cmd], al

    cmp byte [cmd], 0
    je  .clique                  ; ja ha rectangulo no ecra: nao se repinta

    mov byte [valido], 0

    ; --- esta imagem e mesmo o menu? ----------------------------------------
    ; E a propria imagem que se valida, e nao quem a chama: quem salta para uma
    ; imagem sem cabecalho saltaria para o meio do nada e o CPU executaria zeros
    ; sem dar conta. Sem assinatura nao se pinta o rectangulo, mas o controlo
    ; volta na mesma ao chamador (o ecra ja esta azul, com as barras).
    cmp dword [ASSIN], ASSINATURA
    jne  menu_invalido

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

    ; guards: sem geometria nao ha rectangulo para pintar; devolve-se o controlo
    ; ao chamador, que decide se ha bolinha a desenhar
    cmp word [byteslin], 0
    je  menu_invalido
    cmp word [altura], 0
    je  menu_invalido
    cmp word [largura], 0
    je  menu_invalido

    ; --- quantos bytes ocupa um pixel ---------------------------------------
    mov ax, [bpp]
    shr ax, 3                        ; 1, 2 ou 3; 4 nos 32 bits
    mov [bpp8], al

    ; --- pedido AL=2: pintar so a metade cinzenta ---------------------------
    ; Troca de painel vinda da interface: o ecra acabou de ser reconstruido pela
    ; corrente (o rectangulo ja esta pintado) e o que falta e abrir a metade. O
    ; pedido ja nasceu de um clique, por isso nao se decide clique nenhum aqui e
    ; nao se passa pelo tratar_botao - sem borda nova ele devolveria AL=0. Reusa-
    ; -se o pintar_metade, que calcula a metade a partir do contrato.
    cmp byte [cmd], 2
    jne .rectangulo
    call pintar_metade

    ; --- repor o valido que a entrada acima de pôs a zero --------------------
    ; O pedido 2 nao recalcule o rectangulo, mas os hit_* continuam validos: o
    ; pedido 1 da reconstrucao que precede sempre esta chamada acabou de os
    ; calcular (e o proprio pedido 2 acabou de conferir a assinatura e a
    ; geometria, logo acima). Sem repor o valido aqui a imagem ficava marcada
    ; como invalida, e todos os pedidos seguintes - os AL=0 do ciclo - caiam em
    ; menu_invalido: o rectangulo deixava de reagir a cliques depois de
    ; qualquer troca de painel ou de um "voltar" com o menu por baixo do branco.
    mov byte [valido], 1
    mov al, 1
    jmp menu_sai
.rectangulo:

    ; --- o tamanho do rectangulo -------------------------------------------
    ; O painel nunca passa de LARG_MENU x ALT_MENU, como as barras nunca passam
    ; de ALT_BARRA de altura: e uma medida que se le ao mesmo lado em qualquer
    ; ecra. Mas num ecra mais pequeno do que o painel o limite encolhe, senao o
    ; rectangulo saia do ecra. Por isso vale sempre a menor das duas medidas, o
    ; limite fixo ou metade do ecra:
    ;
    ;     1280x1024 -> 25 x 30 (o limite fixo, que e o menor dos dois)
    ;      320x200  -> 25 x 30 (o limite fixo, que e o menor dos dois)
    ;       40x60   -> 20 x 30 (a metade do ecra, que e menor)
    ;
    ; O "jbe" compara a metade do ecra com o limite fixo: se a metade ja for
    ; menor ou igual ao limite, e ela que fica; senao fica o limite.
    mov ax, [largura]
    shr ax, 1                        ; metade da largura do ecra
    cmp ax, LARG_MENU
    jbe .larg_ok
    mov ax, LARG_MENU
.larg_ok:
    mov [larg], ax

    mov ax, [altura]
    shr ax, 1                        ; metade da altura do ecra
    cmp ax, ALT_MENU
    jbe .alt_ok
    mov ax, ALT_MENU
.alt_ok:
    mov [alt], ax

    ; --- a coluna do canto esquerdo: encostado a margem direita ------------
    ; A ultima coluna do rectangulo e a ultima coluna do ecra: e por isso que se
    ; subtrai a largura do rectangulo a largura do ecra. Um ecra mais estreito
    ; do que o rectangulo comeca em zero - o "jae" salta por cima do "xor" quando
    ; a subtracao nao precisa de emprestimo.
    mov ax, [largura]
    sub ax, [larg]
    jae .x_pronto
    xor ax, ax
.x_pronto:
    mov [x0], ax

    ; --- a linha do canto de cima: centrado na vertical --------------------
    ; A sobra (altura - alt) fica dividida por dois: metade em cima e metade em
    ; baixo. A sobra impar perde o pixel para o lado de cima, que e o que o "shr"
    ; faz.
    mov ax, [altura]
    sub ax, [alt]
    jae .divide
    xor ax, ax                        ; ecra mais baixo que o rectangulo
    jmp .y_pronto
.divide:
    shr ax, 1
.y_pronto:
    mov [y0], ax

    ; --- guardar o rectangulo, para o teste do clique ----------------------
    ; O clique que abre o painel testa-se contra o rectangulo tal como ele foi
    ; desenhado (x0, y0, larg, alt). O painel cinzento mexe nestas mesmas
    ; variaveis ao pintar-se, por isso o rectangulo do menu fica guardado a
    ; parte no hit_*: a pintura do painel nunca o toca.
    mov ax, [x0]
    mov [hit_x0], ax
    mov ax, [y0]
    mov [hit_y0], ax
    mov ax, [larg]
    mov [hit_larg], ax
    mov ax, [alt]
    mov [hit_alt], ax

    ; --- quantas linhas se pintam ------------------------------------------
    ; A altura do rectangulo, ou as que faltam ate ao fim do ecra - o "minimo"
    ; das duas coisas. Sem este limite um rectangulo mais alto do que o ecra
    ; escrevia linhas abaixo da ultima do framebuffer.
    mov ax, [altura]
    sub ax, [y0]
    jae .cabe
    xor ax, ax
.cabe:
    cmp ax, [alt]
    jbe .linhas_ok
    mov ax, [alt]
.linhas_ok:
    mov [linhas], ax

    ; -- a partir daqui a imagem esta valida: o rectangulo esta calculado, os
    ;    hit_* guardados e as medidas prontas. O clique ja se pode decidir.
    mov byte [valido], 1

    ; --- escolher o formato pelo bits por pixel ----------------------------
    cmp byte [bpp8], 1
    je  .oito
    cmp byte [bpp8], 2
    je  .dezasseis
    cmp byte [bpp8], 3
    je  .vintequatro
    ; 32 bits (e qualquer valor desconhecido) cai no preenchimento por dword
    call pintar_dword
    jmp pintou

.oito:
    call por_paleta
    call pintar_byte
    jmp pintou
.dezasseis:
    call pintar_word
    jmp pintou
.vintequatro:
    call pintar_24

; ---------------------------------------------------------------------------
; clique: via do ciclo da bolinha (AL=0). Aqui nao se repinta nada - o
;   rectangulo ja esta no ecra desde o arranque ou desde a ultima
;   reconstrucao - e so se decide o clique. Sem imagem valida nao ha clique
;   para decidir: devolve-se AL=0.
; ---------------------------------------------------------------------------
.clique:
    cmp byte [valido], 0
    je  menu_invalido

; ---------------------------------------------------------------------------
; pintou: o rectangulo esta no ecra. Agora decide-se o clique (a metade
;   cinzenta) e devolve-se o controlo ao chamador. O barsup recebe-o e salta
;   para o face.grain; a interface recebe-o com o AL a dizer se o ecra mudou por
;   baixo da bolinha. Quando a imagem nao se valida nao ha nada para pintar nem
;   para decidir: devolve-se AL=0 e o ecra (ja azul, com as barras) fica como
;   esta. Os "pop" nao tocam no AL, por isso o resultado sobrevive ate ao RETF.
; ---------------------------------------------------------------------------
pintou:
    call tratar_botao
    jmp menu_sai

menu_invalido:
    xor al, al                    ; "nao mudei nada no ecra"
menu_sai:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop es
    pop ds
    retf

; ---------------------------------------------------------------------------
; por_paleta: poe a entrada COR8 da paleta no cinzento escolhido.
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
; inicio_linha: poe ES:DI no primeiro pixel da linha [k_linha] do rectangulo
;   O endereco de um pixel e fboff + y * bytes_por_linha + x * bytes_por_pixel, e
;   os dois produtos sao de 32 bits: num ecra grande uma linha ja passa do fim de
;   um segmento. Por isso o offset e separado em duas partes - a alta entra no
;   segmento, de 0x1000 em 0x1000, e a baixa fica no DI - em vez de se arriscar a
;   dar a volta dentro do segmento.
;
;   O "shl ax, 12" multiplica a parte alta por 0x1000, que e o que um segmento de
;   64 KiB vale. A parte alta so transbordaria o AX num framebuffer de mais de
;   4 GiB, coisa que nao cabe na memoria do QEMU.
; ---------------------------------------------------------------------------
inicio_linha:
    mov ax, [y0]
    add ax, [k_linha]                 ; y = y0 + k
    mov cx, [byteslin]
    mul cx                            ; DX:AX = y * bytes por linha
    add ax, [fboff]
    adc dx, 0                         ; DX:AX = fboff + y * bytes por linha
    mov [off_lo], ax                  ; guarda-se a soma: o CX do proximo "mul"
    mov [off_hi], dx                  ; precisa dele

    mov ax, [x0]
    xor cx, cx
    mov cl, [bpp8]                    ; CX = bytes por pixel (1, 2, 3 ou 4)
    mul cx                            ; DX:AX = x0 * bytes por pixel
    add ax, [off_lo]
    adc dx, 0
    mov bx, dx                        ; a parte alta e precisa depois do DI
    mov di, ax
    mov ax, bx
    shl ax, 12                        ; 0x1000 por cada 64 KiB de offset
    add ax, [fbseg]
    mov es, ax
    ret

; ---------------------------------------------------------------------------
; pintar_byte: [linhas] linhas de LARG_MENU pixels a cinzento, um byte por pixel
;   Uma linha do rectangulo sao [larg] bytes: nao se escreve a linha toda, como
;   quem enche o ecra, porque o rectangulo so ocupa as ultimas colunas.
; ---------------------------------------------------------------------------
pintar_byte:
    mov word [k_linha], 0
.linha:
    call inicio_linha
    mov al, COR8
    mov cx, [larg]
    cld
    rep stosb
    inc word [k_linha]
    mov ax, [linhas]
    cmp word [k_linha], ax
    jb  .linha
    ret

; ---------------------------------------------------------------------------
; pintar_word: 16 bits por pixel - dois bytes iguais por pixel nao chegam, porque
;   o valor da cor pode ter os dois bytes diferentes.
; ---------------------------------------------------------------------------
pintar_word:
    mov ax, COR16
    mov [cor], ax
    mov word [k_linha], 0
.linha:
    call inicio_linha
    mov cx, [larg]
    cld
    rep stosw
    inc word [k_linha]
    mov ax, [linhas]
    cmp word [k_linha], ax
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
    mov cx, [larg]
    cld
    rep stosd
    inc word [k_linha]
    mov ax, [linhas]
    cmp word [k_linha], ax
    jb  .linha
    ret

; ---------------------------------------------------------------------------
; pintar_24: 24 bits por pixel - nao ha rep stos de 3 bytes, por isso escreve-se
;   pixel a pixel (B, G, R), como nas barras.
; ---------------------------------------------------------------------------
pintar_24:
    mov word [k_linha], 0
.linha:
    call inicio_linha
    mov cx, [larg]
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
; tratar_botao: decide se o clique abre o painel cinzento.
;   O gatilho e a BORDA de descida do botao esquerdo (bit0 do MI_BOTAO): manter
;   o botao carregado nao repete a pintura, porque so a mudanca de 0 para 1
;   conta. O estado do pedido anterior guarda-se em botao_ant.
;   O teste e contra o rectangulo do menu (hit_*), nao contra a posicao ja
;   encostada da bolinha: e o que esta desenhado no ecra.
; ---------------------------------------------------------------------------
tratar_botao:
    mov ax, SEG_NUC
    mov es, ax
    mov al, [es:MOUSE_INFO + MI_BOTAO]
    mov bl, [botao_ant]
    mov [botao_ant], al

    test al, 1
    jz  .nada                     ; o esquerdo nao esta carregado
    test bl, 1
    jnz .nada                     ; ja estava carregado: nao ha borda

    mov cx, [es:MOUSE_INFO + MI_X]
    mov dx, [es:MOUSE_INFO + MI_Y]
    call dentro_do_menu
    jc  .nada                     ; fora do rectangulo

    call pintar_metade
    mov al, 1
    ret
.nada:
    xor al, al
    ret

; ---------------------------------------------------------------------------
; dentro_do_menu: o ponto (CX, DX) cai dentro do rectangulo do menu?
;   saida: CF=0 dentro, CF=1 fora. Um rectangulo e [x0, x0+larg) x [y0, y0+alt).
; ---------------------------------------------------------------------------
dentro_do_menu:
    cmp cx, [hit_x0]
    jb  .fora
    mov ax, [hit_x0]
    add ax, [hit_larg]
    cmp cx, ax
    jae .fora
    cmp dx, [hit_y0]
    jb  .fora
    mov ax, [hit_y0]
    add ax, [hit_alt]
    cmp dx, ax
    jae .fora
    clc
    ret
.fora:
    stc
    ret

; ---------------------------------------------------------------------------
; pintar_metade: pinta a metade direita da area de trabalho a cinzento.
;   E o "deixar a metade da area de trabalho pintada de cinza": x da metade da
;   largura ate a margem direita, y de uma barra a outra (ALT_BARRA em cima e
;   ALT_BARRA em baixo), para nao pisar as barras. Reaproveita as variaveis do
;   rectangulo - x0, y0, larg, linhas - que os pintores ja leem, e o mesmo
;   cinzento do rectangulo pequeno (COR8/COR16/...). O teste do clique usa o
;   hit_*, que nao se toca aqui.
;   O formato escolhe-se como no start: pelo bpp8.
; ---------------------------------------------------------------------------
pintar_metade:
    ; x0 = largura/2 (o pixel impar fica na metade direita)
    mov ax, [largura]
    shr ax, 1
    mov [x0], ax
    ; larg = largura - x0
    mov bx, [largura]
    sub bx, ax
    mov [larg], bx
    ; y0 = ALT_BARRA
    mov ax, ALT_BARRA
    mov [y0], ax
    ; linhas = altura - 2 * ALT_BARRA (0 se o ecra for mais baixo que as barras)
    mov ax, [altura]
    sub ax, ALT_BARRA
    sub ax, ALT_BARRA
    jae .linhas_ok
    xor ax, ax
.linhas_ok:
    mov [linhas], ax

    cmp byte [bpp8], 1
    je  .oito
    cmp byte [bpp8], 2
    je  .dezasseis
    cmp byte [bpp8], 3
    je  .vintequatro
    jmp pintar_dword
.oito:
    call por_paleta              ; garante o cinzento na entrada COR8
    jmp pintar_byte
.dezasseis:
    jmp pintar_word
.vintequatro:
    jmp pintar_24

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
larg:        dw 0              ; a largura do rectangulo
alt:         dw 0              ; a altura do rectangulo
x0:          dw 0              ; a coluna do canto esquerdo do rectangulo
y0:          dw 0              ; a linha do canto de cima do rectangulo
linhas:      dw 0              ; quantas linhas se pintam
k_linha:     dw 0              ; a linha que se esta a pintar
off_lo:      dw 0              ; parte baixa do offset do pixel
off_hi:      dw 0              ; parte alta do offset do pixel
cor:         dw 0
cor32:       dd 0
cmd:         db 0              ; pedido da chamada: 1 repinta, 0 so decide o clique
valido:      db 0              ; 1 depois de a imagem se validar e calcular o rectangulo
botao_ant:   db 0              ; botoes no pedido anterior (ver tratar_botao)
hit_x0:      dw 0              ; o rectangulo do menu, para o teste do clique
hit_y0:      dw 0
hit_larg:    dw 0
hit_alt:     dw 0
