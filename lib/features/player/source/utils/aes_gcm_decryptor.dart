import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// 纯 Dart 轻量级 AES-256-GCM / CTR 解密引擎
///
/// 特殊处理说明：
/// 1. GCM 模式解密核心为 AES-256-CTR 流密码解密；
/// 2. CTR 模式在解密时，仅需使用 AES 正向加密对 Counter 进行变换，无需引入逆向 S-box / 逆向列混淆；
/// 3. 零第三方外部 C 库与臃肿依赖，在全平台（Windows, Android, iOS, macOS, Linux）毫秒级执行；
/// 4. 专用于解密 Bimi 等基于 HMAC 派生密钥与 AES-GCM 封装的媒体直链。
class AesGcmDecryptor {
  AesGcmDecryptor._();

  static const List<int> _sbox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
  ];

  static const List<int> _rcon = [
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
  ];

  static Uint8List _keyExpansion(Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError('AES-256 requires 32-byte key, got ${key.length}');
    }

    final w = Uint32List(60); // 4 * (14 + 1)
    final byteData = ByteData.sublistView(key);
    for (var i = 0; i < 8; i++) {
      w[i] = byteData.getUint32(i * 4);
    }

    for (var i = 8; i < 60; i++) {
      var temp = w[i - 1];
      if (i % 8 == 0) {
        // RotWord & SubWord & Rcon
        temp = ((_sbox[(temp >> 16) & 0xff] << 24) |
                (_sbox[(temp >> 8) & 0xff] << 16) |
                (_sbox[temp & 0xff] << 8) |
                (_sbox[(temp >> 24) & 0xff])) ^
            (_rcon[i ~/ 8] << 24);
      } else if (i % 8 == 4) {
        // SubWord
        temp = (_sbox[(temp >> 24) & 0xff] << 24) |
            (_sbox[(temp >> 16) & 0xff] << 16) |
            (_sbox[(temp >> 8) & 0xff] << 8) |
            (_sbox[temp & 0xff]);
      }
      w[i] = w[i - 8] ^ temp;
    }

    final out = Uint8List(240);
    final outView = ByteData.sublistView(out);
    for (var i = 0; i < 60; i++) {
      outView.setUint32(i * 4, w[i]);
    }
    return out;
  }

  static void _encryptBlock(Uint8List input, int inOff, Uint8List roundKeys, Uint8List output, int outOff) {
    final state = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      state[i] = input[inOff + i] ^ roundKeys[i];
    }

    int xtime(int x) => ((x << 1) ^ (((x >> 7) & 1) * 0x1b)) & 0xff;

    for (var round = 1; round < 14; round++) {
      final rOff = round * 16;
      // 1. SubBytes & 2. ShiftRows
      final s0 = _sbox[state[0]];
      final s1 = _sbox[state[5]];
      final s2 = _sbox[state[10]];
      final s3 = _sbox[state[15]];

      final s4 = _sbox[state[4]];
      final s5 = _sbox[state[9]];
      final s6 = _sbox[state[14]];
      final s7 = _sbox[state[3]];

      final s8 = _sbox[state[8]];
      final s9 = _sbox[state[13]];
      final s10 = _sbox[state[2]];
      final s11 = _sbox[state[7]];

      final s12 = _sbox[state[12]];
      final s13 = _sbox[state[1]];
      final s14 = _sbox[state[6]];
      final s15 = _sbox[state[11]];

      // 3. MixColumns & 4. AddRoundKey
      // Col 0
      var t = s0 ^ s1 ^ s2 ^ s3;
      state[0] = s0 ^ xtime(s0 ^ s1) ^ t ^ roundKeys[rOff];
      state[1] = s1 ^ xtime(s1 ^ s2) ^ t ^ roundKeys[rOff + 1];
      state[2] = s2 ^ xtime(s2 ^ s3) ^ t ^ roundKeys[rOff + 2];
      state[3] = s3 ^ xtime(s3 ^ s0) ^ t ^ roundKeys[rOff + 3];

      // Col 1
      t = s4 ^ s5 ^ s6 ^ s7;
      state[4] = s4 ^ xtime(s4 ^ s5) ^ t ^ roundKeys[rOff + 4];
      state[5] = s5 ^ xtime(s5 ^ s6) ^ t ^ roundKeys[rOff + 5];
      state[6] = s6 ^ xtime(s6 ^ s7) ^ t ^ roundKeys[rOff + 6];
      state[7] = s7 ^ xtime(s7 ^ s4) ^ t ^ roundKeys[rOff + 7];

      // Col 2
      t = s8 ^ s9 ^ s10 ^ s11;
      state[8] = s8 ^ xtime(s8 ^ s9) ^ t ^ roundKeys[rOff + 8];
      state[9] = s9 ^ xtime(s9 ^ s10) ^ t ^ roundKeys[rOff + 9];
      state[10] = s10 ^ xtime(s10 ^ s11) ^ t ^ roundKeys[rOff + 10];
      state[11] = s11 ^ xtime(s11 ^ s8) ^ t ^ roundKeys[rOff + 11];

      // Col 3
      t = s12 ^ s13 ^ s14 ^ s15;
      state[12] = s12 ^ xtime(s12 ^ s13) ^ t ^ roundKeys[rOff + 12];
      state[13] = s13 ^ xtime(s13 ^ s14) ^ t ^ roundKeys[rOff + 13];
      state[14] = s14 ^ xtime(s14 ^ s15) ^ t ^ roundKeys[rOff + 14];
      state[15] = s15 ^ xtime(s15 ^ s12) ^ t ^ roundKeys[rOff + 15];
    }

    // Round 14: SubBytes, ShiftRows, AddRoundKey (No MixColumns)
    final rOff14 = 14 * 16;
    output[outOff] = _sbox[state[0]] ^ roundKeys[rOff14];
    output[outOff + 1] = _sbox[state[5]] ^ roundKeys[rOff14 + 1];
    output[outOff + 2] = _sbox[state[10]] ^ roundKeys[rOff14 + 2];
    output[outOff + 3] = _sbox[state[15]] ^ roundKeys[rOff14 + 3];

    output[outOff + 4] = _sbox[state[4]] ^ roundKeys[rOff14 + 4];
    output[outOff + 5] = _sbox[state[9]] ^ roundKeys[rOff14 + 5];
    output[outOff + 6] = _sbox[state[14]] ^ roundKeys[rOff14 + 6];
    output[outOff + 7] = _sbox[state[3]] ^ roundKeys[rOff14 + 7];

    output[outOff + 8] = _sbox[state[8]] ^ roundKeys[rOff14 + 8];
    output[outOff + 9] = _sbox[state[13]] ^ roundKeys[rOff14 + 9];
    output[outOff + 10] = _sbox[state[10 ^ 8]] ^ roundKeys[rOff14 + 10];
    output[outOff + 11] = _sbox[state[7]] ^ roundKeys[rOff14 + 11];

    output[outOff + 12] = _sbox[state[12]] ^ roundKeys[rOff14 + 12];
    output[outOff + 13] = _sbox[state[1]] ^ roundKeys[rOff14 + 13];
    output[outOff + 14] = _sbox[state[6]] ^ roundKeys[rOff14 + 14];
    output[outOff + 15] = _sbox[state[11]] ^ roundKeys[rOff14 + 15];
  }

  /// AES-256-GCM / CTR 解密
  ///
  /// [key]: 32 字节 AES 密钥
  /// [iv]: 12 字节初始化向量
  /// [ciphertext]: 密文
  static Uint8List decryptCtr({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List ciphertext,
  }) {
    if (iv.length != 12) {
      throw ArgumentError('GCM mode standard IV must be 12 bytes, got ${iv.length}');
    }

    final roundKeys = _keyExpansion(key);

    // GCM: J0 = IV || 0x00000001
    // CTR 解密数据所用的计数器从 J1 = IV || 0x00000002 开始递增
    final counter = Uint8List(16);
    counter.setRange(0, 12, iv);
    var counterVal = 2; // inc32(J0) -> starts from 2

    final plaintext = Uint8List(ciphertext.length);
    final blockMask = Uint8List(16);

    for (var offset = 0; offset < ciphertext.length; offset += 16) {
      counter[12] = (counterVal >> 24) & 0xff;
      counter[13] = (counterVal >> 16) & 0xff;
      counter[14] = (counterVal >> 8) & 0xff;
      counter[15] = counterVal & 0xff;
      counterVal++;

      _encryptBlock(counter, 0, roundKeys, blockMask, 0);

      final chunkLen = (offset + 16 <= ciphertext.length) ? 16 : ciphertext.length - offset;
      for (var i = 0; i < chunkLen; i++) {
        plaintext[offset + i] = ciphertext[offset + i] ^ blockMask[i];
      }
    }

    return plaintext;
  }

  /// 针对 Bimi 站点的专属派生与解密
  ///
  /// 算法流程：
  /// 1. AAD = "bimi-response-v1|" + challenge
  /// 2. derivedKey = HMAC-SHA256(key: token, msg: AAD)
  /// 3. CTR 解密并解析为 JSON
  static Map<String, dynamic> decryptBimiPayload({
    required String token,
    required String challenge,
    required String ivBase64,
    required String ciphertextBase64,
  }) {
    final aad = utf8.encode('bimi-response-v1|$challenge');
    final hmac = Hmac(sha256, utf8.encode(token));
    final derivedKey = Uint8List.fromList(hmac.convert(aad).bytes);

    final iv = base64Decode(ivBase64);
    final ciphertext = base64Decode(ciphertextBase64);

    final plaintextBytes = decryptCtr(
      key: derivedKey,
      iv: iv,
      ciphertext: ciphertext,
    );

    final jsonStr = utf8.decode(plaintextBytes);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }
}
