import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'smartwatch_status.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  String connectionState = "Disconnected";
  bool isConnected = false;
  String deviceName = '-';

  String battery = '0%';
  String batteryStatus = 'Unknown';
  String batteryVoltage = '0.0v';
  String stepCount = '0';
  String hartRate = '0 bpm';

  @override
  void initState() {
    super.initState();

    _setStatus();
  }

  void _setStatus() async {
    final SharedPreferences prefs = await _prefs;
    setState(() {
      deviceName = prefs.getString('deviceName') ?? '-';
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: FlutterBackgroundService().onDataReceived,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          FlutterBackgroundService().sendData({"action": "get_status"});
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final data = snapshot.data!;

        if (data["action"] == "device_state") {
          String state = data["state"];
          if (state == "connected") {
            connectionState = "Connected to $deviceName";
            isConnected = true;
          } else if (state == "connecting") {
            connectionState = "Connecting to $deviceName";
            isConnected = false;
          } else if (state == "disconnecting") {
            connectionState = "Disconnecting from $deviceName";
            isConnected = false;
          } else {
            connectionState = "Disconnected";
            isConnected = false;
          }

          battery = data["battery"] + '%';
          batteryStatus = data["battery_status"] == "1"
              ? "Unknown"
              : data["batteryStatus"] == "2"
                  ? "Charging"
                  : "Discharging";
          batteryVoltage = data["battery_voltage"] + 'v';
        }

        if (!isConnected) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.watch_outlined, size: 100, color: Colors.orange),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  "No smartwatch connected.",
                  style: Theme.of(context).textTheme.headline6,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _buildStatBattery(
                'Battery',
                battery,
                batteryVoltage,
                batteryStatus,
                batteryStatus == "Charging"
                    ? Icons.battery_charging_full
                    : FontAwesomeIcons.batteryHalf,
                Colors.purple),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard(
                    'Steps', stepCount, FontAwesomeIcons.walking, Colors.blue),
                _buildStatCard('Hartrate', hartRate, FontAwesomeIcons.heartbeat,
                    Colors.green),
              ],
            ),
          ],
        );
      },
    );
  }

  Expanded _buildStatCard(
      String title, String count, IconData icon, MaterialColor color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(8.0),
        padding: const EdgeInsets.all(10.0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              spreadRadius: 5,
              blurRadius: 7,
              offset: const Offset(3, 3), // changes position of shadow
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(
                count,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28.0,
                ),
              ),
              trailing: Icon(
                icon,
                color: Colors.white,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16.0, bottom: 10.0),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  _buildStatBattery(String title, String level, String voltage, String status,
      IconData icon, MaterialColor color) {
    return Container(
      margin: const EdgeInsets.all(8.0),
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 5,
            blurRadius: 7,
            offset: const Offset(3, 3), // changes position of shadow
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              level,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28.0,
              ),
            ),
            trailing: Icon(
              icon,
              color: Colors.white,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 10.0),
            child: Text(
              voltage + " / " + status,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16.0,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16.0, bottom: 10.0),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        ],
      ),
    );
  }
}
