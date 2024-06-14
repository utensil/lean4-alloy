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


scoped syntax (name := leanCppExport) "extern \"C\"" : cDeclSpec

scoped elab (name := externCppDecl) doc?:(docComment)?
"alloy " &"cpp " ex:&"extern " sym?:(str)? attrs?:(Term.attributes)?
"def " id:declId bx:binders " : " type:term " := " body:cStmt : command => do

  -- Lean Definition
  let name := (← getCurrNamespace) ++ id.raw[0].getId
  let (symLit, extSym) :=
    match sym? with
    | some sym => (sym, sym.getString)
    | none =>
      let extSym := "_alloy_c_" ++ name.mangle
      (Syntax.mkStrLit extSym <| SourceInfo.fromRef id, extSym)
  let attr ← withRef ex `(Term.attrInstance| extern $symLit:str)
  let attrs := #[attr] ++ expandAttrs attrs?
  let bs := bx.raw.getArgs.map (⟨.⟩)
  let cmd ← `($[$doc?]? @[$attrs,*] opaque $id $[$bs]* : $type)
  withMacroExpansion (← getRef) cmd <| elabCommand cmd

  -- C Definition
  let env ← getEnv
  let some info := env.find? name
    | throwError "failed to find Lean definition"
  let some decl := IR.findEnvDecl env name
    | throwError "failed to find Lean IR definition"
  let bvs ← liftMacroM <| bs.concatMapM matchBinder
  let id := mkIdentFrom symLit (Name.mkSimple extSym)
  let ty ← liftMacroM <| withRef type <| expandIrResultTypeToC false decl.resultType
  let params ← liftMacroM <| mkParams info.type bvs decl.params
  let body := packBody body
  let fn ← MonadRef.withRef Syntax.missing <| `(function|
    extern "C" LEAN_EXPORT%$ex $ty:cTypeSpec $id:ident($params:params) $body:compStmt
  )
  let cmd ← `(alloy c section $fn:function end)
  withMacroExpansion (← getRef) cmd <| elabCommand cmd


scoped syntax (name := leanCppExport) "extern \"C\"" : cDeclSpec

scoped elab (name := externCppDecl) doc?:(docComment)?
"alloy " &"cpp " ex:&"extern " sym?:(str)? attrs?:(Term.attributes)?
"def " id:declId bx:binders " : " type:term " := " body:cStmt : command => do

  -- Lean Definition
  let name := (← getCurrNamespace) ++ id.raw[0].getId
  let (symLit, extSym) :=
    match sym? with
    | some sym => (sym, sym.getString)
    | none =>
      let extSym := "_alloy_c_" ++ name.mangle
      (Syntax.mkStrLit extSym <| SourceInfo.fromRef id, extSym)
  let attr ← withRef ex `(Term.attrInstance| extern $symLit:str)
  let attrs := #[attr] ++ expandAttrs attrs?
  let bs := bx.raw.getArgs.map (⟨.⟩)
  let cmd ← `($[$doc?]? @[$attrs,*] opaque $id $[$bs]* : $type)
  withMacroExpansion (← getRef) cmd <| elabCommand cmd

  -- C Definition
  let env ← getEnv
  let some info := env.find? name
    | throwError "failed to find Lean definition"
  let some decl := IR.findEnvDecl env name
    | throwError "failed to find Lean IR definition"
  let bvs ← liftMacroM <| bs.concatMapM matchBinder
  let id := mkIdentFrom symLit (Name.mkSimple extSym)
  let ty ← liftMacroM <| withRef type <| expandIrResultTypeToC false decl.resultType
  let params ← liftMacroM <| mkParams info.type bvs decl.params
  let body := packBody body
  let fn ← MonadRef.withRef Syntax.missing <| `(function|
    extern "C" LEAN_EXPORT%$ex $ty:cTypeSpec $id:ident($params:params) $body:compStmt
  )
  let cmd ← `(alloy c section $fn:function end)
  withMacroExpansion (← getRef) cmd <| elabCommand cmd
