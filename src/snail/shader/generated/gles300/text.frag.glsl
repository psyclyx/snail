#version 300 es

precision highp float;
precision highp int;

struct block_SnailPushConstants_0_ {
    mat4x4 mvp_0_;
    vec2 viewport_0_;
    int subpixel_order_0_;
    int output_srgb_0_;
    int layer_base_0_;
    float coverage_exponent_0_;
    float dither_scale_0_;
    int mask_output_0_;
};
vec4 input_color_0_1 = vec4(0.0);

vec4 input_tint_0_1 = vec4(0.0);

vec2 input_texcoord_0_1 = vec2(0.0);

vec4 input_banding_0_1 = vec4(0.0);

ivec4 input_glyph_0_1 = ivec4(0);

uniform highp sampler2DArray _group_0_binding_1_fs;

uniform highp usampler2DArray _group_0_binding_2_fs;

layout(std140) uniform block_SnailPushConstants_0_block_0Fragment { block_SnailPushConstants_0_ _group_0_binding_0_fs; };

vec4 entryPointParam_fragmentMain_0_ = vec4(0.0);

smooth in vec4 _vs2fs_location0;
smooth in vec4 _vs2fs_location4;
smooth in vec2 _vs2fs_location1;
flat in vec4 _vs2fs_location2;
flat in ivec4 _vs2fs_location3;
layout(location = 0) out vec4 _fs2p_location0;

void main_1() {
    ivec4 local = ivec4(0);
    vec4 local_1 = vec4(0.0);
    vec2 local_2 = vec2(0.0);
    vec4 local_3 = vec4(0.0);
    vec4 local_4 = vec4(0.0);
    int local_5 = 0;
    int local_6 = 0;
    int local_7 = 0;
    int local_8 = 0;
    float local_9 = 0.0;
    float local_10 = 0.0;
    float local_11 = 0.0;
    float local_12 = 0.0;
    float local_13 = 0.0;
    float local_14 = 0.0;
    vec4 local_15 = vec4(0.0);
    float local_16 = 0.0;
    vec3 local_17 = vec3(0.0);
    float local_18 = 0.0;
    float local_19 = 0.0;
    float local_20 = 0.0;
    float local_21 = 0.0;
    float local_22 = 0.0;
    float local_23 = 0.0;
    float local_24 = 0.0;
    vec2 local_25 = vec2(0.0);
    vec2 local_26 = vec2(0.0);
    float local_27 = 0.0;
    float local_28 = 0.0;
    float local_29 = 0.0;
    float local_30 = 0.0;
    float local_31 = 0.0;
    float local_32 = 0.0;
    float local_33 = 0.0;
    float local_34 = 0.0;
    float local_35 = 0.0;
    float local_36 = 0.0;
    float local_37 = 0.0;
    float local_38 = 0.0;
    float local_39 = 0.0;
    float local_40 = 0.0;
    float local_41 = 0.0;
    float local_42 = 0.0;
    float local_43 = 0.0;
    float local_44 = 0.0;
    bool local_45 = false;
    vec4 local_46 = vec4(0.0);
    vec2 local_47 = vec2(0.0);
    float local_48 = 0.0;
    uint local_49 = 0u;
    float local_50 = 0.0;
    float local_51 = 0.0;
    vec2 local_52 = vec2(0.0);
    vec4 local_53 = vec4(0.0);
    float local_54 = 0.0;
    vec2 local_55 = vec2(0.0);
    vec2 local_56 = vec2(0.0);
    float local_57 = 0.0;
    float local_58 = 0.0;
    float local_59 = 0.0;
    float local_60 = 0.0;
    float local_61 = 0.0;
    float local_62 = 0.0;
    float local_63 = 0.0;
    float local_64 = 0.0;
    float local_65 = 0.0;
    float local_66 = 0.0;
    float local_67 = 0.0;
    float local_68 = 0.0;
    float local_69 = 0.0;
    float local_70 = 0.0;
    float local_71 = 0.0;
    float local_72 = 0.0;
    float local_73 = 0.0;
    float local_74 = 0.0;
    bool local_75 = false;
    vec4 local_76 = vec4(0.0);
    vec2 local_77 = vec2(0.0);
    float local_78 = 0.0;
    uint local_79 = 0u;
    float local_80 = 0.0;
    float local_81 = 0.0;
    vec2 local_82 = vec2(0.0);
    vec4 local_83 = vec4(0.0);
    int local_84 = 0;
    float local_85 = 0.0;
    float local_86 = 0.0;
    bool local_87 = false;
    int local_88 = 0;
    ivec2 local_89 = ivec2(0);
    int local_90 = 0;
    int local_91 = 0;
    uvec2 local_92 = uvec2(0u);
    bool local_93 = false;
    float local_94 = 0.0;
    float local_95 = 0.0;
    vec2 local_96 = vec2(0.0);
    vec2 local_97 = vec2(0.0);
    ivec2 local_98 = ivec2(0);
    int local_99 = 0;
    float local_100 = 0.0;
    float local_101 = 0.0;
    bool local_102 = false;
    ivec2 local_103 = ivec2(0);
    int local_104 = 0;
    uvec2 local_105 = uvec2(0u);
    float local_106 = 0.0;
    float local_107 = 0.0;
    vec2 local_108 = vec2(0.0);
    vec2 local_109 = vec2(0.0);
    ivec2 local_110 = ivec2(0);
    int local_111 = 0;
    float local_112 = 0.0;
    int local_113 = 0;
    float local_114 = 0.0;
    int local_115 = 0;
    float local_116 = 0.0;
    int local_117 = 0;
    int local_118 = 0;
    int local_119 = 0;
    float local_120 = 0.0;
    vec2 local_121 = vec2(0.0);
    vec2 local_122 = vec2(0.0);
    ivec2 local_123 = ivec2(0);
    int local_124 = 0;
    float local_125 = 0.0;
    vec4 local_126 = vec4(0.0);
    vec4 local_127 = vec4(0.0);
    vec4 local_128 = vec4(0.0);
    vec4 local_129 = vec4(0.0);
    int param = 0;
    int param_1 = 0;
    float param_2 = 0.0;
    int param_3 = 0;
    vec4 _e185 = input_color_0_1;
    vec4 _e186 = input_tint_0_1;
    vec2 _e187 = input_texcoord_0_1;
    vec4 _e188 = input_banding_0_1;
    ivec4 _e189 = input_glyph_0_1;
    local_4 = _e185;
    local_3 = _e186;
    local_2 = _e187;
    local_1 = _e188;
    local = _e189;
    int _e191 = _group_0_binding_0_fs.layer_base_0_;
    param = _e191;
    int _e193 = _group_0_binding_0_fs.output_srgb_0_;
    param_1 = _e193;
    float _e195 = _group_0_binding_0_fs.coverage_exponent_0_;
    param_2 = _e195;
    int _e197 = _group_0_binding_0_fs.mask_output_0_;
    param_3 = _e197;
    local_118 = _e189.w;
    int _e201 = ((_e189.w >> uint(8)) & 255);
    local_119 = _e201;
    if ((_e201 == 255)) {
        discard;
    }
    vec2 _e203 = local_2;
    vec2 _e204 = fwidth(_e203);
    int _e212 = local_118;
    ivec4 _e214 = local;
    ivec2 _e216 = ivec2((_e212 & 255), _e214.z);
    int _e217 = param;
    int _e218 = local_119;
    local_121 = _e203;
    local_122 = vec2((1.0 / max(_e204.x, 1.5258789e-5)), (1.0 / max(_e204.y, 1.5258789e-5)));
    local_123 = _e214.xy;
    vec4 _e221 = local_1;
    local_124 = (_e217 + _e218);
    float _e222 = param_2;
    local_125 = _e222;
    local_84 = _e216.y;
    float _e229 = ((_e203.y * _e221.y) + _e221.w);
    float _e233 = max((abs((_e204.y * _e221.y)) * 0.5), 1e-5);
    int _e236 = min(max(int((_e229 - _e233)), 0), _e216.y);
    int _e240 = max(_e236, min(max(int((_e229 + _e233)), 0), _e216.y));
    local_8 = _e236;
    local_7 = _e240;
    float _e247 = ((_e203.x * _e221.x) + _e221.z);
    float _e251 = max((abs((_e204.x * _e221.x)) * 0.5), 1e-5);
    int _e254 = min(max(int((_e247 - _e251)), 0), _e216.x);
    local_6 = _e254;
    local_5 = max(_e254, min(max(int((_e247 + _e251)), 0), _e216.x));
    local_85 = 0.0;
    local_86 = 0.0;
    local_87 = (_e236 != _e240);
    local_88 = _e236;
    while(true) {
        int _e260 = local_88;
        int _e261 = local_7;
        if ((_e260 <= _e261)) {
        } else {
            break;
        }
        int _e263 = local_88;
        ivec2 _e265 = local_123;
        int _e268 = (_e265.x + int(uint(_e263)));
        ivec2 _e270 = ivec2(_e268, _e265.y);
        ivec2 _e277 = ivec2(_e270.x, (_e270.y + (_e268 >> uint(12))));
        ivec2 _e282 = ivec2((_e277.x & 4095), _e277.y);
        int _e283 = local_124;
        ivec4 _e286 = ivec4(_e282.x, _e282.y, _e283, 0);
        ivec3 _e287 = _e286.xyz;
        uvec4 _e294 = texelFetch(_group_0_binding_2_fs, ivec3(ivec2(_e287.x, _e287.y), int(_e287.z)), _e286.w);
        uvec2 _e295 = _e294.xy;
        int _e299 = (_e265.x + int(_e295.y));
        ivec2 _e301 = ivec2(_e299, _e265.y);
        ivec2 _e308 = ivec2(_e301.x, (_e301.y + (_e299 >> uint(12))));
        local_89 = ivec2((_e308.x & 4095), _e308.y);
        local_90 = int(_e295.x);
        local_91 = 0;
        while(true) {
            int _e316 = local_91;
            int _e317 = local_90;
            if ((_e316 < _e317)) {
            } else {
                break;
            }
            int _e319 = local_91;
            ivec2 _e321 = local_89;
            int _e324 = (_e321.x + int(uint(_e319)));
            ivec2 _e326 = ivec2(_e324, _e321.y);
            ivec2 _e333 = ivec2(_e326.x, (_e326.y + (_e324 >> uint(12))));
            ivec2 _e338 = ivec2((_e333.x & 4095), _e333.y);
            int _e339 = local_124;
            ivec4 _e342 = ivec4(_e338.x, _e338.y, _e339, 0);
            ivec3 _e343 = _e342.xyz;
            uvec4 _e350 = texelFetch(_group_0_binding_2_fs, ivec3(ivec2(_e343.x, _e343.y), int(_e343.z)), _e342.w);
            local_92 = _e350.xy;
            bool _e352 = local_87;
            if (_e352) {
                uvec2 _e353 = local_92;
                int _e354 = local_88;
                int _e355 = local_8;
                local_93 = !((_e354 == max(int((_e353.x >> 12u)), _e355)));
            } else {
                local_93 = false;
            }
            bool _e363 = local_93;
            if (_e363) {
                int _e364 = local_91;
                local_91 = (_e364 + 1);
                continue;
            }
            uvec2 _e366 = local_92;
            float _e374 = local_85;
            local_94 = _e374;
            float _e375 = local_86;
            local_95 = _e375;
            vec2 _e376 = local_121;
            local_96 = _e376;
            vec2 _e377 = local_122;
            local_97 = _e377;
            local_98 = ivec2(int((_e366.x & 4095u)), int((_e366.y & 16383u)));
            int _e378 = local_124;
            local_99 = _e378;
            bool should_continue = false;
            do {
                ivec2 _e380 = local_98;
                int _e381 = local_99;
                ivec4 _e384 = ivec4(_e380.x, _e380.y, _e381, 0);
                ivec3 _e385 = _e384.xyz;
                vec4 _e392 = texelFetch(_group_0_binding_1_fs, ivec3(ivec2(_e385.x, _e385.y), int(_e385.z)), _e384.w);
                int _e394 = (_e380.x + 1);
                ivec2 _e396 = ivec2(_e394, _e380.y);
                ivec2 _e403 = ivec2(_e396.x, (_e396.y + (_e394 >> uint(12))));
                ivec2 _e408 = ivec2((_e403.x & 4095), _e403.y);
                ivec4 _e411 = ivec4(_e408.x, _e408.y, _e381, 0);
                vec2 _e417 = local_96;
                vec4 _e423 = (vec4(_e392.x, _e392.y, _e392.z, _e392.w) - vec4(_e417.x, _e417.y, _e417.x, _e417.y));
                local_76 = _e423;
                ivec3 _e424 = _e411.xyz;
                vec4 _e431 = texelFetch(_group_0_binding_1_fs, ivec3(ivec2(_e424.x, _e424.y), int(_e424.z)), _e411.w);
                vec2 _e433 = (_e431.xy - _e417);
                local_77 = _e433;
                vec2 _e434 = local_97;
                local_78 = _e434.x;
                if (((max(max(_e423.x, _e423.z), _e433.x) * _e434.x) < -0.5)) {
                    local_75 = false;
                    break;
                }
                vec4 _e443 = local_76;
                local_80 = _e443.y;
                local_81 = _e443.w;
                vec2 _e446 = local_77;
                local_72 = _e446.y;
                if ((abs(_e446.y) <= 1.5258789e-5)) {
                    local_71 = 0.0;
                } else {
                    float _e450 = local_72;
                    local_71 = _e450;
                }
                float _e451 = local_71;
                float _e456 = local_81;
                local_73 = _e456;
                if ((abs(_e456) <= 1.5258789e-5)) {
                    local_70 = 0.0;
                } else {
                    float _e459 = local_73;
                    local_70 = _e459;
                }
                float _e460 = local_70;
                float _e465 = local_80;
                local_74 = _e465;
                if ((abs(_e465) <= 1.5258789e-5)) {
                    local_69 = 0.0;
                } else {
                    float _e468 = local_74;
                    local_69 = _e468;
                }
                float _e469 = local_69;
                uint _e479 = ((11892u >> (((floatBitsToUint(_e451) >> 29u) & 4u) | ((((floatBitsToUint(_e460) >> 30u) & 2u) | ((floatBitsToUint(_e469) >> 31u) & 4294967293u)) & 4294967291u))) & 257u);
                local_79 = _e479;
                if ((_e479 != 0u)) {
                    vec4 _e481 = local_76;
                    local_83 = _e481;
                    vec2 _e482 = local_77;
                    vec2 _e483 = _e481.xy;
                    vec2 _e484 = _e481.zw;
                    vec2 _e487 = ((_e483 - (_e484 * 2.0)) + _e482);
                    local_55 = _e487;
                    local_56 = (_e483 - _e484);
                    local_57 = _e487.y;
                    if ((abs(_e487.y) < 1.5258789e-5)) {
                        vec2 _e492 = local_56;
                        local_58 = _e492.y;
                        if ((abs(_e492.y) < 1.5258789e-5)) {
                            local_59 = 0.0;
                        } else {
                            vec4 _e496 = local_83;
                            float _e499 = local_58;
                            local_59 = ((_e496.y * 0.5) / _e499);
                        }
                        float _e501 = local_59;
                        local_60 = _e501;
                    } else {
                        vec2 _e502 = local_56;
                        local_61 = _e502.y;
                        vec4 _e504 = local_83;
                        local_62 = _e504.y;
                        float _e506 = local_57;
                        float _e507 = (_e506 * _e504.y);
                        float _e509 = ((_e502.y * _e502.y) - _e507);
                        local_64 = _e509;
                        if ((_e509 <= (max((_e502.y * _e502.y), abs(_e507)) * 3e-6))) {
                            local_54 = 0.0;
                        } else {
                            float _e515 = local_64;
                            local_54 = sqrt(_e515);
                        }
                        float _e517 = local_54;
                        local_63 = _e517;
                        float _e518 = local_61;
                        if ((_e518 >= 0.0)) {
                            float _e520 = local_61;
                            float _e521 = local_63;
                            float _e522 = (_e520 + _e521);
                            local_65 = _e522;
                            float _e523 = local_57;
                            local_66 = (_e522 / _e523);
                            if ((abs(_e522) < 1.5258789e-5)) {
                                local_59 = 0.0;
                            } else {
                                float _e527 = local_62;
                                float _e528 = local_65;
                                local_59 = (_e527 / _e528);
                            }
                            float _e530 = local_66;
                            local_60 = _e530;
                        } else {
                            float _e531 = local_61;
                            float _e532 = local_63;
                            float _e533 = (_e531 - _e532);
                            local_67 = _e533;
                            float _e534 = local_57;
                            local_68 = (_e533 / _e534);
                            if ((abs(_e533) < 1.5258789e-5)) {
                                local_59 = 0.0;
                            } else {
                                float _e538 = local_62;
                                float _e539 = local_67;
                                local_59 = (_e538 / _e539);
                            }
                            float _e541 = local_59;
                            float _e542 = local_68;
                            local_59 = _e542;
                            local_60 = _e541;
                        }
                    }
                    vec2 _e543 = local_55;
                    vec2 _e545 = local_56;
                    float _e547 = (_e545.x * 2.0);
                    vec4 _e548 = local_83;
                    float _e550 = local_59;
                    float _e555 = local_60;
                    float _e561 = local_78;
                    local_82 = (vec2(((((_e543.x * _e550) - _e547) * _e550) + _e548.x), ((((_e543.x * _e555) - _e547) * _e555) + _e548.x)) * _e561);
                    uint _e563 = local_79;
                    if (((_e563 & 1u) != 0u)) {
                        vec2 _e566 = local_82;
                        float _e568 = local_94;
                        local_94 = (_e568 + clamp((_e566.x + 0.5), 0.0, 1.0));
                        float _e572 = local_95;
                        local_95 = max(_e572, clamp((1.0 - (abs(_e566.x) * 2.0)), 0.0, 1.0));
                    }
                    uint _e578 = local_79;
                    if ((_e578 > 1u)) {
                        vec2 _e580 = local_82;
                        float _e582 = local_94;
                        local_94 = (_e582 - clamp((_e580.y + 0.5), 0.0, 1.0));
                        float _e586 = local_95;
                        local_95 = max(_e586, clamp((1.0 - (abs(_e580.y) * 2.0)), 0.0, 1.0));
                    }
                }
                local_75 = true;
                break;
            } while(false);
            bool _e592 = local_75;
            float _e593 = local_94;
            local_85 = _e593;
            float _e594 = local_95;
            local_86 = _e594;
            if (!(_e592)) {
                break;
            }
            int _e596 = local_91;
            local_91 = (_e596 + 1);
            continue;
        }
        int _e598 = local_88;
        local_88 = (_e598 + 1);
        continue;
    }
    local_100 = 0.0;
    local_101 = 0.0;
    int _e600 = local_6;
    int _e601 = local_5;
    local_102 = (_e600 != _e601);
    local_88 = _e600;
    while(true) {
        int _e603 = local_88;
        int _e604 = local_5;
        if ((_e603 <= _e604)) {
        } else {
            break;
        }
        int _e606 = local_84;
        int _e608 = local_88;
        ivec2 _e611 = local_123;
        int _e614 = (_e611.x + int(uint(((_e606 + 1) + _e608))));
        ivec2 _e616 = ivec2(_e614, _e611.y);
        ivec2 _e623 = ivec2(_e616.x, (_e616.y + (_e614 >> uint(12))));
        ivec2 _e628 = ivec2((_e623.x & 4095), _e623.y);
        int _e629 = local_124;
        ivec4 _e632 = ivec4(_e628.x, _e628.y, _e629, 0);
        ivec3 _e633 = _e632.xyz;
        uvec4 _e640 = texelFetch(_group_0_binding_2_fs, ivec3(ivec2(_e633.x, _e633.y), int(_e633.z)), _e632.w);
        uvec2 _e641 = _e640.xy;
        int _e645 = (_e611.x + int(_e641.y));
        ivec2 _e647 = ivec2(_e645, _e611.y);
        ivec2 _e654 = ivec2(_e647.x, (_e647.y + (_e645 >> uint(12))));
        local_103 = ivec2((_e654.x & 4095), _e654.y);
        local_104 = int(_e641.x);
        local_91 = 0;
        while(true) {
            int _e662 = local_91;
            int _e663 = local_104;
            if ((_e662 < _e663)) {
            } else {
                break;
            }
            int _e665 = local_91;
            ivec2 _e667 = local_103;
            int _e670 = (_e667.x + int(uint(_e665)));
            ivec2 _e672 = ivec2(_e670, _e667.y);
            ivec2 _e679 = ivec2(_e672.x, (_e672.y + (_e670 >> uint(12))));
            ivec2 _e684 = ivec2((_e679.x & 4095), _e679.y);
            int _e685 = local_124;
            ivec4 _e688 = ivec4(_e684.x, _e684.y, _e685, 0);
            ivec3 _e689 = _e688.xyz;
            uvec4 _e696 = texelFetch(_group_0_binding_2_fs, ivec3(ivec2(_e689.x, _e689.y), int(_e689.z)), _e688.w);
            local_105 = _e696.xy;
            bool _e698 = local_102;
            if (_e698) {
                uvec2 _e699 = local_105;
                int _e700 = local_88;
                int _e701 = local_6;
                local_93 = !((_e700 == max(int((_e699.x >> 12u)), _e701)));
            } else {
                local_93 = false;
            }
            bool _e709 = local_93;
            if (_e709) {
                int _e710 = local_91;
                local_91 = (_e710 + 1);
                continue;
            }
            uvec2 _e712 = local_105;
            float _e720 = local_100;
            local_106 = _e720;
            float _e721 = local_101;
            local_107 = _e721;
            vec2 _e722 = local_121;
            local_108 = _e722;
            vec2 _e723 = local_122;
            local_109 = _e723;
            local_110 = ivec2(int((_e712.x & 4095u)), int((_e712.y & 16383u)));
            int _e724 = local_124;
            local_111 = _e724;
            bool should_continue_1 = false;
            do {
                ivec2 _e726 = local_110;
                int _e727 = local_111;
                ivec4 _e730 = ivec4(_e726.x, _e726.y, _e727, 0);
                ivec3 _e731 = _e730.xyz;
                vec4 _e738 = texelFetch(_group_0_binding_1_fs, ivec3(ivec2(_e731.x, _e731.y), int(_e731.z)), _e730.w);
                int _e740 = (_e726.x + 1);
                ivec2 _e742 = ivec2(_e740, _e726.y);
                ivec2 _e749 = ivec2(_e742.x, (_e742.y + (_e740 >> uint(12))));
                ivec2 _e754 = ivec2((_e749.x & 4095), _e749.y);
                ivec4 _e757 = ivec4(_e754.x, _e754.y, _e727, 0);
                vec2 _e763 = local_108;
                vec4 _e769 = (vec4(_e738.x, _e738.y, _e738.z, _e738.w) - vec4(_e763.x, _e763.y, _e763.x, _e763.y));
                local_46 = _e769;
                ivec3 _e770 = _e757.xyz;
                vec4 _e777 = texelFetch(_group_0_binding_1_fs, ivec3(ivec2(_e770.x, _e770.y), int(_e770.z)), _e757.w);
                vec2 _e779 = (_e777.xy - _e763);
                local_47 = _e779;
                vec2 _e780 = local_109;
                local_48 = _e780.y;
                if (((max(max(_e769.y, _e769.w), _e779.y) * _e780.y) < -0.5)) {
                    local_45 = false;
                    break;
                }
                vec4 _e789 = local_46;
                local_50 = _e789.x;
                local_51 = _e789.z;
                vec2 _e792 = local_47;
                local_42 = _e792.x;
                if ((abs(_e792.x) <= 1.5258789e-5)) {
                    local_41 = 0.0;
                } else {
                    float _e796 = local_42;
                    local_41 = _e796;
                }
                float _e797 = local_41;
                float _e802 = local_51;
                local_43 = _e802;
                if ((abs(_e802) <= 1.5258789e-5)) {
                    local_40 = 0.0;
                } else {
                    float _e805 = local_43;
                    local_40 = _e805;
                }
                float _e806 = local_40;
                float _e811 = local_50;
                local_44 = _e811;
                if ((abs(_e811) <= 1.5258789e-5)) {
                    local_39 = 0.0;
                } else {
                    float _e814 = local_44;
                    local_39 = _e814;
                }
                float _e815 = local_39;
                uint _e825 = ((11892u >> (((floatBitsToUint(_e797) >> 29u) & 4u) | ((((floatBitsToUint(_e806) >> 30u) & 2u) | ((floatBitsToUint(_e815) >> 31u) & 4294967293u)) & 4294967291u))) & 257u);
                local_49 = _e825;
                if ((_e825 != 0u)) {
                    vec4 _e827 = local_46;
                    local_53 = _e827;
                    vec2 _e828 = local_47;
                    vec2 _e829 = _e827.xy;
                    vec2 _e830 = _e827.zw;
                    vec2 _e833 = ((_e829 - (_e830 * 2.0)) + _e828);
                    local_25 = _e833;
                    local_26 = (_e829 - _e830);
                    local_27 = _e833.x;
                    if ((abs(_e833.x) < 1.5258789e-5)) {
                        vec2 _e838 = local_26;
                        local_28 = _e838.x;
                        if ((abs(_e838.x) < 1.5258789e-5)) {
                            local_29 = 0.0;
                        } else {
                            vec4 _e842 = local_53;
                            float _e845 = local_28;
                            local_29 = ((_e842.x * 0.5) / _e845);
                        }
                        float _e847 = local_29;
                        local_30 = _e847;
                    } else {
                        vec2 _e848 = local_26;
                        local_31 = _e848.x;
                        vec4 _e850 = local_53;
                        local_32 = _e850.x;
                        float _e852 = local_27;
                        float _e853 = (_e852 * _e850.x);
                        float _e855 = ((_e848.x * _e848.x) - _e853);
                        local_34 = _e855;
                        if ((_e855 <= (max((_e848.x * _e848.x), abs(_e853)) * 3e-6))) {
                            local_24 = 0.0;
                        } else {
                            float _e861 = local_34;
                            local_24 = sqrt(_e861);
                        }
                        float _e863 = local_24;
                        local_33 = _e863;
                        float _e864 = local_31;
                        if ((_e864 >= 0.0)) {
                            float _e866 = local_31;
                            float _e867 = local_33;
                            float _e868 = (_e866 + _e867);
                            local_35 = _e868;
                            float _e869 = local_27;
                            local_36 = (_e868 / _e869);
                            if ((abs(_e868) < 1.5258789e-5)) {
                                local_29 = 0.0;
                            } else {
                                float _e873 = local_32;
                                float _e874 = local_35;
                                local_29 = (_e873 / _e874);
                            }
                            float _e876 = local_36;
                            local_30 = _e876;
                        } else {
                            float _e877 = local_31;
                            float _e878 = local_33;
                            float _e879 = (_e877 - _e878);
                            local_37 = _e879;
                            float _e880 = local_27;
                            local_38 = (_e879 / _e880);
                            if ((abs(_e879) < 1.5258789e-5)) {
                                local_29 = 0.0;
                            } else {
                                float _e884 = local_32;
                                float _e885 = local_37;
                                local_29 = (_e884 / _e885);
                            }
                            float _e887 = local_29;
                            float _e888 = local_38;
                            local_29 = _e888;
                            local_30 = _e887;
                        }
                    }
                    vec2 _e889 = local_25;
                    vec2 _e891 = local_26;
                    float _e893 = (_e891.y * 2.0);
                    vec4 _e894 = local_53;
                    float _e896 = local_29;
                    float _e901 = local_30;
                    float _e907 = local_48;
                    local_52 = (vec2(((((_e889.y * _e896) - _e893) * _e896) + _e894.y), ((((_e889.y * _e901) - _e893) * _e901) + _e894.y)) * _e907);
                    uint _e909 = local_49;
                    if (((_e909 & 1u) != 0u)) {
                        vec2 _e912 = local_52;
                        float _e914 = local_106;
                        local_106 = (_e914 - clamp((_e912.x + 0.5), 0.0, 1.0));
                        float _e918 = local_107;
                        local_107 = max(_e918, clamp((1.0 - (abs(_e912.x) * 2.0)), 0.0, 1.0));
                    }
                    uint _e924 = local_49;
                    if ((_e924 > 1u)) {
                        vec2 _e926 = local_52;
                        float _e928 = local_106;
                        local_106 = (_e928 + clamp((_e926.y + 0.5), 0.0, 1.0));
                        float _e932 = local_107;
                        local_107 = max(_e932, clamp((1.0 - (abs(_e926.y) * 2.0)), 0.0, 1.0));
                    }
                }
                local_45 = true;
                break;
            } while(false);
            bool _e938 = local_45;
            float _e939 = local_106;
            local_100 = _e939;
            float _e940 = local_107;
            local_101 = _e940;
            if (!(_e938)) {
                break;
            }
            int _e942 = local_91;
            local_91 = (_e942 + 1);
            continue;
        }
        int _e944 = local_88;
        local_88 = (_e944 + 1);
        continue;
    }
    float _e946 = local_85;
    float _e947 = local_86;
    float _e949 = local_100;
    float _e950 = local_101;
    local_112 = (((_e946 * _e947) + (_e949 * _e950)) / max((_e947 + _e950), 1.5258789e-5));
    local_113 = 0;
    do {
        int _e957 = local_113;
        if ((_e957 == 1)) {
            float _e959 = local_112;
            local_23 = (1.0 - abs(((fract((_e959 * 0.5)) * 2.0) - 1.0)));
            break;
        }
        float _e966 = local_112;
        local_23 = abs(_e966);
        break;
    } while(false);
    float _e968 = local_23;
    float _e969 = local_85;
    local_114 = _e969;
    local_115 = 0;
    do {
        int _e971 = local_115;
        if ((_e971 == 1)) {
            float _e973 = local_114;
            local_22 = (1.0 - abs(((fract((_e973 * 0.5)) * 2.0) - 1.0)));
            break;
        }
        float _e980 = local_114;
        local_22 = abs(_e980);
        break;
    } while(false);
    float _e982 = local_22;
    float _e983 = local_100;
    local_116 = _e983;
    local_117 = 0;
    do {
        int _e985 = local_117;
        if ((_e985 == 1)) {
            float _e987 = local_116;
            local_21 = (1.0 - abs(((fract((_e987 * 0.5)) * 2.0) - 1.0)));
            break;
        }
        float _e994 = local_116;
        local_21 = abs(_e994);
        break;
    } while(false);
    float _e996 = local_21;
    float _e999 = local_125;
    local_18 = clamp(max(_e968, min(_e982, _e996)), 0.0, 1.0);
    float _e1001 = max(_e999, 1.5258789e-5);
    local_19 = _e1001;
    if ((abs((_e1001 - 1.0)) <= 1e-6)) {
        float _e1005 = local_18;
        local_20 = _e1005;
    } else {
        float _e1006 = local_18;
        float _e1007 = local_19;
        local_20 = pow(_e1006, _e1007);
    }
    float _e1009 = local_20;
    local_120 = _e1009;
    if ((_e1009 < 0.003921569)) {
        discard;
    }
    vec4 _e1011 = local_4;
    vec4 _e1012 = local_3;
    vec4 _e1013 = (_e1011 * _e1012);
    float _e1014 = local_120;
    float _e1016 = (_e1013.w * _e1014);
    vec3 _e1018 = (_e1013.xyz * _e1016);
    local_126 = vec4(_e1018.x, _e1018.y, _e1018.z, _e1016);
    int _e1023 = param_3;
    if ((_e1023 != 0)) {
        vec4 _e1025 = local_126;
        local_127 = vec4(_e1025.w);
    } else {
        int _e1028 = param_1;
        if ((_e1028 != 0)) {
            vec4 _e1030 = local_126;
            local_128 = _e1030;
            do {
                vec4 _e1032 = local_128;
                local_16 = _e1032.w;
                if ((_e1032.w <= 0.0)) {
                    local_15 = vec4(0.0, 0.0, 0.0, 0.0);
                    break;
                }
                vec4 _e1035 = local_128;
                float _e1037 = local_16;
                vec3 _e1039 = (_e1035.xyz * (1.0 / _e1037));
                local_17 = _e1039;
                float _e1041 = max(_e1039.x, 0.0);
                local_12 = _e1041;
                if ((_e1041 <= 0.0031308)) {
                    float _e1043 = local_12;
                    local_11 = (_e1043 * 12.92);
                } else {
                    float _e1045 = local_12;
                    local_11 = ((1.055 * pow(_e1045, 0.41666666)) - 0.055);
                }
                float _e1049 = local_11;
                vec3 _e1050 = local_17;
                float _e1052 = max(_e1050.y, 0.0);
                local_13 = _e1052;
                if ((_e1052 <= 0.0031308)) {
                    float _e1054 = local_13;
                    local_10 = (_e1054 * 12.92);
                } else {
                    float _e1056 = local_13;
                    local_10 = ((1.055 * pow(_e1056, 0.41666666)) - 0.055);
                }
                float _e1060 = local_10;
                vec3 _e1061 = local_17;
                float _e1063 = max(_e1061.z, 0.0);
                local_14 = _e1063;
                if ((_e1063 <= 0.0031308)) {
                    float _e1065 = local_14;
                    local_9 = (_e1065 * 12.92);
                } else {
                    float _e1067 = local_14;
                    local_9 = ((1.055 * pow(_e1067, 0.41666666)) - 0.055);
                }
                float _e1071 = local_9;
                float _e1073 = local_16;
                vec3 _e1074 = (vec3(_e1049, _e1060, _e1071) * _e1073);
                local_15 = vec4(_e1074.x, _e1074.y, _e1074.z, _e1073);
                break;
            } while(false);
            vec4 _e1079 = local_15;
            local_127 = _e1079;
        } else {
            vec4 _e1080 = local_126;
            local_127 = _e1080;
        }
    }
    vec4 _e1081 = local_127;
    local_129 = _e1081;
    vec4 _e1082 = local_129;
    entryPointParam_fragmentMain_0_ = _e1082;
    return;
}

void main() {
    vec4 input_color_0_ = _vs2fs_location0;
    vec4 input_tint_0_ = _vs2fs_location4;
    vec2 input_texcoord_0_ = _vs2fs_location1;
    vec4 input_banding_0_ = _vs2fs_location2;
    ivec4 input_glyph_0_ = _vs2fs_location3;
    input_color_0_1 = input_color_0_;
    input_tint_0_1 = input_tint_0_;
    input_texcoord_0_1 = input_texcoord_0_;
    input_banding_0_1 = input_banding_0_;
    input_glyph_0_1 = input_glyph_0_;
    main_1();
    vec4 _e11 = entryPointParam_fragmentMain_0_;
    _fs2p_location0 = _e11;
    return;
}

