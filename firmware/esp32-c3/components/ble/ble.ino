#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <BLE2901.h>

#define PACKET_SIZE 30
#define BLE_WAIT_TIMEOUT_MS 30000UL
#define SEND_FINISH_DELAY_MS 1000UL

#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer *pServer = nullptr;
BLECharacteristic *pCharacteristic = nullptr;
BLE2901 *descriptor_2901 = nullptr;

volatile bool deviceConnected = false;
volatile bool keyPressed = false;
bool oldDeviceConnected = false;
bool dataSent = false;

uint8_t packetBuffer[PACKET_SIZE];
uint32_t packetNumber = 0;
unsigned long bleStartTime = 0;
/*
 *   为调试提供状态反馈
 */

class MyServerCallbacks : public BLEServerCallbacks
{
    void onConnect(BLEServer *server) override
    {
        deviceConnected = true;
        dataSent = false;
        Serial.println("手机已连接");
    }

    void onDisconnect(BLEServer *server) override
    {
        deviceConnected = false;

        Serial.println("手机断开 BLE");

        pServer->getAdvertising()->start();

        // 重新开始超时计时
        bleStartTime = millis();

        Serial.println("重新开始 BLE 广播");
    }
};

/*
 *   接受手机端的数据，并通过串口传递进行调试
 */
class MyCharacteristicCallbacks : public BLECharacteristicCallbacks
{
    void onWrite(BLECharacteristic *characteristic) override
    {
        String rxValue = characteristic->getValue();
        if (rxValue.length() > 0)
        {
            Serial.print("手机发送的数据: ");
            Serial.println(rxValue);
        }
    }
};

/*
 *   开始广播
 */
void startAdvertising()
{
    BLEDevice::startAdvertising();
    Serial.println("BLE 开始广播");
}

void ble_setup()
{
    BLEDevice::init("ESP32-C3");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    BLEService *pService = pServer->createService(SERVICE_UUID);
    pCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_READ |
            BLECharacteristic::PROPERTY_WRITE |
            BLECharacteristic::PROPERTY_NOTIFY |
            BLECharacteristic::PROPERTY_INDICATE);
    pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
    pCharacteristic->addDescriptor(new BLE2902());

    descriptor_2901 = new BLE2901();
    descriptor_2901->setDescription("ESP32-C3 data characteristic");
    descriptor_2901->setAccessPermissions(ESP_GATT_PERM_READ);
    pCharacteristic->addDescriptor(descriptor_2901);

    pService->start();

    BLEAdvertising *advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(SERVICE_UUID);
    advertising->setScanResponse(false);
    advertising->setMinPreferred(0x0);
    startAdvertising();
    bleStartTime = millis();
}