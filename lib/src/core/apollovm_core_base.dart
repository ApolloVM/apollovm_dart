// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:async';

import '../apollovm_base.dart';
import '../ast/apollovm_ast_base.dart';
import '../ast/apollovm_ast_toplevel.dart';
import '../ast/apollovm_ast_type.dart';
import '../ast/apollovm_ast_value.dart';
import '../ast/apollovm_ast_variable.dart';

class ApolloVMCore {
  static ASTClass<V>? getClass<V>(String className, {List<ASTType>? generics}) {
    switch (className) {
      case 'String':
        return CoreClassString.instance as ASTClass<V>;
      case 'int':
      case 'Integer':
        return CoreClassInt.instance as ASTClass<V>;
      case 'double':
      case 'Double':
        return CoreClassDouble.instance as ASTClass<V>;
      case 'List':
        return CoreClassList.fromType(V) as ASTClass<V>;
      default:
        return null;
    }
  }
}

abstract mixin class CoreClassMixin<T> {
  ASTClass<T> get astClass;

  ASTExternalClassGetter<R> _externalClassGetter<R>(
    String name,
    ASTType<R> returnType,
    Function(Object? o) externalFunction,
  ) {
    return ASTExternalClassGetter<R>(
      astClass,
      name,
      returnType,
      externalFunction,
    );
  }

  ASTExternalClassFunction<R> _externalClassFunctionArgs0<R>(
    String name,
    ASTType<R> returnType,
    Function externalFunction, [
    ParameterValueResolver? parameterValueResolver,
  ]) {
    return ASTExternalClassFunction<R>(
      astClass,
      name,
      ASTParametersDeclaration(null, null, null),
      returnType,
      externalFunction,
      parameterValueResolver,
    );
  }

  ASTExternalClassFunction<R> _externalClassFunctionArgs1<R>(
    String name,
    ASTType<R> returnType,
    ASTFunctionParameterDeclaration param1,
    Function externalFunction, [
    ParameterValueResolver? parameterValueResolver,
  ]) {
    return ASTExternalClassFunction<R>(
      astClass,
      name,
      ASTParametersDeclaration([param1], null, null),
      returnType,
      externalFunction,
      parameterValueResolver,
    );
  }

  ASTExternalClassFunction<R> _externalClassFunctionArgs2<R>(
    String name,
    ASTType<R> returnType,
    ASTFunctionParameterDeclaration param1,
    ASTFunctionParameterDeclaration param2,
    Function externalFunction, [
    ParameterValueResolver? parameterValueResolver,
  ]) {
    return ASTExternalClassFunction<R>(
      astClass,
      name,
      ASTParametersDeclaration([param1, param2], null, null),
      returnType,
      externalFunction,
      parameterValueResolver,
    );
  }

  // ignore: unused_element
  ASTExternalFunction<R> _externalStaticFunctionArgs0<R>(
    String name,
    ASTType<R> returnType,
    Function externalFunction, [
    ParameterValueResolver? parameterValueResolver,
  ]) {
    return ASTExternalFunction<R>(
      name,
      ASTParametersDeclaration(null, null, null),
      returnType,
      externalFunction,
      parameterValueResolver,
    );
  }

  ASTExternalFunction<R> _externalStaticFunctionArgs1<R>(
    String name,
    ASTType<R> returnType,
    ASTFunctionParameterDeclaration param1,
    Function externalFunction, [
    ParameterValueResolver? parameterValueResolver,
  ]) {
    return ASTExternalFunction<R>(
      name,
      ASTParametersDeclaration([param1], null, null),
      returnType,
      externalFunction,
      parameterValueResolver,
    );
  }
}

abstract class CoreClassBase<T> extends ASTClass<T> with CoreClassMixin {
  final String coreName;

  @override
  ASTClass<T> get astClass => this;

  CoreClassBase(ASTType<T> type, this.coreName) : super(coreName, type, null) {
    type.setClass(this);
  }
}

abstract class CoreClassPrimitive<T> extends ASTClassPrimitive<T>
    with CoreClassMixin {
  final String coreName;

  @override
  ASTClass<T> get astClass => this;

  CoreClassPrimitive(super.type, this.coreName) {
    type.setClass(this);
  }
}

class CoreClassString extends CoreClassPrimitive<String> {
  static final CoreClassString instance = CoreClassString._();

  late final ASTExternalClassFunction _functionContains;
  late final ASTExternalClassFunction _functionToUpperCase;
  late final ASTExternalClassFunction _functionToLowerCase;

  late final ASTExternalClassFunction _functionLength;
  late final ASTExternalClassFunction _functionIsEmpty;
  late final ASTExternalClassFunction _functionIsNotEmpty;

  late final ASTExternalClassFunction _functionSubstring;
  late final ASTExternalClassFunction _functionIndexOf;
  late final ASTExternalClassFunction _functionStartsWith;
  late final ASTExternalClassFunction _functionEndsWith;

  late final ASTExternalClassFunction _functionTrim;
  late final ASTExternalClassFunction _functionSplit;
  late final ASTExternalClassFunction _functionReplaceAll;

  late final ASTExternalFunction _functionValueOf;

  CoreClassString._() : super(ASTTypeString.instance, 'String') {
    _functionContains = _externalClassFunctionArgs1(
      'contains',
      ASTTypeBool.instance,
      ASTFunctionParameterDeclaration(ASTTypeString.instance, 's', 0, false),
      (String o, String p1) => o.contains(p1),
    );

    _functionToUpperCase = _externalClassFunctionArgs0(
      'toUpperCase',
      ASTTypeString.instance,
      (String o) => o.toUpperCase(),
    );

    _functionToLowerCase = _externalClassFunctionArgs0(
      'toLowerCase',
      ASTTypeString.instance,
      (String o) => o.toLowerCase(),
    );

    _functionLength = _externalClassFunctionArgs0(
      'length',
      ASTTypeInt.instance,
      (String o) => o.length,
    );

    _functionIsEmpty = _externalClassFunctionArgs0(
      'isEmpty',
      ASTTypeBool.instance,
      (String o) => o.isEmpty,
    );

    _functionIsNotEmpty = _externalClassFunctionArgs0(
      'isNotEmpty',
      ASTTypeBool.instance,
      (String o) => o.isNotEmpty,
    );

    _functionSubstring = _externalClassFunctionArgs2(
      'substring',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'start', 0, false),
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'end', 1, true),
      (String o, dynamic start, dynamic end) => o.substring(start, end),
    );

    _functionIndexOf = _externalClassFunctionArgs1(
      'indexOf',
      ASTTypeInt.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeString.instance,
        'pattern',
        0,
        false,
      ),
      (String o, String p1) => o.indexOf(p1),
    );

    _functionStartsWith = _externalClassFunctionArgs1(
      'startsWith',
      ASTTypeBool.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeString.instance,
        'prefix',
        0,
        false,
      ),
      (String o, String p1) => o.startsWith(p1),
    );

    _functionEndsWith = _externalClassFunctionArgs1(
      'endsWith',
      ASTTypeBool.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeString.instance,
        'suffix',
        0,
        false,
      ),
      (String o, String p1) => o.endsWith(p1),
    );

    _functionTrim = _externalClassFunctionArgs0(
      'trim',
      ASTTypeString.instance,
      (String o) => o.trim(),
    );

    _functionSplit = _externalClassFunctionArgs1(
      'split',
      ASTTypeArray.instanceOfString,
      ASTFunctionParameterDeclaration(
        ASTTypeString.instance,
        'pattern',
        0,
        false,
      ),
      (String o, String p1) => o.split(p1),
    );

    _functionReplaceAll = _externalClassFunctionArgs2(
      'replaceAll',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(ASTTypeString.instance, 'from', 0, false),
      ASTFunctionParameterDeclaration(
        ASTTypeString.instance,
        'replace',
        1,
        false,
      ),
      (String o, dynamic from, dynamic replace) => o.replaceAll(from, replace),
    );

    _functionValueOf = _externalStaticFunctionArgs1(
      'valueOf',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(ASTTypeDynamic.instance, 'obj', 0, false),
      (dynamic o) => o?.toString() ?? 'null',
      resolveValueToString,
    );
  }

  String resolveValueToString(ASTValue? paramVal, VMContext context) {
    if (paramVal == null) return 'null';

    if (paramVal is VMObject) {
      return paramVal.toString();
    }

    final val = paramVal.getValue(context);
    return '$val';
  }

  @override
  ASTFunctionDeclaration? getFunction(
    String fName,
    ASTFunctionSignature parametersSignature,
    VMContext context, {
    bool caseInsensitive = false,
  }) {
    switch (fName) {
      case 'contains':
        return _functionContains;
      case 'toUpperCase':
        return _functionToUpperCase;
      case 'toLowerCase':
        return _functionToLowerCase;

      case 'length':
        return _functionLength;
      case 'isEmpty':
        return _functionIsEmpty;
      case 'isNotEmpty':
        return _functionIsNotEmpty;

      case 'substring':
        return _functionSubstring;
      case 'indexOf':
        return _functionIndexOf;
      case 'startsWith':
        return _functionStartsWith;
      case 'endsWith':
        return _functionEndsWith;

      case 'trim':
        return _functionTrim;
      case 'split':
        return _functionSplit;
      case 'replaceAll':
        return _functionReplaceAll;

      case 'valueOf':
        return _functionValueOf;
    }

    throw StateError(
      "Can't find core function: $coreName.$fName( $parametersSignature )",
    );
  }
}

class CoreClassInt extends CoreClassPrimitive<int> {
  static final CoreClassInt instance = CoreClassInt._();

  late final ASTExternalFunction _functionValueOf;
  late final ASTExternalFunction _functionParseInt;
  late final ASTExternalFunction _functionTryParse;

  late final ASTExternalClassFunction _functionCompareTo;
  late final ASTExternalClassFunction _functionAbs;
  late final ASTExternalClassFunction _functionSign;
  late final ASTExternalClassFunction _functionClamp;
  late final ASTExternalClassFunction _functionRemainder;
  late final ASTExternalClassFunction _functionToRadixString;
  late final ASTExternalClassFunction _functionToDouble;

  CoreClassInt._() : super(ASTTypeInt.instance, 'int') {
    _functionParseInt = _externalStaticFunctionArgs1(
      'parseInt',
      ASTTypeInt.instance,
      ASTFunctionParameterDeclaration(ASTTypeString.instance, 's', 0, false),
      (dynamic s) => int.parse(s),
    );

    _functionTryParse = _externalStaticFunctionArgs1(
      'tryParse',
      ASTTypeInt.instance,
      ASTFunctionParameterDeclaration(ASTTypeString.instance, 's', 0, false),
      (dynamic s) => int.tryParse(s),
    );

    _functionValueOf = _externalStaticFunctionArgs1(
      'valueOf',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(ASTTypeDynamic.instance, 'obj', 0, false),
      (dynamic o) => '$o',
    );

    _functionCompareTo = _externalClassFunctionArgs1(
      'compareTo',
      ASTTypeInt.instance,
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'other', 0, false),
      (int self, dynamic other) => self.compareTo(other),
    );

    _functionAbs = _externalClassFunctionArgs0(
      'abs',
      ASTTypeInt.instance,
      (int self) => self.abs(),
    );

    _functionSign = _externalClassFunctionArgs0(
      'sign',
      ASTTypeInt.instance,
      (int self) => self.sign,
    );

    _functionClamp = _externalClassFunctionArgs2(
      'clamp',
      ASTTypeInt.instance,
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'lower', 0, false),
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'upper', 1, false),
      (int self, dynamic lower, dynamic upper) => self.clamp(lower, upper),
    );

    _functionRemainder = _externalClassFunctionArgs1(
      'remainder',
      ASTTypeInt.instance,
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'other', 0, false),
      (int self, dynamic other) => self.remainder(other),
    );

    _functionToRadixString = _externalClassFunctionArgs1(
      'toRadixString',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'radix', 0, false),
      (int self, dynamic radix) => self.toRadixString(radix),
    );

    _functionToDouble = _externalClassFunctionArgs0(
      'toDouble',
      ASTTypeDouble.instance,
      (int self) => self.toDouble(),
    );
  }

  @override
  ASTFunctionDeclaration? getFunction(
    String fName,
    ASTFunctionSignature parametersSignature,
    VMContext context, {
    bool caseInsensitive = false,
  }) {
    switch (fName) {
      // static
      case 'parseInt':
      case 'parse':
        return _functionParseInt;
      case 'tryParse':
        return _functionTryParse;
      case 'valueOf':
        return _functionValueOf;

      // class
      case 'compareTo':
        return _functionCompareTo;
      case 'abs':
        return _functionAbs;
      case 'sign':
        return _functionSign;
      case 'clamp':
        return _functionClamp;
      case 'remainder':
        return _functionRemainder;
      case 'toRadixString':
        return _functionToRadixString;
      case 'toDouble':
        return _functionToDouble;
    }

    throw StateError(
      "Can't find core function: $coreName.$fName( $parametersSignature )",
    );
  }
}

class CoreClassDouble extends CoreClassPrimitive<double> {
  static final CoreClassDouble instance = CoreClassDouble._();

  // static
  late final ASTExternalFunction _functionParseDouble;
  late final ASTExternalFunction _functionTryParse;
  late final ASTExternalFunction _functionValueOf;

  // class
  late final ASTExternalClassFunction _functionCompareTo;
  late final ASTExternalClassFunction _functionAbs;
  late final ASTExternalClassFunction _functionSign;
  late final ASTExternalClassFunction _functionClamp;
  late final ASTExternalClassFunction _functionRemainder;
  late final ASTExternalClassFunction _functionToStringAsFixed;
  late final ASTExternalClassFunction _functionToStringAsExponential;
  late final ASTExternalClassFunction _functionToStringAsPrecision;
  late final ASTExternalClassFunction _functionToInt;
  late final ASTExternalClassFunction _functionRound;
  late final ASTExternalClassFunction _functionFloor;
  late final ASTExternalClassFunction _functionCeil;
  late final ASTExternalClassFunction _functionTruncate;

  CoreClassDouble._() : super(ASTTypeDouble.instance, 'double') {
    _functionParseDouble = _externalStaticFunctionArgs1(
      'parseDouble',
      ASTTypeDouble.instance,
      ASTFunctionParameterDeclaration(ASTTypeString.instance, 's', 0, false),
      (dynamic s) => double.parse(s),
    );

    _functionTryParse = _externalStaticFunctionArgs1(
      'tryParse',
      ASTTypeDouble.instance,
      ASTFunctionParameterDeclaration(ASTTypeString.instance, 's', 0, false),
      (dynamic s) => double.tryParse(s),
    );

    _functionValueOf = _externalStaticFunctionArgs1(
      'valueOf',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(ASTTypeDynamic.instance, 'obj', 0, false),
      (dynamic o) => '$o',
    );

    _functionCompareTo = _externalClassFunctionArgs1(
      'compareTo',
      ASTTypeInt.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeDouble.instance,
        'other',
        0,
        false,
      ),
      (double self, dynamic other) => self.compareTo(other),
    );

    _functionAbs = _externalClassFunctionArgs0(
      'abs',
      ASTTypeDouble.instance,
      (double self) => self.abs(),
    );

    _functionSign = _externalClassFunctionArgs0(
      'sign',
      ASTTypeDouble.instance,
      (double self) => self.sign,
    );

    _functionClamp = _externalClassFunctionArgs2(
      'clamp',
      ASTTypeDouble.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeDouble.instance,
        'lower',
        0,
        false,
      ),
      ASTFunctionParameterDeclaration(
        ASTTypeDouble.instance,
        'upper',
        1,
        false,
      ),
      (double self, dynamic lower, dynamic upper) => self.clamp(lower, upper),
    );

    _functionRemainder = _externalClassFunctionArgs1(
      'remainder',
      ASTTypeDouble.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeDouble.instance,
        'other',
        0,
        false,
      ),
      (double self, dynamic other) => self.remainder(other),
    );

    _functionToStringAsFixed = _externalClassFunctionArgs1(
      'toStringAsFixed',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeInt.instance,
        'fractionDigits',
        0,
        false,
      ),
      (double self, dynamic digits) => self.toStringAsFixed(digits),
    );

    _functionToStringAsExponential = _externalClassFunctionArgs1(
      'toStringAsExponential',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeInt.instance,
        'fractionDigits',
        0,
        true,
      ),
      (double self, dynamic digits) => digits == null
          ? self.toStringAsExponential()
          : self.toStringAsExponential(digits),
    );

    _functionToStringAsPrecision = _externalClassFunctionArgs1(
      'toStringAsPrecision',
      ASTTypeString.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeInt.instance,
        'precision',
        0,
        false,
      ),
      (double self, dynamic precision) => self.toStringAsPrecision(precision),
    );

    _functionToInt = _externalClassFunctionArgs0(
      'toInt',
      ASTTypeInt.instance,
      (double self) => self.toInt(),
    );

    _functionRound = _externalClassFunctionArgs0(
      'round',
      ASTTypeInt.instance,
      (double self) => self.round(),
    );

    _functionFloor = _externalClassFunctionArgs0(
      'floor',
      ASTTypeInt.instance,
      (double self) => self.floor(),
    );

    _functionCeil = _externalClassFunctionArgs0(
      'ceil',
      ASTTypeInt.instance,
      (double self) => self.ceil(),
    );

    _functionTruncate = _externalClassFunctionArgs0(
      'truncate',
      ASTTypeInt.instance,
      (double self) => self.truncate(),
    );
  }

  @override
  ASTFunctionDeclaration? getFunction(
    String fName,
    ASTFunctionSignature parametersSignature,
    VMContext context, {
    bool caseInsensitive = false,
  }) {
    switch (fName) {
      // static
      case 'parseDouble':
      case 'parse':
        return _functionParseDouble;
      case 'tryParse':
        return _functionTryParse;
      case 'valueOf':
        return _functionValueOf;

      // class
      case 'compareTo':
        return _functionCompareTo;
      case 'abs':
        return _functionAbs;
      case 'sign':
        return _functionSign;
      case 'clamp':
        return _functionClamp;
      case 'remainder':
        return _functionRemainder;
      case 'toStringAsFixed':
        return _functionToStringAsFixed;
      case 'toStringAsExponential':
        return _functionToStringAsExponential;
      case 'toStringAsPrecision':
        return _functionToStringAsPrecision;
      case 'toInt':
        return _functionToInt;
      case 'round':
        return _functionRound;
      case 'floor':
        return _functionFloor;
      case 'ceil':
        return _functionCeil;
      case 'truncate':
        return _functionTruncate;
    }

    throw StateError(
      "Can't find core function: $coreName.$fName( $parametersSignature )",
    );
  }
}

class CoreClassList<T> extends CoreClassBase<List<T>> {
  static final CoreClassList instanceOfObject = CoreClassList<Object>._();
  static final CoreClassList<String> instanceOfString =
      CoreClassList<String>._();
  static final CoreClassList<int> instanceOfInt = CoreClassList<int>._();
  static final CoreClassList<double> instanceOfDouble =
      CoreClassList<double>._();
  static final CoreClassList<bool> instanceOfBool = CoreClassList<bool>._();
  static final CoreClassList<dynamic> instanceOfDynamic =
      CoreClassList<dynamic>._();

  static CoreClassList<T>? fromType<T>(Type type) {
    if (type == List<String>) {
      return instanceOfString as CoreClassList<T>;
    } else if (type == List<int>) {
      return instanceOfInt as CoreClassList<T>;
    } else if (type == List<double>) {
      return instanceOfDouble as CoreClassList<T>;
    } else if (type == List<bool>) {
      return instanceOfBool as CoreClassList<T>;
    } else if (type == List<Object>) {
      return instanceOfObject as CoreClassList<T>;
    } else if (type == List<dynamic>) {
      return instanceOfDynamic as CoreClassList<T>;
    }

    return null;
  }

  late final ASTExternalClassGetter _getterLength;
  late final ASTExternalClassGetter _getterIsEmpty;
  late final ASTExternalClassGetter _getterIsNotEmpty;

  late final ASTExternalClassFunction _functionAdd;
  late final ASTExternalClassFunction _functionAddAll;
  late final ASTExternalClassFunction _functionRemove;
  late final ASTExternalClassFunction _functionRemoveAt;

  late final ASTExternalClassFunction _functionContains;

  late final ASTExternalClassFunction _functionLength;
  late final ASTExternalClassFunction _functionIsEmpty;
  late final ASTExternalClassFunction _functionIsNotEmpty;

  late final ASTExternalClassFunction _functionClear;
  late final ASTExternalClassFunction _functionIndexOf;
  late final ASTExternalClassFunction _functionInsert;

  late final ASTExternalClassFunction _functionFirst;
  late final ASTExternalClassFunction _functionLast;

  late final ASTExternalClassFunction _functionSublist;

  late final ASTExternalFunction _functionValueOf;

  CoreClassList._()
    : super(
        ASTTypeArray.fromType(List<T>) as ASTTypeArray<ASTType<T>, T>? ??
            (throw ArgumentError(
              "Can't resolve `ASTTypeArray` for type `$T` (`ASTTypeArray<$T>`)",
            )),
        'List',
      ) {
    _getterLength = _externalClassGetter(
      'length',
      ASTTypeInt.instance,
      (Object? o) => o is List ? o.length : null,
    );

    _getterIsEmpty = _externalClassGetter(
      'isEmpty',
      ASTTypeBool.instance,
      (Object? o) => o is List ? o.isEmpty : null,
    );

    _getterIsNotEmpty = _externalClassGetter(
      'isNotEmpty',
      ASTTypeBool.instance,
      (Object? o) => o is List ? o.isNotEmpty : null,
    );

    _functionAdd = _externalClassFunctionArgs1(
      'add',
      ASTTypeBool.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeDynamic.instance,
        'value',
        0,
        false,
      ),
      (List o, dynamic v) {
        o.add(v);
        return true;
      },
    );

    _functionAddAll = _externalClassFunctionArgs1(
      'addAll',
      ASTTypeBool.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeArray.instanceOfObject,
        'values',
        0,
        false,
      ),
      (List o, List v) {
        o.addAll(v);
        return true;
      },
    );

    _functionRemove = _externalClassFunctionArgs1(
      'remove',
      ASTTypeBool.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeDynamic.instance,
        'value',
        0,
        false,
      ),
      (List o, dynamic v) => o.remove(v),
    );

    _functionRemoveAt = _externalClassFunctionArgs1(
      'removeAt',
      ASTTypeDynamic.instance,
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'index', 0, false),
      (List o, int i) => o.removeAt(i),
    );

    _functionContains = _externalClassFunctionArgs1(
      'contains',
      ASTTypeBool.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeDynamic.instance,
        'value',
        0,
        false,
      ),
      (List o, dynamic v) => o.contains(v),
    );

    _functionLength = _externalClassFunctionArgs0(
      'length',
      ASTTypeInt.instance,
      (List o) => o.length,
    );

    _functionIsEmpty = _externalClassFunctionArgs0(
      'isEmpty',
      ASTTypeBool.instance,
      (List o) => o.isEmpty,
    );

    _functionIsNotEmpty = _externalClassFunctionArgs0(
      'isNotEmpty',
      ASTTypeBool.instance,
      (List o) => o.isNotEmpty,
    );

    _functionClear = _externalClassFunctionArgs0(
      'clear',
      ASTTypeVoid.instance,
      (List o) {
        o.clear();
        return null;
      },
    );

    _functionIndexOf = _externalClassFunctionArgs1(
      'indexOf',
      ASTTypeInt.instance,
      ASTFunctionParameterDeclaration(
        ASTTypeDynamic.instance,
        'value',
        0,
        false,
      ),
      (List o, dynamic v) => o.indexOf(v),
    );

    _functionInsert = _externalClassFunctionArgs2(
      'insert',
      ASTTypeVoid.instance,
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'index', 0, false),
      ASTFunctionParameterDeclaration(
        ASTTypeDynamic.instance,
        'value',
        1,
        false,
      ),
      (List o, int i, dynamic v) {
        o.insert(i, v);
        return null;
      },
    );

    _functionFirst = _externalClassFunctionArgs0(
      'first',
      ASTTypeDynamic.instance,
      (List o) => o.first,
    );

    _functionLast = _externalClassFunctionArgs0(
      'last',
      ASTTypeDynamic.instance,
      (List o) => o.last,
    );

    _functionSublist = _externalClassFunctionArgs2(
      'sublist',
      ASTTypeArray.instanceOfObject,
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'start', 0, false),
      ASTFunctionParameterDeclaration(ASTTypeInt.instance, 'end', 1, true),
      (List o, dynamic start, dynamic end) {
        if (end == null) return o.sublist(start);
        return o.sublist(start, end);
      },
    );

    _functionValueOf = _externalStaticFunctionArgs1(
      'valueOf',
      ASTTypeArray.instanceOfObject,
      ASTFunctionParameterDeclaration(ASTTypeDynamic.instance, 'obj', 0, false),
      (dynamic o) {
        if (o == null) return [];
        if (o is List) return o;
        return [o];
      },
      resolveValueToList,
    );
  }

  List resolveValueToList(ASTValue? paramVal, VMContext context) {
    if (paramVal == null) return [];

    if (paramVal is VMObject) {
      final v = paramVal.getValue(context);
      if (v is List) return v;
      return [v];
    }

    final val = paramVal.getValue(context);
    if (val is List) return val;
    return [val];
  }

  @override
  ASTGetterDeclaration? getGetter(
    String fName,
    VMContext context, {
    bool caseInsensitive = false,
  }) {
    switch (fName) {
      case 'length':
        return _getterLength;
      case 'isEmpty':
        return _getterIsEmpty;
      case 'isNotEmpty':
        return _getterIsNotEmpty;
    }

    throw StateError("Can't find core getter: $coreName.$fName");
  }

  @override
  ASTFunctionDeclaration? getFunction(
    String fName,
    ASTFunctionSignature parametersSignature,
    VMContext context, {
    bool caseInsensitive = false,
  }) {
    switch (fName) {
      case 'add':
        return _functionAdd;
      case 'addAll':
        return _functionAddAll;
      case 'remove':
        return _functionRemove;
      case 'removeAt':
        return _functionRemoveAt;

      case 'contains':
        return _functionContains;

      case 'length':
        return _functionLength;
      case 'isEmpty':
        return _functionIsEmpty;
      case 'isNotEmpty':
        return _functionIsNotEmpty;

      case 'clear':
        return _functionClear;
      case 'indexOf':
        return _functionIndexOf;
      case 'insert':
        return _functionInsert;

      case 'first':
        return _functionFirst;
      case 'last':
        return _functionLast;

      case 'sublist':
        return _functionSublist;

      case 'valueOf':
        return _functionValueOf;
    }

    throw StateError(
      "Can't find core function: $coreName.$fName( $parametersSignature )",
    );
  }

  @override
  FutureOr<ASTValue<List<T>>?> createInstance(
    VMClassContext<dynamic> context,
    ASTRunStatus runStatus,
  ) {
    throw UnimplementedError();
  }

  @override
  List<ASTClassField<dynamic>> get fields => throw UnimplementedError();

  @override
  List<String> get fieldsNames => throw UnimplementedError();

  @override
  FutureOr<Map<String, Object>> getFieldsMap({
    VMContext? context,
    Map<String, ASTValue<dynamic>>? fieldOverwrite,
  }) {
    throw UnimplementedError();
  }

  @override
  FutureOr<ASTValue<dynamic>?> getInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<List<dynamic>> instance,
    String fieldName, {
    bool caseInsensitive = false,
  }) {
    throw UnimplementedError();
  }

  @override
  FutureOr<void> initializeInstance(
    VMClassContext<dynamic> context,
    ASTRunStatus runStatus,
    ASTValue<List<dynamic>> instance,
  ) {
    throw UnimplementedError();
  }

  @override
  FutureOr<ASTValue<dynamic>?> removeInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<List<dynamic>> instance,
    String fieldName, {
    bool caseInsensitive = false,
  }) {
    throw UnimplementedError();
  }

  @override
  void resolveNodeFields(ASTNode? parentNode) {}

  @override
  FutureOr<void> setInstanceByMap(
    VMClassContext<dynamic> context,
    ASTRunStatus runStatus,
    ASTValue<List<dynamic>> instance,
    Map<String, ASTValue<dynamic>> value, {
    bool caseInsensitive = false,
  }) {
    throw UnimplementedError();
  }

  @override
  FutureOr<void> setInstanceByVMObject(
    VMClassContext<dynamic> context,
    ASTRunStatus runStatus,
    ASTValue<List<dynamic>> instance,
    VMObject value,
  ) {
    throw UnimplementedError();
  }

  @override
  FutureOr<void> setInstanceByValue(
    VMClassContext<dynamic> context,
    ASTRunStatus runStatus,
    ASTValue<List<dynamic>> instance,
    ASTValue<List<dynamic>> value,
  ) {
    throw UnimplementedError();
  }

  @override
  FutureOr<ASTValue<dynamic>?> setInstanceFieldValue(
    VMContext context,
    ASTRunStatus runStatus,
    ASTValue<List<dynamic>> instance,
    String fieldName,
    ASTValue<dynamic> value, {
    bool caseInsensitive = false,
  }) {
    throw UnimplementedError();
  }
}
