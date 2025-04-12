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
    'Red': '0',
    'IR': '0',
    'SpO2': '0%',
    'Signal': 'Weak',
  };
  List<Map<String, String>> scanResults = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    flutterBlue.state.listen((state) {
      if (state == BluetoothState.off) {
        print("Bluetooth state changed to $state, resetting connection");
        _cleanupConnection();
      }
    });
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
    if (isScanning || isConnected) return;
    setState(() {
      isScanning = true;
      scanResults.clear();
      sensorData = {
        'Violet': '0',
        'Blue': '0',
        'Red': '0',
        'IR': '0',
        'SpO2': '0%',
        'Signal': 'Weak',
      };
    });
    flutterBlue.stopScan();
    flutterBlue.startScan(timeout: Duration(seconds: 10)).then((_) {
      flutterBlue.scanResults.listen(
        (results) {
          for (ScanResult result in results) {
            if (result.device.name == 'EnviroHealthMonitor') {
              flutterBlue.stopScan();
              connectToDevice(result.device);
              break;
            }
          }
        },
        onDone: () {
          if (!isConnected) {
            setState(() => isScanning = false);
            print("Scan completed, no device found or connected");
          }
        },
      );
    });
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      if (connectedDevice != null) {
        await _cleanupConnection();
      }
      print("Connecting to ${device.name}");
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
              print("Subscribed to ${characteristic!.uuid}");
              characteristic!.value.listen(
                (value) {
                  String data = String.fromCharCodes(value);
                  print("Received: $data");
                  _parseData(data);
                },
                onError: (error) {
                  print("Characteristic error: $error");
                },
              );
              break;
            }
          }
          break;
        }
      }
      Future.delayed(Duration(seconds: 10), () {
        if (isConnected) {
          _computeFinalResult();
          _cleanupConnection();
        }
      });
    } catch (e) {
      print('Connection error: $e');
      setState(() => isScanning = false);
    }
  }

  Future<void> _cleanupConnection() async {
    print("Cleaning up connection...");
    try {
      if (characteristic != null) {
        await characteristic!.setNotifyValue(false);
        characteristic = null;
      }
    } catch (e) {
      print("Error unsubscribing: $e");
    }
    try {
      if (connectedDevice != null) {
        await connectedDevice!.disconnect();
        connectedDevice = null;
      }
    } catch (e) {
      print("Error disconnecting: $e");
    }
    setState(() => isConnected = false);
  }

  void _parseData(String data) {
    List<String> parts = data.split(',');
    Map<String, String> currentData = {};
    for (String part in parts) {
      if (part.startsWith('V:')) currentData['Violet'] = part.substring(2);
      if (part.startsWith('B:')) currentData['Blue'] = part.substring(2);
      if (part.startsWith('R:')) currentData['Red'] = part.substring(2);
      if (part.startsWith('IR:')) currentData['IR'] = part.substring(3);
      if (part.startsWith('SpO2:')) currentData['SpO2'] = part.substring(5);
      if (part.contains('Good') || part.contains('Weak'))
        currentData['Signal'] = part.split(',').last;
      if (part.startsWith('Hb:')) {
        // Extract the Hb value (e.g., "12.9" from "Hb:12.9 g/dL")
        String hbValue = part.substring(3).split(' ')[0]; // Get "12.9"
        currentData['Hb'] = hbValue;
      }
    }
    scanResults.add(currentData);
    setState(() {
      sensorData = Map.from(currentData);
    });
  }

  void _computeFinalResult() {
    if (scanResults.isEmpty) return;
    double totalSpo2 = 0;
    int validReadings = 0;
    for (var result in scanResults) {
      double? spo2 = double.tryParse(
        result['SpO2']?.replaceAll('%', '') ?? '0',
      );
      if (spo2 != null && spo2 >= 70 && spo2 <= 100) {
        totalSpo2 += spo2;
        validReadings++;
      }
    }
    double finalSpo2 = validReadings > 0 ? totalSpo2 / validReadings : 0;
    int violet = int.tryParse(scanResults.last['Violet'] ?? '0') ?? 0;
    int blue = int.tryParse(scanResults.last['Blue'] ?? '0') ?? 0;
    int red = int.tryParse(scanResults.last['Red'] ?? '0') ?? 0;
    int ir = int.tryParse(scanResults.last['IR'] ?? '0') ?? 0;
    // Use the last parsed Hb value instead of the average
    String lastHb = scanResults.last['Hb'] ?? '0';
    setState(() {
      sensorData['SpO2'] = 'Final result is ${finalSpo2.toStringAsFixed(1)}%';
      sensorData['Violet'] = scanResults.last['Violet'] ?? '0';
      sensorData['Blue'] = scanResults.last['Blue'] ?? '0';
      sensorData['Red'] = scanResults.last['Red'] ?? '0';
      sensorData['IR'] = scanResults.last['IR'] ?? '0';
      sensorData['Signal'] = scanResults.last['Signal'] ?? 'Weak';
      sensorData['Hb'] = 'Hb Index: ${lastHb}'; // Use parsed Hb
    });
    print("Final SpO2: ${sensorData['SpO2']}, Hb Index: ${sensorData['Hb']}");
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
            Text('Red: ${sensorData['Red']}'),
            Text('IR: ${sensorData['IR']}'),
            Text('SpO2: ${sensorData['SpO2']}'),
            Text('Hb: ${sensorData['Hb']}'),
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
          ],
        ),
      ),
    );
  }
}