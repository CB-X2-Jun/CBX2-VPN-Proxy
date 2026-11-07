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
    await _singBox.installService(
      serviceName: 'cbx2_vpn_service',
      displayName: 'CBX2 VPN Service',
      description: 'Core routing service for CBX2 VPN & Proxy',
    );
    _serviceInstalled = true;
  }

  /// 把所有节点写成一个 Profile 并启动服务
  Future<void> applyConfig(List<VpnNode> nodes, {bool useTun = true}) async {
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
            'type': 'tun', 'tag': 'tun-in',
            'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
            'auto_route': true, 'strict_route': true, 'stack': 'mixed',
          }
        : {
            'type': 'mixed', 'tag': 'mixed-in',
            'listen': '127.0.0.1', 'listen_port': 8890,
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
      'dns': {
        'servers': [
          {'tag': 'dns-direct', 'address': '223.5.5.5', 'detour': 'direct'}
        ],
        'final': 'dns-direct',
      },
      'inbounds': [inbound],
      'outbounds': [
        ...outbounds,
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'auto_detect_interface': true,
        'final': _groupTag,
      },
      'experimental': {
        'clash_api': {'external_controller': '127.0.0.1:9090'},
      },
    };
  }
}
