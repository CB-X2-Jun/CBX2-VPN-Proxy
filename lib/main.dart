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
  
  // 多选国家
  Set<String> _selectedCountries = {};

  final Map<String, int?> _delays = {};
  VpnNode? _connectedNode;
  String _status = '未连接';
  String? _exitInfo;
  bool _loading = true;
  
  // 状态控制
  bool _useTun = false;
  bool _isSelectingForTest = false; // 是否处于勾选模式
  bool _testing = false;            // 是否正在测速
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
        _availableCountries = countries;
        _loading = false;
        _selectedCountries.clear(); // 初始为空，代表全部
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
      // 如果为空，说明选中了全部
      if (_selectedCountries.isEmpty) return true;
      return _selectedCountries.contains(n.countryName);
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
    await _vpn.applyConfigAndStart(_allNodes, useTun: _useTun);
    _configApplied = true;
  }

  // 进入勾选模式
  void _enterSelectMode() {
    setState(() {
      _isSelectingForTest = true;
      _isSortedByDelay = false;
      // 默认勾选当前页面显示的所有节点
      _selectedForTest.clear();
      _selectedForTest.addAll(_displayNodes.map((n) => n.id));
    });
  }

  // 退出勾选模式
  void _exitSelectMode() {
    setState(() {
      _isSelectingForTest = false;
    });
  }

  // 全选/反选当前页
  void _toggleSelectAllCurrent() {
    setState(() {
      final currentIds = _displayNodes.map((n) => n.id).toList();
      final isAllSelected = currentIds.every((id) => _selectedForTest.contains(id));
      if (isAllSelected) {
        _selectedForTest.removeAll(currentIds);
      } else {
        _selectedForTest.addAll(currentIds);
      }
    });
  }

  // 真正开始测速
  Future<void> _startBatchTest() async {
    if (_selectedForTest.isEmpty) {
      _exitSelectMode();
      return;
    }
    
    setState(() {
      _isSelectingForTest = false;
      _testing = true;
      _delays.clear();
      _isSortedByDelay = false;
      _status = '正在启动核心并测速…';
    });

    try {
      await _ensureConfig();
      
      // 从选中的节点中找出需要测速的
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
    if (_isSelectingForTest || _testing) return;

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
      _configApplied = false; // 断开后重置
    });
  }

  void _toggleTunMode(bool value) {
    if (_connectedNode != null) {
      _disconnect();
    }
    setState(() {
      _useTun = value;
      _configApplied = false; 
      _status = _useTun ? '已启用 TUN 模式' : '已启用系统代理模式';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CBX2 VPN & Proxy'),
        actions: [
          Row(
            children: [
              const Text('TUN模式', style: TextStyle(fontSize: 13)),
              Switch(
                value: _useTun,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: _testing ? null : _toggleTunMode,
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading || _testing || _isSelectingForTest ? null : _loadNodes,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 国家多选筛选器
                if (!_testing && !_isSelectingForTest)
                  Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: const Text('全部'),
                            selected: _selectedCountries.isEmpty,
                            onSelected: (val) {
                              setState(() => _selectedCountries.clear());
                              _filterAndSortNodes();
                            },
                          ),
                        ),
                        ..._availableCountries.map((country) {
                          final isSelected = _selectedCountries.contains(country);
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(country),
                              selected: isSelected,
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _selectedCountries.add(country);
                                  } else {
                                    _selectedCountries.remove(country);
                                  }
                                });
                                _filterAndSortNodes();
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                if (_exitInfo != null && !_isSelectingForTest)
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
                      return NodeTile(
                        node: node,
                        displayIndex: i + 1,
                        delayMs: _delays[node.id],
                        isConnected: _connectedNode?.id == node.id,
                        isSelectedForTest: _selectedForTest.contains(node.id),
                        testing: _testing,
                        showCheckbox: _isSelectingForTest, // 新增参数
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

                // 状态栏 + 端口显示
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: _status.contains('失败') || _status.contains('警告')
                      ? Colors.red.shade50 
                      : (_status == '未连接' ? Colors.grey.shade100 : Theme.of(context).colorScheme.primaryContainer),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _status,
                        style: TextStyle(
                          color: _status.contains('失败') || _status.contains('警告') ? Colors.red.shade800 : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!_useTun && _status != '未连接')
                        Text(
                          'Mixed端口: 22890',
                          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12),
                        ),
                    ],
                  ),
                ),

                // 底部操作栏
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        if (_isSelectingForTest) ...[
                          // 选择模式下的按钮
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _exitSelectMode,
                              child: const Text('取消'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: _toggleSelectAllCurrent,
                              child: const Text('全选/反选 当前页'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: _selectedForTest.isEmpty ? null : _startBatchTest,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              child: Text('开始测速 (${_selectedForTest.length})'),
                            ),
                          ),
                        ] else ...[
                          // 普通模式下的按钮
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _testing ? null : _enterSelectMode,
                              icon: _testing
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.speed),
                              label: Text(_testing ? '测速中…' : '批量检测'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_connectedNode != null)
                            OutlinedButton(
                              onPressed: _disconnect,
                              child: const Text('断开'),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
