class VpnNode {
  final String id;
  final String country;
  final String countryName;
  final String proto;
  final String type; // residential / datacenter / mobile
  final String source;
  final String trust;
  final Map<String, dynamic> outbound;

  VpnNode({
    required this.id,
    required this.country,
    required this.countryName,
    required this.proto,
    required this.type,
    required this.source,
    required this.trust,
    required this.outbound,
  });

  factory VpnNode.fromJson(Map<String, dynamic> j) => VpnNode(
        id: j['id'] as String,
        country: j['country'] as String,
        countryName: j['country_name'] as String,
        proto: j['proto'] as String,
        type: j['type'] as String? ?? 'unknown',
        source: j['source'] as String? ?? 'unknown',
        trust: j['trust'] as String? ?? 'unknown',
        outbound: Map<String, dynamic>.from(j['outbound'] as Map),
      );

  String get flagUrl =>
      'https://flags.etoj.run.place/flags/4x3/${country.toLowerCase()}.svg';

  String get typeLabel => switch (type) {
        'residential' => '住宅',
        'datacenter' => '机房',
        'mobile' => '移动',
        _ => '未知',
      };
}