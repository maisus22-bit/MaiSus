#!/usr/bin/env python3
# ============================================================================
#  Maisus - imagens/conversor_de_imagens.py
#
#  FERRAMENTA DE COMPILACAO. Este ficheiro NUNCA entra na ISO: e o que traduz
#  um PNG num .img, e nao ha nada no arranque que o leia. Corre-se a mao:
#
#      python3 imagens/conversor_de_imagens.py
#
#  saida: imagens/logo.img - o ficheiro que o inicio.mai carrega da ISO
#  (/imagens/logo.img) para IMG_SEG, e que o nucleo manda o decodificador
#  desenhar no ecra de video.
#
#  ---------------------------------------------------------------------------
#  O QUE E UM .img
#
#  O .img e uma imagem INDEXADA: uma paleta de ate 256 cores e, por pixel, o
#  indice de uma cor dessa paleta. Nao e PNG, nao e BMP e nao tem codificacao
#  nenhuma - e o formato mais pequeno que da para escrever num ecra de 8 bits,
#  que e o modo em que o QEMU arranca o Maisus (0x13, 320x200x256).
#
#  Um pixel e um byte e a imagem inteira cabe em sectores de 2048 bytes, que e
#  como o inicio.mai a carrega da ISO. Um PNG de 322 KiB seria grande demais e
#  teria de ser comprimido em codigo assembly - a paleta resolve o problema sem
#  codigo nenhum.
#
#  O desenho:
#
#    offset  tamanho  o que e
#    0x00    4        assinatura 'IMG1' (quem carrega o ficheiro ve-a antes de
#                      o usar: e o mesmo THEM de assinatura que o video.dr e o
#                      teclado.dr põem no primeiro dword da imagem)
#    0x04    2        versao do formato (1)
#    0x06    2        largura da imagem, em pixels
#    0x08    2        altura da imagem, em pixels
#    0x0A    2        quantas cores a paleta tem (1 a 256)
#    0x0C    2        onde comecam os pixels, em bytes desde o inicio
#    0x0E    2        reservado (a zero)
#    0x10    1024     a paleta: 256 entradas de 4 bytes, { db r, db g, db b,
#                     db 0 }, a contar da primeira
#    0x410   ...      os pixels: largura * altura bytes, um indice de paleta
#                     por pixel, da esquerda para a direita e de cima para baixo
#
#  A paleta e sempre 256 entradas mesmo que a imagem tenha menos cores: assim o
#  offset dos pixels e sempre 0x410 e o decodificador nao tem uma conta a fazer
#  para os casos em que a paleta e curta. As entradas que a imagem nao usa ficam
#  a zero (preto) e nao custam nada.
#
#  A ENTRADA 0 E O PRETO, sempre. Nao e uma escolha estetica: o nucleo limpa o
#  ecra a escrever o indice 0 em todos os pixels (o limpar_video), e o
#  rectangulo da imagem fica no meio com o que sobrou dos lados - as margens.
#  Como o decodificador poe a paleta DESTA imagem no registo de cores do ecra
#  (para o logo ter as suas cores e nao as de um ecra de texto), o indice 0 e
#  o preto desta paleta que pinta as margens. Por isso o quantizador fica com
#  255 cores e o preto entra a seguir, e nenhum dos dois se mexe.
#
#  Este cabecalho e o mesmo no nucleo.asm e no decodificador_de_imagem.asm: e o
#  contrato, e nenhum dos tres o pode mudar sem mudar os outros.
#
#  ---------------------------------------------------------------------------
#  O QUE E QUE FAZ ESTE SCRIPT
#
#  1. Abre o PNG e junta o que e transparente com o preto (o ecra esta preto,
#     e um PNG com transparencia daria um resultado diferente no ecra e no
#     editor).
#  2. Corta o preto a volta da imagem (--sem-corte desliga). Um logo suele
#     vir com uma moldura preta em volta, que no ecra e indistinguivel do
#     preto de fundo e so faz a imagem parecer menor do que e.
#  3. Reduz a imagem para que caiba em LARG x ALT, sem mexer na proporcao -
#     e a imagem que o decodificador desenha, e o que se ve.
#  4. Quantiza para 255 cores, poe o preto no indice 0 e escreve o .img.
#
#  A reducao e feita aqui e nao no decodificador porque o que se ve e o .img:
#  se o conversor mandasse a imagem no tamanho dela e o decodificador
#  encolhesse, cada pixel do ecra seria uma amostra de uma imagem de 1254x1254
#  e a imagem ficava pior a cada mudanca de formato. O decodificador so encolhe
#  quando o ecra e MENOR do que a imagem - e nesse caso nao ha escolha.
# ============================================================================

import argparse
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("falta o Pillow: sudo apt install -y python3-pil")

# --- o formato ---------------------------------------------------------------
ASSINATURA = b"IMG1"      # os 4 primeiros bytes do .img
VERSAO = 1                # a versao do formato que este script escreve
TAM_ENTRADA = 4           # bytes por cor na paleta: { r, g, b, 0 }
ENTRADAS = 256            # a paleta e sempre deste tamanho (ver a nota de cima)
PRETO = b"\x00\x00\x00"   # a cor da entrada 0: as margens do ecra
TAM_PALETA = ENTRADAS * TAM_ENTRADA
CABECALHO = 0x10 + TAM_PALETA   # 0x410: onde comecam os pixels
VERSAO_CABECALHO = 1      # a versao do formato (offset 0x04)

# O ecra em que o Maisus arranca e o 0x13: 320x200. E o tamanho maximo por
# omissao porque e o modo que o video.dr escolhe no QEMU, e a imagem fica do
# tamanho certo sem o nucleo ter de a esticar. Numa tela maior fica
# centralizada e com preto aos lados - e o nucleo que decide isso.
LARG_PADRAO = 320
ALT_PADRAO = 200
CORES_PADRAO = 255         # 256 e o maximo da paleta, mas o indice 0 e sempre
                           # o preto (ver a nota de cima), e por isso que o
                           # quantizador fica com uma a menos

# O decodificador copia a imagem linha a linha para um bloco de 1024 bytes
# (ver decodificador_de_imagem.asm): mais larga do que isso e o decodificador
# recusa a imagem. O limite e do decodificador, nao deste script - o script
# avisa e nao escreve um .img que nao va ser lido.
LARG_MAX_DECODIFICADOR = 1024

# O que corta a moldura preta: um pixel acima deste valor conta-se como conteudo.
LIMIAR_CORTE = 16

# ============================================================================
# caixa_do_conteudo: a caixa onde a imagem tem alguma coisa que nao seja preto
#   entrada: a imagem ja em RGB
#   saida:   (esquerda, cima, direita, baixo), ou None se a imagem for toda preta
#
#   E o que da a margem (--margem) para a moldura preta, sem o converter a
#   propria: um logo e desenhado com o seu espaco em volta, e 0 pixels de
#   espaco dao a impressao de que a imagem foi cortada a meio.
# ============================================================================
def caixa_do_conteudo(img):
    cinza = img.convert("L")
    # "point" e o que transforma o brilho em "conteudo ou nao": sem ele um
    # quase-preto de JPEG contaria como conteudo e a caixa seria a imagem toda.
    mascara = cinza.point(lambda v: 255 if v > LIMIAR_CORTE else 0)
    return mascara.getbbox()


# ============================================================================
# reduzir: a imagem no tamanho maximo, com a proporcao mantida
#   entrada: a imagem, a largura e a altura maximas
#   saida:   a imagem reduzida, ou a mesma se ja cabia
#
#   LANCZOS e o filtro de reamostragem do Pillow que fica melhor nas imagens
#   com texto e com linhas finas (que e o caso de um logo): ao contrario do
#   NEAREST (o "vizinho mais proximo", o mesmo que o decodificador usa) nao
#   parece um xadrez. Aqui importa a qualidade, porque a imagem so e reduzida
#   uma vez - no decodificador ja nao ha qualidade para perder.
# ============================================================================
def reduzir(img, larg, alt):
    if img.width <= larg and img.height <= alt:
        return img
    # A escala e a menor das duas contas: e ela que garante que a imagem cabe
    # nos dois sentidos ao mesmo tempo, sem a distorcer.
    escala = min(larg / img.width, alt / img.height)
    tam = (max(1, round(img.width * escala)), max(1, round(img.height * escala)))
    return img.resize(tam, Image.LANCZOS)


# ============================================================================
# quantizar: ate N cores, sem dithering
#
#   O dithering (a dispersao de pontos para fingir uma cor que nao existe) foi
#   desligado de proposito: no ecra a imagem ja e reduzida outra vez pelo
#   decodificador, e o dithering a essa escala transforma-se em ruido. Sem
#   dithering uma cor da paleta e sempre um indice, e o indice escreve-se
#   directamente no framebuffer de 8 bits.
#
#   MEDIANCUT e o metodo do Pillow que escolhe as cores pelo corte da arvore
#   das medias: e o que da as 255 cores mais bem aproveitadas. Sao as que a
#   paleta acaba por ter, e o que define a qualidade da imagem no ecra.
#
#   NUNCA 256 cores aqui: a entrada 0 da paleta e o preto das margens (ver a
#   nota de cima do ficheiro), e uma cor do quantizador a mais empurrava o
#   ultimo indice para fora. Por isso o limite e ENTRADAS-1.
# ============================================================================
def quantizar(img, cores):
    cores = min(cores, ENTRADAS - 1)
    return img.quantize(colors=cores, method=Image.Quantize.MEDIANCUT,
                        dither=Image.Dither.NONE)


# ============================================================================
# escrever: grava o .img
#   entrada: a imagem ja em modo "P", o caminho de saida
#   saida:   o tamanho do ficheiro em bytes
#
#   O ficheiro e escrito de uma vez, com struct.pack. A ordem dos campos e a do
#   formato (ver a nota de cima) e sao todos "<": o CPU e um x86 pequeno, e um
#   numero que isnt o le-se ao contrario. Os 2 bytes reservados ficam a zero
#   porque o struct comecou a zero e o "<H" escreve em cima deles.
#
#   A paleta e escrita com o preto no indice 0 e as cores do quantizador a
#   partir do indice 1, e os pixels sao mudados de lugar para acompanhar: um
#   pixel que o quantizador pôs na cor 0 passa a ser a cor 1, e so o preto
#   exacto fica no 0. E o que faz o logo e as margens em volta dele serem a
#   MESMA cor: o ecra foi limpo a preto (o que o nucleo faz antes de chamar o
#   decodificador) e o que fica em volta do rectangulo e o que sobrou disso.
# ============================================================================
def escrever(img, caminho):
    import struct

    larg, alt = img.size
    paleta = list(img.getpalette() or [])

    # A paleta do Pillow tem tres bytes por cor e nao quatro, e so traz as
    # cores que a imagem usa: o ficheiro tem de ter as 256 entradas de quatro
    # bytes, com o byte 0 a zero em todas. Um indice que a paleta do Pillow nao
    # tem (porque a quantizacao deixou essa cor de fora) sai a preto, que e o
    # mesmo que o byte a zero.
    #
    # As 256 entradas enchem-se de uma vez: o indice 0 com o preto (que e a
    # cor das margens do ecra) e as restantes com as cores do quantizador, que
    # por isso comecam no indice 1. daqui em diante a entrada i e a cor que o
    # indice i mostra, com o mesmo i que vai para os pixels.
    entradas = bytearray(TAM_PALETA)
    entradas[0:3] = PRETO
    quantizadas = min(len(paleta) // 3, ENTRADAS - 1)
    for i in range(quantizadas):
        base = i * 3
        destino = (i + 1) * TAM_ENTRADA
        entradas[destino + 0] = paleta[base]
        entradas[destino + 1] = paleta[base + 1]
        entradas[destino + 2] = paleta[base + 2]

    # Os pixels mudam de indice com a paleta: o que era a cor i passa a ser a
    # cor i+1. O preto e a excepcao - um pixel preto vai para o indice 0, que e
    # o mesmo preto das margens, e nao para uma cor que so parece preta.
    #
    # A comparacao e com o RGB da imagem ja quantizada (e nao com o do PNG de
    # origem): o que interessa e o que se ve no ecra depois da quantizacao, e
    # nao o pixel de antes dela. O "min" e porque um pixel na cor 255 do
    # quantizador iria para o indice 256, que ja esta a seguir do fim da
    # paleta - e um indice a mais mostraria o que estivesse la, que e o que o
    # bytearray encheu de zeros.
    rgb = img.convert("RGB").tobytes()
    dados = bytearray(img.tobytes())
    for i in range(len(dados)):
        j = i * 3
        if rgb[j] == 0 and rgb[j + 1] == 0 and rgb[j + 2] == 0:
            dados[i] = 0
        else:
            dados[i] = min(dados[i] + 1, ENTRADAS - 1)

    # O numero de cores e o maior indice usado mais um, e nao o numero de
    # cores distintas: e o indice que o decodificador le da paleta, e um indice
    # buraco (uma cor que a paleta tem e a imagem nao usa) faz o mesmo estrago
    # que uma cor a mais - por isso se conta pelo maior e nao pelo numero. O
    # indice 0 conta mesmo sem nenhum pixel preto: e a cor das margens.
    usadas = max(dados) + 1 if max(dados) > 0 else 1

    # 4s + 6 H = 16 bytes: a assinatura e os seis campos de 2 bytes do
    # cabecalho (0x04 a 0xF). O "<" e o que poem os numeros na ordem do x86.
    cabecalho = struct.pack("<4sHHHHHH", ASSINATURA, VERSAO_CABECALHO,
                            larg, alt, usadas, CABECALHO, 0)
    with open(caminho, "wb") as f:
        f.write(cabecalho)
        f.write(entradas)
        f.write(dados)
    return len(cabecalho) + len(entradas) + len(dados)


# ============================================================================
def main():
    ap = argparse.ArgumentParser(
        description="traduz um PNG num .img para o Maisus")
    ap.add_argument("--origem", default="imagens/image.png",
                    help="o PNG de entrada (omissao: imagens/image.png)")
    ap.add_argument("--saida", default="imagens/logo.img",
                    help="o .img de saida (omissao: imagens/logo.img)")
    ap.add_argument("--larg", type=int, default=LARG_PADRAO,
                    help="largura maxima, em pixels (omissao: %d)" % LARG_PADRAO)
    ap.add_argument("--alt", type=int, default=ALT_PADRAO,
                    help="altura maxima, em pixels (omissao: %d)" % ALT_PADRAO)
    ap.add_argument("--cores", type=int, default=CORES_PADRAO,
                    help="cores do quantizador, 1 a 255 (omissao: %d; a entrada 0 da paleta e "
                         "sempre o preto)" % CORES_PADRAO)
    ap.add_argument("--margem", type=int, default=3,
                    help="pixels de respiro a volta da imagem (omissao: 3)")
    ap.add_argument("--sem-corte", action="store_true",
                    help="nao cortar o preto a volta da imagem")
    opcoes = ap.parse_args()

    if not (1 <= opcoes.cores <= ENTRADAS - 1):
        ap.error("--cores tem de estar entre 1 e %d (a entrada 0 e sempre o "
                 "preto das margens)" % (ENTRADAS - 1))
    if opcoes.larg < 1 or opcoes.alt < 1:
        ap.error("--larg e --alt tem de ser pelo menos 1")

    try:
        img = Image.open(opcoes.origem)
    except OSError as erro:
        sys.exit("nao consegui abrir o PNG: %s" % erro)
    if img.mode != "RGB":
        # A transparencia (o canal A) junta-se com o preto: o ecra do nucleo
        # e preto e um PNG transparente daria, no ecra, um resultado diferente
        # do que se ve no editor.
        img = img.convert("RGBA")
        fundo = Image.new("RGB", img.size, (0, 0, 0))
        fundo.paste(img, mask=img.getchannel("A"))
        img = fundo

    if not opcoes.sem_corte:
        caixa = caixa_do_conteudo(img)
        if caixa is not None:
            esq, cim, dir, baixo = caixa
            m = opcoes.margem
            caixa = (max(0, esq - m), max(0, cim - m),
                     min(img.width, dir + m), min(img.height, baixo + m))
            if caixa[2] - caixa[0] > 0 and caixa[3] - caixa[1] > 0:
                img = img.crop(caixa)
                print("  corte    %s -> %d x %d" % (caixa, img.width, img.height))

    antes = img.size
    img = reduzir(img, opcoes.larg, opcoes.alt)
    print("  imagem   %d x %d -> %d x %d" % (antes[0], antes[1],
                                             img.width, img.height))

    if img.width > LARG_MAX_DECODIFICADOR:
        sys.exit("a imagem ficou com %d pixels de largura e o decodificador so "
                 "le ate %d: baixa o --larg" % (img.width,
                                               LARG_MAX_DECODIFICADOR))

    img = quantizar(img, opcoes.cores)
    tamanho = escrever(img, opcoes.saida)

    distintas = len(img.getcolors(img.width * img.height) or [1])
    print("  paleta   %d cores distintas" % distintas)
    print("  saida    %s  %d bytes  (%d sectores de 2048)" %
          (opcoes.saida, tamanho, -(-tamanho // 2048)))


if __name__ == "__main__":
    main()
