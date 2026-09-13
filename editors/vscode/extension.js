// extension.js -- the adapter between VS Code and completion.js and dialect.js.
'use strict';
const fs = require('fs');
const path = require('path');
const vscode = require('vscode');
const completion = require('./completion.js');
const dialect = require('./dialect.js');
const data = require('./selectors.json');

// Where a @use is looked for: beside the file using it, then each entry of
// PROTO_PATH. The -I directories are the command line's and have no
// counterpart here.
function readUse(from, use) {
  const dirs = [];
  if (from && path.isAbsolute(from)) dirs.push(path.dirname(from));
  (process.env.PROTO_PATH || '').split(':').filter(Boolean).forEach(d => dirs.push(d));
  for (const dir of dirs) {
    const candidate = path.resolve(dir, use);
    try {
      return { path: candidate, text: fs.readFileSync(candidate, 'utf8') };
    } catch (e) { /* not here */ }
  }
  return null;
}

function dialectOf(document) {
  if (document.languageId !== 'proto') return null;
  const from = document.uri.scheme === 'file' ? document.uri.fsPath : '';
  return dialect.parse(document.getText(), from, readUse);
}

const OPERATOR = /\|\||[-+*\/<>=!&^%~?\\]+|\|/g;

function activate(context) {
  context.subscriptions.push(vscode.languages.registerCompletionItemProvider(['solveig', 'proto'], {
    provideCompletionItems(document, position) {
      const before = document.lineAt(position.line).text.slice(0, position.character);
      const ctx = completion.context(before, data, document.languageId);
      if (!ctx) return undefined;
      const items = completion.items(data, ctx, ctx.kind === 'word' ? dialectOf(document) : null, dialect);
      return items.map(it => {
        const kind = ctx.kind === 'directive' ? vscode.CompletionItemKind.Keyword
                   : ctx.kind === 'kind' ? vscode.CompletionItemKind.TypeParameter
                   : ctx.kind === 'word' ? vscode.CompletionItemKind.Snippet
                   : vscode.CompletionItemKind.Method;
        const item = new vscode.CompletionItem(it.label, kind);
        item.detail = it.detail;
        item.documentation = new vscode.MarkdownString(it.documentation);
        item.insertText = it.snippet ? new vscode.SnippetString(it.insertText) : it.insertText;
        item.sortText = it.sortText;
        return item;
      });
    }
  }, ':', '@'));

  // Hover on an operator or a syntax word: the declaration that gave it its
  // meaning, and the file that said so.
  context.subscriptions.push(vscode.languages.registerHoverProvider('proto', {
    provideHover(document, position) {
      const line = document.lineAt(position.line).text;
      let range = document.getWordRangeAtPosition(position, /[A-Za-z_][A-Za-z0-9_]*/);
      if (!range) {
        OPERATOR.lastIndex = 0;
        let m;
        while ((m = OPERATOR.exec(line))) {
          if (m.index <= position.character && position.character <= m.index + m[0].length) {
            range = new vscode.Range(position.line, m.index, position.line, m.index + m[0].length);
            break;
          }
        }
      }
      if (!range) return undefined;
      const found = dialect.lookup(dialectOf(document), document.getText(range));
      if (!found.length) return undefined;
      const md = new vscode.MarkdownString();
      found.forEach(d => md.appendCodeblock(d.text, 'proto').appendMarkdown('*' + d.from + '*\n\n'));
      return new vscode.Hover(md, range);
    }
  }));
}

function deactivate() {}

module.exports = { activate, deactivate };
