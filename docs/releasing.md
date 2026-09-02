# Making a release

*How a feature ships, and the checks a claim has to pass before it is believed,
are in [method.md](method.md). This is the release itself.*

Four files in one commit, a tag, and a page on GitHub that the tree cannot
record. Written down because it is a ritual with verification steps in it, and
because three of those steps were learned by getting them wrong.

## First, look at what the release adds

```sh
git diff --name-status vX.Y.Z..HEAD    # the release before this one
```

**Read the list.** It is the only view here that asks what a stretch of work
*added* to the tree, and every other check answers a different question:
[expect.sol](../programs/expect.sol) counts files of a kind, the link checker
walks markdown, [site.sh](../programs/site.sh) reads published pages, and `make
test` compiles what the `Makefile` names.

It is here because of `programs/:=` — 117 kilobytes, byte-identical to
`pascal.sol`, committed by accident on 2026-08-31 and found on 2026-09-02 with
one command, having survived two days and fifty-four commits inside a directory
four checks inspect. **`make dist` archives `HEAD`**, so a stray in the tree is
a stray in the tarball.
[method.md](method.md#and-every-check-here-enumerates-by-extension) has the
rule.

## The four files, in one commit titled `Release X.Y.Z`

| | |
| --- | --- |
| `solum/include/solum/common.h` | `SOLUM_VERSION`. All four binaries report it, and `make dist` names the tarball from it |
| `README.md` | a new Status paragraph *above* the previous one; the old ones stay |
| `docs/CHANGELOG.md` | a `## X.Y.Z — DATE` heading above the loose entries that accumulated since the last one |
| `index.md` | its Status block, since 0.39.0 — it had said **0.3.0** for thirty-five releases because nothing pointed at it |

The loose entries below the heading keep their own commit hashes and dates. The
release heading is a summary of them, not a replacement.

## Verify compatibility rather than asserting it

Every release since 0.36.0 has, and it is the part of the notes a reader cannot
check for themselves — which makes it the part most worth checking.

```sh
git archive vX.Y.Z | tar -x -C /tmp/prev     # the release before this one
( cd /tmp/prev && make )
```

Then compile every example with both compilers and compare the bytes, and run
each `.sob` on both machines both ways round.

**Run both machines from the same working directory.** Four examples read the
filesystem and will differ for that reason alone, which looks exactly like an
incompatibility and is not.

**And run both *compilers* from the same directory too**, which is a second
reason and was learnt in 0.40.0. An `@include` records the library's path in the
chunk, so the previous release unpacked elsewhere resolves `lib/` relative to
itself and writes a different name for identical code. That reported five
examples differing when none did. Copy the old `solas` beside the new one rather
than running it where it was unpacked.

**`examples/system.sol` always differs**, because it prints how long things
took. That one is read, not compared.

**When extensions were touched, load the previous release's bundle on the new
build.** That is the ABI question and it is not the bytecode question — the two
can disagree, and 0.39.0 is the release where they did.

## Then the tag

Annotated, named `vX.Y.Z`, with a one-line message in the form
`Solveig X.Y.Z -- the headline`.

```sh
git tag -a v0.39.0 -m "Solveig 0.39.0 -- measured against another language, and the three things it found"
git push origin main && git push origin v0.39.0
```

## Then the page, and the three fixups it needs

The release body is the changelog entry, with three changes that
[the journal](journal.md) recorded the first time each was needed — it said
*two* until 0.41.0, having been written when there were two and never counted
again, which is [the stale sentence](method.md#a-sentence-that-was-true-when-written-is-not-checked-by-anything)
this page warns about happening to this page. All three are cases of something
that stops being right by being moved rather than by being wrong.

**Strip the `count` markers.** A number written with one of them — the comment
notation [programs.md](programs.md) describes, which tells the checker to
recount the figure in front of it — is a *live* number. A release page is a
historical statement that nothing recounts and nothing on GitHub would correct.

The markers are not quoted here on purpose. A comment that says *recount the
number before me* means that wherever it appears, and prose explaining the
notation is not an exception; writing one into a sentence about it is how the
build was broken the first time this was written down.

**Unwrap the paragraphs.** GitHub renders release notes with *hard* line
breaks, so the 79-column wrapping every document here is written to comes out as
a literal break after every line — a narrow ragged column inside a wide box,
breaking mid-sentence. 0.40.0's page had 41 of them across 8 paragraphs and was
published that way before anybody looked at it. Join the lines within each
paragraph and leave the blank lines between them.

This is the one fixup that cannot be found by reading the markdown, because the
markdown is correct. **Open the page.**

It has a mechanical form as well, and 0.41.0 used it: fetch the published page
and count. `<br>` inside the body is the fault, and the paragraph count is what
it should be instead — fourteen paragraphs and zero `<br>` there, against
0.40.0's forty-one breaks across eight. **That reads the renderer's output,
which is the artefact and is the point of it**, and it would say nothing about
a fault that produced no `<br>`; it fails on the one that has actually
happened, which is the standard the rest of these checks are held to.

**Absolutise the links, pinned at the tag.** `[NET.md](NET.md)` is right inside
`docs/` and a 404 from `/releases/tag/vX.Y.Z`. Rewrite to
`https://github.com/hansolovkarlsson/Solveig/blob/vX.Y.Z/docs/NET.md` — at the
tag rather than at `main`, so the page goes on describing what *this* release
shipped after the documents move underneath it.

**Then fetch each one and check it answers 200**, rather than trusting the
string you built. The tag has to exist on the remote before they can, which is
why this comes after the push; 0.41.0 had six and all six answered.

Attach `dist/solveig-X.Y.Z.tar.gz` from `make dist`, which archives `HEAD` —
check that `HEAD` is the release commit the tag points at.

## What the document checker does not cover

**Run [site.sh](../programs/site.sh) first**, after pushing and once Pages has
rebuilt — a minute or so. It holds every published page against the source at
`origin/main`: headings that stopped being headings, links that lost the
site's baseurl, anchors that name nothing. Both fault classes it exists for are
markdown that is *correct* and publishes wrong, so nothing that reads the file
can see them, and one of them stood for ten days and twenty releases.

The checker itself recounts prose in `docs/` and reads `README.md` and
`index.md` for claims. It does not know that a version number in prose is a
claim, and `_config.yml` is not a document to it at all — which is how the site's description sat at *123
messages* and called Solveig *the Solum language*, inverting the 0.36.0 rename,
until somebody read it. A release is a good moment to read the front page as a
stranger would.
