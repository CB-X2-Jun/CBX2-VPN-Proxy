import 'package:flutter/material.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'package:mmkv/mmkv.dart';
import 'models/node.dart';
import 'services/api_service.dart';
import 'services/vpn_service.dart';
import 'services/latency_service.dart';
import 'theme.dart';
import 'widgets/node_tile.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    try {
      File('cbx2_crash.log').writeAsStringSync(
        'FlutterError: ${details.exceptionAsString()}\n${details.stack}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  };

  try {
    await MMKV.initialize();
    await FlutterSingBox().init();
  } catch (e) {
    try {
      File('cbx2_crash.log').writeAsStringSync('CORE_INIT_FAILED: $e\n',
          mode: FileMode.append);
    } catch (_) {}
  }

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

  List<VpnNode> _allNodes = [];
  List<VpnNode> _displayNodes = [];
  List<String> _availableCountries = [];
  String _selectedCountry = '全部';

  final Map<String, int?> _delays = {};
  VpnNode? _connectedNode;
  String _status = '未连接';
  String? _exitInfo;
  bool _loading = true;
  bool _testing = false;
  bool _configApplied = false;
  bool _isSortedByDelay = false;

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

      final countries = nodes.map((n) => n.countryName).toSet().toList();

      setState(() {
        _allNodes = nodes;
        _availableCountries = ['全部', ...countries];
        _selectedForTest
          ..clear()
          ..addAll(nodes.map((n) => n.id));
        _loading = false;
      });
      _filterAndSortNodes();
    } catch (e) {
      setState(() {
        _status = '拉取节点失败: $e';
        _loading = false;
      });
    }
  }

  void _filterAndSortNodes() {
    List<VpnNode> result = _allNodes.where((n) {
      if (_selectedCountry == '全部') return true;
      return n.countryName == _selectedCountry;
    }).toList();

    if (_isSortedByDelay) {
      result.sort((a, b) {
        final da = _delays[a.id];
        final db = _delays[b.id];
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    } else {
      result.sort((a, b) {
        final cmp = a.countryName.compareTo(b.countryName);
        if (cmp != 0) return cmp;
        return _allNodes.indexOf(a).compareTo(_allNodes.indexOf(b));
      });
    }

    if (mounted) setState(() => _displayNodes = result);
  }

  Future<void> _ensureConfig() async {
    if (_configApplied) return;
    await _vpn.applyConfigAndStart(_allNodes);
    _configApplied = true;
  }

  Future<void> _batchTest() async {
    if (_displayNodes.isEmpty) return;
    setState(() {
      _testing = true;
      _delays.clear();
      _isSortedByDelay = false;
      _status = '正在启动核心并测速…';
    });
    try {
      await _ensureConfig();
      
      final selectedNodes = _allNodes.where((n) => _selectedForTest.contains(n.id)).toList();
      for (final node in selectedNodes) {
        final tag = node.outbound['tag'] as String;
        final delay = await _vpn.testDelay(tag);
        if (mounted) {
          setState(() {
            _delays[node.id] = delay ?? 9999;
          });
        }
      }

      setState(() {
        _isSortedByDelay = true;
        _status = '测速完成';
      });
      _filterAndSortNodes();
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

      await _vpn.switchNode(node.outbound['tag'] as String);
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
    await _vpn.stop();
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
                if (!_testing && _availableCountries.length > 1)
                  Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _availableCountries.length,
                      itemBuilder: (context, index) {
                        final country = _availableCountries[index];
                        final isSelected = _selectedCountry == country;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(country),
                            selected: isSelected,
                            onSelected: (val) {
                              setState(() => _selectedCountry = country);
                              _filterAndSortNodes();
                            },
                            selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                            checkmarkColor: Theme.of(context).colorScheme.primary,
                          ),
                        );
                      },
                    ),
                  ),

                if (_exitInfo != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: _exitInfo!.contains('漂移') ? Colors.orange.shade50 : Colors.green.shade50,
                    child: Text(
                      _exitInfo!,
                      style: TextStyle(
                        color: _exitInfo!.contains('漂移') ? Colors.orange.shade800 : Colors.green.shade800,
                      ),
                    ),
                  ),
                  
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _displayNodes.length,
                    itemBuilder: (_, i) {
                      final node = _displayNodes[i];
                      final displayIndex = i + 1;

                      return NodeTile(
                        node: node,
                        displayIndex: displayIndex,
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

                if (_status != '未连接')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: _status.contains('失败') || _status.contains('警告') || _status.contains('不通')
                        ? Colors.red.shade50 
                        : Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      _status,
                      style: TextStyle(
                        color: _status.contains('失败') || _status.contains('警告') || _status.contains('不通')
                            ? Colors.red.shade800 
                            : Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
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
