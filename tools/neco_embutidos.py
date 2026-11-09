"""Gera os recursos que deixam o NecoBrowser rodar só com o exe (sem arquivos ao lado).

    python -I tools/neco_embutidos.py            (rodar da raiz do projeto)

Gera
  src/engine/NecoLoader32.res   RCDATA NECO_WV2LOADER = redist/Win32/WebView2Loader.dll
  src/engine/NecoLoader64.res   RCDATA NECO_WV2LOADER = redist/Win64/WebView2Loader.dll
  src/ui/NecoData.res           RCDATA NECO_BLOCKLIST = data/blocklist-hosts.txt (zlib)

O exe usa o arquivo ao lado dele quando existe e serve (assim dá para atualizar a lista
sem recompilar); senão, usa o embutido. Rode de novo depois de trocar a DLL ou a lista.
"""
import os
import struct
import sys
import zlib


def entrada_res(nome, dados, tipo=10):
    """Uma entrada de .res (formato Win32). tipo 10 = RT_RCDATA; nome em texto."""
    def ident(v):
        if isinstance(v, int):
            return struct.pack('<HH', 0xFFFF, v)
        return (v.upper() + '\0').encode('utf-16-le')
    cab = ident(tipo) + ident(nome)
    if len(cab) % 4:
        cab += b'\0' * (4 - len(cab) % 4)
    cab += struct.pack('<IHHII', 0, 0x0030, 0x0416, 0, 0)
    cab = struct.pack('<II', len(dados), 8 + len(cab)) + cab
    return cab + dados + b'\0' * ((4 - len(dados) % 4) % 4)


def gravar(caminho, entradas):
    vazio = b'\0\0\0\0\x20\0\0\0\xff\xff\0\0\xff\xff\0\0' + b'\0' * 16
    with open(caminho, 'wb') as f:
        f.write(vazio + b''.join(entrada_res(n, d) for n, d in entradas))
    print('gravado', caminho, os.path.getsize(caminho), 'bytes')


def main():
    for bits in ('32', '64'):
        dll = open(os.path.join('redist', 'Win' + bits, 'WebView2Loader.dll'), 'rb').read()
        # Confere a arquitetura pelo cabeçalho PE (0x14C = x86, 0x8664 = x64).
        pe = struct.unpack_from('<I', dll, 0x3C)[0]
        maquina = struct.unpack_from('<H', dll, pe + 4)[0]
        esperado = 0x14C if bits == '32' else 0x8664
        if maquina != esperado:
            sys.exit('redist/Win%s/WebView2Loader.dll é da arquitetura errada (0x%X)' % (bits, maquina))
        gravar(os.path.join('src', 'engine', 'NecoLoader%s.res' % bits), [('NECO_WV2LOADER', dll)])
    lista = open(os.path.join('data', 'blocklist-hosts.txt'), 'rb').read()
    comp = zlib.compress(lista, 9)
    print('lista: %d -> %d bytes' % (len(lista), len(comp)))
    gravar(os.path.join('src', 'ui', 'NecoData.res'), [('NECO_BLOCKLIST', comp)])


if __name__ == '__main__':
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    main()
