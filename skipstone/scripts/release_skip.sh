#!/bin/bash -ex
#
# This script coordinates releasing the Skip tool and plugin from this repository:
# https://github.com/skiptools/skip.git
#
# It builds the `skip` command-line tool from the skipstone/ package as a universal
# macOS binary and as static Linux binaries, and publishes the resulting
# artifactbundles to the repository's GitHub releases:
# https://github.com/skiptools/skip/releases
#
# The repository is tagged with the next semantic version up from its last tag,
# and the plugin's Package.swift is updated to reference the newly published
# binaries. If a checkout of https://github.com/skiptools/homebrew-skip.git exists
# in a peer folder (or at $SKIPBREWDIR), the Homebrew cask is updated as well.
#
# To make a patch release (like 1.0.2 -> 1.0.3), run:
#
#  ./skipstone/scripts/release_skip.sh
#
# To make a minor release (like 1.0.2 -> 1.1.0):
#
#  SEMVER_BUMP='minor' ./skipstone/scripts/release_skip.sh
#
# To make a major release (like 1.0.2 -> 2.0.0):
#
#  SEMVER_BUMP='major' ./skipstone/scripts/release_skip.sh
#
# To do a dry run that builds everything and shows the changes without
# committing, tagging, pushing, or publishing anything:
#
#  DRY_RUN=1 ./skipstone/scripts/release_skip.sh
#
# The release is made against the GitHub repository of the `origin` remote
# (or $GITHUB_REPOSITORY when running in GitHub Actions), so running the script
# in a fork releases to the fork. Override with SKIP_GITHUB_REPO=owner/name.

set -o pipefail

SCRIPTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# the skipstone/ package folder that contains the transpiler and the skip CLI
SKIPSTONEDIR=$(dirname "${SCRIPTDIR}")
# the root of the repository, which contains the skip plugin package
REPODIR=$(dirname "${SKIPSTONEDIR}")
# the checkout of homebrew-skip whose cask should be updated, if it exists
SKIPBREWDIR=${SKIPBREWDIR:-"${REPODIR}/../homebrew-skip"}

CONFIGURATION=${CONFIGURATION:-"release"}

PRODUCT=SkipRunner
SKIPCMD=skip

# name the artifact the same as the tool
ARTIFACT=${SKIPCMD}
ARTIFACTBUNDLE="${ARTIFACT}.artifactbundle"
PLUGIN_MACOS_ZIP="${ARTIFACT}-macos.zip"
PLUGIN_LINUX_ZIP="${ARTIFACT}-linux.zip"

RELSTAGING=`mktemp -d`

cd "${REPODIR}"

# the owner/name of the GitHub repository that hosts the release
if [[ -z "${SKIP_GITHUB_REPO:-}" ]]; then
    SKIP_GITHUB_REPO=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
fi
echo "Releasing to GitHub repository: ${SKIP_GITHUB_REPO}"

# get the latest changes (fails harmlessly on a detached HEAD in CI)
git pull || true
git fetch --tags --force

GITREF="$(git rev-parse HEAD)"

SKIP_VERSION_OLD=$(git tag -l --sort=-version:refname | grep '^[0-9]*\.[0-9]*\.[0-9]*$' | head -n 1)

major=$(echo "${SKIP_VERSION_OLD}" | tr '.' '\n' | head -n 1 | tail -n 1)
minor=$(echo "${SKIP_VERSION_OLD}" | tr '.' '\n' | head -n 2 | tail -n 1)
patch=$(echo "${SKIP_VERSION_OLD}" | tr '.' '\n' | head -n 3 | tail -n 1)

case "${SEMVER_BUMP:-patch}" in
    patch)
        patch=$((patch+1))
    ;;
    minor)
        patch=0
        minor=$((minor+1))
    ;;
    major)
        patch=0
        minor=0
        major=$((major+1))
    ;;
    *)
        echo "Invalid SEMVER_BUMP component: ${SEMVER_BUMP}"
        exit 2
esac

if [[ "${DRY_RUN:-'0'}" == "1" ]]; then
    export SKIP_VERSION="${SKIP_VERSION_OLD}"
    echo "Dry run: not bumping Skip version from: ${SKIP_VERSION}"
else
    export SKIP_VERSION="${major}.${minor}.${patch}"
    echo "Creating release and tagging new skip version: ${SKIP_VERSION_OLD} -> ${SKIP_VERSION}"
fi

# the version constants for the plugin (SkipDrive) and the tool (SkipSyntax)
SKIPDRIVE_VERSION_PATH="Sources/SkipDrive/Version.swift"
SKIPSTONE_VERSION_PATH="skipstone/Sources/SkipSyntax/Version.swift"

sed -I '' 's;public let skipVersion = .*;public let skipVersion = "'${SKIP_VERSION}'";g' "${SKIPDRIVE_VERSION_PATH}"
sed -I '' 's;public let skipVersion = .*;public let skipVersion = "'${SKIP_VERSION}'";g' "${SKIPSTONE_VERSION_PATH}"

# make sure CI passed on exactly what is being released;
# to ship a fix for a red CI anyway, run: SKIP_RELEASE_IGNORE_CI=1 ./skipstone/scripts/release_skip.sh
if [[ "${DRY_RUN:-0}" != "1" && "${SKIP_RELEASE_IGNORE_CI:-0}" != "1" ]]; then
    # ci.yml tests the plugin package with the tool built from skipstone/, and
    # skipstone-ci.yml tests the skipstone package and the tool on the emulator
    for WORKFLOW in ci.yml skipstone-ci.yml; do
        CONCLUSION=$(gh run list -R "${SKIP_GITHUB_REPO}" --workflow "${WORKFLOW}" --commit "${GITREF}" --status completed --limit 1 --json conclusion -q '.[0].conclusion')
        if [[ "${CONCLUSION}" != "success" ]]; then
            echo "error: ${WORKFLOW} is '${CONCLUSION:-missing}' for ${GITREF}; not releasing (if flaky: gh run rerun --failed -R ${SKIP_GITHUB_REPO} <run>; to start one: gh workflow run ${WORKFLOW} -R ${SKIP_GITHUB_REPO})"
            exit 1
        fi
    done
fi

# build the tool from the skipstone package
cd "${SKIPSTONEDIR}"

swift package update
# a stale build keeps old #if canImport(SkipDriveExternal) results
swift package clean

ARTIFACT_MACOS_BUILD_DIR=.build/artifactbundle-macos
"${SCRIPTDIR}/build_macos_plugin.sh"
cp -av "${ARTIFACT_MACOS_BUILD_DIR}/${PLUGIN_MACOS_ZIP}" "${RELSTAGING}"
PLUGIN_MACOS_CHECKSUM=$(shasum -a 256 "${RELSTAGING}/${PLUGIN_MACOS_ZIP}" | cut -f 1 -d ' ')

ARTIFACT_LINUX_BUILD_DIR=.build/artifactbundle-linux
"${SCRIPTDIR}/build_linux_plugin.sh"
cp -av "${ARTIFACT_LINUX_BUILD_DIR}/${PLUGIN_LINUX_ZIP}" "${RELSTAGING}"
PLUGIN_LINUX_CHECKSUM=$(shasum -a 256 "${RELSTAGING}/${PLUGIN_LINUX_ZIP}" | cut -f 1 -d ' ')

# update the plugin's binary targets to reference the artifacts that will be published
cd "${REPODIR}"

SKIPPKG="Package.swift"

ARTIFACT_MACOS_URL="https://github.com/${SKIP_GITHUB_REPO}/releases/download/${SKIP_VERSION}/${PLUGIN_MACOS_ZIP}"
sed -I '' 's;.binaryTarget(name: "'${ARTIFACT}'", url:.*'${PLUGIN_MACOS_ZIP}'.*);.binaryTarget(name: "'${ARTIFACT}'", url: "'${ARTIFACT_MACOS_URL}'", checksum: "'${PLUGIN_MACOS_CHECKSUM}'");g' ${SKIPPKG}

ARTIFACT_LINUX_URL="https://github.com/${SKIP_GITHUB_REPO}/releases/download/${SKIP_VERSION}/${PLUGIN_LINUX_ZIP}"
sed -I '' 's;.binaryTarget(name: "'${ARTIFACT}'", url:.*'${PLUGIN_LINUX_ZIP}'.*);.binaryTarget(name: "'${ARTIFACT}'", url: "'${ARTIFACT_LINUX_URL}'", checksum: "'${PLUGIN_LINUX_CHECKSUM}'");g' ${SKIPPKG}

git --no-pager diff --stat
git --no-pager diff -- "${SKIPPKG}"

if [[ "${DRY_RUN:-'0'}" == "1" ]]; then
    echo "DRY RUN: EXITING"
    exit 0
fi

git add "${SKIPPKG}" "${SKIPDRIVE_VERSION_PATH}" "${SKIPSTONE_VERSION_PATH}"
git commit --allow-empty --allow-empty-message -m "Release ${SKIP_VERSION}"
git tag "${SKIP_VERSION}" -m "Release ${SKIP_VERSION}"
git push --follow-tags

# need to wait a bit for the tag to show up
sleep 5
gh release -R "github.com/${SKIP_GITHUB_REPO}" create --verify-tag --generate-notes "${SKIP_VERSION}" "${RELSTAGING}"/*.zip

echo "Waiting to download to become available…"
sleep 15

# sometimes need to wait briefly for the artifact to become available
curl --location --fail --retry 10 --retry-all-errors --retry-max-time 120 -o /dev/null "${ARTIFACT_MACOS_URL}"
curl --location --fail --retry 10 --retry-all-errors --retry-max-time 120 -o /dev/null "${ARTIFACT_LINUX_URL}"

# update the homebrew cask with the updated skip command
if [[ -f "${SKIPBREWDIR}/Casks/skip.rb" ]]; then
    cd "${SKIPBREWDIR}"
    git pull || true

    sed -I '' "s;version \".*\";version \"${SKIP_VERSION}\";g" Casks/skip.rb

    # point the cask at the releases of the repository that was just released
    sed -I '' "s;url \"https://github.com/[^/]*/[^/]*/releases/download/;url \"https://github.com/${SKIP_GITHUB_REPO}/releases/download/;g" Casks/skip.rb

    # Update SHA-256 checksums in the Cask for each platform
    sed -I '' "s; arm:[[:space:]]*\"[A-Za-z0-9]\{64\}\"; arm:          \"${PLUGIN_MACOS_CHECKSUM}\";g" Casks/skip.rb
    sed -I '' "s; x86_64:[[:space:]]*\"[A-Za-z0-9]\{64\}\"; x86_64:       \"${PLUGIN_MACOS_CHECKSUM}\";g" Casks/skip.rb

    sed -I '' "s; arm64_linux:[[:space:]]*\"[A-Za-z0-9]\{64\}\"; arm64_linux:  \"${PLUGIN_LINUX_CHECKSUM}\";g" Casks/skip.rb
    sed -I '' "s; x86_64_linux:[[:space:]]*\"[A-Za-z0-9]\{64\}\"; x86_64_linux: \"${PLUGIN_LINUX_CHECKSUM}\";g" Casks/skip.rb

    git add Casks/skip.rb
    git commit -m "Release ${SKIP_VERSION}"
    git tag "${SKIP_VERSION}" -m "Release ${SKIP_VERSION}"
    git push --follow-tags
    cd "${REPODIR}"
else
    echo "warning: no homebrew-skip checkout at ${SKIPBREWDIR}; not updating the Homebrew cask"
fi

# check that homebrew can install/upgrade and run the tool on a developer machine
if [[ -z "${CI:-}" && "${SKIP_GITHUB_REPO}" == "skiptools/skip" ]]; then
    brew remove --formula skip || true
    HOMEBREW_AUTO_UPDATE_SECS=0 brew upgrade skiptools/skip/skip || brew install skiptools/skip/skip
    skip welcome
fi
