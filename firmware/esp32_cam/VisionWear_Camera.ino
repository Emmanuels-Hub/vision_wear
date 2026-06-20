/*
 * Vision Wear - ESP32-CAM Firmware (Standalone)
 *
 * Hardware: AI-Thinker ESP32-CAM module
 *
 * Features:
 *   - WiFi Access Point for easy phone pairing
 *   - HTTP /capture  — single JPEG frame (used by Vision Wear app)
 *   - HTTP /stream   — MJPEG live stream (port 81)
 *   - HTTP /events   — button press events for the mobile app
 *   - HTTP /status   — device status JSON
 *   - 2 physical push buttons for hands-free control (mode + action)
 *
 * Button wiring (one side to GPIO, other side to GND):
 *   Button 1 (GPIO 13) → Mode Button (cycles: Object Detection → OCR → Navigation)
 *   Button 2 (GPIO 14) → Action Button (performs action based on current mode)
 *
 * Modes:
 *   - Object Detection: Ask "What is in front of me?"
 *   - OCR: Capture and read text
 *   - Navigation: Future mode for navigation assistance
 *
 * Flash with Arduino IDE:
 *   Board:     "AI Thinker ESP32-CAM"
 *   Partition: "Huge APP (3MB No OTA)"
 *   PSRAM:     Enabled
 */

#include "esp_camera.h"
#include <WiFi.h>
#include "esp_http_server.h"

// ============ CAMERA PINS (AI-Thinker ESP32-CAM) ============
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

// ============ BUTTON PINS ============
// Connect each button between the GPIO pin and GND (uses internal pull-up).
#define BTN_MODE_PIN      13   // Button 1: cycle through modes
#define BTN_ACTION_PIN    14   // Button 2: perform mode-specific action
#define FLASH_LED_PIN      4   // On-board flash LED (active LOW)

// ============ MODE DEFINITIONS ============
enum AppMode {
  MODE_OBJECT_DETECTION = 0,
  MODE_OCR = 1,
  MODE_NAVIGATION = 2,
  MODE_COUNT = 3
};

volatile AppMode currentMode = MODE_OBJECT_DETECTION;

const char* modeNames[] = {
  "object_detection",
  "ocr",
  "navigation"
};

const char* modeVoiceFeedback[] = {
  "Object Detection Mode",
  "OCR Mode",
  "Navigation Mode"
};

#define DEBOUNCE_MS      300
#define MAX_EVENTS         8

// ============ WIFI CONFIG ============
const char* AP_SSID     = "VisionWear-CAM";
const char* AP_PASSWORD = "visionwear";
const char* AP_IP       = "192.168.4.1";

httpd_handle_t stream_httpd = NULL;
httpd_handle_t camera_httpd = NULL;

// ============ BUTTON EVENT QUEUE ============
struct ButtonEvent {
  uint32_t id;
  const char* action;
  const char* mode;
  const char* voiceFeedback;
  uint32_t timestamp;
};

ButtonEvent eventQueue[MAX_EVENTS];
volatile uint8_t eventCount = 0;
uint32_t nextEventId = 1;
portMUX_TYPE eventMux = portMUX_INITIALIZER_UNLOCKED;

struct ButtonConfig {
  uint8_t pin;
  const char* label;
  bool lastStable;
  unsigned long lastDebounce;
};

ButtonConfig buttons[] = {
  { BTN_MODE_PIN,   "mode_button",   HIGH, 0 },
  { BTN_ACTION_PIN, "action_button", HIGH, 0 },
};

const size_t BUTTON_COUNT = sizeof(buttons) / sizeof(buttons[0]);

// ============ CAMERA INIT ============
bool initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0       = Y2_GPIO_NUM;
  config.pin_d1       = Y3_GPIO_NUM;
  config.pin_d2       = Y4_GPIO_NUM;
  config.pin_d3       = Y5_GPIO_NUM;
  config.pin_d4       = Y6_GPIO_NUM;
  config.pin_d5       = Y7_GPIO_NUM;
  config.pin_d6       = Y8_GPIO_NUM;
  config.pin_d7       = Y9_GPIO_NUM;
  config.pin_xclk     = XCLK_GPIO_NUM;
  config.pin_pclk     = PCLK_GPIO_NUM;
  config.pin_vsync    = VSYNC_GPIO_NUM;
  config.pin_href     = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn     = PWDN_GPIO_NUM;
  config.pin_reset    = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.frame_size   = FRAMESIZE_VGA;
  config.pixel_format = PIXFORMAT_JPEG;
  config.grab_mode    = CAMERA_GRAB_LATEST;
  config.fb_location  = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = 12;
  config.fb_count     = 2;

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed: 0x%x\n", err);
    return false;
  }

  sensor_t* s = esp_camera_sensor_get();
  if (s) {
    s->set_brightness(s, 0);
    s->set_contrast(s, 0);
    s->set_saturation(s, 0);
    s->set_whitebal(s, 1);
    s->set_awb_gain(s, 1);
    s->set_exposure_ctrl(s, 1);
    s->set_gain_ctrl(s, 1);
  }

  return true;
}

// ============ BUTTON HELPERS ============
void initButtons() {
  pinMode(FLASH_LED_PIN, OUTPUT);
  digitalWrite(FLASH_LED_PIN, HIGH);  // LED off (active LOW)

  for (size_t i = 0; i < BUTTON_COUNT; i++) {
    pinMode(buttons[i].pin, INPUT_PULLUP);
    buttons[i].lastStable = HIGH;
    buttons[i].lastDebounce = 0;
  }
}

void flashLed(uint16_t durationMs) {
  digitalWrite(FLASH_LED_PIN, LOW);
  delay(durationMs);
  digitalWrite(FLASH_LED_PIN, HIGH);
}

void queueEvent(const char* action, const char* mode, const char* voiceFeedback) {
  portENTER_CRITICAL(&eventMux);
  if (eventCount < MAX_EVENTS) {
    eventQueue[eventCount].id = nextEventId++;
    eventQueue[eventCount].action = action;
    eventQueue[eventCount].mode = mode;
    eventQueue[eventCount].voiceFeedback = voiceFeedback;
    eventQueue[eventCount].timestamp = millis();
    eventCount++;
    Serial.printf("Button event queued: %s (mode=%s, id=%u)\n", action, mode, nextEventId - 1);
  }
  portEXIT_CRITICAL(&eventMux);
}

void checkButtons() {
  unsigned long now = millis();

  for (size_t i = 0; i < BUTTON_COUNT; i++) {
    bool reading = digitalRead(buttons[i].pin);

    if (reading != buttons[i].lastStable) {
      buttons[i].lastDebounce = now;
    }

    if ((now - buttons[i].lastDebounce) > DEBOUNCE_MS) {
      if (reading == LOW && buttons[i].lastStable == HIGH) {
        // Button pressed
        if (buttons[i].pin == BTN_MODE_PIN) {
          // Mode button: cycle to next mode
          currentMode = (AppMode)((currentMode + 1) % MODE_COUNT);
          const char* modeName = modeNames[currentMode];
          const char* modeFeedback = modeVoiceFeedback[currentMode];
          queueEvent("mode_changed", modeName, modeFeedback);
          flashLed(100);  // Longer flash for mode change
          Serial.printf("Mode changed to: %s\n", modeName);
        } else if (buttons[i].pin == BTN_ACTION_PIN) {
          // Action button: perform action based on current mode
          const char* action = NULL;
          const char* modeName = modeNames[currentMode];
          const char* feedback = NULL;

          switch (currentMode) {
            case MODE_OBJECT_DETECTION:
              action = "object_detection_request";
              feedback = "Analyzing objects in front of you";
              break;
            case MODE_OCR:
              action = "ocr_request";
              feedback = "Capturing and reading text";
              break;
            case MODE_NAVIGATION:
              action = "navigation_request";
              feedback = "Navigation mode";
              break;
          }

          if (action) {
            queueEvent(action, modeName, feedback);
            flashLed(80);
            Serial.printf("Action triggered: %s (mode=%s)\n", action, modeName);
          }
        }
      }
      buttons[i].lastStable = reading;
    }
  }
}

// ============ HTTP HANDLERS ============
static esp_err_t capture_handler(httpd_req_t *req) {
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    httpd_resp_send_500(req);
    return ESP_FAIL;
  }

  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Cache-Control", "no-store, no-cache, must-revalidate");
  httpd_resp_set_hdr(req, "X-Timestamp", String(millis()).c_str());

  esp_err_t res = httpd_resp_send(req, (const char*)fb->buf, fb->len);
  esp_camera_fb_return(fb);
  return res;
}

static esp_err_t stream_handler(httpd_req_t *req) {
  camera_fb_t* fb = NULL;
  esp_err_t res = ESP_OK;
  char part_buf[64];

  res = httpd_resp_set_type(req, "_MULTIPART/x-mixed-replace;boundary=frame");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");

  while (true) {
    fb = esp_camera_fb_get();
    if (!fb) {
      res = ESP_FAIL;
      break;
    }

    size_t hlen = snprintf(part_buf, 64,
      "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n",
      fb->len);

    res = httpd_resp_send_chunk(req, part_buf, hlen);
    if (res == ESP_OK) {
      res = httpd_resp_send_chunk(req, (const char*)fb->buf, fb->len);
    }
    if (res == ESP_OK) {
      res = httpd_resp_send_chunk(req, "\r\n", 2);
    }

    esp_camera_fb_return(fb);
    if (res != ESP_OK) break;
  }

  return res;
}

static esp_err_t status_handler(httpd_req_t *req) {
  char json[512];
  const char* currentModeName = modeNames[currentMode];
  
  int len = snprintf(json, sizeof(json),
    "{\"status\":\"ok\",\"device\":\"VisionWear-CAM\",\"version\":\"2.0.0\","
    "\"current_mode\":\"%s\",\"available_modes\":[\"object_detection\",\"ocr\",\"navigation\"],"
    "\"buttons\":{\"button1\":\"mode_button\",\"button2\":\"action_button\"}}",
    currentModeName);
  
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, json, len);
}

static esp_err_t events_handler(httpd_req_t *req) {
  char json[1024];
  int offset = snprintf(json, sizeof(json), "{\"events\":[");

  portENTER_CRITICAL(&eventMux);
  for (uint8_t i = 0; i < eventCount; i++) {
    if (i > 0) {
      offset += snprintf(json + offset, sizeof(json) - offset, ",");
    }
    offset += snprintf(json + offset, sizeof(json) - offset,
      "{\"id\":%u,\"action\":\"%s\",\"mode\":\"%s\",\"voice_feedback\":\"%s\",\"timestamp\":%u}",
      eventQueue[i].id, eventQueue[i].action, eventQueue[i].mode, 
      eventQueue[i].voiceFeedback, eventQueue[i].timestamp);
  }
  eventCount = 0;
  portEXIT_CRITICAL(&eventMux);

  offset += snprintf(json + offset, sizeof(json) - offset, "]}");

  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
  return httpd_resp_send(req, json, offset);
}

static esp_err_t index_handler(httpd_req_t *req) {
  const char* html =
    "<html><head><title>Vision Wear CAM</title></head>"
    "<body style='font-family:sans-serif;text-align:center;padding:40px'>"
    "<h1>Vision Wear ESP32-CAM</h1>"
    "<p>Camera is running. Connect the Vision Wear app.</p>"
    "<p>WiFi: <b>VisionWear-CAM</b> &nbsp; IP: <b>192.168.4.1</b></p>"
    "<h3>Physical Buttons (2-Button Mode Interface)</h3>"
    "<ul style='list-style:none;padding:0'>"
    "<li><b>Button 1 (GPIO 13)</b> — Mode Button: Cycles through Object Detection → OCR → Navigation</li>"
    "<li><b>Button 2 (GPIO 14)</b> — Action Button: Performs action based on current mode</li>"
    "</ul>"
    "<h3>Available Modes</h3>"
    "<ul style='list-style:none;padding:0'>"
    "<li><b>Object Detection:</b> Press Action Button to ask 'What is in front of me?'</li>"
    "<li><b>OCR:</b> Press Action Button to capture and read text</li>"
    "<li><b>Navigation:</b> Press Action Button for navigation assistance (future)</li>"
    "</ul>"
    "<p><a href='/capture'>Capture</a> | "
    "<a href='/stream'>Stream</a> | "
    "<a href='/events'>Events</a> | "
    "<a href='/status'>Status</a></p>"
    "</body></html>";
  httpd_resp_set_type(req, "text/html");
  return httpd_resp_send(req, html, strlen(html));
}

// ============ START CAMERA SERVER ============
void startCameraServer() {
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port = 80;
  config.ctrl_port   = 32768;
  config.max_uri_handlers = 10;

  if (httpd_start(&camera_httpd, &config) == ESP_OK) {
    httpd_uri_t capture_uri = { .uri = "/capture", .method = HTTP_GET, .handler = capture_handler };
    httpd_uri_t status_uri  = { .uri = "/status",  .method = HTTP_GET, .handler = status_handler };
    httpd_uri_t events_uri  = { .uri = "/events",  .method = HTTP_GET, .handler = events_handler };
    httpd_uri_t index_uri   = { .uri = "/",        .method = HTTP_GET, .handler = index_handler };

    httpd_register_uri_handler(camera_httpd, &capture_uri);
    httpd_register_uri_handler(camera_httpd, &status_uri);
    httpd_register_uri_handler(camera_httpd, &events_uri);
    httpd_register_uri_handler(camera_httpd, &index_uri);
  }

  config.server_port += 1;
  config.ctrl_port   += 1;

  if (httpd_start(&stream_httpd, &config) == ESP_OK) {
    httpd_uri_t stream_uri = { .uri = "/stream", .method = HTTP_GET, .handler = stream_handler };
    httpd_register_uri_handler(stream_httpd, &stream_uri);
  }
}

// ============ SETUP & LOOP ============
void setup() {
  Serial.begin(115200);
  Serial.println("\nVision Wear ESP32-CAM starting...");

  initButtons();

  if (!initCamera()) {
    Serial.println("FATAL: Camera init failed. Check wiring.");
    return;
  }
  Serial.println("Camera initialized.");

  WiFi.softAP(AP_SSID, AP_PASSWORD);
  IPAddress IP = WiFi.softAPIP();
  Serial.printf("AP started: %s\n", AP_SSID);
  Serial.printf("Password:   %s\n", AP_PASSWORD);
  Serial.printf("IP address: %s\n", IP.toString().c_str());
  Serial.printf("Capture URL: http://%s/capture\n", AP_IP);
  Serial.printf("Events URL:  http://%s/events\n", AP_IP);
  Serial.println("Buttons: GPIO13=mode_button (cycles modes), GPIO14=action_button");
  Serial.println("Initial mode: Object Detection");

  startCameraServer();
  Serial.println("HTTP server started. Ready for Vision Wear app.");
}

void loop() {
  checkButtons();
  delay(10);
}
