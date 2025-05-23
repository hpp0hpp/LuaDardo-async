
import 'dart:math' as math;
import '../../lua.dart';

import 'constants.dart' if (dart.library.html) 'constants_js.dart';

class MathLib{

  static Future<int> Function(LuaState) toAsyncFunction(DartFunction f) {
    return (LuaState ls) async {
      return await f(ls);
    };
  }

  static final Map<String, DartFunctionAsync?> _mathLib = {
    "random":     _random,
    "randomseed": toAsyncFunction(_randomseed),
    "max":        _max,
    "min":        _min,
    "exp":        toAsyncFunction(_exp),
    "log":        toAsyncFunction(_log),
    "deg":        toAsyncFunction(_deg),
    "rad":        toAsyncFunction(_rad),
    "sin":        toAsyncFunction(_sin),
    "cos":        toAsyncFunction(_cos),
    "tan":        toAsyncFunction(_tan),
    "asin":       toAsyncFunction(_asin),
    "acos":       toAsyncFunction(_acos),
    "atan":       toAsyncFunction(_atan),
    "ceil":       toAsyncFunction(_ceil),
    "floor":      toAsyncFunction(_floor),
    "fmod":       toAsyncFunction(_fmod),
    "modf":       toAsyncFunction(_modf),
    "abs":        toAsyncFunction(_abs),
    "sqrt":       toAsyncFunction(_sqrt),
    "ult":        _ult,
    "tointeger":  toAsyncFunction(_tointeger),
    "type":       toAsyncFunction(_type),
    /* placeholders */
    "pi":         null,
    "huge":       null,
    "maxinteger": null,
    "mininteger": null,
  };

  static Future<int> openMathLib(LuaState ls) async {

    //await ls.newLib(_mathLib);
    ls.pushGlobalTable();
    await ls.setFuncsAsync(_mathLib, 0); // Replace mathlib with global because it's broken

    ls.pushNumber(math.pi);
    await ls.setField(-2, "pi");
    ls.pushNumber(double.infinity);
    await ls.setField(-2, "huge");
    ls.pushInteger(int64MaxValue);
    await ls.setField(-2, "maxinteger");
    ls.pushInteger(int64MinValue);
    await ls.setField(-2, "mininteger");
    return 1;
  }


  static var rng = new math.Random();

  static Future<int> _random(LuaState ls) async {
    var low, up;
    switch(ls.getTop()){
      case 0:   /* no arguments */
        ls.pushNumber(rng.nextDouble()); /* Number between 0 and 1 */
        return 1;
      case 1:
        low = 1;
        up = await ls.checkInteger(1);
        break;
      case 2:
        low = await ls.checkInteger(1);
        up = await ls.checkInteger(2);
        break;
      default:
        return ls.error2("wrong number of arguments");
    }
    /* random integer in the interval [low, up] */
    ls.argCheck(low <= up, 1, "interval is empty");
    ls.argCheck(low >= 0, 1, "interval too large");

    ls.pushInteger(low + rng.nextInt(up-low));
    return 1;
  }

  static int _randomseed(LuaState ls) {
    var x = ls.checkNumber(1)!;
    rng = new math.Random(x.floor());
    return 0;
  }

  static Future<int> _max(LuaState ls) async {
    var n = ls.getTop(); /* number of arguments */
    var imax = 1;        /* index of current maximum value */
    ls.argCheck(n >= 1, 1, "value expected");
    for (var i = 2; i <= n; i++){
      if(await ls.compare(imax, i, CmpOp.luaOpLt)){
        imax = i;
      }
    }
    ls.pushValue(imax);
    return 1;
  }

  static Future<int> _min(LuaState ls) async {
    var n = ls.getTop(); /* number of arguments */
    var imin = 1;        /* index of current maximum value */
    ls.argCheck(n >= 1, 1, "value expected");
    for (var i = 2; i <= n; i++){
      if(await ls.compare(imin, i, CmpOp.luaOpLt)){
        imin = i;
      }
    }
    ls.pushValue(imin);
    return 1;
  }

  static int _exp(LuaState ls){
    var x = ls.checkNumber(1)!;
    ls.pushNumber(math.pow(math.e, x) as double);
    return 1;
  }

  static int _log(LuaState ls){
    var x = ls.checkNumber(1);
    var res;

    if(ls.isNoneOrNil(2)){
      res = math.log(x!);
    } else {
      var base = ls.toNumber(2);
      // if (base == 2){
      //   res = log2(x);
      // } else
      if (base == 10) {
        res = math.log(x!)/ln10;
      } else {
        res = math.log(x!)/math.log(base);
      }
    }

    ls.pushNumber(res);
    return 1;
  }

  static int _deg(LuaState ls){
    var x = ls.checkNumber(1)!;
    ls.pushNumber(x/rpd);
    return 1;
  }

  static int _rad(LuaState ls){
    var x = ls.checkNumber(1)!;
    ls.pushNumber(x*rpd);
    return 1;
  }

  static int _sin(LuaState ls){
    var x = ls.checkNumber(1)!;
    ls.pushNumber(math.sin(x));
    return 1;
  }

  static int _cos(LuaState ls){
    var x = ls.checkNumber(1)!;
    ls.pushNumber(math.cos(x));
    return 1;
  }

  static int _tan(LuaState ls){
    var x = ls.checkNumber(1)!;
    ls.pushNumber(math.tan(x));
    return 1;
  }

  static int _asin(LuaState ls){
    var x = ls.checkNumber(1)!;
    ls.pushNumber(math.asin(x));
    return 1;
  }

  static int _acos(LuaState ls){
    var x = ls.checkNumber(1)!;
    ls.pushNumber(math.acos(x));
    return 1;
  }

  static int _atan(LuaState ls){
    var y = ls.checkNumber(1)!;
    var x = ls.optNumber(2, 1.0)!;
    ls.pushNumber(math.atan2(y, x));
    return 1;
  }

  static _pushNumInt(LuaState ls,double d) {
    var i = d.toInt();
    if (d - i.toDouble() == 0){ /* does 'd' fit in an integer? */
      ls.pushInteger(i); /* result is integer */
    } else {
      ls.pushNumber(d);  /* result is float */
    }
  }

  static int _ceil(LuaState ls){
    if(ls.isInteger(1)){
      ls.setTop(1); /* integer is its own ceil */
    } else {
      double x = ls.checkNumber(1)!;
      ls.pushInteger(x.ceil());
    }
    return 1;
  }

  static int _floor(LuaState ls){
    if(ls.isInteger(1)){
      ls.setTop(1); /* integer is its own floor */
    } else {
      double x = ls.checkNumber(1)!;
      ls.pushInteger(x.floor());
    }
    return 1;
  }

  static int _fmod(LuaState ls) {
    if (ls.isInteger(1) && ls.isInteger(2)) {
      var d = ls.toInteger(2);
      if (d + 1 <= 1) {
        /* special cases: -1 or 0 */
        ls.argCheck(d != 0, 2, "zero");
        ls.pushInteger(0); /* avoid overflow with 0x80000... / -1 */
      } else {
        ls.pushInteger(ls.toInteger(1) % d);
      }
    } else {
      var x = ls.checkNumber(1)!;
      var y = ls.checkNumber(2)!;
      ls.pushNumber((x % y) * x.sign);
    }
    return 1;
  }

  static int _modf(LuaState ls){
    if (ls.isInteger(1)){
      ls.setTop(1);     /* number is its own integer part */
      ls.pushNumber(0); /* no fractional part */
    } else {
      var x = ls.checkNumber(1)!;
      var o = x.floor();
      ls.pushInteger(o);
      ls.pushNumber(x-o);
    }
    return 1;
  }

  static int _abs(LuaState ls){
    if (ls.isInteger(1)){
      var x = ls.toInteger(1);
      if (x < 0) {
        ls.pushInteger(-x);
      }
    } else {
      var x = ls.checkNumber(1)!;
      ls.pushNumber(x.abs());
    }
    return 1;
  }

  static int _sqrt(LuaState ls){
    var x = ls.checkNumber(1)!;
    ls.pushNumber(math.sqrt(x));
    return 1;
  }

  static Future<int> _ult(LuaState ls) async {
    var m = (await ls.checkInteger(1))!;
    var n = (await ls.checkInteger(2))!;
    ls.pushBoolean(m < n);
    return 1;
  }

  static int _tointeger(LuaState ls){
    var i = ls.toIntegerX(1);
    if (i != null){
      ls.pushInteger(i);
    } else {
      ls.checkAny(1);
      ls.pushNil(); /* value is not convertible to integer */
    }
    return 1;
  }

  static int _type(LuaState ls) {
    if (ls.type(1) == LuaType.luaNumber) {
      if (ls.isInteger(1)) {
        ls.pushString("integer");
      } else {
        ls.pushString("float");
      }
    } else {
      ls.checkAny(1);
      ls.pushNil();
    }
    return 1;
  }
}

const rpd = math.pi/180;
const double ln10 = 2.3025850929940456840179914546843642076011014886288;

