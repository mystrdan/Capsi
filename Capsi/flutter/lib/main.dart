import 'dart:async';

import 'capsi_native.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
          seedColor: const Color(0xFFB8F36B),
          brightness: Brightness.dark,
          surface: const Color(0xFF111516),
        ),
        dividerColor: const Color(0x18FFFFFF),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Color(0xFF0E1112),
          indicatorColor: Color(0x18B8F36B),
          selectedIconTheme: IconThemeData(color: Color(0xFFB8F36B)),
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
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0x66B8F36B))),
        ),
      ),
      home: const CapsiHome(),
    );
  }
}

class CapsiHome extends StatefulWidget {
  const CapsiHome({super.key});

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
    native = CapsiNative.tryLoad();
    _initializeRuntime();
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

      if (native == null) {
        setState(() {
          runtimeLoading = false;
          runtimeError = 'The Capsi native core could not be loaded on this platform.';
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
        runtimeError = 'Capsi could not finish starting: $error';
      });
    }
  }

  void _retryRuntime() {
    discoveryTimer?.cancel();
    messageTimer?.cancel();
    workplaceTimer?.cancel();

    if (mounted) {
      setState(() {
        discoveryHandle = 0;
        messageHandle = 0;
        peers = const [];
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
      final event = bridge.pollMessage(messageHandle);
      if (event != null && event['type'] != null) {
        setState(() => lastMessageEvent = event);
      }
    });
  }

  void _startDiscovery() {
    final bridge = native;
    final dir = dataDirectory;
    if (bridge == null || dir == null) return;
    discoveryHandle = bridge.startDiscovery(
      deviceName: 'Capsi device',
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
    setState(() {
      peers = bridge.pollDiscovery(discoveryHandle);
      scanning = false;
    });
  }

  void _scan() {
    if (!mounted || native == null || dataDirectory == null) return;

    if (discoveryHandle == 0) {
      _startDiscovery();
      return;
    }

    setState(() => scanning = true);
    _pollDiscovery();
  }

  @override
  void dispose() {
    discoveryTimer?.cancel();
    messageTimer?.cancel();
    workplaceTimer?.cancel();
    final messageBridge = native;
    if (messageBridge != null && messageHandle != 0) messageBridge.stopMessageListener(messageHandle);
    final bridge = native;
    if (bridge != null && discoveryHandle != 0) {
      bridge.stopDiscovery(discoveryHandle);
    }
    super.dispose();
  }

  static const pages = <({IconData icon, String label})>[
    (icon: Icons.radar_outlined, label: 'Nearby'),
    (icon: Icons.workspaces_outlined, label: 'WorkPlace'),
    (icon: Icons.chat_bubble_outline, label: 'Messages'),
    (icon: Icons.folder_outlined, label: 'Files'),
    (icon: Icons.verified_user_outlined, label: 'Trusted devices'),
  ];

  void _showSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _SettingsDialog(
        native: native,
        dataDirectory: dataDirectory,
        trustedDeviceCount: trustedDevices.length,
      ),
    );
  }

  Widget build(BuildContext context) {
    final page = pages[selected];
    final body = _PageBody(
      label: page.label,
      peers: peers,
      scanning: scanning,
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
                    'Loading the local Capsi runtime…',
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
                    error ?? 'The local runtime is unavailable.',
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
                      Icon(page.icon, size: 20, color: const Color(0xFFB8F36B)),
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
        Icon(icon, size: 34, color: const Color(0xFFB8F36B)),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF858D88), height: 1.5)),
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
    decoration: BoxDecoration(color: const Color(0x18B8F36B), border: Border.all(color: const Color(0x30B8F36B)), borderRadius: BorderRadius.circular(11)),
    child: Icon(icon, size: 21, color: const Color(0xFFB8F36B)),
  );
}

class _CapsiMark extends StatelessWidget {
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

  const _SettingsDialog({
    required this.native,
    required this.dataDirectory,
    required this.trustedDeviceCount,
  });

  @override
  Widget build(BuildContext context) {
    final version = native?.runtimeVersion ?? '1.0.2';
    final protocol = native?.protocolVersion ?? 'Unavailable';

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
                title: 'Connection',
                children: [
                  _SettingsRow(
                    icon: Icons.wifi_outlined,
                    title: 'Direct communication',
                    subtitle: 'Capsi communicates device to device. No Capsi cloud is required.',
                    trailing: _NetworkStatus(available: native != null),
                  ),
                  _SettingsRow(
                    icon: Icons.radar_outlined,
                    title: 'Discovery',
                    subtitle: 'Discovery is used to find nearby Capsi devices.',
                    trailing: Icon(
                      native == null ? Icons.error_outline : Icons.check_circle_outline,
                      color: native == null ? Colors.orange : const Color(0xFFB8F36B),
                    ),
                  ),
                  _SettingsRow(
                    icon: Icons.message_outlined,
                    title: 'Messages',
                    subtitle: 'Messages use Capsi direct device-to-device transport.',
                    trailing: Icon(
                      native == null ? Icons.error_outline : Icons.check_circle_outline,
                      color: native == null ? Colors.orange : const Color(0xFFB8F36B),
                    ),
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
                  ),
                  const _SettingsRow(
                    icon: Icons.lock_outline,
                    title: 'Trust model',
                    subtitle: 'Only devices you accept can exchange messages and files.',
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
                    subtitle: dataDirectory ?? 'Application data directory unavailable',
                    trailing: dataDirectory == null
                        ? const Icon(Icons.error_outline)
                        : IconButton(
                            tooltip: 'Copy path',
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: dataDirectory!));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Data path copied.')),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_outlined),
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
                  _SettingsRow(
                    icon: Icons.info_outline,
                    title: 'Capsi',
                    subtitle: 'Messages and files, device to device.',
                    trailing: Text('v$version'),
                  ),
                  _SettingsRow(
                    icon: Icons.memory_outlined,
                    title: 'Runtime',
                    subtitle: native == null ? 'Rust core is not loaded.' : 'Rust core linked',
                    trailing: Text(protocol),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.open_in_new_outlined),
                    title: const Text('About Capsi'),
                    subtitle: const Text('Product, version and architecture information'),
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

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 3),
        leading: Icon(icon, color: const Color(0xFFB8F36B)),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(subtitle, style: const TextStyle(color: Color(0xFF858D88))),
        ),
        trailing: trailing,
      );
}

class _AboutDialog extends StatelessWidget {
  final CapsiNative? native;

  const _AboutDialog({required this.native});

  @override
  Widget build(BuildContext context) {
    final runtime = native?.runtimeVersion ?? 'Unavailable';
    final protocol = native?.protocolVersion ?? 'Unavailable';

    return AlertDialog(
      title: Row(
        children: [
          Image.asset('assets/capsi-logo-512.png', width: 38, height: 38),
          const SizedBox(width: 12),
          const Text('About Capsi'),
        ],
      ),
      content: const SizedBox(
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
            Text('CAPSICOM', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Capsi 1.0.2', style: TextStyle(color: Color(0xFF858D88))),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 6),
          child: Text(
            'Runtime $runtime · Protocol $protocol',
            style: const TextStyle(fontSize: 11, color: Color(0xFF666E69)),
          ),
        ),
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
          Icon(Icons.circle, size: 7, color: available ? const Color(0xFFB8F36B) : Colors.orange),
          const SizedBox(width: 7),
          Text(available ? 'Local network' : 'Core unavailable', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _PageBody extends StatefulWidget {
  final String label;
  final List<CapsiPeer> peers;
  final bool scanning;
  final CapsiNative? native;
  final VoidCallback onScan;
  final List<KnownDevice> trustedDevices;
  final VoidCallback onTrustChanged;
  final String? dataDirectory;
  final Map<String, dynamic>? workplaceData;
  const _PageBody({required this.label, required this.peers, required this.scanning, required this.native, required this.onScan, required this.trustedDevices, required this.onTrustChanged, required this.dataDirectory, required this.workplaceData});

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
    if (widget.label == 'WorkPlace') return _workplace(context);

    if (widget.label == 'Trusted devices') {
      return ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Text('Trusted devices', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Only devices you accept are allowed to exchange messages and files.'),
          const SizedBox(height: 20),
          if (widget.trustedDevices.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No trusted devices yet. Accept a device from Nearby to add it here.')))
          else
            for (final device in widget.trustedDevices)
              Card(child: ListTile(leading: const Icon(Icons.verified_user_outlined), title: Text(device.displayName), subtitle: Text(device.fingerprint))),
        ],
      );
    }

    if (widget.label == 'Messages') return _messages(context);
    if (widget.label == 'Files') return _files(context);

ListView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 40),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Devices around you', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Find devices directly. Accept a device to start sending messages and files.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF9AA19C))),
            ])),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: widget.scanning ? null : widget.onScan,
              icon: Icon(widget.scanning ? Icons.sync : Icons.radar_outlined),
              label: Text(widget.scanning ? 'Scanning…' : 'Scan'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (widget.peers.isEmpty)
          const _EmptyPanel(
            icon: Icons.radar_outlined,
            title: 'No devices found',
            message: 'Make sure the other device is running Capsi and both devices can communicate directly.',
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
        Row(children: [
          const Icon(Icons.security_outlined, size: 18, color: Color(0xFFB8F36B)),
          const SizedBox(width: 9),
          Text('Trusted devices control who Capsi can exchange with.', style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 8),
        Text(widget.native == null ? 'Rust core not packaged for this build yet.' : 'Rust ${widget.native!.runtimeVersion} · protocol ${widget.native!.protocolVersion}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF606863))),
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
            Text('Create your WorkPlace', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            const Text('A local workspace for your people, groups, departments and broadcasts. It lives with your Capsi installation.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: widget.dataDirectory == null || widget.native == null ? null : () => _createWorkplace(context),
              icon: const Icon(Icons.add),
              label: const Text('Create WorkPlace'),
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
                        child: Text('Create a group to start messaging.', textAlign: TextAlign.center),
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
                              trailing: IconButton(
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
            ],
          ),
        );

        Widget conversation() => Card(
          margin: EdgeInsets.only(left: compact ? 16 : 0, right: compact ? 16 : 28, bottom: 20),
          child: group == null
              ? const Center(child: Text('Select a group to view messages.'))
              : Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.group_outlined),
                      title: Text(group['name']?.toString() ?? 'Group'),
                      subtitle: Text('${(group['member_ids'] as List?)?.length ?? 0} members'),
                      trailing: IconButton(
                        tooltip: 'Add member',
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        onPressed: () => _addWorkplaceMember(context, group, members),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: groupMessages.isEmpty
                          ? const Center(child: Text('No messages in this group yet.'))
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
                            decoration: const InputDecoration(hintText: 'Message this group', border: OutlineInputBorder()),
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
                        Text(workspace['name']?.toString() ?? 'WorkPlace', style: Theme.of(context).textTheme.titleLarge),
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
                              (name) => widget.native!.createWorkplaceGroup(widget.dataDirectory!, name),
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
                  IconButton(onPressed: widget.onTrustChanged, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
                  if (compact)
                    PopupMenuButton<String>(
                      tooltip: 'WorkPlace actions',
                      enabled: widget.native != null && widget.dataDirectory != null,
                      onSelected: (value) {
                        if (value == 'group') {
                          _createWorkplaceName(
                            context,
                            'Create group',
                            (name) => widget.native!.createWorkplaceGroup(widget.dataDirectory!, name),
                          );
                        } else {
                          _createBroadcast(context);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'group', child: Text('Create group')),
                        PopupMenuItem(value: 'broadcast', child: Text('Create broadcast')),
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

  void _sendWorkplaceMessage() {
    final data = widget.dataDirectory;
    final native = widget.native;
    final text = workplaceController.text.trim();
    final workspace = widget.workplaceData;
    final groups = (workspace?['groups'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    final groupId = selectedWorkplaceGroup != null && groups.any((g) => g['id']?.toString() == selectedWorkplaceGroup)
        ? selectedWorkplaceGroup
        : (groups.isEmpty ? null : groups.first['id']?.toString());
    if (data == null || native == null || groupId == null || text.isEmpty) return;
    final result = native.sendWorkplaceMessage(data, groupId, text);
    if (result != null && result['error'] == null && mounted) {
      setState(() {
        workplaceDraft = '';
        workplaceController.clear();
      });
      widget.onTrustChanged();
    } else if (mounted && result?['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result!['error'].toString())));
    }
  }

  Future<void> _addWorkplaceMember(
    BuildContext context,
    Map<String, dynamic> group,
    List<Map<String, dynamic>> members,
  ) async {
    final current = (group['member_ids'] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
    final available = members.where((member) => !current.contains(member['device_id']?.toString())).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All WorkPlace members are already in this group.')));
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
    final result = widget.native!.addWorkplaceGroupMember(
      widget.dataDirectory!,
      group['id']?.toString() ?? '',
      chosen!['device_id']?.toString() ?? '',
    );
    if (result != null && result['error'] == null) {
      widget.onTrustChanged();
    } else if (mounted && result?['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result!['error'].toString())));
    }
  }

  Future<void> _createWorkplaceName(
    BuildContext context,
    String title,
    Map<String, dynamic>? Function(String name) action,
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
    final result = action(name);
    if (result != null) widget.onTrustChanged();
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
    final result = widget.native!.createWorkplaceBroadcast(widget.dataDirectory!, values.title, values.body);
    if (result != null) widget.onTrustChanged();
  }

  Future<void> _createWorkplace(BuildContext context) async {
    final controller = TextEditingController(text: 'My WorkPlace');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create WorkPlace'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.isEmpty || widget.dataDirectory == null || widget.native == null) return;
    final created = widget.native!.createWorkplace(widget.dataDirectory!, name);
    if (created != null) {
      widget.onTrustChanged();
      setState(() {});
    }
  }

  Widget _files(BuildContext context) {
    final data = widget.dataDirectory;
    final native = widget.native;
    final conversations = data == null || native == null
        ? const <Map<String, dynamic>>[]
        : native.conversations(data);
    final files = <({String deviceId, String name, Map<String, dynamic> file})>[];

    for (final conversation in conversations) {
      final deviceId = conversation['device_id']?.toString() ?? '';
      final name = conversation['name']?.toString() ?? 'Device';
      final messages = (conversation['messages'] as List?)
              ?.whereType<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      for (final message in messages) {
        final file = message['file'];
        if (message['kind'] == 'file' && file is Map<String, dynamic>) {
          files.add((deviceId: deviceId, name: name, file: file));
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
                        'Send files directly to trusted devices.',
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
                message: 'Choose a trusted device and send a file. Transfers stay device to device.',
              )
            else
              for (final item in files.reversed)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _DeviceIcon(icon: _fileIcon(item.file['file_name']?.toString() ?? '')),
                    title: Text(
                      item.file['file_name']?.toString() ?? 'File',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.name} · ${_formatBytes(item.file['size'])} · ${item.file['state'] ?? 'unknown'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      _fileStateIcon(item.file['state']?.toString()),
                      color: _fileStateColor(item.file['state']?.toString()),
                    ),
                  ),
                ),
          ],
        );
      },
    );
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
        return Icons.schedule_outlined;
      default:
        return Icons.sync_outlined;
    }
  }

  Color _fileStateColor(String? state) {
    switch (state?.toLowerCase()) {
      case 'complete':
      case 'completed':
      case 'delivered':
        return const Color(0xFFB8F36B);
      case 'failed':
      case 'error':
        return Colors.orange;
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

  Future<void> _pickAndSendFile() async {
    final data = widget.dataDirectory;
    final native = widget.native;
    if (data == null || native == null || widget.trustedDevices.isEmpty || !mounted) return;

    final selectedId = _validSelectedDevice() ?? widget.trustedDevices.first.deviceId;
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (!mounted || result == null || result.files.single.path == null) return;

    final transferId = native.sendFile(data, selectedId, result.files.single.path!);
    if (transferId == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File transfer failed.')),
      );
    } else if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File transfer started.')),
      );
    }
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
                ? const Color(0xFFB8F36B)
                : const Color(0xFF777E79),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: messages.isEmpty
              ? const _EmptyPanel(
                  icon: Icons.chat_bubble_outline,
                  title: 'No messages yet',
                  message: 'Send the first message to this device.',
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

  void _send() {
    final text = draft.trim();
    final data = widget.dataDirectory;
    final native = widget.native;
    if (text.isEmpty || data == null || native == null || selectedDevice == null) return;
    final id = native.sendMessage(data, selectedDevice!, text);
    if (id != null && mounted) setState(() => draft = '');
  }
}



class _WorkplaceStat extends StatelessWidget {
  final String label;
  final int value;
  const _WorkplaceStat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value.toString(), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ]),
    ),
  );
}
