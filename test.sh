#!/usr/bin/env bash
set -euxo pipefail

LAKE=${LAKE:-lake}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

$LAKE build

pushd examples/my_add
./test.sh
popd

pushd examples/S
./test.sh
popd

# if env var CI is not set, we run the following tests
if [ -z ${CI+x} ]; then
  pushd examples/Libclang
  ./test.sh
  popd
fi

pushd examples/Cpp
./test.sh
popd

pushd tests/compile
./test.sh
popd

find tests/run -type f -name "*.lean" | xargs -n1 $LAKE env lean

# https://github.com/tydeu/lean4-alloy/issues/6
$LAKE env lean tests/envIncludePath.lean && false || true
CPATH=$SCRIPT_DIR/tests $LAKE env lean tests/envIncludePath.lean
C_INCLUDE_PATH=$SCRIPT_DIR/tests $LAKE env lean tests/envIncludePath.lean

echo "all done"
