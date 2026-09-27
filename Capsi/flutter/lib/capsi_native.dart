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


typedef _DiscoveryStartNative = ffi.Uint64 Function(ffi.Pointer<ffi.Char>, ffi.Uint16);
typedef _DiscoveryStartDart = int Function(ffi.Pointer<ffi.Char>, int);

typedef _DiscoveryPollNative = ffi.Pointer<ffi.Char> Function(ffi.Uint64);
typedef _DiscoveryPollDart = ffi.Pointer<ffi.Char> Function(int);

typedef _DiscoveryStopNative = ffi.Void Function(ffi.Uint64);
typedef _DiscoveryStopDart = void Function(int);

typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<ffi.Char>);
typedef _FreeStringDart = void Function(ffi.Pointer<ffi.Char>);

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
        _discoveryPoll = _library.lookupFunction<_DiscoveryPollNative, _DiscoveryPollDart>('capsi_discovery_poll'),
        _discoveryStop = _library.lookupFunction<_DiscoveryStopNative, _DiscoveryStopDart>('capsi_discovery_stop'),
        _freeString = _library.lookupFunction<_FreeStringNative, _FreeStringDart>('capsi_free_string');

  final ffi.DynamicLibrary _library;
  final _RuntimeVersionDart _runtimeVersion;
  final _CoreLinkedDart _coreLinked;
  final _ProtocolVersionDart _protocolVersion;
  final _DiscoveryProbeDart _discoveryProbe;
  final _DiscoveryStartDart _discoveryStart;
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


  int startDiscovery({required String deviceName, int tcpPort = 45893}) {
    final nativeName = deviceName.toNativeUtf8();
    try {
      return _discoveryStart(nativeName.cast<ffi.Char>(), tcpPort);
    } finally {
      calloc.free(nativeName);
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

  void stopDiscovery(int handle) => _discoveryStop(handle);

  String _readString(ffi.Pointer<ffi.Char> pointer) {
    if (pointer == ffi.nullptr) return '';
    return pointer.cast<Utf8>().toDartString();
  }
}
