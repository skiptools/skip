#!/bin/sh -ex
# need to first install OSS Swift toolchain from:
#
# https://www.swift.org/download/#releases
#
# and install Linux Static SDK toolchain with:
# swift sdk install https://download.swift.org/swift-6.1-release/static-sdk/swift-6.1-RELEASE/swift-6.1-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz --checksum 111c6f7d280a651208b8c74c0521dd99365d785c1976a6e23162f55f65379ac6
#
# SkipKey can be built and uploaded with:
#
# PRODUCT=SkipKey COPYPRODUCT=1 ./scripts/build_linux.sh

# e.g., swift.build.x86_64-swift-linux-musl will use "x86_64-swift-linux-musl"
#VERSION="6.0.3"
VERSION="6.1"
SDK="x86_64-swift-linux-musl"
TOOLCHAIN="${HOME}/Library/Developer/Toolchains/swift-${VERSION}-RELEASE.xctoolchain/usr"
CONFIGURATION=${CONFIGURATION:-"debug"}

PRODUCT=${PRODUCT:-"SkipRunner"}
#PRODUCT="SkipKey"

${TOOLCHAIN}/bin/swift build -v --swift-sdk "${SDK}" --configuration "${CONFIGURATION}" --product "${PRODUCT}"

# finally copy up the binary to www.skip.tools with:
if [[ "$COPYPRODUCT" == "1" ]]; then
    scp .build/${SDK}/${CONFIGURATION}/${PRODUCT} www.skip.tools:~/lib/${PRODUCT}
fi

