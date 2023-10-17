import Alloy.C
open scoped Alloy.C

/-
Mac: brew install llvm

To use the bundled libc++ please add the following LDFLAGS:
  LDFLAGS="-L/opt/homebrew/opt/llvm/lib/c++ -Wl,-rpath,/opt/homebrew/opt/llvm/lib/c++"

llvm is keg-only, which means it was not symlinked into /opt/homebrew,
because macOS already provides this software and installing another version in
parallel can cause all kinds of trouble.

If you need to have llvm first in your PATH, run:
  echo 'export PATH="/opt/homebrew/opt/llvm/bin:$PATH"' >> ~/.zshrc

For compilers to find llvm you may need to set:
  export LDFLAGS="-L/opt/homebrew/opt/llvm/lib"
  export CPPFLAGS="-I/opt/homebrew/opt/llvm/include"
-/
alloy c include <lean/lean.h> <clang-c/Index.h>

/-

References:

- https://github.com/KyleMayes/clang-sys
- https://libclang.readthedocs.io/en/latest/
- https://clang.llvm.org/docs/LibClang.html
- https://github.com/llvm/llvm-project/blob/main/clang/include/clang-c/Index.h
- https://clangd.llvm.org/installation

- https://github.com/hargoniX/socket.lean/blob/main/Socket.lean

-/

-- --------------------------------------------------------------------------------
-- /-! ## Definition of Index                                                      -/
-- --------------------------------------------------------------------------------

alloy c section

typedef CXIndex Index;

static inline void noop_foreach(void *mod, b_lean_obj_arg fn) {
  -- do nothing since all types in Libclang do not contain nested Lean objects
}

static void CXIndex_finalize(void* ptr) {
  free(ptr);
}

end

alloy c extern_type Index => Index := {
  foreach := `noop_foreach
  finalize := `CXIndex_finalize
}

-- --------------------------------------------------------------------------------
-- /-! ## Definition of TranslationUnit                                                      -/
-- --------------------------------------------------------------------------------

alloy c section

typedef CXTranslationUnit TranslationUnit;

static void CXTranslationUnit_foreach(void* ptr, b_lean_obj_arg f) {
  lean_apply_1(f, ptr);
}

static void CXTranslationUnit_finalize(void* ptr) {
  free(ptr);
}

end

alloy c extern_type TranslationUnit => TranslationUnit := {
  foreach := `noop_foreach
  finalize := `CXTranslationUnit_finalize
}

--------------------------------------------------------------------------------
/-! ## Lean Interface                                                         -/
--------------------------------------------------------------------------------

alloy c extern "lean_clang_createIndex"
def Index.create (excludeDecls : Bool) : Index := {
  Index index = clang_createIndex(excludeDecls, 0);
  return to_lean<Index>(index);
}

alloy c extern "lean_clang_parseTranslationUnit"
def Index.parse (index : @&Index) (sourceFilename : @&String) : TranslationUnit := {
  TranslationUnit tu = clang_parseTranslationUnit(
    of_lean<Index>(index),
    lean_string_cstr(sourceFilename),
    NULL, 0, NULL, 0, CXTranslationUnit_None);
  return to_lean<TranslationUnit>(tu);
}

alloy c extern "lean_clang_saveTranslationUnit"
def TranslationUnit.save (tu : @&TranslationUnit) (filename : @&String) : UInt32 := {
  return clang_saveTranslationUnit(
    of_lean<TranslationUnit>(tu),
    lean_string_cstr(filename),
    CXSaveTranslationUnit_None
  );
}


