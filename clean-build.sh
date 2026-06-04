#!/bin/bash
#
# Clean build for MacDring.
#
# Stops any in-flight builds, RESETS Xcode's build daemon, wipes MacDring's
# DerivedData, does a fresh Release build, then opens the built products folder
# in Finder. Run from anywhere:
#   ./clean-build.sh
#
# If a build hangs forever at "CreateBuildDescription" / the initial
#   clang -v -E -dM ... -c /dev/null
# probe (clang at 0% CPU), the Swift Build service has wedged: it spawned the
# probe but stopped draining its output pipe, so clang blocks in write(). The
# probe itself is fine -- run that clang line by hand and it finishes in <0.1s.
# This script force-resets the build service before each build to avoid that.
# If it still wedges, reboot (clears the wedged service + its XPC peer state).
#
cd "$(dirname "$0")" || exit 1

# SIGKILL (-9): a process wedged in write() ignores the default SIGTERM.
# SWBBuildService is the Swift Build service on Xcode 16+/26 (older Xcode used
# XCBBuildService); it runs and is supposed to drain the compiler probe.
# Killing it forces a fresh one on the next build.
killall -9 xcodebuild clang swift-frontend SWBBuildService XCBBuildService 2>/dev/null
sleep 1

xcodebuild -project MacDring.xcodeproj -scheme MacDring clean
rm -rf ~/Library/Developer/Xcode/DerivedData/MacDring-*
xcodebuild -project MacDring.xcodeproj -scheme MacDring -configuration Release build
status=$?

# On a successful build, open the products folder (where MacDring.app lands) in
# Finder. DerivedData was just wiped and rebuilt, so there's a single MacDring-*.
if [ "$status" -eq 0 ]; then
    products=$(ls -d ~/Library/Developer/Xcode/DerivedData/MacDring-*/Build/Products/Release 2>/dev/null | head -1)
    [ -n "$products" ] && open "$products"
fi

exit "$status"
