; The program built step by step in docs/TUTORIAL.md: a stock report.
; Run with:  ./bin/solas examples/stock.sol && ./bin/solvm examples/stock.sob

; An item is an object with slots. The slots given here are defaults every
; instance sees until it sets its own.
item := object:new.
item:name  := "".
item:price := 0.0.
item:qty   := #0.

; A slot holding a block is a method. `self` is the receiver, and it comes from
; the send. Note the explicit `asFloat`: integers and floats never coerce, so
; the widening is written down.
item:total := { self:price:mul(self:qty:asFloat) }.

; An object is rendered by asking it, so defining `asString` makes `print`,
; `display`, `fill`, and array rendering all show an item this way.
item:asString := { "{} x{} @ {}":fill([self:name, self:qty, self:price]) }.

; A maker, so building one is a single send. `n, p, q` are parameters and `| it |`
; is a temporary -- a name local to this frame.
item:make := { n, p, q |
    | it |
    it := self:new.
    it:name := n. it:price := p. it:qty := q.
    it
}.

stock := [
    item:make("apples",  1.25, #3),
    item:make("pears",   0.5,  #12),
    item:make("quinces", 7.5,  #1)
].

stock:at(#1):print.              ; apples x3 @ 1.25

; ---------------------------------------------------------------------------
; Walking the collection

; `do` runs a block per element. `sum` is a global, so a block may assign it.
sum := 0.0.
stock:do({ e | sum := sum:add(e:total) }).
sum:print.                       ; 17.25

; `collect` answers a new array of the block's answers; `select` keeps the
; elements the block approves of.
stock:collect({ e | e:name }):print.                       ; ["apples", "pears", "quinces"]
stock:select({ e | e:total:greaterThan(5.0) })
     :collect({ e | e:name }):print.                       ; ["pears", "quinces"]

; `sorted` takes a block saying which of two comes first, so a user-defined type
; sorts itself.
stock:sorted({ a, b | a:total:greaterThan(b:total) })
     :collect({ e | e:name }):print.                       ; ["quinces", "pears", "apples"]

; ---------------------------------------------------------------------------
; The report

; A format spec is [align] [','] ['0'] [width] ['.' decimals]. Text aligns left
; and numbers align right, so a column falls out of the widths.
row := { e |
    "{}{}{}":fill([ e:name:asString("<10"),
                    e:qty:asString("5"),
                    e:total:asString(",12.2") ])
}.

"stock report":display.
stock:sorted({ a, b | a:total:greaterThan(b:total) }):do({ e | row:value(e):display }).
"{}{}{}":fill(["total":asString("<10"), "":asString("5"), sum:asString(",12.2")]):display.

; ---------------------------------------------------------------------------
; A kind of item that is sold at a discount

; `new` answers an object delegating to the receiver, so `sale` starts as an
; item and overrides one method. `via` reaches the version it overrides, running
; it with `self` still the discounted item.
sale := item:new.
sale:total := { self:via(item):total:mul(0.9) }.

full     := item:make("quinces", 7.5, #2).
marked   := sale:make("quinces", 7.5, #2).

full:total:print.                ; 15
marked:total:print.              ; 13.5

; It is an item as far as anything else is concerned.
marked:isKindOf(sale):print.     ; true
marked:isKindOf(item):print.     ; true
row:value(marked):display.       ; the same report row works unchanged
