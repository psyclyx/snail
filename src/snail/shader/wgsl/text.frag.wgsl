struct block_SLANG_ParameterGroup_PushConstants_0_ {
    mvp_0_: mat4x4<f32>,
    viewport_0_: vec2<f32>,
    subpixel_order_0_: i32,
    output_srgb_0_: i32,
    layer_base_0_: i32,
    coverage_exponent_0_: f32,
    dither_scale_0_: f32,
    mask_output_0_: i32,
}

@group(1) @binding(0) 
var u_curve_tex_0_sampler: sampler;
@group(0) @binding(0) 
var u_curve_tex_0_image: texture_2d_array<f32>;
@group(2) @binding(0) 
var<uniform> PushConstants_0_: block_SLANG_ParameterGroup_PushConstants_0_;
@group(1) @binding(1) 
var u_band_tex_0_sampler: sampler;
@group(0) @binding(1) 
var u_band_tex_0_image: texture_2d_array<u32>;
var<private> v_glyph_0_1: vec4<i32>;
var<private> v_texcoord_0_1: vec2<f32>;
var<private> v_banding_0_1: vec4<f32>;
var<private> v_color_0_1: vec4<f32>;
var<private> v_tint_0_1: vec4<f32>;
var<private> entryPointParam_main_frag_color_0_: vec4<f32>;

fn main_1() {
    var local: i32;
    var local_1: i32;
    var local_2: i32;
    var local_3: i32;
    var _S63_: vec4<f32>;
    var local_4: f32;
    var local_5: f32;
    var local_6: f32;
    var local_7: f32;
    var local_8: f32;
    var local_9: f32;
    var local_10: vec4<f32>;
    var local_11: f32;
    var local_12: vec3<f32>;
    var local_13: f32;
    var local_14: f32;
    var local_15: f32;
    var local_16: f32;
    var local_17: f32;
    var local_18: f32;
    var local_19: f32;
    var local_20: vec2<f32>;
    var local_21: vec2<f32>;
    var local_22: f32;
    var local_23: f32;
    var local_24: f32;
    var local_25: f32;
    var local_26: f32;
    var local_27: f32;
    var local_28: f32;
    var local_29: f32;
    var local_30: f32;
    var local_31: f32;
    var local_32: f32;
    var local_33: f32;
    var local_34: f32;
    var local_35: f32;
    var local_36: f32;
    var local_37: f32;
    var local_38: f32;
    var local_39: f32;
    var local_40: bool;
    var local_41: vec4<f32>;
    var local_42: vec2<f32>;
    var local_43: f32;
    var local_44: u32;
    var local_45: f32;
    var local_46: f32;
    var local_47: vec2<f32>;
    var local_48: vec4<f32>;
    var local_49: f32;
    var local_50: vec2<f32>;
    var local_51: vec2<f32>;
    var local_52: f32;
    var local_53: f32;
    var local_54: f32;
    var local_55: f32;
    var local_56: f32;
    var local_57: f32;
    var local_58: f32;
    var local_59: f32;
    var local_60: f32;
    var local_61: f32;
    var local_62: f32;
    var local_63: f32;
    var local_64: f32;
    var local_65: f32;
    var local_66: f32;
    var local_67: f32;
    var local_68: f32;
    var local_69: f32;
    var local_70: bool;
    var local_71: vec4<f32>;
    var local_72: vec2<f32>;
    var local_73: f32;
    var local_74: u32;
    var local_75: f32;
    var local_76: f32;
    var local_77: vec2<f32>;
    var local_78: vec4<f32>;
    var local_79: i32;
    var local_80: f32;
    var local_81: f32;
    var local_82: bool;
    var local_83: i32;
    var local_84: vec2<i32>;
    var local_85: i32;
    var local_86: i32;
    var local_87: vec2<u32>;
    var local_88: bool;
    var local_89: f32;
    var local_90: f32;
    var local_91: vec2<f32>;
    var local_92: vec2<f32>;
    var local_93: vec2<i32>;
    var local_94: i32;
    var local_95: f32;
    var local_96: f32;
    var local_97: bool;
    var local_98: vec2<i32>;
    var local_99: i32;
    var local_100: vec2<u32>;
    var local_101: f32;
    var local_102: f32;
    var local_103: vec2<f32>;
    var local_104: vec2<f32>;
    var local_105: vec2<i32>;
    var local_106: i32;
    var local_107: f32;
    var local_108: i32;
    var local_109: f32;
    var local_110: i32;
    var local_111: f32;
    var local_112: i32;
    var local_113: i32;
    var local_114: f32;
    var local_115: vec2<f32>;
    var local_116: vec2<f32>;
    var local_117: vec2<i32>;
    var local_118: i32;
    var local_119: vec4<f32>;
    var local_120: vec4<f32>;
    var local_121: vec4<f32>;

    let _e178 = v_glyph_0_1[3u];
    let _e181 = ((_e178 >> bitcast<u32>(8i)) & 255i);
    local_113 = _e181;
    if (_e181 == 255i) {
        discard;
    }
    let _e183 = v_texcoord_0_1;
    let _e184 = fwidth(_e183);
    let _e193 = v_glyph_0_1[3u];
    let _e196 = v_glyph_0_1[2u];
    let _e197 = vec2<i32>((_e193 & 255i), _e196);
    let _e199 = PushConstants_0_.layer_base_0_;
    let _e200 = local_113;
    let _e202 = v_texcoord_0_1;
    local_115 = _e202;
    local_116 = vec2<f32>((1f / max(_e184.x, 0.000015258789f)), (1f / max(_e184.y, 0.000015258789f)));
    let _e203 = v_glyph_0_1;
    local_117 = _e203.xy;
    let _e205 = v_banding_0_1;
    local_118 = (_e199 + _e200);
    local_79 = _e197.y;
    let _e212 = ((_e202.y * _e205.y) + _e205.w);
    let _e216 = max((abs((_e184.y * _e205.y)) * 0.5f), 0.00001f);
    let _e219 = clamp(i32((_e212 - _e216)), 0i, _e197.y);
    let _e223 = max(_e219, clamp(i32((_e212 + _e216)), 0i, _e197.y));
    local_3 = _e219;
    local_2 = _e223;
    let _e230 = ((_e202.x * _e205.x) + _e205.z);
    let _e234 = max((abs((_e184.x * _e205.x)) * 0.5f), 0.00001f);
    let _e237 = clamp(i32((_e230 - _e234)), 0i, _e197.x);
    local_1 = _e237;
    local = max(_e237, clamp(i32((_e230 + _e234)), 0i, _e197.x));
    local_80 = 0f;
    local_81 = 0f;
    local_82 = (_e219 != _e223);
    local_83 = _e219;
    loop {
        let _e243 = local_83;
        let _e244 = local_2;
        if (_e243 <= _e244) {
        } else {
            break;
        }
        let _e246 = local_83;
        let _e248 = local_117;
        let _e251 = (_e248.x + bitcast<i32>(bitcast<u32>(_e246)));
        let _e253 = vec2<i32>(_e251, _e248.y);
        let _e260 = vec2<i32>(_e253.x, (_e253.y + (_e251 >> bitcast<u32>(12i))));
        let _e265 = vec2<i32>((_e260.x & 4095i), _e260.y);
        let _e266 = local_118;
        let _e269 = vec4<i32>(_e265.x, _e265.y, _e266, 0i);
        let _e270 = _e269.xyz;
        let _e277 = textureLoad(u_band_tex_0_image, vec2<i32>(_e270.x, _e270.y), i32(_e270.z), _e269.w);
        let _e278 = _e277.xy;
        let _e282 = (_e248.x + bitcast<i32>(_e278.y));
        let _e284 = vec2<i32>(_e282, _e248.y);
        let _e291 = vec2<i32>(_e284.x, (_e284.y + (_e282 >> bitcast<u32>(12i))));
        local_84 = vec2<i32>((_e291.x & 4095i), _e291.y);
        local_85 = bitcast<i32>(_e278.x);
        local_86 = 0i;
        loop {
            let _e299 = local_86;
            let _e300 = local_85;
            if (_e299 < _e300) {
            } else {
                break;
            }
            let _e302 = local_86;
            let _e304 = local_84;
            let _e307 = (_e304.x + bitcast<i32>(bitcast<u32>(_e302)));
            let _e309 = vec2<i32>(_e307, _e304.y);
            let _e316 = vec2<i32>(_e309.x, (_e309.y + (_e307 >> bitcast<u32>(12i))));
            let _e321 = vec2<i32>((_e316.x & 4095i), _e316.y);
            let _e322 = local_118;
            let _e325 = vec4<i32>(_e321.x, _e321.y, _e322, 0i);
            let _e326 = _e325.xyz;
            let _e333 = textureLoad(u_band_tex_0_image, vec2<i32>(_e326.x, _e326.y), i32(_e326.z), _e325.w);
            local_87 = _e333.xy;
            let _e335 = local_82;
            if _e335 {
                let _e336 = local_87;
                let _e337 = local_83;
                let _e338 = local_3;
                local_88 = !((_e337 == max(bitcast<i32>((_e336.x >> bitcast<u32>(12u))), _e338)));
            } else {
                local_88 = false;
            }
            let _e346 = local_88;
            if _e346 {
                let _e347 = local_86;
                local_86 = (_e347 + 1i);
                continue;
            }
            let _e349 = local_87;
            let _e357 = local_80;
            local_89 = _e357;
            let _e358 = local_81;
            local_90 = _e358;
            let _e359 = local_115;
            local_91 = _e359;
            let _e360 = local_116;
            local_92 = _e360;
            local_93 = vec2<i32>(bitcast<i32>((_e349.x & 4095u)), bitcast<i32>((_e349.y & 16383u)));
            let _e361 = local_118;
            local_94 = _e361;
            switch bitcast<i32>(0u) {
                default: {
                    let _e363 = local_93;
                    let _e364 = local_94;
                    let _e367 = vec4<i32>(_e363.x, _e363.y, _e364, 0i);
                    let _e368 = _e367.xyz;
                    let _e375 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e368.x, _e368.y), i32(_e368.z), _e367.w);
                    let _e377 = (_e363.x + 1i);
                    let _e379 = vec2<i32>(_e377, _e363.y);
                    let _e386 = vec2<i32>(_e379.x, (_e379.y + (_e377 >> bitcast<u32>(12i))));
                    let _e391 = vec2<i32>((_e386.x & 4095i), _e386.y);
                    let _e394 = vec4<i32>(_e391.x, _e391.y, _e364, 0i);
                    let _e400 = local_91;
                    let _e406 = (vec4<f32>(_e375.x, _e375.y, _e375.z, _e375.w) - vec4<f32>(_e400.x, _e400.y, _e400.x, _e400.y));
                    local_71 = _e406;
                    let _e407 = _e394.xyz;
                    let _e414 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e407.x, _e407.y), i32(_e407.z), _e394.w);
                    let _e416 = (_e414.xy - _e400);
                    local_72 = _e416;
                    let _e417 = local_92;
                    local_73 = _e417.x;
                    if ((max(max(_e406.x, _e406.z), _e416.x) * _e417.x) < -0.5f) {
                        local_70 = false;
                        break;
                    }
                    let _e426 = local_71;
                    local_75 = _e426.y;
                    local_76 = _e426.w;
                    let _e429 = local_72;
                    local_67 = _e429.y;
                    if (abs(_e429.y) <= 0.000015258789f) {
                        local_66 = 0f;
                    } else {
                        let _e433 = local_67;
                        local_66 = _e433;
                    }
                    let _e434 = local_66;
                    let _e439 = local_76;
                    local_68 = _e439;
                    if (abs(_e439) <= 0.000015258789f) {
                        local_65 = 0f;
                    } else {
                        let _e442 = local_68;
                        local_65 = _e442;
                    }
                    let _e443 = local_65;
                    let _e448 = local_75;
                    local_69 = _e448;
                    if (abs(_e448) <= 0.000015258789f) {
                        local_64 = 0f;
                    } else {
                        let _e451 = local_69;
                        local_64 = _e451;
                    }
                    let _e452 = local_64;
                    let _e462 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e434) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e443) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e452) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                    local_74 = _e462;
                    if (_e462 != 0u) {
                        let _e464 = local_71;
                        local_78 = _e464;
                        let _e465 = local_72;
                        let _e466 = _e464.xy;
                        let _e467 = _e464.zw;
                        let _e470 = ((_e466 - (_e467 * 2f)) + _e465);
                        local_50 = _e470;
                        local_51 = (_e466 - _e467);
                        local_52 = _e470.y;
                        if (abs(_e470.y) < 0.000015258789f) {
                            let _e475 = local_51;
                            local_53 = _e475.y;
                            if (abs(_e475.y) < 0.000015258789f) {
                                local_54 = 0f;
                            } else {
                                let _e479 = local_78;
                                let _e482 = local_53;
                                local_54 = ((_e479.y * 0.5f) / _e482);
                            }
                            let _e484 = local_54;
                            local_55 = _e484;
                        } else {
                            let _e485 = local_51;
                            local_56 = _e485.y;
                            let _e487 = local_78;
                            local_57 = _e487.y;
                            let _e489 = local_52;
                            let _e490 = (_e489 * _e487.y);
                            let _e492 = ((_e485.y * _e485.y) - _e490);
                            local_59 = _e492;
                            if (_e492 <= (max((_e485.y * _e485.y), abs(_e490)) * 0.000003f)) {
                                local_49 = 0f;
                            } else {
                                let _e498 = local_59;
                                local_49 = sqrt(_e498);
                            }
                            let _e500 = local_49;
                            local_58 = _e500;
                            let _e501 = local_56;
                            if (_e501 >= 0f) {
                                let _e503 = local_56;
                                let _e504 = local_58;
                                let _e505 = (_e503 + _e504);
                                local_60 = _e505;
                                let _e506 = local_52;
                                local_61 = (_e505 / _e506);
                                if (abs(_e505) < 0.000015258789f) {
                                    local_54 = 0f;
                                } else {
                                    let _e510 = local_57;
                                    let _e511 = local_60;
                                    local_54 = (_e510 / _e511);
                                }
                                let _e513 = local_61;
                                local_55 = _e513;
                            } else {
                                let _e514 = local_56;
                                let _e515 = local_58;
                                let _e516 = (_e514 - _e515);
                                local_62 = _e516;
                                let _e517 = local_52;
                                local_63 = (_e516 / _e517);
                                if (abs(_e516) < 0.000015258789f) {
                                    local_54 = 0f;
                                } else {
                                    let _e521 = local_57;
                                    let _e522 = local_62;
                                    local_54 = (_e521 / _e522);
                                }
                                let _e524 = local_54;
                                let _e525 = local_63;
                                local_54 = _e525;
                                local_55 = _e524;
                            }
                        }
                        let _e526 = local_50;
                        let _e528 = local_51;
                        let _e530 = (_e528.x * 2f);
                        let _e531 = local_78;
                        let _e533 = local_54;
                        let _e538 = local_55;
                        let _e544 = local_73;
                        local_77 = (vec2<f32>(((((_e526.x * _e533) - _e530) * _e533) + _e531.x), ((((_e526.x * _e538) - _e530) * _e538) + _e531.x)) * _e544);
                        let _e546 = local_74;
                        if ((_e546 & 1u) != 0u) {
                            let _e549 = local_77;
                            let _e551 = local_89;
                            local_89 = (_e551 + clamp((_e549.x + 0.5f), 0f, 1f));
                            let _e555 = local_90;
                            local_90 = max(_e555, clamp((1f - (abs(_e549.x) * 2f)), 0f, 1f));
                        }
                        let _e561 = local_74;
                        if (_e561 > 1u) {
                            let _e563 = local_77;
                            let _e565 = local_89;
                            local_89 = (_e565 - clamp((_e563.y + 0.5f), 0f, 1f));
                            let _e569 = local_90;
                            local_90 = max(_e569, clamp((1f - (abs(_e563.y) * 2f)), 0f, 1f));
                        }
                    }
                    local_70 = true;
                    break;
                }
            }
            let _e575 = local_70;
            let _e576 = local_89;
            local_80 = _e576;
            let _e577 = local_90;
            local_81 = _e577;
            if !(_e575) {
                break;
            }
            let _e579 = local_86;
            local_86 = (_e579 + 1i);
            continue;
        }
        let _e581 = local_83;
        local_83 = (_e581 + 1i);
        continue;
    }
    local_95 = 0f;
    local_96 = 0f;
    let _e583 = local_1;
    let _e584 = local;
    local_97 = (_e583 != _e584);
    local_83 = _e583;
    loop {
        let _e586 = local_83;
        let _e587 = local;
        if (_e586 <= _e587) {
        } else {
            break;
        }
        let _e589 = local_79;
        let _e591 = local_83;
        let _e594 = local_117;
        let _e597 = (_e594.x + bitcast<i32>(bitcast<u32>(((_e589 + 1i) + _e591))));
        let _e599 = vec2<i32>(_e597, _e594.y);
        let _e606 = vec2<i32>(_e599.x, (_e599.y + (_e597 >> bitcast<u32>(12i))));
        let _e611 = vec2<i32>((_e606.x & 4095i), _e606.y);
        let _e612 = local_118;
        let _e615 = vec4<i32>(_e611.x, _e611.y, _e612, 0i);
        let _e616 = _e615.xyz;
        let _e623 = textureLoad(u_band_tex_0_image, vec2<i32>(_e616.x, _e616.y), i32(_e616.z), _e615.w);
        let _e624 = _e623.xy;
        let _e628 = (_e594.x + bitcast<i32>(_e624.y));
        let _e630 = vec2<i32>(_e628, _e594.y);
        let _e637 = vec2<i32>(_e630.x, (_e630.y + (_e628 >> bitcast<u32>(12i))));
        local_98 = vec2<i32>((_e637.x & 4095i), _e637.y);
        local_99 = bitcast<i32>(_e624.x);
        local_86 = 0i;
        loop {
            let _e645 = local_86;
            let _e646 = local_99;
            if (_e645 < _e646) {
            } else {
                break;
            }
            let _e648 = local_86;
            let _e650 = local_98;
            let _e653 = (_e650.x + bitcast<i32>(bitcast<u32>(_e648)));
            let _e655 = vec2<i32>(_e653, _e650.y);
            let _e662 = vec2<i32>(_e655.x, (_e655.y + (_e653 >> bitcast<u32>(12i))));
            let _e667 = vec2<i32>((_e662.x & 4095i), _e662.y);
            let _e668 = local_118;
            let _e671 = vec4<i32>(_e667.x, _e667.y, _e668, 0i);
            let _e672 = _e671.xyz;
            let _e679 = textureLoad(u_band_tex_0_image, vec2<i32>(_e672.x, _e672.y), i32(_e672.z), _e671.w);
            local_100 = _e679.xy;
            let _e681 = local_97;
            if _e681 {
                let _e682 = local_100;
                let _e683 = local_83;
                let _e684 = local_1;
                local_88 = !((_e683 == max(bitcast<i32>((_e682.x >> bitcast<u32>(12u))), _e684)));
            } else {
                local_88 = false;
            }
            let _e692 = local_88;
            if _e692 {
                let _e693 = local_86;
                local_86 = (_e693 + 1i);
                continue;
            }
            let _e695 = local_100;
            let _e703 = local_95;
            local_101 = _e703;
            let _e704 = local_96;
            local_102 = _e704;
            let _e705 = local_115;
            local_103 = _e705;
            let _e706 = local_116;
            local_104 = _e706;
            local_105 = vec2<i32>(bitcast<i32>((_e695.x & 4095u)), bitcast<i32>((_e695.y & 16383u)));
            let _e707 = local_118;
            local_106 = _e707;
            switch bitcast<i32>(0u) {
                default: {
                    let _e709 = local_105;
                    let _e710 = local_106;
                    let _e713 = vec4<i32>(_e709.x, _e709.y, _e710, 0i);
                    let _e714 = _e713.xyz;
                    let _e721 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e714.x, _e714.y), i32(_e714.z), _e713.w);
                    let _e723 = (_e709.x + 1i);
                    let _e725 = vec2<i32>(_e723, _e709.y);
                    let _e732 = vec2<i32>(_e725.x, (_e725.y + (_e723 >> bitcast<u32>(12i))));
                    let _e737 = vec2<i32>((_e732.x & 4095i), _e732.y);
                    let _e740 = vec4<i32>(_e737.x, _e737.y, _e710, 0i);
                    let _e746 = local_103;
                    let _e752 = (vec4<f32>(_e721.x, _e721.y, _e721.z, _e721.w) - vec4<f32>(_e746.x, _e746.y, _e746.x, _e746.y));
                    local_41 = _e752;
                    let _e753 = _e740.xyz;
                    let _e760 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e753.x, _e753.y), i32(_e753.z), _e740.w);
                    let _e762 = (_e760.xy - _e746);
                    local_42 = _e762;
                    let _e763 = local_104;
                    local_43 = _e763.y;
                    if ((max(max(_e752.y, _e752.w), _e762.y) * _e763.y) < -0.5f) {
                        local_40 = false;
                        break;
                    }
                    let _e772 = local_41;
                    local_45 = _e772.x;
                    local_46 = _e772.z;
                    let _e775 = local_42;
                    local_37 = _e775.x;
                    if (abs(_e775.x) <= 0.000015258789f) {
                        local_36 = 0f;
                    } else {
                        let _e779 = local_37;
                        local_36 = _e779;
                    }
                    let _e780 = local_36;
                    let _e785 = local_46;
                    local_38 = _e785;
                    if (abs(_e785) <= 0.000015258789f) {
                        local_35 = 0f;
                    } else {
                        let _e788 = local_38;
                        local_35 = _e788;
                    }
                    let _e789 = local_35;
                    let _e794 = local_45;
                    local_39 = _e794;
                    if (abs(_e794) <= 0.000015258789f) {
                        local_34 = 0f;
                    } else {
                        let _e797 = local_39;
                        local_34 = _e797;
                    }
                    let _e798 = local_34;
                    let _e808 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e780) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e789) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e798) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                    local_44 = _e808;
                    if (_e808 != 0u) {
                        let _e810 = local_41;
                        local_48 = _e810;
                        let _e811 = local_42;
                        let _e812 = _e810.xy;
                        let _e813 = _e810.zw;
                        let _e816 = ((_e812 - (_e813 * 2f)) + _e811);
                        local_20 = _e816;
                        local_21 = (_e812 - _e813);
                        local_22 = _e816.x;
                        if (abs(_e816.x) < 0.000015258789f) {
                            let _e821 = local_21;
                            local_23 = _e821.x;
                            if (abs(_e821.x) < 0.000015258789f) {
                                local_24 = 0f;
                            } else {
                                let _e825 = local_48;
                                let _e828 = local_23;
                                local_24 = ((_e825.x * 0.5f) / _e828);
                            }
                            let _e830 = local_24;
                            local_25 = _e830;
                        } else {
                            let _e831 = local_21;
                            local_26 = _e831.x;
                            let _e833 = local_48;
                            local_27 = _e833.x;
                            let _e835 = local_22;
                            let _e836 = (_e835 * _e833.x);
                            let _e838 = ((_e831.x * _e831.x) - _e836);
                            local_29 = _e838;
                            if (_e838 <= (max((_e831.x * _e831.x), abs(_e836)) * 0.000003f)) {
                                local_19 = 0f;
                            } else {
                                let _e844 = local_29;
                                local_19 = sqrt(_e844);
                            }
                            let _e846 = local_19;
                            local_28 = _e846;
                            let _e847 = local_26;
                            if (_e847 >= 0f) {
                                let _e849 = local_26;
                                let _e850 = local_28;
                                let _e851 = (_e849 + _e850);
                                local_30 = _e851;
                                let _e852 = local_22;
                                local_31 = (_e851 / _e852);
                                if (abs(_e851) < 0.000015258789f) {
                                    local_24 = 0f;
                                } else {
                                    let _e856 = local_27;
                                    let _e857 = local_30;
                                    local_24 = (_e856 / _e857);
                                }
                                let _e859 = local_31;
                                local_25 = _e859;
                            } else {
                                let _e860 = local_26;
                                let _e861 = local_28;
                                let _e862 = (_e860 - _e861);
                                local_32 = _e862;
                                let _e863 = local_22;
                                local_33 = (_e862 / _e863);
                                if (abs(_e862) < 0.000015258789f) {
                                    local_24 = 0f;
                                } else {
                                    let _e867 = local_27;
                                    let _e868 = local_32;
                                    local_24 = (_e867 / _e868);
                                }
                                let _e870 = local_24;
                                let _e871 = local_33;
                                local_24 = _e871;
                                local_25 = _e870;
                            }
                        }
                        let _e872 = local_20;
                        let _e874 = local_21;
                        let _e876 = (_e874.y * 2f);
                        let _e877 = local_48;
                        let _e879 = local_24;
                        let _e884 = local_25;
                        let _e890 = local_43;
                        local_47 = (vec2<f32>(((((_e872.y * _e879) - _e876) * _e879) + _e877.y), ((((_e872.y * _e884) - _e876) * _e884) + _e877.y)) * _e890);
                        let _e892 = local_44;
                        if ((_e892 & 1u) != 0u) {
                            let _e895 = local_47;
                            let _e897 = local_101;
                            local_101 = (_e897 - clamp((_e895.x + 0.5f), 0f, 1f));
                            let _e901 = local_102;
                            local_102 = max(_e901, clamp((1f - (abs(_e895.x) * 2f)), 0f, 1f));
                        }
                        let _e907 = local_44;
                        if (_e907 > 1u) {
                            let _e909 = local_47;
                            let _e911 = local_101;
                            local_101 = (_e911 + clamp((_e909.y + 0.5f), 0f, 1f));
                            let _e915 = local_102;
                            local_102 = max(_e915, clamp((1f - (abs(_e909.y) * 2f)), 0f, 1f));
                        }
                    }
                    local_40 = true;
                    break;
                }
            }
            let _e921 = local_40;
            let _e922 = local_101;
            local_95 = _e922;
            let _e923 = local_102;
            local_96 = _e923;
            if !(_e921) {
                break;
            }
            let _e925 = local_86;
            local_86 = (_e925 + 1i);
            continue;
        }
        let _e927 = local_83;
        local_83 = (_e927 + 1i);
        continue;
    }
    let _e929 = local_80;
    let _e930 = local_81;
    let _e932 = local_95;
    let _e933 = local_96;
    local_107 = (((_e929 * _e930) + (_e932 * _e933)) / max((_e930 + _e933), 0.000015258789f));
    local_108 = 0i;
    switch bitcast<i32>(0u) {
        default: {
            let _e940 = local_108;
            if (_e940 == 1i) {
                let _e942 = local_107;
                local_18 = (1f - abs(((fract((_e942 * 0.5f)) * 2f) - 1f)));
                break;
            }
            let _e949 = local_107;
            local_18 = abs(_e949);
            break;
        }
    }
    let _e951 = local_18;
    let _e952 = local_80;
    local_109 = _e952;
    local_110 = 0i;
    switch bitcast<i32>(0u) {
        default: {
            let _e954 = local_110;
            if (_e954 == 1i) {
                let _e956 = local_109;
                local_17 = (1f - abs(((fract((_e956 * 0.5f)) * 2f) - 1f)));
                break;
            }
            let _e963 = local_109;
            local_17 = abs(_e963);
            break;
        }
    }
    let _e965 = local_17;
    let _e966 = local_95;
    local_111 = _e966;
    local_112 = 0i;
    switch bitcast<i32>(0u) {
        default: {
            let _e968 = local_112;
            if (_e968 == 1i) {
                let _e970 = local_111;
                local_16 = (1f - abs(((fract((_e970 * 0.5f)) * 2f) - 1f)));
                break;
            }
            let _e977 = local_111;
            local_16 = abs(_e977);
            break;
        }
    }
    let _e979 = local_16;
    local_13 = clamp(max(_e951, min(_e965, _e979)), 0f, 1f);
    let _e984 = PushConstants_0_.coverage_exponent_0_;
    let _e985 = max(_e984, 0.000015258789f);
    local_14 = _e985;
    if (abs((_e985 - 1f)) <= 0.000001f) {
        let _e989 = local_13;
        local_15 = _e989;
    } else {
        let _e990 = local_13;
        let _e991 = local_14;
        local_15 = pow(_e990, _e991);
    }
    let _e993 = local_15;
    local_114 = _e993;
    if (_e993 < 0.003921569f) {
        discard;
    }
    let _e995 = v_color_0_1;
    let _e996 = v_tint_0_1;
    let _e997 = (_e995 * _e996);
    let _e998 = local_114;
    let _e1000 = (_e997.w * _e998);
    let _e1002 = (_e997.xyz * _e1000);
    local_119 = vec4<f32>(_e1002.x, _e1002.y, _e1002.z, _e1000);
    let _e1008 = PushConstants_0_.mask_output_0_;
    if (_e1008 != 0i) {
        let _e1010 = local_119;
        local_120 = vec4(_e1010.w);
    } else {
        let _e1014 = PushConstants_0_.output_srgb_0_;
        if (_e1014 != 0i) {
            let _e1016 = local_119;
            local_121 = _e1016;
            switch bitcast<i32>(0u) {
                default: {
                    let _e1018 = local_121;
                    local_11 = _e1018.w;
                    if (_e1018.w <= 0f) {
                        local_10 = vec4<f32>(0f, 0f, 0f, 0f);
                        break;
                    }
                    let _e1021 = local_121;
                    let _e1023 = local_11;
                    let _e1025 = (_e1021.xyz * (1f / _e1023));
                    local_12 = _e1025;
                    let _e1027 = max(_e1025.x, 0f);
                    local_7 = _e1027;
                    if (_e1027 <= 0.0031308f) {
                        let _e1029 = local_7;
                        local_6 = (_e1029 * 12.92f);
                    } else {
                        let _e1031 = local_7;
                        local_6 = ((1.055f * pow(_e1031, 0.41666666f)) - 0.055f);
                    }
                    let _e1035 = local_6;
                    let _e1036 = local_12;
                    let _e1038 = max(_e1036.y, 0f);
                    local_8 = _e1038;
                    if (_e1038 <= 0.0031308f) {
                        let _e1040 = local_8;
                        local_5 = (_e1040 * 12.92f);
                    } else {
                        let _e1042 = local_8;
                        local_5 = ((1.055f * pow(_e1042, 0.41666666f)) - 0.055f);
                    }
                    let _e1046 = local_5;
                    let _e1047 = local_12;
                    let _e1049 = max(_e1047.z, 0f);
                    local_9 = _e1049;
                    if (_e1049 <= 0.0031308f) {
                        let _e1051 = local_9;
                        local_4 = (_e1051 * 12.92f);
                    } else {
                        let _e1053 = local_9;
                        local_4 = ((1.055f * pow(_e1053, 0.41666666f)) - 0.055f);
                    }
                    let _e1057 = local_4;
                    let _e1059 = local_11;
                    let _e1060 = (vec3<f32>(_e1035, _e1046, _e1057) * _e1059);
                    local_10 = vec4<f32>(_e1060.x, _e1060.y, _e1060.z, _e1059);
                    break;
                }
            }
            let _e1065 = local_10;
            local_120 = _e1065;
        } else {
            let _e1066 = local_119;
            local_120 = _e1066;
        }
    }
    let _e1067 = local_120;
    _S63_ = _e1067;
    let _e1068 = _S63_;
    entryPointParam_main_frag_color_0_ = _e1068;
    return;
}

@fragment 
fn main(@location(3) @interpolate(flat) v_glyph_0_: vec4<i32>, @location(1) v_texcoord_0_: vec2<f32>, @location(2) @interpolate(flat) v_banding_0_: vec4<f32>, @location(0) v_color_0_: vec4<f32>, @location(4) v_tint_0_: vec4<f32>) -> @location(0) vec4<f32> {
    v_glyph_0_1 = v_glyph_0_;
    v_texcoord_0_1 = v_texcoord_0_;
    v_banding_0_1 = v_banding_0_;
    v_color_0_1 = v_color_0_;
    v_tint_0_1 = v_tint_0_;
    main_1();
    let _e11 = entryPointParam_main_frag_color_0_;
    return _e11;
}
