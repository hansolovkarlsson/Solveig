// dialect.js -- what a Proto module's header declares, and what it @uses.
//
// A dialect gives a module its operators and forms, and a grammar cannot read
// the file they came from; this can. Nothing from vscode is used here, so
// that test.py can run it under osascript against the real dialect files.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.SolveigDialect = factory();
})(this, function () {
  'use strict';

  var ID = '[A-Za-z_][A-Za-z0-9_]*';

  // The header's statements: from the top of the module to the first that is
  // not a directive, each as its text. Strings, comments and brackets are
  // honoured, and a . between digits belongs to the float it is in.
  function headerStatements(text) {
    var out = [], start = 0, depth = 0, i = 0;
    var inString = false, inComment = false;
    for (; i < text.length; i++) {
      var c = text.charAt(i);
      if (inComment) { if (c === '\n') inComment = false; continue; }
      if (inString) {
        if (c === '\\') i++;
        else if (c === '"') inString = false;
        continue;
      }
      if (c === '"') inString = true;
      else if (c === ';') inComment = true;
      else if (c === '(' || c === '[' || c === '{') depth++;
      else if (c === ')' || c === ']' || c === '}') depth--;
      else if (c === '.' && depth <= 0) {
        if (/[0-9]/.test(text.charAt(i - 1)) && /[0-9]/.test(text.charAt(i + 1))) continue;
        var statement = stripComments(text.slice(start, i)).trim();
        start = i + 1;
        if (!statement) continue;
        if (statement.charAt(0) !== '@' || /^@include\b/.test(statement)) break;
        out.push(statement);
      }
    }
    return out;
  }

  function stripComments(s) {
    var out = '', inString = false;
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (inString) {
        out += c;
        if (c === '\\') { out += s.charAt(++i); }
        else if (c === '"') inString = false;
      } else if (c === '"') { inString = true; out += c; }
      else if (c === ';') { while (i < s.length && s.charAt(i) !== '\n') i++; out += '\n'; }
      else out += c;
    }
    return out;
  }

  // One directive statement to a declaration, or an error saying why not.
  function declaration(statement, from) {
    var m;
    if ((m = /^@use\s+"((?:\\.|[^"\\])*)"$/.exec(statement))) return { use: m[1] };
    if ((m = new RegExp('^@(infixr?)\\s+(\\S+)\\s+([0-9]+)\\s+(?:=>\\s*([\\s\\S]+)|(' + ID + '))$').exec(statement)))
      return { operator: m[2], kind: m[1], precedence: +m[3], template: m[4] || null, message: m[5] || null,
               text: statement + '.', from: from };
    if ((m = new RegExp('^@prefix\\s+(\\S+)\\s+(?:=>\\s*([\\s\\S]+)|(' + ID + '))$').exec(statement)))
      return { operator: m[1], kind: 'prefix', precedence: null, template: m[2] || null, message: m[3] || null,
               text: statement + '.', from: from };
    if ((m = new RegExp('^@syntax\\s+(' + ID + ')\\s*\\(([^)]*)\\)\\s*=>\\s*([\\s\\S]+)$').exec(statement)))
      return { form: m[1], shape: 'call', params: m[2].split(',').map(function (p) { return p.trim(); }).filter(Boolean),
               parts: [], template: m[3], text: statement + '.', from: from };
    if ((m = new RegExp('^@syntax\\s+(' + ID + ')((?:\\s+(?:<[^>]*>|' + ID + '))*)\\s*=>\\s*([\\s\\S]+)$').exec(statement))) {
      var parts = [];
      m[2].replace(new RegExp('<\\s*(' + ID + ')\\s*(?::\\s*(' + ID + '))?\\s*>|(' + ID + ')', 'g'), function (_, hole, kind, word) {
        parts.push(hole ? { hole: hole, kind: kind || 'expression' } : { word: word });
      });
      return { form: m[1], shape: 'pattern', params: [], parts: parts, template: m[3], text: statement + '.', from: from };
    }
    return { error: 'not a declaration this reader knows: ' + statement, from: from };
  }

  // Everything a module's header declares, its @uses followed. `read(from,
  // path)` answers { path, text } for a @use, resolved the way Proto resolves
  // it, or null; a file is read once, so a diamond costs nothing and a cycle
  // is not followed.
  function parse(text, from, read) {
    var result = { operators: [], forms: [], uses: [], errors: [] };
    var seen = {};
    function walk(text, from) {
      headerStatements(text).forEach(function (statement) {
        var d = declaration(statement, from);
        if (d.use) {
          var found = read ? read(from, d.use) : null;
          if (!found) { result.errors.push({ error: 'cannot find "' + d.use + '"', from: from }); return; }
          result.uses.push(found.path);
          if (seen[found.path]) return;
          seen[found.path] = true;
          walk(found.text, found.path);
        } else if (d.error) result.errors.push(d);
        else if (d.operator) result.operators.push(d);
        else result.forms.push(d);
      });
    }
    seen[from] = true;
    walk(text, from);
    return result;
  }

  // A form as the snippet that writes a use of it: a block hole gets its
  // braces, any other hole a tab stop named for it, and a word is itself.
  function formSnippet(f) {
    var n = 0;
    if (f.shape === 'call')
      return f.form + '(' + f.params.map(function (p) { n++; return '${' + n + ':' + p + '}'; }).join(', ') + ')';
    return [f.form].concat(f.parts.map(function (p) {
      if (p.word) return p.word;
      n++;
      return p.kind === 'block' ? '{ $' + n + ' }' : '${' + n + ':' + p.hole + '}';
    })).join(' ');
  }

  // A form's declaration without its template: `while <c> <b: block>`.
  function formHead(f) {
    if (f.shape === 'call') return f.form + '(' + f.params.join(', ') + ')';
    return [f.form].concat(f.parts.map(function (p) {
      return p.word ? p.word : '<' + p.hole + (p.kind === 'expression' ? '' : ': ' + p.kind) + '>';
    })).join(' ');
  }

  // What is declared under a name or an operator, for a hover.
  function lookup(dialect, token) {
    return dialect.operators.filter(function (o) { return o.operator === token; })
      .concat(dialect.forms.filter(function (f) { return f.form === token; }));
  }

  return { parse: parse, headerStatements: headerStatements, declaration: declaration,
           formSnippet: formSnippet, formHead: formHead, lookup: lookup };
});
