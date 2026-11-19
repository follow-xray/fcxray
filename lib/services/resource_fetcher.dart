import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/resources.dart';

enum DownloadRoute { proxy, system }

/// Bounded HTTPS downloads. Errors deliberately omit credential-bearing URLs.
class ResourceFetcher {
  const ResourceFetcher({this.allowLoopbackHttp = false});
  final bool allowLoopbackHttp;
  static const _resourceAgent = 'fcxray/0.7.1';
  Uri validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    final local =
        uri != null &&
        ['localhost', '127.0.0.1', '::1', '[::1]'].contains(uri.host);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(allowLoopbackHttp && local && uri.scheme == 'http'))) {
      throw const FormatException('请输入有效的 HTTPS 地址（不含用户名、密码或 #片段）');
    }
    return uri;
  }

  Stream<List<int>> download(
    String source, {
    required int limit,
    String userAgent = _resourceAgent,
    Uri? proxy,
  }) async* {
    var uri = validateUrl(source);
    if (proxy != null &&
        (proxy.scheme != 'http' ||
            !['127.0.0.1', '::1', '[::1]'].contains(proxy.host) ||
            !proxy.hasPort ||
            proxy.port < 1)) {
      throw const FormatException('本地代理地址无效');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..findProxy = (_) =>
          proxy == null ? 'DIRECT' : 'PROXY ${proxy.host}:${proxy.port}';
    try {
      for (var redirects = 0; redirects <= 5; redirects++) {
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 20));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
        final response = await request.close().timeout(
          const Duration(seconds: 20),
        );
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirects == 5) {
            throw const FormatException('重定向无效或次数过多');
          }
          uri = validateUrl(uri.resolve(location).toString());
          // Do not download a redirect body or leave its connection open.
          (await response.detachSocket()).destroy();
          continue;
        }
        if (response.statusCode != 200) {
          throw FormatException('下载失败：HTTP ${response.statusCode}');
        }
        if (response.contentLength > limit) {
          throw const FormatException('下载内容超过大小限制');
        }
        var count = 0;
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          count += chunk.length;
          if (count > limit) throw const FormatException('下载内容超过大小限制');
          if (DateTime.now().isAfter(deadline)) {
            throw const FormatException('下载总时长超过三分钟');
          }
          yield chunk;
        }
        if (count == 0) throw const FormatException('服务器返回了空文件');
        return;
      }
    } on TimeoutException {
      throw const FormatException('下载超时，请稍后重试');
    } on SocketException {
      throw const FormatException('无法连接下载服务器');
    } on HandshakeException {
      throw const FormatException('下载服务器的 TLS 验证失败');
    } on HttpException {
      throw const FormatException('下载响应不完整');
    } finally {
      client.close(force: true);
    }
  }

  /// Each retry gets a fresh consumer. A partial proxy response can never be
  /// concatenated with the direct retry, or overwrite an installed Geo file.
  Future<T> fetch<T>(
    String source, {
    required int limit,
    String userAgent = _resourceAgent,
    Uri? proxy,
    void Function(DownloadRoute)? onRoute,
    required Future<T> Function(Stream<List<int>>) consume,
  }) async {
    if (proxy != null) {
      onRoute?.call(DownloadRoute.proxy);
      try {
        return await consume(
          download(source, limit: limit, proxy: proxy, userAgent: userAgent),
        );
      } on Object {
        /* Retry the complete download over the system network. */
      }
    }
    onRoute?.call(DownloadRoute.system);
    return consume(download(source, limit: limit, userAgent: userAgent));
  }

  Future<String> subscription(
    String url, {
    String userAgent = SubscriptionAgent.xrayHeader,
    Uri? proxy,
    void Function(DownloadRoute)? onRoute,
  }) => fetch(
    url,
    limit: 1024 * 1024,
    userAgent: userAgent,
    proxy: proxy,
    onRoute: onRoute,
    consume: (bytes) async => utf8.decode(
      await bytes.fold<List<int>>([], (buffer, chunk) => buffer..addAll(chunk)),
    ),
  );
}
