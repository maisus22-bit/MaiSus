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
;          Acabado o azul, salta-se para a barra inferior (barinf.grain), que
;          pinta a base do ecra e salta para a barra superior (barsup.grain),
;          que pinta o topo e salta para o menu (menu.grain), que desenha o
;          rectangulo cinzento da margem direita e devolve o controlo a esta
;          imagem. As tres foram carregadas pelo inicio.mai.
;          De volta aqui, a interface ja esta pintada: entra-se no ciclo da
;          bolinha do rato - le-se a posicao que o handler do driver mantem na
;          MOUSE_INFO do nucleo e desenha-se (e apaga-se) a bolinha vermelha.
;          A bolinha so existe nesta interface: nos ecras de texto do nucleo
;          nao ha rato nenhum.
;
;  entrada: CS=IP=0x2000:0x0000, contrato VIDEO_INFO em 0xC00:0x0E00 e a posicao
;           do rato em 0xC00:MOUSE_INFO
;  saida: nada - a interface fica pintada e o CPU fica no ciclo da bolinha
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

; --- o contrato MOUSE_INFO (igual ao de nucleo.asm e drivers/mouse.asm) ------
; A posicao do ponteiro vive num sitio fixo do segmento do nucleo (MOUSE_INFO,
; logo depois da IMG_INFO) e e o handler do rato que a mantem, a partir da
; interrupcao. Esta interface so a le: quem escreve e o driver.
;
; Alem da posicao ha o estado dos botoes em MOUSE_INFO + MI_BOTAO (bit 0 =
; esquerdo, bit 1 = direito, bit 2 = meio). E na borda de descida do botao
; esquerdo dentro dos dois rectangulos da barra inferior (ver tratar_botoes)
; que a interface reconstroi o ecra inicial: a casa e a seta voltam ao mesmo
; sitio enquanto houver um ecra so; quando houver historico, a casa sera o
; "inicio" e a seta o "anterior", e e aqui, no ciclo da bolinha, que se decide
; o salto.
MI_X        equ 0x06
MI_Y        equ 0x08
MI_BOTAO    equ 0x0A
MOUSE_INFO  equ 0x1200

; --- a bolinha do rato ------------------------------------------------------
; A bolinha e um disco cheio de DOT_N x DOT_N pixels com o centro em (x,y). O
; raio (DOT_R) e a margem que a posicao guarda para o disco nunca sair do ecra.
; O que esta por baixo fica guardado em memoria (dois buffers, ver guarda_a),
; para se poder apagar a bolinha sem repintar o ecra todo. O desenho e por isso
; independente do que esta por baixo - azul, barra branca ou painel cinzento:
; a bolinha e uma sobreposicao, e passa por cima das barras como por cima de
; tudo o resto.
;
; A ORDEM das operacoes de um movimento e o que impede o ponteiro de piscar, e
; ela e esta (quem a escreveu primeiro trocou os dois primeiros passos e o
; ecra ficava sem bolinha nenhuma de cada vez que o rato se mexia):
;
;   1. novo_fundo  - constroi-se o fundo do sitio NOVO. O ecra nao se mexe e a
;                    bolinha velha continua inteira;
;   2. desenhar_dot - desenha-se a bolinha NOVA por cima. Ate aqui o ecra
;                    nunca ficou sem bolinha, e neste ponto ha ate duas;
;   3. apagar_restos - apaga-se so o que da bolinha velha nao faz parte da
;                    nova. A nova ja la esta, por isso nao se ve nada a
;                    desaparecer.
;
; Com a ordem antiga (apagar, guardar, desenhar) o ecra ficava com NENHUMA
; bolinha durante o passo 2 todo - a guarda do fundo novo e o desenho novo
; demoram mais do que um ecra inteiro de QEMU consegue varrer - e o rato a
; mexer-se e exactamente quando ha pacotes a abarrotar, o que fazia o CPU
; trocar de sitio a bolinha sem parar: o ecra era apanhado la pela metade e o
; ponteiro piscava. A ordem de cima nao tem nenhum instante em que o ecra fique
; sem bolinha, por mais depressa que os pacotes cheguem.
DOT_R       equ 3
DOT_N       equ DOT_R * 2 + 1   ; 7
DOT_PIX     equ DOT_N * DOT_N   ; 49 pixels

; ---------------------------------------------------------------------------
; As barras e o menu: /interface/barinf.grain, /interface/barsup.grain e
; /interface/menu.grain, que o inicio.mai carregou da ISO para BAR_SEG:0x0000,
; SUP_SEG:0x0000 e MEN_SEG:0x0000 (linear 0x30000, 0x40000 e 0x50000 - tres,
; quatro e cinco segmentos acima desta imagem).
;
; As barras trazem um cabecalho de 8 bytes - a assinatura BAR1 e a versao do
; desenho - e a entrada do codigo e depois dele, a BAR_INI = 8. A conta e a
; mesma que o nucleo faz com o driver (DRV_INI em nucleo.asm), por isso que os
; dois valores estao escritos a mao nos dois lados. O menu traz um cabecalho
; igual, com a assinatura MEN1.
;
; A corrente das quatro imagens e sempre a mesma:
;
;     face.grain (0x2000)  pinta o ecra de azul e salta para a barra inferior
;     barinf.grain (0x3000) pinta a base do ecra e salta para a de cima
;     barsup.grain (0x4000) pinta o topo do ecra e salta para o menu
;     menu.grain (0x5000)   pinta o rectangulo cinzento da margem direita e
;                           devolve o controlo ao face.grain (0x2000:0x0000)
;
; Cada imagem salta para a seguinte com um "jmp" longe, que nao devolve o
; controlo a ninguem excepto o menu, que fecha o ciclo saltando de volta para
; o principio do face.grain. Por isso cada uma precisa do seu segmento: uma
; imagem carregada por cima da que esta a correr estragava-a. Nenhuma fica
; parada; quem fica no CPU para sempre e o ciclo da bolinha, ja no face.grain.
;
; O salto nunca e condicionado a nada: quem valida cada imagem e a propria
; imagem, no primeiro instante em que arranca (cada uma le a sua assinatura e
; salta logo para a seguinte se ela faltar). Uma imagem em falta ou truncada
; custa-se a ela propria e nunca leva as outras ao ecra com ela - que e o que
; se quer das barras: aparecerem sempre, independentemente do caso.
; ---------------------------------------------------------------------------
SEG_BAR     equ 0x3000         ; segmento da barra inferior (linear 0x30000)
SEG_SUP     equ 0x4000         ; segmento da barra superior (linear 0x40000)
SEG_MEN     equ 0x5000         ; segmento do menu (linear 0x50000)
BAR_INI     equ 0x0008         ; entrada das barras: depois do cabecalho
MEN_INI     equ 0x0008         ; entrada do menu (menu.grain): depois do cabecalho
BAR_ASSIN   equ 0x31524142     ; 'B','A','R','1': assinatura do barsup.grain
BRANCO_INI  equ 0x0006         ; offset do cabecalho onde o barsup guarda a
                               ; entrada "branco" (nao e o mesmo que 0x0008)
; Os dois pedidos da entrada "branco" do barsup, tal como os do menu vao em AL.
; O barsup escreve-os a mao em barra_superior.asm (PEDIDO_PAINEL/PEDIDO_RELOGIO):
; nenhum dos lados calcula o valor do outro.
PEDIDO_PAINEL  equ 0           ; pinta a metade de cima a branco
PEDIDO_RELOGIO equ 1           ; acerta so o relogio da barra de cima

; --- os dois botoes da barra inferior ---------------------------------------
; A barra inferior (barra_inferrior.asm) desenha a casa centrada no quarto
; esquerdo do ecra e a seta no terceiro quarto, cada botao com LARG_CARIMBO x
; ALT_CARIMBO pixels e a (ALT_BARRA - ALT_CARIMBO) / 2 pixels do topo da barra.
; Estas medidas sao as mesmas de barra_inferrior.asm e estao escritas a mao nos
; dois lados, como a entrada do menu. O clique testa-se contra estes dois
; rectangulos (ver tratar_botoes), no ciclo da bolinha.
ALT_BARRA   equ 16              ; altura da barra inferior (igual a barra_inferrior.asm)
ALT_CARIMBO equ 12              ; altura dos icones dos botoes
LARG_CARIMBO equ 14             ; largura dos icones dos botoes

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

; --- o vermelho da bolinha, por formato de pixel ----------------------------
; O vermelho e (255,0,0), o mesmo tratamento do azul: em 8 bits reprograma-se a
; entrada COR8_RATO da paleta (a de omissao tem o 4 num vermelho escuro) e
; escreve-se o indice; nos outros formatos escreve-se o valor do pixel.
COR8_RATO   equ 0x04
COR8_RATO_R equ 63              ; vermelho 0-63 (255/255)
COR8_RATO_G equ 0
COR8_RATO_B equ 0
COR16_RATO  equ 0xF800          ; RGB565 de (255,0,0)
COR24_RATO_B equ 0x00
COR24_RATO_G equ 0x00
COR24_RATO_R equ 0xFF
COR32_RATO  equ 0x00FF0000      ; 0x00RRGGBB de (255,0,0)

start:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x7BFF
    sti

    ; --- DS = o nosso segmento (as variaveis sao locais) -------------------
    mov ax, SEG_IMG
    mov ds, ax

    ; --- a interface ja foi pintada? ---------------------------------------
    ; O menu.grain devolve o controlo a esta imagem (ver menu.asm): a segunda
    ; entrada nao pode repintar o ecra, por isso salta logo para o ciclo da
    ; bolinha. A bandeira vive na area de dados, que sobrevive as duas entradas.
    cmp byte [desenhado], 0
    jne ciclo

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

    ; o byte por pixel, que decide o desenho da bolinha: bpp / 8
    mov cl, 3
    shr ax, cl
    mov [bpp8], al

    mov es, [fbseg]
    mov di, [fboff]

    ; guards: sem geometria nao ha nada para pintar aqui, mas a corrente
    ; continua na mesma - as barras e o menu vao ler este mesmo contrato e nao
    ; paintam nada sem ele, e o menu devolve na mesma o controlo ao ciclo
    cmp word [byteslin], 0
    je  .barra
    cmp word [altura], 0
    je  .barra

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
    ; --- o ecra esta azul: entregar o controlo a barra inferior --------------
    ; A corrente nao tem conditions: salta-se para a barra inferior, que pinta a
    ; base do ecra e salta para a de cima; a de cima pinta o topo e salta para o
    ; menu, que pinta o rectangulo cinzento e devolve o controlo a esta imagem
    ; (0x2000:0x0000). Cada imagem valida a si propria quando arranca, pelo que
    ; uma delas faltar nao tira as outras ao ecra.
    ;
    ; O ".barra" e um rotulo de converencia, e nao uma linha solta depois do
    ; ".trintaedois": os quatro caminhos de pintura tem de cair aqui. Com o
    ; codigo a seguir-se ao ".trintaedois", so o modo de 32 bits chegava a esta
    ; parte - os outros tres passavam a_direita e a barra nunca era executada.
    ; Os guards caem aqui pelo mesmo motivo.
    ;
    ; As interrupcoes ficam ligadas antes da passagem: os "hlt" do ciclo da
    ; bolinha sao o estado final e com IF=0 um "hlt" parava o CPU para sempre
    ; (em modo real so o acorda um NMI).
    ;
    ; Antes de ceder o controlo, preparam-se os dois dados que o ciclo da
    ; bolinha vai precisar e que so agora se sabem: a cor vermelha no formato
    ; do modo, e a bandeira que diz que o ecra ja esta pintado. E a bandeira que
    ; faz a segunda entrada (quando o menu devolver o controlo) saltar directo
    ; ao ciclo, sem repintar nada.
    call preparar_cor_dot
    mov byte [desenhado], 1
    sti
    jmp SEG_BAR:BAR_INI

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

; --- estado da interface e da bolinha ---------------------------------------
desenhado:   db 0              ; 1 depois da interface pintada (ver start)
bpp8:        db 0              ; bytes por pixel (bpp / 8)
tem_dot:     db 0              ; 1 depois de a bolinha estar no ecra
painel_aberto: db 0            ; 1 depois de o menu abrir a metade cinzenta
painel_branco: db 0            ; 1 depois de a barra de cima abrir a metade branca
abrir_menu:  db 0              ; 1 = a troca de painel ja reconstruiu o ecra e o
                               ; ciclo seguinte abre a metade cinzenta (ver ciclo)
botao_barra: db 0              ; botoes da barra inferior no pedido anterior
botao_barra_sup: db 0          ; idem para a barra superior (ver tratar_barra_superior)
branco_ptr:  dd 0              ; ponteiro far para a entrada do painel branco
                               ; (barsup.grain), lido do cabecalho da imagem
                               ; (ver tratar_botoes)
cor_dot:     db 0, 0, 0, 0     ; o vermelho no formato do modo (ver preparar_cor_dot)
mx:          dw 0              ; centro da bolinha, coluna
my:          dw 0              ; centro da bolinha, linha
px:          dw 0              ; onde estava a bolinha antiga (para a repor)
py:          dw 0
k:           dw 0              ; indice corrente no buffer, em bytes
col_i:       dw 0              ; contadores dos ciclos (ver novo_fundo)
lin_i:       dw 0
drow:        dw 0              ; de quantas linhas o ponto novo esta mais baixo
                               ; que o velho: my - py
dcol:        dw 0              ; de quantas colunas esta mais a direita: mx - px
dv:          dw 0              ; de quantos indices o ponto novo e diferente
                               ; do velho: drow * DOT_N + dcol
dv_bytes:    dw 0              ; o mesmo, ja em bytes (dv * bytes por pixel)
buf_velho:   dw guarda_a       ; o fundo de baixo do ponto que esta no ecra
buf_novo:    dw guarda_b       ; onde se constroi o do proximo movimento

; O que fica por baixo da bolinha, antes de a desenhar: 4 bytes no maximo por
; pixel, em todos os formatos (os de 8 e 16 bits usam menos e o resto fica a
; zero, o que nao faz mal porque so se repoe o que se guardou, byte a byte).
;
; Sao DOIS buffers e nao um pelo mesmo motivo da ordem do cabecalho: enquanto
; o novo_fundo constroi o fundo do sitio novo, o fundo do sitio velho ainda e
; preciso - e dele que vem os pixels em que os dois quadrados se sobrepoe - e
; nao pode ser tocado. Os dois trocam de papel em cada movimento (trocar_buf),
; por isso o buffer que foi escrito agora e o que se le na vez seguinte.
guarda_a:    times DOT_PIX * 4 db 0
guarda_b:    times DOT_PIX * 4 db 0

; A mascara do disco: 1 onde ha pixel da bolinha, 0 onde fica o fundo. Um disco
; cheio de 7x7 nao e mais do que a diagonal serrada nos cantos.
mascara:
    db 0, 0, 1, 1, 1, 0, 0
    db 0, 1, 1, 1, 1, 1, 0
    db 1, 1, 1, 1, 1, 1, 1
    db 1, 1, 1, 1, 1, 1, 1
    db 1, 1, 1, 1, 1, 1, 1
    db 0, 1, 1, 1, 1, 1, 0
    db 0, 0, 1, 1, 1, 0, 0

; ---------------------------------------------------------------------------
; ciclo: o ciclo da bolinha do rato
;   E aqui que a interface vive depois de pintada. Le a posicao que o handler do
;   driver mantem na MOUSE_INFO do nucleo, e desenha a bolinha - guardando o
;   fundo, pondo-a e apagando so os restos por esta ordem (ver "a bolinha do
;   rato"). O "hlt" adormece o CPU ate ao proximo pedido: e a IRQ12 do rato
;   que o acorda, quando o ponteiro mexe. Se o ponteiro nao mexeu, nao se toca
;   no ecra - so se volta a dormir.
;
;   E a unica parte desta imagem que corre mais do que uma vez: a primeira
;   entrada (do nucleo) pinta o ecra e salta para a corrente; a segunda entrada
;   (do menu, que fecha a corrente) cai aqui pela bandeira "desenhado".
; ---------------------------------------------------------------------------
ciclo:
    mov ax, SEG_IMG
    mov ds, ax                    ; o menu pode ter deixado outro DS

    ; sem geometria nunca houve ecra para pintar: nao ha bolinha a desenhar
    cmp word [byteslin], 0
    je  .dorme
    cmp word [largura], 0
    je  .dorme
    cmp word [altura], 0
    je  .dorme

    call ler_mouse                ; mx, my = posicao limitada ao ecra

    ; --- o menu decide se o clique abre a metade cinzenta -------------------
    ; A interface nao sabe do painel: chama a entrada do menu.grain (CALL FAR)
    ; em cada pedido do rato e e o menu que decide, lendo ele mesmo a MOUSE_INFO.
    ; Devolve em AL se mexeu no ecra (1) ou nao (0). Se mexeu, o que fica por
    ; baixo da bolinha mudou - o painel foi pintado por cima dela - e o fundo
    ; guardado deixava de valer: poem-se tem_dot a zero para a bolinha ser
    ; re-assentada do zero no mesmo ciclo, sem nunca faltar um instante.
    ; O "CALL FAR" e a unica coisa que a interface faz por este painel.
    ; AL=0 e o pedido "via do ciclo": o menu NAO repinta o rectangulo (ele ja
    ; esta no ecra) e limita-se a decidir o clique. Repinta-lo aqui apagaria a
    ; bolinha sempre que ela passasse por cima do menu, e a interface nao sabia
    ; que lhe faltava o fundo.
    ;
    ; O rectangulo so decide com a metade cinzenta FECHADA. Com ela aberta -
    ; com o branco por cima ou sem ele - o clique nao passa ao menu: nada de
    ; repintar a metade (um piscar sem mudar nada) nem de fechar o painel que
    ; estiver por cima. Fechar so se faz pela seta/casa ou pela barra de cima.
    ; O estado de "aberto" e desta imagem (painel_aberto) e nao do menu, por
    ; isso e aqui que o clique se descarta.
    cmp byte [abrir_menu], 0
    jne .abrir_menu
    cmp byte [painel_aberto], 0
    jne .sem_painel

    ; Com a metade branca aberta (e o menu FECHADO), um clique no rectangulo do
    ; menu troca de painel: fecha-se o branco e abre-se o cinzento. Nao chega
    ; chamar o menu e deixar a metade cinzenta por cima: ela so tapa a metade
    ; direita e o branco ficava a vista do lado esquerdo. Reconstroi-se o ecra
    ; (o branco desaparece de vez) com a bandeira abrir_menu; e o ciclo seguinte,
    ; ja com o ecra limpo, que abre a metade pelo pedido AL=2 - o clique ja foi
    ; consumido, por isso nao se pode voltar a pedi-lo como AL=0.
    cmp byte [painel_branco], 0
    jne .troca_painel
    xor al, al
    call SEG_MEN:MEN_INI
    test al, al
    jz  .sem_painel
    mov byte [tem_dot], 0
    mov byte [painel_aberto], 1   ; o menu abriu a metade: ha por onde voltar
    jmp .sem_painel

.troca_painel:
    ; o menu decide o clique; se abriu a metade, reconstroi-se o ecra para o
    ; branco desaparecer e o ciclo seguinte abre-a outra vez (ver .abrir_menu)
    ;
    ; Com o branco aberto, o rectangulo do menu fechado fica em parte coberto
    ; pela metade branca (o painel vai de y=0 a altura/2). A parte coberta nao
    ; e o menu - nao ha cinzento para clicar - por isso um clique ai nao abre
    ; nada; so a parte do rectangulo que ficou descoberta, abaixo do painel,
    ; decide o clique (o menu ja so aceita a sua propria area, por dentro).
    mov ax, [altura]
    shr ax, 1                      ; o fundo do painel branco e a metade de cima
    cmp [my], ax
    jb  .sem_painel                ; clique na parte coberta de branco: nada
    xor al, al
    call SEG_MEN:MEN_INI
    test al, al
    jz  .sem_painel
    mov byte [abrir_menu], 1
    mov byte [painel_branco], 0
    mov byte [tem_dot], 0
    mov byte [desenhado], 0        ; forca o start a repintar e a correr a corrente
    jmp start

.abrir_menu:
    ; a corrente acabou de reconstruir o ecra (o rectangulo esta pintado): abre-se
    ; so a metade cinzenta, pelo pedido AL=2
    mov byte [abrir_menu], 0
    mov byte [painel_aberto], 1
    mov byte [tem_dot], 0          ; o painel cobriu a bolinha: re-assenta-a
    mov al, 2
    call SEG_MEN:MEN_INI
.sem_painel:
    call tratar_botoes            ; os botoes da barra inferior reconstroem
    call tratar_barra_superior    ; a barra de cima abre/fecha a metade branca
    call chamar_relogio           ; acerta o relogio do canto direito do topo

    cmp byte [tem_dot], 0
    jne .ja_tem
    ; ainda nao ha bolinha: o ecra esta limpo, por isso todo o fundo vem do
    ; ecra. O dcol a DOT_N e o que faz todos os pixels cairem fora do
    ; "quadrado velho" - que nao existe - e le o novo_fundo todo pelo caminho
    ; do ecra em vez do buffer velho.
    mov word [dcol], DOT_N
    mov word [dv], DOT_PIX
    mov word [dv_bytes], DOT_PIX * 4
    call novo_fundo              ; guarda o fundo do sitio onde vai ficar
    call desenhar_dot            ; desenha-la (nao havia la nada a apagar)
    call trocar_buf              ; o fundo guardado passa a ser o actual
    mov byte [tem_dot], 1
    jmp .guardar_pos

.ja_tem:
    ; se a posicao nao mudou, nao se toca no ecra
    mov ax, [mx]
    cmp ax, [px]
    jne .mexeu
    mov ax, [my]
    cmp ax, [py]
    jne .mexeu
    jmp .espera

.mexeu:
    ; --- onde e que o ponto novo fica em relacao ao velho -------------------
    ; drow = my - py e dcol = mx - px dizem o deslocamento do disco, e sao os
    ; dois numeros com que se decide - dentro do novo_fundo e do apagar_restos
    ; - se um pixel cai dentro do quadrado do outro lado. Tem de ser calculado
    ; AGORA, antes de .guardar_pos por o px e o py a dizerem o mesmo que o mx
    ; e o my.
    ;
    ; dv e a mesma conta em indices (drow * DOT_N + dcol), mas so serve para
    ; deslocar dentro dos buffers: la os dois quadrados estam alinhados e o
    ; indice do pixel e linear. NAO serve para saber se um pixel pertence ao
    ; outro quadrado, porque um indice so identifica um pixel DENTRO do
    ; quadrado - um pixel de fora tem um indice que se confunde com o de
    ; outro (row * DOT_N + col com col negativo da o mesmo que a linha acima,
    ; e a faixa [0, DOT_PIX) nao o apanha). Por isso a pertenca e testada
    ; coordenada a coordenada, com drow e dcol: e exacto em todas as direccoes.
    ;
    ; A conta do dv vai por "*8 menos uma vez" em vez de um multiplicar: o
    ; produto e no maximo (altura * DOT_N + largura), que cabe nos 16 bits com
    ; folga (1024 * 7 + 1280 e pouco), e um SHL de tres e tres instrucoes.
    mov ax, [my]
    sub ax, [py]
    mov [drow], ax              ; drow = my - py
    mov bx, ax
    shl ax, 1
    shl ax, 1
    shl ax, 1                   ; (my - py) * 8
    sub ax, bx                  ; menos uma vez = * 7 = * DOT_N
    mov bx, [mx]
    sub bx, [px]
    mov [dcol], bx              ; dcol = mx - px
    add ax, bx                  ; dv = drow * DOT_N + dcol
    mov [dv], ax

    ; o mesmo ja em bytes, porque e assim que os dois buffers se leem: cada
    ; pixel de buffer ocupa [bpp8] bytes. O "imul" de um operando (DX:AX =
    ; AX * CX, com sinal) e do 8086 - os de dois e tres operandos e que nao sao.
    xor cx, cx
    mov cl, [bpp8]
    mov ax, [dv]
    imul cx
    mov [dv_bytes], ax

    ; --- a troca, por esta ordem (a razao esta no cabecalho da bolinha) -----
    call novo_fundo              ; 1. o fundo do sitio novo, sem mexer no ecra
    call desenhar_dot            ; 2. a bolinha nova por cima: ate aqui nunca
                                 ;    houve um instante sem bolinha nenhuma
    call apagar_restos           ; 3. so agora se apaga o que da velha sobrou
    call trocar_buf              ; 4. o fundo novo passa a ser o actual

.guardar_pos:
    mov ax, [mx]
    mov [px], ax
    mov ax, [my]
    mov [py], ax

.espera:
    sti
    hlt
    jmp ciclo

.dorme:
    sti
    hlt
    jmp .dorme

; ---------------------------------------------------------------------------
; ler_mouse: le a posicao do ponteiro da MOUSE_INFO e encosta-a ao ecra
;   entrada: nada
;   saida:   mx, my preenchidos
;
;   A posicao tem de ficar a DOT_R pixels da borda para o disco (que tem
;   DOT_R pixels de raio) nunca sair do framebuffer. O handler do driver ja
;   limita ao ecra; esta segunda limites e o que impede o disco de sair pela
;   margem. A bolinha e uma sobreposicao e passa por cima das barras: este
;   limite e o do ecra todo, nao o da area de trabalho. Nao se limita pela
;   falta de driver: a MOUSE_INFO esta no centro, o que ja e uma posicao
;   valida, e a bolinha aparece parada.
; ---------------------------------------------------------------------------
ler_mouse:
    mov ax, SEG_NUC
    mov es, ax

    ; --- coluna -------------------------------------------------------------
    mov ax, [es:MOUSE_INFO + MI_X]
    cmp ax, DOT_R
    jae .x_min
    mov ax, DOT_R
.x_min:
    ; O disco tem (2 * DOT_R + 1) pixels. Com o centro a largura - DOT_R, o
    ; pixel da direita cai na coluna largura, a PRIMEIRA fora da linha - e como
    ; o framebuffer e uma faixa linear de 320 pixels, escrever ai e escrever na
    ; coluna 0 da linha seguinte: uma parte do disco aparecia do lado esquerdo.
    ; A coluna maxima do centro e largura - 1 - DOT_R, e a linha dos quadrados
    ; do disco cabe em [0, largura).
    mov cx, [largura]
    sub cx, DOT_R
    dec cx
    jae .x_max
    mov cx, DOT_R
.x_max:
    cmp ax, cx
    jbe .x_ok
    mov ax, cx
.x_ok:
    mov [mx], ax

    ; --- linha --------------------------------------------------------------
    mov ax, [es:MOUSE_INFO + MI_Y]
    cmp ax, DOT_R
    jae .y_min
    mov ax, DOT_R
.y_min:
    ; o mesmo para a linha: o pixel de baixo do disco nao pode sair pela
    ; ultima linha (altura - 1); o centro maximo e altura - 1 - DOT_R.
    mov cx, [altura]
    sub cx, DOT_R
    dec cx
    jae .y_max
    mov cx, DOT_R
.y_max:
    cmp ax, cx
    jbe .y_ok
    mov ax, cx
.y_ok:
    mov [my], ax
    ret

; ---------------------------------------------------------------------------
; tratar_botoes: os dois botoes da barra inferior reconstroem o ecra inicial.
;   A barra inferior desenha a casa no quarto esquerdo e a seta no terceiro
;   quarto (ver barra_inferrior.asm). Aqui testa-se o clique contra os dois
;   rectangulos, pela BORDA de descida do botao esquerdo - manter o botao
;   carregado nao repete nada, so a mudanca de 0 para 1 conta.
;
;   Os dois botoes nao fazem o mesmo quando ha dois paineis abertos:
;   A casa e o "inicio": poem-se as bandeiras a zero e salta-se para o start,
;   que repinta o azul e volta a correr a corrente (barras e menu) - fecha tudo.
;   A seta e o "voltar": fecha so o painel de cima. Com a metade branca aberta
;   por cima do menu, o menu fica (ver .voltar); nos outros casos tambem volta ao
;   inicio, e por isso a casa serve tambem aos dois quando ha um ecra so.
;   E isso que fecha os paineis abertos - eles so existem depois de abertos, e
;   sem painel aberto nao ha nada para voltar, por isso o teste a painel_aberto
;   e a painel_branco.
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
tratar_botoes:
    mov ax, SEG_NUC
    mov es, ax
    mov al, [es:MOUSE_INFO + MI_BOTAO]
    mov bl, [botao_barra]
    mov [botao_barra], al
    test al, 1
    jz  .fim                       ; o esquerdo nao esta carregado
    test bl, 1
    jnz .fim                       ; ja estava carregado: nao ha borda
    cmp byte [painel_aberto], 0
    jne .pode
    cmp byte [painel_branco], 0
    je  .fim                       ; nada aberto para voltar
.pode:

    ; --- casa: centrada no quarto esquerdo ---------------------------------
    mov ax, [largura]
    shr ax, 2
    sub ax, LARG_CARIMBO / 2
    jb  .seta
    mov bx, ax
    call dentro_do_botao
    jnc .casa

.seta:
    ; --- seta: centrada no terceiro quarto ---------------------------------
    mov ax, [largura]
    mov bx, 3
    mul bx                         ; DX:AX = 3 * largura
    shr ax, 2                      ; (3 * largura) / 4
    sub ax, LARG_CARIMBO / 2
    jb  .fim
    mov bx, ax
    call dentro_do_botao
    jnc .voltar
.fim:
    ret

.voltar:
    ; --- seta: "voltar", fecha so o painel de cima -------------------------
    ; Com a metade branca aberta por cima do menu, fecha-se so o branco e o menu
    ; fica (a bandeira abrir_menu reabre-o depois de reconstruir o ecra). Nos
    ; outros casos - so o menu, ou so o branco - tambem volta ao inicio.
    cmp byte [painel_branco], 0
    je  .casa
    cmp byte [painel_aberto], 0
    je  .casa
    mov byte [abrir_menu], 1
    mov byte [painel_branco], 0
    mov byte [tem_dot], 0
    mov byte [desenhado], 0
    jmp start

.casa:
    ; --- casa: "inicio", fecha os dois paineis -----------------------------
    mov byte [painel_aberto], 0
    mov byte [painel_branco], 0
    mov byte [tem_dot], 0          ; o ecra vai ser repintado: nao ha bolinha
    mov byte [desenhado], 0        ; forca o start a repintar e a correr a corrente
    jmp start

; ---------------------------------------------------------------------------
; tratar_barra_superior: um clique em qualquer ponto da barra de cima abre a
;   metade branca; um segundo clique na barra fecha-a e volta ao ecra inicial.
;
;   A metade branca e desenhada pelo barsup.grain (e ele que e dono da barra),
;   tal como a metade cinzenta e do menu.grain; aqui so se decide o clique e se
;   chama a entrada "branco" da imagem. O deslocamento dessa entrada vai no
;   cabecalho do barsup (0x4000:0006), para nao haver um numero magico escrito
;   a mao nos dois lados.
;
;   Qualquer clique na barra de cima abre a metade branca, mesmo com a metade
;   cinzenta ja aberta: nesse caso o branco fica por cima do menu, e e a seta
;   ("voltar") que fecha so o branco e deixa o menu - ver tratar_botoes. Um
;   clique na barra com o branco aberto fecha-o (se o menu estiver por baixo, o
;   menu fica; sem menu, volta ao inicio).
;
;   Fechar e reconstruir o ecra: poem-se a bandeira branca a zero e salta-se
;   para o start, que repinta o ecra e corre outra vez a corrente. Se o menu
;   estiver aberto por baixo, marca-se abrir_menu para o menu voltar ao ecra
;   depois da reconstrucao (ver ciclo, .abrir_menu).
; ---------------------------------------------------------------------------
tratar_barra_superior:
    mov ax, SEG_NUC
    mov es, ax
    mov al, [es:MOUSE_INFO + MI_BOTAO]
    mov bl, [botao_barra_sup]
    mov [botao_barra_sup], al
    test al, 1
    jz  .fim                       ; o esquerdo nao esta carregado
    test bl, 1
    jnz .fim                       ; ja estava carregado: nao ha borda
    mov ax, [my]
    cmp ax, ALT_BARRA
    jae .fim                       ; o clique caiu fora da barra de cima

    cmp byte [painel_branco], 0
    jne .fechar

    ; --- abrir: o barsup pinta a metade branca -----------------------------
    ; A assinatura e conferida antes de se acreditar no deslocamento: sem o
    ; barsup carregado aquele dword nao e 'BAR1' e chamar o que la estivesse
    ; seria um salto para o nada.
    mov ax, SEG_SUP
    mov es, ax
    cmp dword [es:0], BAR_ASSIN
    jne .fim
    mov ax, [es:BRANCO_INI]
    mov [branco_ptr], ax
    mov ax, SEG_SUP
    mov [branco_ptr + 2], ax
    mov al, PEDIDO_PAINEL         ; o pedido que pinta a metade branca
    call far [branco_ptr]
    mov byte [painel_branco], 1
    mov byte [tem_dot], 0          ; o painel cobriu a bolinha: re-assenta
    ret

.fechar:
    ; fecha a metade branca. Se o menu estiver aberto por baixo, ele fica: a
    ; bandeira abrir_menu reabre-o depois de a corrente reconstruir o ecra.
    cmp byte [painel_aberto], 0
    je  .sem_menu
    mov byte [abrir_menu], 1
.sem_menu:
    mov byte [painel_branco], 0
    mov byte [tem_dot], 0
    mov byte [desenhado], 0
    jmp start
.fim:
    ret

; ---------------------------------------------------------------------------
; chamar_relogio: pede ao barsup para acertar o relogio do canto direito da
;   barra de cima.
;
;   O relogio vive na barra branca, e a barra e do barsup (tal como a metade
;   cinzenta e do menu): aqui so se entrega o pedido, com CALL FAR, e o barsup e
;   que le o RTC e desenha. O pedido vai em AL, como o do menu, e e o barsup que
;   decide se ha algo a fazer - so redesenha quando a hora muda e nunca por cima
;   da bolinha (ver barra_superior.asm).
;
;   Como esta chamada corre a cada volta do ciclo da bolinha, a assinatura do
;   barsup e conferida primeiro: sem imagem carregada aquele dword nao e 'BAR1' e
;   chamar o que la estivesse seria um salto para o nada. O deslocamento vem do
;   cabecalho (BRANCO_INI), o mesmo sitio onde o tratar_barra_superior o vai
;   buscar para pintar o painel.
; ---------------------------------------------------------------------------
chamar_relogio:
    push es
    push ax
    mov ax, SEG_SUP
    mov es, ax
    cmp dword [es:0], BAR_ASSIN
    jne .fim
    mov ax, [es:BRANCO_INI]
    mov [branco_ptr], ax
    mov ax, SEG_SUP
    mov [branco_ptr + 2], ax
    mov al, PEDIDO_RELOGIO
    call far [branco_ptr]
.fim:
    pop ax
    pop es
    ret

; ---------------------------------------------------------------------------
; dentro_do_botao: o centro da bolinha (mx,my) cai dentro do rectangulo de um
;   botao? BX = coluna esquerda; a linha e a mesma para os dois botoes (estao a
;   mesma altura). saida: CF=0 dentro, CF=1 fora.
;   O topo e altura - ALT_BARRA + (ALT_BARRA - ALT_CARIMBO) / 2, que e a conta
;   de barra_inferrior.asm: o icone fica centrado na altura da barra.
; ---------------------------------------------------------------------------
dentro_do_botao:
    cmp [mx], bx
    jb  .fora
    mov ax, bx
    add ax, LARG_CARIMBO
    cmp [mx], ax
    jae .fora
    mov ax, [altura]
    sub ax, ALT_BARRA - (ALT_BARRA - ALT_CARIMBO) / 2
    cmp [my], ax
    jb  .fora
    add ax, ALT_CARIMBO
    cmp [my], ax
    jae .fora
    clc
    ret
.fora:
    stc
    ret

; ---------------------------------------------------------------------------
; preparar_cor_dot: decide o vermelho da bolinha no formato do modo e guarda
;   em cor_dot os bytes que desenhar_dot vai copiar. E o mesmo bpp8 que decide
;   o formato do azul, por isso os dois desenhos falam sempre a mesma lingua.
; ---------------------------------------------------------------------------
preparar_cor_dot:
    cmp byte [bpp8], 1
    je  .oito
    cmp byte [bpp8], 2
    je  .dezasseis
    cmp byte [bpp8], 3
    je  .vintequatro
    mov dword [cor_dot], COR32_RATO
    ret
.oito:
    call por_paleta_rato
    mov byte [cor_dot], COR8_RATO
    ret
.dezasseis:
    mov word [cor_dot], COR16_RATO
    ret
.vintequatro:
    mov byte [cor_dot], COR24_RATO_B
    mov byte [cor_dot + 1], COR24_RATO_G
    mov byte [cor_dot + 2], COR24_RATO_R
    ret

; ---------------------------------------------------------------------------
; por_paleta_rato: poe a entrada COR8_RATO da paleta no vermelho cheio.
;   Mesma via do azul (RAMDAC em 0x3C8/0x3C9), pela razao explicada em
;   por_paleta. O indice 4 e usado so pela bolinha.
; ---------------------------------------------------------------------------
por_paleta_rato:
    push ax
    push dx
    mov dx, 0x3C8
    mov al, COR8_RATO
    out dx, al
    inc dx
    mov al, COR8_RATO_R
    out dx, al
    mov al, COR8_RATO_G
    out dx, al
    mov al, COR8_RATO_B
    out dx, al
    pop dx
    pop ax
    ret

; ---------------------------------------------------------------------------
; end_pixel: calcula ES:DI do pixel (BX = coluna, SI = linha) no framebuffer
;   entrada: BX = coluna, SI = linha
;   saida:   ES:DI = o pixel
;
;   A conta e a mesma do preenchimento: linear = y * byteslin + x * bpp8
;   (mais o fboff), um produto de 16x16 bits que pode chegar a 24 bits (um ecra
;   de varios MiB). O deslocamento alto vira parte do segmento (cada 0x1000 no
;   offset alto vale 0x1000 de segmento), como faz o pintar_byte quando o DI da
;   a volta. O fboff e somado antes de dividir, para nao perder o transporte.
; ---------------------------------------------------------------------------
end_pixel:
    push ax
    push bx
    push cx
    push dx
    push si
    push bp

    ; --- y * byteslin -------------------------------------------------------
    mov ax, si
    mov cx, [byteslin]
    mul cx                        ; DX:AX
    mov si, ax                    ; parte baixa
    mov bp, dx                    ; parte alta

    ; --- x * bpp8 -----------------------------------------------------------
    mov ax, bx
    xor cx, cx
    mov cl, [bpp8]
    mul cx                        ; DX:AX
    add ax, si
    adc dx, bp
    add ax, [fboff]
    adc dx, 0

    mov di, ax                    ; o offset dentro do segmento
    shl dx, 12                    ; a parte alta, em unidades de segmento
    mov ax, [fbseg]
    add ax, dx
    mov es, ax

    pop bp
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; novo_fundo: guarda em [buf_novo] o que esta por baixo do ponto NOVO (mx,my)
;   entrada: nada
;   saida:   [buf_novo] com o fundo do quadrado novo, o ecra por mexer
;
;   A area e o quadrado que contem o disco, DOT_N x DOT_N, e copia-se todo,
;   mesmo o que a mascara nao pinta: e mais simples e a reposicao fica igual.
;
;   Os pixels do quadrado novo tem duas proveniencias, e o deslocamento e o
;   que as separa: os que caem DENTRO do quadrado velho nao estao limpos no
;   ecra (la esta a bolinha velha por cima deles), por isso vem do buf_velho -
;   o fundo deles esta la, guardado no movimento anterior. Os que caem FORA
;   estao limpos: nunca houve la nada desenhado, e vem directamente do ecra.
;
;   A prova de "dentro ou fora" e feita coordenada a coordenada: a coluna que
;   o pixel teria no quadrado velho e col_i + dcol, a linha e lin_i + drow, e
;   as duas tem de caber em [0, DOT_N). O "cmp" sem sinal apanha tambem os
;   negativos - ficam por cima de DOT_N e caem no mesmo "jae" - por isso nao
;   ha casos especiais.
;
;   Nao se faz a prova pelo indice (i + dv em [0, DOT_PIX)), que e mais
;   curta: um indice so identifica o pixel DENTRO do quadrado, e o de um
;   pixel de fora confunde-se com o de outro, porque a dobradica da coluna
;   faz row * DOT_N + col com col negativo dar o mesmo que a linha acima.
;   Com a pertenca ja sabida e que i + dv da la dentro o indice certo.
;
;   Nao se escreve no ecra: esta rotina so le. E por isso que ela pode correr
;   antes do desenhar_dot sem que o ecra fique um instante sem bolinha.
; ---------------------------------------------------------------------------
novo_fundo:
    mov word [k], 0
    mov word [lin_i], 0
.g_linha:
    mov word [col_i], 0
.g_col:
    ; --- o indice do pixel no quadrado NOVO --------------------------------
    mov ax, [lin_i]
    mov cx, DOT_N
    mul cx                        ; DX:AX = lin_i * DOT_N
    add ax, [col_i]               ; i

    ; --- o mesmo pixel de ecra esta dentro do quadrado VELHO? ---------------
    ; Testa-se linha a linha e nao pelo indice: o indice so identifica o pixel
    ; DENTRO do quadrado, e aqui a pergunta e se o pixel cai la dentro. Com o
    ; deslocamento (dcol/drow) a conta e exacta em todas as direccoes, e o
    ; "cmp" sem sinal apanha os valores negativos - ficam la por cima de
    ; DOT_N e caem no mesmo "jae".
    mov bx, [col_i]
    add bx, [dcol]                ; coluna que o pixel teria no quadrado velho
    cmp bx, DOT_N
    jae .g_ecra                   ; fora pela coluna: o ecra esta limpo
    mov bx, [lin_i]
    add bx, [drow]                ; linha que o pixel teria no quadrado velho
    cmp bx, DOT_N
    jae .g_ecra                   ; fora pela linha: o ecra esta limpo

    ; --- caminho do buffer: a origem e o buf_velho na posicao antiga --------
    ; O dv_bytes ja vem multiplicado pelos bytes por pixel, por isso
    ; buf_velho + k + dv_bytes e buf_velho + (i + dv) * bpp8 - e o pixel
    ; certo, porque com a pertenca provada acima i + dv e exactamente o
    ; indice desse pixel no quadrado velho.
    mov si, [buf_velho]
    add si, [k]
    add si, [dv_bytes]
    mov di, [buf_novo]            ; destino, dentro do proprio segmento
    add di, [k]
    mov cl, [bpp8]
.g_de_buf:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    dec cl
    jnz .g_de_buf
    jmp .g_fim

.g_ecra:
    ; --- caminho do ecra: ES:DI e o pixel, buf_novo + k e o destino ---------
    mov bx, [mx]
    sub bx, DOT_R
    add bx, [col_i]
    mov si, [my]
    sub si, DOT_R
    add si, [lin_i]
    call end_pixel                ; ES:DI (por BX e SI, como ele pede)
    mov si, [buf_novo]
    add si, [k]
    mov cl, [bpp8]
.g_do_ecra:
    mov al, [es:di]               ; do ecra...
    mov [si], al                  ; ...para o buffer
    inc di
    inc si
    dec cl
    jnz .g_do_ecra

.g_fim:
    xor ax, ax
    mov al, [bpp8]
    add [k], ax
    inc word [col_i]
    cmp word [col_i], DOT_N
    jb  .g_col
    inc word [lin_i]
    cmp word [lin_i], DOT_N
    jb  .g_linha
    ret

; ---------------------------------------------------------------------------
; apagar_restos: apaga do ponto VELHO (px,py) so o que nao faz parte do novo
;   entrada: nada
;   saida:   o ecra com a bolinha nova intacta e sem os restos da velha
;
;   E o passo 3 da ordem do cabecalho: a bolinha nova ja esta desenhada, por
;   isso apagar-se aqui nao se ve nada a desaparecer - o ecra passa de "duas
;   bolinhas" para "uma" sem ter ficado um instante sem nenhuma.
;
;   So se toca num pixel se ele estava vermelho (a mascara velha marca-lo) e se
;   nao passou a fazer parte da bolinha nova (a mascara nova nao o marcar). O
;   fundo de cada pixel vem do buf_velho, que ainda guarda o sitio todo.
;
;   A pertenca a bolinha nova testa-se coordenada a coordenada, como no
;   novo_fundo: col_i - dcol e lin_i - drow tem de caber em [0, DOT_N) - e
;   so la dentro que o indice j - dv identifica o pixel no quadrado novo.
;   Fora disso o pixel sobrou da velha e apaga-se.
; ---------------------------------------------------------------------------
apagar_restos:
    mov word [k], 0
    mov word [lin_i], 0
.r_linha:
    mov word [col_i], 0
.r_col:
    ; --- este pixel estava vermelho? ---------------------------------------
    ; O indice so serve para ler a mascara velha - e dentro do quadrado velho
    ; que ele identifica o pixel, que e de onde este vem.
    mov ax, [lin_i]
    mov cx, DOT_N
    mul cx
    add ax, [col_i]               ; j
    mov si, mascara
    add si, ax
    cmp byte [si], 0
    je  .r_pula                   ; a mascara velha nao o pintou: o ecra ja la
                                  ; tem fundo, nao ha nada que apagar

    ; --- o mesmo pixel pertence a bolinha nova? ----------------------------
    ; Linha e coluna, e nao pelo indice - ver a nota equivalente do
    ; novo_fundo: um indice so identifica o pixel DENTRO do quadrado, e aqui a
    ; pergunta e se ele cai la dentro. A coordenada que o pixel teria no
    ; quadrado novo e col_i - dcol / lin_i - drow, e o "cmp" sem sinal apanha
    ; os negativos - ficam por cima de DOT_N e caem no mesmo "jae".
    mov bx, [col_i]
    sub bx, [dcol]
    cmp bx, DOT_N
    jae .r_apaga                  ; fora pela coluna: sobrou da velha
    mov bx, [lin_i]
    sub bx, [drow]
    cmp bx, DOT_N
    jae .r_apaga                  ; fora pela linha: sobrou da velha

    ; --- dentro: la o indice do pixel e mesmo j - dv ------------------------
    mov bx, ax                    ; j intacto (a mascara so gastou SI)
    sub bx, [dv]
    mov si, mascara
    add si, bx
    cmp byte [si], 0
    jne .r_pula                   ; faz parte da nova: deixa-lo vermelho

.r_apaga:
    ; --- o endereco do pixel no ecra, no quadrado VELHO (px,py) ------------
    mov bx, [px]
    sub bx, DOT_R
    add bx, [col_i]
    mov si, [py]
    sub si, DOT_R
    add si, [lin_i]
    call end_pixel                ; ES:DI
    mov si, [buf_velho]
    add si, [k]
    mov cl, [bpp8]
.r_copia:
    mov al, [si]                  ; do buffer...
    mov [es:di], al               ; ...para o ecra
    inc si
    inc di
    dec cl
    jnz .r_copia
.r_pula:
    xor ax, ax
    mov al, [bpp8]
    add [k], ax
    inc word [col_i]
    cmp word [col_i], DOT_N
    jb  .r_col
    inc word [lin_i]
    cmp word [lin_i], DOT_N
    jb  .r_linha
    ret

; ---------------------------------------------------------------------------
; trocar_buf: o fundo que acabou de ser guardado passa a ser o actual
;   Depois disto [buf_velho] aponta para o que o novo_fundo escreveu e
;   [buf_novo] para o outro buffer, que fica livre para a vez seguinte. E o
;   que mantem os dois em dia: o fundo de baixo do ponto que esta no ecra
;   esta sempre no buf_velho, e o que se esta a constroir esta sempre no outro.
; ---------------------------------------------------------------------------
trocar_buf:
    mov ax, [buf_velho]
    mov bx, [buf_novo]
    mov [buf_velho], bx
    mov [buf_novo], ax
    ret

; ---------------------------------------------------------------------------
; desenhar_dot: escreve a bolinha (centro em mx,my) com os pixels de cor_dot
;   So se escrevem os pixels que a mascara marca: os outros ficam com o fundo
;   que o novo_fundo acabou de preservar.
; ---------------------------------------------------------------------------
desenhar_dot:
    mov word [lin_i], 0
.d_linha:
    mov word [col_i], 0
.d_col:
    ; mascara[lin_i * DOT_N + col_i]
    mov ax, [lin_i]
    mov cx, DOT_N
    mul cx
    add ax, [col_i]
    mov si, mascara
    add si, ax
    cmp byte [si], 0
    je  .d_pula
    mov bx, [mx]
    sub bx, DOT_R
    add bx, [col_i]
    mov si, [my]
    sub si, DOT_R
    add si, [lin_i]
    call end_pixel                ; ES:DI
    mov si, cor_dot
    mov cl, [bpp8]
.d_escreve:
    mov al, [si]
    mov [es:di], al
    inc si
    inc di
    dec cl
    jnz .d_escreve
.d_pula:
    inc word [col_i]
    cmp word [col_i], DOT_N
    jb  .d_col
    inc word [lin_i]
    cmp word [lin_i], DOT_N
    jb  .d_linha
    ret
