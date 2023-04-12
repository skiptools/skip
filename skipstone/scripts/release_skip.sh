#!/bin/bash -e
#
# This script will coorinate releasing a binary artifact of:
# https://github.com/skiptools/SkipSource.git
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
eval ${SKIPDIFF:-"git diff --exit-code"}

SKIPCONFIG=${SKIPCONFIG:-"release"}

PRODUCT=SkipRunner
ARTIFACTTOOL=skiptool
# name the artifact the same as the tool
ARTIFACT=${ARTIFACTTOOL}
ARTIFACTBUNDLE="${ARTIFACT}.artifactbundle"

DIR=.build/artifactbundle
GITDATE="$(git log -1 --format=%ad --date=iso-strict)"
GITREF="$(git rev-parse HEAD)"

# the relative path to the repo that hosts the plug-in code and referebce to the binary executable
SKIPPKG="../skip/Package.swift"
SKIPPKGDIR=$(dirname ${SKIPPKG})

# once we get this repo sync'd, we can rely on both tags being the same
cd ${SKIPPKGDIR}
SEMVER_CURRENT=$(git tag -l --sort=-version:refname | grep '[0-9]*\.[0-9]*\.[0-9]*' | head -n 1)
SEMVER_NEXT=$(semver bump "${SEMVER_BUMP:-patch}" "${SEMVER_CURRENT}")

cd '-'

echo "Creating release and tagging new skip version: ${SEMVER_NEXT}"

# mark the internal version
VERSION_PATH="Sources/SkipSyntax/Version.swift"

sed -I '' 's;public let skipVersion = .*;public let skipVersion = "'${SEMVER_NEXT}'";g' "${VERSION_PATH}"

git diff "${VERSION_PATH}"

swift build --arch arm64 --arch x86_64 --configuration ${SKIPCONFIG} --product ${PRODUCT}

set -o pipefail

# try to back up any old artifactbundle folder
mv -f ${DIR}/${ARTIFACTBUNDLE} ${DIR}/${ARTIFACTBUNDLE}.bk.`date +%s` || true
mkdir -p ${DIR}/${ARTIFACTBUNDLE}

# the secret --arch flag emits to the (undocumented) "apple" build folder
cp -av .build/apple/Products/${SKIPCONFIG}/${PRODUCT} ${DIR}/${ARTIFACTBUNDLE}/${ARTIFACTTOOL}

cd ${DIR}

cat > ${ARTIFACTBUNDLE}/info.json << EOF
{
    "schemaVersion": "1.0",
    "artifacts": {
        "${ARTIFACTTOOL}": {
            "type": "executable",
            "version": "${SEMVER_NEXT}",
            "variants": [
                {
                    "path": "${ARTIFACTTOOL}",
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
zip -9 -q --symlinks -r ${ARTIFACTBUNDLE}.zip ${ARTIFACTBUNDLE}

CHECKSUM=$(shasum -a 256 ${ARTIFACTBUNDLE}.zip | cut -f 1 -d ' ')
ls -lah ${ARTIFACTBUNDLE}.zip

# the location of the download once we have uploaded it
ARTIFACT_URL="https://github.com/skiptools/skip/releases/download/${SEMVER_NEXT}/${ARTIFACTBUNDLE}.zip"

#gh release -R github.com/skiptools/skip delete "main-${RELNAME}" --yes || true

cd '-'

# package.targets += [.binaryTarget(name: "${PRODUCT}", url: "${ARTIFACT_URL}", checksum: "${CHECKSUM}")]
sed -I '' 's;package.targets += \[.binaryTarget.*;package.targets += [.binaryTarget(name: "'${ARTIFACT}'", url: "'${ARTIFACT_URL}'", checksum: "'${CHECKSUM}'")];g' ${SKIPPKG}

# First make the release in the skip plugin-in
# this aligns the 
cd ${SKIPPKGDIR}

sed -I '' 's;.package(url: "https://github.com/skiptools/skip", from: ".*");.package(url: "https://github.com/skiptools/skip", from: "'${SEMVER_NEXT}'");g' README.md ../skiphub/Package.swift

# also grab the latest skiphub version and update it in the README
SKIPHUB_VERSION=`git ls-remote --tags https://github.com/skiptools/skiphub | awk -F/ '$NF ~ /^v?[0-9]+\.[0-9]+\.[0-9]+$/ {print $NF}' | sort -V | tail -n1`

sed -I '' 's;.package(url: "https://github.com/skiptools/skiphub", from: ".*");.package(url: "https://github.com/skiptools/skiphub", from: "'${SKIPHUB_VERSION}'");g' ${README_PATH}

git add Package.swift ${README_PATH}
git add .
git commit -m "Release ${SEMVER_NEXT}"
git tag --sign "${SEMVER_NEXT}" -m "Release ${SEMVER_NEXT}"
git push --follow-tags

cd '-'

# Now when we upload, it will be to the tag that corresponds to this download
#echo "Creating release artifact: ${ARTIFACT_URL}"
gh release -R github.com/skiptools/skip create --notes "" "${SEMVER_NEXT}" ${DIR}/${ARTIFACTBUNDLE}.zip

echo "Waiting to download to become available…"
sleep 15

# sometimes need to wait briefly for the artifact to become available
curl --location --fail --retry 5 --retry-all-errors --retry-max-time 120 -o /dev/null "${ARTIFACT_URL}"

# now jump *back* to the package and make sure we can run the command
cd '-'
if [ "${SKIPPKG}" != "/dev/null" ]; then        
    swift package --disable-sandbox --allow-writing-to-package-directory skip info
fi

# finally, jump back and make a corresponding release in the private SwiftSource
cd '-'

echo "Hit return to tag ${VERSION_PATH}"

git add "${VERSION_PATH}"
git commit -m "Release ${SEMVER_NEXT}" "${VERSION_PATH}"
git tag --sign "${SEMVER_NEXT}" -m "Release ${SEMVER_NEXT}"
git push --follow-tags

# get the new ref after we have pushed to SkipSource
GITREF="$(git rev-parse HEAD)"


RELNOTES=`mktemp`
#echo "Updating relnotes: ${RELNOTES}"
cat > ${RELNOTES} << EOF
head: ${GITREF}
checksum: ${CHECKSUM}
EOF

#echo "updating relnotes: ${RELNOTES}"
gh release -R github.com/skiptools/skip edit "${SEMVER_NEXT}" -F ${RELNOTES} 
#echo "done releasing ${SEMVER_NEXT}"

