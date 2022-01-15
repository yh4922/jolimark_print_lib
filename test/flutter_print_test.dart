import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_print/flutter_print.dart';

void main() {
  const MethodChannel channel = MethodChannel('flutter_print');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPluginVersion', () async {
    expect(await FlutterPrint.pluginVersion, '42');
  });
}
