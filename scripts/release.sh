#!/usr/bin/env bash
# Builds a Simmer release: universal app, DMG, Sparkle-signed ZIP, appcast entry, cask update.
#
#   scripts/release.sh 1.2.0               # bump versions, build, package, sign, update feed + cask
#   scripts/release.sh 1.2.0 --no-bump     # versions are already 1.2.0 (CI on a tag): only verify them
#   scripts/release.sh 1.2.0 --skip-build  # reuse dist/Simmer.app (must already be version 1.2.0)
#   scripts/release.sh 1.2.0 --bump-only   # only bump the versions (then commit, tag, let CI build)
#
# What it changes in the repo (commit these, then tag v<version>):
#   project.yml                          MARKETING_VERSION = <version>, CURRENT_PROJECT_VERSION + 1
#   Sources/SimmerShared/Models.swift    Simmer.helperVersion = <version>  (the app offers to update
#                                        the root helper when the installed helper reports another one)
#   appcast.xml                          new <item> with the EdDSA signature of the ZIP
#   Casks/simmer.rb                      version + sha256 of the DMG
#
# Output in $DIST (default dist/): Simmer-<v>.dmg, Simmer-<v>.zip, release-notes-<v>.md
#
# Sparkle signing key (first match wins):
#   SPARKLE_PRIVATE_KEY   the exported key text (base64), e.g. a CI secret
#   SPARKLE_KEY_FILE      path to a file made with `generate_keys --account simmer -x <file>`
#   otherwise             the login keychain, account $SPARKLE_ACCOUNT (default: simmer)
# Sparkle tools: $SPARKLE_BIN, else the SwiftPM artifacts from the Xcode build, else a download.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
[[ $# -ge 1 ]] || usage
VERSION="${1#v}"; shift
BUMP=1; BUILD=1; BUMP_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --no-bump) BUMP=0 ;;
        --bump-only) BUMP_ONLY=1 ;;
        --skip-build) BUILD=0 ;;
        *) usage ;;
    esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "error: '$VERSION' is not x.y.z" >&2; exit 64; }

REPO="${GITHUB_REPOSITORY:-umarwaseeem/simmer}"
DIST="${DIST:-$ROOT/dist}"
TAG="v$VERSION"
APP="$DIST/Simmer.app"
DMG="$DIST/Simmer-$VERSION.dmg"
ZIP="$DIST/Simmer-$VERSION.zip"
NOTES="$DIST/release-notes-$VERSION.md"
MODELS="Sources/SimmerShared/Models.swift"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.10.1}"
mkdir -p "$DIST"

# --- 1. Release notes from CHANGELOG.md ("## [x.y.z] - date" up to the next "## [") -------------
awk -v head="## [$VERSION]" '
    index($0, head) == 1 { found = 1; next }
    found && (/^## \[/ || /^\[[^]]*\]: /) { exit }
    found { lines[++n] = $0 }
    END {
        s = 1; while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++
        e = n; while (e >= s && lines[e] ~ /^[[:space:]]*$/) e--
        for (i = s; i <= e; i++) print lines[i]
    }' CHANGELOG.md > "$NOTES"
if [[ ! -s "$NOTES" ]]; then
    echo "error: CHANGELOG.md has no '## [$VERSION]' section (move 'Unreleased' items under it)" >&2
    exit 1
fi
echo "==> release notes: $NOTES"

# --- 2. Versions --------------------------------------------------------------------------------
current_marketing() { sed -nE 's/^    MARKETING_VERSION: "([^"]*)".*/\1/p' project.yml; }
current_build()     { sed -nE 's/^    CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' project.yml; }
current_helper()    { sed -nE 's/.*public static let helperVersion = "([^"]*)".*/\1/p' "$MODELS"; }

if [[ $BUMP -eq 1 ]]; then
    OLD_BUILD="$(current_build)"
    NEW_BUILD=$(( ${OLD_BUILD:-0} + 1 ))
    echo "==> bumping to $VERSION (build $NEW_BUILD)"
    sed -i '' -E "s/^(    MARKETING_VERSION: )\"[^\"]*\"/\1\"$VERSION\"/" project.yml
    sed -i '' -E "s/^(    CURRENT_PROJECT_VERSION: )\"[0-9]+\"/\1\"$NEW_BUILD\"/" project.yml
    sed -i '' -E "s/(public static let helperVersion = )\"[^\"]*\"/\1\"$VERSION\"/" "$MODELS"
fi
[[ "$(current_marketing)" == "$VERSION" ]] || { echo "error: project.yml MARKETING_VERSION is '$(current_marketing)', expected $VERSION" >&2; exit 1; }
[[ "$(current_helper)" == "$VERSION" ]] || { echo "error: $MODELS helperVersion is '$(current_helper)', expected $VERSION" >&2; exit 1; }
if [[ $BUMP_ONLY -eq 1 ]]; then
    echo "==> versions set to $VERSION. Next: git commit -am \"Release $VERSION\" && git tag $TAG && git push origin main $TAG"
    exit 0
fi

# --- 3. Build ------------------------------------------------------------------------------------
if [[ $BUILD -eq 1 ]]; then
    DIST="$DIST" "$ROOT/scripts/build.sh"
fi
[[ -d "$APP" ]] || { echo "error: $APP missing" >&2; exit 1; }
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" ]] || { echo "error: $APP is version $BUILT_VERSION, expected $VERSION" >&2; exit 1; }
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"

# --- 4. DMG + ZIP --------------------------------------------------------------------------------
DIST="$DIST" APP="$APP" OUT="$DMG" "$ROOT/scripts/make-dmg.sh"
echo "==> zipping for Sparkle"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# --- 5. Sparkle signature ------------------------------------------------------------------------
sparkle_tool() {
    local name="$1" d p
    if [[ -n "${SPARKLE_BIN:-}" && -x "$SPARKLE_BIN/$name" ]]; then echo "$SPARKLE_BIN/$name"; return; fi
    for d in "${DERIVED_DATA:-}" "$ROOT/.build/xcode" "$ROOT/.build/xcode-release"; do
        [[ -n "$d" ]] || continue
        p="$d/SourcePackages/artifacts/sparkle/Sparkle/bin/$name"
        [[ -x "$p" ]] && { echo "$p"; return; }
    done
    d="$ROOT/.build/sparkle-$SPARKLE_VERSION"
    if [[ ! -x "$d/bin/$name" ]]; then
        echo "==> downloading Sparkle $SPARKLE_VERSION tools" >&2
        mkdir -p "$d"
        curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
            | tar -xJ -C "$d"
    fi
    echo "$d/bin/$name"
}
SIGN="$(sparkle_tool sign_update)"
echo "==> signing $ZIP"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    SIG_ATTRS="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" --ed-key-file - "$ZIP")"
elif [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
    SIG_ATTRS="$("$SIGN" --ed-key-file "$SPARKLE_KEY_FILE" "$ZIP")"
else
    SIG_ATTRS="$("$SIGN" --account "${SPARKLE_ACCOUNT:-simmer}" "$ZIP")"
fi
[[ "$SIG_ATTRS" == *'sparkle:edSignature="'*'length="'* ]] || { echo "error: unexpected sign_update output: $SIG_ATTRS" >&2; exit 1; }

# --- 6. appcast.xml ------------------------------------------------------------------------------
md_to_html() {
    awk '
    function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
    function inline(s) {
        s = esc(s)
        while (match(s, /\*\*[^*]+\*\*/)) s = substr(s, 1, RSTART - 1) "<b>" substr(s, RSTART + 2, RLENGTH - 4) "</b>" substr(s, RSTART + RLENGTH)
        while (match(s, /`[^`]+`/)) s = substr(s, 1, RSTART - 1) "<code>" substr(s, RSTART + 1, RLENGTH - 2) "</code>" substr(s, RSTART + RLENGTH)
        return s
    }
    /^###? / { if (ul) { print "</ul>"; ul = 0 }; sub(/^###? /, ""); print "<h3>" inline($0) "</h3>"; next }
    /^[-*] / { if (!ul) { print "<ul>"; ul = 1 }; print "<li>" inline(substr($0, 3)) "</li>"; next }
    /^[[:space:]]*$/ { if (ul) { print "</ul>"; ul = 0 }; next }
    { if (ul) { print "</ul>"; ul = 0 }; print "<p>" inline($0) "</p>" }
    END { if (ul) print "</ul>" }' "$1"
}
PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
ITEM="$(mktemp "${TMPDIR:-/tmp}/simmer-item.XXXXXX")"
trap 'rm -f "$ITEM"' EXIT
{
    echo "    <item>"
    echo "      <title>Simmer $VERSION</title>"
    echo "      <pubDate>$PUBDATE</pubDate>"
    echo "      <link>https://github.com/$REPO/releases/tag/$TAG</link>"
    echo "      <sparkle:version>$BUILD_NUMBER</sparkle:version>"
    echo "      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>"
    echo "      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>"
    # Pre-releases (1.2.0-beta.1) go to the "beta" channel; Sparkle offers them only to apps
    # that opt in to that channel (SPUUpdaterDelegate.allowedChannels).
    [[ "$VERSION" == *-* ]] && echo "      <sparkle:channel>beta</sparkle:channel>"
    echo "      <description><![CDATA["
    md_to_html "$NOTES" | sed 's/^/        /'
    echo "      ]]></description>"
    echo "      <enclosure url=\"https://github.com/$REPO/releases/download/$TAG/Simmer-$VERSION.zip\" type=\"application/octet-stream\" $SIG_ATTRS />"
    echo "    </item>"
} > "$ITEM"
# Replace an earlier entry for the same version (re-runs), then insert the new one under the marker.
V="$VERSION" perl -0pi -e 's{\n[ \t]*<item>(?:(?!</item>).)*?<sparkle:shortVersionString>\Q$ENV{V}\E</sparkle:shortVersionString>.*?</item>}{}s' appcast.xml
grep -q '<!-- RELEASES:' appcast.xml || { echo "error: appcast.xml lost its <!-- RELEASES: marker" >&2; exit 1; }
awk -v f="$ITEM" '{ print } /<!-- RELEASES:/ { while ((getline l < f) > 0) print l }' appcast.xml > appcast.xml.tmp
mv appcast.xml.tmp appcast.xml
xmllint --noout appcast.xml
echo "==> appcast.xml: added $VERSION (build $BUILD_NUMBER)"

# --- 7. Homebrew cask ----------------------------------------------------------------------------
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
sed -i '' -E "s/^(  version )\"[^\"]*\"/\1\"$VERSION\"/; s/^(  sha256 )(:no_check|\"[0-9a-f]*\")/\1\"$SHA\"/" Casks/simmer.rb
echo "==> Casks/simmer.rb: $VERSION, sha256 $SHA"

# --- 8. Next steps -------------------------------------------------------------------------------
cat <<EOF

Release $VERSION is ready:
  $DMG
  $ZIP
  $NOTES

Next steps:
  git add project.yml $MODELS appcast.xml Casks/simmer.rb CHANGELOG.md
  git commit -m "Release $VERSION"
  git tag $TAG && git push origin main $TAG

  # Either let .github/workflows/release.yml publish the tag, or publish by hand:
  gh release create $TAG "$DMG" "$ZIP" --repo $REPO --title "Simmer $VERSION" --notes-file "$NOTES"

  # Homebrew tap (github.com/umarwaseeem/homebrew-tap):
  cp Casks/simmer.rb ../homebrew-tap/Casks/simmer.rb   # then commit and push the tap
EOF
