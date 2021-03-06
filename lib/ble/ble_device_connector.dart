import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:notifications/notifications.dart';
import 'package:quiver/iterables.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../smartwatch_status.dart';
import '../utils.dart';
import 'reactive_state.dart';

class BleDeviceConnector extends ReactiveState<ConnectionStateUpdate> {
  BleDeviceConnector({required FlutterReactiveBle ble}) : _ble = ble;

  List<String> appList = <String>[];

  final FlutterReactiveBle _ble;
  void _logMessage(String message) {
    FlutterBackgroundService()
        .setNotificationInfo(title: "BLE", content: message);
  }

  String _deviceId = '00:00:00:00:00:00';
  int mtuSize = 20;

  SmartWatchStatus smartWatchStatus = SmartWatchStatus();

  @override
  Stream<ConnectionStateUpdate> get state => _deviceConnectionController.stream;

  final _deviceConnectionController = StreamController<ConnectionStateUpdate>();

  // ignore: cancel_subscriptions
  late StreamSubscription<ConnectionStateUpdate> _connection;

  Future<void> connect(String deviceId) async {
    if (!deviceId.contains('00:00:00:00:00:00')) {
      _deviceId = deviceId;
    }

    if (_deviceId.contains('00:00:00:00:00:00')) {
      return;
    }
    _logMessage('Start connecting to $deviceId');
    _connection = _ble.connectToAdvertisingDevice(
      id: _deviceId,
      prescanDuration: const Duration(seconds: 5),
      connectionTimeout: const Duration(seconds: 5),
      withServices: [Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E")],
    ).listen(
      (update) {
        _logMessage(
            'ConnectionState for device $_deviceId : ${update.connectionState}');
        _deviceConnectionController.add(update);
      },
      onError: (Object e) =>
          _logMessage('Connecting to device $_deviceId resulted in error $e'),
    );
  }

  Future<void> disconnect() async {
    try {
      _logMessage('disconnecting to device: $_deviceId');
      await _connection.cancel();
    } on Exception catch (e, _) {
      _logMessage("Error disconnecting from a device: $e");
    } finally {
      // Since [_connection] subscription is terminated, the "disconnected" state cannot be received and propagated
      _deviceConnectionController.add(
        ConnectionStateUpdate(
          deviceId: _deviceId,
          connectionState: DeviceConnectionState.disconnected,
          failure: null,
        ),
      );
      _deviceId = '00:00:00:00:00:00';
    }
  }

  Future<void> dispose() async {
    await _deviceConnectionController.close();
  }

  Future<void> setMTUSize(int size) async {
    final mtu = await _ble.requestMtu(deviceId: _deviceId, mtu: size);
    mtuSize = mtu;
  }

  Future<void> sendData(int cmd, List<int> data) async {
    final characteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),
        characteristicId: Uuid.parse("6E400002-B5A3-F393-E0A9-E50E24DCCA9E"),
        deviceId: _deviceId);

    final List<int> headData = buildHeader(cmd, data);

    _ble.writeCharacteristicWithResponse(characteristic, value: headData);
  }

  void evaluateData(List<int> data) {
    final service = FlutterBackgroundService();
    //service.setNotificationInfo(title: "BLE", content: "Data : ${data.toString()}");
    Uint8List responseData = Uint8List.fromList(data);
    var byteData = responseData.buffer.asByteData();

    if (byteData.getUint8(0) == 0x00) {
      int action = byteData.getUint8(1);
      switch (action) {
        case 0x01:
          // get version
          // send time
          //service.sendData({"action": "send_time", 'deviceId': deviceId});
          service.setNotificationInfo(title: "Status", content: "FW Version");
          break;
        case 0x02:
          // get battery info
          int battery = byteData.getUint16(4);
          double batteryVolt = byteData.getFloat32(6);
          int batteryStatus = byteData.getUint8(10);

          service.setNotificationInfo(
              title: "Status", content: "Battery $battery%");

          /*service.sendData({
            "action": "battery",
            'battery': battery,
            'batteryVolt': batteryVolt,
            'batteryStatus': batteryStatus
          });*/

          smartWatchStatus.deviceBattery = battery;
          smartWatchStatus.deviceBatteryVolt = batteryVolt;
          smartWatchStatus.deviceBatteryStatus = batteryStatus;
          sendStatus("connected");
          break;
        case 0x03:
          // get steps
          int steps = byteData.getUint16(4);
          smartWatchStatus.deviceSteps = steps;
          sendStatus("connected");
          break;
        case 0x04:
          // get harts rate
          int hartRate = byteData.getUint8(2);
          smartWatchStatus.deviceHartrate = hartRate;
          sendStatus("connected");
          break;
        default:
          service.setNotificationInfo(
              title: "BLE", content: "Data : " + data.toString());
      }
    }
  }

  void sendStatus(String status) {
    FlutterBackgroundService().sendData({
      "action": "device_state",
      "state": status,
      "battery": smartWatchStatus.deviceBattery,
      "battery_voltage": smartWatchStatus.deviceBatteryVolt.toStringAsFixed(3),
      "battery_status": smartWatchStatus.deviceBatteryStatus,
      "steps": smartWatchStatus.deviceSteps,
      "heart_rate": smartWatchStatus.deviceHartrate,
    });
  }

  void listenForData() {
    final characteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),
        characteristicId: Uuid.parse("6E400003-B5A3-F393-E0A9-E50E24DCCA9E"),
        deviceId: _deviceId);
    _ble.subscribeToCharacteristic(characteristic).listen((data) {
      // code to handle incoming data
      evaluateData(data);
    }, onError: (dynamic error) {
      // code to handle errors
    });
  }

  void sendTime() {
    var dateTime = DateTime.now();
    dateTime = dateTime.add(Duration(hours: dateTime.timeZoneOffset.inHours));
    int now = dateTime.millisecondsSinceEpoch;
    sendData(0x01, intToList((now / 1000).round() - 946684800));
  }

  void sendNotification(NotificationEvent event) {
    if (event.packageName == null) {
      return;
    }

    if (shouldIgnoreSource(event.packageName!)) {
      return;
    }

    NotificationData notificationData = NotificationData(
      packageName: event.packageName,
      title: event.title,
      message: event.message,
      subText: event.subText,
      ticker: event.ticker,
      timeStamp: event.timeStamp,
    );

    sendData(0x02, notificationData.toBytes().toBytes());

    final service = FlutterBackgroundService();
    service.setNotificationInfo(
      title: "Notification",
      content: notificationData.title,
    );
  }

  void sendDebugNotification() {
    NotificationData notificationData = NotificationData(
      packageName: "packageName",
      title: "title",
      message: "message",
      subText: "subText",
      ticker: "ticker",
      timeStamp: DateTime.now(),
    );

    sendData(0x02, notificationData.toBytes().toBytes());
  }

  Future<void> loadAppList() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    appList = prefs.getStringList('applications') ?? [];
  }

  void appListChanged(List<String> newList) {
    appList = newList;
  }

  bool shouldIgnoreSource(String packageName) {
    bool appFound = appList.contains(packageName);
    return !appFound;
  }
}

class NotificationConstant {
  static const int NOTIFICATION_GENERIC = 0;
  static const int NOTIFICATION_MISSED_CALL = 1;
  static const int NOTIFICATION_SMS = 2;
  static const int NOTIFICATION_SOCIAL = 3;
  static const int NOTIFICATION_EMAIL = 4;
  static const int NOTIFICATION_CALENDAR = 5;
  static const int NOTIFICATION_WHATSAPP = 6;
  static const int NOTIFICATION_MESSENGER = 7;
  static const int NOTIFICATION_INSTAGRAM = 8;
  static const int NOTIFICATION_TWITTER = 9;
  static const int NOTIFICATION_SKYPE = 10;
}

class NotificationData {
  /// The name of the package sending the notification.
  String? packageName;

  /// The title of the notification.
  String? title;

  /// The message in the notification.
  String? message;
  String? subText;
  String? ticker;

  /// The timestamp of the notification.
  DateTime? timeStamp;

  NotificationData({
    this.packageName,
    this.title,
    this.message,
    this.subText,
    this.ticker,
    this.timeStamp,
  });

  factory NotificationData.fromMap(Map<dynamic, dynamic> map) {
    String? name = map['packageName'];
    String? message = map['message'];
    String? subText = map['subtext'];
    String? ticker = map['ticker'];
    String? title = map['title'];

    return NotificationData(
      packageName: name,
      title: title,
      message: message,
      subText: subText,
      ticker: ticker,
      timeStamp: DateTime.now(),
    );
  }

  int getType() {
    // Generic Email
    if (packageName == "com.fsck.k9" ||
        packageName == "com.fsck.k9.material" ||
        packageName == "com.imaeses.squeaky" ||
        packageName == "com.android.email" ||
        packageName == "ch.protonmail.android" ||
        packageName == "security.pEp" ||
        packageName == "eu.faircode.email") {
      return NotificationConstant.NOTIFICATION_EMAIL;
    }

    // Generic SMS
    if (packageName == "com.moez.QKSMS" ||
        packageName == "com.android.mms" ||
        packageName == "com.android.messaging" ||
        packageName == "com.sonyericsson.conversations" ||
        packageName == "org.smssecure.smssecure") {
      return NotificationConstant.NOTIFICATION_SMS;
    }

    // Generic Calendar
    if (packageName == "com.android.calendar" ||
        packageName == "mikado.bizcalpro") {
      return NotificationConstant.NOTIFICATION_CALENDAR;
    }

    // Google
    if (packageName == "com.google.android.gm" ||
        packageName == "mikado.bizcalpro") {
      return NotificationConstant.NOTIFICATION_CALENDAR;
    }

    if (packageName == "com.google.android.apps.inbox") {
      return NotificationConstant.NOTIFICATION_EMAIL;
    }
    if (packageName == "com.google.android.calendar") {
      return NotificationConstant.NOTIFICATION_CALENDAR;
    }
    if (packageName == "com.google.android.apps.messaging") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }
    if (packageName == "com.google.android.talk") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }
    if (packageName == "com.google.android.apps.maps") {
      return NotificationConstant.NOTIFICATION_GENERIC;
    }
    if (packageName == "com.google.android.apps.photos") {
      return NotificationConstant.NOTIFICATION_GENERIC;
    }

    // Conversations
    if (packageName == "eu.siacs.conversations") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }
    if (packageName == "de.pixart.messenger") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }
    if (packageName == "com.google.android.apps.dynamite") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // Riot
    if (packageName == "im.vector.alpha") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // Signal
    if (packageName == "org.thoughtcrime.securesms") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // Wire
    if (packageName == "com.wire") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // Telegram
    if (packageName == "org.telegram.messenger") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }
    if (packageName == "org.telegram.messenger.beta") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }
    if (packageName == "org.telegram.plus") {
      return NotificationConstant.NOTIFICATION_MESSENGER; // "Plus Messenge"
    }
    if (packageName == "org.thunderdog.challegram") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // Twitter
    if (packageName == "org.mariotaku.twidere") {
      return NotificationConstant.NOTIFICATION_TWITTER;
    }
    if (packageName == "com.twitter.android") {
      return NotificationConstant.NOTIFICATION_TWITTER;
    }
    if (packageName == "org.andstatus.app") {
      return NotificationConstant.NOTIFICATION_TWITTER;
    }
    if (packageName == "org.mustard.android") {
      return NotificationConstant.NOTIFICATION_TWITTER;
    }

    // Facebook
    if (packageName == "me.zeeroooo.materialfb") {
      return NotificationConstant.NOTIFICATION_SOCIAL;
    }
    if (packageName == "it.rignanese.leo.slimfacebook") {
      return NotificationConstant.NOTIFICATION_SOCIAL;
    }
    if (packageName == "me.jakelane.wrapperforfacebook") {
      return NotificationConstant.NOTIFICATION_SOCIAL;
    }
    if (packageName == "com.facebook.katana") {
      return NotificationConstant.NOTIFICATION_SOCIAL;
    }
    if (packageName == "org.indywidualni.fblite") {
      return NotificationConstant.NOTIFICATION_SOCIAL;
    }

    // Facebook Messenger
    if (packageName == "com.facebook.orca") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }
    if (packageName == "com.facebook.mlite") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // WhatsApp
    if (packageName == "com.whatsapp") {
      return NotificationConstant.NOTIFICATION_WHATSAPP;
    }

    // HipChat
    if (packageName == "com.hipchat") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // Skype
    if (packageName == "com.skype.raider") {
      return NotificationConstant.NOTIFICATION_SKYPE;
    }

    // Skype for business
    if (packageName == "com.microsoft.office.lync15") {
      return NotificationConstant.NOTIFICATION_SKYPE;
    }

    // Mailbox
    if (packageName == "com.mailboxapp") {
      return NotificationConstant.NOTIFICATION_EMAIL;
    }

    // Snapchat
    if (packageName == "com.snapchat.android") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // WeChat
    if (packageName == "com.tencent.mm") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // Viber
    if (packageName == "com.viber.voip") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // Instagram
    if (packageName == "com.instagram.android") {
      return NotificationConstant.NOTIFICATION_SOCIAL;
    }

    // Microsoft Outlook
    if (packageName == "com.microsoft.office.outlook") {
      return NotificationConstant.NOTIFICATION_EMAIL;
    }

    // Business Calendar
    if (packageName == "com.appgenix.bizcal") {
      return NotificationConstant.NOTIFICATION_CALENDAR;
    }

    // Yahoo Mail
    if (packageName == "com.yahoo.mobile.client.android.mail") {
      return NotificationConstant.NOTIFICATION_EMAIL;
    }

    // LinkedIn
    if (packageName == "com.linkedin.android") {
      return NotificationConstant.NOTIFICATION_SOCIAL;
    }

    // Slack
    if (packageName == "com.slack") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // Transit
    if (packageName == "com.thetransitapp.droid") {
      return NotificationConstant.NOTIFICATION_MESSENGER;
    }

    // Etar
    if (packageName == "ws.xsoh.etar") {
      return NotificationConstant.NOTIFICATION_CALENDAR;
    }

    return NotificationConstant.NOTIFICATION_GENERIC;
  }

  BytesBuilder toBytes() {
    BytesBuilder responseData = BytesBuilder();

    String subject = title.toString();

    if (subject == '') {
      subject = packageName.toString();
    }

    String body = '';

    if (message != '') {
      body = message.toString();
    }

    if (ticker != '' && message == '') {
      body = ticker.toString();
    }

    if (subText != '' && body == '') {
      body = subText.toString();
    }

    responseData.add(intToList(1)); // Id
    responseData.addByte(getType()); // Type
    responseData.addByte(timeStamp!.hour); // HOUR_OF_DAY
    responseData.addByte(timeStamp!.minute); // MINUTE

    // subject (30)
    subject = truncateWithEllipsis(30, subject);
    List<int> _subject = utf8.encode(subject);
    responseData.addByte(_subject.length + 1);
    responseData.add(_subject);
    responseData.addByte(0);

    // body (60)
    body = truncateWithEllipsis(60, body);
    List<int> _body = utf8.encode(body);
    responseData.addByte(_body.length + 1);
    responseData.add(_body);
    responseData.addByte(0);

    return responseData;
  }
}
