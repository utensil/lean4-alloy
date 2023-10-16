/-
Copyright (c) 2022 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Alloy.C.IR
import Alloy.C.Shim
import Alloy.Util.Syntax
import Alloy.Util.Binder
import Lean.Compiler.NameMangling

namespace Alloy.C
open Lean Parser Elab Command

scoped syntax (name := leanExport) "LEAN_EXPORT" : cDeclSpec

def mkParams (fnType : Lean.Expr)
(bvs : Array BinderSyntaxView) (irParams : Array IR.Param)
: MacroM Params := do
  let mut decls := #[]
  let mut viewIdx := 0
  let mut paramIdx := 0
  let mut fnType := fnType
  for p in irParams do
    let mut bv? := none
    if fnType.isBinding then
      let name := fnType.bindingName!
      fnType := fnType.bindingBody!
      -- Attempt to match the parameter to a following binder of the same name
      for h : i in [viewIdx:bvs.size] do
        have := h.upper
        let bv := bvs[i]
        viewIdx := viewIdx + 1
        if bv.id.raw.getId = name then
          bv? := some bv
          break
    if p.ty.isIrrelevant then
      continue -- Lean omits irrelevant parameters for extern constants
    let (id, tyRef) : Ident × Syntax :=
      if let some bv := bv? then
        (⟨bv.id.raw⟩, bv.type)
      else
        (mkIdent <| Name.mkSimple s!"_{paramIdx}", .missing)
    let ty ← MonadRef.withRef tyRef <| expandIrParamTypeToC p.borrow p.ty
    decls := decls.push <| ← `(paramDecl| $ty:cTypeSpec $id:ident)
    paramIdx := paramIdx + 1
  `(params| $[$decls:paramDecl],*)

/--
Create an opaque Lean definition implemented by an external C function
included in the module's shim whose definition is provided here. That is:
```
alloy c extern "alloy_foo" def foo (x : UInt32) : UInt32 := {...}
```
is essentially equivalent to
```
@[extern "alloy_foo"] opaque foo (x : UInt32) : UInt32
alloy c section LEAN_EXPORT uint32_t alloy_foo(uint32_t x) {...}
```
-/
scoped elab (name := externDecl) doc?:(docComment)?
"alloy " &"c " ex:&"extern " sym?:(str)? attrs?:(Term.attributes)?
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
    LEAN_EXPORT%$ex $ty:cTypeSpec $id:ident($params:params) $body:compStmt
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