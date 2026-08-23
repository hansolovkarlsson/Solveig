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
; `sqrt`, no `min`, no `max`, and there is still no source of randomness
; anywhere. Every one of them was written here in Solum first, and the square
; root was wrong twice, silently, before a primitive replaced it -- the story is
; in the changelog and the moral is in
; [3.14](../docs/ROADMAP.md#314-there-is-no-source-of-randomness). `sqrt` is now
; a message a float understands and `min`, `max` and `between` are in
; [math.sol](../lib/math.sol); the generator below is still this program's own,
; because randomness is the half of that entry still open.

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
; [3.14](../docs/ROADMAP.md#314-there-is-no-source-of-randomness).

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
; A source of randomness, which is also not there
;
; **There is no random number anywhere in the language**, so this program
; carries a generator. It is Lehmer's, the multiplier is 16807 and the modulus
; 2^31-1, and both numbers are chosen so that the product cannot exceed a signed
; 64-bit integer -- which matters here more than it does elsewhere, because
; **integer arithmetic traps on overflow rather than wrapping**. The usual
; linear congruential generator relies on the wrap, so the usual one cannot be
; written in this language at all. That is not a complaint about the trap, which
; is right; it is a note that "write your own" is narrower advice than it sounds.
;
; The seed is the clock, and the clock's epoch is deliberately unspecified --
; monotonic seconds from somewhere. Multiplied out to microseconds it is as good
; a seed as this needs, and it is the only entropy a Solum program can reach.

seed := system:clock:mul(1000000.0):truncated:mod(#2147483646):inc.

random := {
    seed := seed:mul(#16807):mod(#2147483647).
    seed }.

; A number in `[#1, n]`. The modulo bias is real and is about one part in a
; hundred thousand here, which is far below the noise in anything being timed.
randomUpTo := { n | random:value:mod(n):inc }.

; ---------------------------------------------------------------------------
; The measurement
;
; `capture` rather than `run`, so that whatever is being timed cannot write over
; the report. What is measured is therefore a fork, an exec, a pipe and a wait,
; which is what any harness outside the process measures and is the reason a
; benchmark of something under a millisecond belongs inside the process instead
; (`{ ... }:timeToRun(#n)` is that, and is cheaper by four orders of magnitude).

; **A child's streams cannot be redirected**, and that shapes this. `run` shares
; both of them and `capture` keeps stdout, so a command that complains on stderr
; writes over the report and there is no message that stops it. The way round is
; `/bin/sh -c '"$@" 2>/dev/null' sh ...`, and a benchmark harness is the one
; program that cannot pay for it: a shell is another fork and another exec on
; every measurement, of the same order as the thing being measured. So the array
; form is used, the number is the command, and a noisy command prints above the
; report. See ROADMAP 3.15.

failures := #0.
lastStatus := #0.

timeOnce := { argv | | start, result, elapsed |
    start := system:clock.
    result := system:capture(argv).
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
    randomUpTo:value(#2):equals(#1):ifElse(
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
    xs:size:repeat({ out:add(xs:at(randomUpTo:value(xs:size))) }).
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
