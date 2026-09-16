#!/bin/bash -ex
CONFIGURATION=${CONFIGURATION:-"release"}
PRODUCT=${PRODUCT:-"SkipRunner"}
SKIPCMD=skip
ARTIFACT=${SKIPCMD}
ARTIFACTBUNDLE="${ARTIFACT}.artifactbundle"
PLUGIN_ZIP="${ARTIFACT}-macos.zip"
ARTIFACT_BUILD_DIR=.build/artifactbundle-macos

# now make the final release build for both architectures
BUILD_ARGS=(build --arch arm64 --arch x86_64 --configuration "${CONFIGURATION}" --product "${PRODUCT}")
swift "${BUILD_ARGS[@]}"

# Where SwiftPM puts the built product depends on the build system: the `native` engine (the
# default through Swift 6.3) and `swiftbuild` (the default from Swift 6.4) use different layouts,
# and the swiftbuild path additionally varies by platform and configuration casing. Ask SwiftPM
# where it put the product rather than hard-coding either layout. For a universal build with the
# secret --arch flags that is .build/apple/Products/Release under 6.3 (the undocumented "apple"
# folder) but .build/out/Products/Release under 6.4.
BIN_PATH=$(swift "${BUILD_ARGS[@]}" --show-bin-path | tail -1)
if [[ ! -f "${BIN_PATH}/${PRODUCT}" ]]; then
    echo "error: ${PRODUCT} not found in the reported build folder: ${BIN_PATH}" >&2
    ls -la "${BIN_PATH}" >&2 || true
    exit 1
fi

# try to back up any old artifactbundle folder
mv -f ${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE} ${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}.bk.`date +%s` || true
mkdir -p ${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}/macos

cp -av "${BIN_PATH}/${PRODUCT}" "${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}/macos/${SKIPCMD}"

cd ${ARTIFACT_BUILD_DIR}

TOOLNAME="skip"
BINDIR="${ARTIFACTBUNDLE}"/bin
mkdir -p "${BINDIR}"

# make a shell script that launches the right binary
# note: logic duplicated in build_macos_plugin.sh and build_linux_plugin.sh
cat > ${BINDIR}/${TOOLNAME} << "EOF"
#!/bin/bash
# This script invokes the tool named after the script
# in the appropriate OS and architecture sub-folder
set -e
SCRIPTPATH="$(realpath "${BASH_SOURCE[0]}")"
TOOLNAME="$(basename "${SCRIPTPATH}")"
TOOLPATH="$(dirname "${SCRIPTPATH}")"
OS="$(uname -s)"
if [ "${OS}" = "Darwin" ]; then
    PROGRAM="${TOOLPATH}"/../macos/"${TOOLNAME}"
    /usr/bin/xattr -c "${PROGRAM}"
else
    ARCH="$(uname -m)"
    PROGRAM="${TOOLPATH}"/../"${ARCH}"-swift-linux-musl/"${TOOLNAME}"
fi
"${PROGRAM}" "${@}"
EOF
chmod +x ${BINDIR}/${TOOLNAME}

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

du -skh "${ARTIFACTBUNDLE}"

# sync file times to git date for build reproducability
#find ${ARTIFACTBUNDLE} -exec touch -d "${GITDATE:0:19}" {} \;
zip -9 -q --symlinks -r ${PLUGIN_ZIP} ${ARTIFACTBUNDLE}
unzip -l "${PLUGIN_ZIP}" 
du -skh "${PLUGIN_ZIP}"

