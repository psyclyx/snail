#ifndef SNAIL_CPU_H
#define SNAIL_CPU_H

#include "snail.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SnailThreadPool SnailThreadPool;

bool snail_cpu_available(void);

int snail_thread_pool_init(const SnailAllocator *alloc,
                           SnailThreadPool **out);
int snail_thread_pool_init_with_threads(const SnailAllocator *alloc,
                                        size_t worker_count,
                                        SnailThreadPool **out);
void snail_thread_pool_deinit(SnailThreadPool *pool);
size_t snail_thread_pool_thread_count(const SnailThreadPool *pool);

int snail_cpu_renderer_init(uint8_t *pixels,
                            uint32_t width,
                            uint32_t height,
                            uint32_t stride,
                            SnailRenderer **out);
int snail_cpu_renderer_reinit_buffer(SnailRenderer *renderer,
                                     uint8_t *pixels,
                                     uint32_t width,
                                     uint32_t height,
                                     uint32_t stride);
int snail_cpu_renderer_set_thread_pool(SnailRenderer *renderer,
                                       SnailThreadPool *pool);

#ifdef __cplusplus
}
#endif

#endif /* SNAIL_CPU_H */
