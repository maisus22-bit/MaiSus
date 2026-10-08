; ============================================================================
;  Maisus - drivers/video.asm
;  Driver de video - build 0.5.2026
;
;  Carregado por inicio.mai da ISO (/drivers/video.dr) para 0xE000. A entrada e
;  DRV_INI = 0x0008, logo depois do cabecalho de 8 bytes.
;  Convencao de entrada: CS=IP=DRV_INI, DS=SEG_DRV, ES:BX = VIDEO_INFO do
;  nucleo, CX = comando.
;
;  missao: (1) ver as informacoes que a BIOS da do dispositivo de video e
;              registar no VIDEO_INFO os modos em que se pode escrever;
;          (2) por o video no modo que o nucleo escolheu e devolver como e o
;              ecra (framebuffer, resolucao, cor do texto).
;  saida: nada. O driver nao escreve pixels: muda de modo e descreve o ecra.
;         Quem limpa o ecra e escreve a mensagem e o nucleo.
;
;  NOTA sobre a BIOS: as funcoes VESA (AX=4F00h/4F01h/4F02h) estragam o SI, e
;  o mesmo se presume do resto. Por isso nenhuma chamada a BIOS e feita com o
;  SI a segurar alguma coisa importante.
; ============================================================================

BITS 16

; Endereco LINEAR onde o inicio.mai carrega este ficheiro, e o segmento
; correspondente. Sao dois numeros diferentes e o nucleo tem o mesmo cuidado
; (ver nucleo.asm): o segmento 0xE00 cobre 0xE000, o endereco linear 0xE000.
SEG_BASE   equ 0xE000 >> 4        ; 0xE00 - o segmento deste codigo

; NAO ha ORG aqui, ao contrario do nucleo.asm. O ORG no formato bin faz o NASM
; somar a origem a todos os rotulos, e o codigo deste driver vive todo
; relativo ao segmento (DS = 0x0E00): um rotulo tem de valer o deslocamento
; dentro da imagem, que e o mesmo numero que o rotulo sem ORG. Com o ORG o
; "classicos" valia 0xE307 em vez de 0x0307 e o driver lia a tabela no sitio
; errado. Quem precisa de endereco linear tira-o de SEG_BASE << 4, como o
; nucleo faz.

CMD_DETETAR equ 0                 ; ver o dispositivo e encher a tabela de modos
CMD_APLICAR equ 1                 ; por o video no modo escolhido

TIPO_CLASSICO equ 0               ; INT 10h AX=<modo>
TIPO_VESA     equ 1               ; INT 10h AX=4F02h

; ---------------------------------------------------------------------------
; VIDEO_INFO: a estrutura com que o nucleo e o driver falam.
;
; Os numeros abaixo sao o contrato. O nucleo tem as mesmas definicoes em
; nucleo.asm: nenhum dos lados pode mudar um valor sem mudar o outro.
;
;   VI_ASSIN    db 'VID1'    assinatura; o nucleo escreve, o driver confirma
;   VI_VERSAO   dw          versao do contrato (1)
;   VI_VBE      dw          1 se a BIOS tem a VESA BIOS Extension
;   VI_VBE_VER  dw          versao do VBE (0x0200, 0x0300, ...)
;   VI_CAPS     dw          capacidades do VBE, tal como a BIOS as escreve
;   VI_MEM      dd          memoria de video que a BIOS reporta, em bytes
;   VI_NMODOS   dw          quantos modos o driver registou na tabela
;   VI_MODO     dw          o modo escolhido: escrito pelo nucleo
;   VI_TIPO     dw          como activar esse modo: TIPO_CLASSICO ou TIPO_VESA
;   VI_LARG     dw          largura do modo aplicado
;   VI_ALT      dw          altura do modo aplicado
;   VI_BPP      dw          bits por pixel
;   VI_BYTESLIN dw          bytes por linha do framebuffer
;   VI_FBSEG    dw          segmento do framebuffer
;   VI_FBOFF    dw          offset do framebuffer dentro do segmento
;   VI_COR      dd          valor de pixel do texto (ou indice de paleta)
;   VI_FLAGS    dw          bit 0: o driver nao vio nenhum modo VESA e usou
;                            a tabela de reserva
;
; A seguir vem a tabela de modos: MAX_MODOS entradas de TAM_ENTRADA bytes,
; cada uma com  { dw modo; dw tipo; dw largura; dw altura; dw bits por pixel }
; ---------------------------------------------------------------------------
VI_ASSIN    equ 0x00
VI_VERSAO   equ 0x04
VI_VBE      equ 0x06
VI_VBE_VER  equ 0x08
VI_CAPS     equ 0x0A
VI_MEM      equ 0x0C
VI_NMODOS   equ 0x10
VI_MODO     equ 0x12
VI_TIPO     equ 0x14
VI_LARG     equ 0x16
VI_ALT      equ 0x18
VI_BPP      equ 0x1A
VI_BYTESLIN equ 0x1C
VI_FBSEG    equ 0x1E
VI_FBOFF    equ 0x20
VI_COR      equ 0x22
VI_FLAGS    equ 0x26
VI_TAB      equ 0x28

TAM_ENTRADA equ 10                 ; bytes por modo na tabela
ENT_MODO    equ 0
ENT_TIPO    equ 2
ENT_LARG    equ 4
ENT_ALT     equ 6
ENT_BPP     equ 8

MAX_MODOS   equ 64                 ; quantos modos cabem na tabela
CONTRATO_N  equ VI_TAB + MAX_MODOS * TAM_ENTRADA

; O driver trabalha sobre uma copia local do VIDEO_INFO (ver CONTRATO no fim do
; ficheiro): assim o codigo todo usa enderecos normais em DS e nunca tem de
; trocar de segmento para ir ler ou escrever um campo. No fim copia tudo de
; volta para o nucleo.
CONTRATO   equ 0x0700              ; a copia local (tem de bater certo com o fim)

ASSINATURA equ 0x31444956          ; 'V','I','D','1' por ordem de bytes
VERSAO_CONTRATO equ 1

; A lista de modos que o VBE devolve pode ser longa demais (a norma nao poe
; limite). Corta-se por aqui para o driver nunca dar a volta ao fim dela.
MAX_LISTA  equ 256

; ---------------------------------------------------------------------------
; O bloco de informacao do VBE (INT 10h AX=4F00h) e o ModeInfoBlock de cada
; modo (INT 10h AX=4F01h) sao structures da BIOS, com o desenho que a norma
; da. Os campos que este driver usa:
;
;   bloco de informacao (VBE 2.0 em diante):
;     0x00 4 bytes  assinatura "VESA"
;     0x04 2 bytes  versao do VBE
;     0x08 4 bytes  apontador para a lista de modos (deslocamento, segmento)
;     0x0C 2 bytes  memoria de video, em blocos de 64 KiB
;     0x2A 2 bytes  capacidades do VBE
;
;   ModeInfoBlock:
;     0x00 2 bytes  atributos do modo (bit 0 suportado, 1 graficos, 7 LFB)
;     0x02 2 bytes  bytes por linha
;     0x04 2 bytes  largura
;     0x06 2 bytes  altura
;     0x0C 1 byte   bits por pixel
;     0x28 4 bytes  endereco do framebuffer linear
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Cabecalho do driver (8 bytes). O nucleo le a assinatura no primeiro dword da
; imagem antes de chamar o driver: e a prova de que o inicio.mai carregou mesmo
; um driver e nao lixo. A entrada do driver e por isso depois do cabecalho, e o
; nucleo tem a mesma conta (DRV_INI = 8 em nucleo.asm).
; ---------------------------------------------------------------------------
    dd ASSINATURA               ; 'V','I','D','1'
    dw VERSAO_CONTRATO          ; versao do contrato que este driver fala
    dw 0x0000                   ; reservado
DRV_INI equ $ - $$             ; deslocamento da entrada dentro da imagem

start:
    ; --- guarda o que o nucleo passou --------------------------------------
    mov [cmd], cx                    ; o "rep movsb" da frente gasta o CX
    mov [seg_contrato], es
    mov [off_contrato], bx

    ; --- traz o VIDEO_INFO para o segmento do driver -----------------------
    ;   O "rep movsb" copia DS:SI -> ES:DI. Para trazer o VIDEO_INFO do nucleo
    ;   (e nao o levar, que e o que a copia de saida faz) os dois segmentos
    ;   trocam de papel: o DS passa a ser o do nucleo (a origem, ES:BX que o
    ;   nucleo passou) e o ES passa a ser o do driver (o destino, a copia
    ;   local). Sem a troca o "cmp" seguinte via zero e o driver recusava o
    ;   trabalho; so trocar o DS mandava a copia para outro sitio, porque o
    ;   destino do "rep movsb" e ES:DI e nao DS:DI.
    push es                      ; DS = driver, ES = nucleo
    push ds
    mov ax, es
    mov ds, ax                   ; DS = o segmento do nucleo (origem)
    mov ax, SEG_BASE
    mov es, ax                   ; ES = o segmento do driver (destino)
    mov si, bx                   ; origem: o VIDEO_INFO que o nucleo passou
    mov di, CONTRATO             ; destino: a copia local do driver
    mov cx, CONTRATO_N
    cld
    rep movsb
    pop ds
    pop es                       ; volta aos segmentos do driver e do nucleo

    ; --- o cabecalho esta bem? --------------------------------------------
    cmp dword [CONTRATO + VI_ASSIN], ASSINATURA
    jne  .mal
    mov word [CONTRATO + VI_VERSAO], VERSAO_CONTRATO
    mov word [CONTRATO + VI_NMODOS], 0
    mov word [CONTRATO + VI_FLAGS], 0

    ; --- o que o nucleo quer que o driver faca? ---------------------------
    ;   "aplicar" e uma rotina como "detetar": entra-se com "call", para o
    ;   "ret" dela ter aonde voltar. Entrar com "je" deixaria o "ret" dela a
    ;   tirar da pilha o IP do "call de segmento" do nucleo sem o CS, e o
    ;   driver saltava para 0x0E00:0x00xx em vez de regressar.
    mov cx, [cmd]
    cmp cx, CMD_APLICAR
    je  .quer_aplicar
    call detetar
    jmp devolver
.quer_aplicar:
    call aplicar
    jmp devolver
.mal:
    stc
    jmp devolver

; ---------------------------------------------------------------------------
; devolver: reenvia o VIDEO_INFO ao nucleo
;   O "rep movsb" mexe em CX, SI e DI mas nao nos flags: o CF que o comando
;   deixou atravessa a copia e chega ao nucleo.
;
;   O regresso e "retf" (e nao "ret") porque quem chamou foi um "call" de
;   segmento: a pilha tem o IP e o CS do nucleo, e as duas coisas tem de sair.
;   As rotinas do meio do driver usam "ret" normal.
; ---------------------------------------------------------------------------
devolver:
    mov es, [seg_contrato]            ; a INT 10h estragou o ES
    mov di, [off_contrato]
    mov si, CONTRATO
    mov cx, CONTRATO_N
    cld
    rep movsb
    retf

; ---------------------------------------------------------------------------
; detetar: le as informacoes do dispositivo de video e escreve o relatorio
; ---------------------------------------------------------------------------
detetar:
    call ler_vbe                      ; a BIOS tem VESA? versao? memoria?
    call modos_vesa                   ; que modos VESA servem, se algum?
    cmp word [CONTRATO + VI_NMODOS], 0
    jne  .fim
    call modos_reserva                ; nenhum: a tabela de modos classicos
    mov word [CONTRATO + VI_FLAGS], 1
.fim:
    ret

; ---------------------------------------------------------------------------
; ler_vbe: INT 10h AX=4F00h -> o bloco de informacao do VBE
;   saida: CF=1 se a BIOS nao tem a VESA BIOS Extension
; ---------------------------------------------------------------------------
ler_vbe:
    mov ax, SEG_BASE
    mov es, ax
    mov di, BUF_VBE
    mov ax, 0x4F00
    int 0x10
    jc  .sem
    cmp dword [BUF_VBE], 0x41534556  ; "VESA" por ordem de bytes
    jne .sem

    mov word [CONTRATO + VI_VBE], 1
    mov ax, [BUF_VBE + 4]            ; versao do VBE (0x0200, 0x0300, ...)
    mov [CONTRATO + VI_VBE_VER], ax
    mov ax, [BUF_VBE + 0x2A]         ; capacidades do VBE (offset 0x2A do bloco)
    mov [CONTRATO + VI_CAPS], ax

    ; a memoria vem em blocos de 64 KiB (offset 0x0C do bloco), que e o mesmo
    ; que dizer 65536 = 0x10000 bytes por bloco. Multiplicar por 0x10000 da
    ; palavra de baixo a zero e a palavra de cima igual ao numero de blocos,
    ; por isso e um "mov" em vez de uma multiplicacao.
    mov ax, [BUF_VBE + 0x0C]
    mov word [CONTRATO + VI_MEM], 0
    mov [CONTRATO + VI_MEM + 2], ax
    clc
    ret
.sem:
    mov word [CONTRATO + VI_VBE], 0
    stc
    ret

; ---------------------------------------------------------------------------
; modos_vesa: percorre a lista de modos que o VBE devolveu e regista os que
;             servem. O criterio esta em validar_modo.
; ---------------------------------------------------------------------------
modos_vesa:
    cmp word [CONTRATO + VI_VBE], 0
    je  .fim

    ; --- onde esta a lista de modos ----------------------------------------
    mov ax, [BUF_VBE + 0x08]         ; deslocamento
    mov bx, [BUF_VBE + 0x0A]         ; segmento
    mov [lst_seg], bx
    mov [lst_off], ax
    or  ax, bx
    jz  .fim                          ; lista a null: nao ha nada a percorrer
    mov word [lst_restam], MAX_LISTA

.procurar:
    ; --- proximo numero de modo da lista ---------------------------------
    ; A lista vive no segmento da BIOS: o SI tem de estar carregado antes de
    ; mexer no DS, senao ia ler o ponteiro no segmento errado.
    mov si, [lst_off]
    push ds
    mov ax, [lst_seg]
    mov ds, ax
    lodsw                            ; AX = proximo modo
    mov bx, ds
    pop ds
    add word [lst_off], 2            ; a lista e uma fila de palavras

    cmp ax, 0xFFFF                    ; 0xFFFF fecha a lista
    je  .fim
    dec word [lst_restam]
    jz  .fim
    test ax, ax
    jz  .procurar                     ; o modo 0 nao e um modo de video

    ; --- o que a BIOS diz sobre este modo? -------------------------------
    ; O numero do modo vai para a memoria antes da chamada: a INT 10h estraga o
    ; AX, e e o numero do modo que tem de sobreviver ate ao registo.
    mov [modo_atual], ax
    mov cx, ax
    call pedir_modo
    jc  .procurar
    call validar_modo
    jc  .procurar

    ; --- registar ---------------------------------------------------------
    mov cx, [CONTRATO + VI_NMODOS]
    call nova_entrada                 ; devolve DI; preserva CX
    jc  .procurar
    mov ax, [modo_atual]
    mov [di + ENT_MODO], ax
    mov word [di + ENT_TIPO], TIPO_VESA
    mov ax, [BUF_MODO + 0x04]         ; largura
    mov [di + ENT_LARG], ax
    mov ax, [BUF_MODO + 0x06]         ; altura
    mov [di + ENT_ALT], ax
    mov al, [BUF_MODO + 0x0C]         ; bits por pixel
    mov ah, 0
    mov [di + ENT_BPP], ax
    inc word [CONTRATO + VI_NMODOS]
    jmp .procurar
.fim:
    ret

; ---------------------------------------------------------------------------
; pedir_modo: INT 10h AX=4F01h -> o ModeInfoBlock do modo em CX
;   entrada: CX = numero do modo
;   saida:   CF=1 se a BIOS recusar
; ---------------------------------------------------------------------------
pedir_modo:
    mov ax, SEG_BASE
    mov es, ax
    mov di, BUF_MODO
    mov ax, 0x4F01
    int 0x10
    ret                              ; a INT 10h devolve o CF

; ---------------------------------------------------------------------------
; validar_modo: o bloco que a BIOS devolveu diz mesmo um modo em que se possa
;               escrever?  (AX = modo, BUF_MODO preenchido)
;   saida: CF=0 se o modo serve | CF=1 se nao
;
; Os criterios:
;   - atributos: bits 0 (o modo existe), 1 (e graficos) e 7 (ha framebuffer
;     linear). Sem framebuffer linear nao ha onde escrever;
;   - pelo menos 320x200: abaixo disso nao ha modo de video que preste;
;   - 8, 16 ou 32 bits por pixel: sao os que o nucleo sabe escrever. O 24 fica
;     de fora de proposito (escrever um pixel de 24 bits e escrever tres
;     bytes) e o driver tambem o nao anuncia;
;   - framebuffer linear dentro de 1 MiB. O CPU esta em modo real e so
;     endereca 1 MiB: o QEMU, por exemplo, poe o seu em 0xE0000000 e nao ha
;     caminho para la sem modo protegido. E por esta regra que a lista da VESA
;     pode vir vazia e sobrar a tabela de reserva.
; ---------------------------------------------------------------------------
validar_modo:
    mov bx, [BUF_MODO + 0x00]
    and bx, 0x0183                    ; bits 0, 1 e 7
    cmp bx, 0x0183
    jne  .nao

    mov bx, [BUF_MODO + 0x04]         ; largura
    cmp bx, 320
    jb   .nao
    mov bx, [BUF_MODO + 0x06]         ; altura
    cmp bx, 200
    jb   .nao

    mov bl, [BUF_MODO + 0x0C]         ; bits por pixel
    cmp bl, 8
    je   .framebuffer
    cmp bl, 16
    je   .framebuffer
    cmp bl, 32
    jne  .nao

.framebuffer:
    ; o endereco do framebuffer tem 32 bits, e a comparacao e feita com DX:AX
    ; (a parte de cima) porque 0xA0000 e 0xFFF00 nao cabem em 16 bits - uma
    ; comparacao de 16 bits daria sempre a resposta errada.
    mov ax, [BUF_MODO + 0x28]
    mov dx, [BUF_MODO + 0x2A]
    or  ax, dx
    jz  .nao                          ; sem framebuffer: nao ha onde escrever
    cmp dx, 0x0A                      ; pelo menos a janela VGA (0xA0000)
    jb  .nao
    cmp dx, 0x0F                      ; e no maximo 1 MiB
    jb  .framebuffer_ok
    ja  .nao
    cmp ax, 0xFF00                    ; 0xF0000: deixa folga para o ultimo pixel
    ja  .nao
.framebuffer_ok:
    clc
    ret
.nao:
    stc
    ret

; ---------------------------------------------------------------------------
; nova_entrada: endereco da proxima entrada livre da tabela do VIDEO_INFO
;   entrada: CX = quantos modos ja estao registados
;   saida:   DI = endereco da entrada | CF=1 se a tabela esta cheia
;   preserva: AX e CX
;
;   O indice multiplica-se por 10 sem "mul" (que ia mexer no AX): (n*8)+(n*2).
;   Com MAX_MODOS = 64 o produto nunca passa de 630, portanto cabe em 16 bits.
; ---------------------------------------------------------------------------
nova_entrada:
    cmp cx, MAX_MODOS
    jae .cheia
    mov dx, cx
    mov bx, cx
    shl bx, 3                        ; n * 8
    shl dx, 1                        ; n * 2
    add bx, dx                       ; n * 10
    add bx, CONTRATO + VI_TAB
    mov di, bx
    clc
    ret
.cheia:
    stc
    ret

; ---------------------------------------------------------------------------
; modos_reserva: quando a BIOS nao deu nenhum modo VESA aproveitavel, o driver
;               announce os modos classicos que ele proprio sabe por e escrever.
;
;   So entram modos cujo framebuffer caiba inteiro na janela VGA (0xA0000 a
;   0xAFFFF, 64 KiB) sem troca de bancos: em modo real o CPU so endereca
;   1 MiB, e o framebuffer linear da VESA, quando existe, vive muito acima
;   disso. Por isso e um so: o 320x200x256, que precisa de 76.800 bytes.
; ---------------------------------------------------------------------------
modos_reserva:
    mov si, classicos
    ; o contador do ciclo vive na memoria porque nova_entrada usa o BX e o DX
    mov word [cl_restam], CLASSICOS
.proximo:
    mov cx, [CONTRATO + VI_NMODOS]
    call nova_entrada
    jc  .fim
    mov ax, [si + 0]                  ; modo
    mov [di + ENT_MODO], ax
    mov ax, [si + 2]                  ; tipo
    mov [di + ENT_TIPO], ax
    mov ax, [si + 4]                  ; largura
    mov [di + ENT_LARG], ax
    mov ax, [si + 6]                  ; altura
    mov [di + ENT_ALT], ax
    mov ax, [si + 8]                  ; bits por pixel
    mov [di + ENT_BPP], ax
    inc word [CONTRATO + VI_NMODOS]
    add si, CLAS_ENTRADA
    dec word [cl_restam]
    jnz .proximo
.fim:
    ret

; ---------------------------------------------------------------------------
; aplicar: poe o video no modo que o nucleo escolheu e devolve a geometria
;   saida: CF=0 se o modo ficou posto | CF=1 se nao
; ---------------------------------------------------------------------------
aplicar:
    mov ax, [CONTRATO + VI_MODO]
    mov [modo_escolhido], ax
    mov ax, [CONTRATO + VI_TIPO]
    cmp ax, TIPO_VESA
    je  aplicar_vesa
    jmp aplicar_classico

; ---------------------------------------------------------------------------
; aplicar_classico: INT 10h AH=00h com AL=modo, e a paleta de 256 cores
;   A geometria sai da tabela classicos, que e a mesma de onde veio o modo.
; ---------------------------------------------------------------------------
aplicar_classico:
    mov si, classicos
    mov cx, CLASSICOS
.procurar:
    mov ax, [si]
    cmp ax, [modo_escolhido]
    je  .achei
    add si, CLAS_ENTRADA
    loop .procurar
    stc
    ret
.achei:
    mov [cl_entrada], si              ; a INT 10h estraga o SI

    ; --- por o modo -------------------------------------------------------
    mov ax, [si]
    mov ah, 0                         ; AH=00h, AL=modo
    int 0x10

    ; --- paleta: BH = indice, BL = verde, CH = azul, DH = vermelho (0 a 63)
    ; O modo 0x13 poe a paleta VGA por omissao, mas o driver nao confia em
    ; omissoes: o preto (indice 0) e o cinza claro (indice 7) sao posto aqui.
    mov bh, 0
    xor bl, bl
    xor ch, ch
    xor dh, dh
    mov ax, 0x1010
    int 0x10
    mov bh, 7
    mov bl, 42                        ; 42 * 4 = 168, o cinza claro do VGA
    mov ch, 42
    mov dh, 42
    mov ax, 0x1010
    int 0x10

    ; --- geometria do modo posto -----------------------------------------
    mov si, [cl_entrada]
    mov ax, [si + 4]                  ; largura
    mov [CONTRATO + VI_LARG], ax
    mov ax, [si + 6]                  ; altura
    mov [CONTRATO + VI_ALT], ax
    mov ax, [si + 8]                  ; bits por pixel
    mov [CONTRATO + VI_BPP], ax
    mov ax, [si + 10]                 ; bytes por linha
    mov [CONTRATO + VI_BYTESLIN], ax
    mov ax, [si + 12]                 ; segmento do framebuffer
    mov [CONTRATO + VI_FBSEG], ax
    mov word [CONTRATO + VI_FBOFF], 0
    mov ax, [si + 14]                 ; cor do texto (indice de paleta)
    mov [CONTRATO + VI_COR], ax
    mov word [CONTRATO + VI_COR + 2], 0
    clc
    ret

; ---------------------------------------------------------------------------
; aplicar_vesa: INT 10h AX=4F02h, a pedir o framebuffer linear (BX bit 14)
; ---------------------------------------------------------------------------
aplicar_vesa:
    mov cx, [modo_escolhido]
    call pedir_modo
    jc  .falha
    mov ax, [modo_escolhido]
    call validar_modo
    jc  .falha

    ; --- por o modo --------------------------------------------------------
    ; BX bit 14 = 1 pede a BIOS o endereco do framebuffer em ES:DI
    mov bx, 0x4000
    mov cx, [modo_escolhido]
    mov ax, 0x4F02
    int 0x10
    jc  .falha

    ; --- onde ficou o framebuffer? ----------------------------------------
    mov [cl_fbseg], es
    mov [cl_fboff], di
    mov ax, es
    or  ax, di
    jnz .tem_fb                       ; a BIOS devolveu o endereco
    ; a BIOS nem sempre devolve o endereco: nesse caso usa-se o do bloco
    mov ax, [BUF_MODO + 0x28]
    mov [cl_fbseg], ax
    mov word [cl_fboff], 0
.tem_fb:

    ; --- resolucao ---------------------------------------------------------
    mov ax, [BUF_MODO + 0x04]
    mov [CONTRATO + VI_LARG], ax
    mov ax, [BUF_MODO + 0x06]
    mov [CONTRATO + VI_ALT], ax
    mov al, [BUF_MODO + 0x0C]
    mov ah, 0
    mov [CONTRATO + VI_BPP], ax

    ; bytes por linha = largura * bytes por pixel. Usa-se o valor calculado e
    ; nao o que a BIOS escreve no bloco: nos modos VESA esse valor costuma ter
    ; preenchimento no fim da linha, e o nucleo escreve pixel a pixel sem o
    ; levar em conta.
    mov cx, [CONTRATO + VI_BPP]
    shr cx, 3
    mov ax, [CONTRATO + VI_LARG]
    mul cx
    mov [CONTRATO + VI_BYTESLIN], ax

    mov ax, [cl_fbseg]
    mov [CONTRATO + VI_FBSEG], ax
    mov ax, [cl_fboff]
    mov [CONTRATO + VI_FBOFF], ax

    ; --- cor do texto ------------------------------------------------------
    ; 8 bits: o indice 7 da paleta (cinza claro, como no modo classico)
    ; 16 e 32 bits: todos os bits a um, que e branco
    cmp word [CONTRATO + VI_BPP], 8
    je  .cor8
    mov word [CONTRATO + VI_COR], 0xFFFF
    jmp .cor_pronta
.cor8:
    mov word [CONTRATO + VI_COR], 7
.cor_pronta:
    mov word [CONTRATO + VI_COR + 2], 0
    clc
    ret
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; Os modos classicos que este driver sabe por e escrever, com tudo o que e
; preciso para os meter no ecra. A mesma tabela serve para a reserva (quando a
; BIOS nao deu modos VESA) e para o "aplicar", que volta aqui para buscar a
; geometria do modo escolhido.
;   +0  modo | +2 tipo | +4 largura | +6 altura | +8 bits por pixel
;  +10 bytes por linha | +12 segmento do framebuffer | +14 cor do texto
; ---------------------------------------------------------------------------
CLAS_ENTRADA equ 16
classicos:
    dw 0x0013                 ; 320x200x256 (64 KiB de framebuffer cabem na janela)
    dw TIPO_CLASSICO
    dw 320, 200
    dw 8
    dw 320
    dw 0xA000                 ; o framebuffer classico comeca em 0xA0000
    dw 7                      ; indice 7 da paleta: cinza claro
classicos_fim:
CLASSICOS equ (classicos_fim - classicos) / CLAS_ENTRADA

; ---------------------------------------------------------------------------
; area de dados
; ---------------------------------------------------------------------------
cmd:            dw CMD_DETETAR
seg_contrato:   dw 0
off_contrato:   dw 0
lst_off:        dw 0
lst_seg:        dw 0
lst_restam:     dw 0
cl_restam:      dw 0
modo_atual:     dw 0
modo_escolhido: dw 0
cl_entrada:     dw 0
cl_fbseg:       dw 0
cl_fboff:       dw 0

; ---------------------------------------------------------------------------
; A imagem do driver tem de caber na area antes do VIDEO_INFO local, e a area
; toda (codigo + dados + buffers) tem de caber em 4 KiB: sao dois sectores que
; o inicio.mai carrega em 0xE000-0xEFFF. Se um dia o codigo crescer demais,
; o "times" da um numero negativo e o nasm falha em vez de o driver passar a
; escrever por cima de si.
; ---------------------------------------------------------------------------
    times 0x0700 - ($ - $$) db 0x90    ; codigo + dados ate 0x700
CONTRATO_BUF:  times CONTRATO_N db 0x00  ; a copia local do VIDEO_INFO
BUF_VBE:       times 512 db 0x00      ; o bloco de informacao do VBE
BUF_MODO:      times 256 db 0x00      ; o ModeInfoBlock de cada modo
    times 0x1000 - ($ - $$) db 0x00    ; o resto da imagem, a zeros
