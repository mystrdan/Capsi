import 'dart:async';

import 'capsi_native.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> _sendFileInIsolate(String dataDirectory, String deviceId, String filePath) async {
  return Isolate.run(() {
    final bridge = CapsiNative.tryLoad();
    if (bridge == null) return null;
    return bridge.sendFile(dataDirectory, deviceId, filePath);
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB8F36B), brightness: Brightness.dark, surface: const Color(0xFF111516)),
        dividerColor: const Color(0x18FFFFFF),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF0E1112),
          indicatorColor: Color(0x18B8F36B),
          selectedIconTheme: IconThemeData(color: Color(0xFFB8F36B)),
          selectedLabelTextStyle: TextStyle(color: Color(0xFFF4F6F2), fontWeight: FontWeight.w700),
          unselectedIconTheme: IconThemeData(color: Color(0xFF777E79)),
          unselectedLabelTextStyle: TextStyle(color: Color(0xFF777E79)),
        ),
        cardTheme: const CardThemeData(color: Color(0xFF111516), surfaceTintColor: Colors.transparent, margin: EdgeInsets.zero),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF0E1112),
          border: OutlineInputBorder(borderSide: BorderSide(color: Color(0x18FFFFFF))),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0x18FFFFFF))),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0x66B8F36B))),
        ),
      ),
      home: const CapsiHome(),
    );
  }
}

class CapsiHome extends StatefulWidget {
  final bool autoInitialize;
  const CapsiHome({super.key, this.autoInitialize = true});
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
  String? dataDirectory;
  List<KnownDevice> trustedDevices = const [];
  Map<String, dynamic>? workplaceData;
  int messageHandle = 0;
  Timer? messageTimer;
  Timer? workplaceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.autoInitialize) {
      native = CapsiNative.tryLoad();
      _initializeRuntime();
    } else {
      runtimeLoading = false;
    }
  }

  Future<void> _initializeRuntime() async {
    if (mounted) setState(() { runtimeLoading = true; runtimeError = null; });
    try {
      final directory = await getApplicationSupportDirectory();
      if (!mounted) return;
      dataDirectory = directory.path;
      if (native == null) {
        setState(() { runtimeLoading = false; runtimeError = 'The Capsi native core could not be loaded on this platform.'; });
        return;
      }
      _loadTrust();
      _loadWorkplace();
      workplaceTimer?.cancel();
      workplaceTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadWorkplace());
      _startDiscovery();
      _startMessages();
      if (mounted) setState(() { runtimeLoading = false; runtimeError = null; });
    } catch (error) {
      if (!mounted) return;
      setState(() { runtimeLoading = false; runtimeError = 'Capsi could not finish starting: $error'; });
    }
  }

  void _stopRuntimeSessions() {
    discoveryTimer?.cancel(); discoveryTimer = null;
    messageTimer?.cancel(); messageTimer = null;
    workplaceTimer?.cancel(); workplaceTimer = null;
    final bridge = native;
    if (bridge != null) {
      if (messageHandle != 0) bridge.stopMessageListener(messageHandle);
      if (discoveryHandle != 0) bridge.stopDiscovery(discoveryHandle);
    }
    messageHandle = 0; discoveryHandle = 0;
  }

  void _retryRuntime() {
    _stopRuntimeSessions();
    if (mounted) setState(() { peers = const []; lastMessageEvent = null; workplaceData = null; scanning = false; runtimeLoading = true; runtimeError = null; });
    native = CapsiNative.tryLoad();
    _initializeRuntime();
  }

  void _loadWorkplace() {
    final bridge = native; final dir = dataDirectory;
    if (bridge == null || dir == null || !mounted) return;
    final value = bridge.workplace(dir);
    if (mounted && value != null) setState(() => workplaceData = value);
  }

  void _loadTrust() {
    final bridge = native; final dir = dataDirectory;
    if (bridge == null || dir == null || !mounted) return;
    setState(() => trustedDevices = bridge.trustList(dir));
  }

  void _startMessages() {
    final bridge = native; final dir = dataDirectory;
    if (bridge == null || dir == null) return;
    if (messageHandle != 0) bridge.stopMessageListener(messageHandle);
    messageTimer?.cancel();
    messageHandle = bridge.startMessageListener(dataDirectory: dir);
    if (messageHandle == 0) return;
    messageTimer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (!mounted || messageHandle == 0) return;
      final event = bridge.pollMessage(messageHandle);
      if (event != null && event['type'] != null && mounted) setState(() => lastMessageEvent = event);
    });
  }

  void _startDiscovery() {
    final bridge = native; final dir = dataDirectory;
    if (bridge == null || dir == null) return;
    if (discoveryHandle != 0) bridge.stopDiscovery(discoveryHandle);
    discoveryTimer?.cancel();
    discoveryHandle = bridge.startDiscovery(deviceName: 'Capsi device', dataDirectory: dir);
    if (discoveryHandle == 0) return;
    _pollDiscovery();
    discoveryTimer = Timer.periodic(const Duration(milliseconds: 750), (_) => _pollDiscovery());
  }

  void _pollDiscovery() {
    final bridge = native;
    if (bridge == null || discoveryHandle == 0 || !mounted) return;
    setState(() { peers = bridge.pollDiscovery(discoveryHandle); scanning = false; });
  }

  void _scan() {
    if (!mounted || native == null || dataDirectory == null) return;
    if (discoveryHandle == 0) { _startDiscovery(); return; }
    setState(() => scanning = true);
    _pollDiscovery();
  }

  @override
  void dispose() { _stopRuntimeSessions(); super.dispose(); }

  static const pages = <({IconData icon, String label})>[
    (icon: Icons.radar_outlined, label: 'Nearby'),
    (icon: Icons.workspaces_outlined, label: 'WorkPlace'),
    (icon: Icons.chat_bubble_outline, label: 'Messages'),
    (icon: Icons.folder_outlined, label: 'Files'),
    (icon: Icons.verified_user_outlined, label: 'Trusted devices'),
  ];

  void _showSettings(BuildContext context) => showDialog<void>(context: context, builder: (_) => _SettingsDialog(native: native, dataDirectory: dataDirectory, trustedDeviceCount: trustedDevices.length));

  @override
  Widget build(BuildContext context) {
    final page = pages[selected];
    final body = _PageBody(label: page.label, peers: peers, scanning: scanning, native: native, onScan: _scan, trustedDevices: trustedDevices, onTrustChanged: () { _loadTrust(); _loadWorkplace(); }, dataDirectory: dataDirectory, workplaceData: workplaceData);
    if (runtimeLoading || runtimeError != null) return _RuntimeGate(loading: runtimeLoading, error: runtimeError, onRetry: _retryRuntime);
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      return Scaffold(
        body: compact
            ? Column(children: [Expanded(child: _DesktopContent(page: page, body: body, native: native, onSettings: () => _showSettings(context))), NavigationBar(selectedIndex: selected, onDestinationSelected: (index) => setState(() => selected = index), destinations: [for (final item in pages) NavigationDestination(icon: Icon(item.icon), selectedIcon: Icon(item.icon), label: item.label)])])
            : Row(children: [NavigationRail(selectedIndex: selected, onDestinationSelected: (index) => setState(() => selected = index), backgroundColor: const Color(0xFF0E1112), labelType: NavigationRailLabelType.all, leading: const Padding(padding: EdgeInsets.only(top: 18, bottom: 28), child: _CapsiMark()), destinations: [for (final item in pages) NavigationRailDestination(icon: Icon(item.icon), selectedIcon: Icon(item.icon), label: Text(item.label))]), const VerticalDivider(width: 1), Expanded(child: _DesktopContent(page: page, body: body, native: native, onSettings: () => _showSettings(context))) ]),
      );
    });
  }
}

class _RuntimeGate extends StatelessWidget {
  final bool loading; final String? error; final VoidCallback onRetry;
  const _RuntimeGate({required this.loading, required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: const Color(0xFF090B0C), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Image.asset('assets/capsi-logo-512.png', width: 88, height: 88), const SizedBox(height: 24), if (loading) ...[const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)), const SizedBox(height: 18), Text('Starting Capsi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 7), const Text('Loading the local Capsi runtime…', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF858D88)))] else ...[Text('Capsi could not start', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 8), Text(error ?? 'The local runtime is unavailable.', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF858D88), height: 1.5)), const SizedBox(height: 20), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again'))]]))));
}

class _DesktopContent extends StatelessWidget {
  final ({IconData icon, String label}) page; final Widget body; final CapsiNative? native; final VoidCallback? onSettings;
  const _DesktopContent({required this.page, required this.body, required this.native, this.onSettings});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(28, 22, 28, 18), child: Row(children: [Expanded(child: Row(children: [Icon(page.icon, size: 20, color: const Color(0xFFB8F36B)), const SizedBox(width: 10), Text(page.label, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))])), Row(mainAxisSize: MainAxisSize.min, children: [_NetworkStatus(available: native != null), const SizedBox(width: 8), IconButton(tooltip: 'Settings', onPressed: onSettings, icon: const Icon(Icons.settings_outlined))])])), const Divider(height: 1), Expanded(child: body)]);
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon; final String title; final String message;
  const _EmptyPanel({required this.icon, required this.title, required this.message});
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(34), child: Column(children: [Icon(icon, size: 34, color: const Color(0xFFB8F36B)), const SizedBox(height: 14), Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 7), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF858D88), height: 1.5))])));
}

class _DeviceIcon extends StatelessWidget {
  final IconData icon; const _DeviceIcon({required this.icon});
  @override
  Widget build(BuildContext context) => Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0x18B8F36B), border: Border.all(color: const Color(0x30B8F36B)), borderRadius: BorderRadius.circular(11)), child: Icon(icon, size: 21, color: const Color(0xFFB8F36B)));
}

class _CapsiMark extends StatelessWidget {
  const _CapsiMark();
  @override
  Widget build(BuildContext context) => Tooltip(message: 'Capsi', child: Image.asset('assets/capsi-logo-512.png', width: 42, height: 42, fit: BoxFit.contain));
}

class _SettingsDialog extends StatelessWidget {
  final CapsiNative? native; final String? dataDirectory; final int trustedDeviceCount;
  const _SettingsDialog({required this.native, required this.dataDirectory, required this.trustedDeviceCount});
  @override
  Widget build(BuildContext context) {
    final version = native?.runtimeVersion ?? '1.0.2'; final protocol = native?.protocolVersion ?? 'Unavailable';
    return AlertDialog(title: Row(children: [const Icon(Icons.settings_outlined), const SizedBox(width: 10), const Expanded(child: Text('Settings')), IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close))]), content: SizedBox(width: 620, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SettingsSection(title: 'Connection', children: [
        _SettingsRow(icon: Icons.wifi_outlined, title: 'Direct communication', subtitle: 'Capsi communicates device to device. No Capsi cloud is required.', trailing: _NetworkStatus(available: native != null)),
        _SettingsRow(icon: Icons.radar_outlined, title: 'Discovery', subtitle: 'Discovery is used to find nearby Capsi devices.', trailing: Icon(native == null ? Icons.error_outline : Icons.check_circle_outline, color: native == null ? Colors.orange : const Color(0xFFB8F36B))),
        _SettingsRow(icon: Icons.message_outlined, title: 'Messages', subtitle: 'Messages use Capsi direct device-to-device transport.', trailing: Icon(native == null ? Icons.error_outline : Icons.check_circle_outline, color: native == null ? Colors.orange : const Color(0xFFB8F36B))),
      ]),
      const SizedBox(height: 14),
      _SettingsSection(title: 'Privacy & devices', children: [_SettingsRow(icon: Icons.verified_user_outlined, title: 'Trusted devices', subtitle: '$trustedDeviceCount trusted device${trustedDeviceCount == 1 ? '' : 's'}', trailing: const Icon(Icons.chevron_right)), const _SettingsRow(icon: Icons.lock_outline, title: 'Trust model', subtitle: 'Only devices you accept can exchange messages and files.')]),
      const SizedBox(height: 14),
      _SettingsSection(title: 'Storage', children: [_SettingsRow(icon: Icons.folder_outlined, title: 'Capsi data', subtitle: dataDirectory ?? 'Application data directory unavailable', trailing: dataDirectory == null ? const Icon(Icons.error_outline) : IconButton(tooltip: 'Copy path', onPressed: () async { await Clipboard.setData(ClipboardData(text: dataDirectory!)); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data path copied.'))); }, icon: const Icon(Icons.copy_outlined)))]),
      const SizedBox(height: 14),
      _SettingsSection(title: 'Appearance', children: const [_SettingsRow(icon: Icons.dark_mode_outlined, title: 'Theme', subtitle: 'Dark', trailing: Text('Current', style: TextStyle(color: Color(0xFF858D88)))]),
      const SizedBox(height: 14),
      _SettingsSection(title: 'About', children: [_SettingsRow(icon: Icons.info_outline, title: 'Capsi', subtitle: 'Messages and files, device to device.', trailing: Text('v$version')), _SettingsRow(icon: Icons.memory_outlined, title: 'Runtime', subtitle: native == null ? 'Rust core is not loaded.' : 'Rust core linked', trailing: Text(protocol)), ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.open_in_new_outlined), title: const Text('About Capsi'), subtitle: const Text('Product, version and architecture information'), onTap: () => showDialog<void>(context: context, builder: (_) => _AboutDialog(native: native))) ]),
    ]))), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))]);
  }
}

class _SettingsSection extends StatelessWidget {
  final String title; final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(left: 2, bottom: 7), child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: Color(0xFF858D88)))), Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: Column(children: children)))]);
}

class _SettingsRow extends StatelessWidget {
  final IconData icon; final String title; final String subtitle; final Widget? trailing;
  const _SettingsRow({required this.icon, required this.title, required this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) => ListTile(contentPadding: const EdgeInsets.symmetric(vertical: 3), leading: Icon(icon, color: const Color(0xFFB8F36B)), title: Text(title), subtitle: Padding(padding: const EdgeInsets.only(top: 3), child: Text(subtitle, style: const TextStyle(color: Color(0xFF858D88)))), trailing: trailing);
}

class _AboutDialog extends StatelessWidget {
  final CapsiNative? native; const _AboutDialog({required this.native});
  @override
  Widget build(BuildContext context) { final runtime = native?.runtimeVersion ?? 'Unavailable'; final protocol = native?.protocolVersion ?? 'Unavailable'; return AlertDialog(title: Row(children: [Image.asset('assets/capsi-logo-512.png', width: 38, height: 38), const SizedBox(width: 12), const Text('About Capsi')]), content: const SizedBox(width: 500, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Messages and files, device to device.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), SizedBox(height: 12), Text('Capsi is a lightweight communication utility built around direct device-to-device exchange. It does not require a Capsi cloud account or Internet service for local communication.', style: TextStyle(height: 1.5, color: Color(0xFF9AA19C))), SizedBox(height: 18), Text('CAPSICOM', style: TextStyle(fontWeight: FontWeight.w700)), SizedBox(height: 4), Text('Capsi 1.0.2', style: TextStyle(color: Color(0xFF858D88)))])), actions: [Padding(padding: const EdgeInsets.only(right: 8, bottom: 6), child: Text('Runtime $runtime · Protocol $protocol', style: const TextStyle(fontSize: 11, color: Color(0xFF666E69)))), TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))]); }
}

class _NetworkStatus extends StatelessWidget {
  final bool available; const _NetworkStatus({required this.available});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7), decoration: BoxDecoration(color: const Color(0xFF111516), border: Border.all(color: const Color(0x18FFFFFF)), borderRadius: BorderRadius.circular(999)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 7, color: available ? const Color(0xFFB8F36B) : Colors.orange), const SizedBox(width: 7), Text(available ? 'Local network' : 'Core unavailable', style: const TextStyle(fontSize: 12))]));
}

class _PageBody extends StatefulWidget {
  final String label; final List<CapsiPeer> peers; final bool scanning; final CapsiNative? native; final VoidCallback onScan; final List<KnownDevice> trustedDevices; final VoidCallback onTrustChanged; final String? dataDirectory; final Map<String, dynamic>? workplaceData;
  const _PageBody({required this.label, required this.peers, required this.scanning, required this.native, required this.onScan, required this.trustedDevices, required this.onTrustChanged, required this.dataDirectory, required this.workplaceData});
  @override
  State<_PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<_PageBody> {
  String? selectedDevice;
  String draft = '';
  String workplaceDraft = '';
  String? selectedWorkplaceGroup;
  final TextEditingController workplaceController = TextEditingController();

  @override
  void dispose() { workplaceController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.label == 'WorkPlace') return _workplace(context);
    if (widget.label == 'Trusted devices') {
      return ListView(padding: const EdgeInsets.all(28), children: [Text('Trusted devices', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8), const Text('Only devices you accept are allowed to exchange messages and files.'), const SizedBox(height: 20), if (widget.trustedDevices.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No trusted devices yet. Accept a device from Nearby to add it here.'))) else for (final device in widget.trustedDevices) Card(child: ListTile(leading: const Icon(Icons.verified_user_outlined), title: Text(device.displayName), subtitle: Text(device.fingerprint.isEmpty ? 'Fingerprint unavailable' : device.fingerprint), trailing: widget.native == null || widget.dataDirectory == null ? null : IconButton(tooltip: 'Remove trusted device', icon: const Icon(Icons.remove_circle_outline), onPressed: () { final removed = widget.native!.ignoreTrust(widget.dataDirectory!, device.deviceId); if (removed != null) widget.onTrustChanged(); })))]);
    }
    if (widget.label == 'Messages') return _messages(context);
    if (widget.label == 'Files') return _files(context);
    return _nearby(context);
  }

  Widget _nearby(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(28, 26, 28, 40), children: [Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Devices around you', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 6), Text('Find devices directly. Accept a device to start sending messages and files.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF9AA19C)))])), const SizedBox(width: 16), OutlinedButton.icon(onPressed: widget.scanning ? null : widget.onScan, icon: Icon(widget.scanning ? Icons.sync : Icons.radar_outlined), label: Text(widget.scanning ? 'Scanning…' : 'Scan'))]), const SizedBox(height: 22), if (widget.peers.isEmpty) const _EmptyPanel(icon: Icons.radar_outlined, title: 'No devices found', message: 'Make sure the other device is running Capsi and both devices can communicate directly.') else LayoutBuilder(builder: (context, constraints) { final columns = constraints.maxWidth > 1050 ? 2 : 1; return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: widget.peers.length, gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: 14, mainAxisSpacing: 14, mainAxisExtent: 112), itemBuilder: (_, index) => _peerCard(context, widget.peers[index])); })]);

  Widget _peerCard(BuildContext context, CapsiPeer peer) => Card(child: ListTile(leading: const _DeviceIcon(icon: Icons.devices_outlined), title: Text(peer.name), subtitle: Text(peer.address), trailing: FilledButton(onPressed: widget.native == null || widget.dataDirectory == null ? null : () { final result = widget.native!.acceptTrust(widget.dataDirectory!, peer.deviceId, alias: peer.name); if (result != null) widget.onTrustChanged(); }, child: const Text('Trust'))));

  Widget _messages(BuildContext context) {
    final native = widget.native; final dir = widget.dataDirectory; final devices = widget.trustedDevices;
    if (native == null || dir == null) return const _EmptyPanel(icon: Icons.chat_bubble_outline, title: 'Messages unavailable', message: 'The Capsi native runtime is not available.');
    if (devices.isEmpty) return const _EmptyPanel(icon: Icons.chat_bubble_outline, title: 'No trusted devices', message: 'Accept a device from Nearby before starting a conversation.');
    final id = selectedDevice != null && devices.any((d) => d.deviceId == selectedDevice) ? selectedDevice! : devices.first.deviceId;
    final device = devices.firstWhere((d) => d.deviceId == id);
    final conversation = native.conversation(dir, id);
    final messages = (conversation?['messages'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const <Map<String, dynamic>>[];
    return Column(children: [SizedBox(height: 76, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(14), itemCount: devices.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) => ChoiceChip(selected: devices[i].deviceId == id, label: Text(devices[i].displayName), onSelected: (_) => setState(() => selectedDevice = devices[i].deviceId))), const Divider(height: 1), Expanded(child: Column(children: [ListTile(leading: const _DeviceIcon(icon: Icons.computer_outlined), title: Text(device.displayName), subtitle: Text(device.fingerprint.isEmpty ? device.state : device.fingerprint)), const Divider(height: 1), Expanded(child: messages.isEmpty ? const _EmptyPanel(icon: Icons.chat_bubble_outline, title: 'No messages yet', message: 'Send the first message to this device.') : ListView.builder(padding: const EdgeInsets.all(18), itemCount: messages.length, itemBuilder: (_, i) { final m = messages[i]; final outgoing = m['outgoing'] == true; return Align(alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft, child: Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text(m['body']?.toString() ?? '')))); })), const Divider(height: 1), Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: TextField(onChanged: (v) => draft = v, onSubmitted: (_) => _sendMessage(id), minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Write a message'))), const SizedBox(width: 8), IconButton.filled(onPressed: draft.trim().isEmpty ? null : () => _sendMessage(id), icon: const Icon(Icons.send))]))]))]);
  }

  void _sendMessage(String deviceId) {
    final dir = widget.dataDirectory; final native = widget.native; final text = draft.trim();
    if (dir == null || native == null || text.isEmpty) return;
    final result = native.sendMessage(dir, deviceId, text);
    if (result != null && mounted) setState(() => draft = '');
  }

  Widget _files(BuildContext context) {
    final native = widget.native; final dir = widget.dataDirectory; final devices = widget.trustedDevices;
    if (native == null || dir == null) return const _EmptyPanel(icon: Icons.folder_outlined, title: 'Files unavailable', message: 'The Capsi native runtime is not available.');
    if (devices.isEmpty) return const _EmptyPanel(icon: Icons.folder_outlined, title: 'No trusted devices', message: 'Accept a device from Nearby before sending files.');
    final id = selectedDevice != null && devices.any((d) => d.deviceId == selectedDevice) ? selectedDevice! : devices.first.deviceId;
    final device = devices.firstWhere((d) => d.deviceId == id);
    final conversation = native.conversation(dir, id);
    final messages = (conversation?['messages'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const <Map<String, dynamic>>[];
    final files = messages.where((m) => m['file'] is Map<String, dynamic>).toList();
    return Column(children: [Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 10), child: Row(children: [Expanded(child: Text('Files · ${device.displayName}', style: Theme.of(context).textTheme.titleMedium)), FilledButton.icon(onPressed: () => _pickAndSendFile(id), icon: const Icon(Icons.attach_file), label: const Text('Send file'))])), const Divider(height: 1), Expanded(child: files.isEmpty ? const _EmptyPanel(icon: Icons.folder_outlined, title: 'No transfers yet', message: 'Choose a file to send it directly to this trusted device.') : ListView.builder(padding: const EdgeInsets.all(18), itemCount: files.length, itemBuilder: (_, i) { final file = files[i]['file'] as Map<String, dynamic>; return Card(child: ListTile(leading: Icon(_fileIcon(file['file_name']?.toString())), title: Text(file['file_name']?.toString() ?? 'File'), subtitle: Text(_formatBytes(file['size'])), trailing: Text(file['state']?.toString() ?? 'unknown')); })))]);
  }

  IconData _fileIcon(String? name) { final lower = (name ?? '').toLowerCase(); if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp')) return Icons.image_outlined; if (lower.endsWith('.pdf') || lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description_outlined; if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.table_chart_outlined; if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return Icons.slideshow_outlined; return Icons.insert_drive_file_outlined; }
  String _formatBytes(dynamic value) { final bytes = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? ''); if (bytes == null) return 'Size unknown'; if (bytes < 1024) return '${bytes.toInt()} B'; if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB'; if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'; return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'; }

  Future<void> _pickAndSendFile(String deviceId) async {
    final dir = widget.dataDirectory; if (dir == null || !mounted) return;
    final result = await FilePicker.platform.pickFiles(withData: false); if (!mounted || result == null || result.files.single.path == null) return;
    final messenger = ScaffoldMessenger.of(context); messenger.showSnackBar(const SnackBar(content: Text('Starting file transfer…')));
    final transferId = await _sendFileInIsolate(dir, deviceId, result.files.single.path!);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(transferId == null ? 'File transfer failed.' : 'File transfer started.')));
    setState(() {});
  }

  Widget _workplace(BuildContext context) {
    final workspace = widget.workplaceData;
    if (workspace == null) return const _EmptyPanel(icon: Icons.workspaces_outlined, title: 'No WorkPlace yet', message: 'Create a WorkPlace from the Rust-backed workspace model when that flow is exposed in this client.');
    final members = (workspace['members'] as List?)?.length ?? 0; final groups = (workspace['groups'] as List?)?.length ?? 0; final departments = (workspace['departments'] as List?)?.length ?? 0; final broadcasts = (workspace['broadcasts'] as List?)?.length ?? 0;
    return ListView(padding: const EdgeInsets.all(28), children: [Text(workspace['name']?.toString() ?? 'WorkPlace', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 8), Text('$members people · $groups groups · $departments departments · $broadcasts broadcasts'), const SizedBox(height: 20), Wrap(spacing: 12, runSpacing: 12, children: [_WorkplaceStat('People', members), _WorkplaceStat('Groups', groups), _WorkplaceStat('Departments', departments), _WorkplaceStat('Broadcasts', broadcasts)]), const SizedBox(height: 20), const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('WorkPlace data is loaded from the Rust core. Group and broadcast actions will be enabled as their Flutter controls are wired.')))]);
  }
}

class _WorkplaceStat extends StatelessWidget {
  final String label; final int value; const _WorkplaceStat(this.label, this.value);
  @override
  Widget build(BuildContext context) => SizedBox(width: 150, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value.toString(), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white70))])));
}
