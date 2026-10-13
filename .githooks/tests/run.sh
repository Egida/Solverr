#!/usr/bin/env bash
# Checks that the git hooks reject what they claim to reject, and pass what they must pass.
#
# Both hooks are regexes, and a regex that silently stops matching looks exactly like a clean
# commit. Every rule below therefore has a case that must fail as well as one that must pass.
# CI runs this before it runs the hooks themselves (.github/workflows/standards.yml).
#
# Run it after touching either hook: bash .githooks/tests/run.sh
set -u

hooks="$(cd "$(dirname "$0")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0
broke=0
em=$(printf '\xe2\x80\x94')

# check <name> <expected exit> <command...>
check() {
  local name="$1" want="$2"
  shift 2
  local got=0
  "$@" > /dev/null 2>&1 || got=1
  if [ "$got" = "$want" ]; then
    echo "  ok    $name"
    pass=$((pass + 1))
  else
    echo "  BROKE $name (wanted exit $want, got $got)"
    broke=$((broke + 1))
  fi
}

# msg <expected exit> <name> <message>
msg() {
  printf '%b' "$3" > "$work/msg"
  check "$2" "$1" bash "$hooks/commit-msg" "$work/msg"
}

echo "commit-msg"
msg 0 "passes a conventional subject"          'fix(stealth): accept a cookie without a domain\n'
msg 0 "passes a subject with no scope"         'docs: explain the passthrough timeout\n'
msg 1 "rejects a subject with no type"         'Fixed the cookie bug.\n'
msg 1 "rejects an unknown type"                'update(api): tweak things\n'
msg 1 "rejects a subject over 72 characters"   'fix(api): this subject keeps going well past the seventy-two character limit\n'
msg 1 "rejects an em dash in the body"         "fix(api): accept headers\n\nIt was refused ${em} now it is not.\n"
msg 1 "rejects an AI co-author trailer"        'fix(api): accept headers\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n'
msg 1 "rejects a Copilot co-author trailer"    'fix(api): accept headers\n\nCo-authored-by: Copilot <copilot@github.com>\n'
msg 1 "rejects a generated-with footer"        'fix(api): accept headers\n\nGenerated with a tool\n'
msg 0 "passes a human co-author trailer"       'fix(api): accept headers\n\nCo-authored-by: Jane Doe <jane@example.com>\n'
msg 1 "rejects a bare issue number"            'fix(api): accept headers\n\nSee #12.\n'
msg 0 "passes the owner/repo issue form"       'fix(chrome): port the focus fix\n\nFrom FlareSolverr/FlareSolverr#1626.\n'
msg 1 "rejects a squash-merge (#N) suffix"     'fix(api): accept headers (#11)\n'
msg 1 "rejects a domain-shaped site name"      'fix: clears example.to again\n'
msg 1 "rejects scraping vocabulary"            'feat: add a scraper mode\n'
msg 0 "lets a merge commit through"            'Merge pull request #11 from someone/branch\n\nfix(api): accept headers\n'

# The pre-commit hook reads the index (or a commit range), so each case runs in a scratch repo.
repo="$work/repo"
g() { git -C "$repo" -c core.hooksPath=/nonexistent -c user.name=t -c user.email=t@example.com -c core.autocrlf=false "$@"; }
reset_repo() {
  rm -rf "$repo"
  mkdir -p "$repo"
  g init -q
  printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0]\n' > "$repo/CHANGELOG.md"
  printf '# Readme\n' > "$repo/README.md"
  printf '# Contributing\n' > "$repo/CONTRIBUTING.md"
  g add -A
  g commit -q -m "chore: baseline"
}
# stage <file> <content to append>
stage() {
  printf '%b' "$2" >> "$repo/$1"
  g add "$1"
}
pre() { (cd "$repo" && bash "$hooks/pre-commit" "$@"); }

echo "pre-commit"
reset_repo; stage README.md 'A plain new line.\n'
check "passes a clean README line"             0 pre
reset_repo; stage README.md "A line ${em} with an em dash.\n"
check "rejects an em dash in the README"       1 pre
reset_repo; stage CONTRIBUTING.md "A line ${em} with an em dash.\n"
check "rejects an em dash in CONTRIBUTING"     1 pre
reset_repo; stage README.md 'Point it at example.to for testing.\n'
check "rejects a site name in the README"      1 pre
reset_repo; mkdir -p "$repo/docs/dev"; stage docs/guide.md "A line ${em} in a guide.\n"
check "rejects an em dash in a docs guide"     1 pre
reset_repo; mkdir -p "$repo/docs/dev"; stage docs/guide.md 'Point it at example.to for testing.\n'
check "rejects a site name in a docs guide"    1 pre
reset_repo; mkdir -p "$repo/docs/dev"; stage docs/dev/record.md 'Measured against example.to.\n'
check "allows site names in docs/dev records" 0 pre
reset_repo
printf '# Changelog\n\n## [Unreleased]\n\n### Fixes\n\n- **A real headline.** Detail.\n\n## [1.0.0]\n' > "$repo/CHANGELOG.md"; g add CHANGELOG.md
check "passes a bold CHANGELOG headline"       0 pre
reset_repo
printf '# Changelog\n\n## [Unreleased]\n\n### Fixes\n\n- No bold headline here.\n\n## [1.0.0]\n' > "$repo/CHANGELOG.md"; g add CHANGELOG.md
check "rejects an entry with no headline"      1 pre
reset_repo
printf '# Changelog\n\n## [Unreleased]\n\n### Fixes\n\n- **A headline with no stop**\n\n## [1.0.0]\n' > "$repo/CHANGELOG.md"; g add CHANGELOG.md
check "rejects a headline with no full stop"   1 pre
reset_repo
printf '# Changelog\n\n## [Unreleased]\n\n### Other\n\n- Bumped a dependency.\n\n## [1.0.0]\n' > "$repo/CHANGELOG.md"; g add CHANGELOG.md
check "exempts the Other section"              0 pre
reset_repo; stage README.md "A line ${em} in a commit.\n"; g commit -q -m "docs: add a line"
check "range mode rejects a committed em dash" 1 pre HEAD~1..HEAD

# changelog <section> <entry>: stage a CHANGELOG whose [Unreleased] holds one entry, taken verbatim.
changelog() {
  reset_repo
  printf '# Changelog\n\n## [Unreleased]\n\n### %s\n\n%s\n\n## [1.0.0]\n' "$1" "$2" > "$repo/CHANGELOG.md"
  g add CHANGELOG.md
}
changelog Fixes '- **Chrome 1.2 support** now works.'
check "rejects a stop only after the headline" 1 pre
changelog Fixes '- **Headline? no**'
check "rejects a stop inside the headline"     1 pre
changelog Fixes '- **Set it to "auto."** Detail.'
check "passes a headline ending inside quotes" 0 pre
changelog Fixes '- **Set `GEO_IP_LOOKUP_URLS`.** Detail.'
check "passes a headline ending on code"       0 pre

# 23 characters of headline plus padding: 377 lands exactly on the 400 cap.
changelog Fixes "- **A real headline.** $(printf '%0377d' 0)"
check "passes an entry at the length cap"      0 pre
changelog Fixes "- **A real headline.** $(printf '%0378d' 0)"
check "rejects an entry over the length cap"   1 pre
changelog Other "- Bumped a dependency. $(printf '%0378d' 0)"
check "caps the Other section too"             1 pre
reset_repo
printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0]\n\n### Fixes\n\n- **Released.** %0400d\n' 0 > "$repo/CHANGELOG.md"; g add CHANGELOG.md
check "leaves released entries uncapped"       0 pre

changelog Fixes '- **A real headline.** Detail.'
printf '# Changelog\n\n## [Unreleased]\n\n### Fixes\n\n- No headline, unstaged.\n' > "$repo/CHANGELOG.md"
check "reads the staged CHANGELOG, not a dirty tree" 0 pre
changelog Fixes '- No bold headline here.'
printf '# Changelog\n\n## [Unreleased]\n\n### Fixes\n\n- **Fixed, but unstaged.**\n' > "$repo/CHANGELOG.md"
check "rejects a bad staged CHANGELOG fixed only in the tree" 1 pre

reset_repo; mkdir -p "$repo/docs/dev"; stage docs/dev/record.md "A line ${em} in a record.\n"
check "rejects an em dash in a docs/dev record" 1 pre
reset_repo; mkdir -p "$repo/docs/dev"; stage docs/dev/record.md 'Fixed in #12 upstream.\n'
check "rejects a bare #N in a docs/dev record" 1 pre
reset_repo; mkdir -p "$repo/docs/dev"; stage docs/dev/record.md 'Ported FlareSolverr/FlareSolverr#1626.\n'
check "passes owner/repo#N in a docs/dev record" 0 pre
reset_repo; mkdir -p "$repo/docs/dev"; stage docs/dev/record.md 'Fixed in #12 later.\n'; g commit -q -m "docs: add a record"
check "range mode rejects a committed docs/dev bare #N" 1 pre HEAD~1..HEAD

echo ""
echo "$pass passed, $broke broke"
[ "$broke" -eq 0 ]
