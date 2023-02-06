import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:mytime/apps_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'smartwatch_screen.dart';

class MainBottomNavBar extends StatefulWidget {
  const MainBottomNavBar({Key? key}) : super(key: key);

  @override
  _MainBottomNavBarState createState() => _MainBottomNavBarState();
}

class _MainBottomNavBarState extends State<MainBottomNavBar> {
  int _selectedIndex = 0;
  bool _permissionStatus = true;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    //await Permission.bluetoothScan.isGranted;
    //await Permission.bluetoothConnect.isGranted;
    //await Permission.location.isGranted;
    //await Permission.accessNotificationPolicy.isGranted;

    final status = await Permission.location.isGranted;

    setState(() {
      _permissionStatus = status;
    });
    if (_permissionStatus) {
      connectToDevice();
    }
  }

  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    SmartWatchScreen(),
    AppsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionStatus == false) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.warning, size: 100, color: Colors.orange),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  "Location permission is not granted.\nPlease grant it, "
                  "otherwise the app won't work.",
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                  child: const Text('Request permission'),
                  onPressed: () async {
                    final status = await Permission.location.request();
                    setState(() {
                      _permissionStatus =
                          status == PermissionStatus.granted ? true : false;
                    });
                  }),
            ],
          ),
        ),
      );
    } else {
      return Scaffold(
        body: SafeArea(
            child: Center(
          child: _pages.elementAt(_selectedIndex),
        )),
        bottomNavigationBar: BottomNavigationBar(
          elevation: 4,
          selectedFontSize: 16,
          selectedIconTheme:
              const IconThemeData(color: Colors.amberAccent, size: 32),
          selectedItemColor: Colors.amberAccent,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.watch_outlined),
              label: 'Smartwatch',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.apps),
              label: 'Apps',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
        ),
      );
    }
  }

  void connectToDevice() {
    final service = FlutterBackgroundService();
    final Future<SharedPreferences> prefs = SharedPreferences.getInstance();
    prefs.then((prefs) {
      String deviceId = prefs.getString('deviceId') ?? '00:00:00:00:00:00';
      //String deviceName = prefs.getString('deviceName') ?? '-';
      if (deviceId.endsWith('00:00:00:00:00:00')) {
        service.invoke('notification', {
          "title": "No device selected",
          "content": "Please select a device",
        });
      } else {
        service.invoke('connect', {'deviceId': deviceId});
      }
    });
  }
}
