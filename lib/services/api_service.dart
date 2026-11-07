import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/node.dart';

class ApiService {
  static const String apiUrl =
      'https://cb-x2-jun.github.io/vpnproxyapi/api.json';

  Future<List<VpnNode>> fetchNodes() async {
    final res = await http.get(Uri.parse(apiUrl));
    if (res.statusCode != 200) {
      throw Exception('API 返回 ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['nodes'] as List;
    return list
        .map((e) => VpnNode.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}