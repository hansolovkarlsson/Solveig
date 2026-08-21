; Strings are immutable, so they are values rather than references: two strings
; with the same characters are equal, and nothing can change one in place.
; Run with:  ./bin/solas examples/strings.sol && ./bin/solvm examples/strings.sob

s := "hello".
s:print.                     ; "hello" -- printed as it would be written
s:size:print.                ; #5

; concat answers a new string; the receiver is untouched.
s:concat(", world"):print.   ; "hello, world"
s:print.                     ; "hello"

; Equality compares characters, not identity -- the opposite of arrays.
"hi":equals("hi"):print.     ; true
[#1]:equals([#1]):print.     ; false, two arrays

; at is one-based, like an array, and answers a one-character string since
; there is no character type of its own.
"abc":at(#1):print.          ; "a"

; Strict, like arithmetic: joining a string to a number is an error, not a
; silent conversion.
;   "a":concat(#1)           ->  'concat' expects a string, got integer

; ---------------------------------------------------------------------------
; Taking one apart
;
; split answers the pieces between occurrences of the separator. There are
; always occurrences + 1 of them, and none is ever dropped.
"a,b,c":split(","):print.    ; ["a", "b", "c"]
"a,,b":split(","):print.     ; ["a", "", "b"] -- nothing between the two commas
",a":split(","):print.       ; ["", "a"]      -- and nothing before the first
"abc":split(","):print.      ; ["abc"]        -- no occurrence, so one piece

; Which means the pieces always go back together into what you started with,
; whatever the string was. `join` is split backwards.
"a,,b":split(","):join(","):print.   ; "a,,b"
",a,":split(","):join(","):print.    ; ",a,"
"":split(","):join(","):print.       ; ""

; An empty separator is allowed here, where split refuses one: nothing cannot be
; looked for, since every position contains it, but putting nothing between the
; pieces is exactly concatenation.
["a", "b", "c"]:join(""):print.      ; "abc"

; join is strict about what it joins -- rendering a value as text is what
; asString and fill are for.
;   ["a", #1]:join(",")      ->  'join' expects an array of strings; #2 is integer

; indexOf answers a one-based index, or nil when there is no match: #0 would be
; a second way of saying "nothing" beside the one the language has.
"hello":indexOf("ll"):print. ; #3
"hello":indexOf("z"):print.  ; nil

; copyFrom takes both ends inclusive, one-based, so copyFrom(#i, #i) is at(#i).
"hello":copyFrom(#2, #4):print.  ; "ell"

; Together they cut a string at a mark.
pair := "name=value".
mark := pair:indexOf("=").
pair:copyFrom(#1, mark:sub(#1)):print.          ; "name"
pair:copyFrom(mark:add(#1), pair:size):print.   ; "value"

; An empty result is spelled with the end one before the start, and that is the
; only spelling -- anything further apart is a mistake rather than a wider empty.
"hello":copyFrom(#3, #2):print.  ; ""
;   "hello":copyFrom(#4, #2)     ->  ends at #2, more than one before its start #4

; Nothing can be looked for: every position in every string contains the empty
; string, so the answer would be arbitrary.
;   "a":split("")            ->  'split' needs at least one character to look for

; They go in arrays and through the iteration protocol like anything else.
names := ["ada", "grace", "alan"].
names:collect({ n | n:concat("!") }):print.        ; ["ada!", "grace!", "alan!"]
names:select({ n | n:size:greaterThan(#3) }):print. ; ["grace", "alan"]

; A method can build one.
string:shout := { self:concat("!!") }.
"hey":shout:print.           ; "hey!!"

; asString gives plain text, where print shows the literal form. That is what
; lets a number be built into a sentence.
"you have ":concat(#45:asString):concat(" apples"):print.   ; "you have 45 apples"
#45:print.                   ; #45   -- the literal form
#45:asString:print.          ; "45"  -- the text

; And back again, strictly: the whole string must be a number and nothing else.
"45":asInteger:print.        ; #45
"2.5":asFloat:print.         ; 2.5
;   " 45":asInteger          ->  ' 45' is not an integer

; format fills {} from an array, asking each value for its asString. That makes
; a sentence readable where a chain of concat would not be.
"you have {} apples and {} pears":fill([#3, #4]):print.
"{{ is a literal brace":fill([]):print.

; Placeholders and values must match exactly -- both too few and too many are
; errors, so a mistake cannot pass as deliberate output.
;   "{} and {}":fill([#1])   ->  more placeholders than the 1 value given

; print shows the literal form; display writes the text. That distinction is why
; a formatted string can be shown without wearing quotes.
"you have {} apples":fill([#3]):print.     ; "you have 3 apples"
"you have {} apples":fill([#3]):display.   ; you have 3 apples

; \" \\ \n \t \r are the escapes, so a string can hold a quote or a newline.
q := "she said \"hi\"".
q:print.                     ; "she said \"hi\"" -- escapes put back
q:display.                   ; she said "hi"
"one\ntwo":display.          ; two lines

; asString takes an optional format spec: [align] [0] [width] [.decimals].
; Numbers align right and text aligns left, so a leading space for a positive
; number falls out of the width rather than needing a mode of its own.
45.8:asString("6.2"):display.    ;  45.80
45.8:asString("08.2"):display.   ; 00045.80
-45.8:asString("08.2"):display.  ; -0045.80  -- the sign comes before the zeros
"ab":asString(">6"):display.     ;     ab

; Which is what makes columns line up.
row := { n, v | "{}{}":fill([n:asString("<8"), v:asString("8.2")]) }.
row:value("apples", 3.5):display.
row:value("pears", 12.25):display.

; "," groups whole-number digits in threes -- and only those, so a sign, a
; fraction, and an exponent pass through untouched.
#1234567:asString(","):display.      ; 1,234,567
1234567.891:asString(",.2"):display. ; 1,234,567.89
#-1234567:asString(","):display.     ; -1,234,567

; Decimals and grouping belong to numbers; asking anything else is an error.
;   #45:asString(".2")   ->  decimals mean nothing for an integer
;   "ab":asString(",")   ->  digit grouping means nothing for a string

; Bases are their own message, not a letter in the spec: one message covers
; every base from 2 to 36, and padding still comes from the spec by chaining.
#255:asBase(#16):display.                    ; ff
#255:asBase(#2):display.                     ; 11111111
#255:asBase(#16):asString("08"):display.     ; 000000ff
"ff":asInteger(#16):print.                   ; #255

; asUppercase and asLowercase change ASCII letters and leave everything else,
; which is what gives uppercase hex.
#255:asBase(#16):asUppercase:display.        ; FF
"Hello, World!":asLowercase:display.         ; hello, world!
