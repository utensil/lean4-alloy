set -ex
rm -rf .lake/build

export DYLD_PRINT_LIBRARIES=1
export DYLD_PRINT_APIS=1
export DYLD_PRINT_WARNINGS=1
unset DYLD_PRINT_LIBRARIES
unset DYLD_PRINT_APIS
unset DYLD_PRINT_WARNINGS

LAKE=${LAKE:-lake}
$LAKE build -U
$LAKE build Test -v
# dyld[48379]: Symbol not found: _LLVMInitializeAMDGPUAsmParser
#   Referenced from: <878DD7CF-0D2B-35AE-9ECD-AE0BAF9BAC21> /opt/homebrew/Cellar/llvm/17.0.6_1/lib/libclang.dylib
#   Expected in:     <9932BC93-8D2E-309F-BE82-45392DF49A77> /Users/utensil/.elan/toolchains/leanprover--lean4---4.8.0-rc1/lib/libLLVM.dylib
# $LAKE exe clangp
