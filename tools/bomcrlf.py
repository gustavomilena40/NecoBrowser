"""Deixa cada arquivo em UTF-8 com BOM e CRLF, e confere.

  python -I bomcrlf.py <arquivo>...

Falha (exit 1) se o arquivo nao for UTF-8 valido ou tiver U+FFFD.
"""
import sys

BOM = b'\xef\xbb\xbf'
ok = True
for p in sys.argv[1:]:
    b = open(p, 'rb').read()
    if b.startswith(BOM):
        b = b[3:]
    try:
        t = b.decode('utf-8')
    except UnicodeDecodeError as e:
        print('NAO-UTF8', p, e)
        ok = False
        continue
    if '\ufffd' in t:
        print('U+FFFD', p)
        ok = False
        continue
    t = t.replace('\r\n', '\n').replace('\r', '\n').replace('\n', '\r\n')
    nb = BOM + t.encode('utf-8')
    if nb != open(p, 'rb').read():
        open(p, 'wb').write(nb)
    cr = nb.count(b'\r')
    lf = nb.count(b'\n')
    print('%-60s BOM=sim CR=%d LF=%d %s' % (p[-60:], cr, lf, 'ok' if cr == lf else 'MISTO'))
    ok = ok and cr == lf
sys.exit(0 if ok else 1)
