import 'dart:convert';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import '../models/node.dart';

import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'dart:io';

class VpnService {
  final _singBox = FlutterSingBox();
  bool _serviceInstalled = false;
  static const _groupTag = 'proxy';

  Future<void> ensureService() async {
    if (_serviceInstalled) return;
    try {
      // 加上 10 秒超时，防止无限等待
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
      rethrow; // 抛出异常，让 UI 能显示 "连接失败"
    }
  }

  /// 把所有节点写成一个 Profile 并启动服务
  Future<void> applyConfig(List<VpnNode> nodes, {bool useTun = false}) async {
    await ensureService();

    final configMap = _buildFullConfigMap(nodes, useTun: useTun);
    final singBox = SingBox.fromJson(configMap);

    final profileId = ProfileStorage.instance.generateProfileId;
    final configPath = await ProfileStorage.instance.getProfilePath(profileId);

    final profile = Profile(
      id: profileId,
      order: 0,
      name: 'CBX2 Nodes',
      outboundsCount: nodes.length,
      typed: TypedProfile(
        type: ProfileType.local, // 需确认枚举值，见下方说明
        path: configPath,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    await ProfileStorage.instance.addProfile(profile, singBox);
    await _singBox.startVpn(); // 此时当前选中 Profile 已是这份配置
  }

  /// 切换节点（服务不重启）
  Future<void> selectNode(VpnNode node) async {
    await _singBox.selectOutbound(
      groupTag: _groupTag,
      outboundTag: node.outbound['tag'] as String,
    );
  }

  /// 批量 URL 测速
  Future<void> testAll() async {
    await _singBox.urlTest(groupTag: _groupTag);
  }

  Future<void> disconnect() async {
    await _singBox.stopVpn();
  }

  /// 构建完整 sing-box 配置 Map（含 selector 分组）
  Map<String, dynamic> _buildFullConfigMap(List<VpnNode> nodes, {required bool useTun}) {
    final inbound = useTun
        ? {
            'type': 'tun',
            'tag': 'tun-in',
            'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
            'auto_route': true,
            'strict_route': true,
            'stack': 'mixed',
          }
        : {
            'type': 'mixed',
            'tag': 'mixed-in',
            'listen': '127.0.0.1',
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
      'log': {'level': 'info'},
      // --- 修复点 1：使用 sing-box 1.14+ 的新版 DNS 格式 ---
      'dns': {
        'servers': [
          {
            'tag': 'dns-direct',
            'type': 'udp',
            'server': '223.5.5.5',
            'detour': 'direct', // 确保这个 DNS 走直连
          },
          {
            'tag': 'dns-remote',
            'type': 'https',
            'server': '1.1.1.1',
            'detour': _groupTag, // 远端 DNS 走代理
          }
        ],
        'rules': [
          {
            // 代理节点的域名解析，必须走直连 DNS，否则会死锁（节点还没连上，没法用节点查 DNS）
            'outbound': 'any',
            'server': 'dns-direct',
          }
        ],
        'final': 'dns-remote', // 默认使用远端 DNS 解析网页
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
        'default_domain_resolver': 'dns-direct', // 路由级 DNS 兜底
      },
      'experimental': {
        // 开启 Clash API 用于测速
        'clash_api': {
          'external_controller': '127.0.0.1:9090',
          'default_mode': 'rule',
        },
      },
    };
  }

  // 在 VpnService 类里追加
  Future<void> startIfNeeded() async {
    try {
      final status = await _singBox.queryServiceStatus();
      final running = (status as dynamic).running;
      if (running != true) {
        await _singBox.startVpn();
      }
    } catch (_) {
      // 状态查询失败时兜底直接启动
      await _singBox.startVpn();
    }
  }
}
