// sha256_test.dart, tests of the catalogue digest.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Run with:  flutter test test/core/sha256_test.dart
//
// The expected digests are the published FIPS 180-4 test vectors (the empty
// message, "abc", the 448 bit message and one million "a"), the same values
// `sha256sum` and Python's `hashlib` print.

import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';

import 'package:convertall/core/sha256.dart';

void main() {
  test('matches the FIPS 180-4 test vectors', () {
    expect(
      sha256Hex(const []),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      sha256HexOfText('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      sha256HexOfText(
        'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
      ),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
    expect(
      sha256HexOfText(
        'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'
        'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
      ),
      '59f109d9533b2b70e7c3b814a2bd218f78ea5d3714455bc67987cf0d664399cf',
    );
    // A message of one megabyte, which exercises the multi block padding.
    expect(
      sha256HexOfText(List.filled(1000000, 'a').join()),
      'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
    );
  });

  test('hashes a file and reports a missing one', () {
    final directory = Directory.systemTemp.createTempSync('convertall-sha');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/message.txt')..writeAsStringSync('abc');
    expect(
      sha256HexOfFileSync(file.path),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(sha256HexOfFileSync('${directory.path}/absent.txt'), isNull);
  });

  test('hashes the unit data of the checkout', () {
    final path = 'assets/units.json';
    final digest = sha256HexOfFileSync(path);
    expect(digest, isNotNull);
    expect(digest!.length, 64);
    expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));
    // The digest is stable: hashing the same file twice gives the same value.
    expect(sha256Hex(File(path).readAsBytesSync()), digest);
  });
}
