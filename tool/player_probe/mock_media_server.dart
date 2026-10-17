import 'dart:async';
import 'dart:io';
import 'dart:math';

enum MockServerMode {
  normal,
  eofAndRefuse, // 场景 4a: 断开后持续拒绝连接
  eofAndRecover, // 场景 4b: 断开后恢复服务
  delayHeaders, // 场景 7a: 响应头延迟 9~12 秒
  dripBody, // 场景 7b: 响应头立即返回，数据缓慢滴入 (9~12 秒出首帧)
}

class MockMediaServer {
  MockMediaServer({
    required this.mediaFile,
    this.mode = MockServerMode.normal,
    this.eofByteThreshold = 64 * 1024, // 默认传输 64KB 后切断
    this.headerDelay = const Duration(seconds: 10),
    this.dripBytesPerSecond = 8 * 1024, // 8KB/s 滴入
  });

  final File mediaFile;
  MockServerMode mode;
  final int eofByteThreshold;
  final Duration headerDelay;
  final int dripBytesPerSecond;

  HttpServer? _server;
  int _requestCount = 0;
  bool _hasDroppedOnce = false;

  int get port => _server?.port ?? 0;
  String get url => 'http://127.0.0.1:$port/media.mp4';

  Future<void> start() async {
    final bytes = await mediaFile.readAsBytes();
    final totalLength = bytes.length;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((HttpRequest request) async {
      _requestCount++;
      final reqNum = _requestCount;

      if (mode == MockServerMode.eofAndRefuse && _hasDroppedOnce) {
        // 持续拒绝连接：直接断开 Socket
        try {
          final sock = await request.response.detachSocket();
          sock.destroy();
        } catch (_) {}
        return;
      }

      if (mode == MockServerMode.delayHeaders && _requestCount == 1) {
        await Future<void>.delayed(headerDelay);
      }

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      int start = 0;
      int end = totalLength - 1;

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        if (parts[0].isNotEmpty) {
          start = int.tryParse(parts[0]) ?? 0;
        }
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]) ?? (totalLength - 1);
        }
      }

      if (start >= totalLength) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalLength');
        await request.response.close();
        return;
      }

      final chunkLength = end - start + 1;
      final isPartial = rangeHeader != null;

      request.response.statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(HttpHeaders.contentTypeHeader, 'video/mp4');
      request.response.headers.set(HttpHeaders.contentLengthHeader, chunkLength.toString());
      if (isPartial) {
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalLength');
      }

      if (mode == MockServerMode.eofAndRefuse || (mode == MockServerMode.eofAndRecover && !_hasDroppedOnce)) {
        // 传输部分字节后强制通过 Socket 销毁切断连接
        final toSend = min(chunkLength, eofByteThreshold);
        request.response.add(bytes.sublist(start, start + toSend));
        await request.response.flush();

        _hasDroppedOnce = true;
        try {
          final sock = await request.response.detachSocket();
          sock.destroy();
        } catch (_) {}
        return;
      }

      if (mode == MockServerMode.dripBody) {
        // 缓慢滴入数据：以每 200ms 发送一小块的方式滴入，直到客户端关闭或发完
        final chunkSize = max(512, (dripBytesPerSecond / 5).round());
        var current = start;
        while (current <= end) {
          final sendEnd = min(current + chunkSize, end + 1);
          request.response.add(bytes.sublist(current, sendEnd));
          await request.response.flush();
          current = sendEnd;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        await request.response.close();
        return;
      }

      // 默认/正常流式传输
      request.response.add(bytes.sublist(start, end + 1));
      await request.response.close();
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
