import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/node.dart';

class VpnService {
  Process? _singBoxProcess;
  static const _groupTag = 'proxy';

  Future<void> applyConfigAndStart(List<VpnNode> nodes, {bool useTun = false}) async {
    final configMap = _buildFullConfigMap(nodes, useTun: useTun);
    final configString = const JsonEncoder.withIndent('  ').convert(configMap);

    final exePath = Platform.resolvedExecutable;
    // 【修复】统一替换为正斜杠，防止路径拼接出问题
    final exeDir = File(exePath).parent.path.replaceAll('\\', '/');
    
    final configFile = File('$exeDir/generated_config.json');
    await configFile.writeAsString(configString);

    final amd64Dir = '$exeDir/data/flutter_assets/packages/flutter_sing_box/assets/windows/amd64';
    
    // 【修复】尝试两种可能的文件名
    File targetExe = File('$amd64Dir/sing-box.exe');
    if (!targetExe.existsSync()) {
      targetExe = File('$amd64Dir/sing_box.exe');
    }
    
    if (!targetExe.existsSync()) {
      throw Exception('找不到内核文件，请确认路径是否正确: $amd64Dir');
    }

    if (_singBoxProcess != null) {
      _singBoxProcess!.kill();
      _singBoxProcess = null;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    debugPrint('正在启动 sing-box: ${targetExe.path}');
    _singBoxProcess = await Process.start(
      targetExe.path, // 使用找到的路径
      ['run', '-c', configFile.path],
      workingDirectory: exeDir,
      mode: ProcessStartMode.detached,
    );

    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        await http.get(Uri.parse('http://127.0.0.1:29090')).timeout(const Duration(seconds: 1));
        debugPrint('sing-box 启动成功，29090 端口已就绪');
        break; 
      } catch (_) {
        if (i == 9) throw Exception('sing-box 启动超时，端口 29090 无法连接');
      }
    }
  }
  
  Future<void> stop() async {
    if (_singBoxProcess != null) {
      _singBoxProcess!.kill();
      _singBoxProcess = null;
    }
  }

  Future<void> switchNode(String tag) async {
    final url = Uri.parse('http://127.0.0.1:29090/proxies/$_groupTag');
    await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': tag}),
    );
  }

  Future<int?> testDelay(String tag) async {
    try {
      final url = Uri.parse(
          'http://127.0.0.1:29090/proxies/${Uri.encodeComponent(tag)}/delay?timeout=5000&url=${Uri.encodeComponent('https://www.gstatic.com/generate_204')}');
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['delay'] as int?;
      }
    } catch (_) {}
    return null;
  }

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
            'listen_port': 22890,
          };

    final outbounds = nodes.map((n) => n.outbound).toList();
    outbounds.add({
      'type': 'selector',
      'tag': _groupTag,
      'outbounds': nodes.map((n) => n.outbound['tag'] as String).toList(),
      'default': nodes.first.outbound['tag'],
    });

    final exeDir = File(Platform.resolvedExecutable).parent.path.replaceAll('\\', '/');
    final logPath = '$exeDir/sing-box.log';

    return {
      'log': {
        'level': 'info',
        'output': logPath,
        'timestamp': true,
      },
      'dns': {
        'servers': [
          {'tag': 'dns-direct', 'type': 'udp', 'server': '223.5.5.5'},
          {'tag': 'dns-remote', 'type': 'https', 'server': '1.1.1.1', 'detour': _groupTag}
        ],
        'final': 'dns-remote',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [inbound],
      'outbounds': [...outbounds, {'type': 'direct', 'tag': 'direct'}],
      'route': {
        'auto_detect_interface': true,
        'final': _groupTag,
        'default_domain_resolver': 'dns-direct',
      },
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:29090',
          'default_mode': 'rule',
        },
      },
    };
  }
}
