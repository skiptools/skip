#!/bin/bash -ex
#
# This script will coorinate releasing a binary artifact of:
# https://github.com/skiptools/skiptool.git
# which will be published to the plug-in repository's releases:
# https://github.com/skiptools/skip/releases
#
# The https://github.com/skiptools/skip.git repository
# will be tagged with the next semantic version up from
# its last tag.
#
# To make a patch release (like 1.0.2 -> 1.0.3), run:
#
#  ./scripts/release_skip.sh
#
# To make a minor release (like 1.0.2 -> 1.1.0):
#
#  SEMVER_BUMP='minor' ./scripts/release_skip.sh
#
# To make a major release (like 1.0.2 -> 2.0.0):
#
#  SEMVER_BUMP='major' ./scripts/release_skip.sh

# cannot run unless there are currently no diffs; override by running: 
# SKIPDIFF=true ./scripts/release_skip.sh
#eval ${SKIPDIFF:-"git diff --exit-code"}
set -o pipefail

# get latest skip
git pull || true
swift package update

CONFIGURATION=${CONFIGURATION:-"release"}

PRODUCT=SkipRunner
SKIPCMD=skip

# name the artifact the same as the tool
ARTIFACT=${SKIPCMD}
ARTIFACTBUNDLE="${ARTIFACT}.artifactbundle"
PLUGIN_MACOS_ZIP="${ARTIFACT}.zip"
PLUGIN_LINUX_ZIP="${ARTIFACT}-linux.zip"

GITDATE="$(git log -1 --format=%ad --date=iso-strict)"
GITREF="$(git rev-parse HEAD)"
RELSTAGING=`mktemp -d`

# the relative path to the repo that hosts the plug-in code
# and references the binary executable
SKIPPKG="../skip/Package.swift"
SKIPSTONEDIR="../skipstone"
SKIPPKGDIR=$(dirname ${SKIPPKG})
SKIPBREWDIR="../homebrew-skip"

# once we get this repo sync'd, we can rely on both tags being the same
cd ${SKIPPKGDIR}
git fetch --tags
git tag -l --sort=-version:refname

SKIP_VERSION_OLD=$(git tag -l --sort=-version:refname | grep '[0-9]*\.[0-9]*\.[0-9]*' | head -n 1)

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
        return 2
esac

if [[ "${DRY_RUN:-'0'}" != '0' ]]; then
    export SKIP_VERSION="${SKIP_VERSION_OLD}"
    echo "Dry run: not bumping Skip version from: ${SKIP_VERSION}"
else
    export SKIP_VERSION="${major}.${minor}.${patch}"
    echo "Creating release and tagging new skip version: ${SKIP_VERSION_OLD} -> ${SKIP_VERSION}"
fi

# also sync the plugin version in skip/Sources/SkipDrive/Version.swift
git pull || true
SKIPDRIVE_VERSION_PATH="Sources/SkipDrive/Version.swift"
sed -I '' 's;public let skipVersion = .*;public let skipVersion = "'${SKIP_VERSION}'";g' "${SKIPDRIVE_VERSION_PATH}"

cd '-'

# mark the internal version in skipstone/Sources/SkipSyntax/Version.swift
SKIPSTONE_VERSION_PATH="Sources/SkipSyntax/Version.swift"
sed -I '' 's;public let skipVersion = .*;public let skipVersion = "'${SKIP_VERSION}'";g' "${SKIPSTONE_VERSION_PATH}"

# make sure checkup passes
# TODO: need a way to have `skip` forked from checkup use the local build
#swift run SkipRunner checkup

# make sure both private skipstone/ and public skip/ tests pass
#swift test --configuration debug --parallel

# note that these sometimes need to be disabled when a framework upate
# is dependent on a skipstone change; the swift test init tests will
# fail until there is a new release
#SKIPLOCAL=${PWD} swift test --configuration debug --package-path ../skip/ 

ARTIFACT_MACOS_BUILD_DIR=.build/artifactbundle-macos
$(dirname $(realpath $0))/build_macos_plugin.sh
cp -av ${SKIPSTONEDIR}/${ARTIFACT_MACOS_BUILD_DIR}/${PLUGIN_MACOS_ZIP} ${RELSTAGING}
PLUGIN_MACOS_CHECKSUM=$(shasum -a 256 ${RELSTAGING}/${PLUGIN_MACOS_ZIP} | cut -f 1 -d ' ')

ARTIFACT_LINUX_BUILD_DIR=.build/artifactbundle-linux
$(dirname $(realpath $0))/build_linux_plugin.sh
cp -av ${SKIPSTONEDIR}/${ARTIFACT_LINUX_BUILD_DIR}/${PLUGIN_LINUX_ZIP} ${RELSTAGING}
PLUGIN_LINUX_CHECKSUM=$(shasum -a 256 ${RELSTAGING}/${PLUGIN_LINUX_ZIP} | cut -f 1 -d ' ')

# make a release of the skip command
cd ${SKIPPKGDIR}

ARTIFACT_MACOS_URL="https://source.skip.tools/skip/releases/download/${SKIP_VERSION}/${PLUGIN_MACOS_ZIP}"
sed -I '' 's;.binaryTarget(name: "'${ARTIFACT}'", url:.*'${PLUGIN_MACOS_ZIP}'.*);.binaryTarget(name: "'${ARTIFACT}'", url: "'${ARTIFACT_MACOS_URL}'", checksum: "'${PLUGIN_MACOS_CHECKSUM}'");g' ${SKIPPKG}

ARTIFACT_LINUX_URL="https://source.skip.tools/skip/releases/download/${SKIP_VERSION}/${PLUGIN_LINUX_ZIP}"
sed -I '' 's;.binaryTarget(name: "'${ARTIFACT}'", url:.*'${PLUGIN_LINUX_ZIP}'.*);.binaryTarget(name: "'${ARTIFACT}'", url: "'${ARTIFACT_LINUX_URL}'", checksum: "'${PLUGIN_LINUX_CHECKSUM}'");g' ${SKIPPKG}

sed -I '' 's;.package(url: "https://.*/skipstone.git", from: ".*");.package(url: "https://source.skip.tools/skipstone.git", exact: "'${SKIP_VERSION}'");g' ${SKIPPKG}

sed -I '' 's;.package(url: "https://.*/skip.git", from: ".*");.package(url: "https://source.skip.tools/skip.git", from: "'${SKIP_VERSION}'");g' "README.md"

if [[ "${DRY_RUN:-'0'}" != '0' ]]; then
    echo "DRY RUN: EXITING"
    exit 0
fi

git add Package.swift ${README_PATH} ${SKIPDRIVE_VERSION_PATH}
git add .
git commit --allow-empty --allow-empty-message -m "Release ${SKIP_VERSION}"
git tag "${SKIP_VERSION}" -m "Release ${SKIP_VERSION}"
git push --follow-tags

cd ${RELSTAGING}

# need to wait a bit for the tag to show up
sleep 5
gh release -R github.com/skiptools/skip create --generate-notes "${SKIP_VERSION}" *.zip
cd '-'

echo "Waiting to download to become available…"
sleep 15

# sometimes need to wait briefly for the artifact to become available
curl --location --fail --retry 10 --retry-all-errors --retry-max-time 120 -o /dev/null "${ARTIFACT_MACOS_URL}"

# now jump *back* to the package and make sure we can run the command
#if [ "${SKIPPKG}" != "/dev/null" ]; then        
    #swift package --disable-sandbox --allow-writing-to-package-directory SkipRunner info
#fi

# jump back and make a corresponding release in skipstone
cd ${SKIPSTONEDIR}

git add "${SKIPSTONE_VERSION_PATH}"
git commit --allow-empty --allow-empty-message -m "Release ${SKIP_VERSION}"
git tag "${SKIP_VERSION}" -m "Release ${SKIP_VERSION}"
git push --follow-tags

# update the homebrew cask with the updated skip command
cd ${SKIPBREWDIR}
git pull || true

sed -I '' "s;version \".*\";version \"${SKIP_VERSION}\";g" Casks/skip.rb
sed -I '' "s;sha256 \".*\";sha256 \"${PLUGIN_MACOS_CHECKSUM}\";g" Casks/skip.rb
# from when they were distributed separately
#sed -I '' "s;sha256 \".*\";sha256 \"${SKIPCMD_CHECKSUM}\";g" Casks/skip.rb

git add Casks/skip.rb
git commit -m "Release ${SKIP_VERSION}" 
git tag "${SKIP_VERSION}" -m "Release ${SKIP_VERSION}"
git push --follow-tags

# check that mint can build/install and run the tool
# works, but is slow and we don't document it
# mint run skiptools/skip version

# check that homebrew can install/upgrade and run the tool
HOMEBREW_AUTO_UPDATE_SECS=0 brew upgrade skiptools/skip/skip || brew install skiptools/skip/skip
skip welcome 
