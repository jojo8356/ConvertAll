// sha256.dart, a small SHA-256 for the catalogue digest.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The specification (annexe C of `doc/CLI_RUST_CAHIER_DES_CHARGES.md`) asks
// the JSON output and `doctor` to report the SHA-256 of the unit catalogue
// that was loaded: without it, nobody can tell *which* catalogue produced a
// result.  Dart ships no digest in its core libraries and this repository has
// no dependency on `crypto`; the algorithm is 60 lines of integer arithmetic
// (FIPS 180-4), so it is implemented here rather than adding a dependency for
// one call per process.
//
// `test/core/sha256_test.dart` checks it against the published test vectors
// (`""`, `"abc"`, the 448-bit message and a one-million `a` message).

import 'dart:convert' show utf8;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List, Uint32List;

/// The SHA-256 digests of [data], as a lowercase hexadecimal string.
String sha256Hex(List<int> data) {
  final digest = _sha256(data);
  final buffer = StringBuffer();
  for (final byte in digest) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// The SHA-256 digest of the UTF-8 encoding of [text].
String sha256HexOfText(String text) => sha256Hex(utf8.encode(text));

/// The SHA-256 digest of the file at [path], or `null` when it cannot be read.
String? sha256HexOfFileSync(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return sha256Hex(file.readAsBytesSync());
  } catch (_) {
    return null;
  }
}

const _k = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

Uint8List _sha256(List<int> data) {
  final message = Uint8List.fromList(data);
  final bitLength = message.length * 8;
  // Padding: one 0x80 byte, then zeros, then the 64 bit length, so that the
  // total is a multiple of 64 bytes.
  var padded = message.length + 9;
  final remainder = padded % 64;
  if (remainder != 0) padded += 64 - remainder;
  final block = Uint8List(padded);
  block.setRange(0, message.length, message);
  block[message.length] = 0x80;
  for (var index = 0; index < 8; index++) {
    block[padded - 1 - index] = (bitLength >> (8 * index)) & 0xff;
  }

  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;
  final schedule = Uint32List(64);

  for (var offset = 0; offset < padded; offset += 64) {
    for (var index = 0; index < 16; index++) {
      final base = offset + index * 4;
      schedule[index] =
          (block[base] << 24) |
          (block[base + 1] << 16) |
          (block[base + 2] << 8) |
          block[base + 3];
    }
    for (var index = 16; index < 64; index++) {
      final s0 = _rotate(schedule[index - 15], 7) ^
          _rotate(schedule[index - 15], 18) ^
          (schedule[index - 15] >> 3);
      final s1 = _rotate(schedule[index - 2], 17) ^
          _rotate(schedule[index - 2], 19) ^
          (schedule[index - 2] >> 10);
      schedule[index] =
          (schedule[index - 16] + s0 + schedule[index - 7] + s1) & 0xffffffff;
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (var index = 0; index < 64; index++) {
      final bigS1 = _rotate(e, 6) ^ _rotate(e, 11) ^ _rotate(e, 25);
      final choose = (e & f) ^ (~e & g);
      final temp1 = (h + bigS1 + choose + _k[index] + schedule[index]) &
          0xffffffff;
      final bigS0 = _rotate(a, 2) ^ _rotate(a, 13) ^ _rotate(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (bigS0 + majority) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    h0 = (h0 + a) & 0xffffffff;
    h1 = (h1 + b) & 0xffffffff;
    h2 = (h2 + c) & 0xffffffff;
    h3 = (h3 + d) & 0xffffffff;
    h4 = (h4 + e) & 0xffffffff;
    h5 = (h5 + f) & 0xffffffff;
    h6 = (h6 + g) & 0xffffffff;
    h7 = (h7 + h) & 0xffffffff;
  }

  final digest = Uint8List(32);
  final words = [h0, h1, h2, h3, h4, h5, h6, h7];
  for (var index = 0; index < 8; index++) {
    final word = words[index];
    digest[index * 4] = (word >> 24) & 0xff;
    digest[index * 4 + 1] = (word >> 16) & 0xff;
    digest[index * 4 + 2] = (word >> 8) & 0xff;
    digest[index * 4 + 3] = word & 0xff;
  }
  return digest;
}

int _rotate(int value, int count) =>
    ((value >> count) | (value << (32 - count))) & 0xffffffff;
