import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device/device_list.dart';
import 'main.dart';

class SmartWatchScreen extends StatefulWidget {
  const SmartWatchScreen({
    Key? key,
  }) : super(key: key);

  @override
  State<SmartWatchScreen> createState() => _SmartWatchScreenState();
}

class _SmartWatchScreenState extends State<SmartWatchScreen> {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  String _deviceId = '00:00:00:00:00:00';
  String text = "Stop Service";

  @override
  void initState() {
    super.initState();
    _setStatus();
  }

  void _setStatus() async {
    final SharedPreferences prefs = await _prefs;
    var isRunning = await FlutterBackgroundService().isServiceRunning();
    setState(() {
      if (isRunning) {
        text = "Stop Service";
      } else {
        text = "Start Service";
      }
      _deviceId = prefs.getString('deviceId') ?? '00:00:00:00:00:00';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_deviceId.endsWith('00:00:00:00:00:00')) {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        ElevatedButton(
            child: const Text("Select Smartwatch"), onPressed: selectDevice),
      ]);
    } else {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_deviceId),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
                child: const Text("Remove device"), onPressed: removeDevice),
            const SizedBox(
              width: 10,
            ),
            ElevatedButton(
              child: Text(text),
              onPressed: () async {
                var isRunning =
                    await FlutterBackgroundService().isServiceRunning();
                if (isRunning) {
                  FlutterBackgroundService().sendData(
                    {"action": "stopService"},
                  );
                } else {
                  FlutterBackgroundService.initialize(onStart);
                }

                setState(() {
                  if (!isRunning) {
                    text = 'Stop Service';
                  } else {
                    text = 'Start Service';
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(
          color: Colors.blueGrey,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
            child: const Text("Send Time"),
            onPressed: () async {
              FlutterBackgroundService().sendData({"action": "send_time"});
            }),
        ElevatedButton(
            child: const Text("Test Notification"),
            onPressed: () async {
              FlutterBackgroundService()
                  .sendData({"action": "send_debug_notification"});
            }),
      ]);
    }
  }

  Future<void> selectDevice() async {
    await Navigator.push<void>(
        context, MaterialPageRoute(builder: (_) => DeviceListScreen()));
    _setStatus();
  }

  void removeDevice() {
    _prefs.then((prefs) async {
      prefs.setString("deviceId", '00:00:00:00:00:00');
      _setStatus();
      FlutterBackgroundService().sendData({"action": "disconnect"});
    });
  }
}
