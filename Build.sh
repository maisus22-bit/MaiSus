#!/usr/bin/env bash
# ============================================================================
#  Maisus - Build.sh
#
#  1. Ensambla os seis estagios:
#        inicio/inicio_minimo.asm    ->  inicio/inimin.mai   (setor 0 / boot)
#        inicio/inicio.asm           ->  inicio/inicio.mai  (gerenciador)
#        nucleo/nucleo.asm           ->  nucleo/0.5.2026    (nucleo)
#        drivers/video.asm           ->  drivers/video.dr    (driver de video)
#        interface/interface.asm     ->  interface/face.grain (interface grafica)
#        interface/barra_inferrior.asm
#                                     ->  interface/barinf.grain (barra inferior,
#                                        executada pelo face.grain)
#  2. Monta a ISO (sem GRUB, sem isolinux) com os ficheiros
#  3. Lanca o QEMU com a ISO
#
#  Nao existe pasta de staging: a ISO e montada com -graft-points, directement
#  a partir dos binarios em inicio/, nucleo/ e drivers/.
#  Ao fechar a janela do QEMU, este comando termina.
#
#  O numero do build vive em tres sitios que tem de concordar: aqui, no nome do
#  ficheiro que o inicio.asm procura dentro da ISO (FIC_NUCLEO) e na string que
#  o nucleo escreve no ecra (VERSAO, em nucleo.asm). O script nao os arruma:
#  muda-se a variavel BUILD e trata-se de actualizar os outros dois.
# ============================================================================

set -euo pipefail

# --- caminhos ---------------------------------------------------------------
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INICIO="$RAIZ/inicio"                  # pasta do fonte e do binario dos 2 primeiros estagios
NUCLEO="$RAIZ/nucleo"                  # pasta do fonte e do binario do nucleo
MOTOR="$RAIZ/drivers"                  # pasta dos drivers
ISO="$RAIZ/Maisus.iso"

# --- o numero do build ------------------------------------------------------
# Vive num sitio so. O nome do binario do nucleo dentro da ISO e o proprio
# numero do build, por isso mudar esta linha muda o nome do ficheiro procurado
# no disco: e o inicio.asm que tem de saber que versao se esta a arrancar.
BUILD="0.5.2026"

# --- nomes ------------------------------------------------------------------
# sao dois ficheiros separados: um fonte e um binario para cada estagio
FONTE_MBR="inicio_minimo.asm"     # fonte do setor 0 (MBR): o boot sector
NOME_MBR="inimin.mai"             # binario: dentro e fora da ISO
FONTE_GER="inicio.asm"            # fonte do gerenciador de boot
NOME_GER="inicio.mai"             # binario: dentro e fora da ISO
FONTE_NUC="nucleo.asm"            # fonte do nucleo
NOME_NUC="$BUILD"                 # binario: "0.5.2026", dentro e fora da ISO
FONTE_DRV="video.asm"             # fonte do driver de video
NOME_DRV="video.dr"               # binario: dentro e fora da ISO
FONTE_INT="interface.asm"         # fonte da interface grafica
NOME_INT="face.grain"             # binario: dentro e fora da ISO
FONTE_BAR="barra_inferrior.asm"   # fonte da barra inferior
NOME_BAR="barinf.grain"           # binario: dentro e fora da ISO
DIR_ISO="inicio"                       # pasta dos binarios dentro da ISO
DIR_NUC="nucleo"                       # pasta do nucleo dentro da ISO
DIR_MOTOR="drivers"                    # pasta dos drivers dentro da ISO
DIR_INT="interface"                    # pasta da interface dentro da ISO
INTERFACE="$RAIZ/interface"              # pasta da interface

# --- nivel de ISO9660 -------------------------------------------------------
# 4 = os identificadores vao para o disco tal e qual: minusculas e SEM ";1".
# Nos niveis 1/2/3 o genisoimage reescreve os nomes, e um nome com dois pontos
# vira "0_3.2026;1"; no nivel 1 ainda truncava para "0_3.202". Como o
# inicio_minimo.asm e o inicio.asm procuram os nomes no disco byte a byte, o
# nivel da ISO e parte do contrato e nao uma opcao estetica.
NIVEL_ISO=4

# aviso do nasm que nao e erro: codigo de 16 bits com enderecos absolutos
# num binario plano da sempre este aviso. Todos os outros continuam a parar
# o build.
AVISO_IGNORADO="reloc-abs-word"

# --- ferramentas ------------------------------------------------------------
NASM="${NASM:-nasm}"
GENISOIMAGE="${GENISOIMAGE:-genisoimage}"
QEMU="${QEMU:-qemu-system-x86_64}"
QEMU_DISPLAY="${QEMU_DISPLAY:-gtk}"

# --- cor no terminal --------------------------------------------------------
if [ -t 1 ]; then TITULO=$'\033[1;36m'; ERRO=$'\033[1;31m'; FIM=$'\033[0m'
else TITULO=""; ERRO=""; FIM=""; fi

erro() { printf '%s%s: %s%s\n' "$ERRO" "$1" "$2" "$FIM" >&2; exit 1; }

# --- 0. dependencias ---------------------------------------------------------
verificar_ferramentas() {
    local falta=0
    for f in "$NASM" "$GENISOIMAGE" "$QEMU"; do
        command -v "$f" >/dev/null 2>&1 || { erro "FALTA" "nao encontrei: $f"; falta=1; }
    done
    [ "$falta" -eq 0 ] || erro "INSTALA" "sudo apt install -y nasm genisoimage qemu-system-x86"
}

# --- 1b. o mapa da memoria ----------------------------------------------------
#   O inicio.mai carrega os dois ficheiros em enderecos fixos, que sao
#   constantes nos fontes (NUC_SEG e DRV_SEG em inicio.asm, DRV_LIN em
#   nucleo.asm). Se a imagem de um deles mudar de tamanho, o inicio.mai passa a
#   ler sectores a mais ou a menos e o nucleo vai ler dados estruturados a esmo -
#   por isso o mapa e impresso todas as vezes, e nao so no fonte.
mapa() {
    local n d
    n="$(stat -c%s "$NUCLEO/$NOME_NUC")"
    d="$(stat -c%s "$MOTOR/$NOME_DRV")"
    printf '  mapa  %-12s %4s bytes  0x%04X-0x%04X  (%s sectores)\n' \
        "$NOME_NUC" "$n" "$((0xC000))" \
        "$((0xC000 + ((n + 2047) / 2048) * 2048 - 1))" "$(((n + 2047) / 2048))"
    printf '  mapa  %-12s %4s bytes  0x%04X-0x%04X  (%s sectores)\n' \
        "$NOME_DRV" "$d" "$((0xE000))" \
        "$((0xE000 + ((d + 2047) / 2048) * 2048 - 1))" "$(((d + 2047) / 2048))"
}

# --- 1. ensamblar ------------------------------------------------------------
#   nasm nao tem como renomear a saida: compilamos directamente para o nome final
#   A pasta entra como argumento porque o nucleo nao vive em inicio/ nem os
#   drivers em nucleo/.
ensamblar() {
    local pasta="$1" fonte="$2" nome="$3"
    local src="$pasta/$fonte"
    local out="$pasta/$nome"
    local log="" avisos ignorados

    printf '  nasm  %-24s -> %s\n' "$fonte" "$nome"
    [ -f "$src" ] || erro "ERRO" "fonte nao encontrada: $src"

    # -w+all activa todos os avisos. Um sector truncado (ex: porta 0x3DA
    # reduzida a 0xDA) assembla sem erro e sobe na mesma -> aviso = falha.
    #
    # -I "$pasta" e para o "%include": o nasm nao procura ficheiros incluidos ao
    # lado do fonte, so no directorio de trabalho, e o nucleo inclui a fonte
    # dos caracteres (nucleo/fonte.inc).
    if ! log="$("$NASM" -f bin -w+all -I "$pasta" "$src" -o "$out" 2>&1)"; then
        printf '%s\n' "$log" >&2
        erro "ERRO" "nasm falhou em: $fonte"
    fi

    # avisos a serio: todos menos os que estao na lista de ignorados
    avisos="$(printf '%s\n' "$log" | grep -i 'warning' | grep -v "$AVISO_IGNORADO" || true)"
    if [ -n "$avisos" ]; then
        printf '%s\n' "$log" >&2
        erro "AVISO" "nasm reportou avisos em $fonte - ver acima (build abortado)"
    fi

    # os avisos ignorados ficam contados, nunca silenciosos
    ignorados="$(printf '%s\n' "$log" | grep -c "$AVISO_IGNORADO" || true)"
    if [ "$ignorados" -gt 0 ]; then
        printf '        %s avisos %s (esperados)\n' "$ignorados" "$AVISO_IGNORADO"
    fi

    printf '        %s bytes\n' "$(stat -c%s "$out")"
}

# --- 2. montar a ISO ---------------------------------------------------------
montar_iso() {
    local alvo_mbr="$DIR_ISO/$NOME_MBR"    # caminho dentro da ISO
    local alvo_ger="$DIR_ISO/$NOME_GER"
    local rel_mbr="$INICIO/$NOME_MBR"      # caminho no disco
    local rel_ger="$INICIO/$NOME_GER"
    local alvo_nuc="$DIR_NUC/$NOME_NUC"
    local rel_nuc="$NUCLEO/$NOME_NUC"
    local alvo_drv="$DIR_MOTOR/$NOME_DRV"
    local rel_drv="$MOTOR/$NOME_DRV"
    local alvo_int="$DIR_INT/$NOME_INT"
    local rel_int="$INTERFACE/$NOME_INT"
    local alvo_bar="$DIR_INT/$NOME_BAR"
    local rel_bar="$INTERFACE/$NOME_BAR"

    rm -f "$ISO"

    printf '  iso  %s + %s + %s + %s + %s + %s -> %s\n' \
        "$alvo_mbr" "$alvo_ger" "$alvo_nuc" "$alvo_drv" "$alvo_int" "$alvo_bar" \
        "$(basename "$ISO")"

    # -graft-points     monta a ISO do fonte, sem pasta de staging
    # -b                boot image -> inicio/inimin.mai
    # -no-emul-boot     a BIOS carrega os sectores tal e quais
    # -boot-load-size   4 sectores = 2048 bytes de espaco para o loader
    # (o genisoimage gera o boot.catalog sozinho: nao ha GRUB nem isolinux)
    # -iso-level        os nomes vao para o disco tal e qual (ver NIVEL_ISO)
    #
    # A interface e a barra vao para a mesma pasta da ISO (interface/): e o
    # inicio.mai que as procura la pelas strings exatas, uma de cada vez.
    ( cd "$RAIZ" && "$GENISOIMAGE" -quiet -o "$ISO" \
        -graft-points \
        -iso-level "$NIVEL_ISO" \
        -b "$alvo_mbr" \
        -no-emul-boot -boot-load-size 4 \
        -J -R -V "MAISUS" \
        "/$alvo_mbr=$rel_mbr" \
        "/$alvo_ger=$rel_ger" \
        "/$alvo_nuc=$rel_nuc" \
        "/$alvo_drv=$rel_drv" \
        "/$alvo_int=$rel_int" \
        "/$alvo_bar=$rel_bar" ) 2>/dev/null \
        || erro "ERRO" "genisoimage falhou"

    [ -f "$ISO" ] || erro "ERRO" "ISO nao foi criada: $ISO"
    printf '        %s bytes\n' "$(stat -c%s "$ISO")"
}

# --- 3. correr ---------------------------------------------------------------
correr() {
    printf '  qemu %-24s -> %s\n' "$(basename "$ISO")" "$QEMU_DISPLAY"
    printf '\n  %sfechar a janela do QEMU para o comando terminar%s\n' "$TITULO" "$FIM"
    printf '  %snao ha loop: o build corre uma vez so%s\n\n' "$TITULO" "$FIM"

    set +e
    "$QEMU" -cdrom "$ISO" -boot d -m 128 -display "$QEMU_DISPLAY"
    local rc=$?
    set -e
    return $rc
}

# --- main --------------------------------------------------------------------
main() {
    printf '\n%s==> Maisus Build %s%s\n\n' "$TITULO" "$BUILD" "$FIM"

    verificar_ferramentas

    printf '%s[1/3] a ensamblar%s\n' "$TITULO" "$FIM"
    ensamblar "$INICIO" "$FONTE_MBR" "$NOME_MBR"
    ensamblar "$INICIO" "$FONTE_GER" "$NOME_GER"
    ensamblar "$NUCLEO" "$FONTE_NUC" "$NOME_NUC"
    ensamblar "$MOTOR" "$FONTE_DRV" "$NOME_DRV"
    ensamblar "$INTERFACE" "$FONTE_INT" "$NOME_INT"
    ensamblar "$INTERFACE" "$FONTE_BAR" "$NOME_BAR"
    mapa
    printf '\n'

    printf '%s[2/3] a montar a ISO%s\n' "$TITULO" "$FIM"
    montar_iso
    printf '\n'

    printf '%s[3/3] a correr no QEMU%s\n' "$TITULO" "$FIM"
    correr
    printf '\n  %sqemu terminou%s\n' "$TITULO" "$FIM"
}

main "$@"
