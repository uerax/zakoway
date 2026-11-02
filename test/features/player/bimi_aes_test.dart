import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/utils/aes_gcm_decryptor.dart';

void main() {
  group('AesGcmDecryptor Bimi 加解密引擎测试', () {
    test('1. 真实抓包数据离线还原测试', () {
      const token =
          'F_Kp_Y22J5tJ6C_XTBexZ833XLTxnh3zlMKVbohh4ejhT2B7B9TAU7UIHMzMirztduUYbP6KWFhH3lnPrK0Uia7_Nd6zu3UoZpvanxtx7_CbdZMiUyAfih3yUC0ODf-eAqPZWroSOfT2l6w6WuKnUxce0aNsXS7_NK1lYPhdfS8bbsPXLKtH8AYwGTTb808XYWJLtCDyJWIOGLdPlTPbwRZBpswVigr8yEBXvqfCD10pigeuzSeltHtNYET7KL6Ld-97kdaCuy1aK4ZgwmU';
      const challenge =
          '454d6ca3e2b643e38b728a1b3d44d5e922244d693f250c24eed4ced902507dd0';
      const iv = '5WMRXj3S11oXtN+Y';
      const ciphertext =
          'kBOMul1zMG4QPl6Pn3sp3qFqYqwIiHjHbtnv+lknJd7Ty3vfILCrFnWAc7l39zMUpQztQC47SIzBi6wUDNDeQ0rtrQa+bcOKKGznFZBwTbtdljNVlFyv5NqA6NEQfJoa1mW9MXuxItzZxH1Edw5x3Y03w/pBAP2vWoKGGx/xKU+bByinJLqeQgYTQy+Ji0Zw0aJTXEWiBKX1UHBxkyFUJaQctMQuE4LUfWqd1/iKnmjYLtBQYgtD+LEYc2qPq9umDG3XaBfuoFvRzHVHBlsmvGzm0AbwjDHci3Hn6hZ4R66JpnMUumlG05Qzeq0U3qu0k1Gw//y6FPt+zDGWaEd1vCUolgKoId203aykaIaLU7qQ3i8mxB0sjUhGAnc23KAJR69acumY2oKRrWQ8voYJ25ZESrzNEnHumPNFR8dpVOXMn3jrUhxLGlthn6vcAV8FxBxG9B3HK5XiDzKZ5FX8aavDq/CPV3K5K+pBK4l9efksBAULDJb3EwXAuGWHK/hmAxc++3kzjVxZ7h2Lt6zSa2Zy7JMQZIvJ8gB/j2NCJxDqRDn2wQtrzZwydSyL0PlWVxRP+noXdOZLb8nk1ok+aS84sTVEl0I3gYSJixyIZzRHn5X8UydXBSzfSv/AsrOVF9PlYx/QUl2IK/De';

      final result = AesGcmDecryptor.decryptBimiPayload(
        token: token,
        challenge: challenge,
        ivBase64: iv,
        ciphertextBase64: ciphertext,
      );

      expect(result['id'], 8742);
      expect(result['sid'], 3);
      expect(result['nid'], 1);
      expect(result['url'], isNotNull);
      expect(result['url'].toString(), contains('tiktokcdn-com.akamaized.net'));
    });
  });
}
