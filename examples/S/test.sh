set -ex
rm -rf .lake
LAKE=${LAKE:-lake}
$LAKE build -U
$LAKE build Test -v

# dyld[55259]: Symbol not found: _LLVMInitializeAMDGPUAsmParser
#   Referenced from: <C328DC0B-007D-3622-ADB4-56E52AB94344> /opt/homebrew/Cellar/llvm/17.0.2/lib/libclang.dylib
#   Expected in:     <9932BC93-8D2E-309F-BE82-45392DF49A77> ~/.elan/toolchains/leanprover--lean4---4.1.0/lib/libLLVM.dylib

# $LAKE exe clangp

.lake/build/bin/s
./build/bin/clangp