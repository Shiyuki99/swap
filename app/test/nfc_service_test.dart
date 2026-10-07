import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swap/services/nfc_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('swap/nfc');
  late NFCService service;
  Object? Function(MethodCall)? handler;

  setUp(() {
    service = NFCService();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => handler?.call(call));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('writeUUID activates HCE when native accepts the session', () async {
    handler = (call) async {
      expect(call.method, 'startSession');
      expect(call.arguments['url'], 'https://example.com/view/abc?sig=xyz');
      return true;
    };
    await service.writeUUID('https://example.com/view/abc?sig=xyz');
    expect(service.isHceActive, isTrue);
  });

  test('writeUUID stays inactive when native rejects the session', () async {
    handler = (call) async => false;
    await service.writeUUID('https://example.com/view/abc?sig=xyz');
    expect(service.isHceActive, isFalse);
  });

  test('stopSession deactivates HCE', () async {
    handler = (call) async => true;
    await service.writeUUID('https://example.com/view/abc?sig=xyz');
    await service.stopSession();
    expect(service.isHceActive, isFalse);
  });

  test('isNFCAvailable reflects the native support check', () async {
    handler = (call) async => call.method == 'isSupported';
    expect(await service.isNFCAvailable(), isTrue);
  });

  test('platform errors are swallowed and report unavailable', () async {
    handler = (call) async => throw PlatformException(code: 'error');
    expect(await service.isNFCAvailable(), isFalse);
    expect(await service.isNFCEnabled(), isFalse);
  });
}
