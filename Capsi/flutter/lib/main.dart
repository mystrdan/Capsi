import 'dart:async';

import 'capsi_native.dart';
import 'package:file_picker/file_picker.dart';

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
  Map<String, dynamic>? lastMessageEvent;
  int selected = 0;
  CapsiNative? native;
  List<CapsiPeer> peers = const [];
  bool scanning = false;
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
    final directory = await getApplicationSupportDirectory();
    if (!mounted) return;
    dataDirectory = directory.path;
    if (native == null) return;
    _loadTrust();
    _loadWorkplace();
    workplaceTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadWorkplace());
    _startDiscovery();
    _startMessages();
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

  void _scan() => _pollDiscovery();

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
    (icon: Icons.near_me_outlined, label: 'Nearby'),
    (icon: Icons.workspaces_outlined, label: 'WorkPlace'),
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
                      _NetworkStatus(available: native != null),
                    ],
                  ),
                ),
                Expanded(child: _PageBody(label: page.label, peers: peers, scanning: scanning, native: native, onScan: _scan, trustedDevices: trustedDevices, onTrustChanged: () { _loadTrust(); _loadWorkplace(); }, dataDirectory: dataDirectory, workplaceData: workplaceData)),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
  final bool available;
  const _NetworkStatus({required this.available});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(Icons.circle, size: 9, color: available ? const Color(0xFF7AC943) : Colors.orange),
      label: Text(available ? 'Local network' : 'Native core unavailable'),
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
                Text(widget.peers.isEmpty ? 'No Nearby devices yet' : '${widget.peers.length} device${widget.peers.length == 1 ? '' : 's'} found', style: Theme.of(context).textTheme.titleLarge),
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
                Text(widget.native == null ? 'Rust core not packaged for this build yet.' : 'Rust ${widget.native!.runtimeVersion} · ${widget.native!.protocolVersion}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                const Text('Run it. Find devices. Send.', style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Row(
            children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(workspace['name']?.toString() ?? 'WorkPlace', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('${members.length} people · ${groups.length} groups · ${departments.length} departments'),
              ])),
              OutlinedButton.icon(
                onPressed: widget.native == null || widget.dataDirectory == null
                    ? null
                    : () => _createWorkplaceName(context, 'Create group', (name) => widget.native!.createWorkplaceGroup(widget.dataDirectory!, name)),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Group'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.native == null || widget.dataDirectory == null ? null : () => _createBroadcast(context),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Broadcast'),
              ),
              IconButton(onPressed: widget.onTrustChanged, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 290,
                child: Card(
                  margin: const EdgeInsets.only(left: 28, right: 12, bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(children: [
                          Text('Groups', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          Text(groups.length.toString(), style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: groups.isEmpty
                            ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Create a group to start messaging.', textAlign: TextAlign.center)))
                            : ListView(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                children: [
                                  for (final item in groups)
                                    ListTile(
                                      selected: item['id']?.toString() == groupId,
                                      leading: const Icon(Icons.group_outlined),
                                      title: Text(item['name']?.toString() ?? 'Group'),
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
                ),
              ),
              Expanded(
                child: Card(
                  margin: const EdgeInsets.only(right: 28, bottom: 20),
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
                                                    if (!outgoing) Text(sender?['display_name']?.toString() ?? 'Member', style: Theme.of(context).textTheme.labelSmall),
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
                                    onChanged: (value) => workplaceDraft = value,
                                    onSubmitted: (_) => _sendWorkplaceMessage(),
                                    decoration: const InputDecoration(hintText: 'Message this group', border: OutlineInputBorder()),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  onPressed: _sendWorkplaceMessage,
                                  icon: const Icon(Icons.send),
                                  label: const Text('Send'),
                                ),
                              ]),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
        if (departments.isNotEmpty || broadcasts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
            child: Row(children: [
              Text('Departments ${departments.length}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 18),
              Text('Broadcasts ${broadcasts.length}', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
      ],
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
        : groups.firstOrNull?['id']?.toString();
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
    final conversations = data == null || native == null ? const <Map<String, dynamic>>[] : native.conversations(data);
    final files = <({String deviceId, String name, Map<String, dynamic> file})>[];
    for (final conversation in conversations) {
      final deviceId = conversation['device_id']?.toString() ?? '';
      final name = conversation['name']?.toString() ?? 'Device';
      final messages = (conversation['messages'] as List?)?.whereType<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      for (final message in messages) {
        final file = message['file'];
        if (message['kind'] == 'file' && file is Map<String, dynamic>) {
          files.add((deviceId: deviceId, name: name, file: file));
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          children: [
            Text('Files', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: widget.trustedDevices.isEmpty ? null : _pickAndSendFile,
              icon: const Icon(Icons.attach_file),
              label: const Text('Send file'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Files move directly between trusted devices. Nothing is uploaded to a cloud service.'),
        const SizedBox(height: 20),
        if (files.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No file transfers yet.')))
        else
          for (final item in files.reversed)
            Card(
              child: ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(item.file['file_name']?.toString() ?? 'File'),
                subtitle: Text('${item.name} · ${item.file['size'] ?? 0} bytes · ${item.file['state'] ?? 'unknown'}'),
              ),
            ),
      ],
    );
  }

  Future<void> _pickAndSendFile() async {
    final data = widget.dataDirectory;
    final native = widget.native;
    if (data == null || native == null || widget.trustedDevices.isEmpty || !mounted) return;
    final selectedId = selectedDevice ?? widget.trustedDevices.first.deviceId;
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (!mounted || result == null || result.files.single.path == null) return;
    final transferId = native.sendFile(data, selectedId, result.files.single.path!);
    if (transferId == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File transfer failed.')));
    } else if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File transfer started.')));
    }
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
                    IconButton(onPressed: widget.trustedDevices.isEmpty ? null : _pickAndSendFile, tooltip: 'Send file', icon: const Icon(Icons.attach_file)),
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
