import '../state/lua_table.dart';
import 'lua_type.dart';

abstract class LuaAuxLib {
/* Error-report functions */
  int error2(String fmt, [List<Object?>? a]);

  int argError(int arg, String extraMsg);

/* Argument check functions */
  void checkStack2(int sz, String msg);

  void argCheck(bool? cond, int arg, String extraMsg);

  void checkAny(int arg);

  void checkType(int arg, LuaType t);

  Future<int?> checkInteger(int arg);

  double? checkNumber(int arg);

  String? checkString(int arg);
  LuaTable? checkTable(int arg);

  Future<int?> optInteger(int arg, int? d);

  double? optNumber(int arg, double d);

  String? optString(int arg, String d);

/* Load functions */
  Future<bool> doFile(String filename);

  Future<bool> doString(String str);

  ThreadStatus loadFile(String? filename);

  ThreadStatus loadFileX(String? filename, String? mode);

  ThreadStatus loadString(String s);

/* Other functions */
  String typeName2(int idx);

  Future<String?> toString2(int idx);

  Future<int?> len2(int idx);

  Future<bool> getSubTable(int idx, String fname);

  Future<LuaType> getMetatableAux(String tname);

  Future<LuaType> getMetafield(int obj, String e);

  Future<bool> callMeta(int obj, String e);

  Future<void> openLibs();

  Future<int> ref(int t);
  Future<void> unRef(int t, int ref);

  Future<void> requireF(String modname, DartFunctionAsync openf, bool glb);

  Future<void> newLib(Map<String, DartFunctionAsync?> l);

  void newLibTable(Map<String, DartFunction> l);
  Future<bool> newMetatable(String tname);

  Future<void> setMetatableAux(String tname);
  Future<void> setFuncs(Map<String, DartFunction?> l, int nup);
  Future<void> setFuncsAsync(Map<String, DartFunctionAsync?> l, int nup);
}
