#!/bin/sh -e
# Note: requires `limactl start default` with Ubuntu 22 and
# swift 5.8 installed in the PATH
rsync -a  --exclude '.build' ${PWD} /tmp/lima/

# unfortunately we can't run it directly from here because the sshfs
# doesn't support some operation the swift comiler tries:
# <unknown>:0: error: unable to open output file '/tmp/lima/skipstone/.build/aarch64-unknown-linux-gnu/debug/ModuleCache/1ZI34EX383YFP/SwiftGlibc-20WEFW7YC1Q3T.pcm': 'Operation not permitted'
# lima swift test --package-path /tmp/lima/skipstone

lima rsync -a --exclude '.build' /tmp/lima/skipstone /opt/skiptools/
#lima swift test --package-path /opt/skiptools/skipstone
lima swift build -c release --product SkipRunner --package-path /opt/skiptools/skipstone

lima /opt/skiptools/skipstone/.build/aarch64-unknown-linux-gnu/release/SkipRunner welcome
lima cp /opt/skiptools/skipstone/.build/aarch64-unknown-linux-gnu/release/SkipRunner /tmp/lima/skip-aarch64-unknown-linux-gnu

cp -a /tmp/lima/skip-aarch64-unknown-linux-gnu .build/
ls -lah .build/skip-aarch64-unknown-linux-gnu

