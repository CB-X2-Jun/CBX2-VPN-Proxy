import 'package:flutter/material.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'models/node.dart';
import 'services/api_service.dart';
import 'services/vpn_service.dart';
import 'services/latency_service.dart';
import 'theme.dart';
import 'widgets/node_tile.dart';
import 'dart:io'; // 必须引入

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 捕获 Flutter 框架内的错误并写入文件
  FlutterError.onError = (FlutterErrorDetails details) {
    try {
      File('cbx2_crash.log').writeAsStringSync(
        'FlutterError: ${details.exceptionAsString()}\n${details.stack}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  };

  // 1. 先启动 UI 界面！
  runApp(const Cbx2App());

  // 2. 在后台偷偷初始化，不让 UI 卡住
  FlutterSingBox().init().then((_) {
    try {
      File('cbx2_crash.log').writeAsStringSync(
        'SINGBOX_INIT_SUCCESS\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }).catchError((e) {
    try {
      File('cbx2_crash.log').writeAsStringSync(
        'SINGBOX_INIT_FAILED: $e\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  });
}

class Cbx2App extends StatelessWidget {
  const Cbx2App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CBX2 VPN & Proxy',
      theme: appTheme,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = ApiService();
  final _vpn = VpnService();
  final _latency = LatencyService();
  final _singBox = FlutterSingBox();

  List<VpnNode> _nodes = [];
  final Map<String, int?> _delays = {};
  VpnNode? _connectedNode;
  String _status = '未连接';
  String? _exitInfo;
  bool _loading = true;
  bool _testing = false;
  bool _configApplied = false;
  final Set<String> _selectedForTest = {};

  @override
  void initState() {
    super.initState();
    _singBox.groupStream.listen(_handleGroups);
    _loadNodes();
  }

  /// 订阅 sing-box 分组流，解析 urlTest 回传的延迟
  void _handleGroups(dynamic groups) {
    bool changed = false;
    try {
      for (final g in groups) {
        final items = g.items;
        if (items is! List) continue;
        for (final item in items) {
          final tag = item.tag;
          final delay = item.delay;
          if (tag is String && delay is int) {
            VpnNode? node;
            for (final n in _nodes) {
              if (n.outbound['tag'] == tag) {
                node = n;
                break;
              }
            }
            if (node != null && _delays[node.id] != delay) {
              _delays[node.id] = delay;
              changed = true;
            }
          }
        }
      }
    } catch (_) {
      // 流结构不匹配时静默忽略，避免影响主流程
    }
    if (changed) {
      _nodes.sort((a, b) {
        final da = _delays[a.id];
        final db = _delays[b.id];
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadNodes() async {
    setState(() => _loading = true);
    try {
      final nodes = await _api.fetchNodes();
      setState(() {
        _nodes = nodes;
        _selectedForTest
          ..clear()
          ..addAll(nodes.map((n) => n.id));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _status = '拉取节点失败: $e';
        _loading = false;
      });
    }
  }

  /// 首次操作时把全部节点写成一个 Profile 并启动服务
  Future<void> _ensureConfig() async {
    if (_configApplied) return;
    await _vpn.applyConfig(_nodes);
    _configApplied = true;
  }

  Future<void> _batchTest() async {
    if (_nodes.isEmpty) return;
    setState(() {
      _testing = true;
      _delays.clear();
    });
    try {
      await _ensureConfig();
      await _vpn.startIfNeeded();
      await _vpn.testAll();
      // urlTest 结果通过 groupStream 异步推送，留出收集窗口
      await Future.delayed(const Duration(seconds: 6));
    } catch (e) {
      if (mounted) setState(() => _status = '测速失败: $e');
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _connect(VpnNode node) async {
    setState(() {
      _status = '连接中…';
      _exitInfo = null;
    });
    try {
      await _ensureConfig();
      await _vpn.startIfNeeded();
      await _vpn.selectNode(node);
      await Future.delayed(const Duration(milliseconds: 800));
      final (ip, country) = await _latency.fetchExitInfo();
      final drift = country.isNotEmpty && country != node.country;
      if (!mounted) return;
      setState(() {
        _connectedNode = node;
        _status = '已连接';
        _exitInfo = '出口 $ip ($country)${drift ? ' ⚠️ 国家漂移' : ''}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '连接失败: $e');
    }
  }

  Future<void> _disconnect() async {
    await _vpn.disconnect();
    if (!mounted) return;
    setState(() {
      _connectedNode = null;
      _status = '未连接';
      _exitInfo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CBX2 VPN & Proxy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadNodes,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_exitInfo != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: _exitInfo!.contains('漂移')
                        ? Colors.orange.shade50
                        : Colors.green.shade50,
                    child: Text(
                      _exitInfo!,
                      style: TextStyle(
                        color: _exitInfo!.contains('漂移')
                            ? Colors.orange.shade800
                            : Colors.green.shade800,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _nodes.length,
                    itemBuilder: (_, i) {
                      final node = _nodes[i];
                      return NodeTile(
                        node: node,
                        delayMs: _delays[node.id],
                        isConnected: _connectedNode?.id == node.id,
                        isSelectedForTest: _selectedForTest.contains(node.id),
                        testing: _testing,
                        onTap: () => _connect(node),
                        onToggleTest: (v) {
                          setState(() {
                            if (v) {
                              _selectedForTest.add(node.id);
                            } else {
                              _selectedForTest.remove(node.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                _BottomBar(
                  status: _status,
                  testing: _testing,
                  connected: _connectedNode != null,
                  onTest: _batchTest,
                  onDisconnect: _disconnect,
                  nodeCount: _selectedForTest.length,
                ),
              ],
            ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final String status;
  final bool testing;
  final bool connected;
  final VoidCallback onTest;
  final VoidCallback onDisconnect;
  final int nodeCount;

  const _BottomBar({
    required this.status,
    required this.testing,
    required this.connected,
    required this.onTest,
    required this.onDisconnect,
    required this.nodeCount,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: testing || nodeCount == 0 ? null : onTest,
                icon: testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.speed),
                label: Text(testing ? '测速中…' : '批量检测 ($nodeCount)'),
              ),
            ),
            const SizedBox(width: 8),
            if (connected)
              OutlinedButton(
                onPressed: onDisconnect,
                child: const Text('断开'),
              ),
          ],
        ),
      ),
    );
  }
}
