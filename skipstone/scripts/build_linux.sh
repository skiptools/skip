#!/bin/sh -ex
# need to first install OSS Swift toolchain from:
# https://www.swift.org/download/#releases
# and install Linux Static SDK toolchain with:
# swift sdk install https://download.swift.org/swift-6.0.1-release/static-sdk/swift-6.0.1-RELEASE/swift-6.0.1-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz --checksum d4f46ba40e11e697387468e18987ee622908bc350310d8af54eb5e17c2ff5481

# e.g., swift.build.x86_64-swift-linux-musl will use "x86_64-swift-linux-musl"
SDK="x86_64-swift-linux-musl"
TOOLCHAIN="${HOME}/Library/Developer/Toolchains/swift-6.0.1-RELEASE.xctoolchain/usr"
CONFIGURATION=${CONFIGURATION:-"release"}

PRODUCT=${PRODUCT:-"SkipRunner"}
#PRODUCT="SkipKey"

${TOOLCHAIN}/bin/swift build --swift-sdk "${SDK}" --configuration "${CONFIGURATION}" --product ${PRODUCT}

# finally copy up the binary to www.skip.tools with:
echo "scp .build/${SDK}/${CONFIGURATION}/${PRODUCT} www.skip.tools:~/lib/${PRODUCT}"

