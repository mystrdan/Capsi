import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a received file the way the host operating system wants it opened.
///
/// The Dart layer never decides *how* a file opens. It asks the host over the
/// existing `win.capsi.app/platform` method channel, and falls back to
/// `url_launcher` only where no host answer is expected. That keeps every
/// platform-specific decision (ShellExecute on Windows, ACTION_VIEW on Android)
/// in the platform layer, where it already keeps the tray and notifications.
class FileOpener {
  const FileOpener._();

  static const MethodChannel _channel = MethodChannel('win.capsi.app/platform');

  /// True where Capsi can hand a local path to the OS.
  ///
  /// Only Windows and Android are in scope; the engine itself loads on no other
  /// platform, so offering the action elsewhere would be a dead control.
  static bool get isSupported => Platform.isWindows || Platform.isAndroid;

  /// Open [path] with the system's default application for its type.
  ///
  /// Returns false when the file is gone, the platform cannot open local files,
  /// or the OS refused. Never throws: failing to open is a reported outcome,
  /// not an error the caller has to handle.
  static Future<bool> open(String path) async {
    if (!isSupported) return false;
    if (!await exists(path)) return false;

    // Windows and Android both answer here; Android needs the host because only
    // it can build a content:// URI and a MIME type for a sandboxed file.
    if (await _invoke('openFile', path)) return true;

    // Fallback for a host build that predates the channel method.
    return _launchFileUri(path);
  }

  /// Show [path] in the platform file manager, with the file selected.
  ///
  /// "Reveal in folder" is a desktop concept. Android has no equivalent a normal
  /// app may rely on — the sandbox folder is not browsable — so this reports
  /// false there rather than opening something misleading.
  static Future<bool> reveal(String path) async {
    if (!Platform.isWindows) return false;
    if (!await exists(path)) return false;
    if (await _invoke('revealFile', path)) return true;
    return _launchDirectory(Uri.directory(path).toString());
  }

  /// Whether [path] currently exists on this machine.
  ///
  /// Cards call this so a file the user deleted outside Capsi is reported as
  /// missing instead of offering an action that would fail.
  static Future<bool> exists(String path) async {
    if (path.isEmpty) return false;
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// Ask the host to perform [method] on [path].
  ///
  /// A `MissingPluginException` means the host build does not implement the
  /// method, which is normal on a platform outside scope; it is treated as "not
  /// handled", not as a failure.
  static Future<bool> _invoke(String method, String path) async {
    try {
      final ok = await _channel.invokeMethod<bool>(method, {'path': path});
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Last-resort open through `url_launcher`.
  ///
  /// `externalApplication` keeps the file in the user's own default application
  /// rather than any in-app handler.
  static Future<bool> _launchFileUri(String path) async {
    try {
      return await launchUrl(
        Uri.file(path),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// Last-resort "show in folder", by opening the containing directory.
  static Future<bool> _launchDirectory(String uri) async {
    try {
      return await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// The file's own name, for messages.
String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;

/// Opens [path], reporting the outcome in a snackbar rather than throwing.
///
/// Used by the file cards so every entry point behaves the same way: the user
/// always learns whether the file opened, and a missing file says so plainly
/// instead of failing silently.
Future<void> openFileWithFeedback(BuildContext context, String path) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final name = _fileName(path);

  if (!await FileOpener.exists(path)) {
    messenger?.showSnackBar(
      SnackBar(content: Text('$name is no longer on this device.')),
    );
    return;
  }

  final opened = await FileOpener.open(path);
  if (!context.mounted) return;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        opened
            ? 'Opening $name'
            : 'Capsi could not open $name on this device.',
      ),
    ),
  );
}

/// Reveals [path] in the platform file manager, with feedback.
Future<void> revealFileWithFeedback(BuildContext context, String path) async {
  final messenger = ScaffoldMessenger.maybeOf(context);

  if (!Platform.isWindows) {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Opening the containing folder is a desktop feature.'),
      ),
    );
    return;
  }

  final name = _fileName(path);
  if (!await FileOpener.exists(path)) {
    messenger?.showSnackBar(
      SnackBar(content: Text('$name is no longer on this device.')),
    );
    return;
  }

  final revealed = await FileOpener.reveal(path);
  if (!context.mounted) return;
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        revealed
            ? 'Showing $name in File Explorer'
            : 'Capsi could not open the folder.',
      ),
    ),
  );
}