import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef _RuntimeVersionNative = ffi.Pointer<ffi.Char> Function();
typedef _RuntimeVersionDart = ffi.Pointer<ffi.Char> Function();

typedef _CoreLinkedNative = ffi.Int32 Function();
typedef _CoreLinkedDart = int Function();

typedef _ProtocolVersionNative = ffi.Pointer<ffi.Char> Function();
typedef _ProtocolVersionDart = ffi.Pointer<ffi.Char> Function();

typedef _DiscoveryProbeNative = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<ffi.Char>,
  ffi.Uint16,
  ffi.Uint32,
);
typedef _DiscoveryProbeDart = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<ffi.Char>,
  int,
  int,
);


typedef _DiscoveryStartNative = ffi.Uint64 Function(ffi.Pointer<ffi.Char>, ffi.Uint16, ffi.Pointer<ffi.Char>);
typedef _DiscoveryStartDart = int Function(ffi.Pointer<ffi.Char>, int, ffi.Pointer<ffi.Char>);

typedef _DiscoveryPollNative = ffi.Pointer<ffi.Char> Function(ffi.Uint64);
typedef _DiscoveryPollDart = ffi.Pointer<ffi.Char> Function(int);

typedef _DiscoveryStopNative = ffi.Void Function(ffi.Uint64);
typedef _DiscoveryStopDart = void Function(int);

typedef _TrustListNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef _TrustListDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);

typedef _TrustActionNative = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Char>,
);

typedef _TrustAcceptNative = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Char>,
);
typedef _TrustActionDart = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Char>,
);

typedef _TrustAcceptDart = ffi.Pointer<ffi.Char> Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Char>,
);

typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<ffi.Char>);
typedef _FreeStringDart = void Function(ffi.Pointer<ffi.Char>);
typedef _MessageStartNative = ffi.Uint64 Function(ffi.Pointer<ffi.Char>, ffi.Uint16);
typedef _MessageStartDart = int Function(ffi.Pointer<ffi.Char>, int);
typedef _MessagePollNative = ffi.Pointer<ffi.Char> Function(ffi.Uint64);
typedef _MessagePollDart = ffi.Pointer<ffi.Char> Function(int);
typedef _MessageStopNative = ffi.Void Function(ffi.Uint64);
typedef _MessageStopDart = void Function(int);
typedef _MessageSendNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _MessageSendDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _ConversationListNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef _ConversationListDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef _ConversationLoadNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _ConversationLoadDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _FileSendNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _FileSendDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _FileActionNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _FileActionDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WorkplaceLoadNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef _WorkplaceLoadDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>);
typedef _WorkplaceCreateNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WorkplaceCreateDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WorkplaceNameActionNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WorkplaceNameActionDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WorkplaceBroadcastNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WorkplaceBroadcastDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WorkplaceSendNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WorkplaceSendDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WorkplaceAddMemberNative = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);
typedef _WorkplaceAddMemberDart = ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>);

class KnownDevice {
  const KnownDevice({required this.deviceId, required this.name, this.alias, required this.state, required this.fingerprint, this.lastAddress});
  final String deviceId;
  final String name;
  final String? alias;
  final String state;
  final String fingerprint;
  final String? lastAddress;
  String get displayName => alias?.isNotEmpty == true ? alias! : name;
  factory KnownDevice.fromJson(Map<String, dynamic> json) => KnownDevice(
    deviceId: json['device_id']?.toString() ?? '', name: json['name']?.toString() ?? 'Unknown',
    alias: json['alias']?.toString(), state: json['state']?.toString() ?? 'pending',
    fingerprint: json['fingerprint']?.toString() ?? '', lastAddress: json['last_address']?.toString());
}

class CapsiPeer {
  const CapsiPeer({
    required this.name,
    required this.deviceId,
    required this.address,
    required this.port,
    required this.fingerprint,
    required this.lastSeen,
  });

  final String name;
  final String deviceId;
  final String address;
  final int port;
  final String fingerprint;
  final int lastSeen;

  String get tcpAddress => '$address:$port';

  factory CapsiPeer.fromJson(Map<String, dynamic> json) {
    final rawDeviceId = json['device_id'];
    final deviceId = rawDeviceId is Map<String, dynamic> ? rawDeviceId['0']?.toString() : rawDeviceId?.toString();
    final fingerprint = json['fingerprint'] as String?;
    final address = json['address'] as String?;
    return CapsiPeer(
      name: json['name'] as String? ?? 'Unknown device',
      deviceId: deviceId ?? 'unknown',
      address: address ?? 'unknown',
      port: json['port'] as int? ?? 0,
      fingerprint: fingerprint ?? '',
      lastSeen: json['last_seen'] as int? ?? 0,
    );
  }
}

/// Thin Dart wrapper around the shared Capsi Rust core.
///
/// The wrapper is intentionally optional during the migration: the Flutter UI
/// can start before the native library is packaged for a target platform.
class CapsiNative {
  CapsiNative._(ffi.DynamicLibrary library)
      : _runtimeVersion = library.lookupFunction<_RuntimeVersionNative, _RuntimeVersionDart>('capsi_runtime_version'),
        _coreLinked = library.lookupFunction<_CoreLinkedNative, _CoreLinkedDart>('capsi_core_linked'),
        _protocolVersion = library.lookupFunction<_ProtocolVersionNative, _ProtocolVersionDart>('capsi_protocol_version'),
        _discoveryProbe = library.lookupFunction<_DiscoveryProbeNative, _DiscoveryProbeDart>('capsi_discovery_probe'),
        _discoveryStart = library.lookupFunction<_DiscoveryStartNative, _DiscoveryStartDart>('capsi_discovery_start'),
        _trustList = library.lookupFunction<_TrustListNative, _TrustListDart>('capsi_trust_list'),
        _trustAccept = library.lookupFunction<_TrustAcceptNative, _TrustAcceptDart>('capsi_trust_accept'),
        _trustIgnore = library.lookupFunction<_TrustActionNative, _TrustActionDart>('capsi_trust_ignore'),
        _discoveryPoll = library.lookupFunction<_DiscoveryPollNative, _DiscoveryPollDart>('capsi_discovery_poll'),
        _discoveryStop = library.lookupFunction<_DiscoveryStopNative, _DiscoveryStopDart>('capsi_discovery_stop'),
        _messageStart = library.lookupFunction<_MessageStartNative, _MessageStartDart>('capsi_message_start'),
        _messagePoll = library.lookupFunction<_MessagePollNative, _MessagePollDart>('capsi_message_poll'),
        _messageStop = library.lookupFunction<_MessageStopNative, _MessageStopDart>('capsi_message_stop'),
        _messageSend = library.lookupFunction<_MessageSendNative, _MessageSendDart>('capsi_message_send'),
        _conversationList = library.lookupFunction<_ConversationListNative, _ConversationListDart>('capsi_conversations_list'),
        _conversationLoad = library.lookupFunction<_ConversationLoadNative, _ConversationLoadDart>('capsi_conversation_load'),
        _fileSend = library.lookupFunction<_FileSendNative, _FileSendDart>('capsi_file_send'),
        _fileAccept = library.lookupFunction<_FileActionNative, _FileActionDart>('capsi_file_accept'),
        _fileDecline = library.lookupFunction<_FileActionNative, _FileActionDart>('capsi_file_decline'),
        _workplaceLoad = library.lookupFunction<_WorkplaceLoadNative, _WorkplaceLoadDart>('capsi_workplace_load'),
        _workplaceCreate = library.lookupFunction<_WorkplaceCreateNative, _WorkplaceCreateDart>('capsi_workplace_create'),
        _workplaceCreateGroup = library.lookupFunction<_WorkplaceNameActionNative, _WorkplaceNameActionDart>('capsi_workplace_create_group'),
        _workplaceCreateDepartment = library.lookupFunction<_WorkplaceNameActionNative, _WorkplaceNameActionDart>('capsi_workplace_create_department'),
        _workplaceCreateBroadcast = library.lookupFunction<_WorkplaceBroadcastNative, _WorkplaceBroadcastDart>('capsi_workplace_create_broadcast'),
        _workplaceSendMessage = library.lookupFunction<_WorkplaceSendNative, _WorkplaceSendDart>('capsi_workplace_send_message'),
        _workplaceAddGroupMember = library.lookupFunction<_WorkplaceAddMemberNative, _WorkplaceAddMemberDart>('capsi_workplace_add_group_member'),
        _freeString = library.lookupFunction<_FreeStringNative, _FreeStringDart>('capsi_free_string');

  // Library is retained by the function pointers; no direct field access is needed.
  final _RuntimeVersionDart _runtimeVersion;
  final _CoreLinkedDart _coreLinked;
  final _ProtocolVersionDart _protocolVersion;
  final _DiscoveryProbeDart _discoveryProbe;
  final _DiscoveryStartDart _discoveryStart;
  final _TrustListDart _trustList;
  final _TrustAcceptDart _trustAccept;
  final _TrustActionDart _trustIgnore;
  final _DiscoveryPollDart _discoveryPoll;
  final _DiscoveryStopDart _discoveryStop;
  final _MessageStartDart _messageStart;
  final _MessagePollDart _messagePoll;
  final _MessageStopDart _messageStop;
  final _MessageSendDart _messageSend;
  final _ConversationListDart _conversationList;
  final _ConversationLoadDart _conversationLoad;
  final _FileSendDart _fileSend;
  final _FileActionDart _fileAccept;
  final _FileActionDart _fileDecline;
  final _FreeStringDart _freeString;
  final _WorkplaceLoadDart _workplaceLoad;
  final _WorkplaceCreateDart _workplaceCreate;
  final _WorkplaceNameActionDart _workplaceCreateGroup;
  final _WorkplaceNameActionDart _workplaceCreateDepartment;
  final _WorkplaceBroadcastDart _workplaceCreateBroadcast;
  final _WorkplaceSendDart _workplaceSendMessage;
  final _WorkplaceAddMemberDart _workplaceAddGroupMember;

  static CapsiNative? tryLoad() {
    final candidates = <String>[
      if (Platform.isWindows) 'capsi_ffi.dll',
      if (Platform.isAndroid) 'libcapsi_ffi.so',
      if (Platform.isIOS) 'process',
      if (Platform.isMacOS) 'libcapsi_ffi.dylib',
      if (Platform.isLinux) 'libcapsi_ffi.so',
    ];

    for (final candidate in candidates) {
      try {
        final library = candidate == 'process' ? ffi.DynamicLibrary.process() : ffi.DynamicLibrary.open(candidate);
        return CapsiNative._(library);
      } catch (_) {
        // The native artifact is packaged separately by the platform build.
      }
    }
    return null;
  }

  Map<String, dynamic>? workplace(String dataDirectory) {
    final dir = dataDirectory.toNativeUtf8();
    try {
      final pointer = _workplaceLoad(dir.cast<ffi.Char>());
      if (pointer == ffi.nullptr) return null;
      try {
        final value = jsonDecode(_readString(pointer));
        return value is Map<String, dynamic> ? value : null;
      } finally {
        _freeString(pointer);
      }
    } finally {
      calloc.free(dir);
    }
  }

  Map<String, dynamic>? createWorkplace(String dataDirectory, String name) {
    final dir = dataDirectory.toNativeUtf8();
    final workplaceName = name.toNativeUtf8();
    try {
      final pointer = _workplaceCreate(dir.cast<ffi.Char>(), workplaceName.cast<ffi.Char>());
      if (pointer == ffi.nullptr) return null;
      try {
        final value = jsonDecode(_readString(pointer));
        return value is Map<String, dynamic> ? value : null;
      } finally {
        _freeString(pointer);
      }
    } finally {
      calloc.free(dir);
      calloc.free(workplaceName);
    }
  }

  Map<String, dynamic>? createWorkplaceGroup(String dataDirectory, String name) => _workplaceNameAction(_workplaceCreateGroup, dataDirectory, name);

  Map<String, dynamic>? createWorkplaceDepartment(String dataDirectory, String name) => _workplaceNameAction(_workplaceCreateDepartment, dataDirectory, name);

  Map<String, dynamic>? addWorkplaceGroupMember(String dataDirectory, String groupId, String deviceId) {
    final d = dataDirectory.toNativeUtf8();
    final g = groupId.toNativeUtf8();
    final m = deviceId.toNativeUtf8();
    try {
      return _readJson(_workplaceAddGroupMember(d.cast(), g.cast(), m.cast()));
    } finally {
      malloc.free(d); malloc.free(g); malloc.free(m);
    }
  }

  Map<String, dynamic>? sendWorkplaceMessage(String dataDirectory, String groupId, String body) {
    final d = dataDirectory.toNativeUtf8();
    final g = groupId.toNativeUtf8();
    final b = body.toNativeUtf8();
    try {
      return _readJson(_workplaceSendMessage(d.cast(), g.cast(), b.cast()));
    } finally {
      malloc.free(d); malloc.free(g); malloc.free(b);
    }
  }

  Map<String, dynamic>? createWorkplaceBroadcast(String dataDirectory, String title, String body) {
    final d = dataDirectory.toNativeUtf8();
    final t = title.toNativeUtf8();
    final b = body.toNativeUtf8();
    try {
      return _readJson(_workplaceCreateBroadcast(d.cast(), t.cast(), b.cast()));
    } finally {
      malloc.free(d); malloc.free(t); malloc.free(b);
    }
  }

  Map<String, dynamic>? _workplaceNameAction(_WorkplaceNameActionDart action, String dataDirectory, String name) {
    final d = dataDirectory.toNativeUtf8();
    final n = name.toNativeUtf8();
    try {
      return _readJson(action(d.cast(), n.cast()));
    } finally {
      malloc.free(d); malloc.free(n);
    }
  }

  String get runtimeVersion => _readString(_runtimeVersion());
  String get protocolVersion => _readString(_protocolVersion());
  bool get coreLinked => _coreLinked() != 0;

  List<CapsiPeer> discoveryProbe({
    required String deviceName,
    int tcpPort = 45893,
    Duration wait = const Duration(milliseconds: 500),
  }) {
    final nativeName = deviceName.toNativeUtf8();
    try {
      final pointer = _discoveryProbe(
        nativeName.cast<ffi.Char>(),
        tcpPort,
        wait.inMilliseconds,
      );
      if (pointer == ffi.nullptr) return const [];
      try {
        final value = jsonDecode(_readString(pointer));
        if (value is! List) return const [];
        return value
            .whereType<Map<String, dynamic>>()
            .map(CapsiPeer.fromJson)
            .toList(growable: false);
      } finally {
        _freeString(pointer);
      }
    } finally {
      calloc.free(nativeName);
    }
  }


  int startDiscovery({required String deviceName, int tcpPort = 45893, required String dataDirectory}) {
    final nativeName = deviceName.toNativeUtf8();
    final nativeDir = dataDirectory.toNativeUtf8();
    try {
      return _discoveryStart(nativeName.cast<ffi.Char>(), tcpPort, nativeDir.cast<ffi.Char>());
    } finally {
      calloc.free(nativeName);
      calloc.free(nativeDir);
    }
  }

  List<CapsiPeer> pollDiscovery(int handle) {
    final pointer = _discoveryPoll(handle);
    if (pointer == ffi.nullptr) return const [];
    try {
      final value = jsonDecode(_readString(pointer));
      if (value is! List) return const [];
      return value
          .whereType<Map<String, dynamic>>()
          .map(CapsiPeer.fromJson)
          .toList(growable: false);
    } finally {
      _freeString(pointer);
    }
  }

  List<KnownDevice> trustList(String dataDirectory) => _decodeTrust(
        _callTrust(_trustList, dataDirectory),
      );

  KnownDevice? acceptTrust(String dataDirectory, String deviceId, {String? alias}) {
    final dir = dataDirectory.toNativeUtf8();
    final id = deviceId.toNativeUtf8();
    final nativeAlias = (alias ?? '').toNativeUtf8();
    try {
      return _decodeKnownDevice(_trustAccept(
        dir.cast<ffi.Char>(), id.cast<ffi.Char>(), nativeAlias.cast<ffi.Char>(),
      ));
    } finally {
      calloc.free(dir);
      calloc.free(id);
      calloc.free(nativeAlias);
    }
  }

  KnownDevice? ignoreTrust(String dataDirectory, String deviceId) {
    final pointer = _callTrustAction(_trustIgnore, dataDirectory, deviceId);
    return _decodeKnownDevice(pointer);
  }

  void stopDiscovery(int handle) => _discoveryStop(handle);

  int startMessageListener({required String dataDirectory, int tcpPort = 45892}) {
    final dir = dataDirectory.toNativeUtf8();
    try { return _messageStart(dir.cast<ffi.Char>(), tcpPort); }
    finally { calloc.free(dir); }
  }

  Map<String, dynamic>? pollMessage(int handle) {
    final pointer = _messagePoll(handle);
    if (pointer == ffi.nullptr) return null;
    try {
      final value = jsonDecode(_readString(pointer));
      return value is Map<String, dynamic> ? value : null;
    } finally { _freeString(pointer); }
  }

  void stopMessageListener(int handle) => _messageStop(handle);

  String? sendMessage(String dataDirectory, String deviceId, String body) {
    final dir = dataDirectory.toNativeUtf8();
    final id = deviceId.toNativeUtf8();
    final text = body.toNativeUtf8();
    try {
      final pointer = _messageSend(dir.cast<ffi.Char>(), id.cast<ffi.Char>(), text.cast<ffi.Char>());
      if (pointer == ffi.nullptr) return null;
      try {
        final value = jsonDecode(_readString(pointer));
        return value is String ? value : null;
      } finally { _freeString(pointer); }
    } finally {
      calloc.free(dir); calloc.free(id); calloc.free(text);
    }
  }

  List<Map<String, dynamic>> conversations(String dataDirectory) {
    final dir = dataDirectory.toNativeUtf8();
    try {
      final pointer = _conversationList(dir.cast<ffi.Char>());
      if (pointer == ffi.nullptr) return const [];
      try {
        final value = jsonDecode(_readString(pointer));
        if (value is! List) return const [];
        return value.whereType<Map<String, dynamic>>().toList(growable: false);
      } finally { _freeString(pointer); }
    } finally { calloc.free(dir); }
  }

  String? sendFile(String dataDirectory, String deviceId, String filePath) {
    final dir = dataDirectory.toNativeUtf8();
    final id = deviceId.toNativeUtf8();
    final path = filePath.toNativeUtf8();
    try {
      final pointer = _fileSend(dir.cast<ffi.Char>(), id.cast<ffi.Char>(), path.cast<ffi.Char>());
      if (pointer == ffi.nullptr) return null;
      try {
        final value = jsonDecode(_readString(pointer));
        return value is String ? value : null;
      } finally {
        _freeString(pointer);
      }
    } finally {
      calloc.free(dir);
      calloc.free(id);
      calloc.free(path);
    }
  }

  bool acceptFile(String dataDirectory, String deviceId, String transferId) =>
      _fileAction(_fileAccept, dataDirectory, deviceId, transferId);

  bool declineFile(String dataDirectory, String deviceId, String transferId) =>
      _fileAction(_fileDecline, dataDirectory, deviceId, transferId);

  bool _fileAction(
    _FileActionDart action,
    String dataDirectory,
    String deviceId,
    String transferId,
  ) {
    final d = dataDirectory.toNativeUtf8();
    final id = deviceId.toNativeUtf8();
    final t = transferId.toNativeUtf8();
    try {
      final value = _readJson(action(d.cast(), id.cast(), t.cast()));
      return value == true;
    } finally {
      calloc.free(d);
      calloc.free(id);
      calloc.free(t);
    }
  }

  Map<String, dynamic>? conversation(String dataDirectory, String deviceId) {
    final dir = dataDirectory.toNativeUtf8();
    final id = deviceId.toNativeUtf8();
    try {
      final pointer = _conversationLoad(dir.cast<ffi.Char>(), id.cast<ffi.Char>());
      if (pointer == ffi.nullptr) return null;
      try {
        final value = jsonDecode(_readString(pointer));
        return value is Map<String, dynamic> ? value : null;
      } finally { _freeString(pointer); }
    } finally { calloc.free(dir); calloc.free(id); }
  }

  ffi.Pointer<ffi.Char> _callTrust(
    _TrustListDart fn,
    String dataDirectory,
  ) {
    final dir = dataDirectory.toNativeUtf8();
    try {
      return fn(dir.cast<ffi.Char>());
    } finally {
      calloc.free(dir);
    }
  }

  ffi.Pointer<ffi.Char> _callTrustAction(
    _TrustActionDart fn,
    String dataDirectory,
    String deviceId,
  ) {
    final dir = dataDirectory.toNativeUtf8();
    final id = deviceId.toNativeUtf8();
    try {
      return fn(dir.cast<ffi.Char>(), id.cast<ffi.Char>());
    } finally {
      calloc.free(dir);
      calloc.free(id);
    }
  }

  List<KnownDevice> _decodeTrust(ffi.Pointer<ffi.Char> pointer) {
    if (pointer == ffi.nullptr) return const [];
    try {
      final value = jsonDecode(_readString(pointer));
      if (value is! List) return const [];
      return value
          .whereType<Map<String, dynamic>>()
          .map(KnownDevice.fromJson)
          .toList(growable: false);
    } finally {
      _freeString(pointer);
    }
  }

  KnownDevice? _decodeKnownDevice(ffi.Pointer<ffi.Char> pointer) {
    if (pointer == ffi.nullptr) return null;
    try {
      final value = jsonDecode(_readString(pointer));
      if (value is! Map<String, dynamic>) return null;
      return KnownDevice.fromJson(value);
    } finally {
      _freeString(pointer);
    }
  }

  Map<String, dynamic>? _readJson(ffi.Pointer<ffi.Char> pointer) {
    if (pointer == ffi.nullptr) return null;
    try {
      final value = jsonDecode(_readString(pointer));
      return value is Map<String, dynamic> ? value : null;
    } finally {
      _freeString(pointer);
    }
  }

  String _readString(ffi.Pointer<ffi.Char> pointer) {
    if (pointer == ffi.nullptr) return '';
    return pointer.cast<Utf8>().toDartString();
  }
}
