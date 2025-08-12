#!/bin/bash -ex
CONFIGURATION=${CONFIGURATION:-"release"}
PRODUCT=${PRODUCT:-"SkipRunner"}
SKIPCMD=skip
ARTIFACT=${SKIPCMD}
ARTIFACTBUNDLE="${ARTIFACT}.artifactbundle"
PLUGIN_ZIP="${ARTIFACT}.zip"
ARTIFACT_BUILD_DIR=.build/artifactbundle-macos

# now make the final release build for both architectures
swift build --arch arm64 --arch x86_64 --configuration ${CONFIGURATION} --product ${PRODUCT}

# try to back up any old artifactbundle folder
mv -f ${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE} ${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}.bk.`date +%s` || true
mkdir -p ${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}/macos

# the secret --arch flag emits to the (undocumented) "apple" build folder
cp -av .build/apple/Products/${CONFIGURATION}/${PRODUCT} ${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}/macos/${SKIPCMD}

cd ${ARTIFACT_BUILD_DIR}
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
                }
            ]
        }
    }
}
EOF

tree "${ARTIFACTBUNDLE}"
du -skh "${ARTIFACTBUNDLE}"

# sync file times to git date for build reproducability
#find ${ARTIFACTBUNDLE} -exec touch -d "${GITDATE:0:19}" {} \;
zip -9 -q --symlinks -r ${PLUGIN_ZIP} ${ARTIFACTBUNDLE}
unzip -l "${PLUGIN_ZIP}" 
du -skh "${PLUGIN_ZIP}"

