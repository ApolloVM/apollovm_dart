// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:swiss_knife/swiss_knife.dart';

import '../../apollovm_base.dart';
import '../../apollovm_runner.dart';
import '../../ast/apollovm_ast_toplevel.dart';
import '../../ast/apollovm_ast_type.dart';
import '../../ast/apollovm_ast_value.dart';
import 'wasm_runtime.dart';

/// WebAssembly (Wasm) implementation of an [ApolloRunner].
class ApolloRunnerWasm extends ApolloRunner {
  final _wasmRuntime = WasmRuntime();

  ApolloRunnerWasm(super.apolloVM, {super.importCorePackageMath});

  @override
  String get language => 'wasm';

  @override
  ApolloRunnerWasm copy() {
    return ApolloRunnerWasm(apolloVM);
  }

  /// Async host functions for real-suspension (Asyncify) `async` Wasm
  /// functions, keyed by import name. When a compiled `async` function awaits
  /// `name(args)`, the runner calls [fn] to produce a `Future`, suspends the
  /// Wasm call, awaits it, then resumes (rewinds) the module. [params] must
  /// match the awaited call's Wasm parameter types (e.g. `i64` for `int`).
  final Map<
    String,
    ({
      List<WasmValueType> params,
      Future<Object?> Function(List<Object?> args) fn,
    })
  >
  _wasmAsyncExternals = {};

  /// Registers an async host function [name] used by real-suspension `async`
  /// Wasm code (see [_wasmAsyncExternals]).
  void mapWasmAsyncFunction(
    String name,
    List<WasmValueType> params,
    Future<Object?> Function(List<Object?> args) fn,
  ) {
    _wasmAsyncExternals[name] = (params: params, fn: fn);
  }

  @override
  Future<ASTValue> executeFunction(
    String namespace,
    String functionName, {
    List? positionalParameters,
    Map? namedParameters,
    bool allowClassMethod = false,
  }) async {
    var r = await getFunctionCodeUnit(
      namespace,
      functionName,
      allowClassMethod: allowClassMethod,
    );

    var codeUnit = r.codeUnit as CodeUnit<Uint8List>?;
    if (codeUnit == null) {
      throw StateError(
        "Can't find function to execute> functionName: $functionName ; language: $language",
      );
    }

    if (!_wasmRuntime.isSupported) {
      throw StateError(
        "`WasmRuntime` not supported on this platform: ${_wasmRuntime.platformVersion}",
      );
    }

    // Host imports the module may declare (only the declared ones are wired).
    WasmModule? loadedModule;
    String decodeString(int ptr) {
      var mem = loadedModule!.readMemory();
      if (mem == null) {
        throw StateError(
          "Wasm module has no exported memory to read a string.",
        );
      }
      var len =
          mem[ptr] |
          (mem[ptr + 1] << 8) |
          (mem[ptr + 2] << 16) |
          (mem[ptr + 3] << 24);
      return utf8.decode(mem.sublist(ptr + 4, ptr + 4 + len));
    }

    // Allocates `[len:i32][utf8]` for [s] in the module's memory (via the
    // exported `__alloc`) and returns its pointer.
    int allocAndWriteString(String s) {
      var m = loadedModule!;
      var bytes = utf8.encode(s);
      var ptr = m.invokeExport('__alloc', [bytes.length + 4]) as int;
      var mem = m.readMemory()!;
      mem[ptr] = bytes.length & 0xff;
      mem[ptr + 1] = (bytes.length >> 8) & 0xff;
      mem[ptr + 2] = (bytes.length >> 16) & 0xff;
      mem[ptr + 3] = (bytes.length >> 24) & 0xff;
      mem.setRange(ptr + 4, ptr + 4 + bytes.length, bytes);
      return ptr;
    }

    int elemSizeOf(int elemTag) =>
        (elemTag == _tagInt || elemTag == _tagDouble) ? 8 : 4;

    // Encodes a Dart [list] into module memory as `[len:i32][cap:i32][dataPtr:i32]`
    // + a separate elements buffer (the generator's indirect list layout), and
    // returns the header pointer. `int` elements use i64, `double` f64, `bool`
    // i32 (0/1), `String` an i32 pointer to its own `[len][utf8]` block.
    int encodeList(List list, int elemTag) {
      var m = loadedModule!;
      var n = list.length;
      var elemSize = elemSizeOf(elemTag);

      // Strings allocate first (each grows the bump pointer); capture pointers.
      List<int>? strPtrs;
      if (elemTag == _tagString) {
        strPtrs = [for (var v in list) allocAndWriteString(v as String)];
      }

      var dataPtr = m.invokeExport('__alloc', [n * elemSize]) as int;
      var header = m.invokeExport('__alloc', [12]) as int;

      // Re-read AFTER all allocations: `__alloc` may have grown memory, which
      // invalidates any earlier view.
      var mem = m.readMemory()!;
      var bd = ByteData.sublistView(mem);
      bd.setInt32(header + 0, n, Endian.little);
      bd.setInt32(header + 4, n, Endian.little);
      bd.setInt32(header + 8, dataPtr, Endian.little);

      for (var i = 0; i < n; ++i) {
        _writeElem(bd, dataPtr + i * elemSize, elemTag, list[i], strPtrs?[i]);
      }
      return header;
    }

    // Decodes a module-memory list ([header] pointer) back into a Dart `List`.
    List decodeList(int header, int elemTag) {
      var mem = loadedModule!.readMemory()!;
      var bd = ByteData.sublistView(mem);
      var n = bd.getInt32(header + 0, Endian.little);
      var dataPtr = bd.getInt32(header + 8, Endian.little);
      var elemSize = elemSizeOf(elemTag);

      var out = [];
      for (var i = 0; i < n; ++i) {
        var addr = dataPtr + i * elemSize;
        out.add(_readElem(bd, addr, elemTag, decodeString));
      }
      return out;
    }

    // Encodes a Dart [map] into module memory as the generator's map layout
    // `[len][cap][keysPtr][valuesPtr]` + parallel key/value buffers, returning
    // the header pointer. Element encodings as for lists.
    int encodeMap(Map map, int keyTag, int valTag) {
      var m = loadedModule!;
      var entries = map.entries.toList();
      var n = entries.length;
      var keySize = elemSizeOf(keyTag);
      var valSize = elemSizeOf(valTag);

      // Pre-allocate String keys/values first (each alloc grows the bump ptr).
      List<int>? keyStrPtrs;
      if (keyTag == _tagString) {
        keyStrPtrs = [
          for (var e in entries) allocAndWriteString(e.key as String),
        ];
      }
      List<int>? valStrPtrs;
      if (valTag == _tagString) {
        valStrPtrs = [
          for (var e in entries) allocAndWriteString(e.value as String),
        ];
      }

      var keysPtr = m.invokeExport('__alloc', [n * keySize]) as int;
      var valsPtr = m.invokeExport('__alloc', [n * valSize]) as int;
      var header = m.invokeExport('__alloc', [16]) as int;

      var mem = m.readMemory()!;
      var bd = ByteData.sublistView(mem);
      bd.setInt32(header + 0, n, Endian.little);
      bd.setInt32(header + 4, n, Endian.little);
      bd.setInt32(header + 8, keysPtr, Endian.little);
      bd.setInt32(header + 12, valsPtr, Endian.little);

      for (var i = 0; i < n; ++i) {
        _writeElem(
          bd,
          keysPtr + i * keySize,
          keyTag,
          entries[i].key,
          keyStrPtrs?[i],
        );
        _writeElem(
          bd,
          valsPtr + i * valSize,
          valTag,
          entries[i].value,
          valStrPtrs?[i],
        );
      }
      return header;
    }

    // Decodes a module-memory map ([header] pointer) into a Dart `Map`.
    Map decodeMap(int header, int keyTag, int valTag) {
      var mem = loadedModule!.readMemory()!;
      var bd = ByteData.sublistView(mem);
      var n = bd.getInt32(header + 0, Endian.little);
      var keysPtr = bd.getInt32(header + 8, Endian.little);
      var valsPtr = bd.getInt32(header + 12, Endian.little);
      var keySize = elemSizeOf(keyTag);
      var valSize = elemSizeOf(valTag);

      var out = {};
      for (var i = 0; i < n; ++i) {
        var key = _readElem(bd, keysPtr + i * keySize, keyTag, decodeString);
        var val = _readElem(bd, valsPtr + i * valSize, valTag, decodeString);
        out[key] = val;
      }
      return out;
    }

    var hostImports = <String, Map<String, WasmHostFunction>>{
      'env': {
        'print': WasmHostFunction(
          params: const [WasmValueType.i32],
          results: const [],
          callback: (args) {
            externalPrintFunction(decodeString(args[0] as int));
            return null;
          },
        ),
        // Number-to-string, mirroring the interpreter's `'$v'` formatting.
        'int_to_str': WasmHostFunction(
          params: const [WasmValueType.i64],
          results: const [WasmValueType.i32],
          callback: (args) => allocAndWriteString('${args[0]}'),
        ),
        'double_to_str': WasmHostFunction(
          params: const [WasmValueType.f64],
          results: const [WasmValueType.i32],
          // `doubleToString` renders whole doubles as "5.0" deterministically
          // (plain `toString` yields "5" under dart2js).
          callback: (args) =>
              allocAndWriteString(ASTTypeDouble.doubleToString(args[0] as num)),
        ),
      },
    };

    // Real-suspension `async` support: a registered async host function is
    // wired as a *suspending* import — its callback produces a `Future` (held
    // in `pendingAwait`) and returns; the generated Asyncify code then unwinds.
    // The drive loop below awaits the `Future` and rewinds the module.
    Future<Object?>? pendingAwait;
    for (var e in _wasmAsyncExternals.entries) {
      var spec = e.value;
      hostImports['env']![e.key] = WasmHostFunction(
        params: spec.params,
        results: const [],
        callback: (args) {
          pendingAwait = spec.fn(args);
          return null;
        },
      );
    }

    var module = await _wasmRuntime.loadModule(
      codeUnit.id,
      codeUnit.code,
      hostImports: hostImports,
    );
    loadedModule = module;

    var f = module.getFunction(functionName);
    if (f == null) {
      throw StateError("Can't find function: $functionName");
    }

    var allParams = [...?positionalParameters, ...?namedParameters?.values];

    // Encode String and List arguments into module memory (via `__alloc`)
    // BEFORE numeric parameter resolution, which would otherwise mangle them.
    // The function receives the i32 pointer; param types come from the
    // `apollovm_sig` descriptors.
    var paramTypes = _signatures(codeUnit.code).sigs[functionName]?.params;
    if (paramTypes != null) {
      for (var i = 0; i < allParams.length && i < paramTypes.length; ++i) {
        var pt = paramTypes[i];
        var arg = allParams[i];
        if (pt.tag == _tagString && arg is String) {
          allParams[i] = allocAndWriteString(arg);
        } else if (pt.isList && arg is List) {
          allParams[i] = encodeList(arg, pt.elemTag);
        } else if (pt.isMap && arg is Map) {
          allParams[i] = encodeMap(arg, pt.elemTag, pt.valTag);
        }
      }
    }

    {
      var astFunction = _getASTFunction(codeUnit, functionName, allParams);
      if (astFunction != null) {
        var (allParamsNormalized, _) = normalizeParameters(
          positionalParameters: allParams,
          astFunctions: [astFunction],
        );
        allParams = allParamsNormalized ?? [];
      }
    }

    var astFunction = _getASTFunction(codeUnit, functionName, allParams);
    if (astFunction != null) {
      _resolveWasmCallParameters(astFunction, allParams);
    }

    final (function: function, varArgs: varArgs) = f;

    dynamic invokeOnce() {
      try {
        if (!varArgs) {
          if (function is Function(List)) {
            return Function.apply(function, [allParams]);
          } else if (function is Function()) {
            if (allParams.isNotEmpty) {
              throw WasmModuleExecutionError(
                functionName,
                parameters: allParams,
                function: function,
                cause:
                    "Function expects no arguments, but ${allParams.length} were provided: $allParams",
              );
            }
            return Function.apply(function, []);
          } else {
            return Function.apply(function, allParams);
          }
        } else {
          return Function.apply(function, allParams);
        }
      } catch (e) {
        throw WasmModuleExecutionError(
          functionName,
          parameters: allParams,
          function: function,
          cause: e,
        );
      }
    }

    final isAsyncFn = _signatures(
      codeUnit.code,
    ).asyncFns.contains(functionName);

    dynamic res;
    if (!isAsyncFn) {
      res = invokeOnce();
    } else {
      // Asyncify drive loop: invoke; if the call unwound (suspended), await the
      // host `Future` it produced, write the result back, flag a rewind, and
      // re-invoke until it completes normally. Offsets match the Asyncify
      // control region in `WasmModuleContext` (state @8 i32, result @16 i64).
      const asyStateOff = 8;
      const asyResultOff = 16;
      while (true) {
        res = invokeOnce();

        var mem = module.readMemory();
        if (mem == null) break;
        var bd = ByteData.sublistView(mem);

        if (bd.getInt32(asyStateOff, Endian.little) != 1) {
          break; // normal completion (state 0)
        }

        var pending = pendingAwait;
        if (pending == null) {
          throw WasmModuleExecutionError(
            functionName,
            parameters: allParams,
            cause:
                "Async Wasm function suspended but no host `Future` was "
                "produced. Register the awaited host function via "
                "`mapWasmAsyncFunction`.",
          );
        }
        pendingAwait = null;

        var resolved = await pending;
        var resolvedInt = resolved is BigInt
            ? resolved.toInt()
            : (resolved is num ? resolved.toInt() : 0);
        _writeI64(bd, asyResultOff, resolvedInt);
        bd.setInt32(asyStateOff, 2, Endian.little); // rewinding
      }
    }

    res = module.resolveReturnedValue(res, astFunction);

    // Decode the raw Wasm return into a Dart value. The return type comes from
    // the AST when available, else from the module's `apollovm_sig` custom
    // section (for modules loaded from raw bytes).
    var sigReturn = _signatures(codeUnit.code).sigs[functionName]?.ret;

    if (res != null) {
      // `String` return: an i32 pointer to a `[len][utf8]` block.
      var returnsString =
          astFunction?.returnType is ASTTypeString ||
          sigReturn?.tag == _tagString;
      // `bool` return: an i32 (0/1).
      var returnsBool =
          astFunction?.returnType is ASTTypeBool || sigReturn?.tag == _tagBool;
      // `List` return: an i32 pointer to a list header.
      var listReturn = astFunction?.returnType is ASTTypeArray
          ? _elemTagOf((astFunction!.returnType as ASTTypeArray).componentType)
          : (sigReturn != null && sigReturn.isList ? sigReturn.elemTag : null);
      // `Map` return: an i32 pointer to a map header.
      ({int keyTag, int valTag})? mapReturn;
      if (astFunction?.returnType is ASTTypeMap) {
        var mt = astFunction!.returnType as ASTTypeMap;
        mapReturn = (
          keyTag: _elemTagOf(mt.keyType),
          valTag: _elemTagOf(mt.valueType),
        );
      } else if (sigReturn != null && sigReturn.isMap) {
        mapReturn = (keyTag: sigReturn.elemTag, valTag: sigReturn.valTag);
      }

      if (returnsString) {
        res = decodeString(res as int);
      } else if (returnsBool && res is! bool) {
        res = (res as num) != 0;
      } else if (listReturn != null) {
        res = decodeList(res as int, listReturn);
      } else if (mapReturn != null) {
        res = decodeMap(res as int, mapReturn.keyTag, mapReturn.valTag);
      }
    }

    var astValue = res == null
        ? ASTValueNull.instance
        : ASTValue.fromValue(res);

    return astValue;
  }

  // Reads/writes a little-endian 64-bit int via BigInt, so it works on both the
  // Dart VM and dart2js (where `ByteData.get/setInt64` throw). Values beyond the
  // web's 2^53 safe-integer range lose precision on `toInt()` — inherent to web
  // `int`s, and outside the supported range anyway.
  static void _writeI64(ByteData bd, int addr, int value) {
    var b = BigInt.from(value).toUnsigned(64);
    var mask = BigInt.from(0xff);
    for (var i = 0; i < 8; ++i) {
      bd.setUint8(addr + i, ((b >> (8 * i)) & mask).toInt());
    }
  }

  static int _readI64(ByteData bd, int addr) {
    var b = BigInt.zero;
    for (var i = 0; i < 8; ++i) {
      b |= BigInt.from(bd.getUint8(addr + i)) << (8 * i);
    }
    return b.toSigned(64).toInt();
  }

  /// Writes a collection element of [tag] at [addr]. `String` elements use the
  /// pre-allocated [strPtr]; numerics/bools are written inline.
  static void _writeElem(
    ByteData bd,
    int addr,
    int tag,
    Object? value,
    int? strPtr,
  ) {
    switch (tag) {
      case _tagInt:
        _writeI64(
          bd,
          addr,
          value is BigInt ? value.toInt() : (value as num).toInt(),
        );
      case _tagDouble:
        bd.setFloat64(addr, (value as num).toDouble(), Endian.little);
      case _tagBool:
        bd.setInt32(addr, (value as bool) ? 1 : 0, Endian.little);
      case _tagString:
        bd.setInt32(addr, strPtr!, Endian.little);
      default:
        throw StateError("Unsupported Wasm element tag: $tag");
    }
  }

  /// Reads a collection element of [tag] at [addr].
  static Object? _readElem(
    ByteData bd,
    int addr,
    int tag,
    String Function(int) decodeString,
  ) {
    switch (tag) {
      case _tagInt:
        return _readI64(bd, addr);
      case _tagDouble:
        return bd.getFloat64(addr, Endian.little);
      case _tagBool:
        return bd.getInt32(addr, Endian.little) != 0;
      case _tagString:
        return decodeString(bd.getInt32(addr, Endian.little));
      default:
        throw StateError("Unsupported Wasm element tag: $tag");
    }
  }

  /// Element tag for an AST list-component type (mirrors the generator's
  /// `_typeTag`). Returns `-1` for unsupported element types.
  static int _elemTagOf(ASTType t) {
    if (t is ASTTypeInt) return _tagInt;
    if (t is ASTTypeDouble) return _tagDouble;
    if (t is ASTTypeBool) return _tagBool;
    if (t is ASTTypeString) return _tagString;
    return -1;
  }

  // High-level type tags from the `apollovm_sig` custom section.
  static const int _tagInt = 1;
  static const int _tagDouble = 2;
  static const int _tagBool = 3;
  static const int _tagString = 4;
  static const int _tagList = 6;
  static const int _tagMap = 7;

  /// Per-module signature cache, keyed by the wasm binary's identity.
  final Map<Uint8List, ({Map<String, _WasmSig> sigs, Set<String> asyncFns})>
  _signaturesCache = {};

  ({Map<String, _WasmSig> sigs, Set<String> asyncFns}) _signatures(
    Uint8List wasmBytes,
  ) => _signaturesCache[wasmBytes] ??= _parseSignatures(wasmBytes);

  /// Parses the `apollovm_sig` custom section (function name -> return/param
  /// type descriptors). Returns an empty map if absent. Each type is a one-byte
  /// tag, except a list (`6`) which is followed by its element tag byte.
  static ({Map<String, _WasmSig> sigs, Set<String> asyncFns}) _parseSignatures(
    Uint8List b,
  ) {
    var sigs = <String, _WasmSig>{};
    var asyncFns = <String>{};
    if (b.length < 8) return (sigs: sigs, asyncFns: asyncFns);

    var pos = 8; // skip magic (4) + version (4)

    int readLeb() {
      var result = 0, shift = 0;
      while (true) {
        var byte = b[pos++];
        result |= (byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
      }
      return result;
    }

    String readName() {
      var len = readLeb();
      var s = utf8.decode(b.sublist(pos, pos + len));
      pos += len;
      return s;
    }

    _WasmType readType() {
      var tag = b[pos++];
      if (tag == _tagList) {
        return _WasmType(tag, b[pos++]);
      }
      if (tag == _tagMap) {
        var keyTag = b[pos++];
        var valTag = b[pos++];
        return _WasmType(tag, keyTag, valTag);
      }
      return _WasmType(tag, -1);
    }

    while (pos < b.length) {
      var id = b[pos++];
      var size = readLeb();
      var sectionEnd = pos + size;
      if (id == 0) {
        var name = readName();
        if (name == 'apollovm_sig') {
          var count = readLeb();
          for (var i = 0; i < count; ++i) {
            var fname = readName();
            var ret = readType();
            var paramCount = readLeb();
            var params = [for (var p = 0; p < paramCount; ++p) readType()];
            sigs[fname] = _WasmSig(ret, params);
          }
          // Optional trailing block: names of Asyncify (real-suspension)
          // functions the runner must drive. Absent in older/non-async modules.
          if (pos < sectionEnd) {
            var asyncCount = readLeb();
            for (var i = 0; i < asyncCount; ++i) {
              asyncFns.add(readName());
            }
          }
        }
      }
      pos = sectionEnd;
    }

    return (sigs: sigs, asyncFns: asyncFns);
  }

  void _resolveWasmCallParameters(
    ASTFunctionDeclaration astFunction,
    List parameters,
  ) {
    var astParameters = astFunction.parameters.allParameters;
    var limit = math.min(parameters.length, astParameters.length);

    for (var i = 0; i < limit; ++i) {
      var p = astParameters[i];
      var v = parameters[i];

      var v2 = _resolveParameterValueType(p, v);
      parameters[i] = v2;
    }
  }

  Object? _resolveParameterValueType(
    ASTFunctionParameterDeclaration p,
    Object? v,
  ) {
    var t = p.type;

    if (t is ASTTypeInt) {
      var n = parseInt(v);

      if (n != null && t.bits == 64) {
        return BigInt.from(n);
      } else {
        return n ?? v;
      }
    } else if (t is ASTTypeDouble) {
      var n = parseDouble(v);
      return n ?? v;
    }

    return v;
  }

  ASTFunctionDeclaration? _getASTFunction(
    CodeUnit<Uint8List> codeUnit,
    String functionName,
    List parameters,
  ) {
    var astFunctionSet = codeUnit.root?.getFunctionWithName(functionName);
    if (astFunctionSet == null) return null;

    if (astFunctionSet.functions.length <= 1) {
      return astFunctionSet.functions.firstOrNull;
    }

    var list = astFunctionSet.functions.where(
      (f) => f.parameters.size == parameters.length,
    );

    if (list.length <= 1) return list.firstOrNull;

    throw StateError(
      "Ambiguous AST functions. Can't determine function with name `$functionName` and with ${parameters.length} parameters",
    );
  }
}

/// A high-level type from the `apollovm_sig` custom section: a [tag] plus, for a
/// list ([ApolloRunnerWasm._tagList]), the element tag in [elemTag]; for a map
/// ([ApolloRunnerWasm._tagMap]), [elemTag] is the key tag and [valTag] the value
/// tag. Unused sub-tags are `-1`.
class _WasmType {
  final int tag;
  final int elemTag;
  final int valTag;
  const _WasmType(this.tag, this.elemTag, [this.valTag = -1]);

  bool get isList => tag == ApolloRunnerWasm._tagList;
  bool get isMap => tag == ApolloRunnerWasm._tagMap;
}

/// A parsed public-function signature (return type + parameter types).
class _WasmSig {
  final _WasmType ret;
  final List<_WasmType> params;
  const _WasmSig(this.ret, this.params);
}
