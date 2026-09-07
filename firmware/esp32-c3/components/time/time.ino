#include <time.h>
#include <sys/time.h>
#include <Arduino.h>

void setManualTime(int year, int month, int day, int hour, int minute, int second)
{
    struct tm timeinfo = {};
    timeinfo.tm_year = year - 1900;
    timeinfo.tm_mon = month - 1;
    timeinfo.tm_mday = day;
    timeinfo.tm_hour = hour;
    timeinfo.tm_min = minute;
    timeinfo.tm_sec = second;

    time_t timestamp = mktime(&timeinfo);
    struct timeval now = {};
    now.tv_sec = timestamp;
    settimeofday(&now, nullptr);
}

/*
 *   通过串口反馈数据
 */
void printTime()
{
    time_t now;
    time(&now);
    struct tm timeinfo;
    localtime_r(&now, &timeinfo);

    Serial.printf("%04d-%02d-%02d %02d:%02d:%02d\n",
                  timeinfo.tm_year + 1900,
                  timeinfo.tm_mon + 1,
                  timeinfo.tm_mday,
                  timeinfo.tm_hour,
                  timeinfo.tm_min,
                  timeinfo.tm_sec);
}
