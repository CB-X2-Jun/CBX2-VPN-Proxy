import 'dart:convert';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import '../models/node.dart';

class VpnService {
  final FlutterSingBox _singBox = FlutterSingBox();
  bool _serviceInstalled = false;

  Future<void> ensureService() async {
    if (_serviceInstalled) return;
    try {
      await _singBox.installService();
    } catch (_) {
      // 服务已安装时可能抛错，忽略
    }
    _serviceInstalled = true;
  }

  Future<void> connect(VpnNode node, {bool useTun = true}) async {
    await ensureService();

    final config = _buildConfig(node, useTun: useTun);
    await _singBox.startVpn(config: config);
  }

  Future<void> disconnect() async {
    await _singBox.stopVpn();
  }

  Map<String, dynamic> _buildConfig(VpnNode node, {required bool useTun}) {
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

    return {
      'log': {'level': 'info'},
      'inbounds': [inbound],
      'outbounds': [node.outbound],
      // Windows 下必须启用 auto_detect_interface 防止路由环回
      'route': {'auto_detect_interface': true},
    };
  }
}