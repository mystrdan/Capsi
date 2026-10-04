import 'dart:io';

import 'package:flutter/material.dart';

import 'file_meta.dart';
import 'file_opener.dart';

/// A single transferred file, rendered identically everywhere it appears.
///
/// The conversation bubble and the Files section both build one of these, which
/// is what keeps the two views from drifting apart: a file looks the same and
/// offers the same actions wherever the user meets it.
///
/// Everything shown is read from the persisted transfer record the Rust core
/// owns. Nothing here guesses: a state the engine did not report is rendered as
/// the engine worded it, and a file that is not on disk says so instead of
/// offering an action that would fail.
class FileCard extends StatelessWidget {
  /// The persisted `StoredFile` map from the conversation.
  final Map<String, dynamic> file;

  /// True when this device sent the file.
  final bool outgoing;

  /// The peer's display name, shown for direction context.
  final String peerName;

  /// Unix seconds from the message, when the caller has it.
  final int? sentAt;

  /// Optional extra row under the card, used by the conversation to host the
  /// Accept/Decline and Cancel buttons that only make sense there.
  final Widget? trailing;

  /// Compact rendering for a message bubble.
  final bool dense;

  const FileCard({
    super.key,
    required this.file,
    required this.outgoing,
    required this.peerName,
    this.sentAt,
    this.trailing,
    this.dense = false,
  });

  String get fileName => file['file_name']?.toString() ?? 'File';

  String? get localPath {
    final path = file['local_path']?.toString();
    return path == null || path.isEmpty ? null : path;
  }

  @override
  Widget build(BuildContext context) {
    final parsed = parseTransferState(file['state']?.toString());
    final info = fileTypeInfo(fileName);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FileThumb(
              info: info,
              path: localPath,
              phase: parsed.phase,
              dense: dense,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${info.label} · ${formatBytes(file['size'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8E9691),
                    ),
                  ),
                  const SizedBox(height: 5),
                  FileStatusRow(
                    phase: parsed.phase,
                    rawState: parsed.raw,
                    outgoing: outgoing,
                    peerName: peerName,
                    sentAt: sentAt,
                  ),
                ],
              ),
            ),
          ],
        ),
        FileActions(path: localPath, phase: parsed.phase),
        if (trailing != null) ...[const SizedBox(height: 6), trailing!],
      ],
    );
  }
}

/// The state line under the file name: status, direction and time.
class FileStatusRow extends StatelessWidget {
  final TransferPhase phase;
  final String rawState;
  final bool outgoing;
  final String peerName;
  final int? sentAt;

  const FileStatusRow({
    super.key,
    required this.phase,
    required this.rawState,
    required this.outgoing,
    required this.peerName,
    required this.sentAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // An unrecognised state is shown as the engine worded it, never rewritten
    // into a state this build happens to understand.
    final status = phase == TransferPhase.unknown && rawState.isNotEmpty
        ? rawState
        : transferLabel(phase, outgoing: outgoing);

    final color = transferPhaseColor(phase);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(transferPhaseIcon(phase), size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          [
            outgoing ? 'To $peerName' : 'From $peerName',
            if (sentAt != null) formatClock(sentAt!),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF777E79),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Thumbnail for images, or the type icon for everything else.
///
/// A file that is not present on disk, or an image whose bytes cannot be
/// decoded, falls back to the same type icon rather than showing a broken
/// frame — the card must still be readable.
class FileThumb extends StatelessWidget {
  final FileTypeInfo info;
  final String? path;
  final TransferPhase phase;
  final bool dense;

  const FileThumb({
    super.key,
    required this.info,
    required this.path,
    required this.phase,
    required this.dense,
  });

  /// True only when there is a decodable image sitting at [path].
  ///
  /// The whole rule lives in `canShowThumbnail` so it can be tested without a
  /// widget tree, and so this widget and the tests cannot disagree about when a
  /// preview is appropriate.
  bool get _canPreview => canShowThumbnail(info, phase, localPath: path);

  @override
  Widget build(BuildContext context) {
    final side = dense ? 44.0 : 56.0;
    final radius = BorderRadius.circular(8);

    final fallback = Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: const Color(0xFF1B1F21),
        borderRadius: radius,
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Icon(
        info.icon,
        color: const Color(0xFF8E9691),
        size: dense ? 22 : 26,
      ),
    );

    if (!_canPreview) return fallback;

    return ClipRRect(
      borderRadius: radius,
      child: Image.file(
        File(path!),
        width: side,
        height: side,
        fit: BoxFit.cover,
        // Decode at roughly display size: a 12 MP photo must not be held in
        // memory at full resolution just to fill a 56 px box.
        cacheWidth: (side * MediaQuery.devicePixelRatioOf(context)).round(),
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => fallback,
      ),
    );
  }
}

/// Open / Show-in-folder actions, shown only when there is something to act on.
///
/// The buttons appear for a completed file that is actually on disk. While a
/// transfer is running, or after it failed, there is nothing to open yet, so the
/// card stays informational instead of offering an action that would fail.
class FileActions extends StatelessWidget {
  final String? path;
  final TransferPhase phase;

  const FileActions({super.key, required this.path, required this.phase});

  @override
  Widget build(BuildContext context) {
    if (path == null || path!.isEmpty || !isLocallyAvailable(phase)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: () => openFileWithFeedback(context, path!),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open'),
          ),
          if (Platform.isWindows)
            TextButton.icon(
              onPressed: () => revealFileWithFeedback(context, path!),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('Show in folder'),
            ),
        ],
      ),
    );
  }
}

/// `4.2 MB`, or `Size unknown` when the core recorded no usable size.
String formatBytes(dynamic value) {
  final bytes =
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
  if (bytes == null || bytes < 0) return 'Size unknown';
  if (bytes < 1024) return '${bytes.toInt()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// A short local `14:05` for message timestamps.
String formatClock(int unixSeconds) {
  final at = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final hour = at.hour.toString().padLeft(2, '0');
  final minute = at.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}