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

#include <assert.h>
#include <stdint.h>
#include <string.h>
#include "nimble/nimble_npl.h"
#include "os/os_mempool.h"

/* Forward declaration to fix musl build error */
void ble_npl_eventq_main(void);

#ifndef INT32_MAX
#define INT32_MAX              (2147483647)
#endif
#define BLE_EVT_Q_COUNT  8


struct ble_eventq_s {
    uint8_t              b_init;
    pthread_mutex_t      m_mutex;
    pthread_mutexattr_t  m_mutex_attr;
    pthread_cond_t         m_condv;

    STAILQ_HEAD(ble_queue_list, ble_npl_event) mq_head;
};

static bool b_pool_init = 0;
struct os_mempool ble_eventq_pool;
static os_membuf_t ble_eventq_pool_buf[
    OS_MEMPOOL_SIZE(BLE_EVT_Q_COUNT, sizeof (struct ble_eventq_s))
];

#define wqueue_t struct ble_eventq_s

struct ble_eventq_s  m_queue[BLE_EVT_Q_COUNT];


int mqueue_init(struct ble_eventq_s *mq)
{

    STAILQ_INIT(&mq->mq_head);

    return (0);
}

struct ble_npl_event *mqueue_get(struct ble_eventq_s *mq)
{
    struct ble_npl_event *mp;
    os_sr_t sr;

    OS_ENTER_CRITICAL(sr);
    mp = STAILQ_FIRST(&mq->mq_head);
    if (mp) {
        STAILQ_REMOVE_HEAD(&mq->mq_head, next);
    }
    OS_EXIT_CRITICAL(sr);

    return (mp);
}

int mqueue_put(struct ble_eventq_s *mq, struct ble_npl_event *evq)
{
    os_sr_t sr;

    OS_ENTER_CRITICAL(sr);
    STAILQ_INSERT_TAIL(&mq->mq_head, evq, next);
    OS_EXIT_CRITICAL(sr);

    return (0);
}

struct ble_npl_event *mqueue_pick(struct ble_eventq_s *mq)
{
    struct ble_npl_event *mp;
    os_sr_t sr;

    OS_ENTER_CRITICAL(sr);
    mp = STAILQ_FIRST(&mq->mq_head);
    OS_EXIT_CRITICAL(sr);

    return (mp);
}

void mqueue_del_unlock(struct ble_eventq_s *mq,struct ble_npl_event *mp)
{
   // os_sr_t sr;

   // OS_ENTER_CRITICAL(sr);
    STAILQ_REMOVE(&mq->mq_head, mp, ble_npl_event, next);
   // OS_EXIT_CRITICAL(sr);

}



void wqueue_init(wqueue_t * q)
{
    q->b_init = 1;
    pthread_mutexattr_init(&q->m_mutex_attr);
    pthread_mutexattr_settype(&q->m_mutex_attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&q->m_mutex, &q->m_mutex_attr);
    pthread_cond_init(&q->m_condv, NULL);
    mqueue_init(q);
}

void wqueue_deinit(wqueue_t * q) {
    if(q->b_init){
        q->b_init = 0;
        pthread_mutex_destroy(&q->m_mutex);
        pthread_cond_destroy(&q->m_condv);
    }
}

void wqueue_put(wqueue_t * q,struct ble_npl_event * ev) {
    pthread_mutex_lock(&q->m_mutex);
    mqueue_put(q,ev);
    pthread_cond_signal(&q->m_condv);
    pthread_mutex_unlock(&q->m_mutex);
}

struct ble_npl_event * wqueue_get(wqueue_t * q,uint32_t tmo) {
    pthread_mutex_lock(&q->m_mutex);
    if (tmo) {
        while ((mqueue_pick(q)) == NULL) {
            pthread_cond_wait(&q->m_condv, &q->m_mutex);
        }
    }

    struct ble_npl_event * item = mqueue_get(q);


    pthread_mutex_unlock(&q->m_mutex);
    return item;
}

void wqueue_remove(wqueue_t * q,struct ble_npl_event * ev) {
    pthread_mutex_lock(&q->m_mutex);
    mqueue_del_unlock(q,ev);
    pthread_mutex_unlock(&q->m_mutex);
}


#if 0//CONFIG_BLE_ADV_CFG==0
struct ble_npl_eventq *
ble_npl_eventq_dflt_get(void)
{
    if (!dflt_evq.q) {
        dflt_evq.q = os_memblock_get(&ble_eventq_pool);
    }

    return &dflt_evq;
}
#endif //CONFIG_BLE_ADV_CFG


void
ble_npl_eventq_init(struct ble_npl_eventq *evq)
{
    if (b_pool_init==0) {
        b_pool_init = 1;
        ble_npl_eventq_main();
    }

    evq->q = os_memblock_get(&ble_eventq_pool);
    if(evq->q){
        wqueue_init((wqueue_t *)evq->q);
    }
    else {
        printf("<error>ble_npl_eventq_init fail\n");
    }
}
void
ble_npl_eventq_release(struct ble_npl_eventq* evq)
{
    if(evq->q){
        wqueue_deinit((wqueue_t *)evq->q);
        os_memblock_put(&ble_eventq_pool, evq->q);
    }
    else {
        printf("<error>ble_npl_eventq_release fail\n");
    }
}

bool
ble_npl_eventq_is_empty(struct ble_npl_eventq *evq)
{
    wqueue_t* q = (wqueue_t*)(evq->q);

    if (mqueue_pick((wqueue_t *)q)) {
        return 1;
    } else {
        return 0;
    }
}

int
ble_npl_eventq_inited(const struct ble_npl_eventq *evq)
{
    return (evq->q != NULL);
}

void
ble_npl_eventq_put(struct ble_npl_eventq *evq, struct ble_npl_event *ev)
{
    wqueue_t *q = (wqueue_t *)(evq->q);

    if (ev->ev_queued) {
        return;
    }

    ev->ev_queued = 1;
    wqueue_put(q,ev);
}

struct ble_npl_event *ble_npl_eventq_get(struct ble_npl_eventq *evq,
                                         ble_npl_time_t tmo)
{
    struct ble_npl_event *ev;
    wqueue_t *q = (wqueue_t *)(evq->q);

    ev = wqueue_get(q,tmo);

    if (ev) {
        ev->ev_queued = 0;
    }

    return ev;
}

void
ble_npl_eventq_run(struct ble_npl_eventq *evq)
{
    struct ble_npl_event *ev;

    ev = ble_npl_eventq_get(evq, BLE_NPL_TIME_FOREVER);
    ble_npl_event_run(ev);
}


// ========================================================================
//                         Event Implementation
// ========================================================================

void
ble_npl_event_init(struct ble_npl_event *ev, ble_npl_event_fn *fn,
                   void *arg)
{
    memset(ev, 0, sizeof(*ev));
    ev->ev_cb = fn;
    ev->ev_arg = arg;
    //ev->next = NULL;

    STAILQ_NEXT(ev, next) = NULL;
}

bool
ble_npl_event_is_queued(struct ble_npl_event *ev)
{
    return ev->ev_queued;
}

void *
ble_npl_event_get_arg(struct ble_npl_event *ev)
{
    return ev->ev_arg;
}

void
ble_npl_event_set_arg(struct ble_npl_event *ev, void *arg)
{
    ev->ev_arg = arg;
}

void
ble_npl_event_run(struct ble_npl_event *ev)
{
    assert(ev->ev_cb != NULL);

    ev->ev_cb(ev);
}

void
ble_npl_eventq_remove(struct ble_npl_eventq *evq, struct ble_npl_event *ev)
{
    wqueue_t *q = (wqueue_t *)(evq->q);

    if (!ev->ev_queued) {
        return;
    }

    ev->ev_queued = 0;
    wqueue_remove(q,ev);
}

void ble_npl_eventq_main(void)
{
    printf("ble_npl_eventq_main\n");
    /* Create memory pool of OS events */
    os_mempool_init(&ble_eventq_pool, BLE_EVT_Q_COUNT,
                         sizeof (struct ble_eventq_s), ble_eventq_pool_buf,
                         "ble_evq_pool");

}
