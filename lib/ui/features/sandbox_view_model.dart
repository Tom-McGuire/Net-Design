import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../data/services/device_templates.dart';
import '../../data/services/library_storage_service.dart';
import '../../data/services/project_storage_service.dart';
import '../../data/services/suite_theme_service.dart';
import '../../domain/engine/multicast_flow_tracer.dart';
import '../../domain/engine/multicast_stream_resolver.dart';
import '../../domain/engine/topology_validator.dart';
import '../../domain/models/endpoint_node_instance.dart';
import '../../domain/models/endpoint_template.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/network_link_edge.dart';
import '../../domain/models/switch_node_instance.dart';
import '../../domain/models/switch_port_config.dart';
import '../../domain/models/switch_template.dart';
import '../../domain/models/topology_project.dart';
import '../../domain/models/validation_issue.dart';

/// Main state container & MVVM view model for the Network Topology Sandbox.
class SandboxViewModel extends ChangeNotifier {
  SandboxViewModel({
    LibraryStorageService? libraryStorage,
    ProjectStorageService? projectStorage,
    this.themeService,
    TopologyValidator? validator,
    TopologyProject? initialProject,
  })  : _libraryStorage = libraryStorage ?? LibraryStorageService(),
        _projectStorage = projectStorage ?? const ProjectStorageService(),
        _validator = validator ?? const TopologyValidator(),
        _project = initialProject ?? DeviceTemplates.healthyReferenceRingDemo(),
        _switchTemplates = DeviceTemplates.defaultSwitchTemplates(),
        _endpointTemplates = DeviceTemplates.defaultEndpointTemplates() {
    _revalidate();
  }

  final LibraryStorageService _libraryStorage;
  final ProjectStorageService _projectStorage;
  final SuiteThemeService? themeService;
  final TopologyValidator _validator;
  final Uuid _uuid = const Uuid();
  final Random _rng = Random();

  TopologyProject _project;
  TopologyProject get project => _project;

  List<SwitchTemplate> _switchTemplates;
  List<SwitchTemplate> get switchTemplates =>
      List.unmodifiable(_switchTemplates);

  List<EndpointTemplate> _endpointTemplates;
  List<EndpointTemplate> get endpointTemplates =>
      List.unmodifiable(_endpointTemplates);

  late ValidationResult _validation;
  ValidationResult get validation => _validation;

  String? _selectedSwitchId;
  String? get selectedSwitchId => _selectedSwitchId;

  String? _selectedEndpointId;
  String? get selectedEndpointId => _selectedEndpointId;

  String? _selectedLinkId;
  String? get selectedLinkId => _selectedLinkId;

  int? _selectedPortNumber;
  int? get selectedPortNumber => _selectedPortNumber;

  int? _highlightedVlanId;
  int? get highlightedVlanId => _highlightedVlanId;

  Offset? _viewportCenterWorld;
  SwitchNodeInstance? _copiedSwitch;
  EndpointNodeInstance? _copiedEndpoint;

  bool get hasCopiedDevice => _copiedSwitch != null || _copiedEndpoint != null;
  bool get copiedDeviceIsSwitch => _copiedSwitch != null;
  String? get copiedDeviceLabel =>
      _copiedSwitch?.userLabel ?? _copiedEndpoint?.userLabel;

  /// Updates the current canvas viewport center in world coordinates without
  /// notifying listeners, so newly added or pasted devices appear in view.
  void updateViewportCenter(Offset? worldCenter) {
    _viewportCenterWorld = worldCenter;
  }

  bool _isTrunkFilterActive = false;
  bool get isTrunkFilterActive => _isTrunkFilterActive;

  String? _activeStreamTraceId;
  String? get activeStreamTraceId => _activeStreamTraceId;
  bool get isStreamTraceActive => activeStreamTraceTarget != null;

  List<StreamTraceTarget> get availableStreamTraceTargets =>
      MulticastFlowTracer.buildTraceTargets(_project);

  StreamTraceTarget? get activeStreamTraceTarget {
    if (_activeStreamTraceId == null) return null;
    for (final target in availableStreamTraceTargets) {
      if (target.id == _activeStreamTraceId) return target;
    }
    return null;
  }

  ({String nodeId, int portNumber})? _pendingWireSource;
  ({String nodeId, int portNumber})? get pendingWireSource =>
      _pendingWireSource;

  String _issueSearchQuery = '';
  String get issueSearchQuery => _issueSearchQuery;

  IssueCategory? _issueCategoryFilter;
  IssueCategory? get issueCategoryFilter => _issueCategoryFilter;

  bool _isIssuesExpanded = true;
  bool get isIssuesExpanded => _isIssuesExpanded;

  int _inspectorTabIndex = 0;
  int get inspectorTabIndex => _inspectorTabIndex;

  String? _lastStatusMessage;
  String? get lastStatusMessage => _lastStatusMessage;

  /// Emitted when clicking an issue so the canvas centers on that object.
  Offset? _canvasCenterRequest;
  Offset? get canvasCenterRequest => _canvasCenterRequest;

  SwitchNodeInstance? get selectedSwitch {
    if (_selectedSwitchId == null) return null;
    for (final sw in _project.switches) {
      if (sw.id == _selectedSwitchId) return sw;
    }
    return null;
  }

  EndpointNodeInstance? get selectedEndpoint {
    if (_selectedEndpointId == null) return null;
    for (final ep in _project.endpoints) {
      if (ep.id == _selectedEndpointId) return ep;
    }
    return null;
  }

  NetworkLinkEdge? get selectedLink {
    if (_selectedLinkId == null) return null;
    for (final l in _project.links) {
      if (l.id == _selectedLinkId) return l;
    }
    return null;
  }

  List<int> get availableVlanIds {
    final ids = <int>{..._project.knownVlans.keys};
    for (final sw in _project.switches) {
      ids.addAll(sw.vlanConfigs.keys);
      for (final p in sw.ports) {
        ids.add(p.nativeVlan);
        ids.addAll(p.allowedVlans);
      }
    }
    for (final ep in _project.endpoints) {
      for (final flow in ep.activeTrafficFlows) {
        ids.add(flow.defaultVlanId);
      }
    }
    final list = ids.toList()..sort();
    return list;
  }

  List<ValidationIssue> get filteredIssues {
    return _validation.issues.where((issue) {
      if (_issueCategoryFilter != null &&
          issue.category != _issueCategoryFilter) {
        return false;
      }
      if (_issueSearchQuery.trim().isNotEmpty) {
        final q = _issueSearchQuery.toLowerCase();
        return issue.title.toLowerCase().contains(q) ||
            issue.message.toLowerCase().contains(q) ||
            issue.category.label.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  Future<void> init() async {
    final bundle = await _libraryStorage.loadLibrary();
    _switchTemplates = bundle.switchTemplates;
    _endpointTemplates = bundle.endpointTemplates;
    notifyListeners();
  }

  void _revalidate() {
    _validation = _validator.validate(_project);
    final traceTarget = activeStreamTraceTarget;
    if (traceTarget == null) {
      _activeStreamTraceId = null;
    }
    MulticastFlowTracer.applyTrace(project: _project, target: traceTarget);
  }

  void clearStatusMessage() {
    _lastStatusMessage = null;
    notifyListeners();
  }

  void consumeCanvasCenterRequest() {
    _canvasCenterRequest = null;
  }

  void setIssuesExpanded(bool expanded) {
    _isIssuesExpanded = expanded;
    notifyListeners();
  }

  void setInspectorTabIndex(int idx) {
    _inspectorTabIndex = idx;
    notifyListeners();
  }

  void setIssueSearchQuery(String query) {
    _issueSearchQuery = query;
    notifyListeners();
  }

  void setIssueCategoryFilter(IssueCategory? category) {
    _issueCategoryFilter = category;
    notifyListeners();
  }

  void setHighlightedVlan(int? vlanId) {
    _highlightedVlanId = vlanId;
    _isTrunkFilterActive = false;
    _activeStreamTraceId = null;
    MulticastFlowTracer.applyTrace(project: _project, target: null);
    notifyListeners();
  }

  void setTrunkFilterActive(bool active) {
    _isTrunkFilterActive = active;
    if (active) {
      _highlightedVlanId = null;
      _activeStreamTraceId = null;
      MulticastFlowTracer.applyTrace(project: _project, target: null);
    }
    notifyListeners();
  }

  void setActiveStreamTrace(String? traceId) {
    _activeStreamTraceId = traceId;
    if (traceId != null) {
      _highlightedVlanId = null;
      _isTrunkFilterActive = false;
    }
    MulticastFlowTracer.applyTrace(
      project: _project,
      target: activeStreamTraceTarget,
    );
    notifyListeners();
  }

  NetworkLinkEdge? linkForPort(String nodeId, int portNumber) {
    for (final l in _project.links) {
      if (l.connectsEndpointPort(nodeId, portNumber)) return l;
    }
    return null;
  }

  bool isPortValidTrunk(String switchId, int portNumber) {
    final link = linkForPort(switchId, portNumber);
    return link != null && link.isValidTrunk;
  }

  bool doesPortCarryHighlightedVlanWorking(
    SwitchNodeInstance sw,
    SwitchPortConfig port,
    int vlanId,
  ) {
    if (!port.permitsVlan(vlanId, switchSupportsVlans: sw.supportsVlans)) {
      return false;
    }
    final link = linkForPort(sw.id, port.portNumber);
    if (link == null) return false;
    return link.activeVlans.contains(vlanId) && !link.hasVlanMismatch;
  }

  void selectSwitch(String? switchId, {int? portNumber}) {
    _selectedSwitchId = switchId;
    _selectedEndpointId = null;
    _selectedLinkId = null;
    _selectedPortNumber = portNumber;
    notifyListeners();
  }

  void selectEndpoint(String? endpointId) {
    _selectedEndpointId = endpointId;
    _selectedSwitchId = null;
    _selectedLinkId = null;
    _selectedPortNumber = null;
    notifyListeners();
  }

  void selectLink(String? linkId) {
    _selectedLinkId = linkId;
    _selectedSwitchId = null;
    _selectedEndpointId = null;
    _selectedPortNumber = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedSwitchId = null;
    _selectedEndpointId = null;
    _selectedLinkId = null;
    _selectedPortNumber = null;
    _pendingWireSource = null;
    notifyListeners();
  }

  /// Focuses and opens inspector for any clicked [ValidationIssue].
  void focusOnIssue(ValidationIssue issue) {
    if (issue.linkId != null) {
      for (final link in _project.links) {
        if (link.id == issue.linkId) {
          selectLink(link.id);
          final posA = _nodePosition(link.sourceNodeId);
          final posB = _nodePosition(link.targetNodeId);
          if (posA != null && posB != null) {
            _canvasCenterRequest = Offset(
              (posA.dx + posB.dx) / 2 + 120,
              (posA.dy + posB.dy) / 2 + 80,
            );
          }
          notifyListeners();
          return;
        }
      }
    }

    if (issue.nodeId != null) {
      for (final sw in _project.switches) {
        if (sw.id == issue.nodeId) {
          selectSwitch(sw.id, portNumber: issue.portNumber);
          _canvasCenterRequest = Offset(sw.dx + 140, sw.dy + 90);
          notifyListeners();
          return;
        }
      }
      for (final ep in _project.endpoints) {
        if (ep.id == issue.nodeId) {
          selectEndpoint(ep.id);
          _canvasCenterRequest = Offset(ep.dx + 110, ep.dy + 60);
          notifyListeners();
          return;
        }
      }
    }
  }

  Offset? _nodePosition(String nodeId) {
    for (final sw in _project.switches) {
      if (sw.id == nodeId) return Offset(sw.dx, sw.dy);
    }
    for (final ep in _project.endpoints) {
      if (ep.id == nodeId) return Offset(ep.dx, ep.dy);
    }
    return null;
  }

  // --- Interactive Wiring ---

  void startWiringFromPort(String nodeId, int portNumber) {
    // Reject if port already connected
    if (isPortConnected(nodeId, portNumber)) {
      _lastStatusMessage =
          'Port $portNumber is already connected. Remove its link first or pick a free port.';
      notifyListeners();
      return;
    }
    _pendingWireSource = (nodeId: nodeId, portNumber: portNumber);
    _lastStatusMessage =
        'Select a destination port on another switch or endpoint to complete cable link.';
    notifyListeners();
  }

  void cancelWiring() {
    _pendingWireSource = null;
    _lastStatusMessage = null;
    notifyListeners();
  }

  PortMediaType? portMediaType(String nodeId, int portNumber) {
    for (final sw in _project.switches) {
      if (sw.id == nodeId) {
        return sw.portByNumber(portNumber)?.mediaType;
      }
    }
    for (final ep in _project.endpoints) {
      if (ep.id == nodeId) {
        return ep.portByNumber(portNumber).mediaType;
      }
    }
    return null;
  }

  PortMediaType? get pendingWireMediaType {
    final src = _pendingWireSource;
    if (src == null) return null;
    return portMediaType(src.nodeId, src.portNumber);
  }

  bool isPortMediaCompatibleWithPendingWire(String nodeId, int portNumber) {
    final pendingMedia = pendingWireMediaType;
    if (pendingMedia == null) return true;
    final targetMedia = portMediaType(nodeId, portNumber);
    if (targetMedia == null) return false;
    return targetMedia == pendingMedia;
  }

  bool completeWiringToPort(String targetNodeId, int targetPortNumber) {
    final source = _pendingWireSource;
    if (source == null) return false;
    _pendingWireSource = null;

    if (source.nodeId == targetNodeId &&
        source.portNumber == targetPortNumber) {
      _lastStatusMessage = 'Cannot connect a port to itself.';
      notifyListeners();
      return false;
    }

    // Prevent connecting two endpoints directly without a switch
    final srcIsEp = _project.endpoints.any((e) => e.id == source.nodeId);
    final dstIsEp = _project.endpoints.any((e) => e.id == targetNodeId);
    if (srcIsEp && dstIsEp) {
      _lastStatusMessage =
          'Connect endpoints to a switch port rather than directly to another endpoint.';
      notifyListeners();
      return false;
    }

    if (isPortConnected(targetNodeId, targetPortNumber)) {
      _lastStatusMessage = 'Target port $targetPortNumber is already occupied.';
      notifyListeners();
      return false;
    }

    final srcMedia = portMediaType(source.nodeId, source.portNumber);
    final dstMedia = portMediaType(targetNodeId, targetPortNumber);
    if (srcMedia != null && dstMedia != null && srcMedia != dstMedia) {
      _lastStatusMessage =
          'Media mismatch: cannot connect ${srcMedia.label} to ${dstMedia.label}. Connect RJ45 to RJ45 and SFP/Fibre to SFP/Fibre.';
      notifyListeners();
      return false;
    }

    connectPorts(
      source.nodeId,
      source.portNumber,
      targetNodeId,
      targetPortNumber,
    );
    return true;
  }

  bool isPortConnected(String nodeId, int portNumber) {
    return _project.links.any((l) => l.connectsEndpointPort(nodeId, portNumber));
  }

  int? firstAvailablePortForNode(
    String nodeId, {
    PortMediaType? requiredMedia,
  }) {
    final mediaFilter = requiredMedia ?? pendingWireMediaType;
    for (final sw in _project.switches) {
      if (sw.id == nodeId) {
        for (final port in sw.ports) {
          if (!isPortConnected(nodeId, port.portNumber) &&
              (mediaFilter == null || port.mediaType == mediaFilter)) {
            return port.portNumber;
          }
        }
        return null;
      }
    }
    for (final ep in _project.endpoints) {
      if (ep.id == nodeId) {
        for (final port in ep.effectivePorts) {
          if (!isPortConnected(nodeId, port.portNumber) &&
              (mediaFilter == null || port.mediaType == mediaFilter)) {
            return port.portNumber;
          }
        }
        return null;
      }
    }
    return null;
  }

  // --- Simulation Controls ---

  void randomiseSwitchMacs() {
    for (var i = 0; i < _project.switches.length; i++) {
      final sw = _project.switches[i];
      _project.switches[i] = sw.copyWith(
        macAddress: SwitchNodeInstance.generateRandomLocalMac(_rng),
      );
    }
    _revalidate();
    _lastStatusMessage =
        'Randomized switch MAC addresses and re-ran STP election.';
    notifyListeners();
  }

  // --- Node & Link Mutations ---

  Offset _resolveSpawnPosition({
    required double cardWidth,
    required double cardHeight,
    double? dx,
    double? dy,
    required Offset fallback,
  }) {
    if (dx != null && dy != null) {
      return Offset(dx.clamp(16.0, 3300.0), dy.clamp(16.0, 2350.0));
    }
    final center = _viewportCenterWorld;
    if (center == null) {
      return Offset(
        fallback.dx.clamp(16.0, 3300.0),
        fallback.dy.clamp(16.0, 2350.0),
      );
    }

    var x = (center.dx - cardWidth / 2).clamp(16.0, 3300.0);
    var y = (center.dy - cardHeight / 2).clamp(16.0, 2350.0);

    bool overlapsExisting(double cx, double cy) {
      for (final s in _project.switches) {
        if ((s.dx - cx).abs() < 20.0 && (s.dy - cy).abs() < 20.0) return true;
      }
      for (final e in _project.endpoints) {
        if ((e.dx - cx).abs() < 20.0 && (e.dy - cy).abs() < 20.0) return true;
      }
      return false;
    }

    for (var step = 0; step < 10 && overlapsExisting(x, y); step++) {
      x = (x + 28.0).clamp(16.0, 3300.0);
      y = (y + 28.0).clamp(16.0, 2350.0);
    }
    return Offset(x, y);
  }

  String _nextCopyLabel(String sourceLabel, Set<String> existingLabels) {
    final base = sourceLabel.replaceFirst(RegExp(r'\s*\(Copy(?:\s+\d+)?\)$'), '');
    final first = '$base (Copy)';
    if (!existingLabels.contains(first)) return first;
    var n = 2;
    while (existingLabels.contains('$base (Copy $n)')) {
      n++;
    }
    return '$base (Copy $n)';
  }

  SwitchNodeInstance addSwitchFromTemplate(
    SwitchTemplate template, {
    double? dx,
    double? dy,
  }) {
    final index = _project.switches.length + 1;
    final pos = _resolveSpawnPosition(
      cardWidth: 268.0,
      cardHeight: 148.0,
      dx: dx,
      dy: dy,
      fallback: Offset(
        160.0 + (index * 45) % 420,
        110.0 + (index * 35) % 240,
      ),
    );
    final vlans = <int, SwitchVlanSettings>{
      for (final entry in _project.knownVlans.entries)
        entry.key: SwitchVlanSettings(
          vlanId: entry.key,
          vlanName: entry.value,
          igmpSnoopingEnabled: template.supportsIgmpSnooping && entry.key != 1,
        ),
    };
    final sw = SwitchNodeInstance(
      id: 'sw-${_uuid.v4().substring(0, 8)}',
      templateId: template.id,
      userLabel: '${template.name.split(' ').take(2).join(' ')} #$index',
      macAddress: SwitchNodeInstance.generateRandomLocalMac(_rng),
      stpMode: template.supportsStp ? StpMode.rstp : StpMode.disabled,
      stpPriority: 32768,
      poeBudgetWatts: template.poeBudgetWatts,
      supportsStp: template.supportsStp,
      supportsVlans: template.supportsVlans,
      supportsIgmpSnooping: template.supportsIgmpSnooping,
      supportsIgmpQuerier: template.supportsIgmpQuerier,
      vlanConfigs: vlans,
      ports: template.generateDefaultPorts(),
      dx: pos.dx,
      dy: pos.dy,
    );
    _project.switches.add(sw);
    _revalidate();
    selectSwitch(sw.id);
    return sw;
  }

  EndpointNodeInstance addEndpointFromTemplate(
    EndpointTemplate template, {
    double? dx,
    double? dy,
  }) {
    final index = _project.endpoints.length + 1;
    final pos = _resolveSpawnPosition(
      cardWidth: 228.0,
      cardHeight: 104.0,
      dx: dx,
      dy: dy,
      fallback: Offset(
        150.0 + (index * 55) % 500,
        420.0 + (index * 25) % 160,
      ),
    );
    final ep = EndpointNodeInstance(
      id: 'ep-${_uuid.v4().substring(0, 8)}',
      templateId: template.id,
      userLabel: '${template.name.split(' ').take(2).join(' ')} #$index',
      category: template.category,
      nicSpeed: template.nicSpeed,
      ports: List<EndpointPortConfig>.from(template.effectivePorts),
      activeTrafficFlows: template.trafficProfiles
          .map((f) => f.copyWith(id: 'flow-${_uuid.v4().substring(0, 6)}'))
          .toList(),
      poeDrawWatts: template.poeDrawWatts,
      dx: pos.dx,
      dy: pos.dy,
    );
    _project.endpoints.add(ep);
    for (final f in ep.activeTrafficFlows) {
      _project.knownVlans.putIfAbsent(
        f.defaultVlanId,
        () => 'VLAN ${f.defaultVlanId}',
      );
    }
    _revalidate();
    selectEndpoint(ep.id);
    return ep;
  }

  void moveNode(String nodeId, double dx, double dy) {
    final clampedX = dx.clamp(16.0, 3300.0);
    final clampedY = dy.clamp(16.0, 2350.0);

    for (var i = 0; i < _project.switches.length; i++) {
      if (_project.switches[i].id == nodeId) {
        _project.switches[i] =
            _project.switches[i].copyWith(dx: clampedX, dy: clampedY);
        notifyListeners();
        return;
      }
    }
    for (var i = 0; i < _project.endpoints.length; i++) {
      if (_project.endpoints[i].id == nodeId) {
        _project.endpoints[i] =
            _project.endpoints[i].copyWith(dx: clampedX, dy: clampedY);
        notifyListeners();
        return;
      }
    }
  }

  void connectPorts(
    String sourceNodeId,
    int sourcePortNumber,
    String targetNodeId,
    int targetPortNumber,
  ) {
    final link = NetworkLinkEdge(
      id: 'lnk-${_uuid.v4().substring(0, 8)}',
      sourceNodeId: sourceNodeId,
      sourcePortNumber: sourcePortNumber,
      targetNodeId: targetNodeId,
      targetPortNumber: targetPortNumber,
    );
    _project.links.add(link);
    _revalidate();
    _lastStatusMessage =
        'Connected Port $sourcePortNumber to Port $targetPortNumber.';
    selectLink(link.id);
  }

  void removeLink(String linkId) {
    _project.links.removeWhere((l) => l.id == linkId);
    if (_selectedLinkId == linkId) _selectedLinkId = null;
    _revalidate();
    notifyListeners();
  }

  void removeNode(String nodeId) {
    _project.switches.removeWhere((s) => s.id == nodeId);
    _project.endpoints.removeWhere((e) => e.id == nodeId);
    _project.links.removeWhere((l) => l.connectsNode(nodeId));
    if (_selectedSwitchId == nodeId) {
      _selectedSwitchId = null;
      _selectedPortNumber = null;
    }
    if (_selectedEndpointId == nodeId) {
      _selectedEndpointId = null;
    }
    if (_pendingWireSource?.nodeId == nodeId) {
      _pendingWireSource = null;
    }
    _revalidate();
    notifyListeners();
  }

  void copySwitch(String switchId) {
    final sw = _project.switches.where((s) => s.id == switchId).firstOrNull;
    if (sw == null) return;
    _copiedSwitch = sw.copyWith(
      vlanConfigs: {
        for (final entry in sw.vlanConfigs.entries)
          entry.key: entry.value.copyWith(),
      },
      ports: [
        for (final p in sw.ports) p.copyWith(),
      ],
    );
    _copiedEndpoint = null;
    _lastStatusMessage = 'Copied ${sw.userLabel}.';
    notifyListeners();
  }

  void copyEndpoint(String endpointId) {
    final ep = _project.endpoints.where((e) => e.id == endpointId).firstOrNull;
    if (ep == null) return;
    _copiedEndpoint = ep.copyWith(
      ports: [
        for (final p in ep.effectivePorts) p.copyWith(),
      ],
      activeTrafficFlows: [
        for (final f in ep.activeTrafficFlows) f.copyWith(),
      ],
    );
    _copiedSwitch = null;
    _lastStatusMessage = 'Copied ${ep.userLabel}.';
    notifyListeners();
  }

  bool copySelectedNode() {
    if (_selectedSwitchId != null) {
      copySwitch(_selectedSwitchId!);
      return true;
    }
    if (_selectedEndpointId != null) {
      copyEndpoint(_selectedEndpointId!);
      return true;
    }
    return false;
  }

  Object? pasteCopiedNode({double? dx, double? dy}) {
    final swSource = _copiedSwitch;
    if (swSource != null) {
      final pos = _resolveSpawnPosition(
        cardWidth: 268.0,
        cardHeight: 148.0,
        dx: dx,
        dy: dy,
        fallback: Offset(swSource.dx + 36.0, swSource.dy + 36.0),
      );
      final label = _nextCopyLabel(
        swSource.userLabel,
        _project.switches.map((s) => s.userLabel).toSet(),
      );
      final pasted = SwitchNodeInstance(
        id: 'sw-${_uuid.v4().substring(0, 8)}',
        templateId: swSource.templateId,
        userLabel: label,
        macAddress: SwitchNodeInstance.generateRandomLocalMac(_rng),
        managementIp: swSource.managementIp,
        stpMode: swSource.stpMode,
        stpPriority: swSource.stpPriority,
        poeBudgetWatts: swSource.poeBudgetWatts,
        supportsStp: swSource.supportsStp,
        supportsVlans: swSource.supportsVlans,
        supportsIgmpSnooping: swSource.supportsIgmpSnooping,
        supportsIgmpQuerier: swSource.supportsIgmpQuerier,
        vlanConfigs: {
          for (final entry in swSource.vlanConfigs.entries)
            entry.key: entry.value.copyWith(),
        },
        ports: [
          for (final p in swSource.ports) p.copyWith(),
        ],
        dx: pos.dx,
        dy: pos.dy,
      );
      _project.switches.add(pasted);
      _revalidate();
      _lastStatusMessage = 'Pasted ${pasted.userLabel}.';
      selectSwitch(pasted.id);
      return pasted;
    }

    final epSource = _copiedEndpoint;
    if (epSource != null) {
      final pos = _resolveSpawnPosition(
        cardWidth: 228.0,
        cardHeight: 104.0,
        dx: dx,
        dy: dy,
        fallback: Offset(epSource.dx + 36.0, epSource.dy + 36.0),
      );
      final label = _nextCopyLabel(
        epSource.userLabel,
        _project.endpoints.map((e) => e.userLabel).toSet(),
      );
      final pasted = EndpointNodeInstance(
        id: 'ep-${_uuid.v4().substring(0, 8)}',
        templateId: epSource.templateId,
        userLabel: label,
        category: epSource.category,
        nicSpeed: epSource.nicSpeed,
        macAddress: epSource.macAddress,
        ipAddress: epSource.ipAddress,
        ports: [
          for (final p in epSource.effectivePorts) p.copyWith(),
        ],
        activeTrafficFlows: epSource.activeTrafficFlows
            .map((f) => f.copyWith(id: 'flow-${_uuid.v4().substring(0, 6)}'))
            .toList(),
        poeDrawWatts: epSource.poeDrawWatts,
        dx: pos.dx,
        dy: pos.dy,
      );
      _project.endpoints.add(pasted);
      _revalidate();
      _lastStatusMessage = 'Pasted ${pasted.userLabel}.';
      selectEndpoint(pasted.id);
      return pasted;
    }

    return null;
  }

  bool deleteSelectedItem() {
    if (_selectedSwitchId != null) {
      removeNode(_selectedSwitchId!);
      _lastStatusMessage = 'Deleted selected switch.';
      notifyListeners();
      return true;
    }
    if (_selectedEndpointId != null) {
      removeNode(_selectedEndpointId!);
      _lastStatusMessage = 'Deleted selected endpoint.';
      notifyListeners();
      return true;
    }
    if (_selectedLinkId != null) {
      removeLink(_selectedLinkId!);
      _lastStatusMessage = 'Deleted selected link.';
      notifyListeners();
      return true;
    }
    return false;
  }

  void updateSwitch(SwitchNodeInstance updated) {
    final idx = _project.switches.indexWhere((s) => s.id == updated.id);
    if (idx < 0) return;
    _project.switches[idx] = updated;
    _revalidate();
    notifyListeners();
  }

  void updatePort(String switchId, SwitchPortConfig updatedPort) {
    final idx = _project.switches.indexWhere((s) => s.id == switchId);
    if (idx < 0) return;
    final sw = _project.switches[idx];
    final ports = List<SwitchPortConfig>.from(sw.ports);
    final pIdx =
        ports.indexWhere((p) => p.portNumber == updatedPort.portNumber);
    if (pIdx < 0) return;
    ports[pIdx] = updatedPort;

    // Ensure any VLAN IDs referenced by the port exist in knownVlans & switch vlanConfigs.
    final vlanConfigs = Map<int, SwitchVlanSettings>.from(sw.vlanConfigs);
    for (final v in updatedPort.effectiveVlans(switchSupportsVlans: sw.supportsVlans)) {
      _project.knownVlans.putIfAbsent(v, () => 'VLAN $v');
      vlanConfigs.putIfAbsent(
        v,
        () => SwitchVlanSettings(
          vlanId: v,
          vlanName: _project.knownVlans[v] ?? 'VLAN $v',
        ),
      );
    }

    _project.switches[idx] = sw.copyWith(
      ports: ports,
      vlanConfigs: vlanConfigs,
    );
    _revalidate();
    notifyListeners();
  }

  void updateSwitchVlan(String switchId, SwitchVlanSettings settings) {
    final idx = _project.switches.indexWhere((s) => s.id == switchId);
    if (idx < 0) return;
    final sw = _project.switches[idx];
    final vlanConfigs = Map<int, SwitchVlanSettings>.from(sw.vlanConfigs);
    vlanConfigs[settings.vlanId] = settings;
    _project.knownVlans.putIfAbsent(settings.vlanId, () => settings.vlanName);
    _project.switches[idx] = sw.copyWith(vlanConfigs: vlanConfigs);
    _revalidate();
    notifyListeners();
  }

  void addKnownVlan(int vlanId, String name) {
    if (vlanId < 1 || vlanId > 4094) return;
    final label = name.trim().isEmpty ? 'VLAN $vlanId' : name.trim();
    _project.knownVlans[vlanId] = label;
    for (var i = 0; i < _project.switches.length; i++) {
      final sw = _project.switches[i];
      if (!sw.vlanConfigs.containsKey(vlanId)) {
        final nextConfigs = Map<int, SwitchVlanSettings>.from(sw.vlanConfigs);
        nextConfigs[vlanId] = SwitchVlanSettings(
          vlanId: vlanId,
          vlanName: label,
          igmpSnoopingEnabled: sw.supportsIgmpSnooping,
        );
        _project.switches[i] = sw.copyWith(vlanConfigs: nextConfigs);
      }
    }
    _revalidate();
    notifyListeners();
  }

  void updateEndpoint(EndpointNodeInstance updated) {
    final idx = _project.endpoints.indexWhere((e) => e.id == updated.id);
    if (idx < 0) return;
    _project.endpoints[idx] = updated;
    for (final f in updated.activeTrafficFlows) {
      _project.knownVlans.putIfAbsent(f.defaultVlanId, () => 'VLAN ${f.defaultVlanId}');
    }
    _revalidate();
    notifyListeners();
  }

  void autoFixLinkVlanSymmetry(String linkId) {
    final link = _project.links.where((l) => l.id == linkId).firstOrNull;
    if (link == null) return;
    final swA = _project.switches
        .where((s) => s.id == link.sourceNodeId)
        .firstOrNull;
    final swB = _project.switches
        .where((s) => s.id == link.targetNodeId)
        .firstOrNull;
    if (swA == null || swB == null) return;

    final portA = swA.portByNumber(link.sourcePortNumber);
    final portB = swB.portByNumber(link.targetPortNumber);
    if (portA == null || portB == null) return;

    final unionVlans = {
      ...portA.effectiveVlans(switchSupportsVlans: swA.supportsVlans),
      ...portB.effectiveVlans(switchSupportsVlans: swB.supportsVlans),
      portA.nativeVlan,
      portB.nativeVlan,
    };
    final nativeVlan = portA.nativeVlan;

    updatePort(
      swA.id,
      portA.copyWith(
        portMode: SwitchPortMode.trunk,
        nativeVlan: nativeVlan,
        allowedVlans: unionVlans,
      ),
    );
    updatePort(
      swB.id,
      portB.copyWith(
        portMode: SwitchPortMode.trunk,
        nativeVlan: nativeVlan,
        allowedVlans: unionVlans,
      ),
    );
    _lastStatusMessage = 'Synchronized trunk VLANs on both ends of link.';
  }

  // --- Template Library CRUD ---

  Future<void> saveSwitchTemplate(SwitchTemplate template) async {
    final idx = _switchTemplates.indexWhere((t) => t.id == template.id);
    if (idx >= 0) {
      _switchTemplates[idx] = template;
    } else {
      _switchTemplates.add(template);
    }
    await _saveLibrarySafe();
    notifyListeners();
  }

  Future<void> deleteSwitchTemplate(String id) async {
    _switchTemplates.removeWhere((t) => t.id == id);
    await _saveLibrarySafe();
    notifyListeners();
  }

  Future<void> saveEndpointTemplate(EndpointTemplate template) async {
    final idx = _endpointTemplates.indexWhere((t) => t.id == template.id);
    if (idx >= 0) {
      _endpointTemplates[idx] = template;
    } else {
      _endpointTemplates.add(template);
    }
    await _saveLibrarySafe();
    notifyListeners();
  }

  Future<void> deleteEndpointTemplate(String id) async {
    _endpointTemplates.removeWhere((t) => t.id == id);
    await _saveLibrarySafe();
    notifyListeners();
  }

  Future<void> resetLibraryDefaults() async {
    _switchTemplates = DeviceTemplates.defaultSwitchTemplates();
    _endpointTemplates = DeviceTemplates.defaultEndpointTemplates();
    await _saveLibrarySafe();
    notifyListeners();
  }

  /// Applies [template] hardware/capability settings to matching switches on
  /// the current plan (or a single switch when [onlySwitchId] is provided),
  /// preserving user labels, MACs, coordinates, VLAN port mappings, and links.
  int applySwitchTemplateToPlan(
    SwitchTemplate template, {
    String? onlySwitchId,
  }) {
    var updatedCount = 0;
    final templatePorts = template.generateDefaultPorts();
    final validPortNums = {for (final p in templatePorts) p.portNumber};

    for (var i = 0; i < _project.switches.length; i++) {
      final sw = _project.switches[i];
      if (onlySwitchId != null) {
        if (sw.id != onlySwitchId) continue;
      } else if (sw.templateId != template.id) {
        continue;
      }

      final mergedPorts = <SwitchPortConfig>[
        for (final tplPort in templatePorts)
          () {
            final old = sw.portByNumber(tplPort.portNumber);
            if (old == null) return tplPort;
            return SwitchPortConfig(
              portNumber: tplPort.portNumber,
              customLabel: old.customLabel,
              mediaType: tplPort.mediaType,
              maxSpeed: tplPort.maxSpeed,
              poeCapable: tplPort.poeCapable,
              poeEnabled: tplPort.poeCapable ? old.poeEnabled : false,
              portMode: old.portMode,
              nativeVlan: old.nativeVlan,
              allowedVlans: Set<int>.from(old.allowedVlans),
              lagGroupId: old.lagGroupId,
            );
          }(),
      ];

      final nextVlans = <int, SwitchVlanSettings>{
        for (final entry in sw.vlanConfigs.entries)
          entry.key: entry.value.copyWith(
            igmpSnoopingEnabled: template.supportsIgmpSnooping
                ? entry.value.igmpSnoopingEnabled
                : false,
            igmpQuerierEnabled: template.supportsIgmpQuerier
                ? entry.value.igmpQuerierEnabled
                : false,
          ),
      };

      final nextStpMode = !template.supportsStp
          ? StpMode.disabled
          : (sw.stpMode == StpMode.disabled && !sw.supportsStp
              ? StpMode.rstp
              : sw.stpMode);

      _project.switches[i] = sw.copyWith(
        stpMode: nextStpMode,
        poeBudgetWatts: template.poeBudgetWatts,
        supportsStp: template.supportsStp,
        supportsVlans: template.supportsVlans,
        supportsIgmpSnooping: template.supportsIgmpSnooping,
        supportsIgmpQuerier: template.supportsIgmpQuerier,
        vlanConfigs: nextVlans,
        ports: mergedPorts,
      );

      _project.links.removeWhere(
        (l) =>
            (l.sourceNodeId == sw.id &&
                !validPortNums.contains(l.sourcePortNumber)) ||
            (l.targetNodeId == sw.id &&
                !validPortNums.contains(l.targetPortNumber)),
      );
      updatedCount++;
    }

    if (updatedCount > 0) {
      _revalidate();
      _lastStatusMessage =
          'Updated $updatedCount switch${updatedCount == 1 ? '' : 'es'} on plan from "${template.name}".';
      notifyListeners();
    }
    return updatedCount;
  }

  /// Applies [template] interface and traffic-profile settings to matching
  /// endpoints on the current plan (or a single endpoint when [onlyEndpointId]
  /// is provided), preserving user labels, IPs, coordinates, and valid links.
  int applyEndpointTemplateToPlan(
    EndpointTemplate template, {
    String? onlyEndpointId,
  }) {
    var updatedCount = 0;
    final templatePorts = template.effectivePorts;
    final validPortNums = {for (final p in templatePorts) p.portNumber};

    for (var i = 0; i < _project.endpoints.length; i++) {
      final ep = _project.endpoints[i];
      if (onlyEndpointId != null) {
        if (ep.id != onlyEndpointId) continue;
      } else if (ep.templateId != template.id) {
        continue;
      }

      final nextFlows = template.trafficProfiles
          .map((f) => f.copyWith(id: 'flow-${_uuid.v4().substring(0, 6)}'))
          .toList();
      for (final f in nextFlows) {
        _project.knownVlans.putIfAbsent(
          f.defaultVlanId,
          () => 'VLAN ${f.defaultVlanId}',
        );
      }

      _project.endpoints[i] = ep.copyWith(
        category: template.category,
        nicSpeed: template.nicSpeed,
        ports: List<EndpointPortConfig>.from(templatePorts),
        activeTrafficFlows: nextFlows,
        poeDrawWatts: template.poeDrawWatts,
      );

      _project.links.removeWhere(
        (l) =>
            (l.sourceNodeId == ep.id &&
                !validPortNums.contains(l.sourcePortNumber)) ||
            (l.targetNodeId == ep.id &&
                !validPortNums.contains(l.targetPortNumber)),
      );
      updatedCount++;
    }

    if (updatedCount > 0) {
      _revalidate();
      _lastStatusMessage =
          'Updated $updatedCount endpoint${updatedCount == 1 ? '' : 's'} on plan from "${template.name}".';
      notifyListeners();
    }
    return updatedCount;
  }

  String exportLibraryJson() {
    return _libraryStorage.exportLibraryJson(
      TemplateLibraryBundle(
        switchTemplates: _switchTemplates,
        endpointTemplates: _endpointTemplates,
      ),
    );
  }

  Future<void> importLibraryJson(String rawJson) async {
    final imported = _libraryStorage.importLibraryJson(rawJson);
    if (imported.switchTemplates.isNotEmpty) {
      _switchTemplates = imported.switchTemplates;
    }
    if (imported.endpointTemplates.isNotEmpty) {
      _endpointTemplates = imported.endpointTemplates;
    }
    await _saveLibrarySafe();
    notifyListeners();
  }

  Future<void> _saveLibrarySafe() async {
    try {
      await _libraryStorage.saveLibrary(
        TemplateLibraryBundle(
          switchTemplates: _switchTemplates,
          endpointTemplates: _endpointTemplates,
        ),
      );
    } catch (_) {
      // Safe no-op in sandboxed test environments without platform channels
    }
  }

  // --- Project Lifecycle & Demos ---

  void newBlankProject() {
    _project = TopologyProject(name: 'Untitled Topology');
    clearSelection();
    _highlightedVlanId = null;
    _isTrunkFilterActive = false;
    _activeStreamTraceId = null;
    _revalidate();
    notifyListeners();
  }

  void loadDemoHealthyRing() {
    _project = DeviceTemplates.healthyReferenceRingDemo();
    clearSelection();
    _highlightedVlanId = null;
    _isTrunkFilterActive = false;
    _activeStreamTraceId = null;
    _revalidate();
    notifyListeners();
  }

  void loadDemoBrokenRing() {
    _project = DeviceTemplates.brokenRingFaultDemo();
    clearSelection();
    _highlightedVlanId = null;
    _isTrunkFilterActive = false;
    _activeStreamTraceId = null;
    _revalidate();
    notifyListeners();
  }

  void loadDemoUnmanagedLoop() {
    _project = DeviceTemplates.unmanagedLoopAndBroadcastDemo();
    clearSelection();
    _highlightedVlanId = null;
    _isTrunkFilterActive = false;
    _activeStreamTraceId = null;
    _revalidate();
    notifyListeners();
  }

  Future<void> saveProjectToFile(String filePath) async {
    await _projectStorage.saveProjectToFile(_project, filePath);
    _lastStatusMessage = 'Saved topology project to $filePath';
    notifyListeners();
  }

  Future<void> loadProjectFromFile(String filePath) async {
    final loaded = await _projectStorage.loadProjectFromFile(filePath);
    _project = loaded;
    clearSelection();
    _highlightedVlanId = null;
    _isTrunkFilterActive = false;
    _activeStreamTraceId = null;
    _revalidate();
    _lastStatusMessage = 'Loaded project "${loaded.name}"';
    notifyListeners();
  }

  /// Returns TX-advertised sACN / multicast stream specs on [vlanId] for quick-pick RX subscription chips.
  List<({
    String sourceLabel,
    String? sacnUniverseSpec,
    String? multicastGroupSpec,
    String summaryLabel,
    double bandwidthMbps,
  })> advertisedTxStreamChipsForVlan(
    int vlanId,
    TrafficProtocol protocol, {
    String? excludeEndpointId,
  }) {
    final switchesById = {for (final sw in _project.switches) sw.id: sw};
    final endpointsById = {for (final ep in _project.endpoints) ep.id: ep};
    final attachments = MulticastFlowTracer.buildEndpointAttachments(
      switchesById: switchesById,
      endpointsById: endpointsById,
      links: _project.links,
    );

    final chips = <({
      String sourceLabel,
      String? sacnUniverseSpec,
      String? multicastGroupSpec,
      String summaryLabel,
      double bandwidthMbps,
    })>[];
    final seen = <String>{};

    for (final ep in _project.endpoints) {
      if (ep.id == excludeEndpointId) continue;
      for (final flow in ep.activeTrafficFlows) {
        if (!flow.direction.isPublisher) continue;
        if (flow.protocol != protocol) continue;
        final att = attachments['${ep.id}:${flow.effectivePortNumber}'];
        final effVlan = MulticastFlowTracer.effectiveVlanForFlow(flow, att);
        if (effVlan != vlanId) continue;

        final resolved = MulticastStreamResolver.resolveFlowStreams(
          flow,
          effectiveVlanId: effVlan,
        );
        if (resolved.isEmpty) continue;

        String? sacnSpec;
        String? mcastSpec;
        String summary;
        if (protocol == TrafficProtocol.sacn) {
          final univs = [
            for (final s in resolved)
              if (s.sacnUniverse != null) s.sacnUniverse!,
          ];
          if (univs.isEmpty) continue;
          sacnSpec = MulticastStreamResolver.formatUniverseRanges(univs);
          summary = 'sACN U$sacnSpec (${ep.userLabel})';
        } else {
          final rawSpec = flow.multicastGroupSpec?.trim() ?? '';
          if (rawSpec.isEmpty) continue;
          mcastSpec = rawSpec;
          summary = '$rawSpec (${ep.userLabel})';
        }

        final dedupKey = '${sacnSpec ?? ""}|${mcastSpec ?? ""}|${ep.id}';
        if (!seen.add(dedupKey)) continue;
        chips.add((
          sourceLabel: ep.userLabel,
          sacnUniverseSpec: sacnSpec,
          multicastGroupSpec: mcastSpec,
          summaryLabel: summary,
          bandwidthMbps: flow.estimatedBandwidthMbps,
        ));
      }
    }
    return chips;
  }

  String serializeCurrentProject() =>
      _projectStorage.serializeProject(_project);

  String buildMarkdownValidationReport() =>
      _projectStorage.buildMarkdownValidationReport(_project, _validation);

  Future<void> toggleTheme() async {
    final nextMode = (themeService?.currentMode ?? 'dark') == 'dark'
        ? 'light'
        : 'dark';
    await themeService?.setThemeMode(nextMode);
    notifyListeners();
  }

  void notifyThemeChanged() {
    notifyListeners();
  }

  /// Generates vendor-neutral CLI reference summary for the selected switch.
  String generateCliConfigPreview(SwitchNodeInstance sw) {
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
