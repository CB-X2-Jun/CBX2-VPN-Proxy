import 'dart:io';
import 'dart:convert';
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

    // 1. 构建完整配置
    final configMap = _buildFullConfigMap(nodes, useTun: useTun);

    // 2. 把生成的 JSON 存到当前目录（exe 旁边），方便你查看排错
    try {
      await File('generated_config.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(configMap)
      );
    } catch (_) {}

    // 3. 转换为 SingBox 对象并存入 Profile
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

  Future<void> selectNode(VpnNode node) async {
    await _singBox.selectOutbound(
      groupTag: _groupTag,
      outboundTag: node.outbound['tag'] as String,
    );
  }

  Future<void> testAll() async {
    await _singBox.urlTest(groupTag: _groupTag);
  }

  Future<void> disconnect() async {
    await _singBox.stopVpn();
  }

  Map<String, dynamic> _buildFullConfigMap(List<VpnNode> nodes, {required bool useTun}) {
    // 强制使用 Mixed 模式，监听 0.0.0.0 方便本机任何客户端连接
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

    // 日志输出路径，用 Windows 标准的正斜杠
    final logPath = '${Directory.systemTemp.path}/sing-box.log'.replaceAll('\\', '/');

    return {
      'log': {
        'level': 'debug',
        'output': logPath,
        'timestamp': true,
      },
      'dns': {
        'servers': [
          {
            'tag': 'dns-direct',
            'type': 'udp',
            'server': '223.5.5.5',
            'detour': 'direct',
          },
          {
            'tag': 'dns-remote',
            'type': 'https',
            'server': '1.1.1.1',
            'detour': _groupTag,
          }
        ],
        'rules': [
          {
            'outbound': 'any',
            'server': 'dns-direct',
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
