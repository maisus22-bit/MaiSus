; ============================================================================
;  Maisus - inicio_minimo.asm
;  Setor 0 (MBR) - Carregado pela BIOS em 0x7C00
;
;  missao: limpar o ecra, localizar /INICIO/INICIO.MAI dentro da ISO9660 e
;          entregar-lhe o controlo em 0xA000:0x0000.
;  saida: inimin.mai
; ============================================================================

BITS 16
ORG 0x7C00                    ; a BIOS carrega o boot sector neste endereco

VIDEO_STATUS equ 0x3DA        ; porta de estado (tambem desbloqueia a CRTC)
VIDEO_PORTA  equ 0x3D4        ; porta de indice do controlador de video
VIDEO_DADOS  equ 0x3DF        ; porta de dados do controlador de video

VIDEO_BASE   equ 0xB800       ; inicio do buffer de texto
COLUNAS     equ 80
LINHAS      equ 25
TOTAL       equ COLUNAS * LINHAS

PREENCHER    equ 0x0100       ; int 10h AH=06: BH=01 usar BL como atributo
PRETO        equ 0x00         ; BL=00 -> fundo preto
VERMELHO     equ 0x10         ; fundo vermelho (so para o ecra de erro)

BLOCO        equ 2048         ; bytes por sector logico (ISO9660 / El Torito)
PVD_LBA      equ 16           ; a norma obriga o 1.o descritor a estar aqui
PVD_TIPO     equ 1            ; tipo 1 = volume descriptor primario
MAX_DESCR    equ 16           ; quantos descritores se procuram no maximo

; o descritor traz o tipo no byte 0 e a assinatura "CD001" nos bytes 1-5.
; Sao comparados 4 desses 5 bytes, lidos como dword a partir do offset 1:
; 43 44 30 30 ('C','D','0','0') em ordem de bytes = 0x30304443
SIG_CD001    equ 0x30304443

ESTAGIO_SET  equ 4            ; sectors do estagio (4 x 2048 = 8 KiB)
N_UNIDADES   equ 3            ; entradas na tabela de unidades

DIR_N        equ 6            ; "INICIO"
FIC_N        equ 12           ; "INICIO.MAI;1"

; ---------------------------------------------------------------------------
; A BIOS usa a pilha que o sector deixa e empurra nela os seus registos
; (da INT 13h descendem ~50 bytes). Se essa pilha for o topo do sector, as
; escritas da BIOS caem por cima do DAP. Por isso a pilha fica na janela
; classica 0x0500-0x0BFF (acima da BDA, abaixo do heap da BIOS) e o sector
; fica livre para codigo e dados.
; ---------------------------------------------------------------------------
PILHA_BIOS   equ 0x0B00

; Sector ISO de trabalho (o mesmo endereco para o PVD e para os dois
; directorios, por isso so se define uma vez).
BUF          equ 0x8000
SEG_BUF      equ BUF      >> 4

; inicio.mai e carregado aqui e salta para 0xA000:0x0000.
ESTAGIO      equ 0xA000
SEG_EST      equ ESTAGIO  >> 4

; ---------------------------------------------------------------------------
start:
    cld                     ; strings em direccao crescente

    ; pilha da BIOS, longe do sector (ver nota de PILHA_BIOS)
    xor ax, ax
    mov ss, ax
    mov sp, PILHA_BIOS

    ; DS = ES = 0: todos os enderecos sao lineares e a INT 13h le o DAP em
    ; DS:SI (e devolve o resultado no mesmo sitio)
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; unidade de arranque: primeiro a que a BIOS deu, depois as alternativas
    ; (a BIOS passa DL=0xE0 no CD; 0x80 e o primeiro disco rigido)
    mov byte [unidades], dl
    mov byte [unidade], 0

    ; --- 1. modo video: 80x25 texto, cor sobre preto ------------------------
    mov ax, 0x0003
    int 0x10

    ; --- 2. limpa o ecra todo, forcando o atributo de BL --------------------
    mov ax, 0x0600          ; AH=06 limpar ecra, AL=00 = ecra inteiro
    mov bx, PREENCHER | PRETO
    int 0x10

    ; --- 3. escreve 0x0000 (caracter + atributo) nas 2000 celulas ------------
    ; rep stosw escreve AX em ES:DI - este e o metodo correcto.
    ; (NAO usar rep outsw: tira o valor de AX, nao da memoria)
    mov ax, VIDEO_BASE
    mov es, ax
    xor di, di
    xor ax, ax              ; caracter 0 + atributo 0 = preto
    mov cx, TOTAL
    rep stosw
    xor ax, ax
    mov es, ax              ; devolve ES ao segmento de dados

    ; --- 4. cursor para o canto (0,0) --------------------------------------
    mov ah, 0x02
    xor bh, bh
    xor dx, dx
    int 0x10

    ; --- 5. desliga o cursor ------------------------------------------------
    ; os registos 0x0A/0x0B da CRTC sao protegidos: e preciso travar o
    ; contador de endereco do cursor pela porta 0x3DA (bit 5) antes de escrever.
    ; NOTA: 0x3DA > 255 e in/out de 8 bits so aceitam porta imm8 -> usar DX.
    ; (usar "in al, 0x3DA" faz o NASM truncar para 0xDA = porta paralela!)
    mov dx, VIDEO_STATUS
    in  al, dx
    or  al, 0x20
    out dx, al

    mov dx, VIDEO_PORTA
    mov al, 0x0A            ; registo Cursor Start
    out dx, al
    mov dx, VIDEO_DADOS
    mov al, 0xFF            ; bit 5 = cursor desactivado
    out dx, al

    ; --- 6. procurar o volume descriptor primario ---------------------------
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

    ; o descritor comeca pelo tipo (byte 0) e so depois vem a assinatura
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
    ; --- 7. ler o directorio raiz (o extent esta no registo do PVD) ---------
    ; o extent (LBA de 32 bits, LE) esta no offset 158 do descritor
    mov cx, 1
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    lea bp, [BUF + 158]
    call ler
    jc  falha

    ; --- 8. procurar o directorio 'INICIO' no directorio raiz -------------
    mov bp, BUF
    mov bx, BLOCO           ; bytes por percorrer ate ao fim do bloco
procura_raiz:
    test bx, bx
    jz  falha              ; sem mais registros
    cmp byte [bp], 0
    jz  falha              ; terminador de sector
    cmp byte [bp + 32], DIR_N
    je  compara_raiz
proximo_raiz:
    mov al, [bp]            ; comprimento do registro
    add bp, ax
    sub bx, ax
    jmp procura_raiz
compara_raiz:
    test byte [bp + 25], 2
    jz  proximo_raiz       ; bit 1 das flags = e um directorio
    mov cx, DIR_N
    lea si, [bp + 33]      ; identificador do registro
    mov di, DIR_INICIO
compara_raiz_l:
    mov al, [si]
    cmp al, [di]
    jne proximo_raiz
    inc si
    inc di
    loop compara_raiz_l

    ; --- 9. ler o directorio /INICIO ---------------------------------------
    ; o extent do registo encontrado esta no offset 2 do proprio registo
    mov cx, 1
    xor bx, bx
    mov ax, SEG_BUF
    mov es, ax
    lea bp, [bp + 2]
    call ler
    jc  falha

    ; --- 10. procurar o ficheiro 'INICIO.MAI;1' ---------------------------
    mov bp, BUF
    mov bx, BLOCO
procura_fic:
    test bx, bx
    jz  falha
    cmp byte [bp], 0
    jz  falha
    cmp byte [bp + 32], FIC_N
    je  compara_fic
proximo_fic:
    mov al, [bp]            ; comprimento do registro
    add bp, ax
    sub bx, ax
    jmp procura_fic
compara_fic:
    mov cx, FIC_N
    lea si, [bp + 33]
    mov di, FIC_INICIO
compara_fic_l:
    mov al, [si]
    cmp al, [di]
    jne proximo_fic
    inc si
    inc di
    loop compara_fic_l

    ; --- 11. carregar o ficheiro em 0xA000 --------------------------------
    mov bx, [bp + 10]       ; tamanho do ficheiro em bytes (LE)
    add bx, BLOCO - 1       ; arredonda para cima
    shr bx, 11              ; bytes / 2048 = sectores
    cmp bx, ESTAGIO_SET
    jbe carregar_ok
    mov bx, ESTAGIO_SET     ; inicio.mai nao passa de 8 KiB
carregar_ok:
    jz  falha               ; ficheiro vazio
    mov cx, bx
    xor bx, bx
    mov ax, SEG_EST
    mov es, ax
    lea bp, [bp + 2]        ; extent (LBA de 32 bits, LE)
    call ler
    jc  falha

    ; --- 12. entregar o controlo ao segundo estagio -----------------------
    mov ax, SEG_EST
    mov ds, ax              ; inicio.mai esta linkado para este segmento
    xor ax, ax
    mov es, ax
    jmp 0x0000:ESTAGIO      ; CS=ESTAGIO, IP=0

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
    mov ax, [bp]            ; o DAP recebe o LBA de 32 bits atraves de AX
    mov [dap_lba], ax
    mov ax, [bp + 2]
    mov [dap_lba + 2], ax
    ; os 4 bytes altos do LBA de 64 bits ficam a zero (montados no sector):
    ; se tiverem lixo a BIOS le um numero gigantesco e rejeita o pedido
.tentar:
    mov cx, [dap_cnt]       ; a INT pode alterar CX: repete sempre a total
    xor bh, bh
    mov bl, [unidade]       ; indice na tabela (BX nao e mais preciso aqui)
    mov dl, [bx + unidades]
    mov ax, [dap_seg]
    mov es, ax              ; a INT pode mexer em ES: repoe sempre
    mov si, DAP             ; idem para SI
    mov ax, 0x4200
    int 0x13
    jnc .fim
    inc byte [unidade]      ; DL da BIOS, depois CD (0xE0), depois HD (0x80)
    cmp byte [unidade], N_UNIDADES
    jb  .tentar
    stc
.fim:
    ret

; ---------------------------------------------------------------------------
; ainda nao ha SO: se o encadeamento falhar, fica com o ecra vermelho
; ---------------------------------------------------------------------------
falha:
    ; ecra vermelho escrito directamente no buffer de texto: a INT 10h AH=06h
    ; usa BH como atributo de preenchimento (e nao BL), conforme a BIOS
    mov ax, VIDEO_BASE
    mov es, ax
    xor di, di
    xor ax, ax              ; caracter 0
    mov ah, VERMELHO        ; atributo: fundo vermelho
    mov cx, TOTAL
    rep stosw
parado:
    hlt
    jmp parado

; ---------------------------------------------------------------------------
; area de dados - fica no fim do sector; a pilha da BIOS esta em 0x0B00,
; muito abaixo, portanto nada escreve aqui durante uma chamada a BIOS
; ---------------------------------------------------------------------------
unidade:     db 0x00          ; indice da unidade a tentar
unidades:    db 0xE0, 0xE0, 0x80  ; DL da BIOS, CD, HD
lba:         dd 0x00000000    ; sector a ler (32 bits, pouco endian)
descr_restam: db 0x00          ; descritores de volume ainda por ver

DIR_INICIO:  db "INICIO", 0           ; 7 bytes
FIC_INICIO:  db "INICIO.MAI;1", 0     ; 13 bytes

; pacote de leitura da INT 13h (16 bytes, montado uma vez aqui):
;   0 tamanho | 1 reservado | 2-3 sectores | 4-5 offset | 6-7 segmento
;   8-15 LBA de 64 bits
DAP:
DAP_size:    db 0x10          ; tamanho do pacote (exigido pela BIOS)
DAP_res:     db 0x00          ; reservado
dap_cnt:     dw 0x0000        ; n. de sectores a transferir
dap_off:     dw 0x0000        ; offset do destino
dap_seg:     dw 0x0000        ; segmento do destino
dap_lba:     dq 0x0000000000000000   ; LBA de 64 bits (so os 4 de baixo mudam)

; ---------------------------------------------------------------------------
; tabela de particoes: 4 entradas de 16 bytes, todas vazias
; ---------------------------------------------------------------------------
times 510 - ($ - $$) db 0x00
dw 0xAA55                      ; assinatura de boot sector
