; ============================================================================
;  Maisus - drivers/teclado.asm
;  Driver de teclado PS/2 - build 0.12.2026
;
;  Carregado por inicio.mai da ISO (/drivers/teclado.dr) para 0x60000. A entrada
;  e TEC_INI = 0x0008, logo depois do cabecalho de 8 bytes.
;  Convencao de entrada: CS=IP=TEC_INI, ES:BX = TEC_INFO de quem chamou, CX =
;  comando. O DS de quem chama fica como esta: este driver poe o seu proprio e
;  repoe-o antes de sair (tem estado proprio, como o rato).
;
;  missao: ler as teclas do controlador (o 8042) e nao da BIOS.
;
;          O controlador tem duas tomadas - o teclado numa e o rato na outra -
;          e as duas partilham as portas 0x60 (dados) e 0x64 (estado). Uma
;          tecla e um scancode que o controlador poe na porta de dados; a
;          BIOS, no arranque, tem um handler proprio na IRQ1 que os le e os
;          guarda. Este driver substitui-o: instala o seu handler na IRQ1
;          (vetor 0x09), le o scancode da porta 0x60 e guarda-o num buffer
;          circular proprio. Quem quer uma tecla chama o comando CMD_LER e
;          recebe-a no TEC_INFO.
;
;          E o mesmo desenho do rato: o handler corre sempre que o teclado tem
;          uma tecla, independentemente de quem esta no CPU, e o estado vive no
;          segmento do driver. A diferenca e que o rato reporta sozinho e o
;          teclado so fala quando se lhe toca - e por isso que o handler e o
;          unico que le a porta 0x60.
;
;  saida: nada. O driver escreve na TEC_INFO de quem chamou e, no CMD_LER,
;         devolve o CF (CF=0 e "havia tecla e vem no TEC_INFO", CF=1 e "nao ha
;         tecla nenhuma").
;
;  NOTAS para quem continuar:
;
;  1. O scancode de uma tecla vem em dois pedacos: a maioria das teclas manda
;     um byte so, mas as teclas alargadas (as setas do teclado numerico, o
;     enter do teclado numerico) mandam primeiro o prefixo E0 e so depois o
;     scancode. O handler guarda os dois: o scancode no byte baixo do registo
;     e o prefixo no byte alto. E o que deixa o enter normal (0x1C) e o do
;     teclado numerico (E0 1C) reconhecidos como a mesma tecla.
;
;  2. O bit mais alto do scancode diz se a tecla foi largada (1) ou premida
;     (0). O buffer so guarda as premiadas; as largadas servem para limpar os
;     modificadores (shift, ctrl, alt) e sao deitadas fora depois disso.
;
;  3. A sequencia da tecla Pause (E1 1D 45 E1 9D C5) nao tem scancode unico:
;     e um prefixo E1 seguido de cinco bytes. O handler ignora os cinco bytes
;     a seguir a um E1. Nenhuma tecla util comeca por E1.
;
;  4. A instalacao (CMD_INI) corre com o IF desligado: a porta 0x60 e
;     partilhada com o rato e, enquanto se troca o vetor da IRQ1 e se fala com
;     o controlador, nao se quer nenhum dos dois a consumir respostas. O "cli"
;     e o "sti" ficam aqui dentro, e nao a cargo de quem chama.
; ============================================================================

BITS 16

; Endereco LINEAR onde o inicio.mai carrega este ficheiro, e o segmento
; correspondente (o mesmo par que o inicio.asm usa em TEC_SEG).
SEG_BASE   equ 0x60000 >> 4      ; 0x6000 - o segmento deste codigo

CMD_INI    equ 0                 ; inicializar: instalar o handler e ligar o teclado
CMD_LER    equ 1                 ; tirar a proxima tecla do buffer

; ---------------------------------------------------------------------------
; TEC_INFO: a estrutura com que quem chama e o driver falam.
;
; Os numeros abaixo sao o contrato. Quem chama tem as mesmas definicoes em
; inicio.asm e em nucleo.asm: nenhum dos tres pode mudar um valor sem mudar os
; outros.
;
;   TI_ASSIN    db 'TEC1'    assinatura; quem chama escreve, o driver confirma
;   TI_VERSAO   dw          versao do contrato (2). Quem chama escreve 0xFFFF
;                            - "ainda nao ha ninguem aqui" - e o driver escreve
;                            a sua: como nenhum dos dois escreve o mesmo valor,
;                            o que estiver la depois da chamada so pode ter
;                            vindo de o driver ter entrado mesmo
;   TI_FLAGS    dw          bit 0: ha tecla no buffer (posto pelo CMD_LER)
;   TI_ESTADO   db          o registo de estado do controlador (porta 0x64)
;   TI_TECLA    db          o scancode da ultima tecla lida (sem o prefixo)
;   TI_PREF     db          o prefixo da ultima tecla: 0 normal, 0xE0 alargada
;   TI_MODS     db          os modificadores: bit0 shift, bit1 ctrl, bit2 alt
;
; A estrutura tem 12 bytes. Quem chama poe a assinatura e a versao a 0xFFFF; o
; driver confirma a assinatura e escreve a versao. O TI_TECLA, o TI_PREF e o
; TI_MODS sao preenchidos pelo CMD_LER; o TI_ESTADO, pelo CMD_INI.
; ---------------------------------------------------------------------------
TI_ASSIN   equ 0x00
TI_VERSAO  equ 0x04
TI_FLAGS   equ 0x06
TI_ESTADO  equ 0x08
TI_TECLA   equ 0x09
TI_PREF    equ 0x0A
TI_MODS    equ 0x0B
TEC_INFO_N equ 12

ASSINATURA equ 0x31434554        ; 'T','E','C','1' por ordem de bytes
VERSAO_CONTRATO equ 2

FLAG_HA_TECLA equ 0x01           ; o bit 0 do TI_FLAGS

MOD_SHIFT  equ 0x01              ; os bits do TI_MODS (e do [mods] aqui dentro)
MOD_CTRL   equ 0x02
MOD_ALT    equ 0x04

; ---------------------------------------------------------------------------
; O 8042. Portas: 0x60 dados, 0x64 estado (leitura) e comandos (escrita).
; O estado interessa por tres bits:
;   bit0  ha um byte para ler (OBF)
;   bit1  o 8042 ainda nao aceitou o ultimo pedido (IBF)
;   bit5  o byte que esta a espera veio do canal auxiliar (o rato)
; ---------------------------------------------------------------------------
PORT_DADOS  equ 0x60
PORT_ESTADO equ 0x64
EST_OBF     equ 0x01
EST_IBF     equ 0x02
EST_AUX     equ 0x20

CMD_LIGA_TEC equ 0xAE            ; liga o canal do teclado (o 0x64)
TEC_HABILITA equ 0xF4            ; teclado: comeca a varrer (o 0x60)

; Vetor da IRQ1 na IVT: a IRQ1 e a interrupcao 0x09 e o vetor vive em 0x09*4.
VETOR_IRQ1  equ 0x09 * 4         ; 0x0024

; ---------------------------------------------------------------------------
; Os modificadores, pelos scancodes das teclas correspondentes. O shift tem
; duas teclas (esquerda e direita); o ctrl e o alt tambem chegam alargados
; (E0 1D e E0 38), mas o scancode e o mesmo - por isso ha so um numero por
; modificador. O bit e posto na tecla premida e tirado na largada (o scancode
; com o bit 7 a 1).
; ---------------------------------------------------------------------------
TEC_SHIFT_E equ 0x2A
TEC_SHIFT_D equ 0x36
TEC_CTRL    equ 0x1D
TEC_ALT     equ 0x38

; ---------------------------------------------------------------------------
; O buffer circular das teclas. Cada entrada e um word: o scancode no byte
; baixo e o prefixo no byte alto (ver a nota 1). Os indices sao deslocamentos
; em BYTES dentro do buffer - por isso andam de 2 em 2 - e BUF_BYTES e potencia
; de dois para o "and" fazer as vezes do modulo. O buffer enche e, a partir
; dai, as teclas novas sao deitadas fora: nunca se perde a mais antiga, que e
; a que a pessoa ja tinha pedido.
; ---------------------------------------------------------------------------
BUF_N      equ 32
BUF_BYTES  equ BUF_N * 2
BUF_MASK   equ BUF_BYTES - 1

; ---------------------------------------------------------------------------
; Cabecalho do driver (8 bytes), igual ao dos outros: quem chama le a
; assinatura no primeiro dword da imagem antes de chamar o driver, e a entrada
; comeca depois dela. Quem chama tem a mesma conta (TEC_INI = 8).
; ---------------------------------------------------------------------------
    dd ASSINATURA               ; 'T','E','C','1'
    dw VERSAO_CONTRATO          ; versao do contrato que este driver fala
    dw 0x0000                   ; reservado
TEC_INI equ $ - $$             ; deslocamento da entrada dentro da imagem

; ---------------------------------------------------------------------------
; start: a entrada do driver
;   entrada: CX = comando, ES:BX = a TEC_INFO de quem chamou
;
;   O DS passa a ser o deste codigo porque o estado proprio (o buffer, os
;   modificadores, o prefixo) vive aqui; e reposto antes do "retf", como faz o
;   driver do rato. O regresso e "retf" porque quem chamou foi um "call" de
;   segmento.
; ---------------------------------------------------------------------------
start:
    push ds
    mov ax, cs
    mov ds, ax                  ; o estado proprio vive neste segmento
    cli                         ; a porta 0x60 e partilhada: sem IRQ a meio

    cmp cx, CMD_INI
    je  .iniciar
    cmp cx, CMD_LER
    je  .ler
    jmp .fora                   ; comando que nao existe: nao se faz nada

; --- CMD_INI: instalar o handler e ligar o teclado -------------------------
.iniciar:
    cmp dword es:[bx], ASSINATURA   ; a estrutura e mesmo nossa? se nao for,
    jne .fora                       ; e quem chamou que mandou a estrutura
                                    ; errada e nao se escreve nada nela
    call instalar_irq1
    call iniciar_teclado

    ; estado novo: buffer vazio, sem prefixo e sem modificadores
    mov byte [n_buf], 0
    mov byte [pos_entrada], 0
    mov byte [pos_saida], 0
    mov byte [prefixo], 0
    mov byte [pular], 0
    mov byte [mods], 0

    ; --- a resposta --------------------------------------------------------
    mov byte es:[bx + TI_FLAGS], 0
    in al, PORT_ESTADO
    mov byte es:[bx + TI_ESTADO], al
    mov word es:[bx + TI_VERSAO], VERSAO_CONTRATO
    mov dword es:[bx + TI_ASSIN], ASSINATURA
    jmp .fora

; --- CMD_LER: tirar a proxima tecla do buffer ------------------------------
.ler:
    cmp dword es:[bx], ASSINATURA
    jne .fora
    ; O tirar usa o BX como indice dentro do buffer e por isso destroi-o; mas o
    ; BX e a TEC_INFO de quem chamou, e e nela que a resposta vai escrita. Sem
    ; isto a resposta cai no sitio errado - o BX ja vale 2, o deslocamento da
    ; proxima tecla, e os campos vao parar a ES:0x0002, por cima do codigo de
    ; quem chamou. Guarda-se e repoe-se: e o que o contrato promete (quem
    ; chama conta com o BX depois de o driver sair).
    push bx
    call tirar                  ; CF=0 e AX = prefixo:scancode; CF=1 vazio
    pop bx
    jc  .vazio
    mov byte es:[bx + TI_TECLA], al
    mov byte es:[bx + TI_PREF], ah
    mov al, [mods]
    mov byte es:[bx + TI_MODS], al
    mov al, 0                   ; as flags dizem se ha mais teclas a espera
    cmp byte [n_buf], 0
    je  .sem_mais
    mov al, FLAG_HA_TECLA
.sem_mais:
    mov byte es:[bx + TI_FLAGS], al
    clc
    jmp .fora
.vazio:
    mov byte es:[bx + TI_FLAGS], 0
    stc

.fora:
    sti
    pop ds
    retf

; ---------------------------------------------------------------------------
; instalar_irq1: poe o handler no vetor 0x09 e destrava a IRQ1 no primeiro PIC
;   O vetor da IRQ1 vive na IVT a 0x09 * 4 = 0x0024 (offset) e 0x0026 (segmento).
;   A IRQ1 e do primeiro PIC: destrava-se o bit 1 da mascara (porta 0x21).
; ---------------------------------------------------------------------------
instalar_irq1:
    push ds
    push es
    mov ax, ds
    mov es, ax                  ; ES = o segmento deste codigo
    xor ax, ax
    mov ds, ax                  ; a IVT comeca em 0:0
    mov word [VETOR_IRQ1], irq1 ; o offset do handler (o "irq1" e um offset aqui)
    mov word [VETOR_IRQ1 + 2], es
    mov dx, 0x21
    in al, dx
    and al, 0xFD                ; bit 1 a zero: IRQ1 destravada
    out dx, al
    pop es
    pop ds
    ret

; ---------------------------------------------------------------------------
; iniciar_teclado: liga o canal do teclado e diz-lhe para varrer
;   O 0xAE liga o canal do teclado no controlador; o 0xF4 vai pelo canal de
;   dados e diz ao teclado para comecar a reportar teclas. A resposta do 0xF4
;   (0xFA) fica no buffer de saida e e preciso tira-la daqui: com o handler ja
;   instalado, um 0xFA esquecido havia de ser lido como se fosse uma tecla.
;   Por isso se espera por ele e se limpa o que ficar.
; ---------------------------------------------------------------------------
iniciar_teclado:
    call esperar_ibi
    mov dx, PORT_ESTADO
    mov al, CMD_LIGA_TEC
    out dx, al

    call esperar_ibi
    mov dx, PORT_DADOS
    mov al, TEC_HABILITA
    out dx, al
    call esperar_obf            ; a resposta 0xFA (com tempo limite)
    call limpar_saida           ; e o que mais estiver a espera
    ret

; ---------------------------------------------------------------------------
; esperar_ibi: espera que o 8042 aceite um pedido (o buffer de entrada vazio)
;   Le o estado (0x64) ate o bit 1 (IBF) ficar a zero. O limite e grande mas
;   existe: um controlador que nunca responda nao pode travar o arranque.
; ---------------------------------------------------------------------------
esperar_ibi:
    push cx
    mov cx, 0xFFFF
.volta:
    mov dx, PORT_ESTADO
    in al, dx
    test al, EST_IBF
    jz  .pronto
    loop .volta
.pronto:
    pop cx
    ret

; ---------------------------------------------------------------------------
; esperar_obf: espera que haja um byte para ler (o bit 0 do estado)
; ---------------------------------------------------------------------------
esperar_obf:
    push cx
    mov cx, 0xFFFF
.volta:
    mov dx, PORT_ESTADO
    in al, dx
    test al, EST_OBF
    jnz .pronto
    loop .volta
.pronto:
    pop cx
    ret

; ---------------------------------------------------------------------------
; limpar_saida: le e deita fora o que estiver a espera no buffer de saida
; ---------------------------------------------------------------------------
limpar_saida:
    push cx
    mov cx, 0x100
.volta:
    mov dx, PORT_ESTADO
    in al, dx
    test al, EST_OBF
    jz  .pronto
    mov dx, PORT_DADOS
    in al, dx
    loop .volta
.pronto:
    pop cx
    ret

; ---------------------------------------------------------------------------
; irq1: o handler do teclado
;   Corre sempre que o teclado poe um byte na porta de dados. Le o scancode,
;   entrega-o ao decodificador (que o guarda ou o usa para os modificadores) e
;   manda o EOI ao primeiro PIC. Guarda tudo o que usa porque interrompeu o
;   que estava a correr (o inicio.mai, ou a interface), e poe o DS no segmento
;   deste codigo para chegar ao estado proprio.
; ---------------------------------------------------------------------------
irq1:
    push ax
    push bx
    push cx
    push dx
    push ds
    push es
    mov ax, cs
    mov ds, ax
    mov es, ax

    mov dx, PORT_ESTADO
    in al, dx
    test al, EST_OBF
    jz  .fim
    test al, EST_AUX            ; veio do rato? entao nao e nossa
    jnz .fim
    mov dx, PORT_DADOS
    in al, dx
    call tratar_scancode

.fim:
    mov al, 0x20
    out 0x20, al                ; EOI no primeiro PIC (a IRQ1 e a 1)

    pop es
    pop ds
    pop dx
    pop cx
    pop bx
    pop ax
    iret

; ---------------------------------------------------------------------------
; tratar_scancode: decide o que fazer com um byte vindo da porta 0x60
;   entrada: AL = o scancode
;
;   Um scancode pode ser: o prefixo de uma tecla alargada (E0), o comeco da
;   sequencia do Pause (E1), uma tecla premida (bit 7 a 0), uma tecla largada
;   (bit 7 a 1) ou um pedaco do Pause. So as teclas premiadas entram no buffer;
;   as largadas limpam os modificadores e o resto e deitado fora.
; ---------------------------------------------------------------------------
tratar_scancode:
    ; A cauda de uma sequencia E1 (Pause): deitada fora ate ao fim
    cmp byte [pular], 0
    je  .sem_pular
    dec byte [pular]
    ret
.sem_pular:
    cmp al, 0xE1
    jne .sem_e1
    mov byte [pular], 5         ; o E1 mais cinco bytes
    ret
.sem_e1:
    cmp al, 0xE0
    jne .sem_e0
    mov byte [prefixo], 0xE0    ; o scancode a seguir e alargado
    ret
.sem_e0:
    test al, 0x80
    jz  .premida
    ; tecla largada: limpa o modificador, se o era, e deixa cair a tecla
    call marcar_solta
    mov byte [prefixo], 0
    ret
.premida:
    call marcar_pressa          ; marca o modificador (se o era)
    mov ah, [prefixo]           ; e junta o prefixo ao scancode
    mov byte [prefixo], 0
    jmp empurra                 ; AX entra no buffer e volta ao handler

; ---------------------------------------------------------------------------
; marcar_pressa: poe o bit do modificador se esta tecla for uma das dele
;   entrada: AL = o scancode. O AX e guardado porque o chamador ainda precisa
;   do AL (o scancode).
; ---------------------------------------------------------------------------
marcar_pressa:
    push ax
    cmp al, TEC_SHIFT_E
    je  .shift
    cmp al, TEC_SHIFT_D
    je  .shift
    cmp al, TEC_CTRL
    je  .ctrl
    cmp al, TEC_ALT
    je  .alt
    jmp .fim
.shift:
    or  byte [mods], MOD_SHIFT
    jmp .fim
.ctrl:
    or  byte [mods], MOD_CTRL
    jmp .fim
.alt:
    or  byte [mods], MOD_ALT
.fim:
    pop ax
    ret

; ---------------------------------------------------------------------------
; marcar_solta: tira o bit do modificador na largada da tecla
;   entrada: AL = o scancode com o bit 7 a 1 (o "solta")
; ---------------------------------------------------------------------------
marcar_solta:
    push ax
    and al, 0x7F                ; o scancode de fabrica
    cmp al, TEC_SHIFT_E
    je  .shift
    cmp al, TEC_SHIFT_D
    je  .shift
    cmp al, TEC_CTRL
    je  .ctrl
    cmp al, TEC_ALT
    je  .alt
    jmp .fim
.shift:
    and byte [mods], 0xFF - MOD_SHIFT
    jmp .fim
.ctrl:
    and byte [mods], 0xFF - MOD_CTRL
    jmp .fim
.alt:
    and byte [mods], 0xFF - MOD_ALT
.fim:
    pop ax
    ret

; ---------------------------------------------------------------------------
; empurra: poe uma entrada (AX = prefixo:scancode) no fim do buffer
;   O buffer nao cresce: quando esta cheio, a tecla nova e deitada fora.
; ---------------------------------------------------------------------------
empurra:
    cmp byte [n_buf], BUF_N
    jae .cheio
    mov bl, [pos_entrada]
    xor bh, bh
    mov [buf + bx], ax
    add bl, 2
    and bl, BUF_MASK
    mov [pos_entrada], bl
    inc byte [n_buf]
.cheio:
    ret

; ---------------------------------------------------------------------------
; tirar: tira a entrada mais antiga do buffer
;   saida: AX = prefixo:scancode e CF=0 se havia tecla; CF=1 se o buffer
;          estava vazio (e o AX nao diz nada)
; ---------------------------------------------------------------------------
tirar:
    cmp byte [n_buf], 0
    je  .vazio
    mov bl, [pos_saida]
    xor bh, bh
    mov ax, [buf + bx]
    add bl, 2
    and bl, BUF_MASK
    mov [pos_saida], bl
    dec byte [n_buf]
    clc
    ret
.vazio:
    stc
    ret

; ---------------------------------------------------------------------------
; area de dados (o estado proprio do driver)
; ---------------------------------------------------------------------------
n_buf:       db 0x00             ; quantas teclas estao no buffer
pos_entrada: db 0x00             ; onde entra a proxima (deslocamento em bytes)
pos_saida:   db 0x00             ; de onde sai a proxima (deslocamento em bytes)
prefixo:     db 0x00             ; o prefixo da tecla a caminho: 0 ou 0xE0
pular:       db 0x00             ; bytes que faltam da sequencia do Pause (0 = fora)
mods:        db 0x00             ; os modificadores (ver MOD_*)
buf:         times BUF_BYTES db 0x00  ; o buffer circular das teclas