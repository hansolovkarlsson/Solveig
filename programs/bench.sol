; bench.sol -- how long does it take, and is the difference real?
;
; Run with:  ./bin/solas programs/bench.sol && ./bin/solvm programs/bench.sob
; Timing one command:  ./bin/solvm programs/bench.sob 20 ls -l
; Comparing two:       ./bin/solvm programs/bench.sob 20 ls -l -- ls -R
;
; The tenth program here, and the first written to press on a specific gap
; rather than to do a job that happened to need one. This repository has been
; quoting timings for six releases -- 40.5us to build a machine, 121us for a
; request, 279us to compile a chunk -- and every one of them was taken by hand,
; once, and reported as a number. A number taken once is a sample of one.
;
; So: run a command n times, and say what the distribution looks like. Then run
; two commands and say whether the difference between them is real, which is a
; harder question and the one that actually gets asked.
;
; **What it found is that the arithmetic was not there.** Not the language's
; shape, which took all of this without complaint -- the *messages*. There was no
; `sqrt`, no `min`, no `max` and no source of randomness anywhere. Every one of
; them was written here in Solum first, and the square root was wrong twice,
; silently, before a primitive replaced it -- the story is in the changelog and
; the moral is in
; [3.14](../docs/COMPLETED.md#314-the-mathematics-that-is-not-here--done). All four are
; the language's now: `sqrt` is a message a float understands, `min`, `max` and
; `between` are in [math.sol](../lib/math.sol), and the generator this file
; carried is `random:new` -- which was built because measuring the one here
; found what was wrong with it.

; `min`, `max` and `between`, which this program wrote out longhand and which
; now live where the next program can have them too.
@include "math.sol".

; ---------------------------------------------------------------------------
; What was asked for
;
; `20 cmd args...`, or `20 cmd args -- other cmd args`. The separator is `--`
; because that is what every other tool uses for it, and a benchmark harness is
; the wrong place to be inventive about argument syntax.

usage := {
    "usage: bench <runs> <command> [args...] [-- <command> [args...]]":display.
    system:exit(#1) }.

; **With no arguments it benchmarks something it supplies itself**, which is the
; convention every program here follows -- one you have to feed before it will
; say anything is one you will not run. What it picks is the cheapest real run
; of the machine there is, `solvm --version`, so the number it prints is what
; starting this language costs: a fork, an exec, the dynamic loader, and a VM
; built and thrown away.
given := system:arguments:size:equals(#0):ifElse(
    { "":display.
      "no command given, so: 20 runs of the cheapest thing the VM does":display.
      ["20", "./bin/solvm", "--version"] },
    { system:arguments }).

given:size:lessThan(#2):ifTrue({ usage:value }).

runs := given:at(#1):asInteger.
runs:lessThan(#3):ifTrue({
    "a distribution needs at least three runs, got {}":fill([runs]):display.
    system:exit(#1) }).

; Splitting on `--`. `indexOf` answers where it is or nil, which is exactly the
; two cases, so no counting is needed.
rest := given:copyFrom(#2, given:size).
cut := rest:indexOf("--").

first := cut:isNil:ifElse({ rest }, { rest:copyFrom(#1, cut:dec) }).
second := cut:isNil:ifElse({ nil }, { rest:copyFrom(cut:inc, rest:size) }).

first:size:equals(#0):ifTrue({ usage:value }).
second:notNil:and({ second:size:equals(#0) }):ifTrue({ usage:value }).

; ---------------------------------------------------------------------------
; The statistics
;
; What is left here after `sqrt`, `min` and `max` went into the language and
; into math.sol: three functions that are this tool's own business rather than
; anything a language owes a program. A mean, a sample standard deviation and a
; quantile belong to the thing doing statistics.
;
; **The square root that used to be here was wrong twice.** First as twenty
; fixed iterations of Newton's method -- right to twelve places at 2 and wrong in
; the fourth digit at 1e10, because quadratic convergence is what happens once
; the guess is near and from `x` itself the approach is one halving per octave.
; Then, corrected, as a loop running until the answer stopped moving with a cap
; of sixty steps to stop it oscillating -- which returned `x` divided by 2^60 for
; anything above about 1e21, so `sqrt(1e300)` answered 8.67e281 rather than
; 1e150. Nineteen orders of magnitude, silently, from the version written to fix
; the first mistake. Neither was caught by testing; both were caught by
; comparing against something that already knew the answer.
;
; That is why `sqrt` is a primitive now and not a library method. See
; [3.14](../docs/COMPLETED.md#314-the-mathematics-that-is-not-here--done).

mean := { xs |
    xs:inject(0.0, { total, x | total:add(x) }):div(xs:size:asFloat) }.

; The sample standard deviation, n-1 in the denominator because these are runs
; drawn from the population of runs that could have happened rather than the
; whole of it.
stddev := { xs | | m, ss |
    m := mean:value(xs).
    ss := xs:inject(0.0, { total, x | | d | d := x:sub(m). total:add(d:mul(d)) }).
    ss:div(xs:size:dec:asFloat):sqrt }.

; A quantile by nearest rank, on an array already sorted. Nearest rank rather
; than interpolating, because at twenty runs the interpolation would be
; inventing precision the sample does not have.
quantile := { sorted, p | | i |
    i := p:mul(sorted:size:dec:asFloat):rounded:inc.
    sorted:at(i:max(#1)) }.

; ---------------------------------------------------------------------------
; A source of randomness, which this program asked for and now has
;
; This carried its own generator for four releases -- Lehmer's, multiplier
; 16807 and modulus 2^31-1, chosen so the product could not exceed a signed
; 64-bit integer, because **integer arithmetic traps on overflow rather than
; wrapping** and the textbook generator relies on the wrap. That is not a
; complaint about the trap, which is right. It is that "write your own" was
; narrower advice than it sounded, and measuring the thing it produced is what
; closed the half of 3.14 that was open.
;
; **The generator was fine and the seeding was not.** The clock was the only
; entropy a Solum program could reach, so two runs a microsecond apart got
; consecutive seeds -- and the first coin flip was then exactly the parity of
; the start time, while the first resample index of 21 took three values out of
; 21, forever. Neither shows in the output. `random:new` is seeded by the
; machine and mixes what it is given, and the same measurement now finds all 21.

dice := random:new.

; ---------------------------------------------------------------------------
; The measurement
;
; `capture` rather than `run`, so that whatever is being timed cannot write over
; the report. What is measured is therefore a fork, an exec, a pipe and a wait,
; which is what any harness outside the process measures and is the reason a
; benchmark of something under a millisecond belongs inside the process instead
; (`{ ... }:timeToRun(#n)` is that, and is cheaper by four orders of magnitude).

; **The child's stderr is discarded**, and this program is the reason that is
; possible. `capture` keeps stdout, so what was left was a command that
; complains on stderr writing straight over the report, with no message that
; stopped it. The way round was `/bin/sh -c '"$@" 2>/dev/null' sh ...`, and a
; benchmark harness is the one program that cannot pay for it: a shell is
; another fork and another exec on every measurement, of the same order as the
; thing being measured. `["stderr", 'discard]` is that redirection without the
; shell, and it closed ROADMAP 3.15.
;
; The noise goes; the *failure* does not. A command that writes to stderr and
; works is quiet now, and a command that fails is still counted below, because
; what says it failed is the status and never the noise.

quiet := ["stderr", 'discard].

failures := #0.
lastStatus := #0.

timeOnce := { argv | | start, result, elapsed |
    start := system:clock.
    result := system:capture(argv, quiet).
    elapsed := system:clock:sub(start).
    ; The status, always. tools.sol learned this the other way round: reading a
    ; command's output without looking at whether it worked is how a report says
    ; "0 files" when what happened is that `find` is not installed. Here it is
    ; worse than wrong -- a command that fails immediately is *fast*, so a
    ; failing command benchmarks beautifully.
    lastStatus := result:at("status").
    lastStatus:equals(#0):ifFalse({ failures := failures:inc }).
    elapsed }.

; One run thrown away before any are kept, and inspected before any are taken.
; The first run of anything pays for the page cache, the dynamic loader and
; whatever the filesystem had not read yet, and including it makes the maximum a
; story about the first run rather than about the command.
warmUp := { argv |
    timeOnce:value(argv).
    lastStatus:equals(#127):ifTrue({
        "no such command: {}":fill([argv:at(#1)]):display.
        system:exit(#1) }).
    ; The warm-up is not one of the runs, so it is not one of the failures
    ; either -- a count of six out of five is the kind of small wrongness that
    ; makes a reader doubt the rest of the report.
    failures := #0 }.

; ---------------------------------------------------------------------------
; Reporting

ms := { seconds | seconds:mul(1000.0) }.

report := { label, xs | | sorted |
    sorted := xs:sorted.
    "":display.
    "{}":fill([label]):display.
    "  runs     {}":fill([xs:size]):display.
    "  min      {} ms":fill([ms:value(sorted:min):asString("8.3")]):display.
    "  median   {} ms":fill([ms:value(quantile:value(sorted, 0.5)):asString("8.3")]):display.
    "  p90      {} ms":fill([ms:value(quantile:value(sorted, 0.9)):asString("8.3")]):display.
    "  max      {} ms":fill([ms:value(sorted:max):asString("8.3")]):display.
    "  mean     {} ms  +/- {}":fill([
        ms:value(mean:value(xs)):asString("8.3"),
        ms:value(stddev:value(xs)):asString("0.3")]):display }.

; Said once at the end rather than at each run, because a command that fails
; every time would otherwise bury its own report.
warnFailures := {
    failures:greaterThan(#0):ifTrue({
        "":display.
        "  {} of the runs ended non-zero -- a command that fails is fast":fill(
            [failures]):display }) }.

; ---------------------------------------------------------------------------
; One command

second:isNil:ifTrue({
    | times |
    warmUp:value(first).
    times := [].
    runs:repeat({ times:add(timeOnce:value(first)) }).
    report:value(first:join(" "), times).
    warnFailures:value.
    "":display.
    system:exit(#0) }).

; ---------------------------------------------------------------------------
; Two commands, and whether the difference is real
;
; **Interleaved, and which goes first is a coin flip.** A machine gets slower
; and faster over the course of a minute -- another process starts, the CPU
; warms and throttles -- so timing all of A and then all of B measures the
; minute as much as it measures the commands. Alternating strictly is better and
; is still a pattern; if anything on the machine has a period of two runs, a
; strict alternation lines up with it exactly. So the coin.

timesA := [].
timesB := [].

warmUp:value(first).
warmUp:value(second).

runs:repeat({
    dice:upTo(#2):equals(#1):ifElse(
        { timesA:add(timeOnce:value(first)).
          timesB:add(timeOnce:value(second)) },
        { timesB:add(timeOnce:value(second)).
          timesA:add(timeOnce:value(first)) }) }).

report:value("A:  ":concat(first:join(" ")), timesA).
report:value("B:  ":concat(second:join(" ")), timesB).
warnFailures:value.

; ---------------------------------------------------------------------------
; The bootstrap
;
; The question is not "which median was smaller", which is arithmetic, but
; "would it be smaller again", which is not. Timings are skewed -- bounded below
; by the work and unbounded above by whatever else the machine did -- so the
; tests that assume a normal distribution do not apply, and the honest answer is
; to resample.
;
; Two thousand times: draw n runs from A with replacement and n from B, take
; each median, keep the ratio. The 2.5th and 97.5th percentiles of those ratios
; are a 95% interval. If the interval contains 1.0, the difference is not
; distinguishable from the noise at this many runs, and the right response is
; more runs rather than a bolder claim.

resample := { xs | | out |
    out := [].
    xs:size:repeat({ out:add(xs:at(dice:upTo(xs:size))) }).
    out }.

medianOf := { xs | quantile:value(xs:sorted, 0.5) }.

ratios := [].
#2000:repeat({
    ratios:add(medianOf:value(resample:value(timesA))
                   :div(medianOf:value(resample:value(timesB)))) }).

ratios := ratios:sorted.

low := quantile:value(ratios, 0.025).
high := quantile:value(ratios, 0.975).
point := medianOf:value(timesA):div(medianOf:value(timesB)).

"":display.
"A / B    {} times, 95% interval {} to {}":fill([
    point:asString("0.3"), low:asString("0.3"), high:asString("0.3")]):display.

1.0:between(low, high):ifElse(
    { "         the interval contains 1, so this many runs cannot tell them apart":display },
    { point:lessThan(1.0):ifElse(
        { "         A is faster":display },
        { "         B is faster":display }) }).
"":display.
