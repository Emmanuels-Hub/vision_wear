/*
 * Vision Wear - ESP32-CAM Firmware
 * Version 3.0.0 (production)
 *
 * Hardware: AI-Thinker ESP32-CAM module
 *
 * WHAT CHANGED vs 2.0.0 (and why)
 *   - WIFI_AP_STA dual mode: the board serves its own AP *and* joins your
 *     home WiFi / phone hotspot at the same time. The phone can therefore stay
 *     on a network that has internet while still reaching the camera.
 *   - WiFi power-save disabled. Modem sleep was adding 100-200 ms of jitter to
 *     every HTTP response.
 *   - Three separate HTTP server instances. esp_http_server processes requests
 *     one at a time per instance, so a blocking MJPEG stream or a long-polled
 *     event request used to starve every other endpoint.
 *   - Sockets: LRU purge enabled + larger socket pool + recv/send timeouts.
 *     The old config ran out of sockets after a few minutes of one-shot HTTP
 *     requests and simply stopped accepting connections. That is the
 *     "ESP32 disconnects" symptom.
 *   - /events supports long-poll (?wait=ms) so a button press reaches the phone
 *     in ~10 ms instead of up to one poll interval.
 *   - UDP discovery beacon so the app finds the board automatically on any
 *     network, with no IP address typing.
 *   - Non-blocking LED, bounded JSON building, camera/WiFi auto-recovery.
 *
 * Button wiring (one side to GPIO, other side to GND):
 *   Button 1 (GPIO 13) -> Mode Button
 *                         short press = cycle Object Detection -> OCR -> Navigation
 *                         long  press = re-announce the current mode
 *   Button 2 (GPIO 14) -> Action Button
 *                         short press = run the action for the current mode
 *                         long  press = start/stop vision
 *
 * HTTP API
 *   port 80  GET  /            info page
 *            GET  /capture     single JPEG frame
 *            GET  /status      JSON device + network status
 *            GET  /health      minimal liveness probe (cheap, no camera touch)
 *            GET  /mode?set=N  set mode 0..2 from the app (keeps both in sync)
 *            GET  /wifi?ssid=..&pass=..   provision station credentials (NVS)
 *            GET  /wifi/clear  forget station credentials
 *   port 81  GET  /stream      MJPEG multipart stream
 *   port 82  GET  /events?wait=25000   button events, long-poll
 *
 * UDP discovery
 *   Broadcasts a JSON beacon to the AP and station subnets on port 4210
 *   every 1.5 s.
 *
 * Flash with Arduino IDE:
 *   Board:     "AI Thinker ESP32-CAM"
 *   Partition: "Huge APP (3MB No OTA)"
 *   PSRAM:     Enabled
 */

#include "esp_camera.h"
#include <WiFi.h>
#include <WiFiUdp.h>
#include <Preferences.h>
#include <esp_wifi.h>
#include "esp_http_server.h"
#include "esp_timer.h"

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
// Connect each button between the GPIO pin and GND (uses the internal pull-up).
#define BTN_MODE_PIN      13   // Button 1: cycle modes
#define BTN_ACTION_PIN    14   // Button 2: mode-specific action
#define FLASH_LED_PIN      4   // On-board flash LED (active LOW)

// ============ TIMING ============
#define DEBOUNCE_MS            40    // contact settle time
#define LONG_PRESS_MS        1200    // hold threshold for the secondary action
#define MAX_EVENTS             12
#define BEACON_INTERVAL_MS   1500
#define WIFI_RETRY_MS       15000
#define CAM_FAIL_LIMIT         12    // consecutive grab failures before re-init

// ============ NETWORK CONFIG ============
const char* AP_SSID       = "VisionWear-CAM";
const char* AP_PASSWORD   = "visionwear";   // must be >= 8 chars
const uint8_t AP_CHANNEL  = 1;
const uint8_t AP_MAX_CONN = 4;

const uint16_t PORT_CONTROL = 80;
const uint16_t PORT_STREAM  = 81;
const uint16_t PORT_EVENTS  = 82;
const uint16_t PORT_BEACON  = 4210;

const char* FW_VERSION = "3.0.0";

// ============ MODE DEFINITIONS ============
enum AppMode {
  MODE_OBJECT_DETECTION = 0,
  MODE_OCR              = 1,
  MODE_NAVIGATION       = 2,
  MODE_COUNT            = 3
};

volatile AppMode currentMode = MODE_OBJECT_DETECTION;

const char* modeNames[] = { "object_detection", "ocr", "navigation" };
const char* modeVoiceFeedback[] = { "Object Detection Mode", "OCR Mode", "Navigation Mode" };

// ============ GLOBAL STATE ============
httpd_handle_t control_httpd = NULL;
httpd_handle_t stream_httpd  = NULL;
httpd_handle_t events_httpd  = NULL;

Preferences prefs;
WiFiUDP beaconUdp;

String staSsid;
String staPass;

volatile bool     cameraReady   = false;
volatile uint32_t camFailStreak = 0;
volatile uint32_t framesServed  = 0;
volatile uint32_t streamClients = 0;

unsigned long lastBeaconMs  = 0;
unsigned long lastWifiTryMs = 0;
unsigned long ledOffAtMs    = 0;
bool          ledOn         = false;

portMUX_TYPE eventMux = portMUX_INITIALIZER_UNLOCKED;

// ============ BUTTON EVENT QUEUE ============
// The strings are string literals with static lifetime, so storing the pointer
// is safe and keeps the critical sections short.
struct ButtonEvent {
  uint32_t    id;
  const char* action;
  const char* mode;
  const char* voiceFeedback;
  uint32_t    timestamp;
};

ButtonEvent eventQueue[MAX_EVENTS];
volatile uint8_t eventCount = 0;
uint32_t nextEventId = 1;

struct ButtonConfig {
  uint8_t       pin;
  const char*   label;
  bool          stableLevel;    // debounced level (HIGH = released)
  bool          lastReading;
  unsigned long lastChangeMs;
  unsigned long pressedAtMs;
  bool          longFired;
};

ButtonConfig buttons[] = {
  { BTN_MODE_PIN,   "mode_button",   HIGH, HIGH, 0, 0, false },
  { BTN_ACTION_PIN, "action_button", HIGH, HIGH, 0, 0, false },
};

const size_t BUTTON_COUNT = sizeof(buttons) / sizeof(buttons[0]);

// ============ SMALL HELPERS ============

// Escapes the characters that would break a JSON string literal. Everything we
// emit is ASCII, so a byte-wise pass is sufficient.
static void appendJsonEscaped(String& out, const String& in) {
  for (size_t i = 0; i < in.length(); i++) {
    char c = in[i];
    switch (c) {
      case '"':  out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n";  break;
      case '\r': out += "\\r";  break;
      case '\t': out += "\\t";  break;
      default:
        if ((uint8_t)c < 0x20) {
          char buf[8];
          snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out += c;
        }
    }
  }
}

static void setCorsHeaders(httpd_req_t* req) {
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Headers", "*");
}

// Non-blocking flash. The old flashLed() sat in delay() inside loop(), which
// stalled button scanning and the beacon for up to 100 ms per press.
static void blinkLed(uint16_t durationMs) {
  digitalWrite(FLASH_LED_PIN, LOW);   // active LOW
  ledOn = true;
  ledOffAtMs = millis() + durationMs;
}

static void serviceLed() {
  if (ledOn && (long)(millis() - ledOffAtMs) >= 0) {
    digitalWrite(FLASH_LED_PIN, HIGH);
    ledOn = false;
  }
}

// ============ CAMERA ============
bool initCamera() {
  camera_config_t config = {};            // zero-init: the old code left
  config.ledc_channel = LEDC_CHANNEL_0;   // unset fields as stack garbage
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
  config.pixel_format = PIXFORMAT_JPEG;
  config.grab_mode    = CAMERA_GRAB_LATEST;   // always hand out the newest frame

  if (psramFound()) {
    config.frame_size   = FRAMESIZE_VGA;      // 640x480, matches the app's model input
    config.jpeg_quality = 12;
    config.fb_count     = 2;
    config.fb_location  = CAMERA_FB_IN_PSRAM;
  } else {
    // Without PSRAM a double-buffered VGA frame will not fit. Degrade instead
    // of failing to boot.
    config.frame_size   = FRAMESIZE_QVGA;
    config.jpeg_quality = 15;
    config.fb_count     = 1;
    config.fb_location  = CAMERA_FB_IN_DRAM;
    Serial.println("WARNING: no PSRAM detected, falling back to QVGA / 1 buffer.");
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed: 0x%x\n", err);
    cameraReady = false;
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
    // Wearable enclosures often mount the sensor upside down. Flip here rather
    // than rotating on the phone, which would cost a full frame copy.
    s->set_vflip(s, 0);
    s->set_hmirror(s, 0);
  }

  cameraReady   = true;
  camFailStreak = 0;
  return true;
}

// Recovers from the sensor wedging (brownout, ribbon glitch) without needing a
// physical reset.
static void recoverCamera() {
  Serial.println("Camera unresponsive, re-initialising...");
  esp_camera_deinit();
  delay(120);
  if (initCamera()) {
    Serial.println("Camera recovered.");
  } else {
    Serial.println("Camera recovery FAILED, will retry.");
  }
}

static camera_fb_t* grabFrame() {
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    camFailStreak++;
    return NULL;
  }
  camFailStreak = 0;
  framesServed++;
  return fb;
}

// ============ BUTTONS ============
void initButtons() {
  pinMode(FLASH_LED_PIN, OUTPUT);
  digitalWrite(FLASH_LED_PIN, HIGH);  // LED off (active LOW)

  for (size_t i = 0; i < BUTTON_COUNT; i++) {
    pinMode(buttons[i].pin, INPUT_PULLUP);
    buttons[i].stableLevel  = HIGH;
    buttons[i].lastReading  = HIGH;
    buttons[i].lastChangeMs = 0;
    buttons[i].pressedAtMs  = 0;
    buttons[i].longFired    = false;
  }
}

void queueEvent(const char* action, const char* mode, const char* voiceFeedback) {
  uint32_t assignedId;

  portENTER_CRITICAL(&eventMux);
  if (eventCount >= MAX_EVENTS) {
    // Drop the oldest rather than the newest: a stale press matters less than
    // the one the user just made.
    for (uint8_t i = 1; i < MAX_EVENTS; i++) {
      eventQueue[i - 1] = eventQueue[i];
    }
    eventCount = MAX_EVENTS - 1;
  }
  assignedId = nextEventId++;
  eventQueue[eventCount].id            = assignedId;
  eventQueue[eventCount].action        = action;
  eventQueue[eventCount].mode          = mode;
  eventQueue[eventCount].voiceFeedback = voiceFeedback;
  eventQueue[eventCount].timestamp     = millis();
  eventCount++;
  portEXIT_CRITICAL(&eventMux);

  Serial.printf("Event queued: %s (mode=%s, id=%u)\n", action, mode, assignedId);
}

static void fireModeAction() {
  const char* action   = NULL;
  const char* feedback = NULL;
  AppMode m = currentMode;

  switch (m) {
    case MODE_OBJECT_DETECTION:
      action   = "object_detection_request";
      feedback = "Analyzing objects in front of you";
      break;
    case MODE_OCR:
      action   = "ocr_request";
      feedback = "Capturing and reading text";
      break;
    case MODE_NAVIGATION:
      action   = "navigation_request";
      feedback = "Navigation mode";
      break;
    default:
      return;
  }

  queueEvent(action, modeNames[m], feedback);
  blinkLed(80);
}

static void cycleMode() {
  currentMode = (AppMode)((currentMode + 1) % MODE_COUNT);
  queueEvent("mode_changed", modeNames[currentMode], modeVoiceFeedback[currentMode]);
  blinkLed(150);
  Serial.printf("Mode changed to: %s\n", modeNames[currentMode]);
}

void checkButtons() {
  unsigned long now = millis();

  for (size_t i = 0; i < BUTTON_COUNT; i++) {
    ButtonConfig& b = buttons[i];
    bool reading = digitalRead(b.pin);

    // Restart the debounce window whenever the raw level moves.
    if (reading != b.lastReading) {
      b.lastReading  = reading;
      b.lastChangeMs = now;
      continue;
    }

    if ((now - b.lastChangeMs) < DEBOUNCE_MS) continue;

    if (reading == b.stableLevel) {
      // Settled and unchanged. Check for a hold that has crossed the long-press
      // threshold while the button is still down.
      if (b.stableLevel == LOW && !b.longFired &&
          (now - b.pressedAtMs) >= LONG_PRESS_MS) {
        b.longFired = true;
        if (b.pin == BTN_MODE_PIN) {
          queueEvent("mode_announce", modeNames[currentMode],
                     modeVoiceFeedback[currentMode]);
        } else {
          queueEvent("toggle_vision", modeNames[currentMode], "Toggling vision");
        }
        blinkLed(300);
      }
      continue;
    }

    // Debounced edge.
    b.stableLevel = reading;

    if (reading == LOW) {
      b.pressedAtMs = now;
      b.longFired   = false;
    } else if (!b.longFired) {
      // Release, and the long press did not already fire for this hold.
      if (b.pin == BTN_MODE_PIN) {
        cycleMode();
      } else {
        fireModeAction();
      }
    }
  }
}

// ============ HTTP HANDLERS ============

static esp_err_t capture_handler(httpd_req_t* req) {
  if (!cameraReady) {
    httpd_resp_send_err(req, HTTPD_503_SERVICE_UNAVAILABLE, "camera not ready");
    return ESP_FAIL;
  }

  int64_t start = esp_timer_get_time();
  camera_fb_t* fb = grabFrame();
  if (!fb) {
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "frame grab failed");
    return ESP_FAIL;
  }

  httpd_resp_set_type(req, "image/jpeg");
  setCorsHeaders(req);
  httpd_resp_set_hdr(req, "Cache-Control", "no-store, no-cache, must-revalidate");

  char tsBuf[24];
  snprintf(tsBuf, sizeof(tsBuf), "%u", (unsigned)millis());
  httpd_resp_set_hdr(req, "X-Timestamp", tsBuf);

  char usBuf[24];
  snprintf(usBuf, sizeof(usBuf), "%lld", (long long)(esp_timer_get_time() - start));
  httpd_resp_set_hdr(req, "X-Capture-Us", usBuf);

  esp_err_t res = httpd_resp_send(req, (const char*)fb->buf, fb->len);
  esp_camera_fb_return(fb);
  return res;
}

static const char* STREAM_CONTENT_TYPE = "multipart/x-mixed-replace;boundary=visionwearframe";
static const char* STREAM_BOUNDARY     = "\r\n--visionwearframe\r\n";
static const char* STREAM_PART_FMT     = "Content-Type: image/jpeg\r\nContent-Length: %u\r\nX-Timestamp: %u\r\n\r\n";

static esp_err_t stream_handler(httpd_req_t* req) {
  esp_err_t res = httpd_resp_set_type(req, STREAM_CONTENT_TYPE);
  if (res != ESP_OK) return res;

  setCorsHeaders(req);
  httpd_resp_set_hdr(req, "Cache-Control", "no-store, no-cache, must-revalidate");
  httpd_resp_set_hdr(req, "X-Framerate", "30");

  streamClients++;
  Serial.printf("Stream client connected (%u active)\n", (unsigned)streamClients);

  char partBuf[128];

  while (true) {
    if (!cameraReady) {
      vTaskDelay(pdMS_TO_TICKS(200));
      continue;
    }

    camera_fb_t* fb = grabFrame();
    if (!fb) {
      // A transient grab failure should not tear down the client's connection.
      if (camFailStreak >= CAM_FAIL_LIMIT) {
        res = ESP_FAIL;
        break;
      }
      vTaskDelay(pdMS_TO_TICKS(20));
      continue;
    }

    res = httpd_resp_send_chunk(req, STREAM_BOUNDARY, strlen(STREAM_BOUNDARY));
    if (res == ESP_OK) {
      size_t hlen = snprintf(partBuf, sizeof(partBuf), STREAM_PART_FMT,
                             (unsigned)fb->len, (unsigned)millis());
      res = httpd_resp_send_chunk(req, partBuf, hlen);
    }
    if (res == ESP_OK) {
      res = httpd_resp_send_chunk(req, (const char*)fb->buf, fb->len);
    }

    esp_camera_fb_return(fb);

    if (res != ESP_OK) break;   // client went away

    // Yield so the idle task and the WiFi stack get scheduled. Without this the
    // stream task can starve the rest of the system.
    vTaskDelay(pdMS_TO_TICKS(5));
  }

  if (streamClients > 0) streamClients--;
  Serial.printf("Stream client disconnected (%u active)\n", (unsigned)streamClients);
  return res;
}

static esp_err_t health_handler(httpd_req_t* req) {
  // Deliberately does not touch the camera: the app uses this as a cheap
  // liveness probe on a short timeout.
  httpd_resp_set_type(req, "application/json");
  setCorsHeaders(req);
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
  const char* body = "{\"ok\":true}";
  return httpd_resp_send(req, body, strlen(body));
}

static esp_err_t status_handler(httpd_req_t* req) {
  bool staUp = (WiFi.status() == WL_CONNECTED);

  String json = "{";
  json += "\"status\":\"ok\",";
  json += "\"device\":\"VisionWear-CAM\",";
  json += "\"version\":\"" + String(FW_VERSION) + "\",";
  json += "\"current_mode\":\"" + String(modeNames[currentMode]) + "\",";
  json += "\"mode_index\":" + String((int)currentMode) + ",";
  json += "\"available_modes\":[\"object_detection\",\"ocr\",\"navigation\"],";
  json += "\"buttons\":{\"button1\":\"mode_button\",\"button2\":\"action_button\"},";
  json += "\"camera_ready\":" + String(cameraReady ? "true" : "false") + ",";
  json += "\"frames_served\":" + String((unsigned)framesServed) + ",";
  json += "\"stream_clients\":" + String((unsigned)streamClients) + ",";
  json += "\"uptime_ms\":" + String((unsigned)millis()) + ",";
  json += "\"free_heap\":" + String((unsigned)ESP.getFreeHeap()) + ",";
  json += "\"psram\":" + String(psramFound() ? "true" : "false") + ",";
  json += "\"stream_port\":" + String(PORT_STREAM) + ",";
  json += "\"events_port\":" + String(PORT_EVENTS) + ",";

  json += "\"ap\":{\"ssid\":\"";
  appendJsonEscaped(json, String(AP_SSID));
  json += "\",\"ip\":\"" + WiFi.softAPIP().toString() + "\",";
  json += "\"clients\":" + String(WiFi.softAPgetStationNum()) + "},";

  json += "\"sta\":{\"configured\":" + String(staSsid.length() ? "true" : "false") + ",";
  json += "\"connected\":" + String(staUp ? "true" : "false") + ",";
  json += "\"ssid\":\"";
  appendJsonEscaped(json, staSsid);
  json += "\",\"ip\":\"" + (staUp ? WiFi.localIP().toString() : String("")) + "\",";
  json += "\"rssi\":" + String(staUp ? WiFi.RSSI() : 0) + "}";

  json += "}";

  httpd_resp_set_type(req, "application/json");
  setCorsHeaders(req);
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
  return httpd_resp_send(req, json.c_str(), json.length());
}

// Long-pollable event endpoint.
//   /events            -> return immediately with whatever is queued
//   /events?wait=25000 -> block up to 25 s until at least one event exists
// Long-poll is what removes button latency: the response is already in flight
// the moment the press is debounced.
static esp_err_t events_handler(httpd_req_t* req) {
  uint32_t waitMs = 0;

  size_t qlen = httpd_req_get_url_query_len(req) + 1;
  if (qlen > 1 && qlen < 128) {
    char query[128];
    if (httpd_req_get_url_query_str(req, query, qlen) == ESP_OK) {
      char value[16];
      if (httpd_query_key_value(query, "wait", value, sizeof(value)) == ESP_OK) {
        waitMs = (uint32_t)strtoul(value, NULL, 10);
        if (waitMs > 30000) waitMs = 30000;   // stay under typical client timeouts
      }
    }
  }

  unsigned long deadline = millis() + waitMs;
  while (waitMs > 0) {
    bool hasEvents;
    portENTER_CRITICAL(&eventMux);
    hasEvents = (eventCount > 0);
    portEXIT_CRITICAL(&eventMux);
    if (hasEvents) break;
    if ((long)(millis() - deadline) >= 0) break;
    vTaskDelay(pdMS_TO_TICKS(10));
  }

  // Copy out under lock, then build the JSON outside it. The old version ran
  // snprintf inside the critical section and could overflow its buffer once
  // `offset` passed sizeof(json), because `sizeof(json) - offset` wraps around
  // as an unsigned value.
  ButtonEvent snapshot[MAX_EVENTS];
  uint8_t count;

  portENTER_CRITICAL(&eventMux);
  count = eventCount;
  for (uint8_t i = 0; i < count; i++) snapshot[i] = eventQueue[i];
  eventCount = 0;
  portEXIT_CRITICAL(&eventMux);

  String json = "{\"device_mode\":\"" + String(modeNames[currentMode]) + "\",\"events\":[";
  for (uint8_t i = 0; i < count; i++) {
    if (i > 0) json += ",";
    json += "{\"id\":" + String((unsigned)snapshot[i].id);
    json += ",\"action\":\"";
    appendJsonEscaped(json, String(snapshot[i].action ? snapshot[i].action : ""));
    json += "\",\"mode\":\"";
    appendJsonEscaped(json, String(snapshot[i].mode ? snapshot[i].mode : ""));
    json += "\",\"voice_feedback\":\"";
    appendJsonEscaped(json, String(snapshot[i].voiceFeedback ? snapshot[i].voiceFeedback : ""));
    json += "\",\"timestamp\":" + String((unsigned)snapshot[i].timestamp);
    json += "}";
  }
  json += "]}";

  httpd_resp_set_type(req, "application/json");
  setCorsHeaders(req);
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
  return httpd_resp_send(req, json.c_str(), json.length());
}

// Lets the app drive the mode too, so the phone UI and the physical button can
// never drift out of sync.
static esp_err_t mode_handler(httpd_req_t* req) {
  size_t qlen = httpd_req_get_url_query_len(req) + 1;
  if (qlen > 1 && qlen < 128) {
    char query[128];
    if (httpd_req_get_url_query_str(req, query, qlen) == ESP_OK) {
      char value[16];
      if (httpd_query_key_value(query, "set", value, sizeof(value)) == ESP_OK) {
        int requested = atoi(value);
        if (requested >= 0 && requested < MODE_COUNT) {
          currentMode = (AppMode)requested;
          queueEvent("mode_changed", modeNames[currentMode],
                     modeVoiceFeedback[currentMode]);
          blinkLed(120);
        }
      }
    }
  }
  return status_handler(req);
}

// Station provisioning. Credentials live in NVS so the board rejoins the
// network on its own after a power cycle.
static esp_err_t wifi_handler(httpd_req_t* req) {
  char ssid[64] = {0};
  char pass[64] = {0};

  size_t qlen = httpd_req_get_url_query_len(req) + 1;
  if (qlen > 1 && qlen < 256) {
    char query[256];
    if (httpd_req_get_url_query_str(req, query, qlen) == ESP_OK) {
      httpd_query_key_value(query, "ssid", ssid, sizeof(ssid));
      httpd_query_key_value(query, "pass", pass, sizeof(pass));
    }
  }

  httpd_resp_set_type(req, "application/json");
  setCorsHeaders(req);

  if (strlen(ssid) == 0) {
    const char* err = "{\"ok\":false,\"error\":\"ssid required\"}";
    return httpd_resp_send(req, err, strlen(err));
  }

  staSsid = String(ssid);
  staPass = String(pass);

  prefs.begin("visionwear", false);
  prefs.putString("sta_ssid", staSsid);
  prefs.putString("sta_pass", staPass);
  prefs.end();

  Serial.printf("Station credentials saved for SSID '%s', connecting...\n", ssid);
  WiFi.begin(staSsid.c_str(), staPass.c_str());
  lastWifiTryMs = millis();

  const char* ok = "{\"ok\":true,\"message\":\"credentials saved, connecting\"}";
  return httpd_resp_send(req, ok, strlen(ok));
}

static esp_err_t wifi_clear_handler(httpd_req_t* req) {
  staSsid = "";
  staPass = "";
  prefs.begin("visionwear", false);
  prefs.remove("sta_ssid");
  prefs.remove("sta_pass");
  prefs.end();
  WiFi.disconnect(false, true);

  httpd_resp_set_type(req, "application/json");
  setCorsHeaders(req);
  const char* ok = "{\"ok\":true,\"message\":\"station credentials cleared\"}";
  return httpd_resp_send(req, ok, strlen(ok));
}

static esp_err_t index_handler(httpd_req_t* req) {
  String staLine = (WiFi.status() == WL_CONNECTED)
      ? ("Joined <b>" + staSsid + "</b> as <b>" + WiFi.localIP().toString() + "</b>")
      : (staSsid.length() ? ("Configured for <b>" + staSsid + "</b> (not connected)")
                          : String("No home network configured"));

  String html =
    "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<title>Vision Wear CAM</title></head>"
    "<body style='font-family:sans-serif;max-width:640px;margin:0 auto;padding:24px'>"
    "<h1>Vision Wear ESP32-CAM</h1>"
    "<p>Firmware " + String(FW_VERSION) + "</p>"
    "<h3>Network</h3>"
    "<p>Access point <b>" + String(AP_SSID) + "</b> at <b>" + WiFi.softAPIP().toString() + "</b><br>"
    + staLine + "</p>"
    "<h3>Buttons</h3><ul>"
    "<li><b>GPIO 13 &mdash; Mode</b>: tap to cycle Object Detection &rarr; OCR &rarr; Navigation, hold to re-announce</li>"
    "<li><b>GPIO 14 &mdash; Action</b>: tap to run the current mode's action, hold to start/stop vision</li>"
    "</ul>"
    "<h3>Endpoints</h3><ul>"
    "<li><a href='/capture'>/capture</a> &mdash; single JPEG</li>"
    "<li>:81/stream &mdash; MJPEG stream</li>"
    "<li>:82/events &mdash; button events (add <code>?wait=25000</code> to long-poll)</li>"
    "<li><a href='/status'>/status</a> &mdash; device status</li>"
    "<li><code>/wifi?ssid=YOURWIFI&amp;pass=YOURPASS</code> &mdash; join a network so the phone keeps internet</li>"
    "</ul></body></html>";

  httpd_resp_set_type(req, "text/html");
  setCorsHeaders(req);
  return httpd_resp_send(req, html.c_str(), html.length());
}

// ============ SERVERS ============
// Three instances, because esp_http_server serves requests sequentially within
// an instance. Keeping /stream and the long-polled /events on their own
// instances means neither can block /capture or /status.
static httpd_config_t baseConfig(uint16_t port, uint16_t sockets, uint16_t stack) {
  httpd_config_t config      = HTTPD_DEFAULT_CONFIG();
  config.server_port         = port;
  config.ctrl_port           = 32768 + port;   // must be unique per instance
  config.max_uri_handlers    = 12;
  config.max_open_sockets    = sockets;
  config.stack_size          = stack;
  config.lru_purge_enable    = true;   // reclaim the oldest socket instead of
                                       // refusing new connections once full
  config.recv_wait_timeout   = 10;
  config.send_wait_timeout   = 10;
  config.keep_alive_enable   = true;   // reuse the TCP connection across frames
  config.keep_alive_idle     = 5;
  config.keep_alive_interval = 5;
  config.keep_alive_count    = 3;
  return config;
}

static void registerUri(httpd_handle_t server, const char* uri,
                        esp_err_t (*handler)(httpd_req_t*)) {
  httpd_uri_t def = {};
  def.uri      = uri;
  def.method   = HTTP_GET;
  def.handler  = handler;
  def.user_ctx = NULL;
  httpd_register_uri_handler(server, &def);
}

void startServers() {
  httpd_config_t controlCfg = baseConfig(PORT_CONTROL, 7, 8192);
  if (httpd_start(&control_httpd, &controlCfg) == ESP_OK) {
    registerUri(control_httpd, "/",           index_handler);
    registerUri(control_httpd, "/capture",    capture_handler);
    registerUri(control_httpd, "/status",     status_handler);
    registerUri(control_httpd, "/health",     health_handler);
    registerUri(control_httpd, "/mode",       mode_handler);
    registerUri(control_httpd, "/wifi",       wifi_handler);
    registerUri(control_httpd, "/wifi/clear", wifi_clear_handler);
    Serial.printf("Control server on port %u\n", PORT_CONTROL);
  } else {
    Serial.println("ERROR: control server failed to start");
  }

  // The stream handler blocks for the lifetime of the client, so this instance
  // only needs a couple of sockets but a roomier stack.
  httpd_config_t streamCfg = baseConfig(PORT_STREAM, 3, 8192);
  if (httpd_start(&stream_httpd, &streamCfg) == ESP_OK) {
    registerUri(stream_httpd, "/stream", stream_handler);
    Serial.printf("Stream server on port %u\n", PORT_STREAM);
  } else {
    Serial.println("ERROR: stream server failed to start");
  }

  httpd_config_t eventsCfg = baseConfig(PORT_EVENTS, 4, 6144);
  if (httpd_start(&events_httpd, &eventsCfg) == ESP_OK) {
    registerUri(events_httpd, "/events", events_handler);
    Serial.printf("Events server on port %u\n", PORT_EVENTS);
  } else {
    Serial.println("ERROR: events server failed to start");
  }
}

// ============ WIFI ============
void setupWifi() {
  prefs.begin("visionwear", true);
  staSsid = prefs.getString("sta_ssid", "");
  staPass = prefs.getString("sta_pass", "");
  prefs.end();

  WiFi.persistent(false);
  WiFi.mode(WIFI_AP_STA);          // serve our own AP *and* join a network
  WiFi.setSleep(false);            // the single biggest latency fix: modem
                                   // sleep was adding 100-200 ms per response
  WiFi.setAutoReconnect(true);

  WiFi.softAP(AP_SSID, AP_PASSWORD, AP_CHANNEL, 0, AP_MAX_CONN);
  delay(100);
  Serial.printf("AP '%s' up at %s\n", AP_SSID, WiFi.softAPIP().toString().c_str());

  if (staSsid.length() > 0) {
    Serial.printf("Joining saved network '%s'...\n", staSsid.c_str());
    WiFi.begin(staSsid.c_str(), staPass.c_str());
    lastWifiTryMs = millis();
  } else {
    Serial.println("No saved home network. The app can send one to /wifi?ssid=..&pass=..");
  }

  // Raise TX power for a more stable link through a jacket pocket.
  esp_wifi_set_max_tx_power(78);

  beaconUdp.begin(PORT_BEACON);
}

// Re-arms the station connection if it drops. softAP keeps serving throughout,
// so the phone never loses the camera while this happens.
static void serviceWifi() {
  if (staSsid.length() == 0) return;
  if (WiFi.status() == WL_CONNECTED) return;

  unsigned long now = millis();
  if ((now - lastWifiTryMs) < WIFI_RETRY_MS) return;

  lastWifiTryMs = now;
  Serial.println("Station link down, retrying...");
  WiFi.disconnect();
  WiFi.begin(staSsid.c_str(), staPass.c_str());
}

// Broadcast presence so the app can discover the board without the user ever
// typing an IP address. Sent on both interfaces.
static void sendBeacon() {
  unsigned long now = millis();
  if ((now - lastBeaconMs) < BEACON_INTERVAL_MS) return;
  lastBeaconMs = now;

  bool staUp = (WiFi.status() == WL_CONNECTED);

  String payload = "{\"device\":\"VisionWear-CAM\"";
  payload += ",\"version\":\"" + String(FW_VERSION) + "\"";
  payload += ",\"ap_ip\":\"" + WiFi.softAPIP().toString() + "\"";
  payload += ",\"sta_ip\":\"" + (staUp ? WiFi.localIP().toString() : String("")) + "\"";
  payload += ",\"control_port\":" + String(PORT_CONTROL);
  payload += ",\"stream_port\":" + String(PORT_STREAM);
  payload += ",\"events_port\":" + String(PORT_EVENTS);
  payload += ",\"mode\":\"" + String(modeNames[currentMode]) + "\"";
  payload += ",\"camera_ready\":" + String(cameraReady ? "true" : "false");
  payload += ",\"uptime_ms\":" + String((unsigned)millis());
  payload += "}";

  // AP subnet broadcast.
  IPAddress apIp = WiFi.softAPIP();
  IPAddress apBroadcast(apIp[0], apIp[1], apIp[2], 255);
  if (beaconUdp.beginPacket(apBroadcast, PORT_BEACON)) {
    beaconUdp.write((const uint8_t*)payload.c_str(), payload.length());
    beaconUdp.endPacket();
  }

  // Station subnet broadcast, so the app finds us when the phone is on the home
  // network / hotspot rather than on our AP.
  if (staUp) {
    IPAddress local = WiFi.localIP();
    IPAddress mask  = WiFi.subnetMask();
    IPAddress staBroadcast(
      (local[0] & mask[0]) | (~mask[0] & 0xFF),
      (local[1] & mask[1]) | (~mask[1] & 0xFF),
      (local[2] & mask[2]) | (~mask[2] & 0xFF),
      (local[3] & mask[3]) | (~mask[3] & 0xFF));
    if (beaconUdp.beginPacket(staBroadcast, PORT_BEACON)) {
      beaconUdp.write((const uint8_t*)payload.c_str(), payload.length());
      beaconUdp.endPacket();
    }
  }
}

// ============ SETUP & LOOP ============
void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(false);
  Serial.printf("\nVision Wear ESP32-CAM %s starting...\n", FW_VERSION);

  initButtons();

  if (!initCamera()) {
    // Do not bail out: without the servers there is no way to diagnose the
    // board remotely. Bring up WiFi anyway and let /status report
    // camera_ready:false.
    Serial.println("Camera init failed at boot. Check the ribbon cable and 5V supply.");
  } else {
    Serial.println("Camera initialized.");
  }

  setupWifi();
  startServers();

  Serial.println("Buttons: GPIO13 = mode (tap cycles, hold announces)");
  Serial.println("         GPIO14 = action (tap runs mode action, hold toggles vision)");
  Serial.printf("Initial mode: %s\n", modeNames[currentMode]);
  Serial.println("Ready.");
}

void loop() {
  checkButtons();
  serviceLed();
  serviceWifi();
  sendBeacon();

  if (cameraReady && camFailStreak >= CAM_FAIL_LIMIT) {
    recoverCamera();
  }

  // 5 ms keeps button latency imperceptible while leaving plenty of CPU for the
  // three HTTP server tasks.
  delay(5);
}
