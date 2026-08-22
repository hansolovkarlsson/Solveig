; serve.sol -- answer one HTTP request, and do it without being injected.
;
; Run with:  ./bin/solas programs/serve.sol && ./bin/solvm programs/serve.sob
;
; With no CGI variables set it runs a handful of requests through the handler
; and prints each response, which is what makes it testable without a socket.
; To answer one real request, set the variables a webserver would set:
;
;   PATH_INFO=/search QUERY_STRING=q=limit ./bin/solvm programs/serve.sob
;   PATH_INFO=/note/limits ./bin/solvm programs/serve.sob
;
; And to run it the way its own case would -- as a guest, with an allowance:
;
;   PATH_INFO=/ ./bin/solvm --steps=100000 --memory=8M programs/serve.sob
;
; The seventh program here, and the first one **whose input does not come from
; whoever ran it.** Every other program in this directory is handed its
; arguments by the person who started it. This one is handed a path and a query string by a stranger, and
; that is what it was written to find out about:
;
;   1. **The message that builds a page inserts exactly what it is given.**
;      `fill` is the natural way to write a template, it reads well, and it is
;      the injection. Nothing in the language or in lib/ escapes HTML --
;      lib/html.sol *reads* entities and cannot write one -- so the escaping is
;      here, and the safe twin of `fill` is the one with the worse name. That is
;      the wrong way round for a language somebody might use this way.
;
;   2. **A template with two kinds of hole cannot be written with `fill` at
;      all**, because it insists the placeholders and the values come to the
;      same number. That check is what makes `fill` worth trusting, so the
;      answer is not to weaken it -- and the marker-and-`split` habit that
;      replaces it is worse, since a marker is a string and a value can contain
;      one. What is left, and what this uses, is an array of pieces joined:
;      seams a value cannot add to.
;
;   3. **Refusing `/note/../../etc/passwd` is not string cleaning**, and the
;      language helps by having nothing. No path joining, no basename, nothing
;      that normalises `..` -- so the tempting wrong answer is not available and
;      what is left is to say which names are names.
;
;   4. **A handler is told what it was asked by `system:environment`**, which
;      ROADMAP 6.32 lists among the messages that *reveal* the machine. It is
;      right to. But this program cannot be written without it, so a permission
;      that can only say yes or no to `environment` has to say yes -- and has
;      then also handed over every secret the server holds. Which is the first
;      concrete argument this project has for the capabilities being finer than
;      one per message.
;
;   5. **And running it under a step limit found the limit's edge.** A request
;      here costs 393 instructions for a note, 465 for the index and 798 for a
;      search, which is the number a host would want. But `system:readFile` of a
;      256MB file and a scan of all of it is **eight instructions** -- the same
;      eight as for a 64MB file, since the count does not follow the size. A
;      step limit bounds how much a program *dispatches*, not how much it does.
;      That is ROADMAP 3.7, written because of this program and correcting two
;      documents that said otherwise.

; ---------------------------------------------------------------------------
; Escaping
;
; `fill` is how a page gets built -- it is the formatting message, it reads
; well, and it inserts **exactly what it is given**. That is right for a message
; that formats and it is the injection, because the value being inserted came
; from the query string.
;
; Nothing in the language or in lib/ escapes HTML. lib/html.sol *decodes*
; entities and has no way to write one, which is the shape of a reader rather
; than an oversight. So it is written here, and the four substitutions are
; `split` and `join`: replacing text is not a message the language has, and does
; not need to be, because taking a string apart on one thing and putting it back
; with another is the same operation said in two words.
;
; `&` goes first. Doing it later would escape the ampersands the earlier passes
; had just written, and `&lt;` would come out `&amp;lt;`.

string:escaped := {
    self:split("&"):join("&amp;")
        :split("<"):join("&lt;")
        :split(">"):join("&gt;")
        :split("\""):join("&quot;") }.

; The safe twin of `fill`, and the reason it exists is the whole lesson of this
; file: the unsafe one is the one with the good name. Every hole in this program
; that reaches untrusted text goes through here.

string:fillEscaped := { values |
    self:fill(values:collect({ v | v:asString:escaped })) }.

; ---------------------------------------------------------------------------
; Reading a query string
;
; `a=1&b=hello+world&c=%2Fetc` into a dictionary. `+` is a space and `%41` is a
; byte in hex, which `asInteger(#16)` and `asCharacter` already spell.
;
; A `%` that is not followed by two hex digits is a `%`. That is a decision, not
; a detail: this is the one place the request can be malformed in a way that has
; nothing to do with what it is asking for, and a handler that raises on it
; answers 500 to a request that is merely untidy.

string:urlDecoded := { | out, i, c |
    out := "". i := #1.
    { i:lessOrEqual(self:size) }:whileTrue({
        c := self:at(i).
        c:equals("%"):and({ i:add(#2):lessOrEqual(self:size) }):ifElse(
            { { out := out:concat(
                    self:copyFrom(i:add(#1), i:add(#2)):asInteger(#16):asCharacter).
                i := i:add(#3) }:onError({ e |
                    out := out:concat(c). i := i:inc }) },
            { out := out:concat(c:equals("+"):ifElse({ " " }, { c })).
              i := i:inc }) }).
    out }.

string:asQuery := { | out |
    out := dictionary:new.
    self:equals(""):ifFalse({
        self:split("&"):do({ pair | | cut |
            cut := pair:indexOf("=").
            cut:isNil:ifElse(
                { out:atPut(pair:urlDecoded, "") },
                { out:atPut(pair:copyFrom(#1, cut:sub(#1)):urlDecoded,
                            pair:copyFrom(cut:inc, pair:size):urlDecoded) }) }) }).
    out }.

; ---------------------------------------------------------------------------
; The notes, which are files
;
; Seeded on first run so the program has something to serve, the way page.sol
; writes itself a sample page.

store := "build/notes".

seed := dictionary:new.
seed:atPut("limits", "A host may say what a program is allowed to spend.
Steps are instructions and memory is live bytes after a collection.
Neither is catchable, because a limit a program can catch is a limit
it can decline.").
seed:atPut("blocks", "A block is a value. It can be stored, passed on, and
called later. Written literally as the argument of ifTrue or whileTrue it
compiles to a jump and no block is made at all.").
seed:atPut("frames", "Recursion reaches about 62 levels, and the failure is
catchable. The limit is a property of how you traverse a structure rather
than of the structure -- a walk against a stack does not meet it.").

system:isDirectory(store):ifFalse({
    system:makeDirectory(store).
    seed:keysAndValuesDo({ name, body |
        system:writeFile("{}/{}.txt":fill([store, name]), body) }) }).

; ---------------------------------------------------------------------------
; Which names are allowed to become a filename
;
; `/note/../../etc/passwd` is the request this refuses, and refusing it is not a
; string-cleaning problem. The language has no path handling at all -- no
; joining, no basename, nothing that normalises `..` -- so there is no tempting
; wrong answer available, and what is left is to say what a name may contain and
; reject everything else.
;
; That is the better answer regardless. Cleaning a name means being right about
; every way of writing the same path, on every filesystem; saying which
; characters a note may be called with means being right once.

allowed := "abcdefghijklmnopqrstuvwxyz0123456789-".

string:isNoteName := {
    self:size:greaterThan(#0):and({ self:size:lessOrEqual(#40) }):and({ | ok |
        ok := true.
        #1:toDo(self:size, { i |
            allowed:indexOf(self:at(i)):isNil:ifTrue({ ok := false }) }).
        ok }) }.

; ---------------------------------------------------------------------------
; The pages

page := { title, body |
    ["<!DOCTYPE html>\n<html>\n<head><title>", title:escaped,
     "</title></head>\n<body>\n", body, "\n</body>\n</html>"]:join("") }.

; The title is escaped and the body is not, because the body is already HTML by
; the time it arrives -- it was built by the blocks below, each of which escaped
; what it inserted. Which is the same rule every template language arrives at
; and is worth writing down: escaping happens where a *value* meets the page,
; once, and never on the way past.
;
; **And that is why this one is an array joined rather than a template.** A page
; with holes of two kinds -- a value to be escaped, a fragment already escaped
; -- cannot be written with `fill`, which insists that the count of placeholders
; match the count of values and so has no way to fill one hole and leave the
; next for later. That check is exactly what makes `fill` worth trusting
; elsewhere, so the answer is not to want it weakened.
;
; The obvious way round is a marker -- `%TITLE%`, `%BODY%`, split and join for
; each. It works and it is the wrong habit, because a marker is a string and a
; value can contain one. The moment a title could be spelled `x%BODY%`, filling
; the title has written a hole for the next pass to fill.
;
; An array of pieces has no markers to collide with. The seams are where the
; commas are, and no value can add one.

notes := { system:filesIn(store):select({ f | f:indexOf(".txt"):notNil })
              :collect({ f | f:copyFrom(#1, f:size:sub(#4)) }):sorted }.

listOf := { names |
    names:size:equals(#0):ifElse(
        { "" },
        { ["<ul>\n", names:collect({ n |
              "  <li><a href=\"/note/{}\">{}</a></li>":fillEscaped([n, n])
           }):join("\n"), "\n</ul>"]:join("") }) }.

index := {
    page:value("Notes", ["<h1>Notes</h1>\n", listOf:value(notes:value)]:join("")) }.

note := { name |
    name:isNoteName:not:ifElse(
        { ['notFound, page:value("Not found",
              "<h1>Not found</h1>\n<p>No note is called {}.":fillEscaped([name]))] },
        { | path |
          path := "{}/{}.txt":fill([store, name]).
          system:fileExists(path):ifElse(
              { ['ok, page:value(name, "<h1>{}</h1>\n<pre>{}</pre>"
                    :fillEscaped([name, system:readFile(path)]))] },
              { ['notFound, page:value("Not found",
                    "<h1>Not found</h1>\n<p>No note is called {}."
                        :fillEscaped([name]))] }) }) }.

search := { term | | hits, body |
    hits := term:equals(""):ifElse({ [] }, { notes:value:select({ n |
        system:readFile("{}/{}.txt":fill([store, n]))
            :asLowercase:indexOf(term:asLowercase):notNil }) }).
    body := ["<h1>Search</h1>\n<p>{} result{} for {}.\n"
                 :fillEscaped([hits:size,
                               hits:size:equals(#1):ifElse({ "" }, { "s" }),
                               term]),
             listOf:value(hits)]:join("").
    page:value("Search", body) }.

; ---------------------------------------------------------------------------
; Routing
;
; A path is its segments, and `split` puts an empty one at the front because the
; path begins with the separator. So `/note/limits` is ["", "note", "limits"].

handle := { path, query | | parts, first, rest |
    parts := path:split("/").
    first := parts:size:greaterOrEqual(#2):ifElse({ parts:at(#2) }, { "" }).
    rest := parts:size:equals(#3):ifElse({ parts:at(#3) }, { nil }).
    parts:size:equals(#2):and({ first:equals("") }):ifElse(
        { ['ok, index:value] },
        { parts:size:equals(#2):and({ first:equals("search") }):ifElse(
            { ['ok, search:value(query:at("q", ""))] },
            { rest:notNil:and({ first:equals("note") }):ifElse(
                { note:value(rest) },
                { ['notFound, page:value("Not found",
                    "<h1>Not found</h1>\n<p>Nothing is at {}."
                        :fillEscaped([path]))] }) }) }) }.

respond := { path, query | | answer, status |
    answer := handle:value(path, query).
    status := answer:at(#1):equals('ok):ifElse({ "200 OK" }, { "404 Not Found" }).
    "HTTP/1.1 {}\r
Content-Type: text/html; charset=utf-8\r
Content-Length: {}\r
\r
{}":fill([status, answer:at(#2):size, answer:at(#2)]) }.

; ---------------------------------------------------------------------------
; One request, from the environment
;
; This is how a webserver tells a CGI program anything, and it is worth noticing
; which message that is. ROADMAP 6.32 lists `environment` among the messages
; that *reveal* the machine rather than change it, and it is right to: it will
; hand over a token from half the CI systems there are. But a handler cannot be
; written without it -- the request arrives that way -- so a permission scheme
; that can only say yes or no to `environment` must say yes here, and has then
; also said yes to every secret the server holds.
;
; Which is an argument for the capabilities being finer than one per message.

requestPath := system:environment("PATH_INFO").
requestQuery := system:environment("QUERY_STRING").

requestPath:notNil:ifTrue({
    respond:value(requestPath,
        requestQuery:isNil:ifElse({ "" }, { requestQuery }):asQuery):display.
    system:exit(#0) }).

; ---------------------------------------------------------------------------
; Otherwise, the demonstration
;
; Seven requests. The last four are the ones this program exists for -- a
; reflected script tag, a name that is only dots, a traversal spelled with
; escapes, and a name carrying the quote that would break out of the `href`.

demo := [
    ["/",                            ""],
    ["/note/limits",                 ""],
    ["/search",                      "q=limit"],
    ["/search",                      "q=%3Cscript%3Ealert%281%29%3C%2Fscript%3E"],
    ["/note/..",                     ""],
    ["/note/..%2F..%2Fetc%2Fpasswd", ""],
    ["/note/limits%22%3E%3Cscript%3E", ""]].

demo:do({ request | | path |
    path := request:at(#1):urlDecoded.
    "==== {}{}":fill([path,
        request:at(#2):equals(""):ifElse({ "" },
            { "?":concat(request:at(#2)) })]):display.
    respond:value(path, request:at(#2):asQuery):display.
    "":display }).
