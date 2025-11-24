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

#include <stdint.h>
#include <pthread.h>

#include "nimble/nimble_npl.h"

/* Fixed for musl compatibility - use proper initialization */
static pthread_mutex_t s_mutex;
static pthread_once_t s_mutex_once = PTHREAD_ONCE_INIT;

static void init_mutex(void)
{
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&s_mutex, &attr);
    pthread_mutexattr_destroy(&attr);
}

uint32_t ble_npl_hw_enter_critical(void)
{
    pthread_once(&s_mutex_once, init_mutex);
    pthread_mutex_lock(&s_mutex);
    return 0;
}

void ble_npl_hw_exit_critical(uint32_t ctx)
{
    pthread_mutex_unlock(&s_mutex);
}
