; ============================================================================
;  Maisus - imagens/decodificador_de_imagem.asm
;  Decodificador de .img - build 0.12.2026
;
;  Carregado por inicio.mai da ISO (/imagens/decod.img) para 0x80000. A
;  entrada e DEC_INI = 0x0008, logo depois do cabecalho de 8 bytes.
;  Convencao de entrada: CS=IP=DEC_INI, DS=SEG_DEC, ES:BX = IMG_INFO do
;  nucleo, CX = comando.
;
;  missao: ver o que o nucleo mandou - a geometria do ecra e a imagem que ele
;          quer ver - e desenhar essa imagem no framebuffer.
;  saida: nada. O decodificador escreve na IMG_INFO de quem chamou: e de la
;         que saem o erro e o numero de pixels escritos.
;
;  ---------------------------------------------------------------------------
;  A DIVISAO DO TRABALHO
;
;  O nucleo e que sabe o ecra que o video.dr poe (e o unico que le o
;  VIDEO_INFO), por isso e ele que decide ONDE a imagem fica no ecra e COM QUE
;  TAMANHO: reduz a imagem proporcionalmente quando o ecra e menor do que ela
;  e deixa o rectangulo centrado, o que faz o resto do ecra ficar preto. O
;  decodificador nao sabe nada do ecra para alem do que o nucleo lhe escreve
;  na IMG_INFO, e nao se importa: escreve o rectangulo que lhe mandaram, nem
;  mais nem menos.
;
;  E o nucleo porque a regra e "a imagem encolhe, mas nunca cresce": o ecra
;  limpo e preto, e uma imagem menor no meio de um ecra grande e um logo com
;  a sua margem; uma imagem maior e o ecra inteiro, sem margem nenhuma. O
;  decodificador so obedece ao rectangulo, seja ele qual for.
;
;  ---------------------------------------------------------------------------
;  PORQUE E UM ESTAGIO E NAO UMAS LINHAS NO NUCLEO
;
;  Porque e o mesmo contracto que o video.dr e o teclado.dr: um cabecalho de 8
;  bytes com uma assinatura, uma entrada depois dele, uma estrutura em ES:BX e
;  um regresso por "retf". Quem chama nao precisa de saber o tamanho do que
;  chamou nem de confiar no que o inicio.mai carregou - le a assinatura e sabe.
;  E porque o nucleo tem de caber em 32 KiB e uma paleta de 256 cores, um
;  buffer de linha e tresversoes de ecra nao cabem la dentro sem grow (ver o
;  "times" do fim deste ficheiro e o CONTRATO do nucleo.asm).
;
;  ---------------------------------------------------------------------------
;  O FORMATO .img
;
;  O .img e uma imagem INDEXADA: uma paleta de 256 cores e, por pixel, o
;  indice de uma cor da paleta. O formato inteiro esta escrito no topo do
;  conversor_de_imagens.py, que e quem escreve o ficheiro. O que o
;  decodificador precisa de saber:
;
;    IMG_ASSIN   dd 'IMG1'     a assinatura, lida antes de mais nada
;    IMG_VERSAO  dw            a versao do formato (1)
;    IMG_LARG    dw            a largura da imagem, em pixels
;    IMG_ALT     dw            a altura da imagem, em pixels
;    IMG_CORES   dw            quantas cores a paleta tem
;    IMG_PIX     dw            onde comecam os pixels (sempre 0x410)
;    IMG_PAL     equ 0x10      a paleta: 256 entradas de 4 bytes, { r, g, b, 0 }
;
;  A paleta tem 8 bits por canal e o registo da VGA tem 6 (0 a 63): a conta e
;  um >> 2, o mesmo que o video.dr faz ao escrever o cinza claro (42 * 4 = 168).
;  Nos modos de 16 e 32 bits os canais vao como estao, so que convertidos no
;  formato do modo.
; ============================================================================

BITS 16

; Endereco LINEAR onde o inicio.mai carrega este ficheiro, e o segmento
; correspondente. Sao dois numeros diferentes e confundir-los e o erro classico
; do modo real: o segmento 0x8000 cobre 0x80000, o segmento 0x80000 cobriria
; 5 MiB. Quem chama usa o segmento (DEC_SEG em inicio.asm), como faz com o
; video.dr.
;
; NAO ha ORG aqui, ao contrario do nucleo.asm: o ORG no formato bin faz o NASM
; somar a origem a todos os rotulos, e o codigo deste ficheiro vive todo
; relativo ao segmento (DS = 0x8000): um rotulo tem de valer o deslocamento
; dentro da imagem. Com o ORG o "classicos" de video.asm valia 0xE307 em vez
; de 0x0307 e o driver lia a tabela no sitio errado.
SEG_BASE   equ 0x80000 >> 4      ; 0x8000 - o segmento deste codigo

; Os dois comandos. O desenho poe a paleta da imagem no registo de cores e
; deixa-a la: o ecra mostra as cores da imagem enquanto ela esta no ecra, e
; quem sabe quando ela sai de la e o nucleo (e a reposta, no CMD_REPOR). Um
; CMD_REPOR sem CMD_DESENHAR antes nao e um erro - e uma paleta que ja esta
; como o nucleo a deixou, que e o que o comando pede.
CMD_DESENHAR equ 0               ; desenhar a imagem no rectangulo da IMG_INFO
CMD_REPOR    equ 1               ; repor a paleta que o ecra tinha antes do desenho

; A assinatura do cabecalho da imagem (o mesmo THEM de assinatura que poe o
; video.dr e o teclado.dr) e a do ficheiro .img, que e outra coisa: a primeira
; e o decodificador a dizer que esta aqui, a segunda e o .img a dizer que e
; uma imagem. Sao as duas comparadas, e com a mesma constante.
ASSINATURA equ 0x31474D49        ; 'I','M','G','1' por ordem de bytes
VERSAO_CONTRATO equ 1            ; a versao do contrato que este decodificador fala
VERSAO_IMG  equ 1                ; a versao do formato .img que se sabe ler

; ---------------------------------------------------------------------------
; IMG_INFO: a estrutura com que o nucleo e o decodificador falam.
; A definicao completa esta em nucleo.asm, com os comentarios: aqui ficam os
; deslocamentos, que sao o contrato e nao podem mudar de um lado so.
;
;   II_ASSIN    dd 'IMG1'    o nucleo escreve, o decodificador confirma
;   II_VERSAO   dw          versao do contrato
;   II_COMANDO  dw          o comando que o nucleo mandou
;   II_ERRO     dw          0 = correu bem, o resto e um dos ERRO_*
;   II_CMDS     dw          quantos comandos o nucleo ja mandou
;   II_LARG     dw          largura do ecra, em pixels
;   II_ALT      dw          altura do ecra, em pixels
;   II_BPP      dw          bits por pixel do framebuffer
;   II_BYTESLIN dw          bytes por linha do framebuffer
;   II_FBSEG    dw          segmento do framebuffer
;   II_FBOFF    dw          deslocamento do framebuffer dentro do segmento
;   II_X        dw          onde a imagem comeca, em pixels
;   II_Y        dw          onde a imagem comeca, em pixels
;   II_DLARG    dw          a largura que a imagem vai ter no ecra
;   II_DALT     dw          a altura que a imagem vai ter no ecra
;   II_IMG_SEG  dw          o segmento onde o inicio.mai carregou o .img
;   II_PIXELS   dd          quantos pixels foram escritos (o que se le e o
;                           que se escreveu: o ecra e o unico sitio onde
;                           vale)
;   II_PARC     dw          reservado, para a estrutura ter um numero par
;
; O nucleo escreve a assinatura e o comando antes de chamar; o decodificador
; escreve a versao, o erro, a conta de comandos e os pixels. E o mesmo sentido
; do VIDEO_INFO, ao contrary do TEC_INFO, que o nucleo preenche antes de
; chamar e o driver preenche a seguir.
; ---------------------------------------------------------------------------
II_ASSIN    equ 0x00
II_VERSAO   equ 0x04
II_COMANDO  equ 0x06
II_ERRO     equ 0x08
II_CMDS     equ 0x0A
II_LARG     equ 0x0C
II_ALT      equ 0x0E
II_BPP      equ 0x10
II_BYTESLIN equ 0x12
II_FBSEG    equ 0x14
II_FBOFF    equ 0x16
II_X        equ 0x18
II_Y        equ 0x1A
II_DLARG    equ 0x1C
II_DALT     equ 0x1E
II_IMG_SEG  equ 0x20
II_PIXELS   equ 0x22
II_PARC     equ 0x26
INFO_N      equ 0x28               ; 40 bytes: par, para o "rep movsw" do
                                   ; inicio do codigo nao deixar o ES torto

; O que o decodificador diz quando nao desenhou. O II_ERRO e posto a zero no
; principio de cada comando e so muda se algo correr mal: quem chama le-o
; depois do regresso e sabe se o comando foi cumprido sem precisar de saber
; nada sobre o que o comando fez.
ERRO_COMANDO equ 1                ; o comando nao existe
ERRO_ASSIN   equ 2                ; a IMG_INFO ou o .img nao tem a assinatura
ERRO_VERSAO  equ 3                ; a versao do .img nao e a que se sabe ler
ERRO_ECRA    equ 4                ; o ecra que o nucleo descreveu nao presta
ERRO_TAMANHO equ 5                ; o rectangulo do desenho nao cabe no ecra
ERRO_IMG     equ 6                ; o .img nao tem cabecalho valido
ERRO_LARGA   equ 7                ; a imagem e mais larga do que BUF_LINHA

; ---------------------------------------------------------------------------
; O formato .img (ver a nota do topo do ficheiro). Os deslocamentos sao
; compensados com IMG_PAL para a paleta.
; ---------------------------------------------------------------------------
IMG_ASSIN   equ 0x00
IMG_VERSAO  equ 0x04
IMG_LARG    equ 0x06
IMG_ALT     equ 0x08
IMG_CORES   equ 0x0A
IMG_PIX     equ 0x0C
IMG_PAL     equ 0x10               ; 256 entradas de 4 bytes, ate 0x40F
CAB_N       equ 0x10               ; o cabecalho tem 16 bytes

; ---------------------------------------------------------------------------
; A paleta do .img sao 256 entradas de 4 bytes: 1024 bytes. E copiada para ca
; antes do desenho (ver copiar_paleta). A paleta que o ecra tinha antes e
; guardada noutro sitio, para ser reposta no fim: sao tres bytes por cor (o
; DAC da VGA e de 6 bits por canal e so precisa de tres), e por isso que os
; dois blocos nao podem ter o mesmo tamanho - nem estar no sitio um do outro.
; ---------------------------------------------------------------------------
ENTRADAS    equ 256
TAM_PALETA  equ ENTRADAS * 4       ; 1024 bytes: a paleta do .img
TAM_VELHA   equ ENTRADAS * 3       ; 768 bytes: a paleta do ecra

; ---------------------------------------------------------------------------
; Os tres registos do DAC da VGA (o conversor analogico de digital, o que
; guarda as cores que o ecra mostra). Nao se usa a INT 10h para nada disto:
; o BIOS desta maquina aceita os pedidos de paleta e devolve os registos como
; estavam, sem escrever no DAC - e o pior dos dois casos, porque nao ha erro
; para se ver. Escrevendo nos registos nao ha nem servico nem duvida: e o
; registo verdadeiro, e o que o ecra le a cada pixel.
;
;   DAC_POR  escrever aqui o indice da cor; DAC_DA escrever (ou ler, com
;            DAC_LE) a cor em tres Channel, vermelho, verde e azul.
;   DAC_LE   o mesmo endereco, mas para leitura: escrever aqui o indice e a
;            cor que se segue vem de DAC_DA, na mesma ordem.
;
; Os canais sao de 6 bits (0 a 63). O do .img e de 8 (0 a 255), e por isso
; que o >> 2 aparece em todas as passagens: 63 << 2 = 252 e o 255 vira 63, o
; branco. E o mesmo que o video.dr faz ao escrever o cinza (42 * 4 = 168).
; ---------------------------------------------------------------------------
DAC_POR    equ 0x3C8               ; o indice da cor a por
DAC_DA     equ 0x3C9               ; os tres canais, na ordem R, G, B
DAC_LE     equ 0x3C7               ; o indice da cor a ler

; ---------------------------------------------------------------------------
; O desenho reduz a imagem quando o ecra e menor do que ela, e nesse caso cada
; pixel do ecra e uma amostra de varios da imagem. A amostra e sempre uma
; linha da imagem, e por isso que cada linha e copiada para BUF_LINHA antes de
; ser desenhada (ver desenhar): e o que deixa o DS quieto no segmento do
; decodificador durante o desenho, em vez de trocar de segmento a cada pixel
; para ir buscar o indice.
;
; O limite e o do bloco: uma imagem mais larga do que isto nao cabe na linha
; copiada e o decodificador recusa (ERRO_LARGA) em vez de escrever fora do
; bloco. O conversor sabe deste numero e avisa antes de escrever um .img que
; nao va ser lido.
; ---------------------------------------------------------------------------
TAM_LINHA   equ 1024               ; bytes: a maior linha que se copia

; ---------------------------------------------------------------------------
; Cabecalho do decodificador (8 bytes). O nucleo le a assinatura no primeiro
; dword da imagem antes de chamar o decodificador: e a prova de que o
; inicio.mai carregou mesmo uma imagem de codigo e nao lixo. A entrada do
; decodificador e por isso depois do cabecalho, e o nucleo tem a mesma conta
; (DEC_INI = 8 em nucleo.asm).
; ---------------------------------------------------------------------------
    dd ASSINATURA               ; 'I','M','G','1'
    dw VERSAO_CONTRATO          ; versao do contrato que este decodificador fala
    dw 0x0000                   ; reservado
DEC_INI equ $ - $$             ; deslocamento da entrada dentro da imagem

start:
    ; --- guarda o que o nucleo passou --------------------------------------
    ; O "rep movsb" da frente gasta o CX, o SI e o DI: o que o nucleo passou
    ; tem de estar em memoria antes disso.
    mov [cmd], cx
    mov [seg_contrato], es
    mov [off_contrato], bx

    ; --- traz a IMG_INFO do nucleo para uma copia local -------------------
    ; E o mesmo vaivem que o video.dr faz com o VIDEO_INFO: o codigo inteiro
    ; deste ficheiro usa enderecos normais em DS e nunca troca de segmento
    ; para ir ler um campo. O ES e o segmento do nucleo (a origem) e o DS o
    ; deste codigo (o destino) - ao contrario, que e o erro classico, porque
    ; o "rep movsb" copia de DS:SI para ES:DI e o destino e o ES.
    ;
    ; O ES e reposto no fim com o valor que o nucleo deu, porque e o registo
    ; que o "retf" e o codigo de saida precisam de encontrar intacto.
    push es                      ; DS = nucleo, ES = este codigo
    push ds
    mov ax, es
    mov ds, ax
    mov ax, SEG_BASE
    mov es, ax
    mov si, bx                   ; a origem: a IMG_INFO que o nucleo passou
    mov di, CONTRATO             ; o destino: a copia local
    mov cx, INFO_N
    cld
    rep movsb
    pop ds
    pop es                       ; volta aos segmentos do nucleo e deste codigo

    ; --- o cabecalho esta bem? -------------------------------------------
    ; E a mesma pergunta que o video.dr faz ao VIDEO_INFO: a estrutura que o
    ; nucleo passou e mesmo a nossa, ou e lixo? Sem isto o decodificador
    ; escrevia nos sitios que o CX e o BX apontassem e o nucleo ficava com a
    ; estrutura estragada sem dar por isso.
    cmp dword [CONTRATO + II_ASSIN], ASSINATURA
    jne .mal
    mov word [CONTRATO + II_VERSAO], VERSAO_CONTRATO
    mov word [CONTRATO + II_ERRO], 0
    mov word [CONTRATO + II_CMDS], 0
    mov dword [CONTRATO + II_PIXELS], 0

    ; --- o que o nucleo quer que se faca? ---------------------------------
    ; Dois comandos: desenhar, e repor a paleta que o ecra tinha antes do
    ; desenho. Um comando desconhecido e um erro declarado, nao um silencio:
    ; quem chamou mandou fazer uma coisa que este decodificador nao sabe
    ; fazer e tem de saber disso pelo II_ERRO.
    mov cx, [cmd]
    cmp cx, CMD_DESENHAR
    je  .desenhar
    cmp cx, CMD_REPOR
    je  .repor
    mov word [CONTRATO + II_ERRO], ERRO_COMANDO
    jmp .mal
.desenhar:
    inc word [CONTRATO + II_CMDS]
    call desenhar
    jmp devolver
.repor:
    inc word [CONTRATO + II_CMDS]
    call repor
    jmp devolver
.mal:
    stc
devolver:
    ; --- reenvia a IMG_INFO ao nucleo -------------------------------------
    ; O "rep movsb" mexe no CX, no SI e no DI mas nao nos flags: o CF que o
    ; comando deixou atravessa a copia e chega ao nucleo.
    ;
    ; O regresso e "retf" (e nao "ret") porque quem chamou foi um "call" de
    ; segmento: a pilha tem o IP e o CS do nucleo, e as duas coisas tem de sair.
    mov es, [seg_contrato]
    mov di, [off_contrato]
    mov si, CONTRATO
    mov cx, INFO_N
    cld
    rep movsb
    retf

; ============================================================================
; desenhar: o comando que o nucleo chama
;   saida: CF=0 se a imagem foi desenhada | CF=1 se nao (o II_ERRO diz por que)
;
;   A ordem e esta: primeiro o ecra (a coisa onde se escreve), depois o
;   rectangulo (a coisa que se escreve), e so depois a imagem. E a ordem em
;   que as perguntas fazem sentido: nao interessa se o .img e valido quando o
;   ecra nao tem onde escrever, e o II_ERRO tem de dizer a primeira coisa que
;   nao prestava, nao a ultima que se chegou a ver.
; ============================================================================
desenhar:
    ; --- o ecra que o nucleo descreveu presta? ---------------------------
    ; Um ecra de 0 em qualquer dimensao e um ecra onde nao se escreve nada, e
    ; uma imagem de zero pixels e uma imagem que nao aparece. Nenhum dos dois
    ; e um erro do nucleo que chegue a correr - sao coisas que este codigo tem
    ; de nao fazer.
    mov ax, [CONTRATO + II_LARG]
    test ax, ax
    jz  .erro_ecra
    mov ax, [CONTRATO + II_ALT]
    test ax, ax
    jz  .erro_ecra
    mov ax, [CONTRATO + II_BYTESLIN]
    test ax, ax
    jz  .erro_ecra

    ; --- quantos bits por pixel tem o ecra? -------------------------------
    ; O desenho escreve no ecra em bytes por pixel, e so ha conta a fazer nos
    ; tres modos que o video.dr sabe descrever: 8, 16 e 32 bits por pixel. Um
    ; II_BPP de 24 (ou de 4, ou de 7) nao dava erro nenhum: o "shr ax, 3" de
    ; baixo dava 3 bytes por pixel e a imagem saia com o ecra meio preenchido,
    ; coluna a coluna, sem ninguem se queixar.
    mov ax, [CONTRATO + II_BPP]
    cmp ax, 8
    je  .bpp_presta
    cmp ax, 16
    je  .bpp_presta
    cmp ax, 32
    je  .bpp_presta
    jmp .erro_ecra              ; nem 8, nem 16, nem 32: ecra que nao se escreve
.bpp_presta:

    ; O II_FBSEG tem de existir: um framebuffer num segmento 0 e um ecra que
    ; nao esta em lado nenhum. O segmento e o que a INT 10h devolve e o que o
    ; nucleo le do VIDEO_INFO, e nos modos classicos e 0xA000.
    mov ax, [CONTRATO + II_FBSEG]
    test ax, ax
    jz  .erro_ecra

    ; --- o offset do framebuffer e multiplo de 16? ------------------------
    ; E o que permite ao desenho dividir o endereco de um pixel entre o segmento
    ; e o deslocamento sem sobrar nada: endereco >> 4 e o segmento e o resto
    ; dos 4 bits de baixo volta ao deslocamento (ver desenhar_ecra). Um offset
    ; que nao fosse multiplo de 16 deixaria o resto do endereco fora das duas
    ; metades, e a imagem aparecia deslocada de 1 a 15 pixels. Nos modos
    ; classicos o framebuffer comeca no principio do segmento (offset 0) e num
    ; modo VESA o offset vem do VIDEO_INFO, que ja e multiplo de 16.
    mov ax, [CONTRATO + II_FBOFF]
    test al, 0x0F
    jnz .erro_ecra

    ; --- o rectangulo cabe no ecra? --------------------------------------
    ; O nucleo ja encolheu a imagem se foi preciso, e sabe o ecra. Ainda assim
    ; o decodificador confirma: escrever fora do ecra, num framebuffer linear,
    ; e escrever na memoria que esta a seguir - e o II_X e o II_Y sao o
    ; canto, que tambem tem de estar dentro.
    mov ax, [CONTRATO + II_DLARG]
    test ax, ax
    jz  .erro_tamanho
    cmp ax, [CONTRATO + II_LARG]
    ja  .erro_tamanho
    mov [dlarg], ax
    mov ax, [CONTRATO + II_DALT]
    test ax, ax
    jz  .erro_tamanho
    cmp ax, [CONTRATO + II_ALT]
    ja  .erro_tamanho
    mov [dalt], ax

    ; --- a imagem e mesmo um .img? ---------------------------------------
    ; A assinatura e a versao do formato. Uma versao diferente nao e um erro
    ; desta imagem: e um ficheiro de outro formato, que este decodificador nao
    ; sabe ler. O que o inicio.mai carregou e o que o Build.sh graftou na ISO,
    ; por isso so muda se mudar o conversor - e mesmo assim o ficheiro errado
    ; tem de dar erro em vez de desenhar pixels a toa.
    ; O cabecalho_img e que poe o DS no segmento da imagem (ele e que le o
    ; cabecalho todo do .img) e o que o reposto antes de sair. A primeira
    ; leitura - a assinatura e a versao - e feita aqui, e so para o erro sair
    ; antes de o DS estar no sitio errado; por isso o caminho da falha repoe o
    ; DS antes de escrever o II_ERRO: o CONTRATO e deste codigo, e escrever nele
    ; com o DS na imagem era escrever por cima da paleta do .img.
    mov ax, [CONTRATO + II_IMG_SEG]
    test ax, ax
    jz  .erro_img              ; nao ha imagem onde ir buscar nada
    mov ds, ax
    cmp dword [IMG_ASSIN], ASSINATURA
    jne .img_mau
    cmp word [IMG_VERSAO], VERSAO_IMG
    jne .img_mau
    mov ax, SEG_BASE           ; o cabecalho_img entra com o DS do codigo: e ele
    mov ds, ax                 ; que poe o DS na imagem, porque e ele que le o
    call cabecalho_img         ; cabecalho todo (e o que o reposto a sair)
    jc  .erro_img              ; o DS ja e o do codigo
    call copiar_paleta         ; a paleta do .img para ca
    jmp .img_pronto
.img_mau:
    mov ax, SEG_BASE           ; o DS tem de voltar, mesmo a falhar
    mov ds, ax
    jmp .erro_img
.img_pronto:

    ; --- o rectangulo no ecra, em bytes ----------------------------------
    ; O canto (x, y) e o rectangulo (dlarg x dalt) traduzidos para um
    ; deslocamento no framebuffer:
    ;
    ;     endereco = fboff + y * bytes_por_linha + x * bytes_por_pixel
    ;
    ; A conta e de 32 bits de proposito. Uma tela de 1920x1080 tem 1080 linhas
    ; de 1920 pixels: a linha 1000 comeca em 1920 * 1000 = 1.920.000 bytes,
    ; muito acima dos 64 KiB de um segmento. Num "mul" de 16 bits o produto
    ; baixo (1.920.000 - 29 * 65536 = 19.456) e o resto (29) saem em AX e DX, e
    ; e a soma dos dois - com o "adc", que e o carry do "add" - que da o
    ; endereco certo. Sem ele a imagem aparecia na linha errada ou no ecra
    ; inteiro.
    mov ax, [CONTRATO + II_BYTESLIN]
    mov [bytes_linha], ax
    mov ax, [CONTRATO + II_BPP]
    shr ax, 3                 ; 1, 2 ou 4 bytes por pixel
    mov [bpp8], al

    mov ax, [CONTRATO + II_FBOFF]
    mov [fboff], ax
    mov ax, [CONTRATO + II_X]
    mov [x_ecra], ax
    mov ax, [CONTRATO + II_Y]
    mov [y_ecra], ax

    ; --- o canto superior esquerdo, uma vez ------------------------------
    ; Y * bytes por linha, mais x * bytes por pixel. Sao dois produtos
    ; distintos e o segundo nao pode entrar no primeiro: com o X no AX o "mul"
    ; multiplicaria os dois juntos, e a soma nao daria o endereco de nenhum
    ; pixel. Por isso sao duas contas de 32 bits, uma de cada vez.
    mov ax, [y_ecra]
    mul word [bytes_linha]     ; DX:AX = y * bytes por linha
    mov [endereco], ax
    mov [endereco + 2], dx
    mov ax, [x_ecra]
    movzx bx, byte [bpp8]      ; sem o "movzx" o "mul" usaria a word toda, e
    mul bx                     ; DX:AX = x * bytes por pixel
    add [endereco], ax
    adc [endereco + 2], dx
    ; --- e o fboff, o mesmo paragrafo do segmento base --------------------
    ; O II_FBOFF e o deslocamento do framebuffer dentro do segmento base, e um
    ; ecra com modo de video comecar a meio do segmento da-o diferente de zero.
    ; O endereco tem de ser o deslocamento inteiro a partir do comeco do
    ; segmento, e nao a partir do ecra: e assim que o desenho o divide em
    ; paragrafo e offset (ver desenhar_ecra).
    ; O fboff tem de passar por um registo, por duas razoes ao mesmo tempo: um
    ; "add" nao soma memoria com memoria, e o "fboff" sem os colchetes e lido
    ; como um numero - o ENDERECO da variavel e nao o que ela vale - que era o
    ; que punha a imagem uns KB para dentro do ecra sem ninguem dar por isso.
    mov ax, [fboff]
    add [endereco], ax
    adc word [endereco + 2], 0

    ; --- e a paleta, se o ecra e de 8 bits -------------------------------
    ; Num ecra de 8 bits por pixel o que vai para o ecra e o indice da cor, e
    ; o ecra so conhece cores pelos indices que tem no registo de cores.
    ; O registo de cores da VGA e o que decide o que se ve: cada pixel do ecra
    ; e um indice nesse registo. O nucleo, antes de chamar este decodificador,
    ; deixou a paleta do ecra como o video.dr a poe (indice 0 preto, indice 7
    ; o cinza do texto). A imagem tem uma paleta propria e por isso o
    ; decodificador troca as duas de lugar: le a do ecra e poe a da imagem. A
    ; do ecra fica guardada em BUF_VELHA e e o CMD_REPOR que a repoe - nao o
    ; desenho, que a deixaria no ecra com a paleta do video.dr durante a
    ; espera. Quem escreve o titulo a seguir e o nucleo, e as cores desse texto
    ; sao as do video.dr, nao as de um pixel da imagem.
    ;
    ; A paleta so interessa nos ecras de 8 bits por pixel (o indice do pixel e
    ; a cor); nos de 16 e 32 o pixel ja traz a cor e o registo nao e lido.
    cmp byte [bpp8], 1
    jne .desenhar_ecra
    call ler_paleta             ; a paleta do ecra, para o CMD_REPOR repor
    call trocar_paleta          ; a paleta da imagem
    mov byte [pal_trocada], 1   ; a partir de agora e o CMD_REPOR que repoe

.desenhar_ecra:
    call desenhar_ecra
    jc  .fim

    ; --- o registo de cores fica com a imagem -----------------------------
    ; E o que o ecra tem de mostrar enquanto o logo esta no ecra: as cores
    ; da imagem, e nao as do video.dr. Por isso o CMD_REPOR e um comando a
    ; parte (o nucleo chama-o depois da espera, antes de limpar o ecra e de
    ; escrever o titulo) e nao uma coisa que o desenho faca ao sair: se fosse
    ; aqui, o logo ficava no ecra durante a espera com a paleta do video.dr -
    ; que e a paleta de um ecra de texto, com o indice 0 preto e o 7 o cinza
    ; do texto - e as cores da imagem sortiam todas trocadas.
.fim:
    clc
    ret

.erro_ecra:
    mov word [CONTRATO + II_ERRO], ERRO_ECRA
    stc
    ret
.erro_tamanho:
    mov word [CONTRATO + II_ERRO], ERRO_TAMANHO
    stc
    ret
.erro_img:
    mov word [CONTRATO + II_ERRO], ERRO_IMG
    stc
    ret

; ============================================================================
; repor: o comando que o nucleo chama
;   entrada: nada - a paleta antiga esta em BUF_VELHA (ver ler_paleta)
;   saida:   CF=0 sempre (ver a nota)
;
;   Nao ha erro nenhum aqui, e e de proposito. O comando pede "deixa o registo
;   de cores como o nucleo o deixou", e se o desenho nao trocou a paleta - um
;   ecra de 16 ou 32 bits, um CMD_REPOR sem CMD_DESENHAR antes, um desenho que
;   se recusou antes de chegar a troca - o registo ja esta como o nucleo
;   o deixou. E um ecra de 8 bits em que o CMD_REPOR chega sem o desenho ter
;   trocado nada: o DAC fica como estava, que e o que se pedia.
;
;   O nucleo chama este comando depois da espera e antes de limpar o ecra, e
;   chama-o sempre que ha codigo - mesmo que o desenho tenha falhado, porque o
;   texto que vem a seguir e do nucleo e as suas cores sao as do video.dr.
; ============================================================================
repor:
    cmp byte [bpp8], 1           ; so os ecras de 8 bits por pixel tem paleta
    jne .ja_esta
    cmp byte [pal_trocada], 0
    je  .ja_esta
    call repor_paleta
    mov byte [pal_trocada], 0
.ja_esta:
    clc
    ret

; ============================================================================
; cabecalho_img: le do .img as medidas da imagem e diz se servem
;   entrada: nada - o segmento da imagem esta no II_IMG_SEG do CONTRATO, e o
;            DS tem de estar no segmento deste codigo
;   saida:   CF=0 se o que o .img diz presta | CF=1 se nao
;
;   O DS NUNCA muda aqui dentro: e o segmento deste codigo durante a rotina toda
;   (e a saida). E o ES que vai a imagem, e as leituras do .img sao todas
;   "es:[...]". E o inverso do que se faria com o DS, e a razao e uma so: o
;   "[i_larg]" e um deslocamento dentro do segmento deste codigo, e quem decide
;   o segmento de um "[...]" e o DS (ou o prefixo que vem antes), nao o nome do
;   campo. Com o DS na imagem, o "mov [i_larg], ax" escrevia a largura da
;   imagem por cima da paleta do .img e a variavel do codigo ficava a zero -
;   e o desenho ai com a paleta em cima dos pixels, a ler a linha errada, sem
;   dar erro nenhum. A paleta e o unico sitio onde o codigo e o ficheiro se
;   cruzam, por isso e ai que esse erro aparecia e nao em mais lado nenhum.
;
;   O ES e reposto em todas as saidas: o ES do desenho e o framebuffer, e quem
;   vem a seguir (o trocar_paleta) precisa de o encontrar como o deixou.
;
;   O que se verifica:
;     - a versao do .img, outra vez (a primeira foi lida byte a byte no
;       desenho, para o erro sair antes de se meter o ES no sitio errado);
;     - largura e altura nao nulas: uma imagem de 0 pixels nao tem pixels;
;     - a largura cabe no bloco de linha (TAM_LINHA), que e o limite do
;       desenho;
;     - a paleta cabe na memoria que este codigo tem: o .img traz sempre 256
;       entradas e este codigo reserva sempre 256, por isso o que se verifica
;       e so que o .img diz ter 256 ou menos;
;     - os pixels estao depois da paleta, e o ficheiro inteiro cabe num
;       segmento: o desenho le o .img com um segmento e um deslocamento de 16
;       bits, e uma imagem que passe da marca dos 64 KiB seria lida a partir do
;       principio outra vez - em vez de dar erro, dava outra imagem.
; ============================================================================
cabecalho_img:
    push es                      ; o ES do desenho e o framebuffer
    mov ax, [CONTRATO + II_IMG_SEG]
    test ax, ax
    jz  .mal                   ; sem imagem nao ha cabecalho para ler
    mov es, ax                   ; ES = a imagem; o DS continua a ser o codigo

    ; --- a versao do formato ---------------------------------------------
    cmp word [es:IMG_VERSAO], VERSAO_IMG
    jne .mal
    ; --- a largura e a altura --------------------------------------------
    mov ax, [es:IMG_LARG]
    test ax, ax
    jz  .mal                   ; largura zero: nao ha linha nenhuma
    cmp ax, TAM_LINHA
    ja  .larga                 ; mais larga do que o bloco onde a copiamos
    mov [i_larg], ax
    mov ax, [es:IMG_ALT]
    test ax, ax
    jz  .mal                   ; altura zero: nao ha imagem nenhuma
    mov [i_alt], ax
    ; --- a paleta ---------------------------------------------------------
    ; O que interessa do campo IMG_CORES e que ele exista e nao diga um numero
    ; de cores que a paleta do .img nao tem (que sao 256). O nome do campo e
    ; o numero de cores que a imagem usa; o decodificador poe as 256 na mesma
    ; porque o registo da VGA tem 256 e nao ha meio de por so as que a imagem
    ; usa (e porque assim o resto do registo fica como o video.dr o deixou,
    ; que e o que o texto do nucleo precisa).
    mov ax, [es:IMG_CORES]
    test ax, ax
    jz  .mal                   ; paleta de zero cores: nao ha cor nenhuma
    cmp ax, ENTRADAS
    ja  .mal                   ; mais de 256: nao cabe no registo da VGA
    mov [i_cores], ax
    ; --- onde estao os pixels ---------------------------------------------
    ; O .img traz sempre os pixels a 0x410 (o conversor escreve assim), mas
    ; confirmar e o que impede que um .img com os pixels fora do sitio - ou com
    ; a paleta por cima deles - seja lido como se estivesse bem. O limite e o
    ; fim da paleta: os pixels tem de comecar depois dela.
    mov ax, [es:IMG_PIX]
    cmp ax, IMG_PAL + TAM_PALETA
    jb  .mal
    mov [i_pix], ax
    ; --- e o ficheiro inteiro cabe num segmento? ---------------------------
    ; O desenho le o .img com um segmento e um deslocamento de 16 bits, por isso
    ; o ultimo pixel tem de caber nos 64 KiB do segmento. Um .img maior nao dava
    ; erro nenhum: o que passasse da marca seria lido outra vez desde o
    ; principio, e a imagem saia com a paleta em cima dos pixels.
    ;
    ; A conta e de 32 bits (o produto de duas palavras pode ser de 32), o
    ; "adc dx, 0" e o que soma o deslocamento dos pixels ao produto sem perder o
    ; carry, e o "cmp dx, 0" e o que pergunta se sobrou alguma coisa acima dos
    ; 64 KiB.
    mov ax, [i_larg]
    mul word [i_alt]           ; DX:AX = o numero de pixels
    add ax, [i_pix]             ; mais o sitio onde eles comecam
    adc dx, 0
    cmp dx, 0
    ja  .mal                   ; passou da marca: o .img nao cabe
    pop es
    clc
    ret
.larga:
    mov word [CONTRATO + II_ERRO], ERRO_LARGA
.mal:
    pop es
    stc
    ret
; ============================================================================
; copiar_paleta: traz a paleta do .img para este codigo
;   entrada: nada (o .img tem de estar no II_IMG_SEG)
;
;   A paleta do .img tem 8 bits por canal (0 a 255). O registo da VGA tem 6
;   (0 a 63), e a conta e o >> 2 - o mesmo que o video.dr faz com o cinza
;   claro (42 * 4 = 168). Numa tela de 16 ou 32 bits por pixel nao ha
;   registo de paleta nenhum: os canais vao como estao, e quem escreve no
;   ecra e que os converte no formato do modo. Por isso a paleta e guardada
;   sempre com 8 bits, e a reducao a 6 e so na hora de a escrever no
;   registo.
; ============================================================================
copiar_paleta:
    mov ax, [CONTRATO + II_IMG_SEG]
    mov ds, ax
    ; --- copiar a paleta, linha a linha, 256 entradas de 4 bytes ----------
    ; Sao 256 "rep movsb" de 4 bytes (ou um "rep movsb" de 1024, que e o
    ; mesmo e mais curto: a paleta sao 1024 bytes a contar de IMG_PAL). Um
    ; unico "rep movsb" de 1024 bytes: o DS e a imagem (a origem), o ES e este
    ; codigo (o destino) e o SI e o offset da paleta no .img.
    ;
    ; O ES tem de ser posto aqui, e nao aproveitado do que la estava: o "rep
    ; movsb" copia de DS:SI para ES:DI, e o ES que se encontra aqui e o do
    ; nucleo (e o dao o video.dr e o teclado.dr quando o codigo acaba de
    ; responder). Com o ES no nucleo a paleta ia parar a memoria do nucleo, a
    ; PALETA deste codigo ficava como estava e o desenho usava cores de outro
    ; ficheiro - sem dar erro nenhum, porque nao houve erro nenhum.
    push es                      ; o ES do desenho e o framebuffer
    mov ax, SEG_BASE             ; este codigo
    mov es, ax
    mov si, IMG_PAL
    mov di, PALETA
    mov cx, TAM_PALETA
    cld
    rep movsb
    pop es                       ; e ja era o ES de sempre
    ; --- o DS volta ao codigo ---------------------------------------------
    mov ax, SEG_BASE
    mov ds, ax
    ret

; ============================================================================
; desenhar_ecra: escreve a imagem no framebuffer, linha a linha
;   entrada: o que o desenho mediu (dlarg, dalt, i_larg, i_alt, i_pix, o
;            endereco do canto, o bpp8 e o segmento do framebuffer)
;   saida:   nada (a conta de pixels e feita no fim, de uma vez)
;
;   -------------------------------------------------------------------------
;   O ENCOLHIMENTO
;
;   O nucleo reduziu a imagem (quando o ecra e menor do que ela) e disse o
;   tamanho a que ficou. O decodificador tem de ir buscar, para cada pixel do
;   ecra, o pixel certo da imagem: e isso que sao as duas contas de cada linha
;   e de cada coluna.
;
;   A coluna de origem de um pixel e (coluna do ecra * largura da imagem) /
;   largura desenhada, e a linha de origem e o mesmo pelo outro lado:
;
;       coluna = cx * i_larg / dlarg          linha = y * i_alt / dalt
;
;   O "mul" e o "div" de 16 bits com o produto de 32 bits, porque tanto
;   cx * i_larg como y * i_alt passam de 65535 assim que a imagem tem mais de
;   256 pixels de lado. E o mesmo cuidado que o nucleo tem em calcular a
;   posicao de um pixel (ver bloco, em nucleo.asm).
;
;   Nao ha interpolacao, e e de proposito: o encolhimento com qualidade
;   (o filtro LANCZOS) ja foi feito no conversor, quando a imagem ainda era
;   grande. Refazer a media aqui daria um resultado pior e por duas vezes: o
;   pixel do ecra seria a media de uma media. Um pixel da imagem, o mais
;   proximo, e o que se ve.
;
;   -------------------------------------------------------------------------
;   A LINHA ANTES DO DESENHO
;
;   A imagem e copiada linha a linha para BUF_LINHA antes de a linha ser
;   desenhada, e nao pixel a pixel. A razao e o DS: o desenho precisa de ler o
;   indice da paleta de um segmento (o do .img) e de escrever a cor no
;   framebuffer, que e de outro segmento (o ES). Sao dois segmentos e o
;   codigo tem dois (o DS e o ES), mas o codigo tambem precisa do DS para si -
;   a paleta, as medidas, a conta das escritas. Copiar a linha deixa o DS
;   sempre no decodificador e usa o ES so para o framebuffer.
;
;   O custo e uma copia por linha (a largura da imagem em bytes) e o
;   trabalho por pixel fica so com o que e preciso: a conta da coluna e a
;   leitura do indice.
; ---------------------------------------------------------------------------
desenhar_ecra:
    mov ax, [CONTRATO + II_FBSEG]
    mov [fb_seg], ax               ; o segmento base do framebuffer

    ; --- o canto superior esquerdo, ja em bytes --------------------------
    ; O desenho fez a conta: DX:AX = fboff + y*byteslin + x*bpp8 (ver o desenho).
    ; Daqui em diante e uma soma de "byteslin" por linha, que e o que faz o
    ; proximo pixel cair na linha seguinte sem recalcular o produto.
    mov [linha], 0                 ; a linha do ecra que se esta a desenhar

.linha_ecra:
    ; --- a linha da imagem que esta linha do ecra vai buscar ------------
    ; sy = y * i_alt / dalt. O "div" divide DX:AX pelo divisor, por isso o
    ; divisor nao pode estar no DX (o mesmo cuidado que o nucleo tem em
    ; calcular_escala): o DX e a metade alta do dividendo e o divisor vai no
    ; SI, que esta livre nesta fase.
    mov ax, [linha]
    xor dx, dx
    mul word [i_alt]               ; DX:AX = linha do ecra * altura da imagem
    mov si, [dalt]
    div si                         ; AX = a linha da imagem
    xor dx, dx
    mul word [i_larg]              ; DX:AX = linha da imagem * largura
    add ax, [i_pix]                ; + o comeco dos pixels no .img
    adc dx, 0
    ; DX tem de ser zero: o cabecalho ja confirmou que a imagem inteira cabe
    ; num segmento de 64 KiB (por isso o offset de uma linha e um numero de
    ; 16 bits e um segmento so chega). Se nao coubesse, esta soma perdia o
    ; que transbordou e a linha ia ser lida do sitio errado.
    mov bx, ax                     ; BX = a linha, em bytes, dentro do .img

    ; --- copiar essa linha da imagem para o bloco -----------------------
    ; Um unico "rep movsb": o DS e o .img (a origem), o ES e este codigo (o
    ; destino) e o CX e a largura da imagem em bytes.
    ;
    ; O ES tem de ser este codigo durante a copia - o "rep movsb" escreve no ES,
    ; e o ES que se encontra aqui e o do nucleo (ver a nota do copiar_paleta). O
    ; "push es"/"pop es" e o que deixa o desenho continuar com o ES de sempre
    ; (que ainda nem e o do framebuffer, porque o framebuffer e posto mais
    ; abaixo, ja com o endereco desta linha).
    push ds                        ; o DS e codigo durante o desenho
    push es
    mov cx, [i_larg]              ; as medidas leem-se ANTES de o DS mudar:
    mov si, bx                    ; com o DS na imagem, o "[i_larg]" lia a
    mov ax, [CONTRATO + II_IMG_SEG]   ; paleta do .img e nao a medida do codigo
    mov ds, ax                    ; (a paleta e a unica coisa que os dois
    mov ax, SEG_BASE               ; segmentos partilham, e dai a leitura vir
    mov es, ax                   ; certa por sorte nenhuma)
    mov di, BUF_LINHA
    cld
    rep movsb
    pop es
    pop ds                         ; e ja era o DS de sempre

    ; --- onde fica esta linha no ecra? ----------------------------------
    ; O endereco e um deslocamento a partir do comeco do segmento base do
    ; framebuffer (o fboff ja la esta), e um deslocamento desse tem de virar
    ; um paragrafo e um offset: o segmento e o segmento base mais os paragrafos
    ; que o endereco passa, e o offset e o que sobra dentro desse segmento. Sao
    ; as duas metades do endereco cada uma no seu sitio - por isso e que a conta
    ; e de 32 bits.
    ;
    ; A metade de cima sao os paragrafos acima do framebuffer, e como um
    ; paragrafo sao 16 bytes e um segmento sao 65536 (65536 / 16 = 4096 =
    ; 2^12) eles entram deslocados 12 para a esquerda. A metade de baixo ja e o
    ; offset dentro do segmento e nao se mexe nela.
    ;
    ; Numa tela pequena - um 320x200 de 8 bits, 64000 bytes - a metade de
    ; cima e sempre zero e o "shl" nunca faz nada, e e por isso que um erro
    ; aqui passou tanto tempo despercebido: o segmento saia certo, o offset
    ; saia torto, e a imagem aparecia amontoada dentro das primeiras 4 KiB do
    ; ecra em vez de ocupar as 200 linhas. Num 1920x1080 de 32 bits (a linha
    ; 300 ja passou dos 64 KiB) o mesmo erro punha a imagem na linha errada.
    mov ax, [endereco + 2]         ; AX = a metade de cima do endereco
    shl ax, 12                     ; os paragrafos que o endereco passa
    add ax, [fb_seg]               ; mais o segmento base do framebuffer
    mov es, ax                     ; ES = o framebuffer desta linha
    mov di, [endereco]             ; DI = o offset dentro desse segmento

    ; --- a linha, pixel a pixel -----------------------------------------
    ; O contador e o BP porque o CX e a coluna de origem (que e preciso logo
    ; a seguir) e o CL e o registo dos "shr", que so existem porque o ECMA nao
    ; tem deslocamento por imediato. O SI e o offset dentro da linha (e da
    ; paleta): o ECMA so multiplica o indice por 2, 4 ou 8 quando ele e o SI, o
    ; DI ou o BP - o CX nao escala, e "cx * 4" nao e um endereco.
    ; O BP e a coluna que se esta a escrever no ecra, e por isso que conta a
    ; SUBIR: o DI tambem sobe um byte por pixel, e as duas coisas a subir e o
    ; que poe a coluna "n" da imagem no pixel "n" da linha do ecra. Um
    ; "dec bp" aqui daria a linha do ecra ao contrario - o logo sairia
    ; espelhado, e num desenho quase simetrico isso passa despercebido.
    ;
    ; E a coluna e nao o numero de pixels que faltam, o que faz o laco ter de
    ; recomecar em zero e nao em "dlarg": a comecar em "dlarg" a coluna zero
    ; nunca seria desenhada e o ecra ficaria com a primeira coluna preta e a
    ; ultima com o byte de fora da linha copiada. Um "dlarg" de zero nao
    ; escreve nada, que e o que um rectangulo de largura zero quer dizer.
    xor bp, bp                   ; a coluna 0 e a primeira a escrever
.coluna:
        mov ax, bp
        xor dx, dx
        mul word [i_larg]           ; DX:AX = coluna * largura da imagem
        mov si, [dlarg]
        div si                     ; AX = a coluna na imagem
        mov cx, ax                  ; CX = a coluna na imagem

        cmp byte [bpp8], 1
        je  .oito
        cmp byte [bpp8], 2
        je  .dezasseis
        ; --- trinta e dois bits por pixel -------------------------------
        ; O pixel e a cor da paleta tal e qual, em quatro bytes: e o que um
        ; modo de 32 bits sem paleta nenhuma espera (o byte de cima e o alpha
        ; e fica a zero). Por isso nao ha aqui nenhuma conta, ao contrario dos
        ; outros dois modos: o 16 tem de agrupar os canais em 5/6/5 bits e o 8
        ; nem sequer olha para a cor.
        mov si, cx
        shl si, 1
        shl si, 1                   ; SI = a cor * 4
        mov al, [ds:PALETA + si]
        mov ah, [ds:PALETA + si + 1]
        mov bl, [ds:PALETA + si + 2]
        mov bh, 0                   ; o 4.o byte do pixel e zero (o alpha)
        mov [es:di], ax
        mov [es:di + 2], bx
        add di, 4                   ; 4 bytes por pixel
        jmp .fim_coluna

.dezasseis:
        ; --- dezasseis bits por pixel: 5/6/5 ----------------------------
        ; O pixel e uma palavra: 5 bits de vermelho (15..11), 6 de verde
        ; (10..5) e 5 de azul (4..0). Os 8 bits do .img encolhem para os
        ; 5/6/5 do modo - o >> 3 do vermelho e do azul e o >> 2 do verde, que
        ; e o que fica depois de se deitarem fora os bits de baixo que este
        ; ecra nao tem.
        ;
        ; O CL e o registo dos "shr" e o "shl": um deslocamento de 16 bits so
        ; aceita o 1 como imediato, e o 11 e o 5 tem de ir no CL. Por isso o
        ; vermelho e o azul vao para o AX (que ja tem o R em cima) e o verde
        ; para o DX, que os junta com o "or".
        mov si, cx
        shl si, 1
        shl si, 1                   ; SI = a cor * 4
        mov al, [ds:PALETA + si]
        mov cl, 3
        shr al, cl                   ; o vermelho em 5 bits
        mov ah, 0
        mov cl, 11
        shl ax, cl                   ; AX = vermelho nos bits 15..11
        mov dl, [ds:PALETA + si + 1]
        xor dh, dh
        mov cl, 2
        shr dx, cl                   ; o verde em 6 bits
        mov cl, 5
        shl dx, cl                   ; DX = verde nos bits 10..5
        or  ax, dx
        mov dl, [ds:PALETA + si + 2]
        xor dh, dh
        mov cl, 3
        shr dx, cl                   ; o azul em 5 bits
        or  ax, dx
        mov [es:di], ax
        add di, 2                   ; 2 bytes por pixel
        jmp .fim_coluna

.oito:
        ; --- oito bits por pixel: o indice, tal e qual -------------------
        ; Num ecra de 8 bits por pixel o pixel e um indice de paleta, e o que
        ; diz que cor e esse indice e o registo da VGA - que a trocar_paleta
        ; poe antes do desenho. Por isso o que vai para o ecra e o indice e
        ; nao a cor: e o byte que a linha copiada devolve.
        mov si, cx
        mov al, [ds:BUF_LINHA + si]
        mov [es:di], al
        inc di                       ; 1 byte por pixel

.fim_coluna:
        inc bp
        ; O "ds:" e obrigatorio: com o BP no comando, o ECMA da a este
        ; operando o segmento SS, e o SS deste codigo e zero (ver a nota do
        ; segmento). Sem o prefixo o "cmp" lia o dlarg no segmento 0 e o laco
        ; terminava a primeira linha.
        cmp bp, word [ds:dlarg]
        jb  .coluna

    ; --- a proxima linha e "bytes por linha" mais abaixo -----------------
    ; Com o carry: o endereco e de 32 bits e uma linha a mais pode transbordar
    ; os 16 bits de baixo (numa tela alta, a linha 300 ja passa dos 64 KiB).
    ; O AX e a soma: nenhuma instrucao do 8086 soma memoria com memoria, o
    ; endereco vai para o AX (que ja pode ser gasto nesta altura do laco) e o
    ; "adc" leva o carry para os 16 bits de cima.
    mov ax, [bytes_linha]
    add word [endereco], ax
    adc word [endereco + 2], 0
    inc word [linha]
    mov ax, [dalt]             ; o "cmp" compara registo com registo
    cmp word [linha], ax
    jb  .linha_ecra

    ; --- quantos pixels foram escritos ----------------------------------
    ; E o rectangulo inteiro (dlarg * dalt) e nao uma contagem pixel a pixel:
    ; o laco escreve sempre todos, ou falha antes de escrever algum - os erros
    ; de ecra, de tamanho e de imagem sao todos verificados antes do desenho
    ; comecar, e depois do desenho nao ha o que falhar.
    mov ax, [dlarg]
    xor dx, dx
    mul word [dalt]
    mov [CONTRATO + II_PIXELS], ax
    mov [CONTRATO + II_PIXELS + 2], dx
    ret

; ============================================================================
; trocar_paleta: poe no DAC da VGA a paleta do .img
;   entrada: nada (PALETA tem a paleta do .img)
;
;   -------------------------------------------------------------------------
;   O DAC E O REGISTO CERTO
;
;   A cor de um pixel e o indice que o ecra le no DAC, e o DAC escreve-se
;   pelos registos 0x3C8 (o indice da cor) e 0x3C9 (os tres canais, vermelho,
;   verde e azul). Nao pela INT 10h: o BIOS desta maquina aceita o pedido de
;   paleta - tanto na forma de cor a cor (AX=1010h) como na de bloco
;   (AX=1002h) - e nao escreve nada, devolvendo os registos como estavam e sem
;   nenhum sinal de erro. Com a forma de bloco a imagem aparecia com as cores
;   do ecra e nada dizia porque; com a de cor a cor, o BIOS devolvia os
;   registos a zero (a BIOS leu-os, so que nao os preencheu) e a paleta do
;   ecra ficava a zeros depois da leitura.
;
;   Vale a pena frisar o porque disto nao e um descuido: um BIOS que responde
;   a um servico que nao faz e pior do que um BIOS que nao responde, porque o
;   primeiro obriga a desconfiar e o segundo da para se proteger.
;
;   Nos registos nao ha duvida nenhuma - e o que o hardware le a cada pixel, e
;   o que o ecra le. Nao ha servico para falhar.
;
;   Os canais sao de 6 bits (0 a 63) e os do .img sao de 8 (0 a 255): a conta
;   e o >> 2, que e o mesmo que o video.dr faz ao escrever o cinza claro
;   (42 * 4 = 168). Sao 256 escritas, uma por cor, porque cada "out" leva um
;   canal so.
; ---------------------------------------------------------------------------
trocar_paleta:
    mov si, PALETA
    mov byte [ind_pal], 0
.escreve:
    mov dx, DAC_POR
    mov al, [ind_pal]           ; AL = o indice da cor
    out dx, al

    mov dx, DAC_DA
    mov al, [si]                ; o vermelho do .img
    shr al, 1
    shr al, 1                   ; 8 bits -> 6 bits
    out dx, al
    mov al, [si + 1]            ; o verde
    shr al, 1
    shr al, 1
    out dx, al
    mov al, [si + 2]            ; o azul
    shr al, 1
    shr al, 1
    out dx, al

    add si, 4
    inc byte [ind_pal]
    cmp byte [ind_pal], 0       ; o indice deu a volta: foram as 256
    jne .escreve
    ret

; ============================================================================
; ler_paleta: le as 256 cores do DAC da VGA para BUF_VELHA
;   entrada: nada
;   saida:   as 256 cores em BUF_VELHA, tres bytes por cor
;
;   A leitura e pelos mesmos registos, com oendereco espelhado: escreve-se o
;   indice em 0x3C7 e a cor vem de 0x3C9, na mesma ordem (vermelho, verde,
;   azul). E o que o ecra tem no momento em que a imagem vai entrar no sitio -
;   e o que o repor_paleta volta a escrever, byte a byte.
;
;   Nao e preciso nenhuma proteccao contra uma BIOS que nao sabe ler (ja nao
;   ha BIOS no meio): o que le esta a ler, e se o registo nao houver - ecra sem
;   DAC - o pixel sairia a cor nenhuma, que e o mesmo que aconteceria sem isto
;   piores.
; ============================================================================
ler_paleta:
    mov si, BUF_VELHA
    mov byte [ind_pal], 0
.le:
    mov dx, DAC_LE
    mov al, [ind_pal]           ; AL = o indice da cor
    out dx, al

    mov dx, DAC_DA
    in al, dx                   ; o vermelho
    mov [si + 2], al
    in al, dx                   ; o verde
    mov [si + 1], al
    in al, dx                   ; o azul
    mov [si], al

    add si, 3
    inc byte [ind_pal]
    cmp byte [ind_pal], 0       ; o indice deu a volta: foram as 256
    jne .le
    ret

; ============================================================================
; repor_paleta: volta a por no DAC a paleta que o ecra tinha antes da imagem
;   entrada: nada (a paleta antiga esta em BUF_VELHA)
;
;   A mesma forma da troca, com os tres bytes de cada cor tal e qual como o
;   ler_paleta os trouxera: o repor e o inverso do ler e nao uma paleta
;   inventada aqui. E o que faz o texto que o nucleo escreve a seguir sair com
;   o cinza que o video.dr deixou no indice 7, e nao com a cor de um pixel da
;   imagem.
; ============================================================================
repor_paleta:
    mov si, BUF_VELHA
    mov byte [ind_pal], 0
.escreve:
    mov dx, DAC_POR
    mov al, [ind_pal]           ; AL = o indice da cor
    out dx, al

    mov dx, DAC_DA
    mov al, [si + 2]            ; o vermelho, como o ler o deu
    out dx, al
    mov al, [si + 1]            ; o verde
    out dx, al
    mov al, [si]                ; o azul
    out dx, al

    add si, 3
    inc byte [ind_pal]
    cmp byte [ind_pal], 0       ; o indice deu a volta: foram as 256
    jne .escreve
    ret

; ============================================================================
; area de dados
; ============================================================================
cmd:            dw CMD_DESENHAR     ; o comando que o nucleo mandou
seg_contrato:   dw 0                ; o segmento da IMG_INFO do nucleo
off_contrato:   dw 0                ; o deslocamento da IMG_INFO

; O que o desenho mediu do que o nucleo disse e do que o .img diz. Ficam na
; memoria porque sao usados em dois sitios (o desenho e o laco de pixels) e o
; DS e o segmento deste codigo.
dlarg:          dw 0                ; a largura que a imagem vai ter no ecra
dalt:           dw 0                ; a altura que a imagem vai ter no ecra
i_larg:         dw 0                ; a largura da imagem
i_alt:          dw 0                ; a altura da imagem
i_cores:        dw 0                ; quantas cores a paleta do .img tem
i_pix:          dw 0                ; onde os pixels comecam no .img
bytes_linha:    dw 0                ; bytes por linha do framebuffer
x_ecra:         dw 0                ; a coluna do canto (o II_X do nucleo)
y_ecra:         dw 0                ; a linha do canto (o II_Y do nucleo)
bpp8:           db 0                ; bytes por pixel: 1, 2 ou 4
fb_seg:         dw 0                ; o segmento base do framebuffer
fboff:          dw 0                ; o deslocamento do framebuffer no segmento
endereco:       dd 0                ; o endereco do pixel de cima a esquerda
linha:          dw 0                ; a linha do ecra que se esta a desenhar
pal_trocada:    db 0                ; o registo de cores e o da imagem?

; ---------------------------------------------------------------------------
; A paleta do .img (1 KiB), a paleta antiga do ecra (768 bytes, tres por cor)
; e a linha de imagem (1 KiB). Ficam aqui em vez de um bloco so porque e o
; que o desenho precisa delas em simultaneo: a paleta do .img e consultada a
; cada pixel (nos ecras de 16 e 32 bits), a paleta antiga e lida antes da
; troca e escrita depois, e a linha copiada e o que garante o DS quieto no
; segmento deste codigo.
; ---------------------------------------------------------------------------
ind_pal:       db 0x00               ; o indice da cor, na troca e na leitura
PALETA:     times TAM_PALETA db 0x00    ; a paleta do .img: { r, g, b, 0 }
BUF_VELHA:  times TAM_VELHA   db 0x00    ; a paleta que o ecra tinha: { r, g, b }
BUF_LINHA:  times TAM_LINHA  db 0x00    ; a linha da imagem que se esta a desenhar

; ---------------------------------------------------------------------------
; A copia local da IMG_INFO do nucleo. O codigo inteiro usa enderecos normais
; em DS e nunca troca de segmento para ir ler um campo do contrato (e o mesmo
; vaivem que o video.dr faz com o VIDEO_INFO).
; ---------------------------------------------------------------------------
CONTRATO:
    times INFO_N db 0x00

; ---------------------------------------------------------------------------
; O codigo, os dados e os tres blocos tem de caber antes do FIM: o inicio.mai
; carrega esta imagem em sectores inteiros e o que ele nao leu e lixo. O
; "times" faz o nasm falhar se um dia o codigo crescer demais, em vez de a
; imagem escrever por cima do fim dela.
;
; O limite e o que o DEC_SET do inicio.mai le (12 KiB), e nao um numero
; escolhido aqui: e o mesmo sitio em que o inicio.mai poe a imagem, e um
; "times" a mais daria uma imagem que o inicio.mai carrega a meio.
; ---------------------------------------------------------------------------
FIM equ $-$$
    times 0x3000 - FIM db 0x00
