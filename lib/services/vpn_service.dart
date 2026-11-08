import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/node.dart';

class VpnService {
  Process? _singBoxProcess;
  static const _groupTag = 'proxy';

  // 直接调用 exe 启动 sing-box，绕过插件的服务模式以触发防火墙提示
  Future<void> applyConfigAndStart(List<VpnNode> nodes, {bool useTun = false}) async {
    // 1. 生成配置
    final configMap = _buildFullConfigMap(nodes, useTun: useTun);
    final configString = const JsonEncoder.withIndent('  ').convert(configMap);

    // 2. 写入本地
    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
    
    final configFile = File('$exeDir/generated_config.json');
    await configFile.writeAsString(configString);

    // 3. 找到 sing_box.exe 的路径
    final singBoxExePath = '$exeDir/data/flutter_assets/packages/flutter_sing_box/assets/windows/amd64/sing_box.exe';
    if (!File(singBoxExePath).existsSync()) {
      throw Exception('找不到内核文件: $singBoxExePath');
    }

    // 4. 如果之前有进程，先杀掉
    if (_singBoxProcess != null) {
      _singBoxProcess!.kill();
      _singBoxProcess = null;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 5. 启动进程
    debugPrint('正在启动 sing-box: $singBoxExePath');
    _singBoxProcess = await Process.start(
      singBoxExePath,
      ['run', '-c', configFile.path],
      workingDirectory: exeDir,
      mode: ProcessStartMode.detached, // 独立运行，不阻塞 Dart
    );

    // 等待 29090 端口就绪
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        await http.get(Uri.parse('http://127.0.0.1:29090')).timeout(const Duration(seconds: 1));
        debugPrint('sing-box 启动成功，29090 端口已就绪');
        break; // 端口通了，跳出循环
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
    final inbound = {
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': '127.0.0.1',
      'listen_port': 22890, // 修改端口
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
          'external_controller': '127.0.0.1:29090', // 修改端口
          'default_mode': 'rule',
        },
      },
    };
  }
}
