// Copyright (c) 2016, Open DICOMweb Project. All rights reserved.
// Use of this source code is governed by the open source license
// that can be found in the LICENSE file.
// Author: Jim Philbin <jfphilbin@gmail.edu>
// See the AUTHORS file for other contributors.

import 'dart:typed_data';
import 'package:bytebuf/src/bytebuf.dart';

void main() {
  var buf = new ByteBuf();
  buf.debug();
  /*
  var s = "aaaaaaa aaaaaaa aaaaaaa aaaaaaaab";
  print('s(${s.length}): $s');

  print('buf: lengthInBytes(${buf.lengthInBytes})');
  buf.writeString(s);
  var t = buf.readString(s.length);
  print('t(${s.length}): $t');
  */
  //var l = [-1, -2, -3, -4];
  var list = [0x01, 0x02, 0x03, 0x04];
  print('List<int> list: $list');
  var list1 = new Int32List.fromList(list);
  print('Int32List list1: $list1');

  buf.writeInt32List(list1);
  buf.debug();

  var list2 = buf.readInt32List(list.length);
  print('list2: $list2');
  buf.debug();

/*
  List<int> uints = [0, 1, 2, 3, 4];
  Uint8List uint8list = new Uint8List.fromList(uints);
  Uint8List bytes = uint8list.buffer.asUint8List();
  var s1 = "aaaaaaa aaaaaaa aaaaaaa aaaaaaaab";
  print('s1(${s1.length}): $s1');
  ByteBuf buf1 = new ByteBuf();
  buf1.writeString(s);
  print('buf1: $buf1');
  //Bytebuf1 reader = new Bytebuf1.fromUint8List(bytes);
  buf1.writeUint8List(uint8list);
  print('buf1: $buf1');
  var t1 = buf1.readString(s.length);
  print('buf1: $buf1');
  print("t1(${t1.length}): $t1");
  var l3 = buf1.readUint8List(uint8list.length);
  print('buf1: $buf1');
  print('l3: $l3');
  */
  /*
  print("buf1:$buf1");
  int n = buf1.readUint8();
  print('Uint8 = $n');
  n = buf1.readUint8();
  print('Uint8 = $n');
  n = buf1.readUint8();
  print('Uint8 = $n');
  n = buf1.readUint8();
  print('Uint8 = $n');
  */
}