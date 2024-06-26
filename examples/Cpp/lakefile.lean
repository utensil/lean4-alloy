import Lake
open Lake DSL

package Cpp where
  buildType := .debug
  -- precompileModules := true
  -- moreLinkArgs := #[s!"-L{__dir__}/.lake/build/lib",
  --   "-lstdc++"] -- "-v",  --, "-lc++", "-lc++abi", "-lunwind"] -- "-lstdc++"]
  -- weakLeanArgs := #[
  --   -- s!"--load-dynlib={__dir__}/build/lib/" ++ nameToSharedLib "xxx",
  -- ]
  moreLinkArgs := #["-lstdc++"]

require alloy from ".."/".."

module_data alloy.cpp.o.export : BuildJob FilePath
module_data alloy.cpp.o.noexport : BuildJob FilePath

lean_lib Cpp where
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then
      #[Module.oExportFacet, `alloy.cpp.o.export]
    else
      #[Module.oNoExportFacet, `alloy.cpp.o.noexport]

-- @[default_target]
lean_exe scpp where
  root := `Main
  supportInterpreter := true

lean_lib Test
