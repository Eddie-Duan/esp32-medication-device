#include "esp_sleep.h"
#define BUTTON_PIN 4

const unsigned long BLE_TIMEOUT = 30000;
/*
bool deadlineReached(uint32_t deadline)
{
  return static_cast<int32_t>(millis() - deadline) >= 0;
}

void enterDeepSleep()
{
  Serial.println("准备进入 Deep Sleep...");
  Serial.flush();
  delay(100);
  esp_deep_sleep_start();
}
*/
void deepsleep_setup()
{
  esp_deep_sleep_enable_gpio_wakeup(
      1ULL << BUTTON_PIN,
      ESP_GPIO_WAKEUP_GPIO_LOW);
}

/*超过限定时长后进入深度睡眠*/
void goToDeepSleep()
{

  Serial.println("BLE 超时，准备进入 Deep Sleep");

  // 停止 BLE
  BLEDevice::deinit(true);

  delay(100);

  // GPIO4 作为唤醒源
  esp_deep_sleep_enable_gpio_wakeup(
      1ULL << BUTTON_PIN,
      ESP_GPIO_WAKEUP_GPIO_LOW);

  Serial.println("进入 Deep Sleep");
  delay(100);

  esp_deep_sleep_start();
}

void deepsleep()
{
  esp_deep_sleep_start();
}