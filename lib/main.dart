import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import 'ble/ble_device_connector.dart';
import 'ble/ble_scanner.dart';
import 'main_bottom_nav_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  await initializeService();

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

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'pinetime40', // id
    'PineTime', // title
    description: 'PineTime companion app notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: true,
      isForegroundMode: true,

      notificationChannelId: 'pinetime40',
      initialNotificationTitle: 'PineTime Companion App',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: true,

      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,
    ),
  );

  service.startService();
}

void sendNotification(
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
    String? title,
    String? content) {
  flutterLocalNotificationsPlugin.show(
    888,
    title,
    content,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'pinetime40',
        'PineTime Companion App',
        icon: 'ic_bg_service_small',
        ongoing: true,
      ),
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  //WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final flutterReactiveBle = FlutterReactiveBle();

  final BleDeviceConnector deviceConnector =
      BleDeviceConnector(ble: flutterReactiveBle);

  DeviceConnectionState connectionState = DeviceConnectionState.disconnecting;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  sendNotification(
      flutterLocalNotificationsPlugin, 'PineTime', 'Service is running...');

  Timer.periodic(const Duration(seconds: 10), (Timer timer) {
    if (connectionState == DeviceConnectionState.disconnected) {
      sendNotification(
          flutterLocalNotificationsPlugin, "BLE", "Retrying to connect...");

      deviceConnector
          .connect('00:00:00:00:00:00')
          .then((_) {})
          .timeout(const Duration(seconds: 15), onTimeout: () {
        sendNotification(
            flutterLocalNotificationsPlugin, "BLE", "Connection timeout...");
      }).catchError((error) {
        sendNotification(
            flutterLocalNotificationsPlugin, "BLE", "Connection error...");
      });
    } else {
      sendNotification(
          flutterLocalNotificationsPlugin, 'PineTime', 'Device connected...');
    }
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
    if (connectionState == DeviceConnectionState.connected) {
      deviceConnector.disconnect();
      sendNotification(flutterLocalNotificationsPlugin, "BLE",
          "Disconnected, service stoped...");
    }
  });

  //service.on('stopService').listen((event) {});

  service.on('sendNotification').listen((event) {
    sendNotification(
        flutterLocalNotificationsPlugin, event?["title"], event?["content"]);
  });

  service.on('disconnect').listen((event) {
    //flutterReactiveBle.deinitialize();
    if (connectionState == DeviceConnectionState.connected) {
      deviceConnector.disconnect();
      sendNotification(flutterLocalNotificationsPlugin, "BLE", "Disconnected");
    }
  });

  service.on('connect').listen((event) {
    sendNotification(flutterLocalNotificationsPlugin, "BLE", "Connecting...");
    String deviceId = event?["deviceId"];

    deviceConnector.connect(deviceId).then((_) {
      sendNotification(flutterLocalNotificationsPlugin, "BLE", "Connected");
    });
  });

  service.on('send_time').listen((event) {
    deviceConnector.sendTime();
  });

  service.on('send_debug_notification').listen((event) {
    deviceConnector.sendDebugNotification();
  });

  service.on('get_status').listen((event) {
    deviceConnector.sendStatus(connectionState.name, service);
  });

  service.on('app_list').listen((event) {
    List<String> appList = List<String>.from(event!['data'] as List);
    deviceConnector.appListChanged(appList);
  });

  deviceConnector.loadAppList();

  // bring to foreground
  //service.setForegroundMode(true);

  deviceConnector.state.listen((state) {
    connectionState = state.connectionState;
    if (state.connectionState == DeviceConnectionState.connected) {
      //_reconnectTimer.cancel();
      sendNotification(
          flutterLocalNotificationsPlugin, "BLE", "Device is connected.");
      deviceConnector.setMTUSize(120);
      deviceConnector.sendTime();
      deviceConnector.listenForData();
    } else if (state.connectionState == DeviceConnectionState.disconnected) {
      sendNotification(
          flutterLocalNotificationsPlugin, "BLE", "Device disconnected.");
    }

    service.invoke('update', {
      "action": "device_connection_state",
      "state": state.connectionState.name
    });
  });
}
