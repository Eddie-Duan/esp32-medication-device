#include <../components/ble/ble.ino>
#include <../components/flash/flash.ino>
#include <../components/time/time.ino>
#include <../components/deepsleep/deepsleep.ino>
#include <Arduino.h>

#include <time.h>
#include <sys/time.h>

// ESP32-C3 的 RTC GPIO 为 GPIO0~GPIO5，这里使用 GPIO4 进行深睡唤醒。
// 按键接线：GPIO4 -- 按键 -- GND。
#define BUTTON_PIN 4
/*
extern BLEServer *pServer = nullptr;
extern BLECharacteristic *pCharacteristic = nullptr;
extern BLE2901 *descriptor_2901 = nullptr;

extern volatile bool deviceConnected = false;
extern volatile bool keyPressed = false;
extern bool oldDeviceConnected = false;
extern bool dataSent = false;

extern uint8_t packetBuffer[PACKET_SIZE];
extern uint32_t packetNumber = 0;
// uint32_t sleepDeadline = 0;
*/
void IRAM_ATTR keyISR()
{
  keyPressed = true;
}

void setup()
{
  Serial.begin(115200);
  delay(500);

  Serial.println();
  Serial.println("ESP32-C3 启动");

  pinMode(BUTTON_PIN, INPUT_PULLUP);
  /*
    // 单个 GPIO4 低电平唤醒。GPIO4 是 ESP32-C3 的 RTC GPIO。
    gpio_wakeup_enable((gpio_num_t)BUTTON_PIN, GPIO_INTR_LOW_LEVEL);
  esp_err_t wakeupResult = esp_sleep_enable_gpio_wakeup();
    if (wakeupResult != ESP_OK)
    {
      Serial.print("深睡唤醒配置失败，错误码: ");
      Serial.println(wakeupResult);
    }
    else
    {
      Serial.println("GPIO4 低电平深睡唤醒已启用");
    }
  */
  spiff_setup();
  deepsleep_setup();
  // 保留原程序的手动时间设置。
  setManualTime(2026, 8, 29, 22, 30, 0);
  Serial.println("Time calibrated.");
  printTime();

  // 每次启动或深睡唤醒时创建一条记录。
  writeFile();

  ble_setup();

  attachInterrupt(digitalPinToInterrupt(BUTTON_PIN), keyISR, FALLING);

  // sleepDeadline = millis() + BLE_WAIT_TIMEOUT_MS;
  Serial.println("Waiting a client connection...");
  delay(1000);

  

  //  delay(10);
}

void loop()
{
  if (deviceConnected && !oldDeviceConnected)
  {
    oldDeviceConnected = true;
    dataSent = false;
  }

  // 中断函数只设置标志，消抖和文件操作放到 loop() 中执行。
  delay(30);

  if (digitalRead(BUTTON_PIN) == LOW)
  {
    Serial.println("按键按下");
    while (digitalRead(BUTTON_PIN) == LOW)
      ;

    writeFile();
    dataSent = false;
    // sleepDeadline = millis() + BLE_WAIT_TIMEOUT_MS;
    Serial.println("按键释放");
    if (deviceConnected)
    sendAllFiles();
  }
  keyPressed = false;
  

  if (!deviceConnected)
  {
    startAdvertising();
    oldDeviceConnected = false;
    dataSent = false;

    if (millis() - bleStartTime >= BLE_TIMEOUT)
    {

      goToDeepSleep();
    }
  }
}