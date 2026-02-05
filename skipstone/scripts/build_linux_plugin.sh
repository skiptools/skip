#!/bin/bash -ex
# need to first install OSS Swift toolchain from:
#
# https://www.swift.org/download/#releases
#
# and install Linux Static SDK toolchain with:
# swift sdk install https://download.swift.org/swift-6.2.3-release/static-sdk/swift-6.2.3-RELEASE/swift-6.2.3-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz --checksum f30ec724d824ef43b5546e02ca06a8682dafab4b26a99fbb0e858c347e507a2c
#
# SkipKey can be built and uploaded with:
#
# PRODUCT=SkipKey COPYPRODUCT=1 ./scripts/build_linux.sh

CONFIGURATION=${CONFIGURATION:-"release"}
PRODUCT=${PRODUCT:-"SkipRunner"}
SKIPCMD=skip
ARTIFACT=${SKIPCMD}
ARTIFACTBUNDLE="${ARTIFACT}.artifactbundle"
PLUGIN_ZIP="${ARTIFACT}-linux.zip"
ARTIFACT_BUILD_DIR=.build/artifactbundle-linux

SWIFT_VERSION=${SWIFT_VERSION:-"6.2.3"}
USE_SWIFTLY=${USE_SWIFTLY:-"1"}

if [[ "${USE_SWIFTLY}" == "1" ]]; then
    swiftly install "${SWIFT_VERSION}"
fi

mv -vf "${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}" "${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}.bk.$(date +%s)" || true

for SDK in "x86_64-swift-linux-musl" "aarch64-swift-linux-musl"; do
    if [[ "${USE_SWIFTLY}" == "1" ]]; then
        swiftly run swift build --swift-sdk "${SDK}" --configuration "${CONFIGURATION}" --product "${PRODUCT}" "+${SWIFT_VERSION}"
    else
        # if swiftly is disabled, just build with the current `swift` version
        swift build --swift-sdk "${SDK}" --configuration "${CONFIGURATION}" --product "${PRODUCT}"
    fi

    if [[ "${PRODUCT}" == "SkipRunner" ]]; then
        mkdir -p "${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}/${SDK}"
        cp -av .build/${SDK}/${CONFIGURATION}/${PRODUCT} ${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}/${SDK}/${SKIPCMD}
    fi
done

SKIP_VERSION=${SKIP_VERSION:-"0.0.1"}

# finally copy up the binary to www.skip.tools with:
if [[ "$COPYPRODUCT" == "1" ]]; then
    scp .build/x86_64-swift-linux-musl/${CONFIGURATION}/${PRODUCT} www.skip.tools:~/lib/${PRODUCT}
elif [[ "${PRODUCT}" == "SkipRunner" ]]; then
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
                    "path": "x86_64-swift-linux-musl/${SKIPCMD}",
                    "supportedTriples": ["x86_64-unknown-linux-gnu"]
                },
                {
                    "path": "aarch64-swift-linux-musl/${SKIPCMD}",
                    "supportedTriples": ["aarch64-unknown-linux-gnu"]
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
fi

