#!/usr/bin/env python3
"""Check the grammar, the selector list and the completion logic.

The grammar: a TextMate engine small enough to read, match, begin/end,
include and captures with patterns, run over every .sol file in the
repository and over a fixture. It is not vscode-textmate, so a difference
between the two is possible, but Oniguruma and Python's re agree on
everything this grammar writes. Every file must leave the bracket stack empty
and produce no invalid.illegal token outside conformance/refused/, and each
fixture line must tokenise exactly as written.

The selector list: selectors.json must be what messages.py would write now.

The completion logic: completion.js is run under osascript, the JavaScript
engine every Mac has, against cases written from the reference. There is no
node here and none is needed.

    python3 editors/vscode/test.py
"""
import json, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
SOLVEIG = json.load(open(os.path.join(HERE, 'syntaxes', 'solveig.tmLanguage.json')))
PROTO = json.load(open(os.path.join(HERE, 'syntaxes', 'proto.tmLanguage.json')))

def rules(patterns, grammar):
    """Flatten includes into a list of rule dicts."""
    out = []
    for p in patterns:
        if 'include' not in p:
            out.append(p); continue
        r = grammar['repository'][p['include'][1:]]
        if 'match' in r or 'begin' in r:
            out.append(r)
        else:
            out.extend(rules(r['patterns'], grammar))
    return out

_cache = {}
def rx(src):
    if src not in _cache:
        _cache[src] = re.compile(src)
    return _cache[src]

def capture_tokens(m, captures, scopes, grammar):
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
            toks.extend(tokenise_span(m.string, s, e, inner, rules(cap['patterns'], grammar), grammar))
        else:
            toks.append((s, e, inner))
        pos = e
    if pos < m.end():
        toks.append((pos, m.end(), scopes))
    return toks

def tokenise_span(text, pos, end, scopes, rs, grammar):
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
        toks.extend(capture_tokens(m, r.get('captures', {}), scopes + ([r['name']] if 'name' in r else []), grammar))
        pos = m.end()
    return toks

def tokenise(text, grammar=SOLVEIG):
    """Yield (line_no, start, end, scopes) over the whole text; return the stack depth left."""
    stack = [(None, [grammar['scopeName']], rules(grammar['patterns'], grammar), {})]
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
                for t in capture_tokens(m, end_caps, scopes, grammar): yield (ln,) + t
                stack.pop()
            elif kind == 'match':
                for t in capture_tokens(m, r.get('captures', {}), scopes + ([r['name']] if 'name' in r else []), grammar): yield (ln,) + t
            else:
                inner = scopes + ([r['name']] if 'name' in r else [])
                for t in capture_tokens(m, r.get('beginCaptures', {}), inner, grammar): yield (ln,) + t
                stack.append((rx(r['end']), inner, rules(r.get('patterns', []), grammar), r.get('endCaptures', {})))
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

# Proto's tokens are Solveig's with operators everywhere, and the directives
# have parts: docs at proto/docs/REFERENCE.md, "The header" and "Tokens".
P = 'proto'
PROTO_FIXTURE = [
    ('@use "../lib/clike.pro".', [
        ('@use', 'keyword.control.directive.use.proto'), ('"', 'punctuation.definition.string.begin.proto'),
        ('../lib/clike.pro', 'string.quoted.double.proto'), ('"', 'punctuation.definition.string.end.proto'),
        ('.', 'punctuation.terminator.statement.proto')]),
    ('@infix  +   60 add.', [
        ('@infix', 'keyword.control.directive.proto'), ('+', 'keyword.operator.declared.proto'),
        ('60', 'constant.numeric.precedence.proto'), ('add', 'entity.name.function.send.proto'),
        ('.', 'punctuation.terminator.statement.proto')]),
    ('@infixr ^ 80 pow.', [
        ('@infixr', 'keyword.control.directive.proto'), ('^', 'keyword.operator.declared.proto'),
        ('80', 'constant.numeric.precedence.proto'), ('pow', 'entity.name.function.send.proto'),
        ('.', 'punctuation.terminator.statement.proto')]),
    ('@infix  &&  30 => left:and({ right }).', [
        ('@infix', 'keyword.control.directive.proto'), ('&&', 'keyword.operator.declared.proto'),
        ('30', 'constant.numeric.precedence.proto'), ('=>', 'keyword.operator.template.proto'),
        ('left', 'variable.parameter.operand.proto'), (':', 'punctuation.separator.send.proto'),
        ('and', 'entity.name.function.send.proto'), ('(', 'punctuation.section.group.begin.proto'),
        ('{', 'punctuation.section.block.begin.proto'), ('right', 'variable.parameter.operand.proto'),
        ('}', 'punctuation.section.block.end.proto'), (')', 'punctuation.section.group.end.proto'),
        ('.', 'punctuation.terminator.statement.proto')]),
    ('@infix  |   50 bitOr. (a | b)', [
        ('@infix', 'keyword.control.directive.proto'), ('|', 'keyword.operator.declared.proto'),
        ('50', 'constant.numeric.precedence.proto'), ('bitOr', 'entity.name.function.send.proto'),
        ('.', 'punctuation.terminator.statement.proto'), ('(', 'punctuation.section.group.begin.proto'),
        ('a', 'entity.name.type.object.proto'), ('|', 'keyword.operator.proto'), ('b', 'entity.name.type.object.proto'),
        (')', 'punctuation.section.group.end.proto')]),
    ('@prefix !      not.', [
        ('@prefix', 'keyword.control.directive.proto'), ('!', 'keyword.operator.declared.proto'),
        ('not', 'entity.name.function.send.proto'), ('.', 'punctuation.terminator.statement.proto')]),
    ('@prefix - => #0:sub(operand).', [
        ('@prefix', 'keyword.control.directive.proto'), ('-', 'keyword.operator.declared.proto'),
        ('=>', 'keyword.operator.template.proto'), ('#0', 'constant.numeric.integer.proto'),
        (':', 'punctuation.separator.send.proto'), ('sub', 'entity.name.function.send.proto'),
        ('(', 'punctuation.section.group.begin.proto'), ('operand', 'variable.parameter.operand.proto'),
        (')', 'punctuation.section.group.end.proto'), ('.', 'punctuation.terminator.statement.proto')]),
    ('@syntax do <b: block> while <c>      => (b:value. { c }:whileTrue(b)).', [
        ('@syntax', 'keyword.control.directive.proto'), ('do', 'entity.name.function.syntax.proto'),
        ('<', 'punctuation.definition.hole.begin.proto'), ('b', 'variable.parameter.hole.proto'),
        (':', 'punctuation.separator.kind.proto'), ('block', 'storage.type.kind.proto'), ('>', 'punctuation.definition.hole.end.proto'),
        ('while', 'keyword.control.syntax-word.proto'),
        ('<', 'punctuation.definition.hole.begin.proto'), ('c', 'variable.parameter.hole.proto'), ('>', 'punctuation.definition.hole.end.proto'),
        ('=>', 'keyword.operator.template.proto'), ('(', 'punctuation.section.group.begin.proto'),
        ('b', 'entity.name.type.object.proto'), (':', 'punctuation.separator.send.proto'), ('value', 'entity.name.function.send.proto'),
        ('.', 'punctuation.terminator.statement.proto'), ('{', 'punctuation.section.block.begin.proto'),
        ('c', 'entity.name.type.object.proto'), ('}', 'punctuation.section.block.end.proto'),
        (':', 'punctuation.separator.send.proto'), ('whileTrue', 'entity.name.function.send.proto'),
        ('(', 'punctuation.section.group.begin.proto'), ('b', 'entity.name.type.object.proto'), (')', 'punctuation.section.group.end.proto'),
        (')', 'punctuation.section.group.end.proto'), ('.', 'punctuation.terminator.statement.proto')]),
    ('@syntax swap(a, b) => { | t | t := a. a := b. b := t }:value.', [
        ('@syntax', 'keyword.control.directive.proto'), ('swap', 'entity.name.function.syntax.proto'),
        ('(', 'punctuation.section.parameters.begin.proto'), ('a', 'variable.parameter.proto'), (',', 'punctuation.separator.comma.proto'),
        ('b', 'variable.parameter.proto'), (')', 'punctuation.section.parameters.end.proto'),
        ('=>', 'keyword.operator.template.proto'), ('{', 'punctuation.section.block.begin.proto'),
        ('|', 'punctuation.separator.temporaries.proto'), ('t', 'variable.other.temporary.proto'), ('|', 'punctuation.separator.temporaries.proto'),
        ('t', 'entity.name.type.object.proto'), (':=', 'keyword.operator.assignment.proto'), ('a', 'entity.name.type.object.proto'),
        ('.', 'punctuation.terminator.statement.proto'), ('a', 'entity.name.type.object.proto'), (':=', 'keyword.operator.assignment.proto'),
        ('b', 'entity.name.type.object.proto'), ('.', 'punctuation.terminator.statement.proto'), ('b', 'entity.name.type.object.proto'),
        (':=', 'keyword.operator.assignment.proto'), ('t', 'entity.name.type.object.proto'), ('}', 'punctuation.section.block.end.proto'),
        (':', 'punctuation.separator.send.proto'), ('value', 'entity.name.function.send.proto'), ('.', 'punctuation.terminator.statement.proto')]),
    ('@syntax if <c> <t: thing> => c.', [
        ('@syntax', 'keyword.control.directive.proto'), ('if', 'entity.name.function.syntax.proto'),
        ('<', 'punctuation.definition.hole.begin.proto'), ('c', 'variable.parameter.hole.proto'), ('>', 'punctuation.definition.hole.end.proto'),
        ('<', 'punctuation.definition.hole.begin.proto'), ('t', 'variable.parameter.hole.proto'), (':', 'punctuation.separator.kind.proto'),
        ('thing', 'invalid.illegal.kind.proto'), ('>', 'punctuation.definition.hole.end.proto'),
        ('=>', 'keyword.operator.template.proto'), ('c', 'entity.name.type.object.proto'), ('.', 'punctuation.terminator.statement.proto')]),
    ('while (n < #20 && a<=b || -3.5 % 2 != %101) { n = n + #1 }.', [
        ('while', 'entity.name.function.call.proto'), ('(', 'punctuation.section.group.begin.proto'),
        ('n', 'entity.name.type.object.proto'), ('<', 'keyword.operator.proto'), ('#20', 'constant.numeric.integer.proto'),
        ('&&', 'keyword.operator.proto'), ('a', 'entity.name.type.object.proto'), ('<=', 'keyword.operator.proto'),
        ('b', 'entity.name.type.object.proto'), ('||', 'keyword.operator.proto'), ('-', 'keyword.operator.proto'),
        ('3.5', 'constant.numeric.float.proto'), ('%', 'keyword.operator.proto'), ('2', 'constant.numeric.float.proto'),
        ('!=', 'keyword.operator.proto'), ('%101', 'constant.numeric.binary.proto'), (')', 'punctuation.section.group.end.proto'),
        ('{', 'punctuation.section.block.begin.proto'), ('n', 'entity.name.type.object.proto'), ('=', 'keyword.operator.proto'),
        ('n', 'entity.name.type.object.proto'), ('+', 'keyword.operator.proto'), ('#1', 'constant.numeric.integer.proto'),
        ('}', 'punctuation.section.block.end.proto'), ('.', 'punctuation.terminator.statement.proto')]),
    ('@expr(a). @nosuch. @include "x.sol". swap(a, b). x := #[a = #1].', [
        ('@expr', 'invalid.illegal.directive.refused.proto'), ('(', 'punctuation.section.group.begin.proto'),
        ('a', 'entity.name.type.object.proto'), (')', 'punctuation.section.group.end.proto'), ('.', 'punctuation.terminator.statement.proto'),
        ('@nosuch', 'invalid.illegal.directive.proto'), ('.', 'punctuation.terminator.statement.proto'),
        ('@include', 'keyword.control.directive.include.proto'), ('"', 'punctuation.definition.string.begin.proto'),
        ('x.sol', 'string.quoted.double.proto'), ('"', 'punctuation.definition.string.end.proto'), ('.', 'punctuation.terminator.statement.proto'),
        ('swap', 'entity.name.function.call.proto'), ('(', 'punctuation.section.group.begin.proto'), ('a', 'entity.name.type.object.proto'),
        (',', 'punctuation.separator.comma.proto'), ('b', 'entity.name.type.object.proto'), (')', 'punctuation.section.group.end.proto'),
        ('.', 'punctuation.terminator.statement.proto'), ('x', 'entity.name.type.object.proto'), (':=', 'keyword.operator.assignment.proto'),
        ('#[', 'punctuation.section.dictionary.begin.proto'), ('a', 'entity.name.type.object.proto'), ('=', 'keyword.operator.pair.proto'),
        ('#1', 'constant.numeric.integer.proto'), (']', 'punctuation.section.dictionary.end.proto'), ('.', 'punctuation.terminator.statement.proto')]),
]

def run_fixture(fixture, grammar):
    bad = 0
    for line, want in fixture:
        lines = line.split('\n')
        got = [(lines[ln - 1][s:e].strip(), leaf(sc)) for (ln, s, e, sc) in tokenise(line, grammar) if lines[ln - 1][s:e].strip()]
        if got != want:
            bad += 1
            print(f'FIXTURE  {line}')
            for g, w in zip(got + [None] * len(want), want + [None] * len(got)):
                if g != w: print(f'    got {g!r}\n   want {w!r}')
    return bad

def run_corpus(glob, grammar):
    files = subprocess.run(['git', 'ls-files', glob], cwd=ROOT, capture_output=True, text=True).stdout.split()
    bad, counts = 0, {}
    for f in files:
        text = open(os.path.join(ROOT, f), encoding='utf-8', errors='replace').read()
        gen = tokenise(text, grammar)
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

def run_messages():
    r = subprocess.run([sys.executable, os.path.join(HERE, 'messages.py'), '--check'], capture_output=True, text=True)
    if r.returncode:
        print('MESSAGES ' + r.stdout.strip())
    return 1 if r.returncode else 0

# The completion cases: what the cursor sees, and what the logic must answer.
JS_CASES = r"""
function ctx(before) { return C.context(before, data); }
function receivers(before) { var c = ctx(before); return c && c.receivers; }
function item(before, name) {
  var list = C.items(data, ctx(before));
  for (var i = 0; i < list.length; i++) if (list[i].label === name) return list[i];
  return null;
}
eq('not after a colon', ctx('a := b'), null);
eq('a binding is not a send', ctx('a :='), null);
eq('inside a comment', ctx('; a:'), null);
eq('inside a string', ctx('"a:'), null);
eq('after a colon', ctx('a:').partial, '');
eq('partial selector', ctx('a:pr').partial, 'pr');
eq('unknown receiver', receivers('a:'), []);
eq('a chain is unknown', receivers('a:size:'), []);
eq('self is unknown', receivers('self:'), []);
eq('tagged integer', receivers('#3:'), ['integer']);
eq('hex', receivers('x := $FF:'), ['integer']);
eq('binary', receivers('%101:'), ['integer']);
eq('float', receivers('1.5:'), ['float']);
eq('float, whole', receivers('45:'), ['float']);
eq('string', receivers('"a":'), ['string']);
eq('string, closed after a colon', receivers('"a:b":'), ['string']);
eq('symbol', receivers("'s:"), ['symbol']);
eq('array or dictionary', receivers('[#1]:'), ['array', 'dictionary']);
eq('block', receivers('{ x | x }:'), ['block']);
eq('prototype by name', receivers('integer:'), ['integer']);
eq('boolean by name', receivers('true:'), ['boolean']);
eq('library object', receivers('re:'), ['re']);
eq('system', receivers('system:'), ['system']);
eq('own receiver sorts first', item('#3:', 'add').sortText, '0add');
eq('other receiver sorts after', item('#3:', 'find').sortText, '1find');
eq('unknown receiver sorts all alike', item('a:', 'add').sortText, '1add');
eq('arguments become a snippet', item('#3:', 'add').insertText, 'add($1)');
eq('and are marked as one', item('#3:', 'add').snippet, true);
eq('no arguments, no snippet', item('a:', 'print').insertText, 'print');
eq('an optional argument is left out', item('a:', 'asString').insertText, 'asString');
eq('the detail names the receivers', item('a:', 'add').detail, 'array, float, integer');
eq('the documentation has one line per signature', item('a:', 'add').documentation.split('\n').length, 3);
eq('a library selector says where it lives', item('a:', 'timesCollect').documentation.indexOf('lib/control.sol') > 0, true);
eq('every selector is offered', C.items(data, ctx('a:')).length, data.selectors.length);
function pctx(before) { return C.context(before, data, 'proto'); }
function pitem(before, name) {
  var list = C.items(data, pctx(before));
  for (var i = 0; i < list.length; i++) if (list[i].label === name) return list[i];
  return null;
}
eq('proto: a colon is a send', pctx('#3:').kind, 'selector');
eq('proto: and knows its receiver', pctx('#3:').receivers, ['integer']);
eq('proto: an @ offers directives', pctx('@').kind, 'directive');
eq('proto: a partial directive', pctx('@inf').partial, 'inf');
eq('proto: an @ in a comment does not', pctx('; @'), null);
eq('proto: an @ in a string does not', pctx('"a@'), null);
eq('proto: the directives are the reference table', C.items(data, pctx('@')).length, data.directives.length);
eq('proto: use inserts its form', pitem('@', 'use').insertText, 'use "${1:file}".');
eq('proto: infix inserts its form', pitem('@', 'infix').insertText, 'infix ${1:op} ${2:prec} ${3:message}.');
eq('proto: the statement shape has a stop for the ellipsis', C.directiveSnippet('@syntax <name> <hole> <word> \u2026 => <template>.'), 'syntax ${1:name} ${2:hole} ${3:word} $4 => ${5:template}.');
eq('proto: a hole colon offers kinds', pctx('@syntax if <c> <t:').kind, 'kind');
eq('proto: a partial kind', pctx('@syntax if <c> <t: bl').partial, 'bl');
eq('proto: the kinds are the five', C.items(data, pctx('<t:')).map(function (k) { return k.label; }), ['expression', 'name', 'literal', 'block', 'place']);
eq('proto: a send colon is not a hole', pctx('<c> => c:').kind, 'selector');
eq('solveig: an @ offers nothing', ctx('@'), null);
eq('solveig: a hole colon is a send', ctx('<t:').kind, 'selector');
"""

# The dialect cases run against the real files: lib/clike.pro through the
# example that uses it, with a reader that resolves a @use beside the file.
DIALECT_CASES = r"""
ObjC.import('Foundation');
function readFile(p) {
  var s = $.NSString.stringWithContentsOfFileEncodingError($(p), 4, null);
  return s.isNil() ? null : ObjC.unwrap(s);
}
function dirname(p) { return p.replace(/\/[^\/]*$/, ''); }
function reader(from, use) {
  var candidate = dirname(from) + '/' + use;
  var text = readFile(candidate);
  return text === null ? null : { path: candidate, text: text };
}
var clike = ROOT + '/proto/examples/clike.pro';
var D = DIALECT.parse(readFile(clike), clike, reader);
eq('dialect: no errors', D.errors, []);
eq('dialect: one @use, resolved beside the file', D.uses, [ROOT + '/proto/examples/../lib/clike.pro']);
eq('dialect: clike declares fifteen operators', D.operators.length, 15);
eq('dialect: and four forms', D.forms.map(function (f) { return f.form; }), ['if', 'while', 'do', 'if']);
eq('dialect: an infix by message', DIALECT.lookup(D, '+')[0].message, 'add');
eq('dialect: its precedence', DIALECT.lookup(D, '+')[0].precedence, 60);
eq('dialect: an infix by template', DIALECT.lookup(D, '&&')[0].template, 'left:and({ right })');
eq('dialect: a prefix', DIALECT.lookup(D, '!')[0].kind, 'prefix');
eq('dialect: a declaration keeps its text', DIALECT.lookup(D, '&&')[0].text, '@infix  &&  30 => left:and({ right }).');
eq('dialect: and says where it came from', DIALECT.lookup(D, '&&')[0].from, ROOT + '/proto/examples/../lib/clike.pro');
eq('dialect: a pattern form has parts', D.forms[2].parts, [{ hole: 'b', kind: 'block' }, { word: 'while' }, { hole: 'c', kind: 'expression' }]);
eq('dialect: its head', DIALECT.formHead(D.forms[2]), 'do <b: block> while <c>');
eq('dialect: its snippet gives a block hole braces', DIALECT.formSnippet(D.forms[2]), 'do { $1 } while ${2:c}');
eq('dialect: an if with an else', DIALECT.formHead(D.forms[3]), 'if <c> <t: block> else <e: block>');
eq('dialect: a call form', DIALECT.declaration('@syntax swap(a, b) => { | t | t := a. a := b. b := t }:value', 'x').params, ['a', 'b']);
eq('dialect: its snippet', DIALECT.formSnippet(DIALECT.declaration('@syntax swap(a, b) => x', 'x')), 'swap(${1:a}, ${2:b})');
eq('dialect: a header stops at the first statement', DIALECT.headerStatements('@infix + 60 add.\nn := #1.\n@infix - 60 sub.').length, 1);
eq('dialect: and at an @include', DIALECT.headerStatements('@include "a.sol".\n@infix + 60 add.').length, 0);
eq('dialect: a full stop inside a template belongs to it', DIALECT.headerStatements('@syntax do <b: block> while <c> => (b:value. { c }:whileTrue(b)).').length, 1);
eq('dialect: a float keeps its point', DIALECT.headerStatements('@infix + 60 => left:add(1.5).').length, 1);
eq('dialect: a comment is not a declaration', DIALECT.headerStatements('; @infix + 60 add.\n@prefix ! not.')[0], '@prefix ! not');
eq('dialect: a bar can be declared', DIALECT.declaration('@infix | 50 bitOr', 'x').operator, '|');
eq('dialect: a missing @use is an error, not a crash', DIALECT.parse('@use "nowhere.pro".', clike, reader).errors.length, 1);
eq('dialect: a cycle is read once', DIALECT.parse('@use "clike.pro".', clike, function () { return { path: clike, text: '@use "clike.pro".' }; }).uses.length, 1);
eq('dialect: what a reader cannot read is an error', DIALECT.declaration('@infix', 'x').error.indexOf('not a declaration'), 0);
var wctx = C.context('n = #1.\nwh', data, 'proto');
eq('completion: a bare word in proto is a word context', wctx.kind, 'word');
eq('completion: with the partial', wctx.partial, 'wh');
eq('completion: a word after a colon is a send', C.context('a:wh', data, 'proto').kind, 'selector');
eq('completion: the forms come as snippets', C.items(data, wctx, D, DIALECT).map(function (i) { return i.insertText; }),
   ['if ${1:c} { $2 }', 'while ${1:c} { $2 }', 'do { $1 } while ${2:c}', 'if ${1:c} { $2 } else { $3 }']);
eq('completion: with the declaration as detail', C.items(data, wctx, D, DIALECT)[1].detail, 'while <c> <b: block>');
eq('completion: and no dialect, no forms', C.items(data, wctx, null, DIALECT), []);
"""

def run_dialect_corpus():
    """Every .pro file's header, read by dialect.js: no errors, every @use found
    beside the file, and as many declarations as the file has directive lines."""
    files = subprocess.run(['git', 'ls-files', '*.pro'], cwd=ROOT, capture_output=True, text=True).stdout.split()
    want = {}
    for f in files:
        text = open(os.path.join(ROOT, f), encoding='utf-8').read()
        want[f] = [len(re.findall(r'^@(?:infixr?|prefix)\b', text, re.M)), len(re.findall(r'^@syntax\b', text, re.M))]
    dsrc = open(os.path.join(HERE, 'dialect.js'), encoding='utf-8').read()
    harness = ('var module = { exports: {} };\n' + dsrc + '\nvar DIALECT = module.exports;\n'
               'var ROOT = ' + json.dumps(ROOT) + ';\nvar want = ' + json.dumps(want) + ';\n'
               + DIALECT_CASES.split('var clike =')[0] +
               """
var out = [];
Object.keys(want).forEach(function (f) {
  var p = ROOT + '/' + f, text = readFile(p);
  var own = DIALECT.headerStatements(text).map(function (s) { return DIALECT.declaration(s, p); });
  var got = [own.filter(function (d) { return d.operator; }).length, own.filter(function (d) { return d.form; }).length];
  own.filter(function (d) { return d.error; }).forEach(function (d) { out.push(f + ': ' + d.error); });
  if (JSON.stringify(got) !== JSON.stringify(want[f])) out.push(f + ': declarations ' + JSON.stringify(got) + ' want ' + JSON.stringify(want[f]));
  DIALECT.parse(text, p, reader).errors.forEach(function (d) { out.push(f + ': ' + d.error); });
});
out.length ? out.join('\\n') : 'ok';
""")
    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False) as f:
        f.write(harness); path = f.name
    r = subprocess.run(['osascript', '-l', 'JavaScript', path], capture_output=True, text=True)
    os.unlink(path)
    out = (r.stdout + r.stderr).strip()
    if r.returncode or out != 'ok':
        for line in out.split('\n'): print('DIALECT  ' + line)
        return 1, len(files)
    return 0, len(files)

def run_js():
    src = open(os.path.join(HERE, 'completion.js'), encoding='utf-8').read()
    dsrc = open(os.path.join(HERE, 'dialect.js'), encoding='utf-8').read()
    data = open(os.path.join(HERE, 'selectors.json'), encoding='utf-8').read()
    harness = ('var module = { exports: {} };\n' + src + '\nvar C = module.exports;\n'
               'module = { exports: {} };\n' + dsrc + '\nvar DIALECT = module.exports;\n'
               'var ROOT = ' + json.dumps(ROOT) + ';\nvar data = ' + data + ';\n'
               'var failures = [];\n'
               'function eq(name, got, want) { var g = JSON.stringify(got), w = JSON.stringify(want);'
               ' if (g !== w) failures.push(name + ": got " + g + " want " + w); }\n'
               + JS_CASES + DIALECT_CASES + '\nfailures.length ? failures.join("\\n") : "ok";\n')
    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False) as f:
        f.write(harness); path = f.name
    r = subprocess.run(['osascript', '-l', 'JavaScript', path], capture_output=True, text=True)
    os.unlink(path)
    out = (r.stdout + r.stderr).strip()
    if r.returncode or out != 'ok':
        for line in out.split('\n'): print('JS       ' + line)
        return 1
    return 0

if __name__ == '__main__':
    bad = run_fixture(FIXTURE, SOLVEIG) + run_fixture(PROTO_FIXTURE, PROTO)
    cbad, n, counts = run_corpus('*.sol', SOLVEIG)
    pbad, pn, pcounts = run_corpus('*.pro', PROTO)
    for k in sorted(counts): print(f'{counts[k]:8d}  {k}')
    for k in sorted(pcounts): print(f'{pcounts[k]:8d}  {k}')
    mbad = run_messages()
    jbad = run_js()
    dbad, dn = run_dialect_corpus()
    cases = (JS_CASES + DIALECT_CASES).count("\neq(")
    total = bad + cbad + pbad + mbad + jbad + dbad
    print(f'{len(FIXTURE)} + {len(PROTO_FIXTURE)} fixture lines, {n} .sol and {pn} .pro files, '
          f'{cases} completion and dialect cases, {dn} headers read; {total} problem(s)')
    sys.exit(1 if total else 0)
