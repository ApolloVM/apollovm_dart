// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';
import 'dart:typed_data';

import 'package:data_serializer/data_serializer.dart';

enum WasmType {
  voidType('void', 0x40),
  i32Type('i32', 0x7f),
  i64Type('i64', 0x7e),
  f32Type('f32', 0x7d),
  f64Type('f64', 0x7c);

  final String name;
  final int value;

  const WasmType(this.name, this.value);
}

enum FloatAlign { align1, align2, align3 }

/// Wasm constants and helpers.
class Wasm {
  static const magicModuleHeader = <int>[0x00, 0x61, 0x73, 0x6d];
  static const moduleVersion = <int>[0x01, 0x00, 0x00, 0x00];

  static const typeIdx = 0x00;
  static const memoryIdx = 0x02;
  static const globalType = 0x03;
  static const functionType = 0x60;

  static List<int> block(WasmType blockType) => <int>[0x02, blockType.value];

  static List<int> loop(WasmType blockType) => <int>[0x03, blockType.value];

  static List<int> ifInstruction(WasmType retType) =>
      <int>[0x04, retType.value];

  static const elseInstruction = 0x05;
  static const end = 0x0b;

  static const functionReturn = 0x0f;

  static List<int> brIf(int i) => <int>[0x0d, ...Leb128.encodeUnsigned(i)];

  static List<int> call(int i) => <int>[0x10, ...Leb128.encodeUnsigned(i)];

  static const drop = 0x1a;
  static const select = 0x1b;

  static List<int> localGet(int i) => <int>[0x20, ...Leb128.encodeUnsigned(i)];

  static List<int> localSet(int i) => <int>[0x21, ...Leb128.encodeUnsigned(i)];

  static List<int> localTee(int i) => <int>[0x22, ...Leb128.encodeUnsigned(i)];

  static List<int> globalGet(int i) => <int>[0x23, ...Leb128.encodeUnsigned(i)];

  static List<int> globalSet(int i) => <int>[0x24, ...Leb128.encodeUnsigned(i)];

  static List<int> encodeString(String s) {
    var strBs = latin1.encode(s);
    return Uint8List.fromList(
        [...Leb128.encodeUnsigned(strBs.length), ...strBs]);
  }
}

/// Wasm 32-bits opcodes.
class Wasm32 {
  static List<int> i32Const(int i) => <int>[0x41, ...Leb128.encodeSigned(i)];

  static List<int> f32Const(double i) => <int>[0x43, ...encodeF32(i)];

  static const int i32ExtendToI64Signed = 0xAC;
  static const int i32ExtendToI64Unsigned = 0xAD;

  static const int i32ConvertToF32Signed = 0xB2;
  static const int i32ConvertToF32Unsigned = 0xB3;
  static const int i32ConvertToF64Signed = 0xB7;
  static const int i32ConvertToF64Unsigned = 0xB8;

  static const int i32Add = 0x6A;
  static const int i32Subtract = 0x6B;
  static const int i32Multiply = 0x6C;
  static const int i32DivideSigned = 0x6D;
  static const int i32DivideUnsigned = 0x6E;

  static const int i32RemainderSigned = 0x6F;
  static const int i32RemainderUnsigned = 0x70;

  static const int i32BitwiseAnd = 0x71;
  static const int i32BitwiseOr = 0x72;
  static const int i32BitwiseXor = 0x73;
  static const int i32ShiftLeft = 0x74;
  static const int i32ShiftRightSigned = 0x75;
  static const int i32ShiftRightUnsigned = 0x76;
  static const int i32RotateLeft = 0x77;
  static const int i32RotateRight = 0x78;

  static const int i32EqualsToZero = 0x45;
  static const int i32Equals = 0x46;
  static const int i32NotEquals = 0x47;

  static const int i32LessThanSigned = 0x48;
  static const int i32LessThanUnsigned = 0x49;
  static const int i32GreaterThanSigned = 0x4A;
  static const int i32GreaterThanUnsigned = 0x4B;

  static const int i32LessThanOrEqualsSigned = 0x4C;
  static const int i32LessThanOrEqualsUnsigned = 0x4D;
  static const int i32GreaterThanOrEqualsSigned = 0x4E;
  static const int i32GreaterThanOrEqualsUnsigned = 0x4F;

  static const int f32LessThan = 0x5D;
  static const int f32GreaterThan = 0x5E;
  static const int f32LessThanOrEquals = 0x5F;
  static const int f32GreaterThanOrEquals = 0x60;

  static const int f32Min = 0x96;
  static const int f32Max = 0x97;

  static const int f32Equals = 0x5B;
  static const int f32NotEquals = 0x5C;

  static const int f32Absolute = 0x8B;
  static const int f32Negation = 0x8C;
  static const int f32Ceil = 0x8D;
  static const int f32Floor = 0x8E;
  static const int f32Sqrt = 0x91;

  static const int f32Add = 0x92;
  static const int f32Subtract = 0x93;
  static const int f32Multiply = 0x94;
  static const int f32Divide = 0x95;

  static const int f32TruncateToF32Signed = 0x8F;
  static const int f32TruncateToI32Signed = 0xA8;
  static const int f32TruncateToI32Unsigned = 0xA9;
  static const int f32TruncateToi64Signed = 0xAE;
  static const int f32TruncateToi64Unsigned = 0xAF;

  static Uint8List encodeF32(double d) {
    final arr = Uint8List(4);
    writeFloat32(arr, 0, d);
    return arr;
  }

  static void writeFloat32(Uint8List buffer, int offset, double value) {
    var byteData =
        buffer.buffer.asByteData(buffer.offsetInBytes, buffer.lengthInBytes);
    byteData.setFloat32(offset, value, Endian.little);
  }
}

/// Wasm 64-bits opcodes.
class Wasm64 {
  static List<int> i64Const(int i) => <int>[0x42, ...Leb128.encodeSigned(i)];

  static List<int> f64Const(double i) => <int>[0x44, ...encodeF64(i)];

  static const int i64ConvertToF32Signed = 0xB4;
  static const int i64ConvertToF32Unsigned = 0xB5;
  static const int i64ConvertToF64Signed = 0xB9;
  static const int i64ConvertToF64Unsigned = 0xBA;

  static const int i64Add = 0x7C;
  static const int i64Subtract = 0x7D;
  static const int i64Multiply = 0x7E;
  static const int i64DivideSigned = 0x7F;
  static const int i64DivideUnsigned = 0x80;

  static const int i64RemainderSigned = 0x81;
  static const int i64RemainderUnsigned = 0x82;

  static const int i64BitwiseAnd = 0x83;
  static const int i64BitwiseOr = 0x84;
  static const int i64BitwiseXor = 0x85;
  static const int i64ShiftLeft = 0x86;
  static const int i64ShiftRightSigned = 0x87;
  static const int i64ShiftRightUnsigned = 0x88;
  static const int i64RotateLeft = 0x89;
  static const int i64RotateRight = 0x8A;

  static const int i64EqualsToZero = 0x50;
  static const int i64Equals = 0x51;
  static const int i64NotEquals = 0x52;

  static const int i64LessThanSigned = 0x53;
  static const int i64LessThanUnsigned = 0x54;
  static const int i64GreaterThanSigned = 0x55;
  static const int i64GreaterThanUnsigned = 0x56;

  static const int i64LessThanOrEqualsSigned = 0x57;
  static const int i64LessThanOrEqualsUnsigned = 0x58;
  static const int i64GreaterThanOrEqualsSigned = 0x59;
  static const int i64GreaterThanOrEqualsUnsigned = 0x5A;

  static const int f64LessThan = 0x63;
  static const int f64GreaterThan = 0x64;
  static const int f64LessThanOrEquals = 0x65;
  static const int f64GreaterThanOrEquals = 0x66;

  static const int f64Min = 0xa4;
  static const int f64Max = 0xa5;

  static const int f64Equals = 0x61;
  static const int f64NotEquals = 0x62;

  static const int f64Absolute = 0x99;
  static const int f64Negation = 0x9a;
  static const int f64Ceil = 0x9b;
  static const int f64Floor = 0x9c;
  static const int f64Sqrt = 0x9f;

  static const int f64Add = 0xA0;
  static const int f64Subtract = 0xA1;
  static const int f64Multiply = 0xA2;
  static const int f64Divide = 0xA3;

  static const int f64TruncateToF64Signed = 0x9D;
  static const int f64TruncateToI32Signed = 0xAA;
  static const int f64TruncateToI32Unsigned = 0xAB;
  static const int f64TruncateToi64Signed = 0xB0;
  static const int f64TruncateToi64Unsigned = 0xB1;

  static Uint8List encodeF64(double d) {
    final arr = Uint8List(8);
    writeFloat64(arr, 0, d);
    return arr;
  }

  static void writeFloat64(Uint8List buffer, int offset, double value) {
    var byteData =
        buffer.buffer.asByteData(buffer.offsetInBytes, buffer.lengthInBytes);
    byteData.setFloat64(offset, value, Endian.little);
  }

  static List<int> f64Load(FloatAlign align, int offset) => <int>[
        0x2b,
        ...Leb128.encodeUnsigned(align.index),
        ...Leb128.encodeUnsigned(offset)
      ];

  static List<int> f64Store(FloatAlign align, int offset) => <int>[
        0x39,
        ...Leb128.encodeUnsigned(align.index),
        ...Leb128.encodeUnsigned(offset)
      ];
}
