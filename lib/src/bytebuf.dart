// Copyright (c) 2016, Open DICOMweb Project. All rights reserved.
// Use of this source code is governed by the open source license
// that can be found in the LICENSE file.
// Author: Jim Philbin <jfphilbin@gmail.edu>
// See the AUTHORS file for other contributors.
library odw.sdk.utilities.bytebuf.bytebuf_base;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

// TODO:
//  * Finish documentation
//  * Make buffers Unmodifiable
//  * Make buffer pools, both heap and non-heap and use check accessable.
//  * Make buffers growable
//  * Make a LoggingByteBuf
//  * create a big_endian_bytebuf.
//  * Can the Argument Errors and RangeErrors be merged


/// A Byte Buffer implementation based on Netty's ByteBuf.
///
/// A [ByteBuf] uses an underlying [Uint8List] to contain byte data,
/// where a "byte" is an unsigned 8-bit integer.  The "capacity" of the
/// [ByteBuf] is always equal to the [length] of the underlying [Uint8List].
//TODO: finish description

const _MB = 1024 * 1024;
const _GB = 1024 * 1024 * 1024;

/// A skeletal implementation of a buffer.

class ByteBuf {
  static const defaultLengthInBytes = 1024;
  static const defaultMaxCapacity = 1 * _MB;
  static const maxMaxCapacity = 2 * _GB;
  static const endianness = Endianness.LITTLE_ENDIAN;

  Uint8List _bytes;
  ByteData _bd;
  int _readIndex;
  int _writeIndex;

  //*** Constructors ***

  /// Creates a new [ByteBuf] of [maxCapacity], where
  ///  [readIndex] = [writeIndex] = 0.
  factory ByteBuf([int lengthInBytes = defaultLengthInBytes]) {
    if (lengthInBytes == null)
      lengthInBytes = defaultLengthInBytes;
    if ((lengthInBytes < 0) || (lengthInBytes > maxMaxCapacity))
      throw new ArgumentError("lengthInBytes: $lengthInBytes "
          "(expected: 0 <= lengthInBytes <= maxCapacity($maxMaxCapacity)");
    return new ByteBuf._(new Uint8List(lengthInBytes), 0, 0, lengthInBytes);
  }

  /// Creates a new readable [ByteBuf] from the [Uint8List] [bytes].
  factory ByteBuf.fromByteBuf(ByteBuf buf, [int offset = 0, int length]) {
    length = (length == null) ? buf._bytes.length : length;
    if ((length < 0) || ((offset < 0) || ((buf._bytes.length - offset) < length)))
      throw new ArgumentError('Invalid offset($offset) or '
          'length($length) for ${buf._bytes}bytes(length = ${buf._bytes.lengthInBytes}');
    return new ByteBuf._(buf._bytes, offset, length, length);
  }
  /// Creates a new readable [ByteBuf] from the [Uint8List] [bytes].
  factory ByteBuf.fromUint8List(Uint8List bytes, [int offset = 0, int length]) {
    length = (length == null) ? bytes.length : length;
    if ((length < 0) || ((offset < 0) || ((bytes.length - offset) < length)))
      throw new ArgumentError('Invalid offset($offset) or '
          'length($length) for $bytes(length = ${bytes.lengthInBytes}');
    return new ByteBuf._(bytes, offset, length, length);
  }

  /// Creates a [Uint8List] with the same length as the elements in [list],
  /// and copies over the elements.  Values are truncated to fit in the list
  /// when they are copied, the same way storing values truncates them.
  factory ByteBuf.fromList(List<int> list) =>
      new ByteBuf._(new Uint8List.fromList(list), 0, list.length, list.length);

  /// Internal Constructor: Returns a [ByteBuf] slice from [bytes].
  ByteBuf._(Uint8List bytes, int readIndex, int writeIndex, int length)
      : _bytes = bytes.buffer.asUint8List(readIndex, length),
        _bd = bytes.buffer.asByteData(readIndex, length),
        _readIndex = readIndex,
        _writeIndex = writeIndex;

  /// Creates a new [ByteBuf] that is a view of [this].  The underlying
  /// [Uint8List] is shared, and modifications to it will be visible in the original.
  ByteBuf readSlice(int offset, int length) =>
      new ByteBuf._(_bytes, offset, length, length);

  /// Creates a new [ByteBuf] that is a view of [this].  The underlying
  /// [Uint8List] is shared, and modifications to it will be visible in the original.
  ByteBuf writeSlice(int offset, int length) =>
      new ByteBuf._(_bytes, offset, offset, length);

  /// Creates a new [ByteBuf] that is a [sublist] of [this].  The underlying
  /// [Uint8List] is shared, and modifications to it will be visible in the original.
  ByteBuf sublist(int start, int end) =>
      new ByteBuf._(_bytes, start, end - start, end - start);


  //*** Operators ***

  /// Returns the byte (Uint8) value at [index]
  int operator [](int index) => getUint8(index);

  /// Sets the byte (Uint8) at [index] to [value].
  void operator []=(int index, int value) {setUint8(index, value); }

  @override
  bool operator ==(Object object) =>
      (this == object) ||
          ((object is ByteBuf) && (this.hashCode == object.hashCode));

  //*** Internal Utilities ***

  /// Returns the length of the underlying [Uint8List].
  int get lengthInBytes => _bytes.lengthInBytes;

  /// Checks that the [readIndex] is valid;
  void _checkReadIndex(int index, [int lengthInBytes = 1]) {
    //print("checkReadIndex: index($index), lengthInBytes($lengthInBytes)");
    //print("checkReadIndex: readIndex($_readIndex), writeIndex($_writeIndex)");
    if ((index < _readIndex) || ((index + lengthInBytes) > writeIndex))
      indexOutOfBounds(index, "read");
  }

  /// Checks that the [writeIndex] is valid;
  void _checkWriteIndex(int index, [int lengthInBytes = 1]) {
    if (((index < _writeIndex) || (index + lengthInBytes) >= _bytes.lengthInBytes))
      indexOutOfBounds(index, "write");
  }

  /// Checks that there are at least [minimumReadableBytes] available.
  void _checkReadableBytes(int minimumReadableBytes) {
    if (_readIndex > (_writeIndex - minimumReadableBytes))
      throw new RangeError(
          "readIndex($readIndex) + length($minimumReadableBytes) "
              "exceeds writeIndex($writeIndex): #this");
  }

  /// Checks that there are at least [minimumWritableableBytes] available.
  void _checkWritableBytes(int minimumWritableBytes) {
    if ((_writeIndex + minimumWritableBytes) > lengthInBytes)
      throw new RangeError(
          "writeIndex($writeIndex) + minimumWritableBytes($minimumWritableBytes) "
              "exceeds lengthInBytes($lengthInBytes): $this");
  }

  /// Sets the [readIndex] to [index].  If [index] is not valid a [RangeError] is thrown.
  ByteBuf setReadIndex(int index) {
    if (index < 0 || index > _writeIndex)
      throw new RangeError("readIndex: $index "
          "(expected: 0 <= readIndex <= writeIndex($_writeIndex))");
    _readIndex = index;
    return this;
  }

  /// Sets the [writeIndex] to [index].  If [index] is not valid a [RangeError] is thrown.
  ByteBuf setWriteIndex(int index) {
    if (index < _readIndex || index > capacity)
      throw new RangeError(
          "writeIndex: $index (expected: readIndex($_readIndex) <= writeIndex <= capacity($capacity))");
    _writeIndex = index;
    return this;
  }

  /// Sets the [readIndex] and [writeIndex].  If either is not valid a [RangeError] is thrown.
  ByteBuf setIndices(int readIndex, int writeIndex) {
    if (readIndex < 0 || readIndex > writeIndex || writeIndex > capacity)
      throw new RangeError("readIndex: $readIndex, writeIndex: $writeIndex "
          "(expected: 0 <= readIndex <= writeIndex <= capacity($capacity))");
    _readIndex = readIndex;
    _writeIndex = writeIndex;
    return this;
  }



  //*** Getters and Setters ***

  @override
  int get hashCode => _bytes.hashCode;

  /// Returns the current value of the index where the next read will start.
  int get readIndex => _readIndex;

  /// Sets the [readIndex] to [index].
  set readIndex(int index) { setReadIndex(index); }

  /// Returns the current value of the index where the next write will start.
  int get writeIndex => _writeIndex;

  /// Sets the [writeIndex] to [index].
  set writeIndex(int index) { setWriteIndex(index); }

  /// Returns [true] if [this] is a read only.
  bool get isReadOnly => false;

  //TODO: create subclass
  /// Returns an unmodifiable version of [this].
  /// Note: an UnmodifiableByteBuf can still be read.
  //BytebBufBase get asReadOnly => new UnmodifiableByteBuf(this);

  //*** ByteBuf [_bytes] management

  /// Returns the number of bytes (octets) this buffer can contain.
  int get capacity => _bytes.lengthInBytes;

  /// Returns [true] if there are readable bytes available, false otherwise.
  bool get isReadable => _writeIndex > _readIndex;

  /// Returns [true] if there are [numBytes] available to read, false otherwise.
  bool hasReadable(int numBytes) => _writeIndex - _readIndex >= numBytes;

  /// Returns [true] if there are writable bytes available, false otherwise.
  bool get isWritable => lengthInBytes > _writeIndex;

  /// Returns [true] if there are [numBytes] available to write, false otherwise.
  bool hasWritable(int numBytes) => lengthInBytes - _writeIndex >= numBytes;

  /// Returns the number of readable bytes.
  int get readableBytes => _writeIndex - _readIndex;

  /// Returns the number of writable bytes.
  int get writableBytes => lengthInBytes - _writeIndex;

  //*** Buffer Management Methods ***

  void checkReadableBytes(int minimumReadableBytes) {
    if (minimumReadableBytes < 0)
      throw new ArgumentError("minimumReadableBytes: $minimumReadableBytes (expected: >= 0)");
    _checkReadableBytes(minimumReadableBytes);
  }

  void checkWritableBytes(int minimumWritableBytes) {
    if (minimumWritableBytes < 0)
      throw new ArgumentError("minimumWritableBytes: $minimumWritableBytes (expected: >= 0)");
    _checkWritableBytes(minimumWritableBytes);
  }

  /// Ensures that there are at least [minReadableBytes] available to read.
  void ensureReadable(int minReadableBytes) {
    if (minReadableBytes < 0)
      throw new ArgumentError("minWritableBytes: $minReadableBytes (expected: >= 0)");
    if (minReadableBytes > readableBytes)
      throw new RangeError("writeIndex($_writeIndex) + "
          "minWritableBytes($minReadableBytes) exceeds lengthInBytes($lengthInBytes): $this");
    return;
  }
  /// Ensures that there are at least [minWritableBytes] available to write.
  void ensureWritable(int minWritableBytes) {
    if (minWritableBytes < 0)
      throw new ArgumentError("minWritableBytes: $minWritableBytes (expected: >= 0)");
    if (minWritableBytes > writableBytes)
      throw new RangeError("writeIndex($_writeIndex) + "
          "minWritableBytes($minWritableBytes) exceeds lengthInBytes($lengthInBytes): $this");
    return;
  }

  /// Reset the [readIndex] and [writeIndex] to 0; however, if [hasZeros]
  /// is [true] the contents of the [Uint8List] are set to 0;
  ByteBuf clear({bool hasZeros: false}) {
    if (hasZeros) clearBytes(0, _bytes.lengthInBytes);
    _readIndex = _writeIndex = 0;
    return this;
  }

  /// Zeros out the bytes from [start] to [end].  Returns [true] if successful
  /// and [false] otherwise.  Does not modify the [readIndex] or [writeIndex].
  ByteBuf clearBytes(int start, int end) {
    if (((start < 0) || (start >= lengthInBytes)) ||
        ((end <= start) || (end > _bytes.lengthInBytes)))
      throw new RangeError('Invalid start($start) or end($end)');
    //TODO: could be optomized to use [Uint64List] to zero out.
    //      Note: it might have to be on a 32 or 64 bit boundary.
    for (int i = start; i < end; i++) {
      _bytes[i] = 0;
    }
    return this;
  }

  //*** Read Methods ***

  ///Returns a [bool] value.  [bools]s are encoded as a single byte
  ///where 0 is false and any other value is true.
  bool getBoolean(int index) => getUint8(index) != 0;

  /// Reads a [bool] value.  [bools]s are encoded as a single byte
  /// where 0 is false and any other value is true,
  /// and advances the [readIndex] by 1.
  bool readBoolean() => readUint8() != 0;

  /// Returns an [List] of [bool].
  List<bool> getBooleanList(int index, int length) {
    _checkReadIndex(index, length);
    List<bool> list = new List(length);
    for (int i = 0; i < length; i++)
      list[i] = getBoolean(i);
    return list;
  }

  /// Reads and Returns a [List] of [bool], and advances
  /// the [readIndex] by the number of byte read.
  List<bool> readBooleanList(int length) {
    _checkReadIndex(_readIndex, length);
    var list = getBooleanList(_readIndex, length);
    _readIndex += length;
    return list;
  }

  //*** Int8 Read Methods ***

  /// Returns an signed 8-bit integer.
  int getInt8(int index) {
    _checkReadIndex(index);
    return _bd.getInt8(index);
  }

  /// Read and returns an signed 8-bit integer.
  int readInt8() {
    // print('readInt8: _readIndex($_readIndex)');
    var v = getInt8(_readIndex);
    _readIndex++;
    return v;
  }

  /// Returns an [Int8List] of signed 8-bit integers.
  Int8List getInt8List(int index, int length) {
    _checkReadIndex(index, length);
    return _bytes.buffer.asInt8List(index, length).sublist(0);
  }

  /// Reads and Returns an [Int8List] of signed 8-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Int8List readInt8List(int length) {
    var list = getInt8List(_readIndex, length);
    _readIndex += length;
    return list;
  }

  /// Returns an [Int8List] view of signed 8-bit integers.
  Int8List getInt8ListView(int index, int length) {
    _checkReadIndex(index, length);
    return _bytes.buffer.asInt8List(index, length);
  }

  /// Returns an [Int8List] view of signed 8-bit integers.
  Int8List readInt8ListView(int index, int length) {
    var list = getInt8ListView(index, length);
    _readIndex += length;
    return list;
  }

  //*** Uint8 get, Read Methods ***

  /// Returns an unsigned 8-bit integer.
  int getUint8(int index) {
    _checkReadIndex(index);
    return _bd.getUint8(index);
  }

  /// Reads and returns an unsigned 8-bit integer.
  int readUint8() {
    var v = getUint8(_readIndex);
    _readIndex++;
    return v;
  }

  /// Returns an [Uint8List] of unsigned 8-bit integers.
  Uint8List getUint8List(int index, int length) {
    _checkReadIndex(index, length);
    return _bytes.sublist(index, index + length);
  }

  /// Reads and Returns an [UintList] of unsigned 8-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Uint8List readUint8List(int length) {
    var list = getUint8List(_readIndex, length);
    _readIndex += length;
    return list;
  }

  /// Returns an [Uint8List] view of unsigned 8-bit integers.
  Uint8List getUint8ListSlice(int index, int length) {
    _checkReadIndex(index, length);
      return _bytes.buffer.asUint8List(index, length);
  }

  /// Returns an [Uint8List] view of unsigned 8-bit integers.
  Uint8List readUint8ListSlice(int length) {
    var list = getUint8ListSlice(_readIndex, length);
    _readIndex += length;
    return list;
  }

  //*** Int16 get, Read Methods ***

  /// Returns an unsigned 8-bit integer.
  int getInt16(int index) {
    _checkReadIndex(index);
    return _bd.getInt16(index, endianness);
  }

  /// Returns an unsigned 8-bit integer.
  int readInt16() {
    var v = getInt16(_readIndex);
    _readIndex += 2;
    return v;
  }

  /// Returns an [Int16List] of unsigned 8-bit integers.
  /// [length] is the number of elements in the returned list.
  Int16List getInt16List(int index, int length) {
    _checkReadIndex(index, length * 2);
    if((index ~/ 2) == 0) {
      return _bytes.buffer.asInt16List(index, length).sublist(0);
    } else {
      var list = new Int16List(length);
      for(int i = 0; i < length; i++)
        list[i] = getInt16(index);
      return list;
    }
  }

  /// Reads and Returns an [Int16List] of signed 16-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Int16List readInt16List(int length) {
    var list = getInt16List(_readIndex, length);
    _readIndex += length * 2;
    return list;
  }

  /// Returns an [Int16List] view of unsigned 8-bit integers.
  Int16List getInt16ListSlice(int index, int length) {
    _checkReadIndex(index, length * 2);
    if((index ~/ 2) == 0) {
      return _bytes.buffer.asInt16List(index, length);
    } else {
      // getInt32List(index, length)
      var list = new Int16List(length);
      for(int i = 0; i < length; i++)
        list[i] = getInt16(index);
      return list;
    }

  }

  /// Returns an [Int16List] view of unsigned 8-bit integers.
  Int16List readInt16ListSlice( int length) {
    var slice = getInt16ListSlice(_readIndex, length);
    _readIndex += length * 2;
    return slice;
  }

  //*** Uint16 get, Read Methods ***

  /// Returns an unsigned 16-bit integer.
  int getUint16(int index) {
    _checkReadIndex(index, 2);
    return _bd.getUint16(index, endianness);
  }

  /// Returns an unsigned 16-bit integer.
  int readUint16() {
    // print('readUint16: _readIndex($_readIndex)');
    var v = getUint16(_readIndex);
    // print('readUint16: v($v)');
    _readIndex += 2;
    return v;
  }

  /// Returns an [Uint16List] of unsigned 16-bit integers.
  /// [length] is the number of elements in the returned list.
  Uint16List getUint16List(int index, int length) {
    _checkReadIndex(index, length * 2);
    if((index ~/ 2) == 0) {
      return _bytes.buffer.asUint16List(index, index + length).sublist(0);
    } else {
      var list = new Uint16List(length);
      for(int i = 0; i < length; i++)
        list[i] = getUint16(index);
      return list;
    }
  }

  /// Reads and Returns an [Uint16List] of unsigned 16-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Uint16List readUint16List(int length) {
    // print('readUint16List: length($length');
    var list = getUint16List(_readIndex, length);
    _readIndex += length * 2;
    return list;
  }

  /// Returns an [Uint16List] view of unsigned 16-bit integers.
  Uint16List getUint16ListSlice(int index, int length) {
    _checkReadIndex(index, length * 2);
    if((index ~/ 2) == 0) {
      return _bytes.buffer.asUint16List(index, length);
    } else {
      // getInt32List(index, length)
      var list = new Uint16List(length);
      for(int i = 0; i < length; i++)
        list[i] = getUint16(index);
      return list;
    }
  }

  /// Reads and Returns an [Uint16List] of unsigned 16-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Uint16List readUint16ListSlice(int length) {
    var list = getUint16ListSlice(_readIndex, length);
    _readIndex += length * 2;
    return list;
  }

  //*** Int32 get, Read Methods **

  /// Returns an signed 32-bit integer.
  int getInt32(int index) {
    _checkReadIndex(index);
    return _bd.getInt32(index, endianness);
  }

  /// Returns an signed 32-bit integer.
  int readInt32() {
    var v = getInt32(_readIndex);
    _readIndex += 4;
    return v;
  }

  /// Returns an [Int32List] of signed 32-bit integers.
  /// [length] is the number of elements in the returned list.
  Int32List getInt32List(int index, int length) {
    _checkReadIndex(index, length * 4);
    if ((index ~/ 4) == 0) {
      return _bytes.buffer.asInt32List(index, length).sublist(0);
    } else {
      var list = new Int32List(length);
      var offset = index;
      for (int i = 0; i < length; i++) {
        offset = index + (i * 4);
        print('offset=$offset');
        int foo = getInt32(offset);
        print('foo=$foo');
        list[i] = foo;
      }
      return list;
    }
  }


  /// Reads and Returns an [Int32List] of signed 32-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Int32List readInt32List(int length) {
    var list = getInt32List(_readIndex, length);
    _readIndex += length * 4;
    return list;
  }

  /// Returns an [Int32List] view of signed 32-bit integers.
  Int32List getInt32ListSlice(int index, int length) {
    _checkReadIndex(index, length * 4);
    if((index ~/ 4) == 0) {
      _checkReadIndex(index, length * 4);
      return _bytes.buffer.asInt32List(index, length);
    } else {
      // getInt32List(index, length)
      var list = new Int32List(length);
      for(int i = 0; i < length; i++)
        list[i] = getInt32(index);
      return list;
    }
  }

  /// Reads and Returns an [Int32List] view of signed 32-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Int32List readInt32Slice(int length) {
    var list = getInt32ListSlice(_readIndex, length);
    _readIndex += length * 4;
    return list;
  }


  //*** Uint32 get, Read Methods **

  /// Returns an unsigned 32-bit integer.
  int getUint32(int index) {
    _checkReadIndex(index);
    return _bd.getUint32(index, endianness);
  }

  /// Returns an unsigned 32-bit integer.
  int readUint32() {
    var v = getUint32(_readIndex);
    _readIndex += 4;
    return v;
  }

  /// Returns an [Uint32List] of unsigned 32-bit integers.
  /// [length] is the number of elements in the returned list.
  Uint32List getUint32List(int index, int length) {
    _checkReadIndex(index, length * 4);
    if((index ~/ 4) == 0) {
      _checkReadIndex(index, length * 4);
      return _bytes.buffer.asUint32List(index, length).sublist(0);
    } else {
      var list = new Uint32List(length);
      for(int i = 0; i < length; i++)
        list[i] = getUint32(index);
      return list;
    }
  }

  /// Reads and Returns an [Uint32List] of unsigned 32-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Uint32List readUint32List(int length) {
    var list = getUint32List(_readIndex, length);
    _readIndex += length * 4;
    return list;
  }

  /// Returns an [Uint32List] view of unsigned 32-bit integers.
  Uint32List getUint32ListSlice(int index, int length) {
    _checkReadIndex(index, length * 4);
    //return _bytes.buffer.asUint32List(index, length).sublist(0);
    if (index ~/ 4 == 0) {
      _checkReadIndex(index, length * 4);
      return _bytes.buffer.asUint32List(index, length);
    } else {
      var list = new Uint32List(length);
      for (int i = 0; i < length; i++)
        list[i] = getUint32(index);
      return list;
    }
  }

  /// Reads and Returns an [Uint32List] view of unsigned 32-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Uint32List readUint32ListSlice(int length) {
    var list = getUint32ListSlice(_readIndex, length);
    _readIndex += length * 4;
    return list;
  }

  //*** Int64 get, Read Methods **

  /// Returns an signed 64-bit integer.
  int getInt64(int index) {
    _checkReadIndex(index);
    return _bd.getInt64(index, endianness);
  }

  /// Returns an signed 64-bit integer.
  int readInt64() {
    var v = getInt64(_readIndex);
    _readIndex += 8;
    return v;
  }

  /// Returns an [Int64List] of signed 64-bit integers.
  /// [length] is the number of elements in the returned list.
  Int64List getInt64List(int index, int length) {
    _checkReadIndex(index, length * 8);
    if((index ~/ 8) == 0) {
      _checkReadIndex(index, length * 8);
      return _bytes.buffer.asInt64List(index, length).sublist(0);
    } else {
      var list = new Int64List(length);
      for(int i = 0; i < length; i++)
        list[i] = getInt64(index);
      return list;
    }
  }

  /// Reads and Returns an [Int64List] of signed 64-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Int64List readInt64List(int length) {
    var list = getInt64List(_readIndex, length);
    _readIndex += length * 8;
    return list;
  }

  /// Returns an [Int64List] view of signed 64-bit integers.
  Int64List getInt64ListSlice(int index, int length) {
    _checkReadIndex(index, length * 8);
    if((index ~/ 8) == 0) {
      _checkReadIndex(index, length * 8);
      return _bytes.buffer.asInt64List(index, length);
    } else {
      var list = new Int64List(length);
      for(int i = 0; i < length; i++)
        list[i] = getInt64(index);
      return list;
    }
  }

  /// Reads and Returns an [Int64List] view of signed 64-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Int64List readInt64ListSlice(int length) {
    var list = getInt64ListSlice(_readIndex, length);
    _readIndex += length * 8;
    return list;
  }

  //*** Uint64 get, Read Methods **

  /// Returns an unsigned 64-bit integer.
  int getUint64(int index) {
    _checkReadIndex(index);
    return _bd.getUint64(index, endianness);
  }

  /// Returns an unsigned 64-bit integer.
  int readUint64() {
    var v = getUint64(_readIndex);
    _readIndex += 8;
    return v;
  }

  /// Returns an [Uint64List] of unsigned 64-bit integers.
  /// [length] is the number of elements in the returned list.
  Uint64List getUint64List(int index, int length) {
    if((index ~/ 8) == 0) {
      _checkReadIndex(index, length * 8);
      return _bytes.buffer.asUint64List(index, length).sublist(0);
    } else {
      var list = new Uint64List(length);
      for(int i = 0; i < length; i++)
        list[i] = getUint64(index);
      return list;
    }
  }

  /// Reads and Returns an [Uint64List] of unsigned 64-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Uint64List readUint64List(int length) {
    var list = getUint64List(_readIndex, length);
    _readIndex += length * 8;
    return list;
  }

  /// Returns an [Uint64List] view of unsigned 64-bit integers.
  Uint64List getUint64ListView(int index, int length) {
    _checkReadIndex(index, length * 8);
    return new Uint64List.view(_bytes.buffer, index, length);
  }

  /// Reads and Returns an [Uint64List] view of unsigned 64-bit integers,
  /// and advances the [readIndex] by the number of byte read.
  Uint64List readUint64Slice(int length) {
    var list = getUint64ListView(_readIndex, length);
    _readIndex += length * 8;
    return list;
  }

  //*** Float32 get, Read Methods **

  /// Returns an signed 32-bit floating point number.
  double getFloat32(int index) {
    _checkReadIndex(index);
    return _bd.getFloat32(index, endianness);
  }

  /// Returns an signed 32-bit floating point number.
  double readFloat32() {
    var v = getFloat32(_readIndex);
    _readIndex += 4;
    return v;
  }

  /// Returns an [Float32List] of signed 32-bit floating point numbers.
  /// [length] is the number of elements in the returned list.
  Float32List getFloat32List(int index, int length) {
    _checkReadIndex(index, length * 4);
    if ((index ~/ 4) == 0) {
      return _bytes.buffer.asFloat32List(index, length).sublist(0);
    } else {
      Float32List list = new Float32List(length);
      for (int i = 0; i < length; i++)
        list[i] = getFloat32(index);
      return list;
    }
  }

  /// Reads and Returns an [Float32List] of signed 32-bit floating point numbers,
  /// and advances the [readIndex] by the number of byte read.
  Float32List readFloat32List(int length) {
    var list = getFloat32List(_readIndex, length);
    _readIndex += length * 4;
    return list;
  }

  /// Returns an [Float32List] view of signed 32-bit floating point numbers.
  Float32List getFloat32ListSlice(int index, int length) {
    _checkReadIndex(index, length * 4);
    return _bytes.buffer.asFloat32List(index, index + length);
  }

  /// Reads and Returns an [Float32List] view of signed 32-bit floating point numbers,
  /// and advances the [readIndex] by the number of byte read.
  Float32List readFloat32ListSlice(int length) {
    var list = getFloat32ListSlice(_readIndex, length);
    _readIndex += length * 4;
    return list;
  }

  //*** Float64 get, Read Methods **

  /// Returns an signed 64-bit floating point number.
  double getFloat64(int index) {
    _checkReadIndex(index);
    return _bd.getFloat64(index, endianness);
  }

  /// Returns an signed 64-bit floating point number.
  double readFloat64() {
    var v = getFloat64(_readIndex);
    _readIndex += 8;
    return v;
  }

  /// Returns an [Float64List] of signed 64-bit floating point numbers.
  /// [length] is the number of elements in the returned list.
  Float64List getFloat64List(int index, int length) {
    _checkReadIndex(index, length * 8);
    if ((index ~/ 4) == 0) {
      return _bytes.buffer.asFloat64List(index, length).sublist(0);
    } else {
      Float64List list = new Float64List(length);
      for (int i = 0; i < length; i++)
        list[i] = getFloat64(index);
      return list;
    }
  }

  /// Reads and Returns an [Float64List] of signed 64-bit floating point numbers,
  /// and advances the [readIndex] by the number of byte read.
  Float64List readFloat64List(int length) {
    var list = getFloat64List(_readIndex, length);
    _readIndex += length * 8;
    return list;
  }

  /// Returns an [Float64List] view of signed 64-bit floating point numbers.
  Float64List getFloat64Slice(int index, int length) {
    _checkReadIndex(index, length * 8);
    return _bytes.buffer.asFloat64List(index, length);
  }

  /// Reads and Returns an [Float64List] view of signed 64-bit floating point numbers,
  /// and advances the [readIndex] by the number of byte read.
  Float64List readFloat64Slice(int length) {
    var list = getFloat64Slice(_readIndex, length);
    _readIndex += length * 8;
    return list;
  }

  //*** Strings
  //TODO: add a [Charset charset = UTF8] argument to String methods.
  //      See dart convert encoding.

  /// Returns a [String] by decoding the bytes from [offset]
  /// to [length] as a UTF-8 string.
  String getString(int index, int length) {
    _checkReadIndex(index, length);
    return UTF8.decode(getUint8List(index, length));
  }

  /// Returns a [String] by decoding the bytes from [readIndex]
  /// to [length] as a UTF-8 string, and advances the [readIndex] by [length].
  String readString(int length) {
    var s = getString(_readIndex, length);
    _readIndex += length;
    return s;
  }

  /// Returns an [List] of [String] by decoding the bytes from [index]
  /// to [length] as a UTF-8 string, and then uses [delimeter] to
  /// separated the [String] into a [List].
  List<String> getStringList(int index, int length, [String delimiter = r"\"]) {
    _checkReadIndex(index, length);
    var s = UTF8.decode(getUint8List(index, length));
    return s.split(delimiter);
  }

  /// Returns an [List] of [String] by decoding the bytes from [readIndex]
  /// to [length] as a UTF-8 string, and then uses [delimeter] to
  /// separated the [String] into a [List]. Finally, the [readIndex] is
  /// advanced by [length].
  List<String> readStringList(int length, [String delimiter = r"\"]) {
    var list = getStringList(_readIndex, length, delimiter);
    _readIndex += length;
    return list;
  }


  //*** Bytes set, write

  /// Stores a 8-bit integer at [index].
  ByteBuf setByte(int index, int value) => setUint8(index, value);

  /// Stores a 8-bit integer at [readIndex] and advances [readIndex] by 1.
  ByteBuf writeByte(int value) => writeUint8(value);

  //*** Write Boolean

  /// Stores a [bool] value at [index] as byte (Uint8),
  /// where 0 = [false], and any other value = [true].
  ByteBuf setBoolean(int index, bool value) {
    setUint8(index, value ? 1 : 0);
    return this;
  }

  /// Stores a [bool] value at [index] as byte (Uint8),
  /// where 0 = [false], and any other value = [true].
  ByteBuf writeBoolean(int index, bool value) {
    setUint8(_writeIndex, value ? 1 : 0);
    _writeIndex++;
    return this;
  }

  /// Stores a [List] of [bool] values from [index] as byte (Uint8),
  /// where 0 = [false], and any other value = [true].
  ByteBuf setBooleanList(int index, List<int> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++)
      setInt8(index, list[i]);
    return this;
  }

  /// Stores a [List] of [bool] values from [writeIndex] as byte (Uint8),
  /// where 0 = [false], and any other value = [true].
  ByteBuf writeBooleanList(List<int> list) {
    setBooleanList(_writeIndex, list);
    _writeIndex += list.length;
    return this;
  }


  //*** Write Int8

  /// Stores a Int8 value at [index].
  ByteBuf setInt8(int index, int value) {
    _checkWriteIndex(index);
    _bd.setInt8(index, value);
    return this;
  }

  /// Stores a Int8 value at [writeIndex], and advances
  /// [writeIndex] by 1.
  ByteBuf writeInt8(int value) {
    setInt8(_writeIndex, value);
    _writeIndex++;
    return this;
  }

  /// Stores a [List] of Uint8 [int] values at [index].
  ByteBuf setInt8List(int index, List<int> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++) {
      setInt8(index, list[i]);
      index += 1;
    }
    return this;
  }

  /// Stores a [List] of Uint8 [int] values at [writeIndex], and advances
  /// [writeIndex] by [List] [length]
  ByteBuf writeInt8List(List<int> list) {
    setInt8List(_writeIndex, list);
    _writeIndex += list.length;
    return this;
  }

  //*** Uint8 set, write

  /// Stores a Uint8 value at [index].
  ByteBuf setUint8(int index, int value) {
    _checkWriteIndex(index);
    _bd.setUint8(index, value);
    return this;
  }

  /// Stores a Uint8 value at [writeIndex], and advances [writeIndex] by 1.
  ByteBuf writeUint8(int value) {
    setUint8(_writeIndex, value);
    _writeIndex++;
    return this;
  }

  /// Stores a [List] of Uint8 values at [index].
  ByteBuf setUint8List(int index, List<int> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++)
      setUint8(index + i, list[i]);
    return this;
  }

  /// Stores a [List] of Uint8 values at [writeIndex],
  /// and advances [writeIndex] by [List] [length].
  ByteBuf writeUint8List(List<int> list) {
    setUint8List(_writeIndex, list);
    _writeIndex += list.length;
    return this;
  }

  //*** Int16 set, write

  /// Stores an Int16 value at [index].
  ByteBuf setInt16(int index, int value) {
    _checkWriteIndex(index, 2);
    _bd.setInt16(index, value,endianness);
    return this;
  }

  /// Stores an Int16 value at [writeIndex], and advances [writeIndex] by 2.
  ByteBuf writeInt16(int value) {
    setInt16(_writeIndex, value);
    _writeIndex += 2;
    return this;
  }

  /// Stores a [List] of Int16 values at [index].
  ByteBuf setInt16List(int index, List<int> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++) {
      setInt16(index, list[i]);
      index += 2;
    }
    return this;
  }

  /// Stores a [List] of Int16 values at [writeIndex],
  /// and advances [writeIndex] by ([list] [length] * 2).
  ByteBuf writeInt16List(List<int> list) {
    setInt16List(_writeIndex, list);
    _writeIndex += (list.length * 2);
    return this;
  }

  //*** Uint16 set, write litte Endian

  /// Stores a Uint16 value at [index],
  ByteBuf setUint16(int index, int value) {
    _checkWriteIndex(index, 2);
    _bd.setInt16(index, value, endianness);
    return this;
  }

  /// Stores a Uint16 value at [writeIndex],
  /// and advances [writeIndex] by 2.
  ByteBuf writeUint16(int value) {
    setUint16(_writeIndex, value);
    _writeIndex += 2;
    return this;
  }

  /// Stores a [List] of Uint16 values at [index].
  ByteBuf setUint16List(int index, List<int> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++) {
      setUint16(index, list[i]);
      index += 2;
    }
    return this;
  }

  /// Stores a [List] of Uint16 values at [writeIndex],
  /// and advances [writeIndex] by ([list] [length] * 2).
  ByteBuf writeUint16List(List<int> list) {
    setUint16List(_writeIndex, list);
    _writeIndex += (list.length * 2);
    return this;
  }

  //*** Int32 set, write ***

  /// Stores an Int32 value at [index].
  ByteBuf setInt32(int index, int value) {
    _checkWriteIndex(index, 4);
    _bd.setInt32(index, value, endianness);
    return this;
  }

  /// Stores an Int32 value at [writeIndex],
  /// and advances [writeIndex] by 4.
  ByteBuf writeInt32(int value) {
    setInt32(_writeIndex, value);
    _writeIndex += 4;
    return this;
  }

  /// Stores a [List] of Int32 values at [index],
  ByteBuf setInt32List(int index, List<int> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++) {
      setInt32(index, list[i]);
      index += 4;
    }
    return this;
  }

  /// Stores a [List] of Int32 values at [writeIndex],
  /// and advances [writeIndex] by ([list] [length] * 4).
  ByteBuf writeInt32List(List<int> list) {
    setInt32List(_writeIndex, list);
    _writeIndex += (list.length * 4);
    return this;
  }

  //*** Uint32 set, write

  /// Stores a Uint32 value at [index].
  ByteBuf setUint32(int index, int value) {
    _checkWriteIndex(index, 4);
    _bd.setUint32(index, value, endianness);
    return this;
  }

  /// Stores a Uint32 value at [writeIndex],
  /// and advances [writeIndex] by 4.
  ByteBuf writeUint32(int value) {
    setUint32(_writeIndex, value);
    _writeIndex += 4;
    return this;
  }

  /// Stores a [List] of Uint32 values at [index].
  ByteBuf setUint32List(int index, List<int> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++) {
      setUint32(index, list[i]);
      index += 4;
    }
    return this;
  }

  /// Stores a [List] of Uint32 values at [writeIndex],
  /// and advances [writeIndex] by ([list] [length] * 4).
  ByteBuf writeUint32List(List<int> list) {
    setUint32List(_writeIndex, list);
    _writeIndex += (list.length * 4);
    return this;
  }

  //*** Int64 set, write

  /// Stores an Int64 values at [index].
  ByteBuf setInt64(int index, int value) {
    _checkWriteIndex(index, 8);
    _bd.setInt64(index, value, endianness);
    return this;
  }

  /// Stores an Int64 values at [writeIndex],
  /// and advances [writeIndex] by 8.
  ByteBuf writeInt64(int value) {
    setInt64(_writeIndex, value);
    _writeIndex += 8;
    return this;
  }

  /// Stores a [List] of Int64 values at [index].
  ByteBuf setInt64List(int index, List<int> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++) {
      setInt64(index, list[i]);
      index += 8;
    }
    return this;
  }

  /// Stores a [List] of Int64 values at [writeIndex],
  /// and advances [writeIndex] by ([list] [length] * 8).
  ByteBuf writeInt64List(List<int> list) {
    setInt64List(_writeIndex, list);
    _writeIndex += (list.length * 8);
    return this;
  }

  //*** Uint64 set, write

  /// Stores a Uint64 value at [index].
  ByteBuf setUint64(int index, int value) {
    _checkWriteIndex(index, 8);
    _bd.setUint64(index, value, endianness);
    return this;
  }

  /// Stores a Uint64 value at [writeIndex],
  /// and advances [writeIndex] by 8.
  ByteBuf writeUint64(int value) {
    setUint64(_writeIndex, value);
    _writeIndex += 8;
    return this;
  }

  /// Stores a [List] of Uint64 values at [index].
  ByteBuf setUint64List(int index, List<int> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++) {
      setUint64(index, list[i]);
      index += 8;
    }
    return this;
  }

  /// Stores a [List] of Uint64 values at [writeIndex],
  /// and advances [writeIndex] by ([list] [length] * 8).
  ByteBuf writeUint64List(List<int> list) {
    setUint64List(_writeIndex, list);
    _writeIndex += (list.length * 8);
    return this;
  }

  //*** Float32 set, write

  /// Stores a Float32 value at [index].
  ByteBuf setFloat32(int index, double value) {
    _checkWriteIndex(4);
    _bd.setFloat32(index, value, endianness);
    return this;
  }

  /// Stores a Float32 value at [writeIndex],
  /// and advances [writeIndex] by 4.
  ByteBuf writeFloat32(double value) {
    setFloat32(_writeIndex, value);
    _writeIndex += 4;
    return this;
  }

  /// Stores a [List] of Float32 values at [index].
  ByteBuf setFloat32List(int index, List<double> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++) {
      setFloat32(index, list[i]);
      index += 4;
    }
    return this;
  }

  /// Stores a [List] of Float32 values at [writeIndex],
  /// and advances [writeIndex] by ([list] [length] * 4).
  ByteBuf writeFloat32List(List<double> list) {
    setFloat32List(_writeIndex, list);
    _writeIndex += (list.length * 4);
    return this;
  }

  //*** Float64 set, write

  /// Stores a Float64 value at [index],
  ByteBuf setFloat64(int index, double value) {
    _checkWriteIndex(8);
    _bd.setFloat64(index, value, endianness);
    return this;
  }

  /// Stores a Float64 value at [writeIndex],
  /// and advances [writeIndex] by 8.
  ByteBuf writeFloat64(double value) {
    setFloat64(_writeIndex, value);
    _writeIndex += 8;
    return this;
  }

  /// Stores a [List] of Float64 values at [index].
  ByteBuf setFloat64List(int index, List<double> list) {
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++) {
      setFloat64(index, list[i]);
      index += 8;
    }

    return this;
  }

  /// Stores a [List] of Float64 values at [writeIndex],
  /// and advances [writeIndex] by ([list] [length] * 8).
  ByteBuf writeFloat64List(List<double> list) {
    setFloat64List(_writeIndex, list);
    _writeIndex += (list.length * 8);
    return this;
  }

  //*** String set, write
  //TODO: add Charset parameter

  /// Internal: Store the [String] [value] at [index] in this [ByteBuf].
  int _setString(int index, String value) {
    Uint8List list = UTF8.encode(value);
    _checkWriteIndex(index, list.length);
    for (int i = 0; i < list.length; i++)
      _bytes[index + i] = list[i];
    return list.length;
  }

  /// Store the [String] [value] at [index].
  ByteBuf setString(int index, String value) {
    _setString(index, value);
    return this;
  }

  /// Store the [String] [value] at [writeIndex].
  /// and advance [writeIndex] by the [length] of the decoded string.
  ByteBuf writeString(String value) {
    var length = _setString(_writeIndex, value);
    _writeIndex += length;
    return this;
  }

  int stringListLength(List<String> list) {
    int length = 0;
    for(int i = 0; i < list.length; i++) {
      length += list[i].length;
      length++;
    }
  }

  /// Converts the [List] of [String] into a single [String] separated
  /// by [delimiter], encodes that string into UTF-8, and store the
  /// UTF-8 string at [index].
  ByteBuf setStringList(int index, List<String> list, [String delimiter = r"\"]) {
    String s = list.join(delimiter);
    _checkWriteIndex(index, s.length);
    _setString(index, s);
    return this;
  }

  /// Converts the [List] of [String] into a single [String] separated
  /// by [delimiter], encodes that string into UTF-8, and stores the UTF-8
  /// string at [writeIndex]. Finally, it advances [writeIndex]
  /// by the [length] of the encoded string.
  ByteBuf writeStringList(List<String> list, [String delimiter = r"\"]) {
    String s = list.join(delimiter);
    var length = _setString(_writeIndex, s);
    _writeIndex += length;
    return this;
  }

  //***
  ByteBuf unreadBytes(int length) {
    _checkWriteIndex(_readIndex, - length);
    _readIndex -= length;
    return this;
  }

  ByteBuf skipReadBytes(int length) {
    _checkReadableBytes(length);
    _readIndex += length;
    return this;
  }

  ByteBuf unwriteBytes(int length) {
    _checkWriteIndex(_writeIndex, - length);
    _writeIndex -= length;
    return this;
  }

  /// Compares the content of [this] to the content
  /// of [other].  Comparison is performed in a similar
  /// manner to the [String.compareTo] method.
  int compareTo(ByteBuf other) {
    if (this == other) return 0;
    final int len = readableBytes;
    final int oLen = other.readableBytes;
    final int minLength = math.min(len, oLen);

    int aIndex = readIndex;
    int bIndex = other.readIndex;
    for (int i = 0; i < minLength; i++) {
      if (this[aIndex] > other[bIndex])
        return 1;
      if (this[aIndex] < other[bIndex])
        return -1;
    }
    // The buffers are == upto minLength, so...
    return len - oLen;
  }

  String toHex(int start, int end) {
    var s = "";
    for(int i = start; i < end; i++)
        s += _bytes[i].toRadixString(16).padLeft(2, " 0") + " ";
    return s;
  }
  String debug() {print( """
  ByteBuf $hashCode
    rdIdx: $_readIndex,
    bytes: '${toHex(_readIndex, _writeIndex)}'
    string:'${_bytes.sublist(_readIndex, _writeIndex).toString()}'
    wrIdx: $_writeIndex,
    remaining: ${capacity - _writeIndex }
    cap: $capacity,
    maxCap: $lengthInBytes
  """);}

  @override
  String toString() => 'ByteBuf (rdIdx: $_readIndex, wrIdx: '
      '$_writeIndex, cap: $capacity, maxCap: $lengthInBytes)';

  //*** Error Methods ***

  ///
  void indexOutOfBounds(int index, String type) {
    // print("indexOutOfBounds: index($index), type($type)");
    // print("indexOutOfBounds: readIndex($_readIndex), writeIndex($_writeIndex)");
    String s;
    if (type == "read")
      s = "Invalid Read Index($index): $index "
          "(readIndex($readIndex) <= index($index) < writeIndex($writeIndex)";
    if (type == "write")
      s = "Invalid Write Index($index): $index to ByteBuf($this) with lengthInB "
          "(writeIndex($writeIndex) <= index($index) < capacity(${_bytes.lengthInBytes})";
    throw new RangeError(s);
  }
}
