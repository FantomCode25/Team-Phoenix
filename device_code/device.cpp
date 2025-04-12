#include <Wire.h>
#include <Adafruit_AS726x.h>
#include <MAX30105.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <math.h> // For log function

#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

#define SDA_PIN 21
#define SCL_PIN 22

Adafruit_AS726x as726x;
MAX30105 particleSensor;
BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

long irValue, redValue;
const int SAMPLE_SIZE = 10; // Buffer size for moving average
long irBuffer[SAMPLE_SIZE], redBuffer[SAMPLE_SIZE];
int bufferIndex = 0;
long irDC = 0, redDC = 0; // DC components
long irAC = 0, redAC = 0; // AC components
long irBaseline = 40000, redBaseline = 40000; // Initial high baseline

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
  as726x.setGain(1); // 3X gain
  as726x.setIntegrationTime(200); // Adjusted for stability
  as726x.drvOn(); // Enable built-in LED
  Serial.println("AS7262 driver enabled - LED should be on");

  // Initialize MAX30102
  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 not found");
    while (1);
  }
  Serial.println("MAX30102 initialized");
  byte ledBrightness = 10; // Optimized for signal
  byte sampleAverage = 8; // Higher averaging
  byte ledMode = 2; // Red + IR
  byte sampleRate = 200; // 200 samples/sec
  int pulseWidth = 1186; // Better resolution
  int adcRange = 4096; // 18-bit
  particleSensor.setup(ledBrightness, sampleAverage, ledMode, sampleRate, pulseWidth, adcRange);
  particleSensor.setPulseAmplitudeRed(ledBrightness);
  particleSensor.setPulseAmplitudeGreen(0);

  // Set initial high baseline
  Serial.print("Initial Baseline IR: "); Serial.print(irBaseline);
  Serial.print(" Initial Baseline Red: "); Serial.println(redBaseline);

  // Initialize buffers
  for (int i = 0; i < SAMPLE_SIZE; i++) {
    irBuffer[i] = 0;
    redBuffer[i] = 0;
  }

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

void updateBuffer(long ir, long red) {
  irBuffer[bufferIndex] = ir;
  redBuffer[bufferIndex] = red;
  bufferIndex = (bufferIndex + 1) % SAMPLE_SIZE;

  // Calculate moving average (DC component)
  irDC = 0;
  redDC = 0;
  for (int i = 0; i < SAMPLE_SIZE; i++) {
    irDC += irBuffer[i];
    redDC += redBuffer[i];
  }
  irDC /= SAMPLE_SIZE;
  redDC /= SAMPLE_SIZE;

  // Peak-to-peak AC component
  long irMax = 0, irMin = irBuffer[0];
  long redMax = 0, redMin = redBuffer[0];
  for (int i = 0; i < SAMPLE_SIZE; i++) {
    if (irBuffer[i] > irMax) irMax = irBuffer[i];
    if (irBuffer[i] < irMin) irMin = irBuffer[i];
    if (redBuffer[i] > redMax) redMax = redBuffer[i];
    if (redBuffer[i] < redMin) redMin = redBuffer[i];
  }
  irAC = irMax - irMin;
  redAC = redMax - redMin;

  // Finger detection
  if (irAC < 50 || irDC < 5000) {
    irAC = 0;
    redAC = 0;
  }
}

void loop() {
  as726x.startMeasurement();
  while (!as726x.dataReady()) delay(5);
  uint16_t violet = as726x.readCalibratedViolet();
  uint16_t blue = as726x.readCalibratedBlue();

  irValue = particleSensor.getIR();
  redValue = particleSensor.getRed();

  // Update buffer for AC/DC estimation
  updateBuffer(irValue, redValue);

  // SpO2 calculation with finger detection
  float ratio = (redAC > 0 && irAC > 0 && redDC > 5000 && irDC > 5000) 
                ? (float)redAC / redDC / (float)irAC / irDC : 1.0;
  int spo2 = (irAC > 50 && ratio > 0) ? (int)(110 - 20 * ratio) : 0; // Adjusted formula
  if (spo2 < 90 && spo2 > 0) spo2 = 90;
  if (spo2 > 100) spo2 = 100;

  // Hb calculation using absorbance approximation
  float absRed = (redBaseline > 0) ? max(0.0f, -log((float)redValue / redBaseline)) : 0.0f;
  float absIR = (irBaseline > 0) ? max(0.0f, -log((float)irValue / irBaseline)) : 0.0f;
  float hbA = 12.0; // Adjusted baseline
  float hbB = 1.5;  // Adjusted Red factor
  float hbC = 1.0;  // Adjusted IR factor
  float hbIndex = (irValue > 5000 && (absRed > 0.0f || absIR > 0.0f)) 
                 ? (hbA + (hbB * absRed) + (hbC * absIR)) : 0.0f;
  if (hbIndex > 18.0) hbIndex = 18.0; // Cap at upper limit

  // Prepare data string
  String data = "V:" + String(violet) + ",B:" + String(blue) + 
               ",IR:" + String(irValue) + ",R:" + String(redValue) + 
               ",SpO2:" + String(spo2) + "%," + 
               "Hb:" + String(hbIndex, 1) + " g/dL," + 
               (irValue > 5000 ? "Good" : "Weak");
  pCharacteristic->setValue(data.c_str());
  if (deviceConnected) {
    pCharacteristic->notify();
  }

  Serial.print("Violet: "); Serial.print(violet);
  Serial.print(" Blue: "); Serial.print(blue);
  Serial.print(" IR: "); Serial.print(irValue);
  Serial.print(" Red: "); Serial.print(redValue);
  Serial.print(" SpO2: "); Serial.print(spo2);
  Serial.print(" Hb: "); Serial.print(hbIndex); Serial.print(" g/dL");
  if (irValue > 5000) Serial.print(" Good signal");
  else Serial.print(" Weak signal");
  Serial.println();
  delay(1000);
}