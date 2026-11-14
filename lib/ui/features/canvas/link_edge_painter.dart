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

/// Estimates rendered switch card height from its role pills, PoE bar, and port strip.
double estimateSwitchCardHeight(SwitchNodeInstance sw) {
  var pillCount = sw.portSummaryPills.length;
  if (sw.isRootBridge) pillCount++;
  if (sw.activeQuerierVlans.isNotEmpty) pillCount++;
  if (!sw.isStpActive) pillCount++;
  final pillHeight = pillCount > 3 ? 46.0 : 22.0;

  final poeHeight = sw.poeBudgetWatts > 0 ? 31.0 : 0.0;
  final portRows = sw.ports.isEmpty ? 1 : ((sw.ports.length + 9) ~/ 10);
  final portHeight = portRows * 19.0 + math.max(0, portRows - 1) * 3.0;

  // Header (~31) + padding (18) + pills + gap (6) + MAC row (16) + gap (8) + ports
  return math.max(
    kSwitchCardMinHeight,
    79.0 + pillHeight + poeHeight + portHeight,
  );
}

/// Estimates rendered endpoint card height from its badges and active traffic flows.
double estimateEndpointCardHeight(EndpointNodeInstance ep) {
  final portCount = ep.effectivePorts.length;
  final totalPoe = ep.totalPoeDrawWatts;
  final extraBadges =
      (totalPoe > 0 ? 1 : 0) + (ep.ipAddress?.isNotEmpty == true ? 1 : 0);
  final badgeRows = ((portCount + extraBadges) / 2).ceil().clamp(1, 5);
  final badgeHeight = badgeRows * 20.0 + math.max(0, badgeRows - 1) * 4.0;

  var flowsHeight = 0.0;
  if (ep.activeTrafficFlows.isNotEmpty) {
    final flowRows = (ep.activeTrafficFlows.length + 1) ~/ 2;
    flowsHeight = 6.0 + flowRows * 20.0 + math.max(0, flowRows - 1) * 4.0;
  }

  return math.max(
    kEndpointCardMinHeight,
    54.0 + badgeHeight + flowsHeight,
  );
}

/// Computes the exact point on [rect]'s perimeter along the ray from [rect.center] to [target].
Offset _intersectRectPerimeter(Rect rect, Offset target) {
  final center = rect.center;
  final dx = target.dx - center.dx;
  final dy = target.dy - center.dy;
  if (dx.abs() < 0.001 && dy.abs() < 0.001) {
    return center;
  }
  final halfW = rect.width / 2;
  final halfH = rect.height / 2;
  final scaleX = dx.abs() > 0.0001 ? halfW / dx.abs() : double.infinity;
  final scaleY = dy.abs() > 0.0001 ? halfH / dy.abs() : double.infinity;
  final t = math.min(scaleX, scaleY);
  return Offset(center.dx + dx * t, center.dy + dy * t);
}

/// Computes curve geometries anchored to node card perimeters, offsetting parallel cables.
List<LinkGeometry> computeLinkGeometries({
  required List<SwitchNodeInstance> switches,
  required List<EndpointNodeInstance> endpoints,
  required List<NetworkLinkEdge> links,
}) {
  final nodeRects = <String, Rect>{};
  for (final sw in switches) {
    nodeRects[sw.id] = Rect.fromLTWH(
      sw.dx,
      sw.dy,
      kSwitchCardWidth,
      estimateSwitchCardHeight(sw),
    );
  }
  for (final ep in endpoints) {
    nodeRects[ep.id] = Rect.fromLTWH(
      ep.dx,
      ep.dy,
      kEndpointCardWidth,
      estimateEndpointCardHeight(ep),
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
      final rectA = nodeRects[link.sourceNodeId];
      final rectB = nodeRects[link.targetNodeId];
      if (rectA == null || rectB == null) continue;

      if (link.sourceNodeId == link.targetNodeId) {
        // Self-loop arc above the switch card
        final topCenter = Offset(rectA.center.dx, rectA.top);
        geometries.add(
          LinkGeometry(
            link: link,
            start: topCenter + const Offset(-28, 0),
            end: topCenter + const Offset(28, 0),
            control: topCenter + Offset(0, -90.0 - (idx * 25.0)),
          ),
        );
        continue;
      }

      final centerA = rectA.center;
      final centerB = rectB.center;
      final centerDelta = centerB - centerA;
      final len = centerDelta.distance;
      final normal = len > 1.0
          ? Offset(-centerDelta.dy / len, centerDelta.dx / len)
          : const Offset(0, 1);
      final offsetFactor =
          group.length > 1 ? (idx - (group.length - 1) / 2) * 44.0 : 0.0;

      final start = _intersectRectPerimeter(
        rectA,
        centerB + normal * offsetFactor,
      );
      final end = _intersectRectPerimeter(
        rectB,
        centerA + normal * offsetFactor,
      );
      final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      final control = mid + normal * offsetFactor;

      geometries.add(
        LinkGeometry(link: link, start: start, end: end, control: control),
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
    required this.isTrunkFilterActive,
    this.isStreamTraceActive = false,
    required this.isDark,
  });

  final List<LinkGeometry> geometries;
  final String? selectedLinkId;
  final int? highlightedVlanId;
  final bool isTrunkFilterActive;
  final bool isStreamTraceActive;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final isFilterActive =
        isTrunkFilterActive || highlightedVlanId != null || isStreamTraceActive;

    for (final geom in geometries) {
      final link = geom.link;
      final isSelected = link.id == selectedLinkId;

      final isBlocked = link.stpState == LinkStpState.blocking;
      final isUnprotectedLoop = link.stpState == LinkStpState.loopUnprotected;
      final isVlanHighlighted = highlightedVlanId != null &&
          link.activeVlans.contains(highlightedVlanId) &&
          !link.hasVlanMismatch &&
          !link.prunedVlans.contains(highlightedVlanId);
      final isVlanPruned = highlightedVlanId != null &&
          link.prunedVlans.contains(highlightedVlanId);
      final traceState = link.streamTraceState;
      final matchesActiveFilter = isStreamTraceActive
          ? (traceState != LinkStreamTraceState.none)
          : (isTrunkFilterActive ? link.isValidTrunk : isVlanHighlighted);

      Color lineColor;
      double strokeWidth = isSelected ? 3.4 : 2.3;
      bool dashed = false;

      if (isStreamTraceActive) {
        switch (traceState) {
          case LinkStreamTraceState.delivered:
            lineColor = AppTheme.success;
            strokeWidth = isSelected ? 3.8 : 3.2;
          case LinkStreamTraceState.flooded:
            lineColor = AppTheme.warning;
            strokeWidth = isSelected ? 3.8 : 3.2;
          case LinkStreamTraceState.igmpPruned:
            lineColor = AppTheme.textMuted.withValues(alpha: 0.45);
            strokeWidth = 1.6;
            dashed = true;
          case LinkStreamTraceState.none:
            lineColor = AppTheme.textMuted.withValues(alpha: 0.16);
            strokeWidth = 1.4;
        }
      } else if (isFilterActive) {
        if (matchesActiveFilter) {
          lineColor = AppTheme.success;
          strokeWidth = isSelected ? 3.6 : 3.2;
          dashed = isBlocked;
        } else {
          lineColor = AppTheme.textMuted.withValues(alpha: 0.22);
          strokeWidth = 1.5;
          dashed = false;
        }
      } else if (link.hasMediaMismatch) {
        lineColor = AppTheme.error;
        strokeWidth = 3.2;
        dashed = true;
      } else if (isUnprotectedLoop) {
        lineColor = AppTheme.error;
        strokeWidth = 3.2;
      } else if (isBlocked) {
        lineColor = AppTheme.error;
        dashed = true;
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

      // Draw circular port anchor terminals where the cable connects to card perimeters.
      final terminalFill = Paint()
        ..color = lineColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(geom.start, 3.5, terminalFill);
      canvas.drawCircle(geom.end, 3.5, terminalFill);

      // Draw directional arrow along stream direction during trace, or STP direction otherwise.
      if (isStreamTraceActive) {
        if (traceState == LinkStreamTraceState.delivered ||
            traceState == LinkStreamTraceState.flooded) {
          _drawDirectionArrow(
            canvas,
            geom,
            lineColor,
            sourceToTarget: link.streamDirectionSourceToTarget,
          );
        }
      } else if (link.stpState == LinkStpState.forwarding &&
          (!isFilterActive || matchesActiveFilter)) {
        _drawDirectionArrow(
          canvas,
          geom,
          lineColor,
          sourceToTarget: link.directionFromRootSourceToTarget,
        );
      }

      // Draw mid-link badge (Trace status, MEDIA MISMATCH, BLK (STP), LOOP!, PRUNED, Speed/Load).
      _drawLinkPill(
        canvas,
        geom,
        lineColor,
        isBlocked,
        isUnprotectedLoop,
        isVlanPruned,
        isFilterActive,
        matchesActiveFilter,
      );
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

  void _drawDirectionArrow(
    Canvas canvas,
    LinkGeometry geom,
    Color color, {
    required bool sourceToTarget,
  }) {
    final t = sourceToTarget ? 0.62 : 0.38;
    final pos = geom.pointAt(t);
    var tangent = geom.tangentAt(t);
    if (!sourceToTarget) {
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
    bool isFilterActive,
    bool matchesActiveFilter,
  ) {
    if (isFilterActive && !matchesActiveFilter) {
      return; // Dimmed unrelated or misconfigured links stay uncluttered
    }

    final link = geom.link;

    double t = 0.5;
    String label;
    Color textColor;

    if (isStreamTraceActive) {
      switch (link.streamTraceState) {
        case LinkStreamTraceState.delivered:
          label =
              '${link.tracedStreamCount} str • ${link.tracedStreamMbps.toStringAsFixed(1)}M';
          textColor = AppTheme.success;
        case LinkStreamTraceState.flooded:
          label = 'FLOODED ${link.tracedStreamMbps.toStringAsFixed(1)}M';
          textColor = AppTheme.warning;
        case LinkStreamTraceState.igmpPruned:
          label = 'IGMP PRUNED';
          textColor = AppTheme.textMuted;
        case LinkStreamTraceState.none:
          return;
      }
    } else if (link.hasMediaMismatch) {
      label = 'MEDIA MISMATCH';
      textColor = AppTheme.error;
    } else if (isUnprotectedLoop) {
      label = 'LOOP!';
      textColor = AppTheme.error;
    } else if (isBlocked) {
      t = (link.blockedAtNodeId == link.sourceNodeId) ? 0.28 : 0.72;
      label = 'BLK (STP) P${link.blockedAtPortNumber ?? ""}';
      textColor = AppTheme.error;
    } else if (isVlanPruned) {
      label = 'VLAN $highlightedVlanId PRUNED';
      textColor = AppTheme.error;
    } else if (link.hasVlanMismatch) {
      label = 'VLAN MISMATCH';
      textColor = AppTheme.error;
    } else if (link.hasSpeedStepDown) {
      label = link.isSfpStepDown
          ? '1G SFP STEP-DOWN'
          : '${link.negotiatedSpeed.label} STEP-DOWN';
      textColor = AppTheme.warning;
    } else {
      final loadStr = link.estimatedLoadMbps >= 0.1
          ? ' • ${link.estimatedLoadMbps.toStringAsFixed(1)}M'
          : '';
      label =
          'P${link.sourcePortNumber}↔P${link.targetPortNumber} (${link.negotiatedSpeed.label}$loadStr)';
      textColor = AppTheme.textPrimary;
    }

    final center = geom.pointAt(t);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: textColor,
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
        oldDelegate.isTrunkFilterActive != isTrunkFilterActive ||
        oldDelegate.isStreamTraceActive != isStreamTraceActive ||
        oldDelegate.geometries != geometries;
  }
}

/// Minor + major engineering grid background painter for the topology canvas.
class CanvasGridPainter extends CustomPainter {
  CanvasGridPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final minorPaint = Paint()
      ..color = isDark ? const Color(0xFF252A32) : const Color(0xFFDADEE5)
      ..strokeWidth = 1.0;

    final majorPaint = Paint()
      ..color = AppTheme.accent.withValues(alpha: isDark ? 0.22 : 0.18)
      ..strokeWidth = 1.2;

    final dotPaint = Paint()
      ..color = AppTheme.accent.withValues(alpha: isDark ? 0.45 : 0.35)
      ..style = PaintingStyle.fill;

    const minorSpacing = 32.0;
    const majorSpacing = 160.0;

    for (double x = 0; x <= size.width; x += minorSpacing) {
      final isMajor = (x % majorSpacing).abs() < 0.01;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? majorPaint : minorPaint,
      );
    }
    for (double y = 0; y <= size.height; y += minorSpacing) {
      final isMajor = (y % majorSpacing).abs() < 0.01;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        isMajor ? majorPaint : minorPaint,
      );
    }

    for (double x = 0; x <= size.width; x += majorSpacing) {
      for (double y = 0; y <= size.height; y += majorSpacing) {
        canvas.drawCircle(Offset(x, y), 1.6, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CanvasGridPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}
