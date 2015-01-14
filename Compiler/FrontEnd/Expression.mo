/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2014, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated package Expression
" file:        Expression.mo
  package:     Expression
  description: Expressions

  RCS: $Id$

  This file contains the module `Expression\', which contains data types for
  describing expressions, after they have been examined by the
  static analyzer in the module `StaticExp\'.  There are of course
  great similarities with the expression types in the `Absyn\'
  module, but there are also several important differences.

  No overloading of operators occur, and subscripts have been
  checked to see if they are slices.  All expressions are also type
  consistent, and all implicit type conversions in the AST are made
  explicit here."

// public imports
public import Absyn;
public import DAE;

protected
type ComponentRef = DAE.ComponentRef;
type Exp = DAE.Exp;
type Operator = DAE.Operator;
type Type = DAE.Type;
type Subscript = DAE.Subscript;
type Var = DAE.Var;

// protected imports
protected import Array;
protected import ClassInf;
protected import ComponentReference;
protected import Config;
protected import DAEUtil;
protected import Debug;
protected import FCore;
protected import FGraph;
protected import Error;
protected import ExpressionDump;
protected import ExpressionSimplify;
protected import Dump;
protected import Flags;
protected import List;
protected import Patternm;
protected import Prefix;
protected import Static;
protected import System; // stringReal
protected import Types;
protected import Util;

/***************************************************/
/* transform to other types */
/***************************************************/

public function intSubscript
  "Converts an integer into an index subscript."
  input Integer inInteger;
  output DAE.Subscript outSubscript;
algorithm
  outSubscript := DAE.INDEX(DAE.ICONST(inInteger));
end intSubscript;

public function intSubscripts
  "Converts a list of integers into index subscripts."
  input list<Integer> inIntegers;
  output list<DAE.Subscript> outSubscripts;
algorithm
  outSubscripts := List.map(inIntegers, intSubscript);
end intSubscripts;

protected function subscriptInt
  "Tries to convert a subscript to an integer index."
  input DAE.Subscript inSubscript;
  output Integer outInteger;
algorithm
  outInteger := match(inSubscript)
    local
      Integer x;
      Boolean b;
    case DAE.INDEX(exp = DAE.ICONST(integer = x)) then x;
    case DAE.INDEX(exp = DAE.ENUM_LITERAL(index = x)) then x;
    case DAE.INDEX(exp = DAE.BCONST(bool = b)) then if b then 1 else 0;
/*
    else
      equation
        Error.addInternalError("subscriptInt failed: " + ExpressionDump.printSubscriptStr(inSubscript), sourceInfo());
      then fail();
 */
  end match;
end subscriptInt;

public function subscriptsInt
  "Tries to convert a list of subscripts to integer indices."
  input list<DAE.Subscript> inSubscripts;
  output list<Integer> outIntegers;
algorithm
  outIntegers := List.map(inSubscripts, subscriptInt);
end subscriptsInt;

public function dimensionIsZero
  input DAE.Dimension inDimension;
  output Boolean outIsZero;
algorithm
  outIsZero := matchcontinue(inDimension)
    case _
      equation
        true = 0 == dimensionSize(inDimension);
      then
        true;

    else false;
  end matchcontinue;
end dimensionIsZero;

public function unelabExp
"Transform an DAE.Exp into Absyn.Expression.
  Note: This function currently only works for
  constants and component references."
  input DAE.Exp inExp;
  output Absyn.Exp outExp;
algorithm
  outExp := matchcontinue (inExp)
    local
      Integer i;
      Real r;
      String s;
      Boolean b;
      Absyn.ComponentRef cr_1;
      ComponentRef cr;
      list<Absyn.Exp> expl_1,aexpl;
      list<DAE.Exp> expl;
      DAE.Exp e1,e2,e3;
      Operator op;
      Absyn.Exp ae1,ae2,ae3;
      Absyn.Operator aop;
      list<list<DAE.Exp>> mexpl2;
      list<list<Absyn.Exp>> amexpl;
      Absyn.ComponentRef acref;
      Absyn.Path path;
      Absyn.CodeNode code;
      DAE.ReductionIterators riters;
      Absyn.ForIterators aiters;
      DAE.Type ty;
      DAE.Dimensions dims;
      Absyn.ReductionIterType iterType;

    case (DAE.ICONST(integer = i)) then Absyn.INTEGER(i);
    case (DAE.RCONST(real = r))
      equation
        s = realString(r);
      then Absyn.REAL(s);
    case (DAE.SCONST(string = s)) then Absyn.STRING(s);
    case (DAE.BCONST(bool = b)) then Absyn.BOOL(b);
    case (DAE.ENUM_LITERAL(name = path))
      equation
        cr_1 = Absyn.pathToCref(path);
      then Absyn.CREF(cr_1);

    case (DAE.CREF(componentRef = cr))
      equation
        cr_1 = ComponentReference.unelabCref(cr);
      then
        Absyn.CREF(cr_1);

    case(DAE.BINARY(e1,op,e2)) equation
      aop = unelabOperator(op);
      ae1 = unelabExp(e1);
      ae2 = unelabExp(e2);
    then Absyn.BINARY(ae1,aop,ae2);

    case(DAE.UNARY(op,e1)) equation
      aop = unelabOperator(op);
      ae1 = unelabExp(e1);
    then Absyn.UNARY(aop,ae1);

    case(DAE.LBINARY(e1,op,e2)) equation
      aop = unelabOperator(op);
      ae1 = unelabExp(e1);
      ae2 = unelabExp(e2);
    then Absyn.LBINARY(ae1,aop,ae2);

    case(DAE.LUNARY(op,e1)) equation
      aop = unelabOperator(op);
      ae1 = unelabExp(e1);
    then Absyn.LUNARY(aop,ae1);

    case(DAE.RELATION(exp1=e1,operator=op,exp2=e2)) equation
      aop = unelabOperator(op);
      ae1 = unelabExp(e1);
      ae2 = unelabExp(e2);
    then Absyn.RELATION(ae1,aop,ae2);

    case(DAE.IFEXP(e1,e2,e3)) equation
      ae1 = unelabExp(e1);
      ae2 = unelabExp(e2);
      ae3 = unelabExp(e3);
    then Absyn.IFEXP(ae1,ae2,ae3,{});

    case (DAE.CALL(path,expl,_))
      equation
        aexpl = List.map(expl,unelabExp);
        acref = Absyn.pathToCref(path);
      then Absyn.CALL(acref,Absyn.FUNCTIONARGS(aexpl,{}));

    case (DAE.RECORD(path = path,exps = expl))
      equation
        aexpl = List.map(expl,unelabExp);
        acref = Absyn.pathToCref(path);
      then Absyn.CALL(acref,Absyn.FUNCTIONARGS(aexpl,{}));

    case(DAE.PARTEVALFUNCTION(path,expl,_,_))
      equation
        aexpl = List.map(expl,unelabExp);
        acref = Absyn.pathToCref(path);
      then
        Absyn.PARTEVALFUNCTION(acref,Absyn.FUNCTIONARGS(aexpl,{}));

    case (DAE.ARRAY(array = {}, ty = ty))
      equation
        (ty,dims) = Types.flattenArrayTypeOpt(ty);
        ae1 = unleabZeroExpFromType(ty);
        expl_1 = List.map(dims, unelabDimensionToFillExp);
      then
        Absyn.CALL(Absyn.CREF_IDENT("fill",{}),Absyn.FUNCTIONARGS(ae1::expl_1,{}));

    case (DAE.ARRAY(array = expl))
      equation
        expl_1 = List.map(expl, unelabExp);
      then
        Absyn.ARRAY(expl_1);

    case(DAE.MATRIX(matrix = mexpl2))
      equation
        amexpl = List.mapList(mexpl2,unelabExp);
      then (Absyn.MATRIX(amexpl));

    case(DAE.RANGE(_,e1,SOME(e2),e3)) equation
      ae1 = unelabExp(e1);
      ae2 = unelabExp(e2);
      ae3 = unelabExp(e3);
    then Absyn.RANGE(ae1,SOME(ae2),ae3);

    case(DAE.RANGE(_,e1,NONE(),e3)) equation
      ae1 = unelabExp(e1);
      ae3 = unelabExp(e3);
    then Absyn.RANGE(ae1,NONE(),ae3);

    case(DAE.TUPLE(expl))
      equation
        expl_1 = List.map(expl, unelabExp);
      then
        Absyn.TUPLE(expl_1);

    case(DAE.CAST(_,e1)) equation
      ae1 = unelabExp(e1);
    then ae1;

     // ASUB can not be unelabed since it has no representation in Absyn.
    case(DAE.ASUB(_,_)) equation
      print("Internal Error, can not unelab ASUB\n");
    then fail();

    // TSUB(expression) => expression
    case(DAE.TSUB(e1,_,_)) equation
      ae1 = unelabExp(e1);
    then ae1;

    case(DAE.SIZE(e1,SOME(e2))) equation
      ae1 = unelabExp(e1);
      ae2 = unelabExp(e2);
    then Absyn.CALL(Absyn.CREF_IDENT("size",{}),Absyn.FUNCTIONARGS({ae1,ae2},{}));

    /* WHAT? exactly the same case as above???!!!
    case(DAE.SIZE(e1,SOME(e2))) equation
      ae1 = unelabExp(e1);
      ae2 = unelabExp(e2);
    then Absyn.CALL(Absyn.CREF_IDENT("size",{}),Absyn.FUNCTIONARGS({ae1,ae2},{}));
    */

    case(DAE.CODE(code,_)) then Absyn.CODE(code);

    case DAE.REDUCTION(reductionInfo=DAE.REDUCTIONINFO(iterType=iterType,path=path),expr=e1,iterators=riters)
      equation
      //print("unelab of reduction not impl. yet");
      acref = Absyn.pathToCref(path);
      ae1 = unelabExp(e1);
      aiters = List.map(riters, unelabReductionIterator);
      then Absyn.CALL(acref, Absyn.FOR_ITER_FARG(ae1, iterType, aiters));

    else
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        print("Expression.unelabExp failed on: " + ExpressionDump.printExpStr(inExp) + "\n");
      then
        fail();
  end matchcontinue;
end unelabExp;

public function unelabDimension
"Transform an DAE.Dimension into Absyn.Subscript, if possible"
  input DAE.Dimension inDim;
  output Absyn.Subscript outDim;
algorithm
  outDim := match (inDim)
    local
      Integer i;
      Absyn.Path p;
      Absyn.ComponentRef c;
      DAE.Exp e;
      Absyn.Exp ae;

    case (DAE.DIM_INTEGER(i)) then Absyn.SUBSCRIPT(Absyn.INTEGER(i));

    case (DAE.DIM_BOOLEAN()) then Absyn.SUBSCRIPT(Absyn.CREF(Absyn.CREF_IDENT("Boolean", {})));

    case (DAE.DIM_ENUM(enumTypeName = p))
      equation
        c = Absyn.pathToCref(p);
      then
        Absyn.SUBSCRIPT(Absyn.CREF(c));

    case (DAE.DIM_EXP(e))
      equation
        ae = unelabExp(e);
      then
        Absyn.SUBSCRIPT(ae);

    case (DAE.DIM_UNKNOWN()) then Absyn.NOSUB();

  end match;
end unelabDimension;

protected function unleabZeroExpFromType
  input DAE.Type ty;
  output Absyn.Exp outExp;
algorithm
  outExp := match ty
    case DAE.T_BOOL() then Absyn.BOOL(false);
    case DAE.T_STRING() then Absyn.STRING("");
    case DAE.T_INTEGER() then Absyn.INTEGER(0);
    case DAE.T_REAL() then Absyn.REAL("0.0");
    case DAE.T_UNKNOWN() then Absyn.REAL("0.0"); /* Look at the crap unelabMod needs... */
  end match;
end unleabZeroExpFromType;

protected function unelabDimensionToFillExp
"Transform an DAE.Dimension into Absyn.Exp, if possible"
  input DAE.Dimension inDim;
  output Absyn.Exp outExp;
algorithm
  outExp := matchcontinue (inDim)
    local
      Integer i;
      DAE.Exp e;

    case (DAE.DIM_INTEGER(i)) then Absyn.INTEGER(i);

    case (DAE.DIM_EXP(e)) then unelabExp(e);

    else Absyn.INTEGER(1); /* Probably bad, but only used with zero-length arrays */

  end matchcontinue;
end unelabDimensionToFillExp;

protected function unelabReductionIterator
  input DAE.ReductionIterator riter;
  output Absyn.ForIterator aiter;
algorithm
  aiter := match riter
    local
      String id;
      DAE.Exp exp;
      Option<DAE.Exp> gexp;
      Absyn.Exp aexp;
      Option<Absyn.Exp> agexp;
    case DAE.REDUCTIONITER(id=id,exp=exp,guardExp=gexp)
      equation
        aexp = unelabExp(exp);
        agexp = Util.applyOption(gexp, unelabExp);
      then Absyn.ITERATOR(id,agexp,SOME(aexp));
  end match;
end unelabReductionIterator;

protected function unelabOperator "help function to unelabExpression."
input DAE.Operator op;
output Absyn.Operator aop;
algorithm
  aop := match(op)
    case(DAE.ADD(_)) then Absyn.ADD();
    case(DAE.SUB(_)) then Absyn.SUB();
    case(DAE.MUL(_)) then Absyn.MUL();
    case(DAE.DIV(_)) then Absyn.DIV();
    case(DAE.POW(_)) then Absyn.POW();
    case(DAE.UMINUS(_)) then Absyn.UMINUS();
    case(DAE.UMINUS_ARR(_)) then Absyn.UMINUS();
    case(DAE.ADD_ARR(_)) then Absyn.ADD();
    case(DAE.SUB_ARR(_)) then Absyn.SUB();
    case(DAE.MUL_ARR(_)) then Absyn.MUL();
    case(DAE.DIV_ARR(_)) then Absyn.DIV();
    case(DAE.MUL_ARRAY_SCALAR(_)) then Absyn.MUL();
    case(DAE.ADD_ARRAY_SCALAR(_)) then Absyn.ADD();
    case(DAE.SUB_SCALAR_ARRAY(_)) then Absyn.SUB();
    case(DAE.MUL_SCALAR_PRODUCT(_)) then Absyn.MUL();
    case(DAE.MUL_MATRIX_PRODUCT(_)) then Absyn.MUL();
    case(DAE.DIV_SCALAR_ARRAY(_)) then Absyn.DIV();
    case(DAE.DIV_ARRAY_SCALAR(_)) then Absyn.DIV();
    case(DAE.POW_SCALAR_ARRAY(_)) then Absyn.POW();
    case(DAE.POW_ARRAY_SCALAR(_)) then Absyn.POW();
    case(DAE.POW_ARR(_)) then Absyn.POW();
    case(DAE.POW_ARR2(_)) then Absyn.POW();
    case(DAE.AND(_)) then Absyn.AND();
    case(DAE.OR(_)) then Absyn.OR();
    case(DAE.NOT(_)) then Absyn.NOT();
    case(DAE.LESS(_)) then Absyn.LESS();
    case(DAE.LESSEQ(_)) then Absyn.LESSEQ();
    case(DAE.GREATER(_)) then Absyn.GREATER();
    case(DAE.GREATEREQ(_)) then Absyn.GREATEREQ();
    case(DAE.EQUAL(_)) then Absyn.EQUAL();
    case(DAE.NEQUAL(_)) then Absyn.NEQUAL();
  end match;
end unelabOperator;

public function stringifyCrefs
"This function takes an expression and transforms all component
  reference  names contained in the expression to a simpler form.
  For instance DAE.CREF_QUAL(a,{}, DAE.CREF_IDENT(b,{})) becomes
  DAE.CREF_IDENT(a.b,{})

  NOTE: This function should not be used in OMC, since the OMC backend no longer
        uses stringified components. It is still used by MathCore though."
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  outExp := traverseExpDummy(inExp, traversingstringifyCrefFinder);
end stringifyCrefs;

public function traversingstringifyCrefFinder "
helper for stringifyCrefs"
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  outExp := match inExp
    local
      ComponentRef cr,crs;
      Type ty;
      DAE.Exp e;
      list<Boolean> blist;

    case DAE.CREF(ty = DAE.T_FUNCTION_REFERENCE_VAR())
      then inExp;

    case DAE.CREF(ty = DAE.T_FUNCTION_REFERENCE_FUNC())
      then inExp;

    case DAE.CREF(cr,ty)
      equation
        crs = ComponentReference.stringifyComponentRef(cr);
      then makeCrefExp(crs,ty);

    else inExp;

  end match;
end traversingstringifyCrefFinder;

public function CodeVarToCref
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  outExp := match(inExp)
    local
      ComponentRef e_cref;
      Absyn.ComponentRef cref;
      DAE.Exp e;

    case(DAE.CODE(Absyn.C_VARIABLENAME(cref),_))
      equation
        (_,e_cref) = Static.elabUntypedCref(FCore.emptyCache(),FGraph.empty(),cref,false,Prefix.NOPRE(),Absyn.dummyInfo);
        e = crefExp(e_cref);
      then
        e;

    case(DAE.CODE(Absyn.C_EXPRESSION(Absyn.CALL(Absyn.CREF_IDENT("der",{}),Absyn.FUNCTIONARGS({Absyn.CREF(cref)},{}))),_))
      equation
        (_,e_cref) = Static.elabUntypedCref(FCore.emptyCache(),FGraph.empty(),cref,false,Prefix.NOPRE(),Absyn.dummyInfo);
        e = crefExp(e_cref);
      then
        DAE.CALL(Absyn.IDENT("der"),{e},DAE.callAttrBuiltinReal);
  end match;
end CodeVarToCref;

public function realToIntIfPossible
"converts to ICONST if possible. If it does
 not fit, a RCONST is returned instead."
  input Real inVal;
  output DAE.Exp outVal;
algorithm
  outVal := matchcontinue(inVal)
    local
      Integer i;

    case  _
      equation
        i = realInt(inVal);
      then
        DAE.ICONST(i);

    case _ then DAE.RCONST(inVal);
  end matchcontinue;
end realToIntIfPossible;

public function liftArrayR "
  function liftArrayR
  Converts a type into an array type with dimension n as first dim"
  input DAE.Type tp;
  input DAE.Dimension n;
  output DAE.Type outTp;
algorithm
  outTp := match(tp,n)
    local
      Type elt_tp;
      list<DAE.Dimension> dims;
      DAE.TypeSource ts;

    case(DAE.T_ARRAY(elt_tp,dims,ts),_)
      equation
        dims = n::dims;
      then
        DAE.T_ARRAY(elt_tp,dims,ts);

    else DAE.T_ARRAY(tp,{n},DAE.emptyTypeSource);

  end match;
end liftArrayR;

public function dimensionSizeConstantExp
  "Converts (extracts) a dimension to an expression.
  This function will fail if dimension is unknown or an expression (in case the dimension is from a different scope).
  If you want to(kind of) handle unknown dims use dimensionSizeExpHandleUnkown."
  input DAE.Dimension dim;
  output DAE.Exp exp;
algorithm
  exp := match(dim)
    local
      Integer i;
      DAE.Exp e;

    case DAE.DIM_INTEGER(integer = i) then DAE.ICONST(i);
    case DAE.DIM_ENUM(size = i) then DAE.ICONST(i);
    case DAE.DIM_BOOLEAN() then DAE.ICONST(2);
  end match;
end dimensionSizeConstantExp;

public function dimensionSizeExp
  "Converts (extracts) a dimension to an expression.
  This function will fail if dimension is unknown. i.e. DIM_UNKNOWN.
  If you want to(kind of) handle unknown dims use dimensionSizeExpHandleUnkown."
  input DAE.Dimension dim;
  output DAE.Exp exp;
algorithm
  exp := match(dim)
    local
      Integer i;
      DAE.Exp e;

    case DAE.DIM_INTEGER(integer = i) then DAE.ICONST(i);
    case DAE.DIM_ENUM(size = i) then DAE.ICONST(i);
    case DAE.DIM_BOOLEAN() then DAE.ICONST(2);
    case DAE.DIM_EXP(exp = e) then e;
  end match;
end dimensionSizeExp;

public function dimensionSizeExpHandleUnkown
  "Converts (extracts) a dimension to an expression.
  This function will change unknown dims to DAE.ICONST(-1).
  we use it to handle unknown dims in code generation. unknown dims
  are okay if the variable is a function input (it's just holds the slot
  and will not be generated). Otherwise it's an error
  since it shouldn't have reached there."
  input DAE.Dimension dim;
  output DAE.Exp exp;
algorithm
  exp := match(dim)
    case DAE.DIM_UNKNOWN() then DAE.ICONST(-1);
    else dimensionSizeExp(dim);
  end match;
end dimensionSizeExpHandleUnkown;

public function intDimension
  "Converts an integer to an array dimension."
  input Integer value;
  output DAE.Dimension dim;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  dim := DAE.DIM_INTEGER(value);
end intDimension;

public function dimensionSubscript
  "Converts an array dimension to a subscript."
  input DAE.Dimension dim;
  output DAE.Subscript sub;
algorithm
  sub := match(dim)
    local
      Integer i;

    case DAE.DIM_INTEGER(integer = i) then DAE.INDEX(DAE.ICONST(i));
    case DAE.DIM_ENUM(size = i) then DAE.INDEX(DAE.ICONST(i));
    case DAE.DIM_BOOLEAN() then DAE.INDEX(DAE.ICONST(2));
    case DAE.DIM_UNKNOWN() then DAE.WHOLEDIM();
  end match;
end dimensionSubscript;

/***************************************************/
/* Change  */
/***************************************************/

public function negate
"author: PA
  Negates an expression."
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  outExp := match(inExp)
    local
      Type t;
      Operator op;
      Boolean b,b_1;
      Real r,r_1;
      Integer i,i_1;
      DAE.Exp e,e1,e2;

    // to avoid un-necessary --e
    case(DAE.UNARY(DAE.UMINUS(_),e)) then e;
    case(DAE.UNARY(DAE.UMINUS_ARR(_),e)) then e;
    case(DAE.LUNARY(DAE.NOT(_),e)) then e;

    // -(a*b) = (-a)*b
    // -(a/b) = (-a)/b
    case(DAE.BINARY(e1,op,e2)) guard(isMulOrDiv(op))
    then DAE.BINARY(negate(e1),op,e2);

    // -(a-b) = b-a
    case(DAE.BINARY(e1,op,e2)) guard(isSub(op))
    then DAE.BINARY(e2,op,e1);

    case (DAE.ICONST(i))
      equation
        i_1 = 0 - i;
      then DAE.ICONST(i_1);
    case (DAE.RCONST(r))
      equation
        r_1 = 0.0 - r;
      then DAE.RCONST(r_1);
    case (DAE.BCONST(b))
      equation
        b_1 = not b;
      then DAE.BCONST(b_1);

    case(e)
      equation
        if isZero(e) // -0 = 0
        then
          outExp = e;
        else
          t = typeof(e);
          outExp = match (t)
            case (DAE.T_BOOL()) // not e
              then DAE.LUNARY(DAE.NOT(t),e);
            else
              equation
                b = DAEUtil.expTypeArray(t);
                op = if b then DAE.UMINUS_ARR(t) else DAE.UMINUS(t);
              then DAE.UNARY(op,e);
          end match;
        end if;
      then
        outExp;

  end match;
end negate;

public function negateReal
  input DAE.Exp inReal;
  output DAE.Exp outNegatedReal;
algorithm
  outNegatedReal := DAE.UNARY(DAE.UMINUS(DAE.T_REAL_DEFAULT), inReal);
end negateReal;

public function expand "expands products
For example
a *(b+c) => a*b + a*c"
  input DAE.Exp e;
  output DAE.Exp outE;
algorithm
  outE := matchcontinue(e)
    local
      DAE.Type tp;
      DAE.Operator op;
      DAE.Exp e1,e2,e21,e22;

    case(DAE.BINARY(e1,DAE.MUL(tp),e2))
      equation
        DAE.BINARY(e21,op,e22) = expand(e2);
        true = isAddOrSub(op);
      then
        DAE.BINARY(DAE.BINARY(e1,DAE.MUL(tp),e21),op,DAE.BINARY(e1,DAE.MUL(tp),e22));

    else e;
  end matchcontinue;
end expand;

public function expDer
"author: Frenkel TUD 2012-11
  exp -> der(exp)"
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  outExp := DAE.CALL(Absyn.IDENT("der"),{inExp},DAE.callAttrBuiltinReal);
end expDer;

public function expAbs
"author: PA
  Makes the expression absolute. i.e. non-negative."
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  outExp := match(inExp)
    local
      Integer i2,i;
      Real r2,r;
      DAE.Exp e_1,e,e1_1,e2_1,e1,e2;
      Type tp;
      Operator op;

    case (DAE.ICONST(integer = i))
      equation
        i2 = intAbs(i);
      then
        DAE.ICONST(i2);

    case (DAE.RCONST(real = r))
      equation
        r2 = realAbs(r);
      then
        DAE.RCONST(r2);

    case (DAE.UNARY(operator = DAE.UMINUS(),exp = e))
      equation
        e_1 = expAbs(e);
      then
        e_1;

    case (DAE.BINARY(exp1 = e1,operator = op,exp2 = e2))
      equation
        e1_1 = expAbs(e1);
        e2_1 = expAbs(e2);
      then
        DAE.BINARY(e1_1,op,e2_1);

    else inExp;
  end match;
end expAbs;

public function stripNoEvent
"Function that strips all noEvent() calls in an expression"
  input DAE.Exp e;
  output DAE.Exp outE;
algorithm
  outE := traverseExpDummy(e,stripNoEventExp);
end stripNoEvent;

protected function stripNoEventExp "
traversal function for stripNoEvent"
  input DAE.Exp e;
  output DAE.Exp outExp;
algorithm
  outExp := match e
    case DAE.CALL(path=Absyn.IDENT("noEvent"),expLst={outExp}) then outExp;
    else e;
  end match;
end stripNoEventExp;

public function addNoEventToRelations
"Function that adds a  noEvent() call to all relations in an expression"
  input DAE.Exp e;
  output DAE.Exp outE;
algorithm
  outE := traverseExpDummy(e,addNoEventToRelationExp);
end addNoEventToRelations;

protected function addNoEventToRelationExp "
traversal function for addNoEventToRelations"
  input DAE.Exp e;
  output DAE.Exp outExp;
algorithm
  outExp := match e
    case DAE.RELATION() then DAE.CALL(Absyn.IDENT("noEvent"),{e},DAE.callAttrBuiltinBool);
    else e;
  end match;
end addNoEventToRelationExp;

public function addNoEventToRelationsAndConds
"Function that adds a  noEvent() call to all relations in an expression"
  input DAE.Exp e;
  output DAE.Exp outE;
algorithm
  outE := traverseExpDummy(e,addNoEventToRelationandCondExp);
end addNoEventToRelationsAndConds;

protected function addNoEventToRelationandCondExp "
traversal function for addNoEventToRelationsAndConds"
  input DAE.Exp e;
  output DAE.Exp outExp;
algorithm
  outExp := match e
    local
      DAE.Exp e1,e2,e3;
    case DAE.RELATION() then DAE.CALL(Absyn.IDENT("noEvent"),{e},DAE.callAttrBuiltinBool);
    case DAE.IFEXP(e1,e2,e3) then DAE.IFEXP(DAE.CALL(Absyn.IDENT("noEvent"),{e1},DAE.callAttrBuiltinBool),e2,e3);
    else e;
  end match;
end addNoEventToRelationandCondExp;

public function addNoEventToEventTriggeringFunctions
" Function that adds a  noEvent() call to all event triggering functions in an expression"
  input DAE.Exp e;
  output DAE.Exp outE;
algorithm
  outE := traverseExpDummy(e,addNoEventToEventTriggeringFunctionsExp);
end addNoEventToEventTriggeringFunctions;

protected function addNoEventToEventTriggeringFunctionsExp "
traversal function for addNoEventToEventTriggeringFunctions"
  input DAE.Exp e;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue e
    case DAE.CALL()
      equation
        true = isEventTriggeringFunctionExp(e);
      then DAE.CALL(Absyn.IDENT("noEvent"),{e},DAE.callAttrBuiltinBool);
    else e;
  end matchcontinue;
end addNoEventToEventTriggeringFunctionsExp;

public function expStripLastSubs
"Strips the last subscripts of a Exp"
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  outExp := match (inExp)
    local
      ComponentRef cr,cr_1;
      Type ty;
      Operator op,op1;
      DAE.Exp e,e_1;
      Boolean b;

    case (DAE.CREF(componentRef=cr))
      equation
        ty = ComponentReference.crefLastType(cr);
        cr_1 = ComponentReference.crefStripLastSubs(cr);
        e = makeCrefExp(cr_1, ty);
      then
        e;

    case (DAE.UNARY(exp=e))
      equation
        e_1 = expStripLastSubs(e);
        ty = typeof(e_1);
        b = DAEUtil.expTypeArray(ty);
        op1 = if b then DAE.UMINUS_ARR(ty) else DAE.UMINUS(ty);
      then
        DAE.UNARY(op1,e_1);
  end match;
end expStripLastSubs;

public function expStripLastIdent
"Strips the last identifier of a cref Exp"
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  outExp:=
  match (inExp)
    local
      ComponentRef cr,cr_1;
      Type ty;
      Operator op,op1;
      DAE.Exp e,e_1;
      Boolean b;

    case (DAE.CREF(componentRef=cr))
      equation
        cr_1 = ComponentReference.crefStripLastIdent(cr);
        ty = ComponentReference.crefLastType(cr_1);
        e = makeCrefExp(cr_1, ty);
      then
        e;

    case (DAE.UNARY(exp=e))
      equation
        e_1 = expStripLastIdent(e);
        ty = typeof(e_1);
        b = DAEUtil.expTypeArray(ty);
        op1 = if b then DAE.UMINUS_ARR(ty) else DAE.UMINUS(ty);
      then
        DAE.UNARY(op1,e_1);
  end match;
end expStripLastIdent;

public function prependSubscriptExp
"Prepends a subscript to a CREF expression
 For instance a.b[1,2] with subscript 'i' becomes a.b[i,1,2]."
  input DAE.Exp exp;
  input DAE.Subscript subscr;
  output DAE.Exp outExp;
algorithm
  outExp := match(exp,subscr)
    local
      Type t; ComponentRef cr,cr1,cr2;
      list<DAE.Subscript> subs;
      DAE.Exp e;

    case (DAE.CREF(cr,t),_)
      equation
        cr1 = ComponentReference.crefStripLastSubs(cr);
        subs = ComponentReference.crefLastSubs(cr);
        cr2 = ComponentReference.subscriptCref(cr1,subscr::subs);
        e = makeCrefExp(cr2, t);
    then
      e;
  end match;
end prependSubscriptExp;

public function applyExpSubscripts "
author: PA
Takes an arbitrary expression and applies subscripts to it. This is done by creating asub
expressions given the original expression and then simplify them.
Note: The subscripts must be INDEX

alternative names: subsriptExp (but already taken), subscriptToAsub"
  input DAE.Exp inExp;
  input list<DAE.Subscript> inSubs;
  output DAE.Exp res;
algorithm
  res := match(inExp,inSubs)
    local
      DAE.Exp s,e;
      DAE.Subscript sub;
      list<DAE.Subscript> subs;

    case(e,{}) then e;

    case(e,sub::subs)
      equation
        // Apply one subscript at a time, so simplify works fine on it.
        s = subscriptIndexExp(sub);
        (e,_) = ExpressionSimplify.simplify(makeASUB(e,{s}));
        res = applyExpSubscripts(e,subs);
      then
        res;
  end match;
end applyExpSubscripts;


public function subscriptExp
"@mahge
  This function does the same job as 'applyExpSubscripts' function.
  However this one doesn't use ExpressionSimplify.simplify.


  Takes an expression and a list of subscripts and subscripts
  the given expression.
  If a component reference is given the subs are applied to it.
  If an array(DAE.ARRAY) is given the element at the specified
  subscripts is returned.
  e.g. subscriptExp on ({{1,2},{3,4}}) with sub [2,1] gives 3
       subscriptExp on (a) with sub [2,1] gives a[2,1]

"
  input DAE.Exp inExp;
  input list<DAE.Subscript> inSubs;
  output DAE.Exp outArg;
algorithm
  outArg := match(inExp, inSubs)
    local
      DAE.ComponentRef cref;
      DAE.Type ty;
      DAE.Exp exp,exp1,exp2;
      list<DAE.Exp> explst;
      DAE.Subscript sub;
      list<DAE.Subscript> restsubs;
      DAE.Operator op;
      String str;

    case(_, {}) then inExp;

    case(DAE.CREF(cref, ty), _)
      equation
        cref = ComponentReference.subscriptCref(cref, inSubs);
      then
        DAE.CREF(cref, ty);

    case(DAE.ARRAY(_, _, explst), sub::restsubs)
      equation
        exp = listGet(explst, subscriptInt(sub));
      then
        subscriptExp(exp, restsubs);

    case (DAE.BINARY(exp1, op, exp2), _)
      equation
        exp1 = subscriptExp(exp1, inSubs);
        exp2 = subscriptExp(exp2, inSubs);
      then
        DAE.BINARY(exp1, op, exp2);

    case (DAE.CAST(ty,exp1), _)
      equation
        exp1 = subscriptExp(exp1, inSubs);
        ty = Types.arrayElementType(ty);
        exp1 = DAE.CAST(ty,exp1);
      then
        exp1;

    else
      equation
        str = "Expression.subscriptExp failed on " + ExpressionDump.printExpStr(inExp) + "\n";
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then
        fail();

  end match;
end subscriptExp;


public function unliftArray
"Converts an array type into its element type
  See also Types.unliftArray.
  ."
  input DAE.Type inType;
  output DAE.Type outType;
algorithm
  outType := match(inType)
    local
      Type tp,t;
      DAE.Dimension d;
      DAE.Dimensions ds;
      DAE.TypeSource ts;

    case (DAE.T_ARRAY(ty = tp,dims = {_}))
      then tp;
    case (DAE.T_ARRAY(ty = tp,dims = (_ :: ds),source = ts))
      then DAE.T_ARRAY(tp,ds,ts);
    case (DAE.T_METATYPE(ty = tp))
      then Types.simplifyType(unliftArray(tp));
    case (DAE.T_METAARRAY(ty = tp))
      then tp;
    else inType;
  end match;
end unliftArray;

public function unliftArrayIgnoreFirst
  input A a;
  input DAE.Type inType;
  output DAE.Type outType;
  replaceable type A subtypeof Any;
algorithm
  outType := unliftArray(inType);
end unliftArrayIgnoreFirst;

public function unliftExp
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  outExp := match(inExp)
    local
      Type ty;
      DAE.ComponentRef cr;
      Boolean s;
      list<DAE.Exp> a;
      Integer i;
      list<list<DAE.Exp>> mat;
      DAE.Exp expCref;

    case DAE.CREF(componentRef = cr, ty = ty)
      equation
        ty = unliftArray(ty);
        expCref = makeCrefExp(cr, ty);
      then
        expCref;

    case DAE.ARRAY(ty = ty, scalar = s, array = a)
      equation
        ty = unliftArray(ty);
      then
        DAE.ARRAY(ty, s, a);

    case DAE.MATRIX(ty = ty, integer = i, matrix = mat)
      equation
        ty = unliftArray(ty);
      then
        DAE.MATRIX(ty, i, mat);

    else inExp;

  end match;
end unliftExp;

public function liftArrayRight "
This function adds an array dimension to a type on the right side, i.e.
liftArrayRigth(Real[2,3],SOME(4)) => Real[2,3,4].
This function has the same functionality as Types.liftArrayType but for DAE.Type.'"
  input DAE.Type inType;
  input DAE.Dimension inDimension;
  output DAE.Type outType;
algorithm
  outType := match(inType,inDimension)
    local
      Type ty_1,ty;
      DAE.Dimensions dims;
      DAE.Dimension dim;
      DAE.TypeSource ts;

    case (DAE.T_ARRAY(ty,dims,ts),dim)
      equation
        ty_1 = liftArrayRight(ty, dim);
      then
        DAE.T_ARRAY(ty_1,dims,ts);

    else DAE.T_ARRAY(inType,{inDimension},DAE.emptyTypeSource);

  end match;
end liftArrayRight;

public function liftArrayLeft "
author: PA
This function adds an array dimension to a type on the left side, i.e.
liftArrayRigth(Real[2,3],SOME(4)) => Real[4,2,3]"
  input DAE.Type inType;
  input DAE.Dimension inDimension;
  output DAE.Type outType;
algorithm
  outType := match(inType,inDimension)
    local
      Type ty;
      DAE.Dimensions dims;
      DAE.Dimension dim;
      DAE.TypeSource ts;

    case (DAE.T_ARRAY(ty,dims,ts),dim) then DAE.T_ARRAY(ty,dim::dims,ts);

    else DAE.T_ARRAY(inType,{inDimension},DAE.emptyTypeSource);

  end match;
end liftArrayLeft;

public function liftArrayLeftList
  input DAE.Type inType;
  input list<DAE.Dimension> inDimensions;
  output DAE.Type outType;
algorithm
  outType := match(inType, inDimensions)
    local
      Type ty;
      DAE.Dimensions dims;
      DAE.TypeSource ts;

    case (_, {}) then inType;

    case (DAE.T_ARRAY(ty, dims, ts), _)
      equation
        dims = listAppend(inDimensions, dims);
      then
        DAE.T_ARRAY(ty, dims, ts);

    else DAE.T_ARRAY(inType, inDimensions, DAE.emptyTypeSource);

  end match;
end liftArrayLeftList;

public function setOpType
  "Sets the type of an operator."
  input DAE.Operator inOp;
  input DAE.Type inType;
  output DAE.Operator outOp;
algorithm
  outOp := match(inOp, inType)
    case (DAE.ADD(), _) then DAE.ADD(inType);
    case (DAE.SUB(), _) then DAE.SUB(inType);
    case (DAE.MUL(), _) then DAE.MUL(inType);
    case (DAE.DIV(), _) then DAE.DIV(inType);
    case (DAE.POW(), _) then DAE.POW(inType);
    case (DAE.UMINUS(), _) then DAE.UMINUS(inType);
    case (DAE.UMINUS_ARR(), _) then DAE.UMINUS_ARR(inType);
    case (DAE.ADD_ARR(), _) then DAE.ADD_ARR(inType);
    case (DAE.SUB_ARR(), _) then DAE.SUB_ARR(inType);
    case (DAE.MUL_ARR(), _) then DAE.MUL_ARR(inType);
    case (DAE.DIV_ARR(), _) then DAE.DIV_ARR(inType);
    case (DAE.MUL_ARRAY_SCALAR(), _) then DAE.MUL_ARRAY_SCALAR(inType);
    case (DAE.ADD_ARRAY_SCALAR(), _) then DAE.ADD_ARRAY_SCALAR(inType);
    case (DAE.SUB_SCALAR_ARRAY(), _) then DAE.SUB_SCALAR_ARRAY(inType);
    case (DAE.MUL_SCALAR_PRODUCT(), _) then DAE.MUL_SCALAR_PRODUCT(inType);
    case (DAE.MUL_MATRIX_PRODUCT(), _) then DAE.MUL_MATRIX_PRODUCT(inType);
    case (DAE.DIV_ARRAY_SCALAR(), _) then DAE.DIV_ARRAY_SCALAR(inType);
    case (DAE.DIV_SCALAR_ARRAY(), _) then DAE.DIV_SCALAR_ARRAY(inType);
    case (DAE.POW_ARRAY_SCALAR(), _) then DAE.POW_ARRAY_SCALAR(inType);
    case (DAE.POW_SCALAR_ARRAY(), _) then DAE.POW_SCALAR_ARRAY(inType);
    case (DAE.POW_ARR(), _) then DAE.POW_ARR(inType);
    case (DAE.POW_ARR2(), _) then DAE.POW_ARR2(inType);
    case (DAE.AND(), _) then DAE.AND(inType);
    case (DAE.OR(), _) then DAE.OR(inType);
    case (DAE.NOT(),_ ) then DAE.NOT(inType);
    case (DAE.LESS(), _) then inOp;
    case (DAE.LESSEQ(), _) then inOp;
    case (DAE.GREATER(), _) then inOp;
    case (DAE.GREATEREQ(), _) then inOp;
    case (DAE.EQUAL(), _) then inOp;
    case (DAE.NEQUAL(), _) then inOp;
    case (DAE.USERDEFINED(), _) then inOp;
    else
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        Debug.traceln("- Expression.setOpType failed on unknown operator");
      then
        fail();
  end match;
end setOpType;

public function unliftOperator
  "Unlifts the type of an operator by removing one dimension from the operator
   type. The operator is changed to the scalar version if the type becomes a
   scalar type."
  input DAE.Operator inOperator;
  output DAE.Operator outOperator;
protected
  Type ty;
algorithm
  ty := typeofOp(inOperator);
  ty := unliftArray(ty);
  outOperator := unliftOperator2(inOperator, ty);
end unliftOperator;

public function unliftOperatorX
  "Unlifts the type of an operator by removing X dimensions from the operator
   type. The operator is changed to the scalar version if the type becomes a
   scalar type."
  input DAE.Operator inOperator;
  input Integer inX;
  output DAE.Operator outOperator;
protected
  Type ty;
algorithm
  ty := typeofOp(inOperator);
  ty := unliftArrayX(ty, inX);
  outOperator := unliftOperator2(inOperator, ty);
end unliftOperatorX;

protected function unliftOperator2
  "Helper function to unliftOperator. Sets the type of the given operator, and
   changes the operator to the scalar version if the type is scalar."
  input DAE.Operator inOperator;
  input DAE.Type inType;
  output DAE.Operator outOperator;
algorithm
  outOperator := match(inOperator, inType)
    case (_, DAE.T_ARRAY()) then setOpType(inOperator, inType);
    else makeScalarOpFromArrayOp(inOperator, inType);
  end match;
end unliftOperator2;

protected function makeScalarOpFromArrayOp
  "Helper function to makeScalarOpFromArrayOp. Returns the scalar version of a
   given array operator."
  input DAE.Operator inOperator;
  input DAE.Type inType;
  output DAE.Operator outOperator;
algorithm
  outOperator := match(inOperator, inType)
    case (DAE.MUL_ARRAY_SCALAR(), _) then DAE.MUL(inType);
    case (DAE.ADD_ARRAY_SCALAR(), _) then DAE.ADD(inType);
    case (DAE.SUB_SCALAR_ARRAY(), _) then DAE.SUB(inType);
    case (DAE.DIV_ARRAY_SCALAR(), _) then DAE.DIV(inType);
    case (DAE.DIV_SCALAR_ARRAY(), _) then DAE.DIV(inType);
    case (DAE.POW_ARRAY_SCALAR(), _) then DAE.POW(inType);
    case (DAE.POW_SCALAR_ARRAY(), _) then DAE.POW(inType);
    case (DAE.UMINUS_ARR(), _)       then DAE.UMINUS(inType);
    case (DAE.ADD_ARR(), _)          then DAE.ADD(inType);
    case (DAE.SUB_ARR(), _)          then DAE.SUB(inType);
    case (DAE.MUL_ARR(), _)          then DAE.MUL(inType);
    case (DAE.DIV_ARR(), _)          then DAE.DIV(inType);
    else inOperator;
  end match;
end makeScalarOpFromArrayOp;

public function isScalarArrayOp
  "Returns true if the operator takes a scalar and an array as arguments."
  input DAE.Operator inOperator;
  output Boolean outIsScalarArrayOp;
algorithm
  outIsScalarArrayOp := match(inOperator)
    case DAE.SUB_SCALAR_ARRAY() then true;
    case DAE.DIV_SCALAR_ARRAY() then true;
    case DAE.POW_SCALAR_ARRAY() then true;
  end match;
end isScalarArrayOp;

public function isArrayScalarOp
  "Returns true if the operator takes an array and a scalar as arguments."
  input DAE.Operator inOperator;
  output Boolean outIsArrayScalarOp;
algorithm
  outIsArrayScalarOp := match(inOperator)
    case DAE.MUL_ARRAY_SCALAR() then true;
    case DAE.ADD_ARRAY_SCALAR() then true;
    case DAE.DIV_ARRAY_SCALAR() then true;
    case DAE.POW_ARRAY_SCALAR() then true;
    else false;
  end match;
end isArrayScalarOp;

public function subscriptsAppend
"This function takes a subscript list and adds a new subscript.
  But there are a few special cases.  When the last existing
  subscript is a slice, it is replaced by the slice indexed by
  the new subscript."
  input list<DAE.Subscript> inSubscriptLst;
  input DAE.Exp inSubscript;
  output list<DAE.Subscript> outSubscriptLst;
algorithm
  outSubscriptLst := match(inSubscriptLst,inSubscript)
    local
      DAE.Exp e_1,e;
      Subscript s;
      list<DAE.Subscript> ss_1,ss;

    case ({},_) then {DAE.INDEX(inSubscript)};
    case (DAE.WHOLEDIM() :: ss,_) then DAE.INDEX(inSubscript) :: ss;

    case ({DAE.SLICE(exp = e)},_)
      equation
        (e_1,_) = ExpressionSimplify.simplify1(makeASUB(e,{inSubscript}));
      then
        {DAE.INDEX(e_1)};

    case ({(s as DAE.INDEX())},_) then {s,DAE.INDEX(inSubscript)};

    case ((s :: ss),_)
      equation
        ss_1 = subscriptsAppend(ss, inSubscript);
      then
        (s :: ss_1);
  end match;
end subscriptsAppend;

public function subscriptsReplaceSlice
  "Replaces the first slice subscript in the given list with the given subscript."
  input list<DAE.Subscript> inSubscripts;
  input DAE.Subscript inSubscript;
  output list<DAE.Subscript> outSubscripts;
algorithm
  outSubscripts := match(inSubscripts, inSubscript)
    local
      list<DAE.Subscript> rest_subs;
      DAE.Subscript sub;

    case (DAE.WHOLEDIM() :: rest_subs, _) then inSubscript :: rest_subs;
    case (DAE.SLICE() :: rest_subs, _) then inSubscript :: rest_subs;
    case (sub :: rest_subs, _)
      equation
        rest_subs = subscriptsReplaceSlice(rest_subs, inSubscript);
      then
        sub :: rest_subs;

  end match;
end subscriptsReplaceSlice;

public function unliftArrayTypeWithSubs "
helper function for renameVarsToUnderlineVar2 unlifts array type as much as we have subscripts"
  input list<DAE.Subscript> subs;
  input DAE.Type ity;
  output DAE.Type oty;
algorithm
  oty := match(subs,ity)
    local
      list<DAE.Subscript> rest;
      Type ty;

    case({},ty) then ty;

    case(_::rest, ty)
      equation
        ty = unliftArray(ty);
        ty = unliftArrayTypeWithSubs(rest,ty);
      then
        ty;
  end match;
end unliftArrayTypeWithSubs;

public function unliftArrayX "Function: unliftArrayX
Unlifts a type with X dimensions..."
  input DAE.Type inType;
  input Integer x;
  output DAE.Type outType;
algorithm
  outType := match(inType,x)
    local Type ty;

    case (_,0) then inType;
    else
      equation
        ty = unliftArray(inType);
      then
        unliftArrayX(ty,x-1);
  end match;
end unliftArrayX;

public function arrayAppend
  "Appends a new element to a DAE.ARRAY."
  input DAE.Exp head;
  input DAE.Exp rest;
  output DAE.Exp array;
algorithm
  array := matchcontinue(head, rest)
    local
      DAE.Type ty;
      Boolean scalar;
      list<DAE.Exp> expl;
      Integer dim;
      DAE.Dimensions dims;
      DAE.TypeSource ts;

    case (_, DAE.ARRAY(
        DAE.T_ARRAY(ty = ty, dims = DAE.DIM_INTEGER(dim) :: dims, source  = ts),
        scalar = scalar,
        array = expl))
      equation
        dim = dim + 1;
        dims = DAE.DIM_INTEGER(dim) :: dims;
      then
        DAE.ARRAY(DAE.T_ARRAY(ty, dims, ts), scalar, head :: expl);

    else
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        Debug.traceln("- Expression.arrayAppend failed.");
      then
        fail();
  end matchcontinue;
end arrayAppend;


public function arrayDimensionSetFirst
  "Updates the first dimension of an array type."
  input DAE.Type inArrayType;
  input DAE.Dimension dimension;
  output DAE.Type outArrayType;
algorithm
  outArrayType := match(inArrayType, dimension)
    local
      DAE.Type ty;
      DAE.Dimensions rest_dims;
      DAE.TypeSource ts;

    case (DAE.T_ARRAY(ty = ty, dims = _ :: rest_dims, source = ts), _)
      then DAE.T_ARRAY(ty, dimension :: rest_dims, ts);
  end match;
end arrayDimensionSetFirst;

/***************************************************/
/* Getter  */
/***************************************************/

public function expReal "returns the real value if expression is constant Real"
  input DAE.Exp exp;
  output Real r;
algorithm
  r := match(exp) local Integer i;
    case(DAE.RCONST(r)) then r;
    case(DAE.ICONST(i)) then intReal(i);
    case(DAE.CAST(_,DAE.ICONST(i))) then intReal(i);
    case (DAE.ENUM_LITERAL(index = i)) then intReal(i);
  end match;
end expReal;

public function realExpIntLit "returns the int value if expression is constant Real that can be represented by an Integer"
  input DAE.Exp exp;
  output Option<Integer> oi;
algorithm
  oi := matchcontinue exp
    local
      Real r;
      Integer i;
    case (DAE.RCONST(real = r))
      equation
        i = realInt(r);
        true = realEq(r,intReal(i));
      then SOME(i);
    else NONE();
  end matchcontinue;
end realExpIntLit;

public function expInt "returns the int value if expression is constant Integer"
  input DAE.Exp exp;
  output Integer i;
algorithm
  i := match(exp) local Integer i2;
    case (DAE.ICONST(integer = i2)) then i2;
    case (DAE.ENUM_LITERAL(index = i2)) then i2;
  end match;
end expInt;

public function varName "Returns the name of a Var"
  input DAE.Var v;
  output String name;
algorithm
  name := match(v)
    case(DAE.TYPES_VAR(name = name)) then name;
  end match;
end varName;

public function varType "Returns the type of a Var"
  input DAE.Var v;
  output DAE.Type tp;
algorithm
  tp := match(v)
    case(DAE.TYPES_VAR(ty = tp)) then tp;
  end match;
end varType;

public function expCref
"Returns the componentref if DAE.Exp is a CREF,"
  input DAE.Exp inExp;
  output DAE.ComponentRef outComponentRef;
algorithm
  outComponentRef:=
  match (inExp)
    local ComponentRef cr;
    case (DAE.CREF(componentRef = cr)) then cr;
  end match;
end expCref;

public function expCrefNegCref
"Returns the componentref if DAE.Exp is a CREF or -CREF"
  input DAE.Exp inExp;
  output DAE.ComponentRef outComponentRef;
algorithm
  outComponentRef:=
  match (inExp)
    local ComponentRef cr;
    case (DAE.CREF(componentRef = cr)) then cr;
    case (DAE.UNARY(DAE.UMINUS(_),DAE.CREF(componentRef = cr))) then cr;
    case (DAE.UNARY(DAE.UMINUS_ARR(_),DAE.CREF(componentRef = cr))) then cr;
  end match;
end expCrefNegCref;

public function expCrefTuple
"Returns the componentref if the expression in inTuple is a CREF."
  input tuple<DAE.Exp, Boolean> inTuple;
  output DAE.ComponentRef outComponentRef;
algorithm
  outComponentRef:=
  match (inTuple)
    local ComponentRef cr;
    case ((DAE.CREF(componentRef = cr),_)) then cr;
  end match;
end expCrefTuple;

public function expCrefInclIfExpFactors
"Returns the componentref if DAE.Exp is a CREF, or the factors of CREF if expression is an if expression.
  This is used in e.g. the tearing algorithm to detect potential division by zero in
  expressions like 1/(if b then 1.0 else x) which could lead to division by zero if b is false and x is 0; "
  input DAE.Exp inExp;
  output list<DAE.ComponentRef> outComponentRefs;
algorithm
  outComponentRefs:=
  match (inExp)
    local ComponentRef cr; DAE.Exp c,tb,fb;
      list<DAE.Exp> f;
      list<DAE.ComponentRef> crefs;
    case (DAE.CREF(componentRef = cr)) then {cr};
    case(DAE.IFEXP(_,tb,fb)) equation
      f = List.select(listAppend(factors(tb),factors(fb)),isCref);
      crefs = List.map(f,expCref);
    then crefs;
  end match;
end expCrefInclIfExpFactors;

public function getArrayContents "returns the list of expressions in the array"
  input DAE.Exp e;
  output list<DAE.Exp> es;
algorithm
  DAE.ARRAY(array=es) := e;
end getArrayContents;

public function getArrayOrMatrixContents
  "Returns the contents of an array or matrix as a list of expressions."
  input DAE.Exp inExp;
  output list<DAE.Exp> outContents;
algorithm
  outContents := match(inExp)
    local
      list<DAE.Exp> expl;
      list<list<DAE.Exp>> mat;
      DAE.Type ty, el_ty;
      DAE.Dimensions dims;
      DAE.TypeSource src;
      Boolean sc;

    case DAE.ARRAY(array = expl) then expl;
    case DAE.MATRIX(ty = DAE.T_ARRAY(el_ty, _ :: dims, src), matrix = mat)
      equation
        ty = DAE.T_ARRAY(el_ty, dims, src);
        sc = Types.basicType(el_ty);
      then
        List.map2(mat, makeArray, ty, sc);

  end match;
end getArrayOrMatrixContents;

public function getComplexContents "returns the list of expressions from a complex structure like array,record,call,tuple...
author:Waurich TUD 2014-04"
  input DAE.Exp e;
  output list<DAE.Exp> es;
algorithm
  es := matchcontinue(e)
    local
      Boolean noArr;
      DAE.ComponentRef cref;
      DAE.Exp exp;
      list<DAE.Exp> expLst;
      list<list<DAE.Exp>> expLstLst;
      list<DAE.ComponentRef> crefs;
    case(DAE.CREF())
      equation
        expLst = arrayElements(e);
        noArr = listLength(expLst)==1;
        exp = List.first(expLst);
        noArr = noArr  and expEqual(exp,e);
        expLst = if noArr then {} else expLst;
      then
        expLst;
    case(DAE.CALL(expLst=expLst))
      equation
         expLstLst = List.map(expLst,getComplexContentsInCall);
         expLst = List.flatten(expLstLst);
      then
        expLst;
    case(DAE.RECORD(exps=expLst))
      then
        expLst;
    case(DAE.ARRAY())
      equation
      expLst = arrayElements(e);
      then
        expLst;
    case(DAE.TUPLE(PR=expLst))
      then
        expLst;
    case(DAE.CAST(exp=exp))
      equation
        expLst = getComplexContents(exp);
      then
        expLst;
    case(DAE.ASUB(exp=exp))
      equation
        expLst = getComplexContents(exp);
      then
        expLst;
    else {};
  end matchcontinue;
end getComplexContents;

protected function getComplexContentsInCall"gets the scalars for the complex expressions inside a function call"
  input DAE.Exp expIn;
  output list<DAE.Exp> expsOut;
protected
  list<DAE.Exp> expLst;
algorithm
  expLst := getComplexContents(expIn);
  expsOut := if List.isEmpty(expLst) then {expIn} else expLst;
end getComplexContentsInCall;

public function getArrayOrRangeContents "returns the list of expressions in the array"
  input DAE.Exp e;
  output list<DAE.Exp> es;
algorithm
  es := match e
    local
      Boolean bstart,bstop;
      Integer istart,istep,istop;
      Real rstart,rstep,rstop;
      list<list<DAE.Exp>> matrix;
      DAE.Type ty;
    case DAE.ARRAY(array=es) then es;
    case DAE.MATRIX(matrix=matrix,ty=ty)
      equation
        ty = Types.unliftArray(ty);
        es = List.map2(matrix,makeArray,ty,not Types.arrayType(ty));
      then es;
    case DAE.CREF(componentRef=DAE.CREF_IDENT(),ty=DAE.T_ARRAY(dims=DAE.DIM_INTEGER(istop)::_))
      equation
        es = List.map(ExpressionSimplify.simplifyRange(1,1,istop), makeIntegerExp);
        es = List.map1r(es, makeASUBSingleSub, e);
      then es;
    case DAE.RANGE(DAE.T_BOOL(), DAE.BCONST(bstart), NONE(), DAE.BCONST(bstop))
      then List.map(ExpressionSimplify.simplifyRangeBool(bstart, bstop), makeBoolExp);

    case DAE.RANGE(DAE.T_INTEGER(),DAE.ICONST(istart),NONE(),DAE.ICONST(istop))
      then List.map(ExpressionSimplify.simplifyRange(istart,1,istop), makeIntegerExp);

    case DAE.RANGE(DAE.T_INTEGER(),DAE.ICONST(istart),SOME(DAE.ICONST(istep)),DAE.ICONST(istop))
      then List.map(ExpressionSimplify.simplifyRange(istart,istep,istop), makeIntegerExp);

    case DAE.RANGE(DAE.T_REAL(),DAE.RCONST(rstart),NONE(),DAE.RCONST(rstop))
      then List.map(ExpressionSimplify.simplifyRangeReal(rstart,1.0,rstop), makeRealExp);

    case DAE.RANGE(DAE.T_REAL(),DAE.RCONST(rstart),SOME(DAE.RCONST(rstep)),DAE.RCONST(rstop))
      then List.map(ExpressionSimplify.simplifyRangeReal(rstart,rstep,rstop), makeRealExp);
  end match;
end getArrayOrRangeContents;

public function get2dArrayOrMatrixContent "returns the list of expressions in the array"
  input DAE.Exp e;
  output list<list<DAE.Exp>> outExps;
algorithm
  outExps := match e
    local
      list<DAE.Exp> es;
      list<list<DAE.Exp>> ess;
    case DAE.ARRAY(array=es) then List.map(es,getArrayContents);
    case DAE.MATRIX(matrix=ess) then ess;
  end match;
end get2dArrayOrMatrixContent;

public function getBoolConst "returns the expression as a Boolean value.
"
input DAE.Exp e;
output Boolean b;
algorithm
  DAE.BCONST(b) := e;
end getBoolConst;

public function getRealConst "returns the expression as a Real value.
Integer constants are cast to Real"
  input DAE.Exp ie;
  output Real v;
algorithm
  v := match (ie)
    local Integer i; DAE.Exp e;
    case(DAE.RCONST(v)) then v;
    case(DAE.CAST(_,e)) then getRealConst(e);
    case(DAE.ICONST(i)) then intReal(i);
    case DAE.ENUM_LITERAL(index = i) then intReal(i);
  end match;
end getRealConst;

// stefan
public function unboxExpType
"takes a type, and if it is boxed, unbox it
  otherwise return the given type"
  input DAE.Type inType;
  output DAE.Type outType;
algorithm
  outType := match(inType)
    local
      Type ty;
    case(DAE.T_METABOXED(ty = ty)) then ty;
    else inType;
  end match;
end unboxExpType;

public function unboxExp
"takes an expression and unboxes it if it is boxed"
  input DAE.Exp ie;
  output DAE.Exp outExp;
algorithm
  outExp := match (ie)
    local
      DAE.Exp e;
    case (DAE.BOX(e)) then unboxExp(e);
    else ie;
  end match;
end unboxExp;

public function boxExp
"takes an expression and boxes it"
  input DAE.Exp e;
  output DAE.Exp outExp;
algorithm
  outExp := match (e)
    case (DAE.BOX(_)) then e;
    else DAE.BOX(e);
  end match;
end boxExp;

public function subscriptIndexExp
  "Returns the expression in a subscript index.
  If the subscript is not an index the function fails."
  input DAE.Subscript inSubscript;
  output DAE.Exp outExp;
algorithm
  DAE.INDEX(exp = outExp) := inSubscript;
end subscriptIndexExp;

public function getSubscriptExp
  "Returns the subscript expression, or fails on DAE.WHOLEDIM."
  input DAE.Subscript inSubscript;
  output DAE.Exp outExp;
algorithm
  outExp := match(inSubscript)
    local DAE.Exp e;

    case DAE.SLICE(exp = e) then e;
    case DAE.INDEX(exp = e) then e;
    case DAE.WHOLE_NONEXP(exp = e) then e;
  end match;
end getSubscriptExp;

public function subscriptNonExpandedExp
"Returns the expression in a subscript representing non-expanded array.
  If the subscript is not WHOLE_NONEXP the function fails."
  input DAE.Subscript inSubscript;
  output DAE.Exp outExp;
algorithm
  outExp:=
  match (inSubscript)
    local DAE.Exp e;
    case (DAE.WHOLE_NONEXP(exp = e)) then e;
  end match;
end subscriptNonExpandedExp;

public function subscriptIsFirst
  "Returns true if the given subscript is the first index for a dimension, i.e.
   1, false or the first enumeration literal in an enumeration."
  input DAE.Subscript inSubscript;
  output Boolean outIsFirst;
algorithm
  outIsFirst := match (inSubscript)
    case DAE.INDEX(exp=DAE.ICONST(1)) then true;
    case DAE.INDEX(exp=DAE.BCONST(false)) then true;
    case DAE.INDEX(exp=DAE.ENUM_LITERAL(index=1)) then true;
  end match;
end subscriptIsFirst;

public function nthArrayExp "author: PA
  Returns the nth expression of an array expression."
  input DAE.Exp inExp;
  input Integer inInteger;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue (inExp)
    local
      DAE.Exp e1, e2, e_1, e_2;
      list<DAE.Exp> expl;
      Operator op;
      Type ty;

    case DAE.BINARY(operator=op, exp1=e1, exp2=e2) equation
      ty = typeofOp(op);
      true = Types.isArray(ty, {});
      e_1 = nthArrayExp(e1, inInteger);
      e_2 = nthArrayExp(e2, inInteger);
    then DAE.BINARY(e_1, op, e_2);

    case DAE.ARRAY(array=expl) equation
      e1 = listGet(expl, inInteger);
    then e1;

    else inExp;
  end matchcontinue;
end nthArrayExp;

public function expLastSubs
"Return the last subscripts of a Exp"
  input DAE.Exp inExp;
  output list<DAE.Subscript> outSubscriptLst;
algorithm
  outSubscriptLst:=
  match (inExp)
    local
      ComponentRef cr;
      list<DAE.Subscript> subs;
      DAE.Exp e;

    case (DAE.CREF(componentRef=cr))
      equation
        subs = ComponentReference.crefLastSubs(cr);
      then subs;

    case (DAE.UNARY(exp=e))
      equation
        subs = expLastSubs(e);
      then subs;
  end match;
end expLastSubs;

public function expDimensions
  "Tries to return the dimensions from an expression, typically an array."
  input DAE.Exp inExp;
  output DAE.Dimensions outDims;
algorithm
  outDims := match(inExp)
    local
      DAE.Type tp;
      Exp e;

    case DAE.ARRAY(ty = tp) then arrayDimension(tp);
    case DAE.MATRIX(ty = tp) then arrayDimension(tp);
    case DAE.LUNARY(exp = e) then expDimensions(e);
    case DAE.LBINARY(exp1 = e) then expDimensions(e);
  end match;
end expDimensions;

public function arrayDimension "
Author BZ
Get dimension of array.
"
  input DAE.Type tp;
  output DAE.Dimensions dims;
algorithm
  dims := match(tp)
    case(DAE.T_ARRAY(dims = dims)) then dims;
    else {};
  end match;
end arrayDimension;

public function arrayTypeDimensions
"Return the array dimensions of a type."
  input DAE.Type tp;
  output DAE.Dimensions dims;
algorithm
  dims := match(tp)
    case(DAE.T_ARRAY(dims = dims)) then dims;
  end match;
end arrayTypeDimensions;

public function subscriptDimensions
  "Converts a list of subscript to a list of dimensions."
  input list<DAE.Subscript> inSubscripts;
  output DAE.Dimensions outDimensions;
algorithm
  outDimensions := List.map(inSubscripts, subscriptDimension);
end subscriptDimensions;

public function subscriptDimension
  "Converts a subscript to a dimension by interpreting the subscript as a
   dimension."
  input DAE.Subscript inSubscript;
  output DAE.Dimension outDimension;
algorithm
  outDimension := matchcontinue(inSubscript)
    local
      Integer x;
      DAE.Exp e;
      String sub_str;

    case DAE.INDEX(exp = DAE.ICONST(x)) then DAE.DIM_INTEGER(x);
    case DAE.INDEX(exp = e) then DAE.DIM_EXP(e);
    case DAE.WHOLEDIM() then DAE.DIM_UNKNOWN();

    // Special cases for non-expanded arrays
    case DAE.WHOLE_NONEXP(exp = DAE.ICONST(x))
      equation
        false = Config.splitArrays();
      then
        DAE.DIM_INTEGER(x);

    case DAE.WHOLE_NONEXP(exp=e)
      equation
        false = Config.splitArrays();
      then
        DAE.DIM_EXP(e);

    else
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        sub_str = ExpressionDump.subscriptString(inSubscript);
        Debug.traceln("- Expression.subscriptDimension failed on " + sub_str);
      then
        fail();

  end matchcontinue;
end subscriptDimension;

public function arrayEltType
" Returns the element type of an array expression."
  input DAE.Type inType;
  output DAE.Type outType;
algorithm
  outType := match(inType)
    local Type t;
    case (DAE.T_ARRAY(ty = t)) then arrayEltType(t);
    else inType;
  end match;
end arrayEltType;

public function sizeOf
"Returns the size of an ET_ARRAY or ET_COMPLEX"
  input DAE.Type inType;
  output Integer i;
algorithm
  i := matchcontinue inType
    local
      DAE.Dimensions ad;
      Integer nr;
      list<Integer> lstInt;
      list<Var> varLst;
      list<DAE.Type> typs;
      Type ty;

    // count the variables in array
    case DAE.T_ARRAY(dims = ad)
      equation
        nr = dimensionSize(List.reduce(ad, dimensionsMult));
      then
        nr;

    // count the variables in record
    case DAE.T_COMPLEX(varLst = varLst)
      equation
        lstInt = List.map(List.map(varLst, varType), sizeOf);
        nr = List.reduce(lstInt, intAdd);
      then
        nr;

    case DAE.T_TUPLE(types=typs)
      equation
        lstInt = List.map(typs,sizeOf);
        nr = List.reduce(lstInt, intAdd);
      then
        nr;
/* Size of Enumeration is 1 like a Integer
    case DAE.T_ENUMERATION(index=NONE(),names=strlst)
      then
        listLength(strlst);
*/
    case DAE.T_FUNCTION(funcResultType=ty)
      then
        sizeOf(ty);

    case DAE.T_METATYPE(ty=ty)
      then
        sizeOf(ty);

    // 0 for T_UNKNOWN as it can only appear in tuples for WILD()??!!
    case DAE.T_UNKNOWN(_) then 0;

    // for all other consider it just 1 variable
    case _ then 1;
  end matchcontinue;
end sizeOf;

public function dimensionSize
  "Extracts an integer from an array dimension"
  input DAE.Dimension dim;
  output Integer value;
algorithm
  value := match(dim)
    local
      Integer i;
    case DAE.DIM_INTEGER(integer = i) then i;
    case DAE.DIM_ENUM(size = i) then i;
    case DAE.DIM_BOOLEAN() then 2;
    case DAE.DIM_EXP(exp = DAE.ICONST(integer = i)) then i;
    case DAE.DIM_EXP(exp = DAE.ENUM_LITERAL(index = i)) then i;
  end match;
end dimensionSize;

public function addDimensions
  input DAE.Dimension dim1;
  input DAE.Dimension dim2;
  output DAE.Dimension dim;
algorithm
  dim := matchcontinue (dim1,dim2)
    local
      Integer i1,i2,i;
    case (_,_)
      equation
        i = dimensionSize(dim1)+dimensionSize(dim2);
      then DAE.DIM_INTEGER(i);
    else DAE.DIM_UNKNOWN();
  end matchcontinue;
end addDimensions;

public function dimensionSizeAll
  "Extracts an integer from an array dimension. Also handles DIM_EXP and
  DIM_UNKNOWN if checkModel is used."
  input DAE.Dimension dim;
  output Integer value;
algorithm
  value := matchcontinue(dim)
    local
      Integer i;
      DAE.Exp e;
    case DAE.DIM_INTEGER(integer = i) then i;
    case DAE.DIM_ENUM(size = i) then i;
    case DAE.DIM_BOOLEAN() then 2;
    case DAE.DIM_EXP(exp = e) then expInt(e);
    case DAE.DIM_EXP()
      equation
        true = Flags.getConfigBool(Flags.CHECK_MODEL);
      then
        0;
    case DAE.DIM_UNKNOWN()
      equation
        true = Flags.getConfigBool(Flags.CHECK_MODEL);
      then
        0;
  end matchcontinue;
end dimensionSizeAll;

public function dimensionsSizes
  "Extracts a list of integers from a list of array dimensions"
  input DAE.Dimensions inDims;
  output list<Integer> outValues;
algorithm
  outValues := List.map(inDims, dimensionSizeAll);
end dimensionsSizes;

public function typeof "Retrieves the Type of the Expression"
  input DAE.Exp inExp;
  output DAE.Type outType;
algorithm
  outType := matchcontinue (inExp)
    local
      Type tp;
      Operator op;
      DAE.Exp e1,e2,e3,e;
      list<DAE.Exp> explist,exps;
      Absyn.Path p;
      String msg;
      DAE.Type ty;
      list<DAE.Type> tys;
      Integer i,i1,i2;
      DAE.Dimension dim;

    case (DAE.ICONST()) then DAE.T_INTEGER_DEFAULT;
    case (DAE.RCONST()) then DAE.T_REAL_DEFAULT;
    case (DAE.SCONST()) then DAE.T_STRING_DEFAULT;
    case (DAE.BCONST()) then DAE.T_BOOL_DEFAULT;
    case (DAE.ENUM_LITERAL(name = p, index=i)) then DAE.T_ENUMERATION(SOME(i), p, {}, {}, {}, DAE.emptyTypeSource);
    case (DAE.CREF(ty = tp)) then tp;
    case (DAE.BINARY(operator = op)) then typeofOp(op);
    case (DAE.UNARY(operator = op)) then typeofOp(op);
    case (DAE.LBINARY(operator = op)) then typeofOp(op);
    case (DAE.LUNARY(operator = op)) then typeofOp(op);
    case (DAE.RELATION(operator = op)) then typeofRelation(typeofOp(op));
    case (DAE.IFEXP(expThen = e2)) then typeof(e2);
    case (DAE.CALL(attr = DAE.CALL_ATTR(ty=tp))) then tp;
    case (DAE.RECORD(ty=tp)) then tp;
    case (DAE.PARTEVALFUNCTION(ty=tp)) then tp;
    case (DAE.ARRAY(ty = tp)) then tp;
    case (DAE.MATRIX(ty = tp)) then tp;
    case (DAE.RANGE(start=DAE.ICONST(i1),step=NONE(),stop=DAE.ICONST(i2),ty = tp as DAE.T_INTEGER()))
      equation
        i = intMax(0,i2-i1+1);
      then DAE.T_ARRAY(tp, {DAE.DIM_INTEGER(i)}, DAE.emptyTypeSource);
    case (DAE.RANGE(start=DAE.ICONST(1),step=NONE(),stop=e,ty = tp as DAE.T_INTEGER()))
      then DAE.T_ARRAY(tp, {DAE.DIM_EXP(e)}, DAE.emptyTypeSource);
    case (DAE.RANGE(ty = tp)) then DAE.T_ARRAY(tp, {DAE.DIM_UNKNOWN()}, DAE.emptyTypeSource);
    case (DAE.CAST(ty = tp)) then tp;
    case (DAE.ASUB(exp = e,sub=explist))
      equation
        tp = unliftArrayTypeWithSubs(List.map(explist,makeIndexSubscript) ,typeof(e));
      then
        tp;
    case (DAE.TSUB(ty = tp)) then tp;
    case (DAE.CODE(ty = tp)) then tp;
      /* array reduction with known size */
    case (DAE.REDUCTION(iterators={DAE.REDUCTIONITER(exp=e,guardExp=NONE())},reductionInfo=DAE.REDUCTIONINFO(exprType=ty as DAE.T_ARRAY(dims=dim::_),path = Absyn.IDENT("array"))))
      equation
        false = dimensionKnown(dim);
        DAE.T_ARRAY(dims={dim}) = typeof(e);
        true = dimensionKnown(dim);
        tp = liftArrayR(Types.unliftArray(Types.simplifyType(ty)),dim);
      then tp;
    case (DAE.REDUCTION(reductionInfo=DAE.REDUCTIONINFO(exprType=ty)))
      then Types.simplifyType(ty);
    case (DAE.SIZE(_,NONE())) then DAE.T_ARRAY(DAE.T_INTEGER_DEFAULT,{DAE.DIM_UNKNOWN()},DAE.emptyTypeSource);
    case (DAE.SIZE(_,SOME(_))) then DAE.T_INTEGER_DEFAULT;

    // MetaModelica extension
    case (DAE.LIST()) then DAE.T_METATYPE(DAE.T_METALIST_DEFAULT, DAE.emptyTypeSource);
    case (DAE.CONS()) then DAE.T_METATYPE(DAE.T_METALIST_DEFAULT, DAE.emptyTypeSource);
    case (DAE.META_TUPLE(exps))
      equation
         tys = List.map(exps, typeof);
      then
        DAE.T_METATYPE(DAE.T_METATUPLE(tys, DAE.emptyTypeSource), DAE.emptyTypeSource);
    case (DAE.TUPLE(exps))
      equation
         tys = List.map(exps, typeof);
      then
        DAE.T_TUPLE(tys, DAE.emptyTypeSource);
    case (DAE.META_OPTION(_))then DAE.T_METATYPE(DAE.T_NONE_DEFAULT, DAE.emptyTypeSource);
    case (DAE.METARECORDCALL(path=p, index = i))
      equation

      then
        DAE.T_METATYPE(DAE.T_METARECORD(p, i, {}, false, DAE.emptyTypeSource), DAE.emptyTypeSource);
    case (DAE.BOX(e))
      equation
         ty = typeof(e);
      then
        DAE.T_METATYPE(DAE.T_METABOXED(ty, DAE.emptyTypeSource), DAE.emptyTypeSource);
    case (DAE.MATCHEXPRESSION(et=tp))
      then tp;
    case (DAE.UNBOX(ty = tp)) then tp;
    case (DAE.SHARED_LITERAL(exp = e)) then typeof(e);
    // A little crazy, but sometimes we call typeof on things that will not be used in the end...
    case (DAE.EMPTY(ty = tp)) then tp;

    case e
      equation
        msg = "- Expression.typeof failed for " + ExpressionDump.printExpStr(e);
        Error.addMessage(Error.INTERNAL_ERROR, {msg});
      then fail();
  end matchcontinue;
end typeof;

protected function typeofRelation
"Boolean or array of boolean"
  input DAE.Type inType;
  output DAE.Type outType;
algorithm
  outType := match(inType)
    local
      Type ty,ty1;
      DAE.Dimensions dims;
      DAE.TypeSource source;
    case (DAE.T_ARRAY(ty=ty,dims=dims,source=source))
      equation
        _ = typeofRelation(ty);
      then
        DAE.T_ARRAY(ty,dims,source);
    else DAE.T_BOOL_DEFAULT;
  end match;
end typeofRelation;

public function typeofOp
"Helper function to typeof"
  input DAE.Operator inOperator;
  output DAE.Type outType;
algorithm
  outType := match (inOperator)
    local Type t;

    case (DAE.ADD(ty = t)) then t;
    case (DAE.SUB(ty = t)) then t;
    case (DAE.MUL(ty = t)) then t;
    case (DAE.DIV(ty = t)) then t;
    case (DAE.POW(ty = t)) then t;
    case (DAE.UMINUS(ty = t)) then t;
    case (DAE.UMINUS_ARR(ty = t)) then t;
    case (DAE.ADD_ARR(ty = t)) then t;
    case (DAE.SUB_ARR(ty = t)) then t;
    case (DAE.MUL_ARR(ty = t)) then t;
    case (DAE.DIV_ARR(ty = t)) then t;
    case (DAE.MUL_ARRAY_SCALAR(ty = t)) then t;
    case (DAE.ADD_ARRAY_SCALAR(ty = t)) then t;
    case (DAE.SUB_SCALAR_ARRAY(ty = t)) then t;
    case (DAE.MUL_SCALAR_PRODUCT(ty = t)) then t;
    case (DAE.MUL_MATRIX_PRODUCT(ty = t)) then t;
    case (DAE.DIV_ARRAY_SCALAR(ty = t)) then t;
    case (DAE.DIV_SCALAR_ARRAY(ty = t)) then t;
    case (DAE.POW_ARRAY_SCALAR(ty = t)) then t;
    case (DAE.POW_SCALAR_ARRAY(ty = t)) then t;
    case (DAE.POW_ARR(ty = t)) then t;
    case (DAE.POW_ARR2(ty = t)) then t;
    case (DAE.AND(ty = t)) then t;
    case (DAE.OR(ty = t)) then t;
    case (DAE.NOT(ty = t)) then t;
    case (DAE.LESS(ty = t)) then t;
    case (DAE.LESSEQ(ty = t)) then t;
    case (DAE.GREATER(ty = t)) then t;
    case (DAE.GREATEREQ(ty = t)) then t;
    case (DAE.EQUAL(ty = t)) then t;
    case (DAE.NEQUAL(ty = t)) then t;
    case (DAE.USERDEFINED()) then DAE.T_UNKNOWN_DEFAULT;
  end match;
end typeofOp;

public function getRelations
"Retrieve all function sub expressions in an expression."
  input DAE.Exp inExp;
  output list<DAE.Exp> outExpLst;
algorithm
  outExpLst := matchcontinue (inExp)
    local
      DAE.Exp e,e1,e2,cond,tb,fb;
      list<DAE.Exp> rellst1,rellst2,rellst,rellst3,rellst4,xs;
      Type t;
      Boolean sc;

    case ((e as DAE.RELATION())) then {e};

    case (DAE.LBINARY(exp1 = e1,exp2 = e2))
      equation
        rellst1 = getRelations(e1);
        rellst2 = getRelations(e2);
        rellst = listAppend(rellst1, rellst2);
      then
        rellst;

    case (DAE.LUNARY(exp = e))
      equation
        rellst = getRelations(e);
      then
        rellst;

    case (DAE.BINARY(exp1 = e1,exp2 = e2))
      equation
        rellst1 = getRelations(e1);
        rellst2 = getRelations(e2);
        rellst = listAppend(rellst1, rellst2);
      then
        rellst;

    case (DAE.IFEXP(expCond = cond,expThen = tb,expElse = fb))
      equation
        rellst1 = getRelations(cond);
        rellst2 = getRelations(tb);
        rellst3 = getRelations(fb);
        rellst4 = listAppend(rellst1, rellst2);
        rellst = listAppend(rellst3, rellst4);
      then
        rellst;

    case (DAE.ARRAY(array = {e}))
      equation
        rellst = getRelations(e);
      then
        rellst;

    case (DAE.ARRAY(ty = t,scalar = sc,array = (e :: xs)))
      equation
        rellst1 = getRelations(DAE.ARRAY(t,sc,xs));
        rellst2 = getRelations(e);
        rellst = listAppend(rellst1, rellst2);
      then
        rellst;

    case (DAE.UNARY(exp = e))
      equation
        rellst = getRelations(e);
      then
        rellst;

    else {};
  end matchcontinue;
end getRelations;

public function allTerms
"simliar to terms, but also perform expansion of
 multiplications to reveal more terms, like for instance:
 allTerms((a+b)*(b+c)) => {a*b,a*c,b*b,b*c}"
  input DAE.Exp inExp;
  output list<DAE.Exp> outExpLst;
algorithm
  outExpLst := matchcontinue (inExp)
    local
      list<DAE.Exp> f1,f2,res,f2_1;
      DAE.Exp e1,e2,e;
      Type tp;
      ComponentRef cr;

    case (DAE.BINARY(exp1 = e1,operator = DAE.ADD(),exp2 = e2))
      equation
        f1 = allTerms(e1);
        f2 = allTerms(e2);
        res = listAppend(f1, f2);
      then
        res;

    case (DAE.BINARY(exp1 = e1,operator = DAE.SUB(),exp2 = e2))
      equation
        f1 = allTerms(e1);
        f2 = allTerms(e2);
        f2_1 = List.map(f2, negate);
        res = listAppend(f1, f2_1);
      then
        res;

    case (DAE.BINARY(exp1 = e1,operator = DAE.ADD_ARR(),exp2 = e2))
      equation
        f1 = allTerms(e1);
        f2 = allTerms(e2);
        res = listAppend(f1, f2);
      then
        res;

    case (DAE.BINARY(exp1 = e1,operator = DAE.SUB_ARR(),exp2 = e2))
      equation
        f1 = allTerms(e1);
        f2 = allTerms(e2);
        f2_1 = List.map(f2, negate);
        res = listAppend(f1, f2_1);
      then
        res;

    // terms( a*(b+c)) => {a*b, c*b}
    case (DAE.BINARY(e1,DAE.MUL(_),e2))
      equation
        (f1 as _::_::_) = allTerms(e2);
        f1 = List.map1(f1,makeProduct,e1);
        f1 = List.flatten(List.map(f1,allTerms));
      then
        f1;

    case (DAE.BINARY(e1,DAE.MUL_ARR(_),e2))
      equation
        (f1 as _::_::_) = allTerms(e2);
        f1 = List.map1(f1,makeProduct,e1);
        f1 = List.flatten(List.map(f1,allTerms));
      then
        f1;

    case (DAE.BINARY(e1,DAE.MUL_ARRAY_SCALAR(_),e2))
      equation
        (f1 as _::_::_) = allTerms(e2);
        f1 = List.map1(f1,makeProduct,e1);
        f1 = List.flatten(List.map(f1,allTerms));
      then
        f1;

    // terms( (b+c)*a) => {b*a, c*a}
    case (DAE.BINARY(e1,DAE.MUL(_),e2))
      equation
        (f1 as _::_::_) = allTerms(e1);
        f1 = List.map1(f1,makeProduct,e2);
        f1 = List.flatten(List.map(f1,allTerms));
      then
        f1;

    case (DAE.BINARY(e1,DAE.MUL_ARR(_),e2))
      equation
        (f1 as _::_::_) = allTerms(e1);
        f1 = List.map1(f1,makeProduct,e2);
        f1 = List.flatten(List.map(f1,allTerms));
      then
        f1;

    case (DAE.BINARY(e1,DAE.MUL_ARRAY_SCALAR(_),e2))
      equation
        (f1 as _::_::_) = allTerms(e1);
        f1 = List.map1(f1,makeProduct,e2);
        f1 = List.flatten(List.map(f1,allTerms));
      then
        f1;

    // terms( (b+c)/a) => {b/a, c/a}
    case (DAE.BINARY(e1,DAE.DIV(_),e2))
      equation
        (f1 as _::_::_) = allTerms(e1);
        f1 = List.map1(f1,expDiv,e2);
        f1 = List.flatten(List.map(f1,allTerms));
      then
        f1;

    case (DAE.BINARY(e1,DAE.DIV_ARR(_),e2))
      equation
        (f1 as _::_::_) = allTerms(e1);
        f1 = List.map1(f1,expDiv,e2);
        f1 = List.flatten(List.map(f1,allTerms));
      then
        f1;

    case (DAE.BINARY(e1,DAE.DIV_ARRAY_SCALAR(_),e2))
      equation
        (f1 as _::_::_) = allTerms(e1);
        f1 = List.map1(f1,expDiv,e2);
        f1 = List.flatten(List.map(f1,allTerms));
      then
        f1;

    case (DAE.BINARY(e1,DAE.DIV_SCALAR_ARRAY(_),e2))
      equation
        (f1 as _::_::_) = allTerms(e1);
        f1 = List.map1(f1,expDiv,e2);
        f1 = List.flatten(List.map(f1,allTerms));
      then
        f1;

    case (DAE.UNARY(operator = DAE.UMINUS(),exp=e1))
      equation
        f1 = allTerms(e1);
        f1 = List.map(f1,negate);
      then
        f1;

    case (DAE.UNARY(operator = DAE.UMINUS_ARR(),exp=e1))
      equation
        f1 = allTerms(e1);
        f1 = List.map(f1,negate);
      then
        f1;

    case (DAE.LUNARY(operator = DAE.NOT(), exp = e1))
      equation
        f1 = allTerms(e1);
        f1 = List.map(f1,negate);
      then
        f1;

    case (DAE.ASUB(exp = e1,sub=f2))
      equation
        f1 = allTerms(e1);
        f1 = List.map1(f1,makeASUB,f2);
      then
        f1;
/*
    case (e as DAE.BINARY(operator = DAE.MUL())) then {e};
    case (e as DAE.BINARY(operator = DAE.MUL_ARR())) then {e};
    case (e as DAE.BINARY(operator = DAE.MUL_ARRAY_SCALAR())) then {e};
    case (e as DAE.BINARY(operator = DAE.DIV())) then {e};
    case (e as DAE.BINARY(operator = DAE.DIV_ARR())) then {e};
    case (e as DAE.BINARY(operator = DAE.DIV_ARRAY_SCALAR())) then {e};
    case (e as DAE.BINARY(operator = DAE.DIV_SCALAR_ARRAY())) then {e};
    case (e as DAE.BINARY(operator = DAE.POW())) then {e};
    case (e as DAE.BINARY(operator = DAE.POW_ARR())) then {e};
    case (e as DAE.BINARY(operator = DAE.POW_ARR2())) then {e};
    case (e as DAE.BINARY(operator = DAE.POW_ARRAY_SCALAR())) then {e};
    case (e as DAE.BINARY(operator = DAE.POW_SCALAR_ARRAY())) then {e};
    case (e as DAE.CREF()) then {e};
    case (e as DAE.ICONST()) then {e};
    case (e as DAE.RCONST()) then {e};
    case (e as DAE.SCONST()) then {e};
    case ((e as DAE.ENUM_LITERAL())) then {e};
    case (e as DAE.UNARY()) then {e};
    case (e as DAE.IFEXP()) then {e};
    case (e as DAE.CALL()) then {e};
    case (e as DAE.RECORD()) then {e};
    case (e as DAE.PARTEVALFUNCTION()) then {e};
    case (e as DAE.ARRAY()) then {e};
    case (e as DAE.MATRIX()) then {e};
    case (e as DAE.RANGE()) then {e};
    case (e as DAE.CAST()) then {e};
    case (e as DAE.ASUB()) then {e};
    case (e as DAE.SIZE()) then {e};
    case (e as DAE.REDUCTION()) then {e};
*/
    else {inExp};
  end matchcontinue;
end allTerms;

public function terms
  "Returns the terms of the expression if any as a list of expressions"
  input DAE.Exp inExp;
  output list<DAE.Exp> outExpLst;
algorithm
  outExpLst := terms2(inExp,{},false);
end terms;

protected function terms2
  "Returns the terms of the expression if any as a list of expressions"
  input DAE.Exp inExp;
  input list<DAE.Exp> inAcc;
  input Boolean neg;
  output list<DAE.Exp> outExpLst;
algorithm
  outExpLst := match (inExp,inAcc,neg)
    local
      DAE.Exp e1,e2,e;
      list<DAE.Exp> acc;

    case (DAE.BINARY(exp1 = e1,operator = DAE.ADD(),exp2 = e2),acc,_)
      equation
        acc = terms2(e2,acc,neg);
        acc = terms2(e1,acc,neg);
      then acc;

    case (DAE.BINARY(exp1 = e1,operator = DAE.SUB(),exp2 = e2),acc,_)
      equation
        acc = terms2(e2,acc,not neg);
        acc = terms2(e1,acc,neg);
      then acc;

    case (e,acc,true)
      equation
        e = negate(e);
      then e::acc;
    case (e,acc,_) then e::acc;
  end match;
end terms2;

public function quotient
"author: PA
  Returns the quotient of an expression.
  For instance e = p/q returns (p,q) for numerator p and denominator q."
  input DAE.Exp inExp;
  output DAE.Exp num;
  output DAE.Exp denom;
algorithm
  (num,denom):=
  matchcontinue (inExp)
    local
      DAE.Exp e1,e2,p,q;
      Type tp;
    case (DAE.BINARY(exp1 = e1,operator = DAE.DIV(),exp2 = e2)) then (e1,e2);  /* (numerator,denominator) */
    case (DAE.BINARY(exp1 = e1,operator = DAE.MUL(),exp2 = e2))
      equation
        (p,q) = quotient(e1);
        tp = typeof(p);
      then
        (DAE.BINARY(e2,DAE.MUL(tp),p),q);
    case (DAE.BINARY(exp1 = e1,operator = DAE.MUL(),exp2 = e2))
      equation
        (p,q) = quotient(e2);
        tp = typeof(p);
      then
        (DAE.BINARY(e1,DAE.MUL(tp),p),q);
  end matchcontinue;
end quotient;

public function factors
"Returns the factors of the expression if any as a list of expressions"
  input DAE.Exp inExp;
  output list<DAE.Exp> outExpLst;
algorithm
  // TODO: Remove this listReverse as it is pointless.
  // It transforms a*b to b*a, but the testsuite expects this :(
  outExpLst := listReverse(factorsWork(inExp,{},false,false));
end factors;

protected function factorsWork
"Returns the factors of the expression if any as a list of expressions"
  input DAE.Exp inExp;
  input list<DAE.Exp> inAcc;
  input Boolean noFactors "Decides if the default is the empty list or not";
  input Boolean doInverseFactors "Decides if a factor e should be 1/e instead";
  output list<DAE.Exp> outExpLst;
algorithm
  outExpLst := match (inExp,inAcc,noFactors,doInverseFactors)
    local
      DAE.Exp e1,e2,e;
      ComponentRef cr;
      Real r;
      Boolean b;
      list<DAE.Exp> acc;

    case (DAE.BINARY(exp1 = e1,operator = DAE.MUL(),exp2 = e2),acc,_,_)
      equation
        acc = factorsWork(e1,acc,true,doInverseFactors);
        acc = factorsWork(e2,acc,true,doInverseFactors);
      then acc;
    case (DAE.BINARY(exp1 = e1,operator = DAE.DIV(ty = DAE.T_REAL()),exp2 = e2),acc,_,_)
      equation
        acc = factorsWork(e1,acc,true,doInverseFactors);
        acc = factorsWork(e2,acc,true,not doInverseFactors);
      then acc;
    case (DAE.CREF(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.BINARY(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.ICONST(integer = 1),acc,_,_)
      then acc;
    case (DAE.ICONST(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.RCONST(real = r),acc,_,_)
      equation
        b = not realEq(r,1.0);
        e = if b and doInverseFactors then inverseFactors(inExp) else inExp;
        acc = List.consOnTrue(b, e, acc);
      then acc;
    case (DAE.SCONST(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.UNARY(),acc,_,_) // factor(-(x*y)) is -(x*y) ??
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.LUNARY(),acc,_,_)
      then inExp::acc;
    case (DAE.IFEXP(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.CALL(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.RECORD(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.RECORD(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.PARTEVALFUNCTION(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.ARRAY(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.MATRIX(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.RANGE(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.CAST(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.ASUB(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.TSUB(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.SIZE(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (DAE.REDUCTION(),acc,_,_)
      equation
        e = if doInverseFactors then inverseFactors(inExp) else inExp;
      then e::acc;
    case (e,acc,true,_)
      equation
        e = if doInverseFactors then inverseFactors(e) else e;
      then e::acc;
    case (_,acc,false,_)
      then acc;
  end match;
end factorsWork;

public function inverseFactors
"each expression in the list inversed.
  For example: inverseFactors {a, 3+b} => {1/a, 1/3+b}"
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue (inExp)
    local
      Type tp2,tp;
      DAE.Exp e1,e2,e;
      DAE.Operator op;

    // e1^e2 =>e1^(-e2)
    case (DAE.BINARY(exp1 = e1,operator = DAE.POW(ty = tp),exp2 = e2))
      equation
        tp2 = typeof(e2);
      then
        DAE.BINARY(e1,DAE.POW(tp),DAE.UNARY(DAE.UMINUS(tp2),e2));

    // e1 / e2 = e2 / e1
    case (DAE.BINARY(exp1 = e1,operator = op as DAE.DIV(),exp2 = e2))
      equation
       false = isZero(e1);
      then
        DAE.BINARY(e2,op,e1);

    case e
      equation
        false = isZero(e);
        tp = typeof(e);
        e = match(tp)
          case DAE.T_REAL() then DAE.BINARY(DAE.RCONST(1.0),DAE.DIV(DAE.T_REAL_DEFAULT),e);
          case DAE.T_INTEGER() then DAE.BINARY(DAE.ICONST(1),DAE.DIV(DAE.T_INTEGER_DEFAULT),e);
        end match;
      then
        e;
  end matchcontinue;
end inverseFactors;

public function expandFactors
"
 Returns the factors of the expression if any as a list of expressions.
 e.g.
 -(x*(x*y)^n) -> {-1,x,x^n,x^n}
"
  input DAE.Exp inExp;
  output list<DAE.Exp> outExpLst;
algorithm
  // TODO: Remove this listReverse as it is pointless.
  // It transforms a*b to b*a, but the testsuite expects this :(
  // issue with expEqual(a*b,b*a) return false
  outExpLst := listReverse(expandFactorsWork(inExp,{},false,false));
end expandFactors;

protected function expandFactorsWork
"Returns the factors of the expression if any as a list of expressions"
  input DAE.Exp inExp;
  input list<DAE.Exp> inAcc;
  input Boolean noFactors "Decides if the default is the empty list or not";
  input Boolean doInverseFactors "Decides if a factor e should be 1/e instead";
  output list<DAE.Exp> outExpLst;
algorithm

  outExpLst := match (inExp,inAcc,noFactors,doInverseFactors)
    local
      DAE.Exp e1,e2,e3,e;
      Type tp;
      list<DAE.Exp> acc, pow_acc, pow_acc2;

    // (x*y)^n = x^n*y^n
    case (DAE.BINARY(DAE.BINARY(e1,DAE.MUL(),e2), DAE.POW(), e3),acc,_,_)
      equation
        pow_acc = expandFactorsWork(e1,{},noFactors,doInverseFactors);
        pow_acc = expPowLst(pow_acc, e3);

        pow_acc2 = expandFactorsWork(e2,{},noFactors,doInverseFactors);
        pow_acc2 = expPowLst(pow_acc2, e3);

        acc = List.appendNoCopy(pow_acc, acc);
        acc = List.appendNoCopy(pow_acc2, acc);
      then acc;
    // (x/y)^n = x^n*y^(-n)
    case (DAE.BINARY(DAE.BINARY(e1,DAE.DIV(),e2), DAE.POW(), e3),acc,_,_)
      equation
        pow_acc = expandFactorsWork(e1,{},noFactors,doInverseFactors);
        pow_acc = expPowLst(pow_acc, e3);

        pow_acc2 = expandFactorsWork(e2,{},noFactors,doInverseFactors);
        pow_acc2 = expPowLst(pow_acc2, negate(e3));

        acc = List.appendNoCopy(pow_acc, acc);
        acc = List.appendNoCopy(pow_acc2, acc);
      then acc;
    // (x^n)^m = x^(n*m)
    case (DAE.BINARY(DAE.BINARY(e1,DAE.POW(),e2), DAE.POW(), e3),acc,_,_)
      equation
        e = expMul(e2,e3);
        pow_acc = expandFactorsWork(e1,{},noFactors,doInverseFactors);
        pow_acc = expPowLst(pow_acc, e);

        acc = List.appendNoCopy(pow_acc, acc);
      then acc;
    // ToDo
    // exp(x + y) = exp(x)*exp(y)
    // exp(x - y) = exp(x)/exp(y)
    // abs(x*y) = abs(x)*abs(y)
    // abs(x/y) = abs(x)/abs(y);

    // -(x) = -1*x
    case(DAE.UNARY(DAE.UMINUS(tp),e1),acc,_,_)
      equation
        e = makeConstOne(tp);
        acc = expandFactorsWork(e1,acc,true,doInverseFactors);
        e = negate(e);
      then e::acc;
    case(DAE.UNARY(DAE.UMINUS_ARR(tp),e1),acc,_,_)
      equation
        e = makeConstOne(tp);
        acc = expandFactorsWork(e1,acc,true,doInverseFactors);
        e = negate(e);
      then e::acc;

   else
     equation
       acc = factorsWork(inExp,inAcc,noFactors,doInverseFactors);
     then expandFactorsWork2(acc, noFactors, doInverseFactors);

   end match;

end expandFactorsWork;

protected function expandFactorsWork2
  input list<DAE.Exp> inAcc;
  input Boolean noFactors "Decides if the default is the empty list or not";
  input Boolean doInverseFactors "Decides if a factor e should be 1/e instead";
  output list<DAE.Exp> outExpLst := {};
protected
  list<DAE.Exp> tmpExpLst;
algorithm

for elem in inAcc loop
  tmpExpLst := match(elem)
                 case(DAE.BINARY(DAE.BINARY(_,DAE.DIV(),_), DAE.POW(), _)) then expandFactorsWork(elem,{},noFactors,doInverseFactors);
                 case(DAE.BINARY(DAE.BINARY(_,DAE.MUL(),_), DAE.POW(), _)) then expandFactorsWork(elem,{},noFactors,doInverseFactors);
                 case(DAE.BINARY(DAE.BINARY(_,DAE.POW(),_), DAE.POW(), _)) then expandFactorsWork(elem,{},noFactors,doInverseFactors);
                 case(DAE.UNARY(DAE.UMINUS(),_))  then expandFactorsWork(elem,{},noFactors,doInverseFactors);
                 case(DAE.UNARY(DAE.UMINUS_ARR(),_))  then expandFactorsWork(elem,{},noFactors,doInverseFactors);
                 else {elem};
               end match;
  outExpLst := List.appendNoCopy(tmpExpLst, outExpLst);
end for;

end expandFactorsWork2;


public function getTermsContainingX
"Retrieves all terms of an expression containng a variable,
  given as second argument (in the form of an Exp)"
  input DAE.Exp inExp1;
  input DAE.Exp inExp2;
  output DAE.Exp outExp1;
  output DAE.Exp outExp2;
algorithm
  (outExp1,outExp2) := matchcontinue (inExp1,inExp2)
    local
      DAE.Exp xt1,nonxt1,xt2,nonxt2,xt,nonxt,e1,e2,cr,e,zero;
      Type ty;
      Boolean res;
    case (DAE.BINARY(exp1 = e1,operator = DAE.ADD(ty = ty),exp2 = e2),(cr as DAE.CREF()))
      equation
        (xt1,nonxt1) = getTermsContainingX(e1, cr);
        (xt2,nonxt2) = getTermsContainingX(e2, cr);
        xt = DAE.BINARY(xt1,DAE.ADD(ty),xt2);
        nonxt = DAE.BINARY(nonxt1,DAE.ADD(ty),nonxt2);
      then
        (xt,nonxt);
    case (DAE.BINARY(exp1 = e1,operator = DAE.SUB(ty = ty),exp2 = e2),(cr as DAE.CREF()))
      equation
        (xt1,nonxt1) = getTermsContainingX(e1, cr);
        (xt2,nonxt2) = getTermsContainingX(e2, cr);
        xt = DAE.BINARY(xt1,DAE.SUB(ty),xt2);
        nonxt = DAE.BINARY(nonxt1,DAE.SUB(ty),nonxt2);
      then
        (xt,nonxt);
    case (DAE.UNARY(operator = DAE.UMINUS(ty = ty),exp = e),(cr as DAE.CREF()))
      equation
        (xt1,nonxt1) = getTermsContainingX(e, cr);
        xt = DAE.UNARY(DAE.UMINUS(ty),xt1);
        nonxt = DAE.UNARY(DAE.UMINUS(ty),nonxt1);
      then
        (xt,nonxt);
    case (DAE.BINARY(exp1 = e1,operator = DAE.ADD_ARR(ty = ty),exp2 = e2),(cr as DAE.CREF()))
      equation
        (xt1,nonxt1) = getTermsContainingX(e1, cr);
        (xt2,nonxt2) = getTermsContainingX(e2, cr);
        xt = DAE.BINARY(xt1,DAE.ADD_ARR(ty),xt2);
        nonxt = DAE.BINARY(nonxt1,DAE.ADD_ARR(ty),nonxt2);
      then
        (xt,nonxt);
    case (DAE.BINARY(exp1 = e1,operator = DAE.SUB_ARR(ty = ty),exp2 = e2),(cr as DAE.CREF()))
      equation
        (xt1,nonxt1) = getTermsContainingX(e1, cr);
        (xt2,nonxt2) = getTermsContainingX(e2, cr);
        xt = DAE.BINARY(xt1,DAE.SUB_ARR(ty),xt2);
        nonxt = DAE.BINARY(nonxt1,DAE.SUB_ARR(ty),nonxt2);
      then
        (xt,nonxt);
    case (DAE.UNARY(operator = DAE.UMINUS_ARR(ty = ty),exp = e),(cr as DAE.CREF()))
      equation
        (xt1,nonxt1) = getTermsContainingX(e, cr);
        xt = DAE.UNARY(DAE.UMINUS_ARR(ty),xt1);
        nonxt = DAE.UNARY(DAE.UMINUS_ARR(ty),nonxt1);
      then
        (xt,nonxt);
    case (e,(cr as DAE.CREF(ty = ty)))
      equation
        res = expContains(e, cr);
        (zero,_) = makeZeroExpression(arrayDimension(ty));
        xt = if res then e else zero;
        nonxt = if res then zero else e;
      then
        (xt,nonxt);
    else
      equation
        /*Print.printBuf("Expression.getTerms_containingX failed: ");
        ExpressionDump.printExp(e);
        Print.printBuf("\nsolving for: ");
        ExpressionDump.printExp(cr);
        Print.printBuf("\n");*/
      then
        fail();
  end matchcontinue;
end getTermsContainingX;

public function flattenArrayExpToList "returns all non-array expressions of an array expression as a long list
E.g. {[1,2;3,4],[4,5;6,7]} => {1,2,3,4,4,5,6,7}"
  input DAE.Exp e;
  output list<DAE.Exp> expLst;
algorithm
  expLst := matchcontinue(e)
    local
      list<DAE.Exp> expl;
      list<list<DAE.Exp>> mexpl;
    case(DAE.UNARY(operator=DAE.UMINUS_ARR(),exp=DAE.ARRAY(array=expl)))
      equation
        expl = List.flatten(List.map(expl,flattenArrayExpToList));
        expLst = List.map(expl,negate);
      then expLst;
    case(DAE.ARRAY(array=expl))
      equation
        expLst = List.flatten(List.map(expl,flattenArrayExpToList));
      then expLst;
    case(DAE.UNARY(operator=DAE.UMINUS_ARR(),exp=DAE.MATRIX(matrix=mexpl)))
      equation
        expl = List.flatten(List.map(List.flatten(mexpl),flattenArrayExpToList));
        expLst = List.map(expl,negate);
      then expLst;
    case(DAE.MATRIX(matrix=mexpl))
      equation
        expLst = List.flatten(List.map(List.flatten(mexpl),flattenArrayExpToList));
      then expLst;
    case _ then {e};
  end matchcontinue;
end flattenArrayExpToList;

/***************************************************/
/* generate  */
/***************************************************/

public function makeNoEvent " adds a noEvent call around an expression"
input DAE.Exp e1;
output DAE.Exp res;
algorithm
  res := DAE.CALL(Absyn.IDENT("noEvent"),{e1},DAE.callAttrBuiltinBool);
end makeNoEvent;

public function makeNestedIf "creates a nested if expression given a list of conditions and
guared expressions and a default value (the else branch)"
  input list<DAE.Exp> inConds "conditions";
  input list<DAE.Exp> inTbExps " guarded expressions, for each condition";
  input DAE.Exp fExp "default value, else branch";
  output DAE.Exp ifExp;
algorithm
  ifExp := matchcontinue(inConds,inTbExps,fExp)
    local DAE.Exp c,tbExp; list<DAE.Exp> conds, tbExps;
    case({c},{tbExp},_)
    then DAE.IFEXP(c,tbExp,fExp);
    case(c::conds,tbExp::tbExps,_)
      equation
        ifExp = makeNestedIf(conds,tbExps,fExp);
      then DAE.IFEXP(c,tbExp,ifExp);
  end matchcontinue;
end makeNestedIf;

public function makeCrefExp
"Makes an expression of a component reference, given also a type"
  input DAE.ComponentRef inCref;
  input DAE.Type inExpType;
  output DAE.Exp outExp;
algorithm
  outExp := match(inCref, inExpType)
    local
      ComponentRef cref;
      Type tGiven, tExisting;

    case (cref, tGiven)
      equation
        if Flags.isSet(Flags.CHECK_DAE_CREF_TYPE)
        then // check type
          tExisting = ComponentReference.crefLastType(cref);
          if not valueEq(tGiven, tExisting)
          then // type not the same
            Debug.traceln("Warning: Expression.makeCrefExp: cref " + ComponentReference.printComponentRefStr(cref) + " was given type DAE.CREF.ty: " +
                      Types.unparseType(tGiven) +
                      " is different from existing DAE.CREF.componentRef.ty: " +
                      Types.unparseType(tExisting));
          end if;
        end if;
      then
        DAE.CREF(cref, tGiven);

  end match;
end makeCrefExp;

public function crefExp "
Author: BZ, 2008-08
generate an DAE.CREF(ComponentRef, Type) from a ComponenRef, make array type correct from subs"
  input DAE.ComponentRef cr;
  output DAE.Exp cref;
algorithm
  cref := match(cr)
    local
      Type ty1,ty2;
      list<DAE.Subscript> subs;

    case _
      equation
        ty1 = ComponentReference.crefLastType(cr);
        cref = match(ty1)
          case DAE.T_ARRAY()
            equation
              subs = ComponentReference.crefLastSubs(cr);
              ty2 = unliftArrayTypeWithSubs(subs,ty1);
            then DAE.CREF(cr,ty2);
          else DAE.CREF(cr,ty1);
        end match;
      then
        cref;

  end match;
end crefExp;

public function makeASUB
"@author: adrpo
  Creates an ASUB given an expression and a list of expression indexes.
  If flag +d=checkASUB is ON we give a warning that the given exp is
  not a component reference."
  input DAE.Exp inExp;
  input list<DAE.Exp> inSubs;
  output DAE.Exp outExp;
algorithm
  outExp := match(inExp,inSubs)
    local
      DAE.Exp exp;
      list<DAE.Exp> subs,subs1,subs2;

    // We need to be careful when constructing ASUB's. All subscripts should be in a list.
    case (DAE.ASUB(exp,subs1),subs2)
      equation
        subs = listAppend(subs1,subs2);
        exp = DAE.ASUB(exp,subs);
      then
        exp;

    case(_, _)
      equation
        if Flags.isSet(Flags.CHECK_ASUB) // check the DAE.ASUB
        then
          _ = match(inExp) // check the DAE.ASUB so that the given expression is NOT a cref
            case (DAE.CREF())
              equation
                Debug.traceln("Warning: makeASUB: given expression: " +
                        ExpressionDump.printExpStr(inExp) +
                        " contains a component reference!\n" +
                        " Subscripts exps: [" + stringDelimitList(List.map(inSubs, ExpressionDump.printExpStr), ",")+ "]\n" +
                        "DAE.ASUB should not be used for component references, instead the subscripts should be added directly to the component reference!");
              then ();
            else (); // check the DAE.ASUB -> was not a cref
          end match;
        end if;
        exp = DAE.ASUB(inExp,inSubs);
      then
        exp;

  end match;
end makeASUB;

public function makeASUBSingleSub
  input DAE.Exp exp;
  input DAE.Exp sub;
  output DAE.Exp outExp;
algorithm
  outExp := makeASUB(exp,{sub});
end makeASUBSingleSub;

public function generateCrefsExpFromExpVar "
Author: Frenkel TUD 2010-05"
  input DAE.Var inVar;
  input DAE.ComponentRef inCrefPrefix;
  output DAE.Exp outCrefExp;
algorithm outCrefExp := match(inVar,inCrefPrefix)
  local
    String name;
    DAE.Type ty;
    DAE.ComponentRef cr;
    DAE.Exp e;

  case (DAE.TYPES_VAR(name=name,ty=ty),_)
    equation
      cr = ComponentReference.crefPrependIdent(inCrefPrefix,name,{},ty);
      e = makeCrefExp(cr, ty);
    then
      e;

 end match;
end generateCrefsExpFromExpVar;

public function generateCrefsFromExpVar "
Author: Frenkel TUD 2010-05"
  input DAE.Var inVar;
  input DAE.ComponentRef inCrefPrefix;
  output DAE.ComponentRef outCref;
algorithm outCref := match(inVar,inCrefPrefix)
  local
    String name;
    DAE.Type ty;
    DAE.ComponentRef cr;
    DAE.Exp e;

  case (DAE.TYPES_VAR(name=name,ty=ty),_)
  equation
    cr = ComponentReference.crefPrependIdent(inCrefPrefix,name,{},ty);
  then
    cr;
 end match;
end generateCrefsFromExpVar;

public function generateCrefsExpFromExp
  input DAE.Exp inExp;
  input DAE.ComponentRef inCrefPrefix;
  output DAE.Exp outCrefExp;
algorithm
  outCrefExp := match(inExp,inCrefPrefix)
    local
      String name;
      DAE.Type ty;
      DAE.ComponentRef cr;
      DAE.Exp e;
      Absyn.Path p1,p2;
      list<DAE.Exp> explst;
      Boolean b;
      DAE.CallAttributes attr;

    case (DAE.CREF(componentRef=DAE.WILD()), _) then inExp;

    case (DAE.ARRAY(ty=ty, scalar=b, array=explst), _)
      equation
        explst = List.map1(explst, generateCrefsExpFromExp, inCrefPrefix);
      then DAE.ARRAY(ty, b, explst);

    case (DAE.CALL(path=p1,expLst=explst,attr=attr as DAE.CALL_ATTR(ty=DAE.T_COMPLEX(complexClassType=ClassInf.RECORD(p2)))),_)
      equation
        true = Absyn.pathEqual(p1,p2) "is record constructor";
        explst = List.map1(explst, generateCrefsExpFromExp, inCrefPrefix);
      then
        DAE.CALL(p1,explst,attr);

    case (DAE.CREF(componentRef=cr,ty=ty),_)
      equation
        name = ComponentReference.crefModelicaStr(cr);
        cr = ComponentReference.crefPrependIdent(inCrefPrefix,name,{},ty);
        e = makeCrefExp(cr, ty);
      then
        e;
  end match;
end generateCrefsExpFromExp;

public function generateCrefsExpLstFromExp
  input DAE.Exp inExp;
  input Option<DAE.ComponentRef> inCrefPrefix;
  output list<DAE.Exp> outCrefExpList;
algorithm
  outCrefExpList := match(inExp,inCrefPrefix)
    local
      String name;
      DAE.Type ty;
      DAE.ComponentRef cr, incref;
      DAE.Exp e;
      Absyn.Path p1,p2;
      list<DAE.Exp> explst;
      Boolean b;

    case (DAE.ARRAY( array=explst), _)
      equation
        explst = List.flatten(List.map1(explst, generateCrefsExpLstFromExp, inCrefPrefix));
      then explst;

    case (DAE.CALL(path=p1,expLst=explst,attr=DAE.CALL_ATTR(ty=DAE.T_COMPLEX(complexClassType=ClassInf.RECORD(p2)))),_)
      equation
        true = Absyn.pathEqual(p1,p2) "is record constructor";
        explst = List.flatten(List.map1(explst, generateCrefsExpLstFromExp, inCrefPrefix));
      then
        explst;

    case (DAE.CREF(componentRef=cr,ty=ty),SOME(incref))
      equation
        name = ComponentReference.crefModelicaStr(cr);
        cr = ComponentReference.crefPrependIdent(incref,name,{},ty);
        e = makeCrefExp(cr, ty);
      then
        {e};

    case (DAE.CREF(),NONE()) then {inExp};
  end match;
end generateCrefsExpLstFromExp;

public function makeArray
  input list<DAE.Exp> inElements;
  input DAE.Type inType;
  input Boolean inScalar;
  output DAE.Exp outArray;
algorithm
  outArray := DAE.ARRAY(inType, inScalar, inElements);
end makeArray;

public function makeScalarArray
  "Constructs an array of the given scalar type."
  input list<DAE.Exp> inExpLst;
  input DAE.Type et;
  output DAE.Exp outExp;
protected
  Integer i;
algorithm
  i := listLength(inExpLst);
  outExp := DAE.ARRAY(DAE.T_ARRAY(et, {DAE.DIM_INTEGER(i)}, DAE.emptyTypeSource), true, inExpLst);
end makeScalarArray;

public function makeRealArray
"Construct an array node of an DAE.Exp list of type REAL."
  input list<DAE.Exp> expl;
  output DAE.Exp outExp;
algorithm
  outExp := makeScalarArray(expl,DAE.T_REAL_DEFAULT);
end makeRealArray;

public function makeRealAdd
"Construct an add node of the two expressions of type REAL."
  input DAE.Exp inExp1;
  input DAE.Exp inExp2;
  output DAE.Exp outExp;
algorithm
  outExp := DAE.BINARY(inExp1, DAE.ADD(DAE.T_REAL_DEFAULT), inExp2);
end makeRealAdd;

public function expAdd
"author: PA
  Adds two scalar expressions."
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue(e1,e2)
    local
      Type tp;
      Boolean b;
      Operator op;
      Real r1,r2;
      Integer i1,i2;
      DAE.Exp e, x, y, z;
    case(_,_)
      equation
        true = isZero(e1);
      then e2;
    case(_,_)
      equation
        true = isZero(e2);
      then e1;
    case(DAE.RCONST(r1),DAE.RCONST(r2))
      equation
        r1 = realAdd(r1,r2);
      then
        DAE.RCONST(r1);
    case(DAE.ICONST(i1),DAE.ICONST(i2))
      equation
        i1 = intAdd(i1,i2);
      then
        DAE.ICONST(i1);
    /* a + (-b) = a - b */
    case (_,DAE.UNARY(operator=DAE.UMINUS(),exp=e))
      then
        expSub(e1,e);
    case (_,DAE.UNARY(operator=DAE.UMINUS_ARR(),exp=e))
      then
        expSub(e1,e);
    // x +(-y)*z
    case (_,DAE.BINARY(DAE.UNARY(DAE.UMINUS(),x),op as DAE.MUL(),y))
      then
        expSub(e1,DAE.BINARY(x,op,y));
    case (_,DAE.BINARY(DAE.UNARY(DAE.UMINUS_ARR(),x), op as DAE.MUL_ARR(),y))
      then
        expSub(e1,DAE.BINARY(x,op,y));
    // x +(-y)/z
    case (_,DAE.BINARY(DAE.UNARY(DAE.UMINUS(),x),op as DAE.DIV(),y))
      then
        expSub(e1,DAE.BINARY(x,op,y));
    case (_,DAE.BINARY(DAE.UNARY(DAE.UMINUS_ARR(),x), op as DAE.DIV_ARR(),y))
      then
        expSub(e1,DAE.BINARY(x,op,y));
    /* -b + a = a - b */
    case (DAE.UNARY(operator=DAE.UMINUS(),exp=e),_)
      then
        expSub(e2,e);
    case (DAE.UNARY(operator=DAE.UMINUS_ARR(),exp=e),_)
      then
        expSub(e2,e);
    // (-y)*z+x
    case (DAE.BINARY(DAE.UNARY(DAE.UMINUS(),x),op as DAE.MUL(),y),_)
      then
        expSub(e2,DAE.BINARY(x,op,y));
    case (DAE.BINARY(DAE.UNARY(DAE.UMINUS_ARR(),x), op as DAE.MUL_ARR(),y),_)
      then
        expSub(e2,DAE.BINARY(x,op,y));
    // (-y)/z + x
    case (DAE.BINARY(DAE.UNARY(DAE.UMINUS(),x),op as DAE.DIV(),y),_)
      then
        expSub(e2,DAE.BINARY(x,op,y));
    case (DAE.BINARY(DAE.UNARY(DAE.UMINUS_ARR(),x), op as DAE.DIV_ARR(),y),_)
      then
        expSub(e2,DAE.BINARY(x,op,y));

    case (_,_)
      equation
        tp = typeof(e1);
        true = Types.isIntegerOrRealOrSubTypeOfEither(tp);
        b = DAEUtil.expTypeArray(tp) "  array_elt_type(tp) => tp\'" ;
        op = if b then DAE.ADD_ARR(tp) else DAE.ADD(tp);
      then
        DAE.BINARY(e1,op,e2);
    else
      equation
        tp = typeof(e1);
        true = Types.isEnumeration(tp);
      then
        DAE.BINARY(e1,DAE.ADD(tp),e2);
  end matchcontinue;
end expAdd;

public function expSub
"author: PA
  Subtracts two scalar expressions."
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue(e1,e2)
    local
      Type tp;
      Boolean b;
      Operator op;
      Real r1,r2;
      Integer i1,i2;
      DAE.Exp e, x,y;
    case(_,_)
      equation
        true = isZero(e1);
      then
        negate(e2);
    case(_,_)
      equation
        true = isZero(e2);
      then
        e1;
    case(DAE.RCONST(r1),DAE.RCONST(r2))
      equation
        r1 = realSub(r1,r2);
      then
        DAE.RCONST(r1);
    case(DAE.ICONST(i1),DAE.ICONST(i2))
      equation
        i1 = intSub(i1,i2);
      then
        DAE.ICONST(i1);
    /* a - (-b) = a + b */
    case (_,DAE.UNARY(operator=DAE.UMINUS(),exp=e))
      then
        expAdd(e1,e);
    case (_,DAE.UNARY(operator=DAE.UMINUS_ARR(),exp=e))
      then
        expAdd(e1,e);
    // x -(-y)*z
    case (_,DAE.BINARY(DAE.UNARY(DAE.UMINUS(),x),op as DAE.MUL(),y))
      then
        expAdd(e1,DAE.BINARY(x,op,y));
    case (_,DAE.BINARY(DAE.UNARY(DAE.UMINUS_ARR(),x), op as DAE.MUL_ARR(),y))
      then
        expAdd(e1,DAE.BINARY(x,op,y));
    // x -(-y)/z
    case (_,DAE.BINARY(DAE.UNARY(DAE.UMINUS(),x),op as DAE.DIV(),y))
      then
        expAdd(e1,DAE.BINARY(x,op,y));
    case (_,DAE.BINARY(DAE.UNARY(DAE.UMINUS_ARR(),x), op as DAE.DIV_ARR(),y))
      then
        expAdd(e1,DAE.BINARY(x,op,y));
    /* - a - b = -(a + b) */
    case (DAE.UNARY(operator=DAE.UMINUS(),exp=e),_)
      equation
        e = expAdd(e,e2);
      then
        negate(e);
    case (DAE.UNARY(operator=DAE.UMINUS_ARR(),exp=e),_)
      equation
        e = expAdd(e,e2);
      then
        negate(e);
    case (_,_)
      equation
        tp = typeof(e1);
        if Types.isIntegerOrRealOrSubTypeOfEither(tp)
        then
          b = DAEUtil.expTypeArray(tp);
          op = if b then DAE.SUB_ARR(tp) else DAE.SUB(tp);
          outExp = DAE.BINARY(e1,op,e2);
        else if Types.isEnumeration(tp)
             then
               outExp = DAE.BINARY(e1,DAE.SUB(tp),e2);
             else
               fail();
             end if;
        end if;
      then
        outExp;

  end matchcontinue;
end expSub;

public function makeDiff
"Takes two expressions and create
 the difference between them"
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp res;
algorithm
  res := if isZero(e2)
         then e1
         elseif isZero(e1)
             then negate(e2)
             else expSub(e1,e2);
end makeDiff;

public function makeDifference
"Takes two expressions and create
 the difference between them --> a-(b+c) = a-b-c"
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp res;
algorithm
  res := makeDiff(e1, e2);
end makeDifference;

public function makeLBinary
"Makes a binary logical expression of all elements in the list."
  input list<DAE.Exp> inExpLst;
  input DAE.Operator op;
  output DAE.Exp outExp;
algorithm
  outExp := match (inExpLst,op)
    local
      DAE.Exp e1,e2,res;
      list<DAE.Exp> rest;
      String str;
    case ({},DAE.AND(_)) then DAE.BCONST(true);
    case ({},DAE.OR(_)) then DAE.BCONST(false);
    case ({e1},_) then e1;
    case ({e1, e2},_) then DAE.LBINARY(e1,op,e2);
    case ((e1 :: rest),_)
      equation
        res = makeLBinary(rest,op);
        res = DAE.LBINARY(e1,op,res);
      then res;
    else
      equation
        str = "Expression.makeLBinary failed for operator " + ExpressionDump.lbinopSymbol(op);
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then fail();
  end match;
end makeLBinary;

public function makeSum1
"Takes a list of expressions an makes a sum
  expression sorting adding all elements in the list.

Note:
makeSum1 => (a + b) + c
makeSum => a + (b + c)
"


  input list<DAE.Exp> inExpLst;
  output DAE.Exp outExp;
protected
  DAE.Exp e1,e2;
algorithm
  outExp := matchcontinue(inExpLst)
            case({}) then DAE.RCONST(0.0);
            case({e1}) then e1;
            case({e1,e2}) then expAdd(e1,e2);
            case(_)then makeSumWork(inExpLst);
            else
              equation
               if Flags.isSet(Flags.FAILTRACE) then
                 Debug.trace("-Expression.makeSum1 failed, DAE.Exp lst:");
                 Debug.trace(ExpressionDump.printExpListStr(inExpLst));
               end if;
              then fail();
            end matchcontinue;

end makeSum1;

protected function makeSumWork
"Takes a list of expressions an makes a sum
  expression adding all elements in the list."
  input list<DAE.Exp> inExpLst;
  output DAE.Exp outExp;

protected
  Type tp;
  list<DAE.Exp> rest;
  DAE.Exp eLst;
  Operator op;

algorithm
  eLst :: rest := inExpLst;
  tp := typeof(eLst);
  op := if DAEUtil.expTypeArray(tp) then DAE.ADD_ARR(tp) else DAE.ADD(tp);

  outExp := eLst;
  for elem in rest loop
    outExp := if isZero(elem) then outExp elseif isZero(outExp) then elem else DAE.BINARY(outExp, op, elem);
  end for;

end makeSumWork;

public function makeSum
"Takes a list of expressions an makes a sum
  expression adding all elements in the list."
  input list<DAE.Exp> inExpLst;
  output DAE.Exp outExp;
algorithm
  outExp:=
  matchcontinue (inExpLst)
    local
      DAE.Exp e1,e2,res;
      Boolean b1;
      Type tp;
      list<DAE.Exp> rest,lst;
      list<String> explst;
      String str;
      Operator op;
      Boolean b;
    case ({}) then DAE.RCONST(0.0);
    case ({e1}) then e1;
    case ({e1, e2})
      equation
        true = isZero(e1);
      then e2;
    case ({e1, e2})
      equation
        true = isZero(e2);
      then e1;
    case ({e1, e2})
      equation
        tp = typeof(e1) "Take type info from e1, ok since type checking already performed." ;
        b = DAEUtil.expTypeArray(tp);
        op = if b then DAE.ADD_ARR(tp) else DAE.ADD(tp);
      then DAE.BINARY(e1, op, e2);
        //res = DAE.BINARY(e1, DAE.ADD(tp), e2);
      //then res;
    /*case ({e1,e2})
      equation
        b1 = isZero(e1);
        tp = typeof(e1) "Take type info from e1, ok since type checking already performed." ;
        res = DAE.BINARY(e1,DAE.ADD(tp),e2);
        res = if_(b1,e2,res);
      then
        res;*/
    case ((e1 :: rest))
      equation
        b1 = isZero(e1);
        e2 = makeSum(rest);
        tp = typeof(e2);
        b = DAEUtil.expTypeArray(tp);
        op = if b then DAE.ADD_ARR(tp) else DAE.ADD(tp);
        res = DAE.BINARY(e1,op,e2);
        res = if b1 then e2 else res;
      then
        res;
    case (lst)
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        Debug.trace("-Expression.makeSum failed, DAE.Exp lst:");
        explst = List.map(lst, ExpressionDump.printExpStr);
        str = stringDelimitList(explst, ", ");
        Debug.traceln(str);
      then
        fail();
  end matchcontinue;
end makeSum;

public function expMul
"author: PA
  Multiplies two scalar expressions."
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue(e1,e2)
    local
      Type tp;
      Boolean b1,b2;
      Operator op;
      Real r1,r2;
      Integer i1,i2;
      DAE.Exp e1_1,e2_1;
    case(_,_)
      equation
        true = isZero(e1);
      then e1;
    case(_,_)
      equation
        true = isZero(e2);
      then e2;
    case(DAE.RCONST(real = 1.0),_)
      then e2;
    case(_,DAE.RCONST(real = 1.0))
      then e1;
    case(DAE.ICONST(1),_)
      then e2;
    case(_,DAE.ICONST(1))
      then e1;
    case(DAE.RCONST(r1),DAE.RCONST(r2))
      equation
        r1 = realMul(r1,r2);
      then
        DAE.RCONST(r1);
    case(DAE.ICONST(i1),DAE.ICONST(i2))
      equation
        i1 = intMul(i1,i2);
      then
        DAE.ICONST(i1);
    else
      equation
        tp = typeof(e1);
        true = Types.isIntegerOrRealOrSubTypeOfEither(tp);
        b1 = DAEUtil.expTypeArray(tp);
        tp = typeof(e2);
        true = Types.isIntegerOrRealOrSubTypeOfEither(tp);
        b2 = DAEUtil.expTypeArray(tp);
        /* swap e1 and e2 if we have scalar mul array */
        (e1_1,e2_1) = Util.swap((not b1) and b2, e1, e2);
        /* Create all kinds of multiplication with scalars or arrays */
        op = if b1 and b2 then DAE.MUL_ARR(tp) else (if b1==b2 then DAE.MUL(tp) else DAE.MUL_ARRAY_SCALAR(tp));
      then
        DAE.BINARY(e1_1,op,e2_1);
  end matchcontinue;
end expMul;

public function expPow "author: vitalij"
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp outExp;

algorithm
  outExp := match(e1,e2)
    local
      Type tp;
      DAE.Exp e,e3,e4,e5;
      Real r1,r2;
      Boolean b;
      Operator op;

    // e1^1 = e1
    case(_,_) guard(isOne(e2))
    then e1;

    // e1^0 = 1
    case(_,_) guard(isZero(e2))
    then makeConstOne(typeof(e1));

    // 1^e2 = 1
    case (_,_) guard(isConstOne(e1))
    then e1;

    // 0^e2 = 0
    case (_,_) guard(isZero(e1) and expIsPositive(e2))
    then makeConstZero(typeof(e1));

    // (-e)^r = e^r if r is even
    case (DAE.UNARY(DAE.UMINUS(),e), _) guard(isEven(e2))
    then expPow(e, e2);

    // (x/y)^(-z) = (y/x)^z
    case (DAE.BINARY(e3, DAE.DIV(), e4), DAE.UNARY(DAE.UMINUS(),e5))
    equation
      e = makeDiv(e4,e3);
      e = expPow(e,e5);
    then e;

    // (e1/e2)^(-r) = (e2/e1)^r
    case (DAE.BINARY(e3, DAE.DIV(), e4) , _) guard(isNegativeOrZero(e2))
    then expPow(makeDiv(e4,e3), negate(e2));

    // x^0.5 => sqrt(x)
    case (_, _) guard(isHalf(e2))
    then Expression.makePureBuiltinCall("sqrt",{e1},DAE.T_REAL_DEFAULT);

    else equation
      tp = typeof(e1);
      b = DAEUtil.expTypeArray(tp);
      op = if b then DAE.POW_ARR(tp) else DAE.POW(tp);
    then DAE.BINARY(e1,op,e2);

  end match;
end expPow;

public function expPowLst
"
{a,b}^n -> {a^n, b^n}
author: vitalij"
  input list<DAE.Exp> expLst;
  input DAE.Exp n;
  output list<DAE.Exp> outExp := List.map1(expLst, expPow, n);
end expPowLst;

public function expMaxScalar "author: Frenkel TUD 2011-04
  returns max(e1,e2)."
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp outExp;
protected
  Type tp;
algorithm
  tp := typeof(e1);
  outExp := DAE.CALL(Absyn.IDENT("max"),{e1,e2},DAE.CALL_ATTR(tp,false,true,false,false,DAE.NO_INLINE(),DAE.NO_TAIL()));
end expMaxScalar;

public function expMinScalar "author: Frenkel TUD 2011-04
  returns min(e1,e2)."
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp outExp;
protected
  Type tp;
  Boolean b;
algorithm
  tp := typeof(e1);
  outExp := DAE.CALL(Absyn.IDENT("min"),{e1,e2},DAE.CALL_ATTR(tp, false, true, false, false, DAE.NO_INLINE(), DAE.NO_TAIL()));
end expMinScalar;

public function makeProductVector "takes and expression e1 and a list of expressisions {v1,v2,...,vn} and returns
{e1*v1,e1*v2,...,e1*vn}"
  input DAE.Exp e1;
  input list<DAE.Exp> v;
  output list<DAE.Exp> res;
algorithm
  res := List.map1(v,makeProduct,e1);
end makeProductVector;

public function makeScalarProduct
"calculate a scalr product <v,w>"
  input array<DAE.Exp> v;
  input array<DAE.Exp> w;
  output DAE.Exp s := DAE.RCONST(0.0);
protected
  Integer size1:=arrayLength(v), size2:= arrayLength(w);
algorithm
  if size1 <> size2 then
    print("makeScalarProduct faili.\n");
    return ;
  end if;

  s := makeSum1(list( expMul(arrayGet(v,i), arrayGet(w,i))  for i in 1:size1 ));
  (s,_) := ExpressionSimplify.simplify(s);

end makeScalarProduct;

public function lenVec
  input array<DAE.Exp> v;
  output DAE.Exp len := makeScalarProduct(v,v);
  algorithm
  len := Expression.makePureBuiltinCall("sqrt",{len},DAE.T_REAL_DEFAULT);
end lenVec;

public function addVec
  input array<DAE.Exp> v;
  input array<DAE.Exp> w;
  output array<DAE.Exp> y;

protected
  Integer size1:=arrayLength(v), size2:= arrayLength(w);
algorithm
  if size1 <> size2 then
    print("addVec fail.\n");
    return ;
  end if;
  y := arrayCreate(size1, DAE.RCONST(0.0));
  for i in 1:size1 loop
    arrayUpdate(y,i,expAdd(arrayGet(v,i), arrayGet(w,i)));
  end for;
end addVec;

public function subVec
  input array<DAE.Exp> v;
  input array<DAE.Exp> w;
  output array<DAE.Exp> y;

protected
  Integer size1:=arrayLength(v), size2:= arrayLength(w);
algorithm
  if size1 <> size2 then
    print("addVec fail.\n");
    return ;
  end if;
  y := arrayCreate(size1, DAE.RCONST(0.0));
  for i in 1:size1 loop
    arrayUpdate(y,i,expSub(arrayGet(v,i), arrayGet(w,i)));
  end for;
end subVec;


public function makeProduct
"Makes a product of two expressions"
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp product;
algorithm
  product := makeProductLst({e1,e2});
end makeProduct;

public function makeProductLst
"Takes a list of expressions an makes a product
  expression multiplying all elements in the list."
  input list<DAE.Exp> inExpLst;
  output DAE.Exp outExp;
algorithm
  outExp:=
  matchcontinue (inExpLst)
    local
      DAE.Exp e1,res,e,e2,p1;
      list<DAE.Exp> es,rest,lst;
      Type tp;
      list<String> explst;
      String str;
      Boolean b_isZero,b1,b2;
    case ({}) then DAE.RCONST(1.0);
    case ({e1}) then e1;
    case ((e :: es)) /* to prevent infinite recursion, disregard constant 1. */
      equation
        true = isConstOne(e);
        res = makeProductLst(es);
      then
        res;
    // e1/e*e2 for e = 0 => fail
    case (DAE.BINARY(operator = DAE.DIV(),exp2 = e)::_)
      equation
        true = isZero(e);
      then
        fail();

    // e2*e1/e for e = 0 => fail
    case ({_,DAE.BINARY(operator = DAE.DIV(),exp2 = e)})
      equation
        true = isZero(e);
      then
        fail();
     case ((e :: _)) /* to prevent infinite recursion, disregard constant 0. */
      equation
        true = isZero(e);
      then e;
    case ({DAE.BINARY(exp1 = e1,operator = DAE.DIV(ty = tp),exp2 = e),e2})
      equation
        true = isConstOne(e1);
      then
        DAE.BINARY(e2,DAE.DIV(tp),e);
    case ({e2,DAE.BINARY(exp1 = e1,operator = DAE.DIV(ty = tp),exp2 = e)})
      equation
        true = isConstOne(e1);
      then
        DAE.BINARY(e2,DAE.DIV(tp),e);
    case ((DAE.BINARY(exp1 = e1,operator = DAE.DIV(ty = tp),exp2 = e) :: es))
      equation
        true = isConstOne(e1);
        p1 = makeProductLst(es);
        res = DAE.BINARY(p1,DAE.DIV(tp),e);
        b_isZero = isZero(p1);
        res = if b_isZero then makeConstZero(typeof(e)) else res;
      then
        res;
    case ({e1,e2})
      equation
        true = isConstOne(e2);
      then
        e1;
    case ({e1,e2})
      equation
        b1 = isZero(e1);
        b2 = isZero(e2);
        b_isZero = boolOr(b1,b2);
        tp = typeof(e1) "Take type info from e1, ok since type checking already performed." ;
        tp = checkIfOther(tp);
        res = DAE.BINARY(e1,DAE.MUL(tp),e2);
        res = if b_isZero then makeConstZero(tp) else res;
      then
        res;
    case ((e1 :: rest))
      equation
        e2 = makeProductLst(rest);
        tp = typeof(e1);
        tp = checkIfOther(tp);
        res = DAE.BINARY(e1,DAE.MUL(tp),e2);
        b1 = isZero(e1);
        b2 = isZero(e2);
        b_isZero = boolOr(b1,b2);
        res = if b_isZero then makeConstZero(typeof(e1)) else res;
      then
        res;
    case (lst)
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        Debug.trace("-Expression.makeProductLst failed, DAE.Exp lst:");
        explst = List.map(lst, ExpressionDump.printExpStr);
        str = stringDelimitList(explst, ", ");
        Debug.traceln(str);
      then
        fail();
  end matchcontinue;
end makeProductLst;

protected function checkIfOther
"Checks if a type is OTHER and in that case returns REAL instead.
 This is used to make proper transformations in case OTHER is
 retrieved from subexpression where it should instead be REAL or INT"
input DAE.Type inTp;
output DAE.Type outTp;
algorithm
  outTp := matchcontinue(inTp)
    case (DAE.T_UNKNOWN(_)) then DAE.T_REAL_DEFAULT;
    case _ then inTp;
  end matchcontinue;
end checkIfOther;

public function expDiv "
function expDiv
  author: PA
  Divides two scalar expressions."
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp outExp;
protected
  Type tp;
  Boolean b;
  Operator op;
algorithm
  tp := typeof(e1);
  true := Types.isIntegerOrRealOrSubTypeOfEither(tp);
  b := DAEUtil.expTypeArray(tp);
  op := if b then DAE.DIV_ARR(tp) else DAE.DIV(tp);
  outExp := DAE.BINARY(e1,op,e2);
end expDiv;

public function makeDiv "Takes two expressions and create a division"
  input DAE.Exp e1;
  input DAE.Exp e2;
  output DAE.Exp res;
algorithm
  res := match(e1,e2)
    case(_,_) guard(isZero(e1) and not isZero(e2))
    then e1;
    case(_,_) guard(isOne(e2))
    then e1;
    else expDiv(e1,e2);
  end match;
end makeDiv;

public function makeDivVector "takes and expression e1 and a list of expressisions {v1,v2,...,vn} and returns
{v1/e1,v2/e1,...,vn/e1}"
  input list<DAE.Exp> v;
  input DAE.Exp e1;
  output list<DAE.Exp> res;
algorithm
  res := List.map1(v,makeDiv,e1);
end makeDivVector;

public function makeAsubAddIndex "creates an ASUB given an expression and an index"
  input DAE.Exp e;
  input Integer indx;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue(e,indx)
    local
      list<DAE.Exp> subs;
      DAE.Exp exp;
    case (DAE.ASUB(exp,subs),_)
      equation
        subs = listAppend(subs,{DAE.ICONST(indx)});
      then makeASUB(exp,subs);
    else makeASUB(e,{DAE.ICONST(indx)});
  end matchcontinue;
end makeAsubAddIndex;

public function makeIntegerExp
"Creates an integer constant expression given the integer input."
  input Integer i;
  output DAE.Exp e;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  e := DAE.ICONST(i);
end makeIntegerExp;

public function makeRealExp
"Creates an integer constant expression given the integer input."
  input Real r;
  output DAE.Exp e;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  e := DAE.RCONST(r);
end makeRealExp;

public function makeBoolExp
"Creates an integer constant expression given the integer input."
  input Boolean b;
  output DAE.Exp e;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  e := DAE.BCONST(b);
end makeBoolExp;

public function makeConstOne
"author: PA
  Create the constant value one, given a type that is INT or REAL"
  input DAE.Type inType;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue (inType)
    case (DAE.T_INTEGER()) then DAE.ICONST(1);
    case (DAE.T_REAL()) then DAE.RCONST(1.0);
    else DAE.RCONST(1.0);
  end matchcontinue;
end makeConstOne;

public function makeConstZero
"Generates a zero constant"
  input DAE.Type inType;
  output DAE.Exp const;
algorithm
  const := matchcontinue(inType)
    case (DAE.T_REAL()) then DAE.RCONST(0.0);
    case (DAE.T_INTEGER()) then DAE.ICONST(0);
    else DAE.RCONST(0.0);
  end matchcontinue;
end makeConstZero;

public function makeListOfZeros
  input Integer inDimension;
  output list<DAE.Exp> outList;
algorithm
  outList := matchcontinue(inDimension)
    local Integer dimension;
      DAE.Exp head;
      list<DAE.Exp> tail;
      case(0)
        then {};
      case(dimension) equation
        head = DAE.RCONST(0.0);
        tail = makeListOfZeros(dimension-1);
        then head :: tail;
  end matchcontinue;
end makeListOfZeros;

public function makeRealArrayOfZeros
  input Integer inDimension;
  output DAE.Exp outExp;
protected
  list<DAE.Exp> l;
algorithm
  l := makeListOfZeros(inDimension);
  outExp := makeRealArray(l);
end makeRealArrayOfZeros;

public function makeZeroExpression
" creates a Real or array<Real> zero expression with given dimensions, also returns its type"
  input DAE.Dimensions inDims;
  output DAE.Exp outExp;
  output DAE.Type outType;
algorithm
  (outExp,outType) := match(inDims)
    local
      Integer i;
      DAE.Dimension d;
      DAE.Dimensions dims;
      DAE.Exp e;
      list<DAE.Exp> eLst;
      DAE.Type ty;
      Boolean scalar;

    case {} then (DAE.RCONST(0.0), DAE.T_REAL_DEFAULT);

    case d::dims
      equation
        i = dimensionSize(d);
        (e, ty) = makeZeroExpression(dims);
        eLst = List.fill(e,i);
        scalar = List.isEmpty(dims);
      then
        (DAE.ARRAY(DAE.T_ARRAY(DAE.T_REAL_DEFAULT,d::dims,DAE.emptyTypeSource),scalar,eLst),
         DAE.T_ARRAY(ty,{d},DAE.emptyTypeSource));
  end match;
end makeZeroExpression;

public function makeOneExpression
" creates a Real or array<Real> one expression with given dimensions, also returns its type"
  input DAE.Dimensions inDims;
  output DAE.Exp outExp;
  output DAE.Type outType;
algorithm
  (outExp,outType) := match(inDims)
    local
      Integer i;
      DAE.Dimension d;
      DAE.Dimensions dims;
      DAE.Exp e;
      list<DAE.Exp> eLst;
      DAE.Type ty;
      Boolean scalar;

    case {} then (DAE.RCONST(1.0), DAE.T_REAL_DEFAULT);

    case d::dims
      equation
        i = dimensionSize(d);
        (e, ty) = makeOneExpression(dims);
        eLst = List.fill(e,i);
        scalar = List.isEmpty(dims);
      then
        (DAE.ARRAY(DAE.T_ARRAY(DAE.T_REAL_DEFAULT,d::dims,DAE.emptyTypeSource),scalar,eLst),
         DAE.T_ARRAY(ty,{d},DAE.emptyTypeSource));
  end match;
end makeOneExpression;

public function listToArray
" @mahge:
  creates an array from a list of expressions and
  dimensions. e.g.
   listToArray({1,2,3,4,5,6}, {3,2}) -> {{1,2}, {3,4}, {5,6}}
"
  input list<DAE.Exp> inList;
  input DAE.Dimensions dims;
  output DAE.Exp oExp;
algorithm
  oExp := matchcontinue(inList, dims)
    local
      DAE.Type ty;
      DAE.Exp exp;

    case(_, {})
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"Expression.listToArray called with empty dimension list."});
      then fail();

    case({}, _)
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"Expression.listToArray called with empty list."});
      then fail();

    // Here we assume that all the elements of the list
    // have the same type.
    case(exp::_, _)
      equation
        ty = typeof(exp);
        oExp = listToArray2(inList,dims,ty);
      then
        oExp;
  end matchcontinue;

end listToArray;


protected function listToArray2
  input list<DAE.Exp> inList;
  input DAE.Dimensions iDims;
  input DAE.Type inType;
  output DAE.Exp oExp;
algorithm
  oExp := matchcontinue(inList, iDims, inType)
  local
    Integer i;
    DAE.Dimension d;
    list<DAE.Exp> explst;
    DAE.Exp arrexp;
    DAE.Dimensions dims;

  case(_, {d}, _)
    equation
      i = dimensionSize(d);
      true = i == listLength(inList);
    then
      DAE.ARRAY(DAE.T_ARRAY(inType,{DAE.DIM_INTEGER(i)},DAE.emptyTypeSource),false,inList);

  case(_, {d}, _)
    equation
      i = dimensionSize(d);
      true = i > listLength(inList);
      Error.addMessage(Error.INTERNAL_ERROR, {"Expression.listToArray2: Not enough elements left in list to fit dimension."});
    then
      fail();

  case(_, _ :: _ , _)
    equation
      i = listLength(iDims) - 1;
      d = List.last(iDims);
      (dims, _) = List.split(iDims,i);

      explst = listToArray3(inList,d,inType);
      arrexp = listToArray2(explst,dims,inType);
    then
      arrexp;

  end matchcontinue;
end listToArray2;


protected function listToArray3
  input list<DAE.Exp> inList;
  input DAE.Dimension iDim;
  input DAE.Type inType;
  output list<DAE.Exp> oExps;
algorithm
  oExps := match(inList, iDim, inType)
  local
    Integer i;
    DAE.Dimension d;
    list<DAE.Exp> explst, restexps, restarr;
    DAE.Exp arrexp;

    case({}, _, _) then {};

    case(_, d, _)
      equation
        i = dimensionSize(d);
        if (i > listLength(inList))
        then
          Error.addMessage(Error.INTERNAL_ERROR, {"Expression.listToArray3: Not enough elements left in list to fit dimension."});
          fail();
        else
          (explst, restexps) = List.split(inList,i);
          arrexp = DAE.ARRAY(DAE.T_ARRAY(inType,{DAE.DIM_INTEGER(i)},DAE.emptyTypeSource),false,explst);
          restarr = listToArray3(restexps,d,inType);
        end if;
      then
        arrexp::restarr;

  end match;
end listToArray3;


public function arrayFill
  input DAE.Dimensions dims;
  input DAE.Exp inExp;
  output DAE.Exp oExp;
algorithm
  oExp := matchcontinue(dims,inExp)

    case({},_) then inExp;

    else
      equation
        oExp = arrayFill2(dims,inExp);
      then
        oExp;

  end matchcontinue;
end arrayFill;

protected function arrayFill2
  input DAE.Dimensions iDims;
  input DAE.Exp inExp;
  output DAE.Exp oExp;
algorithm
  oExp := match(iDims,inExp)
    local
      Integer i;
      DAE.Dimension d;
      Type ty;
      list<DAE.Exp> expl;
      DAE.Exp arrexp;
      DAE.Dimensions dims;

    case({d},_)
      equation
        ty = typeof(inExp);
        i = dimensionSize(d);
        expl = List.fill(inExp, i);
      then
        DAE.ARRAY(DAE.T_ARRAY(ty,{DAE.DIM_INTEGER(i)},DAE.emptyTypeSource),true,expl);

    case(d::dims,_)
      equation
        arrexp = arrayFill2({d},inExp);
        arrexp = arrayFill2(dims,arrexp);
      then
        arrexp;

  end match;
end arrayFill2;

public function makeIndexSubscript
"Creates a Subscript INDEX from an Expression."
  input DAE.Exp exp;
  output DAE.Subscript subscript;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  subscript := DAE.INDEX(exp);
end makeIndexSubscript;

public function makeVar "Creates a Var given a name and Type"
  input String name;
  input DAE.Type tp;
  output DAE.Var v;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  v := DAE.TYPES_VAR(name, DAE.dummyAttrVar, tp, DAE.UNBOUND(), NONE());
end makeVar;

public function dimensionsMult
  "Multiplies two dimensions."
  input DAE.Dimension dim1;
  input DAE.Dimension dim2;
  output DAE.Dimension res;
algorithm
  res := intDimension(dimensionSize(dim1) * dimensionSize(dim2));
end dimensionsMult;

public function dimensionsAdd
  "Adds two dimensions."
  input DAE.Dimension dim1;
  input DAE.Dimension dim2;
  output DAE.Dimension res;
algorithm
  try
    res := intDimension(dimensionSize(dim1) + dimensionSize(dim2));
  else
    res := DAE.DIM_UNKNOWN();
  end try;
end dimensionsAdd;

public function concatArrayType
  "Concatenates two array types, so that the resulting type is correct."
  input DAE.Type arrayType1;
  input DAE.Type arrayType2;
  output DAE.Type concatType;
algorithm
  concatType := match(arrayType1, arrayType2)
    local
      DAE.Type et;
      DAE.Dimension dim1, dim2;
      DAE.Dimensions dims1, dims2;
      DAE.TypeSource ts;

    case (DAE.T_ARRAY(ty = et, dims = dim1 :: dims1, source = ts), DAE.T_ARRAY(dims = dim2 :: _))
      equation
        dim1 = dimensionsAdd(dim1, dim2);
      then
        DAE.T_ARRAY(et, dim1 :: dims1, ts);
  end match;
end concatArrayType;

public function replaceExpTpl
  "Help function to e.g. detectImplicitDiscreteAlgsStatemensFor"
  input DAE.Exp inExp;
  input tuple<DAE.Exp, DAE.Exp> tpl;
  output DAE.Exp outExp;
  output tuple<DAE.Exp, DAE.Exp> outTpl;
algorithm
  (outExp,outTpl) := match(inExp,tpl)
    local
      DAE.Exp e, e1, s, t;

    case (e, (s, t))
      equation
      ((e1, _)) = replaceExp(e, s, t);
      then (e1, (s, t));

  end match;
end replaceExpTpl;

public function replaceExp
"Helper function to replaceExpList."
  input DAE.Exp inExp;
  input DAE.Exp inSourceExp;
  input DAE.Exp inTargetExp;
  output tuple<DAE.Exp,Integer> out;
protected
  DAE.Exp exp;
  Integer i;
algorithm
  (exp,(_,_,i)) := traverseExpTopDown(inExp,replaceExpWork,(inSourceExp,inTargetExp,0));
  out := (exp,i);
end replaceExp;

protected function replaceExpWork
  input DAE.Exp inExp;
  input tuple<DAE.Exp,DAE.Exp,Integer> inTpl;
  output DAE.Exp outExp;
  output Boolean cont;
  output tuple<DAE.Exp,DAE.Exp,Integer> otpl;
algorithm
  (outExp,cont,otpl) := matchcontinue (inExp,inTpl) /* TODO: match */
    local
      tuple<DAE.Exp,DAE.Exp,Integer> tpl;
      DAE.Exp expr,source,target;
      Integer c;
      DAE.ComponentRef cr;
      DAE.Type ty;
    case (_,(source,target,c))
      equation
        true = expEqual(inExp, source);
      then (target,false,(source,target,c+1));

    case (DAE.CREF(cr,ty),tpl)
      equation
        (cr,tpl) = traverseExpTopDownCrefHelper(cr,replaceExpWork,tpl);
      then (DAE.CREF(cr,ty),false,tpl);

    else (inExp,true,inTpl);
  end matchcontinue;
end replaceExpWork;

public function expressionCollector
   input DAE.Exp exp;
   input list<DAE.Exp> acc;
   output DAE.Exp outExp;
   output list<DAE.Exp> outExps;
algorithm
  outExp := exp;
  outExps := exp::acc;
end expressionCollector;

public function replaceCref
"Replace a componentref with a expression"
  input DAE.Exp inExp;
  input tuple<DAE.ComponentRef,DAE.Exp> inTpl;
  output DAE.Exp outExp;
  output tuple<DAE.ComponentRef,DAE.Exp> otpl;
algorithm
  (outExp,otpl) := matchcontinue (inExp,inTpl)
    local
      DAE.Exp target;
      DAE.ComponentRef cr,cr1;
    case (DAE.CREF(componentRef=cr),(cr1,target))
      equation
        true = ComponentReference.crefEqualNoStringCompare(cr, cr1);
      then
        (target,(cr1,target));
    else (inExp,inTpl);
  end matchcontinue;
end replaceCref;

public function containsInitialCall "public function containsInitialCall
  author: lochel
  Spec33 p. 90:
  [...] The equations of a when-clause are active during initialization, if
  and only if they are explicitly enabled with the initial() operator; and
  only in one of the two forms when initial() then or when {…,initial(),…}
  then. [...]"
  input DAE.Exp condition;    // expression of a when-clause
  input Boolean inB;          // use false for primary calls - it us for internal use only
  output Boolean res;
algorithm
  res := matchcontinue(condition, inB)
    local
      Boolean b;
      list<Exp> array;

    case (_, true) equation
    then true;

    case (DAE.CALL(path = Absyn.IDENT(name = "initial")), _) equation
    then true;

    case (DAE.ARRAY(array=array), _) equation
      b = List.fold(array, containsInitialCall, inB);
    then b;

    else
    then false;
  end matchcontinue;
end containsInitialCall;

/***************************************************/
/* traverse DAE.Exp */
/***************************************************/

public function traverseExp
"Traverses all subexpressions of an expression.
  Takes a function and an extra argument passed through the traversal.
  The function can potentially change the expression. In such cases,
  the changes are made bottom-up, i.e. a subexpression is traversed
  and changed before the complete expression is traversed.

  NOTE: The user-provided function is not allowed to fail! If you want to
  detect a failure, return NONE() in your user-provided datatype.
"
  replaceable type Type_a subtypeof Any;
  input DAE.Exp inExp;
  input FuncExpType func;
  input Type_a inTypeA;
  output DAE.Exp outExp;
  output Type_a outA;
  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Type_a outA;
  end FuncExpType;
algorithm
  (outExp,outA) := match (inExp,func,inTypeA)
    local
      DAE.Exp e1_1,e,e1,e2_1,e2,e3_1,e3;
      Type_a ext_arg;
      Operator op;
      FuncExpType rel;
      list<DAE.Exp> expl_1,expl;
      Absyn.Path fn;
      Boolean scalar;
      Type tp,t;
      Integer i;
      list<list<DAE.Exp>> lstexpl_1,lstexpl;
      Integer dim;
      String str;
      list<DAE.Element> localDecls;
      tuple<DAE.Exp,Type_a> res;
      list<String> fieldNames;
      DAE.CallAttributes attr;
      list<DAE.MatchCase> cases,cases_1;
      DAE.MatchType matchTy;
      Integer index_;
      Option<tuple<DAE.Exp,Integer,Integer>> isExpisASUB;
      DAE.ReductionInfo reductionInfo;
      DAE.ReductionIterators riters,riters_1;
      DAE.ComponentRef cr,cr_1;
      list<list<String>> aliases;

    case (DAE.EMPTY(),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.ICONST(_),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.RCONST(_),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.SCONST(_),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.BCONST(_),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.CLKCONST(_),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.ENUM_LITERAL(),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.CREF(cr,tp),rel,ext_arg)
      equation
        (cr_1,ext_arg) = traverseExpCref(cr, rel, ext_arg);
        e = if referenceEq(cr,cr_1) then inExp else DAE.CREF(cr_1,tp);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // unary
    case (DAE.UNARY(operator = op,exp = e1),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.UNARY(op,e1_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // binary
    case (DAE.BINARY(exp1 = e1,operator = op,exp2 = e2),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExp(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.BINARY(e1_1,op,e2_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // logical unary
    case (DAE.LUNARY(operator = op,exp = e1),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.LUNARY(op,e1_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // logical binary
    case (DAE.LBINARY(exp1 = e1,operator = op,exp2 = e2),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExp(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.LBINARY(e1_1,op,e2_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // relation
    case (DAE.RELATION(exp1 = e1,operator = op,exp2 = e2, index=index_, optionExpisASUB= isExpisASUB),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExp(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.RELATION(e1_1,op,e2_1,index_,isExpisASUB);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // if expressions
    case (DAE.IFEXP(expCond = e1,expThen = e2,expElse = e3),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExp(e2, rel, ext_arg);
        (e3_1,ext_arg) = traverseExp(e3, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) and referenceEq(e3,e3_1) then inExp else DAE.IFEXP(e1_1,e2_1,e3_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.CALL(path = fn,expLst = expl,attr = attr),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.CALL(fn,expl_1,attr);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.RECORD(path = fn,exps = expl,comp = fieldNames, ty = tp),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.RECORD(fn,expl_1,fieldNames,tp);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.PARTEVALFUNCTION(fn, expl, tp, t),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.PARTEVALFUNCTION(fn,expl_1,tp,t);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.ARRAY(ty = tp,scalar = scalar,array = expl),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.ARRAY(tp,scalar,expl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.MATRIX(ty = tp,integer = dim, matrix=lstexpl),rel,ext_arg)
      equation
        (lstexpl_1,ext_arg) = traverseExpMatrix(lstexpl, rel, ext_arg);
        e = if referenceEq(lstexpl,lstexpl_1) then inExp else DAE.MATRIX(tp,dim,lstexpl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.RANGE(ty = tp,start = e1,step = NONE(),stop = e2),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExp(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.RANGE(tp,e1_1,NONE(),e2_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.RANGE(ty = tp,start = e1,step = SOME(e2),stop = e3),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExp(e2, rel, ext_arg);
        (e3_1,ext_arg) = traverseExp(e3, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) and referenceEq(e3,e3_1) then inExp else DAE.RANGE(tp,e1_1,SOME(e2_1),e3_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.TUPLE(PR = expl),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.TUPLE(expl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.CAST(ty = tp,exp = e1),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.CAST(tp,e1_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.ASUB(exp = e1,sub = expl),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        (expl_1,ext_arg) = traverseExpList(expl, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(expl,expl_1) then inExp else makeASUB(e1_1,expl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.TSUB(e1,i,tp),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.TSUB(e1_1,i,tp);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.SIZE(exp = e1,sz = NONE()),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.SIZE(e1_1,NONE());
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.SIZE(exp = e1,sz = SOME(e2)),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExp(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.SIZE(e1_1,SOME(e2_1));
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.REDUCTION(reductionInfo=reductionInfo,expr = e1,iterators = riters),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        (riters_1,ext_arg) = traverseReductionIterators(riters, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(riters,riters_1) then inExp else DAE.REDUCTION(reductionInfo,e1_1,riters_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // MetaModelica list
    case (DAE.CONS(e1,e2),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExp(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.CONS(e1_1,e2_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.LIST(expl),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.LIST(expl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.META_TUPLE(expl),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.META_TUPLE(expl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.META_OPTION(NONE()),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.META_OPTION(SOME(e1)),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.META_OPTION(SOME(e1_1));
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.BOX(e1),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.BOX(e1_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.UNBOX(e1,tp),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExp(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.UNBOX(e1_1,tp);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.METARECORDCALL(fn,expl,fieldNames,i),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.METARECORDCALL(fn,expl_1,fieldNames,i);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);
    // ---------------------

    case (DAE.MATCHEXPRESSION(matchTy,expl,aliases,localDecls,cases,tp),rel,ext_arg)
      equation
        // Don't traverse the local declarations; we don't store bindings there (yet)
        (expl_1,ext_arg) = traverseExpList(expl, rel, ext_arg);
        (cases_1,ext_arg) = Patternm.traverseCases(cases,rel,ext_arg);
        e = if referenceEq(expl,expl_1) and referenceEq(cases,cases_1) then inExp else DAE.MATCHEXPRESSION(matchTy,expl_1,aliases,localDecls,cases_1,tp);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.SHARED_LITERAL(),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.PATTERN(),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    // Why don't we call rel() for these expressions?
    case (DAE.CODE(),_,ext_arg) then (inExp,ext_arg);

    else
      equation
        str = ExpressionDump.printExpStr(inExp);
        str = "Expression.traverseExp or one of the user-defined functions using it is not implemented correctly: " + str;
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then fail();
  end match;
end traverseExp;

public function traverseExpDummy "Like traverseExp but passes a default 0 argument"
  replaceable type Type_a subtypeof Any;
  input DAE.Exp inExp;
  input FuncExpType func;
  output DAE.Exp outExp;
  partial function FuncExpType
    input DAE.Exp inExp;
    output DAE.Exp outExp;
  end FuncExpType;
algorithm
  (outExp,_) := traverseExp(inExp,traverseExpDummyHelper,func);
end traverseExpDummy;

public function traverseExpDummyHelper "Like traverseExp but does not use an extra argument"
  replaceable type Type_a subtypeof Any;
  input DAE.Exp inExp;
  input FuncExpType func;
  output DAE.Exp outExp;
  output FuncExpType outFunc;
  partial function FuncExpType
    input DAE.Exp inExp;
    output DAE.Exp outExp;
  end FuncExpType;
algorithm
  outExp := func(inExp);
  outFunc := func;
end traverseExpDummyHelper;

public function traverseSubexpressionsHelper
"This function is used as input to a traverse function that does not traverse all subexpressions.
The extra argument is a tuple of the actul function to call on each subexpression and the extra argument.
"
  replaceable type Type_a subtypeof Any;
  input DAE.Exp inExp;
  input tuple<FuncExpType,Type_a> itpl;
  output DAE.Exp outExp;
  output tuple<FuncExpType,Type_a> otpl;
  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Type_a outA;
  end FuncExpType;
protected
  FuncExpType rel;
  Type_a ext_arg;
algorithm
  (rel,ext_arg) := itpl;
  (outExp,ext_arg) := traverseExp(inExp,rel,ext_arg);
  otpl := (rel,ext_arg);
end traverseSubexpressionsHelper;

public function traverseSubexpressionsDummyHelper
"This function is used as input to a traverse function that does not traverse all subexpressions.
The extra argument is a tuple of the actul function to call on each subexpression and the extra argument.
"
  replaceable type Type_a subtypeof Any;
  input DAE.Exp inExp;
  input FuncExpType inFunc;
  output DAE.Exp outExp;
  output FuncExpType outFunc;
  partial function FuncExpType
    input DAE.Exp inExp;
    output DAE.Exp outExp;
  end FuncExpType;
algorithm
  (outExp,outFunc) := traverseExp(inExp,traverseExpDummyHelper,inFunc);
end traverseSubexpressionsDummyHelper;

public function traverseSubexpressionsTopDownHelper
"This function is used as input to a traverse function that does not traverse all subexpressions.
The extra argument is a tuple of the actul function to call on each subexpression and the extra argument.
"
  replaceable type Type_a subtypeof Any;
  input DAE.Exp inExp;
  input tuple<FuncExpType,Type_a> itpl;
  output DAE.Exp outExp;
  output tuple<FuncExpType,Type_a> otpl;
  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Boolean cont;
    output Type_a outA;
  end FuncExpType;
protected
  FuncExpType rel;
      Type_a ext_arg;
algorithm
  (rel,ext_arg) := itpl;
  (outExp,ext_arg) := traverseExpTopDown(inExp,rel,ext_arg);
  otpl := (rel,ext_arg);
end traverseSubexpressionsTopDownHelper;

public function traverseSubexpressionsWithoutRelations
"This function is used as input to a traverse function that does not traverse all subexpressions.
The extra argument is a tuple of the actul function to call on each subexpression and the extra argument.
"
  replaceable type Type_a subtypeof Any;
  input DAE.Exp inExp;
  input tuple<FuncExpType,Type_a> itpl;
  output DAE.Exp e;
  output Boolean cont;
  output tuple<FuncExpType,Type_a> otpl;
  partial function FuncExpType
    input DAE.Exp inExp;
  input Type_a inTypeA;
    output DAE.Exp outExp;
    output Type_a outA;
  end FuncExpType;
algorithm
  // TODO: Implement flags to traverseExp to handle special cases like WithoutRelations or without updating the expressions?
  (e,cont,otpl) := match (inExp,itpl)
    local
      FuncExpType f;
      Type_a ea1,ea2;
    case (DAE.LUNARY(),_)
      then (inExp,false,itpl);
    case (DAE.LBINARY(),_)
      then (inExp,false,itpl);
    case (DAE.RELATION(),_)
      then (inExp,false,itpl);
    case (_,(f,ea1))
      equation
        (e,ea2) = f(inExp,ea1);
        otpl = if referenceEq(ea1,ea2) then itpl else (f,ea2);
      then (e,true,otpl);
  end match;
end traverseSubexpressionsWithoutRelations;

protected function traverseExpMatrix
"author: PA
   Helper function to traverseExp, traverses matrix expressions."
  replaceable type Type_a subtypeof Any;
  input list<list<DAE.Exp>> inMatrix;
  input FuncExpType func;
  input Type_a inTypeA;
  output list<list<DAE.Exp>> outMatrix;
  output Type_a outTypeA;
  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Type_a outA;
  end FuncExpType;
algorithm
  (outMatrix,outTypeA) := match (inMatrix,func,inTypeA)
    local
      FuncExpType rel;
      Type_a e_arg,e_arg_1,e_arg_2;
      list<DAE.Exp> row_1,row;
      list<list<DAE.Exp>> rows_1,rows;

    case ({},_,e_arg) then ({},e_arg);

    case ((row :: rows),rel,e_arg)
      equation
        (row_1,e_arg_1) = traverseExpList(row, rel, e_arg);
        (rows_1,e_arg_2) = traverseExpMatrix(rows, rel, e_arg_1);
        rows_1 = if referenceEq(row,row_1) and referenceEq(rows,rows_1) then inMatrix else (row_1::rows_1);
      then
        (rows_1,e_arg_2);
  end match;
end traverseExpMatrix;

public function traverseExpList<ArgT> "Calls traverseExp for each element of list."
  input list<DAE.Exp> inExpl;
  input FuncExpType rel;
  input ArgT iext_arg;
  output list<DAE.Exp> expl := {};
  output ArgT ext_arg := iext_arg;
  partial function FuncExpType
    input DAE.Exp inExp;
    input ArgT inTypeA;
    output DAE.Exp outExp;
    output ArgT outA;
  end FuncExpType;
protected
  DAE.Exp e1;
  Boolean same := true;
algorithm
  for e in inExpl loop
    (e1, ext_arg) := traverseExp(e, rel, ext_arg);
    expl := e1 :: expl;
    same := same and referenceEq(e, e1);
  end for;

  expl := if same then inExpl else listReverse(expl);
end traverseExpList;

public function traverseExpTopDown
"Traverses all subexpressions of an expression.
  Takes a function and an extra argument passed through the traversal.
  The function can potentially change the expression. In such cases,
  the changes are made top-down, i.e. a subexpression is traversed
  and changed after the complete expression is traversed."
  replaceable type Type_a subtypeof Any;
  input DAE.Exp inExp;
  input FuncExpType func;
  input Type_a ext_arg;
  output DAE.Exp outExp;
  output Type_a outArg;
  partial function FuncExpType
    input DAE.Exp exp;
    input Type_a arg;
    output DAE.Exp outExp;
    output Boolean cont;
    output Type_a outArg;
  end FuncExpType;
protected
  Boolean cont;
algorithm
  (outExp,cont,outArg) := func(inExp,ext_arg);
  (outExp,outArg) := traverseExpTopDown1(cont,outExp,func,outArg);
end traverseExpTopDown;

protected function traverseExpTopDown1
"Helper for traverseExpTopDown."
  replaceable type Type_a subtypeof Any;
  input Boolean cont;
  input DAE.Exp inExp;
  input FuncExpType func;
  input Type_a inArg;
  output DAE.Exp outExp;
  output Type_a outArg;
  partial function FuncExpType
    input DAE.Exp exp;
    input Type_a arg;
    output DAE.Exp outExp;
    output Boolean cont;
    output Type_a outArg;
  end FuncExpType;
algorithm
  (outExp,outArg) := match (cont,inExp,func,inArg)
    local
      DAE.Exp e1_1,e,e1,e2_1,e2,e3_1,e3;
      Type_a ext_arg_1,ext_arg_2,ext_arg,ext_arg_3;
      Operator op;
      FuncExpType rel;
      list<DAE.Exp> expl_1,expl;
      Absyn.Path fn;
      Boolean scalar;
      Type tp,et,t;
      Integer i;
      String str;
      list<String> fieldNames;
      list<list<DAE.Exp>> lstexpl_1,lstexpl;
      Integer dim;
      Integer index_;
      Option<tuple<DAE.Exp,Integer,Integer>> isExpisASUB;
      Option<DAE.Exp> oe1;
      DAE.ReductionInfo reductionInfo;
      DAE.ReductionIterators riters;
      DAE.CallAttributes attr;
      list<DAE.Element> localDecls;
      DAE.MatchType matchType;
      list<DAE.MatchCase> cases;
      ComponentRef cr,cr_1;
      list<list<String>> aliases;

    case (false,_,_,_) then (inExp,inArg);
    case (_,DAE.ICONST(_),_,ext_arg) then (inExp,ext_arg);
    case (_,DAE.RCONST(_),_,ext_arg) then (inExp,ext_arg);
    case (_,DAE.SCONST(_),_,ext_arg) then (inExp,ext_arg);
    case (_,DAE.BCONST(_),_,ext_arg) then (inExp,ext_arg);
    case (_,DAE.CLKCONST(_),_,ext_arg) then (inExp,ext_arg);
    case (_,DAE.ENUM_LITERAL(),_,ext_arg) then (inExp,ext_arg);
    case (_,DAE.CREF(cr,tp),rel,ext_arg)
      equation
        (cr_1,ext_arg_1) = traverseExpTopDownCrefHelper(cr,rel,ext_arg);
        e = if referenceEq(cr,cr_1) then inExp else DAE.CREF(cr_1,tp);
      then (e,ext_arg_1);
    // unary
    case (_,DAE.UNARY(operator = op,exp = e1),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
      then
        (DAE.UNARY(op,e1_1),ext_arg_1);

    // binary
    case (_,DAE.BINARY(exp1 = e1,operator = op,exp2 = e2),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
        (e2_1,ext_arg_2) = traverseExpTopDown(e2, rel, ext_arg_1);
      then (DAE.BINARY(e1_1,op,e2_1),ext_arg_2);

    // logical unary
    case (_,DAE.LUNARY(operator = op,exp = e1),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
      then (DAE.LUNARY(op,e1_1),ext_arg_1);

    // logical binary
    case (_,DAE.LBINARY(exp1 = e1,operator = op,exp2 = e2),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
        (e2_1,ext_arg_2) = traverseExpTopDown(e2, rel, ext_arg_1);
      then (DAE.LBINARY(e1_1,op,e2_1),ext_arg_2);

    // relation
    case (_,DAE.RELATION(exp1 = e1,operator = op,exp2 = e2, index=index_, optionExpisASUB= isExpisASUB),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
        (e2_1,ext_arg_2) = traverseExpTopDown(e2, rel, ext_arg_1);
      then (DAE.RELATION(e1_1,op,e2_1,index_,isExpisASUB),ext_arg_2);

    // if expressions
    case (_,(DAE.IFEXP(expCond = e1,expThen = e2,expElse = e3)),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
        (e2_1,ext_arg_2) = traverseExpTopDown(e2, rel, ext_arg_1);
        (e3_1,ext_arg_3) = traverseExpTopDown(e3, rel, ext_arg_2);
      then (DAE.IFEXP(e1_1,e2_1,e3_1),ext_arg_3);

    // call
    case (_,(DAE.CALL(path = fn,expLst = expl,attr = attr)),rel,ext_arg)
      equation
        (expl_1,ext_arg_1) = traverseExpListTopDown(expl, rel, ext_arg);
      then (DAE.CALL(fn,expl_1,attr),ext_arg_1);

    case (_,(DAE.RECORD(path = fn,exps = expl,comp = fieldNames,ty = tp)),rel,ext_arg)
      equation
        (expl_1,ext_arg_1) = traverseExpListTopDown(expl, rel, ext_arg);
      then (DAE.RECORD(fn,expl_1,fieldNames,tp),ext_arg_1);

    case (_,(DAE.PARTEVALFUNCTION(fn, expl, tp, t)),rel,ext_arg)
      equation
        (expl_1,ext_arg_1) = traverseExpListTopDown(expl, rel, ext_arg);
      then (DAE.PARTEVALFUNCTION(fn,expl_1,tp,t),ext_arg_1);

    case (_,(DAE.ARRAY(ty = tp,scalar = scalar,array = expl)),rel,ext_arg)
      equation
        (expl_1,ext_arg_1) = traverseExpListTopDown(expl, rel, ext_arg);
      then (DAE.ARRAY(tp,scalar,expl_1),ext_arg_1);

    case (_,(DAE.MATRIX(ty = tp,integer = dim,matrix = lstexpl)),rel,ext_arg)
      equation
        (lstexpl_1,ext_arg_1) = traverseExpMatrixTopDown(lstexpl, rel, ext_arg);
      then (DAE.MATRIX(tp,dim,lstexpl_1),ext_arg_1);

    case (_,(DAE.RANGE(ty = tp,start = e1,step = NONE(),stop = e2)),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
        (e2_1,ext_arg_2) = traverseExpTopDown(e2, rel, ext_arg_1);
      then (DAE.RANGE(tp,e1_1,NONE(),e2_1),ext_arg_2);

    case (_,(DAE.RANGE(ty = tp,start = e1,step = SOME(e2),stop = e3)),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
        (e2_1,ext_arg_2) = traverseExpTopDown(e2, rel, ext_arg_1);
        (e3_1,ext_arg_3) = traverseExpTopDown(e3, rel, ext_arg_2);
      then (DAE.RANGE(tp,e1_1,SOME(e2_1),e3_1),ext_arg_3);

    case (_,(DAE.TUPLE(PR = expl)),rel,ext_arg)
      equation
        (expl_1,ext_arg_1) = traverseExpListTopDown(expl, rel, ext_arg);
      then (DAE.TUPLE(expl_1),ext_arg_1);

    case (_,(DAE.CAST(ty = tp,exp = e1)),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
      then (DAE.CAST(tp,e1_1),ext_arg_1);

    case (_,(DAE.ASUB(exp = e1,sub = expl_1)),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
        (expl_1,ext_arg_2) = traverseExpListTopDown(expl_1, rel, ext_arg_1);
      then (makeASUB(e1_1,expl_1),ext_arg_2);

    case (_,(DAE.TSUB(e1,i,tp)),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
      then (DAE.TSUB(e1_1,i,tp),ext_arg_1);

    case (_,(DAE.SIZE(exp = e1,sz = NONE())),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
      then (DAE.SIZE(e1_1,NONE()),ext_arg_1);

    case (_,(DAE.SIZE(exp = e1,sz = SOME(e2))),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
        (e2_1,ext_arg_2) = traverseExpTopDown(e2, rel, ext_arg_1);
      then (DAE.SIZE(e1_1,SOME(e2_1)),ext_arg_2);

    case (_,DAE.CODE(),_,ext_arg) then (inExp,ext_arg);

    case (_,DAE.REDUCTION(reductionInfo = reductionInfo, expr = e1, iterators = riters),rel,ext_arg)
      equation
        (e1,ext_arg) = traverseExpTopDown(e1, rel, ext_arg);
        (riters,ext_arg) = traverseReductionIteratorsTopDown(riters, rel, ext_arg);
      then (DAE.REDUCTION(reductionInfo,e1,riters),ext_arg);

    // MetaModelica list
    case (_,DAE.CONS(e1,e2),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
        (e2_1,ext_arg_2) = traverseExpTopDown(e2, rel, ext_arg_1);
      then (DAE.CONS(e1_1,e2_1),ext_arg_2);

    case (_,DAE.LIST(expl),rel,ext_arg)
      equation
        (expl_1,ext_arg_1) = traverseExpListTopDown(expl, rel, ext_arg);
      then (DAE.LIST(expl_1),ext_arg_1);

    case (_,DAE.META_TUPLE(expl),rel,ext_arg)
      equation
        (expl_1,ext_arg_1) = traverseExpListTopDown(expl, rel, ext_arg);
      then (DAE.META_TUPLE(expl_1),ext_arg_1);

    case (_,DAE.META_OPTION(oe1),rel,ext_arg)
      equation
        (oe1,ext_arg) = traverseExpOptTopDown(oe1, rel, ext_arg);
      then (DAE.META_OPTION(oe1),ext_arg);

    case (_,DAE.MATCHEXPRESSION(matchType,expl,aliases,localDecls,cases,et),rel,ext_arg)
      equation
        (expl,ext_arg) = traverseExpListTopDown(expl,rel,ext_arg);
        // TODO: Traverse cases
      then (DAE.MATCHEXPRESSION(matchType,expl,aliases,localDecls,cases,et),ext_arg);

    case (_,DAE.METARECORDCALL(fn,expl,fieldNames,i),rel,ext_arg)
      equation
        (expl_1,ext_arg_1) = traverseExpListTopDown(expl, rel, ext_arg);
      then (DAE.METARECORDCALL(fn,expl_1,fieldNames,i),ext_arg_1);

    case (_,DAE.UNBOX(e1,tp),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
      then (DAE.UNBOX(e1_1,tp),ext_arg_1);

    case (_,DAE.BOX(e1),rel,ext_arg)
      equation
        (e1_1,ext_arg_1) = traverseExpTopDown(e1, rel, ext_arg);
      then (DAE.BOX(e1_1),ext_arg_1);

    case (_,DAE.PATTERN(),_,ext_arg)
      then (inExp,ext_arg);

    case (_,DAE.SHARED_LITERAL(),_,ext_arg)
      then (inExp,ext_arg);

    else
      equation
        str = ExpressionDump.printExpStr(inExp);
        str = "Expression.traverseExpTopDown1 not implemented correctly: " + str;
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then fail();
  end match;
end traverseExpTopDown1;

protected function traverseExpMatrixTopDown
"author: PA
   Helper function to traverseExpTopDown, traverses matrix expressions."
  replaceable type Type_a subtypeof Any;
  input list<list<DAE.Exp>> inMatrix;
  input FuncExpType func;
  input Type_a inTypeA;
  output list<list<DAE.Exp>> outMatrix;
  output Type_a outTypeA;
  partial function FuncExpType
    input DAE.Exp exp;
    input Type_a arg;
    output DAE.Exp outExp;
    output Boolean cont;
    output Type_a outArg;
  end FuncExpType;
algorithm
  (outMatrix,outTypeA) := match (inMatrix,func,inTypeA)
    local
      FuncExpType rel;
      Type_a e_arg,e_arg_1,e_arg_2;
      list<DAE.Exp> row_1,row;
      list<list<DAE.Exp>> rows_1,rows;

    case ({},_,e_arg) then ({},e_arg);

    case ((row :: rows),rel,e_arg)
      equation
        (row_1,e_arg_1) = traverseExpListTopDown(row, rel, e_arg);
        (rows_1,e_arg_2) = traverseExpMatrixTopDown(rows, rel, e_arg_1);
      then (row_1 :: rows_1,e_arg_2);
  end match;
end traverseExpMatrixTopDown;

public function traverseExpListTopDown
" author PA:
 Calls traverseExp for each element of list."
  replaceable type Type_a subtypeof Any;
  input list<DAE.Exp> inExpl;
  input FuncExpType rel;
  input Type_a inExt_arg;
  output list<DAE.Exp> outExpl;
  output Type_a outA;
  partial function FuncExpType
    input DAE.Exp exp;
    input Type_a arg;
    output DAE.Exp outExp;
    output Boolean cont;
    output Type_a outArg;
  end FuncExpType;
algorithm
  (outExpl,outA) := match(inExpl,rel,inExt_arg)
    local DAE.Exp e,e1; list<DAE.Exp> expl1, expl; Type_a ext_arg;
    case ({},_,ext_arg) then ({},ext_arg);
    case (e::expl,_,ext_arg)
      equation
        (e1,ext_arg) = traverseExpTopDown(e, rel, ext_arg);
        (expl1,ext_arg) = traverseExpListTopDown(expl,rel,ext_arg);
      then (e1::expl1,ext_arg);
  end match;
end traverseExpListTopDown;

public function traverseExpOpt "Calls traverseExp for SOME(exp) and does nothing for NONE"
  input Option<DAE.Exp> inExp;
  input FuncExpType func;
  input Type_a inTypeA;
  output Option<DAE.Exp> outExp;
  output Type_a outTypeA;
  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Type_a outA;
  end FuncExpType;
  replaceable type Type_a subtypeof Any;
algorithm
  (outExp,outTypeA) := match (inExp,func,inTypeA)
    local
      DAE.Exp e,e1;
      Type_a a;
      Option<DAE.Exp> oe;
    case (NONE(),_,a) then (inExp/*In case external functions create a copy of NONE()*/,a);
    case(oe as SOME(e),_,a) equation
      (e1,a) = traverseExp(e,func,a);
      oe = if referenceEq(e,e1) then oe else SOME(e1);
     then (oe,a);
  end match;
end traverseExpOpt;

public function traverseExpOptTopDown "Calls traverseExpTopDown for SOME(exp) and does nothing for NONE"
  input Option<DAE.Exp> inExp;
  input FuncExpType func;
  input Type_a inTypeA;
  output Option<DAE.Exp> outExp;
  output Type_a outA;
  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Boolean cont;
    output Type_a outA;
  end FuncExpType;
  replaceable type Type_a subtypeof Any;
algorithm
  (outExp,outA) := match (inExp,func,inTypeA)
    local DAE.Exp e; Type_a a;
    case(NONE(),_,a) then (NONE(),a);
    case(SOME(e),_,a)
      equation
        (e,a) = traverseExpTopDown(e,func,a);
      then (SOME(e),a);
  end match;
end traverseExpOptTopDown;

public function traverseExpCrefDims<ArgT>
  input DAE.ComponentRef inCref;
  input FuncType inFunc;
  input ArgT inArg;
  output DAE.ComponentRef outCref;
  output ArgT outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input ArgT inArg;
    output DAE.Exp outExp;
    output ArgT outArg;
  end FuncType;
algorithm
  (outCref, outArg) := match(inCref)
    local
      DAE.Ident id;
      DAE.Type ty, new_ty;
      list<DAE.Subscript> subs;
      DAE.ComponentRef cr, new_cr;
      ArgT arg;
      Integer idx;

    case DAE.CREF_QUAL(id, ty, subs, cr)
      equation
        (new_cr, arg) = traverseExpCrefDims(cr, inFunc, inArg);
        (new_ty, arg) = traverseExpTypeDims(ty, inFunc, inArg);
        cr = if referenceEq(new_cr, cr) and referenceEq(new_ty, ty)
          then inCref else DAE.CREF_QUAL(id, new_ty, subs, new_cr);
      then
        (cr, arg);

    case DAE.CREF_IDENT(id, ty, subs)
      equation
        (new_ty, arg) = traverseExpTypeDims(ty, inFunc, inArg);
        cr = if referenceEq(new_ty, ty)
          then inCref else DAE.CREF_IDENT(id, new_ty, subs);
      then
        (cr, arg);

    case DAE.CREF_ITER(id, idx, ty, subs)
      equation
        (new_ty, arg) = traverseExpTypeDims(ty, inFunc, inArg);
        cr = if referenceEq(new_ty, ty)
          then inCref else DAE.CREF_ITER(id, idx, new_ty, subs);
      then
        (cr, arg);

    else (inCref, inArg);
  end match;
end traverseExpCrefDims;

public function traverseExpTypeDims<ArgT>
  input DAE.Type inType;
  input FuncType inFunc;
  input ArgT inArg;
  output DAE.Type outType;
  output ArgT outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input ArgT inArg;
    output DAE.Exp outExp;
    output ArgT outArg;
  end FuncType;
algorithm
  (outType, outArg) := match(inType)
    local
      DAE.Type ty, new_ty;
      list<DAE.Dimension> dims, new_dims;
      DAE.TypeSource src;
      ArgT arg;
      Boolean changed;
      ClassInf.State state;
      list<DAE.Var> vars;
      DAE.EqualityConstraint ec;

    case DAE.T_ARRAY(ty, dims, src)
      equation
        (_, arg, changed) = traverseExpTypeDims2(dims, inFunc, inArg);
        ty = if changed then DAE.T_ARRAY(ty, dims, src) else inType;
      then
        (ty, arg);

    case DAE.T_SUBTYPE_BASIC(state, vars, ty, ec, src)
      equation
        (new_ty, arg) = traverseExpTypeDims(ty, inFunc, inArg);
        ty = if referenceEq(new_ty, ty) then inType else DAE.T_SUBTYPE_BASIC(state, vars, ty, ec, src);
      then
        (ty, arg);

    else (inType, inArg);
  end match;
end traverseExpTypeDims;

protected function traverseExpTypeDims2<ArgT>
  input list<DAE.Dimension> inDims;
  input FuncType inFunc;
  input ArgT inArg;
  output list<DAE.Dimension> outDims := {};
  output ArgT outArg := inArg;
  output Boolean outChanged := false;

  partial function FuncType
    input DAE.Exp inExp;
    input ArgT inArg;
    output DAE.Exp outExp;
    output ArgT outArg;
  end FuncType;
protected
  Boolean changed := false;
  DAE.Exp exp, new_exp;
algorithm
  for dim in inDims loop
    dim := match(dim)
      case DAE.DIM_EXP(exp)
        equation
          (new_exp, outArg) = inFunc(exp, outArg);
          changed = not referenceEq(new_exp, exp);
          outChanged = outChanged or changed;
        then
          if changed then DAE.DIM_EXP(exp) else dim;

      else dim;
    end match;

    outDims := dim :: outDims;
  end for;

  outDims := if outChanged then listReverse(outDims) else inDims;
end traverseExpTypeDims2;

public function extractCrefsFromExp "
Author: BZ 2008-06, Extracts all ComponentRef from an Expression."
  input DAE.Exp inExp;
  output list<DAE.ComponentRef> ocrefs;
algorithm
  (_,ocrefs) := traverseExp(inExp, traversingComponentRefFinder, {});
end extractCrefsFromExp;

public function extractUniqueCrefsFromExp
  "Extracts all unique ComponentRef from an Expression."
  input DAE.Exp inExp;
  output list<DAE.ComponentRef> ocrefs;
algorithm
  // ocrefs := List.unique(List.flatten(List.map1(extractCrefsFromExp(inExp), ComponentReference.expandCref, true)));
  ocrefs := List.unique(extractCrefsFromExp(inExp));
end extractUniqueCrefsFromExp;

public function extractCrefsFromExpDerPreStart
" author mahge: Same as extractCrefsFromExp except:
  This function will not treat der(), pre() and start() as calls
  but as unique ids. i.e. x is different from der(x) and given der(x) x will not
  be extreacted as a unique id. Instead you get $DER.x. Same oes for pre and start."
  input DAE.Exp inExp;
  output list<DAE.ComponentRef> ocrefs;
algorithm
  (_,ocrefs) := traverseExpDerPreStart(inExp, traversingComponentRefFinder, {});
end extractCrefsFromExpDerPreStart;

public function extractUniqueCrefsFromExpDerPreStart
  "author mahge: Same as extractUniqueCrefsFromExp except:
  This function will not treat der(), pre() and start() as calls
  but as unique ids. i.e. x is different from der(x) and given der(x) x will not
  be extreacted as a unique id. Instead you get $DER.x. Same oes for pre and start.."
  input DAE.Exp inExp;
  output list<DAE.ComponentRef> ocrefs;
algorithm
  // ocrefs := List.unique(List.flatten(List.map1(extractCrefsFromExp(inExp), ComponentReference.expandCref, true)));
  ocrefs := List.unique(extractCrefsFromExpDerPreStart(inExp));
end extractUniqueCrefsFromExpDerPreStart;


public function extractUniqueCrefsFromStatmentS
  "authot mahge: Extracts all unique ComponentRef from Statments."
  input list<DAE.Statement> inStmts;
  output tuple<list<DAE.ComponentRef>,list<DAE.ComponentRef>> ocrefs;
protected
  list<list<DAE.ComponentRef>> lhscreflstlst;
  list<list<DAE.ComponentRef>> rhscreflstlst;
  list<DAE.ComponentRef> orhscrefs;
  list<DAE.ComponentRef> olhscrefs;
algorithm
  (lhscreflstlst,rhscreflstlst) := List.map_2(inStmts,extractCrefsStatment);
  orhscrefs := List.unique(List.flatten(rhscreflstlst));
  olhscrefs := List.unique(List.flatten(lhscreflstlst));
  ocrefs := (olhscrefs,orhscrefs);
end extractUniqueCrefsFromStatmentS;


public function extractCrefsStatment
  "Extracts all ComponentRef from a Statment."
  input DAE.Statement inStmt;
  output list<DAE.ComponentRef> olcrefs;
  output list<DAE.ComponentRef> orcrefs;
algorithm
  (olcrefs,orcrefs) := match(inStmt)
    local
      Exp exp1,exp2;
    case DAE.STMT_ASSERT(cond = exp1)
      equation
        orcrefs = extractCrefsFromExpDerPreStart(exp1);
      then
        ({},orcrefs);

    case DAE.STMT_ASSIGN(exp1 = exp1, exp = exp2)
      equation
        olcrefs = extractCrefsFromExpDerPreStart(exp1);
        orcrefs = extractCrefsFromExpDerPreStart(exp2);
      then
        (olcrefs,orcrefs);

    case _ then  ({},{});

  end match;
end extractCrefsStatment;

public function expHasCrefs "
@author: adrpo 2011-04-29
 returns true if the expression contains crefs"
  input DAE.Exp inExp;
  output Boolean hasCrefs;
algorithm
  hasCrefs := match(inExp)
    local
      Boolean b;

    case _
      equation
        (_,b) = traverseExpTopDown(inExp, traversingComponentRefPresent, false);
      then
        b;
  end match;
end expHasCrefs;

public function traversingComponentRefPresent "Returns a true if the exp is a componentRef"
  input DAE.Exp inExp;
  input Boolean found;
  output DAE.Exp outExp;
  output Boolean cont;
  output Boolean outFound;
algorithm
  (outExp,cont,outFound) := match (inExp,found)
    case (_,true) then (inExp,false,true);
    case (DAE.CREF(), _) then (inExp, false, true);
    else (inExp,true,false);
  end match;
end traversingComponentRefPresent;

public function traversingComponentRefFinder "
Author: BZ 2008-06
Exp traverser that Union the current ComponentRef with list if it is already there.
Returns a list containing, unique, all componentRef in an Expression."
  input DAE.Exp inExp;
  input list<DAE.ComponentRef> inCrefs;
  output DAE.Exp outExp;
  output list<DAE.ComponentRef> crefs;
algorithm
  (outExp,crefs) := match (inExp,inCrefs)
    local
      ComponentRef cr;
    case (DAE.CREF(componentRef=cr), crefs)
      equation
        crefs = List.unionEltOnTrue(cr,crefs,ComponentReference.crefEqual);
      then (inExp,crefs);
    else (inExp,inCrefs);
  end match;
end traversingComponentRefFinder;

public function traversingComponentRefFinderNoPreDer "
Author: BZ 2008-06
Exp traverser that Union the current ComponentRef with list if it is already there.
Returns a list containing, unique, all componentRef in an Expression."
  input DAE.Exp inExp;
  input list<DAE.ComponentRef> inCrefs;
  output DAE.Exp e;
  output Boolean cont;
  output list<DAE.ComponentRef> crefs;
algorithm
  (e,cont,crefs) := match (inExp,inCrefs)
    local
      ComponentRef cr;
    case (DAE.CREF(componentRef=cr), crefs)
      equation
        crefs = List.unionEltOnTrue(cr,crefs,ComponentReference.crefEqual);
      then (inExp, false, crefs);
    case (DAE.CALL(path = Absyn.IDENT(name = "der")), _) then (inExp, false, inCrefs);
    case (DAE.CALL(path = Absyn.IDENT(name = "pre")), _) then (inExp, false, inCrefs);
    else (inExp,true,inCrefs);
  end match;
end traversingComponentRefFinderNoPreDer;

public function traversingDerAndComponentRefFinder "
Author: Frenkel TUD 2012-06
Exp traverser that Union the current ComponentRef with list if it is already there.
Returns a list containing, unique, all componentRef in an Expression and a second list
containing all componentRef from a der function."
  input tuple<DAE.Exp, tuple<list<DAE.ComponentRef>,list<DAE.ComponentRef>>> inExp;
  output tuple<DAE.Exp, tuple<list<DAE.ComponentRef>,list<DAE.ComponentRef>>> outExp;
algorithm
  outExp := matchcontinue(inExp)
    local
      list<DAE.ComponentRef> crefs,dcrefs;
      ComponentRef cr;
      Type ty;
      DAE.Exp e;

    case((e as DAE.CREF(cr,_), (crefs,dcrefs)))
      equation
        crefs = List.unionEltOnTrue(cr,crefs,ComponentReference.crefEqual);
        // e = makeCrefExp(cr,ty);
      then
        ((e, (crefs,dcrefs) ));

    case((e as DAE.CALL(path = Absyn.IDENT(name = "der"),expLst={DAE.CREF(cr,_)}), (crefs,dcrefs)))
      equation
        dcrefs = List.unionEltOnTrue(cr,dcrefs,ComponentReference.crefEqual);
        // e = makeCrefExp(cr,ty);
      then
        ((e, (crefs,dcrefs) ));

    else inExp;

  end matchcontinue;
end traversingDerAndComponentRefFinder;

public function expHasCref "author: Frenkel TUD 2011-04
  returns true if the expression contains the cref"
  input DAE.Exp inExp;
  input DAE.ComponentRef inCr;
  output Boolean hasCref;
algorithm
  (_,(_,hasCref)) := traverseExpTopDown(inExp, traversingexpHasCref, (inCr,false));
end expHasCref;

public function traversingexpHasCref "
@author: Frenkel TUD 2011-04
Returns a true if the exp the componentRef"
  input DAE.Exp inExp;
  input tuple<DAE.ComponentRef,Boolean> inTpl;
  output DAE.Exp outExp;
  output Boolean cont;
  output tuple<DAE.ComponentRef,Boolean> outTpl;
algorithm
  (outExp,cont,outTpl) := matchcontinue(inExp,inTpl)
    local
      Boolean b;
      ComponentRef cr,cr1;

    case (DAE.CREF(componentRef = cr1), (cr,false))
      equation
        b = ComponentReference.crefEqualNoStringCompare(cr,cr1);
      then
        (inExp,not b,(cr,b));

    case (_,(_,b)) then (inExp,not b,inTpl);

  end matchcontinue;
end traversingexpHasCref;

public function expHasCrefName "Returns a true if the exp contains a cref that starts with the given name"
  input DAE.Exp inExp;
  input String name;
  output Boolean hasCref;
algorithm
  (_,(_,hasCref)) := traverseExpTopDown(inExp, traversingexpHasName, (name,false));
end expHasCrefName;

public function anyExpHasCrefName "Returns a true if any exp contains a cref that starts with the given name"
  input list<DAE.Exp> inExps;
  input String name;
  output Boolean hasCref;
algorithm
  hasCref := List.fold(List.map1(inExps, expHasCrefName, name), boolOr, false);
end anyExpHasCrefName;

public function traversingexpHasName "Returns a true if the exp contains a cref that starts with the given name"
  input DAE.Exp inExp;
  input tuple<String,Boolean> inTpl;
  output DAE.Exp outExp;
  output Boolean cont;
  output tuple<String,Boolean> outTpl;
algorithm
  (outExp,cont,outTpl) := match (inExp,inTpl)
    local
      Boolean b;
      String name;
      DAE.ComponentRef cr;
    case (DAE.CREF(componentRef = cr), (name,false))
      equation
        b = name == ComponentReference.crefFirstIdent(cr);
      then (inExp,not b,(name,b));
    case (_,(_,b)) then (inExp,not b,inTpl);
  end match;
end traversingexpHasName;

public function expHasDerCref "
@author: Frenkel TUD 2012-06
 returns true if the expression contains the cref in function der"
  input DAE.Exp inExp;
  input DAE.ComponentRef inCr;
  output Boolean hasCref;
algorithm
  (_,(_,hasCref)) := traverseExpTopDown(inExp, traversingexpHasDerCref, (inCr,false));
end expHasDerCref;

public function traversingexpHasDerCref "
@author: Frenkel TUD 2012-06
Returns a true if the exp contains the componentRef in der"
  input DAE.Exp inExp;
  input tuple<DAE.ComponentRef,Boolean> inTpl;
  output DAE.Exp outExp;
  output Boolean cont;
  output tuple<DAE.ComponentRef,Boolean> outTpl;
algorithm
  (outExp,cont,outTpl) := matchcontinue(inExp,inTpl)
    local
      Boolean b;
      ComponentRef cr,cr1;

    case (DAE.CALL(path= Absyn.IDENT("der"),expLst={DAE.CREF(componentRef = cr1)}), (cr,false))
      equation
        b = ComponentReference.crefEqualNoStringCompare(cr,cr1);
      then (inExp,not b,(cr,b));

    case (DAE.CALL(path= Absyn.IDENT("der"),expLst={DAE.CREF(componentRef = cr1)}), (cr,false))
      equation
        b = ComponentReference.crefPrefixOf(cr,cr1);
      then (inExp,not b,(cr,b));

    case (_,(_,b)) then (inExp,not b,inTpl);

  end matchcontinue;
end traversingexpHasDerCref;

public function expHasCrefNoPreorDer "
@author: Frenkel TUD 2011-04
 returns true if the expression contains the cref, but not in pre,change,edge"
  input DAE.Exp inExp;
  input DAE.ComponentRef inCr;
  output Boolean hasCref;
algorithm
  (_,(_,hasCref)) := traverseExpTopDown(inExp, traversingexpHasCrefNoPreorDer, (inCr,false));
end expHasCrefNoPreorDer;

public function traversingexpHasCrefNoPreorDer "
@author: Frenkel TUD 2011-04
Returns a true if the exp the componentRef"
  input DAE.Exp inExp;
  input tuple<DAE.ComponentRef,Boolean> inTpl;
  output DAE.Exp outExp;
  output Boolean cont;
  output tuple<DAE.ComponentRef,Boolean> outTpl;
algorithm
  (outExp,cont,outTpl) := match (inExp,inTpl)
    local
      Boolean b;
      DAE.ComponentRef cr,cr1;

    case (DAE.CALL(path = Absyn.IDENT(name = "pre")), _)
      then (inExp,false,inTpl);

    case (DAE.CREF(componentRef = cr1), (cr,false))
      equation
        b = ComponentReference.crefEqualNoStringCompare(cr,cr1);
      then (inExp,not b,(cr,b));

/* Not reachable...
    case (DAE.CREF(componentRef = cr1), (cr,false))
      equation
        b = ComponentReference.crefPrefixOf(cr1,cr);
      then (inExp,not b,(cr,b));
*/
    case (_,(_,b)) then (inExp,not b,inTpl);

  end match;
end traversingexpHasCrefNoPreorDer;

public function expHasCrefsNoPreOrStart "
 returns true if the expression contains one cref from the list, but not in pre(),change(),edge(),start(), delay()"
  input DAE.Exp inExp;
  input list<DAE.ComponentRef> inCr;
  output Boolean hasCref;
algorithm
  for cr in inCr loop
    (_,(_,hasCref)) := traverseExpTopDown(inExp, traversingexpHasCrefNoPreOrStart, (cr,false));
    if hasCref then
      break;
    end if;
  end for;
end expHasCrefsNoPreOrStart;


public function expHasCrefNoPreOrStart "
 returns true if the expression contains the cref, but not in pre(),change(),edge(),start(), delay()"
  input DAE.Exp inExp;
  input DAE.ComponentRef inCr;
  output Boolean hasCref;
algorithm
  (_,(_,hasCref)) := traverseExpTopDown(inExp, traversingexpHasCrefNoPreOrStart, (inCr,false));
end expHasCrefNoPreOrStart;

protected function traversingexpHasCrefNoPreOrStart "
return true if the exp the componentRef"
  input DAE.Exp inExp;
  input tuple<DAE.ComponentRef,Boolean> inTpl;
  output DAE.Exp outExp;
  output Boolean cont;
  output tuple<DAE.ComponentRef,Boolean> outTpl;

algorithm
  (outExp,cont,outTpl) := match (inExp,inTpl)
    local
      Boolean b;
      DAE.ComponentRef cr,cr1;

    case (DAE.CALL(path = Absyn.IDENT(name = "pre")), _)
      then (inExp,false,inTpl);
    case (DAE.CALL(path = Absyn.IDENT(name = "change")), _)
      then (inExp,false,inTpl);
    case (DAE.CALL(path = Absyn.IDENT(name = "delay")), _)
      then (inExp,false,inTpl);
    case (DAE.CALL(path = Absyn.IDENT(name = "edge")), _)
      then (inExp,false,inTpl);
    case (DAE.CALL(path = Absyn.IDENT(name = "$_start")), _)
      then (inExp,false,inTpl);

    case (DAE.CREF(componentRef = cr1), (cr,false))
      equation
        b = ComponentReference.crefEqualNoStringCompare(cr,cr1);
      then (inExp,not b,(cr,b));

    case (_,(_,b)) then (inExp,not b,inTpl);

  end match;
end traversingexpHasCrefNoPreOrStart;


public function traverseCrefsFromExp "
Author: Frenkel TUD 2011-05, traverses all ComponentRef from an Expression."
  input DAE.Exp inExp;
  input FuncCrefTypeA inFunc;
  input Type_a inArg;
  output Type_a outArg;
  partial function FuncCrefTypeA
    input DAE.ComponentRef inCref;
    input Type_a inArg;
    output Type_a outArg;
  end FuncCrefTypeA;
  replaceable type Type_a subtypeof Any;
algorithm
  outArg := match(inExp,inFunc,inArg)
   local Type_a arg;
    case(_,_,_)
      equation
        (_,(_,arg)) = traverseExp(inExp, traversingCrefFinder, (inFunc,inArg));
      then
        arg;
  end match;
end traverseCrefsFromExp;

protected function traversingCrefFinder "
Author: Frenkel TUD 2011-05"
  input DAE.Exp inExp;
  input tuple<FuncCrefTypeA,Type_a> inTpl;
  output DAE.Exp outExp;
  output tuple<FuncCrefTypeA,Type_a> outTpl;
  partial function FuncCrefTypeA
    input DAE.ComponentRef inCref;
    input Type_a inArg;
    output Type_a outArg;
  end FuncCrefTypeA;
  replaceable type Type_a subtypeof Any;
algorithm
  (outExp,outTpl) := match (inExp,inTpl)
    local
      Type_a arg,arg1;
      FuncCrefTypeA func;
      ComponentRef cr;

    case (DAE.CREF(cr,_),(func,arg))
      equation
        arg1 = func(cr,arg);
      then (inExp, (func,arg1));

    else (inExp,inTpl);

  end match;
end traversingCrefFinder;

public function extractDivExpFromExp "
Author: Frenkel TUD 2010-02, Extracts all Division DAE.Exp from an Expression."
  input DAE.Exp inExp;
  output list<DAE.Exp> outExps;
algorithm
  (_,outExps) := traverseExp(inExp, traversingDivExpFinder, {});
end extractDivExpFromExp;

protected function traversingDivExpFinder "
Author: Frenkel TUD 2010-02
Returns a list containing, all division DAE.Exp in an Expression."
  input DAE.Exp e;
  input list<DAE.Exp> exps;
  output DAE.Exp outExp;
  output list<DAE.Exp> acc;
algorithm
  (outExp,acc) := match (e,exps)
  local
      DAE.Exp e2;
    case (DAE.BINARY(operator = DAE.DIV(_),exp2 = e2), _)
      then (e, e2::exps);

    case (DAE.BINARY(operator = DAE.DIV_ARR(_),exp2 = e2), _)
      then (e, e2::exps);

    case (DAE.BINARY(operator = DAE.DIV_ARRAY_SCALAR(_),exp2 = e2), _)
      then (e, e2::exps);

    case (DAE.BINARY(operator = DAE.DIV_SCALAR_ARRAY(_),exp2 = e2), _)
      then (e, e2::exps);

    else (e,exps);
  end match;
end traversingDivExpFinder;

public function traverseExpListBidir<ArgT>
  "Traverses a list of expressions, calling traverseExpBidir on each
  expression."
  input list<DAE.Exp> inExpl;
  input FuncType inEnterFunc;
  input FuncType inExitFunc;
  input ArgT inArg;
  output list<DAE.Exp> outExpl;
  output ArgT outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input ArgT inArg;
    output DAE.Exp outExp;
    output ArgT outArg;
  end FuncType;
algorithm
  (outExpl, outArg) :=
    List.map2Fold(inExpl, traverseExpBidir, inEnterFunc, inExitFunc, inArg);
end traverseExpListBidir;

public function traverseExpBidir<ArgT>
  "This function takes an expression and a tuple with an enter function, an exit
  function, and an extra argument. For each expression it encounters it calls
  the enter function with the expression and the extra argument. It then
  traverses all subexpressions in the expression and calls traverseExpBidir on
  them with the updated argument. Finally it calls the exit function, again with
  the updated argument. This means that this function is bidirectional, and can
  be used to emulate both top-down and bottom-up traversal."
  input DAE.Exp inExp;
  input FuncType inEnterFunc;
  input FuncType inExitFunc;
  input ArgT inArg;
  output DAE.Exp outExp;
  output ArgT outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input ArgT inArg;
    output DAE.Exp outExp;
    output ArgT outArg;
  end FuncType;
algorithm
  (outExp, outArg) := inEnterFunc(inExp, inArg);
  (outExp, outArg) := traverseExpBidirSubExps(outExp, inEnterFunc, inExitFunc, outArg);
  (outExp, outArg) := inExitFunc(outExp, outArg);
end traverseExpBidir;

public function traverseExpOptBidir<ArgT>
  "Same as traverseExpBidir, but with an optional expression. Calls
  traverseExpBidir if the option is SOME(), or just returns the input if it's
  NONE()"
  input Option<DAE.Exp> inExp;
  input FuncType inEnterFunc;
  input FuncType inExitFunc;
  input ArgT inArg;
  output Option<DAE.Exp> outExp;
  output ArgT outArg;

  partial function FuncType
    input Exp inExp;
    input ArgT inArg;
    output Exp outExp;
    output ArgT outArg;
  end FuncType;
algorithm
  (outExp, outArg) := match(inExp)
    local
      DAE.Exp e;
      ArgT arg;

    case SOME(e)
      equation
        (e, arg) = traverseExpBidir(e, inEnterFunc, inExitFunc, inArg);
      then
        (SOME(e), arg);

    else (inExp, inArg);
  end match;
end traverseExpOptBidir;

protected function traverseExpBidirSubExps<ArgT>
  "Helper function to traverseExpBidir. Traverses the subexpressions of an
  expression and calls traverseExpBidir on them."
  input DAE.Exp inExp;
  input FuncType inEnterFunc;
  input FuncType inExitFunc;
  input ArgT inArg;
  output DAE.Exp outExp;
  output ArgT outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input ArgT inArg;
    output DAE.Exp outExp;
    output ArgT outArg;
  end FuncType;
algorithm
  (outExp, outArg) := match(inExp)
    local
      Integer i;
      DAE.Exp e1, e2, e3;
      Option<DAE.Exp> oe1;
      DAE.Operator op;
      ComponentRef cref;
      list<DAE.Exp> expl;
      list<list<DAE.Exp>> mat_expl;
      String error_msg;
      DAE.MatchType match_ty;
      list<DAE.Element> match_decls;
      list<DAE.MatchCase> match_cases;
      Integer index, dim;
      Option<tuple<DAE.Exp, Integer, Integer>> opt_exp_asub;
      Absyn.Path path;
      Boolean b1;
      Type ty,t;
      list<String> strl;
      DAE.ReductionInfo reductionInfo;
      DAE.ReductionIterators riters;
      DAE.CallAttributes attr;
      list<list<String>> aliases;
      ArgT arg;

    case DAE.ICONST() then (inExp, inArg);
    case DAE.RCONST() then (inExp, inArg);
    case DAE.SCONST() then (inExp, inArg);
    case DAE.BCONST() then (inExp, inArg);
    case DAE.ENUM_LITERAL() then (inExp, inArg);

    case DAE.CREF(componentRef = cref, ty = ty)
      equation
        (cref, arg) = traverseExpBidirCref(cref, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.CREF(cref, ty), arg);

    case DAE.BINARY(exp1 = e1, operator = op, exp2 = e2)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
        (e2, arg) = traverseExpBidir(e2, inEnterFunc, inExitFunc, arg);
      then
        (DAE.BINARY(e1, op, e2), arg);

    case DAE.UNARY(operator = op, exp = e1)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.UNARY(op, e1), arg);

    case DAE.LBINARY(exp1 = e1, operator = op, exp2 = e2)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
        (e2, arg) = traverseExpBidir(e2, inEnterFunc, inExitFunc, arg);
      then
        (DAE.LBINARY(e1, op, e2), arg);

    case DAE.LUNARY(operator = op, exp = e1)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.LUNARY(op, e1), arg);

    case DAE.RELATION(exp1 = e1, operator = op, exp2 = e2, index = index,
         optionExpisASUB = opt_exp_asub)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
        (e2, arg) = traverseExpBidir(e2, inEnterFunc, inExitFunc, arg);
      then
        (DAE.RELATION(e1, op, e2, index, opt_exp_asub), arg);

    case DAE.IFEXP(expCond = e1, expThen = e2, expElse = e3)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
        (e2, arg) = traverseExpBidir(e2, inEnterFunc, inExitFunc, arg);
        (e3, arg) = traverseExpBidir(e3, inEnterFunc, inExitFunc, arg);
      then
        (DAE.IFEXP(e1, e2, e3), arg);

    case DAE.CALL(path = path, expLst = expl, attr = attr)
      equation
        (expl, arg) = traverseExpListBidir(expl, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.CALL(path, expl, attr), arg);

    case DAE.RECORD(path = path, exps = expl, comp = strl, ty = ty)
      equation
        (expl, arg) = traverseExpListBidir(expl, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.RECORD(path, expl, strl, ty), arg);

    case DAE.PARTEVALFUNCTION(path, expl, ty, t)
      equation
        (expl, arg) = traverseExpListBidir(expl, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.PARTEVALFUNCTION(path, expl, ty, t), arg);

    case DAE.ARRAY(ty = ty, scalar = b1, array = expl)
      equation
        (expl, arg) = traverseExpListBidir(expl, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.ARRAY(ty, b1, expl), arg);

    case DAE.MATRIX(ty = ty, integer = dim, matrix = mat_expl)
      equation
        (mat_expl, arg) = List.map2Fold(mat_expl, traverseExpListBidir,
          inEnterFunc, inExitFunc, inArg);
      then
        (DAE.MATRIX(ty, dim, mat_expl), arg);

    case DAE.RANGE(ty = ty, start = e1, step = oe1, stop = e2)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
        (oe1, arg) = traverseExpOptBidir(oe1, inEnterFunc, inExitFunc, arg);
        (e2, arg) = traverseExpBidir(e2, inEnterFunc, inExitFunc, arg);
      then
        (DAE.RANGE(ty, e1, oe1, e2), arg);

    case DAE.TUPLE(PR = expl)
      equation
        (expl, arg) = traverseExpListBidir(expl, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.TUPLE(expl), arg);

    case DAE.CAST(ty = ty, exp = e1)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.CAST(ty, e1), arg);

    case DAE.ASUB(exp = e1, sub = expl)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
        (expl, arg) = traverseExpListBidir(expl, inEnterFunc, inExitFunc, arg);
      then
        (DAE.ASUB(e1, expl), arg);

    case DAE.TSUB(e1, i, ty)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.TSUB(e1, i, ty), arg);

    case DAE.SIZE(exp = e1, sz = oe1)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
        (oe1, arg) = traverseExpOptBidir(oe1, inEnterFunc, inExitFunc, arg);
      then
        (DAE.SIZE(e1, oe1), arg);

    case DAE.CODE()
      then (inExp, inArg);

    case DAE.REDUCTION(reductionInfo = reductionInfo, expr = e1, iterators = riters)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
        (riters, arg) = List.map2Fold(riters, traverseReductionIteratorBidir,
          inEnterFunc, inExitFunc, arg);
      then
        (DAE.REDUCTION(reductionInfo, e1, riters), arg);

    case DAE.LIST(valList = expl)
      equation
        (expl, arg) = traverseExpListBidir(expl, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.LIST(expl), arg);

    case DAE.CONS(car = e1, cdr = e2)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
        (e2, arg) = traverseExpBidir(e2, inEnterFunc, inExitFunc, arg);
      then
        (DAE.CONS(e1, e2), arg);

    case DAE.META_TUPLE(listExp = expl)
      equation
        (expl, arg) = traverseExpListBidir(expl, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.TUPLE(expl), arg);

    case DAE.META_OPTION(exp = oe1)
      equation
        (oe1, arg) = traverseExpOptBidir(oe1, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.META_OPTION(oe1), arg);

    case DAE.METARECORDCALL(path = path, args = expl, fieldNames = strl, index = index)
      equation
        (expl, arg) = traverseExpListBidir(expl, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.METARECORDCALL(path, expl, strl, index), arg);

    case DAE.MATCHEXPRESSION(matchType = match_ty, inputs = expl, aliases=aliases,
        localDecls = match_decls, cases = match_cases, et = ty)
      equation
        (expl, arg) = traverseExpListBidir(expl, inEnterFunc, inExitFunc, inArg);
        /* TODO: Implement traverseMatchCase! */
        //(cases, tup) = List.mapFold(cases, traverseMatchCase, tup);
      then
        (DAE.MATCHEXPRESSION(match_ty, expl, aliases, match_decls, match_cases, ty), arg);

    case DAE.BOX(exp = e1)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.BOX(e1), arg);

    case DAE.UNBOX(exp = e1, ty = ty)
      equation
        (e1, arg) = traverseExpBidir(e1, inEnterFunc, inExitFunc, inArg);
      then
      (DAE.UNBOX(e1, ty), arg);

    case DAE.SHARED_LITERAL() then (inExp, inArg);
    case DAE.PATTERN() then (inExp, inArg);

    else
      equation
        error_msg = "in Expression.traverseExpBidirSubExps - Unknown expression: ";
        error_msg = error_msg + ExpressionDump.printExpStr(inExp);
        Error.addMessage(Error.INTERNAL_ERROR, {error_msg});
      then
        fail();

  end match;
end traverseExpBidirSubExps;

public function traverseExpBidirCref<ArgT>
  "Helper function to traverseExpBidirSubExps. Traverses any expressions in a
  component reference (i.e. in it's subscripts)."
  input DAE.ComponentRef inCref;
  input FuncType inEnterFunc;
  input FuncType inExitFunc;
  input ArgT inArg;
  output DAE.ComponentRef outCref;
  output ArgT outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input ArgT inArg;
    output DAE.Exp outExp;
    output ArgT outArg;
  end FuncType;
algorithm
  (outCref, outArg) := match(inCref)
    local
      String name;
      ComponentRef cr;
      Type ty;
      list<DAE.Subscript> subs;
      ArgT arg;

    case DAE.CREF_QUAL(name, ty, subs, cr)
      equation
        (subs, arg) = List.map2Fold(subs, traverseExpBidirSubs, inEnterFunc,
          inExitFunc, inArg);
        (cr, arg) = traverseExpBidirCref(cr, inEnterFunc, inExitFunc, arg);
      then
        (DAE.CREF_QUAL(name, ty, subs, cr), arg);

    case DAE.CREF_IDENT(ident = name, identType = ty, subscriptLst = subs)
      equation
        (subs, arg) = List.map2Fold(subs, traverseExpBidirSubs, inEnterFunc,
          inExitFunc, inArg);
      then
        (DAE.CREF_IDENT(name, ty, subs), arg);

    else (inCref, inArg);
  end match;
end traverseExpBidirCref;

public function traverseExpCref
  "Helper function to traverseExp. Traverses any expressions in a
  component reference (i.e. in it's subscripts)."
  input DAE.ComponentRef inCref;
  input FuncType rel;
  input Type_a iarg;
  output DAE.ComponentRef outCref;
  output Type_a outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input Type_a inArg;
    output DAE.Exp outExp;
    output Type_a outArg;
  end FuncType;

  replaceable type Type_a subtypeof Any;
algorithm
  (outCref, outArg) := match(inCref, rel, iarg)
    local
      String name;
      ComponentRef cr,cr_1;
      Type ty;
      list<DAE.Subscript> subs,subs_1;
      Type_a arg;
      Integer ix;
      String instant;

    case (DAE.CREF_QUAL(ident = name, identType = ty, subscriptLst = subs, componentRef = cr), _, arg)
      equation
        (subs_1, arg) = traverseExpSubs(subs, rel, arg);
        (cr_1, arg) = traverseExpCref(cr, rel, arg);
        cr = if referenceEq(cr,cr_1) and referenceEq(subs,subs_1) then inCref else DAE.CREF_QUAL(name, ty, subs_1, cr_1);
      then
        (cr, arg);

    case (DAE.CREF_IDENT(ident = name, identType = ty, subscriptLst = subs), _, arg)
      equation
        (subs_1, arg) = traverseExpSubs(subs, rel, arg);
        cr = if referenceEq(subs,subs_1) then inCref else DAE.CREF_IDENT(name, ty, subs_1);
      then
        (cr, arg);

    case (DAE.CREF_ITER(ident = name, index = ix, identType = ty, subscriptLst = subs), _, arg)
      equation
        (subs_1, arg) = traverseExpSubs(subs, rel, arg);
        cr = if referenceEq(subs,subs_1) then inCref else DAE.CREF_ITER(name, ix, ty, subs_1);
      then
        (cr, arg);

    case (DAE.OPTIMICA_ATTR_INST_CREF(componentRef = cr, instant = instant), _, arg)
      equation
        (cr_1, arg) = traverseExpCref(cr, rel, arg);
        cr = if referenceEq(cr,cr_1) then inCref else DAE.OPTIMICA_ATTR_INST_CREF(cr_1, instant);
      then
        (cr, arg);

    case (DAE.WILD(), _, arg) then (inCref, arg);

    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR, {"Expression.traverseExpCref: Unknown cref"});
      then fail();
  end match;
end traverseExpCref;

protected function traverseExpSubs
  input list<DAE.Subscript> inSubscript;
  input FuncType rel;
  input Type_a iarg;
  output list<DAE.Subscript> outSubscript;
  output Type_a outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input Type_a inArg;
    output DAE.Exp outExp;
    output Type_a outArg;
  end FuncType;

  replaceable type Type_a subtypeof Any;
algorithm
  (outSubscript, outArg) := match(inSubscript, rel, iarg)
    local
      DAE.Exp sub_exp,sub_exp_1;
      list<DAE.Subscript> rest,res;
      Type_a arg;

    case ({}, _, arg) then (inSubscript,arg);
    case (DAE.WHOLEDIM()::rest, _, arg)
      equation
        (res,arg) = traverseExpSubs(rest,rel,arg);
        res = if referenceEq(rest,res) then inSubscript else (DAE.WHOLEDIM()::res);
      then (res, arg);

    case (DAE.SLICE(exp = sub_exp)::rest, _, arg)
      equation
        (sub_exp_1,arg) = traverseExp(sub_exp, rel, arg);
        (res,arg) = traverseExpSubs(rest,rel,arg);
        res = if referenceEq(sub_exp,sub_exp_1) and referenceEq(rest,res) then inSubscript else (DAE.SLICE(sub_exp_1)::res);
      then
        (res, arg);

    case (DAE.INDEX(exp = sub_exp)::rest, _, arg)
      equation
        (sub_exp_1,arg) = traverseExp(sub_exp, rel, arg);
        (res,arg) = traverseExpSubs(rest,rel,arg);
        res = if referenceEq(sub_exp,sub_exp_1) and referenceEq(rest,res) then inSubscript else (DAE.INDEX(sub_exp_1)::res);
      then
        (res, arg);

    case (DAE.WHOLE_NONEXP(exp = sub_exp)::rest, _, arg)
      equation
        (sub_exp_1,arg) = traverseExp(sub_exp, rel, arg);
        (res,arg) = traverseExpSubs(rest,rel,arg);
        res = if referenceEq(sub_exp,sub_exp_1) and referenceEq(rest,res) then inSubscript else (DAE.WHOLE_NONEXP(sub_exp_1)::res);
      then
        (res, arg);

  end match;
end traverseExpSubs;

public function traverseExpTopDownCrefHelper
  input DAE.ComponentRef inCref;
  input FuncType rel;
  input Argument iarg;
  output DAE.ComponentRef outCref;
  output Argument outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input Argument inArg;
    output DAE.Exp outExp;
    output Boolean cont;
    output Argument outArg;
  end FuncType;

  replaceable type Argument subtypeof Any;
algorithm
  (outCref, outArg) := match(inCref, rel, iarg)
    local
      String name;
      ComponentRef cr;
      Type ty;
      list<DAE.Subscript> subs;
      Argument arg;

    case (DAE.CREF_QUAL(ident = name, identType = ty, subscriptLst = subs, componentRef = cr), _, arg)
      equation
        (subs,arg) = traverseExpTopDownSubs(subs, rel, arg);
        (cr, arg) = traverseExpTopDownCrefHelper(cr, rel, arg);
      then
        (DAE.CREF_QUAL(name, ty, subs, cr), arg);

    case (DAE.CREF_IDENT(ident = name, identType = ty, subscriptLst = subs), _, arg)
      equation
        (subs,arg) = traverseExpTopDownSubs(subs, rel, arg);
      then
        (DAE.CREF_IDENT(name, ty, subs), arg);

    case (DAE.WILD(), _, arg) then (inCref, arg);
  end match;
end traverseExpTopDownCrefHelper;

protected function traverseExpBidirSubs<ArgT>
  "Helper function to traverseExpBidirCref. Traverses expressions in a
  subscript."
  input DAE.Subscript inSubscript;
  input FuncType inEnterFunc;
  input FuncType inExitFunc;
  input ArgT inArg;
  output DAE.Subscript outSubscript;
  output ArgT outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input ArgT inArg;
    output DAE.Exp outExp;
    output ArgT outArg;
  end FuncType;
algorithm
  (outSubscript, outArg) := match(inSubscript)
    local
      DAE.Exp sub_exp;
      ArgT arg;

    case DAE.WHOLEDIM() then (inSubscript, inArg);

    case DAE.SLICE(exp = sub_exp)
      equation
        (sub_exp, arg) = traverseExpBidir(sub_exp, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.SLICE(sub_exp), arg);

    case DAE.INDEX(exp = sub_exp)
      equation
        (sub_exp, arg) = traverseExpBidir(sub_exp, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.INDEX(sub_exp), arg);

    case DAE.WHOLE_NONEXP(exp = sub_exp)
      equation
        (sub_exp, arg) = traverseExpBidir(sub_exp, inEnterFunc, inExitFunc, inArg);
      then
        (DAE.WHOLE_NONEXP(sub_exp), arg);

  end match;
end traverseExpBidirSubs;

protected function traverseExpTopDownSubs
  input list<DAE.Subscript> inSubscript;
  input FuncType rel;
  input Argument iarg;
  output list<DAE.Subscript> outSubscript;
  output Argument outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input Argument inArg;
    output DAE.Exp outExp;
    output Boolean cont;
    output Argument outArg;
  end FuncType;

  replaceable type Argument subtypeof Any;
algorithm
  (outSubscript, outArg) := match(inSubscript, rel, iarg)
    local
      DAE.Exp sub_exp;
      list<DAE.Subscript> rest;
      Argument arg;

    case ({}, _, arg) then ({},arg);
    case (DAE.WHOLEDIM()::rest, _, arg)
      equation
        (rest,arg) = traverseExpTopDownSubs(rest,rel,arg);
      then (DAE.WHOLEDIM()::rest, arg);

    case (DAE.SLICE(exp = sub_exp)::rest, _, arg)
      equation
        (sub_exp,arg) = traverseExpTopDown(sub_exp, rel, arg);
        (rest,arg) = traverseExpTopDownSubs(rest,rel,arg);
      then
        (DAE.SLICE(sub_exp)::rest, arg);

    case (DAE.INDEX(exp = sub_exp)::rest, _, arg)
      equation
        (sub_exp,arg) = traverseExpTopDown(sub_exp, rel, arg);
        (rest,arg) = traverseExpTopDownSubs(rest,rel,arg);
      then
        (DAE.INDEX(sub_exp)::rest, arg);

    case (DAE.WHOLE_NONEXP(exp = sub_exp)::rest, _, arg)
      equation
        (sub_exp,arg) = traverseExpTopDown(sub_exp, rel, arg);
        (rest,arg) = traverseExpTopDownSubs(rest,rel,arg);
      then
        (DAE.WHOLE_NONEXP(sub_exp)::rest, arg);

  end match;
end traverseExpTopDownSubs;

/***************************************************/
/* Compare and Check DAE.Exp */
/***************************************************/

public function operatorDivOrMul "returns true if operator is division or multiplication"
  input DAE.Operator op;
  output Boolean res;
algorithm
  res := matchcontinue(op)
    case(DAE.MUL(_)) then true;
    case(DAE.DIV(_)) then true;
    else false;
  end matchcontinue;
end operatorDivOrMul;

public function isRange
"Returns true if expression is a range expression."
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp)
    case DAE.RANGE() then true;
    case _ then false;
  end matchcontinue;
end isRange;

public function isReduction
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp)
    case DAE.REDUCTION() then true;
    case _ then false;
  end matchcontinue;
end isReduction;

public function isOne
"Returns true if an expression is constant
  and has the value one, otherwise false"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp)
    local
      Integer ival;
      Real rval;
      Boolean res;
      Type t;
      DAE.Exp e;

    case (DAE.ICONST(integer = ival)) then intEq(ival,1);
    case (DAE.RCONST(real = rval)) then realEq(rval,1.0);
    case (DAE.CAST(exp = e))
      equation
        res = isOne(e) "Casting to one is still one" ;
      then
        res;
    else false;
  end matchcontinue;
end isOne;

public function isZero
"Returns true if an expression is constant
  and has the value zero, otherwise false"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExp)
    local
      Integer ival;
      Real rval;
      Type t;
      DAE.Exp e;
      list<DAE.Exp> ae;
      list<list<DAE.Exp>> matrix;

    case (DAE.ICONST(integer = ival)) then intEq(ival,0);
    case (DAE.RCONST(real = rval)) then realEq(rval,0.0);
    case (DAE.CAST(exp = e)) then isZero(e);

    case(DAE.UNARY(DAE.UMINUS(_),e)) then isZero(e);
    case(DAE.ARRAY(array = ae)) then List.mapAllValueBool(ae,isZero,true);

    case (DAE.MATRIX(matrix = matrix))
      then List.mapListAllValueBool(matrix,isZero,true);

    case(DAE.UNARY(DAE.UMINUS_ARR(_),e)) then isZero(e);

    else false;

  end match;
end isZero;

public function isPositiveOrZero
  "Returns true if an expression is known to be >= 0"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExp)
    local
      Boolean b,b1,b2,b3;
      DAE.Exp e1,e2;
      Integer i;
      Real r;
      /* abs(e) */
    case DAE.CALL(path = Absyn.IDENT("abs")) then true;
    // exp(x)
    case DAE.CALL(path = Absyn.IDENT("exp")) then true;
    // cosh(x)
    case DAE.CALL(path = Absyn.IDENT("cosh")) then true;
      /* literals */
    case DAE.ICONST(i) then i>=0;
    case DAE.RCONST(r) then realGe(r,0.0);
      /* e1 + e2 */
    case DAE.BINARY(e1,DAE.ADD(),e2)
      then isPositiveOrZero(e1) and isPositiveOrZero(e2);
      /* e1 - e2 */
    case DAE.BINARY(e1,DAE.SUB(),e2)
      then isPositiveOrZero(e1) and isNegativeOrZero(e2);
      /* e1 * e2 , -e1 * -e2, e ^ 2.0 */
    case DAE.BINARY(e1,DAE.MUL(),e2)
      equation
        b1 = (isPositiveOrZero(e1) and isPositiveOrZero(e2));
        b2 = (isNegativeOrZero(e1) and isNegativeOrZero(e2));
        b3 = expEqual(e1,e2);
      then b1 or b2 or b3;
      /* e1 / e2, -e1 / -e2 */
    case DAE.BINARY(e1,DAE.DIV(),e2)
      equation
        b1 = (isPositiveOrZero(e1) and isPositiveOrZero(e2));
        b2 = (isNegativeOrZero(e1) and isNegativeOrZero(e2));
      then b1 or b2;
      /* Integer power we can say something good about */
    case DAE.BINARY(e1,DAE.POW(),DAE.RCONST(r))
      equation
        i = realInt(r);
        b1 = realEq(r,intReal(i));
        b2 = 0 == intMod(i,2);
        b3 = isPositiveOrZero(e1);
        b = b2 or b3;
      then b1 and b;
    case DAE.BINARY(_,DAE.POW(),e2) then isEven(e2);
    // -(x)
    case DAE.UNARY(DAE.UMINUS(), e1) then not isPositiveOrZero(e1);
    else isZero(inExp);

  end match;
end isPositiveOrZero;

public function isNegativeOrZero
"Returns true if an expression is known to be <= 0"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExp)
    local Integer i; Real r; DAE.Exp e1,e2;
    /* literals */
    case DAE.ICONST(i) then i <= 0;
    case DAE.RCONST(r) then r <= 0.0;
    // -(x)
    case DAE.UNARY(DAE.UMINUS(), e1) then isPositiveOrZero(e1);
    /* Integer power we can say something good about */
    case DAE.BINARY(e1,DAE.POW(),e2) guard(isOdd(e2)) then isNegativeOrZero(e2);

    else isZero(inExp);

  end match;
end isNegativeOrZero;

public function isHalf
"Returns true if an expression is 0.5"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExp)
    local
      Real rval;

    case (DAE.RCONST(real = rval)) then realEq(rval,0.5);
    else false;

  end match;
end isHalf;

public function isImpure "author: lochel
  Returns true if an expression contains an impure function call."
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := isConstWork(inExp, true);
  (_, outBoolean) := traverseExpTopDown(inExp, isImpureWork, false);
end isImpure;

protected function isImpureWork "author: lochel"
  input DAE.Exp inExp;
  input Boolean isImpure;
  output DAE.Exp outExp;
  output Boolean cont;
  output Boolean outImpure;
algorithm
  (outExp,cont,outImpure) := matchcontinue (inExp,isImpure)
    case (_, true) then (inExp,true,true);

    case (DAE.CALL(attr=DAE.CALL_ATTR(isImpure=true)), _)
      then (inExp,false,true);

    // workaround for builtin functions that are impure, but not marked as impure
    case (DAE.CALL(path = Absyn.IDENT(name="alarm"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    case (DAE.CALL(path = Absyn.IDENT(name="compareFilesAndMove"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    case (DAE.CALL(path = Absyn.IDENT(name="delay"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    case (DAE.CALL(path = Absyn.IDENT(name="initial"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    case (DAE.CALL(path = Absyn.IDENT(name="print"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    case (DAE.CALL(path = Absyn.IDENT(name="readFile"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    case (DAE.CALL(path = Absyn.IDENT(name="sample"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    case (DAE.CALL(path = Absyn.IDENT(name="system"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    case (DAE.CALL(path = Absyn.IDENT(name="system_parallel"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    case (DAE.CALL(path = Absyn.IDENT(name="terminal"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    case (DAE.CALL(path = Absyn.IDENT(name="writeFile"), attr=DAE.CALL_ATTR(builtin=true)), _)
      then (inExp,false,true);

    else (inExp,true,false);
  end matchcontinue;
end isImpureWork;

public function isConst
"Returns true if an expression is constant"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := isConstWork(inExp,true);
end isConst;

protected function isConstWork
"Returns true if an expression is constant"
  input DAE.Exp inExp;
  input Boolean inRes;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExp,inRes)
    local
      Boolean res;
      Operator op;
      DAE.Exp e,e1,e2;
      Type t;
      list<DAE.Exp> ae;
      list<list<DAE.Exp>> matrix;

    case (_,false) then false;
    case (DAE.ICONST(),_) then true;
    case (DAE.RCONST(),_) then true;
    case (DAE.BCONST(),_) then true;
    case (DAE.SCONST(),_) then true;
    case (DAE.ENUM_LITERAL(),_) then true;

    case (DAE.UNARY(exp = e),_) then isConstWork(e,true);

    case (DAE.CAST(exp = e),_) then isConstWork(e,true);

    case (DAE.BINARY(e1,_,e2),_) then isConstWork(e1,isConstWork(e2,true));

    case (DAE.IFEXP(e,e1,e2),_) then isConstWork(e,isConstWork(e1,isConstWork(e2,true)));

    case (DAE.LBINARY(exp1=e1,exp2=e2),_) then isConstWork(e1,isConstWork(e2,true));

    case (DAE.LUNARY(exp=e),_) then isConstWork(e,true);

    case (DAE.RELATION(exp1=e1,exp2=e2),_) then isConstWork(e1,isConstWork(e2,true));

    case (DAE.ARRAY(array = ae),_) then isConstWorkList(ae,true);

    case (DAE.MATRIX(matrix = matrix),_) then isConstWorkListList(matrix, true);

    case (DAE.RANGE(start=e1,step=NONE(),stop=e2),_) then isConstWork(e1,isConstWork(e2,true));

    case (DAE.RANGE(start=e,step=SOME(e1),stop=e2),_) then isConstWork(e,isConstWork(e1,isConstWork(e2,true)));

    case (DAE.PARTEVALFUNCTION(expList = ae),_) then isConstWorkList(ae,true);

    case (DAE.TUPLE(PR = ae),_) then isConstWorkList(ae,true);

    case (DAE.ASUB(exp=e,sub=ae),_) then isConstWorkList(ae,isConstWork(e,true));

    case (DAE.TSUB(exp=e),_) then isConstWork(e,true);

    case (DAE.SIZE(exp=e,sz=NONE()),_) then isConstWork(e,true);

    case (DAE.SIZE(exp=e1,sz=SOME(e2)),_) then isConstWork(e1,isConstWork(e2,true));

    case (DAE.CALL(expLst=ae, attr=DAE.CALL_ATTR(builtin=false, isImpure=false)),_) then isConstWorkList(ae,true);

    case (DAE.RECORD(exps=ae),_) then isConstWorkList(ae,true);

      /*TODO:Make this work for multiple iters, guard exps*/
    case (DAE.REDUCTION(expr=e1,iterators={DAE.REDUCTIONITER(exp=e2)}),_)
      then isConstWork(e1,isConstWork(e2,true));

    else false;
  end match;
end isConstWork;

protected function isConstValueWork
"Returns true if an expression is a constant value"
  input DAE.Exp inExp;
  input Boolean inRes;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExp,inRes)
    local
      Boolean res;
      DAE.Exp e,e1,e2;
      list<DAE.Exp> ae;
      list<list<DAE.Exp>> matrix;

    case (_,false) then false;
    case (DAE.ICONST(),_) then true;
    case (DAE.RCONST(),_) then true;
    case (DAE.BCONST(),_) then true;
    case (DAE.SCONST(),_) then true;
    case (DAE.ENUM_LITERAL(),_) then true;
    case (DAE.ARRAY(array = ae),_) then isConstValueWorkList(ae,true);
    case (DAE.MATRIX(matrix = matrix),_) then isConstValueWorkListList(matrix, true);
    else false;

  end match;
end isConstValueWork;

public function isConstValue
"Returns true if an expression is a constant value (not a composite operation)"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := isConstValueWork(inExp,true);
end isConstValue;

public function isConstWorkList
"Returns true if a list of expressions is constant"
  input list<DAE.Exp> inExps;
  input Boolean inBoolean;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExps,inBoolean)
    local
      DAE.Exp e; list<DAE.Exp> exps;
    case (_,false) then false;
    case ({},_) then true;
    case (e::exps,_) then isConstWorkList(exps,isConstWork(e,true));
  end match;
end isConstWorkList;

protected function isConstWorkListList
  input list<list<DAE.Exp>> inExps;
  input Boolean inIsConst;
  output Boolean outIsConst;
algorithm
  outIsConst := match(inExps, inIsConst)
    local
      list<DAE.Exp> e;
      list<list<DAE.Exp>> exps;

    case (_, false) then false;
    case (e :: exps, _) then isConstWorkListList(exps, isConstWorkList(e, true));
    case ({}, _) then true;
    else false;
  end match;
end isConstWorkListList;

public function isConstValueWorkList
"Returns true if a list of expressions is a constant value"
  input list<DAE.Exp> inExps;
  input Boolean inBoolean;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExps,inBoolean)
    local
      DAE.Exp e; list<DAE.Exp> exps;
    case (_,false) then false;
    case ({},_) then true;
    case (e::exps,_) then isConstValueWorkList(exps,isConstValueWork(e,true));
  end match;
end isConstValueWorkList;

protected function isConstValueWorkListList
  input list<list<DAE.Exp>> inExps;
  input Boolean inIsConst;
  output Boolean outIsConst;
algorithm
  outIsConst := match(inExps, inIsConst)
    local
      list<DAE.Exp> e;
      list<list<DAE.Exp>> exps;

    case (_, false) then false;
    case (e :: exps, _) then isConstValueWorkListList(exps, isConstWorkList(e, true));
    else false;
  end match;
end isConstValueWorkListList;

public function isNotConst
"author: PA
  Check if expression is not constant."
  input DAE.Exp e;
  output Boolean nb;
protected
  Boolean b;
algorithm
  b := isConst(e);
  nb := boolNot(b);
end isNotConst;

public function isRelation "Returns true if expression is a relation"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExp)
    case (DAE.RELATION()) then true;
    else false;
  end match;
end isRelation;

public function isEventTriggeringFunctionExp
  input DAE.Exp inExp;
  output Boolean outB;
algorithm
  outB := matchcontinue(inExp)
    case (DAE.CALL(path = Absyn.IDENT("div"))) then true;
    case (DAE.CALL(path = Absyn.IDENT("mod"))) then true;
    case (DAE.CALL(path = Absyn.IDENT("rem"))) then true;
    case (DAE.CALL(path = Absyn.IDENT("ceil"))) then true;
    case (DAE.CALL(path = Absyn.IDENT("floor"))) then true;
    case (DAE.CALL(path = Absyn.IDENT("integer"))) then true;
    else false;
  end matchcontinue;
end isEventTriggeringFunctionExp;

public function isAddOrSub "returns true if operator is ADD or SUB"
  input DAE.Operator op;
  output Boolean res;
algorithm
  res := isAdd(op) or isSub(op);
end isAddOrSub;

public function isAdd "returns true if operator is ADD"
  input DAE.Operator op;
  output Boolean res;
algorithm
  res := match(op)
    case(DAE.ADD()) then true;
    case(DAE.ADD_ARR()) then true;
    else false;
  end match;
end isAdd;

public function isSub "returns true if operator is SUB"
  input DAE.Operator op;
  output Boolean res;
algorithm
  res := match(op)
    case(DAE.SUB()) then true;
    case(DAE.SUB_ARR()) then true;
    else false;
  end match;
end isSub;

public function isMulOrDiv "returns true if operator is MUL or DIV"
  input DAE.Operator op;
  output Boolean res := isMul(op) or isDiv(op);
end isMulOrDiv;

public function isMul "returns true if operator is MUL"
  input DAE.Operator op;
  output Boolean res;
algorithm
  res := match(op)
    case(DAE.MUL()) then true;
    case(DAE.MUL_ARR()) then true;
    else false;
  end match;
end isMul;

public function isDiv "returns true if operator is DIV"
  input DAE.Operator op;
  output Boolean res;
algorithm
  res := match(op)
    case(DAE.DIV()) then true;
    case(DAE.DIV_ARR()) then true;
    else false;
  end match;
end isDiv;

public function isDivBinary "returns true if BINARY is a/b"
  input DAE.Exp iExp;
  output Boolean res;
protected
  DAE.Operator op;
algorithm
  res := match(iExp)
         case(DAE.BINARY(_,op,_)) then isDiv(op);
         else false;
         end match;
end isDivBinary;

public function isFunCall "return true if expression is DAE.CALL(path=Absyn.IDENT(name))"
  input DAE.Exp iExp;
  input String name;
  output Boolean res;
algorithm
  res := match(iExp, name)
         local String name_;
          case(DAE.CALL(path=Absyn.IDENT(name_)),_) then name_ == name;
          else false;
         end match;
end isFunCall;

public function equalTypes ""
input DAE.Type t1,t2;
output Boolean b;
algorithm b := matchcontinue(t1,t2)
  local
    list<DAE.Var> vars1,vars2;
    Type ty1,ty2;
    DAE.Dimensions ad1,ad2;
    list<Integer> li1,li2;

  case(DAE.T_INTEGER(),DAE.T_INTEGER()) then true;
  case(DAE.T_REAL(),DAE.T_REAL()) then true;
  case(DAE.T_STRING(),DAE.T_STRING()) then true;
  case(DAE.T_BOOL(),DAE.T_BOOL()) then true;
  // BTH
  case(DAE.T_CLOCK(),DAE.T_CLOCK()) then true;

  case(DAE.T_COMPLEX(varLst = vars1), DAE.T_COMPLEX(varLst = vars2))
       then equalTypesComplexVars(vars1,vars2);

  case(DAE.T_ARRAY(ty1,ad1,_),DAE.T_ARRAY(ty2,ad2,_))
    equation
      li1 = List.map(ad1, dimensionSize);
      li2 = List.map(ad2, dimensionSize);
      true = List.isEqualOnTrue(li1,li2,intEq);
      true = equalTypes(ty1,ty2);
    then
      true;
  else false;
  end matchcontinue;
end equalTypes;

protected function equalTypesComplexVars ""
  input list<DAE.Var> inVars1,inVars2;
  output Boolean b;
algorithm
  b := matchcontinue(inVars1,inVars2)
    local
      DAE.Type t1,t2;
      String s1,s2;
      list<DAE.Var> vars1,vars2;

    case({},{}) then true;

    case(DAE.TYPES_VAR(name = s1, ty = t1)::vars1,DAE.TYPES_VAR(name = s2, ty = t2)::vars2)
      equation
        //print(" verify subvars: " + s1 + " and " + s2 + " to go: " + intString(listLength(vars1)) + " , " + intString(listLength(vars2))  + "\n");
        true = stringEq(s1,s2);
        //print(" types: " + Types.unparseType(t1) + " and " + Types.unparseType(t2) + "\n");
        true = equalTypes(t1,t2);
        //print(s1 + " and " + s2 + " EQUAL \n\n");
      then
        equalTypesComplexVars(vars1,vars2);

    else false;
  end matchcontinue;
end equalTypesComplexVars;

public function typeBuiltin
"Returns true if type is one of the builtin types."
  input DAE.Type inType;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inType)
    case (DAE.T_INTEGER()) then true;
    case (DAE.T_REAL()) then true;
    case (DAE.T_STRING()) then true;
    case (DAE.T_BOOL()) then true;
    // BTH
    case (DAE.T_CLOCK()) then true;
    else false;
  end matchcontinue;
end typeBuiltin;

public function isWholeDim ""
  input DAE.Subscript s;
  output Boolean b;
algorithm
  b := matchcontinue(s)
    case(DAE.WHOLEDIM()) then true;
    else false;
  end matchcontinue;
end isWholeDim;

public function isInt ""
  input DAE.Type it;
  output Boolean re;
algorithm
  re := matchcontinue(it)
    local
      Type t1,t2;
    case(DAE.T_ARRAY(ty=t2))
      then
        isReal(t2);
    case(DAE.T_INTEGER()) then true;
    else false;
  end matchcontinue;
end isInt;

public function isReal ""
  input DAE.Type it;
  output Boolean re;
algorithm
  re := matchcontinue(it)
    local
      Type t1,t2;
    case(DAE.T_ARRAY(ty=t2))
      then
        isReal(t2);
    case(DAE.T_REAL()) then true;
    else false;
  end matchcontinue;
end isReal;

public function isExpReal ""
  input DAE.Exp e;
  output Boolean re;
algorithm
  re := isReal(typeof(e));
end isExpReal;

public function isConstZeroLength
  "Return true if expression has zero-dimension"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExp)
    case DAE.ARRAY(array={}) then true;
    case DAE.MATRIX(matrix={}) then true;
    else false;
  end match;
end isConstZeroLength;

public function isConstFalse
"Return true if expression is false"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := match(inExp)
    case DAE.BCONST(false) then true;
    else false;
  end match;
end isConstFalse;

public function isConstTrue
"Return true if expression is true"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := match(inExp)
    case DAE.BCONST(true) then true;
    else false;
  end match;
end isConstTrue;

public function isConstOne
"Return true if expression is 1"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := match(inExp)
    local Real rval; Integer ival;

    // constant real 1.0
    case DAE.RCONST(rval) then realEq(rval, 1.0);
    // constant integer 1
    case DAE.ICONST(ival) then intEq(ival, 1);
    // anything else
    else false;
  end match;
end isConstOne;

public function isConstMinusOne
"Return true if expression is -1"
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := match(inExp)
    local Real rval; Integer ival;

    // is real -1.0
    case DAE.RCONST(rval) then realEq(rval, -1.0);
    // is integer -1
    case DAE.ICONST(ival) then intEq(ival, -1);
    // anything else
    else false;
  end match;
end isConstMinusOne;


public function containVectorFunctioncall
"Returns true if expression or subexpression is a
 functioncall that returns an array, otherwise false.
  Note: the der operator is represented as a
        function call but still return false."
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp)
    local
      DAE.Exp e1,e2,e,e3;
      Boolean res;
      list<Boolean> blst;
      list<DAE.Exp> elst,flatexplst;
      list<list<DAE.Exp>> explst;
      Option<DAE.Exp> optexp;

    // der is not a vector function
    case (DAE.CALL(path = Absyn.IDENT(name = "der"))) then false;

    // pre is not a vector function, adrpo: 2009-03-03 -> pre is also needed here!
    case (DAE.CALL(path = Absyn.IDENT(name = "pre"))) then false;

    // inStream and actualStream are not a vector function, adrpo: 2010-08-31 -> they are also needed here!
    case (DAE.CALL(path = Absyn.IDENT(name = "inStream"))) then false;
    case (DAE.CALL(path = Absyn.IDENT(name = "actualStream"))) then false;

    // a call that has an return array type returns true
    case (DAE.CALL(attr = DAE.CALL_ATTR(ty = DAE.T_ARRAY()))) then true;

    // any other call returns false
    case (DAE.CALL()) then false;

    // partial evaluation
    case (DAE.PARTEVALFUNCTION(expList = elst)) // stefan
      equation
        blst = List.map(elst,containVectorFunctioncall);
        res = Util.boolOrList(blst);
      then
        res;

    // binary operators, e1 has a vector function call
    case (DAE.BINARY(exp1 = e1))
      equation
        true = containVectorFunctioncall(e1);
      then
        true;
    // binary operators, e2 has a vector function call
    case (DAE.BINARY(exp2 = e2))
      equation
        true = containVectorFunctioncall(e2);
      then
        true;
    // unary operators
    case (DAE.UNARY(exp = e))
      equation
        res = containVectorFunctioncall(e);
      then
        res;
    // logical binary operators, e1 is a vector call
    case (DAE.LBINARY(exp1 = e1))
      equation
        true = containVectorFunctioncall(e1);
      then
        true;
    // logical binary operators, e2 is a vector call
    case (DAE.LBINARY(exp2 = e2))
      equation
        true = containVectorFunctioncall(e2);
      then
        true;
    // logical unary operators, e is a vector call
    case (DAE.LUNARY(exp = e))
      equation
        res = containVectorFunctioncall(e);
      then
        res;
    // relations e1 op e2, where e1 is a vector call
    case (DAE.RELATION(exp1 = e1))
      equation
        true = containVectorFunctioncall(e1);
      then
        true;
    // relations e1 op e2, where e2 is a vector call
    case (DAE.RELATION(exp2 = e2))
      equation
        true = containVectorFunctioncall(e2);
      then
        true;
    // if expression where the condition is a vector call
    case (DAE.IFEXP(expCond = e1))
      equation
        true = containVectorFunctioncall(e1);
      then
        true;
    // if expression where the then part is a vector call
    case (DAE.IFEXP(expThen = e2))
      equation
        true = containVectorFunctioncall(e2);
      then
        true;
    // if expression where the else part is a vector call
    case (DAE.IFEXP(expElse = e3))
      equation
        true = containVectorFunctioncall(e3);
      then
        true;
    // arrays
    case (DAE.ARRAY(array = elst))
      equation
        blst = List.map(elst, containVectorFunctioncall);
        res = Util.boolOrList(blst);
      then
        res;
    // matrixes
    case (DAE.MATRIX(matrix = explst))
      equation
        flatexplst = List.flatten(explst);
        blst = List.map(flatexplst, containVectorFunctioncall);
        res = Util.boolOrList(blst);
      then
        res;
    // ranges [e1:step:e2], where e1 is a vector call
    case (DAE.RANGE(start = e1))
      equation
        true = containVectorFunctioncall(e1);
      then
        true;
    // ranges [e1:step:e2], where e2 is a vector call
    case (DAE.RANGE(stop = e2))
      equation
        true = containVectorFunctioncall(e2);
      then
        true;
    // ranges [e1:step:e2], where step is a vector call
    case (DAE.RANGE(step = SOME(e)))
      equation
        true = containVectorFunctioncall(e);
      then
        true;
    // tuples return true all the time???!! adrpo: FIXME! TODO! is this really true?
    case (DAE.TUPLE(PR = elst))
      equation
        blst = List.map(elst, containVectorFunctioncall);
        res = Util.boolOrList(blst);
      then
        res;
    // cast
    case (DAE.CAST(exp = e))
      equation
        res = containVectorFunctioncall(e);
      then
        res;
    // size operator
    case (DAE.SIZE(exp = e1))
      equation
        true = containVectorFunctioncall(e1);
      then
        true;
    // size operator
    case (DAE.SIZE(sz = SOME(e2)))
      equation
        true = containVectorFunctioncall(e2);
      then
        true;
    // any other expressions return false
    else false;
  end matchcontinue;
end containVectorFunctioncall;

public function containFunctioncall
"Returns true if expression or subexpression
  is a functioncall, otherwise false.
  Note: the der and pre operators are represented
        as function calls but still returns false."
  input DAE.Exp inExp;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp)
    local
      DAE.Exp e1,e2,e,e3;
      Boolean res;
      list<Boolean> blst;
      list<DAE.Exp> elst,flatexplst;
      list<list<DAE.Exp>> explst;
      Option<DAE.Exp> optexp;

    // der(x) is not a function call
    case (DAE.CALL(path = Absyn.IDENT(name = "der"))) then false;

    // pre(x) is not a function call
    case (DAE.CALL(path = Absyn.IDENT(name = "pre"))) then false;

    // any other call is a function call
    case (DAE.CALL()) then true;

    // partial evaluation functions
    case (DAE.PARTEVALFUNCTION(expList = elst)) // stefan
      equation
        blst = List.map(elst,containFunctioncall);
        res = Util.boolOrList(blst);
      then
        res;

    // binary
    case (DAE.BINARY(exp1 = e1))
      equation
        true = containFunctioncall(e1);
      then
        true;

    case (DAE.BINARY(exp2 = e2))
      equation
        true = containFunctioncall(e2);
      then
        true;

    // unary
    case (DAE.UNARY(exp = e))
      equation
        res = containFunctioncall(e);
      then
        res;

    // logical binary
    case (DAE.LBINARY(exp1 = e1))
      equation
        true = containFunctioncall(e1);
      then
        true;

    case (DAE.LBINARY(exp2 = e2))
      equation
        true = containFunctioncall(e2);
      then
        true;

    // logical unary
    case (DAE.LUNARY(exp = e))
      equation
        res = containFunctioncall(e);
      then
        res;

    // relations
    case (DAE.RELATION(exp1 = e1))
      equation
        true = containFunctioncall(e1);
      then
        true;

    case (DAE.RELATION(exp2 = e2))
      equation
        true = containFunctioncall(e2);
      then
        true;

    // if expressions
    case (DAE.IFEXP(expCond = e1))
      equation
        true = containFunctioncall(e1);
      then
        true;

    case (DAE.IFEXP(expThen = e2))
      equation
        true = containFunctioncall(e2);
      then
        true;

    case (DAE.IFEXP(expElse = e3))
      equation
        true = containFunctioncall(e3);
      then
        true;

    // arrays
    case (DAE.ARRAY(array = elst))
      equation
        blst = List.map(elst, containFunctioncall);
        res = Util.boolOrList(blst);
      then
        res;

    // matrix
    case (DAE.MATRIX(matrix = explst))
      equation
        flatexplst = List.flatten(explst);
        blst = List.map(flatexplst, containFunctioncall);
        res = Util.boolOrList(blst);
      then
        res;

    // ranges
    case (DAE.RANGE(start = e1))
      equation
        true = containFunctioncall(e1);
      then
        true;

    case (DAE.RANGE(stop = e2))
      equation
        true = containFunctioncall(e2);
      then
        true;

    case (DAE.RANGE(step = SOME(e)))
      equation
        true = containFunctioncall(e);
      then
        true;

    // tuples return true all the time???!! adrpo: FIXME! TODO! is this really true?
    case (DAE.TUPLE(PR = elst))
      equation
        blst = List.map(elst, containVectorFunctioncall);
        res = Util.boolOrList(blst);
      then
        res;

    // cast
    case (DAE.CAST(exp = e))
      equation
        res = containFunctioncall(e);
      then
        res;

    // size
    case (DAE.SIZE(exp = e1))
      equation
        true = containFunctioncall(e1);
      then
        true;

    case (DAE.SIZE(sz = SOME(e2)))
      equation
        true = containFunctioncall(e2);
      then
        true;

    // anything else
    else false;

  end matchcontinue;
end containFunctioncall;

public function expIntOrder "Function: expIntOrder
This function takes a list of Exp, assumes they are all ICONST
and checks wheter the ICONST are in order."
  input Integer expectedValue;
  input list<DAE.Exp> integers;
  output Boolean ob;
algorithm
  ob := matchcontinue(expectedValue,integers)
    local
      list<DAE.Exp> expl;
      Integer x1,x2;
      Boolean b;
    case(_,{}) then true;
    case(x1, DAE.ICONST(x2)::expl)
      equation
        true = intEq(x1, x2);
        b = expIntOrder(x1+1,expl);
      then
        b;
    else false;
  end matchcontinue;
end expIntOrder;

public function isArray "returns true if expression is an array.
"
  input DAE.Exp inExp;
  output Boolean outB;
algorithm
  outB := match(inExp)
    case(DAE.ARRAY()) then true;
    case(DAE.UNARY(operator=DAE.UMINUS_ARR(),exp=DAE.ARRAY())) then true;
    else false;
  end match;
end isArray;

public function isMatrix "returns true if expression is an matrix.
"
  input DAE.Exp inExp;
  output Boolean outB;
algorithm
  outB := match(inExp)
    case(DAE.MATRIX()) then true;
    case(DAE.UNARY(operator=DAE.UMINUS_ARR(),exp=DAE.MATRIX())) then true;
    else false;
  end match;
end isMatrix;

public function isVector
  "Returns true if the expression is a vector, i.e. an array with one dimension,
   otherwise false."
  input DAE.Exp inExp;
  output Boolean outIsVector;
algorithm
  outIsVector := match(inExp)
    // Nested arrays are not vectors.
    case DAE.ARRAY(ty = DAE.T_ARRAY(ty = DAE.T_ARRAY())) then false;
    // Non-nested array with one dimension is a vector.
    case DAE.ARRAY(ty = DAE.T_ARRAY(dims = {_})) then true;
    else false;
  end match;
end isVector;

public function isUnary
  "Returns true if expression is an unary."
  input DAE.Exp inExp;
  output Boolean outB;
algorithm
  outB:= match(inExp)
    case(DAE.UNARY()) then true;
    else false;
  end match;
end isUnary;

public function isCref
  "Returns true if the given expression is a component reference,
   otherwise false."
  input DAE.Exp inExp;
  output Boolean outIsCref;
algorithm
  outIsCref := match(inExp)
    case DAE.CREF() then true;
    else false;
  end match;
end isCref;

public function isCall
  "Returns true if the given expression is a function call,
   otherwise false."
  input DAE.Exp inExp;
  output Boolean outIsCall;
algorithm
  outIsCall := match(inExp)
    case DAE.CALL() then true;
    else false;
  end match;
end isCall;

public function isNotCref
  "Returns true if the given expression is a not component reference,
   otherwise false."
  input DAE.Exp inExp;
  output Boolean outIsCref;
algorithm
  outIsCref := match(inExp)
    case DAE.CREF() then false;
    else true;
  end match;
end isNotCref;

public function isCrefArray
  "Checks whether a cref is an array or not.
"
  input DAE.Exp inExp;
  output Boolean outIsArray;
algorithm
  outIsArray := match(inExp)
    case(DAE.CREF(ty = DAE.T_ARRAY())) then true;
    else false;
  end match;
end isCrefArray;

public function isCrefScalar
  "Checks whether an expression is a scalar cref or not."
  input DAE.Exp inExp;
  output Boolean isScalar;
algorithm
  isScalar := matchcontinue(inExp)
    local
      ComponentRef cr;
      Boolean b;

    case DAE.CREF(ty = DAE.T_ARRAY())
      equation
        cr = expCref(inExp);
        b = ComponentReference.crefHasScalarSubscripts(cr);
      then
        b;

    case DAE.CREF() then true;

    else false;
  end matchcontinue;
end isCrefScalar;

public function isTuple
  "Returns true if the given expression is a tuple,
   otherwise false."
  input DAE.Exp inExp;
  output Boolean outIsTuple;
algorithm
  outIsTuple := match(inExp)
    case DAE.TUPLE() then true;
    else false;
  end match;
end isTuple;

public function isScalarConst
  "Returns true if the given expression is a scalar constant, otherwise false."
  input DAE.Exp inExp;
  output Boolean outIsScalar;
algorithm
  outIsScalar := match(inExp)
    case DAE.ICONST() then true;
    case DAE.RCONST() then true;
    case DAE.SCONST() then true;
    case DAE.BCONST() then true;
    case DAE.ENUM_LITERAL() then true;
    else false;
  end match;
end isScalarConst;

public function expIsPositive "Returns true if an expression is positive,
Returns true in the following cases:
constant >= 0

See also isPositiveOrZero.
"
  input DAE.Exp e;
  output Boolean res;
algorithm
  res :=isPositiveOrZero(e) and not isZero(e);
end expIsPositive;

public function isEven "returns true if const expression is even"
  input DAE.Exp e;
  output Boolean even;
algorithm
  even := match(e)
    local
      Integer i;
      Real r;
      DAE.Exp exp;

    case(DAE.ICONST(i)) then intMod(i,2) == 0;
    case(DAE.RCONST(r)) then realMod(r, 2.0) == 0.0;
    case(DAE.CAST(exp = exp)) then isEven(exp);
    else false;
  end match;
end isEven;

public function isOdd "returns true if const expression is odd"
  input DAE.Exp e;
  output Boolean even;
algorithm
  even := match(e)
    local
      Integer i;
      Real r;
      DAE.Exp exp;

    case(DAE.ICONST(i)) then intMod(i,2) == 1;
    case(DAE.RCONST(r)) then realMod(r, 2.0) == 1.0;
    case(DAE.CAST(exp = exp)) then isOdd(exp);
    else false;
  end match;
end isOdd;

public function isIntegerOrReal "Returns true if Type is Integer or Real"
input DAE.Type tp;
output Boolean res;
algorithm
  res := match(tp)
    case DAE.T_REAL() then  true;
    case DAE.T_INTEGER() then true;
    else false;
  end match;
end isIntegerOrReal;

public function expEqual
  "Returns true if the two expressions are equal, otherwise false."
  input DAE.Exp inExp1;
  input DAE.Exp inExp2;
  output Boolean outEqual;
algorithm
  // Return true if the references are the same.
  if referenceEq(inExp1, inExp2) then
    outEqual := true;
    return;
  end if;

  // Return false if the expressions are not of the same type.
  if valueConstructor(inExp1) <> valueConstructor(inExp2) then
    outEqual := false;
    return;
  end if;

  // Otherwise, check if the expressions are equal or not.
  // Since the expressions have already been verified to be of the same type
  // above we can match on only one of them to allow the pattern matching to
  // optimize this to jump directly to the correct case.
  outEqual := match(inExp1)
    local
      Integer i;
      Real r;
      String s;
      Boolean b;
      Absyn.Path p;
      DAE.Exp e, e1, e2;
      Option<DAE.Exp> oe;
      list<DAE.Exp> expl;
      list<list<DAE.Exp>> mexpl;
      DAE.Operator op;
      DAE.ComponentRef cr;
      DAE.Type ty;

    case DAE.ICONST()
      algorithm
        DAE.ICONST(integer = i) := inExp2;
      then
        inExp1.integer == i;

    case DAE.RCONST()
      algorithm
        DAE.RCONST(real = r) := inExp2;
      then
        inExp1.real == r;

    case DAE.SCONST()
      algorithm
        DAE.SCONST(string = s) := inExp2;
      then
        inExp1.string == s;

    case DAE.BCONST()
      algorithm
        DAE.BCONST(bool = b) := inExp2;
      then
        inExp1.bool == b;

    case DAE.ENUM_LITERAL()
      algorithm
        DAE.ENUM_LITERAL(name = p) := inExp2;
      then
        Absyn.pathEqual(inExp1.name, p);

    case DAE.CREF()
      algorithm
        DAE.CREF(componentRef = cr) := inExp2;
      then
        ComponentReference.crefEqual(inExp1.componentRef, cr);

    case DAE.ARRAY()
      algorithm
        DAE.ARRAY(ty = ty, array = expl) := inExp2;
      then
        valueEq(inExp1.ty, ty) and expEqualList(inExp1.array, expl);

    case DAE.MATRIX()
      algorithm
        DAE.MATRIX(ty = ty, matrix = mexpl) := inExp2;
      then
        valueEq(inExp1.ty, ty) and expEqualListList(inExp1.matrix, mexpl);

    case DAE.BINARY()
      algorithm
        DAE.BINARY(exp1 = e1, operator = op, exp2 = e2) := inExp2;
      then
        operatorEqual(inExp1.operator, op) and
        expEqual(inExp1.exp1, e1) and
        expEqual(inExp1.exp2, e2);

    case DAE.LBINARY()
      algorithm
        DAE.LBINARY(exp1 = e1, operator = op, exp2 = e2) := inExp2;
      then
        operatorEqual(inExp1.operator, op) and
        expEqual(inExp1.exp1, e1) and
        expEqual(inExp1.exp2, e2);

    case DAE.UNARY()
      algorithm
        DAE.UNARY(exp = e, operator = op) := inExp2;
      then
        operatorEqual(inExp1.operator, op) and
        expEqual(inExp1.exp, e);

    case DAE.LUNARY()
      algorithm
        DAE.LUNARY(exp = e, operator = op) := inExp2;
      then
        operatorEqual(inExp1.operator, op) and
        expEqual(inExp1.exp, e);

    case DAE.RELATION()
      algorithm
        DAE.RELATION(exp1 = e1, operator = op, exp2 = e2) := inExp2;
      then
        operatorEqual(inExp1.operator, op) and
        expEqual(inExp1.exp1, e1) and
        expEqual(inExp1.exp2, e2);

    case DAE.IFEXP()
      algorithm
        DAE.IFEXP(expCond = e, expThen = e1, expElse = e2) := inExp2;
      then
        expEqual(inExp1.expCond, e) and
        expEqual(inExp1.expThen, e1) and
        expEqual(inExp1.expElse, e2);

    case DAE.CALL()
      algorithm
        DAE.CALL(path = p, expLst = expl) := inExp2;
      then
        Absyn.pathEqual(inExp1.path, p) and
        expEqualList(inExp1.expLst, expl);

    case DAE.RECORD()
      algorithm
        DAE.RECORD(path = p, exps = expl) := inExp2;
      then
        Absyn.pathEqual(inExp1.path, p) and
        expEqualList(inExp1.exps, expl);

    case DAE.PARTEVALFUNCTION()
      algorithm
        DAE.PARTEVALFUNCTION(path = p, expList = expl) := inExp2;
      then
        Absyn.pathEqual(inExp1.path, p) and
        expEqualList(inExp1.expList, expl);

    case DAE.RANGE()
      algorithm
        DAE.RANGE(start = e1, step = oe, stop = e2) := inExp2;
      then
        expEqual(inExp1.start, e1) and
        expEqual(inExp1.stop, e2) and
        expEqualOpt(inExp1.step, oe);

    case DAE.TUPLE()
      algorithm
        DAE.TUPLE(PR = expl) := inExp2;
      then
        expEqualList(inExp1.PR, expl);

    case DAE.CAST()
      algorithm
        DAE.CAST(ty = ty, exp = e) := inExp2;
      then
        valueEq(inExp1.ty, ty) and expEqual(inExp1.exp, e);

    case DAE.ASUB()
      algorithm
        DAE.ASUB(exp = e, sub = expl) := inExp2;
      then
        expEqual(inExp1.exp, e) and expEqualList(inExp1.sub, expl);

    case DAE.SIZE()
      algorithm
        DAE.SIZE(exp = e, sz = oe) := inExp2;
      then
        expEqual(inExp1.exp, e) and expEqualOpt(inExp1.sz, oe);

    case DAE.REDUCTION()
      // Reductions contain too much information to compare in a sane manner.
      then valueEq(inExp1, inExp2);

    case DAE.LIST()
      algorithm
        DAE.LIST(valList = expl) := inExp2;
      then
        expEqualList(inExp1.valList, expl);

    case DAE.CONS()
      algorithm
        DAE.CONS(car = e1, cdr = e2) := inExp2;
      then
        expEqual(inExp1.car, e1) and expEqual(inExp1.cdr, e2);

    case DAE.META_TUPLE()
      algorithm
        DAE.META_TUPLE(listExp = expl) := inExp2;
      then
        expEqualList(inExp1.listExp, expl);

    case DAE.META_OPTION()
      algorithm
        DAE.META_OPTION(exp = oe) := inExp2;
      then
        expEqualOpt(inExp1.exp, oe);

    case DAE.METARECORDCALL()
      algorithm
        DAE.METARECORDCALL(path = p, args = expl) := inExp2;
      then
        Absyn.pathEqual(inExp1.path, p) and expEqualList(inExp1.args, expl);

    case DAE.MATCHEXPRESSION()
      then valueEq(inExp1, inExp2);

    case DAE.BOX()
      algorithm
        DAE.BOX(exp = e) := inExp2;
      then
        expEqual(inExp1.exp, e);

    case DAE.UNBOX()
      algorithm
        DAE.UNBOX(exp = e) := inExp2;
      then
        expEqual(inExp1.exp, e);

    case DAE.SHARED_LITERAL()
      algorithm
        DAE.SHARED_LITERAL(index = i) := inExp2;
      then
        inExp1.index == i;

    else false;
  end match;
end expEqual;

protected function expEqualOpt
  input Option<DAE.Exp> inExp1;
  input Option<DAE.Exp> inExp2;
  output Boolean outEqual;
protected
  DAE.Exp e1, e2;
algorithm
  outEqual := match(inExp1, inExp2)
    case (NONE(), NONE()) then true;
    case (SOME(e1), SOME(e2)) then expEqual(e1, e2);
    else false;
  end match;
end expEqualOpt;

protected function expEqualList
  input list<DAE.Exp> inExpl1;
  input list<DAE.Exp> inExpl2;
  output Boolean outEqual;
protected
  DAE.Exp e2;
  list<DAE.Exp> rest_expl2 := inExpl2;
algorithm
  // Check that the lists have the same length, otherwise they can't be equal.
  if listLength(inExpl1) <> listLength(inExpl2) then
    outEqual := false;
    return;
  end if;

  for e1 in inExpl1 loop
    e2 :: rest_expl2 := rest_expl2;

    // Return false if the expressions are not equal.
    if not expEqual(e1, e2) then
      outEqual := false;
      return;
    end if;
  end for;

  outEqual := true;
end expEqualList;

protected function expEqualListList
  input list<list<DAE.Exp>> inExpl1;
  input list<list<DAE.Exp>> inExpl2;
  output Boolean outEqual;
protected
  list<DAE.Exp> expl2;
  list<list<DAE.Exp>> rest_expl2 := inExpl2;
algorithm
  // Check that the lists have the same length, otherwise they can't be equal.
  if listLength(inExpl1) <> listLength(inExpl2) then
    outEqual := false;
    return;
  end if;

  for expl1 in inExpl1 loop
    expl2 :: rest_expl2 := rest_expl2;

    // Return false if the expression lists are not equal.
    if not expEqualList(expl1, expl2) then
      outEqual := false;
      return;
    end if;
  end for;

  outEqual := true;
end expEqualListList;

public function expStructuralEqual
"Returns true if the two expressions are structural equal. This means
  only the componentreference can be different"
  input DAE.Exp inExp1;
  input DAE.Exp inExp2;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inExp1,inExp2)
    local
      Integer i1,i2;
      String s1,s2;
      Boolean b,b1,b2,res;
      DAE.Exp e11,e12,e21,e22,e1,e2,e13,e23;
      Operator op1,op2;
      Absyn.Path path1,path2;
      list<DAE.Exp> expl1,expl2;
      list<list<Exp>> explstlst1,explstlst2;
      Type tp1,tp2;
      Real r1,r2;
      Absyn.Path enum1, enum2;
      ComponentRef cr1,cr2;
      list<DAE.Exp> ae1,ae2;
    case (DAE.ICONST(integer = i1),DAE.ICONST(integer = i2)) then (i1 == i2);
    case (DAE.UNARY(DAE.UMINUS(_),exp=DAE.ICONST(integer = i1)),DAE.ICONST(integer = i2))
      equation
        i1 = - i1;
      then (i1 == i2);
    case (DAE.ICONST(integer = i1),DAE.UNARY(DAE.UMINUS(_),exp=DAE.ICONST(integer = i2)))
      equation
        i2 = - i2;
      then (i1 == i2);
    case (DAE.RCONST(real = r1),DAE.RCONST(real = r2)) then (r1 == r2);
    case (DAE.UNARY(DAE.UMINUS(_),exp=DAE.RCONST(real = r1)),DAE.RCONST(real = r2))
      equation
        r1 = - r1;
      then (r1 == r2);
    case (DAE.RCONST(real = r1),DAE.UNARY(DAE.UMINUS(_),exp=DAE.RCONST(real = r2)))
      equation
        r2 = - r2;
      then (r1 == r2);
    case (DAE.SCONST(string = s1),DAE.SCONST(string = s2)) then stringEq(s1, s2);
    case (DAE.BCONST(bool = b1),DAE.BCONST(bool = b2)) then boolEq(b1, b2);
    case (DAE.ENUM_LITERAL(name = enum1), DAE.ENUM_LITERAL(name = enum2)) then Absyn.pathEqual(enum1, enum2);
    case (DAE.CREF(),DAE.CREF()) then true;

    // binary ops
    case (DAE.BINARY(exp1 = e11,operator = op1,exp2 = e12),DAE.BINARY(exp1 = e21,operator = op2,exp2 = e22))
      equation
        b = operatorEqual(op1, op2);
        b = if b then expStructuralEqual(e11, e21) else b;
        b = if b then expStructuralEqual(e12, e22) else b;
      then
        b;

    // logical binary ops
    case (DAE.LBINARY(exp1 = e11,operator = op1,exp2 = e12),
          DAE.LBINARY(exp1 = e21,operator = op2,exp2 = e22))
      equation
        b = operatorEqual(op1, op2);
        b = if b then expStructuralEqual(e11, e21) else b;
        b = if b then expStructuralEqual(e12, e22) else b;
      then
        b;

    // unary ops
    case (DAE.UNARY(operator = op1,exp = e1),DAE.UNARY(operator = op2,exp = e2))
      equation
        b = operatorEqual(op1, op2);
        b = if b then expStructuralEqual(e1, e2) else b;
      then
        b;

    // logical unary ops
    case (DAE.LUNARY(operator = op1,exp = e1),DAE.LUNARY(operator = op2,exp = e2))
      equation
        b = operatorEqual(op1, op2);
        b = if b then expStructuralEqual(e1, e2) else b;
      then
        b;

    // relational ops
    case (DAE.RELATION(exp1 = e11,operator = op1,exp2 = e12),DAE.RELATION(exp1 = e21,operator = op2,exp2 = e22))
      equation
        b = operatorEqual(op1, op2);
        b = if b then expStructuralEqual(e11, e21) else b;
        b = if b then expStructuralEqual(e12, e22) else b;
      then
        b;

    // if expressions
    case (DAE.IFEXP(expCond = e11,expThen = e12,expElse = e13),DAE.IFEXP(expCond = e21,expThen = e22,expElse = e23))
      equation
        b = expStructuralEqual(e11, e21);
        b = if b then expStructuralEqual(e12, e22) else b;
        b = if b then expStructuralEqual(e13, e23) else b;
      then
        b;

    // function calls
    case (DAE.CALL(path = path1,expLst = expl1),DAE.CALL(path = path2,expLst = expl2))
      equation
        b = Absyn.pathEqual(path1, path2);
        b = if b then expStructuralEqualList(expl1, expl2) else b;
      then
        b;
    case (DAE.RECORD(path = path1,exps = expl1),DAE.RECORD(path = path2,exps = expl2))
      equation
        b = Absyn.pathEqual(path1, path2);
        b = if b then expStructuralEqualList(expl1, expl2) else b;
      then
        b;
    // partially evaluated functions
    case (DAE.PARTEVALFUNCTION(path = path1,expList = expl1),DAE.PARTEVALFUNCTION(path = path2,expList = expl2))
      equation
        b = Absyn.pathEqual(path1, path2);
        b = if b then expStructuralEqualList(expl1, expl2) else b;
      then
        b;

    // arrays
    case (DAE.ARRAY(ty = tp1,array = expl1),DAE.ARRAY(ty = tp2,array = expl2))
      equation
        b = valueEq(tp1, tp2);
        b = if b then expStructuralEqualList(expl1, expl2) else b;
      then
        b;

    // matrix
    case (DAE.MATRIX(matrix = explstlst1), DAE.MATRIX(matrix = explstlst2))
      then
        expStructuralEqualListLst(explstlst1,explstlst2);

    // ranges [start:stop]
    case (DAE.RANGE(start = e11,step = NONE(),stop = e13),
          DAE.RANGE(start = e21,step = NONE(),stop = e23))
      equation
        b = expStructuralEqual(e11, e21);
        b = if b then expStructuralEqual(e13, e23) else b;
      then
        b;

    // ranges [start:step:stop]
    case (DAE.RANGE(start = e11,step = SOME(e12),stop = e13),
          DAE.RANGE(start = e21,step = SOME(e22),stop = e23))
      equation
        b = expStructuralEqual(e11, e21);
        b = if b then expStructuralEqual(e12, e22) else b;
        b = if b then expStructuralEqual(e13, e23) else b;
      then
        b;

    // tuples
    case (DAE.TUPLE(PR = expl1),DAE.TUPLE(PR = expl2))
      then expStructuralEqualList(expl1, expl2);

    // casting
    case (DAE.CAST(ty = tp1,exp = e1),DAE.CAST(ty = tp2,exp = e2))
      equation
        b = valueEq(tp1, tp2);
        b = if b then expStructuralEqual(e1, e2) else b;
      then
        b;

    // array subscripts
    case (DAE.ASUB(exp = e1,sub = ae1),DAE.ASUB(sub = ae2))
      equation
        b = expStructuralEqual(e1, e1);
        b = if b then expStructuralEqualList(ae1, ae2) else b;
      then
        b;

    // size(a)
    case (DAE.SIZE(exp = e1,sz = NONE()),DAE.SIZE(exp = e2,sz = NONE()))
      then expStructuralEqual(e1, e2);

    // size(a, dim)
    case (DAE.SIZE(exp = e1,sz = SOME(e11)),DAE.SIZE(exp = e2,sz = SOME(e22)))
      equation
        b = expStructuralEqual(e1, e2);
        b = if b then expStructuralEqual(e11, e22) else b;
      then
        b;

    // metamodeling code
    case (DAE.CODE(),DAE.CODE())
      equation
        Debug.trace("exp_equal on CODE not impl.\n");
      then
        false;

    case (DAE.REDUCTION(),DAE.REDUCTION())
      equation
        // Reductions contain too much information to compare equality in a sane manner
        res = valueEq(inExp1,inExp2);
      then
        res;

    // end id
    /*// everything else failed, try structural equality
    case (e1,e2)
      equation
        equality(e1 = e2);
      then true;
    case (e1,e2)
      equation
        failure(equality(e1 = e2));
      then false;
    */
    // not equal
    case (DAE.LIST(valList = expl1),DAE.LIST(valList = expl2))
      then expStructuralEqualList(expl1, expl2);

    case (DAE.CONS(car = e11,cdr = e12),
          DAE.CONS(car = e21,cdr = e22))
      equation
        b = expStructuralEqual(e11, e21);
        b = if b then expStructuralEqual(e12, e22) else b;
      then
        b;

    case (DAE.META_TUPLE(listExp = expl1),DAE.META_TUPLE(listExp = expl2))
      then expStructuralEqualList(expl1, expl2);

    case (DAE.META_OPTION(exp = NONE()),
          DAE.META_OPTION(exp = NONE()))
      then true;

    case (DAE.META_OPTION(exp = SOME(e1)),
          DAE.META_OPTION(exp = SOME(e2)))
      then expStructuralEqual(e1, e2);

    case (DAE.METARECORDCALL(path = path1,args = expl1),DAE.METARECORDCALL(path = path2,args = expl2))
      equation
        b = Absyn.pathEqual(path1, path2);
        b = if b then expStructuralEqualList(expl1, expl2) else b;
      then
        b;

    case (e1 as DAE.MATCHEXPRESSION(),
          e2 as DAE.MATCHEXPRESSION())
      then valueEq(e1,e2);

    case (DAE.BOX(e1),DAE.BOX(e2))
      then expStructuralEqual(e1, e2);

    case (DAE.UNBOX(exp=e1),DAE.UNBOX(exp=e2))
      then expStructuralEqual(e1, e2);

    case (DAE.SHARED_LITERAL(index=i1),DAE.SHARED_LITERAL(index=i2)) then intEq(i1,i2);

    else false;
  end match;
end expStructuralEqual;

public function expStructuralEqualList
"Returns true if the two lists of expressions are structural equal."
  input list<DAE.Exp> inExp1;
  input list<DAE.Exp> inExp2;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp1,inExp2)
    local
      DAE.Exp e1,e2;
      list<DAE.Exp> es1,es2;
      Boolean b;
    case ({},{}) then true;
    case (e1::es1,e2::es2)
      equation
        true = expStructuralEqual(e1,e2);
      then
        expStructuralEqualList(es1, es2);
    else
      then
        false;
  end matchcontinue;
end expStructuralEqualList;

protected function expStructuralEqualListLst
"Returns true if the two lists of lists of expressions are structural equal."
  input list<list<DAE.Exp>> inExp1;
  input list<list<DAE.Exp>> inExp2;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp1,inExp2)
    local
      list<DAE.Exp> e1,e2;
      list<list<DAE.Exp>> es1,es2;
      Boolean b;
    case ({},{}) then true;
    case (e1::es1,e2::es2)
      equation
        true = expStructuralEqualList(e1,e2);
      then
        expStructuralEqualListLst(es1, es2);
    else
      then
        false;
  end matchcontinue;
end expStructuralEqualListLst;

public function expContains
"Returns true if first expression contains the
  second one as a sub expression. Only component
  references or der(componentReference) can be
  checked so far."
  input DAE.Exp inExp1;
  input DAE.Exp inExp2;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inExp1,inExp2)
    local
      Integer i;
      DAE.Exp cr,c1,c2,e1,e2,e,c,t,f,cref;
      String s,str;
      Boolean res,res1,res2,res3;
      list<Boolean> reslist;
      list<DAE.Exp> explist,args;
      list<list<DAE.Exp>> expl;
      ComponentRef cr1,cr2;
      Operator op;
      Absyn.Path fcn;

    case (DAE.ICONST(),_) then false;
    case (DAE.RCONST(),_) then false;
    case (DAE.SCONST(),_) then false;
    case (DAE.BCONST(),_) then false;
    case (DAE.ENUM_LITERAL(), _) then false;
    case (DAE.ARRAY(array = explist),cr)
      equation
        reslist = List.map1(explist, expContains, cr);
        res = Util.boolOrList(reslist);
      then
        res;

    case (DAE.MATRIX(matrix = expl),cr)
      equation
        res = Util.boolOrList(List.map(List.map1List(expl, expContains, cr),Util.boolOrList));
      then
        res;

    case ((DAE.CREF(componentRef = cr1)),(DAE.CREF(componentRef = cr2)))
      equation
        res = ComponentReference.crefEqual(cr1, cr2);
      then
        res;

    case ((DAE.CREF()),_ ) then false;

    case (DAE.BINARY(exp1 = e1,exp2 = e2),cr )
      equation
        res1 = expContains(e1, cr);
        res2 = expContains(e2, cr);
        res = boolOr(res1, res2);
      then
        res;

    case (DAE.UNARY(exp = e),cr)
      equation
        res = expContains(e, cr);
      then
        res;

    case (DAE.LBINARY(exp1 = e1,exp2 = e2),cr)
      equation
        res1 = expContains(e1, cr);
        res2 = expContains(e2, cr);
        res = boolOr(res1, res2);
      then
        res;

    case (DAE.LUNARY(exp = e),cr )
      equation
        res = expContains(e, cr);
      then
        res;

    case (DAE.RELATION(exp1 = e1,exp2 = e2),cr)
      equation
        res1 = expContains(e1, cr);
        res2 = expContains(e2, cr);
        res = boolOr(res1, res2);
      then
        res;

    case (DAE.IFEXP(expCond = c,expThen = t,expElse = f),cr)
      equation
        res1 = expContains(c, cr);
        res2 = expContains(t, cr);
        res3 = expContains(f, cr);
        res = Util.boolOrList({res1,res2,res3});
      then
        res;

    case(DAE.CALL(path=Absyn.IDENT(name="der"),expLst={DAE.CREF(cr1,_)}),
         DAE.CALL(path=Absyn.IDENT(name="der"),expLst={DAE.CREF(cr2,_)}))
      equation
        res = ComponentReference.crefEqual(cr1,cr2);
      then res;

    // pre(v) does not contain variable v
    case (DAE.CALL(path = Absyn.IDENT(name = "pre"),expLst = {_}),_) then false;

    // special rule for no arguments
    case (DAE.CALL(expLst = {}),_) then false;

    // general case for arguments
    case (DAE.CALL(expLst = args),(cr as DAE.CREF()))
      equation
        reslist = List.map1(args, expContains, cr);
        res = Util.boolOrList(reslist);
      then
        res;

    case (DAE.PARTEVALFUNCTION(expList = args),(cr as DAE.CREF()))
      equation
        reslist = List.map1(args, expContains, cr);
        res = Util.boolOrList(reslist);
      then
        res;

    case (DAE.CAST(ty = DAE.T_REAL(),exp = DAE.ICONST()),_ ) then false;

    case (DAE.CAST(ty = DAE.T_REAL(),exp = e),cr )
      equation
        res = expContains(e, cr);
      then
        res;

    case (DAE.ASUB(exp = e,sub = explist),cr)
      equation
        reslist = List.map1(explist, expContains, cr);
        res1 = Util.boolOrList(reslist);
        res = expContains(e, cr);
        res = Util.boolOrList({res1,res});
      then
        res;

    case (DAE.REDUCTION(expr = e), cr)
      equation
        res = expContains(e, cr);
      then
        res;

    case (e,_)
      equation
        true = Flags.isSet(Flags.FAILTRACE);
        Debug.trace("- Expression.expContains failed\n");
        s = ExpressionDump.printExpStr(e);
        str = stringAppendList({"exp = ",s});
        Debug.traceln(str);
      then
        fail();
  end matchcontinue;
end expContains;

public function containsExp
"Author BZ 2008-06 same as expContains, but reversed."
  input DAE.Exp inExp1;
  input DAE.Exp inExp2;
  output Boolean outBoolean;
algorithm
  outBoolean:= expContains(inExp2,inExp1);
end containsExp;

public function isExpCrefOrIfExp
"Returns true if expression is a componentRef or an if expression"
  input DAE.Exp e;
  output Boolean res;
algorithm
  res := matchcontinue(e)
    case(DAE.CREF(_,_)) then true;
    case(DAE.IFEXP(_,_,_)) then true;
    else false;
  end matchcontinue;
end isExpCrefOrIfExp;

public function operatorEqual
"Helper function to expEqual."
  input DAE.Operator inOperator1;
  input DAE.Operator inOperator2;
  output Boolean outBoolean;
algorithm
  outBoolean := matchcontinue (inOperator1,inOperator2)
    local
      Boolean res;
      Absyn.Path p1,p2;

    case (DAE.ADD(),DAE.ADD()) then true;
    case (DAE.SUB(),DAE.SUB()) then true;
    case (DAE.MUL(),DAE.MUL()) then true;
    case (DAE.DIV(),DAE.DIV()) then true;
    case (DAE.POW(),DAE.POW()) then true;
    case (DAE.UMINUS(),DAE.UMINUS()) then true;
    case (DAE.UMINUS_ARR(),DAE.UMINUS_ARR()) then true;
    case (DAE.ADD_ARR(),DAE.ADD_ARR()) then true;
    case (DAE.SUB_ARR(),DAE.SUB_ARR()) then true;
    case (DAE.MUL_ARR(),DAE.MUL_ARR()) then true;
    case (DAE.DIV_ARR(),DAE.DIV_ARR()) then true;
    case (DAE.MUL_ARRAY_SCALAR(),DAE.MUL_ARRAY_SCALAR()) then true;
    case (DAE.ADD_ARRAY_SCALAR(),DAE.ADD_ARRAY_SCALAR()) then true;
    case (DAE.SUB_SCALAR_ARRAY(),DAE.SUB_SCALAR_ARRAY()) then true;
    case (DAE.MUL_SCALAR_PRODUCT(),DAE.MUL_SCALAR_PRODUCT()) then true;
    case (DAE.MUL_MATRIX_PRODUCT(),DAE.MUL_MATRIX_PRODUCT()) then true;
    case (DAE.DIV_SCALAR_ARRAY(),DAE.DIV_SCALAR_ARRAY()) then true;
    case (DAE.DIV_ARRAY_SCALAR(),DAE.DIV_ARRAY_SCALAR()) then true;
    case (DAE.POW_SCALAR_ARRAY(),DAE.POW_SCALAR_ARRAY()) then true;
    case (DAE.POW_ARRAY_SCALAR(),DAE.POW_ARRAY_SCALAR()) then true;
    case (DAE.POW_ARR(),DAE.POW_ARR()) then true;
    case (DAE.POW_ARR2(),DAE.POW_ARR2()) then true;
    case (DAE.AND(),DAE.AND()) then true;
    case (DAE.OR(),DAE.OR()) then true;
    case (DAE.NOT(),DAE.NOT()) then true;
    case (DAE.LESS(),DAE.LESS()) then true;
    case (DAE.LESSEQ(),DAE.LESSEQ()) then true;
    case (DAE.GREATER(),DAE.GREATER()) then true;
    case (DAE.GREATEREQ(),DAE.GREATEREQ()) then true;
    case (DAE.EQUAL(),DAE.EQUAL()) then true;
    case (DAE.NEQUAL(),DAE.NEQUAL()) then true;
    case (DAE.USERDEFINED(fqName = p1),DAE.USERDEFINED(fqName = p2))
      equation
        res = Absyn.pathEqual(p1, p2);
      then
        res;
    else false;
  end matchcontinue;
end operatorEqual;

public function arrayContainZeroDimension
  "Checks if one of the dimensions in a list is zero."
  input list<DAE.Dimension> inDimensions;
  output Boolean outContainZeroDim;
algorithm
  outContainZeroDim := match(inDimensions)
    local
      list<DAE.Dimension> rest_dims;

    case (DAE.DIM_INTEGER(0) :: _) then true;
    case (_ :: rest_dims) then arrayContainZeroDimension(rest_dims);
    case ({}) then false;

  end match;
end arrayContainZeroDimension;

public function arrayContainWholeDimension
  "Checks if a list of dimensions contain a wholedim, i.e. NONE."
  input DAE.Dimensions inDim;
  output Boolean wholedim;
algorithm
  wholedim := matchcontinue(inDim)
    local
      DAE.Dimensions rest_dims;
    case ({}) then false;
    case (DAE.DIM_UNKNOWN() :: _) then true;
    case (_ :: rest_dims) then arrayContainWholeDimension(rest_dims);
  end matchcontinue;
end arrayContainWholeDimension;

public function isArrayType
"Returns true if inType is an T_ARRAY"
  input DAE.Type inType;
  output Boolean b;
algorithm
  b := match inType
    case DAE.T_ARRAY() then true;
    else false;
  end match;
end isArrayType;

public function isRecordType
  "Return true if the type is a record type."
  input DAE.Type inType;
  output Boolean b;
algorithm
  b := match(inType)
    case DAE.T_COMPLEX(complexClassType = ClassInf.RECORD()) then true;
    else false;
  end match;
end isRecordType;

public function isNotComplex "returns true if the exp is 1-dimensional"
  input DAE.Exp e;
  output Boolean b;
algorithm
  b := match(e)
    local
      Boolean b2;
      DAE.Exp e2;
    case(DAE.CALL())
      then
        false;
    case(DAE.RECORD())
      then
        false;
    case(DAE.ARRAY())
      then
        false;
    case(DAE.CAST(exp=e2))
      equation
        b2 = isNotComplex(e2);
      then b2;
    else
    then
      true;
  end match;
end isNotComplex;

public function isRealType
 "Return true if the type is Real."
  input DAE.Type inType;
  output Boolean b;
algorithm
  b := match(inType)
    case (DAE.T_REAL()) then true;
    else false;
  end match;
end isRealType;

public function dimensionsEqual
  "Returns whether two dimensions are equal or not."
  input DAE.Dimension dim1;
  input DAE.Dimension dim2;
  output Boolean res;
algorithm
  res := matchcontinue(dim1, dim2)
    local Boolean b;
    case (DAE.DIM_UNKNOWN(), _) then true;
    case (_, DAE.DIM_UNKNOWN()) then true;
    case (DAE.DIM_EXP(), _) then true;
    case (_, DAE.DIM_EXP()) then true;

    else
      equation
        b = intEq(dimensionSize(dim1), dimensionSize(dim2));
      then
        b;
  end matchcontinue;
end dimensionsEqual;

public function dimsEqual
  "Returns whether two dimensions are equal or not."
  input DAE.Dimensions dims1;
  input DAE.Dimensions dims2;
  output Boolean res;
algorithm
  res := matchcontinue(dims1, dims2)
    local
      DAE.Dimension d1, d2;
      DAE.Dimensions dl1, dl2;

    case ({}, {}) then true;
    case (d1::dl1, d2::dl2)
      equation
        true = dimensionsEqual(d1, d2);
        true = dimsEqual(dl1, dl2);
      then
        true;
    else false;
  end matchcontinue;
end dimsEqual;

public function dimsEqualAllowZero
"Returns whether two dimensions are equal or not.
 0 == anydim is allowed"
  input DAE.Dimensions dims1;
  input DAE.Dimensions dims2;
  output Boolean res;
algorithm
  res := matchcontinue(dims1, dims2)
    local
      DAE.Dimension d1, d2;
      DAE.Dimensions dl1, dl2;

    case ({}, {}) then true;
    case (d1::dl1, d2::dl2)
      equation
        true = dimensionsEqualAllowZero(d1, d2);
        true = dimsEqualAllowZero(dl1, dl2);
      then
        true;
    else false;
  end matchcontinue;
end dimsEqualAllowZero;

public function dimensionsEqualAllowZero
"Returns whether two dimensions are equal or not.
 0 == anyDim is allowed"
  input DAE.Dimension dim1;
  input DAE.Dimension dim2;
  output Boolean res;
algorithm
  res := matchcontinue(dim1, dim2)
    local
      Boolean b;
      Integer d1, d2;

    case (DAE.DIM_UNKNOWN(), _) then true;
    case (_, DAE.DIM_UNKNOWN()) then true;
    case (DAE.DIM_EXP(), _) then true;
    case (_, DAE.DIM_EXP()) then true;

    else
      equation
        d1 = dimensionSize(dim1);
        d2 = dimensionSize(dim2);
        b = boolOr(
              intEq(d1, d2),
              boolOr(
                boolAnd(intEq(d1,0), intNe(d2,0)),
                boolAnd(intEq(d2,0), intNe(d1,0))));
      then
        b;
  end matchcontinue;
end dimensionsEqualAllowZero;

public function dimensionsKnownAndEqual
  "Checks that two dimensions are specified and equal."
  input DAE.Dimension dim1;
  input DAE.Dimension dim2;
  output Boolean res;
algorithm
  res := match (dim1,dim2)
    case (DAE.DIM_UNKNOWN(),_) then false; // dimensionSizeExp fails on DIM_UNKNOWN...
    case (_,DAE.DIM_UNKNOWN()) then false;
    else expEqual(dimensionSizeExp(dim1), dimensionSizeExp(dim2));
  end match;
end dimensionsKnownAndEqual;

public function dimensionKnown
  "Checks whether a dimensions is known or not."
  input DAE.Dimension dim;
  output Boolean known;
algorithm
  known := matchcontinue(dim)
    case DAE.DIM_UNKNOWN() then false;
    case DAE.DIM_EXP(exp = DAE.ICONST()) then true;
    case DAE.DIM_EXP(exp = DAE.BCONST()) then true;
    case DAE.DIM_EXP(exp = DAE.ENUM_LITERAL()) then true;
    case DAE.DIM_EXP() then false;
    case _ then true;
  end matchcontinue;
end dimensionKnown;

public function dimensionKnownAndNonZero
  "Checks whether a dimensions is known or not."
  input DAE.Dimension dim;
  output Boolean known;
algorithm
  known := matchcontinue(dim)
    case DAE.DIM_EXP(exp = DAE.ICONST(0)) then false;
    case DAE.DIM_INTEGER(0) then false;
    else dimensionKnown(dim);
  end matchcontinue;
end dimensionKnownAndNonZero;

public function dimensionsKnownAndNonZero
  "Checks whether all dimensions are known or not.
  TODO: mahge: imprive this for speed"
  input list<DAE.Dimension> dims;
  output Boolean allKnown;
algorithm
  allKnown := Util.boolAndList(List.map(dims, dimensionKnownAndNonZero));
end dimensionsKnownAndNonZero;

public function dimensionUnknownOrExp
  "Checks whether a dimensions is known or not."
  input DAE.Dimension dim;
  output Boolean known;
algorithm
  known := matchcontinue(dim)
    case DAE.DIM_UNKNOWN() then true;
    case DAE.DIM_EXP() then true;
    case _ then false;
  end matchcontinue;
end dimensionUnknownOrExp;

public function subscriptEqual
"Returns true if two subscript lists are equal."
  input list<DAE.Subscript> inSubscriptLst1;
  input list<DAE.Subscript> inSubscriptLst2;
  output Boolean outBoolean;
algorithm
  outBoolean := match (inSubscriptLst1,inSubscriptLst2)
    local
      list<DAE.Subscript> xs1,xs2;
      DAE.Exp e1,e2;

    // both lists are empty
    case ({},{}) then true;

    // wholedims as list heads, compare the rest
    case ((DAE.WHOLEDIM() :: xs1),(DAE.WHOLEDIM() :: xs2))
      then subscriptEqual(xs1, xs2);

    // slices as heads, compare the slice exps and then compare the rest
    case ((DAE.SLICE(exp = e1) :: xs1),(DAE.SLICE(exp = e2) :: xs2))
      then expEqual(e1, e2) and subscriptEqual(xs1, xs2);

    // indexes as heads, compare the index exps and then compare the rest
    case ((DAE.INDEX(exp = e1) :: xs1),(DAE.INDEX(exp = e2) :: xs2))
      then expEqual(e1, e2) and subscriptEqual(xs1, xs2);

    case ((DAE.WHOLE_NONEXP(exp = e1) :: xs1),(DAE.WHOLE_NONEXP(exp = e2) :: xs2))
      then expEqual(e1, e2) and subscriptEqual(xs1, xs2);

    // subscripts are not equal, return false
    else false;
  end match;
end subscriptEqual;

public function subscriptConstants "
returns true if all subscripts are known (i.e no cref) constant values (no slice or wholedim "
  input list<DAE.Subscript> inSubs;
  output Boolean areConstant;
algorithm
  for sub in inSubs loop
    areConstant := match(sub)
      case DAE.INDEX(exp = DAE.ICONST()) then true;
      case DAE.INDEX(exp = DAE.ENUM_LITERAL()) then true;
      case DAE.INDEX(exp = DAE.BCONST()) then true;
      else false;
    end match;

    if not areConstant then return; end if;
  end for;
end subscriptConstants;

public function isValidSubscript
  "Checks if an expression is a valid subscript, i.e. an integer or enumeration
  literal."
  input DAE.Exp inSub;
  output Boolean isValid;
algorithm
  isValid := match(inSub)
    case DAE.ICONST() then true;
    case DAE.ENUM_LITERAL() then true;
    case DAE.BCONST() then true;
    else false;
  end match;
end isValidSubscript;

public function subscriptContain "This function checks whether sub2 contains sub1 or not(DAE.WHOLEDIM())"
  input list<DAE.Subscript> issl1;
  input list<DAE.Subscript> issl2;
  output Boolean contained;
algorithm
  contained := matchcontinue(issl1,issl2)
    local
      Boolean b;
      Subscript ss1,ss2;
      list<DAE.Subscript> ssl1,ssl2;
      DAE.Exp e1,e2;
      Integer i;
      list<DAE.Exp> expl;

    case({},_) then true;

    case(_ ::ssl1, (DAE.WHOLEDIM())::ssl2)
      equation
        b = subscriptContain(ssl1,ssl2);
      then b;

    // Should there be additional checking in this case?
    case(_ ::ssl1, (DAE.WHOLE_NONEXP(_))::ssl2)
      equation
        b = subscriptContain(ssl1,ssl2);
      then b;
/*    case(ss1::ssl1, (ss2 as DAE.SLICE(exp)) ::ssl2)
      local DAE.Exp exp;
        equation
         b = subscriptContain(ssl1,ssl2);
        then
          b;
          */
    case((DAE.INDEX(DAE.ICONST(i)))::ssl1, (DAE.SLICE(DAE.ARRAY(_,_,expl))) ::ssl2)
      equation
        true = subscriptContain2(i,expl);
        b = subscriptContain(ssl1,ssl2);
      then
        b;

    case(ss1::ssl1,ss2::ssl2)
      equation
        true = subscriptEqual({ss1},{ss2});
        b = subscriptContain(ssl1,ssl2);
      then
        b;
    else false;
  end matchcontinue;
end subscriptContain;

protected function subscriptContain2 "
"
  input Integer inInt;
  input list<DAE.Exp> inExp2;
  output Boolean contained;
algorithm
  contained := matchcontinue(inInt,inExp2)
    local
      Boolean b,b2;
      DAE.Exp e1,e2;
      list<DAE.Exp> expl,expl2;
      Integer i,j;
      case(i,( (DAE.ICONST(j)) :: _))
        equation
            true = (i == j);
          then
            true;
      case(i,(( DAE.ICONST(_)) :: expl))
        equation
            true = subscriptContain2(i,expl);
          then
            true;
      case(i,( (DAE.ARRAY(_,_,expl2)) :: expl))
        equation
          b = subscriptContain2(i,expl2);
          b2 = subscriptContain2(i,expl);
          b = Util.boolOrList({b,b2});
        then
          b;
      else false;
  end matchcontinue;
end subscriptContain2;

public function hasNoSideEffects
  "Returns true if the expression is free from side-effects. Use with traverseExp."
  input DAE.Exp inExp;
  input Boolean ib;
  output DAE.Exp outExp;
  output Boolean ob;
algorithm
  (outExp,ob) := match (inExp,ib)
    local
      DAE.Exp e;
    case (DAE.CALL(),_) then (inExp,false);
    case (DAE.MATCHEXPRESSION(),_) then (inExp,false);
    else (inExp,ib);
  end match;
end hasNoSideEffects;

public function isBuiltinFunctionReference
  "Returns true if the expression is a reference to a builtin function"
  input DAE.Exp exp;
  output Boolean b;
algorithm
  b := match exp
    case DAE.CREF(ty=DAE.T_FUNCTION_REFERENCE_FUNC(builtin=true)) then true;
    else false;
  end match;
end isBuiltinFunctionReference;

public function makeCons "DAE.CONS"
  input DAE.Exp car;
  input DAE.Exp cdr;
  output DAE.Exp exp;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  exp := DAE.CONS(car,cdr);
end makeCons;

public function makeBuiltinCall
  "Create a DAE.CALL with the given data for a call to a builtin function."
  input String name;
  input list<DAE.Exp> args;
  input DAE.Type result_type;
  input Boolean isImpure;
  output DAE.Exp call;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  call := DAE.CALL(Absyn.IDENT(name),args,DAE.CALL_ATTR(result_type,false,true,isImpure,false,DAE.NO_INLINE(),DAE.NO_TAIL()));
end makeBuiltinCall;

public function makePureBuiltinCall
  "Create a DAE.CALL with the given data for a call to a builtin function."
  input String name;
  input list<DAE.Exp> args;
  input DAE.Type result_type;
  output DAE.Exp call;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  call := makeBuiltinCall(name, args, result_type, false);
end makePureBuiltinCall;

public function makeImpureBuiltinCall
  "Create a DAE.CALL with the given data for a call to a builtin function."
  input String name;
  input list<DAE.Exp> args;
  input DAE.Type result_type;
  output DAE.Exp call;
  annotation(__OpenModelica_EarlyInline = true);
algorithm
  call := makeBuiltinCall(name, args, result_type, true);
end makeImpureBuiltinCall;

public function reductionIterName
  input DAE.ReductionIterator iter;
  output String name;
algorithm
  DAE.REDUCTIONITER(id=name) := iter;
end reductionIterName;

protected function traverseReductionIteratorBidir<ArgT>
  input DAE.ReductionIterator inIter;
  input FuncType inEnterFunc;
  input FuncType inExitFunc;
  input ArgT inArg;
  output DAE.ReductionIterator outIter;
  output ArgT outArg;

  partial function FuncType
    input DAE.Exp inExp;
    input ArgT inArg;
    output DAE.Exp outExp;
    output ArgT outArg;
  end FuncType;
algorithm
  (outIter, outArg) := match(inIter)
    local
      String id;
      DAE.Exp exp;
      Option<DAE.Exp> gexp;
      DAE.Type ty;
      ArgT arg;

    case DAE.REDUCTIONITER(id, exp, gexp, ty)
      equation
        (exp, arg) = traverseExpBidir(exp, inEnterFunc, inExitFunc, inArg);
        (gexp, arg) = traverseExpOptBidir(gexp, inEnterFunc, inExitFunc, arg);
      then
        (DAE.REDUCTIONITER(id, exp, gexp, ty), arg);

  end match;
end traverseReductionIteratorBidir;

protected function traverseReductionIteratorTopDown
  input DAE.ReductionIterator iter;
  input FuncExpType func;
  input Type_a inArg;
  output DAE.ReductionIterator outIter;
  output Type_a outArg;

  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Boolean cont;
    output Type_a outA;
  end FuncExpType;

  replaceable type Type_a subtypeof Any;
algorithm
  (outIter,outArg) := match (iter,func,inArg)
    local
      String id;
      DAE.Exp exp;
      Option<DAE.Exp> gexp;
      DAE.Type ty;
      Type_a arg;
    case (DAE.REDUCTIONITER(id,exp,gexp,ty),_,arg)
      equation
        (exp, arg) = traverseExpTopDown(exp, func, arg);
        (gexp, arg) = traverseExpOptTopDown(gexp, func, arg);
      then (DAE.REDUCTIONITER(id,exp,gexp,ty),arg);
  end match;
end traverseReductionIteratorTopDown;

protected function traverseReductionIteratorsTopDown
  input DAE.ReductionIterators inIters;
  input FuncExpType func;
  input Type_a inArg;
  output DAE.ReductionIterators outIters;
  output Type_a outArg;

  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Boolean cont;
    output Type_a outA;
  end FuncExpType;

  replaceable type Type_a subtypeof Any;
algorithm
  (outIters,outArg) := match (inIters,func,inArg)
    local
      Type_a arg;
      DAE.ReductionIterator iter;
      DAE.ReductionIterators iters;

    case ({},_,arg) then ({},arg);
    case (iter::iters,_,arg)
      equation
        (iter, arg) = traverseReductionIteratorTopDown(iter, func, arg);
        (iters, arg) = traverseReductionIteratorsTopDown(iters, func, arg);
      then (iter::iters,arg);
  end match;
end traverseReductionIteratorsTopDown;

protected function traverseReductionIterator
  input DAE.ReductionIterator iter;
  input FuncExpType func;
  input Type_a iarg;
  output DAE.ReductionIterator outIter;
  output Type_a outArg;

  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Type_a outA;
  end FuncExpType;
  replaceable type Type_a subtypeof Any;
algorithm
  (outIter,outArg) := match (iter,func,iarg)
    local
      String id;
      DAE.Exp exp,exp1;
      Option<DAE.Exp> gexp,gexp1;
      DAE.Type ty;
      Type_a arg;

    case (DAE.REDUCTIONITER(id,exp,gexp,ty),_,arg)
      equation
        (exp1, arg) = traverseExp(exp, func, arg);
        (gexp1, arg) = traverseExpOpt(gexp, func, arg);
        outIter = if referenceEq(exp,exp1) and referenceEq(gexp,gexp1) then iter else DAE.REDUCTIONITER(id,exp1,gexp1,ty);
      then (outIter, arg);
  end match;
end traverseReductionIterator;

protected function traverseReductionIterators
  input DAE.ReductionIterators inIters;
  input FuncExpType func;
  input Type_a inArg;
  output DAE.ReductionIterators outIters;
  output Type_a outArg;

  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Type_a outA;
  end FuncExpType;
  replaceable type Type_a subtypeof Any;
algorithm
  (outIters,outArg) := match (inIters,func,inArg)
    local
      DAE.ReductionIterator iter,iter1;
      DAE.ReductionIterators iters,iters1;
      Type_a arg;

    case ({},_,arg) then ({},arg);
    case (iter::iters,_,arg)
      equation
        (iter1, arg) = traverseReductionIterator(iter, func, arg);
        (iters1, arg) = traverseReductionIterators(iters, func, arg);
        iters = if referenceEq(iter,iter1) and referenceEq(iters,iters1) then inIters else (iter1::iters1);
      then (iters, arg);
  end match;
end traverseReductionIterators;

public function simpleCrefName
  input DAE.Exp exp;
  output String name;
algorithm
  DAE.CREF(componentRef=DAE.CREF_IDENT(ident=name,subscriptLst={})) := exp;
end simpleCrefName;

public function isTailCall
  input DAE.Exp exp;
  output Boolean isTail;
algorithm
  isTail := match exp
    case DAE.CALL(attr=DAE.CALL_ATTR(tailCall=DAE.TAIL())) then true;
    else false;
  end match;
end isTailCall;

public function complexityTraverse
  input DAE.Exp exp;
  input Integer complexity;
  output DAE.Exp outExp;
  output Integer outComplexity;
algorithm
  (outExp,outComplexity) := traverseExp(exp,complexityTraverse2,complexity);
end complexityTraverse;

protected function complexityTraverse2
  input DAE.Exp exp;
  input Integer complexity_;
  output DAE.Exp outExp;
  output Integer outComplexity;
algorithm
  outComplexity := complexity_ + complexity(exp);
  outExp := exp;
end complexityTraverse2;

protected constant Integer complexityAlloc = 5;
protected constant Integer complexityVeryBig = 500000 "Things that are too hard to calculate :(";
protected constant Integer complexityDimLarge = 1000 "Unknown dimensions usually aren't big, but might be";

public function complexity
  input DAE.Exp exp;
  output Integer i;
algorithm
  i := match exp
    local
      DAE.Operator op;
      DAE.Exp e,e1,e2,e3;
      Integer c1,c2,c3;
      list<DAE.Exp> exps;
      list<list<DAE.Exp>> matrix;
      String str,name;
      DAE.Type tp;
    case DAE.ICONST() then 0;
    case DAE.RCONST() then 0;
    case DAE.SCONST() then 0;
    case DAE.BCONST() then 0;
    case DAE.SHARED_LITERAL() then 0;
    case DAE.ENUM_LITERAL() then 0;
    case DAE.CREF(ty=tp) then tpComplexity(tp);
    case DAE.BINARY(exp1=e1,operator=op,exp2=e2)
      equation
        c1 = complexity(e1);
        c2 = complexity(e2);
        c3 = opComplexity(op);
      then c1+c2+c3;
    case DAE.UNARY(exp=e,operator=op)
      equation
        c1 = complexity(e);
        c2 = opComplexity(op);
      then c1+c2;
    case DAE.LBINARY(exp1=e1,exp2=e2,operator=op)
      equation
        c1 = complexity(e1);
        c2 = complexity(e2);
        c3 = opComplexity(op);
      then c1+c2+c3;
    case DAE.LUNARY(exp=e,operator=op)
      equation
        c1 = complexity(e);
        c2 = opComplexity(op);
      then c1+c2;
    case DAE.RELATION(exp1=e1,exp2=e2,operator=op)
      equation
        c1 = complexity(e1);
        c2 = complexity(e2);
        c3 = opComplexity(op);
      then c1+c2+c3;
    case DAE.IFEXP(expCond=e1,expThen=e2,expElse=e3)
      equation
        c1 = complexity(e1);
        c2 = complexity(e2);
        c3 = complexity(e3);
      then c1+intMax(c2,c3);
    case DAE.CALL(path=Absyn.IDENT(name),expLst=exps,attr=DAE.CALL_ATTR(ty=tp,builtin=true))
      equation
        c1 = List.fold(List.map(exps,complexity),intAdd,0);
        c2 = complexityBuiltin(name,tp);
        /* TODO: Cost is based on type and size of inputs. Maybe even name for builtins :) */
      then c1+c2;
    case DAE.CALL(expLst=exps)
      equation
        c1 = List.fold(List.map(exps,complexity),intAdd,0);
        c2 = listLength(exps);
        /* TODO: Cost is based on type and size of inputs. Maybe even name for builtins :) */
      then c1+c2+25;
    case DAE.RECORD(exps=exps)
      equation
        c1 = List.fold(List.map(exps,complexity),intAdd,1);
      then c1;
    case DAE.PARTEVALFUNCTION()
      then complexityVeryBig; /* This should not be here anyway :) */
    case DAE.ARRAY(array=exps,ty=tp)
      equation
        c1 = List.fold(List.map(exps,complexity),intAdd,if isArrayType(tp) then 0 else complexityAlloc);
        c2 = listLength(exps);
      then c1+c2;
    case DAE.MATRIX(matrix=matrix as (exps::_))
      equation
        c1 = List.fold(List.map(List.flatten(matrix),complexity),intAdd,complexityAlloc);
        c2 = listLength(exps)*listLength(matrix);
      then c1 + c2;
    case DAE.RANGE(start=e1,stop=e2,step=NONE())
      then complexityDimLarge+complexity(e1)+complexity(e2); /* TODO: Check type maybe? */
    case DAE.RANGE(start=e1,stop=e2,step=SOME(e3))
      then complexityDimLarge+complexity(e1)+complexity(e2)+complexity(e3); /* TODO: Check type maybe? */
    case DAE.TUPLE(PR=exps)
      equation
        c1 = List.fold(List.map(exps,complexity),intAdd,complexityAlloc);
        c2 = listLength(exps);
      then c1+c2;
    case DAE.CAST(exp=e,ty=tp) then tpComplexity(tp)+complexity(e);
    case DAE.ASUB(exp=e,sub=exps)
      equation
        c1 = List.fold(List.map(exps,complexity),intAdd,complexityAlloc);
        c2 = listLength(exps);
        c3 = complexity(e);
      then c1+c2+c3;
    case DAE.TSUB(exp=e) then complexity(e)+1;
    case DAE.SIZE(exp=e,sz=NONE()) then complexity(e)+complexityAlloc+10; /* TODO: Cost is based on type (creating the array) */
    case DAE.SIZE(exp=e1,sz=SOME(e2)) then complexity(e1)+complexity(e2)+1;
    case DAE.CODE() then complexityVeryBig;
    case DAE.EMPTY() then complexityVeryBig;
    case DAE.REDUCTION() then complexityVeryBig; /* TODO: We need a real traversal... */
    case DAE.LIST(valList=exps)
      equation
        c1 = List.fold(List.map(exps,complexity),intAdd,complexityAlloc);
        c2 = listLength(exps);
      then c1+c2+complexityAlloc;
    case DAE.CONS(car=e1,cdr=e2)
      then complexityAlloc+complexity(e1)+complexity(e2);
    case DAE.META_TUPLE(listExp=exps)
      equation
        c1 = List.fold(List.map(exps,complexity),intAdd,complexityAlloc);
        c2 = listLength(exps);
      then complexityAlloc+c1+c2;
    case DAE.META_OPTION(exp=NONE()) then 0;
    case DAE.META_OPTION(exp=SOME(e)) then complexity(e)+complexityAlloc;
    case DAE.METARECORDCALL(args=exps)
      equation
        c1 = List.fold(List.map(exps,complexity),intAdd,complexityAlloc);
        c2 = listLength(exps);
      then c1+c2+complexityAlloc;
    case DAE.MATCHEXPRESSION() then complexityVeryBig;
    case DAE.BOX(exp=e) then complexityAlloc+complexity(e);
    case DAE.UNBOX(exp=e) then 1+complexity(e);
    case DAE.PATTERN() then 0;
    else
      equation
        str = "Expression.complexityWork failed: " + ExpressionDump.printExpStr(exp);
        Error.addMessage(Error.INTERNAL_ERROR,{str});
      then fail();
  end match;
end complexity;

protected function complexityBuiltin
  input String name;
  input DAE.Type tp;
  output Integer complexity;
algorithm
  complexity := match (name,tp)
    case ("identity",_) then complexityAlloc+tpComplexity(tp);
    case ("cross",_) then 3*3;
    else 25;
  end match;
end complexityBuiltin;

protected function tpComplexity
  input DAE.Type tp;
  output Integer i;
algorithm
  i := match tp
    local
      list<DAE.Dimension> dims;
    case DAE.T_ARRAY(dims=dims)
      equation
        i = List.fold(List.map(dims,dimComplexity),intMul,1);
      then i;
    else 0;
  end match;
end tpComplexity;

public function dimComplexity
  input DAE.Dimension dim;
  output Integer i;
algorithm
  i := match dim
    case DAE.DIM_INTEGER(integer=i) then i;
    case DAE.DIM_ENUM(size=i) then i;
    case DAE.DIM_BOOLEAN() then 2;
    else complexityDimLarge;
  end match;
end dimComplexity;

protected function opComplexity
  input DAE.Operator op;
  output Integer i;
algorithm
  i := match op
    local
      DAE.Type tp;
    case DAE.ADD(ty=DAE.T_STRING()) then 100;
    case DAE.ADD() then 1;
    case DAE.SUB() then 1;
    case DAE.MUL() then 1;
    case DAE.DIV() then 1;
    case DAE.POW() then 30;
    case DAE.UMINUS() then 1;
      /* TODO: Array dims? */
    case DAE.UMINUS_ARR(ty=tp) then complexityAlloc+tpComplexity(tp);
    case DAE.ADD_ARR(ty=tp) then complexityAlloc+tpComplexity(tp);
    case DAE.SUB_ARR(ty=tp) then complexityAlloc+tpComplexity(tp);
    case DAE.MUL_ARR(ty=tp) then complexityAlloc+tpComplexity(tp);
    case DAE.DIV_ARR(ty=tp) then complexityAlloc+tpComplexity(tp);
    case DAE.MUL_ARRAY_SCALAR(ty=tp) then complexityAlloc+tpComplexity(tp);
    case DAE.ADD_ARRAY_SCALAR(ty=tp) then complexityAlloc+tpComplexity(tp);
    case DAE.SUB_SCALAR_ARRAY(ty=tp) then complexityAlloc+tpComplexity(tp);
    case DAE.MUL_SCALAR_PRODUCT(ty=tp) then complexityAlloc+3*tpComplexity(tp);
    case DAE.MUL_MATRIX_PRODUCT(ty=tp) then complexityAlloc+3*tpComplexity(tp);
    case DAE.DIV_ARRAY_SCALAR(ty=tp) then complexityAlloc+tpComplexity(tp);
    case DAE.DIV_SCALAR_ARRAY(ty=tp) then complexityAlloc+tpComplexity(tp);
    case DAE.POW_ARRAY_SCALAR(ty=tp) then complexityAlloc+30*tpComplexity(tp);
    case DAE.POW_SCALAR_ARRAY(ty=tp) then complexityAlloc+30*tpComplexity(tp);
    case DAE.POW_ARR(ty=tp) then complexityAlloc+30*tpComplexity(tp);
    case DAE.POW_ARR2(ty=tp) then complexityAlloc+30*tpComplexity(tp);
    /* TODO: Array ops? */
    case DAE.AND() then 1;
    case DAE.OR() then 1;
    case DAE.NOT() then 1;
    case DAE.LESS() then 1;
    case DAE.LESSEQ() then 1;
    case DAE.GREATER() then 1;
    case DAE.GREATEREQ() then 1;
    case DAE.EQUAL() then 1;
    case DAE.NEQUAL() then 1;
    case DAE.USERDEFINED() then 100;
    else
      equation
        Error.addMessage(Error.INTERNAL_ERROR,{"Expression.opWCET failed"});
      then fail();
  end match;
end opComplexity;

public function makeEnumLiterals
  "Construct a list of enumeration literal expression given the type name of an
   enumeration an a list of literal names."
  input Absyn.Path inTypeName;
  input list<String> inLiterals;
  output list<DAE.Exp> outLiterals;
protected
  list<Absyn.Path> enum_lit_names;
  list<DAE.Exp> enum_lit_expl;
algorithm
  enum_lit_names := List.map1r(inLiterals, Absyn.suffixPath, inTypeName);
  (outLiterals, _) := List.mapFold(enum_lit_names, makeEnumLiteral, 1);
end makeEnumLiterals;

protected function makeEnumLiteral
  "Creates a new enumeration literal. For use with listMapAndFold."
  input Absyn.Path name;
  input Integer index;
  output DAE.Exp enumExp;
  output Integer newIndex;
algorithm
  enumExp := DAE.ENUM_LITERAL(name, index);
  newIndex := index + 1;
end makeEnumLiteral;

public function shouldParenthesize
  "Determines whether an operand in an expression needs parentheses around it."
  input DAE.Exp inOperand;
  input DAE.Exp inOperator;
  input Boolean inLhs;
  output Boolean outShouldParenthesize;
algorithm
  outShouldParenthesize := match(inOperand, inOperator, inLhs)
    local
      Integer diff;

    case (DAE.UNARY(), _, _) then true;

    else
      equation
        diff = Util.intCompare(priority(inOperand, inLhs),
                               priority(inOperator, inLhs));
      then
        shouldParenthesize2(diff, inOperand, inLhs);

  end match;
end shouldParenthesize;

protected function shouldParenthesize2
  input Integer inPrioDiff;
  input DAE.Exp inOperand;
  input Boolean inLhs;
  output Boolean outShouldParenthesize;
algorithm
  outShouldParenthesize := match(inPrioDiff, inOperand, inLhs)
    case (1, _, _) then true;
    case (0, _, false) then not isAssociativeExp(inOperand);
    else false;
  end match;
end shouldParenthesize2;

protected function isAssociativeExp
  "Determines whether the given expression represents an associative operation or not."
  input DAE.Exp inExp;
  output Boolean outIsAssociative;
algorithm
  outIsAssociative := match(inExp)
    local
      DAE.Operator op;

    case DAE.BINARY(operator = op) then isAssociativeOp(op);
    case DAE.LBINARY() then true;
    else false;

  end match;
end isAssociativeExp;

protected function isAssociativeOp
  "Determines whether the given operator is associative or not."
  input DAE.Operator inOperator;
  output Boolean outIsAssociative;
algorithm
  outIsAssociative := match(inOperator)
    case DAE.ADD() then true;
    case DAE.MUL() then true;
    case DAE.ADD_ARR() then true;
    case DAE.MUL_ARRAY_SCALAR() then true;
    case DAE.ADD_ARRAY_SCALAR() then true;
    else false;
  end match;
end isAssociativeOp;

public function priority
  "Returns an integer priority given an expression, which is used by
   ExpressionDumpTpl to add parentheses when dumping expressions. The inLhs
   argument should be true if the expression occurs on the left side of a binary
   operation, otherwise false. This is because we don't need to add parentheses
   to expressions such as x * y / z, but x / (y * z) needs them, so the
   priorities of some binary operations differ depending on which side they are."
  input DAE.Exp inExp;
  input Boolean inLhs;
  output Integer outPriority;
algorithm
  outPriority := match(inExp, inLhs)
    local
      DAE.Operator op;

    case (DAE.BINARY(operator = op), false) then priorityBinopRhs(op);
    case (DAE.BINARY(operator = op), true) then priorityBinopLhs(op);
    case (DAE.UNARY(), _) then 4;
    case (DAE.LBINARY(operator = op), _) then priorityLBinop(op);
    case (DAE.LUNARY(), _) then 7;
    case (DAE.RELATION(), _) then 6;
    case (DAE.RANGE(), _) then 10;
    case (DAE.IFEXP(), _) then 11;
    else 0;
  end match;
end priority;

protected function priorityBinopLhs
  "Returns the priority for a binary operation on the left hand side. Add and
   sub has the same priority, and mul and div too, in contrast with
   priorityBinopRhs."
  input DAE.Operator inOp;
  output Integer outPriority;
algorithm
  outPriority := match(inOp)
    case DAE.ADD() then 5;
    case DAE.SUB() then 5;
    case DAE.MUL() then 2;
    case DAE.DIV() then 2;
    case DAE.POW() then 1;
    case DAE.ADD_ARR() then 5;
    case DAE.SUB_ARR() then 5;
    case DAE.MUL_ARR() then 2;
    case DAE.DIV_ARR() then 2;
    case DAE.MUL_ARRAY_SCALAR() then 2;
    case DAE.ADD_ARRAY_SCALAR() then 5;
    case DAE.SUB_SCALAR_ARRAY() then 5;
    case DAE.MUL_SCALAR_PRODUCT() then 2;
    case DAE.MUL_MATRIX_PRODUCT() then 2;
    case DAE.DIV_ARRAY_SCALAR() then 2;
    case DAE.DIV_SCALAR_ARRAY() then 2;
    case DAE.POW_ARRAY_SCALAR() then 1;
    case DAE.POW_SCALAR_ARRAY() then 1;
    case DAE.POW_ARR() then 1;
    case DAE.POW_ARR2() then 1;
  end match;
end priorityBinopLhs;

protected function priorityBinopRhs
  "Returns the priority for a binary operation on the right hand side. Add and
   sub has different priorities, and mul and div too, in contrast with
   priorityBinopLhs."
  input DAE.Operator inOp;
  output Integer outPriority;
algorithm
  outPriority := match(inOp)
    case DAE.ADD() then 6;
    case DAE.SUB() then 5;
    case DAE.MUL() then 3;
    case DAE.DIV() then 2;
    case DAE.POW() then 1;
    case DAE.ADD_ARR() then 6;
    case DAE.SUB_ARR() then 5;
    case DAE.MUL_ARR() then 3;
    case DAE.DIV_ARR() then 2;
    case DAE.MUL_ARRAY_SCALAR() then 3;
    case DAE.ADD_ARRAY_SCALAR() then 6;
    case DAE.SUB_SCALAR_ARRAY() then 5;
    case DAE.MUL_SCALAR_PRODUCT() then 3;
    case DAE.MUL_MATRIX_PRODUCT() then 3;
    case DAE.DIV_ARRAY_SCALAR() then 2;
    case DAE.DIV_SCALAR_ARRAY() then 2;
    case DAE.POW_ARRAY_SCALAR() then 1;
    case DAE.POW_SCALAR_ARRAY() then 1;
    case DAE.POW_ARR() then 1;
    case DAE.POW_ARR2() then 1;
  end match;
end priorityBinopRhs;

protected function priorityLBinop
  input DAE.Operator inOp;
  output Integer outPriority;
algorithm
  outPriority := match(inOp)
    case DAE.AND() then 8;
    case DAE.OR() then 9;
  end match;
end priorityLBinop;

public function isWild
  input DAE.Exp exp;
  output Boolean b;
algorithm
  b := match exp
    case DAE.CREF(componentRef=DAE.WILD()) then true;
    else false;
  end match;
end isWild;

public function isNotWild
  input DAE.Exp exp;
  output Boolean b;
algorithm
  b := match exp
    case DAE.CREF(componentRef=DAE.WILD()) then false;
    else true;
  end match;
end isNotWild;

public function dimensionsToExps "Takes a list of dimensions and select the expressions dimensions, returning a list of expressions"
  input list<DAE.Dimension> dims;
  input list<DAE.Exp> acc;
  output list<DAE.Exp> exps;
algorithm
  exps := match (dims,acc)
    local
      list<DAE.Dimension> rest;
      DAE.Exp exp;
    case ({},_) then listReverse(acc);
    case (DAE.DIM_EXP(exp)::rest,_) then dimensionsToExps(rest,exp::acc);
    case (_::rest,_) then dimensionsToExps(rest,acc);
  end match;
end dimensionsToExps;

public function splitRecord
  "Splits a record into its elements. Works for crefs, records constructor calls, and casts of the same"
  input DAE.Exp inExp;
  input DAE.Type ty;
  output list<DAE.Exp> outExps;
algorithm
  outExps := match (inExp,ty)
    local
      DAE.Exp exp;
      list<DAE.Var> vs;
      DAE.ComponentRef cr;
      Absyn.Path p1,p2;
      list<DAE.Exp> exps;
    case (DAE.CAST(exp=exp),_) then splitRecord(exp,ty);
    case (DAE.CREF(componentRef=cr),DAE.T_COMPLEX(varLst = vs))
      then List.map1(vs,splitRecord2,cr);
    case (DAE.CALL(path=p1,expLst=exps,attr=DAE.CALL_ATTR(ty=DAE.T_COMPLEX(complexClassType=ClassInf.RECORD(p2)))),_)
      equation
        true = Absyn.pathEqual(p1,p2) "is record constructor";
      then exps;
    case (DAE.RECORD(exps=exps),_)
      then exps;
  end match;
end splitRecord;

protected function splitRecord2
  input DAE.Var var;
  input DAE.ComponentRef cr;
  output DAE.Exp exp;
protected
  String n;
  DAE.Type tt,ty;
algorithm
  DAE.TYPES_VAR(name = n,ty = tt) := var;
  ty := Types.simplifyType(tt);
  exp := makeCrefExp(ComponentReference.crefPrependIdent(cr, n, {}, ty), ty);
end splitRecord2;

public function splitArray
  "Splits an array into a list of elements."
  input DAE.Exp inExp;
  output list<DAE.Exp> outExp;
algorithm
  outExp := match(inExp)
    local
      list<DAE.Exp> expl;
      list<list<DAE.Exp>> mat;

    case DAE.ARRAY(array = expl) then expl;
    case DAE.MATRIX(matrix = mat) then List.flatten(mat);
    else {inExp};

  end match;
end splitArray;

public function equationExpEqual
  input DAE.EquationExp exp1;
  input DAE.EquationExp exp2;
  output Boolean b;
algorithm
  b := match (exp1,exp2)
    local
      DAE.Exp e1,e2,e3,e4;
    case (DAE.PARTIAL_EQUATION(e1),DAE.PARTIAL_EQUATION(e2)) then expEqual(e1,e2);
    case (DAE.RESIDUAL_EXP(e1),DAE.RESIDUAL_EXP(e2)) then expEqual(e1,e2);
    case (DAE.EQUALITY_EXPS(e1,e2),DAE.EQUALITY_EXPS(e3,e4)) then expEqual(e1,e3) and expEqual(e2,e4);
    else false;
  end match;
end equationExpEqual;

public function promoteExp
  "This function corresponds to the promote function described in the Modelica
   spec. It takes an expression, the type of the expression and a number of
   dimensions, and adds dimensions of size 1 to the right of the expression
   until the expression has as many dimensions as given. It also returns the
   type of the promoted expression. E.g.:

     promoteExp({1, 2, 3}, Integer[3], 3) =>
        ({{{1}}, {{2}}, {{3}}}, Integer[3,1,1])

   The reason why this function takes a type instead of using the type of the
   expression is because it's used by Static.promoteExp, which already knows the
   type."
  input DAE.Exp inExp;
  input DAE.Type inType;
  input Integer inDims;
  output DAE.Exp outExp;
  output DAE.Type outType;
algorithm
  (outExp, outType) := matchcontinue(inExp, inType, inDims)
    local
      Integer  dims_to_add;
      DAE.Type ty, res_ty;
      DAE.Exp exp;
      list<DAE.Type> tys;
      list<DAE.Dimension> dims, added_dims;
      Boolean is_array_ty;

    case (_, _, _)
      equation
        // Figure out how many dimensions we need to add.
        dims_to_add = inDims - Types.numberOfDimensions(inType);
        // If the expression already has at least as many dimensions as we want,
        // fail and return the unchanged expression.
        true = dims_to_add > 0;

        // Construct all the types we will need here, to avoid having to
        // construct new types for all the subexpressions created.
        dims = Types.getDimensions(inType);
        // Add as many dimensions of size 1 as needed.
        added_dims = List.fill(DAE.DIM_INTEGER(1), dims_to_add);
        dims = listAppend(dims, added_dims);
        // Construct the result type.
        ty = Types.arrayElementType(inType);
        res_ty = Types.liftArrayListDims(ty, dims);
        // Construct the expression types.
        ty = Types.simplifyType(ty);
        tys = makePromotedTypes(dims, ty, {});

        // Use the constructed types to promote the expression.
        is_array_ty = Types.isArray(inType, {});
        exp = promoteExp2(inExp, is_array_ty, dims_to_add, tys);
      then
        (exp, res_ty);

    else (inExp, inType);

  end matchcontinue;
end promoteExp;

protected function makePromotedTypes
  "Creates a lift of types given a list of dimensions and an element type. The
   types are created by removing the head of the dimension list one by one and
   creating types from the remaining dimensions. E.g.:

     makePromotedTypes({[2], [3], [1]}, Real) =>
        {Real[2,3,1], Real[3,1], Real[1]}
   "
  input list<DAE.Dimension> inDimensions;
  input DAE.Type inElementType;
  input list<DAE.Type> inAccumTypes;
  output list<DAE.Type> outAccumTypes;
algorithm
  outAccumTypes := match(inDimensions, inElementType, inAccumTypes)
    local
      list<DAE.Dimension> rest_dims;
      DAE.Type ty;

    case (_ :: rest_dims, _, _)
      equation
        ty = DAE.T_ARRAY(inElementType, inDimensions, DAE.emptyTypeSource);
      then
        makePromotedTypes(rest_dims, inElementType, ty :: inAccumTypes);

    case ({}, _, _) then listReverse(inAccumTypes);

  end match;
end makePromotedTypes;

protected function promoteExp2
  "Helper function to promoteExp."
  input DAE.Exp inExp;
  input Boolean inIsArray;
  input Integer inDims;
  input list<DAE.Type> inTypes;
  output DAE.Exp outExp;
algorithm
  outExp := match(inExp, inIsArray, inDims, inTypes)
    local
      DAE.Type ty;
      list<DAE.Exp> expl;
      list<DAE.Type> rest_ty;

    // No types left, we're done!
    case (_, _, _, {}) then inExp;

    // An array, promote each element in the array.
    case (DAE.ARRAY(_, _, expl), _, _, ty :: rest_ty)
      equation
        expl = List.map3(expl, promoteExp2, false, inDims, rest_ty);
      then
        DAE.ARRAY(ty, false, expl);

    // An expression with array type, but which is not an array expression. Such
    // an expression can't be promoted here, so we create a promote call instead.
    case (_, true, _, ty :: _)
      then makePureBuiltinCall("promote", {inExp, DAE.ICONST(inDims)}, ty);

    // Any other expression, call promoteExp3.
    else promoteExp3(inExp, inTypes);

  end match;
end promoteExp2;

protected function promoteExp3
  "Helper function to promoteExp2. Promotes a scalar expression as many times as
   the number of types given."
  input DAE.Exp inExp;
  input list<DAE.Type> inTypes;
  output DAE.Exp outExp;
algorithm
  outExp := match(inExp, inTypes)
    local
      DAE.Type ty;
      list<DAE.Type> rest_ty;
      DAE.Exp exp;

    // No types left, were' done!
    case (_, {}) then inExp;

    // Only one type left, create a scalar array with it.
    case (_, {ty}) then makeArray({inExp}, ty, true);

    // Several types left. Promote the expression using the rest of the types,
    // and then create an non-scalar array of the expression with the first type.
    case (_, ty :: rest_ty)
      equation
        exp = promoteExp3(inExp, rest_ty);
      then
        makeArray({exp}, ty, false);

  end match;
end promoteExp3;

public function hashExpMod "
author: PA
hash expression to value in range [0,mod-1]"
  input DAE.Exp e;
  input Integer mod;
  output Integer hash;
algorithm
  hash := intMod(intAbs(hashExp(e)),mod);
end hashExpMod;

public function hashExp "help function to hashExpMod"
  input DAE.Exp e;
  output Integer hash;
algorithm
 hash := matchcontinue(e)
   local
    Real r;
    Integer i;
    Boolean b;
    String s;
    Absyn.Path path;
    DAE.Exp e1,e2,e3;
    DAE.Operator op;
    list<DAE.Exp> expl;
    list<list<DAE.Exp>> mexpl;
    DAE.ComponentRef cr;
    DAE.ReductionIterators iters;
    DAE.ReductionInfo info;

 case(DAE.ICONST(i))                                then stringHashDjb2(intString(i));
 case(DAE.RCONST(r))                                then stringHashDjb2(realString(r));
 case(DAE.BCONST(b))                                then stringHashDjb2(boolString(b));
 case(DAE.SCONST(s))                                then stringHashDjb2(s);
 case(DAE.ENUM_LITERAL(name=path))                  then stringHashDjb2(Absyn.pathString(path));
 case(DAE.CREF(componentRef=cr))                    then ComponentReference.hashComponentRef(cr);

 case(DAE.BINARY(e1,op,e2))                         then 1 + hashExp(e1)+hashOp(op)+hashExp(e2);
 case(DAE.UNARY(op,e1))                             then 2 + hashOp(op)+hashExp(e1);
 case(DAE.LBINARY(e1,op,e2))                        then 3 + hashExp(e1)+hashOp(op)+hashExp(e2);
 case(DAE.LUNARY(op,e1))                            then 4 + hashOp(op)+hashExp(e1);
 case(DAE.RELATION(e1,op,e2,_,_))                   then 5 + hashExp(e1)+hashOp(op)+hashExp(e2);
 case(DAE.IFEXP(e1,e2,e3))                          then 6 + hashExp(e1)+hashExp(e2)+hashExp(e3);
 case(DAE.CALL(path=path,expLst=expl))              then 7 + stringHashDjb2(Absyn.pathString(path))+List.reduce(List.map(expl,hashExp),intAdd);
 case(DAE.RECORD(path=path,exps=expl))            then 8 + stringHashDjb2(Absyn.pathString(path))+List.reduce(List.map(expl,hashExp),intAdd);
 case(DAE.PARTEVALFUNCTION(path=path,expList=expl)) then 9 + stringHashDjb2(Absyn.pathString(path))+List.reduce(List.map(expl,hashExp),intAdd);
 case(DAE.ARRAY(array=expl))                        then 10 + List.reduce(List.map(expl,hashExp),intAdd);
 case(DAE.MATRIX(matrix=mexpl))                     then 11 + List.reduce(List.map(List.flatten(mexpl),hashExp),intAdd);
 case(DAE.RANGE(_,e1,SOME(e2),e3))                  then 12 + hashExp(e1)+hashExp(e2)+hashExp(e3);
 case(DAE.RANGE(_,e1,NONE(),e3))                    then 13 + hashExp(e1)+hashExp(e3);
 case(DAE.TUPLE(expl))                              then 14 + List.reduce(List.map(expl,hashExp),intAdd);
 case(DAE.CAST(_,e1))                               then 15 + hashExp(e1);
 case(DAE.ASUB(e1,expl))                            then 16 + hashExp(e1)+List.reduce(List.map(expl,hashExp),intAdd);
 case(DAE.TSUB(e1,i,_))                             then 17 + hashExp(e1)+stringHashDjb2(intString(i));
 case(DAE.SIZE(e1,SOME(e2)))                        then 18 + hashExp(e1)+hashExp(e2);
 case(DAE.SIZE(e1,NONE()))                          then 19 + hashExp(e1);
 // case(DAE.CODE(_,_))                             then 20; // TODO: implement hashing of CODE AST
 // case(DAE.EMPTY(scope=_))                        then 21; // TODO: implement hashing of EMTPY (needed ?)
 case(DAE.REDUCTION(info,e1,iters))                 then 22 + hashReductionInfo(info)+hashExp(e1)+List.reduce(List.map(iters,hashReductionIter),intAdd);
 // TODO: hashing of all MetaModelica extensions
 else stringHashDjb2(ExpressionDump.printExpStr(e));
 end matchcontinue;
end hashExp;


protected function hashReductionInfo "help function to hashExp"
  input DAE.ReductionInfo info;
  output Integer hash;
algorithm
  hash := match(info)
  local
    Absyn.Path path;

    // TODO: complete hasing of all subexpressions
    case (DAE.REDUCTIONINFO(path=path)) then 22 + stringHashDjb2(Absyn.pathString(path));
  end match;
end hashReductionInfo;

protected protected function hashReductionIter "help function to hashExp"
  input DAE.ReductionIterator iter;
  output Integer hash;
algorithm
  hash := match(iter)
  local
    String id;
    DAE.Exp e1,e2;


    case(DAE.REDUCTIONITER(id,e1,SOME(e2),_))       then 23 + stringHashDjb2(id)+hashExp(e1)+hashExp(e2);
    case(DAE.REDUCTIONITER(id,e1,NONE(),_))         then 24 + stringHashDjb2(id)+hashExp(e1);
  end match;

end hashReductionIter;
protected protected function hashOp "help function to hashExp"
  input DAE.Operator op;
  output Integer hash;
algorithm
  hash := match(op)
    local
      Absyn.Path path;

    case(DAE.ADD(_))                                    then 25;
    case(DAE.SUB(_))                                    then 26;
    case(DAE.MUL(_))                                    then 27;
    case(DAE.DIV(_))                                    then 28;
    case(DAE.POW(_))                                    then 29;
    case(DAE.UMINUS(_))                                 then 30;
    case(DAE.UMINUS_ARR(_))                             then 31;
    case(DAE.ADD_ARR(_))                                then 32;
    case(DAE.SUB_ARR(_))                                then 33;
    case(DAE.MUL_ARR(_))                                then 34;
    case(DAE.DIV_ARR(_))                                then 35;
    case(DAE.MUL_ARRAY_SCALAR(_))                       then 36;
    case(DAE.ADD_ARRAY_SCALAR(_))                       then 37;
    case(DAE.SUB_SCALAR_ARRAY(_))                       then 38;
    case(DAE.MUL_SCALAR_PRODUCT(_))                     then 39;
    case(DAE.MUL_MATRIX_PRODUCT(_))                     then 40;
    case(DAE.DIV_ARRAY_SCALAR(_))                       then 41;
    case(DAE.DIV_SCALAR_ARRAY(_))                       then 42;
    case(DAE.POW_ARRAY_SCALAR(_))                       then 43;
    case(DAE.POW_SCALAR_ARRAY(_))                       then 44;
    case(DAE.POW_ARR(_))                                then 45;
    case(DAE.POW_ARR2(_))                               then 46;
    case(DAE.AND(_))                                    then 47;
    case(DAE.OR(_))                                     then 48;
    case(DAE.NOT(_))                                    then 49;
    case(DAE.LESS(_))                                   then 50;
    case(DAE.LESSEQ(_))                                 then 51;
    case(DAE.GREATER(_))                                then 52;
    case(DAE.GREATEREQ(_))                              then 53;
    case(DAE.EQUAL(_))                                  then 54;
    case(DAE.NEQUAL(_))                                 then 55;
    case(DAE.USERDEFINED(path))                         then 56 + stringHashDjb2(Absyn.pathString(path)) ;
    end match;
end hashOp;

public function matrixToArray
  input DAE.Exp inMatrix;
  output DAE.Exp outArray;
algorithm
  outArray := match(inMatrix)
    local
      DAE.Type ty, row_ty;
      list<list<Exp>> matrix;
      list<DAE.Exp> rows;

    case DAE.MATRIX(ty = ty, matrix = matrix)
      equation
        row_ty = unliftArray(ty);
        rows = List.map2(matrix, makeArray, row_ty, true);
      then
        DAE.ARRAY(ty, false, rows);

    else inMatrix;

  end match;
end matrixToArray;

public function transposeArray
  input DAE.Exp inArray;
  output DAE.Exp outArray;
  output Boolean outWasTransposed;
algorithm
  (outArray, outWasTransposed) := match(inArray)
    local
      DAE.Type ty, row_ty;
      DAE.Dimension dim1, dim2;
      DAE.Dimensions rest_dims;
      DAE.TypeSource ty_src;
      list<Exp> expl;
      list<list<Exp>> matrix;
      Integer i;

    // Empty array, just transpose the type.
    case DAE.ARRAY(DAE.T_ARRAY(ty, dim1 :: dim2 :: rest_dims, ty_src), _, {})
      then (DAE.ARRAY(DAE.T_ARRAY(ty, dim2 :: dim1 :: rest_dims, ty_src), false, {}), true);

    case DAE.ARRAY(DAE.T_ARRAY(ty, dim1 :: dim2 :: rest_dims, ty_src), _, expl)
      equation
        row_ty = DAE.T_ARRAY(ty, dim1 :: rest_dims, ty_src);
        matrix = List.map(expl, getArrayOrMatrixContents);
        matrix = List.transposeList(matrix);
        expl = List.map2(matrix, makeArray, row_ty, true);
      then
        (DAE.ARRAY(DAE.T_ARRAY(ty, dim2 :: dim1 :: rest_dims, ty_src), false, expl), true);

    case DAE.MATRIX (matrix=matrix,ty=DAE.T_ARRAY(ty, {dim1, dim2}, ty_src))
      equation
        matrix = List.transposeList(matrix);
        ty = DAE.T_ARRAY(ty, {dim2, dim1}, ty_src);
        i = listLength(matrix);
      then
        (DAE.MATRIX(ty,i,matrix), true);

    else (inArray, false);

  end match;
end transposeArray;

public function getCrefFromCrefOrAsub
  "Get the cref from an expression that might be ASUB. If so, return the base CREF (this function does *not* always return a CREF with the same type as the full expression)."
  input DAE.Exp exp;
  output DAE.ComponentRef cr;
algorithm
  cr := match exp
    case DAE.CREF(componentRef=cr) then cr;
    case DAE.ASUB(exp=DAE.CREF(componentRef=cr)) then cr;
  end match;
end getCrefFromCrefOrAsub;

public function arrayElements
  "Returns the array elements of an expression."
  input DAE.Exp inExp;
  output list<DAE.Exp> outExp;
algorithm
  outExp := match(inExp)
    local
      list<DAE.Exp> expl;
      DAE.ComponentRef cr;
      list<DAE.ComponentRef> crl;
      list<list<DAE.Exp>> mat;

    case DAE.CREF(componentRef = cr)
      equation
        crl = ComponentReference.expandCref(cr, false);
        expl = List.map(crl, crefExp);
      then
        expl;

    case DAE.ARRAY(array = expl, ty = DAE.T_ARRAY())
      then List.mapFlat(expl, arrayElements);

    case DAE.ARRAY(array = expl) then expl;

    case DAE.MATRIX(matrix = mat) then List.flatten(mat);

    else {inExp};

  end match;
end arrayElements;

public function arrayContent
  "Returns the contents of an array expression, i.e. a list of expressions."
  input DAE.Exp inExp;
  output list<DAE.Exp> outContent;
algorithm
  DAE.ARRAY(array = outContent) := inExp;
end arrayContent;

public function fromAbsynExp
"@author: adrpo
 transform Absyn.Exp into DAE.Exp, uknown types are used"
  input Absyn.Exp inAExp;
  output DAE.Exp outDExp;
algorithm
  outDExp := match(inAExp)
    local
      Integer i;
      Real r;
      Boolean b;
      String s;
      Absyn.Exp ae, ae1, ae2, cond;
      Absyn.Operator aop;
      Absyn.ComponentRef acr;
      list<Absyn.Exp> aexps;
      list<list<Absyn.Exp>> aexpslst;
      Absyn.FunctionArgs fargs;
      Absyn.Path p;
      Option<Absyn.Exp> aoe;
      DAE.ComponentRef cr;
      DAE.Exp e, e1, e2;
      DAE.Operator op;
      list<DAE.Exp> exps;
      list<list<DAE.Exp>> expslst;
      Option<DAE.Exp> oe;

    case (Absyn.INTEGER(i)) then DAE.ICONST(i);
    case (Absyn.REAL(s))
      equation
        r = System.stringReal(s);
      then DAE.RCONST(r);
    case (Absyn.BOOL(b)) then DAE.BCONST(b);
    case (Absyn.STRING(s)) then DAE.SCONST(s);

    case (Absyn.CREF(acr))
      equation
        cr = ComponentReference.toExpCref(acr);
        e = makeCrefExp(cr, DAE.T_UNKNOWN_DEFAULT);
      then
        e;

    case (Absyn.BINARY(ae1, aop, ae2))
      equation
        op = fromAbsynOperator(aop, DAE.T_UNKNOWN_DEFAULT);
        e1 = fromAbsynExp(ae1);
        e2 = fromAbsynExp(ae2);
        e = DAE.BINARY(e1, op, e2);
      then
        e;

    case (Absyn.UNARY(aop, ae))
      equation
        op = fromAbsynOperator(aop, DAE.T_UNKNOWN_DEFAULT);
        e = fromAbsynExp(ae);
        e = DAE.UNARY(op, e);
      then
        e;

    case (Absyn.LBINARY(ae1, aop, ae2))
      equation
        op = fromAbsynOperator(aop, DAE.T_UNKNOWN_DEFAULT);
        e1 = fromAbsynExp(ae1);
        e2 = fromAbsynExp(ae2);
        e = DAE.LBINARY(e1, op, e2);
      then
        e;

    case (Absyn.LUNARY(aop, ae))
      equation
        op = fromAbsynOperator(aop, DAE.T_UNKNOWN_DEFAULT);
        e = fromAbsynExp(ae);
        e = DAE.LUNARY(op, e);
      then
        e;

    case (Absyn.RELATION(ae1, aop, ae2))
      equation
        op = fromAbsynOperator(aop, DAE.T_UNKNOWN_DEFAULT);
        e1 = fromAbsynExp(ae1);
        e2 = fromAbsynExp(ae2);
        e = DAE.RELATION(e1, op, e2, 0, NONE());
      then
        e;

    case (ae as Absyn.IFEXP())
      equation
        Absyn.IFEXP(ifExp = cond, trueBranch = ae1, elseBranch = ae2) = Absyn.canonIfExp(ae);
        e = fromAbsynExp(cond);
        e1 = fromAbsynExp(ae1);
        e2 = fromAbsynExp(ae2);
        e = DAE.IFEXP(e, e1, e2);
      then
        e;

    case (Absyn.CALL(acr, fargs))
      equation
        exps = fargsToExps(fargs);
        p = Absyn.crefToPath(acr);
        e = DAE.CALL(p, exps, DAE.callAttrBuiltinOther);
      then
        e;

    case (Absyn.PARTEVALFUNCTION(acr, fargs))
      equation
        exps = fargsToExps(fargs);
        p = Absyn.crefToPath(acr);
        e = DAE.PARTEVALFUNCTION(p, exps, DAE.T_UNKNOWN_DEFAULT, DAE.T_UNKNOWN_DEFAULT);
      then
        e;

    case (Absyn.ARRAY(aexps))
      equation
        exps = List.map(aexps, fromAbsynExp);
        e = DAE.ARRAY(DAE.T_UNKNOWN_DEFAULT, false, exps);
      then
        e;

    case (Absyn.MATRIX(aexpslst))
      equation
        expslst = List.mapList(aexpslst, fromAbsynExp);
        i = listLength(List.first(expslst));
        e = DAE.MATRIX(DAE.T_UNKNOWN_DEFAULT, i, expslst);
      then
        e;

    case (Absyn.RANGE(ae1, aoe, ae2))
      equation
        e1 = fromAbsynExp(ae1);
        e2 = fromAbsynExp(ae2);
        oe = fromAbsynExpOpt(aoe);
        e = DAE.RANGE(DAE.T_UNKNOWN_DEFAULT, e1, oe, e2);
      then
        e;

    case (Absyn.TUPLE(aexps))
      equation
        exps = List.map(aexps, fromAbsynExp);
        e = DAE.TUPLE(exps);
      then
        e;

    else
    equation
      print("Expression.fromAbsynExp: Unhandled expression: " + Dump.printExpStr(inAExp) + "\n");
    then
      fail();

  end match;
end fromAbsynExp;

public function fargsToExps
  input Absyn.FunctionArgs inFargs;
  output list<DAE.Exp> outExps;
algorithm
  outExps := matchcontinue(inFargs)
    local
      list<DAE.Exp> exps;
      list<Absyn.NamedArg> nargs;
      list<Absyn.Exp> aexps;

    case (Absyn.FUNCTIONARGS(aexps, {}))
      equation
        exps = List.map(aexps, fromAbsynExp);
      then
        exps;

    case (Absyn.FUNCTIONARGS(_, _))
      equation
        print("Expression.fargsToExps: Named arguments are not handled!\n");
      then
        {};

  end matchcontinue;
end fargsToExps;

protected function fromAbsynExpOpt
  input Option<Absyn.Exp> aoe;
  output Option<DAE.Exp> oe;
algorithm
  oe := match(aoe)
    local
      Absyn.Exp ae;
      DAE.Exp e;

    case (NONE()) then NONE();

    case (SOME(ae))
      equation
        e = fromAbsynExp(ae);
      then
        SOME(e);

  end match;
end fromAbsynExpOpt;

protected function fromAbsynOperator
"@author: adrpo"
 input Absyn.Operator aop;
 input DAE.Type ty;
 output DAE.Operator op;
algorithm
  op := match(aop, ty)
    case(Absyn.ADD(), _) then DAE.ADD(ty);
    case(Absyn.SUB(), _) then DAE.SUB(ty);
    case(Absyn.MUL(), _) then DAE.MUL(ty);
    case(Absyn.DIV(), _) then DAE.DIV(ty);
    case(Absyn.POW(), _) then DAE.POW(ty);
    case(Absyn.UMINUS(), _) then DAE.UMINUS(ty);
    case(Absyn.AND(), _) then DAE.AND(ty);
    case(Absyn.OR(), _) then DAE.OR(ty);
    case(Absyn.NOT(), _) then DAE.NOT(ty);
    case(Absyn.LESS(), _) then DAE.LESS(ty);
    case(Absyn.LESSEQ(), _) then DAE.LESSEQ(ty);
    case(Absyn.GREATER(), _) then DAE.GREATER(ty);
    case(Absyn.GREATEREQ(), _) then DAE.GREATEREQ(ty);
    case(Absyn.EQUAL(), _) then DAE.EQUAL(ty);
    case(Absyn.NEQUAL(), _) then DAE.NEQUAL(ty);
    else
    equation
      print("Expression.fromAbsynOperator: Unhandled operator: " + Dump.opSymbol(aop) + "\n");
    then
      fail();
  end match;
end fromAbsynOperator;

public function replaceDerOpInExp
  "Replaces all der(cref) with $DER.cref in an expression."
  input DAE.Exp inExp;
  output DAE.Exp outExp;
algorithm
  (outExp, _) := traverseExp(inExp, replaceDerOpInExpTraverser, NONE());
end replaceDerOpInExp;

public function replaceDerOpInExpCond
  "Replaces der(cref) with $DER.cref in an expression, where the cref to replace
  is explicitly given."
  input DAE.Exp e;
  input Option<DAE.ComponentRef> cr;
  output DAE.Exp outExp;
  output Option<DAE.ComponentRef> outCr;
algorithm
  (outExp, outCr) := traverseExp(e, replaceDerOpInExpTraverser, cr);
end replaceDerOpInExpCond;

public function replaceDerOpInExpTraverser
  "Used with Expression.traverseExp to traverse an expression an replace calls to
  der(cref) with a component reference $DER.cref. If an optional component
  reference is supplied, then only that component reference is replaced.
  Otherwise all calls to der are replaced.

  This is done since some parts of the compiler can't handle der-calls, such as
  Derive.differentiateExpression. Ideally these parts should be fixed so that they can
  handle der-calls, but until that happens we just replace the der-calls with
  crefs."
  input DAE.Exp e;
  input Option<DAE.ComponentRef> optCr;
  output DAE.Exp outExp;
  output Option<DAE.ComponentRef> outCr;
algorithm
  (outExp,outCr) := matchcontinue (e,optCr)
    local
      DAE.ComponentRef cr, derCr;
      DAE.Exp cref_exp;
      DAE.ComponentRef cref;

    case (DAE.CALL(path = Absyn.IDENT("der"), expLst = {DAE.CREF(componentRef = cr)}), SOME(cref))
      equation
        derCr = ComponentReference.crefPrefixDer(cr);
        true = ComponentReference.crefEqualNoStringCompare(derCr, cref);
        cref_exp = crefExp(derCr);
      then (cref_exp, SOME(cref));

    case (DAE.CALL(path = Absyn.IDENT("der"), expLst = {DAE.CREF(componentRef = cr)}), NONE())
      equation
        cr = ComponentReference.crefPrefixDer(cr);
        cref_exp = crefExp(cr);
      then (cref_exp, NONE());
    else (e,optCr);
  end matchcontinue;
end replaceDerOpInExpTraverser;

public function makeBinaryExp
  input DAE.Exp inLhs;
  input DAE.Operator inOp;
  input DAE.Exp inRhs;
  output DAE.Exp outExp;
algorithm
  outExp := DAE.BINARY(inLhs, inOp, inRhs);
end makeBinaryExp;

public function checkDimensionSizes
  "Extracts an integer from an array dimension. Also handles DIM_EXP and
  DIM_UNKNOWN if checkModel is used."
  input DAE.Dimension dim;
  output Boolean value;
  protected
      Integer i;
      DAE.Exp e;
algorithm
  value := matchcontinue(dim)

    case DAE.DIM_INTEGER(integer = i) then true;
    case DAE.DIM_ENUM(size = i) then true;
    case DAE.DIM_BOOLEAN() then true;
    case DAE.DIM_EXP(exp = e) then true;
    case DAE.DIM_EXP()
      then
        false;
    case DAE.DIM_UNKNOWN()
      then
        false;
  end matchcontinue;
end checkDimensionSizes;

public function dimensionsList
  "Extracts a list of integers from a list of array dimensions"
  input DAE.Dimensions inDims;
  output list<Integer> outValues;
protected
  list<Boolean> boolHelperList;
  list<Integer> dims;
algorithm
 outValues := matchcontinue(inDims)
    case (_)
    equation
    boolHelperList = List.map(inDims, checkDimensionSizes);
    true = List.reduce(boolHelperList,boolAnd);
    dims = List.map(inDims, dimensionSizeAll);
    then dims;
    case (_)
      then {};
   end matchcontinue;
end dimensionsList;

public function isCrefListWithEqualIdents
  "Checks if all expressions in the given list are crefs with the same identifiers.
    e.g.  {A[1],A[2],…,A[n]} -> true
          {A[1],B[1]} -> false"
  input list<DAE.Exp> iExpressions;
  output Boolean oCrefWithEqualIdents;
protected
  Boolean tmpCrefWithEqualIdents;
  list<Boolean> boolHelperList;
  list<DAE.ComponentRef> crefs;
  DAE.Exp head;
  DAE.ComponentRef headCref;
algorithm
  oCrefWithEqualIdents := matchcontinue(iExpressions)
    case(head::_)
      equation
        //print("isCrefListWithEqualIdents: \n" + stringDelimitList(List.map1(iExpressions, ExpressionDump.dumpExpStr, 1), ""));
        boolHelperList = List.map(iExpressions, isCref);
        true = List.reduce(boolHelperList,boolAnd);
        //print("isCrefListWithEqualIdents: all crefs!\n");
        crefs = List.map(iExpressions, expCref);
        headCref = expCref(head);
        boolHelperList = List.map1(crefs, ComponentReference.crefEqualWithoutLastSubs, headCref);
        tmpCrefWithEqualIdents = List.reduce(boolHelperList,boolAnd);
        //print("isCrefListWithEqualIdents: returns " + boolString(tmpCrefWithEqualIdents) + "\n\n");
      then tmpCrefWithEqualIdents;
    case({})
      then true;
    else
      equation
        //print("isCrefListWithEqualIdents: returns false\n\n");
      then false;
  end matchcontinue;
end isCrefListWithEqualIdents;

protected function traverseExpDerPreStart
" TODO: REPLACE THIS ABOMINATION WITH A BETTER traverseExp

  Traverses all subexpressions of an expression.
  Takes a function and an extra argument passed through the traversal.
  The function can potentially change the expression. In such cases,
  the changes are made bottom-up, i.e. a subexpression is traversed
  and changed before the complete expression is traversed.

  NOTE: The user-provided function is not allowed to fail! If you want to
  detect a failure, return NONE() in your user-provided datatype.

  mahge : This function will not treat der(), pre() and start() as calls
  but as unique ids. i.e. x is different from der(x) and given der(x) x will not
  be extreacted as a unique id. Instead you get $DER.x. Same oes for pre and start.
"
  replaceable type Type_a subtypeof Any;
  input DAE.Exp inExp;
  input FuncExpType func;
  input Type_a inTypeA;
  output DAE.Exp outExp;
  output Type_a outA;
  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Type_a outA;
  end FuncExpType;
algorithm
  (outExp,outA) := match (inExp,func,inTypeA)
    local
      DAE.Exp e1_1,e,e1,e2_1,e2,e3_1,e3;
      Type_a ext_arg_1,ext_arg_2,ext_arg,ext_arg_3,ext_arg_4;
      Operator op;
      FuncExpType rel;
      list<DAE.Exp> expl_1,expl;
      Absyn.Path fn;
      Boolean scalar;
      Type tp, t;
      Integer i;
      list<list<DAE.Exp>> lstexpl_1,lstexpl;
      Integer dim;
      String str;
      list<DAE.Element> localDecls;
      tuple<DAE.Exp,Type_a> res;
      list<String> fieldNames;
      DAE.CallAttributes attr;
      list<DAE.MatchCase> cases,cases_1;
      DAE.MatchType matchTy;
      Integer index_;
      Option<tuple<DAE.Exp,Integer,Integer>> isExpisASUB;
      DAE.ReductionInfo reductionInfo;
      DAE.ReductionIterators riters,riters_1;
      DAE.ComponentRef cr,cr_1;
      list<list<String>> aliases;

    case ((e as DAE.EMPTY()),rel,ext_arg)
      equation
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case ((e as DAE.ICONST(_)),rel,ext_arg)
      equation
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case ((e as DAE.RCONST(_)),rel,ext_arg)
      equation
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case ((e as DAE.SCONST(_)),rel,ext_arg)
      equation
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case ((e as DAE.BCONST(_)),rel,ext_arg)
      equation
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case ((e as DAE.ENUM_LITERAL()),rel,ext_arg)
      equation
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.CREF(cr,tp),rel,ext_arg)
      equation
        (cr_1,ext_arg) = traverseExpCref(cr, rel, ext_arg);
        e = if referenceEq(cr,cr_1) then inExp else DAE.CREF(cr_1,tp);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // unary
    case (DAE.UNARY(operator = op,exp = e1),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.UNARY(op,e1_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // binary
    case (DAE.BINARY(exp1 = e1,operator = op,exp2 = e2),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExpDerPreStart(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.BINARY(e1_1,op,e2_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // logical unary
    case (DAE.LUNARY(operator = op,exp = e1),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.LUNARY(op,e1_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // logical binary
    case (DAE.LBINARY(exp1 = e1,operator = op,exp2 = e2),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExpDerPreStart(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.LBINARY(e1_1,op,e2_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // relation
    case (DAE.RELATION(exp1 = e1,operator = op,exp2 = e2, index=index_, optionExpisASUB= isExpisASUB),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExpDerPreStart(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.RELATION(e1_1,op,e2_1,index_,isExpisASUB);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // if expressions
    case (DAE.IFEXP(expCond = e1,expThen = e2,expElse = e3),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExpDerPreStart(e2, rel, ext_arg);
        (e3_1,ext_arg) = traverseExpDerPreStart(e3, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) and referenceEq(e3,e3_1) then inExp else DAE.IFEXP(e1_1,e2_1,e3_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.CALL(path = fn,expLst = expl,attr = attr),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpDerPreStartList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.CALL(fn,expl_1,attr);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.RECORD(path = fn,exps = expl,comp = fieldNames, ty = tp),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpDerPreStartList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.RECORD(fn,expl_1,fieldNames,tp);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.PARTEVALFUNCTION(fn, expl, tp, t),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpDerPreStartList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.PARTEVALFUNCTION(fn,expl_1,tp,t);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.ARRAY(ty = tp,scalar = scalar,array = expl),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpDerPreStartList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.ARRAY(tp,scalar,expl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.MATRIX(ty = tp,integer = dim, matrix=lstexpl),rel,ext_arg)
      equation
        (lstexpl_1,ext_arg) = traverseExpMatrix(lstexpl, rel, ext_arg);
        e = if referenceEq(lstexpl,lstexpl_1) then inExp else DAE.MATRIX(tp,dim,lstexpl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.RANGE(ty = tp,start = e1,step = NONE(),stop = e2),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExpDerPreStart(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.RANGE(tp,e1_1,NONE(),e2_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.RANGE(ty = tp,start = e1,step = SOME(e2),stop = e3),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExpDerPreStart(e2, rel, ext_arg);
        (e3_1,ext_arg) = traverseExpDerPreStart(e3, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) and referenceEq(e3,e3_1) then inExp else DAE.RANGE(tp,e1_1,SOME(e2_1),e3_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.TUPLE(PR = expl),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpDerPreStartList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.TUPLE(expl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.CAST(ty = tp,exp = e1),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.CAST(tp,e1_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.ASUB(exp = e1,sub = expl),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        (expl_1,ext_arg) = traverseExpDerPreStartList(expl, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(expl,expl_1) then inExp else makeASUB(e1_1,expl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.TSUB(e1,i,tp),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.TSUB(e1_1,i,tp);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.SIZE(exp = e1,sz = NONE()),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.SIZE(e1_1,NONE());
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.SIZE(exp = e1,sz = SOME(e2)),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExpDerPreStart(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.SIZE(e1_1,SOME(e2_1));
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.REDUCTION(reductionInfo=reductionInfo,expr = e1,iterators = riters),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        (riters_1,ext_arg) = traverseReductionIterators(riters, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(riters,riters_1) then inExp else DAE.REDUCTION(reductionInfo,e1_1,riters_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    // MetaModelica list
    case (DAE.CONS(e1,e2),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        (e2_1,ext_arg) = traverseExpDerPreStart(e2, rel, ext_arg);
        e = if referenceEq(e1,e1_1) and referenceEq(e2,e2_1) then inExp else DAE.CONS(e1_1,e2_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.LIST(expl),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpDerPreStartList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.LIST(expl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.META_TUPLE(expl),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpDerPreStartList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.META_TUPLE(expl_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.META_OPTION(NONE()),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.META_OPTION(SOME(e1)),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.META_OPTION(SOME(e1_1));
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.BOX(e1),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.BOX(e1_1);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.UNBOX(e1,tp),rel,ext_arg)
      equation
        (e1_1,ext_arg) = traverseExpDerPreStart(e1, rel, ext_arg);
        e = if referenceEq(e1,e1_1) then inExp else DAE.UNBOX(e1_1,tp);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.METARECORDCALL(fn,expl,fieldNames,i),rel,ext_arg)
      equation
        (expl_1,ext_arg) = traverseExpDerPreStartList(expl, rel, ext_arg);
        e = if referenceEq(expl,expl_1) then inExp else DAE.METARECORDCALL(fn,expl_1,fieldNames,i);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);
    // ---------------------

    case (DAE.MATCHEXPRESSION(matchTy,expl,aliases,localDecls,cases,tp),rel,ext_arg)
      equation
        // Don't traverse the local declarations; we don't store bindings there (yet)
        (expl_1,ext_arg) = traverseExpDerPreStartList(expl, rel, ext_arg);
        (cases_1,ext_arg) = Patternm.traverseCases(cases,rel,ext_arg);
        e = if referenceEq(expl,expl_1) and referenceEq(cases,cases_1) then inExp else DAE.MATCHEXPRESSION(matchTy,expl_1,aliases,localDecls,cases_1,tp);
        (e,ext_arg) = rel(e,ext_arg);
      then (e,ext_arg);

    case (DAE.SHARED_LITERAL(),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    case (DAE.PATTERN(),rel,ext_arg)
      equation
        (e,ext_arg) = rel(inExp,ext_arg);
      then (e,ext_arg);

    // Why don't we call rel() for these expressions?
    case (DAE.CODE(),_,ext_arg) then (inExp,ext_arg);

    else
      equation
        str = ExpressionDump.printExpStr(inExp);
        str = "Expression.traverseExpDerPreStart or one of the user-defined functions using it is not implemented correctly: " + str;
        Error.addMessage(Error.INTERNAL_ERROR, {str});
      then fail();
  end match;
end traverseExpDerPreStart;

protected function traverseExpDerPreStartList
" TODO: REPLACE THIS ABOMINATION WITH A BETTER traverseExp

  author mahge: Same as traverseExpList except:
  This function will not treat der(), pre() and start() as calls
  but as unique ids. i.e. x is different from der(x) and given der(x) x will not
  be extreacted as a unique id. Instead you get $DER.x. Same oes for pre and start.."

  replaceable type Type_a subtypeof Any;
  input list<DAE.Exp> inExpl;
  input FuncExpType rel;
  input Type_a iext_arg;
  output list<DAE.Exp> outExpl;
  output Type_a outA;
  partial function FuncExpType
    input DAE.Exp inExp;
    input Type_a inTypeA;
    output DAE.Exp outExp;
    output Type_a outA;
  end FuncExpType;
algorithm
  (outExpl,outA) := match(inExpl,rel,iext_arg)
    local
      DAE.Exp e,e1;
      list<DAE.Exp> expl,expl1;
      Type_a ext_arg;

    case ({},_,ext_arg) then (inExpl,ext_arg);

    case (e::expl,_,ext_arg)
      equation
        (e1,ext_arg) = traverseExpDerPreStart(e, rel, ext_arg);
        (expl1,ext_arg) = traverseExpDerPreStartList(expl,rel,ext_arg);
        expl = if referenceEq(e,e1) and referenceEq(expl,expl1) then inExpl else (e1::expl1);
      then (expl,ext_arg);
  end match;
end traverseExpDerPreStartList;

public function renameExpCrefIdent
  input DAE.Exp inExp;
  input tuple<String,String> inTpl;
  output DAE.Exp outExp;
  output tuple<String,String> outTpl;
algorithm
  (outExp,outTpl) := match (inExp,inTpl)
    local
      DAE.Type ty1,ty2;
      String name,from,to;
      DAE.Exp exp;
    case (DAE.CREF(DAE.CREF_IDENT(name,ty1,{}),ty2),(from,to))
      equation
        exp = if stringEq(name,from) then DAE.CREF(DAE.CREF_IDENT(to,ty1,{}),ty2) else inExp;
      then (exp,inTpl);
    else (inExp,inTpl);
  end match;
end renameExpCrefIdent;

public function emptyToWild
  input DAE.Exp exp;
  output DAE.Exp outExp;
protected
  DAE.Type ty;
algorithm
  ty := typeof(exp);
  outExp := if Types.isZeroLengthArray(ty) then DAE.CREF(DAE.WILD(),ty) else exp;
end emptyToWild;

public function makeVectorCall
  input DAE.Exp exp;
  input DAE.Type tp;
  output DAE.Exp outExp;
algorithm
  outExp := makePureBuiltinCall("vector",{exp},tp);
end makeVectorCall;

public function extendArrExp "author: Frenkel TUD 2010-07
  alternative name: vectorizeExp"
  input DAE.Exp inExp;
  input Boolean inExpanded "True if something was expanded, otherwise false.";
  output DAE.Exp outExp;
  output Boolean outExpanded;
algorithm
  (outExp, outExpanded) := matchcontinue (inExp, inExpanded)
    local
      DAE.Exp exp;
      Boolean b;

    case (outExp, _)
      equation
        (exp, b) = traverseExp(inExp, traversingextendArrExp, false);
      then
        (exp, b);

    else (inExp, inExpanded);

  end matchcontinue;
end extendArrExp;

protected function traversingextendArrExp "author: Frenkel TUD 2010-07.
  This function extend all array and record componentrefs to their
  elements. This is necessary for BLT and substitution of simple
  equations."
  input DAE.Exp inExp;
  input Boolean inExpanded;
  output DAE.Exp outExp;
  output Boolean outExpanded;
algorithm
  (outExp, outExpanded) := matchcontinue(inExp, inExpanded)
    local
      DAE.ComponentRef cr;
      list<DAE.ComponentRef> crlst;
      DAE.Type t,ty;
      DAE.Dimension id, jd;
      list<DAE.Dimension> ad;
      Integer i,j;
      list<list<DAE.Subscript>> subslst,subslst1;
      list<DAE.Subscript> sublstcref;
      list<DAE.Exp> expl;
      DAE.Exp e,e_new;
      list<DAE.Var> varLst;
      Absyn.Path name;
      list<list<DAE.Exp>> mat;
      Boolean b;

    // CASE for Matrix
    case (DAE.CREF(componentRef=cr,ty= t as DAE.T_ARRAY(ty=ty,dims=ad as {id, jd})), _)
      equation
        i = dimensionSize(id);
        j = dimensionSize(jd);
        subslst = List.map(ad, expandDimension);
        subslst1 = rangesToSubscripts(subslst);
        cr = ComponentReference.crefStripLastSubs(cr);
        crlst = List.map1r(subslst1,ComponentReference.subscriptCref,cr);
        expl = List.map1(crlst,makeCrefExp,ty);
        mat = makeMatrix(expl,j,j,{});
        e_new = DAE.MATRIX(t,i,mat);
        (e, b) = traverseExp(e_new, traversingextendArrExp, true);
      then
        (e, b);

    // CASE for Matrix and checkModel is on
    case (DAE.CREF(componentRef=cr,ty= t as DAE.T_ARRAY(ty=ty,dims=ad as {_, _})), _)
      equation
        true = Flags.getConfigBool(Flags.CHECK_MODEL);
        // consider size 1
        i = dimensionSize(DAE.DIM_INTEGER(1));
        j = dimensionSize(DAE.DIM_INTEGER(1));
        subslst = List.map(ad, expandDimension);
        subslst1 = rangesToSubscripts(subslst);
        crlst = List.map1r(subslst1,ComponentReference.subscriptCref,cr);
        expl = List.map1(crlst,makeCrefExp,ty);
        mat = makeMatrix(expl,j,j,{});
        e_new = DAE.MATRIX(t,i,mat);
        (e, b) = traverseExp(e_new, traversingextendArrExp, true);
      then
        (e, b);

    // CASE for Array
    case (DAE.CREF(componentRef=cr,ty= t as DAE.T_ARRAY(ty=ty,dims=ad)), _)
      equation
        sublstcref = ComponentReference.crefSubs(cr);
        subslst = List.map(ad, expandDimension);
        subslst1 = rangesToSubscripts(subslst);
        subslst = insertSubScripts(sublstcref,subslst1,{});
        subslst1 = subslst;
        cr = ComponentReference.crefStripLastSubs(cr);
        crlst = List.map1r(subslst1,ComponentReference.subscriptCref,cr);
        expl = List.map1(crlst,makeCrefExp,ty);
        e_new = DAE.ARRAY(t,true,expl);
        (e, b) = traverseExp(e_new, traversingextendArrExp, true);
      then
        (e, b);

    // CASE for Array and checkModel is on
    case (DAE.CREF(componentRef=cr,ty= t as DAE.T_ARRAY(ty=ty)), _)
      equation
        true = Flags.getConfigBool(Flags.CHECK_MODEL);
        // consider size 1
        subslst = {{DAE.INDEX(DAE.ICONST(1))}};
        subslst1 = rangesToSubscripts(subslst);
        crlst = List.map1r(subslst1,ComponentReference.subscriptCref,cr);
        expl = List.map1(crlst,makeCrefExp,ty);
        e_new = DAE.ARRAY(t,true,expl);
        (e, b) = traverseExp(e_new, traversingextendArrExp, true);
      then
        (e, b);

    // CASE for Records
    case (DAE.CREF(componentRef=cr,ty= t as DAE.T_COMPLEX(varLst=varLst,complexClassType=ClassInf.RECORD(name))), _)
      equation
        expl = List.map1(varLst,generateCrefsExpFromExpVar,cr);
        i = listLength(expl);
        true = intGt(i,0);
        e_new = DAE.CALL(name,expl,DAE.CALL_ATTR(t,false,false,false,false,DAE.NO_INLINE(),DAE.NO_TAIL()));
        (e, b) = traverseExp(e_new, traversingextendArrExp, true);
      then
        (e, b);

    else (inExp, inExpanded);

  end matchcontinue;
end traversingextendArrExp;

protected function insertSubScripts"traverses the subscripts of the templSubScript and searches for wholedim. the value replaces the wholedim.
If there are multiple values, the templSubScript will be used for each of them and multiple new subScriptLsts are created.
author:Waurich TUD 2014-04"
  input list<DAE.Subscript> templSubScript;
  input list<list<DAE.Subscript>> value;
  input list<DAE.Subscript> lstIn;
  output list<list<DAE.Subscript>> outSubScript;
algorithm
  outSubScript := matchcontinue(templSubScript,value,lstIn)
    local
      Integer i;
      DAE.Subscript sub;
      list<DAE.Subscript> rest,lst,val;
      list<list<DAE.Subscript>> lsts;
    case(DAE.WHOLEDIM()::rest,_,_)
      equation
        // found a wholedim, replace with value, insert in lst
        lsts = List.map(value,listReverse);
        lsts = List.map1(lsts,listAppend,lstIn);
        rest = listReverse(rest);
        lsts = List.map1(lsts,List.appendr,rest);
        lsts = List.map(lsts,listReverse);
      then
        lsts;
    case(DAE.INDEX()::rest,_,_)
      equation
        sub = List.first(templSubScript);
        lsts = insertSubScripts(rest,value,sub::lstIn);
      then
        lsts;
    else
      then
        value;
  end matchcontinue;
end insertSubScripts;

protected function makeMatrix
  input list<DAE.Exp> expl;
  input Integer r;
  input Integer n;
  input list<DAE.Exp> incol;
  output list<list<DAE.Exp>> scalar;
algorithm
  scalar := matchcontinue (expl, r, n, incol)
    local
      DAE.Exp e;
      list<DAE.Exp> rest;
      list<list<DAE.Exp>> res;
      list<DAE.Exp> col;
  case({},_,_,_)
    equation
      col = listReverse(incol);
    then {col};
  case(e::rest,_,_,_)
    equation
      true = intEq(r,0);
      col = listReverse(incol);
      res = makeMatrix(e::rest,n,n,{});
    then
      (col::res);
  case(e::rest,_,_,_)
    equation
      res = makeMatrix(rest,r-1,n,e::incol);
    then
      res;
  end matchcontinue;
end makeMatrix;

public function rangesToSubscripts
  "This function takes a list of subscript ranges representing dimensions, e.g.
    {{1, 2, 3}, {1, 2}} which corresponds to dimensions [3, 2], and generates
    all subscript combinations, e.g. {{1, 1}, {1, 2}, {2, 1}, {2, 2}, {3, 1},
    {3, 2}}."
  input list<list<DAE.Subscript>> inRangelist;
  output list<list<DAE.Subscript>> outSubslst;
algorithm
  outSubslst := Util.allCombinations(inRangelist, NONE(), Absyn.dummyInfo);
end rangesToSubscripts;

public function expandSubscript
  "Expands a subscript into a list of subscripts. Also takes a dimension to be
   able to evaluate : subscripts."
  input DAE.Subscript inSubscript;
  input DAE.Dimension inDimension;
  output list<DAE.Subscript> outSubscripts;
algorithm
  outSubscripts := match(inSubscript, inDimension)
    local
      DAE.Exp exp;

    // An index subscript from range.
    case (DAE.INDEX(exp = exp as DAE.RANGE()), _)
      then getRangeContents(exp);

    // An index subscript, return it as an array.
    case (DAE.INDEX(), _) then {inSubscript};

    // A : subscript, use the dimension to generate all subscripts.
    case (DAE.WHOLEDIM(), _)
      then expandDimension(inDimension);

    // A slice subscript.
    case (DAE.SLICE(exp = exp), _)
      then expandSlice(exp);

  end match;
end expandSubscript;

protected function getRangeContents
  input DAE.Exp inExp;
  output list<DAE.Subscript> outSubscripts;
protected
  Integer istart, istep, istop;
  Option<DAE.Exp> iostep;
algorithm
  DAE.RANGE(DAE.T_INTEGER(), DAE.ICONST(istart), iostep,
    DAE.ICONST(istop)) := inExp;
  DAE.ICONST(istep) := Util.getOptionOrDefault(iostep, DAE.ICONST(1));
  outSubscripts := intSubscripts(List.intRange3(istart, istep, istop));
end getRangeContents;

public function expandDimension
  "Generates a list of subscripts given an array dimension."
  input DAE.Dimension inDimension;
  output list<DAE.Subscript> outSubscript;
algorithm
  outSubscript := match(inDimension)
    local
      Integer dim_int;
      Absyn.Path enum_ty;
      list<String> enum_lits;
      list<DAE.Exp> enum_expl;

    // An integer dimension, generate a list of integer subscripts.
    case DAE.DIM_INTEGER(integer = dim_int)
      then dimensionSizeSubscripts(dim_int);

    // An enumeration dimension, construct all enumeration literals and make
    // subscript out of them.
    case DAE.DIM_ENUM(enumTypeName = enum_ty, literals = enum_lits)
      equation
        enum_expl = makeEnumLiterals(enum_ty, enum_lits);
      then
        List.map(enum_expl, makeIndexSubscript);

    case DAE.DIM_BOOLEAN()
      then DAE.INDEX(DAE.BCONST(false))::DAE.INDEX(DAE.BCONST(true))::{};

    else {};
  end match;
end expandDimension;

protected function expandSlice
  "Expands a slice subscript expression."
  input DAE.Exp inSliceExp;
  output list<DAE.Subscript> outSubscripts;
algorithm
  outSubscripts := match(inSliceExp)
    local
      list<DAE.Exp> expl;
      String exp_str, err_str;

    case DAE.ARRAY(array = expl)
      then List.map(expl, makeIndexSubscript);

  end match;
end expandSlice;

public function dimensionSizesSubscripts
  input list<Integer> inDimSizes;
  output list<list<DAE.Subscript>> outSubscripts;
algorithm
  outSubscripts := List.map(inDimSizes, dimensionSizeSubscripts);
end dimensionSizesSubscripts;

public function dimensionSizesSubcriptsOpt
  input list<Option<Integer>> inDimSizes;
  output list<list<DAE.Subscript>> outSubscripts;
algorithm
  outSubscripts := List.mapOption(inDimSizes, dimensionSizeSubscripts);
end dimensionSizesSubcriptsOpt;

public function dimensionSizeSubscripts
  "Converts a dimension size in the form of an integer into a list of
   subscripts, e.g.: [3] => {1, 2, 3}."
  input Integer inDimSize;
  output list<DAE.Subscript> outSubscripts;
algorithm
  outSubscripts := list(DAE.INDEX(DAE.ICONST(i)) for i in 1:inDimSize);
end dimensionSizeSubscripts;

public function createResidualExp
"author: Frenkel TUD 2012-10
  do some numerical helpfull thinks like
  a = b/c - > a*c-b"
  input DAE.Exp inExp1;
  input DAE.Exp inExp2;
  output DAE.Exp resExp;
protected
  DAE.Exp iExp1, iExp2;
algorithm
  (iExp1,iExp2) := createResidualExp2(inExp1,inExp2);

  resExp := matchcontinue(iExp1, iExp2)
    local
      DAE.Exp e, e1, e2, res, res1, res2, N1, D1, N2, D2, N ,D;
      list<DAE.Exp> explst, explst1, mexplst;
      DAE.Type ty;

    case(_, DAE.RCONST(real = 0.0)) then iExp1;
    case(_, DAE.ICONST(0)) then iExp1;
    case(DAE.RCONST(real = 0.0), _) then iExp2;
    case(DAE.ICONST(0), _) then iExp2;
    case(_, _)
      equation
        ty = typeof(iExp1);
        true = Types.isIntegerOrRealOrSubTypeOfEither(ty);
        // get terms
        explst = terms(iExp1);
        explst1 = terms(iExp2);
        // N1/D1 = N2/D2
        (N1,D1) = makeFraction(iExp1);
        (N2,D2) = makeFraction(iExp2);
        // N1*D2 = N2*D1
        res1 = expMul(N1,D2);
        res2 = expMul(N2,D1);

        if isConst(res1) or (listLength(explst1) + 1) > listLength(explst) then //heuristic
          res = expSub(res2,res1);
        else
          res = expSub(res1,res2);
        end if;

        (res, _) = ExpressionSimplify.simplify(res);
      then
        res;
    case(_, _)
      equation
        ty = typeof(iExp1);
        true = Types.isEnumeration(ty);
        res = expSub(iExp1, iExp2);
      then
        res;
    case(_, _)
      equation
        ty = typeof(iExp1);
        true = Types.isBooleanOrSubTypeBoolean(ty);
        res = DAE.LUNARY(DAE.NOT(ty), DAE.RELATION(iExp1, DAE.EQUAL(ty), iExp2, -1, NONE()));
      then
        res;
    case(_, _)
      equation
        ty = typeof(iExp1);
        true = Types.isStringOrSubTypeString(ty);
        res = DAE.LUNARY(DAE.NOT(ty), DAE.RELATION(iExp1, DAE.EQUAL(ty), iExp2, -1, NONE()));
      then
        res;
    else
      equation
        res = expSub(iExp1, iExp2);
       (res, _) = ExpressionSimplify.simplify(res);
      then
        res;
  end matchcontinue;
end createResidualExp;

public function makeFraction
"
In: f(x) {+,-} g(x)
Out: {N,D}

where f(x) {+,-} g(x) = N/D

author: Vitalij Ruge

"
  input DAE.Exp iExp;
  output DAE.Exp n "numerator";
  output DAE.Exp d "denominator";
protected
  list<DAE.Exp> N, D, T;
  DAE.Type tp := typeof(iExp);
algorithm
  T := terms(iExp);
  T := ExpressionSimplify.simplifyList(T, {});
  (N,D) := moveDivToMul(T, {}, {});
  N := ExpressionSimplify.simplifyList(N, {});
  D := ExpressionSimplify.simplifyList(D, {});
  n := makeSum1(N);
  d := makeProductLst(D);
  (n,_) := ExpressionSimplify.simplify1(n);
  (d,_) := ExpressionSimplify.simplify1(d);
end makeFraction;

protected function moveDivToMul
  input list<DAE.Exp> iExpLst;
  input list<DAE.Exp> iExpLstAcc;
  input list<DAE.Exp> iExpMuls;
  output list<DAE.Exp> oExpLst;
  output list<DAE.Exp> oExpMuls;
algorithm
  (oExpLst, oExpMuls) := match(iExpLst, iExpLstAcc, iExpMuls)
    local
      DAE.Exp e, e1, e2;
      list<DAE.Exp> rest, acc, elst, elst1;
    case ({}, _, _) then (iExpLstAcc, iExpMuls);
    //-(a/b)
    case (DAE.UNARY(_,DAE.BINARY(exp1=e1, operator=DAE.DIV(), exp2=e2))::rest, _, _)
      equation
         acc = List.map1(iExpLstAcc, Expression.expMul, e2);
         rest = List.map1(rest, Expression.expMul, e2);
         rest = ExpressionSimplify.simplifyList(rest, {});
        (elst, elst1) = moveDivToMul(rest, negate(e1)::acc, e2::iExpMuls);
      then
        (elst, elst1);
    case (DAE.UNARY(_,DAE.BINARY(exp1=e1, operator=DAE.DIV_ARRAY_SCALAR(), exp2=e2))::rest, _, _)
      equation
         acc = List.map1(iExpLstAcc, Expression.expMul, e2);
         rest = List.map1(rest, Expression.expMul, e2);
         rest = ExpressionSimplify.simplifyList(rest, {});
        (elst, elst1) = moveDivToMul(rest, negate(e1)::acc, e2::iExpMuls);
      then
        (elst, elst1);
    // a/b
    case (DAE.BINARY(exp1=e1, operator=DAE.DIV(), exp2=e2)::rest, _, _)
      equation
         acc = List.map1(iExpLstAcc, Expression.expMul, e2);
         rest = List.map1(rest, Expression.expMul, e2);
         rest = ExpressionSimplify.simplifyList(rest, {});
        (elst, elst1) = moveDivToMul(rest, e1::acc, e2::iExpMuls);
      then
        (elst, elst1);
    case (DAE.BINARY(exp1=e1, operator=DAE.DIV_ARRAY_SCALAR(), exp2=e2)::rest, _, _)
      equation
         acc = List.map1(iExpLstAcc, Expression.expMul, e2);
         rest = List.map1(rest, Expression.expMul, e2);
         rest = ExpressionSimplify.simplifyList(rest, {});
        (elst, elst1) = moveDivToMul(rest, e1::acc, e2::iExpMuls);
      then
        (elst, elst1);
    case (e::rest, _, _)
      equation
        (elst, elst1) = moveDivToMul(rest, e::iExpLstAcc, iExpMuls);
      then
        (elst, elst1);
  end match;
end moveDivToMul;

protected function createResidualExp2
"author: Vitalij
  do some numerical helpfull thinks on like
  sqrt(f()) - sqrt(g(.)) = 0 -> f(.) - g(.)"
  input DAE.Exp iExp1;
  input DAE.Exp iExp2;
  output DAE.Exp oExp1 := iExp1;
  output DAE.Exp oExp2 := iExp2;
protected
  Boolean con := true, con1;
  Integer ii := 1;
algorithm

while con and ii < 15 loop
  (oExp1, oExp2, con) := matchcontinue(oExp1, oExp2)
    local DAE.Exp e, e1, e2;

    case(_,_)
     equation
      (e1,e2,true) = createResidualExp3(oExp1, oExp2);
      (e1,_) = ExpressionSimplify.simplify1(e1);
      (e2,_) = ExpressionSimplify.simplify1(e2);
    then (e1 ,e2, true);

    case(_,_)
     equation
      (e2,e1,true) = createResidualExp3(oExp2, oExp1);
      (e1,_) = ExpressionSimplify.simplify1(e1);
      (e2,_) = ExpressionSimplify.simplify1(e2);
    then (e1 ,e2, true);
    else (oExp1, oExp2, false);
    end matchcontinue;

  (oExp1, oExp2, con1) := matchcontinue(oExp1, oExp2)
    local DAE.Exp e, e1, e2;
    case(_,_)
    equation
      true = isZero(oExp1);
      (e1,e2) = makeFraction(oExp2);
    then (e1 ,oExp1, not isOne(e2));

    case(_,_)
    equation
      true = isZero(oExp2);
      (e1,e2) = makeFraction(oExp1);
    then (e1 ,oExp2, not isOne(e2));

    case(_,_)
    equation
      true = isOne(oExp1);
      (e1,e2) = makeFraction(oExp2);
    then (e1 ,e2, not isOne(e2));

    case(_,_)
    equation
      true = isOne(oExp2);
      (e1,e2) = makeFraction(oExp1);
    then (e1 ,e2, not isOne(e2));

    else (oExp1, oExp2, false);
    end matchcontinue;
   con := con or con1;

   ii := ii + 1;
   if not con then
     (oExp1,con) := ExpressionSimplify.simplify1(oExp1);
     (oExp2,con1) := ExpressionSimplify.simplify1(oExp2);
     con := con or con1;
     ii := ii + 3;
  // else
  //   print("\niExp1");print(ExpressionDump.printExpStr(iExp1));
  //    print("\te1");print(ExpressionDump.printExpStr(oExp2));
  //   print("\niExp2");print(ExpressionDump.printExpStr(iExp2));
  //    print("\te2");print(ExpressionDump.printExpStr(oExp2));
   end if;

end while;

 (oExp1,_) := ExpressionSimplify.simplify1(oExp1);
 (oExp2,_) := ExpressionSimplify.simplify1(oExp2);

end createResidualExp2;

protected function createResidualExp3
"author: Vitalij
  helper function of createResidualExp3
  swaps args"
  input DAE.Exp iExp1;
  input DAE.Exp iExp2;
  output DAE.Exp oExp1;
  output DAE.Exp oExp2;
  output Boolean con;
algorithm
  (oExp1, oExp2, con) := matchcontinue(iExp1, iExp2)
      local
        DAE.Exp e,e1,e2,e3,e4,e5,res;
        String s1, s2;
        DAE.Type tp;
        Real r;

    // f(x) = f(y) -> x = y
    case(DAE.CALL(path = Absyn.IDENT(s1), expLst={e1}),DAE.CALL(path = Absyn.IDENT(s2) ,expLst={e2}))
     equation
       true = s1 == s2;
       true = createResidualExp4(s1);
     then (e1,e2, true);
    // sqrt(f(x)) = 0.0 -> f(x) = 0
    case(DAE.CALL(path = Absyn.IDENT("sqrt"), expLst={e1}), DAE.RCONST(0.0))
      then (e1,iExp2,true);
    // sqrt(f(x)) = c -> f(x) = c^2
    case(DAE.CALL(path = Absyn.IDENT("sqrt"), expLst={e1}), DAE.RCONST())
      equation
       e = Expression.expPow(iExp2, DAE.RCONST(2.0));
      then (e1,e,true);
    // log(f(x)) = c -> f(x) = exp(c)
    case(DAE.CALL(path = Absyn.IDENT("log"), expLst={e1}), DAE.RCONST())
      equation
       tp = Expression.typeof(iExp2);
       e = Expression.makePureBuiltinCall("exp", {iExp2}, tp);
      then (e1,e,true);
    // log10(f(x)) = c -> f(x) = 10^(c)
    case(DAE.CALL(path = Absyn.IDENT("log10"), expLst={e1}), DAE.RCONST())
      equation
       e = Expression.expPow(DAE.RCONST(10.0),iExp2);
      then (e1,e,true);
/*
    // f(x)^y = 0 -> x = 0
    case(DAE.BINARY(e1,DAE.POW(_),e2),DAE.RCONST(0.0))
      then (e1, iExp2, true);
    // abs(f(x)) = 0.0 -> f(x) = 0
    case(DAE.CALL(path = Absyn.IDENT("abs"), expLst={e1}), DAE.RCONST(0.0))
      then (e1,iExp2,true);
*/
   // semiLinear(0,e1,e2) = 0 -> e1 - e2 = 0
   case(DAE.CALL(path = Absyn.IDENT("semiLinear"), expLst={DAE.RCONST(0.0), e1, e2}), DAE.RCONST(0.0))
      then (e1,e2,true);
   // -f(.) = 0 -> f(.) = 0
   case(DAE.UNARY(operator = DAE.UMINUS(),exp = e1), e2 as DAE.RCONST(0.0))
    then (e1,e2,true);
  // f(x) - f(y) = 0 -> x = y
    case(DAE.BINARY(DAE.CALL(path = Absyn.IDENT(s1), expLst={e1}),DAE.SUB(),DAE.CALL(path = Absyn.IDENT(s2) ,expLst={e2})), DAE.RCONST(0.0))
     equation
       true = s1 == s2;
       true = createResidualExp4(s1);
     then (e1,e2,true);
   else (iExp1, iExp2, false);
  end matchcontinue;
end createResidualExp3;

protected function createResidualExp4"
 author: Vitalij
 helper function of createResidualExp3
 return true if f(x) = f(y), then it can be transformed into x = y.

 Beware: function is not complete, yet!
"
  input String f;
  output Boolean resB;
algorithm
  resB := match(f)
    case("sqrt") then true;
    case("exp") then true;
    case("log") then true;
    case("log10") then true;
    case("tanh") then true;
    case("sinh") then true;
    else false;
  end match;
end createResidualExp4;

public function isAsubExp
  input DAE.Exp expIn;
  output Boolean isAsub;
algorithm
  isAsub := match(expIn)
    case(DAE.ASUB(_,_)) equation
      then true;
    else false;
  end match;
end isAsubExp;

annotation(__OpenModelica_Interface="frontend");
end Expression;
