set -ex
rm -rf .lake/build
LAKE=${LAKE:-lake}

# export DYLD_PRINT_LIBRARIES=1
# export DYLD_PRINT_APIS=1
# export DYLD_PRINT_WARNINGS=1
# unset DYLD_PRINT_LIBRARIES
# unset DYLD_PRINT_APIS
# unset DYLD_PRINT_WARNINGS

$LAKE build -U
$LAKE build Test -v
$LAKE exe scpp
