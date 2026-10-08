; ============================================================================
;  Maisus - recuperacao.asm
;  Recuperacao - recu.mai
;
;  Compilado para recu.mai e colocado em inicio/recu.mai dentro da ISO. O
;  inicio.mai carrega-o em REC_SEG:0x0000 e salta para a entrada depois de a
;  pessoa ter parado o relogio com uma seta e escolhido a segunda opcao do menu,
;  "Recuperacao" (a escolha e feita em espera_enter, no inicio.mai).
;
;  ATENCAO: esta imagem e o unico ramo do arranque que NAO vai a montante do
;  nucleo. Tudo o que o inicio.mai carrega a cadeia do arranque - o nucleo, os
;  dois drivers, a interface, as barras, o menu, o logo e o decodificador - ja
;  esta na memoria quando esta imagem arranca, porque a escolha acontece antes
;  da caminhada pela ISO e nao depois. Ver a nota do "o que esta imagem faz" e
;  a nota do inicio.mai sobre a ordem da escolha.
;
;  missao: ser o terminal de recuperacao. O desenho ja la esta (a linha de
;          titulo, o aviso do --ajuda--, o prompt ">" e o cursor a seguir) e o
;          que se junta agora e a leitura das teclas: o que se carrega no
;          teclado aparece depois do ">", o backspace apaga para tras e o enter
;          desce uma linha e poe outro ">". Nao ha comandos - o "--ajuda--" e
;          o resto vem no passo seguinte; por agora o terminal so escreve.
;  saida: nada - o CPU fica no laco do terminal (dorme, atende a tecla,
;         desenha) ate haver comandos para os quais existir uma saida
;
;  MODOS, E O PORQUE DESTE SER UM ECRA DE TEXTO E NAO UM COMO O RESTO
;  ---------------------------------------------------------------------------
;  A interface grafica (face.grain e as tres imagens que ele chama) pinta o
;  ecra com o driver de video, num modo VESA com framebuffer proprio. Este ecra
;  e de texto, e e o modo 80x25 do BIOS - o mesmo em que o inicio.mai escreve o
;  titulo e o menu, e em que a pessoa escolheu "Recuperacao" um instante antes.
;
;  Porque nao aproveitar o modo VESA: para usar o driver de video seria preciso
;  chamar o video.dr e encher o VIDEO_INFO do nucleo, e o nucleo e precisamente
;  a coisa que este ramo do arranque nao arranca. Um ecra de recuperacao que
;  precisa do nucleo para pintar-se nao sobrevive ao nucleo nao estar a correr -
;  que e o caso que faz sentido Recovery existir.
;
;  O driver de teclado e que nao tem esse problema: nao depende do nucleo, ja
;  esta na memoria quando esta imagem arranca (o inicio.mai carrega-o e liga-o
;  - CMD_INI - antes da contagem, e a escolha do menu vem depois) e e o proprio
;  inicio.mai que le as setas e o enter por ele. Por isso este ecra fala com o
;  driver e nao com a BIOS, exatamente como o inicio.mai: o handler da IRQ1 ja
;  esta instalado, o IF fica ligado, e quem vai buscar a tecla e o CMD_LER.
;  Ver iniciar_teclado e le_tecla, la em baixo.
;
;  Em texto, o ecra e o buffer em 0xB800 (VIDEO_BASE): 80 colunas x 25 linhas de
;  2 bytes, o primeiro o caracter e o segundo o atributo. E o mesmo contrato que
;  o inicio.mai escreve (celula e celula, ver a rotina celula em inicio.asm), e
;  nao ha modo nenhum para por nem driver nenhum para chamar: e a memoria.
;
;  O terminal nasce por partes, e a primeira parte e so o desenho: as tres
;  linhas e o cursor. A leitura de teclas e os comandos (--ajuda-- e os que
;  vierem a seguir) entram depois, por cima disto, sem ter de mexer no que ja
;  esta feito - escrever no buffer de texto e uma conta, ler do teclado e
;  outra, e as duas nao se estorvam.
; ============================================================================

BITS 16

; A imagem e carregada em REC_SEG:0x0000 (linear 0x9000, a ver REC_LIN no
; inicio.mai): o ORG=0 faz todos os rotulos valerem o deslocamento dentro da
; imagem, que e o que CS=REC_SEG espera. E o mesmo que as quatro imagens da
; interface fazem, e pelo mesmo motivo - os rotulos sao deslocamentos e nao
; enderecos absolutos.
ORG 0x0000

; O segmento onde esta imagem esta carregada. E o REC_SEG do inicio.mai: os dois
; numeros tem de concordar, e nenhum dos dois e o endereco LINEAR (0x9000) - o
; segmento e o linear dividido por 16 (0x9000 >> 4 = 0x0900). O inicio.mai e
; quem salta para ca, por isso o valor vive aqui como uma copia e a saida (o
; "jmp") e sempre escrito a partir de REC_SEG; o comentario da nota de la em
; cima explica porque e que os dois tem de ser o mesmo numero.
SEG_IMG     equ 0x0900         ; 0x9000 >> 4

; --- o ecra de texto ---------------------------------------------------------
; O buffer de texto do modo 80x25 vive em 0xB800 (o mesmo VIDEO_BASE que o
; inicio_minimo.asm e o inicio.asm usam). Cada celula sao 2 bytes: o caracter e
; o atributo. Sao 80 x 25 = 2000 celulas, portanto 4000 bytes a escrever para
; limpar o ecra inteiro.
VIDEO_BASE  equ 0xB800         ; o buffer de texto do modo 80x25
COLS        equ 80              ; colunas: uma linha e COLS celulas = COLS * 2 bytes
CELULAS     equ COLS * 25       ; quantas celulas o ecra tem
BYTES_CEL   equ 2             ; bytes por celula (caracter + atributo)

; --- as tres linhas do terminal -----------------------------------------------
; O ecra sao 25 linhas de COLS celulas, e cada linha comeca COLS * 2 bytes
; depois da anterior - a linha 0 e a primeira e a 24 e a ultima. E a mesma
; numeracao que o cursor usa (DH = a linha), por isso a linha do prompt e a
; linha do cursor sao a mesma conta escrita duas vezes.
LINHA_TITULO equ 0              ; "MaiSus Beta v0.1 Build ..."
LINHA_AJUDA  equ 1              ; "digite --ajuda-- para lista comandos ..."
LINHA_PROMPT equ 2              ; ">" - a linha onde vai ficar a escrita
LINHA_ULT    equ 24             ; a ultima das 25: abaixo dela ha de rolar

; --- o driver de teclado ------------------------------------------------------
; O contrato e o de drivers/teclado.asm, campo a campo, e e o mesmo que o
; inicio.asm (carregar_teclado e le_tecla) e o nucleo.asm falam: os numeros
; sao os tres ficheiros nao podem mudar sem mudar os outros, e agora sao
; QUATRO - este e o quarto a falar com o driver.
;
; O endereco e o do mapa da memoria (o TEC_LIN do inicio.asm): e la que o
; inicio.mai carrega o teclado.dr, e a imagem esta la inteira quando esta
; recuperacao arranca - a escolha do menu e feita antes da caminhada pela ISO,
; por isso nada disto volta a ser carregado aqui.
TEC_LIN     equ 0x60000         ; onde o inicio.mai poe o driver
TEC_SEG     equ TEC_LIN >> 4    ; 0x6000 - o segmento do driver
TEC_INI     equ 8               ; a entrada dele (depois do cabecalho de 8)
TEC_ASSIN   equ 0x31434554      ; 'T','E','C','1' por ordem de bytes
TEC_VERSAO  equ 2               ; a versao do contrato que este sector fala
TEC_CMD_INI equ 0               ; instalar o handler e ligar o teclado
TEC_CMD_LER equ 1               ; tirar a proxima tecla do buffer

; A estrutura que o driver escreve (os mesmos TEC_I_* do inicio.asm):
TEC_I_ASSIN  equ 0x00           ; a assinatura, que o driver confirma
TEC_I_VERSAO equ 0x04           ; a versao: 0xFFFF ate o driver a escrever
TEC_I_FLAGS  equ 0x06           ; bit 0: o driver ainda tem teclas no buffer
TEC_I_ESTADO equ 0x08           ; o registo de estado lido em 0x64 (CMD_INI)
TEC_I_TECLA  equ 0x09           ; o scancode da ultima tecla lida (CMD_LER)
TEC_I_PREF   equ 0x0A           ; o prefixo dela: 0 normal, 0xE0 alargada
TEC_I_MODS   equ 0x0B           ; os modificadores (shift, ctrl, alt)

MOD_SHIFT   equ 0x01            ; o bit do shift no TEC_I_MODS (e nos mods la)

; As teclas que nao passam pela tabela, porque tem tratamento proprio. Sao os
; scancodes, os mesmos que o driver devolve em TEC_I_TECLA.
TEC_ENTER   equ 0x1C            ; enter (o do teclado numerico e o mesmo, E0 1C)
TEC_BACK    equ 0x0E            ; backspace

; O atributo das celulas vazias, que e tambem a cor de todo o texto que esta
; imagem escreve (o ATRIB, la em baixo). Nao e uma questao estetica: e o que
; decide se o cursor se ve.
;
; O cursor de texto nao tem cor propria. O controlador de video desenha-o na
; cor de frente do atributo da celula onde ele esta - e nao numa cor que se possa
; escolher por aparte. Uma celula com atributo 0x00 (preto sobre preto) tem a
; cor de frente preta, portanto o cursor e desenhado preto sobre um fundo preto:
; existe, esta na posicao certa, e nao se ve. Foi o que aconteceu da primeira
; vez que esta imagem foi escrita, e o ecra ficava preto sem cursor nenhum - o
; registo do CRTC estava correcto (a forma e a posicao, como se ve na nota do
; cursor) e mesmo assim nao aparecia nada.
;
; Por isso o atributo tem de ser uma cor de frente que se veja: o cursor herda a
; cor de frente da celula onde esta. O fundo continua a ser preto, e o ecra
; continua a ser um ecra preto - um caracter vazio (o espaco, que e o que o
; limpar do ecra la em baixo la poe) nao desenha nada com atributo nenhum. O que
; muda e a cor de frente da celula, que so se ve no cursor - que era a unica
; coisa que este ecra tinha para mostrar, antes das tres linhas.
;
; E e a mesma cor do inicio.mai, que escreve o titulo e o menu dele com o
; 0x0E: amarelo claro sobre preto. O texto que esta imagem escreve sai com esta
; cor, e as celulas vazias tambem - que e o que se quer, para o cursor nascer
; amarelo a seguir ao prompt e nao cinzento.
ATRIB       equ 0x0E            ; amarelo claro sobre preto (o do inicio.mai)
ATRIB_VAZIA equ ATRIB           ; as celulas vazias sao a mesma cor, outro nome

; --- o cursor ---------------------------------------------------------------
; O cursor e posto com a INT 10h AH=02h: BH = pagina, DH = a linha, DL = a
; coluna, e e o caminho do BIOS para a posicao do cursor. A forma e o piscar
; sao os que o BIOS deixou (ver a nota do cursor no codigo, que explica porque
; e que nao se mexem neles).
;
; Nao nasce no canto: nasce depois do prompt, na terceira linha, coluna 1 - e
; la que o terminal vai escrever quando tiver o que escrever. A conta e a do
; prompt: o ">" ocupa a celula 0, portanto a escrita comeca na seguinte.
CURSOR_LIN  equ LINHA_PROMPT   ; a linha do prompt (a terceira, contado de 0)
CURSOR_COL  equ 1              ; a coluna a seguir ao ">"

; ---------------------------------------------------------------------------
; Cabecalho da imagem (8 bytes). A propria imagem le a assinatura no primeiro
; dword quando arranca: e a prova de que o inicio.mai carregou mesmo o recu.mai e
; nao lixo - e sem ela nao se pinta nada, mas ninguem fica a espera (e o
; "hlt" do fim nao depende de assinatura nenhuma).
; A entrada e por isso depois do cabecalho, nos 8 bytes, como no video.dr, no
; teclado.dr e nas quatro imagens da interface. Quem salta para ca tem a mesma
; conta (REC_INI = 8 em inicio.asm).
; ---------------------------------------------------------------------------
ASSIN:
    dd ASSINATURA               ; 'R','E','C','1'
    dw VERSAO_IMAGEM            ; versao do desenho desta imagem
    dw 0x0000                   ; reservado
REC_INI equ $ - $$              ; deslocamento da entrada dentro da imagem

ASSINATURA   equ 0x31434552     ; 'R','E','C','1' por ordem de bytes
VERSAO_IMAGEM equ 1

start:
    ; --- pilha e interrupcoes -------------------------------------------------
    ; Esta imagem nao volta para o inicio.mai, por isso nao e a pilha dele que se
    ; pode usar: o "hlt" do fim precisa de uma pilha que nao esteja a servir a
    ; BIOS. E a mesma pilha que o inicio.mai usa (0x7BFF) e pelo mesmo motivo -
    ; uma pilha no buffer de texto empilha para o ecra, e o "cli"/"sti" de
    ; arrivada garante que nenhum IRQ da BIOS a estraga enquanto o ecra e
    ; pintado.
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x7BFF
    sti

    ; --- DS = o nosso segmento -----------------------------------------------
    ; Tudo o que esta imagem guarda mora aqui: as tres variaveis do terminal, a
    ; TEC_INFO com que se fala com o driver e as duas tabelas de teclas. O DS
    ; nao muda mais a partir daqui - nem o rolar do ecra nem o driver o mexem
    ; (o primeiro faz push/pop do seu, o segundo tem o proprio), por isso os
    ; "[pos_lin]" de todo o laco sao sempre lidos neste segmento.
    mov ax, SEG_IMG
    mov ds, ax

    ; --- esta imagem e mesmo a recuperacao? ------------------------------------
    ; E a propria imagem que se valida, e nao quem a salta: quem salta para uma
    ; imagem sem cabecalho saltaria para o meio do nada e o CPU executaria zeros
    ; sem dar conta. Sem assinatura nao se pinta nada e o CPU fica a dormir -
    ; um "hlt" e o que o inicio.mai deixaria a fazer, e um ecra de recuperacao
    ; que nao se pinta e pior do que o ecra do gerenciador, que era o ecra que
    ; estava la antes.
    cmp dword [ASSIN], ASSINATURA
    jne  fim

    ; --- o modo de video: 80x25 texto, que e o que esta imagem usa ----------
    ; O ecra e o buffer de texto e nao ha framebuffer nenhum, por isso o que se
    ; pede ao BIOS e o modo de texto: INT 10h AH=00h com AL=03h (80x25 em texto,
    ; preto sobre preto). O BIOS tambem limpa o ecra com este pedido - e por isso
    ; que o ecra abaixo ja preta quando o "rep stosw" comeca.
    ;
    ; Este pedido e feito mesmo que o ecra ja estivesse em modo de texto: quem
    ; salta para ca e o inicio.mai, que tambem esta em texto (o modo e posto no
    ; arranque dele), mas o modo de texto e o unico pedido que faz sentido repetir
    ; - e ele que garante que o buffer e mesmo o de 0xB800 e que a fonte e a
    ; dele. A alternativa (nao pedir nada eTrustar que o ecra ja esta em texto)
    ; seria uma aposta sobre o estado em que o outro sector o deixou.
    mov ax, 0x0003              ; AH=00h (mudar de modo), AL=03h (80x25 texto)
    int 0x10

    ; --- pintar o ecra todo ----------------------------------------------------
    ; O ecra inteiro, celula a celula. O "rep stosw" escreve o word inteiro
    ; (caracter e atributo) e avanca o ES:DI de dois em dois bytes, que e a
    ; unica conta necessaria num ecra de texto: e o mesmo "rep stosw" que o
    ; inicio.mai usa para a frase e para o ecra do erro (ver a rotina falha).
    ;
    ; O AX vai montado em duasInstrucoes de proposito. O "xor ax, ax" e o que
    ; poe o caracter a zero; o atributo vai no byte alto do word e tem de vir do
    ; ATRIB_VAZIA. Um "xor ax, ax" e mais nada - que e como estava - pinta o
    ; ecra com o atributo 0x00 e o cursor fica invisivel (ver a nota do
    ; atributo): o ecra saia preto na mesma, entao a falha era so o cursor em
    ; falta e o ATRIB_VAZIA ficava ali como uma constante que ninguem usava.
    mov ax, VIDEO_BASE
    mov es, ax
    xor di, di                  ; a primeira celula (linha 0, coluna 0)
    xor ax, ax                  ; AX = 0x0000: o caracter vazio
    mov ah, ATRIB_VAZIA         ; o atributo no byte alto: e o que se ve no cursor
    mov cx, CELULAS
    rep stosw

    ; --- as tres linhas do terminal -------------------------------------------
    ; O desenho do terminal, e so ele: titulo, aviso do --ajuda-- e prompt. As
    ; tres sao escritas no buffer de texto celula a celula, e nao pela INT 10h
    ; AH=13h - essa funcao devolve coisas diferentes conforme a BIOS, e o que se
    ; quer aqui e a mesma conta do inicio.mai quando escreve o titulo dele (ver
    ; a nota do titulo, la): escrever o par (caracter, atributo) e avancar dois
    ; bytes. O laco esta no fim da imagem, na rotina escreve.
    ;
    ; O ES ja aponta para 0xB800 desde que limpou o ecra e o DS ja aponta para
    ; esta imagem desde o arranque, por isso cada linha e tres numeros: DI e a
    ; celula inicial (linha * COLS celulas * 2 bytes), SI e o rotulo da cadeia
    ; - o ORG 0 faz o rotulo valer o deslocamento dentro da imagem, que e o que
    ; o DS=SEG_IMG espera - e CX e o comprimento, contado em tempo de montagem
    ; a partir do "$ - rotulo", para o texto poder mudar sem se mexer na conta.
    mov di, (LINHA_TITULO * COLS) * 2     ; a linha 0, coluna 0
    mov si, TITULO
    mov cx, TITULO_N
    call escreve

    mov di, (LINHA_AJUDA * COLS) * 2      ; a linha 1, coluna 0
    mov si, AJUDA
    mov cx, AJUDA_N
    call escreve

    mov di, (LINHA_PROMPT * COLS) * 2     ; a linha 2, coluna 0
    mov si, PROMPT
    mov cx, PROMPT_N
    call escreve

    ; --- o cursor: depois do prompt, e a piscar -------------------------------
    ; E a INT 10h AH=02h e so isso: BH = numero de pagina de video, DH = a
    ; linha, DL = a coluna. E o caminho do BIOS para o sitio do cursor.
    ;
    ; Nao se toca na forma nem no piscar do cursor. A forma vem do registo 0x0A
    ; do CRTC (o "Cursor Start": os bits baixos sao a linha de scaneamento onde
    ; o cursor comeca) e o BIOS ja a deixou como se quer - um sublinhado nas
    ; ultimas duas linhas do caracter. O piscar e o que o BIOS faz, nao o que esta
    ; imagem liga: depois da mudanca de modo, o cursor pisca sem mais.
    ;
    ; A ideia de ligar o piscar escrevendo no CRTC - "o bit 5 do registo 0xA e o
    ; bit de blink, e um cursor que nao pisca e esse bit a zero" - e o que estava
    ; aqui, e e ao contrario do que se pensava. Medido no QEMU, com o cursor em
    ; 0,0 e a forma 13-14 em todas as tentativas, contando os frames de 8 em que
    ; o cursor aparecia:
    ;
    ;     CRTC 0x0A = 0x0D  (bit 5 a zero, como o BIOS deixa)   4-5 de 8
    ;     CRTC 0x0A = 0x2D  (com o "or al, 0x20" de aqui)     0 de 8
    ;
    ; Ou seja, o bit ligado tirava o cursor do ecra. Nao era o piscar que
    ; faltava: era o cursor, e o unico sintoma era um ecra preto sem nada, que e
    ; indistinguivel de uma imagem que nunca chegou a correr. Por isso o CRTC
    ; nao e mexido. E o registo 0x0A e o unico sitio onde se poderia ir buscar
    ; "o cursor pisca" a mao, e ha aqui uma razao a mais para nao ir: um registo
    ; de hardware que se escreve a mao e um registo em que se pode passar a letra
    ; ao hardware, e o ganho seria zero - o BIOS ja faz o que se queria.
    mov ah, 0x02                ; AH=02h: poer o cursor numa posicao
    mov bh, 0x00                ; a pagina de video: a 0 (a unica em modo de texto)
    mov dh, CURSOR_LIN          ; a linha do prompt (a terceira)
    mov dl, CURSOR_COL          ; a coluna a seguir ao ">"
    int 0x10

    ; --- ligar o teclado: o driver ja la esta --------------------------------
    ; O teclado.dr esta em 0x60000 e esta ligado desde o inicio.mai (CMD_INI,
    ; antes da contagem) - o que se faz aqui e a mesma chamada, e por tres
    ; razoes que valem a pena:
    ;
    ;   - prova que o driver e o que se espera: antes de saltar para
    ;     0x6000:0x0008 le-se o cabecalho e ha de ser 'TEC1'. Sem esse dword
    ;     nao se salta para codigo nenhum, e o que se faz e ficar sem teclado;
    ;   - limpa o buffer: as teclas que a pessoa tenha premido durante a
    ;     contagem ou no menu nao devem aparecer no terminal a meio da primeira
    ;     linha;
    ;   - confirma a versao do contrato pela TEC_INFO, como o inicio.mai faz:
    ;     quem escreve 0xFFFF antes da chamada e escreve 2 depois so pode ter
    ;     sido o driver a entrar.
    ;
    ; CF=1 e "nao ha driver para aqui" - entao ha o laco de baixo para isso:
    ; o ecra fica desenhado e ninguem o move, que e o que este ecra era antes.
    call iniciar_teclado
    jc  sem_teclado

    ; --- o laco do terminal ---------------------------------------------------
    ; Dorme, atende a tecla, desenha, volta a dormir. E o mesmo "hlt" em vao de
    ; antes, so que agora ha quem o acorde com o que se quer: o handler da IRQ1
    ; do driver guarda a tecla no buffer proprio sempre que ha uma, e o timer da
    ; BIOS acorda o CPU de 18 em 18 vezes por segundo - o que faz a espera custar
    ; CPU zero em vez de um "jmp" a rodar.
    ;
    ; O IF tem de estar ligado, porque e a IRQ1 que enche o buffer: o "sti" esta
    ; aqui em cima, o driver repoe o IF em cada saida dele (o cli/sti e la
    ; dentro), e a BIOS nao mexe no IF por sua conta. Se o IF ficasse a zero, o
    ; "hlt" pararia o CPU para sempre e o terminal nunca mais atendia nada.
    sti
ciclo:
    call le_tecla                ; CF=1: nao ha tecla nenhuma
    jnc .tem_tecla
    hlt                          ; nao ha: dorme ate a proxima IRQ e volta a ver
    jmp ciclo
.tem_tecla:
    call tratar_tecla            ; AL = o scancode, AH = os modificadores
    jmp ciclo

sem_teclado:
    ; Nao ha driver onde haveria de haver (o cabecalho de 0x6000 nao e 'TEC1'),
    ; ou o driver respondeu com uma versao que este sector nao conhece. As tres
    ; linhas ficam escritas e nao ha nada que as mova: e o mesmo "hlt" do fim
    ; sem assinatura, com a mesma razao - sem teclado nao ha terminal que se
    ; leia, e inventar uma leitura a BIOS seria trocar o problema por outro.
    hlt
    jmp sem_teclado

fim:
    hlt
    jmp fim

; ---------------------------------------------------------------------------
; escreve: uma cadeia de caracteres no buffer de texto
;   entrada: DI = deslocamento da celula onde comeca (a linha * COLS * 2,
;            somada a coluna - e sempre par, porque cada celula sao dois bytes)
;            SI = deslocamento da cadeia dentro desta imagem (DS = SEG_IMG)
;            CX = quantos caracteres escrever
;   saida:   DI e SI apontam para o que vem a seguir, CX = 0
;   altera:  AX, CX, SI, DI
;
;   E o mesmo laco com que o inicio.mai escreve o titulo e as tres opcoes do
;   menu, tirado de la para ca: o "lodsb" busca o byte em DS:SI para AL, o
;   "stosw" poe o word inteiro em ES:DI e avanca dois bytes. O atributo e o
;   byte alto do AX, e por isso o "mov ah" vem depois do "lodsb" - o "lodsb"
;   so mexe no AL, e o AH da volta anterior e reutilizado, la se perde.
;
;   Nao ha "cld": o DF tem de estar a zero para o "stosw" andar para a frente,
;   e esta imagem ja confia nisso no "rep stosw" de cima - e a mesma confianca
;   que o inicio.mai tem. O BIOS devolve DF=0, e a INT 10h do modo de video e
;   a ultima coisa que passou por aqui.
escreve:
    lodsb
    mov ah, ATRIB
    stosw
    loop escreve
    ret

; ---------------------------------------------------------------------------
; iniciar_teclado: fala com o driver em 0x6000 e confirma o contrato
;   saida: CF=0 e o driver respondeu com a versao esperada; CF=1 e nao ha
;          driver nenhum para aqui (ou o que la esta nao e o que se espera)
;
;   A primeira verificacao e a do cabecalho do proprio driver: 'TEC1' no
;   primeiro dword de 0x6000:0x0000, o mesmo que o inicio.mai le quando o vai
;   carregar. Sem ela, um "call 0x6000:0x0008" saltaria para o que la estiver -
;   e nao ha nada em 0x6000 que se possa assumir que e codigo.
;
;   A segunda e a da versao, e e a mesma conta do carregar_teclado do
;   inicio.asm: quem chama escreve 0xFFFF na TEC_INFO ("ainda nao ha ninguem
;   aqui") e o driver escreve 2 no lugar. Se o valor for ainda 0xFFFF depois
;   da chamada, ou o driver nao correu ou nao e este - e as duas coisas dizem
;   que nao se pode confiar no que ele faz a seguir.
;
;   O CMD_INI alem disto limpa o buffer de teclas (as que a pessoa premiu a caminho)
;   e volta a instalar o handler da IRQ1, que e idempotente: poe o mesmo
;   vetor outra vez e destrava a mesma mascara.
iniciar_teclado:
    push es
    push bx
    push cx

    mov ax, TEC_SEG
    mov es, ax
    xor bx, bx
    cmp dword es:[bx], TEC_ASSIN
    jne .sem_driver

    mov ax, SEG_IMG             ; a TEC_INFO mora no nosso segmento: ES:BX = a nossa
    mov es, ax
    mov bx, TEC_INFO
    mov dword es:[bx + TEC_I_ASSIN], TEC_ASSIN
    mov word  es:[bx + TEC_I_VERSAO], 0xFFFF
    mov cx, TEC_CMD_INI
    call TEC_SEG:TEC_INI
    cmp word es:[bx + TEC_I_VERSAO], TEC_VERSAO
    jne .sem_driver

    clc
    jmp .sai
.sem_driver:
    stc
.sai:
    pop cx
    pop bx
    pop es
    ret

; ---------------------------------------------------------------------------
; le_tecla: a proxima tecla do driver, se a houver
;   saida: CF=0 e AL = o scancode, AH = os modificadores (TI_MODS)
;          CF=1 e nao ha tecla nenhuma (o buffer esta vazio)
;
;   E a mesma chamada da le_tecla do inicio.asm: ES:BX na TEC_INFO, CX no
;   comando, "call" de segmento, resposta no CF. O que aqui se fica com e o
;   scancode e os mods - o que se faz com eles e assunto de tratar_tecla.
;
;   O prefixo (TEC_I_PREF) nao e lido: o driver ja separou os dois pedacos, e
;   o scancode chega sempre no mesmo sitio - por isso o enter do teclado
;   numerico (E0 1C) e o mesmo 0x1C do enter normal e as setas (0x48, 0x50)
;   caem fora da tabela e sao ignoradas sem mais. As alargadas que interessam
;   sao so o enter, e esse ja vem certinho.
;
;   O ES e guardado e reposto: o driver escreve na TEC_INFO com o ES que lhe
;   passam, e o ES deste ecra e o do buffer de texto (0xB800) - um sem o outro
;   e a troca por engano que so se apanha a correr.
le_tecla:
    push es
    push bx
    push cx
    mov ax, SEG_IMG
    mov es, ax
    mov bx, TEC_INFO
    mov cx, TEC_CMD_LER
    call TEC_SEG:TEC_INI        ; CF=0: ha tecla e esta na TEC_INFO
    jc  .vazia
    mov al, es:[bx + TEC_I_TECLA]   ; o scancode, ja sem o prefixo
    mov ah, es:[bx + TEC_I_MODS]    ; shift, ctrl e alt
    clc
    jmp .sai
.vazia:
    stc
.sai:
    pop cx
    pop bx
    pop es
    ret

; ---------------------------------------------------------------------------
; tratar_tecla: o que fazer com a tecla que chegou
;   entrada: AL = o scancode, AH = os modificadores
;
;   Sao tres casos e mais nada, por esta ordem: o enter, o backspace e o resto.
;
;   O resto passa pelas duas tabelas do fim do ficheiro, porque o driver devolve
;   scancodes e nao caracteres: e aqui que um 0x1E vira um 'a', e um 'A' se o
;   shift estiver carregado (o bit esta no AH, que vem do TEC_I_MODS - o driver
;   e quem o guarda nas largadas e nas premidas, e este sector so le).
;
;   O que nao escreve sao tres coisas, e nenhuma e erro: as entradas a zero da
;   tabela (ctrl, alt, shift, esc, tab - teclas sem letra), as teclas acima de
;   0x39 (setas, F1..F12, o teclado numerico: todas fora da tabela) e o proprio
;   prefixo E0, que nem se olha (o scancode vem separado no TEC_I_TECLA).
tratar_tecla:
    cmp al, TEC_ENTER
    je  .enter
    cmp al, TEC_BACK
    je  .back
    cmp al, TAB_N               ; fora da tabela: nao e uma tecla com letra
    jae .nada

    mov bl, al                  ; o indice da tabela: o scancode
    xor bh, bh
    test ah, MOD_SHIFT
    jz  .sem_shift
    mov bl, [tab_com_shift + bx]
    jmp .tem_caracter
.sem_shift:
    mov bl, [tab_sem_shift + bx]
.tem_caracter:
    test bl, bl                 ; zero = tecla sem letra (ctrl, alt, shift..)
    jz  .nada
    mov cl, bl                  ; o caracter a escrever
    call por_caracter
.nada:
    ret

    ; --- enter: a linha de baixo com outro ">" --------------------------------
    ; E a mesma escrita de sempre - o ">" e um caracter como os outros, feito
    ; por_caracter, que avanca a coluna de 0 para 1: o cursor fica logo a
    ; seguir ao prompt sem uma conta nenhuma a mais.
    ;
    ; O que nao ha e uma linha de baixo quando se esta na ultima: entao tudo
    ; sobe uma linha (rolar_ecra) e a escrita la fica na ultima. E por isto que
    ; o "cmp" e ao LINHA_ULT e nao ao fim do buffer - o ecra e que se mexe, as
    ; variaveis nao andam para tras.
    ;
    ; ini_lin acompanha: e a linha onde comeca o prompt em que se escreve, e o
    ; backspace usa-a para saber onde parar (nao se come o ">").
.enter:
    inc byte [pos_lin]
    cmp byte [pos_lin], LINHA_ULT
    jbe .linha                  ; ainda ha linha de baixo
    call rolar_ecra             ; nao ha: tudo sobe e a escrita fica na ultima
    mov byte [pos_lin], LINHA_ULT
.linha:
    mov byte [pos_col], 0       ; a coluna zero e onde vive o prompt
    mov cl, '>'
    call por_caracter
    mov al, [pos_lin]
    mov [ini_lin], al
    ret

    ; --- backspace: apagar a celula onde se esta e ficar la -------------------
    ; O apagar e escrever um espaco por cima - e a razao de o por_caracter nao
    ; servir: ele escreve e AVANCA, e aqui quer-se escrever e ficar. Por isso a
    ; posicao mexe primeiro, com as contas de baixo, e so depois vem o
    ; por_celula com o espaco.
    ;
    ; O limite do apagar e a linha do prompt (ini_lin): nunca se apaga o ">"
    ; nem nada acima dele. Na linha do prompt isso e a coluna PROMPT_N (a zero
    ; e o proprio ">"); nas linhas de baixo, o texto comecou todo depois dele,
    ; por isso la pode apagar ate ao fim da linha - e quando a coluna esta a
    ; zero, a celula anterior e a ultima da linha de cima, que tambem e texto.
    ; O que nunca acontece e estar acima do prompt: nada mexe pos_lin para cima.
.back:
    mov al, [pos_lin]
    cmp al, [ini_lin]
    ja  .pode_apagar            ; numa linha abaixo do prompt: ha o que apagar
    cmp byte [pos_col], PROMPT_N
    jbe .nada                   ; encostado ao ">": nao se come o prompt
.pode_apagar:
    cmp byte [pos_col], 0
    jne .sem_subir
    dec byte [pos_lin]          ; a coluna zero da linha de baixo: o fim da
    mov byte [pos_col], COLS - 1 ; linha de cima e onde se vai parar
.sem_subir:
    dec byte [pos_col]
    mov cl, ' '
    call por_celula             ; o espaco tapa o caracter - e la sem avanco
    call poer_cursor            ; o cursor fica na celula apagada
    ret

; ---------------------------------------------------------------------------
; por_caracter: escreve um caracter na posicao actual e avanca
;   entrada: CL = o caracter
;   altera:  as variaveis pos_lin/pos_col (e o ecra, e o cursor)
;
;   O avanco e celula a celula, e o fim da linha e o fim do ecra sao os dois
;   unicos casos: na coluna COLS desce uma linha, e na linha alem da ultima
;   rola - que e o unico caminho para o ecra encher de texto a valer.
por_caracter:
    call por_celula
    inc byte [pos_col]
    cmp byte [pos_col], COLS
    jb  .cursor                 ; ainda ha coluna nesta linha
    mov byte [pos_col], 0       ; acabou a linha: a de baixo, coluna zero
    inc byte [pos_lin]
    cmp byte [pos_lin], LINHA_ULT + 1
    jb  .cursor                 ; ainda ha linha abaixo da ultima
    call rolar_ecra             ; nao ha: o ecra rola e a escrita fica na
    mov byte [pos_lin], LINHA_ULT ; ultima linha, coluna zero
.cursor:
    call poer_cursor
    ret

; ---------------------------------------------------------------------------
; por_celula: escreve um caracter na posicao actual, sem avancar
;   entrada: CL = o caracter; o atributo e sempre o ATRIB
;
;   E a unica coisa que faz escrever no buffer de texto: o par (caracter,
;   atributo) na celula que pos_lin/pos_col dizem. O resto do codigo - o
;   escrever as tres linhas de cima, o apagar, o prompt novo - passa por aqui
;   ou pelo escreve, e as duas coisas usam o mesmo ATRIB, por isso nao ha
;   saindo uma cor que nao seja a que se escolheu no comeco.
por_celula:
    push ax
    push di
    push es
    mov ax, VIDEO_BASE
    mov es, ax
    call celula_di              ; DI = a celula (pos_lin, pos_col)
    mov ah, ATRIB
    mov al, cl
    stosw                       ; o par inteiro, e o DI avanca dois bytes
    pop es
    pop di
    pop ax
    ret

; ---------------------------------------------------------------------------
; celula_di: o deslocamento da celula (pos_lin, pos_col) no buffer de texto
;   saida: DI = (linha * COLS + coluna) * 2
;
;   A conta inteira do ecra de texto: COLS celulas por linha, duas por celula,
;   e o buffer e uma coisa so - a linha 1 comeca 160 bytes depois da zero, e o
;   que numa linha e a coluna 79 noutra e so o byte a seguir.
;
;   O "mul bl" e de 8 bits porque a linha e um byte (ate 24) e o produto e 1920,
;   que cabe no AX - e deixa o DX livre, ao contrario do "mul cx". Os registos
;   sao todos guardados, porque o chamador tem o caracter no CL.
celula_di:
    push ax
    push bx
    mov al, [pos_lin]
    xor ah, ah
    mov bl, COLS
    mul bl                      ; AX = linha * COLS
    mov bl, [pos_col]
    xor bh, bh
    add ax, bx                  ; + coluna
    shl ax, 1                   ; * 2 bytes por celula
    mov di, ax
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; poer_cursor: poe o cursor do BIOS onde o terminal escreve a seguir
;   A posicao vem das mesmas variaveis do desenho, por isso nao ha duas contas
;   que tenham de concordar - o cursor acompanha pos_lin/pos_col em vez de ser
;   escrito a mao em cada passo. A INT 10h AH=02h e a mesma do comeco, e a
;   forma e o piscar continuam a ser os que o BIOS deixou (a nota do CRTC esta
;   no bloco de comentarios la em cima, junto das constantes do cursor).
poer_cursor:
    push ax
    push bx
    push dx
    mov ah, 0x02                ; AH=02h: poer o cursor numa posicao
    mov bh, 0x00                ; a pagina de video: a 0 (a unica em modo de texto)
    mov dh, [pos_lin]
    mov dl, [pos_col]
    int 0x10
    pop dx
    pop bx
    pop ax
    ret

; ---------------------------------------------------------------------------
; rolar_ecra: toda a imagem sobe uma linha e a ultima fica vazia
;   altera: o ecra e o ini_lin (a linha do prompt com que se escreve tambem
;           sobe - e se ja saiu do ecra la pelo topo, fica em 0, que e o mesmo
;           que "nao ha prompt visivel para nao apagar")
;
;   E um "rep movsw" do buffer todo para trás: a linha 1 vai para a zero, a
;   ultima para a penultima, e a que sobra no fim e limpa com um "rep stosw"
;   de espacos - o mesmo ATRIB, por isso o ecra nao muda de cor nem de fundo.
;
;   O DS e o ES passam a ser os do buffer de texto e voltam aos de antes: esta
;   rotina e a unica, em todo o ficheiro, que muda o DS, e faz push/pop porque
;   o laco todo conta com o DS a apontar para as variaveis. O DF tem de estar
;   a zero para o "movsw" andar para a frente, que e a mesma confianca que o
;   "rep stosw" do limpar la em cima ja tinha.
;
;   pos_lin nao mexe aqui: quem a poe na ultima linha e quem a chama (o enter
;   e o fim do por_caracter), porque o que rola e o conteudo, nao a posicao de
;   escrita - a escrita fica sempre na linha de baixo, que e a ultima.
rolar_ecra:
    push ax
    push cx
    push si
    push di
    push ds
    push es
    mov ax, VIDEO_BASE
    mov ds, ax
    mov es, ax
    xor di, di                  ; o destino: a primeira celula
    mov si, COLS * BYTES_CEL    ; a origem: a segunda linha (160 bytes)
    mov cx, CELULAS - COLS      ; as 24 linhas que sobem
    rep movsw
    mov ax, (ATRIB << 8) | ' '  ; a ultima linha: espacos com a cor do ecra
    mov cx, COLS
    rep stosw
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax

    cmp byte [ini_lin], 0       ; a linha do prompt tambem sobe uma
    je  .feito
    dec byte [ini_lin]
.feito:
    ret

; --- as variaveis do terminal ---------------------------------------------------
; As unicas tres, e moram todas aqui em cima do DS (= o segmento da imagem).
; Os valores iniciais sao os das constantes do comeco: o prompt ja foi desenhado
; na linha LINHA_PROMPT e o cursor posto na coluna CURSOR_COL, por isso a
; escrita comeca exactamente onde o desenho parou.
;
;   pos_lin/pos_col  onde entra o proximo caracter (e onde o cursor esta)
;   ini_lin          a linha do prompt em que se escreve: e o chao do backspace
pos_lin: db LINHA_PROMPT
pos_col: db CURSOR_COL
ini_lin: db LINHA_PROMPT

; --- a TEC_INFO com que se fala com o driver -----------------------------------
; Os mesmos 12 bytes do TEC_INFO do inicio.asm e do nucleo.asm, com os mesmos
; nomes e a mesma ordem (o contrato esta inteiro em drivers/teclado.asm). O que
; se escreve aqui antes da chamada e a assinatura e o 0xFFFF da versao; o resto
; e do driver - e o CMD_LER que poe o scancode em TEC_I_TECLA e os mods em
; TEC_I_MODS, e o CMD_INI que poe a versao em 2.
TEC_INFO:
    dd 0x00000000               ; TEC_I_ASSIN: enche-se na chamada (o 'TEC1')
    dw 0xFFFF                   ; TEC_I_VERSAO: "ainda nao ha ninguem aqui"
    dw 0x0000                   ; TEC_I_FLAGS: bit 0 = o driver tem mais teclas
    db 0x00                     ; TEC_I_ESTADO: o estado lido em 0x64 (CMD_INI)
    db 0x00                     ; TEC_I_TECLA: o scancode (CMD_LER)
    db 0x00                     ; TEC_I_PREF: o prefixo (CMD_LER)
    db 0x00                     ; TEC_I_MODS: shift, ctrl e alt (CMD_LER)

; --- as tabelas de teclas -------------------------------------------------------
; O driver devolve scancodes do conjunto 1, e o terminal quer caracteres - por
; isso ha uma tabela por tecla, indexada pelo scancode, com o caracter que ele
; escreve. Sao 58 entradas (0x00 a 0x39) e o TAB_N e' o comprimento: o que
; vier de 0x3A para cima nem chega a tabelas (setas, F1..F12, o numerico), e as
; entradas a zero sao as teclas sem letra (ctrl, alt, shift, esc, tab, o enter
; e o backspace, que tem tratamento proprio).
;
; A da esquerda e a sem shift; a da direita e com, e e so o que muda: letras
; maiusculas, os simbolos de cima dos digitos e os que ficam em cima do ponto.
; Nao ha caps lock nem ctrl nem alt nas tabelas - o shift e o unico modificador
; que escreve, e as outras teclas dao zero e sao ignoradas.
TAB_N       equ 0x3A            ; quantas entradas tem cada tabela (0x00-0x39)

tab_sem_shift:
    db 0, 0                                        ; 00 esc, 01 (nenhuma)
    db '1','2','3','4','5','6','7','8','9','0'     ; 02-0B os digitos
    db '-','='                                     ; 0C, 0D
    db 0, 0                                        ; 0E backspace, 0F tab
    db 'q','w','e','r','t','y','u','i','o','p'     ; 10-19 a linha de cima
    db '[',']'                                     ; 1A, 1B
    db 0                                           ; 1C enter
    db 0                                           ; 1D ctrl
    db 'a','s','d','f','g','h','j','k','l'         ; 1E-26 a linha do meio
    db ';',"'",'`'                                 ; 27-29
    db 0                                           ; 2A shift esquerdo
    db '\'                                         ; 2B
    db 'z','x','c','v','b','n','m'                 ; 2C-32 a linha de baixo
    db ',','.','/'                                 ; 33-35
    db 0                                           ; 36 shift direito
    db '*'                                         ; 37 o asterisco do numerico
    db 0                                           ; 38 alt
    db ' '                                         ; 39 o espaco
    times TAB_N - ($ - tab_sem_shift) db 0         ; e se uma tabela sair curta

tab_com_shift:
    db 0, 0
    db '!','@','#','$','%','^','&','*','(',')'
    db '_','+'
    db 0, 0
    db 'Q','W','E','R','T','Y','U','I','O','P'
    db '{','}'
    db 0
    db 0
    db 'A','S','D','F','G','H','J','K','L'
    db ':','"','~'
    db 0
    db '|'
    db 'Z','X','C','V','B','N','M'
    db '<','>','?'
    db 0
    db '*'                                         ; o shift nao muda este
    db 0
    db ' '                                         ; nem o espaco
    times TAB_N - ($ - tab_com_shift) db 0

; --- o texto das tres linhas ---------------------------------------------------
; Os bytes que o "escreve" la em cima poe no ecra. Estao depois do "hlt" do fim
; e nao no meio do codigo: quem salta para esta imagem entra nos 8 bytes do
; cabecalho, e o que vem a seguir e a sequencia de arranque - estas cadeias sao
; lidas, nunca executadas.
;
; O numero do build aparece uma vez so, e e a quarta casa onde ele vive (a
; variavel BUILD do Build.sh, o FIC_NUCLEO do inicio.asm e o VERSAO_LIT do
; nucleo.asm sao as outras tres): ao mudar de build escreve-se o numero tambem
; aqui. O comprimento nao e escrito a mao - o "$ - rotulo" conta-o, por isso o
; titulo pode ganhar ou perder caracteres sem esta linha saber.
TITULO:
    db "MaiSus Beta v0.1 Build 0.12.2026"
TITULO_N equ $ - TITULO          ; 32 caracteres

AJUDA:
    db "digite --ajuda-- para lista comandos disponiveis"
AJUDA_N equ $ - AJUDA            ; 48 caracteres

PROMPT:
    db ">"
PROMPT_N equ $ - PROMPT          ; 1 caracter (e a coluna onde nasce o cursor)

; ---------------------------------------------------------------------------
; O que nao e usado fica a zero: os "equ" nao ocupam espaco e o resto sao os
; bytes que as rotinas de cima leem - as tres variaveis, a TEC_INFO, as duas
; tabelas e as tres cadeias. Tudo isto cabe com folga nos dois sectores que o
; inicio.mai le (REC_SET, 4 KiB), e nao ha initialization data nenhuma: o que
; nao e tocado fica a zero sem o inicio.mai ter de encher sectors inteiros -
; o mesmo que o decodificador faz com o "times" do fim (ver decod.img).
; ---------------------------------------------------------------------------
