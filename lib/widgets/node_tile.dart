import 'package:flutter/material.dart';
import '../models/node.dart';

class NodeTile extends StatelessWidget {
  final VpnNode node;
  final int? delayMs;
  final bool isConnected;
  final bool isSelectedForTest;
  final bool testing;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleTest;

  const NodeTile({
    super.key,
    required this.node,
    required this.delayMs,
    required this.isConnected,
    required this.isSelectedForTest,
    required this.testing,
    required this.onTap,
    required this.onToggleTest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delayText = delayMs == null
        ? (testing ? '…' : '—')
        : delayMs! >= 9999
            ? '超时'
            : '${delayMs}ms';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (testing)
                Checkbox(
                  value: isSelectedForTest,
                  onChanged: (v) => onToggleTest(v ?? false),
                  activeColor: theme.colorScheme.primary,
                ),
              _Flag(iso: node.country),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${node.countryName} #${node.id.hashCode % 100}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          node.typeLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.55),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          delayText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: delayMs == null
                                ? Colors.grey
                                : delayMs! < 200
                                    ? Colors.green
                                    : delayMs! < 500
                                        ? Colors.orange
                                        : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ProtoBadge(proto: node.proto),
              if (isConnected) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_circle,
                    size: 18, color: theme.colorScheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  final String iso;

  const _Flag({required this.iso});

  @override
  Widget build(BuildContext context) {
    final url =
        'https://flags.etoj.run.place/flags/4x3/${iso.toLowerCase()}.svg';
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.network(
        url,
        width: 28,
        height: 21,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 28,
          height: 21,
          color: Colors.grey.shade200,
          child: const Icon(Icons.public, size: 14, color: Colors.grey),
        ),
      ),
    );
  }
}

class _ProtoBadge extends StatelessWidget {
  final String proto;

  const _ProtoBadge({required this.proto});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        proto.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}