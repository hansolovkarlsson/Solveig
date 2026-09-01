; asm.pro -- ARM64 as something you can write down.
;
; A dialect, so directives and nothing else. Every form here appends one line to
; the global `out`, which the compiler prints when it is done.
;
; The connectives -- `from`, `imm`, `slot`, `ifzero` -- are there because **a
; pattern's literal parts are names**, so `mov x0, x1` is not a form anybody can
; declare: `,` is not a name. That was the first prediction in README.md and it
; was right within a minute of trying. The workaround reads well enough that it
; is not obviously a workaround, which is its own finding.
;
; Where several holes are the same kind of thing and no word separates them, the
; call shape is the right one -- `binop(op, d, a, b)` and not a pattern with four
; holes in a row, which is banned for the reason two in a row are. The two shapes
; turn out to divide by *what the form is*, not by taste: a pattern for something
; that reads as a step, a call for something that reads as an application.
;
; **And getting that wrong is silent until it runs.** A pattern where a call was
; meant still parses; its trailing hole simply takes what came after it. `emit`
; was declared wrongly here and `at`, `eat`, `skip` and `take` were declared
; wrongly in programs/grammar -- twice, in two programs, by the author of the
; sentence above. The instruction forms below are steps and are patterns, and
; their trailing holes end at the `.` that ends the statement.

@use "../../lib/arith.pro".

; A call and not a pattern, because its answer gets used -- `load <d> adr <s>`
; below wanted to chain two of them. A pattern's trailing hole would have taken
; the `:add` that followed; a call's parentheses end it. See the note there.
@syntax emit(s)               => out:add(s).

@syntax comment <s>           => emit("; {}":fill([s])).
@syntax blank                 => emit("").

; Labels are numbered rather than named. A compiler that wanted readable labels
; would pass a string here and nothing else would change.
@syntax label <n>             => emit("L{}:":fill([n])).
@syntax goto <n>              => emit("    b L{}":fill([n])).
@syntax goto <n> ifzero <r>   => emit("    cbz {}, L{}":fill([r, n])).

@syntax load <d> imm <n>      => emit("    mov {}, #{}":fill([d, n])).
; Two lines, so the template is a group.
;
; The first draft chained -- `emit(A):add(emit(B))` -- and put the `:add` inside
; the hole rather than after the form, because `emit` was declared as a pattern
; and a pattern's trailing hole takes an expression, which a postfix send
; continues. That was written up as a limitation of Proto and it is not one:
; **`emit` is an application and should have been a call**, which is what it is
; now, and a call's parentheses end it. A group is still clearer than a chain
; for two instructions, so the group stays -- but it stays by choice.
@syntax load <d> adr <s>      => (emit("    adrp {}, {}@PAGE":fill([d, s])).
                                  emit("    add {}, {}, {}@PAGEOFF":fill([d, d, s]))).

; Locals live below the frame pointer, eight bytes each, one-based.
@syntax load <d> slot <n>     => emit("    ldr {}, [x29, #-{}]":fill([d, n:mul(#8)])).
@syntax store <s> slot <n>    => emit("    str {}, [x29, #-{}]":fill([s, n:mul(#8)])).

; The expression stack is the machine stack, sixteen bytes a slot because that
; is what ARM64 wants it aligned to.
@syntax push <r>              => emit("    str {}, [sp, #-16]!":fill([r])).
@syntax pop <r>               => emit("    ldr {}, [sp], #16":fill([r])).

@syntax binop(op, d, a, b)    => emit("    {} {}, {}, {}":fill([op, d, a, b])).
@syntax compare <a> with <b>  => emit("    cmp {}, {}":fill([a, b])).
@syntax set <d> when <cond>   => emit("    cset {}, {}":fill([d, cond])).

@syntax call <name>           => emit("    bl {}":fill([name])).
