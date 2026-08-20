# For building the GitHub Pages site only. The language itself still needs
# nothing but a C11 compiler and make -- this is never touched by `make`, and
# the workflow in .github/workflows/pages.yml is the only thing that reads it.
#
# Jekyll 4 rather than the 3.10 that GitHub's built-in Pages build pins, for one
# reason: `render_with_liquid: false`. Solum's `fill` templates are written with
# {} and {{, which is Liquid's own syntax, so any document explaining them is a
# Liquid syntax error under the built-in build. These documents are markdown and
# not templates, and Jekyll 4 lets us say so.
source "https://rubygems.org"

gem "jekyll", "~> 4.3"

group :jekyll_plugins do
  gem "jekyll-optional-front-matter", "~> 0.3"
  gem "jekyll-relative-links", "~> 0.6"
  gem "jekyll-titles-from-headings", "~> 0.5"
end
