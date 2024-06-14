import Lake
open Lake DSL

package Cpp where
  buildType := .debug
  precompileModules := true
  moreLinkArgs := #[s!"-L{__dir__}/.lake/build/lib",
    "-lstdc++"] -- "-v",  --, "-lc++", "-lc++abi", "-lunwind"] -- "-lstdc++"]
  weakLeanArgs := #[
    -- s!"--load-dynlib={__dir__}/build/lib/" ++ nameToSharedLib "xxx",
  ]

require alloy from ".."/".."

module_data alloy.cpp.o.export : BuildJob FilePath
module_data alloy.cpp.o.noexport : BuildJob FilePath

lean_lib Cpp {
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then
      #[Module.oExportFacet, `alloy.cpp.o.export]
    else
      #[Module.oNoExportFacet, `alloy.cpp.o.noexport]
}

-- @[default_target]
-- lean_exe alloycpp {
--   root := `Main
-- }

-- For now, test with `lake -R build Test -v`

lean_lib Test
