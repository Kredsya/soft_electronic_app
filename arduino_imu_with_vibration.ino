#include "Wire.h"
#include "I2Cdev.h"
#include "MPU6050.h"
#include <SoftwareSerial.h>
#include <ArduinoJson.h>

// 블루투스 모듈 연결핀 (RX: 2, TX: 3)
SoftwareSerial mySerial(2, 3);
MPU6050 mpu;

// 진동 모터 핀
const int VIBRATION_PIN = 11;

// 가속도 센서 값
int16_t ax, ay, az;
// 기준 자세(Pitch) 값
float baselinePitch = 0;

// 측정 상태를 제어하는 변수
bool isMeasuring = false;
unsigned long lastPrintTime = 0;
unsigned long measurementStartTime = 0;

// 'ready' 메시지 주기적 전송을 위한 변수
unsigned long lastReadySendTime = 0;
const long readyInterval = 5000; // 5초 간격으로 'ready' 전송

// 센서 스케일 상수
const float ACCEL_SCALE = 16384.0;

// 진동 관련 변수
unsigned long vibrationStartTime = 0;
int vibrationDuration = 0;
bool isVibrating = false;

// --- 진동 모터 제어 함수 ---
void startVibration(int duration) {
  digitalWrite(VIBRATION_PIN, HIGH);
  vibrationStartTime = millis();
  vibrationDuration = duration;
  isVibrating = true;
  Serial.print("진동 시작 - 지속시간: ");
  Serial.print(duration);
  Serial.println("ms");
}

void stopVibration() {
  digitalWrite(VIBRATION_PIN, LOW);
  isVibrating = false;
  Serial.println("진동 중지");
}

void updateVibration() {
  if (isVibrating && millis() - vibrationStartTime >= vibrationDuration) {
    stopVibration();
  }
}

// --- 'ready' 메시지를 보내는 함수 ---
void sendReadyMessage() {
  StaticJsonDocument<128> readyDoc;
  readyDoc["module"] = "IMU";
  readyDoc["status"] = "ready";
  serializeJson(readyDoc, mySerial);
  mySerial.println();
  lastReadySendTime = millis();
}

void setup() {
  Serial.begin(115200);
  mySerial.begin(9600);
  Wire.begin();

  // 진동 모터 핀 설정
  pinMode(VIBRATION_PIN, OUTPUT);
  digitalWrite(VIBRATION_PIN, LOW);

  mpu.initialize();
  if (!mpu.testConnection()) {
    Serial.println("MPU6050 연결 실패");
    while (1);
  }

  // 진동 테스트 (초기화 확인용)
  Serial.println("진동 테스트 시작...");
  startVibration(500);
  delay(600); // 진동 완료까지 대기
  updateVibration();
  Serial.println("진동 테스트 완료");

  // 최초 'ready' 메시지 전송
  sendReadyMessage();

  Serial.println("MPU6050 및 진동 모터 준비 완료. 앱의 시작(start) 명령을 기다립니다...");
}

void loop() {
  // 진동 상태 업데이트
  updateVibration();

  // 1. 앱으로부터 명령 수신 처리
  if (mySerial.available() > 0) {
    String input = mySerial.readStringUntil('\n');
    input.trim(); // 공백 제거
    Serial.print("수신된 명령: ");
    Serial.println(input);
    
    StaticJsonDocument<128> doc;
    DeserializationError error = deserializeJson(doc, input);

    if (!error) {
      const char* command = doc["command"];
      if (command) {
        Serial.print("명령 파싱 성공: ");
        Serial.println(command);
        
        // "vibrate" 명령 처리
        if (strcmp(command, "vibrate") == 0) {
          int duration = doc["duration"] | 500; // 기본값 500ms
          Serial.print("🔥🔥🔥 진동 명령 수신! 지속시간: ");
          Serial.print(duration);
          Serial.println("ms");
          
          startVibration(duration);

          // 응답 전송
          StaticJsonDocument<128> responseDoc;
          responseDoc["status"] = "vibration_started";
          responseDoc["duration"] = duration;
          serializeJson(responseDoc, mySerial);
          mySerial.println();
          Serial.println("📤 진동 시작 응답 전송됨");
        }

        // "test" 명령 처리 (진동 테스트용)
        else if (strcmp(command, "test") == 0) {
          Serial.println("🧪 진동 테스트 명령 수신!");
          startVibration(1000);
          Serial.println("📳 1초 진동 테스트 시작");
        }

        // "start" 명령 처리
        else if (strcmp(command, "start") == 0 && !isMeasuring) {
          mySerial.println("{\"status\":\"Calibrating for 5 seconds...\"}");
          Serial.println("기준 자세 측정을 시작합니다. 5초간 자세를 유지해주세요.");

          long calibrationStartTime = millis();
          float pitchSum = 0;
          int readingCount = 0;

          while (millis() - calibrationStartTime < 5000) {
            updateVibration(); // 진동이 자동으로 꺼지도록 유지

            mpu.getAcceleration(&ax, &ay, &az);
            float ax_g = (float)ax / ACCEL_SCALE;
            float ay_g = (float)ay / ACCEL_SCALE;
            float az_g = (float)az / ACCEL_SCALE;
            float denom = sqrt(ay_g * ay_g + az_g * az_g);

            if (denom >= 1e-3) {
              pitchSum += atan2(ax_g, denom) * 180.0 / PI;
              readingCount++;
            }
            delay(20); // 짧은 대기 (센서 안정화용)
          }

          if (readingCount > 0) {
            baselinePitch = pitchSum / readingCount;
          }

          Serial.print("기준 자세 설정 완료. Baseline Pitch: ");
          Serial.println(baselinePitch);
          mySerial.println("{\"status\":\"Calibration complete. Starting measurement.\"}");

          // 측정 시작
          isMeasuring = true;
          measurementStartTime = millis();
          lastPrintTime = measurementStartTime;
        }

        // "stop" 명령 처리
        else if (strcmp(command, "stop") == 0 && isMeasuring) {
          isMeasuring = false;
          mySerial.println("{\"status\":\"Measurement stopped\"}");
          Serial.println("측정이 중지되었습니다.");
        }
      }
    } else {
      Serial.print("JSON 파싱 오류: ");
      Serial.println(error.c_str());
    }
  }

  // 2. 측정 상태가 아닐 때 5초마다 'ready' 메시지 전송
  if (!isMeasuring) {
    unsigned long now = millis();
    if (now - lastReadySendTime >= readyInterval) {
      sendReadyMessage();
    }
  }

  // 3. 측정 상태일 때만 1초마다 데이터 전송
  if (isMeasuring) {
    unsigned long now = millis();
    if (now - lastPrintTime >= 1000) {
      mpu.getAcceleration(&ax, &ay, &az);
      float ax_g = (float)ax / ACCEL_SCALE;
      float ay_g = (float)ay / ACCEL_SCALE;
      float az_g = (float)az / ACCEL_SCALE;
      float denom = sqrt(ay_g * ay_g + az_g * az_g);

      if (denom >= 1e-3) {
        float currentPitch = atan2(ax_g, denom) * 180.0 / PI;
        float relativePitch = currentPitch - baselinePitch;

        StaticJsonDocument<128> dataDoc;
        dataDoc["module"] = "IMU";
        JsonArray valueArray = dataDoc.createNestedArray("value");
        valueArray.add(relativePitch);
        dataDoc["timestamp"] = now - measurementStartTime;

        serializeJson(dataDoc, mySerial);
        mySerial.println();
      }
      lastPrintTime = now;
    }
  }
}