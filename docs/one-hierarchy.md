# One hierarchy: everything is an object

*Why a method added to `object` is answered by a number, where a value is still
not an object, and the one place that difference shows. Every snippet here has
been run; the outputs are what the VM actually prints.*

For the design history — why this was long believed to need the class-side /
instance-side split, and did not — see
[class-and-instance.md](class-and-instance.md#the-single-root--done-and-it-was-not-gated-by-this).
For the messages themselves see [REFERENCE.md](REFERENCE.md#objects).

---

## The chain ends at object

Every built-in class delegates to `object`. It is ten lines in `builtins.c`:

```c
vm->integer_class->proto = vm->object_class;
vm->float_class->proto   = vm->object_class;
vm->nil_class->proto     = vm->object_class;
vm->bool_class->proto    = vm->object_class;
vm->block_class->proto   = vm->object_class;
vm->array_class->proto   = vm->object_class;
vm->dict_class->proto    = vm->object_class;
vm->time_class->proto    = vm->object_class;
vm->string_class->proto  = vm->object_class;
vm->symbol_class->proto  = vm->object_class;
```

`error` gets it at birth, being made with `sol_object_new(vm, vm->object_class)`.
`object` itself has no prototype: the chain has to end somewhere, and this is
where.

```
#45:isKindOf(object):print.            ; true
"s":isKindOf(object):print.            ; true
integer:parent:equals(object):print.   ; true
object:parent:print.                   ; nil   -- the chain ends here
```

So "everything is an object" is true of the type graph and not only of the
slogan.

## One definition, every receiver

That is what the root is *for*. A method bound on `object` is found from
anything:

```
object:describe := { "understood by ":concat(self:asString) }.
```

```
#45:describe:display.               ; understood by 45
1.5:describe:display.               ; understood by 1.5
"s":describe:display.               ; understood by s
'sym:describe:display.              ; understood by sym
true:describe:display.              ; understood by true
nil:describe:display.               ; understood by nil
[#1, #2]:describe:display.          ; understood by [#1, #2]
{ #1 }:describe:display.            ; understood by <block>
dictionary:new:describe:display.    ; understood by <dictionary>
system:time:describe:display.       ; understood by 2026-08-21T18:26:14Z
error:new:describe:display.         ; understood by <object 0x102dfa500>
```

One definition, eleven kinds of receiver. Reflection walks the same chain, so it
agrees:

```
#45:respondsTo('describe):print.   ; true
#45:isKindOf(integer):print.       ; true
#45:isKindOf(object):print.        ; true
#45:isKindOf(string):print.        ; false
```

The nearest slot still wins, exactly as it does anywhere else in a delegation
chain — the root is the end of the search, not a special case in it:

```
object:describe  := { "some value" }.
integer:describe := { "a number" }.

#45:describe:display.        ; a number
"s":describe:display.        ; some value
```

## A value is a kind of object, and is not an object

This is the distinction to hold on to. Delegating to `object` gives a value the
*behaviour*; it does not give it the *storage*.

```
#45:parent.
solvm: 'parent' expects an object, got integer

#45:via(object).
solvm: 'via' expects an object, got integer

#45:x := #1.
solvm: cannot bind 'x' on integer
```

`#45` is an immediate — a tagged word, not a heap object with a slot table.
There is nowhere to put a slot, so it cannot carry state of its own, cannot be
re-parented, and cannot be subclassed: an unboxed number's class is chosen by its
type tag, and there is nowhere to record a different one.

| | a value: `#45`, `"s"`, `true` | an object: `object:new` |
| --- | --- | --- |
| answers methods bound on `object` | yes | yes |
| `isKindOf(object)` | true | true |
| slots of its own | **no** | yes |
| `parent`, `via` | **refused** | answered |
| what `new` on its class does | refuses, and says what to write | makes one |

## Why this was safe to do

The two capabilities a value cannot honour were already refused before the root
existed, which is the whole reason ten lines were enough.

`via` and `parent` are the only two messages `integer` does not define for
itself, and both are installed as `instance(vm->object_class, SOL_OBJ, ...)` —
the receiver requirement refuses anything that is not an object. That check went
in with 1.6, three commits before anyone thought about a root.

The other worry was `new`. A built-in inheriting `object:new` would answer a
plain object delegating to the class — for `string`, a thing that refuses every
message a string understands. `integer`, `float` and `array` already shadowed it;
the four left now refuse and teach:

```
integer:new(#45).
solvm: an integer is written #45, and there is nothing for 'new' to make -- #0 is the empty one

symbol:new.
solvm: a symbol is written 'name, or made from a string with asSymbol -- not with 'new'

block:new.
solvm: a block is written { ... } and compiled -- there is nothing for 'new' to make

boolean:new.
solvm: there are only two booleans, true and false -- 'new' makes neither
```

The rule underneath: **`new` means "make an object delegating to me", and those
classes have instances that are not objects delegating to them.**

## The one place the difference shows

Override on a value class a method that `object` defines, and the override
cannot call the one it displaced — because reaching past a nearer slot is
`via`'s job, and `via` wants an object:

```
object:describe  := { "some value" }.
integer:describe := { "a number, and then ":concat(self:via(object):describe) }.

#45:describe.
solvm: 'via' expects an object, got integer
```

[`boundTo`](fetched-methods.md) is the way through. It supplies a receiver to an
already-fetched method rather than searching from one, so it takes a value
happily:

```
object:slotAt('describe):boundTo(#45):value:display.    ; some value
```

That asymmetry is a leftover rather than a design: `via` was written to refuse
non-objects back when a value's chain ended at its own class, and now that every
class delegates to `object` a value *has* a well-defined chain to walk. Recorded
as a loose end in [2.14](ROADMAP.md#214-loose-ends-from-the-decided-items).

## What it quietly removed

[ideas.md](ideas.md#already-there-or-already-writable) used to carry this, to put
one `caseOf` on numbers as well as objects:

```
integer:caseOf := object:slotAt('caseOf).
```

It has not been needed since the root: a method on `object` is found from a
number like anything else. The single root took a paragraph of cleverness and
made it unnecessary, which is the better outcome.

## What it costs

The **miss** path only, and only because a failed lookup now walks object's
slots before giving up: 200,000 failed lookups cost about 10% more. A send that
hits is unchanged, and the path that got slower is the one that ends in *does not
understand*.
