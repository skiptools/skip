#!/bin/sh -ev
# Runs the tests in the peer ../skip/ repo against skipstone
# in the various build configurations
cd ../skip

swift test --filter testSkipTool
echo "EXTERNAL DEBUG PASSED"

swift test -c release --filter testSkipTool
echo "EXTERNAL RELEASE PASSED"

SKIPLOCAL=${PWD}/../skipstone swift test --filter testSkipTool
echo "INTERNAL DEBUG PASSED"

swift test -c release --filter testSkipTool
echo "INTERNAL RELEASE PASSED"

