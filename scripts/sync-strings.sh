#!/bin/zsh
# Puts every user-facing string of the engine into its two catalogs.
#
# Xcode syncs a catalog only when a person builds in the IDE. This builds the
# package with xcodebuild and syncs the .stringsdata files it leaves.
# A sync can move existing keys too. Read the diff and keep only your own keys.
set -e
root="${0:A:h:h}"
cd "$root"

derived=$(mktemp -d)
trap 'rm -rf "$derived"' EXIT

xcodebuild -scheme ASCKitEngine-Package -destination 'platform=macOS' \
    -derivedDataPath "$derived" -skipPackagePluginValidation build >/dev/null

for target in ASCKitAPI ASCKitProject; do
    build_dir=$(find "$derived/Build/Intermediates.noindex" -type d -name "$target-t.build" | head -1)
    if [[ -z "$build_dir" ]]; then
        echo "No build output for $target. Did the build make it?" >&2
        exit 1
    fi
    arguments=()
    for file in $(find "$build_dir" -name '*.stringsdata'); do
        arguments+=(--stringsdata "$file")
    done
    xcrun xcstringstool sync "Sources/$target/Resources/Localizable.xcstrings" "${arguments[@]}"
    echo "Synced $target"
done

# The build rewrites the pins without the packages that the app shares.
git checkout --quiet Package.resolved
