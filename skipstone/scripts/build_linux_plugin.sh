#!/bin/bash -ex
# need to first install OSS Swift toolchain from:
#
# https://www.swift.org/download/#releases
#
# and install Linux Static SDK toolchain with:
#
# curl -fSLo ${TMPDIR}/swift-linux-sdk.tar.gz https://download.swift.org/swift-6.3.1-release/static-sdk/swift-6.3.1-RELEASE/swift-6.3.1-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz && swift sdk install ${TMPDIR}/swift-linux-sdk.tar.gz
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

# The compiler has to match the Linux static SDK that is installed, or the build fails with
# "module compiled with Swift X cannot be imported by the Swift Y compiler". Leave SWIFT_VERSION
# unset to build with whatever toolchain swiftly currently has selected — CI installs the
# toolchain and the matching SDK together (`swiftly install --use <version>`), so following its
# selection keeps the two in step. A hard-coded default silently drifts out of date instead.
SWIFT_VERSION=${SWIFT_VERSION:-""}
USE_SWIFTLY=${USE_SWIFTLY:-"1"}

# Parse --arch flags; defaults to both x86_64 and aarch64
ARCHS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCHS+=("$2")
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done
if [[ ${#ARCHS[@]} -eq 0 ]]; then
    ARCHS=("x86_64" "aarch64")
fi

if [[ "${USE_SWIFTLY}" == "1" ]]; then
    if [[ -n "${SWIFT_VERSION}" ]]; then
        swiftly install "${SWIFT_VERSION}"
    fi
    # report the compiler that will be used, so any mismatch with the installed SDK is visible
    swiftly run swift --version ${SWIFT_VERSION:+"+${SWIFT_VERSION}"}
fi

mv -vf "${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}" "${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}.bk.$(date +%s)" || true

for ARCH in "${ARCHS[@]}"; do
    SDK="${ARCH}-swift-linux-musl"

    BUILD_ARGS=(build --swift-sdk "${SDK}" --configuration "${CONFIGURATION}" --product "${PRODUCT}")
    if [[ "${USE_SWIFTLY}" == "1" ]]; then
        SWIFT_CMD=(swiftly run swift)
        # only pin a toolchain when one was explicitly requested; otherwise use swiftly's selection
        PIN=(${SWIFT_VERSION:+"+${SWIFT_VERSION}"})
    else
        # if swiftly is disabled, just build with the current `swift` version
        SWIFT_CMD=(swift)
        PIN=()
    fi

    "${SWIFT_CMD[@]}" "${BUILD_ARGS[@]}" "${PIN[@]}"

    # Where SwiftPM puts the built product depends on the build system: the `native` engine (the
    # default through Swift 6.3) and `swiftbuild` (the default from Swift 6.4) use different layouts,
    # and the swiftbuild path additionally varies by platform and configuration casing. Ask SwiftPM
    # where it put the product rather than hard-coding either layout. Note that the swiftbuild
    # path has no architecture component (.build/out/Products/Release-linux), so every arch in
    # this loop reports the same folder: the copy below must stay inside the loop, right after
    # the build that produced the binary.
    BIN_PATH=$("${SWIFT_CMD[@]}" "${BUILD_ARGS[@]}" --show-bin-path "${PIN[@]}" | tail -1)
    if [[ ! -f "${BIN_PATH}/${PRODUCT}" ]]; then
        echo "error: ${PRODUCT} not found in the reported build folder: ${BIN_PATH}" >&2
        ls -la "${BIN_PATH}" >&2 || true
        exit 1
    fi

    mkdir -p "${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}/${SDK}"
    cp -av "${BIN_PATH}/${PRODUCT}" "${ARTIFACT_BUILD_DIR}/${ARTIFACTBUNDLE}/${SDK}/${SKIPCMD}"
done

SKIP_VERSION=${SKIP_VERSION:-"0.0.1"}

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

# Build the variants JSON array based on the architectures that were built
VARIANTS=""
for ARCH in "${ARCHS[@]}"; do
    SDK="${ARCH}-swift-linux-musl"
    TRIPLE="${ARCH}-unknown-linux-gnu"
    if [[ -n "${VARIANTS}" ]]; then
        VARIANTS="${VARIANTS},"
    fi
    VARIANTS="${VARIANTS}
            {
                \"path\": \"${SDK}/${SKIPCMD}\",
                \"supportedTriples\": [\"${TRIPLE}\"]
            }"
done

cat > ${ARTIFACTBUNDLE}/info.json << EOF
{
"schemaVersion": "1.0",
"artifacts": {
    "${SKIPCMD}": {
        "type": "executable",
        "version": "${SKIP_VERSION}",
        "variants": [${VARIANTS}
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

