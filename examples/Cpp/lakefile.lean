import Lake
open Lake DSL

package Cpp where
  buildType := .debug
  precompileModules := true
  moreLinkArgs := #[s!"-L{__dir__}/build/lib",
    "-lstdc++"] -- "-v",  --, "-lc++", "-lc++abi", "-lunwind"] -- "-lstdc++"]
  weakLeanArgs := #[
    -- s!"--load-dynlib={__dir__}/build/lib/" ++ nameToSharedLib "xxx",
  ]

require alloy from ".."/".."

module_data alloy.cpp.o : BuildJob FilePath
lean_lib Cpp {
  precompileModules := true
  nativeFacets := #[Module.oFacet, `alloy.cpp.o]
}

-- @[default_target]
-- lean_exe alloycpp {
--   root := `Main
-- }

-- For now, test with `lake -R build Test -v`

lean_lib Test
