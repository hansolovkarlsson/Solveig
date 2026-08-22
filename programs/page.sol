; page.sol -- read an HTML file and report on it.
;
; Run with:  ./bin/solas programs/page.sol && ./bin/solvm programs/page.sob
; Over a file of your own:  ./bin/solvm programs/page.sob path/to/page.html
; Listing one kind of element:  ./bin/solvm programs/page.sob page.html img
;
; The parser is [lib/html.sol](../lib/html.sol), on the search path, so this
; says `@include "html.sol".` and not where it lives.
;
; The fourth program here, and the one that pushed on ground the other three did
; not:
;
;   1. **It cannot fail on bad input, because bad input is the normal case.**
;      log.sol skips a bad line, json.sol refuses a bad document -- both right
;      for their format. HTML is generated, served, and wrong, so a reader that
;      stops is no use. The parser recovers and keeps a list, and this program
;      prints the list as part of the report rather than as an error.
;
;   2. **The tree is built against a stack, not by recursion**, and that is what
;      takes it out of reach of the 62-frame limit (ROADMAP 3.5) that stops
;      json.sol at 28 levels of nesting. Measured: this reads a document nested
;      50,000 deep. The catch was that walking the tree back down recursed, and
;      capped at 28 again -- so `text`, `find` and `findAll` are written with a
;      stack too. The limit is not a property of the data; it is a property of
;      how you traverse it.
;
;   3. **An array could not be popped, or asked what it holds**, which a stack
;      notices immediately. Both were written around here first and both are
;      built now -- `removeLast` and `indexOf`, COMPLETED 6.23. The workaround
;      being in shipped library code is what made the case for them.

@include "html.sol".

; ---------------------------------------------------------------------------
; Where the page comes from

sample := "<!DOCTYPE html>
<html>
<head><title>Solveig &mdash; a small language</title></head>
<body>
  <h1>Solveig</h1>
  <p>A small object-oriented language, its bytecode virtual machine, and a REPL.
  <p>Everything is an object &amp; all work happens by sending messages.
  <h2>Getting started</h2>
  <ul>
    <li><a href=\"docs/TUTORIAL.md\">Tutorial</a>
    <li><a href=\"docs/GUIDE.md\">Guide</a>
    <li><a href=\"docs/REFERENCE.md\">Reference</a>
  </ul>
  <h2>Examples</h2>
  <p>There are <b>27</b> of them, and <i>three</i> are whole programs.</p>
  <img src=\"diagram.png\" alt=\"the three parts\">
  <img src=\"screenshot.png\">
  <script>if (count < 10) { show(); }</script>
  <h2>Status</h2>
  <p>Version 0.4.0.</i>
</body>
</html>".

path := system:arguments:size:greaterThan(#0):ifElse(
    { system:arguments:at(#1) },
    { | fallback |
      fallback := "build/example.html".
      system:writeFile(fallback, sample).
      fallback }).

system:fileExists(path):ifFalse({
    "no such file: {}":fill([path]):display.
    system:exit(#1) }).

; No `onError` around this one, and that is the point: it does not raise.
page := html:read(system:readFile(path)).

; ---------------------------------------------------------------------------
; What is in it

title := page:find("title").
"":display.
"{} -- {} bytes":fill([path, system:fileSize(path)]):display.
title:isNil:ifElse(
    { "no <title>":display },
    { "title: {}":fill([title:text]):display }).

; A tag named on the command line is dumped and nothing else is, which is what
; makes this usable as a tool rather than only as a demonstration.
system:arguments:size:greaterThan(#1):ifTrue({ | wanted, found |
    wanted := system:arguments:at(#2):asLowercase.
    found := page:findAll(wanted).
    "":display.
    "{} <{}>":fill([found:size, wanted]):display.
    found:do({ e |
        "  {}{}":fill([
            e:attributes:size:equals(#0):ifElse({ "" }, {
                e:attributes:keys:sorted:collect({ k |
                    "{}=\"{}\"":fill([k, e:attributes:at(k)]) }):join(" "):concat("  ") }),
            e:text]):display }).
    system:exit(#0) }).

; ---------------------------------------------------------------------------
; The outline
;
; Every heading, in document order, which one walk gives and six calls to
; `findAll` would not -- those would answer all the h1s, then all the h2s.
; `selectNodes` takes the test as a block, so "is this a heading" is written
; once and the order is the document's.

isHeading := { node | "h1 h2 h3 h4 h5 h6":indexOf(node:name):notNil }.
headings := page:selectNodes(isHeading).

"":display.
headings:size:equals(#0):ifElse(
    { "no headings":display },
    { "outline":display.
      headings:do({ h | | level, indent |
        level := h:name:copyFrom(#2, #2):asInteger.
        indent := "".
        #1:toDo(level:sub(#1), { n | indent := indent:concat("  ") }).
        "  {}{}":fill([indent, h:text]):display }) }).

; ---------------------------------------------------------------------------
; Links and images

links := page:findAll("a").
"":display.
"{} links":fill([links:size]):display.
links:do({ a | | href |
    href := a:attribute("href").
    "  {}  {}":fill([
        href:isNil:ifElse({ "(no href)" }, { href:asString("<22") }),
        a:text]):display }).

; The one check worth making on a page, and the reason `attribute` answers nil
; rather than raising: a missing attribute is a question, not a failure.
images := page:findAll("img").
missing := images:select({ img | img:attribute("alt"):isNil }).
"":display.
"{} images, {} without alt text":fill([images:size, missing:size]):display.
missing:do({ img |
    "  {}":fill([img:attribute("src"):isNil:ifElse(
        { "(no src)" }, { img:attribute("src") })]):display }).

; ---------------------------------------------------------------------------
; What was wrong with it
;
; Printed as part of the report rather than as an error, because for this format
; they are a finding about the page and not a failure of the reader. The tree
; above was built from the same document that produced them.

"":display.
html:complaints:size:equals(#0):ifElse(
    { "no complaints":display },
    { "{} thing{} wrong with the markup":fill([html:complaints:size,
          html:complaints:size:equals(#1):ifElse({ "" }, { "s" })]):display.
      html:complaints:do({ c | "  ":concat(c):display }) }).
