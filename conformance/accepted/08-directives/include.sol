; conformance: an included file's globals are the including file's globals
; varies: front
;
; There is one flat global namespace and an include puts the file's statements
; into the including file, so a global bound there is bound here. The path is
; relative to the file doing the including.

@include "include-part.sol".
partName:display.
partCount:print.
partCount:add(#1):print.
