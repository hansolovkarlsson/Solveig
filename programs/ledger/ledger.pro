; ledger.pro -- a statement, in fixed-point decimal.
;
;     proto ledger.pro -o ledger.sol && solas ledger.sol -o ledger.sob
;     solvm ledger.sob
;
; Amounts are hundredths throughout. money.pro is the header; what it buys and
; what it costs is in README.md under "What it found".

@use "money.pro".

@include "text.sol".

; ---------------------------------------------------------------- the ledger

names := ["Opening balance", "Consulting fee", "Refund",
          "Supplies", "Late fee"].
amounts := [#125000, #48750, -#1225, -#89900, -#1500].

rate := #750.                       ; 7.50%, in hundredths like everything else
ways := #4.                         ; a count, and not an amount

; ------------------------------------------------------------- presentation
;
; Everything from here down is where the dialect stops paying. Turning
; hundredths into "1250.00" is sign handling, floored division and digit
; padding, and none of the three is money arithmetic.

pad2 := { n |
    if n < #10 then "0":concat(n:asString) else n:asString }.

; `:div` and `:mod` as **sends**, deliberately. The dialect's `/` rounds to the
; nearest hundredth, which is right for splitting a bill and wrong for taking a
; number apart -- `#-1225 / #100` is `#-12`, and the whole part of -12.25 is
; -12 with 25 hundredths after it. Solveig's `div` and `mod` are floored, so
; the sign is taken off first and put back at the end rather than trusted
; through the division.
format := { c | | v, body |
    v := c:abs.
    body := v:div(#100):asString:concat("."):concat(pad2:value(v:mod(#100))).
    if c < #0 then "-":concat(body) else body }.

padLeft := { text, width | | out |
    out := text.
    while out:size < width do (out := " ":concat(out)).
    out }.

padRight := { text, width | | out |
    out := text.
    while out:size < width do (out := out:concat(" ")).
    out }.

line := { label, amount |
    ("{}{}":fill([padRight:value(label, #24),
                  padLeft:value(format:value(amount), #12)])):display }.

rule := { ("-":concat(padLeft:value("", #35))):display }.

; --------------------------------------------------------------- the report

"LEDGER":display.
rule:value.

subtotal := #0.
i := #1.                            ; Solveig arrays are one-based
while i <= names:size do (
    line:value(names:at(i), amounts:at(i)).
    subtotal := subtotal + amounts:at(i).
    i := i + #1).

rule:value.

interest := percent rate of subtotal.
total := subtotal + interest.
share := total / ways.
effective := ratio interest to subtotal.

line:value("Subtotal", subtotal).
line:value("Interest", interest).
line:value("Total", total).
line:value("Each of four", share).
line:value("Rounding left over", total - share * #400).
line:value("Interest / subtotal", effective).   ; and see README.md: two
                                                ; places is not enough for a
                                                ; rate, and the dialect has one
                                                ; precision to offer
