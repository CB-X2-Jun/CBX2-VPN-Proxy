import 'dart:convert';
import 'package:http/http.dart' as http;

class LatencyResult {
  final String nodeId;
  final int? delayMs; // null 表示超时/失败
  final String? exitIp;
  final String? exitCountry;

  LatencyResult({
    required this.nodeId,
    this.delayMs,
    this.exitIp,
    this.exitCountry,
  });
}

class LatencyService {
  /// 通过 Clash API 对单个节点触发 URLTest 延迟测试。
  /// 前提：sing-box 已经以包含该节点 outbound 的配置启动，
  /// 并且 Clash API 端口可访问（默认 9090）。
  Future<int?> testDelay(String tag) async {
    try {
      final uri = Uri.parse(
          'http://127.0.0.1:9090/proxies/${Uri.encodeComponent(tag)}/delay?timeout=5000&url=${Uri.encodeComponent('https://www.gstatic.com/generate_204')}');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['delay'] as int?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 通过代理请求 cloudflare trace，校验出口 IP 与国家。
  Future<(String ip, String country)> fetchExitInfo() async {
    final res = await http.get(
      Uri.parse('https://cloudflare.com/cdn-cgi/trace'),
    );
    if (res.statusCode != 200) throw Exception('trace 请求失败');
    final lines = res.body.split('\n');
    String ip = '', country = '';
    for (final line in lines) {
      if (line.startsWith('ip=')) ip = line.substring(3).trim();
      if (line.startsWith('loc=')) country = line.substring(4).trim();
    }
    return (ip, country);
  }
}