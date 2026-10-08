; ============================================================================
;  Maisus - drivers/mouse.asm
;  Driver de rato PS/2 - build 0.12.2026
;
;  Carregado por inicio.mai da ISO (/drivers/mouse.dr) para 0x90000. A entrada
;  e MOU_INI = 0x0008, logo depois do cabecalho de 8 bytes.
;  Convencao de entrada: CS=IP=MOU_INI, ES:BX = MOUSE_INFO de quem chamou, CX =
;  comando. O DS de quem chama fica como esta: este driver poe o seu proprio e
;  repoe-o antes de sair (ao contrario do teclado, que nao tem estado proprio).
;
;  missao: ligar o rato PS/2 e por a posicao do ponteiro a atualizar-se sozinha.
;
;          O controlador (o 8042) tem duas tomadas - o teclado numa e o rato na
;          outra - e as duas partilham as portas. Ligar o rato e, entao, uma
;          sequencia de comandos ao 8042: destravar o relogio do canal auxiliar,
;          ligar a interrupcao desse canal (IRQ12), dizer ao rato para reportar
;          e instalar o handler que le os tres bytes de cada movimento.
;
;          O handler corre sempre que o rato mexe (mesmo depois de o nucleo
;          entregar o controlo a interface: a IRQ nao depende de quem esta no
;          CPU) e vai somando as variacoes a posicao que vive na MOUSE_INFO do
;          nucleo. Quem desenha e a interface (face.grain), que le essa posicao.
;          Este driver nao desenha nada: o que ele sabe poe-lo na MOUSE_INFO,
;          que e toda a resposta.
;
;  saida: nada. O driver escreve na MOUSE_INFO de quem chamou.
;
;  NOTAS para quem continuar:
;
;  1. O rato PS/2 reporta em pacotes de 3 bytes: o primeiro tem os botoes e as
;     bandeiras de estouro, o segundo a variacao em X e o terceiro a variacao
;     em Y (complemento de dois). O bit 3 do primeiro byte e sempre 1, e por
;     isso que o handler o usa para se ressincronizar sempre que perde um byte.
;
;  2. O Y do rato cresce para cima e o Y do ecra cresce para baixo: por isso a
;     variacao entra na posicao ja negada.
;
;  3. A MOUSE_INFO e limitada ao ecra dentro do handler, lendo as medidas ao
;     VIDEO_INFO do nucleo. Assim nao ha uma copia das medidas que possa ficar
;     desatualizada - o ecra e sempre o que o nucleo aplicou.
;
;  4. A sequencia do 8042 fica com o IF desligado (o "cli" do start) porque o
;     handler da BIOS para a IRQ1 tambem le a porta 0x60, e durante a montagem
;     do canal auxiliar nao se quer nenhum dos dois a consumir respostas. O
;     "sti" volta antes de sair.
; ============================================================================

BITS 16

; Endereco LINEAR onde o inicio.mai carrega este ficheiro, e o segmento
; correspondente (o mesmo par que o inicio.asm usa em MOU_SEG).
SEG_BASE   equ 0x90000 >> 4      ; 0x9000 - o segmento deste codigo

CMD_INI    equ 0                 ; inicializar: ligar o rato e o handler

; ---------------------------------------------------------------------------
; MOUSE_INFO: a estrutura com que quem chama e o driver falam.
;
; Os numeros abaixo sao o contrato. Quem chama tem as mesmas definicoes em
; nucleo.asm: nenhum dos dois pode mudar um valor sem mudar o outro.
;
;   MI_ASSIN    db 'MOU1'    assinatura; quem chama escreve, o driver confirma
;   MI_VERSAO   dw          versao do contrato (1). Quem chama escreve 0xFFFF
;                            - "ainda nao ha ninguem aqui" - e o driver escreve
;                            a sua: como nenhum dos dois escreve o mesmo
;                            valor, o que estiver la depois da chamada so pode
;                            ter vindo de o driver ter entrado mesmo
;   MI_X        dw          coluna do ponteiro (o handler mantem)
;   MI_Y        dw          linha do ponteiro (o handler mantem)
;   MI_BOTAO    db          botoes: bit0 esquerdo, bit1 direito, bit2 meio
;   MI_PARC     db          reservado
;
; A estrutura tem 12 bytes (e par). Quem chama poe a assinatura, a versao a
; 0xFFFF e a posicao no centro do ecra; o driver confirma a assinatura e
; escreve a versao; o handler atualiza a posicao e os botoes.
; ---------------------------------------------------------------------------
MI_ASSIN   equ 0x00
MI_VERSAO  equ 0x04
MI_X       equ 0x06
MI_Y       equ 0x08
MI_BOTAO   equ 0x0A
MI_PARC    equ 0x0B

ASSINATURA equ 0x31554F4D        ; 'M','O','U','1' por ordem de bytes
VERSAO_CONTRATO equ 1

; ---------------------------------------------------------------------------
; VIDEO_INFO: so as duas medidas que o handler precisa para limitar o
; ponteiro. A definicao completa esta em nucleo.asm: aqui ficam so os dois
; deslocamentos, que nao podem mudar de um lado so.
;
; O VIDEO_INFO vive num sitio fixo do segmento do nucleo (CONTRATO), e nao
; numa estrutura passada: o handler corre fora de qualquer chamada e so pode
; chegar la pela constante.
; ---------------------------------------------------------------------------
SEG_NUC    equ 0xC00             ; segmento do nucleo
CONTRATO   equ 0x0E00            ; offset do VIDEO_INFO dentro do nucleo
VI_LARG    equ 0x16
VI_ALT     equ 0x18

; ---------------------------------------------------------------------------
; O 8042 e o rato. Portas partilhadas com o teclado:
;   0x60   dados (teclado ou rato, conforme o pedido)
;   0x64   estado (leitura) e comandos (escrita)
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

CMD_LER_CB  equ 0x20            ; le o command byte
CMD_ESCREVE_CB equ 0x60         ; escreve o command byte
CMD_DESLIGA_TEC equ 0xAD        ; poe o teclado em pausa
CMD_DESLIGA_RATO equ 0xA7       ; poe o rato em pausa
CMD_LIGA_RATO equ 0xA8          ; liga o canal auxiliar
CMD_LIGA_TEC equ 0xAE           ; liga o teclado outra vez
CMD_PARA_RATO equ 0xD4          ; o proximo byte e para o rato
RATO_DEFAULTS equ 0xF6          ; rato: volta aos valores de fabrica
RATO_REPORTAR equ 0xF4          ; rato: comeca a reportar

; ---------------------------------------------------------------------------
; Cabecalho do driver (8 bytes), igual ao dos outros: quem chama le a
; assinatura no primeiro dword da imagem antes de chamar o driver - e a prova
; de que o inicio.mai carregou mesmo um driver e nao lixo - e por isso que a
; entrada do driver e depois do cabecalho. Quem chama tem a mesma conta
; (MOU_INI = 8 em inicio.asm).
; ---------------------------------------------------------------------------
    dd ASSINATURA               ; 'M','O','U','1'
    dw VERSAO_CONTRATO          ; versao do contrato que este driver fala
    dw 0x0000                   ; reservado
MOU_INI equ $ - $$             ; deslocamento da entrada dentro da imagem

; ---------------------------------------------------------------------------
; start: a entrada do driver
;   entrada: CX = comando, ES:BX = a MOUSE_INFO de quem chamou
; ---------------------------------------------------------------------------
start:
    push ds
    mov ax, cs
    mov ds, ax                  ; o estado proprio vive neste segmento
    cli                         ; a porta 0x60 e partilhada: sem IRQ a meio

    cmp cx, CMD_INI
    jne .fora                   ; so ha um comando por enquanto

    cmp dword es:[bx], ASSINATURA   ; a estrutura e mesmo nossa? se nao for,
    jne .fora                       ; e quem chamou que mandou a estrutura
                                    ; errada e nao se escreve nada nela

    mov [info_seg], es          ; guardar onde fica a MOUSE_INFO: o handler
    mov [info_off], bx          ; corre fora desta chamada e so a alcanca por aqui

    call instalar_irq12         ; primeiro o handler, so depois o report
    call iniciar_8042

    ; --- a resposta --------------------------------------------------------
    ; A versao e o que prova que o driver entrou: foi posta a 0xFFFF por quem
    ; chamou e so o driver escreve aqui o numero dele. Escreve-se mesmo que o
    ; rato nao responda: ela diz que o driver entrou, nao que o rato esta la.
    mov es, [info_seg]
    mov bx, [info_off]
    mov word es:[bx + MI_VERSAO], VERSAO_CONTRATO
    mov dword es:[bx + MI_ASSIN], ASSINATURA

.fora:
    sti
    pop ds
    retf

; ---------------------------------------------------------------------------
; instalar_irq12: poe o handler no vetor 0x74 e destrava a IRQ12 nos PICs
;   O IRQ12 e o rato: no 8259 poe-se o vetor 0x74 (0x20 + 12) e o vetor vive
;   na IVT a 0x74 * 4 = 0x01D0. O 8086 guarda o offset em 0x01D0 e o segmento
;   em 0x01D2.
;   A IRQ12 esta no segundo PIC (o dos IRQ8..15), ligado ao primeiro pela IRQ2:
;   e preciso destravar o bit 4 da mascara do segundo (0xA1) e o bit 2 da
;   mascara do primeiro (0x21), senao o pedido nunca chega ao CPU.
; ---------------------------------------------------------------------------
instalar_irq12:
    push ds
    push es
    mov ax, ds
    mov es, ax
    xor ax, ax
    mov ds, ax
    mov word [0x01D0], irq12    ; offset do handler
    mov word [0x01D2], es       ; segmento = o deste codigo (CS do start)
    ; primeiro PIC: destravar a cascata (bit 2)
    mov dx, 0x21
    in al, dx
    and al, 0xFB
    out dx, al
    ; segundo PIC: destravar a IRQ12 (bit 4)
    mov dx, 0xA1
    in al, dx
    and al, 0xEF
    out dx, al
    pop es
    pop ds
    ret

; ---------------------------------------------------------------------------
; iniciar_8042: monta o canal auxiliar e poe o rato a reportar
;   A ordem e a classica. Primeiro poem-se os dois dispositivos em pausa, para
;   nada responder enquanto se mexe no command byte; limpa-se o buffer de
;   saida; le-se o command byte, liga-se a interrupcao do rato (bit 1) e
;   destrava-se o relogio do canal auxiliar (bit 5 a zero); escreve-se o
;   command byte; liga-se o canal auxiliar (0xA8) e o teclado (0xAE); e por
;   fim fala-se com o rato pelo prefixo 0xD4 (o proximo byte e para ele).
;
;   Fala-se com o rato pelo prefixo 0xD4 (o proximo byte e para ele) e le-se a
;   resposta (0xFA) de cada comando, para o buffer ficar limpo quando o report
;   comeca - ver para_rato. O handler tambem se sabe ressincronizar sozinho pelo
;   bit 3 do primeiro byte, por isso uma resposta atrasada nao o atrapalha.
; ---------------------------------------------------------------------------
iniciar_8042:
    ; --- os dois dispositivos em pausa ------------------------------------
    call esperar_ibi
    mov dx, PORT_ESTADO
    mov al, CMD_DESLIGA_TEC
    out dx, al
    call esperar_ibi
    mov dx, PORT_ESTADO
    mov al, CMD_DESLIGA_RATO
    out dx, al

    ; --- limpar o que ficou no buffer --------------------------------------
    call limpar_saida

    ; --- command byte: ligar a interrupcao do rato -------------------------
    mov dx, PORT_ESTADO
    mov al, CMD_LER_CB
    out dx, al
    call esperar_obf
    mov dx, PORT_DADOS
    in al, dx
    or  al, 0x02                ; bit 1: interrupcao do rato ligada
    and al, 0xDF                ; bit 5 a zero: relogio do auxiliar destravado
    mov [cmd_byte], al

    call esperar_ibi
    mov dx, PORT_ESTADO
    mov al, CMD_ESCREVE_CB
    out dx, al
    call esperar_ibi
    mov dx, PORT_DADOS
    mov al, [cmd_byte]
    out dx, al

    ; --- ligar o canal auxiliar e o teclado --------------------------------
    call esperar_ibi
    mov dx, PORT_ESTADO
    mov al, CMD_LIGA_RATO
    out dx, al
    call esperar_ibi
    mov dx, PORT_ESTADO
    mov al, CMD_LIGA_TEC
    out dx, al

    ; --- rato: valores de fabrica e reportar -------------------------------
    mov al, RATO_DEFAULTS
    call para_rato
    mov al, RATO_REPORTAR
    call para_rato
    ret

; ---------------------------------------------------------------------------
; para_rato: envia um byte ao rato (prefixo 0xD4 + o byte na porta de dados)
;   entrada: AL = o byte para o rato
;   O AL passa por uma copia em memoria porque esperar_ibi le o estado para o
;   AL e o apagaria.
;
;   No fim le-se a resposta do rato (0xFA): se ficasse no buffer, o handler
;   havia de a ler como se fosse o primeiro byte de um pacote - o 0xFA tem o
;   bit 3 a 1 - e todos os pacotes seguintes entravam desalinhados, com os eixos
;   trocados. Ler aqui a resposta e o que deixa o buffer limpo quando o report
;   comeca. O esperar_obf tem tempo limite, por isso um rato que nao responda
;   nao trava o arranque.
; ---------------------------------------------------------------------------
para_rato:
    mov [comando], al
    call esperar_ibi
    mov dx, PORT_ESTADO
    mov al, CMD_PARA_RATO
    out dx, al
    call esperar_ibi
    mov dx, PORT_DADOS
    mov al, [comando]
    out dx, al
    call esperar_obf
    mov dx, PORT_DADOS
    in al, dx
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
; irq12: o handler do rato
;   Corre a cada pacote. Le um byte (o primeiro que estiver), encaixa-o na
;   maquina de 3 bytes e, ao fechar o pacote, aplica-o a MOUSE_INFO.
;   Guarda tudo o que usa, porque interrompeu o que quer que estivesse a
;   correr - a interface, no meio do desenho. O DS e posto no segmento deste
;   codigo (o estado proprio) e o ES no do nucleo (a MOUSE_INFO e o VIDEO_INFO).
; ---------------------------------------------------------------------------
irq12:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es

    push cs
    pop ds                      ; o estado proprio vive neste segmento

    mov dx, PORT_ESTADO
    in al, dx
    test al, EST_OBF            ; ha mesmo um byte?
    jz  .fim
    test al, EST_AUX            ; e veio mesmo do rato?
    jz  .fim
    mov dx, PORT_DADOS
    in al, dx

    ; --- a maquina dos tres bytes ------------------------------------------
    mov bl, [estado]
    test bl, bl
    jz  .primeiro
    cmp bl, 1
    je  .x
    jmp .y

.primeiro:
    test al, 0x08               ; o bit 3 do primeiro byte e sempre 1
    jz  .fim                    ; nao e um inicio: deita fora e ressincroniza
    cmp al, 0xFA                ; 0xFA e 0xAA sao respostas do rato (ack e
    je  .fim                    ; autoteste): tem o bit 3 a 1 mas nao sao
    cmp al, 0xAA                ; cabecalho de pacote - deitam-se fora
    je  .fim
    mov [pacote], al
    mov byte [estado], 1
    jmp .fim
.x:
    mov [pacote + 1], al
    mov byte [estado], 2
    jmp .fim
.y:
    mov [pacote + 2], al
    mov byte [estado], 0
    call aplicar_pacote

.fim:
    ; --- fim de interrupcao nos dois PICs ----------------------------------
    ; O bit de EOI e o mesmo nos dois (0x20), mas sao duas portas: primeiro o
    ; segundo PIC (0xA0, onde esta a IRQ12) e so depois o primeiro (0x20).
    mov dx, 0xA0
    mov al, 0x20
    out dx, al
    mov dx, 0x20
    mov al, 0x20
    out dx, al

    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret

; ---------------------------------------------------------------------------
; aplicar_pacote: soma o pacote a posicao e guarda os botoes
;   pacote[0] = botoes e estouros; pacote[1] = variacao X; pacote[2] = variacao
;   Y. Os estouros (bits 6 e 7) sao movimentos grandes que o rato nao conseguiu
;   contar: um salto assim seria um salto enorme e errado, por isso o pacote
;   inteiro e deitado fora e fica so a posicao anterior.
; ---------------------------------------------------------------------------
aplicar_pacote:
    mov al, [pacote]
    test al, 0x40
    jnz .fim
    test al, 0x80
    jnz .fim

    mov ax, [info_seg]
    mov es, ax
    mov bx, [info_off]

    ; X += variacao X
    mov al, [pacote + 1]
    cbw                          ; complemento de dois: AL -> AX
    add es:[bx + MI_X], ax

    ; Y -= variacao Y (o Y do rato cresce para cima, o do ecra para baixo)
    mov al, [pacote + 2]
    cbw
    neg ax
    add es:[bx + MI_Y], ax

    ; botoes
    mov al, [pacote]
    and al, 0x07
    mov es:[bx + MI_BOTAO], al

    call limitar
.fim:
    ret

; ---------------------------------------------------------------------------
; limitar: encosta a posicao ao ecra lido ao VIDEO_INFO do nucleo
;   Sem isto um movimento a mais levava o ponteiro para fora do framebuffer, e
;   a interface escrevia em memoria que nao e o ecra. Se o ecra ainda nao
;   tiver medidas (largura a zero), nao se limita nada.
; ---------------------------------------------------------------------------
limitar:
    ; --- X -----------------------------------------------------------------
    mov ax, es:[bx + MI_X]
    test ax, ax
    jns .x_nao_neg
    xor ax, ax
.x_nao_neg:
    mov cx, es:[CONTRATO + VI_LARG]
    test cx, cx
    jz  .x_ok
    cmp ax, cx
    jb  .x_ok
    mov ax, cx
    dec ax
.x_ok:
    mov es:[bx + MI_X], ax

    ; --- Y -----------------------------------------------------------------
    mov ax, es:[bx + MI_Y]
    test ax, ax
    jns .y_nao_neg
    xor ax, ax
.y_nao_neg:
    mov cx, es:[CONTRATO + VI_ALT]
    test cx, cx
    jz  .y_ok
    cmp ax, cx
    jb  .y_ok
    mov ax, cx
    dec ax
.y_ok:
    mov es:[bx + MI_Y], ax
    ret

; ---------------------------------------------------------------------------
; area de dados
; ---------------------------------------------------------------------------
info_seg:  dw 0x0000           ; segmento da MOUSE_INFO (do nucleo)
info_off:  dw 0x0000           ; offset da MOUSE_INFO no nucleo
cmd_byte:  db 0x00             ; o command byte lido, ja com o bit do rato
comando:   db 0x00             ; o byte em transito para o rato (ver para_rato)
estado:    db 0x00             ; quantos bytes do pacote ja entraram
pacote:    db 0x00, 0x00, 0x00 ; o pacote em construcao