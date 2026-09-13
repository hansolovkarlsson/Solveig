#!/usr/bin/env python3
"""Run the grammar over every .sol file in the repository and over a fixture.

A TextMate engine small enough to read: match, begin/end, include, captures
with patterns. It is not vscode-textmate, so a difference between the two is
possible, but Oniguruma and Python's re agree on everything this grammar
writes. Two checks: every file leaves the bracket stack empty and produces no
invalid.illegal token outside conformance/refused/, and each fixture line
tokenises exactly as written.

    python3 editors/vscode/test.py
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
GRAMMAR = json.load(open(os.path.join(HERE, 'syntaxes', 'solveig.tmLanguage.json')))
REPO = GRAMMAR['repository']

def rules(patterns):
    """Flatten includes into a list of rule dicts."""
    out = []
    for p in patterns:
        if 'include' not in p:
            out.append(p); continue
        r = REPO[p['include'][1:]]
        if 'match' in r or 'begin' in r:
            out.append(r)
        else:
            out.extend(rules(r['patterns']))
    return out

_cache = {}
def rx(src):
    if src not in _cache:
        _cache[src] = re.compile(src)
    return _cache[src]

def capture_tokens(m, captures, scopes):
    """Tokens for a match, honouring captures and their nested patterns."""
    toks, pos = [], m.start()
    for k in sorted(captures, key=int):
        i = int(k)
        if i > m.re.groups or m.start(i) < pos or m.start(i) == m.end(i):
            continue                      # absent, empty, or inside an earlier capture
        s, e, cap = m.start(i), m.end(i), captures[k]
        if s > pos:
            toks.append((pos, s, scopes))
        inner = scopes + ([cap['name']] if 'name' in cap else [])
        if 'patterns' in cap:
            toks.extend(tokenise_span(m.string, s, e, inner, rules(cap['patterns'])))
        else:
            toks.append((s, e, inner))
        pos = e
    if pos < m.end():
        toks.append((pos, m.end(), scopes))
    return toks

def tokenise_span(text, pos, end, scopes, rs):
    """Match-only rules over text[pos:end], as a capture's patterns are."""
    toks = []
    while pos < end:
        best = None
        for r in rs:
            m = rx(r['match']).search(text, pos, end)
            if m and m.start() < m.end() and (best is None or m.start() < best[0].start()):
                best = (m, r)
        if best is None:
            toks.append((pos, end, scopes)); break
        m, r = best
        if m.start() > pos:
            toks.append((pos, m.start(), scopes))
        toks.extend(capture_tokens(m, r.get('captures', {}), scopes + ([r['name']] if 'name' in r else [])))
        pos = m.end()
    return toks

def tokenise(text):
    """Yield (line_no, start, end, scopes) over the whole text; return the stack depth left."""
    stack = [(None, ['source.solveig'], rules(GRAMMAR['patterns']), {})]
    for ln, line in enumerate(text.split('\n'), 1):
        pos = 0
        while True:
            end_rx, scopes, rs, end_caps = stack[-1]
            best = None                      # (start, m, kind, rule); the end pattern wins a tie
            if end_rx is not None:
                m = end_rx.search(line, pos)
                if m: best = (m.start(), m, 'end', None)
            for r in rs:
                m = rx(r['begin'] if 'begin' in r else r['match']).search(line, pos)
                if m and m.start() < m.end() and (best is None or m.start() < best[0]):
                    best = (m.start(), m, 'begin' if 'begin' in r else 'match', r)
            if best is None:
                if pos < len(line): yield (ln, pos, len(line), scopes)
                break
            _, m, kind, r = best
            if m.start() > pos: yield (ln, pos, m.start(), scopes)
            if kind == 'end':
                for t in capture_tokens(m, end_caps, scopes): yield (ln,) + t
                stack.pop()
            elif kind == 'match':
                for t in capture_tokens(m, r.get('captures', {}), scopes + ([r['name']] if 'name' in r else [])): yield (ln,) + t
            else:
                inner = scopes + ([r['name']] if 'name' in r else [])
                for t in capture_tokens(m, r.get('beginCaptures', {}), inner): yield (ln,) + t
                stack.append((rx(r['end']), inner, rules(r.get('patterns', [])), r.get('endCaptures', {})))
            pos = m.end()
            if pos >= len(line) and not (kind == 'end' and m.start() == m.end()):
                # the line is spent, unless an empty end ($) is still to be matched here
                if not (stack[-1][0] is not None and stack[-1][0].pattern == '$'):
                    break
                if kind == 'end': break
    return len(stack)

def leaf(scopes):
    return scopes[-1]

# The fixture: each entry tokenised by hand from docs/GRAMMAR.md. A token is
# (text, leaf scope); whitespace-only tokens are dropped before comparing, and
# a bracket's inner whitespace is named by its meta scope.
FIXTURE = [
    ('a := [#10, #20, #30].', [
        ('a', 'entity.name.type.object.solveig'), (':=', 'keyword.operator.assignment.solveig'),
        ('[', 'punctuation.section.array.begin.solveig'), ('#10', 'constant.numeric.integer.solveig'),
        (',', 'punctuation.separator.comma.solveig'), ('#20', 'constant.numeric.integer.solveig'),
        (',', 'punctuation.separator.comma.solveig'), ('#30', 'constant.numeric.integer.solveig'),
        (']', 'punctuation.section.array.end.solveig'), ('.', 'punctuation.terminator.statement.solveig')]),
    ('a:at(#1):print.   ; #10 -- first', [
        ('a', 'entity.name.type.object.solveig'), (':', 'punctuation.separator.send.solveig'), ('at', 'entity.name.function.send.solveig'),
        ('(', 'punctuation.section.group.begin.solveig'), ('#1', 'constant.numeric.integer.solveig'), (')', 'punctuation.section.group.end.solveig'),
        (':', 'punctuation.separator.send.solveig'), ('print', 'entity.name.function.send.solveig'),
        ('.', 'punctuation.terminator.statement.solveig'),
        (';', 'punctuation.definition.comment.solveig'), ('#10 -- first', 'comment.line.semicolon.solveig')]),
    ('integer:upto := { | out, i |', [
        ('integer', 'entity.name.type.object.solveig'), (':', 'punctuation.separator.send.solveig'),
        ('upto', 'entity.name.function.definition.solveig'), (':=', 'keyword.operator.assignment.solveig'),
        ('{', 'punctuation.section.block.begin.solveig'), ('|', 'punctuation.separator.temporaries.solveig'),
        ('out', 'variable.other.temporary.solveig'), (',', 'meta.block.solveig'), ('i', 'variable.other.temporary.solveig'),
        ('|', 'punctuation.separator.temporaries.solveig')]),
    ('{ a | | t | t }', [
        ('{', 'punctuation.section.block.begin.solveig'), ('a', 'variable.parameter.solveig'),
        ('|', 'punctuation.separator.parameters.solveig'), ('|', 'punctuation.separator.temporaries.solveig'),
        ('t', 'variable.other.temporary.solveig'), ('|', 'punctuation.separator.temporaries.solveig'),
        ('t', 'entity.name.type.object.solveig'), ('}', 'punctuation.section.block.end.solveig')]),
    ('{ x:print }', [
        ('{', 'punctuation.section.block.begin.solveig'), ('x', 'entity.name.type.object.solveig'),
        (':', 'punctuation.separator.send.solveig'), ('print', 'entity.name.function.send.solveig'),
        ('}', 'punctuation.section.block.end.solveig')]),
    ('b:do({ e | sum := sum:add(e) }).', [
        ('b', 'entity.name.type.object.solveig'), (':', 'punctuation.separator.send.solveig'), ('do', 'entity.name.function.send.solveig'),
        ('(', 'punctuation.section.group.begin.solveig'), ('{', 'punctuation.section.block.begin.solveig'),
        ('e', 'variable.parameter.solveig'), ('|', 'punctuation.separator.parameters.solveig'),
        ('sum', 'entity.name.type.object.solveig'), (':=', 'keyword.operator.assignment.solveig'), ('sum', 'entity.name.type.object.solveig'),
        (':', 'punctuation.separator.send.solveig'), ('add', 'entity.name.function.send.solveig'),
        ('(', 'punctuation.section.group.begin.solveig'), ('e', 'entity.name.type.object.solveig'), (')', 'punctuation.section.group.end.solveig'),
        ('}', 'punctuation.section.block.end.solveig'), (')', 'punctuation.section.group.end.solveig'),
        ('.', 'punctuation.terminator.statement.solveig')]),
    ('@expr(a | b | c).', [
        ('@expr', 'keyword.control.directive.expr.solveig'), ('(', 'punctuation.section.group.begin.solveig'),
        ('a', 'entity.name.type.object.solveig'), ('|', 'keyword.operator.solveig'), ('b', 'entity.name.type.object.solveig'),
        ('|', 'keyword.operator.solveig'), ('c', 'entity.name.type.object.solveig'), (')', 'punctuation.section.group.end.solveig'),
        ('.', 'punctuation.terminator.statement.solveig')]),
    ('@expr{ a | a^2 + 3*(sin(a/2) + sqrt(b)) }', [
        ('@expr', 'keyword.control.directive.expr.solveig'), ('{', 'punctuation.section.block.begin.solveig'),
        ('a', 'variable.parameter.solveig'), ('|', 'punctuation.separator.parameters.solveig'),
        ('a', 'entity.name.type.object.solveig'), ('^', 'keyword.operator.solveig'), ('2', 'constant.numeric.float.solveig'),
        ('+', 'keyword.operator.solveig'), ('3', 'constant.numeric.float.solveig'), ('*', 'keyword.operator.solveig'),
        ('(', 'punctuation.section.group.begin.solveig'), ('sin', 'entity.name.function.call.solveig'),
        ('(', 'punctuation.section.group.begin.solveig'), ('a', 'entity.name.type.object.solveig'), ('/', 'keyword.operator.solveig'),
        ('2', 'constant.numeric.float.solveig'), (')', 'punctuation.section.group.end.solveig'), ('+', 'keyword.operator.solveig'),
        ('sqrt', 'entity.name.function.call.solveig'), ('(', 'punctuation.section.group.begin.solveig'),
        ('b', 'entity.name.type.object.solveig'), (')', 'punctuation.section.group.end.solveig'), (')', 'punctuation.section.group.end.solveig'),
        ('}', 'punctuation.section.block.end.solveig')]),
    ('@expr(-2^2 <> -3.5e-1 & ~x >= $FF08)', [
        ('@expr', 'keyword.control.directive.expr.solveig'), ('(', 'punctuation.section.group.begin.solveig'),
        ('-', 'keyword.operator.solveig'), ('2', 'constant.numeric.float.solveig'), ('^', 'keyword.operator.solveig'),
        ('2', 'constant.numeric.float.solveig'), ('<>', 'keyword.operator.solveig'), ('-', 'keyword.operator.solveig'),
        ('3.5e-1', 'constant.numeric.float.solveig'), ('&', 'keyword.operator.solveig'), ('~', 'keyword.operator.solveig'),
        ('x', 'entity.name.type.object.solveig'), ('>=', 'keyword.operator.solveig'), ('$FF08', 'constant.numeric.hex.solveig'),
        (')', 'punctuation.section.group.end.solveig')]),
    ('sizes := #["small" = #1, "large" = n:mul(#2)].', [
        ('sizes', 'entity.name.type.object.solveig'), (':=', 'keyword.operator.assignment.solveig'),
        ('#[', 'punctuation.section.dictionary.begin.solveig'), ('"', 'punctuation.definition.string.begin.solveig'),
        ('small', 'string.quoted.double.solveig'), ('"', 'punctuation.definition.string.end.solveig'),
        ('=', 'keyword.operator.pair.solveig'), ('#1', 'constant.numeric.integer.solveig'), (',', 'punctuation.separator.comma.solveig'),
        ('"', 'punctuation.definition.string.begin.solveig'), ('large', 'string.quoted.double.solveig'), ('"', 'punctuation.definition.string.end.solveig'),
        ('=', 'keyword.operator.pair.solveig'), ('n', 'entity.name.type.object.solveig'), (':', 'punctuation.separator.send.solveig'),
        ('mul', 'entity.name.function.send.solveig'), ('(', 'punctuation.section.group.begin.solveig'),
        ('#2', 'constant.numeric.integer.solveig'), (')', 'punctuation.section.group.end.solveig'),
        (']', 'punctuation.section.dictionary.end.solveig'), ('.', 'punctuation.terminator.statement.solveig')]),
    ('"a\\tb\\q" \'sym %1010 45. x1 #-7 1.5', [
        ('"', 'punctuation.definition.string.begin.solveig'), ('a', 'string.quoted.double.solveig'),
        ('\\t', 'constant.character.escape.solveig'), ('b', 'string.quoted.double.solveig'),
        ('\\q', 'invalid.illegal.escape.solveig'), ('"', 'punctuation.definition.string.end.solveig'),
        ("'sym", 'constant.other.symbol.solveig'), ('%1010', 'constant.numeric.binary.solveig'),
        ('45', 'constant.numeric.float.solveig'), ('.', 'punctuation.terminator.statement.solveig'),
        ('x1', 'entity.name.type.object.solveig'), ('#-7', 'constant.numeric.integer.solveig'), ('1.5', 'constant.numeric.float.solveig')]),
    ('@include "shell.sol". @bogus self:x. nil', [
        ('@include', 'keyword.control.directive.include.solveig'), ('"', 'punctuation.definition.string.begin.solveig'),
        ('shell.sol', 'string.quoted.double.solveig'), ('"', 'punctuation.definition.string.end.solveig'),
        ('.', 'punctuation.terminator.statement.solveig'), ('@bogus', 'invalid.illegal.directive.solveig'),
        ('self', 'variable.language.self.solveig'), (':', 'punctuation.separator.send.solveig'), ('x', 'entity.name.function.send.solveig'),
        ('.', 'punctuation.terminator.statement.solveig'), ('nil', 'constant.language.solveig')]),
    ('item:make := { n, p, q |\n    | it |\n    it := self:new }', [
        ('item', 'entity.name.type.object.solveig'), (':', 'punctuation.separator.send.solveig'),
        ('make', 'entity.name.function.definition.solveig'), (':=', 'keyword.operator.assignment.solveig'),
        ('{', 'punctuation.section.block.begin.solveig'), ('n', 'variable.parameter.solveig'), (',', 'meta.block.solveig'),
        ('p', 'variable.parameter.solveig'), (',', 'meta.block.solveig'), ('q', 'variable.parameter.solveig'),
        ('|', 'punctuation.separator.parameters.solveig'),
        ('|', 'punctuation.separator.temporaries.solveig'), ('it', 'variable.other.temporary.solveig'),
        ('|', 'punctuation.separator.temporaries.solveig'),
        ('it', 'entity.name.type.object.solveig'), (':=', 'keyword.operator.assignment.solveig'), ('self', 'variable.language.self.solveig'),
        (':', 'punctuation.separator.send.solveig'), ('new', 'entity.name.function.send.solveig'),
        ('}', 'punctuation.section.block.end.solveig')]),
    ('@expr(a\n | b | c)', [
        ('@expr', 'keyword.control.directive.expr.solveig'), ('(', 'punctuation.section.group.begin.solveig'),
        ('a', 'entity.name.type.object.solveig'), ('|', 'keyword.operator.solveig'), ('b', 'entity.name.type.object.solveig'),
        ('|', 'keyword.operator.solveig'), ('c', 'entity.name.type.object.solveig'), (')', 'punctuation.section.group.end.solveig')]),
    ('( | a, b | a:print )', [
        ('(', 'punctuation.section.group.begin.solveig'), ('|', 'punctuation.separator.temporaries.solveig'),
        ('a', 'variable.other.temporary.solveig'), (',', 'meta.group.solveig'), ('b', 'variable.other.temporary.solveig'),
        ('|', 'punctuation.separator.temporaries.solveig'), ('a', 'entity.name.type.object.solveig'),
        (':', 'punctuation.separator.send.solveig'), ('print', 'entity.name.function.send.solveig'),
        (')', 'punctuation.section.group.end.solveig')]),
]

def run_fixture():
    bad = 0
    for line, want in FIXTURE:
        lines = line.split('\n')
        got = [(lines[ln - 1][s:e].strip(), leaf(sc)) for (ln, s, e, sc) in tokenise(line) if lines[ln - 1][s:e].strip()]
        if got != want:
            bad += 1
            print(f'FIXTURE  {line}')
            for g, w in zip(got + [None] * len(want), want + [None] * len(got)):
                if g != w: print(f'    got {g!r}\n   want {w!r}')
    return bad

def run_corpus():
    files = subprocess.run(['git', 'ls-files', '*.sol'], cwd=ROOT, capture_output=True, text=True).stdout.split()
    bad, counts = 0, {}
    for f in files:
        text = open(os.path.join(ROOT, f), encoding='utf-8', errors='replace').read()
        gen = tokenise(text)
        illegal = []
        try:
            while True:
                ln, s, e, sc = next(gen)
                counts[leaf(sc)] = counts.get(leaf(sc), 0) + 1
                if any(x.startswith('invalid.') for x in sc):
                    illegal.append((ln, sc[-1]))
        except StopIteration as stop:
            depth = stop.value
        if depth != 1:
            bad += 1; print(f'CORPUS   {f}: {depth - 1} bracket(s) left open at end of file')
        # conformance/refused/ holds files the compiler refuses, so an invalid
        # token there is the grammar agreeing with the compiler, and anywhere
        # else it is the grammar disagreeing with it.
        for ln, sc in illegal[:3]:
            if f.startswith('conformance/refused/'):
                print(f'refused  {f}:{ln}: {sc}')
            else:
                bad += 1; print(f'CORPUS   {f}:{ln}: {sc}')
    return bad, len(files), counts

if __name__ == '__main__':
    bad = run_fixture()
    cbad, n, counts = run_corpus()
    for k in sorted(counts): print(f'{counts[k]:8d}  {k}')
    print(f'{len(FIXTURE)} fixture lines, {n} files; {bad + cbad} problem(s)')
    sys.exit(1 if bad + cbad else 0)
