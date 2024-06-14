/-
Copyright (c) 2022 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Alloy.C.ExternImpl

namespace Alloy.C
open Lean Parser Elab Command

/--
Create an opaque Lean definition implemented by an external C function
whose definition is provided here. That is:

```
alloy c extern "alloy_foo" def foo (x : UInt32) : UInt32 := {...}
```

is essentially equivalent to

```
@[extern "alloy_foo"] opaque foo (x : UInt32) : UInt32
alloy c section LEAN_EXPORT uint32_t alloy_foo(uint32_t x) {...}
```
-/
scoped syntax (name := externDecl)
(docComment)? (Term.attributes)?  "alloy " &"c " &"extern " (str)?
(visibility)? «unsafe»? "def " declId binders " : " term " := " stmtSeq
: command

elab_rules : command
| `(externDecl| $[$doc?]? $[$attrs?]? alloy c extern%$exTk $[$sym?]?
  $[$vis?]? $[unsafe%$uTk?]? def $id $bs* : $ty := $stmts*) => do
  let cmd ← `($[$doc?]? $[$attrs?]? $[$vis?]? noncomputable $[unsafe%$uTk?]? opaque $id $[$bs]* : $ty)
  withMacroExpansion (← getRef) cmd <| elabCommand cmd
  let bvs ← liftMacroM <| bs.concatMapM matchBinder
  elabExternImpl exTk sym? ⟨id.raw[0]⟩ bvs ty (packBody stmts)

-- declaring this syntax si we can use it in the line marked "leanCppExport" below
scoped syntax (name := leanCppExport) "extern \"C\"" : cDeclSpec

-- this is a copy of `elabExternImpl` with modifications marked with "mod begin/end"
def elabExternImplCpp (exTk : Syntax) (sym? : Option StrLit) (id : Ident) (bvs : Array BinderSyntaxView)
(type : Syntax) (body : CompStmt) : CommandElabM Unit := do
  let name ← liftCoreM <| realizeGlobalConstNoOverloadWithInfo id
  let (cId, extSym) :=
    match sym? with
    | some sym =>
      (mkIdentFrom sym (.mkSimple sym.getString), sym.getString)
    | none =>
      let extSym := "_alloy_c_" ++ name.mangle
      (mkIdentFrom id (.mkSimple extSym), extSym)
  withRef id <| setExtern name extSym
  let env ← getEnv
  let some info := env.find? name
    | throwErrorAt id "failed to find Lean definition"
  let some decl := IR.findEnvDecl env name
    | throwErrorAt id "failed to find Lean IR definition"
  let ty ← liftMacroM <| MonadRef.withRef type <| expandIrResultTypeToC false decl.resultType
  let params ← liftTermElabM <| mkParams info.type bvs decl.params

  -- mod begin
  -- leanCppExport: prefix the function with `extern "C"`
  let fn ← MonadRef.withRef Syntax.missing <| `(function|
    extern "C" LEAN_EXPORT%$exTk $ty:cTypeSpec $cId:ident($params:params) $body:compStmt
  )
  -- mod end

  let cmd ← `(alloy c section $fn:function end)
  withMacroExpansion (← getRef) cmd <| elabCommand cmd

scoped syntax (name := externCppDecl)
(docComment)? (Term.attributes)? "alloy " &"cpp " &"extern " (str)?
(visibility)? «unsafe»? "def " declId binders " : " term " := " stmtSeq
: command

elab_rules : command
| `(externCppDecl| $[$doc?]? $[$attrs?]? alloy cpp extern%$exTk $[$sym?]?
  $[$vis?]? $[unsafe%$uTk?]? def $id $bs* : $ty := $stmts*) => do
  let cmd ← `($[$doc?]? $[$attrs?]? $[$vis?]? noncomputable $[unsafe%$uTk?]? opaque $id $[$bs]* : $ty)
  withMacroExpansion (← getRef) cmd <| elabCommand cmd
  let bvs ← liftMacroM <| bs.concatMapM matchBinder
  elabExternImplCpp exTk sym? ⟨id.raw[0]⟩ bvs ty (packBody stmts)
