"""Gera os sprites da Neco-Arc para o NecoBrowser a partir do zip do usuário.

    python -I tools/neco_sprites.py            (rodar da raiz do projeto)

Lê   Sprites/Neco Arc Sprites.zip  (fora do Git: é do usuário)
Gera src/ui/NecoSprites.res        RCDATA: NECO_INDEX (texto) + uma folha PNG por animação
     data/neco.ico                 ícone do exe (rosto da nek00)
     %TEMP%/NecoBuild/neco-previa.png  todas as animações lado a lado, para conferir

Para trocar ou acrescentar animações, mexa só na tabela ANIMS. O Pascal lê o índice
e não conhece os nomes dos arquivos originais.

Cada folha tem os quadros lado a lado, todos do mesmo tamanho (o recorte que cobre os
quadros escolhidos), com 2 px transparentes entre eles para o filtro bilinear não
vazar de um quadro para o outro. Os quadros originais vêm num quadro fixo de 256x256
com a posição certa; ANCORA_X e CHAO são o ponto dos pés nesse quadro, e o índice
guarda onde esse ponto caiu dentro do recorte.
"""
import io
import os
import struct
import sys
import tempfile
import zipfile

from PIL import Image

ZIP = os.path.join('Sprites', 'Neco Arc Sprites.zip')
RES = os.path.join('src', 'ui', 'NecoSprites.res')
ICO = os.path.join('data', 'neco.ico')
ANCORA_X = 129   # centro do corpo no quadro 256x256
CHAO = 222       # linha dos pés no quadro 256x256
VAO = 2

# nome: (prefixo no zip, quadros na ordem de exibição, ms por quadro, repete)
ANIMS = {
    'idle':   ('nek00', [0, 1, 2, 3, 4, 3, 2, 1], 150, True),    # parada, respirando
    'hop':    ('nek14', [6, 7, 8, 9, 10, 11, 12, 13], 90, True),  # carregando página
    'sink':   ('nek51', [0, 1, 2, 3, 4, 5, 6], 70, False),       # afunda no chão
    'emerge': ('nek51', [7, 8, 9, 10, 11, 12, 13], 80, False),   # brota do chão
    'slide':  ('nek69', [2, 3, 4, 5, 6, 7, 8, 9, 10], 60, True),  # atravessa deslizando
    'dash':   ('nek14', [2, 3], 50, True),                        # atravessa num borrão
    'shadow': ('nek67', list(range(21)), 60, True),               # gato-sombra (raro)
    'flip':   ('nek16', list(range(17)), 70, False),              # pula e dá cambalhota
    'dance':  ('ner92', list(range(53)), 80, False),              # dancinha
    'turn':   ('nek45', list(range(11)), 90, False),              # vira e faz pose
    'lazy':   ('nek68', list(range(10)), 130, True),              # deitada (ociosa)
    'cheer':  ('nek81', [0, 1, 2, 3, 4, 3, 2, 3, 4], 100, False),  # comemora
    'taunt':  ('nek80', [0, 1, 2, 1, 2, 1, 0], 120, False),       # ri (clique nela)
    # Página de erro (Neco.UI.Main, sobre a área da página)
    'stretcher': ('nek88', [0, 1, 2, 1], 420, True),             # na maca: sem internet
    'tumble': ('nek24', list(range(19)), 85, True),               # tombo: site não encontrado
}


def quadros(z, prefixo, idx):
    """idx = posição na lista ordenada dos arquivos da animação (a numeração no zip tem buracos)."""
    nomes = sorted(n for n in z.namelist()
                   if n.startswith(f'neco/{prefixo}_') and n.count('/') == 1 and n.endswith('.png'))
    return [Image.open(io.BytesIO(z.read(nomes[i]))).convert('RGBA') for i in idx]


def recorte(ims):
    l = t = 10 ** 6
    r = b = -1
    for im in ims:
        bb = im.getbbox()
        if bb:
            l, t, r, b = min(l, bb[0]), min(t, bb[1]), max(r, bb[2]), max(b, bb[3])
    return l, t, r, b


def png(im):
    s = io.BytesIO()
    im.save(s, 'PNG', optimize=True)
    return s.getvalue()


def entrada_res(nome, dados, tipo=10):
    """Uma entrada de .res (formato Win32). tipo 10 = RT_RCDATA; nome em texto."""
    def ident(v):
        if isinstance(v, int):
            return struct.pack('<HH', 0xFFFF, v)
        return (v.upper() + '\0').encode('utf-16-le')
    cab = ident(tipo) + ident(nome)
    if len(cab) % 4:
        cab += b'\0' * (4 - len(cab) % 4)
    cab += struct.pack('<IHHII', 0, 0x0030, 0x0416, 0, 0)  # versão, flags, pt-BR, versão, caract.
    cab = struct.pack('<II', len(dados), 8 + len(cab)) + cab
    corpo = dados + b'\0' * ((4 - len(dados) % 4) % 4)
    return cab + corpo


def main():
    z = zipfile.ZipFile(ZIP)
    indice = ['# nome|res|quadros|largura|altura|ancoraX|chaoY|ms|repete']
    entradas = [b'\0\0\0\0\x20\0\0\0\xff\xff\0\0\xff\xff\0\0' + b'\0' * 16]
    previa = []
    for nome, (prefixo, idx, ms, repete) in ANIMS.items():
        ims = quadros(z, prefixo, idx)
        l, t, r, b = recorte(ims)
        w, h = r - l, b - t
        folha = Image.new('RGBA', (len(ims) * (w + VAO) - VAO, h), (0, 0, 0, 0))
        for i, im in enumerate(ims):
            folha.paste(im.crop((l, t, r, b)), (i * (w + VAO), 0))
        res = 'NECO_' + nome.upper()
        entradas.append(entrada_res(res, png(folha)))
        indice.append(f'{nome}|{res}|{len(ims)}|{w}|{h}|{ANCORA_X - l}|{CHAO - t}|{ms}|{int(repete)}')
        previa.append((nome, folha))
        print(f'{nome:7s} {prefixo} {len(ims):2d} quadros {w}x{h}  pés em ({ANCORA_X - l},{CHAO - t})')
    entradas.insert(1, entrada_res('NECO_INDEX', ('\r\n'.join(indice) + '\r\n').encode('utf-8')))
    with open(RES, 'wb') as f:
        f.write(b''.join(entradas))
    print('gravado', RES, os.path.getsize(RES), 'bytes')

    # Ícone: o rosto da nek00 num quadrado, ampliado sem suavizar.
    rosto = quadros(z, 'nek00', [0])[0].crop((112, 175, 146, 209))
    grande = rosto.resize((256, 256), Image.NEAREST)
    grande.save(ICO, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print('gravado', ICO)

    # Prévia para conferência, fora do projeto.
    larg = max(f.width for _, f in previa) * 2
    alt = sum(f.height * 2 + 6 for _, f in previa)
    p = Image.new('RGBA', (larg, alt), (30, 31, 34, 255))
    y = 0
    for _, f in previa:
        f2 = f.resize((f.width * 2, f.height * 2), Image.NEAREST)
        p.paste(f2, (0, y), f2)
        y += f2.height + 6
    destino = os.path.join(os.environ.get('TEMP', tempfile.gettempdir()), 'NecoBuild', 'neco-previa.png')
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    p.save(destino)
    p2 = Image.new('RGBA', (300, 80), (30, 31, 34, 255))
    for i, s in enumerate((16, 32, 48)):
        p2.paste(grande.resize((s, s), Image.LANCZOS), (10 + i * 70, 10), grande.resize((s, s), Image.LANCZOS))
    p2.paste(grande.resize((64, 64), Image.NEAREST), (220, 8))
    p2.save(destino.replace('.png', '-icone.png'))
    print('prévia', destino)


if __name__ == '__main__':
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    sys.exit(main())
