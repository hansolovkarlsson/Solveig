#!/usr/bin/env python3
"""Write selectors.json from the references and lib/*.sol, or check it.

    python3 editors/vscode/messages.py            # rewrite selectors.json
    python3 editors/vscode/messages.py --check    # exit 1 if it would change

The list is the reference's Message index, which the build holds to
builtins.c; the per-type tables give each message its signature and what it
answers. A library adds the selectors it binds with :=, less any that its
object's exports list leaves out. Parasol's reference gives its header
directives and the five hole kinds. Nothing here is typed in by hand, so the
completion list cannot drift from the documents without this check saying so.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(HERE, 'selectors.json')

TYPES = ['integer', 'float', 'string', 'array', 'symbol', 'boolean', 'dictionary',
         'time', 'block', 'object', 'system', 'random', 'nil']
ID = r'[A-Za-z_][A-Za-z0-9_]*'
BORROWS = {'float': 'integer'}      # "Everything integer has, minus ..., plus:"

def anchor(heading):
    return re.sub(r'[^a-z0-9 -]', '', heading.lower()).replace(' ', '-')

def plain(md):
    """Markdown to the text a completion detail can show."""
    md = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', md)
    return md.strip()

def reference():
    text = open(os.path.join(ROOT, 'docs', 'REFERENCE.md'), encoding='utf-8').read()
    lines = text.split('\n')
    heading, rows, index = '', [], {}
    in_index = False
    for line in lines:
        if line.startswith('#'):
            heading = line.lstrip('#').strip()
            in_index = heading == 'Message index'
            continue
        if not line.startswith('| `'):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if len(cells) < 2:
            continue
        if in_index:
            name = cells[0].strip('`')
            index[name] = re.findall(r'\]\(#([a-z0-9-]+)\)', cells[1])
        else:
            for sig in re.findall(r'`([^`]*)`', cells[0]):
                sig = re.sub(r'^' + ID + ':', '', sig)          # float:atan2(y, x) is class-side
                m = re.match(r'(' + ID + r')(\(.*\))?$', sig)
                if m:
                    rows.append((anchor(heading), m.group(1), sig, plain(cells[1])))
    return index, rows

def first_sentence(text):
    text = re.sub(r'\s+', ' ', text).strip()
    m = re.match(r'(.*?[.!?])(?:\s|$)', text)
    text = m.group(1) if m else text
    return text.split(' -- ')[0].rstrip('.').strip()

def summary_for(lines, i, name):
    """The one line a library says about a definition at lines[i], if it says one.

    The comment block directly above is read as paragraphs. A `name -- summary`
    header line wins; then the paragraph that opens by naming the selector;
    then the last paragraph that is prose rather than a title, since a block
    that opens with a title puts the sentence about the code nearest to it. Failing a block, any comment in the
    file that opens with the name."""
    block = []
    j = i - 1
    while j >= 0 and (lines[j].startswith(';') or not lines[j].strip()):
        if lines[j].startswith(';'):
            if lines[j].strip(' ;-') and not lines[j].startswith('; -'):   # a rule is not a sentence
                block.insert(0, lines[j][1:].strip())
            else:
                block.insert(0, '')
        elif block:
            break
        j -= 1
    paragraphs = [p.strip() for p in '\n'.join(block).split('\n\n') if p.strip()]
    for p in paragraphs:
        h = re.match(r'(' + ID + r'(?:, ' + ID + r')*) -- (.*)$', p.split('\n')[0])
        if h and name in h.group(1).split(', '):
            return h.group(2).strip()
    for p in paragraphs:
        if re.match(r'`' + name + r'`', p.strip()):
            return first_sentence(p)
    prose = [p for p in paragraphs if '\n' in p or len(p.split()) > 4 or p.rstrip().endswith('.')]
    if prose:
        return first_sentence(prose[-1])
    for line in lines:
        if line.startswith('; `' + name + '`'):
            return first_sentence(line[1:].strip())
    return ''

def library():
    """Selectors a shipped library binds, less what its object's exports leave out."""
    out = []
    for path in sorted(os.listdir(os.path.join(ROOT, 'lib'))):
        if not path.endswith('.sol'):
            continue
        lines = open(os.path.join(ROOT, 'lib', path), encoding='utf-8').read().split('\n')
        text = '\n'.join(lines)
        exports = {}
        for m in re.finditer(r'^(' + ID + r'):exports\(\[([^\]]*)\]', text, re.M):
            exports[m.group(1)] = set(re.findall(r"'(" + ID + ')', m.group(2)))
        for i, line in enumerate(lines):
            m = re.match(r'^(' + ID + r'):(' + ID + r')\s*:=\s*\{\s*(?:(' + ID + r'(?:\s*,\s*' + ID + r')*)\s*\|(?!\|))?', line)
            if not m:
                continue
            recv, name, params = m.group(1), m.group(2), m.group(3)
            if recv in exports and name not in exports[recv]:
                continue
            sig = name + ('(' + re.sub(r'\s*,\s*', ', ', params) + ')' if params else '')
            out.append((recv, name, sig, summary_for(lines, i, name), 'lib/' + path))
    return out

def parasol():
    """The header directives and hole kinds, from the two tables that list them."""
    text = open(os.path.join(ROOT, 'parasol', 'docs', 'REFERENCE.md'), encoding='utf-8').read()
    heading, directives, kinds = '', [], []
    for line in text.split('\n'):
        if line.startswith('#'):
            heading = line.lstrip('#').strip(); continue
        if not line.startswith('| `'):
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        form = cells[0].strip('`')
        if heading == 'The header' and form.startswith('@'):
            directives.append({'form': form, 'meaning': plain(cells[1])})
        elif heading == 'What a hole accepts':
            kinds.append({'kind': form, 'meaning': plain(cells[1])})
    return directives, kinds

def build():
    index, rows = reference()
    by = {}
    def entry(name):
        return by.setdefault(name, {'name': name, 'signatures': []})
    for name, anchors in sorted(index.items()):
        e = entry(name)
        for a in anchors:
            here = [r for r in rows if r[0] == a and r[1] == name]
            if not here:
                # No row in that type's own table. "Every type" is prose, so
                # its messages are described wherever a table has them; float
                # says "everything integer has", and takes integer's row
                # under its own name, marked as borrowed.
                found = [r for r in rows if r[1] == name and r[0] == BORROWS.get(a, r[0])]
                if a == 'every-type':
                    here = [(r[0], name, r[2], r[3]) for r in found]
                else:
                    here = [(a, name, r[2], 'as ' + r[0].replace('-', ' ')) for r in found]
            if not here:
                here = [(a, name, name, '')]
            for where, _, sig, answers in here:
                e['signatures'].append({'receiver': where.replace('-', ' '), 'signature': sig,
                                        'answers': answers, 'source': 'REFERENCE.md#' + where})
    for recv, name, sig, summary, source in library():
        entry(name)['signatures'].append({'receiver': recv, 'signature': sig,
                                          'answers': summary, 'source': source})
    for e in by.values():
        seen, uniq = set(), []
        for s in e['signatures']:
            key = (s['receiver'], s['signature'])
            if key not in seen:
                seen.add(key); uniq.append(s)
        e['signatures'] = uniq
    directives, kinds = parasol()
    return {'generated': 'by editors/vscode/messages.py from docs/REFERENCE.md, lib/*.sol and parasol/docs/REFERENCE.md; do not edit',
            'types': TYPES,
            'selectors': [by[k] for k in sorted(by)],
            'directives': directives,
            'holeKinds': kinds}

if __name__ == '__main__':
    data = json.dumps(build(), indent=1, ensure_ascii=False) + '\n'
    if '--check' in sys.argv:
        current = open(OUT, encoding='utf-8').read() if os.path.exists(OUT) else ''
        if current != data:
            print('selectors.json is behind the documents: run editors/vscode/messages.py')
            sys.exit(1)
        print('selectors.json is current')
    else:
        open(OUT, 'w', encoding='utf-8').write(data)
        d = json.loads(data)
        print(f"{len(d['selectors'])} selectors, {len(d['directives'])} directive forms and "
              f"{len(d['holeKinds'])} hole kinds written to {os.path.relpath(OUT, ROOT)}")
