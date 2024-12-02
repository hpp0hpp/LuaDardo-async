import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import '../../lua.dart';
import '../stdlib/math_lib.dart';

import '../stdlib/os_lib.dart';
import '../stdlib/package_lib.dart';
import '../stdlib/string_lib.dart';
import '../stdlib/table_lib.dart';
import 'package:sprintf/sprintf.dart';

import '../number/lua_number.dart';

import '../stdlib/basic_lib.dart';
import '../api/lua_vm.dart';
import '../binchunk/binary_chunk.dart';
import '../compiler/compiler.dart';
import '../vm/instruction.dart';
import '../vm/opcodes.dart';
import 'arithmetic.dart';
import 'comparison.dart';
import 'lua_stack.dart';
import 'lua_table.dart';
import 'lua_value.dart';
import 'closure.dart';
import 'upvalue_holder.dart';

class LuaStateImpl implements LuaState, LuaVM {
  LuaStack? _stack = LuaStack();

  /// 注册表
  LuaTable? registry = LuaTable(0, 0);

  LuaStateImpl() {
    registry!.put(luaRidxGlobals, LuaTable(0, 0));
    LuaStack stack = LuaStack();
    stack.state = this;
    _pushLuaStack(stack);
  }

  /// 压入调用栈帧
  void _pushLuaStack(LuaStack newTop) {
    newTop.prev = this._stack;
    this._stack = newTop;
  }

  void _popLuaStack() {
    LuaStack top = this._stack!;
    this._stack = top.prev;
    top.prev = null;
  }

  /* metatable */
  LuaTable? _getMetatable(Object? val) {
    if (val is LuaTable) {
      return val.metatable;
    }
    String key = "_MT${LuaValue.typeOf(val)}";
    Object? mt = registry!.get(key);
    return mt != null ? (mt as LuaTable) : null;
  }

  void _setMetatable(Object? val, LuaTable? mt) {
    if (val is LuaTable) {
      val.metatable = mt;
      return;
    }
    String key = "_MT${LuaValue.typeOf(val)}";
    registry!.put(key, mt);
  }

  Object? _getMetafield(Object? val, String fieldName) {
    LuaTable? mt = _getMetatable(val);
    return mt != null ? mt.get(fieldName) : null;
  }

  Object? getMetamethod(Object? a, Object? b, String mmName) {
    Object? mm = _getMetafield(a, mmName);
    if (mm == null) {
      mm = _getMetafield(b, mmName);
    }
    return mm;
  }

  Future<Object?> callMetamethod(Object? a, Object? b, Object mm) async {
    _stack!.push(mm);
    _stack!.push(a);
    _stack!.push(b);
    await call(2, 1);
    return _stack!.pop();
  }

  //**************************************************
  //******************* LuaState *********************
  //**************************************************

  @override
  int absIndex(int idx) {
    return _stack!.absIndex(idx);
  }

  @override
  bool checkStack(int n) {
    return true; // TODO
  }

  @override
  void copy(int fromIdx, int toIdx) {
    _stack!.set(toIdx, _stack!.get(fromIdx));
  }

  @override
  int getTop() {
    return _stack!.top();
  }

  @override
  void insert(int idx) {
    rotate(idx, 1);
  }

  @override
  bool isFunction(int idx) {
    return type(idx) == LuaType.luaFunction;
  }

  @override
  bool isInteger(int idx) {
    return _stack!.get(idx) is int;
  }

  @override
  bool isNil(int idx) {
    return type(idx) == LuaType.luaNil;
  }

  @override
  bool isNone(int idx) {
    return type(idx) == LuaType.luaNone;
  }

  @override
  bool isNoneOrNil(int idx) {
    LuaType t = type(idx);
    return t == LuaType.luaNone || t == LuaType.luaNil;
  }

  @override
  bool isNumber(int idx) {
    return toNumberX(idx) != null;
  }

  @override
  bool isString(int idx) {
    LuaType t = type(idx);
    return t == LuaType.luaString || t == LuaType.luaNumber;
  }

  @override
  bool isTable(int idx) {
    return type(idx) == LuaType.luaTable;
  }

  @override
  bool isThread(int idx) {
    return type(idx) == LuaType.luaThread;
  }

  @override
  bool isBoolean(int idx) {
    return type(idx) == LuaType.luaBoolean;
  }

  @override
  bool isUserdata(int idx) {
    return type(idx) == LuaType.luaUserdata;
  }

  @override
  void pop(int n) {
    for (int i = 0; i < n; i++) {
      _stack!.pop();
    }
  }

  @override
  void pushInteger(int? n) {
    _stack!.push(n);
  }

  @override
  void pushNil() {
    _stack!.push(null);
  }

  @override
  void pushNumber(double n) {
    _stack!.push(n);
  }

  @override
  void pushString(String? s) {
    _stack!.push(s);
  }

  @override
  void pushValue(int idx) {
    _stack!.push(_stack!.get(idx));
  }

  @override
  void pushBoolean(bool b) {
    _stack!.push(b);
  }

  @override
  void remove(int idx) {
    rotate(idx, -1);
    pop(1);
  }

  @override
  void replace(int idx) {
    _stack!.set(idx, _stack!.pop());
  }

  @override
  void rotate(int idx, int n) {
    int t = _stack!.top() - 1; /* end of stack segment being rotated */
    int p = _stack!.absIndex(idx) - 1; /* start of segment */
    int m = n >= 0 ? t - n : p - n - 1; /* end of prefix */

    _stack!.reverse(p, m); /* reverse the prefix with length 'n' */
    _stack!.reverse(m + 1, t); /* reverse the suffix */
    _stack!.reverse(p, t); /* reverse the entire segment */
  }

  @override
  void setTop(int idx) {
    int newTop = _stack!.absIndex(idx);
    if (newTop < 0) {
      throw Exception("stack underflow!");
    }

    int n = _stack!.top() - newTop;
    if (n > 0) {
      for (int i = 0; i < n; i++) {
        _stack!.pop();
      }
    } else if (n < 0) {
      for (int i = 0; i > n; i--) {
        _stack!.push(null);
      }
    }
  }

  @override
  int toInteger(int idx) {
    int? i = toIntegerX(idx);
    return i == null ? 0 : i;
  }

  @override
  int? toIntegerX(int idx) {
    Object? val = _stack!.get(idx);
    return val is int ? val : null;
  }

  @override
  double toNumber(int idx) {
    double? n = toNumberX(idx);
    return n == null ? 0 : n;
  }

  @override
  double? toNumberX(int idx) {
    Object? val = _stack!.get(idx);
    if (val is double) {
      return val;
    } else if (val is int) {
      return val.toDouble();
    } else {
      return null;
    }
  }

  @override
  Userdata? toUserdata<T>(int idx) {
    Object? val = _stack!.get(idx);
    return val is Userdata ? val : null;
  }

  @override
  bool toBoolean(int idx) {
    return LuaValue.toBoolean(_stack!.get(idx));
  }

  @override
  LuaType type(int idx) {
    return _stack!.isValid(idx)
        ? LuaValue.typeOf(_stack!.get(idx))
        : LuaType.luaNone;
  }

  @override
  String typeName(LuaType tp) {
    switch (tp) {
      case LuaType.luaNone:
        return "no value";
      case LuaType.luaNil:
        return "nil";
      case LuaType.luaBoolean:
        return "boolean";
      case LuaType.luaNumber:
        return "number";
      case LuaType.luaString:
        return "string";
      case LuaType.luaTable:
        return "table";
      case LuaType.luaFunction:
        return "function";
      case LuaType.luaThread:
        return "thread";
      default:
        return "userdata";
    }
  }

  @override
  String? toStr(int idx) {
    Object? val = _stack!.get(idx);
    if (val is String) {
      return val;
    } else if (val is int || val is double) {
      return val.toString();
    } else {
      return null;
    }
  }

  @override
  Future<void> arith(ArithOp op) async {
    Object? b = _stack!.pop();
    Object? a =
        op != ArithOp.luaOpUnm && op != ArithOp.luaOpBnot ? _stack!.pop() : b;
    Object? result = await Arithmetic.arith(a, b, op, this);
    if (result != null) {
      _stack!.push(result);
    } else {
      throw Exception("arithmetic error!");
    }
  }

  @override
  Future<bool> compare(int idx1, int idx2, CmpOp op) async {
    if (!_stack!.isValid(idx1) || !_stack!.isValid(idx2)) {
      return false;
    }

    Object? a = _stack!.get(idx1);
    Object? b = _stack!.get(idx2);
    switch (op) {
      case CmpOp.luaOpEq:
        return await Comparison.eq(a, b, this);
      case CmpOp.luaOpLt:
        return await Comparison.lt(a, b, this);
      case CmpOp.luaOpLe:
        return await Comparison.le(a, b, this);
      default:
        throw Exception("invalid compare op!");
    }
  }

  @override
  Future<void> concat(int n) async {
    if (n == 0) {
      _stack!.push("");
    } else if (n >= 2) {
      for (int i = 1; i < n; i++) {
        if (isString(-1) && isString(-2)) {
          String s2 = toStr(-1)!;
          String s1 = toStr(-2)!;
          pop(2);
          pushString(s1 + s2);
          continue;
        }

        Object? b = _stack!.pop();
        Object? a = _stack!.pop();
        Object? mm = getMetamethod(a, b, "__concat");
        if (mm != null) {
          _stack!.push(await callMetamethod(a, b, mm));
          continue;
        }

        throw Exception("concatenation error!");
      }
    }
    // n == 1, do nothing
  }

  @override
  Future<void> len(int idx) async {
    Object? val = _stack!.get(idx);
    if (val is String) {
      pushInteger(val.length);
      return;
    }

    Object? mm = getMetamethod(val, val, "__len");
    if (mm != null) {
      _stack!.push(await callMetamethod(val, val, mm));
      return;
    }

    if (val is LuaTable) {
      pushInteger(val.length());
      return;
    } else {
      throw Exception("length error!");
    }
  }

  @override
  void createTable(int nArr, int nRec) {
    _stack!.push(LuaTable(nArr, nRec));
  }

  @override
  Future<LuaType> getField(int idx, String? k) async {
    Object? t = _stack!.get(idx);
    return await _getTable(t, k, false);
  }

  @override
  Future<LuaType> getI(int idx, int i) async {
    Object? t = _stack!.get(idx);
    return await _getTable(t, i, false);
  }

  @override
  Future<LuaType> getTable(int idx) async {
    Object? t = _stack!.get(idx);
    Object? k = _stack!.pop();
    return await _getTable(t, k, false);
  }

  /// [raw] 是否忽略元方法
  /// _setTable 同
  Future<LuaType> _getTable(Object? t, Object? k, bool raw) async {
    if (t is LuaTable) {
      LuaTable tbl = t;
      Object? v = t.get(k);

      if (raw || v != null || !tbl.hasMetafield("__index")) {
        _stack!.push(v);
        return LuaValue.typeOf(v);
      }
    }

    if (!raw) {
      Object? mf = _getMetafield(t, "__index");
      if (mf != null) {
        if (mf is LuaTable) {
          return await _getTable(mf, k, false);
        } else if (mf is Closure) {
          Object? v = await callMetamethod(t, k, mf);
          _stack!.push(v);
          return LuaValue.typeOf(v);
        }
      }
    }
    throw Exception("${t.runtimeType}, not a table!"); // todo
  }

  @override
  void newTable() {
    createTable(0, 0);
  }

  @override
  Userdata newUserdata<T>() {
    var r = Userdata<T>();
    _stack!.push(r);
    return r;
  }

  @override
  Future<void> setField(int idx, String? k) async {
    Object? t = _stack!.get(idx);
    Object? v = _stack!.pop();
    await _setTable(t, k, v, false);
  }

  @override
  Future<void> setTable(int idx) async {
    Object? t = _stack!.get(idx);
    Object? v = _stack!.pop();
    Object? k = _stack!.pop();
    await _setTable(t, k, v, false);
  }

  @override
  Future<void> setI(int idx, int? i) async {
    Object? t = _stack!.get(idx);
    Object? v = _stack!.pop();
    await _setTable(t, i, v, false);
  }

  Future<void> _setTable(Object? t, Object? k, Object? v, bool raw) async {
    if (t is LuaTable) {
      LuaTable tbl = t;
      if (raw || tbl.get(k) != null || !tbl.hasMetafield("__newindex")) {
        tbl.put(k, v);
        return;
      }
    }

    if (!raw) {
      Object? mf = _getMetafield(t, "__newindex");
      if (mf != null) {
        if (mf is LuaTable) {
          await _setTable(mf, k, v, false);
          return;
        }
        if (mf is Closure) {
          _stack!.push(mf);
          _stack!.push(t);
          _stack!.push(k);
          _stack!.push(v);
          await call(3, 0);
          return;
        }
      }
    }
    throw Exception("${t.runtimeType}, not a table!");
  }

  @override
  Future<void> call(int nArgs, int nResults) async {
    Object? val = _stack!.get(-(nArgs + 1));
    Object? f = val is Closure ? val : null;

    if (f == null) {
      Object? mf = _getMetafield(val, "__call");
      if (mf != null && mf is Closure) {
        _stack!.push(f);
        insert(-(nArgs + 2));
        nArgs += 1;
        f = mf;
      }
    }

    if (f != null) {
      Closure c = f as Closure;
      if (c.proto != null) {
        await _callLuaClosure(nArgs, nResults, c);
      } else {
        await _callDartClosure(nArgs, nResults, c);
      }
    } else {
      throw Exception("not function!");
    }
  }

  Future<void> _callLuaClosure(int nArgs, int nResults, Closure c) async {
    int nRegs = c.proto!.maxStackSize;
    int nParams = c.proto!.numParams!;
    bool isVararg = c.proto!.isVararg == 1;

    // create new lua stack
    LuaStack newStack = LuaStack(/*nRegs + 20*/);
    newStack.state = this;
    newStack.closure = c;

    // pass args, pop func
    List<Object?> funcAndArgs = _stack!.popN(nArgs + 1);
    newStack.pushN(funcAndArgs.sublist(1, funcAndArgs.length), nParams);
    if (nArgs > nParams && isVararg) {
      newStack.varargs = funcAndArgs.sublist(nParams + 1, funcAndArgs.length);
    }

    // run closure
    _pushLuaStack(newStack);
    setTop(nRegs);
    await _runLuaClosure();
    _popLuaStack();

    // return results
    if (nResults != 0) {
      List<Object?> results = newStack.popN(newStack.top() - nRegs);
      //stack.check(results.size())
      _stack!.pushN(results, nResults);
    }
  }

  Future<void> _callDartClosure(int nArgs, int nResults, Closure c) async {
    // create new lua stack
    LuaStack newStack = new LuaStack(/*nRegs+LUA_MINSTACK*/);
    newStack.state = this;
    newStack.closure = c;

    // pass args, pop func
    if (nArgs > 0) {
      newStack.pushN(_stack!.popN(nArgs), nArgs);
    }
    _stack!.pop();

    // run closure
    _pushLuaStack(newStack);
    int r = await c.dartFunc!.call(this);
    _popLuaStack();

    // return results
    if (nResults != 0) {
      List<Object?> results = newStack.popN(r);
      //stack.check(results.size())
      _stack!.pushN(results, nResults);
    }
  }

  Future<void> _runLuaClosure() async {
    for (;;) {
      int i = fetch();
      OpCode opCode = Instruction.getOpCode(i);
      await opCode.action!.call(i, this);
      if (opCode.name == "RETURN") {
        break;
      }
    }
  }

  @override
  ThreadStatus load(Uint8List chunk, String chunkName, String? mode) {
    Prototype proto = BinaryChunk.isBinaryChunk(chunk)
        ? BinaryChunk.unDump(chunk)
        : Compiler.compile(utf8.decode(chunk), chunkName);
    Closure closure = Closure(proto);
    _stack!.push(closure);
    if (proto.upvalues.length > 0) {
      Object? env = registry!.get(luaRidxGlobals);
      closure.upvals[0] = UpvalueHolder.value(env); // todo
    }
    return ThreadStatus.luaOk;
  }

  @override
  bool isDartFunction(int idx) {
    Object? val = _stack!.get(idx);
    return val is Closure && val.dartFunc != null;
  }

  @override
  void pushDartFunction(f) {
    _stack!.push(Closure.DartFunc(f, 0));
  }

  @override
  toDartFunction(int idx) async {
    Object? val = _stack!.get(idx);
    return val is Closure ? await val.dartFunc : null;
  }

  @override
  Future<LuaType> getGlobal(String name) async {
    Object? t = registry!.get(luaRidxGlobals);
    return await _getTable(t, name, false);
  }

  @override
  void pushGlobalTable() {
    _stack!.push(registry!.get(luaRidxGlobals));
  }

  @override
  void pushDartClosure(DartFunctionAsync? f, int n) {
    Closure closure = Closure.DartFunc(f, n);
    for (int i = n; i > 0; i--) {
      Object? val = _stack!.pop();
      closure.upvals[i - 1] = UpvalueHolder.value(val); // TODO
    }
    _stack!.push(closure);
  }

  Future<int> Function(LuaState) toAsyncFunction(DartFunction f) {
    return (LuaState ls) async {
      return await f(ls);
    };
  }

  @override
  Future<void> register(String name, f) async {
    pushDartFunction(toAsyncFunction(f));
    await setGlobal(name);
  }

  @override
  Future<void> registerAsync(String name, f) async {
    pushDartFunction(f);
    await setGlobal(name);
  }

  @override
  Future<void> setGlobal(String name) async {
    Object? t = registry!.get(luaRidxGlobals);
    Object? v = _stack!.pop();
    await _setTable(t, name, v, false);
  }

  @override
  bool getMetatable(int idx) {
    Object? val = _stack!.get(idx);
    Object? mt = _getMetatable(val);
    if (mt != null) {
      _stack!.push(mt);
      return true;
    } else {
      return false;
    }
  }

  @override
  Future<bool> rawEqual(int idx1, int idx2) async {
    if (!_stack!.isValid(idx1) || !_stack!.isValid(idx2)) {
      return false;
    }

    Object? a = _stack!.get(idx1);
    Object? b = _stack!.get(idx2);
    return await Comparison.eq(a, b, null);
  }

  @override
  Future<LuaType> rawGet(int idx) async {
    Object? t = _stack!.get(idx);
    Object? k = _stack!.pop();
    return await _getTable(t, k, true);
  }

  @override
  Future<LuaType> rawGetI(int idx, int i) async {
    Object? t = _stack!.get(idx);
    return await _getTable(t, i, true);
  }

  @override
  int rawLen(int idx) {
    Object? val = _stack!.get(idx);
    if (val is String) {
      return val.length;
    } else if (val is LuaTable) {
      return val.length();
    } else {
      return 0;
    }
  }

  @override
  Future<void> rawSet(int idx) async {
    Object? t = _stack!.get(idx);
    Object? v = _stack!.pop();
    Object? k = _stack!.pop();
    await _setTable(t, k, v, true);
  }

  @override
  Future<void> rawSetI(int idx, int i) async {
    Object? t = _stack!.get(idx);
    Object? v = _stack!.pop();
    await _setTable(t, i, v, true);
  }

  @override
  void setMetatable(int idx) {
    Object? val = _stack!.get(idx);
    Object? mtVal = _stack!.pop();

    if (mtVal == null) {
      _setMetatable(val, null);
    } else if (mtVal is LuaTable) {
      _setMetatable(val, mtVal);
    } else {
      throw Exception("table expected!"); // todo
    }
  }

  @override
  bool next(int idx) {
    Object? val = _stack!.get(idx);
    if (val is LuaTable) {
      LuaTable t = val;
      Object? key = _stack!.pop();
      Object? nextKey = t.nextKey(key);
      if (nextKey != null) {
        _stack!.push(nextKey);
        _stack!.push(t.get(nextKey));
        return true;
      }
      return false;
    }
    throw Exception("table expected!");
  }

  @override
  int error() {
    Object? err = _stack!.pop();
    throw Exception(err.toString()); // TODO
  }

  @override
  Future<ThreadStatus> pCall(int nArgs, int nResults, int msgh) async {
    LuaStack? caller = _stack;
    try {
      await call(nArgs, nResults);
      return ThreadStatus.luaOk;
    } catch (e) {
      if (msgh != 0) {
        throw e;
      }
      while (_stack != caller) {
        _popLuaStack();
      }
      _stack!.push("$e"); // TODO
      return ThreadStatus.luaErrRun;
    }
  }

  //**************************************************
  //******************* LuaAuxLib ********************
  //**************************************************
  @override
  void argCheck(bool? cond, int arg, String extraMsg) {
    if (!cond!) {
      argError(arg, extraMsg);
    }
  }

  @override
  int argError(int arg, String extraMsg) {
    return error2("bad argument #%d (%s)", [arg, extraMsg]); // todo
  }

  @override
  Future<bool> callMeta(int obj, String e) async {
    obj = absIndex(obj);
    if (await getMetafield(obj, e) == LuaType.luaNil) {
      /* no metafield? */
      return false;
    }

    pushValue(obj);
    await call(1, 1);
    return true;
  }

  @override
  void checkAny(int arg) {
    if (type(arg) == LuaType.luaNone) {
      argError(arg, "value expected");
    }
  }

  @override
  Future<int?> checkInteger(int arg) async {
    int? i = toIntegerX(arg);
    if (i == null) {
      await intError(arg);
    }
    return i;
  }

  Future<void> intError(int arg) async {
    if (isNumber(arg)) {
      argError(arg, "number has no integer representation");
    } else {
      await tagError(arg, LuaType.luaNumber);
    }
  }

  Future<void> tagError(int arg, LuaType tag) async {
    await typeError(arg, typeName(tag));
  }

  Future<void> typeError(int arg, String tname) async {
    String? typeArg; /* name for the type of the actual argument */
    if (await getMetafield(arg, "__name") == LuaType.luaString) {
      typeArg = toStr(-1); /* use the given type name */
    } else if (type(arg) == LuaType.luaLightUserdata) {
      typeArg = "light userdata"; /* special name for messages */
    } else {
      typeArg = typeName2(arg); /* standard name */
    }
    String msg = tname + " expected, got " + typeArg!;
    pushString(msg);
    argError(arg, msg);
  }

  @override
  double? checkNumber(int arg) {
    double? f = toNumberX(arg);
    if (f == null) {
      tagError(arg, LuaType.luaNumber);
    }
    return f;
  }

  @override
  void checkStack2(int sz, String msg) {
    if (!checkStack(sz)) {
      if (msg != "") {
        error2("stack overflow (%s)", [msg]);
      } else {
        error2("stack overflow");
      }
    }
  }

  @override
  String? checkString(int arg) {
    String? s = toStr(arg);
    if (s == null) {
      tagError(arg, LuaType.luaString);
    }
    return s;
  }

  @override
  LuaTable checkTable(int arg) {
    if (type(arg) != LuaType.luaTable) {
      tagError(arg, LuaType.luaTable);
    }

    return _stack!.get(arg) as LuaTable;
  }

  @override
  void checkType(int arg, LuaType t) {
    if (type(arg) != t) {
      tagError(arg, t);
    }
  }

  @override
  Future<bool> doFile(String filename) async {
    return loadFile(filename) == ThreadStatus.luaOk &&
        await pCall(0, luaMultret, 0) == ThreadStatus.luaOk;
  }

  @override
  Future<bool> doString(String str) async {
    return loadString(str) == ThreadStatus.luaOk &&
        await pCall(0, luaMultret, 0) == ThreadStatus.luaOk;
  }

  @override
  int error2(String fmt, [List<Object?>? a]) {
    pushFString(fmt, a);
    return error();
  }

  @override
  Future<LuaType> getMetafield(int obj, String e) async {
    if (!getMetatable(obj)) {
      /* no metatable? */
      return LuaType.luaNil;
    }

    pushString(e);
    LuaType tt = await rawGet(-2);
    if (tt == LuaType.luaNil) {
      /* is metafield nil? */
      pop(2); /* remove metatable and metafield */
    } else {
      remove(-2); /* remove only metatable */
    }
    return tt; /* return metafield type */
  }

  @override
  Future<LuaType> getMetatableAux(String tname) async {
    return await getField(luaRegistryIndex, tname);
  }

  @override
  Future<bool> getSubTable(int idx, String fname) async {
    if (await getField(idx, fname) == LuaType.luaTable) {
      return true; /* table already there */
    }
    pop(1); /* remove previous result */
    idx = _stack!.absIndex(idx);
    newTable();
    pushValue(-1); /* copy to be left at top */
    await setField(idx, fname); /* assign new table to field */
    return false; /* false, because did not find table there */
  }

  @override
  Future<int?> len2(int idx) async {
    await len(idx);
    int? i = toIntegerX(-1);
    if (i == null) {
      error2("object length is not an integer");
    }
    pop(1);
    return i;
  }

  @override
  ThreadStatus loadFile(String? filename) {
    return loadFileX(filename, "bt");
  }

  @override
  ThreadStatus loadFileX(String? filename, String? mode) {
    try {
      File file = File(filename!);
      return load(file.readAsBytesSync(), "@" + filename, mode);
    } catch (e, s) {
      print(e);
      print(s);
      return ThreadStatus.luaErrFile;
    }
  }

  @override
  ThreadStatus loadString(String s) {
    return load(utf8.encode(s) as Uint8List, s, "bt");
  }

  @override
  Future<void> newLib(Map l) async {
    newLibTable(l);
    await setFuncsAsync(l as Map<String, Future<int> Function(LuaState)?>, 0);
  }

  @override
  void newLibTable(Map l) {
    createTable(0, l.length);
  }

  @override
  Future<void> openLibs() async {
    Map<String, DartFunctionAsync> libs = <String, DartFunctionAsync>{
      "_G": BasicLib.openBaseLib,
      "package": PackageLib.openPackageLib,
      "table": TableLib.openTableLib,
      "string": StringLib.openStringLib,
      "math": MathLib.openMathLib,
      "os": OSLib.openOSLib
    };

    for (int i = 0; i < libs.length; i++) {
      await requireF(libs.keys.elementAt(i), libs.values.elementAt(i), false);
      pop(1);
    }
  }

  @override
  Future<int?> optInteger(int arg, int? dft) async {
    return isNoneOrNil(arg) ? dft : await checkInteger(arg);
  }

  @override
  double? optNumber(int arg, double d) {
    return isNoneOrNil(arg) ? d : checkNumber(arg);
  }

  @override
  String? optString(int arg, String d) {
    return isNoneOrNil(arg) ? d : checkString(arg);
  }

  @override
  void pushFString(String fmt, [List<Object?>? a]) {
    String? str = a == null ? fmt : sprintf(fmt, a);
    pushString(str);
  }

  @override
  Future<void> requireF(String modname, openf, bool glb) async {
    await getSubTable(luaRegistryIndex, "_LOADED");
    await getField(-1, modname); /* LOADED[modname] */
    if (!toBoolean(-1)) {
      /* package not already loaded? */
      pop(1); /* remove field */
      pushDartFunction(openf);
      pushString(modname); /* argument to open function */
      await call(1, 1); /* call 'openf' to open module */
      pushValue(-1); /* make copy of module (call result) */
      await setField(-3, modname); /* _LOADED[modname] = module */
    }
    remove(-2); /* remove _LOADED table */
    if (glb) {
      pushValue(-1); /* copy of module */
      await setGlobal(modname); /* _G[modname] = module */
    }
  }

  @override
  Future<void> setMetatableAux(String tname) async {
    await getMetatableAux(tname);
    setMetatable(-2);
  }

  @override
  Future<void> setFuncs(Map<String, DartFunction?> l, int nup) async {
    checkStack2(nup, "too many upvalues");
    for (int y = 0; y < l.length; y++) {
      String name = l.keys.elementAt(y);
      DartFunction? fun = l.values.elementAt(y);

      for (int i = 0; i < nup; i++) {
        /* copy upvalues to the top */
        pushValue(-nup);
      }

      // r[-(nup+2)][name]=fun
      /* closure with those upvalues */
      if (fun != null) {
        pushDartClosure(toAsyncFunction(fun), nup);
      } else {
        pushDartClosure(null, nup);
      }

      await setField(-(nup + 2), name);
    }
    pop(nup); /* remove upvalues */
  }

  @override
  Future<void> setFuncsAsync(Map<String, DartFunctionAsync?> l, int nup) async {
    checkStack2(nup, "too many upvalues");
    for (int y = 0; y < l.length; y++) {
      String name = l.keys.elementAt(y);
      DartFunctionAsync? fun = l.values.elementAt(y);

      for (int i = 0; i < nup; i++) {
        /* copy upvalues to the top */
        pushValue(-nup);
      }
      // r[-(nup+2)][name]=fun
      pushDartClosure(fun, nup); /* closure with those upvalues */
      await setField(-(nup + 2), name);
    }
    pop(nup); /* remove upvalues */
  }

  @override
  bool stringToNumber(String s) {
    int? i = LuaNumber.parseInteger(s);
    if (i != null) {
      pushInteger(i);
      return true;
    }
    double? f = LuaNumber.parseFloat(s);
    if (f != null) {
      pushNumber(f);
      return true;
    }
    return false;
  }

  @override
  Object? toPointer(int idx) {
    return _stack!.get(idx); // todo
  }

  @override
  Future<String?> toString2(int idx) async {
    if (await callMeta(idx, "__tostring")) {
      /* metafield? */
      if (!isString(-1)) {
        error2("'__tostring' must return a string");
      }
    } else {
      switch (type(idx)) {
        case LuaType.luaNumber:
          if (isInteger(idx)) {
            pushString("${toInteger(idx)}"); // todo
          } else {
            pushString(sprintf("%g", [toNumber(idx)]));
          }
          break;
        case LuaType.luaString:
          pushValue(idx);
          break;
        case LuaType.luaBoolean:
          pushString(toBoolean(idx) ? "true" : "false");
          break;
        case LuaType.luaNil:
          pushString("nil");
          break;
        default:
          LuaType tt = await getMetafield(idx, "__name");
          /* try name */
          String? kind =
              tt == LuaType.luaString ? checkString(-1) : typeName2(idx);
          pushString("$kind: ${toPointer(idx).hashCode}");
          if (tt != LuaType.luaNil) {
            remove(-2); /* remove '__name' */
          }
          break;
      }
    }
    return checkString(-1);
  }

  @override
  String typeName2(int idx) {
    return typeName(type(idx));
  }

  @override
  Future<bool> newMetatable(String tname) async {
    if (await getMetatableAux(tname) != LuaType.luaNil) {
      /* name already in use? */
      return false; /* leave previous value on top, but return false */
    }

    pop(1);
    createTable(0, 2); /* create metatable */
    pushString(tname);
    await setField(-2, "__name"); /* metatable.__name = tname */
    pushValue(-1);
    await setField(luaRegistryIndex, tname); /* registry.name = metatable */
    return true;
  }

  Future<int> ref(int t) async {
    int _ref;
    if (isNil(-1)) {
      pop(1); /* remove from stack */
      return -1; /* 'nil' has a unique fixed reference */
    }
    t = absIndex(t);
    await rawGetI(t, 0); /* get first free element */
    _ref = toInteger(-1); /* ref = t[freelist] */
    pop(1); /* remove it from stack */
    if (_ref != 0) {
      /* any free element? */
      await rawGetI(t, _ref); /* remove it from list */
      await rawSetI(t, 0); /* (t[freelist] = t[ref]) */
    } else
      /* no free elements */
      _ref = rawLen(t) + 1;
    /* get a new reference */

    await rawSetI(t, _ref);
    return _ref;
  }

  Future<void> unRef(int t, int ref) async {
    if (ref >= 0) {
      t = absIndex(t);
      await rawGetI(t, 0);
      await rawSetI(t, ref); /* t[ref] = t[freelist] */
      pushInteger(ref);
      await rawSetI(t, 0); /* t[freelist] = ref */
    }
  }

  //**************************************************
  //******************** LuaVM ***********************
  //**************************************************
  @override
  void addPC(int n) {
    _stack!.pc += n;
  }

  @override
  int fetch() {
    return _stack!.closure!.proto!.code[_stack!.pc++];
  }

  @override
  void getConst(int idx) {
    _stack!.push(_stack!.closure!.proto!.constants[idx]);
  }

  @override
  int getPC() {
    return _stack!.pc;
  }

  @override
  void getRK(int rk) {
    if (rk > 0xFF) {
      // constant
      getConst(rk & 0xFF);
    } else {
      // register
      pushValue(rk + 1);
    }
  }

  @override
  void loadProto(int idx) {
    Prototype proto = _stack!.closure!.proto!.protos[idx]!;
    Closure closure = Closure(proto);
    _stack!.push(closure);

    for (int i = 0; i < proto.upvalues.length; i++) {
      Upvalue uvInfo = proto.upvalues[i]!;
      int? uvIdx = uvInfo.idx;
      if (uvInfo.instack == 1) {
        if (_stack!.openuvs == null) {
          _stack!.openuvs = Map<int?, UpvalueHolder?>();
        }
        if (_stack!.openuvs!.containsKey(uvIdx)) {
          closure.upvals[i] = _stack!.openuvs![uvIdx];
        } else {
          closure.upvals[i] = UpvalueHolder(_stack, uvIdx);
          _stack!.openuvs![uvIdx] = closure.upvals[i];
        }
      } else {
        closure.upvals[i] = _stack!.closure!.upvals[uvIdx!];
      }
    }
  }

  @override
  void loadVararg(int n) {
    List<Object?>? varargs =
        _stack!.varargs != null ? _stack!.varargs : const <Object>[];
    if (n < 0) {
      n = varargs!.length;
    }

    //stack.check(n)
    _stack!.pushN(varargs, n);
  }

  @override
  int registerCount() {
    return _stack!.closure!.proto!.maxStackSize;
  }

  @override
  void closeUpvalues(int a) {
    if (_stack!.openuvs != null) {
      _stack!.openuvs!.removeWhere((k, v) {
        if (v!.index! >= a - 1) {
          v.migrate();
          return true;
        } else
          return false;
      });
    }
  }

//**************************************************
//**************************************************
//**************************************************
}
