# The mark

![Solveig](logo-wordmark.png)

One disc, parted. **Above the line is *sól*** — the sun, and the Norse sun
goddess whose name is the first element of *Solveig*. **Below it is *solum***,
the ground the language stands on and the machine that runs it.

So the mark is the naming decision rather than a decoration of it: the two words
the project is built from, in the two places they belong, in one shape.

It is also *only* one shape, which is the other sense of *solum* and the whole
design principle — there is one kind of thing here and one thing that happens to
it. A mark with a second element would have been arguing against the language.

## The files

| | |
| --- | --- |
| `logo.svg` | the mark; scales to anything |
| `logo-wordmark.svg` | the mark with the name beside it |
| `logo-512.png` … `logo-16.png` | rendered sizes, for places that will not take an SVG |

## Two things it is built to survive

**The gap is geometry, not paint.** The two halves are separate shapes with
space between them, so the background shows through — the mark works on white,
on a dark page, and on whatever colour a README badge happens to sit on. A white
line painted across a disc would only have worked on white.

**In the site header the ground half is `currentColor`**, so it takes the
theme's foreground the way the wordmark next to it does: slate on a light page,
pale on a dark one. The sun half never changes, being the one fixed thing in the
system.

## Colours

| | |
| --- | --- |
| sun | `#E8A33D` |
| ground | `#3E4A5B` on light, `currentColor` where a theme is in play |

## What it deliberately is not

**Not a sun-wheel.** Radiating spokes in a circle is the obvious way to draw a
Nordic sun and it is one to stay away from: eight- and twelve-fold spoked wheels
are close to a symbol that has been thoroughly ruined by other people. A disc
and a horizon say the same thing and say nothing else.

**Not a chariot, and not Sól herself.** The Trundholm sun disc and the horses
that draw it are the richer image and the wrong one for something that has to
read at sixteen pixels in a browser tab.
