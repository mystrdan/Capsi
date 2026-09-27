import 'dart:async';

import 'capsi_native.dart';
import 'package:flutter/material.dart';
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
        scaffoldBackgroundColor: const Color(0xFF0B0D0E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7AC943),
          brightness: Brightness.dark,
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
  int selected = 0;
  CapsiNative? native;
  List<CapsiPeer> peers = const [];
  bool scanning = false;
  int discoveryHandle = 0;
  Timer? discoveryTimer;
  String? dataDirectory;
  List<KnownDevice> trustedDevices = const [];
  int messageHandle = 0;
  Timer? messageTimer;

  @override
  void initState() {
    super.initState();
    native = CapsiNative.tryLoad();
    _initializeRuntime();
  }

  Future<void> _initializeRuntime() async {
    final directory = await getApplicationSupportDirectory();
    if (!mounted) return;
    dataDirectory = directory.path;
    if (native == null) return;
    _loadTrust();
    _startDiscovery();
    _startMessages();
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
      bridge.pollMessage(messageHandle);
      setState(() {});
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

  void _scan() => _pollDiscovery();

  @override
  void dispose() {
    discoveryTimer?.cancel();
    messageTimer?.cancel();
    final messageBridge = native;
    if (messageBridge != null && messageHandle != 0) messageBridge.stopMessageListener(messageHandle);
    final bridge = native;
    if (bridge != null && discoveryHandle != 0) {
      bridge.stopDiscovery(discoveryHandle);
    }
    super.dispose();
  }

  static const pages = <({IconData icon, String label})>[
    (icon: Icons.near_me_outlined, label: 'Nearby'),
    (icon: Icons.chat_bubble_outline, label: 'Messages'),
    (icon: Icons.folder_outlined, label: 'Files'),
    (icon: Icons.devices_other_outlined, label: 'Trusted devices'),
  ];

  @override
  Widget build(BuildContext context) {
    final page = pages[selected];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: (index) => setState(() => selected = index),
            backgroundColor: const Color(0xFF101314),
            leading: Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 28),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                  child: Row(
                    children: [
                      Text(page.label, style: Theme.of(context).textTheme.headlineSmall),
                      const Spacer(),
                      const _NetworkStatus(),
                    ],
                  ),
                ),
                Expanded(child: _PageBody(label: page.label, peers: peers, scanning: scanning, native: native, onScan: _scan, trustedDevices: trustedDevices, onTrustChanged: _loadTrust, dataDirectory: dataDirectory)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<CapsiPeer> _probePeers() {
  final bridge = CapsiNative.tryLoad();
  if (bridge == null) return const [];
  return bridge.discoveryProbe(deviceName: 'Capsi device');
}

class _CapsiMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: const Text('C', style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.w800)),
    );
  }
}

class _NetworkStatus extends StatelessWidget {
  const _NetworkStatus();

  @override
  Widget build(BuildContext context) {
    return const Chip(
      avatar: Icon(Icons.circle, size: 9, color: Color(0xFF7AC943)),
      label: Text('Local network'),
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
  const _PageBody({required this.label, required this.peers, required this.scanning, required this.native, required this.onScan, required this.trustedDevices, required this.onTrustChanged, required this.dataDirectory});

  @override
  State<_PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<_PageBody> {
  String? selectedDevice;
  String draft = '';

  @override
  Widget build(BuildContext context) {
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
    if (widget.label == 'Files') {
      return const Center(child: Text('File transfer UI is next; the Rust protocol already defines encrypted offers, receipts and chunks.'));
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Card(
          color: const Color(0xFF111516),
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.devices_outlined, size: 54, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 20),
                Text(widget.peers.isEmpty ? 'No Nearby devices yet' : widget.peers.length.toString() + ' device' + (widget.peers.length == 1 ? '' : 's') + ' found', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                const Text('Capsi finds devices directly on the local network. No cloud service or account is involved.', textAlign: TextAlign.center),
                if (widget.peers.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  for (final peer in widget.peers.take(8))
                    ListTile(
                      leading: const Icon(Icons.computer_outlined),
                      title: Text(peer.name),
                      subtitle: Text(peer.fingerprint.isEmpty ? peer.tcpAddress : peer.fingerprint),
                      trailing: widget.dataDirectory == null ? null : FilledButton(
                        onPressed: () {
                          final accepted = widget.native?.acceptTrust(widget.dataDirectory!, peer.deviceId);
                          if (accepted != null) widget.onTrustChanged();
                        },
                        child: const Text('Accept'),
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(onPressed: widget.scanning ? null : widget.onScan, icon: Icon(widget.scanning ? Icons.sync : Icons.refresh), label: Text(widget.scanning ? 'Scanning…' : 'Scan again')),
                const SizedBox(height: 12),
                Text(widget.native == null ? 'Rust core not packaged for this build yet.' : 'Rust ' + widget.native!.runtimeVersion + ' · ' + widget.native!.protocolVersion, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                const Text('Run it. Find devices. Send.', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _messages(BuildContext context) {
    final devices = widget.trustedDevices;
    if (devices.isEmpty) return const Center(child: Text('Accept a device from Nearby before starting a conversation.'));
    selectedDevice ??= devices.first.deviceId;
    final selected = devices.firstWhere((d) => d.deviceId == selectedDevice, orElse: () => devices.first);
    final data = widget.dataDirectory;
    final native = widget.native;
    final conversation = data == null || native == null ? null : native.conversation(data, selected.deviceId);
    final messages = (conversation?['messages'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const <Map<String, dynamic>>[];

    return Row(
      children: [
        SizedBox(
          width: 260,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final device in devices)
                ListTile(
                  selected: device.deviceId == selected.deviceId,
                  leading: const Icon(Icons.computer_outlined),
                  title: Text(device.displayName),
                  subtitle: Text(device.state),
                  onTap: () => setState(() => selectedDevice = device.deviceId),
                ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              ListTile(title: Text(selected.displayName), subtitle: Text(selected.fingerprint)),
              const Divider(height: 1),
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Text('No messages yet. Say hello.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: messages.length,
                        itemBuilder: (_, index) {
                          final message = messages[index];
                          final outgoing = message['outgoing'] == true;
                          return Align(
                            alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
                            child: Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text(message['body']?.toString() ?? ''))),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: TextField(onChanged: (value) => draft = value, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Message', border: OutlineInputBorder()))),
                    const SizedBox(width: 10),
                    FilledButton.icon(onPressed: _send, icon: const Icon(Icons.send), label: const Text('Send')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
\n