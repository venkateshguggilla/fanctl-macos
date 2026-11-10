#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

// Layout expected by the AppleSMC kernel user client (selector 2).
typedef struct { char major, minor, build, reserved; uint16_t release; } SMCVers;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, mem; } SMCPLimit;
typedef struct { uint32_t dataSize, dataType; uint8_t attr; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVers vers;
    SMCPLimit plimit;
    SMCKeyInfo info;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

_Static_assert(sizeof(SMCParam) == 80, "SMCParam must be 80 bytes");

enum { kSMCHandleYPCEvent = 2, kSMCReadKey = 5, kSMCWriteKey = 6, kSMCGetKeyFromIndex = 8, kSMCGetKeyInfo = 9 };

static io_connect_t conn;

static uint32_t fourcc(const char *k) {
    return ((uint32_t)(uint8_t)k[0] << 24) | ((uint32_t)(uint8_t)k[1] << 16) |
           ((uint32_t)(uint8_t)k[2] << 8) | (uint32_t)(uint8_t)k[3];
}

static int call(SMCParam *in, SMCParam *out) {
    size_t size = sizeof(*out);
    kern_return_t kr = IOConnectCallStructMethod(conn, kSMCHandleYPCEvent, in, sizeof(*in), out, &size);
    if (kr != KERN_SUCCESS) return kr;
    if (out->result) return 0x1000 | out->result;
    return 0;
}

int smc_open(void) {
    if (conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return kr;
}

void smc_close(void) {
    if (conn) IOServiceClose(conn);
    conn = 0;
}

int smc_key_info(const char *key, smc_keyinfo *info) {
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.data8 = kSMCGetKeyInfo;
    int r = call(&in, &out);
    if (r) return r;
    info->size = out.info.dataSize;
    info->type = out.info.dataType;
    info->attr = out.info.attr;
    return 0;
}

int smc_read(const char *key, smc_keyinfo *info, uint8_t *out32) {
    int r = smc_key_info(key, info);
    if (r) return r;
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.info.dataSize = info->size;
    in.data8 = kSMCReadKey;
    r = call(&in, &out);
    if (r) return r;
    memcpy(out32, out.bytes, sizeof(out.bytes));
    return 0;
}

int smc_write(const char *key, const uint8_t *data, uint32_t len) {
    smc_keyinfo info;
    int r = smc_key_info(key, &info);
    if (r) return r;
    if (info.size != len || len > 32) return -2;
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.info.dataSize = len;
    in.data8 = kSMCWriteKey;
    memcpy(in.bytes, data, len);
    return call(&in, &out);
}

int smc_key_at(uint32_t index, char *out5) {
    SMCParam in = {0}, out = {0};
    in.data8 = kSMCGetKeyFromIndex;
    in.data32 = index;
    int r = call(&in, &out);
    if (r) return r;
    for (int i = 0; i < 4; i++) out5[i] = (char)(out.key >> (24 - 8 * i));
    out5[4] = 0;
    return 0;
}
