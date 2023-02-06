import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device/device_list.dart';

class SmartWatchScreen extends StatefulWidget {
  const SmartWatchScreen({
    Key? key,
  }) : super(key: key);

  @override
  State<SmartWatchScreen> createState() => _SmartWatchScreenState();
}

class _SmartWatchScreenState extends State<SmartWatchScreen> {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  String deviceId = '00:00:00:00:00:00';
  String deviceName = '-';
  String serviceStatus = "Service stoped";

  String connectionState = "Disconnected";
  bool isConnected = false;

  String text = "(Waiting)";

  @override
  void initState() {
    super.initState();
    _setStatus();
  }

  void _setStatus() async {
    final SharedPreferences prefs = await _prefs;
    var isRunning = await FlutterBackgroundService().isRunning();
    setState(() {
      deviceId = prefs.getString('deviceId') ?? '00:00:00:00:00:00';
      deviceName = prefs.getString('deviceName') ?? '-';
      serviceStatus = isRunning ? "Service is running" : "Service stoped";
      if (isRunning) {
        text = 'Stop Service';
      } else {
        text = 'Start Service';
      }
    });
    //final service = FlutterBackgroundService();
    if (isRunning) {
      //service.invoke('stopService');
      FlutterBackgroundService().invoke('get_status');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(slivers: [
      SliverFillRemaining(
          hasScrollBody: false,
          fillOverscroll: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  "MY-Time",
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Expanded(
                child: smartWatchInfo(),
              ),
            ],
          ))
    ]);
  }

  Widget smartWatchInfo() {
    if (deviceId.endsWith('00:00:00:00:00:00')) {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        ElevatedButton.icon(
            label: const Text("Select Smartwatch"),
            icon: const Icon(Icons.watch_outlined),
            style: ButtonStyle(
                padding: MaterialStateProperty.all(const EdgeInsets.all(10)),
                textStyle:
                    MaterialStateProperty.all(const TextStyle(fontSize: 18))),
            onPressed: selectDevice),
      ]);
    } else {
      return StreamBuilder<Map<String, dynamic>?>(
          stream: FlutterBackgroundService().on('update'),
          builder: (context, snapshot) {
            /*if (!snapshot.hasData) {
              FlutterBackgroundService().invoke("get_status");
              return const Center(
                child: CircularProgressIndicator(),
              );
            }*/

            if (snapshot.hasData) {
              final data = snapshot.data!;

              if (data["action"] == "device_state" ||
                  data["action"] == "device_connection_state") {
                String state = data["state"];
                if (state == "connected") {
                  connectionState = "Connected to\n$deviceName";
                  isConnected = true;
                } else if (state == "connecting") {
                  connectionState = "Connecting to\n$deviceName";
                  isConnected = false;
                } else if (state == "disconnecting") {
                  connectionState = "Disconnecting from\n$deviceName";
                  isConnected = false;
                } else {
                  connectionState = "Disconnected";
                  isConnected = false;
                }
              }
            }

            return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    connectionState,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  Text(deviceId,
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.greenAccent,
                      )),
                  const SizedBox(height: 40),
                  Text(serviceStatus),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.delete_forever),
                        label: const Text("Remove device"),
                        style: ButtonStyle(
                          backgroundColor:
                              MaterialStateProperty.all(Colors.red),
                        ),
                        onPressed: removeDevice,
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      /*ElevatedButton.icon(
                          icon: const Icon(Icons.bluetooth_disabled),
                          label: const Text("Disconnect"),
                          onPressed: isConnected ? disconnectDevice : null),*/
                      ElevatedButton(
                        child: Text(text),
                        onPressed: () async {
                          var isRunning =
                              await FlutterBackgroundService().isRunning();
                          if (isRunning) {
                            FlutterBackgroundService().invoke(
                              'stopService',
                            );
                          } else {
                            FlutterBackgroundService().startService();
                            if (deviceId.endsWith('00:00:00:00:00:00')) {
                              FlutterBackgroundService()
                                  .invoke('sendNotification', {
                                "title": "MY-Time",
                                "content": "Please select a device",
                              });
                            } else {
                              FlutterBackgroundService()
                                  .invoke('connect', {'deviceId': deviceId});
                            }
                          }
                          setState(() {
                            serviceStatus = !isRunning
                                ? "Service is running"
                                : "Service stoped";
                            if (!isRunning) {
                              text = 'Stop Service';
                            } else {
                              text = 'Start Service';
                              connectionState = "Disconnected";
                              isConnected = false;
                            }
                          });
                        },
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                      onPressed: isConnected
                          ? () async {
                              FlutterBackgroundService().invoke('send_time');
                            }
                          : null,
                      child: const Text("Send Time")),
                  ElevatedButton(
                      onPressed: isConnected
                          ? () async {
                              FlutterBackgroundService()
                                  .invoke('send_debug_notification');
                            }
                          : null,
                      child: const Text("Test Notification")),
                ]);
          });
    }
  }

  Future<void> selectDevice() async {
    await Navigator.push<void>(
        context, MaterialPageRoute(builder: (_) => const DeviceListScreen()));
    _setStatus();
  }

  void removeDevice() {
    _prefs.then((prefs) async {
      prefs.setString("deviceId", '00:00:00:00:00:00');
      prefs.setString("deviceName", '-');
      _setStatus();
      FlutterBackgroundService().invoke('disconnect');
    });
  }

  void disconnectDevice() {
    FlutterBackgroundService().invoke('disconnect');
  }
}
