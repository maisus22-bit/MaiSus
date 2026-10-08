#  1. Verifica que a imagem do logo (imagens/logo.img) existe
#  2. Ensambla os doze estagios:
#        inicio/inicio_minimo.asm    ->  inicio/inimin.mai   (setor 0 / boot)
#        inicio/inicio.asm           ->  inicio/inicio.mai  (gerenciador)
#        nucleo/nucleo.asm           ->  nucleo/0.12.2026    (nucleo)
#        drivers/video.asm           ->  drivers/video.dr    (driver de video)
#        drivers/teclado.asm         ->  drivers/teclado.dr  (driver de teclado,
#                                        chamado pelo inicio.mai e pelo nucleo)
#        drivers/mouse.asm           ->  drivers/mouse.dr    (driver de rato,
#                                        carregado pelo inicio.mai e executado
#                                        pelo nucleo - liga a IRQ12)
#        interface/interface.asm     ->  interface/face.grain (interface grafica)
#        interface/barra_inferior.asm
#                                    ->  interface/barinf.grain (barra inferior,
#                                        executada pelo face.grain)
#        interface/barra_superior.asm
#                                    ->  interface/barsup.grain (barra superior,
#                                        executada pelo barinf.grain)
#        interface/menu.asm          ->  interface/menu.grain (menu,
#                                        executado pelo barsup.grain)
#        imagens/decodificador_de_imagem.asm
#                                    ->  imagens/decod.img   (decodificador de
#                                        imagem, chamado pelo nucleo)
#        inicio/recuperacao.asm      ->  inicio/recu.mai    (ecra de recuperacao,
#                                        a segunda opcao do menu)
#  3. Monta a ISO (sem GRUB, sem isolinux) com os ficheiros
#  4. Lanca o QEMU com a ISO
#
#  O logo (imagens/logo.img) nao e ensamblado nem gerado: e um ficheiro de dados
#  feito a mao pelo conversor (imagens/conversor_de_imagens.py, que nunca entra
#  na ISO). O build falha se ele nao existir - ver verificar_imagem.
#
#  Nao existe pasta de staging: a ISO e montada com -graft-points, directement
#  a partir dos binarios em inicio/, nucleo/, drivers/, interface/ e imagens/.
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
BUILD="0.12.2026"

# --- nomes ------------------------------------------------------------------
# sao dois ficheiros separados: um fonte e um binario para cada estagio
FONTE_MBR="inicio_minimo.asm"     # fonte do setor 0 (MBR): o boot sector
NOME_MBR="inimin.mai"             # binario: dentro e fora da ISO
FONTE_GER="inicio.asm"            # fonte do gerenciador de boot
NOME_GER="inicio.mai"             # binario: dentro e fora da ISO
FONTE_NUC="nucleo.asm"            # fonte do nucleo
NOME_NUC="$BUILD"                 # binario: "0.12.2026", dentro e fora da ISO
FONTE_DRV="video.asm"             # fonte do driver de video
NOME_DRV="video.dr"               # binario: dentro e fora da ISO
FONTE_TEC="teclado.asm"           # fonte do driver de teclado
NOME_TEC="teclado.dr"             # binario: dentro e fora da ISO
FONTE_MOU="mouse.asm"             # fonte do driver de rato
NOME_MOU="mouse.dr"               # binario: dentro e fora da ISO
FONTE_INT="interface.asm"         # fonte da interface grafica
NOME_INT="face.grain"             # binario: dentro e fora da ISO
FONTE_BAR="barra_inferrior.asm"   # fonte da barra inferior
NOME_BAR="barinf.grain"           # binario: dentro e fora da ISO
FONTE_SUP="barra_superior.asm"    # fonte da barra superior
NOME_SUP="barsup.grain"           # binario: dentro e fora da ISO
FONTE_MEN="menu.asm"              # fonte do menu
NOME_MEN="menu.grain"             # binario: dentro e fora da ISO
FONTE_DEC="decodificador_de_imagem.asm"  # fonte do decodificador de imagem
NOME_DEC="decod.img"              # binario: dentro e fora da ISO
FONTE_REC="recuperacao.asm"        # fonte do ecra de recuperacao
NOME_REC="recu.mai"                # binario: dentro e fora da ISO
DIR_ISO="inicio"                       # pasta dos binarios dentro da ISO
DIR_NUC="nucleo"                       # pasta do nucleo dentro da ISO
DIR_MOTOR="drivers"                    # pasta dos drivers dentro da ISO
DIR_INT="interface"                    # pasta da interface dentro da ISO
DIR_IMG="imagens"                      # pasta da imagem dentro da ISO
INTERFACE="$RAIZ/interface"              # pasta da interface
IMAGENS="$RAIZ/imagens"                  # pasta da imagem
NOME_LOGO="logo.img"                 # a imagem do logo: dentro e fora da ISO

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
#   O inicio.mai carrega os ficheiros em enderecos fixos, que sao constantes nos
#   fontes (NUC_SEG e DRV_SEG em inicio.asm, DRV_LIN em nucleo.asm, BAR_SEG e
#   SUP_SEG em inicio.asm e em interface.asm). Se a imagem de um deles mudar de
#   tamanho, o inicio.mai passa a ler sectores a mais ou a menos e quem o executa
#   vai ler dados estruturados a esmo - por isso o mapa e impresso todas as
#   vezes, e nao so no fonte.
mapa() {
    local n d t
    n="$(stat -c%s "$NUCLEO/$NOME_NUC")"
    d="$(stat -c%s "$MOTOR/$NOME_DRV")"
    t="$(stat -c%s "$MOTOR/$NOME_TEC")"
    printf '  mapa  %-12s %4s bytes  0x%04X-0x%04X  (%s sectores)\n' \
        "$NOME_NUC" "$n" "$((0xC000))" \
        "$((0xC000 + ((n + 2047) / 2048) * 2048 - 1))" "$(((n + 2047) / 2048))"
    printf '  mapa  %-12s %4s bytes  0x%04X-0x%04X  (%s sectores)\n' \
        "$NOME_DRV" "$d" "$((0xE000))" \
        "$((0xE000 + ((d + 2047) / 2048) * 2048 - 1))" "$(((d + 2047) / 2048))"

    # A recuperacao e o unico ficheiro abaixo do inicio.mai: vive em 0x9000, no
    # intervalo que sobra entre o BUF da caminhada (0x8000) e o inicio.mai
    # (0xA000) - REC_LIN no inicio.asm. Fica no mapa pela mesma razao dos
    # outros: e um endereco fixo, e se a imagem crescer para fora dos 2 sectores
    # que o inicio.mai le (REC_SET) e para dentro do inicio.mai, quem o executa
    # le codigo do gerenciador em vez do codigo da recuperacao. O limite
    # escrita a mao e o mesmo que no fonte - as duas contas que tem de concordar
    # sao o REC_LIN de la e o 0x9000 daqui.
    local rec
    rec="$(stat -c%s "$INICIO/$NOME_REC")"
    printf '  mapa  %-12s %4s bytes  0x%04X-0x%04X  (%s sectores)\n' \
        "$NOME_REC" "$rec" "$((0x9000))" \
        "$((0x9000 + ((rec + 2047) / 2048) * 2048 - 1))" "$(((rec + 2047) / 2048))"
    printf '  mapa  %-12s %4s bytes  0x%05X-0x%05X  (%s sectores)\n' \
        "$NOME_TEC" "$t" "$((0x60000))" \
        "$((0x60000 + ((t + 2047) / 2048) * 2048 - 1))" "$(((t + 2047) / 2048))"
    # o driver de rato vive a seguir ao decodificador, em 0x90000 (MOU_LIN em
    # inicio.asm e em mouse.asm): o primeiro sitio livre acima do teclado, do
    # logo e do decodificador. Se a imagem crescer para dentro do que vier a
    # seguir, o mapa da a ver antes do arranque.
    local mou
    mou="$(stat -c%s "$MOTOR/$NOME_MOU")"
    printf '  mapa  %-12s %4s bytes  0x%05X-0x%05X  (%s sectores)\n' \
        "$NOME_MOU" "$mou" "$((0x90000))" \
        "$((0x90000 + ((mou + 2047) / 2048) * 2048 - 1))" "$(((mou + 2047) / 2048))"
    # a interface, as duas barras e o menu tambem entram em enderecos fixos, e
    # todas seguem a mesma regra: segmento = linear / 16
    local lin
    for lin in 0x20000:face 0x30000:barinf 0x40000:barsup 0x50000:menu; do
        local end="${lin%%:*}" nome="${lin##*:}"
        local tam="$INTERFACE/$nome.grain"
        printf '  mapa  %-12s %4s bytes  0x%05X-0x%05X  (%s sectores)\n' \
            "$nome.grain" "$(stat -c%s "$tam")" "$end" \
            "$((end + (( $(stat -c%s "$tam") + 2047) / 2048) * 2048 - 1))" \
            "$((( $(stat -c%s "$tam") + 2047) / 2048))"
    done

    # o .img do logo e o decod.img seguem a mesma regra: o logo em 0x70000 e o
    # codigo em 0x80000 (IMG_LIN e DEC_LIN no inicio.asm), e o decodificador vai
    # ler o logo enquanto corre - por isso os dois nao podem entrar um no outro
    local l d
    l="$(stat -c%s "$IMAGENS/$NOME_LOGO")"
    d="$(stat -c%s "$IMAGENS/$NOME_DEC")"
    printf '  mapa  %-12s %4s bytes  0x%05X-0x%05X  (%s sectores)\n' \
        "$NOME_LOGO" "$l" "$((0x70000))" \
        "$((0x70000 + ((l + 2047) / 2048) * 2048 - 1))" "$(((l + 2047) / 2048))"
    printf '  mapa  %-12s %4s bytes  0x%05X-0x%05X  (%s sectores)\n' \
        "$NOME_DEC" "$d" "$((0x80000))" \
        "$((0x80000 + ((d + 2047) / 2048) * 2048 - 1))" "$(((d + 2047) / 2048))"
}

# --- 1b. o numero do build, conferido nos binarios --------------------------
#   O numero do build tem de concordar em tres sitios (ver a nota de la em cima):
#   a variavel BUILD, o nome que o inicio.mai procura na ISO e o titulo que o
#   nucleo escreve no ecra. A regra e escrita a mao e as tres coisas vivem em
#   ficheiros diferentes, pelo que uma mudanca de build deixa sempre um sitio
#   para esquecer - e o esquecimento nao se ve no build: assembla bem, a ISO
#   monta bem, e o que falha e em silencio.
#
#   Os dois silencios que aqui ficam apanhados:
#
#     - o inicio.mai procura "0.9.2026" e o Build.sh meter "0.12.2026": a
#       caminhada pela ISO nao acha o nucleo, e o arranque cai no ecra de
#       falha (todo azul, um "hlt" a dormir) sem dizer porque.
#     - o nucleo escreve o titulo sem o numero: o titulo fica um bocado mais
#       curto e o ecra parece o de sempre. Nao ha aviso nenhum - so de longe,
#       a contar os caracteres.
#
#   Por isso o build vai aos binarios ja assemblados e procura os bytes: no
#   inicio.mai o nome que vai procurar, e no nucleo o titulo completo. E a
#   verificacao a este nivel: os bytes que van para a ISO, e nao o
#   texto dos fontes, que podem estar bem escritos e nao chegar ao binario.
# --------------------------------------------------------------------------
verificar_build() {
    # O prefixo do titulo e o VERSAO_LONG de nucleo/nucleo.asm. Nao e decorativo:
    # o "grep" abaixo procura esta string nos bytes do nucleo ja assemblado, e um
    # prefixo aqui diferente do de la nao da erro nenhum - da um "nao contem o
    # titulo" sobre um binario que esta perfeitamente bem. (E o que aconteceu da
    # primeira vez que esta verificacao foi escrita, com um "MaisSus" em vez de
    # "MaiSus": o build acusou o nucleo de estar errado quando o errado era o
    # Build.sh.)
    local titulo_esperado="MaiSus Beta v0.1 Build $BUILD"

    if ! grep -qa -- "$BUILD" "$INICIO/$NOME_GER"; then
        erro "BUILD" "o $NOME_GER nao contem o numero do build ($BUILD).
     Procura-o com FIC_NUCLEO em inicio/inicio.asm - e esse o nome que o
     inicio.mai vai procurar na ISO, e o que este build nao poe la."
    fi

    if ! grep -qa -- "$titulo_esperado" "$NUCLEO/$NOME_NUC"; then
        erro "BUILD" "o $NOME_NUC nao contem o titulo completo:
     \"$titulo_esperado\"
     O nucleo escreve esse titulo no ecra do arranque. Ou o numero em
     VERSAO_LIT (nucleo/nucleo.asm) nao e o $BUILD, ou o titulo deixou de ser
     o prefixo colado ao numero (e entao o ecra mostra o titulo sem o numero,
     sem nenhum aviso)."
    fi

    printf '  build  %s concorda em %s, %s e %s\n' \
        "$BUILD" "$NOME_GER" "$NOME_NUC" "nucleo.asm"
}

# --- 1c. a imagem do logo -----------------------------------------------------
#   O conversor (imagens/conversor_de_imagens.py) NAO e corrido aqui: a conversao
#   e a mao, e o que vai para dentro da ISO e sempre o ficheiro que a pessoa
#   escolheu ver. O que este script faz e o oposto de correr o conversor: e
#  Falhar se o logo.img nao existir, em vez de gerar um.
#
#   A razao de nao gerar: o conversor corta a imagem ao conteudo, encolhe-a e
#   quantiza-a com 255 cores. Sao tres decisoes esteticas, e tres pessoas
#   diferentes querem tres resultados diferentes do mesmo PNG. Se o build
#   gerasse o .img sozinho, o logo do ecra seria o resultado das opcoes por
#   omissao do conversor e nao a imagem que a pessoa escolheu - e o resultado
#   mudava de maquina para maquina conforme a versao do Pillow.
#
#   Por isso o caminho e: correr o conversor a mao
#
#       python3 imagens/conversor_de_imagens.py
#
#   e so depois o Build.sh, que falha com uma mensagem que diz o comando a
#   correr. O ficheiro gerado fica no disco (e nao e limpo pelo build), para o
#   proximo build o usar tal e qual.
verificar_imagem() {
    local logo="$IMAGENS/$NOME_LOGO"
    if [ ! -f "$logo" ]; then
        erro "IMAGEM" "$NOME_LOGO nao existe - a conversao e a mao:
    cd \"$RAIZ\" && python3 imagens/conversor_de_imagens.py
  (o build nao corre o conversor: a imagem e a que a pessoa escolheu)"
    fi
    # o .img tem de ter a assinatura, senao o nucleo cai no numero do build em
    # vez de desenhar o logo - e a falha aparece no ecra sem dizer porque
    local assinatura
    assinatura="$(head -c4 "$logo")"
    [ "$assinatura" = "IMG1" ] || erro "IMAGEM" \
        "$NOME_LOGO nao parece um .img (a assinatura devia ser IMG1, e '$assinatura')"
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
    local alvo_tec="$DIR_MOTOR/$NOME_TEC"
    local rel_tec="$MOTOR/$NOME_TEC"
    local alvo_mou="$DIR_MOTOR/$NOME_MOU"
    local rel_mou="$MOTOR/$NOME_MOU"
    local alvo_int="$DIR_INT/$NOME_INT"
    local rel_int="$INTERFACE/$NOME_INT"
    local alvo_bar="$DIR_INT/$NOME_BAR"
    local rel_bar="$INTERFACE/$NOME_BAR"
    local alvo_sup="$DIR_INT/$NOME_SUP"
    local rel_sup="$INTERFACE/$NOME_SUP"
    local alvo_men="$DIR_INT/$NOME_MEN"
    local rel_men="$INTERFACE/$NOME_MEN"
    local alvo_log="$DIR_IMG/$NOME_LOGO"
    local rel_log="$IMAGENS/$NOME_LOGO"
    local alvo_dec="$DIR_IMG/$NOME_DEC"
    local rel_dec="$IMAGENS/$NOME_DEC"
    local alvo_rec="$DIR_ISO/$NOME_REC"   # a recuperacao vai para inicio/, como
    local rel_rec="$INICIO/$NOME_REC"     # o sector 0 e o inicio.mai (DIR_ISO)

    rm -f "$ISO"

    printf '  iso  %s + %s + %s + %s + %s + %s + %s + %s + %s + %s + %s + %s + %s -> %s\n' \
        "$alvo_mbr" "$alvo_ger" "$alvo_nuc" "$alvo_drv" "$alvo_tec" \
        "$alvo_mou" "$alvo_int" "$alvo_bar" "$alvo_sup" "$alvo_men" \
        "$alvo_log" "$alvo_dec" "$alvo_rec" "$(basename "$ISO")"

    # -graft-points     monta a ISO do fonte, sem pasta de staging
    # -b                boot image -> inicio/inimin.mai
    # -no-emul-boot     a BIOS carrega os sectores tal e quais
    # -boot-load-size   4 sectores = 2048 bytes de espaco para o loader
    # (o genisoimage gera o boot.catalog sozinho: nao ha GRUB nem isolinux)
    # -iso-level        os nomes vao para o disco tal e qual (ver NIVEL_ISO)
    #
    # A interface, as barras e o menu vao para a mesma pasta da ISO (interface/):
    # e o inicio.mai que as procura la pelas strings exatas, uma de cada vez.
    #
    # O logo (.img) e o decodificador (.img) vao para uma pasta propria
    # (imagens/), e nao para drivers/ nem para interface/: o primeiro e um
    # ficheiro de dados e o segundo um codigo que o nucleo chama, e nenhum dos
    # dois e parte da interface nem um driver de um dispositivo. A pasta e
    # procurada pelo inicio.mai pelo nome exacto, como as outras.
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
        "/$alvo_tec=$rel_tec" \
        "/$alvo_mou=$rel_mou" \
        "/$alvo_int=$rel_int" \
        "/$alvo_bar=$rel_bar" \
        "/$alvo_sup=$rel_sup" \
        "/$alvo_men=$rel_men" \
        "/$alvo_log=$rel_log" \
        "/$alvo_dec=$rel_dec" \
        "/$alvo_rec=$rel_rec" ) 2>/dev/null \
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

    printf '%s[1/4] a verificar a imagem do logo%s\n' "$TITULO" "$FIM"
    verificar_imagem

    printf '%s[2/4] a ensamblar%s\n' "$TITULO" "$FIM"
    ensamblar "$INICIO" "$FONTE_MBR" "$NOME_MBR"
    ensamblar "$INICIO" "$FONTE_GER" "$NOME_GER"
    ensamblar "$NUCLEO" "$FONTE_NUC" "$NOME_NUC"
    ensamblar "$MOTOR" "$FONTE_DRV" "$NOME_DRV"
    ensamblar "$MOTOR" "$FONTE_TEC" "$NOME_TEC"
    ensamblar "$MOTOR" "$FONTE_MOU" "$NOME_MOU"
    ensamblar "$INTERFACE" "$FONTE_INT" "$NOME_INT"
    ensamblar "$INTERFACE" "$FONTE_BAR" "$NOME_BAR"
    ensamblar "$INTERFACE" "$FONTE_SUP" "$NOME_SUP"
    ensamblar "$INTERFACE" "$FONTE_MEN" "$NOME_MEN"
    ensamblar "$IMAGENS" "$FONTE_DEC" "$NOME_DEC"
    # a recuperacao e a ultima a ser ensamblada porque e a unica que nao pertence
    # a corrente do arranque: e carregada na mesma cadeia, mas e executada a
    # partir do inicio.mai e nao por outra imagem (ver a nota em recuperacao.asm)
    ensamblar "$INICIO" "$FONTE_REC" "$NOME_REC"
    verificar_build
    mapa
    printf '\n'

    printf '%s[3/4] a montar a ISO%s\n' "$TITULO" "$FIM"
    montar_iso
    printf '\n'

    printf '%s[4/4] a correr no QEMU%s\n' "$TITULO" "$FIM"
    correr
    printf '\n  %sqemu terminou%s\n' "$TITULO" "$FIM"
}

main "$@"
