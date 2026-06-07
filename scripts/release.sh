#!/usr/bin/env bash
#
# Cuts a release whose Git tag matches the app's version, so the tag and the version
# the in-app updater reads (CFBundleShortVersionString / MARKETING_VERSION) can never
# drift apart. The updater normalises a leading "v" and trailing ".0"s, so only the
# numbers have to match (tag "v1.3" == version "1.3.0").
#
# The project's MARKETING_VERSION is the single source of truth. Pass a version to bump
# it (and commit that change) before tagging; omit it to tag the version that's already
# set.
#
#   scripts/release.sh 1.3.0            # bump to 1.3.0, commit, create tag v1.3.0
#   scripts/release.sh 1.3.0 --push     # …also push the commit + tag and open a draft release
#   scripts/release.sh                  # tag the current MARKETING_VERSION as-is
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

# --- Bump MARKETING_VERSION + commit (only if a version was requested) ------------
if [[ -n "$NEW_VERSION" && "$NEW_VERSION" != "$CURRENT" ]]; then
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

  git add "$PBXPROJ"
  git commit -m "Bump version to ${NEW_VERSION}" >/dev/null
  echo "Committed version bump."
elif [[ -n "$NEW_VERSION" ]]; then
  echo "Version is already ${NEW_VERSION}; nothing to bump."
fi

# --- Tag --------------------------------------------------------------------------
git tag -a "${TAG}" -m "MacDring ${TARGET}"
echo "Created tag ${TAG}."

# --- Push (optional) --------------------------------------------------------------
if $PUSH; then
  git push origin HEAD
  git push origin "${TAG}"
  echo "Pushed branch + ${TAG} to origin."
  if command -v gh >/dev/null 2>&1; then
    gh release create "${TAG}" --title "MacDring ${TARGET}" --generate-notes --draft
    echo
    echo "Opened a DRAFT release. Attach the build and publish:"
    echo "  gh release upload ${TAG} path/to/MacDring-${TARGET}.dmg path/to/MacDring-${TARGET}.zip"
    echo "  gh release edit ${TAG} --draft=false"
  else
    echo "(Install the GitHub CLI 'gh' to also open a draft release automatically.)"
  fi
else
  echo "Local tag ${TAG} created (not pushed)."
  echo "Push it with:  git push origin HEAD && git push origin ${TAG}"
  echo "Or undo:       git tag -d ${TAG}$( [[ -n "$NEW_VERSION" && "$NEW_VERSION" != "$CURRENT" ]] && echo " && git reset --hard HEAD~1" )"
fi
