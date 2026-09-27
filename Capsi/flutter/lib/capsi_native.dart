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
  CapsiNative._(this._library)
      : _runtimeVersion = _library.lookupFunction<_RuntimeVersionNative, _RuntimeVersionDart>('capsi_runtime_version'),
        _coreLinked = _library.lookupFunction<_CoreLinkedNative, _CoreLinkedDart>('capsi_core_linked'),
        _protocolVersion = _library.lookupFunction<_ProtocolVersionNative, _ProtocolVersionDart>('capsi_protocol_version'),
        _discoveryProbe = _library.lookupFunction<_DiscoveryProbeNative, _DiscoveryProbeDart>('capsi_discovery_probe'),
        _discoveryStart = _library.lookupFunction<_DiscoveryStartNative, _DiscoveryStartDart>('capsi_discovery_start'),
        _trustList = _library.lookupFunction<_TrustListNative, _TrustListDart>('capsi_trust_list'),
        _trustAccept = _library.lookupFunction<_TrustAcceptNative, _TrustAcceptDart>('capsi_trust_accept'),
        _trustIgnore = _library.lookupFunction<_TrustActionNative, _TrustActionDart>('capsi_trust_ignore'),
        _discoveryPoll = _library.lookupFunction<_DiscoveryPollNative, _DiscoveryPollDart>('capsi_discovery_poll'),
        _discoveryStop = _library.lookupFunction<_DiscoveryStopNative, _DiscoveryStopDart>('capsi_discovery_stop'),
        _freeString = _library.lookupFunction<_FreeStringNative, _FreeStringDart>('capsi_free_string');

  final ffi.DynamicLibrary _library;
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
  final _FreeStringDart _freeString;

  static CapsiNative? tryLoad() {
    final candidates = <String>[
      if (Platform.isWindows) 'capsi_ffi.dll',
      if (Platform.isAndroid) 'libcapsi_ffi.so',
      if (Platform.isMacOS) 'libcapsi_ffi.dylib',
      if (Platform.isLinux) 'libcapsi_ffi.so',
    ];

    for (final candidate in candidates) {
      try {
        return CapsiNative._(ffi.DynamicLibrary.open(candidate));
      } catch (_) {
        // The native artifact is packaged separately by the platform build.
      }
    }
    return null;
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

  String _readString(ffi.Pointer<ffi.Char> pointer) {
    if (pointer == ffi.nullptr) return '';
    return pointer.cast<Utf8>().toDartString();
  }
}
