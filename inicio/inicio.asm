; ============================================================================
;  Maisus - inicio.asm
;  Gerenciador de boot - segundo estagio
;
;  Carregado por inimin.mai da ISO (/inicio/inicio.mai) para BASE:0x0000.
;  Convencao de entrada: CS=IP=BASE, DS=BASE, ES=0x0000.
;
;  missao: escrever a versao do build, carregar o nucleo da ISO para
;          0xC000:0x0000, esperar 4 segundos e entregar-lhe o controlo.
;  saida: nucleo (0.3.2026)
; ============================================================================

BITS 16

BASE       equ 0xA000          ; segmento onde inimin.mai carrega este ficheiro
ORG BASE

SEG_VIDEO  equ 0xB800          ; inicio do buffer de texto
ATRIB      equ 0x0E            ; amarelo claro sobre preto

; Endereco LINEAR onde o nucleo e carregado, e o segmento correspondente.
; Sao dois numeros diferentes e confundir-os e o erro classico do modo real:
; o segmento 0xC00 cobre 0xC000, mas o segmento 0xC000 cobre 0xC0000 (768 KiB).
; O nucleo carrega com NUC_SEG:0x0000 e o codigo dele e ligado para NUC_SEG.
NUC_LIN    equ 0xC000          ; endereco linear do nucleo
NUC_SEG    equ NUC_LIN >> 4    ; 0xC00

BLOCO      equ 2048           ; bytes por sector logico (ISO9660 / El Torito)
PVD_LBA    equ 16             ; a norma obriga o 1.o descritor a estar aqui
PVD_TIPO   equ 1              ; tipo 1 = volume descriptor primario
MAX_DESCR  equ 16             ; quantos descritores se procuram no maximo
NUC_SET    equ 16             ; sectores maxima do nucleo (16 x 2048 = 32 KiB)
N_UNIDADES equ 3              ; unidades na tabela de tentativas do sector 0

; o descritor traz o tipo no byte 0 e a assinatura "CD001" nos bytes 1-5.
; Sao comparados 4 desses 5 bytes, lidos como dword a partir do offset 1:
; 43 44 30 30 ('C','D','0','0') em ordem de bytes = 0x30304443
SIG_CD001  equ 0x30304443

; Sector ISO de trabalho (o mesmo endereco para o PVD e para os dois
; directorios, por isso so se define uma vez).
BUF        equ 0x8000          ; livre: o sector 0 vive em 0x7C00-0x8000

; ---------------------------------------------------------------------------
; A espera de 4 segundos e pedida a BIOS com a INT 15h AH=86h, que espera
; CX:DX microssegundos. Nao se programou o PIT para isso de proposito:
;
;   - o PIT do contador 0 ja esta ao servico da IRQ do timer da propria BIOS,
;     mexer nele durante o arranque e mexer no relogio que esta a medir-nos;
;   - a INT 15h/86 e um servico documentado (AT e posteriores, incluindo a
;     SeaBIOS do QEMU), devolve quando passou, e cabe numa unica instrucao.
;
; So se cairia em esperar a mao se a BIOS nao tivesse esse servico: nesse caso
; entrava um laco sobre a INT 1Ah AH=00h, que devolve os tiques desde a meia-noite.
; ---------------------------------------------------------------------------
ESPERA_US  equ 4000000         ; 4 segundos em microssegundos

; ---------------------------------------------------------------------------
; A pilha nao pode estar em 0xB800-0xC000: essa e a janela do buffer de texto e
; empilhar la vai para o ecra. Fica em 0x7BFF, abaixo do sector 0 (0x7C00) e
; acima da janela classica da BIOS (0x0500-0x0BFF).
; ---------------------------------------------------------------------------
PILHA      equ 0x7BFF

; ---------------------------------------------------------------------------
start:
    cld

    ; pilha propria: a do primeiro estagio ja nao serve
    xor ax, ax
    mov ss, ax
    mov sp, PILHA

    ; --- modo video: 80x25 texto, cor sobre preto -------------------------
    mov ax, 0x0003
    int 0x10

    ; --- escreve a versao na primeira linha --------------------------------
    ; escreve-se directamente no buffer de texto: cada celula ocupa 2 bytes
    ; (caracter + atributo). Nao se usa a INT 10h AH=13h porque a implementacao
    ; dessa funcao varia entre BIOS e aqui nao devolve nada.
    mov ax, SEG_VIDEO
    mov es, ax
    xor di, di                ; celula (0,0) = inicio do ecra
    mov cx, VERSAO_N
    mov si, VERSAO - BASE     ; DS=BASE, por isso SI e o deslocamento no segmento
.escreve:
    lodsb
    mov ah, ATRIB
    stosw                     ; caracter + atributo; avanca 2 bytes em DI
    xor ax, ax
    loop .escreve
    mov ax, SEG_VIDEO
    mov es, ax                ; devolve ES ao segmento do buffer de texto

; ---------------------------------------------------------------------------
; A partir daqui comeca a caminhada pela ISO9660, a mesma que o sector 0 faz.
; Este codigo e de proposito uma copia do de inicio_minimo.asm: o sector 0 tem
; 510 bytes e nao ha espaco para as duas coisas, e nao se pode dar ao sector 0 a
; responsabilidade de carregar o nucleo. A duplicacao e o preco de o sector 0
; ter de ser um sector so. Quando este sector grow, a duplicacao deve morrer.
;
; Aqui DS passa a 0: os enderecos do volume sao lineares e a INT 13h le o DAP em
; DS:SI. O texto do ecra ja foi escrito antes desta mudanca, por isso o
; deslocamento relativo a BASE so era preciso na seccao de cima.
; ---------------------------------------------------------------------------
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; unidade de arranque: o DL com que a BIOS arrancou este sector morreu
    ; quando o sector 0 passou o controlo. Nao se pode perguntar a BIOS outra
    ; vez, por isso tenta-se a lista de unidades provaveis por ordem: primeiro o
    ; CD (0xE0), depois o primeiro disco rigido (0x80), depois o floppy A:
    mov byte [unidade], 0

    ; --- procurar o volume descriptor primario ---------------------------
    ; nao se assume um LBA fixo: comeca-se no sector 16 (exigido pela norma) e
    ; percorre-se a cadeia de descritores ate aparecer o tipo 1 com CD001
    mov dword [lba], PVD_LBA
    mov byte [descr_restam], MAX_DESCR
procurar_pvd:
    mov cx, 1               ; 1 sector de 512 = 2048 bytes = 1 bloco ISO
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    lea bp, [lba]           ; 32 bits, pouco endian
    call ler
    jc  falha

    cmp byte [BUF], PVD_TIPO
    jne proximo_descr       ; sector sem um descritor de volume: ignora
    cmp dword [BUF + 1], SIG_CD001
    je  pvd_pronto

proximo_descr:
    inc dword [lba]
    dec byte [descr_restam]
    jnz procurar_pvd
    jmp falha               ; nenhum descritor primario em MAX_DESCR sectores

pvd_pronto:
    ; --- ler o directorio raiz (o extent esta no registo do PVD) ---------
    mov cx, 1
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    lea bp, [BUF + 158]
    call ler
    jc  falha

    ; --- procurar o directorio 'nucleo' no directorio raiz --------------
    mov bp, BUF
    mov bx, BLOCO           ; bytes por percorrer ate ao fim do bloco
procura_raiz:
    test bx, bx
    jz  falha              ; sem mais registros
    cmp byte [bp], 0
    jz  falha              ; terminador de sector
    cmp byte [bp + 32], DIR_N
    je compara_raiz
proximo_raiz:
    mov al, [bp]            ; comprimento do registro
    add bp, ax
    sub bx, ax
    jmp procura_raiz
compara_raiz:
    test byte [bp + 25], 2
    jz proximo_raiz       ; bit 1 das flags = e um directorio
    mov cx, DIR_N
    lea si, [bp + 33]      ; identificador do registro
    mov di, DIR_NUCLEO
compara_raiz_l:
    mov al, [si]
    cmp al, [di]
    jne proximo_raiz
    inc si
    inc di
    loop compara_raiz_l

    ; --- ler o directorio /nucleo ---------------------------------------
    mov cx, 1
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    lea bp, [bp + 2]
    call ler
    jc  falha

    ; --- procurar o ficheiro do build corrente -------------------------
    ; o nome do ficheiro e o proprio numero do build: nucleo/0.3.2026. Como o
    ; Build.sh monta a ISO em -iso-level 4, o identificador no disco e o nome
    ; tal e qual, em minusculas e sem a versao ";1".
    mov bp, BUF
    mov bx, BLOCO
procura_fic:
    test bx, bx
    jz  falha
    cmp byte [bp], 0
    jz  falha
    cmp byte [bp + 32], FIC_N
    je compara_fic
proximo_fic:
    mov al, [bp]
    add bp, ax
    sub bx, ax
    jmp procura_fic
compara_fic:
    mov cx, FIC_N
    lea si, [bp + 33]
    mov di, FIC_NUCLEO
compara_fic_l:
    mov al, [si]
    cmp al, [di]
    jne proximo_fic
    inc si
    inc di
    loop compara_fic_l

    ; --- carregar o nucleo em SEG_NUC:0x0000 ----------------------------
    mov bx, [bp + 10]       ; tamanho do ficheiro em bytes (LE)
    add bx, BLOCO - 1       ; arredonda para cima
    shr bx, 11              ; bytes / 2048 = sectores
    cmp bx, NUC_SET
    jbe carregar_ok
    mov bx, NUC_SET         ; o nucleo nao passa de 32 KiB
carregar_ok:
    jz  falha               ; ficheiro vazio
    mov cx, bx
    xor bx, bx
    mov ax, NUC_SEG
    mov es, ax
    lea bp, [bp + 2]        ; extent (LBA de 32 bits, LE)
    call ler
    jc  falha

; ---------------------------------------------------------------------------
; esperar 4 segundos
; ---------------------------------------------------------------------------
;   INT 15h AH=86h  CX:DX = microssegundos a esperar (CX = metade alta)
;
; As interrupcoes ficam ligadas durante a espera: a implementacao deste servico
; pode usar a IRQ do timer, e uma espera com IF=0 seria um alvo movel.
    mov cx, ESPERA_US >> 16
    mov dx, ESPERA_US & 0xFFFF
    mov ah, 0x86
    int 0x15

; ---------------------------------------------------------------------------
; entregar o controlo ao nucleo
; ---------------------------------------------------------------------------
    ; as interrupcoes ficam ligadas antes da passagem: com IF=0 o "hlt" do
    ; nucleo pararia o CPU para sempre (em modo real so o acorda um NMI)
    sti

    ; o nucleo entra com CS=IP=NUC_SEG:0x0000 (ou seja, linear 0xC000) e uma
    ; pilha limpa
    xor ax, ax
    mov ss, ax
    mov sp, PILHA
    mov ax, NUC_SEG
    mov ds, ax
    mov es, ax
    jmp NUC_SEG:0x0000

; ---------------------------------------------------------------------------
; ler: le sectores da ISO com a INT 13h extendida (AH=42h)
;   entrada: BP = endereco do LBA de 32 bits | ES:BX = destino
;            CX = n. de sectores
;   saida:   CF=1 se falhou em todas as unidades
; ---------------------------------------------------------------------------
ler:
    mov word [dap_cnt], cx  ; o pacote tem de estar montado antes de tentar
    mov [dap_off], bx
    mov ax, es
    mov [dap_seg], ax
    mov ax, [bp]
    mov [dap_lba], ax
    mov ax, [bp + 2]
    mov [dap_lba + 2], ax
.tentar:
    mov cx, [dap_cnt]
    xor bh, bh
    mov bl, [unidade]
    mov dl, [bx + unidades]
    mov ax, [dap_seg]
    mov es, ax
    mov si, DAP
    mov ax, 0x4200
    int 0x13
    jnc .fim
    inc byte [unidade]
    cmp byte [unidade], N_UNIDADES
    jb .tentar
    stc
.fim:
    ret

; ---------------------------------------------------------------------------
; se a caminhada pela ISO falhar, o ecra fica vermelho e paramos
; (aqui as interrupcoes ainda estao ligadas: o "cli" fica mais abaixo, na espera)
; ---------------------------------------------------------------------------
falha:
    mov ax, SEG_VIDEO
    mov es, ax
    xor di, di
    xor ax, ax
    mov ah, 0x10            ; fundo vermelho
    mov cx, 80 * 25
    rep stosw
falha_parado:
    hlt
    jmp falha_parado

; ---------------------------------------------------------------------------
; area de dados
; ---------------------------------------------------------------------------
unidade:     db 0x00          ; indice da unidade a tentar (ver a tabela)
unidades:    db 0xE0, 0x80, 0x00  ; CD, primeiro HD, floppy A:
lba:         dd 0x00000000
descr_restam: db 0x00

DIR_NUCLEO:  db "nucleo", 0          ; 7 bytes
FIC_NUCLEO:  db "0.3.2026", 0        ; 9 bytes

DIR_N        equ 6
FIC_N        equ 8                    ; "0.3.2026"

DAP:
DAP_size:    db 0x10
DAP_res:     db 0x00
dap_cnt:     dw 0x0000
dap_off:     dw 0x0000
dap_seg:     dw 0x0000
dap_lba:     dq 0x0000000000000000

SEG_BUF      equ BUF >> 4

VERSAO:   db "Maisus v0.1 Build 0.3.2026"
VERSAO_N  equ $ - VERSAO

; ---------------------------------------------------------------------------
; o texto fica no fim do ficheiro (nao ha padding: este estagio cresce)
; ---------------------------------------------------------------------------
