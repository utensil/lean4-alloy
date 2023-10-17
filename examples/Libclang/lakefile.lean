import Lake
open Lake DSL

package Libclang where
  buildType := .debug
  -- moreLinkArgs := #[s!"-L{__dir__}/build/lib"]
  weakLeanArgs := #[
    s!"--load-dynlib=/opt/homebrew/opt/llvm/lib/" ++ nameToSharedLib "clang"
  ]

require alloy from ".."/".."

module_data alloy.c.o : BuildJob FilePath

lean_lib Libclang {
  precompileModules := true
  nativeFacets := #[Module.oFacet, `alloy.c.o]
  moreLeancArgs := #[s!"-I/opt/homebrew/opt/llvm/include"] -- FIXME: for mac only now
  moreLinkArgs := #[s!"-L/opt/homebrew/opt/llvm/lib"] -- FIXME: for mac only now
}

lean_lib Test
