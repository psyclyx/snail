// Vulkan records storage for the arbitrary-position coverage sampler
// (`snail_text_sample_premul_linear`, from snail_text_sample_body.glsl).
//
// The per-glyph emit words live in a read-only SSBO in a *caller-owned*
// descriptor set and binding selected by the caller. An SSBO (rather than a
// uniform texel buffer) removes the ~64K-texel capacity ceiling and needs no
// VkBufferView.
//
// The caller must also provide `int u_snail_text_glyph_count` — declare it as a
// push-constant / specialization-constant member before #including the sample
// body. (It is not declared here so this file imposes nothing on the caller's
// push-constant layout.)
#ifndef SNAIL_RECORDS_SET
#error "define SNAIL_RECORDS_SET before including snail_text_sample.interface.vulkan.glsl"
#endif
#ifndef SNAIL_RECORDS_BINDING
#error "define SNAIL_RECORDS_BINDING before including snail_text_sample.interface.vulkan.glsl"
#endif

layout(set = SNAIL_RECORDS_SET, binding = SNAIL_RECORDS_BINDING) readonly buffer SnailTextRecords {
    uint words[];
} u_snail_text_records;

uint snailTextRecordWord(int linear_index) {
    return u_snail_text_records.words[linear_index];
}
