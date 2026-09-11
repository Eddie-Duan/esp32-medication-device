#include <Arduino.h>
#include "esp_sleep.h"

#define BUTTON_PIN 4

void lightsleep_setup()
{
    pinMode(BUTTON_PIN, INPUT_PULLUP);

    esp_sleep_enable_gpio_wakeup();

    gpio_wakeup_enable(
        (gpio_num_t)BUTTON_PIN,
        GPIO_INTR_LOW_LEVEL);
}

void lightsleep()
{
    // 进入 Light Sleep
    esp_light_sleep_start();
}
