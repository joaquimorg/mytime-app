import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ble/ble_device_connector.dart';
import 'ble/ble_scanner.dart';
import 'main_bottom_nav_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  await initializeService();

  final ble = FlutterReactiveBle();
  final scanner = BleScanner(ble: ble);

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: scanner),
        StreamProvider<BleScannerState?>(
          create: (_) => scanner.state,
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
      BleDeviceConnector(service, ble: flutterReactiveBle);

  DeviceConnectionState connectionState = DeviceConnectionState.disconnecting;

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  sendNotification(flutterLocalNotificationsPlugin, 'Service is running',
      'Ready to connect.');

  Timer.periodic(const Duration(seconds: 10), (Timer timer) {
    if (connectionState == DeviceConnectionState.disconnected) {
      final Future<SharedPreferences> prefs = SharedPreferences.getInstance();
      prefs.then((prefs) {
        String prefDeviceId =
            prefs.getString('deviceId') ?? '00:00:00:00:00:00';

        sendNotification(flutterLocalNotificationsPlugin, "Trying to connect",
            "Looking for device...");
        deviceConnector
            .connect(prefDeviceId)
            .then((_) {})
            .timeout(const Duration(seconds: 15), onTimeout: () {
          sendNotification(flutterLocalNotificationsPlugin,
              "Connection timeout", "No device in range...");
        }).catchError((error) {
          sendNotification(flutterLocalNotificationsPlugin, "Connection error",
              error.toString());
        });
      });
    } /*else {
      sendNotification(
          flutterLocalNotificationsPlugin, 'PineTime', 'Device connected...');
    }*/
  });

  service.on('stop_service').listen((event) {
    service.stopSelf();
    if (connectionState == DeviceConnectionState.connected) {
      deviceConnector.disconnect();
      sendNotification(flutterLocalNotificationsPlugin,
          "Background service stopped", "Start service to connect");
    }
  });

  //service.on('stopService').listen((event) {});

  service.on('notification').listen((event) {
    /*sendNotification(
        flutterLocalNotificationsPlugin, event!["title"], event["content"]);*/

    flutterLocalNotificationsPlugin.show(
      888,
      event!["title"],
      event["content"],
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'pinetime40',
          'PineTime Companion App',
          icon: 'ic_bg_service_small',
          ongoing: true,
        ),
      ),
    );
  });

  service.on('disconnect').listen((event) {
    //flutterReactiveBle.deinitialize();
    if (connectionState == DeviceConnectionState.connected) {
      deviceConnector.disconnect();
      sendNotification(
          flutterLocalNotificationsPlugin,
          "Disconnected from smartwatch",
          "Connection to smartwatch terminated");
    }
  });

  service.on('connect').listen((event) {
    /*sendNotification(
        flutterLocalNotificationsPlugin, "BLE", "Trying to connect...");*/
    String deviceId = event?["deviceId"];

    deviceConnector.connect(
        deviceId); /*.then((_) {
      sendNotification(flutterLocalNotificationsPlugin, "BLE", "Connected to smartwatch");
    });*/
  });

  service.on('send_debug_notification').listen((event) {
    deviceConnector.sendDebugNotification();
  });

  service.on('get_status').listen((event) {
    deviceConnector.sendStatus();
  });

  service.on('app_list').listen((event) {
    List<String> appList = List<String>.from(event!['data'] as List);
    deviceConnector.appListChanged(appList);
  });

  service.on('send_time').listen((event) {
    deviceConnector.sendTime();
  });

  deviceConnector.loadAppList();

  // bring to foreground
  //service.setForegroundMode(true);

  deviceConnector.state.listen((state) {
    connectionState = state.connectionState;
    if (state.connectionState == DeviceConnectionState.connected) {
      //_reconnectTimer.cancel();
      /*sendNotification(flutterLocalNotificationsPlugin, "PineTime",
          "Connected to smartwatch.");*/
      deviceConnector.setMTUSize(240);
      deviceConnector.sendTime();
      deviceConnector.listenForData();

      final Future<SharedPreferences> prefs = SharedPreferences.getInstance();
      prefs.then((prefs) {
        //String deviceId = prefs.getString('deviceId') ?? '00:00:00:00:00:00';
        String deviceName = prefs.getString('deviceName') ?? '-';
        sendNotification(
            flutterLocalNotificationsPlugin, "Connected", deviceName);
      });
    } else if (state.connectionState == DeviceConnectionState.disconnected) {
      sendNotification(flutterLocalNotificationsPlugin,
          "Disconnected from smartwatch.", "Device not in range.");
    }

    service.invoke('update', {
      "action": "device_connection_state",
      "state": state.connectionState.name
    });
  });
}
