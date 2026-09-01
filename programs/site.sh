#!/bin/sh
#
# site.sh -- the published pages against the markdown they were built from.
#
# **Every check in this repository reads the file. GitHub Pages renders it, and
# nothing compared the two.** On 2026-09-01 the difference was 263 headings on
# one page, standing since 0.20.0 -- ten days and twenty releases -- while every
# `make test` passed, because every check reads the file. ROADMAP 3.23.
#
# Three comparisons over one fetch, and each is a fault class that has actually
# happened here rather than one that might:
#
#   headings   how many the page rendered, against how many the source has
#              outside fenced blocks. `CHANGELOG.md` had a paragraph wrapped so
#              that ``` began a line -- a code fence -- and an inline code span
#              wrapped so that `<if-statement>` began one, which kramdown reads
#              as raw HTML and which stops rendering to the end of the file. The
#              fault class *is* "a heading stopped being a heading", so counting
#              headings is not a proxy for it.
#
#   baseurl    every site-absolute link, against the base the site is served
#              from. A markdown link whose *text wraps across a line* loses the
#              baseurl when Jekyll rewrites its `.md` target to `.html`: eleven
#              of them were writing `/docs/X.html` instead of `/Solveig/docs/X.html`,
#              and every one was a 404 on a page that reads correctly as markdown.
#
#   anchors    every internal `#link`, against the `id=` attributes the renderer
#              actually emitted. The same question expect.sol answers locally,
#              asked of the artefact a reader touches.
#
# **It reads the source from `origin/main`, not from the working tree**, which is
# the one thing that stops it being noise: the site renders what was pushed, so a
# published page held against a local file reports every unpushed edit as a
# fault. HEAD is compared against the ref and the difference said out loud.
#
# **Not in `make test`, and it must stay out.** The suite is offline and
# dependency-free; a check that fails on a train is not a check. This is the
# shape the oracles already have -- run on demand, needing something the machine
# happens to have.
#
#   SOURCE_REF   what the site is built from; origin/main by default.
#   SITE         the base URL; built from _config.yml by default.
#
# `README.md` is not checked because the site does not publish it. `index.md` is
# the front page and its URL is the bare base.

set -u

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 1

ref=${SOURCE_REF:-origin/main}

url=$(sed -n 's/^url: *//p' _config.yml | head -1)
base=$(sed -n 's/^baseurl: *//p' _config.yml | head -1)
site=${SITE:-$url$base}

if ! git rev-parse --verify --quiet "$ref" >/dev/null; then
    echo "no such ref: $ref -- fetch first, or set SOURCE_REF"
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
: > "$work/map"

echo
echo "$site against $ref"

# Said out loud rather than guessed at: a page cannot render a commit that has
# not been pushed, so a difference here explains a difference below.
if [ "$(git rev-parse HEAD)" != "$(git rev-parse "$ref")" ]; then
    ahead=$(git rev-list --count "$ref"..HEAD 2>/dev/null || echo '?')
    echo "  note: HEAD is $ahead commit(s) ahead of $ref; the site cannot show them"
fi

# And the tree, which is the easier one to be caught by: a fix made and not
# committed leaves the fault standing here, correctly, and it reads as though
# the fix did not work.
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "  note: the working tree has uncommitted changes; this reads $ref"
fi
echo

# Headings in the source, outside fenced blocks -- the rule expect.sol keeps: a
# fence opens on a line starting ``` and closes only on a bare one.
source_headings() {
    awk '
        { line = $0; sub(/^[ \t]+/, "", line) }
        line ~ /^```/ {
            if (!fence) fence = 1
            else if (line == "```") fence = 0
            next
        }
        !fence && /^#{1,6} / { n++ }
        END { print n + 0 }'
}

pages=$(git ls-tree --name-only "$ref" docs/ | grep '\.md$')
pages="$pages
index.md"

faults=0
fetched=0
headings=0

for page in $pages; do
    case "$page" in
        index.md) path="$base/" ;;
        *)        path="$base/${page%.md}.html" ;;
    esac

    out="$work/$(echo "$page" | tr / _).html"
    if ! curl -sfL "$site${path#$base}" -o "$out"; then
        printf '  FETCH     %-30s %s\n' "$page" "$site${path#$base}"
        faults=$((faults + 1))
        continue
    fi
    fetched=$((fetched + 1))
    printf '%s\t%s\t%s\n' "$path" "$out" "$page" >> "$work/map"

    want=$(git show "$ref:$page" | source_headings)
    got=$(grep -o '<h[1-6][ >]' "$out" | wc -l | tr -d ' ')
    headings=$((headings + want))

    if [ "$got" -lt "$want" ]; then
        printf '  LOST      %-30s %s of %s headings rendered\n' "$page" "$got" "$want"
        faults=$((faults + 1))
    elif [ "$got" -ne "$want" ]; then
        printf '  extra     %-30s %s rendered, %s in the source\n' "$page" "$got" "$want"
    fi
done

# The links, in one pass: the map first, then every page. Ids and hrefs are
# collected as they are seen and resolved at the end, because a link may point
# at a page that has not been read yet.
if [ "$fetched" -gt 0 ]; then
    awk -v base="$base" -v mapfile="$work/map" '
        FILENAME == mapfile {
            local[$1] = $2; name[$2] = $3
            if ($1 ~ /\/$/) local[$1 "index.html"] = $2
            next
        }
        {
            s = $0
            while (match(s, /id="[^"]*"/)) {
                ids[FILENAME SUBSEP substr(s, RSTART + 4, RLENGTH - 5)] = 1
                s = substr(s, RSTART + RLENGTH)
            }
            s = $0
            while (match(s, /href="[^"]*"/)) {
                href[++n] = FILENAME SUBSEP substr(s, RSTART + 6, RLENGTH - 7)
                s = substr(s, RSTART + RLENGTH)
            }
        }
        END {
            for (i = 1; i <= n; i++) {
                split(href[i], part, SUBSEP)
                from = part[1]; link = part[2]

                if (link ~ /^(https?:|mailto:)/) continue
                if (link !~ /#/) continue

                at = index(link, "#")
                path = substr(link, 1, at - 1)
                frag = substr(link, at + 1)

                if (path == "") { target = from }
                else {
                    if (substr(path, 1, 1) != "/") continue      # not ours to resolve
                    if (index(path, base "/") != 1) {
                        printf "  NO BASE   %-30s %s\n", name[from], link
                        bad++
                        continue
                    }
                    if (!(path in local)) continue               # not a page we read
                    target = local[path]
                }

                total++
                if (!((target SUBSEP frag) in ids)) {
                    printf "  DEAD      %-30s %s\n", name[from], link
                    bad++
                }
            }
            printf "%d %d\n", total, bad + 0 > "/dev/stderr"
        }
    ' "$work/map" $(cut -f2 "$work/map") 2> "$work/links"
fi

read -r links bad < "$work/links" 2>/dev/null || { links=0; bad=0; }
faults=$((faults + bad))

echo
if [ "$faults" -eq 0 ]; then
    echo "$fetched pages, $headings headings, $links internal links: nothing to look at."
    exit 0
fi
echo "$faults to look at, over $fetched pages."
exit 1
