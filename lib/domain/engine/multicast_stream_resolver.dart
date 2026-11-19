import '../models/endpoint_template.dart';
import '../models/enums.dart';

/// Concrete resolved multicast stream derived from an endpoint traffic requirement.
class ResolvedMulticastStream {
  const ResolvedMulticastStream({
    required this.multicastIp,
    required this.vlanId,
    required this.protocol,
    this.sacnUniverse,
    required this.bandwidthMbps,
  });

  final String multicastIp;
  final int vlanId;
  final TrafficProtocol protocol;
  final int? sacnUniverse;
  final double bandwidthMbps;

  String get displayLabel => sacnUniverse != null
      ? 'U$sacnUniverse ($multicastIp)'
      : '${protocol.label} ($multicastIp)';
}

/// Parses sACN universe specs and optional multicast IPv4 group ranges
/// into deterministic [ResolvedMulticastStream] lists.
class MulticastStreamResolver {
  MulticastStreamResolver._();

  static const double defaultSacnMbpsPerUniverse = 0.25;
  static const int minSacnUniverse = 1;
  static const int maxSacnUniverse = 63999;
  static const int maxExpandedStreams = 512;

  /// Converts an ANSI E1.31 sACN universe number (`1..63999`) to its multicast IP.
  static String sacnUniverseToIp(int universe) {
    final highByte = (universe >> 8) & 0xFF;
    final lowByte = universe & 0xFF;
    return '239.255.$highByte.$lowByte';
  }

  /// Calculates default sACN bandwidth at 0.25 Mbps per universe.
  static double sacnBandwidthMbps(int universeCount) =>
      universeCount * defaultSacnMbpsPerUniverse;

  /// Formats a sorted list of universes into compact range notation (e.g. `1-4, 8`).
  static String formatUniverseRanges(List<int> universes) {
    if (universes.isEmpty) return '';
    final sorted = universes.toSet().toList()..sort();
    final parts = <String>[];
    var start = sorted.first;
    var prev = sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      final curr = sorted[i];
      if (curr == prev + 1) {
        prev = curr;
      } else {
        parts.add(start == prev ? '$start' : '$start-$prev');
        start = curr;
        prev = curr;
      }
    }
    parts.add(start == prev ? '$start' : '$start-$prev');
    return parts.join(', ');
  }

  /// Parses universe numbers and ranges such as `"1-8, 20"`.
  static ({List<int> universes, String? error}) parseSacnUniverses(
    String? spec,
  ) {
    final trimmed = spec?.trim() ?? '';
    if (trimmed.isEmpty) {
      return (universes: const [], error: null);
    }

    final result = <int>{};
    final tokens = trimmed.split(',');
    for (final rawToken in tokens) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;

      if (token.contains('-')) {
        final bounds = token.split('-');
        if (bounds.length != 2) {
          return (
            universes: const [],
            error: 'Invalid sACN universe range "$token" (expected e.g. 1-8).',
          );
        }
        final start = int.tryParse(bounds[0].trim());
        final end = int.tryParse(bounds[1].trim());
        if (start == null || end == null) {
          return (
            universes: const [],
            error: 'Non-numeric universe range "$token".',
          );
        }
        if (start < minSacnUniverse ||
            start > maxSacnUniverse ||
            end < minSacnUniverse ||
            end > maxSacnUniverse) {
          return (
            universes: const [],
            error: 'sACN universes must be between 1 and 63999.',
          );
        }
        if (start > end) {
          return (
            universes: const [],
            error: 'Reverse universe range "$token" ($start > $end).',
          );
        }
        if (end - start + 1 > maxExpandedStreams ||
            result.length + (end - start + 1) > maxExpandedStreams) {
          return (
            universes: const [],
            error: 'Expanded universe count exceeds $maxExpandedStreams limit.',
          );
        }
        for (var u = start; u <= end; u++) {
          result.add(u);
        }
      } else {
        final u = int.tryParse(token);
        if (u == null) {
          return (
            universes: const [],
            error: 'Invalid sACN universe "$token".',
          );
        }
        if (u < minSacnUniverse || u > maxSacnUniverse) {
          return (
            universes: const [],
            error: 'sACN universe $u must be between 1 and 63999.',
          );
        }
        if (result.length >= maxExpandedStreams && !result.contains(u)) {
          return (
            universes: const [],
            error: 'Expanded universe count exceeds $maxExpandedStreams limit.',
          );
        }
        result.add(u);
      }
    }

    final sorted = result.toList()..sort();
    return (universes: List<int>.unmodifiable(sorted), error: null);
  }

  /// Parses IPv4 multicast addresses and last-octet ranges (e.g. `"239.69.0.1-4"`).
  static ({List<String> ips, String? error}) parseMulticastGroups(
    String? spec,
  ) {
    final trimmed = spec?.trim() ?? '';
    if (trimmed.isEmpty) {
      return (ips: const [], error: null);
    }

    final result = <String>{};
    final tokens = trimmed.split(',');
    for (final rawToken in tokens) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;

      if (token.contains('-')) {
        final parts = token.split('-');
        if (parts.length != 2) {
          return (
            ips: const [],
            error: 'Invalid multicast range "$token" (expected e.g. 239.69.0.1-4).',
          );
        }
        final startIp = _parseIpv4Octets(parts[0].trim());
        if (startIp == null || !_isMulticastFirstOctet(startIp[0])) {
          return (
            ips: const [],
            error: 'Invalid multicast start address in "$token" (expected 224.0.0.0–239.255.255.255).',
          );
        }

        final rhs = parts[1].trim();
        int endLastOctet;
        if (rhs.contains('.')) {
          final endIp = _parseIpv4Octets(rhs);
          if (endIp == null || !_isMulticastFirstOctet(endIp[0])) {
            return (
              ips: const [],
              error: 'Invalid multicast end address in "$token".',
            );
          }
          if (endIp[0] != startIp[0] ||
              endIp[1] != startIp[1] ||
              endIp[2] != startIp[2]) {
            return (
              ips: const [],
              error: 'Multicast IP range "$token" must share its first three octets.',
            );
          }
          endLastOctet = endIp[3];
        } else {
          final parsedOctet = int.tryParse(rhs);
          if (parsedOctet == null || parsedOctet < 0 || parsedOctet > 255) {
            return (
              ips: const [],
              error: 'Invalid last-octet range bound "$rhs" in "$token".',
            );
          }
          endLastOctet = parsedOctet;
        }

        if (startIp[3] > endLastOctet) {
          return (
            ips: const [],
            error: 'Reverse multicast IP range "$token".',
          );
        }
        final count = endLastOctet - startIp[3] + 1;
        if (result.length + count > maxExpandedStreams) {
          return (
            ips: const [],
            error: 'Expanded multicast stream count exceeds $maxExpandedStreams limit.',
          );
        }
        for (var last = startIp[3]; last <= endLastOctet; last++) {
          result.add('${startIp[0]}.${startIp[1]}.${startIp[2]}.$last');
        }
      } else {
        final octets = _parseIpv4Octets(token);
        if (octets == null || !_isMulticastFirstOctet(octets[0])) {
          return (
            ips: const [],
            error: 'Invalid multicast IP "$token" (expected 224.0.0.0–239.255.255.255).',
          );
        }
        if (result.length >= maxExpandedStreams && !result.contains(token)) {
          return (
            ips: const [],
            error: 'Expanded multicast stream count exceeds $maxExpandedStreams limit.',
          );
        }
        result.add('${octets[0]}.${octets[1]}.${octets[2]}.${octets[3]}');
      }
    }

    return (ips: List<String>.unmodifiable(result), error: null);
  }

  /// Validates stream syntax for [flow] and returns an error string if malformed.
  static String? validateFlowSpec(TrafficRequirement flow) {
    if (flow.deliveryType != DeliveryType.multicast) return null;
    if (flow.protocol == TrafficProtocol.sacn) {
      return parseSacnUniverses(flow.sacnUniverseSpec).error;
    }
    if (flow.multicastGroupSpec != null &&
        flow.multicastGroupSpec!.trim().isNotEmpty) {
      return parseMulticastGroups(flow.multicastGroupSpec).error;
    }
    return null;
  }

  /// Resolves concrete multicast stream groups declared by [flow].
  static List<ResolvedMulticastStream> resolveFlowStreams(
    TrafficRequirement flow, {
    int? effectiveVlanId,
  }) {
    if (flow.deliveryType != DeliveryType.multicast) {
      return const [];
    }

    final vlan = effectiveVlanId ?? flow.defaultVlanId;

    if (flow.protocol == TrafficProtocol.sacn) {
      final parsed = parseSacnUniverses(flow.sacnUniverseSpec);
      if (parsed.error != null || parsed.universes.isEmpty) {
        return const [];
      }
      final perStreamBw = flow.estimatedBandwidthMbps > 0
          ? flow.estimatedBandwidthMbps / parsed.universes.length
          : defaultSacnMbpsPerUniverse;
      return [
        for (final u in parsed.universes)
          ResolvedMulticastStream(
            multicastIp: sacnUniverseToIp(u),
            vlanId: vlan,
            protocol: flow.protocol,
            sacnUniverse: u,
            bandwidthMbps: perStreamBw,
          ),
      ];
    }

    if (flow.multicastGroupSpec != null &&
        flow.multicastGroupSpec!.trim().isNotEmpty) {
      final parsed = parseMulticastGroups(flow.multicastGroupSpec);
      if (parsed.error != null || parsed.ips.isEmpty) {
        return const [];
      }
      final perStreamBw = flow.estimatedBandwidthMbps > 0
          ? flow.estimatedBandwidthMbps / parsed.ips.length
          : 0.0;
      return [
        for (final ip in parsed.ips)
          ResolvedMulticastStream(
            multicastIp: ip,
            vlanId: vlan,
            protocol: flow.protocol,
            bandwidthMbps: perStreamBw,
          ),
      ];
    }

    return const [];
  }

  static List<int>? _parseIpv4Octets(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final p in parts) {
      final val = int.tryParse(p.trim());
      if (val == null || val < 0 || val > 255) return null;
      octets.add(val);
    }
    return octets;
  }

  static bool _isMulticastFirstOctet(int octet) => octet >= 224 && octet <= 239;
}
