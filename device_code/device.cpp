#include <Wire.h>
#include <Adafruit_AS726x.h>
#include <MAX30105.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

#define SDA_PIN 21
#define SCL_PIN 22

Adafruit_AS726x as726x;
MAX30105 particleSensor;
BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

long irValue;
long redValue;

class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
  }
};

void setup() {
  Serial.begin(115200);
  Wire.begin(SDA_PIN, SCL_PIN);

  // Initialize AS726x
  if (!as726x.begin()) {
    Serial.println("AS7262 not found");
    while (1);
  }
  Serial.println("AS7262 detected");
  as726x.setGain(2); // 16X gain
  as726x.setIntegrationTime(250); // Adjusted for stability
  as726x.drvOn(); // Enable built-in LED
  Serial.println("AS7262 driver enabled - LED should be on");

  // Initialize MAX30102
  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 not found");
    while (1);
  }
  Serial.println("MAX30102 initialized");
  byte ledBrightness = 5; // Reduced to avoid saturation
  byte sampleAverage = 8; // Higher averaging for stability
  byte ledMode = 2; // Red + IR
  byte sampleRate = 200; // 200 samples/sec
  int pulseWidth = 699; // 699 µs
  int adcRange = 4096; // 18-bit
  particleSensor.setup(ledBrightness, sampleAverage, ledMode, sampleRate, pulseWidth, adcRange);
  particleSensor.setPulseAmplitudeRed(ledBrightness);
  particleSensor.setPulseAmplitudeGreen(0);

  // Initialize BLE
  BLEDevice::init("EnviroHealthMonitor");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pService->start();
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->start();
  Serial.println("BLE started - Connect with iPhone app");
}

void loop() {
  as726x.startMeasurement();
  while (!as726x.dataReady()) delay(5);
  uint16_t violet = as726x.readCalibratedViolet();
  uint16_t blue = as726x.readCalibratedBlue();

  irValue = particleSensor.getIR();
  redValue = particleSensor.getRed();

  // Prepare data string
  String data = "V:" + String(violet) + ",B:" + String(blue) + ",IR:" + String(irValue) + ",R:" + String(redValue) + "," + (irValue > 5000 ? "Good" : "Weak");
  pCharacteristic->setValue(data.c_str());
  if (deviceConnected) {
    pCharacteristic->notify();
  }

  Serial.print("Violet: "); Serial.print(violet);
  Serial.print(" Blue: "); Serial.print(blue);
  Serial.print(" IR: "); Serial.print(irValue);
  Serial.print(" Red: "); Serial.print(redValue);
  if (irValue > 5000) Serial.print(" Good signal");
  else Serial.print(" Weak signal");
  Serial.println();
  delay(1000);
}