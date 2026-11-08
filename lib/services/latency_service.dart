import 'dart:convert';
import 'dart:io';

class LatencyService {
  Future<(String ip, String country)> fetchExitInfo() async {
    // 强制走本地 22890 代理的 HttpClient
    final client = HttpClient();
    client.findProxy = (uri) {
      return "PROXY 127.0.0.1:22890"; // 修改端口
    };
    // 忽略证书错误（代理某些节点不安全）
    client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;

    try {
      final request = await client.getUrl(Uri.parse('https://cloudflare.com/cdn-cgi/trace'));
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw Exception('trace 请求失败: ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      String ip = '', country = '';
      for (final line in body.split('\n')) {
        if (line.startsWith('ip=')) ip = line.substring(3).trim();
        if (line.startsWith('loc=')) country = line.substring(4).trim();
      }
      return (ip, country);
    } finally {
      client.close();
    }
  }
}
