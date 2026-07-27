/*
 * OS NPL Extensions - Additional functions not in standard NimBLE NPL API
 *
 * These functions are used by the NimBLE host but not declared in the
 * standard NPL headers when CONFIG_LINUX_BLE_STACK_APP is set.
 */

#ifndef _OS_NPL_EXTENSIONS_H_
#define _OS_NPL_EXTENSIONS_H_

#include "nimble/nimble_npl.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Mutex extensions */
ble_npl_error_t ble_npl_mutex_free(struct ble_npl_mutex *mu);

/* Callout extensions */
void ble_npl_callout_free(struct ble_npl_callout *co);

/* Semaphore extensions */
void ble_npl_sem_free(struct ble_npl_sem *sem);

/* Event queue extensions */
void ble_npl_eventq_release(struct ble_npl_eventq *evq);
struct ble_npl_eventq *nimble_port_get_dflt_eventq(void);

/* CLI/Application callbacks (stubs for Improv WiFi mode) */
void ble_startup_indication(const void *data);
void cli_set_event(const char *cmd_line, int len);

#ifdef __cplusplus
}
#endif

#endif /* _OS_NPL_EXTENSIONS_H_ */
