#!/bin/bash -e
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
git pull
swift package update

SKIPCONFIG=${SKIPCONFIG:-"release"}

PRODUCT=SkipRunner
SKIPCMD=skip

# name the artifact the same as the tool
ARTIFACT=${SKIPCMD}
ARTIFACTBUNDLE="${ARTIFACT}.artifactbundle"
PLUGIN_ZIP="${ARTIFACT}.zip"

DIR=.build/artifactbundle
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
SKIP_VERSION_OLD=$(git tag -l --sort=-version:refname | grep '[0-9]*\.[0-9]*\.[0-9]*' | head -n 1)

#SKIP_VERSION=$(semver bump "${SEMVER_BUMP:-patch}" "${SKIP_VERSION_OLD}")

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

SKIP_VERSION="${major}.${minor}.${patch}"

cd '-'

echo "Creating release and tagging new skip version: ${SKIP_VERSION}"

# mark the internal version in skipstone/Sources/SkipSyntax/Version.swift
SKIPSTONE_VERSION_PATH="Sources/SkipSyntax/Version.swift"
sed -I '' 's;public let skipVersion = .*;public let skipVersion = "'${SKIP_VERSION}'";g' "${SKIPSTONE_VERSION_PATH}"
#git diff "${SKIPSTONE_VERSION_PATH}" || true

# also sync the plugin version in skip/Sources/SkipDrive/Version.swift
cd ${SKIPPKGDIR}
git pull
SKIPDRIVE_VERSION_PATH="Sources/SkipDrive/Version.swift"
sed -I '' 's;public let skipVersion = .*;public let skipVersion = "'${SKIP_VERSION}'";g' "${SKIPDRIVE_VERSION_PATH}"
#git diff "${SKIPSTONE_VERSION_PATH}" || true
cd -


# make sure checkup passes
# TODO: need a way to have `skip` forked from checkup use the local build
#swift run SkipRunner checkup

# make sure both private skipstone/ and public skip/ tests pass
swift test --configuration debug --parallel

# note that these sometimes need to be disabled when a framework upate
# is dependent on a skipstone change; the swift test init tests will
# fail until there is a new release
#SKIPLOCAL=${PWD} swift test --configuration debug --package-path ../skip/ 

# now make the final release build for both architectures
swift build --arch arm64 --arch x86_64 --configuration ${SKIPCONFIG} --product ${PRODUCT}

# build for linux using docker (or else try a cross-compilation toolchain)
#docker run -v "$PWD:/code" -w /code --platform linux/amd64 -e QEMU_CPU=max swift:focal swift build

# try to back up any old artifactbundle folder
mv -f ${DIR}/${ARTIFACTBUNDLE} ${DIR}/${ARTIFACTBUNDLE}.bk.`date +%s` || true
mkdir -p ${DIR}/${ARTIFACTBUNDLE}/macos

# the secret --arch flag emits to the (undocumented) "apple" build folder
cp -av .build/apple/Products/${SKIPCONFIG}/${PRODUCT} ${DIR}/${ARTIFACTBUNDLE}/macos/${SKIPCMD}

cd ${DIR}

cat > ${ARTIFACTBUNDLE}/info.json << EOF
{
    "schemaVersion": "1.0",
    "artifacts": {
        "${SKIPCMD}": {
            "type": "executable",
            "version": "${SKIP_VERSION}",
            "variants": [
                {
                    "path": "macos/${SKIPCMD}",
                    "supportedTriples": ["x86_64-apple-macosx", "arm64-apple-macosx"]
                },
            ]
        }
    }
}
EOF

tree "${ARTIFACTBUNDLE}"
du -skh "${ARTIFACTBUNDLE}"

# sync file times to git date for build reproducability
find ${ARTIFACTBUNDLE} -exec touch -d "${GITDATE:0:19}" {} \;
zip -9 -q --symlinks -r ${PLUGIN_ZIP} ${ARTIFACTBUNDLE}

PLUGIN_CHECKSUM=$(shasum -a 256 ${PLUGIN_ZIP} | cut -f 1 -d ' ')
du -skh "${PLUGIN_ZIP}"

# the location of the download once we have uploaded it
#ARTIFACT_URL="https://github.com/skiptools/skip/releases/download/${SKIP_VERSION}/${ARTIFACTBUNDLE}.zip"
#ARTIFACT_URL="https://skip.tools/skiptools/skip/releases/download/${SKIP_VERSION}/${PLUGIN_ZIP}"
ARTIFACT_URL="https://source.skip.tools/skip/releases/download/${SKIP_VERSION}/${PLUGIN_ZIP}"

cd -

# make a release of the skip command
cd ${SKIPPKGDIR}

#SKIP_ARTIFACT_ZIP="skip.zip"
#echo "Building ${SKIP_ARTIFACT_ZIP}"
#SKIPLOCAL=${PWD}/../skipstone swift build --arch arm64 --arch x86_64 --configuration ${SKIPCONFIG} --product skip

#cd .build/apple/Products/${SKIPCONFIG}/
## ensure we can run the skip command
#./skip version
#zip -9 ${RELSTAGING}/${SKIP_ARTIFACT_ZIP} skip
#SKIPCMD_CHECKSUM=$(shasum -a 256 ${RELSTAGING}/${SKIP_ARTIFACT_ZIP} | cut -f 1 -d ' ')
#cd -

# package.targets += [.binaryTarget(name: "${PRODUCT}", url: "${ARTIFACT_URL}", checksum: "${PLUGIN_CHECKSUM}")]
sed -I '' 's;.binaryTarget(name: "'${ARTIFACT}'", url:.*);.binaryTarget(name: "'${ARTIFACT}'", url: "'${ARTIFACT_URL}'", checksum: "'${PLUGIN_CHECKSUM}'");g' ${SKIPPKG}

sed -I '' 's;.package(url: "https://.*/skip.git", from: ".*");.package(url: "https://source.skip.tools/skip.git", from: "'${SKIP_VERSION}'");g' "README.md"

git add Package.swift ${README_PATH} ${SKIPDRIVE_VERSION_PATH}
git add .
git commit --allow-empty --allow-empty-message -m "Release ${SKIP_VERSION}"
git tag "${SKIP_VERSION}" -m "Release ${SKIP_VERSION}"
git push --follow-tags

# also grab the latest skiphub version and update it in the README
SKIPHUB_VERSION=`git ls-remote --tags https://github.com/skiptools/skiphub | awk -F/ '$NF ~ /^v?[0-9]+\.[0-9]+\.[0-9]+$/ {print $NF}' | sort -V | tail -n1`

cp -a ${SKIPSTONEDIR}/${DIR}/${PLUGIN_ZIP} ${RELSTAGING}

RELNOTES="${RELSTAGING}/releasenotes.md"
#echo "Updating relnotes: ${RELNOTES}"
cat > ${RELNOTES} << EOF
Skip release ${SKIP_VERSION}.
EOF

cd ${RELSTAGING}

shasum -a 256 *.zip >> checksums.txt
echo '```' >> ${RELNOTES}
cat checksums.txt >> ${RELNOTES}
echo '```' >> ${RELNOTES}

cat ${RELNOTES}

gh release -R github.com/skiptools/skip create -F releasenotes.md "${SKIP_VERSION}" *.zip checksums.txt
cd '-'

echo "Waiting to download to become available…"
sleep 15

# sometimes need to wait briefly for the artifact to become available
curl --location --fail --retry 10 --retry-all-errors --retry-max-time 120 -o /dev/null "${ARTIFACT_URL}"

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
git pull

sed -I '' "s;version \".*\";version \"${SKIP_VERSION}\";g" Casks/skip.rb
sed -I '' "s;sha256 \".*\";sha256 \"${PLUGIN_CHECKSUM}\";g" Casks/skip.rb
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
