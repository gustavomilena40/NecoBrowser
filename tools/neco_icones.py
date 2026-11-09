"""Gera as constantes de ícone do NecoBrowser com o conversor da skill delphi-fmx-visual,
sem alterar o icones.py compartilhado (os SVGs novos entram só em memória)."""
import contextlib
import io
import sys

SKILL = r'C:\Users\user02\.agent-bridge\skills\delphi-fmx-visual'
sys.path.insert(0, SKILL)
with contextlib.redirect_stdout(io.StringIO()):
    import icones  # noqa: E402
    import icone_pas  # noqa: E402

NOVOS = {
    'recarregar': ['M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8', 'M21 3v5h-5'],
    'escudo': ['M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z'],
    'escudo_off': ['m2 2 20 20', 'M5 5a1 1 0 0 0-1 1v7c0 5 3.5 7.5 7.67 8.94a1 1 0 0 0 .67.01c2.35-.82 4.48-1.97 5.9-3.71',
                   'M9.309 3.652A12.252 12.252 0 0 0 11.24 2.28a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1v7a9.784 9.784 0 0 1-.08 1.264'],
    'estrela': ['M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638a2.123 2.123 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56l-4.618-2.428a2.122 2.122 0 0 0-1.973 0L6.396 21.01a.53.53 0 0 1-.77-.56l.881-5.139a2.122 2.122 0 0 0-.611-1.879L2.16 9.795a.53.53 0 0 1 .294-.906l5.165-.755a2.122 2.122 0 0 0 1.597-1.16z'],
    'baixar': ['M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4', 'M7 10l5 5 5-5', 'M12 15V3'],
    'marcador': ['m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z'],
    'sol': [('circle', 12, 12, 4), 'M12 2v2', 'M12 20v2', 'm4.93 4.93 1.41 1.41', 'm17.66 17.66 1.41 1.41',
            'M2 12h2', 'M20 12h2', 'm6.34 17.66-1.41 1.41', 'm19.07 4.93-1.41 1.41'],
    'lua': ['M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z'],
    'globo': [('circle', 12, 12, 10), 'M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20', 'M2 12h20'],
    'pasta': ['M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z'],
}
icones.ICONES.update(NOVOS)

NOMES = ['voltar', 'seta', 'recarregar', 'fechar', 'mais', 'cadeado', 'globo', 'escudo', 'escudo_off',
         'estrela', 'baixar', 'marcador', 'sol', 'lua', 'pasta', 'lixeira']
for nome in NOMES:
    t = icone_pas.texto(nome)
    pedacos = [t[j:j + 90] for j in range(0, len(t), 90)]
    print('  ICO_%s =' % nome.upper())
    print(' +\r\n'.join("    '%s'" % p for p in pedacos) + ';')
