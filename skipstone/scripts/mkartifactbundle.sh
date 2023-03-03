#!/bin/bash -e

# cannot run unless there are currently no diffs
git diff --exit-code

CONFIG=release
#CONFIG=debug

PRODUCT=SkipRunner
ARTIFACTTOOL=skiptool
# name the artifact the same as the tool
ARTIFACT=${ARTIFACTTOOL}
ARTIFACTBUNDLE="${ARTIFACT}.artifactbundle"

DIR=.build/artifactbundle
GITDATE="$(git log -1 --format=%ad --date=iso-strict)"
GITREF="$(git rev-parse HEAD)"

# the relative path to the repository that hosts the plug-in
# and redirects to the binary plug-in
SKIPPKG="../skip/Package.swift"
SKIPPKGDIR=$(dirname ${SKIPPKG})

# once we get this repo sync'd, we can rely on both tags being the same
cd ${SKIPPKGDIR}
SEMVER_CURRENT=$(git tag -l --sort=-version:refname | grep '[0-9]*\.[0-9]*\.[0-9]*' | head -n 1)
SEMVER_NEXT=$(semver bump patch "${SEMVER_CURRENT}")
cd -

echo "Creating release and tagging new skip version: ${SEMVER_NEXT}"

# mark the internal version
RUNNER_PATH="Sources/SkipRunner/Runner.swift"
sed -I '' 's;public let skipVersion = .*;public let skipVersion = "'${SEMVER_NEXT}'";g' ${RUNNER_PATH}



swift build --arch arm64 --arch x86_64 --configuration ${CONFIG} --product ${PRODUCT}

set -o pipefail

# try to back up any old artifactbundle folder
mv -f ${DIR}/${ARTIFACTBUNDLE} ${DIR}/${ARTIFACTBUNDLE}.bk.`date +%s` || true
mkdir -p ${DIR}/${ARTIFACTBUNDLE}

# the secret --arch flag emits to the (undocumented) "apple" build folder
cp -av .build/apple/Products/${CONFIG}/${PRODUCT} ${DIR}/${ARTIFACTBUNDLE}/${ARTIFACTTOOL}

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

# the location of the download once we have uploadedit
ARTIFACT_URL="https://github.com/skipsource/skip/releases/download/${SEMVER_NEXT}/${ARTIFACTBUNDLE}.zip"

#gh release -R github.com/skipsource/skip delete "main-${RELNAME}" --yes || true

cd -

# package.targets += [.binaryTarget(name: "${PRODUCT}", url: "${ARTIFACT_URL}", checksum: "${CHECKSUM}")]
sed -I '' 's;package.targets += .*;package.targets += [.binaryTarget(name: "'${ARTIFACT}'", url: "'${ARTIFACT_URL}'", checksum: "'${CHECKSUM}'")];g' ${SKIPPKG}

# First make the release in the skip plugin-in
# this aligns the 
cd ${SKIPPKGDIR}

README_PATH="README.md"
sed -I '' 's;package.dependencies += .*;package.dependencies += [.package(url: "https://github.com/skiptools/skip.git", from: "'${SEMVER_NEXT}'")];g' ${README_PATH}

git add Package.swift ${README_PATH}
git add .
git commit -m "Release ${SEMVER_NEXT}"
git tag --sign "${SEMVER_NEXT}" -m "Release ${SEMVER_NEXT}"
git push --follow-tags

cd -

# Now when we upload, it will be to the tag that corresponds to this download
#echo "Creating release artifact: ${ARTIFACT_URL}"
gh release -R github.com/skipsource/skip create --notes "" "${SEMVER_NEXT}" ${DIR}/${ARTIFACTBUNDLE}.zip

sleep 5

# sometimes need to wait briefly for the artifact to become available
curl --silent --location --fail --head "${ARTIFACT_URL}" 2>&1 > /dev/null || sleep 5
curl --silent --location --fail --head "${ARTIFACT_URL}" 2>&1 > /dev/null || sleep 5
curl --silent --location --fail --head "${ARTIFACT_URL}" 2>&1 > /dev/null || sleep 5
curl --silent --location --fail --head "${ARTIFACT_URL}" 2>&1 > /dev/null || sleep 5
curl --silent --location --fail --head "${ARTIFACT_URL}" 2>&1 > /dev/null || sleep 5


# now jump *back* to the package and make sure we can run the command
cd -
if [ "${SKIPPKG}" != "/dev/null" ]; then        
    swift package --disable-sandbox --allow-writing-to-package-directory skip
fi

# finally, jump back and make a corresponding release in the private SwiftSource
cd -

git add "${RUNNER_PATH}"
git commit -m "Release ${SEMVER_NEXT}" "${RUNNER_PATH}"
git tag -s -a "${SEMVER_NEXT}" -m "Release ${SEMVER_NEXT}"
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
gh release -R github.com/skipsource/skip edit "${SEMVER_NEXT}" -F ${RELNOTES} 
#echo "done releasing ${SEMVER_NEXT}"

