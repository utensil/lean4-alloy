import Lake
open Lake DSL

package Libclang where
  buildType := .debug
  moreLinkArgs := #[s!"-L{__dir__}/build/lib", s!"-L/opt/homebrew/opt/llvm/lib", "-lclang"]
  weakLeanArgs := #[
    s!"--load-dynlib=/opt/homebrew/opt/llvm/lib/" ++ nameToSharedLib "LLVM",
    s!"--load-dynlib=/opt/homebrew/opt/llvm/lib/" ++ nameToSharedLib "clang"
  ]

/-
export DYLD_PRINT_LIBRARIES=1
export DYLD_PRINT_APIS=1
export DYLD_PRINT_WARNINGS=1

export DYLD_PRINT_LIBRARIES=0
export DYLD_PRINT_APIS=0
export DYLD_PRINT_WARNINGS=0
-/

require alloy from ".."/".."

module_data alloy.c.o.export : BuildJob FilePath
module_data alloy.c.o.noexport : BuildJob FilePath

lean_lib Libclang {
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then
      #[Module.oExportFacet, `alloy.c.o.export]
    else
      #[Module.oNoExportFacet, `alloy.c.o.noexport]
  moreLeancArgs := #[s!"-I/opt/homebrew/opt/llvm/include"] -- FIXME: for mac only now
  moreLinkArgs := #[s!"-L/opt/homebrew/opt/llvm/lib"] -- FIXME: for mac only now
}

lean_lib Test

@[default_target]
lean_exe clangp {
  root := `Main
}
