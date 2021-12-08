import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:notifications/notifications.dart';
import 'package:provider/provider.dart';
import 'ble/ble_device_connector.dart';
import 'ble/ble_scanner.dart';
import 'main_bottom_nav_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterBackgroundService.initialize(onStart);

  final _ble = FlutterReactiveBle();
  final _scanner = BleScanner(ble: _ble);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: _scanner),
        StreamProvider<BleScannerState?>(
          create: (_) => _scanner.state,
          initialData: const BleScannerState(
            discoveredDevices: [],
            scanIsInProgress: false,
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(
          primarySwatch: Colors.teal,
          brightness: Brightness.dark,
        ),
        debugShowCheckedModeBanner: false,
        home: const MainBottomNavBar(),
      ),
    ),
  );
}

void onStart() {
  WidgetsFlutterBinding.ensureInitialized();
  final service = FlutterBackgroundService();
  final flutterReactiveBle = FlutterReactiveBle();

  final BleDeviceConnector deviceConnector =
      BleDeviceConnector(ble: flutterReactiveBle);

  DeviceConnectionState connectionState = DeviceConnectionState.connecting;

  StreamSubscription<NotificationEvent>? _subscription;

  Timer _reconnectTimer;

  service.onDataReceived.listen((event) async {
    // ------------------ stopService
    if (event!["action"] == "stopService") {
      service.setNotificationInfo(title: "MY-Time", content: "Service stopped");
      service.stopBackgroundService();
      //flutterReactiveBle.deinitialize();
      if (connectionState == DeviceConnectionState.connected) {
        await deviceConnector.disconnect();
        service.setNotificationInfo(title: "BLE", content: "Disconnected");
      }
    }

    // ------------------ disconnect
    if (event["action"] == "disconnect") {
      //flutterReactiveBle.deinitialize();
      if (connectionState == DeviceConnectionState.connected) {
        await deviceConnector.disconnect();
        service.setNotificationInfo(title: "BLE", content: "Disconnected");
      }
    }

    // ------------------ connect
    if (event["action"] == "connect") {
      //service.setNotificationInfo(title: "Action", content: "connect");
      String deviceId = event["deviceId"];

      deviceConnector.connect(deviceId).then((_) {
        //service.setNotificationInfo(title: "BLE", content: "Connected");
      });
    }

    // ------------------ Send Time
    if (event["action"] == "send_time") {
      deviceConnector.sendTime();
    }

    if (event["action"] == "send_debug_notification") {
      deviceConnector.sendDebugNotification();
    }
  });

  // bring to foreground
  service.setForegroundMode(true);

  service.setNotificationInfo(
    title: "MY-Time",
    content: "My-Time service is running.",
  );

  _reconnectTimer = Timer.periodic(
      const Duration(
        seconds: 30,
      ), (timer) {
    if (connectionState == DeviceConnectionState.disconnected) {
      service.setNotificationInfo(
          title: "BLE", content: "Retrying to connect...");
      deviceConnector
          .connect('00:00:00:00:00:00')
          .then((_) {})
          .timeout(const Duration(seconds: 20), onTimeout: () {
        service.setNotificationInfo(title: "BLE", content: "Failed to connect");
      });
    }
  });

  deviceConnector.state.listen((state) {
    connectionState = state.connectionState;
    if (state.connectionState == DeviceConnectionState.connected) {
      //_reconnectTimer.cancel();
      service.setNotificationInfo(title: "BLE", content: "Connected");
      deviceConnector.setMTUSize(120);
      deviceConnector.sendTime();
      deviceConnector.listenForData();
    } else if (state.connectionState == DeviceConnectionState.disconnected) {
      service.setNotificationInfo(title: "BLE", content: "Disconnected");
    }
  });

  Notifications _notifications = Notifications();
  _subscription = _notifications.notificationStream!.listen(
    (NotificationEvent event) {
      deviceConnector.sendNotification(event);
    },
  );
}
