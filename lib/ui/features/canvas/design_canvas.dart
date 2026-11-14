import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../sandbox_view_model.dart';
import 'endpoint_node_widget.dart';
import 'link_edge_painter.dart';
import 'switch_node_widget.dart';

/// Interactive topology canvas supporting node dragging, port wiring, zoom/pan,
/// link hit-testing, and auto-centering on clicked validation issues.
class DesignCanvas extends StatefulWidget {
  const DesignCanvas({super.key});

  @override
  State<DesignCanvas> createState() => _DesignCanvasState();
}

class _DesignCanvasState extends State<DesignCanvas> {
  static const double _canvasWidth = 3600.0;
  static const double _canvasHeight = 2600.0;

  final TransformationController _transformController =
      TransformationController();
  double _canvasScale = 1.0;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final raw = _transformController.value.getMaxScaleOnAxis();
    final next = raw > 0 ? raw : 1.0;
    if ((next - _canvasScale).abs() > 0.001) {
      setState(() {
        _canvasScale = next;
      });
    }
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _applyCenterRequest(Offset targetWorld, Size viewportSize) {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final tx = viewportSize.width / 2 - targetWorld.dx * scale;
    final ty = viewportSize.height / 2 - targetWorld.dy * scale;
    _transformController.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  void _zoomBy(double factor) {
    final current = _transformController.value.clone();
    final scale = current.getMaxScaleOnAxis();
    final nextScale = (scale * factor).clamp(0.45, 2.0);
    final appliedFactor = nextScale / scale;
    current.scaleByDouble(appliedFactor, appliedFactor, 1.0, 1.0);
    _transformController.value = current;
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  String? _hitTestLink(Offset tapWorld, List<LinkGeometry> geometries) {
    String? closestId;
    var bestDist = 18.0; // 18px tap tolerance
    for (final geom in geometries) {
      for (var step = 0; step <= 24; step++) {
        final pt = geom.pointAt(step / 24.0);
        final dist = (pt - tapWorld).distance;
        if (dist < bestDist) {
          bestDist = dist;
          closestId = geom.link.id;
        }
      }
    }
    return closestId;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SandboxViewModel>();
    final geometries = computeLinkGeometries(
      switches: vm.project.switches,
      endpoints: vm.project.endpoints,
      links: vm.project.links,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final focusReq = vm.canvasCenterRequest;
        if (focusReq != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            vm.consumeCanvasCenterRequest();
            _applyCenterRequest(focusReq, constraints.biggest);
          });
        }

        final backdropColor = AppTheme.isDark
            ? const Color(0xFF0B0C0E)
            : const Color(0xFFDDE1E7);

        return Container(
          color: backdropColor,
          child: Stack(
            children: [
              InteractiveViewer(
                transformationController: _transformController,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(600),
                minScale: 0.45,
                maxScale: 2.0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    final hitLinkId =
                        _hitTestLink(details.localPosition, geometries);
                    if (hitLinkId != null) {
                      vm.selectLink(hitLinkId);
                    } else {
                      vm.clearSelection();
                    }
                  },
                  child: Container(
                    width: _canvasWidth,
                    height: _canvasHeight,
                    decoration: BoxDecoration(
                      color: AppTheme.scaffoldBg,
                      border: Border.all(
                        color: AppTheme.accent.withValues(
                          alpha: AppTheme.isDark ? 0.5 : 0.4,
                        ),
                        width: 1.5,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: CanvasGridPainter(isDark: AppTheme.isDark),
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: LinkEdgePainter(
                              geometries: geometries,
                              selectedLinkId: vm.selectedLinkId,
                              highlightedVlanId: vm.highlightedVlanId,
                              isTrunkFilterActive: vm.isTrunkFilterActive,
                              isStreamTraceActive: vm.isStreamTraceActive,
                              isDark: AppTheme.isDark,
                            ),
                          ),
                        ),
                        for (final sw in vm.project.switches)
                          Positioned(
                            left: sw.dx,
                            top: sw.dy,
                            child: SwitchNodeWidget(
                              switchNode: sw,
                              canvasScale: _canvasScale,
                            ),
                          ),
                        for (final ep in vm.project.endpoints)
                          Positioned(
                            left: ep.dx,
                            top: ep.dy,
                            child: EndpointNodeWidget(
                              endpointNode: ep,
                              canvasScale: _canvasScale,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // Empty canvas prompt
              if (vm.project.switches.isEmpty && vm.project.endpoints.isEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hub_outlined,
                          size: 40,
                          color: AppTheme.accent,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Empty Design Canvas',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Add switches and endpoints from the top bar, or load a demo scenario.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Top-left project title / legend chip
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        vm.project.name,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (vm.isStreamTraceActive) ...[
                        _LegendDot(color: AppTheme.success, label: 'DELIVERED'),
                        const SizedBox(width: 6),
                        _LegendDot(color: AppTheme.warning, label: 'FLOODED'),
                        const SizedBox(width: 6),
                        _LegendDot(color: AppTheme.textMuted, label: 'IGMP PRUNED'),
                      ] else ...[
                        _LegendDot(color: AppTheme.success, label: 'FWD'),
                        const SizedBox(width: 6),
                        _LegendDot(color: AppTheme.error, label: 'BLK/FAULT'),
                        const SizedBox(width: 6),
                        _LegendDot(color: AppTheme.warning, label: 'WARN/ROOT'),
                      ],
                    ],
                  ),
                ),
              ),

              // Bottom-right zoom controls
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Zoom Out',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _zoomBy(0.85),
                        icon: Icon(
                          Icons.zoom_out,
                          size: 16,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Reset View',
                        visualDensity: VisualDensity.compact,
                        onPressed: _resetZoom,
                        icon: Icon(
                          Icons.center_focus_strong,
                          size: 15,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Zoom In',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _zoomBy(1.15),
                        icon: Icon(
                          Icons.zoom_in,
                          size: 16,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        color: AppTheme.border,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(_canvasScale * 100).round()}%',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 9.5,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}
