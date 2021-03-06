module System.Protocol

import Effects
import Effect.StdIO
import Effect.Msg

%access public

using (xs : List a)
  data Elem : a -> List a -> Type where
       Here  : Elem x (x :: xs)
       There : Elem x xs -> Elem x (y :: xs)

%reflection
reflectListElem : List a -> Tactic
reflectListElem [] = Refine "Here" `Seq` Solve
reflectListElem (x :: xs)
     = Try (Refine "Here" `Seq` Solve)
           (Refine "There" `Seq` (Solve `Seq` reflectListElem xs))
-- TMP HACK! FIXME!
-- The evaluator needs a 'function case' to know its a reflection function
-- until we propagate that information! Without this, the _ case won't get
-- matched. 
reflectListElem (x ++ y) = Refine "Here" `Seq` Solve
reflectListElem _ = Refine "Here" `Seq` Solve

%reflection
reflectElem : (P : Type) -> Tactic
reflectElem (Elem a xs)
     = reflectListElem xs `Seq` Solve

syntax IsElem = tactics { byReflection reflectElem; }


using (xs : List princ)
  data Protocol : List princ -> Type -> Type where
       Send'  : (from : princ) -> (to : princ) -> (a : Type) ->
                Elem from xs   -> Elem to xs -> Protocol xs a
       (>>=)  : Protocol xs a -> (a -> Protocol xs b) -> Protocol xs b
       Rec    : Inf (Protocol xs a) -> Protocol xs a
       pure   : a -> Protocol xs a

  Done : Protocol xs ()
  Done = pure ()

  Send : (from : princ) -> (to : princ) -> (a : Type) ->
         {default IsElem pf : Elem from xs} ->
         {default IsElem pt : Elem to xs} ->
         Protocol xs a
  Send from to {pf} {pt} = Send' from to pf pt

  syntax [from] "==>" [to] "|" [t] = Send' from to t IsElem IsElem

  total
  mkProcess : (x : princ) -> Protocol xs ty -> (ty -> Actions) -> Actions
  mkProcess x (Send' from to ty fp tp) k with (prim__syntactic_eq _ _ x from)
    mkProcess x (Send' from to ty fp tp) k | Nothing with (prim__syntactic_eq _ _ x to)
      mkProcess x (Send' from to ty fp tp) k | Nothing | Nothing = End
      mkProcess x (Send' from x ty fp tp) k | Nothing | (Just refl) 
            = DoRecv from ty k
    mkProcess x (Send' x to ty fp tp) k | (Just refl) 
            = DoSend to ty k
  mkProcess x (y >>= f) k = mkProcess x y (\cmd => mkProcess x (f cmd) k)
  mkProcess x (Rec p) k = DoRec (mkProcess x p k)
  mkProcess x (pure y) k = End

Agent : {xs : List princ} ->
           (Type -> Type) ->
           Protocol xs () -> princ -> 
           List (princ, chan) ->
           List EFFECT -> Type -> Type
Agent {princ} {chan} m s p ps es t
    = Eff m t (MSG princ m ps (mkProcess p s (\x => End)) :: es)
              (\v => MSG princ m ps End :: es)

Process : {xs : List princ} ->
           (Type -> Type) ->
           Protocol xs () -> princ -> 
           List (princ, PID) ->
           List EFFECT -> Type -> Type
Process m s p ps es t = Agent m s p ps (CONC :: es) t

IPC : {xs : List princ} ->
      Protocol xs () -> princ -> 
      List (princ, File) ->
      List EFFECT -> Type -> Type
IPC s p ps es t = Agent (IOExcept String) s p ps es t

syntax spawn [p] [rs] = fork (\parent => runInit (Proto :: () :: rs) (p parent))
syntax runConc [es] [p] = runInit (Proto :: () :: es) p

