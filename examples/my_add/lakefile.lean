import Lake
open System Lake DSL

package my_add

require alloy from ".."/".."

module_data alloy.c.o.export : BuildJob FilePath
module_data alloy.c.o.noexport : BuildJob FilePath
lean_lib MyAdd where
  precompileModules := true
  nativeFacets := fun shouldExport =>
    if shouldExport then
      #[Module.oExportFacet, `alloy.c.o.export]
    else
      #[Module.oNoExportFacet, `alloy.c.o.noexport]

lean_lib Test

@[default_target]
lean_exe my_add where
  root := `Main
