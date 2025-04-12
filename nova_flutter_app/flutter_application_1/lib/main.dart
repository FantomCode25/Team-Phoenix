import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:permission_handler/permission_handler.dart';

class MLPredictor {
  static double predictHb(Map<String, String> sensorData) {
    double violet = double.tryParse(sensorData['Violet'] ?? '0') ?? 0;
    double blue = double.tryParse(sensorData['Blue'] ?? '0') ?? 0;
    double red = double.tryParse(sensorData['Red'] ?? '0') ?? 0;
    double ir = double.tryParse(sensorData['IR'] ?? '0') ?? 0;
    double spo2 = double.tryParse(sensorData['SpO2'] ?? '0') ?? 0;
    String lastHb = sensorData['Hb'] ?? '0';

    double predictedHb = double.tryParse(lastHb) ?? 0.0;

    print(
      'ML Prediction: Using features (Violet:$violet, Blue:$blue, Red:$red, IR:$ir, SpO2:$spo2) to predict Hb = $predictedHb',
    );
    return predictedHb;
  }
}

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'N.O.V.A',
      theme: ThemeData(primarySwatch: Colors.blue, fontFamily: 'SF Pro Text'),
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
  bool isFinalResultReady = false;
  Map<String, String> sensorData = {
    'Violet': '0',
    'Blue': '0',
    'Red': '0',
    'IR': '0',
    'SpO2': '0',
    'Hb': '0',
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
        'SpO2': '0',
        'Hb': '0',
        'Signal': 'Weak',
      };
      isFinalResultReady = false;
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
      if (part.startsWith('SpO2:'))
        currentData['SpO2'] = part.substring(5).replaceAll('%', '');
      if (part.contains('Good') || part.contains('Weak'))
        currentData['Signal'] = part.split(',').last;
      if (part.startsWith('Hb:')) {
        String hbValue = part.substring(3).split(' ')[0];
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
      double? spo2 = double.tryParse(result['SpO2'] ?? '0');
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

    double predictedHb = MLPredictor.predictHb(scanResults.last);

    setState(() {
      sensorData['SpO2'] = finalSpo2.toStringAsFixed(1);
      sensorData['Violet'] = scanResults.last['Violet'] ?? '0';
      sensorData['Blue'] = scanResults.last['Blue'] ?? '0';
      sensorData['Red'] = scanResults.last['Red'] ?? '0';
      sensorData['IR'] = scanResults.last['IR'] ?? '0';
      sensorData['Signal'] = scanResults.last['Signal'] ?? 'Weak';
      sensorData['Hb'] = predictedHb.toStringAsFixed(1);
      isFinalResultReady = true;
    });
    print("Final SpO2: ${sensorData['SpO2']}, Hb Index: ${sensorData['Hb']}");
  }

  Widget _getDietRecommendation(double hb) {
    if (hb < 8) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🔴 Severe Anemia (Hb < 8 g/dL)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          Text(
            'Goal: Rapid iron replenishment, high absorption, supplements (if needed)',
          ),
          SizedBox(height: 8),
          Text('🥩 Non-Vegetarian'),
          Text('Beef, mutton, lamb (especially liver and kidney)'),
          Text('Chicken liver, turkey'),
          Text('Tuna, salmon, sardines, mackerel'),
          Text('Shellfish: oysters, mussels, clams'),
          Text('Eggs (especially yolk)'),
          SizedBox(height: 8),
          Text('🥦 Vegetarian'),
          Text('Spinach, amaranth leaves, moringa (drumstick leaves)'),
          Text('Beetroot, sweet potatoes'),
          Text('Blackstrap molasses'),
          Text('Iron-fortified cereals, bread'),
          Text('Cooked lentils, soybeans, chickpeas'),
          Text('Tofu, tempeh'),
          Text('Pumpkin seeds, flaxseeds, sesame seeds'),
          Text('Dried fruits: prunes, raisins, apricots'),
          Text('Dates and figs'),
          Text('Jaggery with peanuts or sesame'),
          SizedBox(height: 8),
          Text('🍊 Iron Absorption Enhancers'),
          Text('Orange, lemon, guava, Indian gooseberry (amla)'),
          Text('Tomato, bell peppers'),
          Text('Vitamin C-rich juices with iron meals'),
        ],
      );
    } else if (hb >= 8 && hb <= 10.9) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🟠 Moderate Anemia (Hb 8–10.9 g/dL)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          Text(
            'Goal: Regular intake of iron-rich meals, better absorption, balance',
          ),
          SizedBox(height: 8),
          Text('🥩 Non-Vegetarian'),
          Text('Lean red meats'),
          Text('Chicken and turkey'),
          Text('Boiled eggs'),
          Text('Grilled fish'),
          Text('Bone marrow broth'),
          SizedBox(height: 8),
          Text('🥦 Vegetarian'),
          Text('Cooked spinach, kale, methi'),
          Text('Peas, black-eyed peas (lobia), lentils'),
          Text('Sprouted moong, chana'),
          Text('Quinoa, millets (ragi, bajra)'),
          Text('Brown rice, oats'),
          Text('Paneer, cheese'),
          Text('Iron-fortified soy milk or almond milk'),
          Text('Baked potatoes (with skin)'),
          SizedBox(height: 8),
          Text('🍊 Enhancers'),
          Text('Add lemon juice to dals or sabzi'),
          Text('Drink citrus juice with meals'),
          Text(
            'Avoid dairy and caffeine during iron-rich meals (inhibits absorption)',
          ),
        ],
      );
    } else if (hb >= 11 && hb <= 11.9) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🟡 Mild Anemia (Hb 11–11.9 g/dL)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.yellow[700],
            ),
          ),
          Text('Goal: Prevent worsening, improve iron status naturally'),
          SizedBox(height: 8),
          Text('🥩 Non-Vegetarian'),
          Text('Boiled or poached eggs'),
          Text('Lightly cooked chicken'),
          Text('Fish once or twice a week'),
          SizedBox(height: 8),
          Text('🥦 Vegetarian'),
          Text('Apples, pomegranate, watermelon'),
          Text('Whole grains (wheat, oats)'),
          Text('Broccoli, cabbage, cauliflower'),
          Text('Cooked lentils and pulses'),
          Text('Sprouted grains (green gram, chana)'),
          Text('Dry fruits and nuts'),
          SizedBox(height: 8),
          Text('🍊 Enhancers'),
          Text('Citrus fruits in mid-meals'),
          Text('Use lemon, amla chutney, or raw mango in dishes'),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🟢 Normal Hemoglobin (Hb ≥ 12–13 g/dL)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          Text('Goal: Maintain hemoglobin and support blood health'),
          SizedBox(height: 8),
          Text('🥩 Non-Vegetarian'),
          Text('Balanced intake of fish, eggs, and lean meats'),
          Text('Once-a-week organ meat'),
          SizedBox(height: 8),
          Text('🥦 Vegetarian'),
          Text('Balanced intake of leafy greens, grains, pulses'),
          Text('Include vitamin C sources daily'),
          Text('Regular dry fruit and nuts intake'),
          Text('Include jaggery-based snacks once in a while'),
          SizedBox(height: 8),
          Text('💧 Hydration & Lifestyle'),
          Text('Hydration aids nutrient transport'),
          Text('Regular physical activity improves circulation and oxygen use'),
          SizedBox(height: 8),
          Text('⚠ Additional Tips:'),
          Text(
            'Avoid with iron-rich meals: tea, coffee, calcium-rich foods (milk, curd)',
          ),
          Text(
            'Cooking tip: Use iron utensils (like iron kadai) to increase iron content in food',
          ),
          Text(
            'Combine foods: e.g., Spinach dal with lemon, or beetroot salad with oranges',
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status bar and header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'N.O.V.A',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'HT45.5 - N.O.V.A',
                        style: TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                    ],
                  ),
                  Text(
                    '${sensorData['Signal']} Signal',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color:
                          sensorData['Signal'] == 'Good'
                              ? Colors.green
                              : Colors.red,
                    ),
                  ),
                ],
              ),
            ),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // Hb Level Card
                      _buildMeasurementCard(
                        title: 'Hb Level',
                        value: '${sensorData['Hb']}',
                        unit: 'g/dL',
                        color: Color(0xFFFFF1F1),
                        iconWidget: Icon(
                          Icons.water_drop,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),

                      SizedBox(height: 16),

                      // SpO2 Level Card
                      _buildMeasurementCard(
                        title: 'SpO2 Level',
                        value: '${sensorData['SpO2']}',
                        unit: '%',
                        color: Color(0xFFF1F5FF),
                        iconWidget: Text(
                          '%',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      SizedBox(height: 16),

                      if (isFinalResultReady)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            'Final Result Displayed',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                        ),

                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Color(0xFFF8FFFD),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            _buildSensorReading(
                              'Violet',
                              sensorData['Violet'] ?? '0',
                            ),
                            SizedBox(height: 8),
                            _buildSensorReading(
                              'Blue',
                              sensorData['Blue'] ?? '0',
                            ),
                            SizedBox(height: 8),
                            _buildSensorReading('IR', sensorData['IR'] ?? '0'),
                            SizedBox(height: 8),
                            _buildSensorReading(
                              'Red',
                              sensorData['Red'] ?? '0',
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 16),

                      // Recommended Diet
                      if (isFinalResultReady)
                        Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Color(0xFFFFFBF8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Recommended Diet',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              SizedBox(height: 10),
                              _getDietRecommendation(
                                double.tryParse(sensorData['Hb'] ?? '0') ?? 0,
                              ),
                            ],
                          ),
                        ),

                      SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),

            // Start Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isScanning || isConnected ? null : startScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF5E7BF9),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    disabledBackgroundColor: Color(0xFF5E7BF9).withOpacity(0.6),
                  ),
                  child: Text(
                    'Start',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeasurementCard({
    required String title,
    required String value,
    required String unit,
    required Color color,
    required Widget iconWidget,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
                SizedBox(height: 8),
                Text(
                  '$value $unit',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(child: iconWidget),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorReading(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Color(0xFF24A677))),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}