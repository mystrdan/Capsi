import 'dart:async';
import 'dart:isolate';
import 'dart:io';

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
  final Set<String> _incomingOfferDialogs = <String>{};
  final Map<String, int> _transferReceived = <String, int>{};

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

  void _stopRuntimeSessions() {
    discoveryTimer?.cancel();
    discoveryTimer = null;
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
      }
    });
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
    _stopRuntimeSessions();
    super.dispose();
  }

  static const pages = <({IconData icon, String label})>[
    (icon: Icons.radar_outlined, label: 'Nearby'),
    (icon: Icons.workspaces_outlined, label: 'WorkPlace'),
    (icon: Icons.chat_bubble_outline, label: 'Messages'),
    (icon: Icons.folder_outlined, label: 'Files'),
    (icon: Icons.verified_user_outlined, label: 'Trusted devices'),
  ];

  Future<void> _showIncomingFileOffer(Map<String, dynamic> event) async {
    final transferId = event['transfer_id']?.toString();
    final deviceId = event['device_id']?.toString();
    if (transferId == null ||
        deviceId == null ||
        transferId.isEmpty ||
        deviceId.isEmpty ||
        _incomingOfferDialogs.contains(transferId) ||
        !mounted) {
      return;
    }

    _incomingOfferDialogs.add(transferId);
    final fileName = event['file_name']?.toString() ?? 'File';
    final size = event['size'];
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Incoming file'),
        content: Text(
          '${fileName}\n${_formatBytes(size)}\n\nThis file is being offered by a trusted device.',
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
    if (!mounted || accepted == null) return;
    await _decideIncomingFile(deviceId, transferId, accept: accepted);
  }

  Future<void> _cancelFileTransfer(String deviceId, String transferId) async {
    final data = dataDirectory;
    if (data == null) return;
    final result = await _nativeJsonInIsolate(
      data,
      'file_cancel',
      [deviceId, transferId],
    );
    if (!mounted) return;
    if (result?['ok'] == true) {
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The file could not be cancelled.')),
      );
    }
  }

  Future<void> _decideIncomingFile(
    String deviceId,
    String transferId, {
    required bool accept,
  }) async {
    final data = dataDirectory;
    if (data == null) return;
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
                ? 'The file could not be accepted.'
                : 'The file could not be declined.',
          ),
        ),
      );
    }
  }

  Widget _fileTransferSubtitle(({String deviceId, String name, bool outgoing, Map<String, dynamic> file}) item) {
    final state = item.file['state']?.toString() ?? 'unknown';
    final size = item.file['size'];
    final received = _transferReceived[item.file['transfer_id']?.toString() ?? ''];
    final progress = received != null && size is num && size > 0
        ? ' · ${(received / size * 100).clamp(0, 100).toStringAsFixed(0)}%'
        : '';
    return Text(
      '${item.name} · ${_formatBytes(size)} · $state$progress',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _fileTransferActions(({String deviceId, String name, bool outgoing, Map<String, dynamic> file}) item) {
    final state = item.file['state']?.toString().toLowerCase();
    final transferId = item.file['transfer_id']?.toString();
    if (transferId == null) {
      return Icon(_fileStateIcon(state), color: _fileStateColor(state));
    }
    if (!item.outgoing && state == 'offered') {
      return Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: 'Decline',
            onPressed: () => _respondToFile(item.deviceId, transferId, false),
            icon: const Icon(Icons.close_outlined),
          ),
          IconButton(
            tooltip: 'Accept',
            onPressed: () => _respondToFile(item.deviceId, transferId, true),
            icon: const Icon(Icons.check_outlined),
          ),
        ],
      );
    }
    if (state == 'transferring') {
      return IconButton(
        tooltip: 'Cancel',
        onPressed: () => _cancelFile(item.deviceId, transferId),
        icon: const Icon(Icons.close_outlined),
      );
    }
    return Icon(_fileStateIcon(state), color: _fileStateColor(state));
  }

  Future<void> _respondToFile(String deviceId, String transferId, bool accept) async {
    final data = dataDirectory;
    if (data == null) return;
    await _nativeJsonInIsolate(data, accept ? 'file_accept' : 'file_decline', [deviceId, transferId]);
    if (mounted) setState(() {});
  }

  Future<void> _cancelFile(String deviceId, String transferId) async {
    final data = dataDirectory;
    if (data == null) return;
    await _nativeJsonInIsolate(data, 'file_cancel', [deviceId, transferId]);
    if (mounted) setState(() {});
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
        return const Color(0xFFB8F36B);
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

  Future<void> _pickAndSendFile() async {
    final data = widget.dataDirectory;
    final native = widget.native;
    if (data == null || native == null || widget.trustedDevices.isEmpty || !mounted) return;

    final selectedId = _validSelectedDevice() ?? widget.trustedDevices.first.deviceId;
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (!mounted || result == null || result.files.single.path == null) return;

    final transferId = await _sendFileInIsolate(data, selectedId, result.files.single.path!);
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