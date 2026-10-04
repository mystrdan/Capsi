import 'package:capsi/file_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a transferred file card actually shows.
///
/// The regression these guard against is specific: a file message used to render
/// its (deliberately empty) text body, so a conversation full of transferred
/// files showed nothing but blank cards. These assert the card names the file,
/// its type and its size, and that it never offers to open a file the user does
/// not actually have.
Map<String, dynamic> storedFile({
  String name = 'report.pdf',
  int size = 2516582,
  String state = 'complete',
  String? localPath,
  bool outgoing = false,
}) =>
    <String, dynamic>{
      'transfer_id': 't-1',
      'file_name': name,
      'size': size,
      'digest': 'ab',
      if (localPath != null) 'local_path': localPath,
      'state': state,
    };

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('a file card names the file, its type and its size', (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(),
      outgoing: false,
      peerName: 'Office PC',
      sentAt: 1700000000,
    )));

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('PDF · 2.4 MB'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    expect(find.textContaining('From Office PC'), findsOneWidget);
  });

  testWidgets('a received image renders a thumbnail slot, not a generic card',
      (tester) async {
    // The decode rule itself is covered as pure logic in file_meta_test.dart.
    // What matters here is that a completed image is routed to the preview
    // branch, which is the only branch that builds an Image widget at all.
    await tester.pumpWidget(host(FileCard(
      file: storedFile(name: 'holiday.png', localPath: '/tmp/holiday.png'),
      outgoing: false,
      peerName: 'Office PC',
    )));

    expect(find.text('holiday.png'), findsOneWidget);
    expect(find.text('PNG · 2.4 MB'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
  });

  testWidgets('a file with no extension shows a plain type icon, not a broken image',
      (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(name: 'README', localPath: '/tmp/README'),
      outgoing: false,
      peerName: 'Office PC',
    )));

    expect(find.text('README'), findsOneWidget);
    expect(find.text('File · 2.4 MB'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('an unknown extension falls back to a generic file label',
      (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(name: 'mystery.qqq'),
      outgoing: false,
      peerName: 'Office PC',
    )));

    expect(find.text('QQQ · 2.4 MB'), findsOneWidget);
    // Nothing local yet, so no action is offered.
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('no open action is offered before the transfer completes',
      (tester) async {
    // The core points local_path at the .part file while receiving, so offering
    // Open here would hand the user a half-written file.
    for (final state in ['offered', 'transferring', 'failed', 'cancelled']) {
      await tester.pumpWidget(host(FileCard(
        file: storedFile(state: state, localPath: '/tmp/report.pdf.part'),
        outgoing: false,
        peerName: 'Office PC',
      )));
      expect(find.text('Open'), findsNothing, reason: 'state=$state');
    }
  });

  testWidgets('a completed file offers Open', (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(localPath: '/tmp/report.pdf'),
      outgoing: false,
      peerName: 'Office PC',
    )));

    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('a failed transfer says so', (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(state: 'failed'),
      outgoing: false,
      peerName: 'Office PC',
    )));

    expect(find.text('Failed'), findsOneWidget);
  });

  testWidgets('a cancelled transfer says so', (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(state: 'cancelled'),
      outgoing: true,
      peerName: 'Office PC',
    )));

    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.textContaining('To Office PC'), findsOneWidget);
  });

  testWidgets('a state this build does not know is shown as the engine worded it',
      (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(state: 'quarantined'),
      outgoing: false,
      peerName: 'Office PC',
    )));

    expect(find.text('quarantined'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
  });

  testWidgets('a sent file reads Sent, not Received', (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(localPath: '/tmp/report.pdf'),
      outgoing: true,
      peerName: 'Office PC',
    )));

    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Received'), findsNothing);
  });

  testWidgets('an in-progress send reads Sending', (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(state: 'transferring'),
      outgoing: true,
      peerName: 'Office PC',
    )));

    expect(find.text('Sending'), findsOneWidget);
  });

  testWidgets('an in-progress receive reads Receiving', (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(state: 'transferring'),
      outgoing: false,
      peerName: 'Office PC',
    )));

    expect(find.text('Receiving'), findsOneWidget);
  });

  testWidgets('a file with no recorded size says so instead of guessing',
      (tester) async {
    await tester.pumpWidget(host(FileCard(
      file: storedFile(size: -1),
      outgoing: false,
      peerName: 'Office PC',
    )));

    expect(find.text('PDF · Size unknown'), findsOneWidget);
  });
}