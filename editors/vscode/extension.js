// extension.js -- the adapter between VS Code and completion.js.
'use strict';
const vscode = require('vscode');
const completion = require('./completion.js');
const data = require('./selectors.json');

function activate(context) {
  const provider = vscode.languages.registerCompletionItemProvider('solveig', {
    provideCompletionItems(document, position) {
      const before = document.lineAt(position.line).text.slice(0, position.character);
      const ctx = completion.context(before, data);
      if (!ctx) return undefined;
      return completion.items(data, ctx).map(it => {
        const item = new vscode.CompletionItem(it.label, vscode.CompletionItemKind.Method);
        item.detail = it.detail;
        item.documentation = new vscode.MarkdownString(it.documentation);
        item.insertText = it.snippet ? new vscode.SnippetString(it.insertText) : it.insertText;
        item.sortText = it.sortText;
        return item;
      });
    }
  }, ':');
  context.subscriptions.push(provider);
}

function deactivate() {}

module.exports = { activate, deactivate };
