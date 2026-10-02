import 'package:capsi/capsi_native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parsing the engine's startup self-check.
///
/// The report is the only thing standing between "the app launched" and "the
/// engine works", so these tests pin the rule that makes it meaningful: a step
/// that is not explicitly reported as passed is not a pass.
void main() {
  test('a fully passed engine report is ready and names every step', () {
    // Captured verbatim from capsi_ffi.dll's capsi_self_test on Windows.
    final report = CapsiSelfTestReport.fromJson(const {
      'ok': true,
      'protocol': 'capsi/1',
      'runtime': '1.1.0',
      'steps': [
        {'name': 'core_linked', 'ok': true},
        {'name': 'protocol', 'ok': true, 'detail': 'capsi/1'},
        {'name': 'storage', 'ok': true},
        {'name': 'identity', 'ok': true, 'detail': '4D5F 94AF D7ED B4BB'},
        {'name': 'network_listener', 'ok': true, 'detail': '0.0.0.0:45892'},
        {'name': 'discovery', 'ok': true, 'detail': 'udp 0.0.0.0:45893'},
      ],
    });

    expect(report.ok, isTrue);
    expect(report.protocol, 'capsi/1');
    expect(report.runtime, '1.1.0');
    expect(report.steps, hasLength(6));
    expect(report.failed, isEmpty);
  });

  test('a step the engine reported as failed keeps the engine reason', () {
    final report = CapsiSelfTestReport.fromJson(const {
      'ok': false,
      'steps': [
        {'name': 'core_linked', 'ok': true},
        {
          'name': 'network_listener',
          'ok': false,
          'detail': 'Only one usage of each socket address is normally permitted',
        },
        {'name': 'discovery', 'ok': true},
      ],
    });

    expect(report.ok, isFalse);
    expect(report.failed, hasLength(1));
    expect(report.failed.single.name, 'network_listener');
    expect(report.failed.single.detail, contains('socket address'));
  });

  test('a step with no explicit verdict counts as failed, never as a pass', () {
    final report = CapsiSelfTestReport.fromJson(const {
      'ok': false,
      'steps': [
        {'name': 'storage'},
      ],
    });

    expect(report.failed, hasLength(1));
    expect(report.failed.single.name, 'storage');
    expect(report.failed.single.ok, isFalse);
  });

  test('an engine error envelope becomes a named failing step', () {
    // capsi_self_test answers a refused call with {"error": ...} rather than a
    // report. Reading that as an ordinary report would leave ok:false with no
    // failing step, so the startup gate would show a cause-less failure.
    final report = CapsiSelfTestReport.fromJson(const {
      'error': 'device name is invalid',
    });

    expect(report.ok, isFalse);
    expect(report.failed, hasLength(1));
    expect(report.failed.single.name, 'self_test');
    expect(report.failed.single.detail, 'device name is invalid');
  });

  test('a report the engine called ready but with a failed step is not trusted', () {
    // ok and the step list must not be able to disagree in a way that hides a
    // failure: the failed list is what the gate renders.
    final report = CapsiSelfTestReport.fromJson(const {
      'ok': true,
      'steps': [
        {'name': 'discovery', 'ok': false, 'detail': 'udp port busy'},
      ],
    });

    expect(report.failed, hasLength(1));
    expect(report.failed.single.name, 'discovery');
  });
}