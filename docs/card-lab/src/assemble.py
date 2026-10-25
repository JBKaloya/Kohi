# Rebuilds ../kohi-card-lab.html from lab/*.js + lab/page.html and the marks in ../fixtures/marks.
#   python3 assemble.py
import base64, json, os
here = os.path.dirname(os.path.abspath(__file__))
marks_dir = os.path.join(here, '..', 'fixtures', 'marks')
marks = {}
for key, name in [('klover', 'klover'), ('angel', 'peru-angel'), ('panama', 'panama'), ('bottle', 'blue-bottle')]:
    with open(os.path.join(marks_dir, name + '.png'), 'rb') as f:
        marks[key] = 'data:image/png;base64,' + base64.b64encode(f.read()).decode()
js = '\n'.join(open(os.path.join(here, 'lab', f)).read() for f in ['data.js', 'engine.js', 'stickers.js', 'ui.js'])
page = open(os.path.join(here, 'lab', 'page.html')).read().replace('__MARKS__', json.dumps(marks)).replace('__SCRIPTS__', js)
out = os.path.join(here, '..', 'kohi-card-lab.html')
open(out, 'w').write(page)
print('wrote', os.path.normpath(out))
