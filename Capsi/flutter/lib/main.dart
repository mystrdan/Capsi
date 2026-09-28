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