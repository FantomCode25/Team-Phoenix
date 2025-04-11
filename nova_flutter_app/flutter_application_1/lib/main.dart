import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EnviroHealth Monitor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: BluetoothPage(),
    );
  }
}

class BluetoothPage extends StatefulWidget {
  @override
  _BluetoothPageState createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  FlutterBlue flutterBlue = FlutterBlue.instance;
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? characteristic;
  bool isScanning = false;
  bool isConnected = false;
  Map<String, String> sensorData = {
    'Violet': '0',
    'Blue': '0',
    'IR': '0',
    'Red': '0',
    'Signal': 'Weak',
  };

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    var status =
        await [
          Permission.bluetooth,
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
          Permission.locationWhenInUse,
        ].request();
    if (status[Permission.bluetooth]!.isGranted &&
        status[Permission.locationWhenInUse]!.isGranted) {
      print('Permissions granted');
    } else {
      print('Permissions denied');
    }
  }

  void startScan() {
    setState(() => isScanning = true);
    flutterBlue.startScan(timeout: Duration(seconds: 10));
    flutterBlue.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (result.device.name == 'EnviroHealthMonitor') {
          flutterBlue.stopScan();
          connectToDevice(result.device);
          break;
        }
      }
    });
    setState(() => isScanning = false);
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        connectedDevice = device;
        isConnected = true;
      });
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid.toString() == '4fafc201-1fb5-459e-8fcc-c5c9c331914b') {
          for (BluetoothCharacteristic c in service.characteristics) {
            if (c.uuid.toString() == 'beb5483e-36e1-4688-b7f5-ea07361b26a8') {
              characteristic = c;
              await characteristic!.setNotifyValue(true);
              characteristic!.value.listen((value) {
                String data = String.fromCharCodes(value);
                _parseData(data);
              });
              break;
            }
          }
          break;
        }
      }
    } catch (e) {
      print('Connection error: $e');
    }
  }

  void _parseData(String data) {
    List<String> parts = data.split(',');
    for (String part in parts) {
      if (part.startsWith('V:')) sensorData['Violet'] = part.substring(2);
      if (part.startsWith('B:')) sensorData['Blue'] = part.substring(2);
      if (part.startsWith('IR:')) sensorData['IR'] = part.substring(3);
      if (part.startsWith('R:')) sensorData['Red'] = part.substring(2);
      if (part.contains('Good') || part.contains('Weak'))
        sensorData['Signal'] = part.split(',').last;
    }
    setState(() {});
  }

  void disconnect() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      setState(() {
        connectedDevice = null;
        isConnected = false;
        sensorData = {
          'Violet': '0',
          'Blue': '0',
          'IR': '0',
          'Red': '0',
          'Signal': 'Weak',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('EnviroHealth Monitor')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Violet: ${sensorData['Violet']}'),
            Text('Blue: ${sensorData['Blue']}'),
            Text('IR: ${sensorData['IR']}'),
            Text('Red: ${sensorData['Red']}'),
            Text(
              'Signal: ${sensorData['Signal']}',
              style: TextStyle(
                color:
                    sensorData['Signal'] == 'Good' ? Colors.green : Colors.red,
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: isScanning || isConnected ? null : startScan,
              child: Text('Start Scan'),
            ),
            ElevatedButton(
              onPressed: isConnected ? disconnect : null,
              child: Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }
}