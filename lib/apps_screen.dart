import 'package:device_apps/device_apps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({Key? key}) : super(key: key);

  @override
  _AppsScreenState createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  bool _showSystemApps = false;
  bool _onlySelectedApps = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Applications'),
        actions: <Widget>[
          PopupMenuButton<String>(
            itemBuilder: (BuildContext context) {
              return <CheckedPopupMenuItem<String>>[
                CheckedPopupMenuItem<String>(
                    checked: _showSystemApps,
                    value: 'system_apps',
                    enabled: !_onlySelectedApps,
                    child: Text('Show system apps')),
                CheckedPopupMenuItem<String>(
                  checked: _onlySelectedApps,
                  value: 'selected_apps',
                  child: Text('Show selectd apps only'),
                )
              ];
            },
            onSelected: (String key) {
              if (key == 'system_apps') {
                setState(() {
                  _showSystemApps = !_showSystemApps;
                });
              }
              if (key == 'selected_apps') {
                setState(() {
                  _onlySelectedApps = !_onlySelectedApps;
                });
              }
            },
          )
        ],
      ),
      body: _AppsListScreenContent(
          includeSystemApps: _showSystemApps,
          selectedApps: _onlySelectedApps,
          key: GlobalKey()),
    );
  }
}

class _AppsListScreenContent extends StatefulWidget {
  final bool includeSystemApps;
  final bool selectedApps;

  const _AppsListScreenContent(
      {Key? key, this.includeSystemApps = false, this.selectedApps = false})
      : super(key: key);

  @override
  State<_AppsListScreenContent> createState() => _AppsListScreenContentState();
}

class _AppsListScreenContentState extends State<_AppsListScreenContent> {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  List<String> appList = <String>[];

  @override
  void initState() {
    super.initState();
    getPrefs();
  }

  void getPrefs() async {
    final SharedPreferences prefs = await _prefs;
    appList = prefs.getStringList('applications') ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Application>>(
      future: DeviceApps.getInstalledApplications(
          includeAppIcons: true,
          includeSystemApps: widget.includeSystemApps || widget.selectedApps,
          onlyAppsWithLaunchIntent: false),
      builder: (BuildContext context, AsyncSnapshot<List<Application>> data) {
        if (data.data == null) {
          return const Center(child: CircularProgressIndicator());
        } else {
          List<Application> apps = widget.selectedApps
              ? data.data!
                  .where((e) => appList.contains(e.packageName))
                  .toList()
              : data.data!;

          apps.sort((a, b) => a.appName.compareTo(b.appName));
          return Scrollbar(
            child: ListView.builder(
              itemCount: apps.length,
              itemBuilder: (BuildContext context, int position) {
                Application app = apps[position];
                bool isSelected = appList.contains(app.packageName);
                return Column(
                  children: <Widget>[
                    CheckboxListTile(
                      activeColor: Colors.blue,
                      dense: false,
                      //font change
                      title: Text(
                        app.appName,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5),
                      ),
                      subtitle: Text(app.packageName),
                      value: isSelected,
                      selected: isSelected,
                      secondary: SizedBox(
                        height: 50,
                        width: 50,
                        child: app is ApplicationWithIcon
                            ? CircleAvatar(
                                backgroundImage: MemoryImage(app.icon),
                                backgroundColor: Colors.white,
                              )
                            : null,
                      ),
                      onChanged: (bool? value) {
                        setState(() {
                          if (value! == true) {
                            appList.add(app.packageName);
                          } else {
                            appList.remove(app.packageName);
                          }
                        });

                        updatePregs();
                      },
                    ),
                    const Divider(
                      height: 1.0,
                    ),
                  ],
                );
              },
            ),
          );
        }
      },
    );
  }

  void updatePregs() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove('applications');
    await prefs.setStringList('applications', appList);
    FlutterBackgroundService()
        .sendData({"action": "app_list", "data": appList});
  }
}
