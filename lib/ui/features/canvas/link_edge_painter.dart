import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../domain/models/endpoint_node_instance.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/network_link_edge.dart';
import '../../../domain/models/switch_node_instance.dart';
import '../../theme/app_theme.dart';
import 'endpoint_node_widget.dart';
import 'switch_node_widget.dart';

/// Geometry metadata for an edge so both [LinkEdgePainter] and hit-testing share exact paths.
class LinkGeometry {
  const LinkGeometry({
    required this.link,
    required this.start,
    required this.end,
    required this.control,
  });

  final NetworkLinkEdge link;
  final Offset start;
  final Offset end;
  final Offset control;

  Offset pointAt(double t) {
    final mt = 1 - t;
    return Offset(
      mt * mt * start.dx + 2 * mt * t * control.dx + t * t * end.dx,
      mt * mt * start.dy + 2 * mt * t * control.dy + t * t * end.dy,
    );
  }

  Offset tangentAt(double t) {
    final dx =
        2 * (1 - t) * (control.dx - start.dx) + 2 * t * (end.dx - control.dx);
    final dy =
        2 * (1 - t) * (control.dy - start.dy) + 2 * t * (end.dy - control.dy);
    return Offset(dx, dy);
  }
}

/// Computes curve geometries for all topology links, offsetting parallel cables.
List<LinkGeometry> computeLinkGeometries({
  required List<SwitchNodeInstance> switches,
  required List<EndpointNodeInstance> endpoints,
  required List<NetworkLinkEdge> links,
}) {
  final centers = <String, Offset>{};
  for (final sw in switches) {
    centers[sw.id] = Offset(
      sw.dx + kSwitchCardWidth / 2,
      sw.dy + kSwitchCardMinHeight / 2,
    );
  }
  for (final ep in endpoints) {
    centers[ep.id] = Offset(
      ep.dx + kEndpointCardWidth / 2,
      ep.dy + kEndpointCardMinHeight / 2,
    );
  }

  // Group parallel links between the same unordered node pair.
  final grouped = <String, List<NetworkLinkEdge>>{};
  for (final link in links) {
    final pair = ([link.sourceNodeId, link.targetNodeId]..sort()).join('::');
    grouped.putIfAbsent(pair, () => []).add(link);
  }

  final geometries = <LinkGeometry>[];
  for (final entry in grouped.entries) {
    final group = entry.value;
    for (var idx = 0; idx < group.length; idx++) {
      final link = group[idx];
      final p1 = centers[link.sourceNodeId];
      final p2 = centers[link.targetNodeId];
      if (p1 == null || p2 == null) continue;

      if (link.sourceNodeId == link.targetNodeId) {
        // Self-loop arc above the switch card
        geometries.add(
          LinkGeometry(
            link: link,
            start: p1 + const Offset(-30, -50),
            end: p1 + const Offset(30, -50),
            control: p1 + Offset(0, -140 - (idx * 25)),
          ),
        );
        continue;
      }

      final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
      final delta = p2 - p1;
      final len = delta.distance;
      Offset control = mid;
      if (group.length > 1 && len > 1) {
        final normal = Offset(-delta.dy / len, delta.dx / len);
        final offsetFactor = (idx - (group.length - 1) / 2) * 44.0;
        control = mid + normal * offsetFactor;
      }
      geometries.add(
        LinkGeometry(link: link, start: p1, end: p2, control: control),
      );
    }
  }
  return geometries;
}

/// CustomPainter rendering topology links, STP directional arrows, BLK badges,
/// VLAN highlight paths, and speed/load warnings.
class LinkEdgePainter extends CustomPainter {
  LinkEdgePainter({
    required this.geometries,
    required this.selectedLinkId,
    required this.highlightedVlanId,
    required this.isDark,
  });

  final List<LinkGeometry> geometries;
  final String? selectedLinkId;
  final int? highlightedVlanId;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    for (final geom in geometries) {
      final link = geom.link;
      final isSelected = link.id == selectedLinkId;

      final isBlocked = link.stpState == LinkStpState.blocking;
      final isUnprotectedLoop = link.stpState == LinkStpState.loopUnprotected;
      final isVlanHighlighted = highlightedVlanId != null &&
          link.activeVlans.contains(highlightedVlanId);
      final isVlanPruned = highlightedVlanId != null &&
          link.prunedVlans.contains(highlightedVlanId);

      Color lineColor;
      double strokeWidth = isSelected ? 3.4 : 2.3;
      bool dashed = false;

      if (isUnprotectedLoop) {
        lineColor = AppTheme.error;
        strokeWidth = 3.2;
      } else if (isBlocked) {
        lineColor = AppTheme.error;
        dashed = true;
      } else if (highlightedVlanId != null) {
        if (isVlanPruned) {
          lineColor = AppTheme.error;
          strokeWidth = 3.0;
        } else if (isVlanHighlighted) {
          lineColor = AppTheme.success;
          strokeWidth = 3.2;
        } else {
          lineColor = AppTheme.textMuted.withValues(alpha: 0.22);
          strokeWidth = 1.5;
        }
      } else if (link.hasVlanMismatch || link.utilizationPercent > 95.0) {
        lineColor = AppTheme.error;
      } else if (link.hasSpeedStepDown || link.utilizationPercent > 75.0) {
        lineColor = AppTheme.warning;
      } else if (link.stpState == LinkStpState.forwarding) {
        lineColor = AppTheme.success;
      } else {
        lineColor = AppTheme.accent;
      }

      if (isSelected) {
        final glowPaint = Paint()
          ..color = AppTheme.accent.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + 5.0;
        _drawCurve(canvas, geom, glowPaint, dashed: false);
      }

      final paint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      _drawCurve(canvas, geom, paint, dashed: dashed);

      // Draw directional arrow away from Root Bridge on forwarding links.
      if (link.stpState == LinkStpState.forwarding &&
          (highlightedVlanId == null || isVlanHighlighted)) {
        _drawDirectionArrow(canvas, geom, lineColor);
      }

      // Draw mid-link badge (BLK (STP), LOOP!, PRUNED, Speed/Load).
      _drawLinkPill(canvas, geom, lineColor, isBlocked, isUnprotectedLoop, isVlanPruned);
    }
  }

  void _drawCurve(
    Canvas canvas,
    LinkGeometry geom,
    Paint paint, {
    required bool dashed,
  }) {
    final path = Path()
      ..moveTo(geom.start.dx, geom.start.dy)
      ..quadraticBezierTo(
        geom.control.dx,
        geom.control.dy,
        geom.end.dx,
        geom.end.dy,
      );

    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }

    // Dash along sampled metrics.
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dashLen = 8.0;
      const gapLen = 6.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLen, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLen;
      }
    }
  }

  void _drawDirectionArrow(Canvas canvas, LinkGeometry geom, Color color) {
    final t = geom.link.directionFromRootSourceToTarget ? 0.62 : 0.38;
    final pos = geom.pointAt(t);
    var tangent = geom.tangentAt(t);
    if (!geom.link.directionFromRootSourceToTarget) {
      tangent = -tangent;
    }
    if (tangent.distance < 0.001) return;
    final angle = math.atan2(tangent.dy, tangent.dx);

    const arrowSize = 8.5;
    final path = Path()
      ..moveTo(pos.dx, pos.dy)
      ..lineTo(
        pos.dx - arrowSize * math.cos(angle - 0.5),
        pos.dy - arrowSize * math.sin(angle - 0.5),
      )
      ..lineTo(
        pos.dx - arrowSize * math.cos(angle + 0.5),
        pos.dy - arrowSize * math.sin(angle + 0.5),
      )
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  void _drawLinkPill(
    Canvas canvas,
    LinkGeometry geom,
    Color color,
    bool isBlocked,
    bool isUnprotectedLoop,
    bool isVlanPruned,
  ) {
    final link = geom.link;

    // Position BLK pill closer to the blocked switch end.
    double t = 0.5;
    String label;
    if (isUnprotectedLoop) {
      label = 'LOOP!';
    } else if (isBlocked) {
      t = (link.blockedAtNodeId == link.sourceNodeId) ? 0.28 : 0.72;
      label = 'BLK (STP) P${link.blockedAtPortNumber ?? ""}';
    } else if (isVlanPruned) {
      label = 'VLAN $highlightedVlanId PRUNED';
    } else if (link.hasVlanMismatch) {
      label = 'VLAN MISMATCH';
    } else if (link.hasSpeedStepDown) {
      label = '${link.negotiatedSpeed.label} STEP-DOWN';
    } else if (highlightedVlanId != null &&
        !link.activeVlans.contains(highlightedVlanId)) {
      return; // Dimmed unrelated links stay uncluttered
    } else {
      final loadStr = link.estimatedLoadMbps >= 0.1
          ? ' • ${link.estimatedLoadMbps.toStringAsFixed(1)}M'
          : '';
      label = 'P${link.sourcePortNumber}↔P${link.targetPortNumber} (${link.negotiatedSpeed.label}$loadStr)';
    }

    final center = geom.pointAt(t);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: (isBlocked || isUnprotectedLoop || isVlanPruned || link.hasVlanMismatch)
              ? AppTheme.error
              : (link.hasSpeedStepDown ? AppTheme.warning : AppTheme.textPrimary),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final rect = Rect.fromCenter(
      center: center,
      width: tp.width + 10,
      height: tp.height + 5,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    canvas.drawRRect(
      rrect,
      Paint()..color = AppTheme.surfaceElevated,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(
      canvas,
      Offset(rect.left + 5, rect.top + 2.5),
    );
  }

  @override
  bool shouldRepaint(covariant LinkEdgePainter oldDelegate) {
    return oldDelegate.isDark != isDark ||
        oldDelegate.selectedLinkId != selectedLinkId ||
        oldDelegate.highlightedVlanId != highlightedVlanId ||
        oldDelegate.geometries != geometries;
  }
}

/// Subtle grid background painter for the topology canvas.
class CanvasGridPainter extends CustomPainter {
  CanvasGridPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.border.withValues(alpha: isDark ? 0.5 : 0.7)
      ..strokeWidth = 1.0;

    const spacing = 40.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CanvasGridPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
