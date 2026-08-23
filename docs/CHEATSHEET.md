# Solum cheatsheet

*Everything the language answers, on one page, for when you know what you want
and not what it is called. [REFERENCE.md](REFERENCE.md) is the full account of
each of these — this is the index to your own memory.*

**Every built-in message appears below, and a test in
[tests/test_compile.c](../tests/test_compile.c) fails if one is added without
being listed here.** The examples in the fenced blocks are run on every build
and their answers checked, the same as everywhere else in this repository.

---

## Syntax, all of it

```
a := #45.                       ; -- ':=' binds, '.' ends a statement
a:print.                        ; #45   -- ':' sends a message
a:add(#5):print.                ; #50   -- sends chain left to right

xs := [#1, #2, #3].             ; -- array literal
xs:at(#2):print.                ; #2
```

```
double := { x | x:mul(#2) }.        ; -- a block: { params | body }
double:value(#21):print.            ; #42

counted := { | n | n := #0. n:inc }.  ; -- { | temps | body }
counted:value:print.                  ; #1
```

```
point := object:new.            ; -- an object is made from another object
point:x := #3.                  ; -- a slot holds data
point:show := { self:x }.       ; -- a slot holding a block is a method
point:show:print.               ; #3
```

| Written | Is |
| --- | --- |
| `#45` | an integer |
| `45` `4.5` `4e2` | a **float** — the unmarked number is the float here |
| `"text"` | a string, bytes, with `\n \t \" \\` escapes |
| `'name` | a symbol, interned, compared by pointer |
| `[a, b]` | an array — sugar for `array:of(a, b)` |
| `{ x \| body }` | a block; `{ x, y \| \| t \| body }` takes two and has a temp |
| `; to end of line` | a comment |
| `@include "file.sol".` | splices another file in, once, before compiling |
| `nil` `true` `false` `infinity` `nan` | the value globals |
| `object` `integer` `float` `string` `symbol` `array` `dictionary` `boolean` `block` `time` `error` `system` | the class globals |

## Six rules that bite

| | |
| --- | --- |
| **No implicit conversion, anywhere** | `#1:add(1.0)` is an error, not `2.0`. `#1:lessThan(1.0)` is an error. `equals` is the one exception and answers `false` across types. |
| **Indices are one-based** | `xs:at(#1)` is the first, and `copyFrom(#a, #b)` includes both ends. |
| **`ifTrue` answers the block's value** | Not a boolean. Never chain `ifTrue(...):ifFalse(...)` — use `ifElse(t, f)`. |
| **Integers trap, floats do not** | Overflow is an error; float division by zero is `infinity`. |
| **A capturing block cannot outlive its frame** | Reading an enclosing local is fine while that frame is alive, reported after ([3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame)). |
| **No `^`, no early return** | A block answers its last expression; a loop is left by its condition or by `error:raise` ([3.13](ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing)). |

## Control flow is message sending

There is no `if`, no `while`, no `for`. These are ordinary messages taking
blocks, and the compiler inlines them to jumps when written literally.

| Message | On | Answers |
| --- | --- | --- |
| `ifTrue(block)` `ifFalse(block)` | boolean | the block's answer, or nil |
| `ifElse(then, else)` | boolean | the chosen block's answer |
| `and(block)` `or(block)` | boolean | short-circuit; the block runs only if needed |
| `not` | boolean | a boolean |
| `whileTrue(body)` | block | nil, having run `body` while the receiver answers true |
| `doUntil(condition)` | block | nil; **body first**, so always at least once |
| `repeat(#n)` | block | nil, having run the receiver `n` times |
| `#n:repeat(block)` | integer | nil, having run the block `n` times |
| `toDo(#b, block)` | integer | counts up to `#b` **inclusive**, block given each |
| `toByDo(#b, #step, block)` | integer | the same by `#step`; negative counts down |
| `do(block)` | array, dictionary | the receiver, block per element |

```
#3:greaterThan(#2):ifTrue({ "yes":display }).       ; yes
n := #5:greaterThan(#9):ifElse({ "big" }, { "small" }).
n:display.                                          ; small

i := #0.
{ i:lessThan(#3) }:whileTrue({ i := i:inc }).
i:print.                                            ; #3

ticks := #0.
#3:repeat({ ticks := ticks:inc }).
ticks:print.                                        ; #3

seen := "".
#1:toByDo(#7, #3, { n | seen := seen:concat(n:asString) }).
seen:display.                                       ; 147
```

## Every type answers these

| Message | Answers |
| --- | --- |
| `print` | the receiver, having written its literal form and a newline |
| `display` | the receiver, having written it *without* quotes on a string |
| `asString` | its text |
| `equals(v)` `notEquals(v)` | a boolean; value for numbers and text, identity for containers |
| `isNil` `notNil` | a boolean |
| `isKindOf(class)` | a boolean, searching the prototype chain |
| `respondsTo('name)` | a boolean — whether a send would find something |
| `perform('name, ...)` | sends the message that symbol names |
| `slots` | an array of symbols naming the receiver's **own** slots |
| `slotAt('name)` | the value in that slot, searching the chain like a send |
| `new` | on a class: a new instance; on a value type: refused, there is nothing to make |

```
#45:respondsTo('add):print.         ; true
#45:perform('add, #5):print.        ; #50
"x":isKindOf(string):print.         ; true
nil:isNil:print.                    ; true
```

**Reflection reads and never writes.** There is no `slotAtPut`, no way to remove
a slot, and no re-parenting.

## integer

Arithmetic traps on overflow rather than wrapping — which is why the textbook
random generator cannot be written here at all.

| Message | Answers |
| --- | --- |
| `add(n)` `sub(n)` `mul(n)` | an integer; traps on overflow |
| `div(n)` `mod(n)` | **floored**; traps on zero |
| `inc` `dec` | one more, one less |
| `negated` `abs` | an integer; traps on the most negative |
| `lessThan(n)` `greaterThan(n)` | a boolean |
| `lessOrEqual(n)` `greaterOrEqual(n)` | a boolean |
| `bitAnd(n)` `bitOr(n)` `bitXor(n)` `bitNot` | an integer, bit by bit |
| `shiftLeft(#n)` `shiftRight(#n)` | an integer; `#0` to `#63` |
| `asFloat` | a float; loses precision above 2^53 |
| `asString` | the digits, without the `#` |
| `asBase(#n)` | the digits in base `n`, 2 to 36 |
| `asCharacter` | the one-byte string that byte spells; `#0` to `#255` |
| `repeat(block)` `toDo(#b, block)` `toByDo(#b, #s, block)` | loops — see above |

```
#7:div(#2):print.               ; #3
#-7:div(#2):print.              ; #-4   -- floored, not truncated
#7:mod(#3):print.               ; #1
#255:asBase(#16):display.       ; ff
#65:asCharacter:display.        ; A
#5:asFloat:print.               ; 5
```

## float

The unmarked number. Everything integer has except `asFloat`, `asBase` and the
overflow traps, plus:

| Message | Answers |
| --- | --- |
| `floor` `ceiling` `rounded` `truncated` | an **integer**; errors on infinity, nan, out of range |
| `sqrt` | a float; `nan` for a negative |
| `asString(spec)` | padded text — `[align][,][0][width][.decimals]` |

There is no `asInteger`: narrowing names its direction. Dividing by zero answers
`infinity` rather than erring.

```
2.7:floor:print.                ; #2
-2.7:truncated:print.           ; #-2   -- floor goes down, truncate to zero
9.0:sqrt:print.                 ; 3
1:div(3):print.                 ; 0.3333333333333333
3.14159:asString("0.2"):display.  ; 3.14
"[":concat(1234.5:asString(",10.2")):concat("]"):display.  ; [  1,234.50]
```

## string

Bytes, not characters: `"café":size` is 5.

| Message | Answers |
| --- | --- |
| `size` | an integer |
| `at(#i)` | a one-character string; **one-based** |
| `concat(s)` | a new string; strict about its argument |
| `split(s)` | an array of the pieces between occurrences of `s` |
| `indexOf(s)` | where `s` first appears, one-based, or nil |
| `copyFrom(#a, #b)` | the characters `#a` to `#b`, both ends included |
| `fill([...])` | the blanks `{}` filled in from the array |
| `trim` | the same text without the space around it |
| `asUppercase` `asLowercase` | a new string; **ASCII letters only** |
| `asInteger` `asFloat` | strict: the whole string must be a number |
| `asInteger(#n)` | reads base `n`, 2 to 36 |
| `asByte` | the number of the one byte in it |
| `asSymbol` | the interned symbol for these characters |
| `asTime` `asTime(format)` | an instant; ISO-8601, or `strptime` format |
| `asString(spec)` | padded text |
| `lessThan(s)` `greaterThan(s)` `lessOrEqual(s)` `greaterOrEqual(s)` | a boolean, comparing bytes |

There is no `replace`: `split(a):join(b)` is the same operation in two words.

```
"a,b,c":split(","):print.               ; ["a", "b", "c"]
"hello":copyFrom(#2, #4):display.       ; ell
"{} of {}":fill([#3, #10]):display.     ; 3 of 10
"  x  ":trim:display.                   ; x
"a-b":split("-"):join("+"):display.     ; a+b
"left":asString("<8"):concat("|"):display.  ; left    |
```

## symbol

Interned and compared by pointer, which is what makes `perform` cheap.

| Message | Answers |
| --- | --- |
| `size` | an integer |
| `asString` | the name, as a string |
| `lessThan(s)` `greaterThan(s)` `lessOrEqual(s)` `greaterOrEqual(s)` | a boolean, comparing the text |

```
'add:asString:display.          ; add
'add:equals('add):print.        ; true
```

## array

One-based, and `add` answers the array so it chains.

| Message | Answers |
| --- | --- |
| `new` / `of(...)` | an empty array / one of the arguments |
| `size` | an integer |
| `at(#i)` | the element; out of range is an error |
| `at_put(#i, v)` | the value stored |
| `add(v)` | **the array**, so it chains |
| `removeLast` | the last element, taken off; an error when empty |
| `indexOf(v)` | where `v` first is, or nil |
| `copyFrom(#a, #b)` | a new array, both ends included |
| `first(#n)` `last(#n)` | a new array of up to `n`; **clamps** |
| `do(block)` | the array, block per element |
| `collect(block)` | a new array of the block's answers |
| `select(block)` | a new array of the elements the block accepted |
| `inject(start, block)` | one value, folded left to right |
| `sorted` `sorted(block)` | a new array, ascending or by the block |
| `join(s)` | the strings with `s` between them; strict |

```
xs := [#4, #1, #3].
xs:sorted:print.                            ; [#1, #3, #4]
xs:collect({ x | x:mul(#2) }):print.        ; [#8, #2, #6]
xs:select({ x | x:greaterThan(#2) }):print. ; [#4, #3]
xs:inject(#0, { a, b | a:add(b) }):print.   ; #8
xs:add(#9):size:print.                      ; #4   -- add answers the array
```

## dictionary

| Message | Answers |
| --- | --- |
| `new` | an empty dictionary |
| `size` | an integer |
| `at(key)` | the value; **an error** when the key is not there |
| `at(key, default)` | the value, or `default` |
| `atPut(key, value)` | **the value stored**, so it chains |
| `includes(key)` | a boolean |
| `remove(key)` | the value removed; an error when absent |
| `keys` `values` | an array, in **no order worth relying on** |
| `do(block)` | the dictionary, block once per **value** |
| `keysAndValuesDo(block)` | the same, block taking a key and a value |

```
d := dictionary:new.
d:atPut("port", #8080).
d:at("port"):print.             ; #8080
d:at("host", "any"):display.    ; any
d:includes("port"):print.       ; true
d:size:print.                   ; #1
```

## block

| Message | Answers |
| --- | --- |
| `value(...)` | the block's answer; the count must match its parameters |
| `boundTo(receiver)` | a new block over the same code, with `self` set |
| `whileTrue(body)` `doUntil(condition)` `repeat(#n)` | loops — see above |
| `onError(handler)` | the block's answer, or the handler's if it failed |
| `ensure(cleanUp)` | the block's answer, having run `cleanUp` either way |
| `timeToRun` `timeToRun(#n)` | seconds one run, or `n` runs, took, as a float |

```
{ error:raise("no") }:onError({ e | e:message }):display.   ; no
{ #1:div(#0) }:onError({ e | "caught" }):display.           ; caught
cleaned := false.
r := { #2:add(#2) }:ensure({ cleaned := true }).
r:print.                                                    ; #4
cleaned:print.                                              ; true
```

## object, and errors

| Message | Answers |
| --- | --- |
| `new` | a fresh object delegating to the receiver |
| `via(ancestor)` | a delegating view: lookup starts there, `self` stays |
| `parent` | the prototype, or nil at the root; read-only |
| `error:raise(text)` | never — it unwinds to the nearest `onError` |
| `e:message` | the text an error was raised with |

`via` is what `super` is elsewhere, except that it names what it overrides.

```
animal := object:new.
animal:speak := { "..." }.
dog := animal:new.
dog:speak := { self:via(animal):speak:concat("woof") }.
dog:speak:display.              ; ...woof
dog:parent:equals(animal):print.  ; true
```

## time

An instant, held as nanoseconds since 1970. A **value**: two are equal when they
name the same instant.

| Message | Answers |
| --- | --- |
| `time:fromSeconds(f)` | an instant, from seconds since the epoch *(on the class)* |
| `asSeconds` | seconds since the epoch, as a float |
| `secondsSince(other)` | a float; negative when `other` is later |
| `plusSeconds(f)` | another instant, `f` seconds along |
| `year` `month` `day` | integers; **January is `#1`** |
| `hour` `minute` `second` | integers |
| `weekday` | an integer; **Monday is `#1`**, Sunday `#7` |
| `asString` | ISO-8601 in UTC |
| `asString(format)` | the format handed to `strftime` |
| `lessThan(t)` `greaterThan(t)` `lessOrEqual(t)` `greaterOrEqual(t)` | a boolean |

```
t := time:fromSeconds(946684800.0).
t:asString:display.                     ; 2000-01-01T00:00:00Z
t:year:print.                           ; #2000
t:weekday:print.                        ; #6   -- a Saturday
t:plusSeconds(86400.0):day:print.       ; #2
"2000-01-01T00:00:00Z":asTime:equals(t):print.   ; true
```

## system

The process, rather than any value. One object with slots, not a class.

| Message | Answers |
| --- | --- |
| `arguments` | an array of strings; empty when there were none |
| `exit(#status)` | nothing — the program stops, `#0` to `#255` |
| `clock` | monotonic seconds as a float; only differences mean anything |
| `time` | the current instant |
| `readLine` `readKey` | one line, or one byte, of standard input; nil at the end |
| `readFile(path)` | the whole file as a string |
| `writeFile(path, text)` `appendFile(path, text)` | nil, having written |
| `fileExists(path)` `isDirectory(path)` | a boolean |
| `fileSize(path)` | an integer, without reading the file |
| `filesIn(path)` | an array of the names in a directory |
| `makeDirectory(path)` | **true** if it made one, false if it was there |
| `remove(path)` | nil, having deleted a file or an **empty** directory |
| `rename(from, to)` | nil, having moved it; **replaces** an existing `to` |
| `modifiedAt(path)` `setModifiedAt(path, t)` | when a file was last written |
| `modeOf(path)` `setMode(path, #mode)` | the permission bits, `#0` to `#4095` |
| `environment(name)` | the variable, or **nil** when unset |
| `run(argv)` | the exit status; `argv` is an **array**, never a command line |
| `capture(argv)` | a dictionary of `"output"` and `"status"` |

`run` and `capture` take an array so that nothing in it is ever read as syntax.
`#127` is the status for *no such command*.

```
system:writeFile("note.txt", "hello").
system:readFile("note.txt"):display.        ; hello
system:fileExists("note.txt"):print.        ; true
system:fileSize("note.txt"):print.          ; #5
system:capture(["echo", "hi"]):at("output"):trim:display.  ; hi
system:remove("note.txt").
```

## The library

Shipped `.sol` files on the search path — `@include "name.sol".` finds them
without being told where they live.

| File | Binds | For |
| --- | --- | --- |
| [control.sol](../lib/control.sol) | `integer:timesCollect(block)` | `n` results, gathered |
| [math.sol](../lib/math.sol) | `min` `max` `between` on numbers; `min` `max` on arrays | the comparisons written out by hand too often |
| [text.sol](../lib/text.sol) | `integer:asUtf8` | a code point as the bytes UTF-8 spells it |
| [lexer.sol](../lib/lexer.sol) | `lexer:all` `on` `next` `atEnd` | Solum's own tokens, scanned by Solum |
| [shell.sol](../lib/shell.sol) | `shell:run` `capture` `read` `line` | when the shell's pipes and globs are the point |
| [json.sol](../lib/json.sol) | `json:read` `json:write` `value:asJson` | JSON in and out |
| [html.sol](../lib/html.sol) | `html:read`, a tree with `find`, `text`, `attribute` | HTML that recovers from bad markup |

```
@include "math.sol".
#3:min(#7):print.               ; #3
[4.0, 1.0, 9.0]:max:print.      ; 9
#5:between(#1, #10):print.      ; true
```

```
@include "json.sol".
v := json:read("{\"port\": 8080}").
v:at("port"):print.             ; #8080
v:asJson:display.               ; {"port":8080}
```

## Running it

```sh
solas prog.sol              # compile to prog.sob
solas prog.sol -o out.sob   # somewhere else
solvm prog.sob              # run it
solvm prog.sob a b          # with arguments, seen as system:arguments
solvm --trace prog.sob      # write the call tree
solvm --steps N --memory N  # bound it
solis                       # the REPL
solid prog.sob              # the debugger: step, next, break, print
```

---

*What is deliberately not in the language is in [ROADMAP.md](ROADMAP.md)
section 3. Why any of it is shaped this way is in [design.md](design.md), and
[lineage.md](lineage.md) places it against Smalltalk, Self, Io, Lua and Ruby.*
