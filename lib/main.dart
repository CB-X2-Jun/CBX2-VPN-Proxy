import 'package:flutter/material.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'package:provider/provider.dart';
import 'models/node.dart';
import 'services/api_service.dart';
import 'services/vpn_service.dart';
import 'services/latency_service.dart';
import 'theme.dart';
import 'widgets/node_tile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterSingBox().init();
  runApp(const Cbx2App());
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

  List<VpnNode> _nodes = [];
  final Map<String, int?> _delays = {};
  VpnNode? _connectedNode;
  String _status = '未连接';
  String? _exitInfo;
  bool _loading = true;
  bool _testing = false;
  final Set<String> _selectedForTest = {};

  @override
  void initState() {
    super.initState();
    _loadNodes();
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

  Future<void> _batchTest() async {
    if (_nodes.isEmpty) return;
    setState(() {
      _testing = true;
      _delays.clear();
    });

    // 把选中的节点注入一个临时配置并启动，以便 Clash API 能对它们测延迟
    final selected = _nodes.where((n) => _selectedForTest.contains(n.id)).toList();
    if (selected.isEmpty) {
      setState(() => _testing = false);
      return;
    }

    await _vpn.ensureService();

    for (final node in selected) {
      // 逐个节点启动并测延迟（最小可用实现；批量并发需额外处理端口冲突）
      try {
        await _vpn.connect(node);
        // 稍等内核就绪
        await Future.delayed(const Duration(milliseconds: 600));
        final delay = await _latency.testDelay(node.outbound['tag'] as String);
        _delays[node.id] = delay;
        setState(() {});
      } catch (_) {
        _delays[node.id] = null;
      }
    }

    await _vpn.disconnect();

    // 按延迟升序排列，超时/失败的排在末尾
    _nodes.sort((a, b) {
      final da = _delays[a.id];
      final db = _delays[b.id];
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    setState(() {
      _testing = false;
      _status = '测速完成';
    });
  }

  Future<void> _connect(VpnNode node) async {
    setState(() {
      _status = '连接中…';
      _exitInfo = null;
    });
    try {
      await _vpn.connect(node);
      final (ip, country) = await _latency.fetchExitInfo();
      final drift = country.isNotEmpty && country != node.country;
      setState(() {
        _connectedNode = node;
        _status = '已连接';
        _exitInfo =
            '出口 $ip ($country)${drift ? ' ⚠️ 国家漂移' : ''}';
      });
    } catch (e) {
      setState(() => _status = '连接失败: $e');
    }
  }

  Future<void> _disconnect() async {
    await _vpn.disconnect();
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
                        isSelectedForTest:
                            _selectedForTest.contains(node.id),
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
                label: Text(
                  testing ? '测速中…' : '批量检测 ($nodeCount)',
                ),
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