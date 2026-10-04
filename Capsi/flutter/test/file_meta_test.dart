import 'package:capsi/file_card.dart';
import 'package:capsi/file_meta.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rules that decide what a transferred file is called and how it behaves.
///
/// The transfer protocol carries a name, a size and a digest and no MIME type,
/// so every conclusion here is derived from the name. These tests pin the cases
/// where a naive implementation would mislead the user: an unknown extension
/// must not be forced into a category, a dotfile must not be read as an
/// extension, and an in-progress transfer must never be presented as a file the
/// user can open.
void main() {
  group('file extension', () {
    test('reads the extension after the final dot, lower-cased', () {
      expect(fileExtension('report.PDF'), 'pdf');
      expect(fileExtension('archive.tar.gz'), 'gz');
      expect(fileExtension('photo.jpeg'), 'jpeg');
    });

    test('a name with no dot has no extension', () {
      expect(fileExtension('README'), '');
      expect(fileExtension('Makefile'), '');
    });

    test('a leading dot is part of the name, not an extension', () {
      // `.gitignore` is a whole filename, and treating "gitignore" as its type
      // would label a hidden dotfile as an unknown source file.
      expect(fileExtension('.gitignore'), '');
      expect(fileKind('.gitignore'), FileKind.unknown);
    });

    test('a trailing dot is not an extension', () {
      expect(fileExtension('notes.'), '');
    });
  });

  group('file kind', () {
    test('recognises the categories a card renders differently', () {
      expect(fileKind('a.png'), FileKind.image);
      expect(fileKind('a.mp4'), FileKind.video);
      expect(fileKind('a.mp3'), FileKind.audio);
      expect(fileKind('a.pdf'), FileKind.pdf);
      expect(fileKind('a.zip'), FileKind.archive);
      expect(fileKind('a.docx'), FileKind.document);
      expect(fileKind('a.xlsx'), FileKind.spreadsheet);
      expect(fileKind('a.pptx'), FileKind.presentation);
      expect(fileKind('a.txt'), FileKind.text);
      expect(fileKind('a.rs'), FileKind.code);
    });

    test('an unrecognised extension is unknown, not a guess', () {
      expect(fileKind('a.qqq'), FileKind.unknown);
      expect(fileKind('mystery'), FileKind.unknown);
    });

    test('is case insensitive', () {
      expect(fileKind('REPORT.PDF'), FileKind.pdf);
    });
  });

  group('file type info', () {
    test('labels by the extension the user recognises', () {
      expect(fileTypeInfo('report.pdf').label, 'PDF');
      expect(fileTypeInfo('holiday.PNG').label, 'PNG');
    });

    test('falls back to a category name when there is no extension', () {
      expect(fileTypeInfo('README').label, 'File');
    });

    test('a preview is offered only for formats Flutter can decode', () {
      // .heic is a real image the OS may open, but Flutter's decoder cannot
      // render it, so offering a thumbnail would only ever show a broken frame.
      expect(fileKind('photo.heic'), FileKind.image);
      expect(isPreviewableImage('photo.heic'), isFalse);

      expect(isPreviewableImage('photo.jpg'), isTrue);
      expect(isPreviewableImage('photo.png'), isTrue);
      expect(isPreviewableImage('report.pdf'), isFalse);
    });
  });
  group('transfer state', () {
    test('maps every state the core can persist', () {
      expect(parseTransferState('offered').phase, TransferPhase.waiting);
      expect(parseTransferState('transferring').phase, TransferPhase.transferring);
      expect(parseTransferState('complete').phase, TransferPhase.complete);
      expect(parseTransferState('declined').phase, TransferPhase.declined);
      expect(parseTransferState('failed').phase, TransferPhase.failed);
      expect(parseTransferState('cancelled').phase, TransferPhase.cancelled);
    });

    test('an unknown state keeps its own wording', () {
      // A conversation written by a newer build must never be relabelled
      // "Complete" just because this build does not recognise the state.
      final parsed = parseTransferState('quarantined');
      expect(parsed.phase, TransferPhase.unknown);
      expect(parsed.raw, 'quarantined');
    });

    test('direction changes the wording only where it genuinely differs', () {
      expect(transferLabel(TransferPhase.transferring, outgoing: true), 'Sending');
      expect(transferLabel(TransferPhase.transferring, outgoing: false), 'Receiving');
      expect(transferLabel(TransferPhase.complete, outgoing: true), 'Sent');
      expect(transferLabel(TransferPhase.complete, outgoing: false), 'Received');

      // Terminal states read the same both ways, because the core treats them
      // the same way.
      for (final outgoing in [true, false]) {
        expect(transferLabel(TransferPhase.failed, outgoing: outgoing), 'Failed');
        expect(transferLabel(TransferPhase.cancelled, outgoing: outgoing), 'Cancelled');
      }
    });

    test('only terminal states are terminal', () {
      expect(isTerminalTransfer(TransferPhase.complete), isTrue);
      expect(isTerminalTransfer(TransferPhase.failed), isTrue);
      expect(isTerminalTransfer(TransferPhase.declined), isTrue);
      expect(isTerminalTransfer(TransferPhase.cancelled), isTrue);
      expect(isTerminalTransfer(TransferPhase.transferring), isFalse);
      expect(isTerminalTransfer(TransferPhase.waiting), isFalse);
    });

    test('only a completed transfer counts as locally available', () {
      // The decisive case: while an incoming file is transferring, the core
      // points local_path at the .part file, so a card that trusted the mere
      // presence of that path would offer to "open" a half-received download.
      expect(isLocallyAvailable(TransferPhase.transferring), isFalse);
      expect(isLocallyAvailable(TransferPhase.waiting), isFalse);
      expect(isLocallyAvailable(TransferPhase.failed), isFalse);
      expect(isLocallyAvailable(TransferPhase.cancelled), isFalse);
      expect(isLocallyAvailable(TransferPhase.complete), isTrue);
    });
  });

  group('thumbnail eligibility', () {
    test('a completed, local, decodable image gets a preview', () {
      expect(
        canShowThumbnail(
          fileTypeInfo('holiday.png'),
          TransferPhase.complete,
          localPath: '/tmp/holiday.png',
        ),
        isTrue,
      );
    });

    test('a half-received image does not, even though a path exists', () {
      // The decisive case: while receiving, the core points local_path at the
      // .part file, so trusting the path alone would preview an unfinished
      // download as though it were the finished picture.
      expect(
        canShowThumbnail(
          fileTypeInfo('holiday.png'),
          TransferPhase.transferring,
          localPath: '/tmp/holiday.png.part',
        ),
        isFalse,
      );
    });

    test('a completed image with no path does not', () {
      expect(
        canShowThumbnail(fileTypeInfo('holiday.png'), TransferPhase.complete),
        isFalse,
      );
    });

    test('a non-image never gets a preview, however complete', () {
      expect(
        canShowThumbnail(
          fileTypeInfo('report.pdf'),
          TransferPhase.complete,
          localPath: '/tmp/report.pdf',
        ),
        isFalse,
      );
    });

    test('an image format Flutter cannot decode falls back to its icon', () {
      // A .heic the OS could open, but a preview would only ever fail to render.
      expect(
        canShowThumbnail(
          fileTypeInfo('photo.heic'),
          TransferPhase.complete,
          localPath: '/tmp/photo.heic',
        ),
        isFalse,
      );
    });
  });

  group('size and time formatting', () {
    test('formats byte counts', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(2 * 1024 * 1024), '2.0 MB');
    });

    test('a missing or nonsensical size is reported, not invented', () {
      expect(formatBytes(null), 'Size unknown');
      expect(formatBytes('not a number'), 'Size unknown');
      expect(formatBytes(-1), 'Size unknown');
    });
  });
}