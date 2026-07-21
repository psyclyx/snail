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

@group(1) @binding(2) 
var u_layer_tex_0_sampler: sampler;
@group(0) @binding(2) 
var u_layer_tex_0_image: texture_2d<f32>;
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
    var _S65_: vec4<f32>;
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
    var local_113: vec2<i32>;
    var local_114: f32;
    var local_115: vec2<f32>;
    var local_116: vec2<f32>;
    var local_117: vec2<i32>;
    var local_118: i32;
    var local_119: vec4<f32>;
    var local_120: vec4<f32>;
    var local_121: vec4<f32>;

    let _e183 = v_glyph_0_1[3u];
    if (((_e183 >> bitcast<u32>(8i)) & 255i) != 255i) {
        discard;
    }
    let _e189 = v_glyph_0_1[3u];
    if ((_e189 & 255i) != 2i) {
        discard;
    }
    let _e192 = v_texcoord_0_1;
    let _e193 = fwidth(_e192);
    let _e201 = v_glyph_0_1;
    let _e202 = _e201.xy;
    let _e205 = vec3<i32>(_e202.x, _e202.y, 0i);
    let _e208 = textureLoad(u_layer_tex_0_image, _e205.xy, _e205.z);
    let _e209 = textureDimensions(u_layer_tex_0_image, 0i);
    let _e212 = local_113;
    let _e215 = vec2<i32>(vec2<i32>(_e209).x, _e212.y);
    let _e216 = textureDimensions(u_layer_tex_0_image, 0i);
    let _e221 = vec2<i32>(_e215.x, vec2<i32>(_e216).y);
    local_113 = _e221;
    let _e227 = (((_e202.y * _e221.x) + _e202.x) + 1i);
    let _e236 = vec2<i32>((_e227 - (i32(floor((f32(_e227) / f32(_e221.x)))) * _e221.x)), (_e227 / _e221.x));
    let _e239 = vec3<i32>(_e236.x, _e236.y, 0i);
    let _e241 = bitcast<i32>(_e208.z);
    let _e248 = vec2<i32>(((_e241 >> bitcast<u32>(16i)) & 65535i), (_e241 & 65535i));
    let _e251 = textureLoad(u_layer_tex_0_image, _e239.xy, _e239.z);
    let _e253 = PushConstants_0_.layer_base_0_;
    let _e255 = v_banding_0_1[3u];
    let _e258 = v_texcoord_0_1;
    local_115 = _e258;
    local_116 = vec2<f32>((1f / max(_e193.x, 0.000015258789f)), (1f / max(_e193.y, 0.000015258789f)));
    local_117 = vec2<i32>(_e208.xy);
    local_118 = (_e253 + i32(_e255));
    local_79 = _e248.y;
    let _e265 = ((_e258.y * _e251.y) + _e251.w);
    let _e269 = max((abs((_e193.y * _e251.y)) * 0.5f), 0.00001f);
    let _e272 = clamp(i32((_e265 - _e269)), 0i, _e248.y);
    let _e276 = max(_e272, clamp(i32((_e265 + _e269)), 0i, _e248.y));
    local_3 = _e272;
    local_2 = _e276;
    let _e283 = ((_e258.x * _e251.x) + _e251.z);
    let _e287 = max((abs((_e193.x * _e251.x)) * 0.5f), 0.00001f);
    let _e290 = clamp(i32((_e283 - _e287)), 0i, _e248.x);
    local_1 = _e290;
    local = max(_e290, clamp(i32((_e283 + _e287)), 0i, _e248.x));
    local_80 = 0f;
    local_81 = 0f;
    local_82 = (_e272 != _e276);
    local_83 = _e272;
    loop {
        let _e296 = local_83;
        let _e297 = local_2;
        if (_e296 <= _e297) {
        } else {
            break;
        }
        let _e299 = local_83;
        let _e301 = local_117;
        let _e304 = (_e301.x + bitcast<i32>(bitcast<u32>(_e299)));
        let _e306 = vec2<i32>(_e304, _e301.y);
        let _e313 = vec2<i32>(_e306.x, (_e306.y + (_e304 >> bitcast<u32>(12i))));
        let _e318 = vec2<i32>((_e313.x & 4095i), _e313.y);
        let _e319 = local_118;
        let _e322 = vec4<i32>(_e318.x, _e318.y, _e319, 0i);
        let _e323 = _e322.xyz;
        let _e330 = textureLoad(u_band_tex_0_image, vec2<i32>(_e323.x, _e323.y), i32(_e323.z), _e322.w);
        let _e331 = _e330.xy;
        let _e335 = (_e301.x + bitcast<i32>(_e331.y));
        let _e337 = vec2<i32>(_e335, _e301.y);
        let _e344 = vec2<i32>(_e337.x, (_e337.y + (_e335 >> bitcast<u32>(12i))));
        local_84 = vec2<i32>((_e344.x & 4095i), _e344.y);
        local_85 = bitcast<i32>(_e331.x);
        local_86 = 0i;
        loop {
            let _e352 = local_86;
            let _e353 = local_85;
            if (_e352 < _e353) {
            } else {
                break;
            }
            let _e355 = local_86;
            let _e357 = local_84;
            let _e360 = (_e357.x + bitcast<i32>(bitcast<u32>(_e355)));
            let _e362 = vec2<i32>(_e360, _e357.y);
            let _e369 = vec2<i32>(_e362.x, (_e362.y + (_e360 >> bitcast<u32>(12i))));
            let _e374 = vec2<i32>((_e369.x & 4095i), _e369.y);
            let _e375 = local_118;
            let _e378 = vec4<i32>(_e374.x, _e374.y, _e375, 0i);
            let _e379 = _e378.xyz;
            let _e386 = textureLoad(u_band_tex_0_image, vec2<i32>(_e379.x, _e379.y), i32(_e379.z), _e378.w);
            local_87 = _e386.xy;
            let _e388 = local_82;
            if _e388 {
                let _e389 = local_87;
                let _e390 = local_83;
                let _e391 = local_3;
                local_88 = !((_e390 == max(bitcast<i32>((_e389.x >> bitcast<u32>(12u))), _e391)));
            } else {
                local_88 = false;
            }
            let _e399 = local_88;
            if _e399 {
                let _e400 = local_86;
                local_86 = (_e400 + 1i);
                continue;
            }
            let _e402 = local_87;
            let _e410 = local_80;
            local_89 = _e410;
            let _e411 = local_81;
            local_90 = _e411;
            let _e412 = local_115;
            local_91 = _e412;
            let _e413 = local_116;
            local_92 = _e413;
            local_93 = vec2<i32>(bitcast<i32>((_e402.x & 4095u)), bitcast<i32>((_e402.y & 16383u)));
            let _e414 = local_118;
            local_94 = _e414;
            switch bitcast<i32>(0u) {
                default: {
                    let _e416 = local_93;
                    let _e417 = local_94;
                    let _e420 = vec4<i32>(_e416.x, _e416.y, _e417, 0i);
                    let _e421 = _e420.xyz;
                    let _e428 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e421.x, _e421.y), i32(_e421.z), _e420.w);
                    let _e430 = (_e416.x + 1i);
                    let _e432 = vec2<i32>(_e430, _e416.y);
                    let _e439 = vec2<i32>(_e432.x, (_e432.y + (_e430 >> bitcast<u32>(12i))));
                    let _e444 = vec2<i32>((_e439.x & 4095i), _e439.y);
                    let _e447 = vec4<i32>(_e444.x, _e444.y, _e417, 0i);
                    let _e453 = local_91;
                    let _e459 = (vec4<f32>(_e428.x, _e428.y, _e428.z, _e428.w) - vec4<f32>(_e453.x, _e453.y, _e453.x, _e453.y));
                    local_71 = _e459;
                    let _e460 = _e447.xyz;
                    let _e467 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e460.x, _e460.y), i32(_e460.z), _e447.w);
                    let _e469 = (_e467.xy - _e453);
                    local_72 = _e469;
                    let _e470 = local_92;
                    local_73 = _e470.x;
                    if ((max(max(_e459.x, _e459.z), _e469.x) * _e470.x) < -0.5f) {
                        local_70 = false;
                        break;
                    }
                    let _e479 = local_71;
                    local_75 = _e479.y;
                    local_76 = _e479.w;
                    let _e482 = local_72;
                    local_67 = _e482.y;
                    if (abs(_e482.y) <= 0.000015258789f) {
                        local_66 = 0f;
                    } else {
                        let _e486 = local_67;
                        local_66 = _e486;
                    }
                    let _e487 = local_66;
                    let _e492 = local_76;
                    local_68 = _e492;
                    if (abs(_e492) <= 0.000015258789f) {
                        local_65 = 0f;
                    } else {
                        let _e495 = local_68;
                        local_65 = _e495;
                    }
                    let _e496 = local_65;
                    let _e501 = local_75;
                    local_69 = _e501;
                    if (abs(_e501) <= 0.000015258789f) {
                        local_64 = 0f;
                    } else {
                        let _e504 = local_69;
                        local_64 = _e504;
                    }
                    let _e505 = local_64;
                    let _e515 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e487) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e496) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e505) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                    local_74 = _e515;
                    if (_e515 != 0u) {
                        let _e517 = local_71;
                        local_78 = _e517;
                        let _e518 = local_72;
                        let _e519 = _e517.xy;
                        let _e520 = _e517.zw;
                        let _e523 = ((_e519 - (_e520 * 2f)) + _e518);
                        local_50 = _e523;
                        local_51 = (_e519 - _e520);
                        local_52 = _e523.y;
                        if (abs(_e523.y) < 0.000015258789f) {
                            let _e528 = local_51;
                            local_53 = _e528.y;
                            if (abs(_e528.y) < 0.000015258789f) {
                                local_54 = 0f;
                            } else {
                                let _e532 = local_78;
                                let _e535 = local_53;
                                local_54 = ((_e532.y * 0.5f) / _e535);
                            }
                            let _e537 = local_54;
                            local_55 = _e537;
                        } else {
                            let _e538 = local_51;
                            local_56 = _e538.y;
                            let _e540 = local_78;
                            local_57 = _e540.y;
                            let _e542 = local_52;
                            let _e543 = (_e542 * _e540.y);
                            let _e545 = ((_e538.y * _e538.y) - _e543);
                            local_59 = _e545;
                            if (_e545 <= (max((_e538.y * _e538.y), abs(_e543)) * 0.000003f)) {
                                local_49 = 0f;
                            } else {
                                let _e551 = local_59;
                                local_49 = sqrt(_e551);
                            }
                            let _e553 = local_49;
                            local_58 = _e553;
                            let _e554 = local_56;
                            if (_e554 >= 0f) {
                                let _e556 = local_56;
                                let _e557 = local_58;
                                let _e558 = (_e556 + _e557);
                                local_60 = _e558;
                                let _e559 = local_52;
                                local_61 = (_e558 / _e559);
                                if (abs(_e558) < 0.000015258789f) {
                                    local_54 = 0f;
                                } else {
                                    let _e563 = local_57;
                                    let _e564 = local_60;
                                    local_54 = (_e563 / _e564);
                                }
                                let _e566 = local_61;
                                local_55 = _e566;
                            } else {
                                let _e567 = local_56;
                                let _e568 = local_58;
                                let _e569 = (_e567 - _e568);
                                local_62 = _e569;
                                let _e570 = local_52;
                                local_63 = (_e569 / _e570);
                                if (abs(_e569) < 0.000015258789f) {
                                    local_54 = 0f;
                                } else {
                                    let _e574 = local_57;
                                    let _e575 = local_62;
                                    local_54 = (_e574 / _e575);
                                }
                                let _e577 = local_54;
                                let _e578 = local_63;
                                local_54 = _e578;
                                local_55 = _e577;
                            }
                        }
                        let _e579 = local_50;
                        let _e581 = local_51;
                        let _e583 = (_e581.x * 2f);
                        let _e584 = local_78;
                        let _e586 = local_54;
                        let _e591 = local_55;
                        let _e597 = local_73;
                        local_77 = (vec2<f32>(((((_e579.x * _e586) - _e583) * _e586) + _e584.x), ((((_e579.x * _e591) - _e583) * _e591) + _e584.x)) * _e597);
                        let _e599 = local_74;
                        if ((_e599 & 1u) != 0u) {
                            let _e602 = local_77;
                            let _e604 = local_89;
                            local_89 = (_e604 + clamp((_e602.x + 0.5f), 0f, 1f));
                            let _e608 = local_90;
                            local_90 = max(_e608, clamp((1f - (abs(_e602.x) * 2f)), 0f, 1f));
                        }
                        let _e614 = local_74;
                        if (_e614 > 1u) {
                            let _e616 = local_77;
                            let _e618 = local_89;
                            local_89 = (_e618 - clamp((_e616.y + 0.5f), 0f, 1f));
                            let _e622 = local_90;
                            local_90 = max(_e622, clamp((1f - (abs(_e616.y) * 2f)), 0f, 1f));
                        }
                    }
                    local_70 = true;
                    break;
                }
            }
            let _e628 = local_70;
            let _e629 = local_89;
            local_80 = _e629;
            let _e630 = local_90;
            local_81 = _e630;
            if !(_e628) {
                break;
            }
            let _e632 = local_86;
            local_86 = (_e632 + 1i);
            continue;
        }
        let _e634 = local_83;
        local_83 = (_e634 + 1i);
        continue;
    }
    local_95 = 0f;
    local_96 = 0f;
    let _e636 = local_1;
    let _e637 = local;
    local_97 = (_e636 != _e637);
    local_83 = _e636;
    loop {
        let _e639 = local_83;
        let _e640 = local;
        if (_e639 <= _e640) {
        } else {
            break;
        }
        let _e642 = local_79;
        let _e644 = local_83;
        let _e647 = local_117;
        let _e650 = (_e647.x + bitcast<i32>(bitcast<u32>(((_e642 + 1i) + _e644))));
        let _e652 = vec2<i32>(_e650, _e647.y);
        let _e659 = vec2<i32>(_e652.x, (_e652.y + (_e650 >> bitcast<u32>(12i))));
        let _e664 = vec2<i32>((_e659.x & 4095i), _e659.y);
        let _e665 = local_118;
        let _e668 = vec4<i32>(_e664.x, _e664.y, _e665, 0i);
        let _e669 = _e668.xyz;
        let _e676 = textureLoad(u_band_tex_0_image, vec2<i32>(_e669.x, _e669.y), i32(_e669.z), _e668.w);
        let _e677 = _e676.xy;
        let _e681 = (_e647.x + bitcast<i32>(_e677.y));
        let _e683 = vec2<i32>(_e681, _e647.y);
        let _e690 = vec2<i32>(_e683.x, (_e683.y + (_e681 >> bitcast<u32>(12i))));
        local_98 = vec2<i32>((_e690.x & 4095i), _e690.y);
        local_99 = bitcast<i32>(_e677.x);
        local_86 = 0i;
        loop {
            let _e698 = local_86;
            let _e699 = local_99;
            if (_e698 < _e699) {
            } else {
                break;
            }
            let _e701 = local_86;
            let _e703 = local_98;
            let _e706 = (_e703.x + bitcast<i32>(bitcast<u32>(_e701)));
            let _e708 = vec2<i32>(_e706, _e703.y);
            let _e715 = vec2<i32>(_e708.x, (_e708.y + (_e706 >> bitcast<u32>(12i))));
            let _e720 = vec2<i32>((_e715.x & 4095i), _e715.y);
            let _e721 = local_118;
            let _e724 = vec4<i32>(_e720.x, _e720.y, _e721, 0i);
            let _e725 = _e724.xyz;
            let _e732 = textureLoad(u_band_tex_0_image, vec2<i32>(_e725.x, _e725.y), i32(_e725.z), _e724.w);
            local_100 = _e732.xy;
            let _e734 = local_97;
            if _e734 {
                let _e735 = local_100;
                let _e736 = local_83;
                let _e737 = local_1;
                local_88 = !((_e736 == max(bitcast<i32>((_e735.x >> bitcast<u32>(12u))), _e737)));
            } else {
                local_88 = false;
            }
            let _e745 = local_88;
            if _e745 {
                let _e746 = local_86;
                local_86 = (_e746 + 1i);
                continue;
            }
            let _e748 = local_100;
            let _e756 = local_95;
            local_101 = _e756;
            let _e757 = local_96;
            local_102 = _e757;
            let _e758 = local_115;
            local_103 = _e758;
            let _e759 = local_116;
            local_104 = _e759;
            local_105 = vec2<i32>(bitcast<i32>((_e748.x & 4095u)), bitcast<i32>((_e748.y & 16383u)));
            let _e760 = local_118;
            local_106 = _e760;
            switch bitcast<i32>(0u) {
                default: {
                    let _e762 = local_105;
                    let _e763 = local_106;
                    let _e766 = vec4<i32>(_e762.x, _e762.y, _e763, 0i);
                    let _e767 = _e766.xyz;
                    let _e774 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e767.x, _e767.y), i32(_e767.z), _e766.w);
                    let _e776 = (_e762.x + 1i);
                    let _e778 = vec2<i32>(_e776, _e762.y);
                    let _e785 = vec2<i32>(_e778.x, (_e778.y + (_e776 >> bitcast<u32>(12i))));
                    let _e790 = vec2<i32>((_e785.x & 4095i), _e785.y);
                    let _e793 = vec4<i32>(_e790.x, _e790.y, _e763, 0i);
                    let _e799 = local_103;
                    let _e805 = (vec4<f32>(_e774.x, _e774.y, _e774.z, _e774.w) - vec4<f32>(_e799.x, _e799.y, _e799.x, _e799.y));
                    local_41 = _e805;
                    let _e806 = _e793.xyz;
                    let _e813 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e806.x, _e806.y), i32(_e806.z), _e793.w);
                    let _e815 = (_e813.xy - _e799);
                    local_42 = _e815;
                    let _e816 = local_104;
                    local_43 = _e816.y;
                    if ((max(max(_e805.y, _e805.w), _e815.y) * _e816.y) < -0.5f) {
                        local_40 = false;
                        break;
                    }
                    let _e825 = local_41;
                    local_45 = _e825.x;
                    local_46 = _e825.z;
                    let _e828 = local_42;
                    local_37 = _e828.x;
                    if (abs(_e828.x) <= 0.000015258789f) {
                        local_36 = 0f;
                    } else {
                        let _e832 = local_37;
                        local_36 = _e832;
                    }
                    let _e833 = local_36;
                    let _e838 = local_46;
                    local_38 = _e838;
                    if (abs(_e838) <= 0.000015258789f) {
                        local_35 = 0f;
                    } else {
                        let _e841 = local_38;
                        local_35 = _e841;
                    }
                    let _e842 = local_35;
                    let _e847 = local_45;
                    local_39 = _e847;
                    if (abs(_e847) <= 0.000015258789f) {
                        local_34 = 0f;
                    } else {
                        let _e850 = local_39;
                        local_34 = _e850;
                    }
                    let _e851 = local_34;
                    let _e861 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e833) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e842) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e851) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                    local_44 = _e861;
                    if (_e861 != 0u) {
                        let _e863 = local_41;
                        local_48 = _e863;
                        let _e864 = local_42;
                        let _e865 = _e863.xy;
                        let _e866 = _e863.zw;
                        let _e869 = ((_e865 - (_e866 * 2f)) + _e864);
                        local_20 = _e869;
                        local_21 = (_e865 - _e866);
                        local_22 = _e869.x;
                        if (abs(_e869.x) < 0.000015258789f) {
                            let _e874 = local_21;
                            local_23 = _e874.x;
                            if (abs(_e874.x) < 0.000015258789f) {
                                local_24 = 0f;
                            } else {
                                let _e878 = local_48;
                                let _e881 = local_23;
                                local_24 = ((_e878.x * 0.5f) / _e881);
                            }
                            let _e883 = local_24;
                            local_25 = _e883;
                        } else {
                            let _e884 = local_21;
                            local_26 = _e884.x;
                            let _e886 = local_48;
                            local_27 = _e886.x;
                            let _e888 = local_22;
                            let _e889 = (_e888 * _e886.x);
                            let _e891 = ((_e884.x * _e884.x) - _e889);
                            local_29 = _e891;
                            if (_e891 <= (max((_e884.x * _e884.x), abs(_e889)) * 0.000003f)) {
                                local_19 = 0f;
                            } else {
                                let _e897 = local_29;
                                local_19 = sqrt(_e897);
                            }
                            let _e899 = local_19;
                            local_28 = _e899;
                            let _e900 = local_26;
                            if (_e900 >= 0f) {
                                let _e902 = local_26;
                                let _e903 = local_28;
                                let _e904 = (_e902 + _e903);
                                local_30 = _e904;
                                let _e905 = local_22;
                                local_31 = (_e904 / _e905);
                                if (abs(_e904) < 0.000015258789f) {
                                    local_24 = 0f;
                                } else {
                                    let _e909 = local_27;
                                    let _e910 = local_30;
                                    local_24 = (_e909 / _e910);
                                }
                                let _e912 = local_31;
                                local_25 = _e912;
                            } else {
                                let _e913 = local_26;
                                let _e914 = local_28;
                                let _e915 = (_e913 - _e914);
                                local_32 = _e915;
                                let _e916 = local_22;
                                local_33 = (_e915 / _e916);
                                if (abs(_e915) < 0.000015258789f) {
                                    local_24 = 0f;
                                } else {
                                    let _e920 = local_27;
                                    let _e921 = local_32;
                                    local_24 = (_e920 / _e921);
                                }
                                let _e923 = local_24;
                                let _e924 = local_33;
                                local_24 = _e924;
                                local_25 = _e923;
                            }
                        }
                        let _e925 = local_20;
                        let _e927 = local_21;
                        let _e929 = (_e927.y * 2f);
                        let _e930 = local_48;
                        let _e932 = local_24;
                        let _e937 = local_25;
                        let _e943 = local_43;
                        local_47 = (vec2<f32>(((((_e925.y * _e932) - _e929) * _e932) + _e930.y), ((((_e925.y * _e937) - _e929) * _e937) + _e930.y)) * _e943);
                        let _e945 = local_44;
                        if ((_e945 & 1u) != 0u) {
                            let _e948 = local_47;
                            let _e950 = local_101;
                            local_101 = (_e950 - clamp((_e948.x + 0.5f), 0f, 1f));
                            let _e954 = local_102;
                            local_102 = max(_e954, clamp((1f - (abs(_e948.x) * 2f)), 0f, 1f));
                        }
                        let _e960 = local_44;
                        if (_e960 > 1u) {
                            let _e962 = local_47;
                            let _e964 = local_101;
                            local_101 = (_e964 + clamp((_e962.y + 0.5f), 0f, 1f));
                            let _e968 = local_102;
                            local_102 = max(_e968, clamp((1f - (abs(_e962.y) * 2f)), 0f, 1f));
                        }
                    }
                    local_40 = true;
                    break;
                }
            }
            let _e974 = local_40;
            let _e975 = local_101;
            local_95 = _e975;
            let _e976 = local_102;
            local_96 = _e976;
            if !(_e974) {
                break;
            }
            let _e978 = local_86;
            local_86 = (_e978 + 1i);
            continue;
        }
        let _e980 = local_83;
        local_83 = (_e980 + 1i);
        continue;
    }
    let _e982 = local_80;
    let _e983 = local_81;
    let _e985 = local_95;
    let _e986 = local_96;
    local_107 = (((_e982 * _e983) + (_e985 * _e986)) / max((_e983 + _e986), 0.000015258789f));
    local_108 = 0i;
    switch bitcast<i32>(0u) {
        default: {
            let _e993 = local_108;
            if (_e993 == 1i) {
                let _e995 = local_107;
                local_18 = (1f - abs(((fract((_e995 * 0.5f)) * 2f) - 1f)));
                break;
            }
            let _e1002 = local_107;
            local_18 = abs(_e1002);
            break;
        }
    }
    let _e1004 = local_18;
    let _e1005 = local_80;
    local_109 = _e1005;
    local_110 = 0i;
    switch bitcast<i32>(0u) {
        default: {
            let _e1007 = local_110;
            if (_e1007 == 1i) {
                let _e1009 = local_109;
                local_17 = (1f - abs(((fract((_e1009 * 0.5f)) * 2f) - 1f)));
                break;
            }
            let _e1016 = local_109;
            local_17 = abs(_e1016);
            break;
        }
    }
    let _e1018 = local_17;
    let _e1019 = local_95;
    local_111 = _e1019;
    local_112 = 0i;
    switch bitcast<i32>(0u) {
        default: {
            let _e1021 = local_112;
            if (_e1021 == 1i) {
                let _e1023 = local_111;
                local_16 = (1f - abs(((fract((_e1023 * 0.5f)) * 2f) - 1f)));
                break;
            }
            let _e1030 = local_111;
            local_16 = abs(_e1030);
            break;
        }
    }
    let _e1032 = local_16;
    local_13 = clamp(max(_e1004, min(_e1018, _e1032)), 0f, 1f);
    let _e1037 = PushConstants_0_.coverage_exponent_0_;
    let _e1038 = max(_e1037, 0.000015258789f);
    local_14 = _e1038;
    if (abs((_e1038 - 1f)) <= 0.000001f) {
        let _e1042 = local_13;
        local_15 = _e1042;
    } else {
        let _e1043 = local_13;
        let _e1044 = local_14;
        local_15 = pow(_e1043, _e1044);
    }
    let _e1046 = local_15;
    local_114 = _e1046;
    if (_e1046 < 0.003921569f) {
        discard;
    }
    let _e1048 = v_color_0_1;
    let _e1049 = v_tint_0_1;
    let _e1050 = (_e1048 * _e1049);
    let _e1051 = local_114;
    let _e1053 = (_e1050.w * _e1051);
    let _e1055 = (_e1050.xyz * _e1053);
    local_119 = vec4<f32>(_e1055.x, _e1055.y, _e1055.z, _e1053);
    let _e1061 = PushConstants_0_.mask_output_0_;
    if (_e1061 != 0i) {
        let _e1063 = local_119;
        local_120 = vec4(_e1063.w);
    } else {
        let _e1067 = PushConstants_0_.output_srgb_0_;
        if (_e1067 != 0i) {
            let _e1069 = local_119;
            local_121 = _e1069;
            switch bitcast<i32>(0u) {
                default: {
                    let _e1071 = local_121;
                    local_11 = _e1071.w;
                    if (_e1071.w <= 0f) {
                        local_10 = vec4<f32>(0f, 0f, 0f, 0f);
                        break;
                    }
                    let _e1074 = local_121;
                    let _e1076 = local_11;
                    let _e1078 = (_e1074.xyz * (1f / _e1076));
                    local_12 = _e1078;
                    let _e1080 = max(_e1078.x, 0f);
                    local_7 = _e1080;
                    if (_e1080 <= 0.0031308f) {
                        let _e1082 = local_7;
                        local_6 = (_e1082 * 12.92f);
                    } else {
                        let _e1084 = local_7;
                        local_6 = ((1.055f * pow(_e1084, 0.41666666f)) - 0.055f);
                    }
                    let _e1088 = local_6;
                    let _e1089 = local_12;
                    let _e1091 = max(_e1089.y, 0f);
                    local_8 = _e1091;
                    if (_e1091 <= 0.0031308f) {
                        let _e1093 = local_8;
                        local_5 = (_e1093 * 12.92f);
                    } else {
                        let _e1095 = local_8;
                        local_5 = ((1.055f * pow(_e1095, 0.41666666f)) - 0.055f);
                    }
                    let _e1099 = local_5;
                    let _e1100 = local_12;
                    let _e1102 = max(_e1100.z, 0f);
                    local_9 = _e1102;
                    if (_e1102 <= 0.0031308f) {
                        let _e1104 = local_9;
                        local_4 = (_e1104 * 12.92f);
                    } else {
                        let _e1106 = local_9;
                        local_4 = ((1.055f * pow(_e1106, 0.41666666f)) - 0.055f);
                    }
                    let _e1110 = local_4;
                    let _e1112 = local_11;
                    let _e1113 = (vec3<f32>(_e1088, _e1099, _e1110) * _e1112);
                    local_10 = vec4<f32>(_e1113.x, _e1113.y, _e1113.z, _e1112);
                    break;
                }
            }
            let _e1118 = local_10;
            local_120 = _e1118;
        } else {
            let _e1119 = local_119;
            local_120 = _e1119;
        }
    }
    let _e1120 = local_120;
    _S65_ = _e1120;
    let _e1121 = _S65_;
    entryPointParam_main_frag_color_0_ = _e1121;
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
