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
"you have {} apples and {} pears":format([#3, #4]):print.
"{{ is a literal brace":format([]):print.

; Placeholders and values must match exactly -- both too few and too many are
; errors, so a mistake cannot pass as deliberate output.
;   "{} and {}":format([#1])   ->  more placeholders than the 1 value given

; print shows the literal form; display writes the text. That distinction is why
; a formatted string can be shown without wearing quotes.
"you have {} apples":format([#3]):print.     ; "you have 3 apples"
"you have {} apples":format([#3]):display.   ; you have 3 apples

; \" \\ \n \t \r are the escapes, so a string can hold a quote or a newline.
q := "she said \"hi\"".
q:print.                     ; "she said \"hi\"" -- escapes put back
q:display.                   ; she said "hi"
"one\ntwo":display.          ; two lines
