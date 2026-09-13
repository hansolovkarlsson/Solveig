// completion.js -- what to offer after a colon, and in what order.
//
// Nothing from vscode is used here, so that test.py can run this file under
// osascript, the one JavaScript engine every Mac has. extension.js is the
// adapter that turns what this answers into CompletionItems.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.SolveigCompletion = factory();
})(this, function () {
  'use strict';

  var ID = '[A-Za-z_][A-Za-z0-9_]*';

  // Whether the end of `before` is inside a string or a comment. Strings may
  // span lines, which a single line cannot see; a quote count that is odd on
  // the line is the best a line can do.
  function inTextOrComment(before) {
    var inString = false;
    for (var i = 0; i < before.length; i++) {
      var c = before.charAt(i);
      if (inString) {
        if (c === '\\') i++;
        else if (c === '"') inString = false;
      } else if (c === '"') inString = true;
      else if (c === ';') return true;
    }
    return inString;
  }

  // What the text before the colon says the receiver is, when it says.
  // A literal is its type; a name is the prototype or library object it
  // names, and nothing else can be known without running the program.
  function receiverOf(head, known) {
    head = head.replace(/\s+$/, '');
    if (/(?:#-?[0-9]+|\$[0-9A-Fa-f]+|%[01]+)$/.test(head)) return ['integer'];
    if (/(?:^|[^A-Za-z0-9_#$%])[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/.test(head)) return ['float'];
    if (/"$/.test(head)) return ['string'];
    if (new RegExp("'" + ID + '$').test(head)) return ['symbol'];
    if (/\]$/.test(head)) return ['array', 'dictionary'];
    if (/\}$/.test(head)) return ['block'];
    var m = new RegExp('(?:^|[^A-Za-z0-9_:])(' + ID + ')$').exec(head);
    if (!m) return [];
    var name = m[1];
    if (name === 'true' || name === 'false') return ['boolean'];
    return known.indexOf(name) >= 0 ? [name] : [];
  }

  // The situation at the cursor: null when it is not after a colon, or is
  // inside a string or a comment, or the colon is the := of a binding.
  function context(before, data) {
    var m = new RegExp('^(.*?)(:)(' + ID + ')?$').exec(before);
    if (!m || inTextOrComment(m[1])) return null;
    var known = [];
    data.selectors.forEach(function (s) {
      s.signatures.forEach(function (sig) {
        if (known.indexOf(sig.receiver) < 0) known.push(sig.receiver);
      });
    });
    return { receivers: receiverOf(m[1], known), partial: m[3] || '' };
  }

  function takesArguments(sig) {
    return /\(.+\)$/.test(sig.signature);
  }

  // One item per selector. A selector the guessed receiver answers sorts
  // first; the rest follow, because a chain's receiver is not knowable and
  // hiding them would hide the right answer as often as not.
  function items(data, ctx) {
    return data.selectors.map(function (s) {
      var mine = s.signatures.filter(function (sig) { return ctx.receivers.indexOf(sig.receiver) >= 0; });
      var shown = mine.length ? mine : s.signatures;
      var receivers = [];
      s.signatures.forEach(function (sig) {
        if (receivers.indexOf(sig.receiver) < 0) receivers.push(sig.receiver);
      });
      var lines = s.signatures.map(function (sig) {
        var where = sig.source.indexOf('lib/') === 0 ? ' *(' + sig.source + ')*' : '';
        var tail = sig.answers ? (where ? ': ' + sig.answers : ' answers ' + sig.answers) : '';
        return '- `' + sig.receiver + ':' + sig.signature + '`' + where + tail;
      });
      var withArgs = shown.every(takesArguments);
      return {
        label: s.name,
        detail: receivers.join(', '),
        documentation: lines.join('\n'),
        insertText: withArgs ? s.name + '($1)' : s.name,
        snippet: withArgs,
        sortText: (mine.length ? '0' : '1') + s.name
      };
    });
  }

  return { context: context, items: items, receiverOf: receiverOf, inTextOrComment: inTextOrComment };
});
