#include "Arduino.h"
#include "uTimerLib.h"

//HardwareSerial mySerial1(1); // UART1 RX=GPIO16, TX=GPIO17

uint8_t RX1PIN = 16;
uint8_t TX1PIN = 17;
uint8_t N_BREAKPIN = 33;
uint8_t BREAK_PULSE = 120;  // UART break pulse = 120mS
uint8_t RESPONSE = 10;       // DS2480B Response time < 10ms
//DS2480B command
uint8_t SIF_RESET   = 0xc1; // Reset 1wire-bus
uint8_t SIF_DATA    = 0xe1; // data mode
uint8_t SIF_COMMAND = 0xe3; // command mode
uint8_t SIF_ACCON   = 0xb1; // search accelerator on
uint8_t SIF_ACCOFF  = 0xa1; // search accelerator off
//DS2480B config data (config command)
uint8_t SIF_PDSRC   = 0x19; // 0 001 100 1 PDSRC (1.1V/us)
uint8_t SIF_W1LT    = 0x41; // 0 100 000 1 W1LT  (8us)
uint8_t SIF_DSO     = 0x51; // 0 101 000 1 DSO/WORT (3us)
uint8_t SIF_RBR9600B  = 0x71; // set Baudrate 9600
uint8_t SIF_RBR19200B = 0x73; // set Baudrate 19200
uint8_t SIF_RBR57600B = 0x75; // set Baudrate 57600
#define ACCEL_WORDS 16
uint8_t acceler_data[ACCEL_WORDS];

//DS18B20 command
uint8_t SCMD_CONV   = 0x44; // temprature conversion start
uint8_t SCMD_RDPAD  = 0xbe; // Read Scratchpad
uint8_t SCMD_WRPAD  = 0x4e; // Write Scratchpad
int     SCPAD_SIZE  = 9;
// 1Wire Rom search comand
uint8_t ROM_SEARCH = 0xf0;
uint8_t ROM_MATCH  = 0x55;
uint8_t ROM_SKIP   = 0xcc;
int     ROMID_SIZE = 8;

int     DS2480BAUD = 9600;

// Timeout
// uTimeLib
// TimerLib.setTimeout_us(callback_function, microseconds);
// タイマ割り込みの設定値はμS単位だがハードウェアの機能としてはms単位の指定となる
// ms単位に丸められる
int     TIMEOUT = 20000000; /* Timeout : 200ms */
void timed_function(){
  Serial.print("Timeout Error\n");
  exit(1);
}

uint8_t crc_table[] = {
       0, 94,188,226, 97, 63,221,131,194,156,126, 32,163,253, 31, 65,
      157,195, 33,127,252,162, 64, 30, 95,  1,227,189, 62, 96,130,220,
       35,125,159,193, 66, 28,254,160,225,191, 93,  3,128,222, 60, 98,
      190,224,  2, 92,223,129, 99, 61,124, 34,192,158, 29, 67,161,255,
       70, 24,250,164, 39,121,155,197,132,218, 56,102,229,187, 89,  7,
      219,133,103, 57,186,228,  6, 88, 25, 71,165,251,120, 38,196,154,
      101, 59,217,135,  4, 90,184,230,167,249, 27, 69,198,152,122, 36,
      248,166, 68, 26,153,199, 37,123, 58,100,134,216, 91,  5,231,185,
      140,210, 48,110,237,179, 81, 15, 78, 16,242,172, 47,113,147,205,
       17, 79,173,243,112, 46,204,146,211,141,111, 49,178,236, 14, 80,
      175,241, 19, 77,206,144,114, 44,109, 51,209,143, 12, 82,176,238,
       50,108,142,208, 83, 13,239,177,240,174, 76, 18,145,207, 45,115,
      202,148,118, 40,171,245, 23, 73,  8, 86,180,234,105, 55,213,139,
       87,  9,235,181, 54,104,138,212,149,203, 41,119,244,170, 72, 22,
      233,183, 85, 11,136,214, 52,106, 43,117,151,201, 74, 20,246,168,
      116, 42,200,150, 21, 75,169,247,182,232, 10, 84,215,137,107, 53
      };

uint8_t MASTER_RESET=0;
uint8_t RESET_WAIT=200; // 10ms

// Model Strings
const char* ModelStrings[] PROGMEM = {"", "ESP32"};

// Add Feature String
void AddFeatureString(String &S, const String F) {
  if (S.length() != 0) S.concat(", ");
  S.concat(F);
}

void setup() {
  int sdata = 0;
  int ix;
  // Get Chip Information
  esp_chip_info_t chip_info;
  esp_chip_info(&chip_info);

  pinMode(N_BREAKPIN,OUTPUT);
  digitalWrite(N_BREAKPIN,HIGH);
  
  Serial.begin(115200);
  while (!Serial);
  Serial2.begin(DS2480BAUD,SERIAL_8N1,RX1PIN,TX1PIN);
  while (!Serial2);
  
  Serial.println("\r\n***** Chip Information *****");

  // Model
  Serial.printf("Model: %s\r\n", ModelStrings[chip_info.model]);

  // Features
  String Features = "";
  if (chip_info.features & CHIP_FEATURE_EMB_FLASH) AddFeatureString(Features, "Embedded Flash");
  if (chip_info.features & CHIP_FEATURE_WIFI_BGN ) AddFeatureString(Features, "Wifi-BGN"      );
  if (chip_info.features & CHIP_FEATURE_BLE      ) AddFeatureString(Features, "BLE"           );
  if (chip_info.features & CHIP_FEATURE_BT       ) AddFeatureString(Features, "Bluetooth"     );
  Serial.println("Features: " + Features);

  // Cores
  Serial.printf("Cores: %d\r\n", chip_info.cores);

  // Revision
  Serial.printf("Revision: %d\r\n", chip_info.revision);

  // MAC Address
  String MACString = "";
  uint64_t chipid = ESP.getEfuseMac(); 
  for (int i=0; i<6; i++) {
    if (i > 0) MACString.concat(":");
    uint8_t Octet = chipid >> (i * 8);
    if (Octet < 16) MACString.concat("0");
    MACString.concat(String(Octet, HEX));
  }
  Serial.println("MAC Address: " + MACString);

  // Flash Size
  uint32_t FlashSize = ESP.getFlashChipSize();
  String ValueString = "";
  do {
    String temp = String(FlashSize);
    if (FlashSize >= 1000) {
      temp = "00" + temp;
      ValueString = "," + temp.substring(temp.length() - 3, temp.length()) + ValueString;
    } else {
      ValueString = temp + ValueString;
    }  
    FlashSize /= 1000;
  } while (FlashSize > 0);
  Serial.println("Flash Size: " + ValueString);
  
  ds2480_master_reset();
  init_ds2480();
}

uint8_t bus_reset(){
  uint8_t read_data;
  read_data = writeread1(SIF_RESET);
  if (read_data <= 0) {
    Serial.println("DS2480B bus Reset fail\r\n");
    exit(1);
  }
  return(read_data);  
}

void ds2480_master_reset() {
  digitalWrite(N_BREAKPIN,LOW);
  delay(BREAK_PULSE);
  digitalWrite(N_BREAKPIN,HIGH);
  delay(10);
}

int writeread1(uint8_t wrdata){
  int out = 0;
  TimerLib.setTimeout_us(timed_function,TIMEOUT); /* 200msタイムアウト設定 */
  out = Serial2.write(wrdata);
  Serial2.flush();
  delay(RESPONSE);
  while(Serial2.available() > 0){
    out = Serial2.read();
    Serial.print("Received: ");
    Serial.println(out,HEX);
  }
  TimerLib.clearTimer(); /* タイムアウトのクリア */
  return(out);
}

int restart_ds2480(){
  //bus_reset();
  //ds2480_master_reset();
  init_ds2480();
  return(1);  
}

int init_ds2480(){
  uint8_t out;
  
  Serial.println("init DS2480B");
  out = bus_reset();
  Serial.print("bus reset result: ");
  Serial.println(out,HEX);
  out = writeread1(SIF_PDSRC);
  Serial.print("PDSRC    ");
  Serial.println(out,BIN);
  out = writeread1(SIF_W1LT);
  Serial.print("W1LT     ");
  Serial.println(out,BIN);
  out = writeread1(SIF_DSO);
  Serial.print("DSO/WORT ");
  Serial.println(out,BIN); 
  return(1);
}

uint8_t write_1wire(uint8_t wdata)
{
  if(wdata == SIF_COMMAND) {　//DS2480Bのコマンドモードへの移行ワード（0xe3)を1-wireへ送る場合は0xe3を2回送る
    Serial1.write(wdata);
  }
  return(Serial1.write(wdata));
}


uint8_t * search_acceler()
{
    uint8_t retc;
    int i;
    
    retc = bus_reset();
    Serial2.write(SIF_DATA);    // data mode -> send 1-wire bus
    write_1wire(ROM_SEARCH);    // 1-w CMD: Search ROM cmd
    Serial2.write(SIF_COMMAND); // command mode
    Serial2.write(SIF_ACCON);   // DS2480B Acceleratator ON
    Serial2.write(SIF_DATA);    // data mode -> read 1-wire bus
    Serial2.flush();
    for (i = 0; i < ACCEL_WORDS; i++) {
      retc = write_1wire(0); //アクセラレータ初期データ
    }
    
}


uint8_t wdata = 0;
void loop() {
  uint8_t out;
  delay(100);
  bus_reset();
}
