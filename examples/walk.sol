; walk.sol -- walking a directory tree.
; Run with:  ./bin/solas examples/walk.sol && ./bin/solvm examples/walk.sob
; Or over a directory of your own:  ./bin/solvm examples/walk.sob docs
;
; This is the program that could not be written at all until `system:filesIn`
; existed. Reading a file needed you to know its path already, so a program
; could be told what to work on and could never go and look.

root := system:arguments:size:greaterThan(#0):ifElse(
    { system:arguments:at(#1) },
    { "examples" }).

system:isDirectory(root):ifFalse({
    "{} is not a directory":fill([root]):display.
    system:exit(#1) }).

; ---------------------------------------------------------------------------
; The walk
;
; `filesIn` answers names, not paths, so the caller joins them -- which is one
; `concat` and means the answer is a name you can print without cutting the
; directory off the front again.
;
; Directories are in the answer along with files, because leaving them out would
; make this impossible; `isDirectory` tells them apart.
;
; The order is the directory's, which is to say none worth relying on, so
; anything shown is sorted first.

files := #0.
directories := #0.
bytes := #0.
deepest := #0.

walk := { path, depth |
    depth:greaterThan(deepest):ifTrue({ deepest := depth }).
    system:filesIn(path):sorted:do({ name | | full |
        full := path:concat("/"):concat(name).
        system:isDirectory(full):ifElse({
            directories := directories:add(#1).
            walk:value(full, depth:add(#1)) },
            { files := files:add(#1).
              bytes := bytes:add(system:readFile(full):size) })
    })
}.

; A tree deep enough would run out of frames -- a walk spends a couple per
; level, against the machine's 62 -- so the failure is caught and reported
; rather than being the last thing the program does. See ROADMAP 3.5.
{ walk:value(root, #1) }:onError({ e |
    "stopped walking: {}":fill([e:message]):display }).

"":display.
"{}: {} files in {} directories":fill([root, files, directories]):display.
"{} bytes, deepest {} levels":fill([bytes:asString(","), deepest]):display.

; ---------------------------------------------------------------------------
; What else is out there

; `environment` answers nil when a variable is not set, rather than failing: a
; variable nobody set is a legitimate answer to a legitimate question, the way
; the end of input is.
system:environment("HOME"):isNil:ifElse(
    { "no HOME set":display },
    { "HOME is set":display }).

system:environment("NO_SUCH_VARIABLE_HERE"):isNil:print.     ; true

; ---------------------------------------------------------------------------
; Appending
;
; `writeFile` replaces what is there. A log wants the other one.

note := "build/walk-log.txt".
system:writeFile(note, "walked {}\n":fill([root])).
system:appendFile(note, "{} files\n":fill([files])).
system:appendFile(note, "{} directories\n":fill([directories])).
system:readFile(note):split("\n"):size:sub(#1):print.        ; #3 -- lines
