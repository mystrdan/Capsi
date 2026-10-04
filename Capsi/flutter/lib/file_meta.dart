import 'package:flutter/material.dart';

/// What kind of thing a transferred file is, for display purposes only.
///
/// The transfer protocol (`FileOffer` in capsi-core) carries a name, a size and a
/// digest — and no MIME type — so nothing here claims more certainty than that.
/// Every field is derived from the file name, which is the only type signal the
/// core can actually vouch for. [FileKind.unknown] is therefore a normal outcome,
/// not an error.
enum FileKind {
  image,
  video,
  audio,
  pdf,
  archive,
  document,
  spreadsheet,
  presentation,
  text,
  code,
  unknown,
}

/// A file's display metadata, derived from its name.
///
/// Kept as a plain value type so the rules are testable without a widget tree,
/// and so the conversation bubble and the Files section cannot drift apart: both
/// build one of these and render it the same way.
@immutable
class FileTypeInfo {
  /// The coarse category, used to pick an icon and a tint.
  final FileKind kind;

  /// The lower-case extension without the dot, or an empty string when the file
  /// has none (`README` is not "README.md" and must not be shown as one).
  final String extension;

  /// A short human label, e.g. `PDF`, `PNG`, `ZIP`.
  final String label;

  const FileTypeInfo({
    required this.kind,
    required this.extension,
    required this.label,
  });

  /// True when this file can be shown as an actual image preview.
  bool get isImage => kind == FileKind.image;

  /// Icon for the category, from the existing Material icon set.
  IconData get icon {
    switch (kind) {
      case FileKind.image:
        return Icons.image_outlined;
      case FileKind.video:
        return Icons.movie_outlined;
      case FileKind.audio:
        return Icons.audio_file_outlined;
      case FileKind.pdf:
        return Icons.picture_as_pdf_outlined;
      case FileKind.archive:
        return Icons.archive_outlined;
      case FileKind.document:
        return Icons.description_outlined;
      case FileKind.spreadsheet:
        return Icons.table_chart_outlined;
      case FileKind.presentation:
        return Icons.slideshow_outlined;
      case FileKind.text:
        return Icons.subject_outlined;
      case FileKind.code:
        return Icons.code_outlined;
      case FileKind.unknown:
        return Icons.insert_drive_file_outlined;
    }
  }
}

/// Extension sets, kept as one table so adding a type is a single edit.
///
/// Sets are lower-case and written without the leading dot. The reverse lookup is
/// built once on first use rather than on every call, because these lists are
/// walked for every file card the UI builds.
const Map<FileKind, Set<String>> _extensions = <FileKind, Set<String>>{
  FileKind.image: <String>{
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'tif', 'tiff',
  },
  FileKind.video: <String>{
    'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', 'mpg', 'mpeg', 'wmv', '3gp',
  },
  FileKind.audio: <String>{
    'mp3', 'wav', 'm4a', 'flac', 'ogg', 'oga', 'opus', 'aac', 'wma',
  },
  FileKind.pdf: <String>{'pdf'},
  FileKind.archive: <String>{
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz', 'zst',
  },
  FileKind.document: <String>{
    'doc', 'docx', 'odt', 'rtf', 'pages',
  },
  FileKind.spreadsheet: <String>{
    'xls', 'xlsx', 'ods', 'csv', 'tsv', 'numbers',
  },
  FileKind.presentation: <String>{
    'ppt', 'pptx', 'odp', 'key',
  },
  FileKind.text: <String>{
    'txt', 'md', 'markdown', 'log',
  },
  FileKind.code: <String>{
    'rs', 'dart', 'js', 'jsx', 'ts', 'tsx', 'py', 'java', 'kt', 'kts', 'c',
    'h', 'cc', 'cpp', 'hpp', 'cs', 'go', 'rb', 'php', 'swift', 'sh', 'ps1',
    'bat', 'cmd', 'json', 'yaml', 'yml', 'toml', 'xml', 'html', 'css', 'scss',
    'sql', 'ini', 'cfg', 'conf',
  },
};

Map<String, FileKind>? _reverse;

/// The extension → category lookup, inverted once on first use.
Map<String, FileKind> get _byExtension {
  return _reverse ??= <String, FileKind>{
    for (final entry in _extensions.entries)
      for (final extension in entry.value) extension: entry.key,
  };
}

/// The part of [fileName] after the final dot, lower-cased.
///
/// Returns an empty string when there is no dot, or when the dot is the first
/// character (`.gitignore` is a name, not an extension). A trailing dot does not
/// count either: `notes.` has no extension and must not be read as one.
String fileExtension(String fileName) {
  final name = fileName.trim();
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// The coarse category for [fileName], or `FileKind.unknown`.
///
/// Unknown is a first-class answer. The core has no MIME type to fall back on,
/// so an extension it has never seen is shown honestly as a generic file rather
/// than forced into a category it may not belong to.
FileKind fileKind(String fileName) =>
    _byExtension[fileExtension(fileName)] ?? FileKind.unknown;

/// Full display metadata for [fileName].
///
/// The label prefers the extension the user recognises (`PDF`, `PNG`), and falls
/// back to a readable category name when the file has no extension at all.
FileTypeInfo fileTypeInfo(String fileName) {
  final extension = fileExtension(fileName);
  final kind = fileKind(fileName);

  if (extension.isEmpty) {
    return FileTypeInfo(
      kind: kind,
      extension: '',
      label: kind == FileKind.unknown ? 'File' : _categoryLabel(kind),
    );
  }

  return FileTypeInfo(
    kind: kind,
    extension: extension,
    label: extension.toUpperCase(),
  );
}

/// A readable name for a category, used only when a file has no extension.
String _categoryLabel(FileKind kind) {
  switch (kind) {
    case FileKind.image:
      return 'Image';
    case FileKind.video:
      return 'Video';
    case FileKind.audio:
      return 'Audio';
    case FileKind.pdf:
      return 'PDF';
    case FileKind.archive:
      return 'Archive';
    case FileKind.document:
      return 'Document';
    case FileKind.spreadsheet:
      return 'Spreadsheet';
    case FileKind.presentation:
      return 'Presentation';
    case FileKind.text:
      return 'Text';
    case FileKind.code:
      return 'Source';
    case FileKind.unknown:
      return 'File';
  }
}

/// Whether [fileName] is a category worth rendering a thumbnail for.
///
/// The image bytes are decoded from disk, so only formats Flutter can actually
/// decode qualify. Anything else (a `.heic` from a modern phone, a raw `.psd`)
/// still gets its correct type icon and the same open action — it just never
/// shows a preview that could only ever fail.
bool isPreviewableImage(String fileName) =>
    isPreviewableExtension(fileExtension(fileName));

/// Whether an already-extracted [extension] (lower-case, no dot) can be decoded.
///
/// Split out from [isPreviewableImage] because the file card holds a
/// [FileTypeInfo] whose extension is already separated, and re-joining it into a
/// fake filename just to parse it again is how "png" ends up read as a file
/// with no extension at all.
bool isPreviewableExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'bmp':
      return true;
    default:
      return false;
  }
}
/// Whether a card should try to decode a real thumbnail for this file.
///
/// All four conditions are required, and the last two are the ones that keep a
/// half-received download from being shown as a finished picture: the core
/// points `local_path` at the `.part` file until the transfer completes
/// (`native/src/lib.rs:426`), so "a path is set" is not the same as "the file is
/// here". [isLocallyAvailable] is what distinguishes the two.
bool canShowThumbnail(
  FileTypeInfo info,
  TransferPhase phase, {
  String? localPath,
}) =>
    info.isImage &&
    isPreviewableExtension(info.extension) &&
    isLocallyAvailable(phase) &&
    localPath != null &&
    localPath.isNotEmpty;

/// How a transferred file should be described to the user.
///
/// The wire protocol and the persisted conversation expose exactly six states
/// (`TransferState` in capsi-core): offered, transferring, complete, declined,
/// failed, cancelled. This enum does not add states the core cannot verify —
/// there is no separate "delivered" acknowledgement for a file, so none is
/// invented. Direction (sent vs received) is a presentation concern, carried
/// separately, because the same core state means different things on each side.
enum TransferPhase {
  /// Offer sent, waiting for the other side to accept.
  waiting,

  /// Accepted; bytes are moving.
  transferring,

  /// Every chunk arrived and the digest matched.
  complete,

  /// The other side refused it.
  declined,

  /// Something went wrong mid-transfer.
  failed,

  /// Stopped by either side.
  cancelled,

  /// A state string this build does not recognise.
  ///
  /// Rendered as the engine's own wording rather than hidden, so a conversation
  /// written by a newer build is never silently misreported as "Complete".
  unknown,
}

/// Parse the `state` field of a stored file, keeping the original text.
///
/// An unrecognised value maps to [TransferPhase.unknown] with its `raw` text
/// intact so the UI can show what the engine actually said.
({TransferPhase phase, String raw}) parseTransferState(String? state) {
  final raw = (state ?? '').trim().toLowerCase();
  switch (raw) {
    case 'offered':
    case 'queued':
    case 'pending':
      return (phase: TransferPhase.waiting, raw: raw);
    case 'transferring':
      return (phase: TransferPhase.transferring, raw: raw);
    case 'complete':
    case 'completed':
    case 'delivered':
      return (phase: TransferPhase.complete, raw: raw);
    case 'declined':
      return (phase: TransferPhase.declined, raw: raw);
    case 'failed':
    case 'error':
      return (phase: TransferPhase.failed, raw: raw);
    case 'cancelled':
      return (phase: TransferPhase.cancelled, raw: raw);
    default:
      return (phase: TransferPhase.unknown, raw: raw);
  }
}

/// Whether [phase] is a state that will never change again.
///
/// Only these are safe to describe in the past tense.
bool isTerminalTransfer(TransferPhase phase) =>
    phase == TransferPhase.complete ||
    phase == TransferPhase.declined ||
    phase == TransferPhase.failed ||
    phase == TransferPhase.cancelled;

/// Whether this transfer should have produced a usable local file.
///
/// Derived from the state machine rather than from the mere presence of
/// `local_path`. While an incoming file is transferring, the core points
/// `local_path` at the `.part` file (`native/src/lib.rs:426`), so "a path is
/// set" would wrongly claim a half-received file is available. Only a completed
/// transfer has been renamed to its final location. The caller still stats the
/// path, because a completed file can still have been deleted by the user.
bool isLocallyAvailable(TransferPhase phase) => phase == TransferPhase.complete;

/// The label a file card shows for [phase] on the [outgoing] side.
///
/// Direction changes the wording only where the two sides genuinely differ; the
/// terminal states read the same in both, because the core treats them the same.
String transferLabel(TransferPhase phase, {required bool outgoing}) {
  switch (phase) {
    case TransferPhase.waiting:
      return outgoing ? 'Waiting to send' : 'Waiting for response';
    case TransferPhase.transferring:
      return outgoing ? 'Sending' : 'Receiving';
    case TransferPhase.complete:
      return outgoing ? 'Sent' : 'Received';
    case TransferPhase.declined:
      return 'Declined';
    case TransferPhase.failed:
      return 'Failed';
    case TransferPhase.cancelled:
      return 'Cancelled';
    case TransferPhase.unknown:
      return 'Unknown';
  }
}

/// Icon matching [phase].
IconData transferPhaseIcon(TransferPhase phase) {
  switch (phase) {
    case TransferPhase.waiting:
      return Icons.schedule_outlined;
    case TransferPhase.transferring:
      return Icons.sync_outlined;
    case TransferPhase.complete:
      return Icons.check_circle_outline;
    case TransferPhase.declined:
      return Icons.block_outlined;
    case TransferPhase.failed:
      return Icons.error_outline;
    case TransferPhase.cancelled:
      return Icons.cancel_outlined;
    case TransferPhase.unknown:
      return Icons.help_outline;
  }
}

/// Colour matching [phase], following the colours the transfer list already used.
Color transferPhaseColor(TransferPhase phase) {
  switch (phase) {
    case TransferPhase.complete:
      return const Color(0xFF7ED957);
    case TransferPhase.failed:
      return Colors.orange;
    case TransferPhase.waiting:
      return Colors.amber;
    case TransferPhase.declined:
    case TransferPhase.cancelled:
      return const Color(0xFF777E79);
    case TransferPhase.transferring:
    case TransferPhase.unknown:
      return const Color(0xFF858D88);
  }
}