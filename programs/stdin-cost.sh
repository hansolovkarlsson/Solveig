#!/bin/sh
#
# stdin-cost.sh -- what the two ways of reading standard input cost.
#
#     sh programs/stdin-cost.sh              # about 600 KB
#     sh programs/stdin-cost.sh 40000        # a bigger sample
#
# **This backs [6.43](../docs/ROADMAP.md#643-a-program-cannot-read-standard-input-whole-and-the-call-that-looks-as-though-it-can-answers-)**,
# which states a ratio and a nanosecond figure, and it is here because that
# entry is a document and
# [method.md](../docs/method.md#and-a-comparison-whose-two-sides-did-not-run-alike-is-not-one-either)
# says a throwaway that measures something the documents will state is a check.
# It was a throwaway on 2026-09-02 and the numbers went into the entry; this is
# the rest of paying for that.
#
# ---------------------------------------------------------------------------
# What the two ways are, and why a program may not simply take the fast one
#
#   readLine   a line at a time, **without its terminator**, folding `\r\n`
#              into one. Fast, and it cannot say whether the last line ended
#              with a newline -- so `diff` cannot use it, since that is the one
#              thing `\ No newline at end of file` reports -- and it silently
#              rewrites a file written on another system, which is why `sort`
#              cannot use it either.
#
#   readKey    a byte at a time. Exact, and the price is what this measures.
#
# **And the third way does not work.** `readFile("/dev/stdin")` reads a
# redirect and answers `""` on a **pipe**, silently: the size comes from a seek
# that a pipe refuses, and a failed seek is indistinguishable from an empty
# file. That is the defect half of 6.43 and this script demonstrates it rather
# than describing it.
#
# One harness, both sides, the same bytes, in one run -- which is the rule the
# `tail -f` measurement on 2026-09-01 was written to obey after breaking it.

set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

lines=${1:-20000}

if [ ! -f "$root/bin/solvm" ] || [ ! -f "$root/bin/solas" ]; then
    echo "build first:  make"
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/read.sol" <<'EOF'
; How long does standard input take, a line at a time against a byte at a time?
; The two are the same program bar the message, so that nothing but the message
; is being compared.
mode := system:arguments:at(#1).
units := #0.
took := { mode:equals("key"):ifElse(
    { | c, parts |
      parts := array:new.
      c := system:readKey.
      { c:notNil }:whileTrue({ parts:add(c). units := units:inc. c := system:readKey }).
      parts:join("") },
    { | line, parts |
      parts := array:new.
      line := system:readLine.
      { line:notNil }:whileTrue({ parts:add(line). units := units:inc.
                                  line := system:readLine }).
      parts:join("\n") }) }:timeToRun.
system:writeError("{} {} {}\n":fill([mode, units, took:asString("0.6")])).
EOF

cat > "$work/whole.sol" <<'EOF'
; The shortcut that is not one.
{ system:readFile("/dev/stdin"):size:print }
    :onError({ e | "refused: ":concat(e:message):display }).
EOF

"$root/bin/solas" -o "$work/read.sob" "$work/read.sol" > /dev/null || exit 1
"$root/bin/solas" -o "$work/whole.sob" "$work/whole.sol" > /dev/null || exit 1

python3 - "$work/in.txt" "$lines" <<'PY'
import sys
path, n = sys.argv[1], int(sys.argv[2])
open(path, 'w').write(''.join('line %d with some text on it\n' % i for i in range(n)))
PY

bytes=$(wc -c < "$work/in.txt" | tr -d ' ')

echo
echo "$bytes bytes of standard input"
echo

for mode in line key; do
    "$root/bin/solvm" "$work/read.sob" "$mode" < "$work/in.txt" 2> "$work/r.$mode" > /dev/null
done

python3 - "$work/r.line" "$work/r.key" "$bytes" <<'PY'
import sys
line = open(sys.argv[1]).read().split()
key = open(sys.argv[2]).read().split()
n = int(sys.argv[3])
lt, kt = float(line[2]), float(key[2])
mb = n / 1048576.0
print("  readLine  %8s lines  %8.4f s  %7.1f MB/s" % (line[1], lt, mb / lt))
print("  readKey   %8s bytes  %8.4f s  %7.1f MB/s,  %.0f ns a byte"
      % (key[1], kt, mb / kt, kt * 1e9 / n))
print()
print("  the exact route costs %.0fx the fast one." % (kt / lt))
PY

echo
echo "and readFile(\"/dev/stdin\"):"
printf '  from a redirect:  '
"$root/bin/solvm" "$work/whole.sob" < "$work/in.txt"
printf '  from a pipe:      '
cat "$work/in.txt" | "$root/bin/solvm" "$work/whole.sob"
echo
echo "  A pipe answers \"\" -- neither the contents nor an error. That is 6.43."
