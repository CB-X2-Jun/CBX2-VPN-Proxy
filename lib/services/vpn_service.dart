import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_sing_box/flutter_sing_box.dart';
import '../models/node.dart';

class VpnService {
  final _singBox = FlutterSingBox();
  bool _serviceInstalled = false;
  static const _groupTag = 'proxy';

  Future<void> ensureService() async {
    if (_serviceInstalled) return;
    try {
      await _singBox.installService(
        serviceName: 'cbx2_vpn_service',
        displayName: 'CBX2 VPN Service',
        description: 'Core routing service for CBX2 VPN & Proxy',
      ).timeout(const Duration(seconds: 10));
      _serviceInstalled = true;
    } catch (e) {
      try {
        File('cbx2_crash.log').writeAsStringSync(
          'ensureService Error: $e\n',
          mode: FileMode.append,
        );
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> applyConfig(List<VpnNode> nodes, {bool useTun = false}) async {
    await ensureService();

    final configMap = _buildFullConfigMap(nodes, useTun: useTun);

    // 保存到本地方便排错
    try {
      await File('generated_config.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(configMap)
      );
    } catch (_) {}

    final singBox = SingBox.fromJson(configMap);
    final profileId = ProfileStorage.instance.generateProfileId;
    final configPath = await ProfileStorage.instance.getProfilePath(profileId);

    final profile = Profile(
      id: profileId,
      order: 0,
      name: 'CBX2 Nodes',
      outboundsCount: nodes.length,
      typed: TypedProfile(
        type: ProfileType.local, 
        path: configPath,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    await ProfileStorage.instance.addProfile(profile, singBox);
    await _singBox.startVpn();
  }

  Future<void> startIfNeeded() async {
    try {
      final status = await _singBox.queryServiceStatus();
      final running = (status as dynamic).running;
      if (running != true) {
        await _singBox.startVpn();
      }
    } catch (_) {
      await _singBox.startVpn();
    }
  }

  // ======= 手搓 HTTP 通信，绕开插件 Bug =======

  /// 通过请求 Clash API 切换当前分组下的节点
  Future<void> switchNode(String tag) async {
    final url = Uri.parse('http://127.0.0.1:9090/proxies/$_groupTag');
    await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': tag}),
    );
  }

  /// 通过请求 Clash API 获取单个节点的真实延迟
  Future<int?> testDelay(String tag) async {
    try {
      final url = Uri.parse(
          'http://127.0.0.1:9090/proxies/${Uri.encodeComponent(tag)}/delay?timeout=5000&url=${Uri.encodeComponent('https://www.gstatic.com/generate_204')}');
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['delay'] as int?;
      }
    } catch (_) {}
    return null;
  }

  Future<void> disconnect() async {
    await _singBox.stopVpn();
  }

  Map<String, dynamic> _buildFullConfigMap(List<VpnNode> nodes, {required bool useTun}) {
    final inbound = {
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': '0.0.0.0',
      'listen_port': 8890,
    };

    final outbounds = nodes.map((n) => n.outbound).toList();
    outbounds.add({
      'type': 'selector',
      'tag': _groupTag,
      'outbounds': nodes.map((n) => n.outbound['tag'] as String).toList(),
      'default': nodes.first.outbound['tag'],
    });

    return {
      'log': {
        'level': 'info',
        'timestamp': true,
      },
      'dns': {
        'servers': [
          {
            'tag': 'dns-direct',
            'type': 'udp',
            'server': '223.5.5.5',
          },
          {
            'tag': 'dns-remote',
            'type': 'https',
            'server': '1.1.1.1',
            'detour': _groupTag,
          }
        ],
        'final': 'dns-remote',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [inbound],
      'outbounds': [
        ...outbounds,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'auto_detect_interface': true,
        'final': _groupTag,
        'default_domain_resolver': 'dns-direct',
      },
      'experimental': {
        'clash_api': {
          'external_controller': '0.0.0.0:9090',
          'default_mode': 'rule',
        },
      },
    };
  }
}
