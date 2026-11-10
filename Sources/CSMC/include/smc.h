#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>

typedef struct {
    uint32_t size;  // payload length in bytes
    uint32_t type;  // four-char type code, e.g. 'flt '
    uint8_t attr;
} smc_keyinfo;

// All functions return 0 on success, an IOReturn code, or 0x1000|smc_result.
int smc_open(void);
void smc_close(void);
int smc_key_info(const char *key, smc_keyinfo *info);
int smc_read(const char *key, smc_keyinfo *info, uint8_t *out32);
int smc_write(const char *key, const uint8_t *data, uint32_t len);

#endif
