"""Troca só o recurso de versão (VERSIONINFO) de um .res, mantendo o resto (ícone, manifesto).

  python -I versao_res.py <res_com_a_versao_nova> <res_do_projeto>

O msbuild (/t:BuildVersionResource) gera um .res com a versão do .dproj, mas sem o ícone.
O exe usa o NecoBrowser.res (o da IDE): este script copia o bloco de versão de um para o outro.
"""
import struct
import sys

RT_VERSION = 16


def ler_nome(b, o):
    if struct.unpack_from('<H', b, o)[0] == 0xFFFF:
        return struct.unpack_from('<H', b, o + 2)[0], o + 4
    s = ''
    while True:
        c = struct.unpack_from('<H', b, o)[0]
        o += 2
        if c == 0:
            return s, o
        s += chr(c)


def entradas(b):
    """Lista de (tipo, bytes da entrada inteira, com alinhamento)."""
    o, res = 0, []
    while o + 8 <= len(b):
        tam_dados, tam_cab = struct.unpack_from('<II', b, o)
        tipo, _ = ler_nome(b, o + 8)
        fim = (o + tam_cab + tam_dados + 3) & ~3
        res.append((tipo, b[o:fim]))
        o = fim
    return res


def main():
    nova, alvo = sys.argv[1], sys.argv[2]
    ver = [e for t, e in entradas(open(nova, 'rb').read()) if t == RT_VERSION]
    if len(ver) != 1:
        sys.exit('ERRO: %s sem recurso de versão' % nova)
    atuais = entradas(open(alvo, 'rb').read())
    if sum(1 for t, _ in atuais if t == RT_VERSION) > 1:
        sys.exit('ERRO: %s tem mais de um recurso de versão' % alvo)
    saida, trocou = [], False
    for t, e in atuais:
        if t == RT_VERSION:
            saida.append(ver[0])
            trocou = True
        else:
            saida.append(e)
    if not trocou:
        # Sem versão ainda: entra logo depois da entrada vazia inicial do .res.
        saida.insert(1 if atuais else 0, ver[0])
    open(alvo, 'wb').write(b''.join(saida))
    print('versão trocada em %s (%d recursos)' % (alvo, len(saida)))


if __name__ == '__main__':
    main()
