import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medication_device_app/ble/ble_service.dart';
import 'ble_service_test.dart' show FakeBleTransport, MemoryTextStore, until;

void main() {
  late FakeBleTransport transport;
  late MemoryTextStore store;
  late BleService service;
  setUp(() {
    transport = FakeBleTransport();
    store = MemoryTextStore();
    service = BleService(
      transport: transport,
      store: store,
      usePreferences: false,
      handshakeInterval: const Duration(milliseconds: 20),
      reconnectDelay: const Duration(milliseconds: 20),
    );
  });
  tearDown(() async {
    service.dispose();
    await until(() => store.closed);
    await transport.close();
  });
  test(
    'background cancels HELLO, releases link, ignores late data, foreground reconnects once',
    () async {
      await service.connectToDevice('phone-link');
      transport.state(DeviceConnectionState.connected);
      await until(() => transport.writes.isNotEmpty);
      await service.setForeground(false);
      final writes = transport.writes.length;
      transport.frame('READY|AABBCCDDEEFF|P01');
      await Future<void>.delayed(const Duration(milliseconds: 65));
      expect(transport.writes.length, writes);
      expect(transport.connections, 1);
      expect(service.hasConnection, false);
      await service.setForeground(true);
      expect(transport.connections, 2);
      await service.setForeground(true);
      expect(transport.connections, 2);
    },
  );
  test(
    'explicit disconnect while backgrounded cancels automatic restoration',
    () async {
      await service.connectToDevice('phone-link');
      await service.setForeground(false);
      await service.disconnect();
      await service.setForeground(true);
      expect(transport.connections, 1);
    },
  );
  test(
    'disabled auto-reconnect respects the choice after background/foreground',
    () async {
      await service.connectToDevice('phone-link');
      service.setAutoReconnect(false);
      await service.setForeground(false);
      await service.setForeground(true);
      expect(transport.connections, 1);
    },
  );
  test(
    'late permission response cannot create a connection after suspension',
    () async {
      transport.readiness = Completer<void>();
      final connect = service.connectToDevice('phone-link');
      await Future<void>.delayed(Duration.zero);
      await service.setForeground(false);
      transport.readiness!.complete();
      await connect;
      expect(transport.connections, 0);
      expect(service.hasConnection, false);
      await service.setForeground(true);
      expect(transport.connections, 1);
    },
  );
  test(
    'rapid lifecycle transitions are serialized without duplicate reconnects',
    () async {
      await service.connectToDevice('phone-link');
      await Future.wait([
        service.setForeground(false),
        service.setForeground(true),
        service.setForeground(false),
        service.setForeground(true),
      ]);
      expect(transport.connections, 3);
      expect(service.foreground, true);
    },
  );
}
