#ifndef SNAIL_CPU_H
#define SNAIL_CPU_H

#include "snail.h"

#ifdef __cplusplus
extern "C" {
#endif

bool snail_cpu_available(void);
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

#ifdef __cplusplus
}
#endif

#endif /* SNAIL_CPU_H */
