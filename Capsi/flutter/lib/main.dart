import 'dart:async';

import 'capsi_native.dart';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    native = CapsiNative.tryLoad();
    _startDiscovery();
  }

  void _startDiscovery() {
    final bridge = native;
    if (bridge == null) return;
    discoveryHandle = bridge.startDiscovery(deviceName: 'Capsi device');
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
                Expanded(child: _PageBody(label: page.label, peers: peers, scanning: scanning, native: native, onScan: _scan)),
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

class _PageBody extends StatelessWidget {
  final String label;
  final List<CapsiPeer> peers;
  final bool scanning;
  final CapsiNative? native;
  final VoidCallback onScan;
  const _PageBody({required this.label, required this.peers, required this.scanning, required this.native, required this.onScan});

  @override
  Widget build(BuildContext context) {
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
                Text(peers.isEmpty ? 'No $label yet' : '${peers.length} device${peers.length == 1 ? '' : 's'} found', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                const Text(
                  'Capsi is ready for the Rust core. The Flutter interface is now the shared UI foundation for Windows, Android, macOS and iOS.',
                  textAlign: TextAlign.center,
                ),
                if (label == 'Nearby' && peers.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  for (final peer in peers.take(8))
                    ListTile(leading: const Icon(Icons.computer_outlined), title: Text(peer.name), subtitle: Text(peer.fingerprint.isEmpty ? peer.tcpAddress : peer.fingerprint)),
                ],
                const SizedBox(height: 20),
                if (label == 'Nearby') OutlinedButton.icon(onPressed: scanning ? null : onScan, icon: Icon(scanning ? Icons.sync : Icons.refresh), label: Text(scanning ? 'Scanning…' : 'Scan again')),
                const SizedBox(height: 12),
                Text(native == null ? 'Rust core not packaged for this build yet.' : 'Rust ${native!.runtimeVersion} · ${native!.protocolVersion}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                const Text('Run it. Find devices. Send.', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
