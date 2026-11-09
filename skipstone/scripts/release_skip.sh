#!/bin/bash -ex
#
# This script releases the Skip tool and plugin from this repository:
# https://github.com/skiptools/skip.git
#
# It is run by the "skip release" GitHub Actions workflow (.github/workflows/release.yml)
# when a semantic version tag is pushed:
#
#   git push origin HEAD:refs/tags/1.9.21
#
# It builds the `skip` command-line tool from the skipstone/ package as a universal
# macOS binary and as static Linux binaries, creates a "Release X.Y.Z" commit on main
# that bumps the version constants and points the plugin's binary targets at the new
# artifacts, moves the tag onto that commit, and publishes the artifacts to the GitHub
# release for the tag:
# https://github.com/skiptools/skip/releases
#
# If a checkout of https://github.com/skiptools/homebrew-skip.git exists at
# $SKIPBREWDIR, the Homebrew cask is updated as well.
#
# Environment:
#
#   SKIP_VERSION             the version to release (the tag name); defaults to the latest
#                            tag when doing a dry run
#   DRY_RUN=1                build the artifacts and show the changes a release would make
#                            without committing, tagging, pushing, or publishing anything
#   SKIP_RELEASE_IGNORE_CI=1 release even if CI has not passed for the commit
#   SKIP_GITHUB_REPO         the owner/name of the GitHub repository to release to; defaults
#                            to $GITHUB_REPOSITORY, then to the `origin` remote, so running the
#                            script in a fork releases to the fork
#   SKIPBREWDIR              a checkout of homebrew-skip whose cask should be updated
#
# To check the release build locally without releasing anything, run from the
# repository root:
#
#   DRY_RUN=1 ./skipstone/scripts/release_skip.sh

set -o pipefail

SCRIPTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# the skipstone/ package folder that contains the transpiler and the skip CLI
SKIPSTONEDIR=$(dirname "${SCRIPTDIR}")
# the root of the repository, which contains the skip plugin package
REPODIR=$(dirname "${SKIPSTONEDIR}")
# the checkout of homebrew-skip whose cask should be updated, if it exists
SKIPBREWDIR=${SKIPBREWDIR:-"${REPODIR}/../homebrew-skip"}

# the build configuration used by the build_*_plugin.sh scripts
export CONFIGURATION=${CONFIGURATION:-"release"}
DRY_RUN=${DRY_RUN:-0}

SKIPCMD=skip

# name the artifact the same as the tool
ARTIFACT=${SKIPCMD}
PLUGIN_MACOS_ZIP="${ARTIFACT}-macos.zip"
PLUGIN_LINUX_ZIP="${ARTIFACT}-linux.zip"

# the files that are updated by a release
SKIPPKG="Package.swift"
SKIPDRIVE_VERSION_PATH="Sources/SkipDrive/Version.swift"
SKIPSTONE_VERSION_PATH="skipstone/Sources/SkipSyntax/Version.swift"

RELSTAGING=$(mktemp -d)

cd "${REPODIR}"

# the owner/name of the GitHub repository that hosts the release
if [[ -z "${SKIP_GITHUB_REPO:-}" ]]; then
    SKIP_GITHUB_REPO=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
fi
echo "Releasing to GitHub repository: ${SKIP_GITHUB_REPO}"

git fetch --tags --force origin main

GITREF="$(git rev-parse HEAD)"

if [[ -z "${SKIP_VERSION:-}" ]]; then
    if [[ "${DRY_RUN}" != "1" ]]; then
        echo "error: SKIP_VERSION must be set to the version to release (or set DRY_RUN=1)"
        exit 2
    fi
    # a dry run without a version just rebuilds the current version
    SKIP_VERSION=$(git tag -l --sort=-version:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
    if [[ -z "${SKIP_VERSION}" ]]; then
        echo "error: no version tags found in the repository; set SKIP_VERSION for the dry run"
        exit 2
    fi
    echo "Dry run: using current Skip version: ${SKIP_VERSION}"
fi
export SKIP_VERSION

if ! [[ "${SKIP_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: SKIP_VERSION '${SKIP_VERSION}' is not a semantic version like 1.9.21"
    exit 2
fi

if [[ "${DRY_RUN}" != "1" ]]; then
    # the release commit moves the tag onto itself, which re-triggers the workflow when the push is made
    # with a personal access token; a release commit is recognizable by its binary target URLs
    if grep -q "/releases/download/${SKIP_VERSION}/" "${SKIPPKG}"; then
        echo "${GITREF} already references the ${SKIP_VERSION} release artifacts; nothing to do"
        exit 0
    fi

    if gh release view -R "${SKIP_GITHUB_REPO}" "${SKIP_VERSION}" >/dev/null 2>&1; then
        echo "error: release ${SKIP_VERSION} already exists in ${SKIP_GITHUB_REPO}; delete it to release this version again: gh release delete -R ${SKIP_GITHUB_REPO} ${SKIP_VERSION} --cleanup-tag"
        exit 1
    fi

    # the release commit is pushed to main, so the released commit must be on main
    if ! git merge-base --is-ancestor "${GITREF}" origin/main; then
        echo "error: ${GITREF} is not on main; releases are made from commits on main"
        exit 1
    fi

    if [[ -n "$(git status --porcelain)" ]]; then
        echo "error: the working tree has uncommitted changes"
        git status --porcelain
        exit 1
    fi

    # make sure CI passed on exactly what is being released;
    # to ship a fix for a red CI anyway, dispatch the workflow with "ignore_ci" or set SKIP_RELEASE_IGNORE_CI=1
    if [[ "${SKIP_RELEASE_IGNORE_CI:-0}" != "1" ]]; then
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
fi

echo "Releasing Skip ${SKIP_VERSION} from ${GITREF}"

# bump the version constants for the plugin (SkipDrive) and the tool (SkipSyntax)
sed -I '' 's;public let skipVersion = .*;public let skipVersion = "'"${SKIP_VERSION}"'";g' "${SKIPDRIVE_VERSION_PATH}"
sed -I '' 's;public let skipVersion = .*;public let skipVersion = "'"${SKIP_VERSION}"'";g' "${SKIPSTONE_VERSION_PATH}"

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

ARTIFACT_MACOS_URL="https://github.com/${SKIP_GITHUB_REPO}/releases/download/${SKIP_VERSION}/${PLUGIN_MACOS_ZIP}"
sed -I '' 's;.binaryTarget(name: "'${ARTIFACT}'", url:.*'${PLUGIN_MACOS_ZIP}'.*);.binaryTarget(name: "'${ARTIFACT}'", url: "'${ARTIFACT_MACOS_URL}'", checksum: "'${PLUGIN_MACOS_CHECKSUM}'");g' ${SKIPPKG}

ARTIFACT_LINUX_URL="https://github.com/${SKIP_GITHUB_REPO}/releases/download/${SKIP_VERSION}/${PLUGIN_LINUX_ZIP}"
sed -I '' 's;.binaryTarget(name: "'${ARTIFACT}'", url:.*'${PLUGIN_LINUX_ZIP}'.*);.binaryTarget(name: "'${ARTIFACT}'", url: "'${ARTIFACT_LINUX_URL}'", checksum: "'${PLUGIN_LINUX_CHECKSUM}'");g' ${SKIPPKG}

git --no-pager diff --stat
git --no-pager diff -- "${SKIPPKG}"

if [[ "${DRY_RUN}" == "1" ]]; then
    echo "DRY RUN: built ${RELSTAGING}/${PLUGIN_MACOS_ZIP} and ${RELSTAGING}/${PLUGIN_LINUX_ZIP}; restoring the modified files and exiting"
    git checkout -- "${SKIPPKG}" "${SKIPDRIVE_VERSION_PATH}" "${SKIPSTONE_VERSION_PATH}"
    exit 0
fi

# create the release commit, push it to main, and move the tag onto it
git add "${SKIPPKG}" "${SKIPDRIVE_VERSION_PATH}" "${SKIPSTONE_VERSION_PATH}"
git commit -m "Release ${SKIP_VERSION}"
RELEASE_COMMIT=$(git rev-parse HEAD)

if ! git push origin "HEAD:refs/heads/main"; then
    echo "warning: main has moved since ${GITREF} was tagged; the release commit ${RELEASE_COMMIT} is not on main. Merge the ${SKIP_VERSION} tag into main after the release completes: git merge ${SKIP_VERSION}"
fi

git tag -f -a "${SKIP_VERSION}" -m "Release ${SKIP_VERSION}"
git push --force origin "refs/tags/${SKIP_VERSION}"

# need to wait a bit for the tag to show up
sleep 5
gh release -R "${SKIP_GITHUB_REPO}" create --verify-tag --generate-notes "${SKIP_VERSION}" "${RELSTAGING}"/*.zip

echo "Waiting for the downloads to become available…"
sleep 15

# sometimes need to wait briefly for the artifacts to become available
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

echo "Released Skip ${SKIP_VERSION}: https://github.com/${SKIP_GITHUB_REPO}/releases/tag/${SKIP_VERSION}"
