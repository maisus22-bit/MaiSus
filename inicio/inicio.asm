; ============================================================================
;  Maisus - inicio.asm
;  Gerenciador de boot - segundo estagio
;
;  Carregado por inimin.mai da ISO (/inicio/inicio.mai) para BASE:0x0000.
;  Convencao de entrada: CS=IP=BASE, DS=BASE, ES=0x0000.
;
;  missao: escrever a versao do build, esperar 4 segundos, carregar da ISO o
;          nucleo (/nucleo/0.5.2026), o driver de video (/drivers/video.dr) e a
;          interface (/interface/face.grain) com a barra inferior que ela
;          executa (/interface/barinf.grain), e entregar o controlo ao nucleo.
;  saida: nucleo (0.5.2026)
;
;  O nucleo entra sem levar nada na mao: os dois ficheiros ja estao na memoria
;  nos sitios onde ele vai buscar (as constantes de nucleo.asm). A espera de 4
;  segundos e feita aqui, depois de escrever o numero do build no ecra: o
;  controlo so passa ao nucleo quando a mensagem ja foi mostrada.
; ============================================================================

BITS 16

BASE       equ 0xA000          ; segmento onde inimin.mai carrega este ficheiro
ORG BASE

SEG_VIDEO  equ 0xB800          ; inicio do buffer de texto
ATRIB      equ 0x0E            ; amarelo claro sobre preto

; Endereco LINEAR onde o nucleo e carregado, e o segmento correspondente.
; Sao dois numeros diferentes e confundir-los e o erro classico do modo real:
; o segmento 0xC00 cobre 0xC000, mas o segmento 0xC000 cobre 0xC0000 (768 KiB).
; O nucleo carrega com NUC_SEG:0x0000 e o codigo dele e ligado para NUC_SEG.
NUC_LIN    equ 0xC000          ; endereco linear do nucleo
NUC_SEG    equ NUC_LIN >> 4    ; 0xC00

; Endereco LINEAR onde o driver de video e carregado, e o segmento
; correspondente. Sao dois numeros diferentes e confundir-los e o erro classico
; do modo real: o segmento 0xE00 cobre 0xE000, mas o segmento 0xE000 cobre
; 0xE0000 (896 KiB). O driver chama-se a si mesmo pelo segmento 0xE00, e por isso
; que a imagem dele e ligada para esse segmento.
DRV_LIN    equ 0xE000          ; endereco linear do driver
DRV_SEG    equ DRV_LIN >> 4    ; 0xE00

; A barra inferior segue a mesma regra, dois segmentos acima da interface: o
; face.grain vive em 0x2000:0x0000 e a barra em 0x3000:0x0000, por isso nenhum
; dos dois pode estar a ser executado de cima do outro. Os dois sitios estao na
; memoria convencional livre (abaixo de 0xA000), longe do framebuffer, que num
; modo VESA vive bem acima de 1 MiB.
;
; O numero e o endereco LINEAR, como o do nucleo e o do driver: o segmento de
; destino e o linear dividido por 16 (0x30000 >> 4 = 0x3000). Escrever 0x3000
; aqui punha a barra em 0x3000:0x0000, isto e, no linear 0x3000, e o face.grain
; saltava para um segmento vazio.
BAR_LIN    equ 0x30000         ; endereco linear da barra
BAR_SEG    equ BAR_LIN >> 4    ; 0x3000 - o segmento que o face.grain salta

BLOCO      equ 2048           ; bytes por sector logico (ISO9660 / El Torito)
PVD_LBA    equ 16             ; a norma obriga o 1.o descritor a estar aqui
PVD_TIPO   equ 1              ; tipo 1 = volume descriptor primario
MAX_DESCR  equ 16             ; quantos descritores se procuram no maximo
NUC_SET    equ 16             ; sectores maxima do nucleo (16 x 2048 = 32 KiB)
DRV_SET    equ 2              ; sectores maxima do driver (2 x 2048 = 4 KiB)
BAR_SET    equ 4              ; sectores maxima da barra (4 x 2048 = 8 KiB)
N_UNIDADES equ 3              ; unidades na tabela de tentativas do sector 0

; Quanto tempo o numero do build fica no ecra antes de o controlo passar ao
; nucleo (em microssegundos).
ESPERA_US  equ 4000000        ; 4 segundos

; o descritor traz o tipo no byte 0 e a assinatura "CD001" nos bytes 1-5.
; Sao comparados 4 desses 5 bytes, lidos como dword a partir do offset 1:
; 43 44 30 30 ('C','D','0','0') em ordem de bytes = 0x30304443
SIG_CD001  equ 0x30304443

; Sector ISO de trabalho (o mesmo endereco para o PVD e para os dois
; directorios, por isso so se define uma vez).
BUF        equ 0x8000          ; livre: o sector 0 vive em 0x7C00-0x8000

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
    ; escreve-se diretamente no buffer de texto: cada celula ocupa 2 bytes
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

    ; --- espera 4 segundos -------------------------------------------------
    ; A espera e deste estagio: o ecra esta em modo texto com o numero do build
    ; escrito acima, e so depois de o mostrar durante 4 segundos e que o
    ; controlo passa ao nucleo.
    ;
    ; A espera e pedida a BIOS com a INT 15h AH=86h, que espera CX:DX
    ; microssegundos (CX = metade alta). Nao se programa o PIT para isso de
    ; proposito: o PIT do contador 0 ja esta ao servico da IRQ do timer da
    ; propria BIOS, e mexer nele durante o arranque e mexer no relogio que nos
    ; esta a medir. A INT 15h/86 e um servico documentado (AT e posteriores,
    ; incluindo a SeaBIOS do QEMU): devolve quando o tempo passou e cabe numa
    ; unica instrucao.
    ;
    ; As interrupcoes ficam ligadas durante a espera: a implementacao deste
    ; servico pode usar a IRQ do timer, e uma espera com IF=0 seria um alvo
    ; movel.
    mov cx, ESPERA_US >> 16
    mov dx, ESPERA_US & 0xFFFF
    mov ah, 0x86
    int 0x15

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

    ; --- o nucleo: /nucleo/<numero do build> ------------------------------
    ; O nome do ficheiro e o proprio numero do build, e a versao do nucleo e
    ; uma constante deste ficheiro: mudar o build e mudar esta string.
    call ficheiro_nucleo
    jc  falha

    ; --- o driver de video: /drivers/video.dr ------------------------------
    call ficheiro_driver
    jc  falha

    ; --- a interface: /interface/face.grain ------------------------------
    call ficheiro_interface
    jc  falha

    ; --- a barra inferior: /interface/barinf.grain --------------------------
    ; A barra vai na mesma caminhada que a interface e na mesma pasta da ISO,
    ; mas para outro sitio da memoria: o face.grain salta para ela depois de
    ; pintar o ecra, e nenhum dos dois pode estar a ser executado de cima do
    ; outro.
    call ficheiro_barra
    jc  falha

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
; ficheiro_nucleo: procura /nucleo/<build> no volume e carrega-o em NUC_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
; ---------------------------------------------------------------------------
ficheiro_nucleo:
    mov si, DIR_NUCLEO
    mov cx, DIR_N
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_NUCLEO
    mov cx, FIC_N
    call achar_ficheiro
    jc  .falha
    mov ax, NUC_SEG
    mov [dest_seg], ax
    mov word [max_set], NUC_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_interface: procura /interface/face.grain no volume e carrega-o em memoria
;   saida: CF=1 se nao encontrar ou se a leitura falhar
; ---------------------------------------------------------------------------
ficheiro_interface:
    mov si, DIR_INTERFACE
    mov cx, DIR_I
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_INTERFACE
    mov cx, FIC_I
    call achar_ficheiro
    jc  .falha
    mov ax, 0x2000                ; face.grain fica em 0x2000:0x0000 (linear 0x20000)
    mov [dest_seg], ax
    mov word [max_set], 16        ; espaco de sobra: a interface e de 1 sector
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_barra: procura /interface/barinf.grain no volume e carrega-o em BAR_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
;
;   O nome procurado e o mesmo ficheiro que o Build.sh graftou na ISO; e o
;   face.grain que verifica a assinatura da imagem carregada antes de saltar
;   para ela, por isso aqui basta achar o ficheiro e coloca-lo no sitio.
; ---------------------------------------------------------------------------
ficheiro_barra:
    mov si, DIR_INTERFACE
    mov cx, DIR_I
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_BARRA
    mov cx, FIC_B
    call achar_ficheiro
    jc  .falha
    mov ax, BAR_SEG
    mov [dest_seg], ax
    mov word [max_set], BAR_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ficheiro_driver: procura /drivers/video.dr no volume e carrega-o em DRV_SEG
;   saida: CF=1 se nao encontrar ou se a leitura falhar
; ---------------------------------------------------------------------------
ficheiro_driver:
    mov si, DIR_MOTOR
    mov cx, DIR_M
    call abrir_raiz
    jc  .falha
    call ler_directorio
    jc  .falha
    mov si, FIC_MOTOR
    mov cx, FIC_M
    call achar_ficheiro
    jc  .falha
    mov ax, DRV_SEG
    mov [dest_seg], ax
    mov word [max_set], DRV_SET
    jmp carregar_ficheiro
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; abrir_raiz: procura um directorio no directorio raiz do volume
;   entrada: SI = o nome do directorio, CX = o comprimento do nome
;   saida:   BP = o endereco do registo encontrado no BUF | CF=1 se nao existe
;
;   Chama ler_pvd porque o extent do directorio raiz esta dentro do descritor
;   de volume, e o BUF ja foi entretanto reescrito por outras leituras.
;
;   O par SI/CX com o nome e guardado em memoria antes das leituras: tanto
;   ler_pvd como ler mexem em SI e em CX, e procura_reg precisa de os receber
;   intactos. Sem este provisoio o nome procurado era o endereco do DAP com o
;   comprimento 1, e o directorio nunca era encontrado.
; ---------------------------------------------------------------------------
abrir_raiz:
    mov [nome_proc], si
    mov [nome_tam], cx

    call ler_pvd
    jc  .falha

    ; o extent do directorio raiz esta no offset 158 do descritor
    mov cx, 1               ; 1 sector de 512 = 2048 bytes = 1 bloco ISO
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    mov bp, BUF + 158
    call ler
    jc  .falha

    ; agora o directorio raiz esta no BUF: procura-se la dentro o nome
    mov bp, BUF
    mov bx, BLOCO           ; bytes por percorrer ate ao fim do bloco
    mov si, [nome_proc]
    mov cx, [nome_tam]
    jmp procura_reg         ; devolve BP (o registo) e o CF
.falha:
    stc
    ret

; ---------------------------------------------------------------------------
; ler_directorio: le para o BUF o directorio cujo registo esta em BP
;   saida: CF=1 se a leitura falhar
; ---------------------------------------------------------------------------
ler_directorio:
    mov cx, 1
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    add bp, 2               ; o extent do directorio esta no offset 2 do registo
    call ler
    ret

; ---------------------------------------------------------------------------
; achar_ficheiro: procura um ficheiro no directorio que esta no BUF
;   entrada: SI = o nome, CX = o comprimento do nome
;   saida:   BP = o endereco do registo | CF=1 se nao existe
; ---------------------------------------------------------------------------
achar_ficheiro:
    mov bp, BUF
    mov bx, BLOCO
    jmp procura_reg

; ---------------------------------------------------------------------------
; procura_reg: percorre o directorio que esta no BUF a procura de um registo
;             cujo identificador (offset 32) seja igual a [SI], com [CX] bytes
;   entrada: BP = inicio do bloco, BX = quantos bytes ha para percorrer,
;            SI = o nome procurado, CX = o comprimento do nome
;   saida:   BP = o endereco do registo | CF=1 se nao existe
;
;   O nome procurado e o comprimento sao copiados para duas variaveis porque o
;   laco precisa deles outra vez a cada registo, e a comparacao dos bytes leva
;   o CX a zero.
; ---------------------------------------------------------------------------
procura_reg:
    mov [nome_proc], si
    mov [nome_tam], cx
.loop:
    test bx, bx
    jz  .nao                ; sem mais registros
    cmp byte [bp], 0
    jz  .nao                ; terminador de sector
    mov cl, [nome_tam]
    cmp byte [bp + 32], cl ; o identificador tem o comprimento certo?
    je  .achou
.proximo:
    mov al, [bp]            ; comprimento do registro
    xor ah, ah              ; AX = comprimento (so AL foi escrito)
    add bp, ax
    sub bx, ax
    jmp .loop
.achou:
    push si
    push bx
    mov si, bp
    add si, 33              ; identificador do registro
    mov di, [nome_proc]
    mov cx, [nome_tam]
.compara:
    mov al, [si]
    cmp al, [di]
    jne .desistir
    inc si
    inc di
    loop .compara
    pop bx
    pop si
    clc
    ret
.desistir:
    pop bx
    pop si
    jmp .proximo
.nao:
    stc
    ret

; ---------------------------------------------------------------------------
; carregar_ficheiro: carrega em [dest_seg]:0x0000 o ficheiro do registo em BP
;   entrada: BP = o registo do directorio (offset 10 = tamanho em bytes,
;            offset 2 = extent), [dest_seg] = o segmento de destino,
;            [max_set] = quantos sectores se podem ler
;   saida:   CF=1 se a leitura falhar
; ---------------------------------------------------------------------------
carregar_ficheiro:
    mov bx, [bp + 10]       ; tamanho do ficheiro em bytes (LE)
    add bx, BLOCO - 1       ; arredonda para cima
    shr bx, 11              ; bytes / 2048 = sectores
    cmp bx, [max_set]
    jbe .ok
    mov bx, [max_set]       ; corta ao maximo permitido
.ok:
    test bx, bx             ; o teste tem de ser sobre BX, nao sobre as flags
    jz  falha               ; do cmp de cima: um ficheiro com um numero exacto
                            ; de sectores (BX == max_set) punha ZF=1 e falhava
    mov cx, bx
    xor bx, bx
    mov ax, [dest_seg]
    mov es, ax
    add bp, 2                ; o extent do ficheiro esta no offset 2 do registo
    call ler
    jc  falha
    ret

; ---------------------------------------------------------------------------
; ler_pvd: procura o descritor de volume primario e le-o para o BUF
;   saida: CF=1 se nao aparecer em MAX_DESCR sectores
; ---------------------------------------------------------------------------
ler_pvd:
    mov dword [lba], PVD_LBA
    mov byte [descr_restam], MAX_DESCR
.procurar:
    mov cx, 1               ; 1 sector de 512 = 2048 bytes = 1 bloco ISO
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    lea bp, [lba]           ; 32 bits, pouco endian
    call ler
    jc  .falha
    cmp byte [BUF], PVD_TIPO
    jne .proximo            ; sector sem um descritor de volume: ignora
    cmp dword [BUF + 1], SIG_CD001
    ret                     ; sao iguais, portanto o "cmp" deixou CF=0
.proximo:
    inc dword [lba]
    dec byte [descr_restam]
    jnz .procurar
.falha:
    stc
    ret

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
; (aqui as interrupcoes ainda estao ligadas: o "hlt" precisa delas)
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

nome_proc:   dw 0x0000        ; o nome que procura_reg esta a procurar
nome_tam:    dw 0x0000
dest_seg:    dw 0x0000        ; segmento de destino de carregar_ficheiro
max_set:     dw 0x0000        ; sectores maxima de carregar_ficheiro

DIR_NUCLEO:  db "nucleo", 0          ; 7 bytes
FIC_NUCLEO:  db "0.5.2026", 0        ; 9 bytes

DIR_N        equ 6
FIC_N        equ 8                    ; "0.5.2026"

DIR_MOTOR:   db "drivers", 0          ; 8 bytes
FIC_MOTOR:   db "video.dr", 0         ; 9 bytes

DIR_M        equ 7
FIC_M        equ 8                    ; "video.dr"

DIR_INTERFACE: db "interface", 0       ; 10 bytes
FIC_INTERFACE: db "face.grain", 0      ; 11 bytes

DIR_I        equ 9
FIC_I        equ 10                   ; "face.grain"

FIC_BARRA:   db "barinf.grain", 0      ; 13 bytes
FIC_B        equ 12                   ; "barinf.grain"

DAP:
DAP_size:    db 0x10
DAP_res:     db 0x00
dap_cnt:     dw 0x0000
dap_off:     dw 0x0000
dap_seg:     dw 0x0000
dap_lba:     dq 0x0000000000000000

SEG_BUF      equ BUF >> 4

VERSAO:   db "Maisus v0.1 Build 0.5.2026"
VERSAO_N  equ $ - VERSAO

; ---------------------------------------------------------------------------
; Este estagio e carregado em 3 sectores (6 KiB, de 0xA000 a 0xB7FF, ate ao
; comeco do buffer de texto). O "times" faz o nasm falhar se o codigo passar
; dai: sem ele o inicio_minimo.asm carregava este ficheiro a meio e o nucleo
; arrancava de um codigo truncado.
; ---------------------------------------------------------------------------
    times 0x1800 - ($ - $$) db 0x00
