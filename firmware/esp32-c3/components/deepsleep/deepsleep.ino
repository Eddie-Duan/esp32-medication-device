#include "esp_sleep.h"
#define BUTTON_PIN 4

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
void deepsleep()
{
  esp_deep_sleep_start();
}