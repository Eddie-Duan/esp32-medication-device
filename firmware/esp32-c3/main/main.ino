#include <Arduino.h>
#include "../components/ble/ble.ino"
#include "../components/flash/flash.ino"
#include "../components/time/time.ino"

// ESP32-C3 GPIO4 -- button -- GND. Sleep stays disabled during foreground sync.
#define BUTTON_PIN 4
void IRAM_ATTR keyISR() { keyPressed = true; }

void setup() {
  Serial.begin(115200);
  delay(500);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  // A mount error must never erase recordings. A factory-blank board may need
  // a one-time filesystem initialization by the hardware team before testing.
  storageReady = SPIFFS.begin(false);
  counterReady = fileCounter.begin("proto-files", false);
  Serial.println(storageReady ? "SPIFFS mounted" : "SPIFFS unavailable; no auto-format");
  // Existing hardware time stub retained; raw timestamps are not validated UTC.
  setManualTime(2026, 8, 29, 22, 30, 0);
  writeFile();
  char identity[13];
  const uint64_t chipId = ESP.getEfuseMac();
  snprintf(identity, sizeof(identity), "%04X%08X", (uint16_t)(chipId >> 32), (uint32_t)chipId);
  stableDeviceId = identity;
  commandQueue = xQueueCreate(12, sizeof(ControlCommand));
  if (!commandQueue) { Serial.println("CONTROL_QUEUE_ALLOCATION_FAILED"); return; }
  BLEDevice::init("ESP32-C3");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *service = pServer->createService(SERVICE_UUID);
  pCharacteristic = service->createCharacteristic(CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY);
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  notifyDescriptor = new BLE2902();
  pCharacteristic->addDescriptor(notifyDescriptor);
  service->start();
  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(false);
  startAdvertising();
  attachInterrupt(digitalPinToInterrupt(BUTTON_PIN), keyISR, FALLING);
}
void loop() {
  if (!commandQueue) { delay(100); return; }
  if (!deviceConnected && advertisePending) {
    advertisePending = false;
    startAdvertising();
  }
  serviceSync();
  // Do not block for a held button: ACKs and BLE callbacks must keep progressing.
  static uint32_t lastButtonAt = 0;
  if (keyPressed) {
    keyPressed = false;
    if (millis() - lastButtonAt > 250 && digitalRead(BUTTON_PIN) == LOW) {
      lastButtonAt = millis();
      writeFile();
      Serial.println("Press Re-sync in app to fetch new files");
    }
  }
  delay(10);
}
