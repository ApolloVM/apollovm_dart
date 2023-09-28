// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

import 'dart:convert';
import 'dart:typed_data';

import '../../apollovm_generated_output.dart';

enum BlockType {
  voidType(0x40),
  i32Type(0x7f),
  i64Type(0x7e),
  f32Type(0x7d),
  f64Type(0x7c);

  final int value;

  const BlockType(this.value);
}

enum FloatAlign { align1, align2, align3 }

/// Wasm constants and helpers.
class Wasm {
  static const typeIdx = 0x00;
  static const memoryIdx = 0x02;
  static const globalType = 0x03;
  static const functionType = 0x60;

  static const i32Eqz = 0x45;
  static const i32Eq = 0x46;
  static const i32Ne = 0x47;
  static const i32LtS = 0x48;
  static const i32LtU = 0x49;
  static const i32GtS = 0x4a;
  static const i32LeS = 0x4c;
  static const i32LeU = 0x4d;
  static const i32GeS = 0x4e;

  static const f64Eq = 0x61;
  static const f64Ne = 0x62;
  static const f64Lt = 0x63;
  static const f64Gt = 0x64;
  static const f64Le = 0x65;
  static const f64Ge = 0x66;

  static const i32Add = 0x6a;
  static const i32Sub = 0x6b;
  static const i32Mul = 0x6c;
  static const i32RemS = 0x6f;
  static const i32And = 0x71;
  static const i32Or = 0x72;

  static const i64RemS = 0x81;
  static const i64And = 0x83;
  static const i64Or = 0x84;

  static const f64Abs = 0x99;
  static const f64Neg = 0x9a;
  static const f64Ceil = 0x9b;
  static const f64Floor = 0x9c;
  static const f64Sqrt = 0x9f;
  static const f64Add = 0xa0;
  static const f64Sub = 0xa1;
  static const f64Mul = 0xa2;
  static const f64Div = 0xa3;
  static const f64Min = 0xa4;
  static const f64Max = 0xa5;

  static const i32TruncF64S = 0xaa;
  static const i32TruncF64U = 0xab;
  static const i64TruncSF64 = 0xb0;
  static const f64ConvertI64S = 0xb9;
  static const f64ConvertI32S = 0xb7;

  static block(BlockType blockType) => [0x02, blockType];

  static loop(BlockType blockType) => [0x03, blockType];

  static ifInstruction(BlockType retType) => [0x04, retType];
  static const elseInstruction = 0x05;
  static const end = 0x0b;

  static List<int> brIf(int i) => [0x0d, ...Leb128.encodeUnsigned(i)];

  static call(int i) => [0x10, ...Leb128.encodeUnsigned(i)];

  static const drop = 0x1a;
  static const select = 0x1b;

  static List<int> localGet(int i) => [0x20, ...Leb128.encodeUnsigned(i)];

  static List<int> localSet(int i) => [0x21, ...Leb128.encodeUnsigned(i)];

  static List<int> localTee(int i) => [0x22, ...Leb128.encodeUnsigned(i)];

  static List<int> globalGet(int i) => [0x23, ...Leb128.encodeUnsigned(i)];

  static List<int> globalSet(int i) => [0x24, ...Leb128.encodeUnsigned(i)];

  static List<int> f64Load(FloatAlign align, int offset) => [
        0x2b,
        ...Leb128.encodeUnsigned(align.index),
        ...Leb128.encodeUnsigned(offset)
      ];

  static List<int> f64Store(FloatAlign align, int offset) => [
        0x39,
        ...Leb128.encodeUnsigned(align.index),
        ...Leb128.encodeUnsigned(offset)
      ];

  static List<int> i32Const(int i) => [0x41, ...Leb128.encodeUnsigned(i)];

  static List<int> f64Const(double i) => [0x44, ...encodeF64(i)];

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

  static List<int> encodeString(String s) {
    var strBs = latin1.encode(s);
    return Uint8List.fromList(
        [...Leb128.encodeUnsigned(strBs.length), ...strBs]);
  }
}
