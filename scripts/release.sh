#!/usr/bin/env bash
#
# Cuts a release by pushing a "v<version>" tag, which triggers the release workflow
# (.github/workflows/release.yml) to build, package (.zip + .dmg), and publish the
# GitHub Release. CI derives the released version from the tag, so the tag is the
# source of truth — this script just keeps the committed MARKETING_VERSION and the
# README version line in step so *local/dev* builds (and the in-app updater) report the
# same number. The updater normalises a leading "v" and trailing ".0"s, so only the
# numbers have to match (tag "v1.3" == version "1.3.0").
#
#   scripts/release.sh 1.3.0          # bump MARKETING_VERSION + README, commit, tag v1.3.0
#   scripts/release.sh 1.3.0 --push   # …also push the commit + tag (CI then publishes)
#   scripts/release.sh                # tag the current MARKETING_VERSION as-is
#
# Usage: scripts/release.sh [X.Y[.Z]] [--push]
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="MacDring.xcodeproj"
SCHEME="MacDring"
PBXPROJ="$PROJECT/project.pbxproj"

# --- Parse args (an optional version, and/or --push, in any order) ----------------
NEW_VERSION=""
PUSH=false
for arg in "$@"; do
  case "$arg" in
    --push) PUSH=true ;;
    -*)     echo "error: unknown option '$arg'" >&2; exit 1 ;;
    *)
      if [[ -n "$NEW_VERSION" ]]; then echo "error: version given twice" >&2; exit 1; fi
      NEW_VERSION="$arg"
      ;;
  esac
done

VERSION_RE='^[0-9]+(\.[0-9]+){1,2}$'
if [[ -n "$NEW_VERSION" && ! "$NEW_VERSION" =~ $VERSION_RE ]]; then
  echo "error: version must look like 1.3 or 1.3.0 (got '$NEW_VERSION')" >&2
  exit 1
fi

# --- Read the current version, and decide the target ------------------------------
read_marketing_version() {
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION =/ {print $2; exit}'
}

CURRENT=$(read_marketing_version)
if [[ -z "${CURRENT:-}" ]]; then
  echo "error: could not read MARKETING_VERSION from $PROJECT" >&2
  exit 1
fi

TARGET="${NEW_VERSION:-$CURRENT}"
TAG="v${TARGET}"

# --- Pre-flight checks (do these before mutating anything) ------------------------
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree has uncommitted changes — commit or stash them first." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "error: tag ${TAG} already exists." >&2
  echo "       Pass a newer version, e.g. scripts/release.sh 1.3.0" >&2
  exit 1
fi

# --- Bump MARKETING_VERSION + README, then commit (only if a version was requested) -
DID_COMMIT=false
if [[ -n "$NEW_VERSION" ]]; then
  if [[ "$NEW_VERSION" != "$CURRENT" ]]; then
    echo "Bumping MARKETING_VERSION ${CURRENT} → ${NEW_VERSION}…"
    # Every MARKETING_VERSION line (app + test targets stay in lockstep). BSD/macOS sed.
    sed -i '' -E "s/(MARKETING_VERSION = )[^;]+;/\1${NEW_VERSION};/g" "$PBXPROJ"

    VERIFY=$(read_marketing_version)
    if [[ "$VERIFY" != "$NEW_VERSION" ]]; then
      echo "error: tried to set ${NEW_VERSION} but build settings report ${VERIFY}." >&2
      echo "       The version may come from an xcconfig — set it in Xcode instead." >&2
      git checkout -- "$PBXPROJ"
      exit 1
    fi
  fi

  # Reflect the version in README.md, between the <!-- version --> markers.
  if [[ -f README.md ]]; then
    sed -i '' -E "s|(<!-- version -->)[^<]*(<!-- /version -->)|\1${NEW_VERSION}\2|" README.md
    if ! grep -qF "<!-- version -->${NEW_VERSION}<!-- /version -->" README.md; then
      echo "note: README.md has no <!-- version --> marker — left unchanged." >&2
    fi
  fi

  # Commit whatever the version change touched (project and/or README).
  if [[ -n "$(git status --porcelain)" ]]; then
    git commit -am "Bump version to ${NEW_VERSION}" >/dev/null
    DID_COMMIT=true
    echo "Committed version bump (project + README)."
  else
    echo "Version is already ${NEW_VERSION}; nothing to bump."
  fi
fi

# --- Tag --------------------------------------------------------------------------
git tag -a "${TAG}" -m "MacDring ${TARGET}"
echo "Created tag ${TAG}."

# --- Push (optional) — pushing the tag is what triggers the release workflow -------
if $PUSH; then
  git push origin HEAD
  git push origin "${TAG}"
  echo "Pushed branch + ${TAG}."
  echo "CI (release.yml) will now build, package (.zip + .dmg), and publish the GitHub Release for ${TAG}."
else
  echo "Local tag ${TAG} created (not pushed)."
  echo "Push it to trigger the release:  git push origin HEAD && git push origin ${TAG}"
  echo "Or undo:                         git tag -d ${TAG}$( $DID_COMMIT && echo " && git reset --hard HEAD~1" )"
fi
