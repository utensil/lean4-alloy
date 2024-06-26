import Lake
open Lake DSL

package s where
  buildType := .debug

require alloy from ".."/".."

module_data alloy.c.o.export : BuildJob FilePath
module_data alloy.c.o.noexport : BuildJob FilePath
lean_lib S where
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then
      #[Module.oExportFacet, `alloy.c.o.export]
    else
      #[Module.oNoExportFacet, `alloy.c.o.noexport]

@[default_target]
lean_exe s where
  root := `Main

lean_lib Test
