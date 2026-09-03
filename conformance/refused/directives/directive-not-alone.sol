; conformance: a directive must stand alone as a statement
; varies: front
; refused: directives/directive-not-alone
;
; A directive is not an expression, so it cannot be the right-hand side of a
; binding. It is refused at the point the '@' appears rather than after the file
; has been looked for, which is why this case names no file that exists.

x := @include "nowhere.sol".
