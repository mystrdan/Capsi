import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'capsi_native.dart';
import 'package:file_selector/file_selector.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// User preferences that survive a restart, stored beside the rest of the Capsi
/// data as a single small JSON file.
///
/// The native side already owns the data directory (`capsi_data.json`, trust
/// store, workplace), so preferences live there too rather than in a second
/// location the user would never find. Reads are best-effort: a missing or
/// corrupt file falls back to the defaults instead of blocking startup, because
/// preferences are not worth refusing to launch over.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._directory);

  /// Used before [load] resolves, and by tests.
  factory AppSettings.inMemory() => AppSettings._(null);

  final Directory? _directory;

  static const _defaultDeviceName = 'Capsi device';

  String _deviceName = _defaultDeviceName;
  bool _notificationsEnabled = true;
  bool _minimizeToTray = true;
  bool _sendReadReceipts = true;

  /// The name this device advertises over discovery. Peers show this, so it is
  /// worth letting the user pick something recognisable.
  String get deviceName => _deviceName;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get minimizeToTray => _minimizeToTray;
  bool get sendReadReceipts => _sendReadReceipts;

  File? get _file {
    final directory = _directory;
    if (directory == null) return null;
    return File('${directory.path}${Platform.pathSeparator}capsi_settings.json');
  }

  /// Load from disk, creating the file on first run so the location is obvious.
  static Future<AppSettings> load() async {
    AppSettings settings;
    try {
      settings = AppSettings._(await getApplicationSupportDirectory());
    } catch (_) {
      return AppSettings.inMemory();
    }
    await settings._read();
    return settings;
  }

  Future<void> _read() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final name = decoded['deviceName'];
      _deviceName = name is String && name.trim().isNotEmpty ? name.trim() : _defaultDeviceName;
      _notificationsEnabled = decoded['notificationsEnabled'] is bool ? decoded['notificationsEnabled'] as bool : true;
      _minimizeToTray = decoded['minimizeToTray'] is bool ? decoded['minimizeToTray'] as bool : true;
      _sendReadReceipts = decoded['sendReadReceipts'] is bool ? decoded['sendReadReceipts'] as bool : true;
    } catch (_) {
      // Corrupt preferences are not a reason to fail; keep the defaults.
    }
  }

  Future<void> _write() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(jsonEncode({
        'deviceName': _deviceName,
        'notificationsEnabled': _notificationsEnabled,
        'minimizeToTray': _minimizeToTray,
        'sendReadReceipts': _sendReadReceipts,
      }));
    } catch (_) {
      // Losing a preference write must never take the app down with it.
    }
  }

  /// Capsi validates the name in the core (`validate_device_name`), which
  /// trims and caps the length; mirror that here so the user gets the message
  /// before discovery restarts.
  static const maxDeviceNameLength = 32;

  /// Returns the trimmed name, or an error the UI can show.
  String? setDeviceName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Device name cannot be empty.';
    if (trimmed.length > maxDeviceNameLength) {
      return 'Device name is limited to $maxDeviceNameLength characters.';
    }
    if (trimmed == _deviceName) return null;
    _deviceName = trimmed;
    _write();
    notifyListeners();
    return null;
  }

  void setNotificationsEnabled(bool value) {
    if (value == _notificationsEnabled) return;
    _notificationsEnabled = value;
    _write();
    notifyListeners();
  }

  void setMinimizeToTray(bool value) {
    if (value == _minimizeToTray) return;
    _minimizeToTray = value;
    _write();
    notifyListeners();
  }

  void setSendReadReceipts(bool value) {
    if (value == _sendReadReceipts) return;
    _sendReadReceipts = value;
    _write();
    notifyListeners();
  }
}

/// Capsi is published by Capsicom and every build points at the public site.
const String capsiWebsite = 'https://capsi.win';
const String capsiPublisher = 'Capsicom';

/// Fallback shown when the native bridge (and with it the authoritative crate
/// version) is unavailable. scripts/bump-version.ps1 updates this const.
const String capsiVersionFallback = '1.1.0';

/// True where the Capsi data folder is an ordinary folder the user can open.
/// The mobile sandbox keeps application data private to the application, so
/// Android and iOS expose the path instead of a file manager.
bool get _dataFolderIsOpenable =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Opens [url] in the user's browser. A device without a browser handler is
/// still a working Capsi device, so a failure is reported instead of thrown.
Future<void> _openExternalLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void report(String message) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  try {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened) report('Could not open $url.');
  } catch (_) {
    report('Could not open $url.');
  }
}

/// Opens the Capsi data folder in the platform file manager.
Future<void> _openDataFolder(BuildContext context, String directory) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void report(String message) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  if (!_dataFolderIsOpenable) {
    report('Capsi data stays private to the application on this device.');
    return;
  }

  // explorer.exe opens a directory in File Explorer; `open` and `xdg-open` are
  // the equivalents on the other desktops.
  final command = Platform.isWindows
      ? 'explorer.exe'
      : Platform.isMacOS
          ? 'open'
          : 'xdg-open';

  try {
    await Process.run(command, [directory]);
  } catch (_) {
    report('Could not open the Capsi data folder.');
  }
}

Future<String?> _sendFileInIsolate(String dataDirectory, String deviceId, String filePath) async {
  return Isolate.run(() {
    final bridge = CapsiNative.tryLoad();
    if (bridge == null) return null;
    return bridge.sendFile(dataDirectory, deviceId, filePath);
  });
}

Future<String?> _sendMessageInIsolate(String dataDirectory, String deviceId, String body) async {
  return Isolate.run(() {
    final bridge = CapsiNative.tryLoad();
    if (bridge == null) return null;
    return bridge.sendMessage(dataDirectory, deviceId, body);
  });
}

Future<Map<String, dynamic>?> _nativeJsonInIsolate(
  String dataDirectory,
  String operation,
  List<String> args,
) async {
  return Isolate.run(() {
    final bridge = CapsiNative.tryLoad();
    if (bridge == null) return null;
    switch (operation) {
      case 'workplace_create':
        return bridge.createWorkplace(dataDirectory, args[0]);
      case 'workplace_group':
        return bridge.createWorkplaceGroup(dataDirectory, args[0]);
      case 'workplace_department':
        return bridge.createWorkplaceDepartment(dataDirectory, args[0]);
      case 'workplace_broadcast':
        return bridge.createWorkplaceBroadcast(dataDirectory, args[0], args[1]);
      case 'workplace_send':
        return bridge.sendWorkplaceMessage(dataDirectory, args[0], args[1]);
      case 'workplace_add_member':
        return bridge.addWorkplaceGroupMember(dataDirectory, args[0], args[1]);
      case 'workplace_remove_member':
        return bridge.removeWorkplaceGroupMember(dataDirectory, args[0], args[1]);
      case 'workplace_move_member':
        return bridge.moveWorkplaceGroupMember(dataDirectory, args[0], args[1], args[2]);
      case 'workplace_set_role':
        return bridge.setWorkplaceMemberRole(dataDirectory, args[0], args[1]);
      case 'workplace_rename':
        return bridge.renameWorkplace(dataDirectory, args[0]);
      case 'workplace_delete':
        return bridge.deleteWorkplace(dataDirectory);
      case 'file_accept':
        return {'ok': bridge.acceptFile(dataDirectory, args[0], args[1])};
      case 'file_decline':
        return {'ok': bridge.declineFile(dataDirectory, args[0], args[1])};
      case 'file_cancel':
        return {'ok': bridge.cancelFile(dataDirectory, args[0], args[1])};
      default:
        return null;
    }
  });
}

void main() {
  runApp(const CapsiApp());
}

class CapsiApp extends StatelessWidget {
  const CapsiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Capsi',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF090B0C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7ED957),
          brightness: Brightness.dark,
          surface: const Color(0xFF111516),
        ),
        dividerColor: const Color(0x18FFFFFF),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF0E1112),
          indicatorColor: Color(0x187ED957),
          selectedIconTheme: IconThemeData(color: Color(0xFF7ED957)),
          selectedLabelTextStyle: TextStyle(color: Color(0xFFF4F6F2), fontWeight: FontWeight.w700),
          unselectedIconTheme: IconThemeData(color: Color(0xFF777E79)),
          unselectedLabelTextStyle: TextStyle(color: Color(0xFF777E79)),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF111516),
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF0E1112),
          border: OutlineInputBorder(borderSide: BorderSide(color: Color(0x18FFFFFF))),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0x18FFFFFF))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0x667ED957))),
        ),
      ),
      home: const CapsiHome(),
    );
  }
}

class CapsiHome extends StatefulWidget {
  const CapsiHome({
    super.key,
    this.autoInitialize = true,
    this.settings,
  });

  final bool autoInitialize;

  /// Preferences are injected so a widget test can supply an in-memory instance
  /// instead of touching the filesystem.
  final AppSettings? settings;

  @override
  State<CapsiHome> createState() => _CapsiHomeState();
}

class _CapsiHomeState extends State<CapsiHome> {
  Map<String, dynamic>? lastMessageEvent;
  int selected = 0;
  CapsiNative? native;
  List<CapsiPeer> peers = const [];
  bool scanning = false;
  bool runtimeLoading = true;
  String? runtimeError;
  int discoveryHandle = 0;
  Timer? discoveryTimer;
  Timer? scanTimer;

  /// True once a scan has run to completion. It is what lets the Nearby surface
  /// tell "nothing found yet" apart from "looked and found nothing".
  bool scanFinished = false;
  String? dataDirectory;
  List<KnownDevice> trustedDevices = const [];
  Map<String, dynamic>? workplaceData;
  int messageHandle = 0;
  Timer? messageTimer;
  Timer? workplaceTimer;
  final Set<String> _incomingOfferDialogs = <String>{};
  final Map<String, int> _transferReceived = <String, int>{};

  /// Preferences. Always non-null: injected by a test, or loaded from disk.
  late AppSettings settings;

  /// Whether the app is currently visible. A notification is only worth raising
  /// when the user is not already looking at the conversation.
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    native = CapsiNative.tryLoad();
    settings = widget.settings ?? AppSettings.inMemory();
    settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(_lifecycle);
    if (widget.autoInitialize) {
      _initializeRuntime();
    } else {
      runtimeLoading = false;
    }
  }

  /// A changed device name has to be re-announced: the beacon is signed once
  /// when discovery starts, so the running listener would keep advertising the
  /// old name until the next launch. Restarting discovery is the only way to
  /// make peers see the new one straight away.
  void _onSettingsChanged() {
    if (!mounted) return;
    _restartDiscovery();
  }

  late final WidgetsBindingObserver _lifecycle = _CapsiLifecycleObserver(this);

  void _restartDiscovery() {
    final bridge = native;
    if (bridge == null || discoveryHandle == 0) return;
    bridge.stopDiscovery(discoveryHandle);
    discoveryTimer?.cancel();
    discoveryTimer = null;
    discoveryHandle = 0;
    _startDiscovery();
  }

  Future<void> _initializeRuntime() async {
    if (mounted) {
      setState(() {
        runtimeLoading = true;
        runtimeError = null;
      });
    }

    try {
      final directory = await getApplicationSupportDirectory();
      if (!mounted) return;
      dataDirectory = directory.path;

      // Preferences are loaded alongside the directory because that is where
      // they live; an injected instance (test) is already resolved.
      if (widget.settings == null) {
        settings = await AppSettings.load();
        settings.addListener(_onSettingsChanged);
      }

      if (native == null) {
        setState(() {
          runtimeLoading = false;
          runtimeError = 'Capsi could not start on this device. Try again.';
        });
        return;
      }

      _loadTrust();
      _loadWorkplace();
      workplaceTimer?.cancel();
      workplaceTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadWorkplace());
      _startDiscovery();
      _startMessages();

      if (mounted) {
        setState(() {
          runtimeLoading = false;
          runtimeError = null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        runtimeLoading = false;
        runtimeError = 'Capsi could not finish starting. Try again.';
      });
    }
  }

  void _stopRuntimeSessions() {
    discoveryTimer?.cancel();
    discoveryTimer = null;
    scanTimer?.cancel();
    scanTimer = null;
    messageTimer?.cancel();
    messageTimer = null;
    workplaceTimer?.cancel();
    workplaceTimer = null;
    final bridge = native;
    if (bridge != null) {
      if (messageHandle != 0) bridge.stopMessageListener(messageHandle);
      if (discoveryHandle != 0) bridge.stopDiscovery(discoveryHandle);
    }
    messageHandle = 0;
    discoveryHandle = 0;
  }

  void _retryRuntime() {
    _stopRuntimeSessions();
    if (mounted) {
      setState(() {
        discoveryHandle = 0;
        messageHandle = 0;
        peers = const [];
        lastMessageEvent = null;
        workplaceData = null;
        scanning = false;
        scanFinished = false;
        runtimeLoading = true;
        runtimeError = null;
      });
    }
    native = CapsiNative.tryLoad();
    _initializeRuntime();
  }

  void _loadWorkplace() {
    final bridge = native;
    final dir = dataDirectory;
    if (bridge == null || dir == null || !mounted) return;
    setState(() => workplaceData = bridge.workplace(dir));
  }

  void _loadTrust() {
    final bridge = native;
    final dir = dataDirectory;
    if (bridge == null || dir == null || !mounted) return;
    setState(() => trustedDevices = bridge.trustList(dir));
  }

  void _startMessages() {
    final bridge = native;
    final dir = dataDirectory;
    if (bridge == null || dir == null) return;
    messageHandle = bridge.startMessageListener(dataDirectory: dir);
    if (messageHandle == 0) return;
    messageTimer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (!mounted) return;
      for (var i = 0; i < 64; i++) {
        final event = bridge.pollMessage(messageHandle);
        if (event == null || event['type'] == null) break;
        _loadTrust();
        _loadWorkplace();
        if (!mounted) return;
        setState(() {
          lastMessageEvent = event;
          final transferId = event['transfer_id']?.toString();
          final received = event['received'];
          final sent = event['sent'];
          if (transferId != null && received is num) {
            _transferReceived[transferId] = received.toInt();
          } else if (transferId != null && sent is num) {
            _transferReceived[transferId] = sent.toInt();
          }
          if (event['type'] == 'file_complete' && transferId != null) {
            final size = event['size'];
            if (size is num) _transferReceived[transferId] = size.toInt();
          }
        });
        if (event['type'] == 'file_offer') {
          _showIncomingFileOffer(event);
        }
        _notifyForEvent(event);
      }
    });
  }

  /// Raise a host notification for an incoming message or file offer.
  ///
  /// Skipped while the app is in the foreground: the user is already looking at
  /// the conversation, and a balloon over the window they are using is noise.
  /// [foreground] is maintained from the app lifecycle observer.
  void _notifyForEvent(Map<String, dynamic> event) {
    if (!settings.notificationsEnabled || _foreground) return;
    final type = event['type']?.toString();
    if (type != 'message' && type != 'file_offer') return;

    final sender = event['device_name']?.toString();
    final who = sender == null || sender.isEmpty ? 'A Capsi device' : sender;
    final body = type == 'file_offer'
        ? '$who wants to send you a file.'
        : '$who sent you a message.';
    postMessageNotification(title: 'Capsi', body: body);
  }

  Future<void> _showIncomingFileOffer(Map<String, dynamic> event) async {
    final transferId = event['transfer_id']?.toString();
    final deviceId = event['device_id']?.toString();
    final fileName = event['file_name']?.toString() ?? 'File';
    final size = event['size'];
    if (transferId == null || deviceId == null || !mounted) return;
    if (!_incomingOfferDialogs.add(transferId)) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Incoming file'),
        content: Text(
          '${event['device_name']?.toString() ?? 'A trusted device'} wants to send $fileName (${_formatBytes(size)}).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    _incomingOfferDialogs.remove(transferId);
    if (!mounted || dataDirectory == null) return;

    final operation = accepted == true ? 'file_accept' : 'file_decline';
    await _nativeJsonInIsolate(dataDirectory!, operation, [deviceId, transferId]);
    if (mounted) setState(() {});
  }

  void _startDiscovery() {
    final bridge = native;
    final dir = dataDirectory;
    if (bridge == null || dir == null) return;
    discoveryHandle = bridge.startDiscovery(
      // The name is re-announced by restarting discovery whenever it changes,
      // because the beacon is signed once when the listener starts.
      deviceName: settings.deviceName,
      dataDirectory: dir,
    );
    if (discoveryHandle == 0) return;
    _pollDiscovery();
    discoveryTimer = Timer.periodic(
      const Duration(milliseconds: 750),
      (_) => _pollDiscovery(),
    );
  }

  void _pollDiscovery() {
    final bridge = native;
    if (bridge == null || discoveryHandle == 0 || !mounted) return;
    setState(() => peers = bridge.pollDiscovery(discoveryHandle));
  }

  void _scan() {
    if (!mounted || native == null || dataDirectory == null) return;
    if (discoveryHandle == 0) {
      _startDiscovery();
      if (discoveryHandle == 0) {
        _showScanMessage('Discovery could not start on this device.');
        return;
      }
    }
    scanTimer?.cancel();
    setState(() {
      scanning = true;
      scanFinished = false;
    });
    scanTimer = Timer(_scanWindow, _finishScan);
  }

  void _finishScan() {
    if (!mounted) return;
    // Poll once more before reporting, so the count is what this scan turned up
    // rather than whatever the last background tick happened to hold.
    _pollDiscovery();
    final found = peers.length;
    setState(() {
      scanning = false;
      scanFinished = true;
    });
    _showScanMessage(
      found == 0
          ? 'No Capsi devices found. Make sure the other device has Capsi open on the same network.'
          : 'Found $found device${found == 1 ? '' : 's'}.',
    );
  }

  void _showScanMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycle);
    settings.removeListener(_onSettingsChanged);
    _stopRuntimeSessions();
    super.dispose();
  }

  /// How long a scan stays open before it reports a result.
  ///
  /// Peers announce as soon as they start and then every five seconds, so a
  /// shorter window could miss a device that had announced just before the
  /// button was pressed, which would look like the scan being broken.
  static const Duration _scanWindow = Duration(seconds: 6);

  static const pages = <({IconData icon, String label})>[
    (icon: Icons.radar_outlined, label: 'Nearby'),
    (icon: Icons.workspaces_outlined, label: 'Workplace'),
    (icon: Icons.chat_bubble_outline, label: 'Messages'),
    (icon: Icons.folder_outlined, label: 'Files'),
    (icon: Icons.verified_user_outlined, label: 'Trusted devices'),
  ];

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  void _showSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _SettingsDialog(
        native: native,
        dataDirectory: dataDirectory,
        trustedDeviceCount: trustedDevices.length,
        settings: settings,
        // Settings is a dialog over whichever page was open, so its trusted
        // devices row closes the dialog and moves the shell to that page rather
        // than stacking a second dialog on top of the first.
        onOpenTrustedDevices: _openTrustedDevicesPage,
      ),
    );
  }

  /// Show the full trusted devices list, which is a page of its own.
  void _openTrustedDevicesPage() {
    final index = pages.indexWhere((page) => page.label == 'Trusted devices');
    if (index >= 0) setState(() => selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final page = pages[selected];
    final body = _PageBody(
      label: page.label,
      peers: peers,
      scanning: scanning,
      scanFinished: scanFinished,
      native: native,
      onScan: _scan,
      trustedDevices: trustedDevices,
      onTrustChanged: () { _loadTrust(); _loadWorkplace(); },
      dataDirectory: dataDirectory,
      workplaceData: workplaceData,
    );

    if (runtimeLoading || runtimeError != null) {
      return _RuntimeGate(
        loading: runtimeLoading,
        error: runtimeError,
        onRetry: _retryRuntime,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Scaffold(
          body: compact
              ? Column(
                  children: [
                    Expanded(child: _DesktopContent(page: page, body: body, native: native, onSettings: () => _showSettings(context))),
                    NavigationBar(
                      selectedIndex: selected,
                      onDestinationSelected: (index) => setState(() => selected = index),
                      destinations: [
                        for (final item in pages)
                          NavigationDestination(icon: Icon(item.icon), selectedIcon: Icon(item.icon), label: item.label),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    NavigationRail(
                      selectedIndex: selected,
                      onDestinationSelected: (index) => setState(() => selected = index),
                      backgroundColor: const Color(0xFF0E1112),
                      labelType: NavigationRailLabelType.all,
                      leading: const Padding(
                        padding: EdgeInsets.only(top: 18, bottom: 28),
                        child: _CapsiMark(),
                      ),
                      destinations: [
                        for (final item in pages)
                          NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.icon),
                            label: Text(item.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _DesktopContent(page: page, body: body, native: native, onSettings: () => _showSettings(context))),
                  ],
                ),
        );
      },
    );
  }
}

class _RuntimeGate extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  const _RuntimeGate({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B0C),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/capsi-logo-512.png',
                  width: 88,
                  height: 88,
                ),
                const SizedBox(height: 24),
                if (loading) ...[
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Starting Capsi',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'Getting things ready…',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF858D88)),
                  ),
                ] else ...[
                  Text(
                    'Capsi could not start',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error ?? 'Capsi is not ready yet.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF858D88),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopContent extends StatelessWidget {
  final ({IconData icon, String label}) page;
  final Widget body;
  final CapsiNative? native;
  final VoidCallback? onSettings;

  const _DesktopContent({required this.page, required this.body, required this.native, this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(page.icon, size: 20, color: const Color(0xFF7ED957)),
                      const SizedBox(width: 10),
                      Text(page.label, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NetworkStatus(available: native != null),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: onSettings == null ? null : () => onSettings!(),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyPanel({required this.icon, required this.title, required this.message});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(34),
      child: Column(children: [
        Icon(icon, size: 34, color: const Color(0xFF7ED957)),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF858D88), height: 1.5)),
      ]),
    ),
  );
}

/// The Nearby surface while a scan is still running.
///
/// A scan stays open for a few seconds, so it needs something on screen other
/// than the same "no devices found" card a finished scan shows.
class _ScanningPanel extends StatelessWidget {
  const _ScanningPanel();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(34),
      child: Column(children: [
        SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        SizedBox(height: 16),
        Text('Scanning for devices…', style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 7),
        Text(
          'Looking for other Capsi devices on this network.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF858D88), height: 1.5),
        ),
      ]),
    ),
  );
}

class _DeviceIcon extends StatelessWidget {
  final IconData icon;
  const _DeviceIcon({required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    width: 42, height: 42,
    decoration: BoxDecoration(color: const Color(0x187ED957), border: Border.all(color: const Color(0x307ED957)), borderRadius: BorderRadius.circular(11)),
    child: Icon(icon, size: 21, color: const Color(0xFF7ED957)),
  );
}

class _CapsiMark extends StatelessWidget {
  const _CapsiMark();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Capsi',
      child: Image.asset(
        'assets/capsi-logo-512.png',
        width: 42,
        height: 42,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _SettingsDialog extends StatelessWidget {
  final CapsiNative? native;
  final String? dataDirectory;
  final int trustedDeviceCount;
  final AppSettings settings;

  /// Closes this dialog and moves the shell to the trusted devices page.
  final VoidCallback onOpenTrustedDevices;

  const _SettingsDialog({
    required this.native,
    required this.dataDirectory,
    required this.trustedDeviceCount,
    required this.settings,
    required this.onOpenTrustedDevices,
  });

  @override
  Widget build(BuildContext context) {
    final version = native?.runtimeVersion ?? capsiVersionFallback;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings_outlined),
          const SizedBox(width: 10),
          const Expanded(child: Text('Settings')),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SettingsSection(
                title: 'Device',
                children: [
                  _DeviceNameRow(settings: settings),
                  _SettingsRow(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    subtitle: 'Show a notification when a message or file arrives.',
                    trailing: Switch(
                      value: settings.notificationsEnabled,
                      onChanged: (value) {
                        settings.setNotificationsEnabled(value);
                        _syncNotificationPreference(context, value);
                      },
                    ),
                  ),
                  // Only Windows has a tray; offering it elsewhere would be a
                  // switch that silently does nothing.
                  if (_traySupported)
                    _SettingsRow(
                      icon: Icons.alternate_email,
                      title: 'Keep running in the system tray',
                      subtitle: 'Closing the window keeps Capsi listening in the notification area.',
                      trailing: Switch(
                        value: settings.minimizeToTray,
                        onChanged: settings.setMinimizeToTray,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: 'Connection',
                children: [
                  // One status row rather than three repeating the same
                  // ready/not-ready answer about the same native bridge.
                  _SettingsRow(
                    icon: native == null ? Icons.error_outline : Icons.check_circle_outline,
                    title: native == null ? 'Capsi is not ready' : 'Capsi is ready to connect',
                    subtitle: native == null
                        ? 'The native runtime did not load on this device.'
                        : 'Devices, discovery and messages are available.',
                    iconColor: native == null ? Colors.orange : const Color(0xFF7ED957),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: 'Privacy & devices',
                children: [
                  _SettingsRow(
                    icon: Icons.verified_user_outlined,
                    title: 'Trusted devices',
                    subtitle: '$trustedDeviceCount trusted device${trustedDeviceCount == 1 ? '' : 's'}',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // The list itself is a page of the shell, not part of this
                      // dialog, so the row hands the user over to it.
                      Navigator.of(context).pop();
                      onOpenTrustedDevices();
                    },
                  ),
                  const _SettingsRow(
                    icon: Icons.lock_outline,
                    title: 'Trust model',
                    subtitle: 'Choose which devices can communicate with you.',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: 'Storage',
                children: [
                  _SettingsRow(
                    icon: Icons.folder_outlined,
                    title: 'Capsi data',
                    subtitle: dataDirectory ?? 'Data folder is unavailable.',
                    onTap: dataDirectory == null
                        ? null
                        : () => _openDataFolder(context, dataDirectory!),
                    trailing: dataDirectory == null
                        ? const Icon(Icons.error_outline)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_dataFolderIsOpenable)
                                IconButton(
                                  tooltip: 'Open folder',
                                  onPressed: () => _openDataFolder(context, dataDirectory!),
                                  icon: const Icon(Icons.folder_open_outlined),
                                ),
                              IconButton(
                                tooltip: 'Copy path',
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: dataDirectory!));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Data folder path copied.')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy_outlined),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: 'Appearance',
                children: const [
                  _SettingsRow(
                    icon: Icons.dark_mode_outlined,
                    title: 'Theme',
                    subtitle: 'Dark',
                    trailing: Text('Current', style: TextStyle(color: Color(0xFF858D88))),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SettingsSection(
                title: 'About',
                children: [
                  // Version, publisher and website all live in the About dialog,
                  // so they are listed once here rather than shown twice.
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Capsi'),
                    subtitle: const Text('Messages and files, device to device.'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('v$version', style: const TextStyle(color: Color(0xFF858D88))),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _AboutDialog(native: native),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Editable row for the name this device advertises to its peers.
///
/// The name is the only part of a device a user can change, and peers identify
/// it by that name, so it is edited inline rather than behind a dialog.
/// Tracks whether the app is visible, which decides if an incoming message
/// warrants a notification.
///
/// Kept as a separate observer rather than inline in the state so the state class
/// stays focused on the message session.
class _CapsiLifecycleObserver extends WidgetsBindingObserver {
  _CapsiLifecycleObserver(this._state);

  final _CapsiHomeState _state;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state._foreground = state == AppLifecycleState.resumed;
  }
}

class _DeviceNameRow extends StatefulWidget {
  final AppSettings settings;

  const _DeviceNameRow({required this.settings});

  @override
  State<_DeviceNameRow> createState() => _DeviceNameRowState();
}

class _DeviceNameRowState extends State<_DeviceNameRow> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.settings.deviceName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final error = widget.settings.setDeviceName(_controller.text);
    setState(() => _error = error);
    if (error == null) {
      // Show what was actually stored, which is the trimmed value.
      _controller.text = widget.settings.deviceName;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device name updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Icon(Icons.badge_outlined),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Device name'),
                const SizedBox(height: 2),
                Text(
                  'Other devices on your network see this name.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF858D88)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  maxLength: AppSettings.maxDeviceNameLength,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 26),
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
    );
  }
}

/// Method channel to the host for the two things Flutter cannot draw itself:
/// a Windows tray icon and a desktop/mobile notification.
///
/// Both are host concerns - `Shell_NotifyIcon` on Windows, `NotificationManager`
/// on Android - so the Dart side asks for them and never has to know which
/// platform answered.
const MethodChannel capsiPlatformChannel = MethodChannel('win.capsi.app/platform');

/// True only where a system tray actually exists. Offering a tray switch on a
/// phone would be a control that silently does nothing.
bool get _traySupported => Platform.isWindows;

/// Asks the host to raise a notification for an incoming message or file.
///
/// Returns false when the host has no notification support or the user turned
/// notifications off, so the caller never has to branch on platform itself.
Future<bool> postMessageNotification({
  required String title,
  required String body,
}) async {
  if (!Platform.isWindows && !Platform.isAndroid) return false;
  try {
    final ok = await capsiPlatformChannel.invokeMethod<bool>('notify', {
      'title': title,
      'body': body,
    });
    return ok ?? false;
  } on MissingPluginException {
    // An older host build (or a platform without the channel) simply cannot
    // notify; that is not an error worth surfacing to the user.
    return false;
  } catch (_) {
    return false;
  }
}

/// Tells the host whether the window should minimise to the tray on close, and
/// asks it to (re)draw the tray icon when [enabled] turns on.
Future<void> _syncNotificationPreference(BuildContext context, bool enabled) async {
  if (!Platform.isWindows && !Platform.isAndroid) return;
  try {
    await capsiPlatformChannel.invokeMethod<void>('setNotificationsEnabled', enabled);
  } catch (_) {
    // The preference is still stored, so it applies on the next launch.
  }
}

/// Keeps [text] in sync with a settings field that lives on this widget.
class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 7),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: Color(0xFF858D88),
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(children: children),
            ),
          ),
        ],
      );
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 3),
        leading: Icon(icon, color: iconColor ?? const Color(0xFF7ED957)),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(subtitle, style: const TextStyle(color: Color(0xFF858D88))),
        ),
        trailing: trailing,
        onTap: onTap,
      );
}

class _AboutDialog extends StatelessWidget {
  final CapsiNative? native;

  const _AboutDialog({required this.native});

  @override
  Widget build(BuildContext context) {
    final version = native?.runtimeVersion ?? capsiVersionFallback;

    return AlertDialog(
      title: Row(
        children: [
          Image.asset('assets/capsi-logo-512.png', width: 38, height: 38),
          const SizedBox(width: 12),
          const Text('About Capsi'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Messages and files, device to device.',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 12),
            Text(
              'Capsi is a lightweight communication utility built around direct device-to-device exchange. It does not require a Capsi cloud account or Internet service for local communication.',
              style: TextStyle(height: 1.5, color: Color(0xFF9AA19C)),
            ),
            SizedBox(height: 18),
            Text('Version $version', style: const TextStyle(color: Color(0xFF858D88))),
            const SizedBox(height: 4),
            Text('Published by $capsiPublisher', style: const TextStyle(color: Color(0xFF858D88))),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => _openExternalLink(context, capsiWebsite),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(capsiWebsite),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _NetworkStatus extends StatelessWidget {
  final bool available;
  const _NetworkStatus({required this.available});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF111516),
        border: Border.all(color: const Color(0x18FFFFFF)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: available ? const Color(0xFF7ED957) : Colors.orange),
          const SizedBox(width: 7),
          Text(available ? 'Ready' : 'Unavailable', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _PageBody extends StatefulWidget {
  final String label;
  final List<CapsiPeer> peers;
  final bool scanning;
  final bool scanFinished;
  final CapsiNative? native;
  final VoidCallback onScan;
  final List<KnownDevice> trustedDevices;
  final VoidCallback onTrustChanged;
  final String? dataDirectory;
  final Map<String, dynamic>? workplaceData;
  const _PageBody({required this.label, required this.peers, required this.scanning, required this.scanFinished, required this.native, required this.onScan, required this.trustedDevices, required this.onTrustChanged, required this.dataDirectory, required this.workplaceData});

  @override
  State<_PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<_PageBody> {
  String? selectedDevice;
  String draft = '';
  String? selectedWorkplaceGroup;
  String workplaceDraft = '';
  final TextEditingController workplaceController = TextEditingController();

  @override
  void dispose() {
    workplaceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.label == 'Workplace') return _workplace(context);

    if (widget.label == 'Trusted devices') {
      return ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Text('Trusted devices', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Only devices you accept are allowed to exchange messages and files.'),
          const SizedBox(height: 20),
          if (widget.trustedDevices.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('Accept a device from Nearby to allow messages and file sharing.')))
          else
            for (final device in widget.trustedDevices)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(device.displayName),
                  subtitle: Text(device.fingerprint.isEmpty ? 'Fingerprint unavailable' : device.fingerprint),
                  trailing: widget.native == null || widget.dataDirectory == null
                      ? null
                      : IconButton(
                          tooltip: 'Remove trusted device',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _confirmRemoveTrustedDevice(context, device),
                        ),
                ),
              ),
        ],
      );
    }
    if (widget.label == 'Messages') return _messages(context);
    if (widget.label == 'Files') return _files(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 40),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Nearby devices', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Find nearby Capsi devices and choose who you want to communicate with.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF9AA19C))),
            ])),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: widget.scanning ? null : widget.onScan,
              icon: widget.scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar_outlined),
              label: Text(widget.scanning ? 'Scanning…' : 'Scan'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (widget.scanning && widget.peers.isEmpty)
          const _ScanningPanel()
        else if (widget.peers.isEmpty)
          _EmptyPanel(
            icon: Icons.radar_outlined,
            title: 'No devices found',
            message: widget.scanFinished
                ? 'Nothing answered this scan. Check that the other device is on the same network, has Capsi open, and is not blocked by a firewall.'
                : 'Make sure the other device is running Capsi and both devices can communicate directly.',
          )
        else
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth > 1050 ? 2 : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 112,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: widget.peers.length,
              itemBuilder: (_, index) {
                final peer = widget.peers[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      _DeviceIcon(icon: Icons.computer_outlined),
                      const SizedBox(width: 13),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(peer.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(peer.fingerprint.isEmpty ? peer.tcpAddress : peer.fingerprint, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF747C77))),
                      ])),
                      if (widget.dataDirectory != null)
                        FilledButton(
                          onPressed: () {
                            final accepted = widget.native?.acceptTrust(widget.dataDirectory!, peer.deviceId);
                            if (accepted != null) widget.onTrustChanged();
                          },
                          child: const Text('Accept'),
                        ),
                    ]),
                  ),
                );
              },
            );
          }),
        const SizedBox(height: 28),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.security_outlined, size: 18, color: Color(0xFF7ED957)),
          const SizedBox(width: 9),
          Expanded(child: Text('Trusted devices let you choose who can communicate with you.', style: Theme.of(context).textTheme.bodySmall)),
        ]),
        const SizedBox(height: 8),
        Text(widget.native == null ? 'Capsi is not ready on this device yet.' : 'Capsi is ready to connect and communicate.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF606863))),
      ],
    );
  }

  Widget _workplace(BuildContext context) {
    final workspace = widget.workplaceData;
    if (workspace == null) {
      return Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Card(child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.workspaces_outlined, size: 54),
            const SizedBox(height: 20),
            Text('Create your Workplace', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            const Text('A shared space for your people and groups. Create groups, organize people, share messages and send announcements locally.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: widget.dataDirectory == null || widget.native == null ? null : () => _createWorkplace(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Workplace'),
            ),
          ]),
        )),
      ));
    }

    final members = (workspace['members'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    final groups = (workspace['groups'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    final departments = (workspace['departments'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    final broadcasts = (workspace['broadcasts'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    final messages = (workspace['messages'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];

    final effectiveGroupId = groups.isEmpty
        ? null
        : (selectedWorkplaceGroup != null && groups.any((g) => g['id']?.toString() == selectedWorkplaceGroup)
            ? selectedWorkplaceGroup
            : groups.first['id']?.toString());
    final group = groups.cast<Map<String, dynamic>?>().firstWhere(
      (g) => g?['id']?.toString() == effectiveGroupId,
      orElse: () => null,
    );
    final groupId = group?['id']?.toString();
    final groupMessages = groupId == null
        ? const <Map<String, dynamic>>[]
        : messages.where((m) => m['group_id']?.toString() == groupId).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;

        Widget groupList() => Card(
          margin: EdgeInsets.only(left: compact ? 16 : 28, right: compact ? 16 : 12, bottom: compact ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(children: [
                  Text('Groups', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text(groups.length.toString(), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: groups.isEmpty
                    ? const Center(child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Create a group to start communicating.', textAlign: TextAlign.center),
                      ))
                    : ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (final item in groups)
                            ListTile(
                              selected: item['id']?.toString() == groupId,
                              leading: const Icon(Icons.group_outlined),
                              title: Text(item['name']?.toString() ?? 'Group', maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${(item['member_ids'] as List?)?.length ?? 0} members'),
                              onTap: () => setState(() {
                                selectedWorkplaceGroup = item['id']?.toString();
                                workplaceDraft = '';
                                workplaceController.clear();
                              }),
                              trailing: _canManageGroups(workspace)
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Manage members',
                                          icon: const Icon(Icons.manage_accounts_outlined),
                                          onPressed: () => _manageGroupMembers(context, item, members, groups),
                                        ),
                                        IconButton(
                                          tooltip: 'Add member',
                                          icon: const Icon(Icons.person_add_alt_1_outlined),
                                          onPressed: () => _addWorkplaceMember(context, item, members),
                                        ),
                                      ],
                                    )
                                  : IconButton(
                                      tooltip: 'Add member',
                                      icon: const Icon(Icons.person_add_alt_1_outlined),
                                      onPressed: () => _addWorkplaceMember(context, item, members),
                                    ),
                            ),
                        ],
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('People ${members.length}', style: Theme.of(context).textTheme.bodySmall),
              ),
              if (_canManageMembers(workspace))
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 14, 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _manageAllMembers(context, workspace, members),
                      icon: const Icon(Icons.shield_outlined, size: 16),
                      label: const Text('Manage people'),
                    ),
                  ),
                ),
            ],
          ),
        );

        Widget conversation() => Card(
          margin: EdgeInsets.only(left: compact ? 16 : 0, right: compact ? 16 : 28, bottom: 20),
          child: group == null
              ? const Center(child: Text('Select a group to view the conversation.'))
              : Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.group_outlined),
                      title: Text(group['name']?.toString() ?? 'Group'),
                      subtitle: Text('${(group['member_ids'] as List?)?.length ?? 0} members'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_canManageGroups(workspace))
                            IconButton(
                              tooltip: 'Manage members',
                              icon: const Icon(Icons.manage_accounts_outlined),
                              onPressed: () => _manageGroupMembers(context, group, members, groups),
                            ),
                          IconButton(
                            tooltip: 'Add member',
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            onPressed: () => _addWorkplaceMember(context, group, members),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: groupMessages.isEmpty
                          ? const Center(child: Text('No messages here yet.'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(20),
                              itemCount: groupMessages.length,
                              itemBuilder: (_, index) {
                                final message = groupMessages[index];
                                final senderId = message['sender_device_id']?.toString();
                                final sender = members.cast<Map<String, dynamic>?>().firstWhere(
                                  (m) => m?['device_id']?.toString() == senderId,
                                  orElse: () => null,
                                );
                                final outgoing = senderId != null && senderId == _localWorkplaceMemberId(workspace);
                                return Align(
                                  alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 560),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (!outgoing)
                                              Text(sender?['display_name']?.toString() ?? 'Member', style: Theme.of(context).textTheme.labelSmall),
                                            const SizedBox(height: 4),
                                            Text(message['body']?.toString() ?? ''),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: workplaceController,
                            minLines: 1,
                            maxLines: 4,
                            onChanged: (value) => workplaceDraft = value,
                            onSubmitted: (_) => _sendWorkplaceMessage(),
                            decoration: const InputDecoration(hintText: 'Write a message to this group', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _sendWorkplaceMessage,
                          child: const Icon(Icons.send),
                        ),
                      ]),
                    ),
                  ],
                ),
        );

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 0, compact ? 16 : 28, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(workspace['name']?.toString() ?? 'Workplace', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text('${members.length} people · ${groups.length} groups · ${departments.length} departments'),
                      ],
                    ),
                  ),
                  if (!compact)
                    OutlinedButton.icon(
                      onPressed: widget.native == null || widget.dataDirectory == null
                          ? null
                          : () => _createWorkplaceName(
                              context,
                              'Create group',
                              'workplace_group',
                            ),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Group'),
                    ),
                  if (!compact) const SizedBox(width: 8),
                  if (!compact)
                    OutlinedButton.icon(
                      onPressed: widget.native == null || widget.dataDirectory == null ? null : () => _createBroadcast(context),
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('Broadcast'),
                    ),
                  if (!compact && _canManageDepartments(workspace)) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: widget.native == null || widget.dataDirectory == null
                          ? null
                          : () => _createWorkplaceName(
                              context,
                              'Create department',
                              'workplace_department',
                            ),
                      icon: const Icon(Icons.apartment_outlined),
                      label: const Text('Department'),
                    ),
                  ],
                  IconButton(onPressed: widget.onTrustChanged, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
                  // Only the owner carries ManageWorkspace in the core, so the
                  // rename/delete entry point is hidden from everyone else.
                  if (_isWorkplaceOwner(workspace)) ...[
                    if (!compact) const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'Workplace settings',
                      onSelected: (value) {
                        if (value == 'rename') {
                          _renameWorkplace(context, workspace);
                        } else {
                          _deleteWorkplace(context, workspace);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Rename workplace'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Delete workplace'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                  if (compact)
                    PopupMenuButton<String>(
                      tooltip: 'Workplace actions',
                      enabled: widget.native != null && widget.dataDirectory != null,
                      onSelected: (value) {
                        if (value == 'group') {
                          _createWorkplaceName(
                            context,
                            'Create group',
                            'workplace_group',
                          );
                        } else if (value == 'broadcast') {
                          _createBroadcast(context);
                        } else if (value == 'department') {
                          _createWorkplaceName(
                            context,
                            'Create department',
                            'workplace_department',
                          );
                        } else if (value == 'rename') {
                          _renameWorkplace(context, workspace);
                        } else if (value == 'delete') {
                          _deleteWorkplace(context, workspace);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'group', child: Text('Create group')),
                        const PopupMenuItem(value: 'broadcast', child: Text('Create broadcast')),
                        if (_canManageDepartments(workspace))
                          const PopupMenuItem(value: 'department', child: Text('Create department')),
                        if (_isWorkplaceOwner(workspace)) ...[
                          const PopupMenuDivider(),
                          const PopupMenuItem(value: 'rename', child: Text('Rename workplace')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete workplace')),
                        ],
                      ],
                      icon: const Icon(Icons.more_horiz),
                    ),
                ],
              ),
            ),
            if (departments.isNotEmpty || broadcasts.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 0, compact ? 16 : 28, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (departments.isNotEmpty)
                        Chip(
                          avatar: const Icon(Icons.apartment_outlined, size: 17),
                          label: Text('${departments.length} departments'),
                        ),
                      if (broadcasts.isNotEmpty)
                        Chip(
                          avatar: const Icon(Icons.campaign_outlined, size: 17),
                          label: Text('${broadcasts.length} broadcasts'),
                        ),
                    ],
                  ),
                ),
              ),
            if (compact) ...[
              SizedBox(height: 92, child: groupList()),
              Expanded(child: conversation()),
            ] else
              Expanded(
                child: Row(
                  children: [
                    SizedBox(width: 290, child: groupList()),
                    Expanded(child: conversation()),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String? _localWorkplaceMemberId(Map<String, dynamic> workspace) {
    final id = workspace['local_device_id']?.toString();
    return id == null || id.isEmpty ? null : id;
  }

  /// The role this device holds in the workplace, or null when it is not a
  /// member. Mirrors `Workspace::permissions_for` so the UI can hide actions
  /// the native layer would refuse anyway.
  String? _localWorkplaceRole(Map<String, dynamic> workspace) {
    final localId = _localWorkplaceMemberId(workspace);
    if (localId == null) return null;
    final members = (workspace['members'] as List?)?.whereType<Map<String, dynamic>>() ?? const [];
    final role = members
        .cast<Map<String, dynamic>?>()
        .firstWhere((m) => m?['device_id']?.toString() == localId, orElse: () => null)?['role']
        ?.toString()
        .split('.')
        .last;
    return role == null || role.isEmpty ? null : role;
  }

  /// Only the owner may rename or delete the workplace.
  bool _isWorkplaceOwner(Map<String, dynamic> workspace) => _localWorkplaceRole(workspace) == 'Owner';

  /// Owner, admin and manager roles all carry `ManageGroups` in the core.
  bool _canManageGroups(Map<String, dynamic> workspace) {
    final role = _localWorkplaceRole(workspace);
    return role == 'Owner' || role == 'Admin' || role == 'Manager';
  }

  /// `ManageDepartments` is held by owner and admin only.
  bool _canManageDepartments(Map<String, dynamic> workspace) {
    final role = _localWorkplaceRole(workspace);
    return role == 'Owner' || role == 'Admin';
  }

  /// `ManageMembers` is held by owner and admin. Role changes ride on the same
  /// permission as removing a member, so the two appear together.
  bool _canManageMembers(Map<String, dynamic> workspace) {
    final role = _localWorkplaceRole(workspace);
    return role == 'Owner' || role == 'Admin';
  }

  /// The roles this device is allowed to hand out, mirroring
  /// `Role::assignable_roles` so the list never offers something the core
  /// rejects. Ownership is absent by design: it is not assignable here.
  List<String> _assignableRoles(Map<String, dynamic> workspace) {
    final role = _localWorkplaceRole(workspace);
    // Only the owner may mint an admin; an admin may delegate manager/member.
    if (role == 'Owner') return const ['Admin', 'Manager', 'Member'];
    if (role == 'Admin') return const ['Manager', 'Member'];
    return const [];
  }

  Future<void> _sendWorkplaceMessage() async {
    final data = widget.dataDirectory;
    final native = widget.native;
    final text = workplaceController.text.trim();
    final workspace = widget.workplaceData;
    final groups = (workspace?['groups'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    final groupId = selectedWorkplaceGroup != null && groups.any((g) => g['id']?.toString() == selectedWorkplaceGroup)
        ? selectedWorkplaceGroup
        : (groups.isEmpty ? null : groups.first['id']?.toString());
    if (data == null || native == null || groupId == null || text.isEmpty) return;
    final result = await _nativeJsonInIsolate(data, 'workplace_send', [groupId, text]);
    if (!mounted) return;
    if (result != null && result['error'] == null) {
      setState(() {
        workplaceDraft = '';
        workplaceController.clear();
      });
      widget.onTrustChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result?['error']?.toString() ?? 'Message could not be sent.')),
      );
    }
  }

  /// Owner-only. Renames the workplace and pushes the new state to members.
  Future<void> _renameWorkplace(BuildContext context, Map<String, dynamic> workspace) async {
    final controller = TextEditingController(text: workspace['name']?.toString() ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Workplace'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty || widget.native == null || widget.dataDirectory == null) return;
    await _runWorkplaceAction('workplace_rename', [name], 'Workplace could not be renamed.');
  }

  Future<void> _setMemberRole(
    Map<String, dynamic> member,
    String role,
  ) async {
    await _runWorkplaceAction(
      'workplace_set_role',
      [member['device_id']?.toString() ?? '', role],
      'Role could not be changed.',
    );
  }

  /// Lists every member with the roles this device may grant, so an owner can
  /// promote and demote without going group by group.
  Future<void> _manageAllMembers(
    BuildContext context,
    Map<String, dynamic> workspace,
    List<Map<String, dynamic>> members,
  ) async {
    final assignable = _assignableRoles(workspace);
    final localId = _localWorkplaceMemberId(workspace);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('People'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final member in members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    member['display_name']?.toString().isNotEmpty == true
                        ? member['display_name'].toString()
                        : 'Unnamed device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(member['role']?.toString().split('.').last ?? 'Member'),
                  trailing: _roleTrailing(
                    member,
                    assignable,
                    isSelf: member['device_id']?.toString() == localId,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  /// The role control for one row. The owner row has no control at all, and a
  /// member's current role is left out of the list so the menu never offers a
  /// change that would do nothing.
  Widget? _roleTrailing(Map<String, dynamic> member, List<String> assignable, {required bool isSelf}) {
    final current = member['role']?.toString().split('.').last ?? 'Member';
    // Ownership is not assignable through this screen, and nobody may edit
    // their own role here.
    if (current == 'Owner' || isSelf) return null;
    final choices = assignable.where((role) => role != current).toList();
    if (choices.isEmpty) return null;

    return PopupMenuButton<String>(
      tooltip: 'Change role',
      onSelected: (role) => _setMemberRole(member, role),
      itemBuilder: (_) => [
        for (final role in choices)
          PopupMenuItem(value: role, child: Text('Make $role')),
      ],
      icon: const Icon(Icons.shield_outlined),
    );
  }

  /// Runs a workplace mutation and reports the outcome on a single snackbar.
  Future<void> _runWorkplaceAction(String operation, List<String> args, String failure) async {
    final data = widget.dataDirectory;
    if (data == null || widget.native == null) return;
    final result = await _nativeJsonInIsolate(data, operation, args);
    if (!mounted) return;
    if (result != null && result['error'] == null) {
      widget.onTrustChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result?['error']?.toString() ?? failure)),
      );
    }
  }

  /// Owner-only. Warns that every member loses the workplace, then deletes it
  /// locally and tells the trusted members to drop their copy.
  Future<void> _deleteWorkplace(BuildContext context, Map<String, dynamic> workspace) async {
    final memberCount = (workspace['members'] as List?)?.length ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Workplace'),
        content: Text(
          memberCount <= 1
              ? 'This workplace will be removed from this device. This cannot be undone.'
              : 'This workplace will be removed from this device and from $memberCount '
                  'members. Their messages and groups go with it. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || widget.native == null || widget.dataDirectory == null) return;

    final result = await _nativeJsonInIsolate(widget.dataDirectory!, 'workplace_delete', const []);
    if (!mounted) return;
    if (result != null && result['error'] == null) {
      // The selected group is gone with the workplace; dropping it here avoids
      // a stale selection flashing before the next poll lands.
      setState(() => selectedWorkplaceGroup = null);
      widget.onTrustChanged();
      ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Workplace deleted.')));
    } else {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(result?['error']?.toString() ?? 'Workplace could not be deleted.')),
      );
    }
  }

  /// Shows the members of [group] with per-member move and remove actions.
  Future<void> _manageGroupMembers(
    BuildContext context,
    Map<String, dynamic> group,
    List<Map<String, dynamic>> members,
    List<Map<String, dynamic>> groups,
  ) async {
    final groupId = group['id']?.toString() ?? '';
    final memberIds = (group['member_ids'] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
    final inGroup = members.where((m) => memberIds.contains(m['device_id']?.toString())).toList();
    final otherGroups = groups.where((g) => g['id']?.toString() != groupId).toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Members of ${group['name']?.toString() ?? 'group'}'),
        content: SizedBox(
          width: 460,
          child: inGroup.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('This group has no members yet.')),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final member in inGroup)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(
                          member['display_name']?.toString().isNotEmpty == true
                              ? member['display_name'].toString()
                              : 'Unnamed device',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(member['role']?.toString().split('.').last ?? 'Member'),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Manage member',
                          onSelected: (value) {
                            Navigator.pop(dialogContext);
                            if (value == 'remove') {
                              _removeGroupMember(group, member);
                            } else {
                              _moveGroupMember(group, member, otherGroups);
                            }
                          },
                          itemBuilder: (_) => [
                            if (otherGroups.isNotEmpty)
                              const PopupMenuItem(value: 'move', child: Text('Move to another group')),
                            const PopupMenuItem(value: 'remove', child: Text('Remove from group')),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _removeGroupMember(Map<String, dynamic> group, Map<String, dynamic> member) async {
    await _runWorkplaceAction(
      'workplace_remove_member',
      [group['id']?.toString() ?? '', member['device_id']?.toString() ?? ''],
      'Member could not be removed.',
    );
  }

  Future<void> _moveGroupMember(
    Map<String, dynamic> group,
    Map<String, dynamic> member,
    List<Map<String, dynamic>> groups,
  ) async {
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a second group before moving a member.')),
      );
      return;
    }
    String? targetId;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move to group'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final target in groups)
                ListTile(
                  leading: const Icon(Icons.group_outlined),
                  title: Text(target['name']?.toString() ?? 'Group'),
                  onTap: () {
                    targetId = target['id']?.toString();
                    Navigator.pop(dialogContext);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        ],
      ),
    );
    if (!mounted || targetId == null) return;
    await _runWorkplaceAction(
      'workplace_move_member',
      [
        group['id']?.toString() ?? '',
        targetId!,
        member['device_id']?.toString() ?? '',
      ],
      'Member could not be moved.',
    );
  }

  Future<void> _addWorkplaceMember(
    BuildContext context,
    Map<String, dynamic> group,
    List<Map<String, dynamic>> members,
  ) async {
    final current = (group['member_ids'] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
    final available = members.where((member) => !current.contains(member['device_id']?.toString())).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All Workplace members are already in this group.')));
      return;
    }
    Map<String, dynamic>? chosen;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add member to ${group['name']?.toString() ?? 'group'}'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final member in available)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(member['display_name']?.toString().isNotEmpty == true ? member['display_name'].toString() : 'Unnamed device'),
                  subtitle: Text(member['role']?.toString().split('.').last ?? 'Member'),
                  onTap: () {
                    chosen = member;
                    Navigator.pop(dialogContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || chosen == null || widget.native == null || widget.dataDirectory == null) return;
    final result = await _nativeJsonInIsolate(
      widget.dataDirectory!,
      'workplace_add_member',
      [
        group['id']?.toString() ?? '',
        chosen!['device_id']?.toString() ?? '',
      ],
    );
    if (!mounted) return;
    if (result != null && result['error'] == null) {
      widget.onTrustChanged();
    } else {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(result?['error']?.toString() ?? 'Member could not be added.')),
      );
    }
  }

  Future<void> _createWorkplaceName(
    BuildContext context,
    String title,
    String operation,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) return;
    final data = widget.dataDirectory;
    if (data == null) return;
    final result = await _nativeJsonInIsolate(data, operation, [name]);
    if (!mounted) return;
    if (result != null && result['error'] == null) {
      widget.onTrustChanged();
    } else {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(result?['error']?.toString() ?? 'Workplace change could not be completed.')),
      );
    }
  }

  Future<void> _createBroadcast(BuildContext context) async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    final values = await showDialog<({String title, String body})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create broadcast'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, autofocus: true, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 12),
              TextField(controller: bodyController, maxLines: 4, decoration: const InputDecoration(labelText: 'Message')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (title: titleController.text.trim(), body: bodyController.text.trim())),
            child: const Text('Broadcast'),
          ),
        ],
      ),
    );
    titleController.dispose();
    bodyController.dispose();
    if (!mounted || values == null || values.title.isEmpty || values.body.isEmpty || widget.native == null || widget.dataDirectory == null) return;
    final result = await _nativeJsonInIsolate(
      widget.dataDirectory!,
      'workplace_broadcast',
      [values.title, values.body],
    );
    if (!mounted) return;
    if (result != null && result['error'] == null) {
      widget.onTrustChanged();
    } else {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(result?['error']?.toString() ?? 'Broadcast could not be created.')),
      );
    }
  }

  Future<void> _createWorkplace(BuildContext context) async {
    final controller = TextEditingController(text: 'My Workplace');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Workplace'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty || widget.dataDirectory == null || widget.native == null) return;
    final created = await _nativeJsonInIsolate(
      widget.dataDirectory!,
      'workplace_create',
      [name],
    );
    if (!mounted) return;
    if (created != null && created['error'] == null) {
      widget.onTrustChanged();
      setState(() {});
    } else {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(created?['error']?.toString() ?? 'Workplace could not be created.')),
      );
    }
  }

  Widget _files(BuildContext context) {
    final data = widget.dataDirectory;
    final native = widget.native;
    final conversations = data == null || native == null
        ? const <Map<String, dynamic>>[]
        : native.conversations(data);
    final files = <({String deviceId, String name, bool outgoing, Map<String, dynamic> file})>[];

    for (final conversation in conversations) {
      final deviceId = conversation['device_id']?.toString() ?? '';
      final name = conversation['name']?.toString() ?? 'Device';
      final messages = (conversation['messages'] as List?)
              ?.whereType<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      for (final message in messages) {
        final file = message['file'];
        if (message['kind'] == 'file' && file is Map<String, dynamic>) {
          files.add((
            deviceId: deviceId,
            name: name,
            outgoing: message['outgoing'] == true,
            file: file,
          ));
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return ListView(
          padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 20, compact ? 16 : 28, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Files', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 5),
                      Text(
                        'Send files directly to your trusted devices.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF8E9691),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: widget.trustedDevices.isEmpty ? null : _pickAndSendFile,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(compact ? 'Send' : 'Send file'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (files.isEmpty)
              const _EmptyPanel(
                icon: Icons.folder_open_outlined,
                title: 'No file transfers yet',
                message: 'Choose a trusted device to send a file directly.',
              )
            else
              for (final item in files.reversed)
                _fileTransferCard(context, item.deviceId, item.name, item.outgoing, item.file),
          ],
        );
      },
    );
  }

  Widget _fileTransferCard(
    BuildContext context,
    String deviceId,
    String deviceName,
    bool outgoing,
    Map<String, dynamic> file,
  ) {
    final state = file['state']?.toString().toLowerCase() ?? 'unknown';
    final transferId = file['transfer_id']?.toString() ?? '';
    final size = file['size'];
    final total = size is num ? size.toInt() : int.tryParse(size?.toString() ?? '');
    int? received;
    final localPath = file['local_path']?.toString();
    // For incoming transfers the .part file is real progress. For outgoing
    // transfers, the selected source file is already complete, so never use
    // its size as a fake "sent" byte count.
    if (!outgoing && localPath != null && total != null && total > 0) {
      try {
        final length = File(localPath).lengthSync();
        if (length >= 0) received = length;
      } catch (_) {}
    }
    final progress = total != null && total > 0 && received != null
        ? (received / total).clamp(0.0, 1.0).toDouble()
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _DeviceIcon(icon: _fileIcon(file['file_name']?.toString() ?? '')),
              title: Text(
                file['file_name']?.toString() ?? 'File',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '$deviceName · ${_formatBytes(size)} · ${_fileStateLabel(state)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                _fileStateIcon(state),
                color: _fileStateColor(state),
              ),
            ),
            if (state == 'transferring') ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(value: outgoing ? null : progress),
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  outgoing && received == null
                      ? 'Sending…'
                      : '${_formatBytes(received)} of ${_formatBytes(total)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF858D88),
                  ),
                ),
              ),
            ],
            if (state == 'offered' && !outgoing)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: transferId.isEmpty
                        ? null
                        : () => _decideIncomingFile(
                              deviceId,
                              transferId,
                              accept: false,
                            ),
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: transferId.isEmpty
                        ? null
                        : () => _decideIncomingFile(
                              deviceId,
                              transferId,
                              accept: true,
                            ),
                    child: const Text('Accept'),
                  ),
                ],
              ),
            if (state == 'transferring' || (state == 'offered' && outgoing))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: transferId.isEmpty
                      ? null
                      : () => _cancelFileTransfer(deviceId, transferId),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelFileTransfer(String deviceId, String transferId) async {
    final data = widget.dataDirectory;
    if (data == null || widget.native == null) return;
    final result = await _nativeJsonInIsolate(data, 'file_cancel', [deviceId, transferId]);
    if (!mounted) return;
    if (result?['ok'] == true) {
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The file could not be cancelled. Try again.')),
      );
    }
  }

  Future<void> _decideIncomingFile(
    String deviceId,
    String transferId, {
    required bool accept,
  }) async {
    final data = widget.dataDirectory;
    if (data == null || widget.native == null) return;
    final result = await _nativeJsonInIsolate(
      data,
      accept ? 'file_accept' : 'file_decline',
      [deviceId, transferId],
    );
    if (!mounted) return;
    if (result?['ok'] == true) {
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'The file could not be accepted. Try again.'
                : 'The file could not be declined. Try again.',
          ),
        ),
      );
    }
  }

  String _fileStateLabel(String state) {
    switch (state) {
      case 'complete':
      case 'completed':
      case 'delivered':
        return 'Complete';
      case 'failed':
      case 'error':
        return 'Failed';
      case 'queued':
      case 'pending':
        return 'Waiting';
      case 'offered':
        return 'Waiting for response';
      case 'declined':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      case 'transferring':
        return 'In progress';
      default:
        return 'Preparing';
    }
  }

  IconData _fileIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) {
      return Icons.archive_outlined;
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif')) {
      return Icons.image_outlined;
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm')) {
      return Icons.movie_outlined;
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.m4a')) {
      return Icons.audio_file_outlined;
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description_outlined;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.table_chart_outlined;
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return Icons.slideshow_outlined;
    return Icons.insert_drive_file_outlined;
  }

  IconData _fileStateIcon(String? state) {
    switch (state?.toLowerCase()) {
      case 'complete':
      case 'completed':
      case 'delivered':
        return Icons.check_circle_outline;
      case 'failed':
      case 'error':
        return Icons.error_outline;
      case 'queued':
      case 'pending':
      case 'offered':
        return Icons.schedule_outlined;
      case 'declined':
        return Icons.block_outlined;
      case 'cancelled':
        return Icons.cancel_outlined;
      case 'transferring':
        return Icons.sync_outlined;
      default:
        return Icons.sync_outlined;
    }
  }

  Color _fileStateColor(String? state) {
    switch (state?.toLowerCase()) {
      case 'complete':
      case 'completed':
      case 'delivered':
        return const Color(0xFF7ED957);
      case 'failed':
      case 'error':
        return Colors.orange;
      case 'offered':
        return Colors.amber;
      case 'declined':
      case 'cancelled':
        return const Color(0xFF777E79);
      default:
        return const Color(0xFF858D88);
    }
  }

  // Keep transfer and message UI deliberately simple; transport details belong to the core.
  String _formatBytes(dynamic value) {
    final bytes = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (bytes == null) return 'Size unknown';
    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<String?> _materialisePickedFile(XFile file) async {
    final path = file.path;
    if (path.isNotEmpty && await File(path).exists()) return path;

    // Android hands the picker back a content:// uri that the Rust core cannot
    // open directly, so cache a real copy the transfer can read.
    late final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return null;
    }
    final support = await getApplicationSupportDirectory();
    final outbox = Directory('${support.path}${Platform.pathSeparator}outbox');
    await outbox.create(recursive: true);
    final safeName = file.name.replaceAll(RegExp(r'[\\/]'), '_');
    final target = File('${outbox.path}${Platform.pathSeparator}$safeName');
    await target.writeAsBytes(bytes);
    return target.path;
  }

  Future<void> _pickAndSendFile() async {
    final data = widget.dataDirectory;
    final native = widget.native;
    if (data == null || native == null || widget.trustedDevices.isEmpty || !mounted) return;

    final selectedId = _validSelectedDevice() ?? widget.trustedDevices.first.deviceId;
    final file = await openFile();
    if (!mounted || file == null) return;
    final path = await _materialisePickedFile(file);
    if (!mounted || path == null) return;

    final transferId = await _sendFileInIsolate(data, selectedId, path);
    if (transferId == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File transfer could not be started.')),
      );
    } else if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File transfer started.')),
      );
    }
  }

  Future<void> _confirmRemoveTrustedDevice(BuildContext context, KnownDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove trusted device?'),
        content: Text('Remove ${device.displayName} from trusted devices?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || widget.dataDirectory == null || widget.native == null) return;
    final result = widget.native!.ignoreTrust(widget.dataDirectory!, device.deviceId);
    if (result != null && mounted) widget.onTrustChanged();
  }

  Widget _messages(BuildContext context) {
    final devices = widget.trustedDevices;
    if (devices.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.chat_bubble_outline,
        title: 'No trusted devices',
        message: 'Accept a device from Nearby before starting a conversation.',
      );
    }

    final currentId = _validSelectedDevice() ?? devices.first.deviceId;
    if (selectedDevice != currentId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && selectedDevice != currentId) {
          setState(() => selectedDevice = currentId);
        }
      });
    }

    final selected = devices.firstWhere(
      (d) => d.deviceId == currentId,
      orElse: () => devices.first,
    );
    final data = widget.dataDirectory;
    final native = widget.native;
    final conversation =
        data == null || native == null ? null : native.conversation(data, selected.deviceId);
    final messages = (conversation?['messages'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        if (compact) {
          return Column(
            children: [
              SizedBox(
                height: 76,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final device = devices[index];
                    final active = device.deviceId == selected.deviceId;
                    return ChoiceChip(
                      selected: active,
                      avatar: const Icon(Icons.computer_outlined, size: 18),
                      label: Text(device.displayName),
                      onSelected: (_) => setState(() => selectedDevice = device.deviceId),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _conversationPane(context, selected, messages)),
            ],
          );
        }

        return Row(
          children: [
            SizedBox(
              width: 270,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
                    child: Text(
                      'Conversations',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  for (final device in devices)
                    ListTile(
                      selected: device.deviceId == selected.deviceId,
                      leading: _DeviceIcon(icon: Icons.computer_outlined),
                      title: Text(
                        device.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(device.state),
                      onTap: () => setState(() => selectedDevice = device.deviceId),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _conversationPane(context, selected, messages)),
          ],
        );
      },
    );
  }

  Widget _conversationPane(
    BuildContext context,
    KnownDevice selected,
    List<Map<String, dynamic>> messages,
  ) {
    return Column(
      children: [
        ListTile(
          leading: _DeviceIcon(icon: Icons.computer_outlined),
          title: Text(selected.displayName),
          subtitle: Text(
            selected.fingerprint.isEmpty ? selected.state : selected.fingerprint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            selected.state.toLowerCase() == 'accepted'
                ? Icons.verified_outlined
                : Icons.circle_outlined,
            color: selected.state.toLowerCase() == 'accepted'
                ? const Color(0xFF7ED957)
                : const Color(0xFF777E79),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: messages.isEmpty
              ? const _EmptyPanel(
                  icon: Icons.chat_bubble_outline,
                  title: 'No messages yet',
                  message: 'Start the conversation by sending a message.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: messages.length,
                  itemBuilder: (_, index) {
                    final message = messages[index];
                    final outgoing = message['outgoing'] == true;
                    return Align(
                      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 620),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Text(message['body']?.toString() ?? ''),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => draft = value,
                    onSubmitted: (_) => _send(),
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Write a message',
                      prefixIcon: Icon(Icons.chat_bubble_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _pickAndSendFile,
                  tooltip: 'Send file',
                  icon: const Icon(Icons.attach_file),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: draft.trim().isEmpty ? null : _send,
                  tooltip: 'Send message',
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String? _validSelectedDevice() {
    final id = selectedDevice;
    if (id == null) return null;
    return widget.trustedDevices.any((device) => device.deviceId == id) ? id : null;
  }

  Future<void> _send() async {
    final text = draft.trim();
    final data = widget.dataDirectory;
    final native = widget.native;
    final deviceId = selectedDevice;
    if (text.isEmpty || data == null || native == null || deviceId == null) return;
    final id = await _sendMessageInIsolate(data, deviceId, text);
    if (!mounted) return;
    if (id != null) {
      setState(() => draft = '');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message could not be sent.')),
      );
    }
  }
}


