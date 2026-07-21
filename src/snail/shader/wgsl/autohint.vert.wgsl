struct block_SLANG_ParameterGroup_PushConstants_0_ {
    mvp_0_: mat4x4<f32>,
    viewport_0_: vec2<f32>,
    subpixel_order_0_: i32,
}

struct gl_PerVertex {
    @builtin(position) gl_Position: vec4<f32>,
    gl_PointSize: f32,
    gl_ClipDistance: array<f32, 1>,
    gl_CullDistance: array<f32, 1>,
}

struct VertexOutput {
    @location(2) @interpolate(flat) member: vec2<i32>,
    @location(3) @interpolate(flat) member_1: vec4<u32>,
    @location(4) @interpolate(flat) member_2: vec3<u32>,
    @location(1) member_3: vec3<f32>,
    @location(0) member_4: vec4<f32>,
    @builtin(position) gl_Position: vec4<f32>,
    @location(13) @interpolate(flat) member_5: vec4<u32>,
    @location(14) @interpolate(flat) member_6: vec4<u32>,
    @location(5) @interpolate(flat) member_7: vec4<f32>,
    @location(6) @interpolate(flat) member_8: vec4<f32>,
    @location(7) @interpolate(flat) member_9: vec4<f32>,
    @location(8) @interpolate(flat) member_10: vec4<f32>,
    @location(9) @interpolate(flat) member_11: vec4<f32>,
    @location(10) @interpolate(flat) member_12: vec4<f32>,
    @location(11) @interpolate(flat) member_13: vec4<f32>,
    @location(12) @interpolate(flat) member_14: vec4<f32>,
}

var<private> gl_VertexIndex_1: i32;
@group(2) @binding(0) 
var<uniform> PushConstants_0_: block_SLANG_ParameterGroup_PushConstants_0_;
var<private> a_rect_0_1: vec4<f32>;
var<private> a_xform_0_1: vec4<f32>;
var<private> a_origin_0_1: vec2<f32>;
var<private> a_glyph_0_1: vec2<u32>;
var<private> a_policy0_0_1: vec4<u32>;
var<private> a_policy1_0_1: vec3<u32>;
var<private> a_bnd_0_1: vec4<f32>;
var<private> a_col_0_1: vec4<f32>;
var<private> a_tint_0_1: vec4<f32>;
@group(1) @binding(2) 
var u_layer_tex_0_sampler: sampler;
@group(0) @binding(2) 
var u_layer_tex_0_image: texture_2d<f32>;
var<private> entryPointParam_main_v_info_0_: vec2<i32>;
var<private> entryPointParam_main_v_policy0_0_: vec4<u32>;
var<private> entryPointParam_main_v_policy1_0_: vec3<u32>;
var<private> entryPointParam_main_v_texcoord_layer_0_: vec3<f32>;
var<private> entryPointParam_main_v_paint_0_: vec4<f32>;
var<private> unnamed: gl_PerVertex = gl_PerVertex(vec4<f32>(0f, 0f, 0f, 1f), 1f, array<f32, 1>(), array<f32, 1>());
var<private> entryPointParam_main_v_ah_x_sources_0_: vec4<u32>;
var<private> entryPointParam_main_v_ah_y_sources_0_: vec4<u32>;
var<private> entryPointParam_main_v_ah_x_targets0_0_: vec4<f32>;
var<private> entryPointParam_main_v_ah_x_targets1_0_: vec4<f32>;
var<private> entryPointParam_main_v_ah_x_targets2_0_: vec4<f32>;
var<private> entryPointParam_main_v_ah_x_targets3_0_: vec4<f32>;
var<private> entryPointParam_main_v_ah_y_targets0_0_: vec4<f32>;
var<private> entryPointParam_main_v_ah_y_targets1_0_: vec4<f32>;
var<private> entryPointParam_main_v_ah_y_targets2_0_: vec4<f32>;
var<private> entryPointParam_main_v_ah_y_targets3_0_: vec4<f32>;

fn main_1() {
    var local: f32;
    var local_1: f32;
    var local_2: f32;
    var local_3: f32;
    var local_4: f32;
    var local_5: f32;
    var local_6: f32;
    var local_7: i32;
    var local_8: i32;
    var local_9: i32;
    var local_10: i32;
    var local_11: i32;
    var local_12: i32;
    var local_13: i32;
    var local_14: i32;
    var local_15: i32;
    var local_16: i32;
    var local_17: i32;
    var local_18: i32;
    var local_19: i32;
    var local_20: i32;
    var local_21: i32;
    var local_22: i32;
    var local_23: i32;
    var local_24: i32;
    var local_25: i32;
    var local_26: i32;
    var local_27: i32;
    var local_28: i32;
    var local_29: i32;
    var local_30: i32;
    var local_31: f32;
    var local_32: f32;
    var local_33: f32;
    var local_34: f32;
    var local_35: f32;
    var local_36: f32;
    var local_37: f32;
    var local_38: f32;
    var local_39: f32;
    var local_40: f32;
    var local_41: f32;
    var local_42: f32;
    var local_43: f32;
    var local_44: f32;
    var local_45: f32;
    var local_46: f32;
    var local_47: f32;
    var local_48: f32;
    var local_49: f32;
    var local_50: f32;
    var local_51: f32;
    var local_52: f32;
    var local_53: f32;
    var local_54: i32;
    var local_55: i32;
    var local_56: i32;
    var local_57: i32;
    var local_58: i32;
    var local_59: i32;
    var local_60: i32;
    var local_61: i32;
    var local_62: i32;
    var local_63: i32;
    var local_64: i32;
    var local_65: i32;
    var local_66: i32;
    var local_67: i32;
    var local_68: i32;
    var local_69: i32;
    var local_70: i32;
    var local_71: i32;
    var local_72: i32;
    var local_73: i32;
    var local_74: i32;
    var local_75: i32;
    var local_76: i32;
    var local_77: i32;
    var local_78: f32;
    var local_79: f32;
    var local_80: f32;
    var local_81: f32;
    var local_82: f32;
    var local_83: f32;
    var local_84: f32;
    var local_85: f32;
    var local_86: f32;
    var local_87: f32;
    var local_88: f32;
    var local_89: f32;
    var local_90: f32;
    var local_91: f32;
    var local_92: f32;
    var local_93: f32;
    var local_94: f32;
    var local_95: f32;
    var local_96: f32;
    var local_97: f32;
    var local_98: f32;
    var local_99: f32;
    var local_100: f32;
    var local_101: i32;
    var local_102: i32;
    var local_103: i32;
    var local_104: i32;
    var local_105: i32;
    var local_106: i32;
    var local_107: i32;
    var local_108: i32;
    var local_109: f32;
    var local_110: f32;
    var local_111: f32;
    var local_112: f32;
    var local_113: f32;
    var local_114: f32;
    var local_115: f32;
    var local_116: i32;
    var local_117: i32;
    var local_118: i32;
    var local_119: i32;
    var local_120: i32;
    var local_121: i32;
    var local_122: i32;
    var local_123: i32;
    var _S27_: vec4<u32>;
    var _S26_: vec4<u32>;
    var v_ah_y_targets_0_: array<vec4<f32>, 4>;
    var v_ah_x_targets_0_: array<vec4<f32>, 4>;
    var snailAhVertexInfoBase_0_: vec2<i32>;
    var _S8_: vec4<f32>;
    var _S6_: vec4<f32>;
    var _S4_: vec3<f32>;
    var _S3_: vec3<u32>;
    var _S2_: vec4<u32>;
    var _S1_: vec2<i32>;
    var local_124: i32;
    var local_125: i32;
    var local_126: i32;
    var local_127: i32;
    var local_128: bool;
    var local_129: f32;
    var local_130: vec2<i32>;
    var local_131: vec4<f32>;
    var local_132: i32;
    var local_133: f32;
    var local_134: vec2<i32>;
    var local_135: vec4<f32>;
    var local_136: i32;
    var local_137: f32;
    var local_138: vec2<i32>;
    var local_139: vec4<f32>;
    var local_140: i32;
    var local_141: f32;
    var local_142: vec2<i32>;
    var local_143: vec4<f32>;
    var local_144: i32;
    var local_145: f32;
    var local_146: vec2<i32>;
    var local_147: vec4<f32>;
    var local_148: i32;
    var local_149: f32;
    var local_150: vec2<i32>;
    var local_151: vec4<f32>;
    var local_152: i32;
    var local_153: f32;
    var local_154: vec2<i32>;
    var local_155: vec4<f32>;
    var local_156: i32;
    var local_157: f32;
    var local_158: vec2<i32>;
    var local_159: vec4<f32>;
    var local_160: i32;
    var local_161: f32;
    var local_162: vec2<i32>;
    var local_163: vec4<f32>;
    var local_164: i32;
    var local_165: f32;
    var local_166: bool = false;
    var local_167: bool;
    var local_168: bool;
    var local_169: bool;
    var local_170: i32;
    var local_171: bool;
    var local_172: bool;
    var local_173: i32;
    var local_174: i32;
    var local_175: array<f32, 16>;
    var local_176: array<f32, 16>;
    var local_177: array<i32, 16>;
    var local_178: array<i32, 16>;
    var local_179: u32;
    var local_180: array<bool, 16>;
    var local_181: array<bool, 16>;
    var local_182: i32;
    var local_183: array<i32, 16>;
    var local_184: u32;
    var local_185: i32;
    var local_186: i32;
    var local_187: array<i32, 16>;
    var local_188: bool;
    var local_189: array<bool, 16>;
    var local_190: bool;
    var local_191: bool;
    var local_192: bool;
    var local_193: bool;
    var local_194: bool;
    var local_195: bool;
    var local_196: i32;
    var local_197: f32;
    var local_198: f32;
    var local_199: f32;
    var local_200: f32;
    var local_201: f32;
    var local_202: array<f32, 16>;
    var local_203: f32;
    var local_204: f32;
    var local_205: f32;
    var local_206: f32;
    var local_207: f32;
    var local_208: f32;
    var local_209: f32;
    var local_210: i32;
    var local_211: i32;
    var local_212: f32;
    var local_213: f32;
    var local_214: f32;
    var local_215: f32;
    var local_216: f32;
    var local_217: f32;
    var local_218: f32;
    var local_219: f32;
    var local_220: f32;
    var local_221: f32;
    var local_222: f32;
    var local_223: i32;
    var local_224: i32;
    var local_225: bool;
    var local_226: f32;
    var local_227: bool;
    var local_228: i32;
    var local_229: array<bool, 16>;
    var local_230: array<bool, 16>;
    var local_231: i32;
    var local_232: f32;
    var local_233: bool;
    var local_234: f32;
    var local_235: vec2<i32>;
    var local_236: vec4<f32>;
    var local_237: i32;
    var local_238: f32;
    var local_239: vec2<i32>;
    var local_240: vec4<f32>;
    var local_241: i32;
    var local_242: f32;
    var local_243: vec2<i32>;
    var local_244: vec4<f32>;
    var local_245: i32;
    var local_246: f32;
    var local_247: vec2<i32>;
    var local_248: vec4<f32>;
    var local_249: i32;
    var local_250: f32;
    var local_251: vec2<i32>;
    var local_252: vec4<f32>;
    var local_253: i32;
    var local_254: f32;
    var local_255: vec2<i32>;
    var local_256: vec4<f32>;
    var local_257: i32;
    var local_258: f32;
    var local_259: vec2<i32>;
    var local_260: vec4<f32>;
    var local_261: i32;
    var local_262: f32;
    var local_263: vec2<i32>;
    var local_264: vec4<f32>;
    var local_265: i32;
    var local_266: f32;
    var local_267: vec2<i32>;
    var local_268: vec4<f32>;
    var local_269: i32;
    var local_270: f32;
    var local_271: bool = false;
    var local_272: bool;
    var local_273: bool;
    var local_274: bool;
    var local_275: i32;
    var local_276: bool;
    var local_277: bool;
    var local_278: i32;
    var local_279: i32;
    var local_280: array<f32, 16>;
    var local_281: array<f32, 16>;
    var local_282: array<i32, 16>;
    var local_283: array<i32, 16>;
    var local_284: u32;
    var local_285: array<bool, 16>;
    var local_286: array<bool, 16>;
    var local_287: i32;
    var local_288: array<i32, 16>;
    var local_289: u32;
    var local_290: i32;
    var local_291: i32;
    var local_292: array<i32, 16>;
    var local_293: bool;
    var local_294: array<bool, 16>;
    var local_295: bool;
    var local_296: bool;
    var local_297: bool;
    var local_298: bool;
    var local_299: bool;
    var local_300: bool;
    var local_301: i32;
    var local_302: f32;
    var local_303: f32;
    var local_304: f32;
    var local_305: f32;
    var local_306: f32;
    var local_307: array<f32, 16>;
    var local_308: f32;
    var local_309: f32;
    var local_310: f32;
    var local_311: f32;
    var local_312: f32;
    var local_313: f32;
    var local_314: f32;
    var local_315: i32;
    var local_316: i32;
    var local_317: f32;
    var local_318: f32;
    var local_319: f32;
    var local_320: f32;
    var local_321: f32;
    var local_322: f32;
    var local_323: f32;
    var local_324: f32;
    var local_325: f32;
    var local_326: f32;
    var local_327: f32;
    var local_328: i32;
    var local_329: i32;
    var local_330: bool;
    var local_331: f32;
    var local_332: bool;
    var local_333: i32;
    var local_334: array<bool, 16>;
    var local_335: array<bool, 16>;
    var local_336: i32;
    var local_337: f32;
    var local_338: vec2<i32>;
    var local_339: vec4<f32>;
    var local_340: i32;
    var local_341: f32;
    var local_342: i32;
    var local_343: i32;
    var local_344: bool;
    var local_345: bool;
    var local_346: vec2<i32>;
    var local_347: vec4<f32>;
    var local_348: i32;
    var local_349: f32;
    var local_350: bool;
    var local_351: bool;
    var local_352: vec2<i32>;
    var local_353: vec4<f32>;
    var local_354: i32;
    var local_355: f32;
    var local_356: bool;
    var local_357: bool;
    var local_358: vec2<i32>;
    var local_359: vec4<f32>;
    var local_360: i32;
    var local_361: f32;
    var local_362: bool;
    var local_363: u32;
    var local_364: u32;
    var local_365: bool;
    var local_366: vec2<i32>;
    var local_367: vec4<f32>;
    var local_368: i32;
    var local_369: f32;
    var local_370: vec2<i32>;
    var local_371: vec4<f32>;
    var local_372: i32;
    var local_373: f32;
    var local_374: i32;
    var local_375: i32;
    var local_376: bool;
    var local_377: f32;
    var local_378: f32;
    var local_379: f32;
    var local_380: f32;
    var local_381: f32;
    var local_382: f32;
    var local_383: bool;
    var local_384: f32;
    var local_385: f32;
    var local_386: f32;
    var local_387: f32;
    var local_388: f32;
    var local_389: f32;
    var local_390: f32;
    var local_391: f32;
    var local_392: f32;
    var local_393: f32;
    var local_394: f32;
    var local_395: f32;
    var local_396: f32;
    var local_397: f32;
    var local_398: f32;
    var local_399: f32;
    var local_400: f32;
    var local_401: f32;
    var local_402: array<vec2<f32>, 4>;
    var local_403: array<vec2<f32>, 4>;
    var local_404: f32;
    var local_405: f32;
    var local_406: vec2<f32>;
    var local_407: vec2<f32>;
    var local_408: f32;
    var local_409: f32;
    var local_410: f32;
    var local_411: f32;
    var local_412: vec3<f32>;
    var local_413: vec3<f32>;
    var local_414: vec2<f32>;
    var local_415: f32;
    var local_416: f32;
    var local_417: f32;
    var local_418: f32;
    var local_419: vec2<f32>;
    var local_420: i32;
    var local_421: vec2<f32>;
    var local_422: vec2<f32>;
    var local_423: array<vec4<f32>, 4>;
    var local_424: array<vec4<f32>, 4>;
    var local_425: i32;
    var local_426: i32;
    var local_427: f32;
    var local_428: f32;
    var local_429: vec4<u32>;
    var local_430: vec3<u32>;
    var local_431: bool;
    var local_432: f32;
    var local_433: i32;
    var local_434: i32;
    var local_435: f32;
    var local_436: i32;
    var local_437: i32;
    var local_438: f32;
    var local_439: array<vec4<f32>, 4>;
    var local_440: array<vec4<f32>, 4>;
    var local_441: i32;
    var local_442: i32;
    var local_443: bool;
    var local_444: i32;
    var local_445: i32;
    var local_446: i32;
    var local_447: f32;
    var local_448: f32;
    var local_449: f32;
    var local_450: i32;
    var local_451: array<f32, 16>;
    var local_452: array<f32, 16>;
    var local_453: array<i32, 16>;
    var local_454: bool;
    var local_455: i32;
    var local_456: i32;
    var local_457: i32;
    var local_458: f32;
    var local_459: f32;
    var local_460: f32;
    var local_461: i32;
    var local_462: array<f32, 16>;
    var local_463: array<f32, 16>;
    var local_464: array<i32, 16>;
    var local_465: i32;
    var local_466: array<f32, 16>;
    var local_467: array<i32, 16>;
    var local_468: array<vec4<f32>, 4>;
    var local_469: vec4<u32>;
    var local_470: array<vec4<f32>, 4>;
    var local_471: i32;
    var local_472: array<f32, 16>;
    var local_473: array<i32, 16>;
    var local_474: array<vec4<f32>, 4>;
    var local_475: vec4<u32>;
    var local_476: array<vec4<f32>, 4>;

    switch bitcast<i32>(0u) {
        default: {
            let _e585 = gl_VertexIndex_1;
            let _e586 = a_rect_0_1;
            let _e588 = a_rect_0_1;
            local_402 = array<vec2<f32>, 4>(vec2<f32>(0f, 0f), vec2<f32>(1f, 0f), vec2<f32>(1f, 1f), vec2<f32>(0f, 1f));
            let _e591 = local_402[_e585];
            let _e592 = mix(_e586.xy, _e588.zw, _e591);
            local_403 = array<vec2<f32>, 4>(vec2<f32>(0f, 0f), vec2<f32>(1f, 0f), vec2<f32>(1f, 1f), vec2<f32>(0f, 1f));
            let _e594 = local_403[_e585];
            let _e596 = ((_e594 * 2f) - vec2<f32>(1f, 1f));
            let _e598 = a_xform_0_1[0u];
            local_404 = _e592.x;
            let _e601 = a_xform_0_1[1u];
            local_405 = _e592.y;
            let _e604 = a_xform_0_1[2u];
            let _e606 = a_xform_0_1[3u];
            let _e611 = a_origin_0_1[0u];
            let _e617 = a_origin_0_1[1u];
            local_406 = vec2<f32>((((_e598 * _e592.x) + (_e601 * _e592.y)) + _e611), (((_e604 * _e592.x) + (_e606 * _e592.y)) + _e617));
            local_407 = vec2<f32>(((_e598 * _e596.x) + (_e601 * _e596.y)), ((_e604 * _e596.x) + (_e606 * _e596.y)));
            let _e632 = (1f / ((_e598 * _e606) - (_e601 * _e604)));
            local_408 = (_e606 * _e632);
            local_409 = (-(_e601) * _e632);
            local_410 = (-(_e604) * _e632);
            local_411 = (_e598 * _e632);
            let _e640 = a_glyph_0_1[0u];
            _S1_ = vec2<i32>(bitcast<i32>((_e640 & 65535u)), bitcast<i32>((_e640 >> bitcast<u32>(16u))));
            let _e647 = a_policy0_0_1;
            _S2_ = _e647;
            let _e648 = a_policy1_0_1;
            _S3_ = _e648;
            let _e650 = a_bnd_0_1[3u];
            let _e651 = _S4_;
            _S4_ = vec3<f32>(_e651.x, _e651.y, _e650);
            let _e656 = a_col_0_1;
            let _e657 = _e656.xyz;
            local_412 = _e657;
            local_399 = _e657.x;
            if (_e657.x <= 0.04045f) {
                let _e660 = local_399;
                local_398 = (_e660 * 0.07739938f);
            } else {
                let _e662 = local_399;
                local_398 = pow(((_e662 + 0.055f) * 0.94786733f), 2.4f);
            }
            let _e666 = local_398;
            let _e667 = local_412;
            local_400 = _e667.y;
            if (_e667.y <= 0.04045f) {
                let _e670 = local_400;
                local_397 = (_e670 * 0.07739938f);
            } else {
                let _e672 = local_400;
                local_397 = pow(((_e672 + 0.055f) * 0.94786733f), 2.4f);
            }
            let _e676 = local_397;
            let _e677 = local_412;
            local_401 = _e677.z;
            if (_e677.z <= 0.04045f) {
                let _e680 = local_401;
                local_396 = (_e680 * 0.07739938f);
            } else {
                let _e682 = local_401;
                local_396 = pow(((_e682 + 0.055f) * 0.94786733f), 2.4f);
            }
            let _e686 = local_396;
            let _e687 = vec3<f32>(_e666, _e676, _e686);
            let _e689 = a_col_0_1[3u];
            let _e694 = a_tint_0_1;
            let _e695 = _e694.xyz;
            local_413 = _e695;
            local_393 = _e695.x;
            if (_e695.x <= 0.04045f) {
                let _e698 = local_393;
                local_392 = (_e698 * 0.07739938f);
            } else {
                let _e700 = local_393;
                local_392 = pow(((_e700 + 0.055f) * 0.94786733f), 2.4f);
            }
            let _e704 = local_392;
            let _e705 = local_413;
            local_394 = _e705.y;
            if (_e705.y <= 0.04045f) {
                let _e708 = local_394;
                local_391 = (_e708 * 0.07739938f);
            } else {
                let _e710 = local_394;
                local_391 = pow(((_e710 + 0.055f) * 0.94786733f), 2.4f);
            }
            let _e714 = local_391;
            let _e715 = local_413;
            local_395 = _e715.z;
            if (_e715.z <= 0.04045f) {
                let _e718 = local_395;
                local_390 = (_e718 * 0.07739938f);
            } else {
                let _e720 = local_395;
                local_390 = pow(((_e720 + 0.055f) * 0.94786733f), 2.4f);
            }
            let _e724 = local_390;
            let _e725 = vec3<f32>(_e704, _e714, _e724);
            let _e727 = a_tint_0_1[3u];
            _S6_ = (vec4<f32>(_e687.x, _e687.y, _e687.z, _e689) * vec4<f32>(_e725.x, _e725.y, _e725.z, _e727));
            let _e733 = local_407;
            let _e734 = normalize(_e733);
            local_414 = _e734;
            let _e738 = PushConstants_0_.mvp_0_[0][3u];
            let _e742 = PushConstants_0_.mvp_0_[1][3u];
            let _e743 = vec2<f32>(_e738, _e742);
            let _e744 = local_406;
            let _e749 = PushConstants_0_.mvp_0_[3][3u];
            let _e750 = (dot(_e743, _e744) + _e749);
            let _e751 = dot(_e743, _e734);
            let _e755 = PushConstants_0_.mvp_0_[0][0u];
            let _e759 = PushConstants_0_.mvp_0_[1][0u];
            let _e760 = vec2<f32>(_e755, _e759);
            let _e767 = PushConstants_0_.mvp_0_[3][0u];
            let _e773 = PushConstants_0_.viewport_0_[0u];
            let _e774 = (((_e750 * dot(_e760, _e734)) - (_e751 * (dot(_e760, _e744) + _e767))) * _e773);
            let _e778 = PushConstants_0_.mvp_0_[0][1u];
            let _e782 = PushConstants_0_.mvp_0_[1][1u];
            let _e783 = vec2<f32>(_e778, _e782);
            let _e790 = PushConstants_0_.mvp_0_[3][1u];
            let _e796 = PushConstants_0_.viewport_0_[1u];
            let _e797 = (((_e750 * dot(_e783, _e734)) - (_e751 * (dot(_e783, _e744) + _e790))) * _e796);
            local_415 = (_e750 * _e750);
            let _e799 = (_e750 * _e751);
            local_416 = _e799;
            let _e802 = ((_e774 * _e774) + (_e797 * _e797));
            local_417 = _e802;
            let _e804 = (_e802 - (_e799 * _e799));
            local_418 = _e804;
            if (abs(_e804) > 0.0000000001f) {
                let _e807 = local_414;
                let _e808 = local_415;
                let _e809 = local_416;
                let _e810 = local_417;
                let _e814 = local_418;
                local_419 = (_e807 * ((_e808 * (_e809 + sqrt(_e810))) / _e814));
            } else {
                let _e817 = local_414;
                let _e820 = PushConstants_0_.viewport_0_;
                local_419 = ((_e817 * 2f) / _e820);
            }
            let _e822 = local_419;
            let _e824 = PushConstants_0_.subpixel_order_0_;
            if (_e824 == 0i) {
                local_389 = 1f;
            } else {
                local_389 = 2.3333333f;
            }
            let _e826 = local_389;
            let _e828 = (_e822 * (1.4142135f * _e826));
            let _e829 = local_406;
            let _e830 = (_e829 + _e828);
            let _e831 = local_404;
            let _e832 = local_408;
            let _e833 = local_409;
            let _e837 = local_405;
            let _e838 = local_410;
            let _e839 = local_411;
            let _e843 = _S4_;
            let _e847 = vec3<f32>((_e831 + dot(_e828, vec2<f32>(_e832, _e833))), _e843.y, _e843.z);
            _S4_ = vec3<f32>(_e847.x, (_e837 + dot(_e828, vec2<f32>(_e838, _e839))), _e847.z);
            let _e853 = PushConstants_0_.mvp_0_;
            _S8_ = (_e853 * vec4<f32>(_e830.x, _e830.y, 0f, 1f));
            let _e858 = gl_VertexIndex_1;
            if (_e858 != 0i) {
                local_420 = 0i;
                loop {
                    let _e860 = local_420;
                    if (_e860 < 4i) {
                    } else {
                        break;
                    }
                    let _e862 = local_420;
                    v_ah_x_targets_0_[_e862] = vec4<f32>(0f, 0f, 0f, 0f);
                    v_ah_y_targets_0_[_e862] = vec4<f32>(0f, 0f, 0f, 0f);
                    local_420 = (_e862 + 1i);
                    continue;
                }
                _S26_ = vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u);
                _S27_ = vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u);
                break;
            }
            let _e866 = _S1_;
            snailAhVertexInfoBase_0_ = _e866;
            switch bitcast<i32>(0u) {
                default: {
                    let _e871 = PushConstants_0_.mvp_0_[0][0u];
                    local_377 = _e871;
                    let _e875 = PushConstants_0_.mvp_0_[1][0u];
                    local_378 = _e875;
                    let _e879 = PushConstants_0_.mvp_0_[0][1u];
                    local_379 = _e879;
                    let _e883 = PushConstants_0_.mvp_0_[1][1u];
                    local_380 = _e883;
                    let _e887 = PushConstants_0_.mvp_0_[1][3u];
                    local_381 = _e887;
                    let _e891 = PushConstants_0_.mvp_0_[3][3u];
                    local_382 = _e891;
                    let _e895 = PushConstants_0_.mvp_0_[0][3u];
                    if (abs(_e895) > 0.0000001f) {
                        local_383 = true;
                    } else {
                        let _e898 = local_381;
                        local_383 = (abs(_e898) > 0.0000001f);
                    }
                    let _e901 = local_383;
                    if _e901 {
                        local_383 = true;
                    } else {
                        let _e902 = local_382;
                        local_383 = !((abs(_e902) <= 340282300000000000000000000000000000000f));
                    }
                    let _e906 = local_383;
                    if _e906 {
                        local_383 = true;
                    } else {
                        let _e907 = local_382;
                        local_383 = (abs(_e907) < 0.0000000001f);
                    }
                    let _e910 = local_383;
                    if _e910 {
                        local_376 = false;
                        break;
                    }
                    let _e912 = a_xform_0_1[0u];
                    let _e914 = a_xform_0_1[2u];
                    let _e915 = vec2<f32>(_e912, _e914);
                    let _e917 = a_xform_0_1[1u];
                    let _e919 = a_xform_0_1[3u];
                    let _e920 = vec2<f32>(_e917, _e919);
                    let _e921 = local_377;
                    let _e922 = local_378;
                    let _e923 = vec2<f32>(_e921, _e922);
                    let _e924 = local_379;
                    let _e925 = local_380;
                    let _e926 = vec2<f32>(_e924, _e925);
                    let _e928 = PushConstants_0_.viewport_0_;
                    let _e934 = local_382;
                    let _e936 = (((_e928 * 0.5f) * vec2<f32>(dot(_e923, _e915), dot(_e926, _e915))) / vec2(_e934));
                    let _e938 = PushConstants_0_.viewport_0_;
                    let _e945 = (((_e938 * 0.5f) * vec2<f32>(dot(_e923, _e920), dot(_e926, _e920))) / vec2(_e934));
                    local_384 = _e936.x;
                    local_385 = _e945.y;
                    local_386 = _e945.x;
                    local_387 = _e936.y;
                    let _e952 = ((_e936.x * _e945.y) - (_e945.x * _e936.y));
                    local_388 = _e952;
                    if !((abs(_e952) <= 340282300000000000000000000000000000000f)) {
                        local_383 = true;
                    } else {
                        let _e956 = local_388;
                        local_383 = (abs(_e956) < 0.0000000001f);
                    }
                    let _e959 = local_383;
                    if _e959 {
                        local_376 = false;
                        break;
                    }
                    let _e960 = local_388;
                    let _e961 = abs(_e960);
                    let _e962 = local_385;
                    let _e964 = local_386;
                    let _e968 = local_387;
                    let _e970 = local_384;
                    let _e975 = (vec2<f32>(1f, 1f) / vec2<f32>(((abs(_e962) + abs(_e964)) / _e961), ((abs(_e968) + abs(_e970)) / _e961)));
                    local_422 = _e975;
                    if (abs(_e975.x) <= 340282300000000000000000000000000000000f) {
                        let _e979 = local_422;
                        local_383 = (abs(_e979.y) <= 340282300000000000000000000000000000000f);
                    } else {
                        local_383 = false;
                    }
                    let _e983 = local_383;
                    if _e983 {
                        let _e984 = local_422;
                        local_383 = (_e984.x > 0f);
                    } else {
                        local_383 = false;
                    }
                    let _e987 = local_383;
                    if _e987 {
                        let _e988 = local_422;
                        local_383 = (_e988.y > 0f);
                    } else {
                        local_383 = false;
                    }
                    let _e991 = local_383;
                    local_376 = _e991;
                    break;
                }
            }
            let _e992 = local_376;
            let _e993 = local_422;
            local_421 = _e993;
            if !(_e992) {
                local_375 = 0i;
                loop {
                    let _e995 = local_375;
                    if (_e995 < 4i) {
                    } else {
                        break;
                    }
                    let _e997 = local_375;
                    local_423[_e997] = vec4<f32>(0f, 0f, 0f, 0f);
                    local_375 = (_e997 + 1i);
                    continue;
                }
                let _e1005 = local_423;
                v_ah_x_targets_0_ = _e1005;
                _S26_ = vec4<u32>(4294967294u, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).y, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).z, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).w);
                local_374 = 0i;
                loop {
                    let _e1006 = local_374;
                    if (_e1006 < 4i) {
                    } else {
                        break;
                    }
                    let _e1008 = local_374;
                    local_424[_e1008] = vec4<f32>(0f, 0f, 0f, 0f);
                    local_374 = (_e1008 + 1i);
                    continue;
                }
                let _e1016 = local_424;
                v_ah_y_targets_0_ = _e1016;
                _S27_ = vec4<u32>(4294967294u, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).y, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).z, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).w);
                break;
            }
            local_425 = 0i;
            local_426 = 0i;
            let _e1017 = (0i + 8i);
            let _e1020 = snailAhVertexInfoBase_0_;
            let _e1021 = textureDimensions(u_layer_tex_0_image, 0i);
            let _e1024 = local_370;
            let _e1027 = vec2<i32>(vec2<i32>(_e1021).x, _e1024.y);
            let _e1028 = textureDimensions(u_layer_tex_0_image, 0i);
            let _e1033 = vec2<i32>(_e1027.x, vec2<i32>(_e1028).y);
            local_370 = _e1033;
            let _e1039 = (((_e1020.y * _e1033.x) + _e1020.x) + (_e1017 >> bitcast<u32>(2i)));
            let _e1048 = vec2<i32>((_e1039 - (i32(floor((f32(_e1039) / f32(_e1033.x)))) * _e1033.x)), (_e1039 / _e1033.x));
            let _e1051 = vec3<i32>(_e1048.x, _e1048.y, 0i);
            let _e1054 = textureLoad(u_layer_tex_0_image, _e1051.xy, _e1051.z);
            local_371 = _e1054;
            let _e1055 = (_e1017 & 3i);
            local_372 = _e1055;
            if (_e1055 == 0i) {
                let _e1057 = local_371;
                local_373 = _e1057.x;
            } else {
                let _e1059 = local_372;
                if (_e1059 == 1i) {
                    let _e1061 = local_371;
                    local_373 = _e1061.y;
                } else {
                    let _e1063 = local_372;
                    if (_e1063 == 2i) {
                        let _e1065 = local_371;
                        local_373 = _e1065.z;
                    } else {
                        let _e1067 = local_371;
                        local_373 = _e1067.w;
                    }
                }
            }
            let _e1069 = local_373;
            local_427 = _e1069;
            let _e1070 = (0i + 9i);
            let _e1073 = snailAhVertexInfoBase_0_;
            let _e1074 = textureDimensions(u_layer_tex_0_image, 0i);
            let _e1077 = local_366;
            let _e1080 = vec2<i32>(vec2<i32>(_e1074).x, _e1077.y);
            let _e1081 = textureDimensions(u_layer_tex_0_image, 0i);
            let _e1086 = vec2<i32>(_e1080.x, vec2<i32>(_e1081).y);
            local_366 = _e1086;
            let _e1092 = (((_e1073.y * _e1086.x) + _e1073.x) + (_e1070 >> bitcast<u32>(2i)));
            let _e1101 = vec2<i32>((_e1092 - (i32(floor((f32(_e1092) / f32(_e1086.x)))) * _e1086.x)), (_e1092 / _e1086.x));
            let _e1104 = vec3<i32>(_e1101.x, _e1101.y, 0i);
            let _e1107 = textureLoad(u_layer_tex_0_image, _e1104.xy, _e1104.z);
            local_367 = _e1107;
            let _e1108 = (_e1070 & 3i);
            local_368 = _e1108;
            if (_e1108 == 0i) {
                let _e1110 = local_367;
                local_369 = _e1110.x;
            } else {
                let _e1112 = local_368;
                if (_e1112 == 1i) {
                    let _e1114 = local_367;
                    local_369 = _e1114.y;
                } else {
                    let _e1116 = local_368;
                    if (_e1116 == 2i) {
                        let _e1118 = local_367;
                        local_369 = _e1118.z;
                    } else {
                        let _e1120 = local_367;
                        local_369 = _e1120.w;
                    }
                }
            }
            let _e1122 = local_369;
            local_428 = _e1122;
            let _e1123 = a_policy0_0_1;
            local_429 = _e1123;
            let _e1124 = a_policy1_0_1;
            local_430 = _e1124;
            switch bitcast<i32>(0u) {
                default: {
                    let _e1126 = local_429;
                    local_363 = _e1126.x;
                    local_364 = _e1126.y;
                    if ((_e1126.x & 4286578688u) != 0u) {
                        local_365 = true;
                    } else {
                        let _e1131 = local_364;
                        local_365 = ((_e1131 & 4294967232u) != 0u);
                    }
                    let _e1134 = local_365;
                    if _e1134 {
                        local_362 = false;
                        break;
                    }
                    let _e1135 = local_363;
                    let _e1137 = bitcast<i32>((_e1135 & 3u));
                    local_108 = _e1137;
                    local_107 = bitcast<i32>(((_e1135 >> bitcast<u32>(2u)) & 3u));
                    local_106 = bitcast<i32>(((_e1135 >> bitcast<u32>(4u)) & 3u));
                    local_105 = bitcast<i32>(((_e1135 >> bitcast<u32>(6u)) & 3u));
                    local_101 = bitcast<i32>(((_e1135 >> bitcast<u32>(8u)) & 1u));
                    local_100 = f32(((_e1135 >> bitcast<u32>(9u)) & 127u));
                    local_99 = f32(((_e1135 >> bitcast<u32>(16u)) & 127u));
                    let _e1162 = local_364;
                    local_104 = bitcast<i32>((_e1162 & 3u));
                    local_103 = bitcast<i32>(((_e1162 >> bitcast<u32>(2u)) & 3u));
                    local_102 = bitcast<i32>(((_e1162 >> bitcast<u32>(4u)) & 3u));
                    if (_e1137 > 1i) {
                        local_365 = true;
                    } else {
                        let _e1174 = local_107;
                        local_365 = (_e1174 > 2i);
                    }
                    let _e1176 = local_365;
                    if _e1176 {
                        local_365 = true;
                    } else {
                        let _e1177 = local_106;
                        local_365 = (_e1177 > 1i);
                    }
                    let _e1179 = local_365;
                    if _e1179 {
                        local_365 = true;
                    } else {
                        let _e1180 = local_105;
                        local_365 = (_e1180 > 1i);
                    }
                    let _e1182 = local_365;
                    if _e1182 {
                        local_365 = true;
                    } else {
                        let _e1183 = local_104;
                        local_365 = (_e1183 > 2i);
                    }
                    let _e1185 = local_365;
                    if _e1185 {
                        local_365 = true;
                    } else {
                        let _e1186 = local_103;
                        local_365 = (_e1186 > 2i);
                    }
                    let _e1188 = local_365;
                    if _e1188 {
                        local_365 = true;
                    } else {
                        let _e1189 = local_102;
                        local_365 = (_e1189 > 1i);
                    }
                    let _e1191 = local_365;
                    if _e1191 {
                        local_362 = false;
                        break;
                    }
                    let _e1192 = local_429;
                    local_98 = bitcast<f32>(_e1192.z);
                    local_97 = bitcast<f32>(_e1192.w);
                    let _e1197 = local_430;
                    local_96 = bitcast<f32>(_e1197.x);
                    local_95 = bitcast<f32>(_e1197.y);
                    local_94 = bitcast<f32>(_e1197.z);
                    let _e1204 = local_107;
                    if (_e1204 != 0i) {
                        let _e1206 = local_98;
                        if !((abs(_e1206) <= 340282300000000000000000000000000000000f)) {
                            local_365 = true;
                        } else {
                            let _e1210 = local_98;
                            local_365 = (_e1210 < 0f);
                        }
                    } else {
                        local_365 = false;
                    }
                    let _e1212 = local_365;
                    if _e1212 {
                        local_365 = true;
                    } else {
                        let _e1213 = local_107;
                        if (_e1213 == 1i) {
                            let _e1215 = local_97;
                            if !((abs(_e1215) <= 340282300000000000000000000000000000000f)) {
                                local_365 = true;
                            } else {
                                let _e1219 = local_97;
                                local_365 = (_e1219 < 0f);
                            }
                        } else {
                            local_365 = false;
                        }
                    }
                    let _e1221 = local_365;
                    if _e1221 {
                        local_365 = true;
                    } else {
                        let _e1222 = local_103;
                        if (_e1222 != 0i) {
                            let _e1224 = local_96;
                            if !((abs(_e1224) <= 340282300000000000000000000000000000000f)) {
                                local_365 = true;
                            } else {
                                let _e1228 = local_96;
                                local_365 = (_e1228 < 0f);
                            }
                        } else {
                            local_365 = false;
                        }
                    }
                    let _e1230 = local_365;
                    if _e1230 {
                        local_365 = true;
                    } else {
                        let _e1231 = local_103;
                        if (_e1231 == 1i) {
                            let _e1233 = local_95;
                            if !((abs(_e1233) <= 340282300000000000000000000000000000000f)) {
                                local_365 = true;
                            } else {
                                let _e1237 = local_95;
                                local_365 = (_e1237 < 0f);
                            }
                        } else {
                            local_365 = false;
                        }
                    }
                    let _e1239 = local_365;
                    if _e1239 {
                        local_365 = true;
                    } else {
                        let _e1240 = local_102;
                        if (_e1240 == 1i) {
                            let _e1242 = local_94;
                            if !((abs(_e1242) <= 340282300000000000000000000000000000000f)) {
                                local_365 = true;
                            } else {
                                let _e1246 = local_94;
                                local_365 = (_e1246 < 0f);
                            }
                        } else {
                            local_365 = false;
                        }
                    }
                    let _e1248 = local_365;
                    if _e1248 {
                        local_365 = true;
                    } else {
                        let _e1249 = local_106;
                        if (_e1249 == 1i) {
                            let _e1251 = local_108;
                            local_365 = (_e1251 == 0i);
                        } else {
                            local_365 = false;
                        }
                    }
                    let _e1253 = local_365;
                    if _e1253 {
                        local_365 = true;
                    } else {
                        let _e1254 = local_102;
                        if (_e1254 == 1i) {
                            let _e1256 = local_104;
                            local_365 = (_e1256 != 2i);
                        } else {
                            local_365 = false;
                        }
                    }
                    let _e1258 = local_365;
                    if _e1258 {
                        local_362 = false;
                        break;
                    }
                    local_362 = true;
                    break;
                }
            }
            let _e1259 = local_362;
            let _e1260 = local_94;
            let _e1261 = local_95;
            let _e1262 = local_96;
            let _e1263 = local_97;
            let _e1264 = local_98;
            let _e1265 = local_99;
            let _e1266 = local_100;
            let _e1267 = local_101;
            let _e1268 = local_102;
            let _e1269 = local_103;
            let _e1270 = local_104;
            let _e1271 = local_105;
            let _e1272 = local_106;
            let _e1273 = local_107;
            let _e1274 = local_108;
            local_123 = _e1274;
            local_122 = _e1273;
            local_121 = _e1272;
            local_120 = _e1271;
            local_119 = _e1270;
            local_118 = _e1269;
            local_117 = _e1268;
            local_116 = _e1267;
            local_115 = _e1266;
            local_114 = _e1265;
            local_113 = _e1264;
            local_112 = _e1263;
            local_111 = _e1262;
            local_110 = _e1261;
            local_109 = _e1260;
            if _e1259 {
                let _e1275 = local_427;
                local_431 = (abs(_e1275) <= 340282300000000000000000000000000000000f);
            } else {
                local_431 = false;
            }
            let _e1278 = local_431;
            if _e1278 {
                let _e1279 = local_427;
                local_431 = (_e1279 >= 0f);
            } else {
                local_431 = false;
            }
            let _e1281 = local_431;
            if _e1281 {
                let _e1282 = local_428;
                local_431 = (abs(_e1282) <= 340282300000000000000000000000000000000f);
            } else {
                local_431 = false;
            }
            let _e1285 = local_431;
            if _e1285 {
                let _e1286 = local_428;
                local_431 = (_e1286 >= 0f);
            } else {
                local_431 = false;
            }
            let _e1288 = local_431;
            if _e1288 {
                let _e1289 = (0i + 10i);
                let _e1292 = snailAhVertexInfoBase_0_;
                let _e1293 = textureDimensions(u_layer_tex_0_image, 0i);
                let _e1296 = local_358;
                let _e1299 = vec2<i32>(vec2<i32>(_e1293).x, _e1296.y);
                let _e1300 = textureDimensions(u_layer_tex_0_image, 0i);
                let _e1305 = vec2<i32>(_e1299.x, vec2<i32>(_e1300).y);
                local_358 = _e1305;
                let _e1311 = (((_e1292.y * _e1305.x) + _e1292.x) + (_e1289 >> bitcast<u32>(2i)));
                let _e1320 = vec2<i32>((_e1311 - (i32(floor((f32(_e1311) / f32(_e1305.x)))) * _e1305.x)), (_e1311 / _e1305.x));
                let _e1323 = vec3<i32>(_e1320.x, _e1320.y, 0i);
                let _e1326 = textureLoad(u_layer_tex_0_image, _e1323.xy, _e1323.z);
                local_359 = _e1326;
                let _e1327 = (_e1289 & 3i);
                local_360 = _e1327;
                if (_e1327 == 0i) {
                    let _e1329 = local_359;
                    local_361 = _e1329.x;
                } else {
                    let _e1331 = local_360;
                    if (_e1331 == 1i) {
                        let _e1333 = local_359;
                        local_361 = _e1333.y;
                    } else {
                        let _e1335 = local_360;
                        if (_e1335 == 2i) {
                            let _e1337 = local_359;
                            local_361 = _e1337.z;
                        } else {
                            let _e1339 = local_359;
                            local_361 = _e1339.w;
                        }
                    }
                }
                let _e1341 = local_361;
                local_432 = _e1341;
                switch bitcast<i32>(0u) {
                    default: {
                        let _e1343 = local_432;
                        if !((abs(_e1343) <= 340282300000000000000000000000000000000f)) {
                            local_357 = true;
                        } else {
                            let _e1347 = local_432;
                            local_357 = (_e1347 < 0f);
                        }
                        let _e1349 = local_357;
                        if _e1349 {
                            local_357 = true;
                        } else {
                            let _e1350 = local_432;
                            local_357 = (_e1350 > 16f);
                        }
                        let _e1352 = local_357;
                        if _e1352 {
                            local_357 = true;
                        } else {
                            let _e1353 = local_432;
                            local_357 = (floor(_e1353) != _e1353);
                        }
                        let _e1356 = local_357;
                        if _e1356 {
                            local_433 = 0i;
                            local_356 = false;
                            break;
                        }
                        let _e1357 = local_432;
                        local_433 = i32(_e1357);
                        local_356 = true;
                        break;
                    }
                }
                let _e1359 = local_356;
                let _e1360 = local_433;
                local_425 = _e1360;
                local_431 = _e1359;
            } else {
                local_431 = false;
            }
            let _e1361 = local_425;
            local_434 = (12i + (2i * _e1361));
            let _e1364 = local_431;
            if _e1364 {
                let _e1365 = local_434;
                let _e1366 = (_e1365 + 0i);
                let _e1369 = snailAhVertexInfoBase_0_;
                let _e1370 = textureDimensions(u_layer_tex_0_image, 0i);
                let _e1373 = local_352;
                let _e1376 = vec2<i32>(vec2<i32>(_e1370).x, _e1373.y);
                let _e1377 = textureDimensions(u_layer_tex_0_image, 0i);
                let _e1382 = vec2<i32>(_e1376.x, vec2<i32>(_e1377).y);
                local_352 = _e1382;
                let _e1388 = (((_e1369.y * _e1382.x) + _e1369.x) + (_e1366 >> bitcast<u32>(2i)));
                let _e1397 = vec2<i32>((_e1388 - (i32(floor((f32(_e1388) / f32(_e1382.x)))) * _e1382.x)), (_e1388 / _e1382.x));
                let _e1400 = vec3<i32>(_e1397.x, _e1397.y, 0i);
                let _e1403 = textureLoad(u_layer_tex_0_image, _e1400.xy, _e1400.z);
                local_353 = _e1403;
                let _e1404 = (_e1366 & 3i);
                local_354 = _e1404;
                if (_e1404 == 0i) {
                    let _e1406 = local_353;
                    local_355 = _e1406.x;
                } else {
                    let _e1408 = local_354;
                    if (_e1408 == 1i) {
                        let _e1410 = local_353;
                        local_355 = _e1410.y;
                    } else {
                        let _e1412 = local_354;
                        if (_e1412 == 2i) {
                            let _e1414 = local_353;
                            local_355 = _e1414.z;
                        } else {
                            let _e1416 = local_353;
                            local_355 = _e1416.w;
                        }
                    }
                }
                let _e1418 = local_355;
                local_435 = _e1418;
                switch bitcast<i32>(0u) {
                    default: {
                        let _e1420 = local_435;
                        if !((abs(_e1420) <= 340282300000000000000000000000000000000f)) {
                            local_351 = true;
                        } else {
                            let _e1424 = local_435;
                            local_351 = (_e1424 < 0f);
                        }
                        let _e1426 = local_351;
                        if _e1426 {
                            local_351 = true;
                        } else {
                            let _e1427 = local_435;
                            local_351 = (_e1427 > 16f);
                        }
                        let _e1429 = local_351;
                        if _e1429 {
                            local_351 = true;
                        } else {
                            let _e1430 = local_435;
                            local_351 = (floor(_e1430) != _e1430);
                        }
                        let _e1433 = local_351;
                        if _e1433 {
                            local_436 = 0i;
                            local_350 = false;
                            break;
                        }
                        let _e1434 = local_435;
                        local_436 = i32(_e1434);
                        local_350 = true;
                        break;
                    }
                }
                let _e1436 = local_350;
                let _e1437 = local_436;
                local_426 = _e1437;
                local_431 = _e1436;
            } else {
                local_431 = false;
            }
            let _e1438 = local_434;
            let _e1440 = local_426;
            local_437 = ((_e1438 + 1i) + (4i * _e1440));
            let _e1443 = local_431;
            if _e1443 {
                let _e1444 = local_437;
                let _e1445 = (_e1444 + 0i);
                let _e1448 = snailAhVertexInfoBase_0_;
                let _e1449 = textureDimensions(u_layer_tex_0_image, 0i);
                let _e1452 = local_346;
                let _e1455 = vec2<i32>(vec2<i32>(_e1449).x, _e1452.y);
                let _e1456 = textureDimensions(u_layer_tex_0_image, 0i);
                let _e1461 = vec2<i32>(_e1455.x, vec2<i32>(_e1456).y);
                local_346 = _e1461;
                let _e1467 = (((_e1448.y * _e1461.x) + _e1448.x) + (_e1445 >> bitcast<u32>(2i)));
                let _e1476 = vec2<i32>((_e1467 - (i32(floor((f32(_e1467) / f32(_e1461.x)))) * _e1461.x)), (_e1467 / _e1461.x));
                let _e1479 = vec3<i32>(_e1476.x, _e1476.y, 0i);
                let _e1482 = textureLoad(u_layer_tex_0_image, _e1479.xy, _e1479.z);
                local_347 = _e1482;
                let _e1483 = (_e1445 & 3i);
                local_348 = _e1483;
                if (_e1483 == 0i) {
                    let _e1485 = local_347;
                    local_349 = _e1485.x;
                } else {
                    let _e1487 = local_348;
                    if (_e1487 == 1i) {
                        let _e1489 = local_347;
                        local_349 = _e1489.y;
                    } else {
                        let _e1491 = local_348;
                        if (_e1491 == 2i) {
                            let _e1493 = local_347;
                            local_349 = _e1493.z;
                        } else {
                            let _e1495 = local_347;
                            local_349 = _e1495.w;
                        }
                    }
                }
                let _e1497 = local_349;
                local_438 = _e1497;
                switch bitcast<i32>(0u) {
                    default: {
                        let _e1499 = local_438;
                        if !((abs(_e1499) <= 340282300000000000000000000000000000000f)) {
                            local_345 = true;
                        } else {
                            let _e1503 = local_438;
                            local_345 = (_e1503 < 0f);
                        }
                        let _e1505 = local_345;
                        if _e1505 {
                            local_345 = true;
                        } else {
                            let _e1506 = local_438;
                            local_345 = (_e1506 > 16f);
                        }
                        let _e1508 = local_345;
                        if _e1508 {
                            local_345 = true;
                        } else {
                            let _e1509 = local_438;
                            local_345 = (floor(_e1509) != _e1509);
                        }
                        let _e1512 = local_345;
                        if _e1512 {
                            local_344 = false;
                            break;
                        }
                        local_344 = true;
                        break;
                    }
                }
                let _e1513 = local_344;
                local_431 = _e1513;
            } else {
                local_431 = false;
            }
            let _e1514 = local_431;
            if !(_e1514) {
                local_343 = 0i;
                loop {
                    let _e1516 = local_343;
                    if (_e1516 < 4i) {
                    } else {
                        break;
                    }
                    let _e1518 = local_343;
                    local_439[_e1518] = vec4<f32>(0f, 0f, 0f, 0f);
                    local_343 = (_e1518 + 1i);
                    continue;
                }
                let _e1526 = local_439;
                v_ah_x_targets_0_ = _e1526;
                _S26_ = vec4<u32>(4294967294u, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).y, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).z, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).w);
                local_342 = 0i;
                loop {
                    let _e1527 = local_342;
                    if (_e1527 < 4i) {
                    } else {
                        break;
                    }
                    let _e1529 = local_342;
                    local_440[_e1529] = vec4<f32>(0f, 0f, 0f, 0f);
                    local_342 = (_e1529 + 1i);
                    continue;
                }
                let _e1537 = local_440;
                v_ah_y_targets_0_ = _e1537;
                _S27_ = vec4<u32>(4294967294u, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).y, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).z, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).w);
                break;
            }
            local_441 = 0i;
            local_442 = 0i;
            let _e1538 = (0i + 11i);
            let _e1541 = snailAhVertexInfoBase_0_;
            let _e1542 = textureDimensions(u_layer_tex_0_image, 0i);
            let _e1545 = local_338;
            let _e1548 = vec2<i32>(vec2<i32>(_e1542).x, _e1545.y);
            let _e1549 = textureDimensions(u_layer_tex_0_image, 0i);
            let _e1554 = vec2<i32>(_e1548.x, vec2<i32>(_e1549).y);
            local_338 = _e1554;
            let _e1560 = (((_e1541.y * _e1554.x) + _e1541.x) + (_e1538 >> bitcast<u32>(2i)));
            let _e1569 = vec2<i32>((_e1560 - (i32(floor((f32(_e1560) / f32(_e1554.x)))) * _e1554.x)), (_e1560 / _e1554.x));
            let _e1572 = vec3<i32>(_e1569.x, _e1569.y, 0i);
            let _e1575 = textureLoad(u_layer_tex_0_image, _e1572.xy, _e1572.z);
            local_339 = _e1575;
            let _e1576 = (_e1538 & 3i);
            local_340 = _e1576;
            if (_e1576 == 0i) {
                let _e1578 = local_339;
                local_341 = _e1578.x;
            } else {
                let _e1580 = local_340;
                if (_e1580 == 1i) {
                    let _e1582 = local_339;
                    local_341 = _e1582.y;
                } else {
                    let _e1584 = local_340;
                    if (_e1584 == 2i) {
                        let _e1586 = local_339;
                        local_341 = _e1586.z;
                    } else {
                        let _e1588 = local_339;
                        local_341 = _e1588.w;
                    }
                }
            }
            let _e1590 = local_341;
            local_444 = 0i;
            let _e1591 = local_434;
            local_445 = _e1591;
            let _e1592 = local_425;
            local_446 = _e1592;
            let _e1593 = local_427;
            local_447 = _e1593;
            local_448 = _e1590;
            let _e1594 = local_421;
            local_449 = _e1594.x;
            let _e1596 = local_109;
            let _e1597 = local_110;
            let _e1598 = local_111;
            let _e1599 = local_112;
            let _e1600 = local_113;
            let _e1601 = local_114;
            let _e1602 = local_115;
            let _e1603 = local_116;
            let _e1604 = local_117;
            let _e1605 = local_118;
            let _e1606 = local_119;
            let _e1607 = local_120;
            let _e1608 = local_121;
            let _e1609 = local_122;
            let _e1610 = local_123;
            local_61 = _e1610;
            local_60 = _e1609;
            local_59 = _e1608;
            local_58 = _e1607;
            local_57 = _e1606;
            local_56 = _e1605;
            local_55 = _e1604;
            local_54 = _e1603;
            local_53 = _e1602;
            local_52 = _e1601;
            local_51 = _e1600;
            local_50 = _e1599;
            local_49 = _e1598;
            local_48 = _e1597;
            local_47 = _e1596;
            local_271 = false;
            switch bitcast<i32>(0u) {
                default: {
                    local_450 = 0i;
                    let _e1612 = local_449;
                    if !((abs(_e1612) <= 340282300000000000000000000000000000000f)) {
                        local_273 = true;
                    } else {
                        let _e1616 = local_449;
                        local_273 = (_e1616 <= 0f);
                    }
                    let _e1618 = local_273;
                    if _e1618 {
                        local_273 = true;
                    } else {
                        let _e1619 = local_446;
                        local_273 = (_e1619 < 0i);
                    }
                    let _e1621 = local_273;
                    if _e1621 {
                        local_273 = true;
                    } else {
                        let _e1622 = local_446;
                        local_273 = (_e1622 > 16i);
                    }
                    let _e1624 = local_273;
                    if _e1624 {
                        local_273 = true;
                    } else {
                        let _e1625 = local_447;
                        local_273 = !((abs(_e1625) <= 340282300000000000000000000000000000000f));
                    }
                    let _e1629 = local_273;
                    if _e1629 {
                        local_273 = true;
                    } else {
                        let _e1630 = local_447;
                        local_273 = (_e1630 < 0f);
                    }
                    let _e1632 = local_273;
                    if _e1632 {
                        local_271 = true;
                        local_272 = false;
                        break;
                    }
                    let _e1633 = local_444;
                    let _e1634 = (_e1633 == 0i);
                    local_274 = _e1634;
                    if _e1634 {
                        let _e1635 = local_61;
                        local_273 = (_e1635 == 0i);
                    } else {
                        local_273 = false;
                    }
                    let _e1637 = local_273;
                    if _e1637 {
                        let _e1638 = local_60;
                        local_273 = (_e1638 == 0i);
                    } else {
                        local_273 = false;
                    }
                    let _e1640 = local_273;
                    if _e1640 {
                        let _e1641 = local_59;
                        local_273 = (_e1641 == 0i);
                    } else {
                        local_273 = false;
                    }
                    let _e1643 = local_273;
                    if _e1643 {
                        let _e1644 = local_58;
                        local_273 = (_e1644 == 0i);
                    } else {
                        local_273 = false;
                    }
                    let _e1646 = local_273;
                    if _e1646 {
                        local_273 = true;
                    } else {
                        let _e1647 = local_444;
                        if (_e1647 == 1i) {
                            let _e1649 = local_57;
                            local_273 = (_e1649 == 0i);
                        } else {
                            local_273 = false;
                        }
                        let _e1651 = local_273;
                        if _e1651 {
                            let _e1652 = local_56;
                            local_273 = (_e1652 == 0i);
                        } else {
                            local_273 = false;
                        }
                        let _e1654 = local_273;
                        if _e1654 {
                            let _e1655 = local_55;
                            local_273 = (_e1655 == 0i);
                        } else {
                            local_273 = false;
                        }
                    }
                    let _e1657 = local_273;
                    if _e1657 {
                        local_271 = true;
                        local_272 = true;
                        break;
                    }
                    let _e1658 = local_445;
                    let _e1659 = (_e1658 + 0i);
                    let _e1662 = snailAhVertexInfoBase_0_;
                    let _e1663 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e1666 = local_267;
                    let _e1669 = vec2<i32>(vec2<i32>(_e1663).x, _e1666.y);
                    let _e1670 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e1675 = vec2<i32>(_e1669.x, vec2<i32>(_e1670).y);
                    local_267 = _e1675;
                    let _e1681 = (((_e1662.y * _e1675.x) + _e1662.x) + (_e1659 >> bitcast<u32>(2i)));
                    let _e1690 = vec2<i32>((_e1681 - (i32(floor((f32(_e1681) / f32(_e1675.x)))) * _e1675.x)), (_e1681 / _e1675.x));
                    let _e1693 = vec3<i32>(_e1690.x, _e1690.y, 0i);
                    let _e1696 = textureLoad(u_layer_tex_0_image, _e1693.xy, _e1693.z);
                    local_268 = _e1696;
                    let _e1697 = (_e1659 & 3i);
                    local_269 = _e1697;
                    if (_e1697 == 0i) {
                        let _e1699 = local_268;
                        local_270 = _e1699.x;
                    } else {
                        let _e1701 = local_269;
                        if (_e1701 == 1i) {
                            let _e1703 = local_268;
                            local_270 = _e1703.y;
                        } else {
                            let _e1705 = local_269;
                            if (_e1705 == 2i) {
                                let _e1707 = local_268;
                                local_270 = _e1707.z;
                            } else {
                                let _e1709 = local_268;
                                local_270 = _e1709.w;
                            }
                        }
                    }
                    let _e1711 = local_270;
                    let _e1712 = i32(_e1711);
                    local_275 = _e1712;
                    if (_e1712 <= 0i) {
                        local_273 = true;
                    } else {
                        let _e1714 = local_275;
                        local_273 = (_e1714 > 16i);
                    }
                    let _e1716 = local_273;
                    if _e1716 {
                        let _e1717 = local_275;
                        local_271 = true;
                        local_272 = (_e1717 == 0i);
                        break;
                    }
                    let _e1719 = local_444;
                    let _e1720 = (_e1719 == 1i);
                    local_276 = _e1720;
                    if _e1720 {
                        let _e1721 = local_57;
                        local_273 = (_e1721 == 2i);
                    } else {
                        local_273 = false;
                    }
                    let _e1723 = local_274;
                    if _e1723 {
                        let _e1724 = local_58;
                        local_277 = (_e1724 == 1i);
                    } else {
                        local_277 = false;
                    }
                    let _e1726 = local_277;
                    if _e1726 {
                        let _e1727 = local_448;
                        local_277 = !((abs(_e1727) <= 340282300000000000000000000000000000000f));
                    } else {
                        local_277 = false;
                    }
                    let _e1731 = local_277;
                    if _e1731 {
                        local_271 = true;
                        local_272 = false;
                        break;
                    }
                    local_278 = 0i;
                    loop {
                        let _e1732 = local_278;
                        if (_e1732 < 16i) {
                        } else {
                            break;
                        }
                        let _e1734 = local_278;
                        let _e1735 = local_275;
                        if (_e1734 >= _e1735) {
                            break;
                        }
                        let _e1737 = local_445;
                        let _e1739 = local_278;
                        let _e1741 = ((_e1737 + 1i) + (4i * _e1739));
                        local_279 = _e1741;
                        let _e1742 = (_e1741 + 0i);
                        let _e1745 = snailAhVertexInfoBase_0_;
                        let _e1746 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1749 = local_263;
                        let _e1752 = vec2<i32>(vec2<i32>(_e1746).x, _e1749.y);
                        let _e1753 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1758 = vec2<i32>(_e1752.x, vec2<i32>(_e1753).y);
                        local_263 = _e1758;
                        let _e1764 = (((_e1745.y * _e1758.x) + _e1745.x) + (_e1742 >> bitcast<u32>(2i)));
                        let _e1773 = vec2<i32>((_e1764 - (i32(floor((f32(_e1764) / f32(_e1758.x)))) * _e1758.x)), (_e1764 / _e1758.x));
                        let _e1776 = vec3<i32>(_e1773.x, _e1773.y, 0i);
                        let _e1779 = textureLoad(u_layer_tex_0_image, _e1776.xy, _e1776.z);
                        local_264 = _e1779;
                        let _e1780 = (_e1742 & 3i);
                        local_265 = _e1780;
                        if (_e1780 == 0i) {
                            let _e1782 = local_264;
                            local_266 = _e1782.x;
                        } else {
                            let _e1784 = local_265;
                            if (_e1784 == 1i) {
                                let _e1786 = local_264;
                                local_266 = _e1786.y;
                            } else {
                                let _e1788 = local_265;
                                if (_e1788 == 2i) {
                                    let _e1790 = local_264;
                                    local_266 = _e1790.z;
                                } else {
                                    let _e1792 = local_264;
                                    local_266 = _e1792.w;
                                }
                            }
                        }
                        let _e1794 = local_266;
                        let _e1795 = local_278;
                        local_280[_e1795] = _e1794;
                        let _e1797 = local_279;
                        let _e1798 = (_e1797 + 1i);
                        let _e1801 = snailAhVertexInfoBase_0_;
                        let _e1802 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1805 = local_259;
                        let _e1808 = vec2<i32>(vec2<i32>(_e1802).x, _e1805.y);
                        let _e1809 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1814 = vec2<i32>(_e1808.x, vec2<i32>(_e1809).y);
                        local_259 = _e1814;
                        let _e1820 = (((_e1801.y * _e1814.x) + _e1801.x) + (_e1798 >> bitcast<u32>(2i)));
                        let _e1829 = vec2<i32>((_e1820 - (i32(floor((f32(_e1820) / f32(_e1814.x)))) * _e1814.x)), (_e1820 / _e1814.x));
                        let _e1832 = vec3<i32>(_e1829.x, _e1829.y, 0i);
                        let _e1835 = textureLoad(u_layer_tex_0_image, _e1832.xy, _e1832.z);
                        local_260 = _e1835;
                        let _e1836 = (_e1798 & 3i);
                        local_261 = _e1836;
                        if (_e1836 == 0i) {
                            let _e1838 = local_260;
                            local_262 = _e1838.x;
                        } else {
                            let _e1840 = local_261;
                            if (_e1840 == 1i) {
                                let _e1842 = local_260;
                                local_262 = _e1842.y;
                            } else {
                                let _e1844 = local_261;
                                if (_e1844 == 2i) {
                                    let _e1846 = local_260;
                                    local_262 = _e1846.z;
                                } else {
                                    let _e1848 = local_260;
                                    local_262 = _e1848.w;
                                }
                            }
                        }
                        let _e1850 = local_262;
                        let _e1851 = local_278;
                        local_281[_e1851] = _e1850;
                        let _e1853 = local_279;
                        let _e1854 = (_e1853 + 2i);
                        let _e1857 = snailAhVertexInfoBase_0_;
                        let _e1858 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1861 = local_255;
                        let _e1864 = vec2<i32>(vec2<i32>(_e1858).x, _e1861.y);
                        let _e1865 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1870 = vec2<i32>(_e1864.x, vec2<i32>(_e1865).y);
                        local_255 = _e1870;
                        let _e1876 = (((_e1857.y * _e1870.x) + _e1857.x) + (_e1854 >> bitcast<u32>(2i)));
                        let _e1885 = vec2<i32>((_e1876 - (i32(floor((f32(_e1876) / f32(_e1870.x)))) * _e1870.x)), (_e1876 / _e1870.x));
                        let _e1888 = vec3<i32>(_e1885.x, _e1885.y, 0i);
                        let _e1891 = textureLoad(u_layer_tex_0_image, _e1888.xy, _e1888.z);
                        local_256 = _e1891;
                        let _e1892 = (_e1854 & 3i);
                        local_257 = _e1892;
                        if (_e1892 == 0i) {
                            let _e1894 = local_256;
                            local_258 = _e1894.x;
                        } else {
                            let _e1896 = local_257;
                            if (_e1896 == 1i) {
                                let _e1898 = local_256;
                                local_258 = _e1898.y;
                            } else {
                                let _e1900 = local_257;
                                if (_e1900 == 2i) {
                                    let _e1902 = local_256;
                                    local_258 = _e1902.z;
                                } else {
                                    let _e1904 = local_256;
                                    local_258 = _e1904.w;
                                }
                            }
                        }
                        let _e1906 = local_258;
                        let _e1907 = bitcast<u32>(_e1906);
                        let _e1908 = local_278;
                        local_282[_e1908] = (bitcast<i32>((_e1907 << bitcast<u32>(16u))) >> bitcast<u32>(16i));
                        local_283[_e1908] = (bitcast<i32>(_e1907) >> bitcast<u32>(16i));
                        let _e1919 = local_279;
                        let _e1920 = (_e1919 + 3i);
                        let _e1923 = snailAhVertexInfoBase_0_;
                        let _e1924 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1927 = local_251;
                        let _e1930 = vec2<i32>(vec2<i32>(_e1924).x, _e1927.y);
                        let _e1931 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1936 = vec2<i32>(_e1930.x, vec2<i32>(_e1931).y);
                        local_251 = _e1936;
                        let _e1942 = (((_e1923.y * _e1936.x) + _e1923.x) + (_e1920 >> bitcast<u32>(2i)));
                        let _e1951 = vec2<i32>((_e1942 - (i32(floor((f32(_e1942) / f32(_e1936.x)))) * _e1936.x)), (_e1942 / _e1936.x));
                        let _e1954 = vec3<i32>(_e1951.x, _e1951.y, 0i);
                        let _e1957 = textureLoad(u_layer_tex_0_image, _e1954.xy, _e1954.z);
                        local_252 = _e1957;
                        let _e1958 = (_e1920 & 3i);
                        local_253 = _e1958;
                        if (_e1958 == 0i) {
                            let _e1960 = local_252;
                            local_254 = _e1960.x;
                        } else {
                            let _e1962 = local_253;
                            if (_e1962 == 1i) {
                                let _e1964 = local_252;
                                local_254 = _e1964.y;
                            } else {
                                let _e1966 = local_253;
                                if (_e1966 == 2i) {
                                    let _e1968 = local_252;
                                    local_254 = _e1968.z;
                                } else {
                                    let _e1970 = local_252;
                                    local_254 = _e1970.w;
                                }
                            }
                        }
                        let _e1972 = local_254;
                        let _e1973 = bitcast<u32>(_e1972);
                        local_284 = _e1973;
                        let _e1974 = local_278;
                        local_285[_e1974] = ((_e1973 & 1u) != 0u);
                        local_286[_e1974] = ((_e1973 & 2u) != 0u);
                        if ((_e1973 & 4u) == 0u) {
                            local_271 = true;
                            local_272 = false;
                            break;
                        }
                        let _e1983 = local_284;
                        if ((_e1983 & 8u) != 0u) {
                            local_287 = -1i;
                        } else {
                            local_287 = 1i;
                        }
                        let _e1986 = local_278;
                        let _e1987 = local_287;
                        local_288[_e1986] = _e1987;
                        let _e1989 = local_273;
                        if _e1989 {
                            local_289 = 10u;
                        } else {
                            local_289 = 4u;
                        }
                        let _e1990 = local_284;
                        let _e1991 = local_289;
                        let _e1995 = bitcast<i32>(((_e1990 >> bitcast<u32>(_e1991)) & 63u));
                        local_290 = _e1995;
                        if (_e1995 >= 62i) {
                            local_291 = -1i;
                        } else {
                            let _e1997 = local_290;
                            local_291 = _e1997;
                        }
                        let _e1998 = local_278;
                        let _e1999 = local_291;
                        local_292[_e1998] = _e1999;
                        let _e2001 = local_290;
                        if (_e2001 >= 63i) {
                            let _e2003 = local_278;
                            let _e2005 = local_285[_e2003];
                            local_277 = _e2005;
                        } else {
                            local_277 = false;
                        }
                        let _e2006 = local_277;
                        if _e2006 {
                            let _e2007 = local_278;
                            let _e2009 = local_283[_e2007];
                            local_293 = (_e2009 >= 0i);
                        } else {
                            local_293 = false;
                        }
                        let _e2011 = local_293;
                        if _e2011 {
                            local_271 = true;
                            local_272 = false;
                            break;
                        }
                        let _e2012 = local_278;
                        local_294[_e2012] = false;
                        let _e2015 = local_280[_e2012];
                        if !((abs(_e2015) <= 340282300000000000000000000000000000000f)) {
                            local_295 = true;
                        } else {
                            let _e2019 = local_278;
                            let _e2021 = local_281[_e2019];
                            local_295 = !((abs(_e2021) <= 340282300000000000000000000000000000000f));
                        }
                        let _e2025 = local_295;
                        if _e2025 {
                            local_296 = true;
                        } else {
                            let _e2026 = local_278;
                            let _e2028 = local_281[_e2026];
                            local_296 = (_e2028 < 0f);
                        }
                        let _e2030 = local_296;
                        if _e2030 {
                            local_297 = true;
                        } else {
                            let _e2031 = local_278;
                            let _e2033 = local_282[_e2031];
                            local_297 = (_e2033 < -1i);
                        }
                        let _e2035 = local_297;
                        if _e2035 {
                            local_298 = true;
                        } else {
                            let _e2036 = local_278;
                            let _e2038 = local_282[_e2036];
                            let _e2039 = local_275;
                            local_298 = (_e2038 >= _e2039);
                        }
                        let _e2041 = local_298;
                        if _e2041 {
                            local_299 = true;
                        } else {
                            let _e2042 = local_278;
                            let _e2044 = local_283[_e2042];
                            local_299 = (_e2044 < -1i);
                        }
                        let _e2046 = local_299;
                        if _e2046 {
                            local_300 = true;
                        } else {
                            let _e2047 = local_278;
                            let _e2049 = local_283[_e2047];
                            let _e2050 = local_446;
                            local_300 = (_e2049 >= _e2050);
                        }
                        let _e2052 = local_300;
                        if _e2052 {
                            local_271 = true;
                            local_272 = false;
                            break;
                        }
                        let _e2053 = local_278;
                        local_278 = (_e2053 + 1i);
                        continue;
                    }
                    let _e2055 = local_271;
                    if _e2055 {
                        break;
                    }
                    local_278 = 0i;
                    loop {
                        let _e2056 = local_278;
                        if (_e2056 < 16i) {
                        } else {
                            break;
                        }
                        let _e2058 = local_278;
                        let _e2059 = local_446;
                        if (_e2058 >= _e2059) {
                            break;
                        }
                        let _e2061 = local_278;
                        let _e2062 = (2i * _e2061);
                        local_301 = _e2062;
                        let _e2063 = (12i + _e2062);
                        let _e2066 = snailAhVertexInfoBase_0_;
                        let _e2067 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e2070 = local_247;
                        let _e2073 = vec2<i32>(vec2<i32>(_e2067).x, _e2070.y);
                        let _e2074 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e2079 = vec2<i32>(_e2073.x, vec2<i32>(_e2074).y);
                        local_247 = _e2079;
                        let _e2085 = (((_e2066.y * _e2079.x) + _e2066.x) + (_e2063 >> bitcast<u32>(2i)));
                        let _e2094 = vec2<i32>((_e2085 - (i32(floor((f32(_e2085) / f32(_e2079.x)))) * _e2079.x)), (_e2085 / _e2079.x));
                        let _e2097 = vec3<i32>(_e2094.x, _e2094.y, 0i);
                        let _e2100 = textureLoad(u_layer_tex_0_image, _e2097.xy, _e2097.z);
                        local_248 = _e2100;
                        let _e2101 = (_e2063 & 3i);
                        local_249 = _e2101;
                        if (_e2101 == 0i) {
                            let _e2103 = local_248;
                            local_250 = _e2103.x;
                        } else {
                            let _e2105 = local_249;
                            if (_e2105 == 1i) {
                                let _e2107 = local_248;
                                local_250 = _e2107.y;
                            } else {
                                let _e2109 = local_249;
                                if (_e2109 == 2i) {
                                    let _e2111 = local_248;
                                    local_250 = _e2111.z;
                                } else {
                                    let _e2113 = local_248;
                                    local_250 = _e2113.w;
                                }
                            }
                        }
                        let _e2115 = local_250;
                        local_302 = _e2115;
                        let _e2116 = local_301;
                        let _e2118 = (12i + (_e2116 + 1i));
                        let _e2121 = snailAhVertexInfoBase_0_;
                        let _e2122 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e2125 = local_243;
                        let _e2128 = vec2<i32>(vec2<i32>(_e2122).x, _e2125.y);
                        let _e2129 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e2134 = vec2<i32>(_e2128.x, vec2<i32>(_e2129).y);
                        local_243 = _e2134;
                        let _e2140 = (((_e2121.y * _e2134.x) + _e2121.x) + (_e2118 >> bitcast<u32>(2i)));
                        let _e2149 = vec2<i32>((_e2140 - (i32(floor((f32(_e2140) / f32(_e2134.x)))) * _e2134.x)), (_e2140 / _e2134.x));
                        let _e2152 = vec3<i32>(_e2149.x, _e2149.y, 0i);
                        let _e2155 = textureLoad(u_layer_tex_0_image, _e2152.xy, _e2152.z);
                        local_244 = _e2155;
                        let _e2156 = (_e2118 & 3i);
                        local_245 = _e2156;
                        if (_e2156 == 0i) {
                            let _e2158 = local_244;
                            local_246 = _e2158.x;
                        } else {
                            let _e2160 = local_245;
                            if (_e2160 == 1i) {
                                let _e2162 = local_244;
                                local_246 = _e2162.y;
                            } else {
                                let _e2164 = local_245;
                                if (_e2164 == 2i) {
                                    let _e2166 = local_244;
                                    local_246 = _e2166.z;
                                } else {
                                    let _e2168 = local_244;
                                    local_246 = _e2168.w;
                                }
                            }
                        }
                        let _e2170 = local_246;
                        local_303 = _e2170;
                        let _e2171 = local_302;
                        if !((abs(_e2171) <= 340282300000000000000000000000000000000f)) {
                            local_277 = true;
                        } else {
                            let _e2175 = local_303;
                            local_277 = !((abs(_e2175) <= 340282300000000000000000000000000000000f));
                        }
                        let _e2179 = local_277;
                        if _e2179 {
                            local_271 = true;
                            local_272 = false;
                            break;
                        }
                        let _e2180 = local_278;
                        local_278 = (_e2180 + 1i);
                        continue;
                    }
                    let _e2182 = local_271;
                    if _e2182 {
                        break;
                    }
                    let _e2183 = local_276;
                    if _e2183 {
                        let _e2184 = local_55;
                        local_277 = (_e2184 == 1i);
                    } else {
                        local_277 = false;
                    }
                    let _e2186 = local_277;
                    if _e2186 {
                        let _e2187 = local_47;
                        local_304 = _e2187;
                    } else {
                        local_304 = 0f;
                    }
                    local_278 = 0i;
                    loop {
                        let _e2188 = local_278;
                        if (_e2188 < 16i) {
                        } else {
                            break;
                        }
                        let _e2190 = local_278;
                        let _e2191 = local_275;
                        if (_e2190 >= _e2191) {
                            break;
                        }
                        let _e2193 = local_278;
                        let _e2195 = local_282[_e2193];
                        if (_e2195 >= 0i) {
                            let _e2197 = local_278;
                            let _e2199 = local_282[_e2197];
                            let _e2201 = local_280[_e2199];
                            let _e2203 = local_280[_e2197];
                            local_277 = (_e2201 > _e2203);
                        } else {
                            local_277 = false;
                        }
                        let _e2205 = local_273;
                        if _e2205 {
                            let _e2206 = local_278;
                            let _e2208 = local_283[_e2206];
                            local_293 = (_e2208 >= 0i);
                        } else {
                            local_293 = false;
                        }
                        let _e2210 = local_273;
                        if !(_e2210) {
                            let _e2212 = local_277;
                            if _e2212 {
                                local_287 = -1i;
                            } else {
                                local_287 = 1i;
                            }
                            let _e2213 = local_278;
                            let _e2214 = local_287;
                            local_288[_e2213] = _e2214;
                        }
                        let _e2216 = local_293;
                        if _e2216 {
                            let _e2217 = local_278;
                            let _e2219 = local_283[_e2217];
                            let _e2221 = (12i + (2i * _e2219));
                            let _e2224 = snailAhVertexInfoBase_0_;
                            let _e2225 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2228 = local_239;
                            let _e2231 = vec2<i32>(vec2<i32>(_e2225).x, _e2228.y);
                            let _e2232 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2237 = vec2<i32>(_e2231.x, vec2<i32>(_e2232).y);
                            local_239 = _e2237;
                            let _e2243 = (((_e2224.y * _e2237.x) + _e2224.x) + (_e2221 >> bitcast<u32>(2i)));
                            let _e2252 = vec2<i32>((_e2243 - (i32(floor((f32(_e2243) / f32(_e2237.x)))) * _e2237.x)), (_e2243 / _e2237.x));
                            let _e2255 = vec3<i32>(_e2252.x, _e2252.y, 0i);
                            let _e2258 = textureLoad(u_layer_tex_0_image, _e2255.xy, _e2255.z);
                            local_240 = _e2258;
                            let _e2259 = (_e2221 & 3i);
                            local_241 = _e2259;
                            if (_e2259 == 0i) {
                                let _e2261 = local_240;
                                local_242 = _e2261.x;
                            } else {
                                let _e2263 = local_241;
                                if (_e2263 == 1i) {
                                    let _e2265 = local_240;
                                    local_242 = _e2265.y;
                                } else {
                                    let _e2267 = local_241;
                                    if (_e2267 == 2i) {
                                        let _e2269 = local_240;
                                        local_242 = _e2269.z;
                                    } else {
                                        let _e2271 = local_240;
                                        local_242 = _e2271.w;
                                    }
                                }
                            }
                            let _e2273 = local_242;
                            local_305 = _e2273;
                            let _e2274 = local_278;
                            let _e2276 = local_283[_e2274];
                            let _e2279 = (12i + ((2i * _e2276) + 1i));
                            let _e2282 = snailAhVertexInfoBase_0_;
                            let _e2283 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2286 = local_235;
                            let _e2289 = vec2<i32>(vec2<i32>(_e2283).x, _e2286.y);
                            let _e2290 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2295 = vec2<i32>(_e2289.x, vec2<i32>(_e2290).y);
                            local_235 = _e2295;
                            let _e2301 = (((_e2282.y * _e2295.x) + _e2282.x) + (_e2279 >> bitcast<u32>(2i)));
                            let _e2310 = vec2<i32>((_e2301 - (i32(floor((f32(_e2301) / f32(_e2295.x)))) * _e2295.x)), (_e2301 / _e2295.x));
                            let _e2313 = vec3<i32>(_e2310.x, _e2310.y, 0i);
                            let _e2316 = textureLoad(u_layer_tex_0_image, _e2313.xy, _e2313.z);
                            local_236 = _e2316;
                            let _e2317 = (_e2279 & 3i);
                            local_237 = _e2317;
                            if (_e2317 == 0i) {
                                let _e2319 = local_236;
                                local_238 = _e2319.x;
                            } else {
                                let _e2321 = local_237;
                                if (_e2321 == 1i) {
                                    let _e2323 = local_236;
                                    local_238 = _e2323.y;
                                } else {
                                    let _e2325 = local_237;
                                    if (_e2325 == 2i) {
                                        let _e2327 = local_236;
                                        local_238 = _e2327.z;
                                    } else {
                                        let _e2329 = local_236;
                                        local_238 = _e2329.w;
                                    }
                                }
                            }
                            let _e2331 = local_238;
                            local_306 = _e2331;
                            let _e2332 = local_278;
                            let _e2334 = local_285[_e2332];
                            if _e2334 {
                                let _e2335 = local_276;
                                local_295 = _e2335;
                            } else {
                                local_295 = false;
                            }
                            let _e2336 = local_295;
                            if _e2336 {
                                let _e2337 = local_55;
                                local_296 = (_e2337 == 0i);
                            } else {
                                local_296 = false;
                            }
                            let _e2339 = local_296;
                            if _e2339 {
                                let _e2340 = local_278;
                                let _e2342 = local_280[_e2340];
                                local_307[_e2340] = _e2342;
                            } else {
                                let _e2344 = local_278;
                                let _e2345 = local_305;
                                let _e2346 = local_449;
                                local_307[_e2344] = (round((_e2345 * _e2346)) / _e2346);
                                let _e2352 = local_285[_e2344];
                                if _e2352 {
                                    let _e2353 = local_306;
                                    let _e2354 = local_305;
                                    let _e2356 = local_449;
                                    let _e2359 = local_304;
                                    local_297 = (abs(((_e2353 - _e2354) * _e2356)) >= _e2359);
                                } else {
                                    local_297 = false;
                                }
                                let _e2361 = local_297;
                                if _e2361 {
                                    let _e2362 = local_278;
                                    let _e2364 = local_307[_e2362];
                                    let _e2365 = local_306;
                                    let _e2366 = local_305;
                                    local_307[_e2362] = (_e2364 + (_e2365 - _e2366));
                                }
                            }
                        } else {
                            let _e2370 = local_278;
                            let _e2372 = local_280[_e2370];
                            let _e2373 = local_449;
                            local_307[_e2370] = (round((_e2372 * _e2373)) / _e2373);
                        }
                        let _e2378 = local_278;
                        local_278 = (_e2378 + 1i);
                        continue;
                    }
                    let _e2380 = local_449;
                    local_308 = (1f / _e2380);
                    let _e2382 = local_274;
                    if _e2382 {
                        let _e2383 = local_60;
                        local_287 = _e2383;
                    } else {
                        let _e2384 = local_56;
                        local_287 = _e2384;
                    }
                    let _e2385 = local_274;
                    if _e2385 {
                        let _e2386 = local_51;
                        local_304 = _e2386;
                    } else {
                        let _e2387 = local_49;
                        local_304 = _e2387;
                    }
                    let _e2388 = local_274;
                    if _e2388 {
                        let _e2389 = local_50;
                        local_309 = _e2389;
                    } else {
                        let _e2390 = local_48;
                        local_309 = _e2390;
                    }
                    let _e2391 = local_274;
                    if _e2391 {
                        let _e2392 = local_61;
                        local_273 = (_e2392 == 1i);
                    } else {
                        let _e2394 = local_57;
                        local_273 = (_e2394 != 0i);
                    }
                    let _e2396 = local_274;
                    if _e2396 {
                        let _e2397 = local_59;
                        local_277 = (_e2397 == 1i);
                    } else {
                        local_277 = false;
                    }
                    local_293 = false;
                    local_310 = 0f;
                    local_311 = 0f;
                    local_312 = 0f;
                    local_313 = 0f;
                    local_314 = 0f;
                    local_291 = 0i;
                    local_278 = 0i;
                    local_315 = 0i;
                    loop {
                        let _e2399 = local_278;
                        if (_e2399 < 16i) {
                        } else {
                            break;
                        }
                        let _e2401 = local_278;
                        let _e2402 = local_275;
                        if (_e2401 >= _e2402) {
                            break;
                        }
                        let _e2404 = local_278;
                        let _e2406 = local_282[_e2404];
                        local_316 = _e2406;
                        let _e2408 = local_282[_e2404];
                        if (_e2408 < 0i) {
                            local_295 = true;
                        } else {
                            let _e2410 = local_316;
                            let _e2411 = local_278;
                            local_295 = (_e2410 <= _e2411);
                        }
                        let _e2413 = local_295;
                        if _e2413 {
                            let _e2414 = local_293;
                            local_297 = _e2414;
                            let _e2415 = local_278;
                            local_278 = (_e2415 + 1i);
                            continue;
                        }
                        let _e2417 = local_278;
                        let _e2419 = local_281[_e2417];
                        local_318 = _e2419;
                        let _e2420 = local_447;
                        local_319 = _e2420;
                        let _e2421 = local_304;
                        local_320 = _e2421;
                        if (_e2420 > 0f) {
                            let _e2423 = local_318;
                            let _e2424 = local_319;
                            let _e2427 = local_320;
                            local_233 = (abs((_e2423 - _e2424)) <= (_e2427 * _e2424));
                        } else {
                            local_233 = false;
                        }
                        let _e2430 = local_233;
                        if _e2430 {
                            let _e2431 = local_319;
                            local_234 = _e2431;
                        } else {
                            let _e2432 = local_318;
                            local_234 = _e2432;
                        }
                        let _e2433 = local_234;
                        local_317 = _e2433;
                        let _e2434 = local_278;
                        let _e2436 = local_281[_e2434];
                        local_321 = _e2436;
                        let _e2437 = local_287;
                        if (_e2437 == 2i) {
                            local_296 = true;
                        } else {
                            let _e2439 = local_287;
                            if (_e2439 == 1i) {
                                let _e2441 = local_317;
                                let _e2442 = local_449;
                                let _e2444 = local_309;
                                local_296 = ((_e2441 * _e2442) < _e2444);
                            } else {
                                local_296 = false;
                            }
                        }
                        let _e2446 = local_296;
                        if _e2446 {
                            let _e2447 = local_317;
                            let _e2448 = local_449;
                            let _e2452 = local_308;
                            local_322 = (max(round((_e2447 * _e2448)), 1f) * _e2452);
                        } else {
                            let _e2454 = local_321;
                            local_322 = _e2454;
                        }
                        let _e2455 = local_277;
                        if _e2455 {
                            let _e2456 = local_293;
                            if _e2456 {
                                let _e2457 = local_278;
                                let _e2458 = local_310;
                                let _e2460 = local_280[_e2457];
                                let _e2461 = local_311;
                                let _e2463 = local_449;
                                let _e2466 = local_308;
                                local_307[_e2457] = (_e2458 + (round(((_e2460 - _e2461) * _e2463)) * _e2466));
                                let _e2470 = local_312;
                                local_323 = _e2470;
                                let _e2471 = local_313;
                                local_324 = _e2471;
                                let _e2472 = local_293;
                                local_297 = _e2472;
                            } else {
                                let _e2473 = local_278;
                                let _e2475 = local_280[_e2473];
                                let _e2476 = local_449;
                                let _e2479 = (round((_e2475 * _e2476)) / _e2476);
                                local_307[_e2473] = _e2479;
                                local_323 = _e2479;
                                let _e2482 = local_280[_e2473];
                                local_324 = _e2482;
                                local_297 = true;
                            }
                            let _e2483 = local_316;
                            let _e2484 = local_278;
                            let _e2486 = local_307[_e2484];
                            let _e2487 = local_322;
                            local_307[_e2483] = (_e2486 + _e2487);
                            let _e2490 = local_323;
                            let _e2492 = local_280[_e2484];
                            let _e2493 = local_324;
                            let _e2495 = local_449;
                            let _e2498 = local_308;
                            let _e2502 = local_315;
                            let _e2505 = local_307[_e2484];
                            local_323 = _e2505;
                            let _e2507 = local_280[_e2484];
                            local_324 = _e2507;
                            local_325 = _e2490;
                            local_326 = _e2493;
                            local_327 = ((_e2490 + (round(((_e2492 - _e2493) * _e2495)) * _e2498)) + _e2487);
                            local_328 = _e2483;
                            local_329 = (_e2502 + 1i);
                        } else {
                            let _e2508 = local_274;
                            if _e2508 {
                                let _e2509 = local_61;
                                local_297 = (_e2509 != 0i);
                            } else {
                                let _e2511 = local_57;
                                local_297 = (_e2511 != 0i);
                            }
                            let _e2513 = local_297;
                            if _e2513 {
                                let _e2514 = local_278;
                                let _e2516 = local_283[_e2514];
                                local_298 = (_e2516 >= 0i);
                            } else {
                                local_298 = false;
                            }
                            let _e2518 = local_297;
                            if _e2518 {
                                let _e2519 = local_316;
                                let _e2521 = local_283[_e2519];
                                local_299 = (_e2521 >= 0i);
                            } else {
                                local_299 = false;
                            }
                            let _e2523 = local_273;
                            if !(_e2523) {
                                let _e2525 = local_278;
                                let _e2527 = local_280[_e2525];
                                local_307[_e2525] = _e2527;
                            }
                            let _e2529 = local_299;
                            if _e2529 {
                                let _e2530 = local_298;
                                local_300 = !(_e2530);
                            } else {
                                local_300 = false;
                            }
                            let _e2532 = local_300;
                            if _e2532 {
                                let _e2533 = local_273;
                                local_330 = _e2533;
                            } else {
                                local_330 = false;
                            }
                            let _e2534 = local_330;
                            if _e2534 {
                                let _e2535 = local_278;
                                let _e2536 = local_316;
                                let _e2538 = local_307[_e2536];
                                let _e2539 = local_322;
                                local_307[_e2535] = (_e2538 - _e2539);
                            } else {
                                let _e2542 = local_316;
                                let _e2543 = local_278;
                                let _e2545 = local_307[_e2543];
                                let _e2546 = local_322;
                                local_307[_e2542] = (_e2545 + _e2546);
                            }
                            let _e2549 = local_293;
                            local_297 = _e2549;
                            let _e2550 = local_310;
                            local_323 = _e2550;
                            let _e2551 = local_311;
                            local_324 = _e2551;
                            let _e2552 = local_312;
                            local_325 = _e2552;
                            let _e2553 = local_313;
                            local_326 = _e2553;
                            let _e2554 = local_314;
                            local_327 = _e2554;
                            let _e2555 = local_291;
                            local_328 = _e2555;
                            let _e2556 = local_315;
                            local_329 = _e2556;
                        }
                        let _e2557 = local_278;
                        local_294[_e2557] = true;
                        let _e2559 = local_316;
                        local_294[_e2559] = true;
                        let _e2561 = local_323;
                        local_310 = _e2561;
                        let _e2562 = local_324;
                        local_311 = _e2562;
                        let _e2563 = local_325;
                        local_312 = _e2563;
                        let _e2564 = local_326;
                        local_313 = _e2564;
                        let _e2565 = local_327;
                        local_314 = _e2565;
                        let _e2566 = local_328;
                        local_291 = _e2566;
                        let _e2567 = local_329;
                        local_315 = _e2567;
                        let _e2569 = local_297;
                        local_293 = _e2569;
                        local_278 = (_e2557 + 1i);
                        continue;
                    }
                    let _e2570 = local_277;
                    if _e2570 {
                        let _e2571 = local_315;
                        local_273 = (_e2571 > 1i);
                    } else {
                        local_273 = false;
                    }
                    let _e2573 = local_273;
                    if _e2573 {
                        let _e2574 = local_314;
                        let _e2575 = local_291;
                        let _e2577 = local_307[_e2575];
                        local_331 = (_e2574 - _e2577);
                        local_278 = 0i;
                        loop {
                            let _e2579 = local_278;
                            if (_e2579 < 16i) {
                            } else {
                                break;
                            }
                            let _e2581 = local_278;
                            let _e2582 = local_275;
                            if (_e2581 >= _e2582) {
                                break;
                            }
                            let _e2584 = local_278;
                            let _e2586 = local_294[_e2584];
                            if _e2586 {
                                let _e2587 = local_278;
                                let _e2589 = local_307[_e2587];
                                let _e2590 = local_331;
                                local_307[_e2587] = (_e2589 + _e2590);
                            }
                            let _e2593 = local_278;
                            local_278 = (_e2593 + 1i);
                            continue;
                        }
                    }
                    let _e2595 = local_287;
                    if (_e2595 == 1i) {
                        let _e2597 = local_309;
                        local_304 = _e2597;
                    } else {
                        local_304 = 1.6f;
                    }
                    local_278 = 0i;
                    loop {
                        let _e2598 = local_278;
                        if (_e2598 < 16i) {
                        } else {
                            break;
                        }
                        let _e2600 = local_278;
                        let _e2601 = local_275;
                        if (_e2600 >= _e2601) {
                            break;
                        }
                        let _e2603 = local_274;
                        if _e2603 {
                            let _e2604 = local_61;
                            local_297 = (_e2604 != 0i);
                        } else {
                            let _e2606 = local_57;
                            local_297 = (_e2606 != 0i);
                        }
                        let _e2608 = local_297;
                        if !(_e2608) {
                            local_273 = true;
                        } else {
                            let _e2610 = local_278;
                            let _e2612 = local_283[_e2610];
                            local_273 = (_e2612 < 0i);
                        }
                        let _e2614 = local_273;
                        if _e2614 {
                            local_277 = true;
                        } else {
                            let _e2615 = local_278;
                            let _e2617 = local_285[_e2615];
                            local_277 = !(_e2617);
                        }
                        let _e2619 = local_277;
                        if _e2619 {
                            local_293 = true;
                        } else {
                            let _e2620 = local_278;
                            let _e2622 = local_294[_e2620];
                            local_293 = _e2622;
                        }
                        let _e2623 = local_293;
                        if _e2623 {
                            let _e2624 = local_278;
                            local_278 = (_e2624 + 1i);
                            continue;
                        }
                        let _e2626 = local_278;
                        let _e2628 = local_288[_e2626];
                        local_332 = (_e2628 > 0i);
                        let _e2631 = local_292[_e2626];
                        local_333 = _e2631;
                        let _e2633 = local_292[_e2626];
                        if (_e2633 >= 0i) {
                            let _e2635 = local_332;
                            if _e2635 {
                                let _e2636 = local_278;
                                let _e2638 = local_280[_e2636];
                                let _e2639 = local_333;
                                let _e2641 = local_280[_e2639];
                                local_309 = (_e2638 - _e2641);
                            } else {
                                let _e2643 = local_333;
                                let _e2645 = local_280[_e2643];
                                let _e2646 = local_278;
                                let _e2648 = local_280[_e2646];
                                local_309 = (_e2645 - _e2648);
                            }
                            let _e2650 = local_333;
                            local_328 = _e2650;
                            let _e2651 = local_309;
                            local_322 = _e2651;
                        } else {
                            let _e2652 = local_333;
                            if (_e2652 == -2i) {
                                local_322 = 340282350000000000000000000000000000000f;
                                let _e2654 = local_333;
                                local_328 = _e2654;
                                local_329 = 0i;
                                loop {
                                    let _e2655 = local_329;
                                    if (_e2655 < 16i) {
                                    } else {
                                        break;
                                    }
                                    let _e2657 = local_329;
                                    let _e2658 = local_275;
                                    if (_e2657 >= _e2658) {
                                        break;
                                    }
                                    let _e2660 = local_329;
                                    let _e2661 = local_278;
                                    if (_e2660 == _e2661) {
                                        local_295 = true;
                                    } else {
                                        let _e2663 = local_329;
                                        let _e2665 = local_288[_e2663];
                                        let _e2666 = local_278;
                                        let _e2668 = local_288[_e2666];
                                        local_295 = (_e2665 == _e2668);
                                    }
                                    let _e2670 = local_295;
                                    if _e2670 {
                                        let _e2671 = local_329;
                                        local_329 = (_e2671 + 1i);
                                        continue;
                                    }
                                    let _e2673 = local_332;
                                    if _e2673 {
                                        let _e2674 = local_278;
                                        let _e2676 = local_280[_e2674];
                                        let _e2677 = local_329;
                                        let _e2679 = local_280[_e2677];
                                        local_323 = (_e2676 - _e2679);
                                    } else {
                                        let _e2681 = local_329;
                                        let _e2683 = local_280[_e2681];
                                        let _e2684 = local_278;
                                        let _e2686 = local_280[_e2684];
                                        local_323 = (_e2683 - _e2686);
                                    }
                                    let _e2688 = local_323;
                                    if (_e2688 <= 0f) {
                                        local_296 = true;
                                    } else {
                                        let _e2690 = local_323;
                                        let _e2691 = local_322;
                                        local_296 = (_e2690 >= _e2691);
                                    }
                                    let _e2693 = local_296;
                                    if _e2693 {
                                        let _e2694 = local_329;
                                        local_329 = (_e2694 + 1i);
                                        continue;
                                    }
                                    let _e2696 = local_323;
                                    local_322 = _e2696;
                                    let _e2697 = local_329;
                                    local_328 = _e2697;
                                    local_329 = (_e2697 + 1i);
                                    continue;
                                }
                            } else {
                                let _e2699 = local_333;
                                local_328 = _e2699;
                                local_322 = 340282350000000000000000000000000000000f;
                            }
                        }
                        let _e2700 = local_328;
                        if (_e2700 < 0i) {
                            local_295 = true;
                        } else {
                            let _e2702 = local_328;
                            let _e2704 = local_294[_e2702];
                            local_295 = _e2704;
                        }
                        let _e2705 = local_295;
                        if _e2705 {
                            local_296 = true;
                        } else {
                            let _e2706 = local_328;
                            let _e2708 = local_283[_e2706];
                            local_296 = (_e2708 >= 0i);
                        }
                        let _e2710 = local_296;
                        if _e2710 {
                            local_298 = true;
                        } else {
                            let _e2711 = local_322;
                            let _e2712 = local_449;
                            let _e2714 = local_304;
                            local_298 = ((_e2711 * _e2712) >= _e2714);
                        }
                        let _e2716 = local_298;
                        if _e2716 {
                            let _e2717 = local_278;
                            local_278 = (_e2717 + 1i);
                            continue;
                        }
                        let _e2719 = local_328;
                        let _e2721 = local_286[_e2719];
                        if _e2721 {
                            let _e2722 = local_322;
                            local_323 = _e2722;
                        } else {
                            let _e2723 = local_322;
                            let _e2724 = local_449;
                            let _e2728 = local_308;
                            local_323 = (max(round((_e2723 * _e2724)), 1f) * _e2728);
                        }
                        let _e2730 = local_332;
                        if _e2730 {
                            let _e2731 = local_278;
                            let _e2733 = local_307[_e2731];
                            let _e2734 = local_323;
                            local_309 = (_e2733 - _e2734);
                        } else {
                            let _e2736 = local_278;
                            let _e2738 = local_307[_e2736];
                            let _e2739 = local_323;
                            local_309 = (_e2738 + _e2739);
                        }
                        let _e2741 = local_328;
                        let _e2742 = local_309;
                        local_307[_e2741] = _e2742;
                        local_294[_e2741] = true;
                        let _e2745 = local_278;
                        local_278 = (_e2745 + 1i);
                        continue;
                    }
                    local_278 = 0i;
                    loop {
                        let _e2747 = local_278;
                        if (_e2747 < 16i) {
                        } else {
                            break;
                        }
                        let _e2749 = local_278;
                        let _e2750 = local_275;
                        if (_e2749 >= _e2750) {
                            break;
                        }
                        let _e2752 = local_274;
                        if _e2752 {
                            let _e2753 = local_61;
                            local_297 = (_e2753 != 0i);
                        } else {
                            let _e2755 = local_57;
                            local_297 = (_e2755 != 0i);
                        }
                        let _e2757 = local_278;
                        let _e2759 = local_294[_e2757];
                        if !(_e2759) {
                            let _e2761 = local_297;
                            if _e2761 {
                                let _e2762 = local_278;
                                let _e2764 = local_283[_e2762];
                                local_273 = (_e2764 >= 0i);
                            } else {
                                local_273 = false;
                            }
                            let _e2766 = local_273;
                            local_273 = !(_e2766);
                        } else {
                            local_273 = false;
                        }
                        let _e2768 = local_273;
                        if _e2768 {
                            let _e2769 = local_278;
                            local_278 = (_e2769 + 1i);
                            continue;
                        }
                        let _e2771 = local_450;
                        let _e2772 = local_278;
                        let _e2774 = local_280[_e2772];
                        local_451[_e2771] = _e2774;
                        let _e2777 = local_307[_e2772];
                        local_452[_e2771] = _e2777;
                        let _e2779 = local_297;
                        if _e2779 {
                            let _e2780 = local_278;
                            let _e2782 = local_283[_e2780];
                            local_277 = (_e2782 >= 0i);
                        } else {
                            local_277 = false;
                        }
                        let _e2784 = local_450;
                        let _e2785 = local_277;
                        local_334[_e2784] = _e2785;
                        let _e2787 = local_278;
                        let _e2789 = local_286[_e2787];
                        local_335[_e2784] = _e2789;
                        local_453[_e2784] = _e2787;
                        local_450 = (_e2784 + 1i);
                        local_278 = (_e2787 + 1i);
                        continue;
                    }
                    let _e2794 = local_274;
                    if _e2794 {
                        let _e2795 = local_58;
                        local_273 = (_e2795 == 1i);
                    } else {
                        local_273 = false;
                    }
                    let _e2797 = local_273;
                    if _e2797 {
                        let _e2798 = local_450;
                        local_273 = (_e2798 > 0i);
                    } else {
                        local_273 = false;
                    }
                    let _e2800 = local_273;
                    if _e2800 {
                        let _e2801 = local_450;
                        local_273 = (_e2801 < 16i);
                    } else {
                        local_273 = false;
                    }
                    let _e2803 = local_273;
                    if _e2803 {
                        let _e2804 = local_448;
                        let _e2806 = local_451[0i];
                        let _e2807 = local_308;
                        local_273 = (_e2804 < (_e2806 - (0.25f * _e2807)));
                    } else {
                        local_273 = false;
                    }
                    let _e2811 = local_273;
                    if _e2811 {
                        local_278 = 15i;
                        loop {
                            let _e2812 = local_278;
                            if (_e2812 > 0i) {
                            } else {
                                break;
                            }
                            let _e2814 = local_278;
                            let _e2815 = local_450;
                            if (_e2814 <= _e2815) {
                                let _e2817 = local_278;
                                let _e2818 = (_e2817 - 1i);
                                let _e2820 = local_451[_e2818];
                                local_451[_e2817] = _e2820;
                                let _e2823 = local_452[_e2818];
                                local_452[_e2817] = _e2823;
                                let _e2826 = local_334[_e2818];
                                local_334[_e2817] = _e2826;
                                let _e2829 = local_335[_e2818];
                                local_335[_e2817] = _e2829;
                                let _e2832 = local_453[_e2818];
                                local_453[_e2817] = _e2832;
                            }
                            let _e2834 = local_278;
                            local_278 = (_e2834 - 1i);
                            continue;
                        }
                        let _e2836 = local_448;
                        local_451[0i] = _e2836;
                        let _e2838 = local_449;
                        local_452[0i] = (round((_e2836 * _e2838)) / _e2838);
                        local_334[0i] = false;
                        local_335[0i] = false;
                        local_453[0i] = 32i;
                        let _e2846 = local_450;
                        local_450 = (_e2846 + 1i);
                    }
                    local_328 = 15i;
                    loop {
                        let _e2848 = local_328;
                        if (_e2848 > 0i) {
                        } else {
                            break;
                        }
                        let _e2850 = local_328;
                        let _e2851 = local_450;
                        if (_e2850 >= _e2851) {
                            local_273 = true;
                        } else {
                            let _e2853 = local_328;
                            let _e2855 = local_334[_e2853];
                            local_273 = !(_e2855);
                        }
                        let _e2857 = local_273;
                        if _e2857 {
                            let _e2858 = local_328;
                            local_328 = (_e2858 - 1i);
                            continue;
                        }
                        local_329 = 15i;
                        loop {
                            let _e2860 = local_329;
                            if (_e2860 > 0i) {
                            } else {
                                break;
                            }
                            let _e2862 = local_329;
                            let _e2863 = local_328;
                            if (_e2862 > _e2863) {
                                let _e2865 = local_329;
                                local_329 = (_e2865 - 1i);
                                continue;
                            }
                            let _e2867 = local_329;
                            let _e2868 = (_e2867 - 1i);
                            local_336 = _e2868;
                            let _e2870 = local_334[_e2868];
                            if _e2870 {
                                break;
                            }
                            let _e2871 = local_336;
                            let _e2873 = local_335[_e2871];
                            if _e2873 {
                                local_304 = 0.000001f;
                            } else {
                                let _e2874 = local_308;
                                local_304 = _e2874;
                            }
                            let _e2875 = local_336;
                            let _e2877 = local_452[_e2875];
                            let _e2878 = local_329;
                            let _e2880 = local_452[_e2878];
                            let _e2881 = local_304;
                            local_452[_e2875] = min(_e2877, (_e2880 - _e2881));
                            local_329 = (_e2878 - 1i);
                            continue;
                        }
                        let _e2886 = local_328;
                        local_328 = (_e2886 - 1i);
                        continue;
                    }
                    local_278 = 1i;
                    loop {
                        let _e2888 = local_278;
                        if (_e2888 < 16i) {
                        } else {
                            break;
                        }
                        let _e2890 = local_278;
                        let _e2891 = local_450;
                        if (_e2890 >= _e2891) {
                            break;
                        }
                        let _e2893 = local_278;
                        let _e2895 = local_452[_e2893];
                        let _e2898 = local_452[(_e2893 - 1i)];
                        if (_e2895 <= _e2898) {
                            let _e2900 = local_278;
                            let _e2903 = local_452[(_e2900 - 1i)];
                            let _e2904 = local_308;
                            local_452[_e2900] = (_e2903 + _e2904);
                        }
                        let _e2907 = local_278;
                        local_278 = (_e2907 + 1i);
                        continue;
                    }
                    let _e2909 = local_54;
                    if (_e2909 != 0i) {
                        let _e2911 = local_449;
                        let _e2912 = local_53;
                        local_273 = (_e2911 > _e2912);
                    } else {
                        local_273 = false;
                    }
                    let _e2914 = local_273;
                    if _e2914 {
                        let _e2915 = local_52;
                        let _e2916 = local_53;
                        let _e2917 = (_e2915 - _e2916);
                        local_337 = _e2917;
                        if (_e2917 <= 0f) {
                            local_273 = true;
                        } else {
                            let _e2919 = local_449;
                            let _e2920 = local_52;
                            local_273 = (_e2919 >= _e2920);
                        }
                        let _e2922 = local_273;
                        if _e2922 {
                            local_304 = 1f;
                        } else {
                            let _e2923 = local_449;
                            let _e2924 = local_53;
                            let _e2926 = local_337;
                            local_304 = ((_e2923 - _e2924) / _e2926);
                        }
                        local_278 = 0i;
                        loop {
                            let _e2928 = local_278;
                            if (_e2928 < 16i) {
                            } else {
                                break;
                            }
                            let _e2930 = local_278;
                            let _e2931 = local_450;
                            if (_e2930 >= _e2931) {
                                break;
                            }
                            let _e2933 = local_278;
                            let _e2935 = local_452[_e2933];
                            let _e2937 = local_451[_e2933];
                            let _e2939 = local_452[_e2933];
                            let _e2941 = local_304;
                            local_452[_e2933] = (_e2935 + ((_e2937 - _e2939) * _e2941));
                            local_278 = (_e2933 + 1i);
                            continue;
                        }
                    }
                    local_278 = 0i;
                    loop {
                        let _e2946 = local_278;
                        if (_e2946 < 16i) {
                        } else {
                            break;
                        }
                        let _e2948 = local_278;
                        let _e2949 = local_450;
                        if (_e2948 >= _e2949) {
                            break;
                        }
                        let _e2951 = local_278;
                        let _e2953 = local_451[_e2951];
                        if !((abs(_e2953) <= 340282300000000000000000000000000000000f)) {
                            local_273 = true;
                        } else {
                            let _e2957 = local_278;
                            let _e2959 = local_452[_e2957];
                            local_273 = !((abs(_e2959) <= 340282300000000000000000000000000000000f));
                        }
                        let _e2963 = local_273;
                        if _e2963 {
                            local_450 = 0i;
                            local_271 = true;
                            local_272 = false;
                            break;
                        }
                        let _e2964 = local_278;
                        local_278 = (_e2964 + 1i);
                        continue;
                    }
                    let _e2966 = local_271;
                    if _e2966 {
                        break;
                    }
                    local_271 = true;
                    local_272 = true;
                    break;
                }
            }
            let _e2967 = local_272;
            let _e2968 = local_450;
            local_441 = _e2968;
            let _e2969 = local_452;
            local_93 = _e2969[0];
            local_92 = _e2969[1];
            local_91 = _e2969[2];
            local_90 = _e2969[3];
            local_89 = _e2969[4];
            local_88 = _e2969[5];
            local_87 = _e2969[6];
            local_86 = _e2969[7];
            local_85 = _e2969[8];
            local_84 = _e2969[9];
            local_83 = _e2969[10];
            local_82 = _e2969[11];
            local_81 = _e2969[12];
            local_80 = _e2969[13];
            local_79 = _e2969[14];
            local_78 = _e2969[15];
            let _e2986 = local_453;
            local_77 = _e2986[0];
            local_76 = _e2986[1];
            local_75 = _e2986[2];
            local_74 = _e2986[3];
            local_73 = _e2986[4];
            local_72 = _e2986[5];
            local_71 = _e2986[6];
            local_70 = _e2986[7];
            local_69 = _e2986[8];
            local_68 = _e2986[9];
            local_67 = _e2986[10];
            local_66 = _e2986[11];
            local_65 = _e2986[12];
            local_64 = _e2986[13];
            local_63 = _e2986[14];
            local_62 = _e2986[15];
            local_443 = _e2967;
            local_455 = 1i;
            let _e3003 = local_437;
            local_456 = _e3003;
            let _e3004 = local_425;
            local_457 = _e3004;
            let _e3005 = local_428;
            local_458 = _e3005;
            local_459 = 0f;
            let _e3006 = local_421;
            local_460 = _e3006.y;
            let _e3008 = local_109;
            let _e3009 = local_110;
            let _e3010 = local_111;
            let _e3011 = local_112;
            let _e3012 = local_113;
            let _e3013 = local_114;
            let _e3014 = local_115;
            let _e3015 = local_116;
            let _e3016 = local_117;
            let _e3017 = local_118;
            let _e3018 = local_119;
            let _e3019 = local_120;
            let _e3020 = local_121;
            let _e3021 = local_122;
            let _e3022 = local_123;
            local_14 = _e3022;
            local_13 = _e3021;
            local_12 = _e3020;
            local_11 = _e3019;
            local_10 = _e3018;
            local_9 = _e3017;
            local_8 = _e3016;
            local_7 = _e3015;
            local_6 = _e3014;
            local_5 = _e3013;
            local_4 = _e3012;
            local_3 = _e3011;
            local_2 = _e3010;
            local_1 = _e3009;
            local = _e3008;
            local_166 = false;
            switch bitcast<i32>(0u) {
                default: {
                    local_461 = 0i;
                    let _e3024 = local_460;
                    if !((abs(_e3024) <= 340282300000000000000000000000000000000f)) {
                        local_168 = true;
                    } else {
                        let _e3028 = local_460;
                        local_168 = (_e3028 <= 0f);
                    }
                    let _e3030 = local_168;
                    if _e3030 {
                        local_168 = true;
                    } else {
                        let _e3031 = local_457;
                        local_168 = (_e3031 < 0i);
                    }
                    let _e3033 = local_168;
                    if _e3033 {
                        local_168 = true;
                    } else {
                        let _e3034 = local_457;
                        local_168 = (_e3034 > 16i);
                    }
                    let _e3036 = local_168;
                    if _e3036 {
                        local_168 = true;
                    } else {
                        let _e3037 = local_458;
                        local_168 = !((abs(_e3037) <= 340282300000000000000000000000000000000f));
                    }
                    let _e3041 = local_168;
                    if _e3041 {
                        local_168 = true;
                    } else {
                        let _e3042 = local_458;
                        local_168 = (_e3042 < 0f);
                    }
                    let _e3044 = local_168;
                    if _e3044 {
                        local_166 = true;
                        local_167 = false;
                        break;
                    }
                    let _e3045 = local_455;
                    let _e3046 = (_e3045 == 0i);
                    local_169 = _e3046;
                    if _e3046 {
                        let _e3047 = local_14;
                        local_168 = (_e3047 == 0i);
                    } else {
                        local_168 = false;
                    }
                    let _e3049 = local_168;
                    if _e3049 {
                        let _e3050 = local_13;
                        local_168 = (_e3050 == 0i);
                    } else {
                        local_168 = false;
                    }
                    let _e3052 = local_168;
                    if _e3052 {
                        let _e3053 = local_12;
                        local_168 = (_e3053 == 0i);
                    } else {
                        local_168 = false;
                    }
                    let _e3055 = local_168;
                    if _e3055 {
                        let _e3056 = local_11;
                        local_168 = (_e3056 == 0i);
                    } else {
                        local_168 = false;
                    }
                    let _e3058 = local_168;
                    if _e3058 {
                        local_168 = true;
                    } else {
                        let _e3059 = local_455;
                        if (_e3059 == 1i) {
                            let _e3061 = local_10;
                            local_168 = (_e3061 == 0i);
                        } else {
                            local_168 = false;
                        }
                        let _e3063 = local_168;
                        if _e3063 {
                            let _e3064 = local_9;
                            local_168 = (_e3064 == 0i);
                        } else {
                            local_168 = false;
                        }
                        let _e3066 = local_168;
                        if _e3066 {
                            let _e3067 = local_8;
                            local_168 = (_e3067 == 0i);
                        } else {
                            local_168 = false;
                        }
                    }
                    let _e3069 = local_168;
                    if _e3069 {
                        local_166 = true;
                        local_167 = true;
                        break;
                    }
                    let _e3070 = local_456;
                    let _e3071 = (_e3070 + 0i);
                    let _e3074 = snailAhVertexInfoBase_0_;
                    let _e3075 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e3078 = local_162;
                    let _e3081 = vec2<i32>(vec2<i32>(_e3075).x, _e3078.y);
                    let _e3082 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e3087 = vec2<i32>(_e3081.x, vec2<i32>(_e3082).y);
                    local_162 = _e3087;
                    let _e3093 = (((_e3074.y * _e3087.x) + _e3074.x) + (_e3071 >> bitcast<u32>(2i)));
                    let _e3102 = vec2<i32>((_e3093 - (i32(floor((f32(_e3093) / f32(_e3087.x)))) * _e3087.x)), (_e3093 / _e3087.x));
                    let _e3105 = vec3<i32>(_e3102.x, _e3102.y, 0i);
                    let _e3108 = textureLoad(u_layer_tex_0_image, _e3105.xy, _e3105.z);
                    local_163 = _e3108;
                    let _e3109 = (_e3071 & 3i);
                    local_164 = _e3109;
                    if (_e3109 == 0i) {
                        let _e3111 = local_163;
                        local_165 = _e3111.x;
                    } else {
                        let _e3113 = local_164;
                        if (_e3113 == 1i) {
                            let _e3115 = local_163;
                            local_165 = _e3115.y;
                        } else {
                            let _e3117 = local_164;
                            if (_e3117 == 2i) {
                                let _e3119 = local_163;
                                local_165 = _e3119.z;
                            } else {
                                let _e3121 = local_163;
                                local_165 = _e3121.w;
                            }
                        }
                    }
                    let _e3123 = local_165;
                    let _e3124 = i32(_e3123);
                    local_170 = _e3124;
                    if (_e3124 <= 0i) {
                        local_168 = true;
                    } else {
                        let _e3126 = local_170;
                        local_168 = (_e3126 > 16i);
                    }
                    let _e3128 = local_168;
                    if _e3128 {
                        let _e3129 = local_170;
                        local_166 = true;
                        local_167 = (_e3129 == 0i);
                        break;
                    }
                    let _e3131 = local_455;
                    let _e3132 = (_e3131 == 1i);
                    local_171 = _e3132;
                    if _e3132 {
                        let _e3133 = local_10;
                        local_168 = (_e3133 == 2i);
                    } else {
                        local_168 = false;
                    }
                    let _e3135 = local_169;
                    if _e3135 {
                        let _e3136 = local_11;
                        local_172 = (_e3136 == 1i);
                    } else {
                        local_172 = false;
                    }
                    let _e3138 = local_172;
                    if _e3138 {
                        let _e3139 = local_459;
                        local_172 = !((abs(_e3139) <= 340282300000000000000000000000000000000f));
                    } else {
                        local_172 = false;
                    }
                    let _e3143 = local_172;
                    if _e3143 {
                        local_166 = true;
                        local_167 = false;
                        break;
                    }
                    local_173 = 0i;
                    loop {
                        let _e3144 = local_173;
                        if (_e3144 < 16i) {
                        } else {
                            break;
                        }
                        let _e3146 = local_173;
                        let _e3147 = local_170;
                        if (_e3146 >= _e3147) {
                            break;
                        }
                        let _e3149 = local_456;
                        let _e3151 = local_173;
                        let _e3153 = ((_e3149 + 1i) + (4i * _e3151));
                        local_174 = _e3153;
                        let _e3154 = (_e3153 + 0i);
                        let _e3157 = snailAhVertexInfoBase_0_;
                        let _e3158 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3161 = local_158;
                        let _e3164 = vec2<i32>(vec2<i32>(_e3158).x, _e3161.y);
                        let _e3165 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3170 = vec2<i32>(_e3164.x, vec2<i32>(_e3165).y);
                        local_158 = _e3170;
                        let _e3176 = (((_e3157.y * _e3170.x) + _e3157.x) + (_e3154 >> bitcast<u32>(2i)));
                        let _e3185 = vec2<i32>((_e3176 - (i32(floor((f32(_e3176) / f32(_e3170.x)))) * _e3170.x)), (_e3176 / _e3170.x));
                        let _e3188 = vec3<i32>(_e3185.x, _e3185.y, 0i);
                        let _e3191 = textureLoad(u_layer_tex_0_image, _e3188.xy, _e3188.z);
                        local_159 = _e3191;
                        let _e3192 = (_e3154 & 3i);
                        local_160 = _e3192;
                        if (_e3192 == 0i) {
                            let _e3194 = local_159;
                            local_161 = _e3194.x;
                        } else {
                            let _e3196 = local_160;
                            if (_e3196 == 1i) {
                                let _e3198 = local_159;
                                local_161 = _e3198.y;
                            } else {
                                let _e3200 = local_160;
                                if (_e3200 == 2i) {
                                    let _e3202 = local_159;
                                    local_161 = _e3202.z;
                                } else {
                                    let _e3204 = local_159;
                                    local_161 = _e3204.w;
                                }
                            }
                        }
                        let _e3206 = local_161;
                        let _e3207 = local_173;
                        local_175[_e3207] = _e3206;
                        let _e3209 = local_174;
                        let _e3210 = (_e3209 + 1i);
                        let _e3213 = snailAhVertexInfoBase_0_;
                        let _e3214 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3217 = local_154;
                        let _e3220 = vec2<i32>(vec2<i32>(_e3214).x, _e3217.y);
                        let _e3221 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3226 = vec2<i32>(_e3220.x, vec2<i32>(_e3221).y);
                        local_154 = _e3226;
                        let _e3232 = (((_e3213.y * _e3226.x) + _e3213.x) + (_e3210 >> bitcast<u32>(2i)));
                        let _e3241 = vec2<i32>((_e3232 - (i32(floor((f32(_e3232) / f32(_e3226.x)))) * _e3226.x)), (_e3232 / _e3226.x));
                        let _e3244 = vec3<i32>(_e3241.x, _e3241.y, 0i);
                        let _e3247 = textureLoad(u_layer_tex_0_image, _e3244.xy, _e3244.z);
                        local_155 = _e3247;
                        let _e3248 = (_e3210 & 3i);
                        local_156 = _e3248;
                        if (_e3248 == 0i) {
                            let _e3250 = local_155;
                            local_157 = _e3250.x;
                        } else {
                            let _e3252 = local_156;
                            if (_e3252 == 1i) {
                                let _e3254 = local_155;
                                local_157 = _e3254.y;
                            } else {
                                let _e3256 = local_156;
                                if (_e3256 == 2i) {
                                    let _e3258 = local_155;
                                    local_157 = _e3258.z;
                                } else {
                                    let _e3260 = local_155;
                                    local_157 = _e3260.w;
                                }
                            }
                        }
                        let _e3262 = local_157;
                        let _e3263 = local_173;
                        local_176[_e3263] = _e3262;
                        let _e3265 = local_174;
                        let _e3266 = (_e3265 + 2i);
                        let _e3269 = snailAhVertexInfoBase_0_;
                        let _e3270 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3273 = local_150;
                        let _e3276 = vec2<i32>(vec2<i32>(_e3270).x, _e3273.y);
                        let _e3277 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3282 = vec2<i32>(_e3276.x, vec2<i32>(_e3277).y);
                        local_150 = _e3282;
                        let _e3288 = (((_e3269.y * _e3282.x) + _e3269.x) + (_e3266 >> bitcast<u32>(2i)));
                        let _e3297 = vec2<i32>((_e3288 - (i32(floor((f32(_e3288) / f32(_e3282.x)))) * _e3282.x)), (_e3288 / _e3282.x));
                        let _e3300 = vec3<i32>(_e3297.x, _e3297.y, 0i);
                        let _e3303 = textureLoad(u_layer_tex_0_image, _e3300.xy, _e3300.z);
                        local_151 = _e3303;
                        let _e3304 = (_e3266 & 3i);
                        local_152 = _e3304;
                        if (_e3304 == 0i) {
                            let _e3306 = local_151;
                            local_153 = _e3306.x;
                        } else {
                            let _e3308 = local_152;
                            if (_e3308 == 1i) {
                                let _e3310 = local_151;
                                local_153 = _e3310.y;
                            } else {
                                let _e3312 = local_152;
                                if (_e3312 == 2i) {
                                    let _e3314 = local_151;
                                    local_153 = _e3314.z;
                                } else {
                                    let _e3316 = local_151;
                                    local_153 = _e3316.w;
                                }
                            }
                        }
                        let _e3318 = local_153;
                        let _e3319 = bitcast<u32>(_e3318);
                        let _e3320 = local_173;
                        local_177[_e3320] = (bitcast<i32>((_e3319 << bitcast<u32>(16u))) >> bitcast<u32>(16i));
                        local_178[_e3320] = (bitcast<i32>(_e3319) >> bitcast<u32>(16i));
                        let _e3331 = local_174;
                        let _e3332 = (_e3331 + 3i);
                        let _e3335 = snailAhVertexInfoBase_0_;
                        let _e3336 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3339 = local_146;
                        let _e3342 = vec2<i32>(vec2<i32>(_e3336).x, _e3339.y);
                        let _e3343 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3348 = vec2<i32>(_e3342.x, vec2<i32>(_e3343).y);
                        local_146 = _e3348;
                        let _e3354 = (((_e3335.y * _e3348.x) + _e3335.x) + (_e3332 >> bitcast<u32>(2i)));
                        let _e3363 = vec2<i32>((_e3354 - (i32(floor((f32(_e3354) / f32(_e3348.x)))) * _e3348.x)), (_e3354 / _e3348.x));
                        let _e3366 = vec3<i32>(_e3363.x, _e3363.y, 0i);
                        let _e3369 = textureLoad(u_layer_tex_0_image, _e3366.xy, _e3366.z);
                        local_147 = _e3369;
                        let _e3370 = (_e3332 & 3i);
                        local_148 = _e3370;
                        if (_e3370 == 0i) {
                            let _e3372 = local_147;
                            local_149 = _e3372.x;
                        } else {
                            let _e3374 = local_148;
                            if (_e3374 == 1i) {
                                let _e3376 = local_147;
                                local_149 = _e3376.y;
                            } else {
                                let _e3378 = local_148;
                                if (_e3378 == 2i) {
                                    let _e3380 = local_147;
                                    local_149 = _e3380.z;
                                } else {
                                    let _e3382 = local_147;
                                    local_149 = _e3382.w;
                                }
                            }
                        }
                        let _e3384 = local_149;
                        let _e3385 = bitcast<u32>(_e3384);
                        local_179 = _e3385;
                        let _e3386 = local_173;
                        local_180[_e3386] = ((_e3385 & 1u) != 0u);
                        local_181[_e3386] = ((_e3385 & 2u) != 0u);
                        if ((_e3385 & 4u) == 0u) {
                            local_166 = true;
                            local_167 = false;
                            break;
                        }
                        let _e3395 = local_179;
                        if ((_e3395 & 8u) != 0u) {
                            local_182 = -1i;
                        } else {
                            local_182 = 1i;
                        }
                        let _e3398 = local_173;
                        let _e3399 = local_182;
                        local_183[_e3398] = _e3399;
                        let _e3401 = local_168;
                        if _e3401 {
                            local_184 = 10u;
                        } else {
                            local_184 = 4u;
                        }
                        let _e3402 = local_179;
                        let _e3403 = local_184;
                        let _e3407 = bitcast<i32>(((_e3402 >> bitcast<u32>(_e3403)) & 63u));
                        local_185 = _e3407;
                        if (_e3407 >= 62i) {
                            local_186 = -1i;
                        } else {
                            let _e3409 = local_185;
                            local_186 = _e3409;
                        }
                        let _e3410 = local_173;
                        let _e3411 = local_186;
                        local_187[_e3410] = _e3411;
                        let _e3413 = local_185;
                        if (_e3413 >= 63i) {
                            let _e3415 = local_173;
                            let _e3417 = local_180[_e3415];
                            local_172 = _e3417;
                        } else {
                            local_172 = false;
                        }
                        let _e3418 = local_172;
                        if _e3418 {
                            let _e3419 = local_173;
                            let _e3421 = local_178[_e3419];
                            local_188 = (_e3421 >= 0i);
                        } else {
                            local_188 = false;
                        }
                        let _e3423 = local_188;
                        if _e3423 {
                            local_166 = true;
                            local_167 = false;
                            break;
                        }
                        let _e3424 = local_173;
                        local_189[_e3424] = false;
                        let _e3427 = local_175[_e3424];
                        if !((abs(_e3427) <= 340282300000000000000000000000000000000f)) {
                            local_190 = true;
                        } else {
                            let _e3431 = local_173;
                            let _e3433 = local_176[_e3431];
                            local_190 = !((abs(_e3433) <= 340282300000000000000000000000000000000f));
                        }
                        let _e3437 = local_190;
                        if _e3437 {
                            local_191 = true;
                        } else {
                            let _e3438 = local_173;
                            let _e3440 = local_176[_e3438];
                            local_191 = (_e3440 < 0f);
                        }
                        let _e3442 = local_191;
                        if _e3442 {
                            local_192 = true;
                        } else {
                            let _e3443 = local_173;
                            let _e3445 = local_177[_e3443];
                            local_192 = (_e3445 < -1i);
                        }
                        let _e3447 = local_192;
                        if _e3447 {
                            local_193 = true;
                        } else {
                            let _e3448 = local_173;
                            let _e3450 = local_177[_e3448];
                            let _e3451 = local_170;
                            local_193 = (_e3450 >= _e3451);
                        }
                        let _e3453 = local_193;
                        if _e3453 {
                            local_194 = true;
                        } else {
                            let _e3454 = local_173;
                            let _e3456 = local_178[_e3454];
                            local_194 = (_e3456 < -1i);
                        }
                        let _e3458 = local_194;
                        if _e3458 {
                            local_195 = true;
                        } else {
                            let _e3459 = local_173;
                            let _e3461 = local_178[_e3459];
                            let _e3462 = local_457;
                            local_195 = (_e3461 >= _e3462);
                        }
                        let _e3464 = local_195;
                        if _e3464 {
                            local_166 = true;
                            local_167 = false;
                            break;
                        }
                        let _e3465 = local_173;
                        local_173 = (_e3465 + 1i);
                        continue;
                    }
                    let _e3467 = local_166;
                    if _e3467 {
                        break;
                    }
                    local_173 = 0i;
                    loop {
                        let _e3468 = local_173;
                        if (_e3468 < 16i) {
                        } else {
                            break;
                        }
                        let _e3470 = local_173;
                        let _e3471 = local_457;
                        if (_e3470 >= _e3471) {
                            break;
                        }
                        let _e3473 = local_173;
                        let _e3474 = (2i * _e3473);
                        local_196 = _e3474;
                        let _e3475 = (12i + _e3474);
                        let _e3478 = snailAhVertexInfoBase_0_;
                        let _e3479 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3482 = local_142;
                        let _e3485 = vec2<i32>(vec2<i32>(_e3479).x, _e3482.y);
                        let _e3486 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3491 = vec2<i32>(_e3485.x, vec2<i32>(_e3486).y);
                        local_142 = _e3491;
                        let _e3497 = (((_e3478.y * _e3491.x) + _e3478.x) + (_e3475 >> bitcast<u32>(2i)));
                        let _e3506 = vec2<i32>((_e3497 - (i32(floor((f32(_e3497) / f32(_e3491.x)))) * _e3491.x)), (_e3497 / _e3491.x));
                        let _e3509 = vec3<i32>(_e3506.x, _e3506.y, 0i);
                        let _e3512 = textureLoad(u_layer_tex_0_image, _e3509.xy, _e3509.z);
                        local_143 = _e3512;
                        let _e3513 = (_e3475 & 3i);
                        local_144 = _e3513;
                        if (_e3513 == 0i) {
                            let _e3515 = local_143;
                            local_145 = _e3515.x;
                        } else {
                            let _e3517 = local_144;
                            if (_e3517 == 1i) {
                                let _e3519 = local_143;
                                local_145 = _e3519.y;
                            } else {
                                let _e3521 = local_144;
                                if (_e3521 == 2i) {
                                    let _e3523 = local_143;
                                    local_145 = _e3523.z;
                                } else {
                                    let _e3525 = local_143;
                                    local_145 = _e3525.w;
                                }
                            }
                        }
                        let _e3527 = local_145;
                        local_197 = _e3527;
                        let _e3528 = local_196;
                        let _e3530 = (12i + (_e3528 + 1i));
                        let _e3533 = snailAhVertexInfoBase_0_;
                        let _e3534 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3537 = local_138;
                        let _e3540 = vec2<i32>(vec2<i32>(_e3534).x, _e3537.y);
                        let _e3541 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3546 = vec2<i32>(_e3540.x, vec2<i32>(_e3541).y);
                        local_138 = _e3546;
                        let _e3552 = (((_e3533.y * _e3546.x) + _e3533.x) + (_e3530 >> bitcast<u32>(2i)));
                        let _e3561 = vec2<i32>((_e3552 - (i32(floor((f32(_e3552) / f32(_e3546.x)))) * _e3546.x)), (_e3552 / _e3546.x));
                        let _e3564 = vec3<i32>(_e3561.x, _e3561.y, 0i);
                        let _e3567 = textureLoad(u_layer_tex_0_image, _e3564.xy, _e3564.z);
                        local_139 = _e3567;
                        let _e3568 = (_e3530 & 3i);
                        local_140 = _e3568;
                        if (_e3568 == 0i) {
                            let _e3570 = local_139;
                            local_141 = _e3570.x;
                        } else {
                            let _e3572 = local_140;
                            if (_e3572 == 1i) {
                                let _e3574 = local_139;
                                local_141 = _e3574.y;
                            } else {
                                let _e3576 = local_140;
                                if (_e3576 == 2i) {
                                    let _e3578 = local_139;
                                    local_141 = _e3578.z;
                                } else {
                                    let _e3580 = local_139;
                                    local_141 = _e3580.w;
                                }
                            }
                        }
                        let _e3582 = local_141;
                        local_198 = _e3582;
                        let _e3583 = local_197;
                        if !((abs(_e3583) <= 340282300000000000000000000000000000000f)) {
                            local_172 = true;
                        } else {
                            let _e3587 = local_198;
                            local_172 = !((abs(_e3587) <= 340282300000000000000000000000000000000f));
                        }
                        let _e3591 = local_172;
                        if _e3591 {
                            local_166 = true;
                            local_167 = false;
                            break;
                        }
                        let _e3592 = local_173;
                        local_173 = (_e3592 + 1i);
                        continue;
                    }
                    let _e3594 = local_166;
                    if _e3594 {
                        break;
                    }
                    let _e3595 = local_171;
                    if _e3595 {
                        let _e3596 = local_8;
                        local_172 = (_e3596 == 1i);
                    } else {
                        local_172 = false;
                    }
                    let _e3598 = local_172;
                    if _e3598 {
                        let _e3599 = local;
                        local_199 = _e3599;
                    } else {
                        local_199 = 0f;
                    }
                    local_173 = 0i;
                    loop {
                        let _e3600 = local_173;
                        if (_e3600 < 16i) {
                        } else {
                            break;
                        }
                        let _e3602 = local_173;
                        let _e3603 = local_170;
                        if (_e3602 >= _e3603) {
                            break;
                        }
                        let _e3605 = local_173;
                        let _e3607 = local_177[_e3605];
                        if (_e3607 >= 0i) {
                            let _e3609 = local_173;
                            let _e3611 = local_177[_e3609];
                            let _e3613 = local_175[_e3611];
                            let _e3615 = local_175[_e3609];
                            local_172 = (_e3613 > _e3615);
                        } else {
                            local_172 = false;
                        }
                        let _e3617 = local_168;
                        if _e3617 {
                            let _e3618 = local_173;
                            let _e3620 = local_178[_e3618];
                            local_188 = (_e3620 >= 0i);
                        } else {
                            local_188 = false;
                        }
                        let _e3622 = local_168;
                        if !(_e3622) {
                            let _e3624 = local_172;
                            if _e3624 {
                                local_182 = -1i;
                            } else {
                                local_182 = 1i;
                            }
                            let _e3625 = local_173;
                            let _e3626 = local_182;
                            local_183[_e3625] = _e3626;
                        }
                        let _e3628 = local_188;
                        if _e3628 {
                            let _e3629 = local_173;
                            let _e3631 = local_178[_e3629];
                            let _e3633 = (12i + (2i * _e3631));
                            let _e3636 = snailAhVertexInfoBase_0_;
                            let _e3637 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e3640 = local_134;
                            let _e3643 = vec2<i32>(vec2<i32>(_e3637).x, _e3640.y);
                            let _e3644 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e3649 = vec2<i32>(_e3643.x, vec2<i32>(_e3644).y);
                            local_134 = _e3649;
                            let _e3655 = (((_e3636.y * _e3649.x) + _e3636.x) + (_e3633 >> bitcast<u32>(2i)));
                            let _e3664 = vec2<i32>((_e3655 - (i32(floor((f32(_e3655) / f32(_e3649.x)))) * _e3649.x)), (_e3655 / _e3649.x));
                            let _e3667 = vec3<i32>(_e3664.x, _e3664.y, 0i);
                            let _e3670 = textureLoad(u_layer_tex_0_image, _e3667.xy, _e3667.z);
                            local_135 = _e3670;
                            let _e3671 = (_e3633 & 3i);
                            local_136 = _e3671;
                            if (_e3671 == 0i) {
                                let _e3673 = local_135;
                                local_137 = _e3673.x;
                            } else {
                                let _e3675 = local_136;
                                if (_e3675 == 1i) {
                                    let _e3677 = local_135;
                                    local_137 = _e3677.y;
                                } else {
                                    let _e3679 = local_136;
                                    if (_e3679 == 2i) {
                                        let _e3681 = local_135;
                                        local_137 = _e3681.z;
                                    } else {
                                        let _e3683 = local_135;
                                        local_137 = _e3683.w;
                                    }
                                }
                            }
                            let _e3685 = local_137;
                            local_200 = _e3685;
                            let _e3686 = local_173;
                            let _e3688 = local_178[_e3686];
                            let _e3691 = (12i + ((2i * _e3688) + 1i));
                            let _e3694 = snailAhVertexInfoBase_0_;
                            let _e3695 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e3698 = local_130;
                            let _e3701 = vec2<i32>(vec2<i32>(_e3695).x, _e3698.y);
                            let _e3702 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e3707 = vec2<i32>(_e3701.x, vec2<i32>(_e3702).y);
                            local_130 = _e3707;
                            let _e3713 = (((_e3694.y * _e3707.x) + _e3694.x) + (_e3691 >> bitcast<u32>(2i)));
                            let _e3722 = vec2<i32>((_e3713 - (i32(floor((f32(_e3713) / f32(_e3707.x)))) * _e3707.x)), (_e3713 / _e3707.x));
                            let _e3725 = vec3<i32>(_e3722.x, _e3722.y, 0i);
                            let _e3728 = textureLoad(u_layer_tex_0_image, _e3725.xy, _e3725.z);
                            local_131 = _e3728;
                            let _e3729 = (_e3691 & 3i);
                            local_132 = _e3729;
                            if (_e3729 == 0i) {
                                let _e3731 = local_131;
                                local_133 = _e3731.x;
                            } else {
                                let _e3733 = local_132;
                                if (_e3733 == 1i) {
                                    let _e3735 = local_131;
                                    local_133 = _e3735.y;
                                } else {
                                    let _e3737 = local_132;
                                    if (_e3737 == 2i) {
                                        let _e3739 = local_131;
                                        local_133 = _e3739.z;
                                    } else {
                                        let _e3741 = local_131;
                                        local_133 = _e3741.w;
                                    }
                                }
                            }
                            let _e3743 = local_133;
                            local_201 = _e3743;
                            let _e3744 = local_173;
                            let _e3746 = local_180[_e3744];
                            if _e3746 {
                                let _e3747 = local_171;
                                local_190 = _e3747;
                            } else {
                                local_190 = false;
                            }
                            let _e3748 = local_190;
                            if _e3748 {
                                let _e3749 = local_8;
                                local_191 = (_e3749 == 0i);
                            } else {
                                local_191 = false;
                            }
                            let _e3751 = local_191;
                            if _e3751 {
                                let _e3752 = local_173;
                                let _e3754 = local_175[_e3752];
                                local_202[_e3752] = _e3754;
                            } else {
                                let _e3756 = local_173;
                                let _e3757 = local_200;
                                let _e3758 = local_460;
                                local_202[_e3756] = (round((_e3757 * _e3758)) / _e3758);
                                let _e3764 = local_180[_e3756];
                                if _e3764 {
                                    let _e3765 = local_201;
                                    let _e3766 = local_200;
                                    let _e3768 = local_460;
                                    let _e3771 = local_199;
                                    local_192 = (abs(((_e3765 - _e3766) * _e3768)) >= _e3771);
                                } else {
                                    local_192 = false;
                                }
                                let _e3773 = local_192;
                                if _e3773 {
                                    let _e3774 = local_173;
                                    let _e3776 = local_202[_e3774];
                                    let _e3777 = local_201;
                                    let _e3778 = local_200;
                                    local_202[_e3774] = (_e3776 + (_e3777 - _e3778));
                                }
                            }
                        } else {
                            let _e3782 = local_173;
                            let _e3784 = local_175[_e3782];
                            let _e3785 = local_460;
                            local_202[_e3782] = (round((_e3784 * _e3785)) / _e3785);
                        }
                        let _e3790 = local_173;
                        local_173 = (_e3790 + 1i);
                        continue;
                    }
                    let _e3792 = local_460;
                    local_203 = (1f / _e3792);
                    let _e3794 = local_169;
                    if _e3794 {
                        let _e3795 = local_13;
                        local_182 = _e3795;
                    } else {
                        let _e3796 = local_9;
                        local_182 = _e3796;
                    }
                    let _e3797 = local_169;
                    if _e3797 {
                        let _e3798 = local_4;
                        local_199 = _e3798;
                    } else {
                        let _e3799 = local_2;
                        local_199 = _e3799;
                    }
                    let _e3800 = local_169;
                    if _e3800 {
                        let _e3801 = local_3;
                        local_204 = _e3801;
                    } else {
                        let _e3802 = local_1;
                        local_204 = _e3802;
                    }
                    let _e3803 = local_169;
                    if _e3803 {
                        let _e3804 = local_14;
                        local_168 = (_e3804 == 1i);
                    } else {
                        let _e3806 = local_10;
                        local_168 = (_e3806 != 0i);
                    }
                    let _e3808 = local_169;
                    if _e3808 {
                        let _e3809 = local_12;
                        local_172 = (_e3809 == 1i);
                    } else {
                        local_172 = false;
                    }
                    local_188 = false;
                    local_205 = 0f;
                    local_206 = 0f;
                    local_207 = 0f;
                    local_208 = 0f;
                    local_209 = 0f;
                    local_186 = 0i;
                    local_173 = 0i;
                    local_210 = 0i;
                    loop {
                        let _e3811 = local_173;
                        if (_e3811 < 16i) {
                        } else {
                            break;
                        }
                        let _e3813 = local_173;
                        let _e3814 = local_170;
                        if (_e3813 >= _e3814) {
                            break;
                        }
                        let _e3816 = local_173;
                        let _e3818 = local_177[_e3816];
                        local_211 = _e3818;
                        let _e3820 = local_177[_e3816];
                        if (_e3820 < 0i) {
                            local_190 = true;
                        } else {
                            let _e3822 = local_211;
                            let _e3823 = local_173;
                            local_190 = (_e3822 <= _e3823);
                        }
                        let _e3825 = local_190;
                        if _e3825 {
                            let _e3826 = local_188;
                            local_192 = _e3826;
                            let _e3827 = local_173;
                            local_173 = (_e3827 + 1i);
                            continue;
                        }
                        let _e3829 = local_173;
                        let _e3831 = local_176[_e3829];
                        local_213 = _e3831;
                        let _e3832 = local_458;
                        local_214 = _e3832;
                        let _e3833 = local_199;
                        local_215 = _e3833;
                        if (_e3832 > 0f) {
                            let _e3835 = local_213;
                            let _e3836 = local_214;
                            let _e3839 = local_215;
                            local_128 = (abs((_e3835 - _e3836)) <= (_e3839 * _e3836));
                        } else {
                            local_128 = false;
                        }
                        let _e3842 = local_128;
                        if _e3842 {
                            let _e3843 = local_214;
                            local_129 = _e3843;
                        } else {
                            let _e3844 = local_213;
                            local_129 = _e3844;
                        }
                        let _e3845 = local_129;
                        local_212 = _e3845;
                        let _e3846 = local_173;
                        let _e3848 = local_176[_e3846];
                        local_216 = _e3848;
                        let _e3849 = local_182;
                        if (_e3849 == 2i) {
                            local_191 = true;
                        } else {
                            let _e3851 = local_182;
                            if (_e3851 == 1i) {
                                let _e3853 = local_212;
                                let _e3854 = local_460;
                                let _e3856 = local_204;
                                local_191 = ((_e3853 * _e3854) < _e3856);
                            } else {
                                local_191 = false;
                            }
                        }
                        let _e3858 = local_191;
                        if _e3858 {
                            let _e3859 = local_212;
                            let _e3860 = local_460;
                            let _e3864 = local_203;
                            local_217 = (max(round((_e3859 * _e3860)), 1f) * _e3864);
                        } else {
                            let _e3866 = local_216;
                            local_217 = _e3866;
                        }
                        let _e3867 = local_172;
                        if _e3867 {
                            let _e3868 = local_188;
                            if _e3868 {
                                let _e3869 = local_173;
                                let _e3870 = local_205;
                                let _e3872 = local_175[_e3869];
                                let _e3873 = local_206;
                                let _e3875 = local_460;
                                let _e3878 = local_203;
                                local_202[_e3869] = (_e3870 + (round(((_e3872 - _e3873) * _e3875)) * _e3878));
                                let _e3882 = local_207;
                                local_218 = _e3882;
                                let _e3883 = local_208;
                                local_219 = _e3883;
                                let _e3884 = local_188;
                                local_192 = _e3884;
                            } else {
                                let _e3885 = local_173;
                                let _e3887 = local_175[_e3885];
                                let _e3888 = local_460;
                                let _e3891 = (round((_e3887 * _e3888)) / _e3888);
                                local_202[_e3885] = _e3891;
                                local_218 = _e3891;
                                let _e3894 = local_175[_e3885];
                                local_219 = _e3894;
                                local_192 = true;
                            }
                            let _e3895 = local_211;
                            let _e3896 = local_173;
                            let _e3898 = local_202[_e3896];
                            let _e3899 = local_217;
                            local_202[_e3895] = (_e3898 + _e3899);
                            let _e3902 = local_218;
                            let _e3904 = local_175[_e3896];
                            let _e3905 = local_219;
                            let _e3907 = local_460;
                            let _e3910 = local_203;
                            let _e3914 = local_210;
                            let _e3917 = local_202[_e3896];
                            local_218 = _e3917;
                            let _e3919 = local_175[_e3896];
                            local_219 = _e3919;
                            local_220 = _e3902;
                            local_221 = _e3905;
                            local_222 = ((_e3902 + (round(((_e3904 - _e3905) * _e3907)) * _e3910)) + _e3899);
                            local_223 = _e3895;
                            local_224 = (_e3914 + 1i);
                        } else {
                            let _e3920 = local_169;
                            if _e3920 {
                                let _e3921 = local_14;
                                local_192 = (_e3921 != 0i);
                            } else {
                                let _e3923 = local_10;
                                local_192 = (_e3923 != 0i);
                            }
                            let _e3925 = local_192;
                            if _e3925 {
                                let _e3926 = local_173;
                                let _e3928 = local_178[_e3926];
                                local_193 = (_e3928 >= 0i);
                            } else {
                                local_193 = false;
                            }
                            let _e3930 = local_192;
                            if _e3930 {
                                let _e3931 = local_211;
                                let _e3933 = local_178[_e3931];
                                local_194 = (_e3933 >= 0i);
                            } else {
                                local_194 = false;
                            }
                            let _e3935 = local_168;
                            if !(_e3935) {
                                let _e3937 = local_173;
                                let _e3939 = local_175[_e3937];
                                local_202[_e3937] = _e3939;
                            }
                            let _e3941 = local_194;
                            if _e3941 {
                                let _e3942 = local_193;
                                local_195 = !(_e3942);
                            } else {
                                local_195 = false;
                            }
                            let _e3944 = local_195;
                            if _e3944 {
                                let _e3945 = local_168;
                                local_225 = _e3945;
                            } else {
                                local_225 = false;
                            }
                            let _e3946 = local_225;
                            if _e3946 {
                                let _e3947 = local_173;
                                let _e3948 = local_211;
                                let _e3950 = local_202[_e3948];
                                let _e3951 = local_217;
                                local_202[_e3947] = (_e3950 - _e3951);
                            } else {
                                let _e3954 = local_211;
                                let _e3955 = local_173;
                                let _e3957 = local_202[_e3955];
                                let _e3958 = local_217;
                                local_202[_e3954] = (_e3957 + _e3958);
                            }
                            let _e3961 = local_188;
                            local_192 = _e3961;
                            let _e3962 = local_205;
                            local_218 = _e3962;
                            let _e3963 = local_206;
                            local_219 = _e3963;
                            let _e3964 = local_207;
                            local_220 = _e3964;
                            let _e3965 = local_208;
                            local_221 = _e3965;
                            let _e3966 = local_209;
                            local_222 = _e3966;
                            let _e3967 = local_186;
                            local_223 = _e3967;
                            let _e3968 = local_210;
                            local_224 = _e3968;
                        }
                        let _e3969 = local_173;
                        local_189[_e3969] = true;
                        let _e3971 = local_211;
                        local_189[_e3971] = true;
                        let _e3973 = local_218;
                        local_205 = _e3973;
                        let _e3974 = local_219;
                        local_206 = _e3974;
                        let _e3975 = local_220;
                        local_207 = _e3975;
                        let _e3976 = local_221;
                        local_208 = _e3976;
                        let _e3977 = local_222;
                        local_209 = _e3977;
                        let _e3978 = local_223;
                        local_186 = _e3978;
                        let _e3979 = local_224;
                        local_210 = _e3979;
                        let _e3981 = local_192;
                        local_188 = _e3981;
                        local_173 = (_e3969 + 1i);
                        continue;
                    }
                    let _e3982 = local_172;
                    if _e3982 {
                        let _e3983 = local_210;
                        local_168 = (_e3983 > 1i);
                    } else {
                        local_168 = false;
                    }
                    let _e3985 = local_168;
                    if _e3985 {
                        let _e3986 = local_209;
                        let _e3987 = local_186;
                        let _e3989 = local_202[_e3987];
                        local_226 = (_e3986 - _e3989);
                        local_173 = 0i;
                        loop {
                            let _e3991 = local_173;
                            if (_e3991 < 16i) {
                            } else {
                                break;
                            }
                            let _e3993 = local_173;
                            let _e3994 = local_170;
                            if (_e3993 >= _e3994) {
                                break;
                            }
                            let _e3996 = local_173;
                            let _e3998 = local_189[_e3996];
                            if _e3998 {
                                let _e3999 = local_173;
                                let _e4001 = local_202[_e3999];
                                let _e4002 = local_226;
                                local_202[_e3999] = (_e4001 + _e4002);
                            }
                            let _e4005 = local_173;
                            local_173 = (_e4005 + 1i);
                            continue;
                        }
                    }
                    let _e4007 = local_182;
                    if (_e4007 == 1i) {
                        let _e4009 = local_204;
                        local_199 = _e4009;
                    } else {
                        local_199 = 1.6f;
                    }
                    local_173 = 0i;
                    loop {
                        let _e4010 = local_173;
                        if (_e4010 < 16i) {
                        } else {
                            break;
                        }
                        let _e4012 = local_173;
                        let _e4013 = local_170;
                        if (_e4012 >= _e4013) {
                            break;
                        }
                        let _e4015 = local_169;
                        if _e4015 {
                            let _e4016 = local_14;
                            local_192 = (_e4016 != 0i);
                        } else {
                            let _e4018 = local_10;
                            local_192 = (_e4018 != 0i);
                        }
                        let _e4020 = local_192;
                        if !(_e4020) {
                            local_168 = true;
                        } else {
                            let _e4022 = local_173;
                            let _e4024 = local_178[_e4022];
                            local_168 = (_e4024 < 0i);
                        }
                        let _e4026 = local_168;
                        if _e4026 {
                            local_172 = true;
                        } else {
                            let _e4027 = local_173;
                            let _e4029 = local_180[_e4027];
                            local_172 = !(_e4029);
                        }
                        let _e4031 = local_172;
                        if _e4031 {
                            local_188 = true;
                        } else {
                            let _e4032 = local_173;
                            let _e4034 = local_189[_e4032];
                            local_188 = _e4034;
                        }
                        let _e4035 = local_188;
                        if _e4035 {
                            let _e4036 = local_173;
                            local_173 = (_e4036 + 1i);
                            continue;
                        }
                        let _e4038 = local_173;
                        let _e4040 = local_183[_e4038];
                        local_227 = (_e4040 > 0i);
                        let _e4043 = local_187[_e4038];
                        local_228 = _e4043;
                        let _e4045 = local_187[_e4038];
                        if (_e4045 >= 0i) {
                            let _e4047 = local_227;
                            if _e4047 {
                                let _e4048 = local_173;
                                let _e4050 = local_175[_e4048];
                                let _e4051 = local_228;
                                let _e4053 = local_175[_e4051];
                                local_204 = (_e4050 - _e4053);
                            } else {
                                let _e4055 = local_228;
                                let _e4057 = local_175[_e4055];
                                let _e4058 = local_173;
                                let _e4060 = local_175[_e4058];
                                local_204 = (_e4057 - _e4060);
                            }
                            let _e4062 = local_228;
                            local_223 = _e4062;
                            let _e4063 = local_204;
                            local_217 = _e4063;
                        } else {
                            let _e4064 = local_228;
                            if (_e4064 == -2i) {
                                local_217 = 340282350000000000000000000000000000000f;
                                let _e4066 = local_228;
                                local_223 = _e4066;
                                local_224 = 0i;
                                loop {
                                    let _e4067 = local_224;
                                    if (_e4067 < 16i) {
                                    } else {
                                        break;
                                    }
                                    let _e4069 = local_224;
                                    let _e4070 = local_170;
                                    if (_e4069 >= _e4070) {
                                        break;
                                    }
                                    let _e4072 = local_224;
                                    let _e4073 = local_173;
                                    if (_e4072 == _e4073) {
                                        local_190 = true;
                                    } else {
                                        let _e4075 = local_224;
                                        let _e4077 = local_183[_e4075];
                                        let _e4078 = local_173;
                                        let _e4080 = local_183[_e4078];
                                        local_190 = (_e4077 == _e4080);
                                    }
                                    let _e4082 = local_190;
                                    if _e4082 {
                                        let _e4083 = local_224;
                                        local_224 = (_e4083 + 1i);
                                        continue;
                                    }
                                    let _e4085 = local_227;
                                    if _e4085 {
                                        let _e4086 = local_173;
                                        let _e4088 = local_175[_e4086];
                                        let _e4089 = local_224;
                                        let _e4091 = local_175[_e4089];
                                        local_218 = (_e4088 - _e4091);
                                    } else {
                                        let _e4093 = local_224;
                                        let _e4095 = local_175[_e4093];
                                        let _e4096 = local_173;
                                        let _e4098 = local_175[_e4096];
                                        local_218 = (_e4095 - _e4098);
                                    }
                                    let _e4100 = local_218;
                                    if (_e4100 <= 0f) {
                                        local_191 = true;
                                    } else {
                                        let _e4102 = local_218;
                                        let _e4103 = local_217;
                                        local_191 = (_e4102 >= _e4103);
                                    }
                                    let _e4105 = local_191;
                                    if _e4105 {
                                        let _e4106 = local_224;
                                        local_224 = (_e4106 + 1i);
                                        continue;
                                    }
                                    let _e4108 = local_218;
                                    local_217 = _e4108;
                                    let _e4109 = local_224;
                                    local_223 = _e4109;
                                    local_224 = (_e4109 + 1i);
                                    continue;
                                }
                            } else {
                                let _e4111 = local_228;
                                local_223 = _e4111;
                                local_217 = 340282350000000000000000000000000000000f;
                            }
                        }
                        let _e4112 = local_223;
                        if (_e4112 < 0i) {
                            local_190 = true;
                        } else {
                            let _e4114 = local_223;
                            let _e4116 = local_189[_e4114];
                            local_190 = _e4116;
                        }
                        let _e4117 = local_190;
                        if _e4117 {
                            local_191 = true;
                        } else {
                            let _e4118 = local_223;
                            let _e4120 = local_178[_e4118];
                            local_191 = (_e4120 >= 0i);
                        }
                        let _e4122 = local_191;
                        if _e4122 {
                            local_193 = true;
                        } else {
                            let _e4123 = local_217;
                            let _e4124 = local_460;
                            let _e4126 = local_199;
                            local_193 = ((_e4123 * _e4124) >= _e4126);
                        }
                        let _e4128 = local_193;
                        if _e4128 {
                            let _e4129 = local_173;
                            local_173 = (_e4129 + 1i);
                            continue;
                        }
                        let _e4131 = local_223;
                        let _e4133 = local_181[_e4131];
                        if _e4133 {
                            let _e4134 = local_217;
                            local_218 = _e4134;
                        } else {
                            let _e4135 = local_217;
                            let _e4136 = local_460;
                            let _e4140 = local_203;
                            local_218 = (max(round((_e4135 * _e4136)), 1f) * _e4140);
                        }
                        let _e4142 = local_227;
                        if _e4142 {
                            let _e4143 = local_173;
                            let _e4145 = local_202[_e4143];
                            let _e4146 = local_218;
                            local_204 = (_e4145 - _e4146);
                        } else {
                            let _e4148 = local_173;
                            let _e4150 = local_202[_e4148];
                            let _e4151 = local_218;
                            local_204 = (_e4150 + _e4151);
                        }
                        let _e4153 = local_223;
                        let _e4154 = local_204;
                        local_202[_e4153] = _e4154;
                        local_189[_e4153] = true;
                        let _e4157 = local_173;
                        local_173 = (_e4157 + 1i);
                        continue;
                    }
                    local_173 = 0i;
                    loop {
                        let _e4159 = local_173;
                        if (_e4159 < 16i) {
                        } else {
                            break;
                        }
                        let _e4161 = local_173;
                        let _e4162 = local_170;
                        if (_e4161 >= _e4162) {
                            break;
                        }
                        let _e4164 = local_169;
                        if _e4164 {
                            let _e4165 = local_14;
                            local_192 = (_e4165 != 0i);
                        } else {
                            let _e4167 = local_10;
                            local_192 = (_e4167 != 0i);
                        }
                        let _e4169 = local_173;
                        let _e4171 = local_189[_e4169];
                        if !(_e4171) {
                            let _e4173 = local_192;
                            if _e4173 {
                                let _e4174 = local_173;
                                let _e4176 = local_178[_e4174];
                                local_168 = (_e4176 >= 0i);
                            } else {
                                local_168 = false;
                            }
                            let _e4178 = local_168;
                            local_168 = !(_e4178);
                        } else {
                            local_168 = false;
                        }
                        let _e4180 = local_168;
                        if _e4180 {
                            let _e4181 = local_173;
                            local_173 = (_e4181 + 1i);
                            continue;
                        }
                        let _e4183 = local_461;
                        let _e4184 = local_173;
                        let _e4186 = local_175[_e4184];
                        local_462[_e4183] = _e4186;
                        let _e4189 = local_202[_e4184];
                        local_463[_e4183] = _e4189;
                        let _e4191 = local_192;
                        if _e4191 {
                            let _e4192 = local_173;
                            let _e4194 = local_178[_e4192];
                            local_172 = (_e4194 >= 0i);
                        } else {
                            local_172 = false;
                        }
                        let _e4196 = local_461;
                        let _e4197 = local_172;
                        local_229[_e4196] = _e4197;
                        let _e4199 = local_173;
                        let _e4201 = local_181[_e4199];
                        local_230[_e4196] = _e4201;
                        local_464[_e4196] = _e4199;
                        local_461 = (_e4196 + 1i);
                        local_173 = (_e4199 + 1i);
                        continue;
                    }
                    let _e4206 = local_169;
                    if _e4206 {
                        let _e4207 = local_11;
                        local_168 = (_e4207 == 1i);
                    } else {
                        local_168 = false;
                    }
                    let _e4209 = local_168;
                    if _e4209 {
                        let _e4210 = local_461;
                        local_168 = (_e4210 > 0i);
                    } else {
                        local_168 = false;
                    }
                    let _e4212 = local_168;
                    if _e4212 {
                        let _e4213 = local_461;
                        local_168 = (_e4213 < 16i);
                    } else {
                        local_168 = false;
                    }
                    let _e4215 = local_168;
                    if _e4215 {
                        let _e4216 = local_459;
                        let _e4218 = local_462[0i];
                        let _e4219 = local_203;
                        local_168 = (_e4216 < (_e4218 - (0.25f * _e4219)));
                    } else {
                        local_168 = false;
                    }
                    let _e4223 = local_168;
                    if _e4223 {
                        local_173 = 15i;
                        loop {
                            let _e4224 = local_173;
                            if (_e4224 > 0i) {
                            } else {
                                break;
                            }
                            let _e4226 = local_173;
                            let _e4227 = local_461;
                            if (_e4226 <= _e4227) {
                                let _e4229 = local_173;
                                let _e4230 = (_e4229 - 1i);
                                let _e4232 = local_462[_e4230];
                                local_462[_e4229] = _e4232;
                                let _e4235 = local_463[_e4230];
                                local_463[_e4229] = _e4235;
                                let _e4238 = local_229[_e4230];
                                local_229[_e4229] = _e4238;
                                let _e4241 = local_230[_e4230];
                                local_230[_e4229] = _e4241;
                                let _e4244 = local_464[_e4230];
                                local_464[_e4229] = _e4244;
                            }
                            let _e4246 = local_173;
                            local_173 = (_e4246 - 1i);
                            continue;
                        }
                        let _e4248 = local_459;
                        local_462[0i] = _e4248;
                        let _e4250 = local_460;
                        local_463[0i] = (round((_e4248 * _e4250)) / _e4250);
                        local_229[0i] = false;
                        local_230[0i] = false;
                        local_464[0i] = 32i;
                        let _e4258 = local_461;
                        local_461 = (_e4258 + 1i);
                    }
                    local_223 = 15i;
                    loop {
                        let _e4260 = local_223;
                        if (_e4260 > 0i) {
                        } else {
                            break;
                        }
                        let _e4262 = local_223;
                        let _e4263 = local_461;
                        if (_e4262 >= _e4263) {
                            local_168 = true;
                        } else {
                            let _e4265 = local_223;
                            let _e4267 = local_229[_e4265];
                            local_168 = !(_e4267);
                        }
                        let _e4269 = local_168;
                        if _e4269 {
                            let _e4270 = local_223;
                            local_223 = (_e4270 - 1i);
                            continue;
                        }
                        local_224 = 15i;
                        loop {
                            let _e4272 = local_224;
                            if (_e4272 > 0i) {
                            } else {
                                break;
                            }
                            let _e4274 = local_224;
                            let _e4275 = local_223;
                            if (_e4274 > _e4275) {
                                let _e4277 = local_224;
                                local_224 = (_e4277 - 1i);
                                continue;
                            }
                            let _e4279 = local_224;
                            let _e4280 = (_e4279 - 1i);
                            local_231 = _e4280;
                            let _e4282 = local_229[_e4280];
                            if _e4282 {
                                break;
                            }
                            let _e4283 = local_231;
                            let _e4285 = local_230[_e4283];
                            if _e4285 {
                                local_199 = 0.000001f;
                            } else {
                                let _e4286 = local_203;
                                local_199 = _e4286;
                            }
                            let _e4287 = local_231;
                            let _e4289 = local_463[_e4287];
                            let _e4290 = local_224;
                            let _e4292 = local_463[_e4290];
                            let _e4293 = local_199;
                            local_463[_e4287] = min(_e4289, (_e4292 - _e4293));
                            local_224 = (_e4290 - 1i);
                            continue;
                        }
                        let _e4298 = local_223;
                        local_223 = (_e4298 - 1i);
                        continue;
                    }
                    local_173 = 1i;
                    loop {
                        let _e4300 = local_173;
                        if (_e4300 < 16i) {
                        } else {
                            break;
                        }
                        let _e4302 = local_173;
                        let _e4303 = local_461;
                        if (_e4302 >= _e4303) {
                            break;
                        }
                        let _e4305 = local_173;
                        let _e4307 = local_463[_e4305];
                        let _e4310 = local_463[(_e4305 - 1i)];
                        if (_e4307 <= _e4310) {
                            let _e4312 = local_173;
                            let _e4315 = local_463[(_e4312 - 1i)];
                            let _e4316 = local_203;
                            local_463[_e4312] = (_e4315 + _e4316);
                        }
                        let _e4319 = local_173;
                        local_173 = (_e4319 + 1i);
                        continue;
                    }
                    let _e4321 = local_7;
                    if (_e4321 != 0i) {
                        let _e4323 = local_460;
                        let _e4324 = local_6;
                        local_168 = (_e4323 > _e4324);
                    } else {
                        local_168 = false;
                    }
                    let _e4326 = local_168;
                    if _e4326 {
                        let _e4327 = local_5;
                        let _e4328 = local_6;
                        let _e4329 = (_e4327 - _e4328);
                        local_232 = _e4329;
                        if (_e4329 <= 0f) {
                            local_168 = true;
                        } else {
                            let _e4331 = local_460;
                            let _e4332 = local_5;
                            local_168 = (_e4331 >= _e4332);
                        }
                        let _e4334 = local_168;
                        if _e4334 {
                            local_199 = 1f;
                        } else {
                            let _e4335 = local_460;
                            let _e4336 = local_6;
                            let _e4338 = local_232;
                            local_199 = ((_e4335 - _e4336) / _e4338);
                        }
                        local_173 = 0i;
                        loop {
                            let _e4340 = local_173;
                            if (_e4340 < 16i) {
                            } else {
                                break;
                            }
                            let _e4342 = local_173;
                            let _e4343 = local_461;
                            if (_e4342 >= _e4343) {
                                break;
                            }
                            let _e4345 = local_173;
                            let _e4347 = local_463[_e4345];
                            let _e4349 = local_462[_e4345];
                            let _e4351 = local_463[_e4345];
                            let _e4353 = local_199;
                            local_463[_e4345] = (_e4347 + ((_e4349 - _e4351) * _e4353));
                            local_173 = (_e4345 + 1i);
                            continue;
                        }
                    }
                    local_173 = 0i;
                    loop {
                        let _e4358 = local_173;
                        if (_e4358 < 16i) {
                        } else {
                            break;
                        }
                        let _e4360 = local_173;
                        let _e4361 = local_461;
                        if (_e4360 >= _e4361) {
                            break;
                        }
                        let _e4363 = local_173;
                        let _e4365 = local_462[_e4363];
                        if !((abs(_e4365) <= 340282300000000000000000000000000000000f)) {
                            local_168 = true;
                        } else {
                            let _e4369 = local_173;
                            let _e4371 = local_463[_e4369];
                            local_168 = !((abs(_e4371) <= 340282300000000000000000000000000000000f));
                        }
                        let _e4375 = local_168;
                        if _e4375 {
                            local_461 = 0i;
                            local_166 = true;
                            local_167 = false;
                            break;
                        }
                        let _e4376 = local_173;
                        local_173 = (_e4376 + 1i);
                        continue;
                    }
                    let _e4378 = local_166;
                    if _e4378 {
                        break;
                    }
                    local_166 = true;
                    local_167 = true;
                    break;
                }
            }
            let _e4379 = local_167;
            let _e4380 = local_461;
            local_442 = _e4380;
            let _e4381 = local_463;
            local_46 = _e4381[0];
            local_45 = _e4381[1];
            local_44 = _e4381[2];
            local_43 = _e4381[3];
            local_42 = _e4381[4];
            local_41 = _e4381[5];
            local_40 = _e4381[6];
            local_39 = _e4381[7];
            local_38 = _e4381[8];
            local_37 = _e4381[9];
            local_36 = _e4381[10];
            local_35 = _e4381[11];
            local_34 = _e4381[12];
            local_33 = _e4381[13];
            local_32 = _e4381[14];
            local_31 = _e4381[15];
            let _e4398 = local_464;
            local_30 = _e4398[0];
            local_29 = _e4398[1];
            local_28 = _e4398[2];
            local_27 = _e4398[3];
            local_26 = _e4398[4];
            local_25 = _e4398[5];
            local_24 = _e4398[6];
            local_23 = _e4398[7];
            local_22 = _e4398[8];
            local_21 = _e4398[9];
            local_20 = _e4398[10];
            local_19 = _e4398[11];
            local_18 = _e4398[12];
            local_17 = _e4398[13];
            local_16 = _e4398[14];
            local_15 = _e4398[15];
            local_454 = _e4379;
            let _e4415 = local_443;
            if _e4415 {
                let _e4416 = local_441;
                local_465 = _e4416;
                let _e4417 = local_78;
                let _e4418 = local_79;
                let _e4419 = local_80;
                let _e4420 = local_81;
                let _e4421 = local_82;
                let _e4422 = local_83;
                let _e4423 = local_84;
                let _e4424 = local_85;
                let _e4425 = local_86;
                let _e4426 = local_87;
                let _e4427 = local_88;
                let _e4428 = local_89;
                let _e4429 = local_90;
                let _e4430 = local_91;
                let _e4431 = local_92;
                let _e4432 = local_93;
                local_466 = array<f32, 16>(_e4432, _e4431, _e4430, _e4429, _e4428, _e4427, _e4426, _e4425, _e4424, _e4423, _e4422, _e4421, _e4420, _e4419, _e4418, _e4417);
                let _e4434 = local_62;
                let _e4435 = local_63;
                let _e4436 = local_64;
                let _e4437 = local_65;
                let _e4438 = local_66;
                let _e4439 = local_67;
                let _e4440 = local_68;
                let _e4441 = local_69;
                let _e4442 = local_70;
                let _e4443 = local_71;
                let _e4444 = local_72;
                let _e4445 = local_73;
                let _e4446 = local_74;
                let _e4447 = local_75;
                let _e4448 = local_76;
                let _e4449 = local_77;
                local_467 = array<i32, 16>(_e4449, _e4448, _e4447, _e4446, _e4445, _e4444, _e4443, _e4442, _e4441, _e4440, _e4439, _e4438, _e4437, _e4436, _e4435, _e4434);
                switch bitcast<i32>(0u) {
                    default: {
                        local_127 = 0i;
                        loop {
                            let _e4452 = local_127;
                            if (_e4452 < 4i) {
                            } else {
                                break;
                            }
                            let _e4454 = local_127;
                            local_468[_e4454] = vec4<f32>(0f, 0f, 0f, 0f);
                            local_127 = (_e4454 + 1i);
                            continue;
                        }
                        local_469 = vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u);
                        let _e4457 = local_465;
                        if (_e4457 > 16i) {
                            let _e4460 = local_469[0u];
                            local_469[0u] = ((_e4460 & 4294967040u) | 254u);
                            break;
                        }
                        local_127 = 0i;
                        loop {
                            let _e4464 = local_127;
                            if (_e4464 < 16i) {
                            } else {
                                break;
                            }
                            let _e4466 = local_127;
                            let _e4467 = local_465;
                            if (_e4466 >= _e4467) {
                                break;
                            }
                            let _e4469 = local_127;
                            let _e4471 = (_e4469 >> bitcast<u32>(2i));
                            let _e4472 = (_e4469 & 3i);
                            let _e4474 = local_466[_e4469];
                            local_468[_e4471][_e4472] = _e4474;
                            let _e4478 = bitcast<u32>((_e4472 * 8i));
                            let _e4480 = local_469[_e4471];
                            let _e4486 = local_467[_e4469];
                            local_469[_e4471] = ((_e4480 & ~((255u << bitcast<u32>(_e4478)))) | ((bitcast<u32>(_e4486) & 255u) << bitcast<u32>(_e4478)));
                            local_127 = (_e4469 + 1i);
                            continue;
                        }
                        break;
                    }
                }
                let _e4494 = local_468;
                v_ah_x_targets_0_ = _e4494;
                let _e4495 = local_469;
                _S26_ = _e4495;
            } else {
                local_126 = 0i;
                loop {
                    let _e4496 = local_126;
                    if (_e4496 < 4i) {
                    } else {
                        break;
                    }
                    let _e4498 = local_126;
                    local_470[_e4498] = vec4<f32>(0f, 0f, 0f, 0f);
                    local_126 = (_e4498 + 1i);
                    continue;
                }
                let _e4506 = local_470;
                v_ah_x_targets_0_ = _e4506;
                _S26_ = vec4<u32>(4294967294u, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).y, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).z, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).w);
            }
            let _e4507 = local_454;
            if _e4507 {
                let _e4508 = local_442;
                local_471 = _e4508;
                let _e4509 = local_31;
                let _e4510 = local_32;
                let _e4511 = local_33;
                let _e4512 = local_34;
                let _e4513 = local_35;
                let _e4514 = local_36;
                let _e4515 = local_37;
                let _e4516 = local_38;
                let _e4517 = local_39;
                let _e4518 = local_40;
                let _e4519 = local_41;
                let _e4520 = local_42;
                let _e4521 = local_43;
                let _e4522 = local_44;
                let _e4523 = local_45;
                let _e4524 = local_46;
                local_472 = array<f32, 16>(_e4524, _e4523, _e4522, _e4521, _e4520, _e4519, _e4518, _e4517, _e4516, _e4515, _e4514, _e4513, _e4512, _e4511, _e4510, _e4509);
                let _e4526 = local_15;
                let _e4527 = local_16;
                let _e4528 = local_17;
                let _e4529 = local_18;
                let _e4530 = local_19;
                let _e4531 = local_20;
                let _e4532 = local_21;
                let _e4533 = local_22;
                let _e4534 = local_23;
                let _e4535 = local_24;
                let _e4536 = local_25;
                let _e4537 = local_26;
                let _e4538 = local_27;
                let _e4539 = local_28;
                let _e4540 = local_29;
                let _e4541 = local_30;
                local_473 = array<i32, 16>(_e4541, _e4540, _e4539, _e4538, _e4537, _e4536, _e4535, _e4534, _e4533, _e4532, _e4531, _e4530, _e4529, _e4528, _e4527, _e4526);
                switch bitcast<i32>(0u) {
                    default: {
                        local_125 = 0i;
                        loop {
                            let _e4544 = local_125;
                            if (_e4544 < 4i) {
                            } else {
                                break;
                            }
                            let _e4546 = local_125;
                            local_474[_e4546] = vec4<f32>(0f, 0f, 0f, 0f);
                            local_125 = (_e4546 + 1i);
                            continue;
                        }
                        local_475 = vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u);
                        let _e4549 = local_471;
                        if (_e4549 > 16i) {
                            let _e4552 = local_475[0u];
                            local_475[0u] = ((_e4552 & 4294967040u) | 254u);
                            break;
                        }
                        local_125 = 0i;
                        loop {
                            let _e4556 = local_125;
                            if (_e4556 < 16i) {
                            } else {
                                break;
                            }
                            let _e4558 = local_125;
                            let _e4559 = local_471;
                            if (_e4558 >= _e4559) {
                                break;
                            }
                            let _e4561 = local_125;
                            let _e4563 = (_e4561 >> bitcast<u32>(2i));
                            let _e4564 = (_e4561 & 3i);
                            let _e4566 = local_472[_e4561];
                            local_474[_e4563][_e4564] = _e4566;
                            let _e4570 = bitcast<u32>((_e4564 * 8i));
                            let _e4572 = local_475[_e4563];
                            let _e4578 = local_473[_e4561];
                            local_475[_e4563] = ((_e4572 & ~((255u << bitcast<u32>(_e4570)))) | ((bitcast<u32>(_e4578) & 255u) << bitcast<u32>(_e4570)));
                            local_125 = (_e4561 + 1i);
                            continue;
                        }
                        break;
                    }
                }
                let _e4586 = local_474;
                v_ah_y_targets_0_ = _e4586;
                let _e4587 = local_475;
                _S27_ = _e4587;
            } else {
                local_124 = 0i;
                loop {
                    let _e4588 = local_124;
                    if (_e4588 < 4i) {
                    } else {
                        break;
                    }
                    let _e4590 = local_124;
                    local_476[_e4590] = vec4<f32>(0f, 0f, 0f, 0f);
                    local_124 = (_e4590 + 1i);
                    continue;
                }
                let _e4598 = local_476;
                v_ah_y_targets_0_ = _e4598;
                _S27_ = vec4<u32>(4294967294u, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).y, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).z, vec4<u32>(4294967295u, 4294967295u, 4294967295u, 4294967295u).w);
            }
            break;
        }
    }
    let _e4600 = v_ah_x_targets_0_[0i];
    let _e4602 = v_ah_x_targets_0_[1i];
    let _e4604 = v_ah_x_targets_0_[2i];
    let _e4606 = v_ah_x_targets_0_[3i];
    let _e4608 = v_ah_y_targets_0_[0i];
    let _e4610 = v_ah_y_targets_0_[1i];
    let _e4612 = v_ah_y_targets_0_[2i];
    let _e4614 = v_ah_y_targets_0_[3i];
    let _e4615 = _S2_;
    let _e4616 = _S3_;
    let _e4617 = _S4_;
    let _e4618 = _S6_;
    let _e4619 = _S8_;
    let _e4620 = _S26_;
    let _e4621 = _S27_;
    let _e4622 = _S1_;
    entryPointParam_main_v_info_0_ = _e4622;
    entryPointParam_main_v_policy0_0_ = _e4615;
    entryPointParam_main_v_policy1_0_ = _e4616;
    entryPointParam_main_v_texcoord_layer_0_ = _e4617;
    entryPointParam_main_v_paint_0_ = _e4618;
    unnamed.gl_Position = _e4619;
    entryPointParam_main_v_ah_x_sources_0_ = _e4620;
    entryPointParam_main_v_ah_y_sources_0_ = _e4621;
    entryPointParam_main_v_ah_x_targets0_0_ = _e4600;
    entryPointParam_main_v_ah_x_targets1_0_ = _e4602;
    entryPointParam_main_v_ah_x_targets2_0_ = _e4604;
    entryPointParam_main_v_ah_x_targets3_0_ = _e4606;
    entryPointParam_main_v_ah_y_targets0_0_ = _e4608;
    entryPointParam_main_v_ah_y_targets1_0_ = _e4610;
    entryPointParam_main_v_ah_y_targets2_0_ = _e4612;
    entryPointParam_main_v_ah_y_targets3_0_ = _e4614;
    return;
}

@vertex 
fn main(@builtin(vertex_index) gl_VertexIndex: u32, @location(0) a_rect_0_: vec4<f32>, @location(1) a_xform_0_: vec4<f32>, @location(2) a_origin_0_: vec2<f32>, @location(3) a_glyph_0_: vec2<u32>, @location(7) a_policy0_0_: vec4<u32>, @location(8) a_policy1_0_: vec3<u32>, @location(4) a_bnd_0_: vec4<f32>, @location(5) a_col_0_: vec4<f32>, @location(6) a_tint_0_: vec4<f32>) -> VertexOutput {
    gl_VertexIndex_1 = i32(gl_VertexIndex);
    a_rect_0_1 = a_rect_0_;
    a_xform_0_1 = a_xform_0_;
    a_origin_0_1 = a_origin_0_;
    a_glyph_0_1 = a_glyph_0_;
    a_policy0_0_1 = a_policy0_0_;
    a_policy1_0_1 = a_policy1_0_;
    a_bnd_0_1 = a_bnd_0_;
    a_col_0_1 = a_col_0_;
    a_tint_0_1 = a_tint_0_;
    main_1();
    let _e39 = unnamed.gl_Position.y;
    unnamed.gl_Position.y = -(_e39);
    let _e41 = entryPointParam_main_v_info_0_;
    let _e42 = entryPointParam_main_v_policy0_0_;
    let _e43 = entryPointParam_main_v_policy1_0_;
    let _e44 = entryPointParam_main_v_texcoord_layer_0_;
    let _e45 = entryPointParam_main_v_paint_0_;
    let _e46 = unnamed.gl_Position;
    let _e47 = entryPointParam_main_v_ah_x_sources_0_;
    let _e48 = entryPointParam_main_v_ah_y_sources_0_;
    let _e49 = entryPointParam_main_v_ah_x_targets0_0_;
    let _e50 = entryPointParam_main_v_ah_x_targets1_0_;
    let _e51 = entryPointParam_main_v_ah_x_targets2_0_;
    let _e52 = entryPointParam_main_v_ah_x_targets3_0_;
    let _e53 = entryPointParam_main_v_ah_y_targets0_0_;
    let _e54 = entryPointParam_main_v_ah_y_targets1_0_;
    let _e55 = entryPointParam_main_v_ah_y_targets2_0_;
    let _e56 = entryPointParam_main_v_ah_y_targets3_0_;
    return VertexOutput(_e41, _e42, _e43, _e44, _e45, _e46, _e47, _e48, _e49, _e50, _e51, _e52, _e53, _e54, _e55, _e56);
}
