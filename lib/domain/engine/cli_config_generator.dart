import '../models/enums.dart';
import '../models/switch_node_instance.dart';

/// Generates vendor-neutral CLI reference configuration summaries for switches.
class CliConfigGenerator {
  const CliConfigGenerator._();

  static String generate(SwitchNodeInstance sw) {
    final buf = StringBuffer();
    buf.writeln('! Vendor-Neutral Reference Config: ${sw.userLabel}');
    buf.writeln('! Bridge MAC: ${sw.macAddress}  (BID: ${sw.bridgeIdHex})');
    if (sw.managementIp != null && sw.managementIp!.isNotEmpty) {
      buf.writeln('management ip ${sw.managementIp}');
    }
    buf.writeln(
      'spanning-tree mode ${sw.stpMode.name}  ! priority ${sw.stpPriority}${sw.isRootBridge ? " (ROOT BRIDGE)" : ""}',
    );
    buf.writeln('!');

    final sortedVlans = sw.vlanConfigs.keys.toList()..sort();
    for (final vId in sortedVlans) {
      final cfg = sw.vlanConfigs[vId]!;
      buf.writeln('vlan $vId  ! ${cfg.vlanName}');
      if (sw.supportsIgmpSnooping) {
        buf.writeln(
          '  ip igmp snooping ${cfg.igmpSnoopingEnabled ? "enable" : "disable"} (${cfg.igmpQuerierVersion.label})',
        );
      }
      if (sw.supportsIgmpQuerier && cfg.igmpQuerierEnabled) {
        buf.writeln(
          '  ip igmp snooping querier enable${sw.activeQuerierVlans.contains(vId) ? "  ! ACTIVE QUERIER" : ""}',
        );
      }
    }
    buf.writeln('!');

    for (final port in sw.ports) {
      buf.writeln('interface ${port.displayName}  ! ${port.maxSpeed.label}');
      if (port.portMode == SwitchPortMode.access) {
        buf.writeln('  switchport mode access');
        buf.writeln('  switchport access vlan ${port.nativeVlan}');
      } else {
        final allowed = (port.allowedVlans.toList()..sort()).join(',');
        buf.writeln('  switchport mode trunk');
        buf.writeln('  switchport trunk native vlan ${port.nativeVlan}');
        buf.writeln('  switchport trunk allowed vlan $allowed');
      }
      if (port.poeCapable) {
        buf.writeln('  power inline ${port.poeEnabled ? "auto" : "never"}');
      }
    }
    return buf.toString();
  }
}
