/*
 * Stub implementations for application-level callbacks
 *
 * These functions are referenced by the NimBLE stack but are not needed
 * when building as a library. Applications using the library can provide
 * their own implementations if needed.
 */

#include <stdint.h>
#include <stddef.h>

/* Global variable referenced by NimBLE porting layer */
int lib_ble_reduce_mem = 0;

/* CLI command handler stub - not used in library mode */
__attribute__((weak))
void cli_set_event(const char *cmd_line, int len)
{
    /* Stub - applications can override this if they need CLI support */
    (void)cmd_line;
    (void)len;
}

/* BLE startup indication stub - not used in library mode */
__attribute__((weak))
void ble_startup_indication(const void *data)
{
    /* Stub - applications can override this if they need startup notifications */
    (void)data;
}