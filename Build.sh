#!/usr/bin/env bash
# ============================================================================
#  Maisus - Build.sh
#
#  1. Ensambla inicio/inicio_minimo.asm  ->  inicio/inimin.mai
#  2. Monta a ISO (sem GRUB, sem isolinux) com inicio/inimin.mai
#  3. Lanca o QEMU com a ISO
#
#  Nao existe pasta de staging: a ISO e montada com -graft-points, directement
#  a partir do binario em inicio/.
#  Ao fechar a janela do QEMU, este comando termina.
# ============================================================================

set -euo pipefail

# --- caminhos ---------------------------------------------------------------
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INICIO="$RAIZ/inicio"                  # pasta do fonte e do binario
ISO="$RAIZ/Maisus.iso"

# --- nomes ------------------------------------------------------------------
FONTE="inicio_minimo.asm"             # fonte do setor 0 (MBR)
NOME_MAI="inimin.mai"                 # binario: dentro e fora da ISO
DIR_ISO="inicio"                       # pasta do binario dentro da ISO

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

# --- 1. ensamblar ------------------------------------------------------------
#   nasm nao tem como renomear a saida: compilamos directamente para inimin.mai
ensamblar() {
    local src="$INICIO/$FONTE"
    local out="$INICIO/$NOME_MAI"
    local log

    printf '  nasm  %-24s -> %s\n' "$FONTE" "$NOME_MAI"
    [ -f "$src" ] || erro "ERRO" "fonte nao encontrada: $src"

    # -w+all activa todos os avisos. Um sector truncado (ex: porta 0x3DA
    # reduzida a 0xDA) assembla sem erro e sobe na mesma -> aviso = falha.
    if ! log="$("$NASM" -f bin -w+all "$src" -o "$out" 2>&1)"; then
        printf '%s\n' "$log" >&2
        erro "ERRO" "nasm falhou em: $FONTE"
    fi
    if printf '%s' "$log" | grep -qi 'warning'; then
        printf '%s\n' "$log" >&2
        erro "AVISO" "nasm reportou avisos em $FONTE - ver acima (build abortado)"
    fi

    printf '        %s bytes\n' "$(stat -c%s "$out")"
}

# --- 2. montar a ISO ---------------------------------------------------------
montar_iso() {
    local alvo="$DIR_ISO/$NOME_MAI"      # caminho dentro da ISO
    local rel="$INICIO/$NOME_MAI"        # caminho no disco

    rm -f "$ISO"
    printf '  iso  %-24s -> %s\n' "$alvo" "$(basename "$ISO")"

    # -graft-points     monta a ISO do fonte, sem pasta de staging
    # -b                boot image -> inicio/inimin.mai
    # -no-emul-boot     a BIOS carrega os sectores tal e qual
    # -boot-load-size   4 sectores = 2048 bytes de espaco para o loader
    # (o genisoimage gera o boot.catalog sozinho: nao ha GRUB nem isolinux)
    ( cd "$RAIZ" && "$GENISOIMAGE" -quiet -o "$ISO" \
        -graft-points \
        -b "$alvo" \
        -no-emul-boot -boot-load-size 4 \
        -J -R -V "MAISUS" \
        "/$alvo=$rel" ) 2>/dev/null \
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
    printf '\n%s==> Maisus Build%s\n\n' "$TITULO" "$FIM"

    verificar_ferramentas

    printf '%s[1/3] a ensamblar%s\n' "$TITULO" "$FIM"
    ensamblar
    printf '\n'

    printf '%s[2/3] a montar a ISO%s\n' "$TITULO" "$FIM"
    montar_iso
    printf '\n'

    printf '%s[3/3] a correr no QEMU%s\n' "$TITULO" "$FIM"
    correr
    printf '\n  %sqemu terminou%s\n' "$TITULO" "$FIM"
}

main "$@"
