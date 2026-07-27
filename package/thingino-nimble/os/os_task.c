/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

#include <stdlib.h>
#include <pthread.h>
#include <sched.h>

#include "os/os.h"
#include "nimble/nimble_npl.h"

void *
ble_npl_get_current_task_id(void)
{
    return (void *)pthread_self();
}

bool
ble_npl_os_started(void)
{
    return true;
}

void
ble_npl_task_yield(void)
{
    /* Fixed for musl: use sched_yield() instead of pthread_yield() */
    sched_yield();
}

pAtbm_thread_t
atbm_createThread(atbm_int32(*task)(atbm_void* p_arg), atbm_void* p_arg, int prio)
{
    struct ble_npl_task* s_task = malloc(sizeof(struct ble_npl_task));
    int err;

    if (BLE_AT_PRIO == prio)
        prio = 9;
    else
        prio = 1;

    err = ble_npl_task_init(s_task, "s_task[0]",
                            (ble_npl_task_func_t)(void*)task,  /* Cast to correct type */
                            p_arg, 1, 0, NULL, 0);

    if (err) {
        free(s_task);
        return NULL;
    }

    return s_task;
}

int
atbm_stopThread(pAtbm_thread_t thread_id)
{
    ble_npl_task_remove(thread_id);
    free(thread_id);
    return 0;
}

int
atbm_ThreadStopEvent(pAtbm_thread_t thread_id)
{
    (void)thread_id;
    return 0;
}

int
atbm_changeThreadPriority(int prio)
{
    (void)prio;
    return 0;
}

int
atbm_IncThreadPriority(int prio)
{
    (void)prio;
    return 0;
}

int
ble_npl_task_init(struct ble_npl_task *t, const char *name, ble_npl_task_func_t func,
                  void *arg, uint8_t prio, ble_npl_time_t sanity_itvl,
                  ble_npl_stack_t *stack_bottom, uint16_t stack_size)
{
    int err;

    if ((t == NULL) || (func == NULL)) {
        return -1;
    }

    /* Unused parameters */
    (void)name;
    (void)prio;
    (void)sanity_itvl;
    (void)stack_bottom;
    (void)stack_size;

    err = pthread_create(&t->handle, NULL, func, arg);

    return err ? -1 : 0;
}

int
ble_npl_task_remove(struct ble_npl_task *t)
{
    void *ret;

    if (!t) {
        return -1;
    }

    pthread_cancel(t->handle);
    pthread_join(t->handle, &ret);

    return 0;
}
