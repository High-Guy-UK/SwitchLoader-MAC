// Shim mapping Awoo's custom USB comms onto libnx's stock usbComms, so the
// vendored engine shares the single interface opened in main.cpp. Timeouts are
// ignored (stock usbCommsRead/Write block until the transfer completes).
#pragma once

#include <switch.h>

#ifdef __cplusplus
extern "C" {
#endif

static inline size_t awoo_usbCommsRead(void* buffer, size_t size, u64 timeout) {
    (void)timeout;
    return usbCommsRead(buffer, size);
}

static inline size_t awoo_usbCommsWrite(const void* buffer, size_t size, u64 timeout) {
    (void)timeout;
    return usbCommsWrite(buffer, size);
}

static inline Result awoo_usbCommsInitialize(void) { return 0; }
static inline void awoo_usbCommsExit(void) {}

#ifdef __cplusplus
}
#endif
