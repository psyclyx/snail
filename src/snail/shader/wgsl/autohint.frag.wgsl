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
var<private> v_info_0_1: vec2<i32>;
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
var<private> v_texcoord_layer_0_1: vec3<f32>;
var<private> v_ah_x_sources_0_1: vec4<u32>;
var<private> v_ah_y_sources_0_1: vec4<u32>;
var<private> v_policy0_0_1: vec4<u32>;
var<private> v_policy1_0_1: vec3<u32>;
var<private> v_paint_0_1: vec4<f32>;
var<private> v_ah_x_targets0_0_1: vec4<f32>;
var<private> v_ah_x_targets1_0_1: vec4<f32>;
var<private> v_ah_x_targets2_0_1: vec4<f32>;
var<private> v_ah_x_targets3_0_1: vec4<f32>;
var<private> v_ah_y_targets0_0_1: vec4<f32>;
var<private> v_ah_y_targets1_0_1: vec4<f32>;
var<private> v_ah_y_targets2_0_1: vec4<f32>;
var<private> v_ah_y_targets3_0_1: vec4<f32>;
var<private> entryPointParam_main_frag_color_0_: vec4<f32>;

fn main_1() {
    var local: vec4<f32>;
    var local_1: vec4<f32>;
    var local_2: vec4<f32>;
    var local_3: vec4<f32>;
    var local_4: vec4<f32>;
    var local_5: vec4<f32>;
    var local_6: vec4<f32>;
    var local_7: vec4<f32>;
    var local_8: vec4<f32>;
    var local_9: vec4<f32>;
    var local_10: vec4<f32>;
    var local_11: vec4<f32>;
    var local_12: f32;
    var local_13: f32;
    var local_14: f32;
    var local_15: f32;
    var local_16: f32;
    var local_17: f32;
    var local_18: f32;
    var local_19: i32;
    var local_20: i32;
    var local_21: i32;
    var local_22: i32;
    var local_23: i32;
    var local_24: i32;
    var local_25: i32;
    var local_26: i32;
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
    var local_70: f32;
    var local_71: f32;
    var local_72: f32;
    var local_73: f32;
    var local_74: f32;
    var local_75: f32;
    var local_76: f32;
    var local_77: f32;
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
    var local_98: i32;
    var local_99: i32;
    var local_100: i32;
    var local_101: i32;
    var local_102: i32;
    var local_103: i32;
    var local_104: i32;
    var local_105: i32;
    var local_106: f32;
    var local_107: f32;
    var local_108: f32;
    var local_109: f32;
    var local_110: f32;
    var local_111: f32;
    var local_112: f32;
    var local_113: f32;
    var local_114: f32;
    var local_115: f32;
    var local_116: f32;
    var local_117: f32;
    var local_118: f32;
    var local_119: f32;
    var local_120: f32;
    var local_121: f32;
    var local_122: f32;
    var local_123: f32;
    var local_124: f32;
    var local_125: f32;
    var local_126: f32;
    var local_127: f32;
    var local_128: f32;
    var local_129: f32;
    var local_130: f32;
    var local_131: f32;
    var local_132: f32;
    var local_133: f32;
    var local_134: f32;
    var local_135: f32;
    var local_136: f32;
    var local_137: f32;
    var local_138: f32;
    var local_139: f32;
    var local_140: f32;
    var local_141: f32;
    var local_142: f32;
    var local_143: f32;
    var local_144: f32;
    var local_145: f32;
    var local_146: f32;
    var local_147: f32;
    var local_148: f32;
    var local_149: f32;
    var local_150: f32;
    var local_151: f32;
    var local_152: f32;
    var local_153: f32;
    var local_154: f32;
    var local_155: f32;
    var local_156: f32;
    var local_157: f32;
    var local_158: f32;
    var local_159: f32;
    var local_160: f32;
    var local_161: f32;
    var local_162: f32;
    var local_163: f32;
    var local_164: f32;
    var local_165: f32;
    var local_166: f32;
    var local_167: f32;
    var local_168: f32;
    var local_169: f32;
    var local_170: f32;
    var local_171: f32;
    var local_172: f32;
    var local_173: f32;
    var local_174: f32;
    var local_175: f32;
    var local_176: f32;
    var local_177: i32;
    var local_178: i32;
    var local_179: i32;
    var local_180: i32;
    var local_181: i32;
    var local_182: i32;
    var local_183: i32;
    var local_184: i32;
    var local_185: f32;
    var local_186: f32;
    var local_187: f32;
    var local_188: f32;
    var local_189: f32;
    var local_190: f32;
    var local_191: f32;
    var local_192: i32;
    var local_193: i32;
    var local_194: i32;
    var local_195: i32;
    var local_196: i32;
    var local_197: i32;
    var local_198: i32;
    var local_199: i32;
    var local_200: i32;
    var local_201: i32;
    var local_202: i32;
    var local_203: i32;
    var local_204: vec4<f32>;
    var local_205: vec4<f32>;
    var local_206: vec4<f32>;
    var local_207: vec4<f32>;
    var local_208: vec4<f32>;
    var local_209: vec4<f32>;
    var local_210: vec4<f32>;
    var local_211: vec4<f32>;
    var _S115_: vec4<f32>;
    var local_212: f32;
    var local_213: f32;
    var local_214: f32;
    var local_215: f32;
    var local_216: f32;
    var local_217: f32;
    var local_218: vec4<f32>;
    var local_219: f32;
    var local_220: vec3<f32>;
    var local_221: f32;
    var local_222: f32;
    var local_223: f32;
    var local_224: f32;
    var local_225: f32;
    var local_226: f32;
    var local_227: f32;
    var local_228: vec2<f32>;
    var local_229: vec2<f32>;
    var local_230: f32;
    var local_231: f32;
    var local_232: f32;
    var local_233: f32;
    var local_234: f32;
    var local_235: f32;
    var local_236: f32;
    var local_237: f32;
    var local_238: f32;
    var local_239: f32;
    var local_240: f32;
    var local_241: f32;
    var local_242: f32;
    var local_243: f32;
    var local_244: f32;
    var local_245: f32;
    var local_246: f32;
    var local_247: f32;
    var local_248: bool;
    var local_249: vec4<f32>;
    var local_250: vec2<f32>;
    var local_251: f32;
    var local_252: u32;
    var local_253: f32;
    var local_254: f32;
    var local_255: vec2<f32>;
    var local_256: vec4<f32>;
    var local_257: f32;
    var local_258: vec2<f32>;
    var local_259: vec2<f32>;
    var local_260: f32;
    var local_261: f32;
    var local_262: f32;
    var local_263: f32;
    var local_264: f32;
    var local_265: f32;
    var local_266: f32;
    var local_267: f32;
    var local_268: f32;
    var local_269: f32;
    var local_270: f32;
    var local_271: f32;
    var local_272: f32;
    var local_273: f32;
    var local_274: f32;
    var local_275: f32;
    var local_276: f32;
    var local_277: f32;
    var local_278: bool;
    var local_279: vec4<f32>;
    var local_280: vec2<f32>;
    var local_281: f32;
    var local_282: u32;
    var local_283: f32;
    var local_284: f32;
    var local_285: vec2<f32>;
    var local_286: vec4<f32>;
    var local_287: i32;
    var local_288: f32;
    var local_289: f32;
    var local_290: bool;
    var local_291: i32;
    var local_292: vec2<i32>;
    var local_293: i32;
    var local_294: i32;
    var local_295: vec2<u32>;
    var local_296: bool;
    var local_297: f32;
    var local_298: f32;
    var local_299: vec2<f32>;
    var local_300: vec2<f32>;
    var local_301: vec2<i32>;
    var local_302: i32;
    var local_303: f32;
    var local_304: f32;
    var local_305: bool;
    var local_306: vec2<i32>;
    var local_307: i32;
    var local_308: vec2<u32>;
    var local_309: f32;
    var local_310: f32;
    var local_311: vec2<f32>;
    var local_312: vec2<f32>;
    var local_313: vec2<i32>;
    var local_314: i32;
    var local_315: f32;
    var local_316: i32;
    var local_317: f32;
    var local_318: i32;
    var local_319: f32;
    var local_320: i32;
    var local_321: vec2<i32>;
    var local_322: vec4<f32>;
    var local_323: i32;
    var local_324: f32;
    var local_325: u32;
    var local_326: vec4<u32>;
    var local_327: f32;
    var local_328: vec2<i32>;
    var local_329: vec4<f32>;
    var local_330: i32;
    var local_331: f32;
    var local_332: u32;
    var local_333: vec4<u32>;
    var local_334: f32;
    var local_335: vec2<i32>;
    var local_336: vec4<f32>;
    var local_337: i32;
    var local_338: f32;
    var local_339: u32;
    var local_340: vec4<u32>;
    var local_341: f32;
    var local_342: vec2<i32>;
    var local_343: vec4<f32>;
    var local_344: i32;
    var local_345: f32;
    var local_346: u32;
    var local_347: vec4<u32>;
    var local_348: f32;
    var local_349: f32;
    var local_350: f32;
    var local_351: array<vec4<f32>, 4>;
    var local_352: f32;
    var local_353: i32;
    var local_354: f32;
    var local_355: f32;
    var local_356: array<vec4<f32>, 4>;
    var local_357: f32;
    var local_358: i32;
    var local_359: f32;
    var local_360: i32;
    var local_361: i32;
    var local_362: i32;
    var local_363: bool;
    var local_364: array<vec4<f32>, 4>;
    var local_365: f32;
    var local_366: array<vec4<f32>, 4>;
    var local_367: i32;
    var local_368: f32;
    var local_369: array<vec4<f32>, 4>;
    var local_370: f32;
    var local_371: i32;
    var local_372: f32;
    var local_373: i32;
    var local_374: f32;
    var local_375: f32;
    var local_376: f32;
    var local_377: f32;
    var local_378: vec2<i32>;
    var local_379: vec4<f32>;
    var local_380: i32;
    var local_381: f32;
    var local_382: u32;
    var local_383: vec4<u32>;
    var local_384: f32;
    var local_385: vec2<i32>;
    var local_386: vec4<f32>;
    var local_387: i32;
    var local_388: f32;
    var local_389: u32;
    var local_390: vec4<u32>;
    var local_391: f32;
    var local_392: vec2<i32>;
    var local_393: vec4<f32>;
    var local_394: i32;
    var local_395: f32;
    var local_396: u32;
    var local_397: vec4<u32>;
    var local_398: f32;
    var local_399: vec2<i32>;
    var local_400: vec4<f32>;
    var local_401: i32;
    var local_402: f32;
    var local_403: u32;
    var local_404: vec4<u32>;
    var local_405: f32;
    var local_406: f32;
    var local_407: f32;
    var local_408: array<vec4<f32>, 4>;
    var local_409: f32;
    var local_410: i32;
    var local_411: f32;
    var local_412: f32;
    var local_413: array<vec4<f32>, 4>;
    var local_414: f32;
    var local_415: i32;
    var local_416: f32;
    var local_417: i32;
    var local_418: i32;
    var local_419: i32;
    var local_420: bool;
    var local_421: array<vec4<f32>, 4>;
    var local_422: f32;
    var local_423: array<vec4<f32>, 4>;
    var local_424: i32;
    var local_425: f32;
    var local_426: array<vec4<f32>, 4>;
    var local_427: f32;
    var local_428: i32;
    var local_429: f32;
    var local_430: i32;
    var local_431: f32;
    var local_432: f32;
    var local_433: f32;
    var local_434: f32;
    var local_435: vec2<i32>;
    var local_436: vec4<f32>;
    var local_437: i32;
    var local_438: f32;
    var local_439: f32;
    var local_440: i32;
    var local_441: i32;
    var local_442: i32;
    var local_443: i32;
    var local_444: bool;
    var local_445: i32;
    var local_446: f32;
    var local_447: i32;
    var local_448: f32;
    var local_449: f32;
    var local_450: bool;
    var local_451: f32;
    var local_452: vec2<i32>;
    var local_453: vec4<f32>;
    var local_454: i32;
    var local_455: f32;
    var local_456: vec2<i32>;
    var local_457: vec4<f32>;
    var local_458: i32;
    var local_459: f32;
    var local_460: vec2<i32>;
    var local_461: vec4<f32>;
    var local_462: i32;
    var local_463: f32;
    var local_464: vec2<i32>;
    var local_465: vec4<f32>;
    var local_466: i32;
    var local_467: f32;
    var local_468: vec2<i32>;
    var local_469: vec4<f32>;
    var local_470: i32;
    var local_471: f32;
    var local_472: vec2<i32>;
    var local_473: vec4<f32>;
    var local_474: i32;
    var local_475: f32;
    var local_476: vec2<i32>;
    var local_477: vec4<f32>;
    var local_478: i32;
    var local_479: f32;
    var local_480: vec2<i32>;
    var local_481: vec4<f32>;
    var local_482: i32;
    var local_483: f32;
    var local_484: vec2<i32>;
    var local_485: vec4<f32>;
    var local_486: i32;
    var local_487: f32;
    var local_488: vec2<i32>;
    var local_489: vec4<f32>;
    var local_490: i32;
    var local_491: f32;
    var local_492: vec2<i32>;
    var local_493: vec4<f32>;
    var local_494: i32;
    var local_495: f32;
    var local_496: vec2<i32>;
    var local_497: vec4<f32>;
    var local_498: i32;
    var local_499: f32;
    var local_500: vec2<i32>;
    var local_501: vec4<f32>;
    var local_502: i32;
    var local_503: f32;
    var local_504: bool = false;
    var local_505: bool;
    var local_506: bool;
    var local_507: bool;
    var local_508: i32;
    var local_509: bool;
    var local_510: bool;
    var local_511: i32;
    var local_512: i32;
    var local_513: f32;
    var local_514: array<f32, 32>;
    var local_515: array<f32, 32>;
    var local_516: array<i32, 32>;
    var local_517: array<i32, 32>;
    var local_518: array<bool, 32>;
    var local_519: array<bool, 32>;
    var local_520: array<bool, 32>;
    var local_521: array<bool, 32>;
    var local_522: array<i32, 32>;
    var local_523: array<i32, 32>;
    var local_524: array<bool, 32>;
    var local_525: bool;
    var local_526: bool;
    var local_527: bool;
    var local_528: bool;
    var local_529: bool;
    var local_530: i32;
    var local_531: f32;
    var local_532: f32;
    var local_533: i32;
    var local_534: f32;
    var local_535: f32;
    var local_536: f32;
    var local_537: i32;
    var local_538: i32;
    var local_539: f32;
    var local_540: f32;
    var local_541: i32;
    var local_542: bool;
    var local_543: bool;
    var local_544: array<i32, 32>;
    var local_545: i32;
    var local_546: array<i32, 32>;
    var local_547: f32;
    var local_548: f32;
    var local_549: bool;
    var local_550: array<f32, 32>;
    var local_551: bool;
    var local_552: f32;
    var local_553: f32;
    var local_554: f32;
    var local_555: f32;
    var local_556: f32;
    var local_557: f32;
    var local_558: i32;
    var local_559: f32;
    var local_560: f32;
    var local_561: f32;
    var local_562: f32;
    var local_563: f32;
    var local_564: f32;
    var local_565: f32;
    var local_566: f32;
    var local_567: f32;
    var local_568: f32;
    var local_569: f32;
    var local_570: i32;
    var local_571: f32;
    var local_572: bool;
    var local_573: i32;
    var local_574: array<bool, 32>;
    var local_575: array<bool, 32>;
    var local_576: i32;
    var local_577: f32;
    var local_578: f32;
    var local_579: i32;
    var local_580: i32;
    var local_581: i32;
    var local_582: i32;
    var local_583: bool;
    var local_584: i32;
    var local_585: f32;
    var local_586: i32;
    var local_587: f32;
    var local_588: f32;
    var local_589: bool;
    var local_590: f32;
    var local_591: vec2<i32>;
    var local_592: vec4<f32>;
    var local_593: i32;
    var local_594: f32;
    var local_595: vec2<i32>;
    var local_596: vec4<f32>;
    var local_597: i32;
    var local_598: f32;
    var local_599: vec2<i32>;
    var local_600: vec4<f32>;
    var local_601: i32;
    var local_602: f32;
    var local_603: vec2<i32>;
    var local_604: vec4<f32>;
    var local_605: i32;
    var local_606: f32;
    var local_607: vec2<i32>;
    var local_608: vec4<f32>;
    var local_609: i32;
    var local_610: f32;
    var local_611: vec2<i32>;
    var local_612: vec4<f32>;
    var local_613: i32;
    var local_614: f32;
    var local_615: vec2<i32>;
    var local_616: vec4<f32>;
    var local_617: i32;
    var local_618: f32;
    var local_619: vec2<i32>;
    var local_620: vec4<f32>;
    var local_621: i32;
    var local_622: f32;
    var local_623: vec2<i32>;
    var local_624: vec4<f32>;
    var local_625: i32;
    var local_626: f32;
    var local_627: vec2<i32>;
    var local_628: vec4<f32>;
    var local_629: i32;
    var local_630: f32;
    var local_631: vec2<i32>;
    var local_632: vec4<f32>;
    var local_633: i32;
    var local_634: f32;
    var local_635: vec2<i32>;
    var local_636: vec4<f32>;
    var local_637: i32;
    var local_638: f32;
    var local_639: vec2<i32>;
    var local_640: vec4<f32>;
    var local_641: i32;
    var local_642: f32;
    var local_643: bool = false;
    var local_644: bool;
    var local_645: bool;
    var local_646: bool;
    var local_647: i32;
    var local_648: bool;
    var local_649: bool;
    var local_650: i32;
    var local_651: i32;
    var local_652: f32;
    var local_653: array<f32, 32>;
    var local_654: array<f32, 32>;
    var local_655: array<i32, 32>;
    var local_656: array<i32, 32>;
    var local_657: array<bool, 32>;
    var local_658: array<bool, 32>;
    var local_659: array<bool, 32>;
    var local_660: array<bool, 32>;
    var local_661: array<i32, 32>;
    var local_662: array<i32, 32>;
    var local_663: array<bool, 32>;
    var local_664: bool;
    var local_665: bool;
    var local_666: bool;
    var local_667: bool;
    var local_668: bool;
    var local_669: i32;
    var local_670: f32;
    var local_671: f32;
    var local_672: i32;
    var local_673: f32;
    var local_674: f32;
    var local_675: f32;
    var local_676: i32;
    var local_677: i32;
    var local_678: f32;
    var local_679: f32;
    var local_680: i32;
    var local_681: bool;
    var local_682: bool;
    var local_683: array<i32, 32>;
    var local_684: i32;
    var local_685: array<i32, 32>;
    var local_686: f32;
    var local_687: f32;
    var local_688: bool;
    var local_689: array<f32, 32>;
    var local_690: bool;
    var local_691: f32;
    var local_692: f32;
    var local_693: f32;
    var local_694: f32;
    var local_695: f32;
    var local_696: f32;
    var local_697: i32;
    var local_698: f32;
    var local_699: f32;
    var local_700: f32;
    var local_701: f32;
    var local_702: f32;
    var local_703: f32;
    var local_704: f32;
    var local_705: f32;
    var local_706: f32;
    var local_707: f32;
    var local_708: f32;
    var local_709: i32;
    var local_710: f32;
    var local_711: bool;
    var local_712: i32;
    var local_713: array<bool, 32>;
    var local_714: array<bool, 32>;
    var local_715: i32;
    var local_716: f32;
    var local_717: vec2<i32>;
    var local_718: vec4<f32>;
    var local_719: i32;
    var local_720: f32;
    var local_721: bool;
    var local_722: u32;
    var local_723: u32;
    var local_724: bool;
    var local_725: vec2<i32>;
    var local_726: vec4<f32>;
    var local_727: i32;
    var local_728: f32;
    var local_729: vec2<i32>;
    var local_730: vec4<f32>;
    var local_731: i32;
    var local_732: f32;
    var local_733: i32;
    var local_734: vec4<u32>;
    var local_735: i32;
    var local_736: i32;
    var local_737: vec4<u32>;
    var local_738: i32;
    var local_739: vec4<u32>;
    var local_740: i32;
    var local_741: i32;
    var local_742: vec4<u32>;
    var local_743: bool;
    var local_744: bool;
    var local_745: vec2<i32>;
    var local_746: vec4<f32>;
    var local_747: i32;
    var local_748: f32;
    var local_749: bool;
    var local_750: bool;
    var local_751: vec2<i32>;
    var local_752: vec4<f32>;
    var local_753: i32;
    var local_754: f32;
    var local_755: bool;
    var local_756: bool;
    var local_757: vec2<i32>;
    var local_758: vec4<f32>;
    var local_759: i32;
    var local_760: f32;
    var local_761: vec2<i32>;
    var local_762: vec4<f32>;
    var local_763: vec2<i32>;
    var local_764: i32;
    var local_765: i32;
    var local_766: i32;
    var local_767: vec2<f32>;
    var local_768: vec2<f32>;
    var local_769: f32;
    var local_770: f32;
    var local_771: i32;
    var local_772: i32;
    var local_773: f32;
    var local_774: i32;
    var local_775: i32;
    var local_776: f32;
    var local_777: i32;
    var local_778: bool;
    var local_779: i32;
    var local_780: f32;
    var local_781: i32;
    var local_782: vec4<u32>;
    var local_783: i32;
    var local_784: vec4<u32>;
    var local_785: i32;
    var local_786: f32;
    var local_787: f32;
    var local_788: bool;
    var local_789: bool;
    var local_790: f32;
    var local_791: f32;
    var local_792: vec4<u32>;
    var local_793: vec3<u32>;
    var local_794: bool;
    var local_795: i32;
    var local_796: i32;
    var local_797: i32;
    var local_798: f32;
    var local_799: f32;
    var local_800: f32;
    var local_801: i32;
    var local_802: array<f32, 32>;
    var local_803: array<f32, 32>;
    var local_804: i32;
    var local_805: array<f32, 32>;
    var local_806: array<f32, 32>;
    var local_807: f32;
    var local_808: f32;
    var local_809: i32;
    var local_810: i32;
    var local_811: i32;
    var local_812: f32;
    var local_813: f32;
    var local_814: f32;
    var local_815: i32;
    var local_816: array<f32, 32>;
    var local_817: array<f32, 32>;
    var local_818: i32;
    var local_819: array<f32, 32>;
    var local_820: array<f32, 32>;
    var local_821: f32;
    var local_822: f32;
    var local_823: i32;
    var local_824: vec4<u32>;
    var local_825: i32;
    var local_826: f32;
    var local_827: f32;
    var local_828: f32;
    var local_829: i32;
    var local_830: vec4<u32>;
    var local_831: i32;
    var local_832: f32;
    var local_833: f32;
    var local_834: f32;
    var local_835: f32;
    var local_836: vec2<f32>;
    var local_837: vec2<f32>;
    var local_838: vec2<i32>;
    var local_839: i32;
    var local_840: vec4<f32>;
    var local_841: vec4<f32>;
    var local_842: vec4<f32>;

    let _e941 = v_ah_x_targets0_0_1;
    local_207 = _e941;
    let _e942 = v_ah_x_targets1_0_1;
    local_206 = _e942;
    let _e943 = v_ah_x_targets2_0_1;
    local_205 = _e943;
    let _e944 = v_ah_x_targets3_0_1;
    local_204 = _e944;
    let _e945 = v_ah_y_targets0_0_1;
    local_211 = _e945;
    let _e946 = v_ah_y_targets1_0_1;
    local_210 = _e946;
    let _e947 = v_ah_y_targets2_0_1;
    local_209 = _e947;
    let _e948 = v_ah_y_targets3_0_1;
    local_208 = _e948;
    let _e949 = v_info_0_1;
    let _e952 = vec3<i32>(_e949.x, _e949.y, 0i);
    let _e955 = textureLoad(u_layer_tex_0_image, _e952.xy, _e952.z);
    let _e956 = v_info_0_1;
    let _e957 = textureDimensions(u_layer_tex_0_image, 0i);
    let _e960 = local_761;
    let _e963 = vec2<i32>(vec2<i32>(_e957).x, _e960.y);
    let _e964 = textureDimensions(u_layer_tex_0_image, 0i);
    let _e969 = vec2<i32>(_e963.x, vec2<i32>(_e964).y);
    local_761 = _e969;
    let _e975 = (((_e956.y * _e969.x) + _e956.x) + 1i);
    let _e984 = vec2<i32>((_e975 - (i32(floor((f32(_e975) / f32(_e969.x)))) * _e969.x)), (_e975 / _e969.x));
    let _e987 = vec3<i32>(_e984.x, _e984.y, 0i);
    let _e990 = textureLoad(u_layer_tex_0_image, _e987.xy, _e987.z);
    local_762 = _e990;
    local_763 = vec2<i32>(i32((_e955.x + 0.5f)), i32((_e955.y + 0.5f)));
    let _e999 = bitcast<i32>(_e955.z);
    local_764 = (_e999 & 65535i);
    local_765 = ((_e999 >> bitcast<u32>(16i)) & 65535i);
    let _e1005 = PushConstants_0_.layer_base_0_;
    let _e1007 = v_texcoord_layer_0_1[2u];
    local_766 = (_e1005 + i32(_e1007));
    let _e1010 = v_texcoord_layer_0_1;
    let _e1011 = _e1010.xy;
    local_767 = _e1011;
    let _e1012 = fwidth(_e1011);
    local_768 = _e1012;
    local_769 = (1f / _e1012.x);
    local_770 = (1f / _e1012.y);
    local_771 = 0i;
    local_772 = 0i;
    let _e1017 = (0i + 10i);
    let _e1020 = v_info_0_1;
    let _e1021 = textureDimensions(u_layer_tex_0_image, 0i);
    let _e1024 = local_757;
    let _e1027 = vec2<i32>(vec2<i32>(_e1021).x, _e1024.y);
    let _e1028 = textureDimensions(u_layer_tex_0_image, 0i);
    let _e1033 = vec2<i32>(_e1027.x, vec2<i32>(_e1028).y);
    local_757 = _e1033;
    let _e1039 = (((_e1020.y * _e1033.x) + _e1020.x) + (_e1017 >> bitcast<u32>(2i)));
    let _e1048 = vec2<i32>((_e1039 - (i32(floor((f32(_e1039) / f32(_e1033.x)))) * _e1033.x)), (_e1039 / _e1033.x));
    let _e1051 = vec3<i32>(_e1048.x, _e1048.y, 0i);
    let _e1054 = textureLoad(u_layer_tex_0_image, _e1051.xy, _e1051.z);
    local_758 = _e1054;
    let _e1055 = (_e1017 & 3i);
    local_759 = _e1055;
    if (_e1055 == 0i) {
        let _e1057 = local_758;
        local_760 = _e1057.x;
    } else {
        let _e1059 = local_759;
        if (_e1059 == 1i) {
            let _e1061 = local_758;
            local_760 = _e1061.y;
        } else {
            let _e1063 = local_759;
            if (_e1063 == 2i) {
                let _e1065 = local_758;
                local_760 = _e1065.z;
            } else {
                let _e1067 = local_758;
                local_760 = _e1067.w;
            }
        }
    }
    let _e1069 = local_760;
    local_773 = _e1069;
    switch bitcast<i32>(0u) {
        default: {
            let _e1071 = local_773;
            if !((abs(_e1071) <= 340282300000000000000000000000000000000f)) {
                local_756 = true;
            } else {
                let _e1075 = local_773;
                local_756 = (_e1075 < 0f);
            }
            let _e1077 = local_756;
            if _e1077 {
                local_756 = true;
            } else {
                let _e1078 = local_773;
                local_756 = (_e1078 > 32f);
            }
            let _e1080 = local_756;
            if _e1080 {
                local_756 = true;
            } else {
                let _e1081 = local_773;
                local_756 = (floor(_e1081) != _e1081);
            }
            let _e1084 = local_756;
            if _e1084 {
                local_774 = 0i;
                local_755 = false;
                break;
            }
            let _e1085 = local_773;
            local_774 = i32(_e1085);
            local_755 = true;
            break;
        }
    }
    let _e1087 = local_755;
    let _e1088 = local_774;
    local_771 = _e1088;
    local_775 = (12i + (2i * _e1088));
    if _e1087 {
        let _e1091 = local_775;
        let _e1092 = (_e1091 + 0i);
        let _e1095 = v_info_0_1;
        let _e1096 = textureDimensions(u_layer_tex_0_image, 0i);
        let _e1099 = local_751;
        let _e1102 = vec2<i32>(vec2<i32>(_e1096).x, _e1099.y);
        let _e1103 = textureDimensions(u_layer_tex_0_image, 0i);
        let _e1108 = vec2<i32>(_e1102.x, vec2<i32>(_e1103).y);
        local_751 = _e1108;
        let _e1114 = (((_e1095.y * _e1108.x) + _e1095.x) + (_e1092 >> bitcast<u32>(2i)));
        let _e1123 = vec2<i32>((_e1114 - (i32(floor((f32(_e1114) / f32(_e1108.x)))) * _e1108.x)), (_e1114 / _e1108.x));
        let _e1126 = vec3<i32>(_e1123.x, _e1123.y, 0i);
        let _e1129 = textureLoad(u_layer_tex_0_image, _e1126.xy, _e1126.z);
        local_752 = _e1129;
        let _e1130 = (_e1092 & 3i);
        local_753 = _e1130;
        if (_e1130 == 0i) {
            let _e1132 = local_752;
            local_754 = _e1132.x;
        } else {
            let _e1134 = local_753;
            if (_e1134 == 1i) {
                let _e1136 = local_752;
                local_754 = _e1136.y;
            } else {
                let _e1138 = local_753;
                if (_e1138 == 2i) {
                    let _e1140 = local_752;
                    local_754 = _e1140.z;
                } else {
                    let _e1142 = local_752;
                    local_754 = _e1142.w;
                }
            }
        }
        let _e1144 = local_754;
        local_776 = _e1144;
        switch bitcast<i32>(0u) {
            default: {
                let _e1146 = local_776;
                if !((abs(_e1146) <= 340282300000000000000000000000000000000f)) {
                    local_750 = true;
                } else {
                    let _e1150 = local_776;
                    local_750 = (_e1150 < 0f);
                }
                let _e1152 = local_750;
                if _e1152 {
                    local_750 = true;
                } else {
                    let _e1153 = local_776;
                    local_750 = (_e1153 > 32f);
                }
                let _e1155 = local_750;
                if _e1155 {
                    local_750 = true;
                } else {
                    let _e1156 = local_776;
                    local_750 = (floor(_e1156) != _e1156);
                }
                let _e1159 = local_750;
                if _e1159 {
                    local_777 = 0i;
                    local_749 = false;
                    break;
                }
                let _e1160 = local_776;
                local_777 = i32(_e1160);
                local_749 = true;
                break;
            }
        }
        let _e1162 = local_749;
        let _e1163 = local_777;
        local_772 = _e1163;
        local_778 = _e1162;
    } else {
        local_778 = false;
    }
    let _e1164 = local_775;
    let _e1166 = local_772;
    local_779 = ((_e1164 + 1i) + (4i * _e1166));
    let _e1169 = local_778;
    if _e1169 {
        let _e1170 = local_779;
        let _e1171 = (_e1170 + 0i);
        let _e1174 = v_info_0_1;
        let _e1175 = textureDimensions(u_layer_tex_0_image, 0i);
        let _e1178 = local_745;
        let _e1181 = vec2<i32>(vec2<i32>(_e1175).x, _e1178.y);
        let _e1182 = textureDimensions(u_layer_tex_0_image, 0i);
        let _e1187 = vec2<i32>(_e1181.x, vec2<i32>(_e1182).y);
        local_745 = _e1187;
        let _e1193 = (((_e1174.y * _e1187.x) + _e1174.x) + (_e1171 >> bitcast<u32>(2i)));
        let _e1202 = vec2<i32>((_e1193 - (i32(floor((f32(_e1193) / f32(_e1187.x)))) * _e1187.x)), (_e1193 / _e1187.x));
        let _e1205 = vec3<i32>(_e1202.x, _e1202.y, 0i);
        let _e1208 = textureLoad(u_layer_tex_0_image, _e1205.xy, _e1205.z);
        local_746 = _e1208;
        let _e1209 = (_e1171 & 3i);
        local_747 = _e1209;
        if (_e1209 == 0i) {
            let _e1211 = local_746;
            local_748 = _e1211.x;
        } else {
            let _e1213 = local_747;
            if (_e1213 == 1i) {
                let _e1215 = local_746;
                local_748 = _e1215.y;
            } else {
                let _e1217 = local_747;
                if (_e1217 == 2i) {
                    let _e1219 = local_746;
                    local_748 = _e1219.z;
                } else {
                    let _e1221 = local_746;
                    local_748 = _e1221.w;
                }
            }
        }
        let _e1223 = local_748;
        local_780 = _e1223;
        switch bitcast<i32>(0u) {
            default: {
                let _e1225 = local_780;
                if !((abs(_e1225) <= 340282300000000000000000000000000000000f)) {
                    local_744 = true;
                } else {
                    let _e1229 = local_780;
                    local_744 = (_e1229 < 0f);
                }
                let _e1231 = local_744;
                if _e1231 {
                    local_744 = true;
                } else {
                    let _e1232 = local_780;
                    local_744 = (_e1232 > 32f);
                }
                let _e1234 = local_744;
                if _e1234 {
                    local_744 = true;
                } else {
                    let _e1235 = local_780;
                    local_744 = (floor(_e1235) != _e1235);
                }
                let _e1238 = local_744;
                if _e1238 {
                    local_743 = false;
                    break;
                }
                local_743 = true;
                break;
            }
        }
        let _e1239 = local_743;
        local_778 = _e1239;
    } else {
        local_778 = false;
    }
    let _e1240 = local_778;
    if _e1240 {
        let _e1241 = v_ah_x_sources_0_1;
        local_782 = _e1241;
        switch bitcast<i32>(0u) {
            default: {
                let _e1243 = local_782;
                local_739 = _e1243;
                let _e1247 = local_739[(0i >> bitcast<u32>(2i))];
                if (((_e1247 >> bitcast<u32>(bitcast<u32>(((0i & 3i) * 8i)))) & 255u) == 254u) {
                    local_738 = -1i;
                    break;
                }
                local_740 = 0i;
                local_741 = 0i;
                loop {
                    let _e1255 = local_740;
                    if (_e1255 < 16i) {
                    } else {
                        break;
                    }
                    let _e1257 = local_782;
                    local_742 = _e1257;
                    let _e1258 = local_740;
                    let _e1262 = local_742[(_e1258 >> bitcast<u32>(2i))];
                    if (((_e1262 >> bitcast<u32>(bitcast<u32>(((_e1258 & 3i) * 8i)))) & 255u) == 255u) {
                        break;
                    }
                    let _e1270 = local_741;
                    let _e1272 = local_740;
                    local_740 = (_e1272 + 1i);
                    local_741 = (_e1270 + 1i);
                    continue;
                }
                let _e1274 = local_741;
                local_738 = _e1274;
                break;
            }
        }
        let _e1275 = local_738;
        local_781 = _e1275;
    } else {
        local_781 = 0i;
    }
    let _e1276 = local_781;
    local_783 = _e1276;
    let _e1277 = local_778;
    if _e1277 {
        let _e1278 = v_ah_y_sources_0_1;
        local_784 = _e1278;
        switch bitcast<i32>(0u) {
            default: {
                let _e1280 = local_784;
                local_734 = _e1280;
                let _e1284 = local_734[(0i >> bitcast<u32>(2i))];
                if (((_e1284 >> bitcast<u32>(bitcast<u32>(((0i & 3i) * 8i)))) & 255u) == 254u) {
                    local_733 = -1i;
                    break;
                }
                local_735 = 0i;
                local_736 = 0i;
                loop {
                    let _e1292 = local_735;
                    if (_e1292 < 16i) {
                    } else {
                        break;
                    }
                    let _e1294 = local_784;
                    local_737 = _e1294;
                    let _e1295 = local_735;
                    let _e1299 = local_737[(_e1295 >> bitcast<u32>(2i))];
                    if (((_e1299 >> bitcast<u32>(bitcast<u32>(((_e1295 & 3i) * 8i)))) & 255u) == 255u) {
                        break;
                    }
                    let _e1307 = local_736;
                    let _e1309 = local_735;
                    local_735 = (_e1309 + 1i);
                    local_736 = (_e1307 + 1i);
                    continue;
                }
                let _e1311 = local_736;
                local_733 = _e1311;
                break;
            }
        }
        let _e1312 = local_733;
        local_781 = _e1312;
    } else {
        local_781 = 0i;
    }
    let _e1313 = local_781;
    local_785 = _e1313;
    local_786 = 1f;
    local_787 = 1f;
    let _e1314 = local_783;
    local_788 = (_e1314 < 0i);
    local_789 = (_e1313 < 0i);
    let _e1317 = local_778;
    if _e1317 {
        let _e1318 = local_788;
        if _e1318 {
            local_778 = true;
        } else {
            let _e1319 = local_789;
            local_778 = _e1319;
        }
    } else {
        local_778 = false;
    }
    let _e1320 = local_778;
    if _e1320 {
        let _e1321 = (0i + 8i);
        let _e1324 = v_info_0_1;
        let _e1325 = textureDimensions(u_layer_tex_0_image, 0i);
        let _e1328 = local_729;
        let _e1331 = vec2<i32>(vec2<i32>(_e1325).x, _e1328.y);
        let _e1332 = textureDimensions(u_layer_tex_0_image, 0i);
        let _e1337 = vec2<i32>(_e1331.x, vec2<i32>(_e1332).y);
        local_729 = _e1337;
        let _e1343 = (((_e1324.y * _e1337.x) + _e1324.x) + (_e1321 >> bitcast<u32>(2i)));
        let _e1352 = vec2<i32>((_e1343 - (i32(floor((f32(_e1343) / f32(_e1337.x)))) * _e1337.x)), (_e1343 / _e1337.x));
        let _e1355 = vec3<i32>(_e1352.x, _e1352.y, 0i);
        let _e1358 = textureLoad(u_layer_tex_0_image, _e1355.xy, _e1355.z);
        local_730 = _e1358;
        let _e1359 = (_e1321 & 3i);
        local_731 = _e1359;
        if (_e1359 == 0i) {
            let _e1361 = local_730;
            local_732 = _e1361.x;
        } else {
            let _e1363 = local_731;
            if (_e1363 == 1i) {
                let _e1365 = local_730;
                local_732 = _e1365.y;
            } else {
                let _e1367 = local_731;
                if (_e1367 == 2i) {
                    let _e1369 = local_730;
                    local_732 = _e1369.z;
                } else {
                    let _e1371 = local_730;
                    local_732 = _e1371.w;
                }
            }
        }
        let _e1373 = local_732;
        local_790 = _e1373;
        let _e1374 = (0i + 9i);
        let _e1377 = v_info_0_1;
        let _e1378 = textureDimensions(u_layer_tex_0_image, 0i);
        let _e1381 = local_725;
        let _e1384 = vec2<i32>(vec2<i32>(_e1378).x, _e1381.y);
        let _e1385 = textureDimensions(u_layer_tex_0_image, 0i);
        let _e1390 = vec2<i32>(_e1384.x, vec2<i32>(_e1385).y);
        local_725 = _e1390;
        let _e1396 = (((_e1377.y * _e1390.x) + _e1377.x) + (_e1374 >> bitcast<u32>(2i)));
        let _e1405 = vec2<i32>((_e1396 - (i32(floor((f32(_e1396) / f32(_e1390.x)))) * _e1390.x)), (_e1396 / _e1390.x));
        let _e1408 = vec3<i32>(_e1405.x, _e1405.y, 0i);
        let _e1411 = textureLoad(u_layer_tex_0_image, _e1408.xy, _e1408.z);
        local_726 = _e1411;
        let _e1412 = (_e1374 & 3i);
        local_727 = _e1412;
        if (_e1412 == 0i) {
            let _e1414 = local_726;
            local_728 = _e1414.x;
        } else {
            let _e1416 = local_727;
            if (_e1416 == 1i) {
                let _e1418 = local_726;
                local_728 = _e1418.y;
            } else {
                let _e1420 = local_727;
                if (_e1420 == 2i) {
                    let _e1422 = local_726;
                    local_728 = _e1422.z;
                } else {
                    let _e1424 = local_726;
                    local_728 = _e1424.w;
                }
            }
        }
        let _e1426 = local_728;
        local_791 = _e1426;
        let _e1427 = v_policy0_0_1;
        local_792 = _e1427;
        let _e1428 = v_policy1_0_1;
        local_793 = _e1428;
        switch bitcast<i32>(0u) {
            default: {
                let _e1430 = local_792;
                local_722 = _e1430.x;
                local_723 = _e1430.y;
                if ((_e1430.x & 4286578688u) != 0u) {
                    local_724 = true;
                } else {
                    let _e1435 = local_723;
                    local_724 = ((_e1435 & 4294967232u) != 0u);
                }
                let _e1438 = local_724;
                if _e1438 {
                    local_721 = false;
                    break;
                }
                let _e1439 = local_722;
                let _e1441 = bitcast<i32>((_e1439 & 3u));
                local_184 = _e1441;
                local_183 = bitcast<i32>(((_e1439 >> bitcast<u32>(2u)) & 3u));
                local_182 = bitcast<i32>(((_e1439 >> bitcast<u32>(4u)) & 3u));
                local_181 = bitcast<i32>(((_e1439 >> bitcast<u32>(6u)) & 3u));
                local_177 = bitcast<i32>(((_e1439 >> bitcast<u32>(8u)) & 1u));
                local_176 = f32(((_e1439 >> bitcast<u32>(9u)) & 127u));
                local_175 = f32(((_e1439 >> bitcast<u32>(16u)) & 127u));
                let _e1466 = local_723;
                local_180 = bitcast<i32>((_e1466 & 3u));
                local_179 = bitcast<i32>(((_e1466 >> bitcast<u32>(2u)) & 3u));
                local_178 = bitcast<i32>(((_e1466 >> bitcast<u32>(4u)) & 3u));
                if (_e1441 > 1i) {
                    local_724 = true;
                } else {
                    let _e1478 = local_183;
                    local_724 = (_e1478 > 2i);
                }
                let _e1480 = local_724;
                if _e1480 {
                    local_724 = true;
                } else {
                    let _e1481 = local_182;
                    local_724 = (_e1481 > 1i);
                }
                let _e1483 = local_724;
                if _e1483 {
                    local_724 = true;
                } else {
                    let _e1484 = local_181;
                    local_724 = (_e1484 > 1i);
                }
                let _e1486 = local_724;
                if _e1486 {
                    local_724 = true;
                } else {
                    let _e1487 = local_180;
                    local_724 = (_e1487 > 2i);
                }
                let _e1489 = local_724;
                if _e1489 {
                    local_724 = true;
                } else {
                    let _e1490 = local_179;
                    local_724 = (_e1490 > 2i);
                }
                let _e1492 = local_724;
                if _e1492 {
                    local_724 = true;
                } else {
                    let _e1493 = local_178;
                    local_724 = (_e1493 > 1i);
                }
                let _e1495 = local_724;
                if _e1495 {
                    local_721 = false;
                    break;
                }
                let _e1496 = local_792;
                local_174 = bitcast<f32>(_e1496.z);
                local_173 = bitcast<f32>(_e1496.w);
                let _e1501 = local_793;
                local_172 = bitcast<f32>(_e1501.x);
                local_171 = bitcast<f32>(_e1501.y);
                local_170 = bitcast<f32>(_e1501.z);
                let _e1508 = local_183;
                if (_e1508 != 0i) {
                    let _e1510 = local_174;
                    if !((abs(_e1510) <= 340282300000000000000000000000000000000f)) {
                        local_724 = true;
                    } else {
                        let _e1514 = local_174;
                        local_724 = (_e1514 < 0f);
                    }
                } else {
                    local_724 = false;
                }
                let _e1516 = local_724;
                if _e1516 {
                    local_724 = true;
                } else {
                    let _e1517 = local_183;
                    if (_e1517 == 1i) {
                        let _e1519 = local_173;
                        if !((abs(_e1519) <= 340282300000000000000000000000000000000f)) {
                            local_724 = true;
                        } else {
                            let _e1523 = local_173;
                            local_724 = (_e1523 < 0f);
                        }
                    } else {
                        local_724 = false;
                    }
                }
                let _e1525 = local_724;
                if _e1525 {
                    local_724 = true;
                } else {
                    let _e1526 = local_179;
                    if (_e1526 != 0i) {
                        let _e1528 = local_172;
                        if !((abs(_e1528) <= 340282300000000000000000000000000000000f)) {
                            local_724 = true;
                        } else {
                            let _e1532 = local_172;
                            local_724 = (_e1532 < 0f);
                        }
                    } else {
                        local_724 = false;
                    }
                }
                let _e1534 = local_724;
                if _e1534 {
                    local_724 = true;
                } else {
                    let _e1535 = local_179;
                    if (_e1535 == 1i) {
                        let _e1537 = local_171;
                        if !((abs(_e1537) <= 340282300000000000000000000000000000000f)) {
                            local_724 = true;
                        } else {
                            let _e1541 = local_171;
                            local_724 = (_e1541 < 0f);
                        }
                    } else {
                        local_724 = false;
                    }
                }
                let _e1543 = local_724;
                if _e1543 {
                    local_724 = true;
                } else {
                    let _e1544 = local_178;
                    if (_e1544 == 1i) {
                        let _e1546 = local_170;
                        if !((abs(_e1546) <= 340282300000000000000000000000000000000f)) {
                            local_724 = true;
                        } else {
                            let _e1550 = local_170;
                            local_724 = (_e1550 < 0f);
                        }
                    } else {
                        local_724 = false;
                    }
                }
                let _e1552 = local_724;
                if _e1552 {
                    local_724 = true;
                } else {
                    let _e1553 = local_182;
                    if (_e1553 == 1i) {
                        let _e1555 = local_184;
                        local_724 = (_e1555 == 0i);
                    } else {
                        local_724 = false;
                    }
                }
                let _e1557 = local_724;
                if _e1557 {
                    local_724 = true;
                } else {
                    let _e1558 = local_178;
                    if (_e1558 == 1i) {
                        let _e1560 = local_180;
                        local_724 = (_e1560 != 2i);
                    } else {
                        local_724 = false;
                    }
                }
                let _e1562 = local_724;
                if _e1562 {
                    local_721 = false;
                    break;
                }
                local_721 = true;
                break;
            }
        }
        let _e1563 = local_721;
        let _e1564 = local_170;
        let _e1565 = local_171;
        let _e1566 = local_172;
        let _e1567 = local_173;
        let _e1568 = local_174;
        let _e1569 = local_175;
        let _e1570 = local_176;
        let _e1571 = local_177;
        let _e1572 = local_178;
        let _e1573 = local_179;
        let _e1574 = local_180;
        let _e1575 = local_181;
        let _e1576 = local_182;
        let _e1577 = local_183;
        let _e1578 = local_184;
        local_199 = _e1578;
        local_198 = _e1577;
        local_197 = _e1576;
        local_196 = _e1575;
        local_195 = _e1574;
        local_194 = _e1573;
        local_193 = _e1572;
        local_192 = _e1571;
        local_191 = _e1570;
        local_190 = _e1569;
        local_189 = _e1568;
        local_188 = _e1567;
        local_187 = _e1566;
        local_186 = _e1565;
        local_185 = _e1564;
        if _e1563 {
            let _e1579 = local_790;
            local_778 = (abs(_e1579) <= 340282300000000000000000000000000000000f);
        } else {
            local_778 = false;
        }
        let _e1582 = local_778;
        if _e1582 {
            let _e1583 = local_790;
            local_778 = (_e1583 >= 0f);
        } else {
            local_778 = false;
        }
        let _e1585 = local_778;
        if _e1585 {
            let _e1586 = local_791;
            local_778 = (abs(_e1586) <= 340282300000000000000000000000000000000f);
        } else {
            local_778 = false;
        }
        let _e1589 = local_778;
        if _e1589 {
            let _e1590 = local_791;
            local_778 = (_e1590 >= 0f);
        } else {
            local_778 = false;
        }
        let _e1592 = local_778;
        if _e1592 {
            let _e1593 = local_788;
            local_794 = _e1593;
        } else {
            local_794 = false;
        }
        let _e1594 = local_794;
        if _e1594 {
            let _e1595 = (0i + 11i);
            let _e1598 = v_info_0_1;
            let _e1599 = textureDimensions(u_layer_tex_0_image, 0i);
            let _e1602 = local_717;
            let _e1605 = vec2<i32>(vec2<i32>(_e1599).x, _e1602.y);
            let _e1606 = textureDimensions(u_layer_tex_0_image, 0i);
            let _e1611 = vec2<i32>(_e1605.x, vec2<i32>(_e1606).y);
            local_717 = _e1611;
            let _e1617 = (((_e1598.y * _e1611.x) + _e1598.x) + (_e1595 >> bitcast<u32>(2i)));
            let _e1626 = vec2<i32>((_e1617 - (i32(floor((f32(_e1617) / f32(_e1611.x)))) * _e1611.x)), (_e1617 / _e1611.x));
            let _e1629 = vec3<i32>(_e1626.x, _e1626.y, 0i);
            let _e1632 = textureLoad(u_layer_tex_0_image, _e1629.xy, _e1629.z);
            local_718 = _e1632;
            let _e1633 = (_e1595 & 3i);
            local_719 = _e1633;
            if (_e1633 == 0i) {
                let _e1635 = local_718;
                local_720 = _e1635.x;
            } else {
                let _e1637 = local_719;
                if (_e1637 == 1i) {
                    let _e1639 = local_718;
                    local_720 = _e1639.y;
                } else {
                    let _e1641 = local_719;
                    if (_e1641 == 2i) {
                        let _e1643 = local_718;
                        local_720 = _e1643.z;
                    } else {
                        let _e1645 = local_718;
                        local_720 = _e1645.w;
                    }
                }
            }
            let _e1647 = local_720;
            local_795 = 0i;
            let _e1648 = local_775;
            local_796 = _e1648;
            let _e1649 = local_771;
            local_797 = _e1649;
            let _e1650 = local_790;
            local_798 = _e1650;
            local_799 = _e1647;
            let _e1651 = local_769;
            local_800 = _e1651;
            let _e1652 = local_185;
            let _e1653 = local_186;
            let _e1654 = local_187;
            let _e1655 = local_188;
            let _e1656 = local_189;
            let _e1657 = local_190;
            let _e1658 = local_191;
            let _e1659 = local_192;
            let _e1660 = local_193;
            let _e1661 = local_194;
            let _e1662 = local_195;
            let _e1663 = local_196;
            let _e1664 = local_197;
            let _e1665 = local_198;
            let _e1666 = local_199;
            local_105 = _e1666;
            local_104 = _e1665;
            local_103 = _e1664;
            local_102 = _e1663;
            local_101 = _e1662;
            local_100 = _e1661;
            local_99 = _e1660;
            local_98 = _e1659;
            local_97 = _e1658;
            local_96 = _e1657;
            local_95 = _e1656;
            local_94 = _e1655;
            local_93 = _e1654;
            local_92 = _e1653;
            local_91 = _e1652;
            local_643 = false;
            switch bitcast<i32>(0u) {
                default: {
                    local_801 = 0i;
                    let _e1668 = local_800;
                    if !((abs(_e1668) <= 340282300000000000000000000000000000000f)) {
                        local_645 = true;
                    } else {
                        let _e1672 = local_800;
                        local_645 = (_e1672 <= 0f);
                    }
                    let _e1674 = local_645;
                    if _e1674 {
                        local_645 = true;
                    } else {
                        let _e1675 = local_797;
                        local_645 = (_e1675 < 0i);
                    }
                    let _e1677 = local_645;
                    if _e1677 {
                        local_645 = true;
                    } else {
                        let _e1678 = local_797;
                        local_645 = (_e1678 > 32i);
                    }
                    let _e1680 = local_645;
                    if _e1680 {
                        local_645 = true;
                    } else {
                        let _e1681 = local_798;
                        local_645 = !((abs(_e1681) <= 340282300000000000000000000000000000000f));
                    }
                    let _e1685 = local_645;
                    if _e1685 {
                        local_645 = true;
                    } else {
                        let _e1686 = local_798;
                        local_645 = (_e1686 < 0f);
                    }
                    let _e1688 = local_645;
                    if _e1688 {
                        local_643 = true;
                        local_644 = false;
                        break;
                    }
                    let _e1689 = local_795;
                    let _e1690 = (_e1689 == 0i);
                    local_646 = _e1690;
                    if _e1690 {
                        let _e1691 = local_105;
                        local_645 = (_e1691 == 0i);
                    } else {
                        local_645 = false;
                    }
                    let _e1693 = local_645;
                    if _e1693 {
                        let _e1694 = local_104;
                        local_645 = (_e1694 == 0i);
                    } else {
                        local_645 = false;
                    }
                    let _e1696 = local_645;
                    if _e1696 {
                        let _e1697 = local_103;
                        local_645 = (_e1697 == 0i);
                    } else {
                        local_645 = false;
                    }
                    let _e1699 = local_645;
                    if _e1699 {
                        let _e1700 = local_102;
                        local_645 = (_e1700 == 0i);
                    } else {
                        local_645 = false;
                    }
                    let _e1702 = local_645;
                    if _e1702 {
                        local_645 = true;
                    } else {
                        let _e1703 = local_795;
                        if (_e1703 == 1i) {
                            let _e1705 = local_101;
                            local_645 = (_e1705 == 0i);
                        } else {
                            local_645 = false;
                        }
                        let _e1707 = local_645;
                        if _e1707 {
                            let _e1708 = local_100;
                            local_645 = (_e1708 == 0i);
                        } else {
                            local_645 = false;
                        }
                        let _e1710 = local_645;
                        if _e1710 {
                            let _e1711 = local_99;
                            local_645 = (_e1711 == 0i);
                        } else {
                            local_645 = false;
                        }
                    }
                    let _e1713 = local_645;
                    if _e1713 {
                        local_643 = true;
                        local_644 = true;
                        break;
                    }
                    let _e1714 = local_796;
                    let _e1715 = (_e1714 + 0i);
                    let _e1718 = v_info_0_1;
                    let _e1719 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e1722 = local_639;
                    let _e1725 = vec2<i32>(vec2<i32>(_e1719).x, _e1722.y);
                    let _e1726 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e1731 = vec2<i32>(_e1725.x, vec2<i32>(_e1726).y);
                    local_639 = _e1731;
                    let _e1737 = (((_e1718.y * _e1731.x) + _e1718.x) + (_e1715 >> bitcast<u32>(2i)));
                    let _e1746 = vec2<i32>((_e1737 - (i32(floor((f32(_e1737) / f32(_e1731.x)))) * _e1731.x)), (_e1737 / _e1731.x));
                    let _e1749 = vec3<i32>(_e1746.x, _e1746.y, 0i);
                    let _e1752 = textureLoad(u_layer_tex_0_image, _e1749.xy, _e1749.z);
                    local_640 = _e1752;
                    let _e1753 = (_e1715 & 3i);
                    local_641 = _e1753;
                    if (_e1753 == 0i) {
                        let _e1755 = local_640;
                        local_642 = _e1755.x;
                    } else {
                        let _e1757 = local_641;
                        if (_e1757 == 1i) {
                            let _e1759 = local_640;
                            local_642 = _e1759.y;
                        } else {
                            let _e1761 = local_641;
                            if (_e1761 == 2i) {
                                let _e1763 = local_640;
                                local_642 = _e1763.z;
                            } else {
                                let _e1765 = local_640;
                                local_642 = _e1765.w;
                            }
                        }
                    }
                    let _e1767 = local_642;
                    let _e1768 = i32(_e1767);
                    local_647 = _e1768;
                    if (_e1768 <= 0i) {
                        local_645 = true;
                    } else {
                        let _e1770 = local_647;
                        local_645 = (_e1770 > 32i);
                    }
                    let _e1772 = local_645;
                    if _e1772 {
                        let _e1773 = local_647;
                        local_643 = true;
                        local_644 = (_e1773 == 0i);
                        break;
                    }
                    let _e1775 = local_795;
                    let _e1776 = (_e1775 == 1i);
                    local_648 = _e1776;
                    if _e1776 {
                        let _e1777 = local_101;
                        local_645 = (_e1777 == 2i);
                    } else {
                        local_645 = false;
                    }
                    let _e1779 = local_646;
                    if _e1779 {
                        let _e1780 = local_102;
                        local_649 = (_e1780 == 1i);
                    } else {
                        local_649 = false;
                    }
                    let _e1782 = local_649;
                    if _e1782 {
                        let _e1783 = local_799;
                        local_649 = !((abs(_e1783) <= 340282300000000000000000000000000000000f));
                    } else {
                        local_649 = false;
                    }
                    let _e1787 = local_649;
                    if _e1787 {
                        local_643 = true;
                        local_644 = false;
                        break;
                    }
                    local_650 = 0i;
                    loop {
                        let _e1788 = local_650;
                        if (_e1788 < 32i) {
                        } else {
                            break;
                        }
                        let _e1790 = local_650;
                        let _e1791 = local_647;
                        if (_e1790 >= _e1791) {
                            break;
                        }
                        let _e1793 = local_796;
                        let _e1795 = local_650;
                        let _e1797 = ((_e1793 + 1i) + (4i * _e1795));
                        local_651 = _e1797;
                        let _e1798 = (_e1797 + 0i);
                        let _e1801 = v_info_0_1;
                        let _e1802 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1805 = local_635;
                        let _e1808 = vec2<i32>(vec2<i32>(_e1802).x, _e1805.y);
                        let _e1809 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1814 = vec2<i32>(_e1808.x, vec2<i32>(_e1809).y);
                        local_635 = _e1814;
                        let _e1820 = (((_e1801.y * _e1814.x) + _e1801.x) + (_e1798 >> bitcast<u32>(2i)));
                        let _e1829 = vec2<i32>((_e1820 - (i32(floor((f32(_e1820) / f32(_e1814.x)))) * _e1814.x)), (_e1820 / _e1814.x));
                        let _e1832 = vec3<i32>(_e1829.x, _e1829.y, 0i);
                        let _e1835 = textureLoad(u_layer_tex_0_image, _e1832.xy, _e1832.z);
                        local_636 = _e1835;
                        let _e1836 = (_e1798 & 3i);
                        local_637 = _e1836;
                        if (_e1836 == 0i) {
                            let _e1838 = local_636;
                            local_638 = _e1838.x;
                        } else {
                            let _e1840 = local_637;
                            if (_e1840 == 1i) {
                                let _e1842 = local_636;
                                local_638 = _e1842.y;
                            } else {
                                let _e1844 = local_637;
                                if (_e1844 == 2i) {
                                    let _e1846 = local_636;
                                    local_638 = _e1846.z;
                                } else {
                                    let _e1848 = local_636;
                                    local_638 = _e1848.w;
                                }
                            }
                        }
                        let _e1850 = local_638;
                        local_652 = _e1850;
                        let _e1851 = local_650;
                        local_653[_e1851] = _e1850;
                        let _e1853 = local_651;
                        let _e1854 = (_e1853 + 1i);
                        let _e1857 = v_info_0_1;
                        let _e1858 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1861 = local_631;
                        let _e1864 = vec2<i32>(vec2<i32>(_e1858).x, _e1861.y);
                        let _e1865 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1870 = vec2<i32>(_e1864.x, vec2<i32>(_e1865).y);
                        local_631 = _e1870;
                        let _e1876 = (((_e1857.y * _e1870.x) + _e1857.x) + (_e1854 >> bitcast<u32>(2i)));
                        let _e1885 = vec2<i32>((_e1876 - (i32(floor((f32(_e1876) / f32(_e1870.x)))) * _e1870.x)), (_e1876 / _e1870.x));
                        let _e1888 = vec3<i32>(_e1885.x, _e1885.y, 0i);
                        let _e1891 = textureLoad(u_layer_tex_0_image, _e1888.xy, _e1888.z);
                        local_632 = _e1891;
                        let _e1892 = (_e1854 & 3i);
                        local_633 = _e1892;
                        if (_e1892 == 0i) {
                            let _e1894 = local_632;
                            local_634 = _e1894.x;
                        } else {
                            let _e1896 = local_633;
                            if (_e1896 == 1i) {
                                let _e1898 = local_632;
                                local_634 = _e1898.y;
                            } else {
                                let _e1900 = local_633;
                                if (_e1900 == 2i) {
                                    let _e1902 = local_632;
                                    local_634 = _e1902.z;
                                } else {
                                    let _e1904 = local_632;
                                    local_634 = _e1904.w;
                                }
                            }
                        }
                        let _e1906 = local_634;
                        let _e1907 = local_650;
                        local_654[_e1907] = _e1906;
                        let _e1909 = local_651;
                        let _e1910 = (_e1909 + 2i);
                        let _e1913 = v_info_0_1;
                        let _e1914 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1917 = local_627;
                        let _e1920 = vec2<i32>(vec2<i32>(_e1914).x, _e1917.y);
                        let _e1921 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1926 = vec2<i32>(_e1920.x, vec2<i32>(_e1921).y);
                        local_627 = _e1926;
                        let _e1932 = (((_e1913.y * _e1926.x) + _e1913.x) + (_e1910 >> bitcast<u32>(2i)));
                        let _e1941 = vec2<i32>((_e1932 - (i32(floor((f32(_e1932) / f32(_e1926.x)))) * _e1926.x)), (_e1932 / _e1926.x));
                        let _e1944 = vec3<i32>(_e1941.x, _e1941.y, 0i);
                        let _e1947 = textureLoad(u_layer_tex_0_image, _e1944.xy, _e1944.z);
                        local_628 = _e1947;
                        let _e1948 = (_e1910 & 3i);
                        local_629 = _e1948;
                        if (_e1948 == 0i) {
                            let _e1950 = local_628;
                            local_630 = _e1950.x;
                        } else {
                            let _e1952 = local_629;
                            if (_e1952 == 1i) {
                                let _e1954 = local_628;
                                local_630 = _e1954.y;
                            } else {
                                let _e1956 = local_629;
                                if (_e1956 == 2i) {
                                    let _e1958 = local_628;
                                    local_630 = _e1958.z;
                                } else {
                                    let _e1960 = local_628;
                                    local_630 = _e1960.w;
                                }
                            }
                        }
                        let _e1962 = local_630;
                        let _e1963 = bitcast<u32>(_e1962);
                        let _e1964 = local_650;
                        local_655[_e1964] = (bitcast<i32>((_e1963 << bitcast<u32>(16u))) >> bitcast<u32>(16i));
                        local_656[_e1964] = (bitcast<i32>(_e1963) >> bitcast<u32>(16i));
                        let _e1975 = local_651;
                        let _e1976 = (_e1975 + 3i);
                        let _e1979 = v_info_0_1;
                        let _e1980 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1983 = local_623;
                        let _e1986 = vec2<i32>(vec2<i32>(_e1980).x, _e1983.y);
                        let _e1987 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e1992 = vec2<i32>(_e1986.x, vec2<i32>(_e1987).y);
                        local_623 = _e1992;
                        let _e1998 = (((_e1979.y * _e1992.x) + _e1979.x) + (_e1976 >> bitcast<u32>(2i)));
                        let _e2007 = vec2<i32>((_e1998 - (i32(floor((f32(_e1998) / f32(_e1992.x)))) * _e1992.x)), (_e1998 / _e1992.x));
                        let _e2010 = vec3<i32>(_e2007.x, _e2007.y, 0i);
                        let _e2013 = textureLoad(u_layer_tex_0_image, _e2010.xy, _e2010.z);
                        local_624 = _e2013;
                        let _e2014 = (_e1976 & 3i);
                        local_625 = _e2014;
                        if (_e2014 == 0i) {
                            let _e2016 = local_624;
                            local_626 = _e2016.x;
                        } else {
                            let _e2018 = local_625;
                            if (_e2018 == 1i) {
                                let _e2020 = local_624;
                                local_626 = _e2020.y;
                            } else {
                                let _e2022 = local_625;
                                if (_e2022 == 2i) {
                                    let _e2024 = local_624;
                                    local_626 = _e2024.z;
                                } else {
                                    let _e2026 = local_624;
                                    local_626 = _e2026.w;
                                }
                            }
                        }
                        let _e2028 = local_626;
                        let _e2029 = bitcast<u32>(_e2028);
                        let _e2030 = local_650;
                        local_657[_e2030] = ((_e2029 & 1u) != 0u);
                        local_658[_e2030] = ((_e2029 & 2u) != 0u);
                        local_659[_e2030] = ((_e2029 & 4u) != 0u);
                        local_660[_e2030] = ((_e2029 & 8u) != 0u);
                        local_661[_e2030] = bitcast<i32>(((_e2029 >> bitcast<u32>(4u)) & 63u));
                        local_662[_e2030] = bitcast<i32>(((_e2029 >> bitcast<u32>(10u)) & 63u));
                        local_663[_e2030] = false;
                        let _e2054 = local_652;
                        if !((abs(_e2054) <= 340282300000000000000000000000000000000f)) {
                            local_649 = true;
                        } else {
                            let _e2058 = local_650;
                            let _e2060 = local_654[_e2058];
                            local_649 = !((abs(_e2060) <= 340282300000000000000000000000000000000f));
                        }
                        let _e2064 = local_649;
                        if _e2064 {
                            local_664 = true;
                        } else {
                            let _e2065 = local_650;
                            let _e2067 = local_654[_e2065];
                            local_664 = (_e2067 < 0f);
                        }
                        let _e2069 = local_664;
                        if _e2069 {
                            local_665 = true;
                        } else {
                            let _e2070 = local_650;
                            let _e2072 = local_655[_e2070];
                            local_665 = (_e2072 < -1i);
                        }
                        let _e2074 = local_665;
                        if _e2074 {
                            local_666 = true;
                        } else {
                            let _e2075 = local_650;
                            let _e2077 = local_655[_e2075];
                            let _e2078 = local_647;
                            local_666 = (_e2077 >= _e2078);
                        }
                        let _e2080 = local_666;
                        if _e2080 {
                            local_667 = true;
                        } else {
                            let _e2081 = local_650;
                            let _e2083 = local_656[_e2081];
                            local_667 = (_e2083 < -1i);
                        }
                        let _e2085 = local_667;
                        if _e2085 {
                            local_668 = true;
                        } else {
                            let _e2086 = local_650;
                            let _e2088 = local_656[_e2086];
                            let _e2089 = local_797;
                            local_668 = (_e2088 >= _e2089);
                        }
                        let _e2091 = local_668;
                        if _e2091 {
                            local_643 = true;
                            local_644 = false;
                            break;
                        }
                        let _e2092 = local_650;
                        local_650 = (_e2092 + 1i);
                        continue;
                    }
                    let _e2094 = local_643;
                    if _e2094 {
                        break;
                    }
                    local_650 = 0i;
                    loop {
                        let _e2095 = local_650;
                        if (_e2095 < 32i) {
                        } else {
                            break;
                        }
                        let _e2097 = local_650;
                        let _e2098 = local_797;
                        if (_e2097 >= _e2098) {
                            break;
                        }
                        let _e2100 = local_650;
                        let _e2101 = (2i * _e2100);
                        local_669 = _e2101;
                        let _e2102 = (12i + _e2101);
                        let _e2105 = v_info_0_1;
                        let _e2106 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e2109 = local_619;
                        let _e2112 = vec2<i32>(vec2<i32>(_e2106).x, _e2109.y);
                        let _e2113 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e2118 = vec2<i32>(_e2112.x, vec2<i32>(_e2113).y);
                        local_619 = _e2118;
                        let _e2124 = (((_e2105.y * _e2118.x) + _e2105.x) + (_e2102 >> bitcast<u32>(2i)));
                        let _e2133 = vec2<i32>((_e2124 - (i32(floor((f32(_e2124) / f32(_e2118.x)))) * _e2118.x)), (_e2124 / _e2118.x));
                        let _e2136 = vec3<i32>(_e2133.x, _e2133.y, 0i);
                        let _e2139 = textureLoad(u_layer_tex_0_image, _e2136.xy, _e2136.z);
                        local_620 = _e2139;
                        let _e2140 = (_e2102 & 3i);
                        local_621 = _e2140;
                        if (_e2140 == 0i) {
                            let _e2142 = local_620;
                            local_622 = _e2142.x;
                        } else {
                            let _e2144 = local_621;
                            if (_e2144 == 1i) {
                                let _e2146 = local_620;
                                local_622 = _e2146.y;
                            } else {
                                let _e2148 = local_621;
                                if (_e2148 == 2i) {
                                    let _e2150 = local_620;
                                    local_622 = _e2150.z;
                                } else {
                                    let _e2152 = local_620;
                                    local_622 = _e2152.w;
                                }
                            }
                        }
                        let _e2154 = local_622;
                        local_670 = _e2154;
                        let _e2155 = local_669;
                        let _e2157 = (12i + (_e2155 + 1i));
                        let _e2160 = v_info_0_1;
                        let _e2161 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e2164 = local_615;
                        let _e2167 = vec2<i32>(vec2<i32>(_e2161).x, _e2164.y);
                        let _e2168 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e2173 = vec2<i32>(_e2167.x, vec2<i32>(_e2168).y);
                        local_615 = _e2173;
                        let _e2179 = (((_e2160.y * _e2173.x) + _e2160.x) + (_e2157 >> bitcast<u32>(2i)));
                        let _e2188 = vec2<i32>((_e2179 - (i32(floor((f32(_e2179) / f32(_e2173.x)))) * _e2173.x)), (_e2179 / _e2173.x));
                        let _e2191 = vec3<i32>(_e2188.x, _e2188.y, 0i);
                        let _e2194 = textureLoad(u_layer_tex_0_image, _e2191.xy, _e2191.z);
                        local_616 = _e2194;
                        let _e2195 = (_e2157 & 3i);
                        local_617 = _e2195;
                        if (_e2195 == 0i) {
                            let _e2197 = local_616;
                            local_618 = _e2197.x;
                        } else {
                            let _e2199 = local_617;
                            if (_e2199 == 1i) {
                                let _e2201 = local_616;
                                local_618 = _e2201.y;
                            } else {
                                let _e2203 = local_617;
                                if (_e2203 == 2i) {
                                    let _e2205 = local_616;
                                    local_618 = _e2205.z;
                                } else {
                                    let _e2207 = local_616;
                                    local_618 = _e2207.w;
                                }
                            }
                        }
                        let _e2209 = local_618;
                        local_671 = _e2209;
                        let _e2210 = local_670;
                        if !((abs(_e2210) <= 340282300000000000000000000000000000000f)) {
                            local_649 = true;
                        } else {
                            let _e2214 = local_671;
                            local_649 = !((abs(_e2214) <= 340282300000000000000000000000000000000f));
                        }
                        let _e2218 = local_649;
                        if _e2218 {
                            local_643 = true;
                            local_644 = false;
                            break;
                        }
                        let _e2219 = local_650;
                        local_650 = (_e2219 + 1i);
                        continue;
                    }
                    let _e2221 = local_643;
                    if _e2221 {
                        break;
                    }
                    local_650 = 0i;
                    loop {
                        let _e2222 = local_650;
                        if (_e2222 < 32i) {
                        } else {
                            break;
                        }
                        let _e2224 = local_650;
                        let _e2225 = local_647;
                        if (_e2224 >= _e2225) {
                            break;
                        }
                        let _e2227 = local_650;
                        let _e2229 = local_655[_e2227];
                        if (_e2229 >= 0i) {
                            let _e2231 = local_650;
                            let _e2233 = local_655[_e2231];
                            local_672 = _e2233;
                            let _e2235 = local_655[_e2231];
                            let _e2236 = local_647;
                            if (_e2235 >= _e2236) {
                                local_649 = true;
                            } else {
                                let _e2238 = local_672;
                                let _e2239 = local_650;
                                local_649 = (_e2238 == _e2239);
                            }
                            let _e2241 = local_649;
                            if _e2241 {
                                local_664 = true;
                            } else {
                                let _e2242 = local_672;
                                let _e2244 = local_655[_e2242];
                                let _e2245 = local_650;
                                local_664 = (_e2244 != _e2245);
                            }
                            let _e2247 = local_664;
                            if _e2247 {
                                local_665 = true;
                            } else {
                                let _e2248 = local_672;
                                let _e2250 = local_653[_e2248];
                                local_665 = !((abs(_e2250) <= 340282300000000000000000000000000000000f));
                            }
                            let _e2254 = local_665;
                            if _e2254 {
                                local_666 = true;
                            } else {
                                let _e2255 = local_672;
                                let _e2257 = local_653[_e2255];
                                let _e2258 = local_650;
                                let _e2260 = local_653[_e2258];
                                local_666 = (_e2257 == _e2260);
                            }
                            let _e2262 = local_666;
                            if _e2262 {
                                local_667 = true;
                            } else {
                                let _e2263 = local_672;
                                let _e2265 = local_654[_e2263];
                                local_667 = !((abs(_e2265) <= 340282300000000000000000000000000000000f));
                            }
                            let _e2269 = local_667;
                            if _e2269 {
                                local_668 = true;
                            } else {
                                let _e2270 = local_672;
                                let _e2272 = local_654[_e2270];
                                let _e2273 = local_650;
                                let _e2275 = local_654[_e2273];
                                local_668 = (_e2272 != _e2275);
                            }
                            let _e2277 = local_668;
                            if _e2277 {
                                local_643 = true;
                                local_644 = false;
                                break;
                            }
                        }
                        let _e2278 = local_650;
                        local_650 = (_e2278 + 1i);
                        continue;
                    }
                    let _e2280 = local_643;
                    if _e2280 {
                        break;
                    }
                    let _e2281 = local_648;
                    if _e2281 {
                        let _e2282 = local_99;
                        local_649 = (_e2282 == 1i);
                    } else {
                        local_649 = false;
                    }
                    let _e2284 = local_649;
                    if _e2284 {
                        let _e2285 = local_91;
                        local_673 = _e2285;
                    } else {
                        local_673 = 0f;
                    }
                    local_650 = 0i;
                    loop {
                        let _e2286 = local_650;
                        if (_e2286 < 32i) {
                        } else {
                            break;
                        }
                        let _e2288 = local_650;
                        let _e2289 = local_647;
                        if (_e2288 >= _e2289) {
                            break;
                        }
                        let _e2291 = local_650;
                        let _e2293 = local_655[_e2291];
                        if (_e2293 >= 0i) {
                            let _e2295 = local_650;
                            let _e2297 = local_655[_e2295];
                            let _e2299 = local_653[_e2297];
                            let _e2301 = local_653[_e2295];
                            local_649 = (_e2299 > _e2301);
                        } else {
                            local_649 = false;
                        }
                        let _e2303 = local_645;
                        if _e2303 {
                            let _e2304 = local_650;
                            let _e2306 = local_656[_e2304];
                            local_664 = (_e2306 >= 0i);
                        } else {
                            local_664 = false;
                        }
                        let _e2308 = local_664;
                        if _e2308 {
                            let _e2309 = local_650;
                            let _e2311 = local_656[_e2309];
                            let _e2314 = (12i + ((2i * _e2311) + 1i));
                            let _e2317 = v_info_0_1;
                            let _e2318 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2321 = local_611;
                            let _e2324 = vec2<i32>(vec2<i32>(_e2318).x, _e2321.y);
                            let _e2325 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2330 = vec2<i32>(_e2324.x, vec2<i32>(_e2325).y);
                            local_611 = _e2330;
                            let _e2336 = (((_e2317.y * _e2330.x) + _e2317.x) + (_e2314 >> bitcast<u32>(2i)));
                            let _e2345 = vec2<i32>((_e2336 - (i32(floor((f32(_e2336) / f32(_e2330.x)))) * _e2330.x)), (_e2336 / _e2330.x));
                            let _e2348 = vec3<i32>(_e2345.x, _e2345.y, 0i);
                            let _e2351 = textureLoad(u_layer_tex_0_image, _e2348.xy, _e2348.z);
                            local_612 = _e2351;
                            let _e2352 = (_e2314 & 3i);
                            local_613 = _e2352;
                            if (_e2352 == 0i) {
                                let _e2354 = local_612;
                                local_614 = _e2354.x;
                            } else {
                                let _e2356 = local_613;
                                if (_e2356 == 1i) {
                                    let _e2358 = local_612;
                                    local_614 = _e2358.y;
                                } else {
                                    let _e2360 = local_613;
                                    if (_e2360 == 2i) {
                                        let _e2362 = local_612;
                                        local_614 = _e2362.z;
                                    } else {
                                        let _e2364 = local_612;
                                        local_614 = _e2364.w;
                                    }
                                }
                            }
                            let _e2366 = local_614;
                            local_674 = _e2366;
                            let _e2367 = local_650;
                            let _e2369 = local_656[_e2367];
                            let _e2371 = (12i + (2i * _e2369));
                            let _e2374 = v_info_0_1;
                            let _e2375 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2378 = local_607;
                            let _e2381 = vec2<i32>(vec2<i32>(_e2375).x, _e2378.y);
                            let _e2382 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2387 = vec2<i32>(_e2381.x, vec2<i32>(_e2382).y);
                            local_607 = _e2387;
                            let _e2393 = (((_e2374.y * _e2387.x) + _e2374.x) + (_e2371 >> bitcast<u32>(2i)));
                            let _e2402 = vec2<i32>((_e2393 - (i32(floor((f32(_e2393) / f32(_e2387.x)))) * _e2387.x)), (_e2393 / _e2387.x));
                            let _e2405 = vec3<i32>(_e2402.x, _e2402.y, 0i);
                            let _e2408 = textureLoad(u_layer_tex_0_image, _e2405.xy, _e2405.z);
                            local_608 = _e2408;
                            let _e2409 = (_e2371 & 3i);
                            local_609 = _e2409;
                            if (_e2409 == 0i) {
                                let _e2411 = local_608;
                                local_610 = _e2411.x;
                            } else {
                                let _e2413 = local_609;
                                if (_e2413 == 1i) {
                                    let _e2415 = local_608;
                                    local_610 = _e2415.y;
                                } else {
                                    let _e2417 = local_609;
                                    if (_e2417 == 2i) {
                                        let _e2419 = local_608;
                                        local_610 = _e2419.z;
                                    } else {
                                        let _e2421 = local_608;
                                        local_610 = _e2421.w;
                                    }
                                }
                            }
                            let _e2423 = local_610;
                            let _e2424 = local_674;
                            local_665 = (_e2424 < _e2423);
                        } else {
                            local_665 = false;
                        }
                        let _e2426 = local_650;
                        let _e2428 = local_659[_e2426];
                        if !(_e2428) {
                            let _e2430 = local_650;
                            let _e2432 = local_655[_e2430];
                            local_666 = (_e2432 < 0i);
                        } else {
                            local_666 = false;
                        }
                        let _e2434 = local_666;
                        if _e2434 {
                            let _e2435 = local_664;
                            local_667 = !(_e2435);
                        } else {
                            local_667 = false;
                        }
                        let _e2437 = local_667;
                        if _e2437 {
                            let _e2438 = local_645;
                            local_668 = _e2438;
                        } else {
                            local_668 = false;
                        }
                        let _e2439 = local_668;
                        if _e2439 {
                            local_675 = 340282350000000000000000000000000000000f;
                            local_676 = 1i;
                            local_677 = 0i;
                            loop {
                                let _e2440 = local_677;
                                if (_e2440 < 32i) {
                                } else {
                                    break;
                                }
                                let _e2442 = local_677;
                                let _e2443 = local_647;
                                if (_e2442 >= _e2443) {
                                    break;
                                }
                                let _e2445 = local_677;
                                let _e2447 = local_656[_e2445];
                                if (_e2447 < 0i) {
                                    let _e2449 = local_677;
                                    local_677 = (_e2449 + 1i);
                                    continue;
                                }
                                let _e2451 = local_677;
                                let _e2453 = local_653[_e2451];
                                let _e2454 = local_650;
                                let _e2456 = local_653[_e2454];
                                let _e2458 = abs((_e2453 - _e2456));
                                local_678 = _e2458;
                                let _e2459 = local_675;
                                if (_e2458 >= _e2459) {
                                    let _e2461 = local_677;
                                    local_677 = (_e2461 + 1i);
                                    continue;
                                }
                                let _e2463 = local_677;
                                let _e2465 = local_656[_e2463];
                                let _e2468 = (12i + ((2i * _e2465) + 1i));
                                let _e2471 = v_info_0_1;
                                let _e2472 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e2475 = local_603;
                                let _e2478 = vec2<i32>(vec2<i32>(_e2472).x, _e2475.y);
                                let _e2479 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e2484 = vec2<i32>(_e2478.x, vec2<i32>(_e2479).y);
                                local_603 = _e2484;
                                let _e2490 = (((_e2471.y * _e2484.x) + _e2471.x) + (_e2468 >> bitcast<u32>(2i)));
                                let _e2499 = vec2<i32>((_e2490 - (i32(floor((f32(_e2490) / f32(_e2484.x)))) * _e2484.x)), (_e2490 / _e2484.x));
                                let _e2502 = vec3<i32>(_e2499.x, _e2499.y, 0i);
                                let _e2505 = textureLoad(u_layer_tex_0_image, _e2502.xy, _e2502.z);
                                local_604 = _e2505;
                                let _e2506 = (_e2468 & 3i);
                                local_605 = _e2506;
                                if (_e2506 == 0i) {
                                    let _e2508 = local_604;
                                    local_606 = _e2508.x;
                                } else {
                                    let _e2510 = local_605;
                                    if (_e2510 == 1i) {
                                        let _e2512 = local_604;
                                        local_606 = _e2512.y;
                                    } else {
                                        let _e2514 = local_605;
                                        if (_e2514 == 2i) {
                                            let _e2516 = local_604;
                                            local_606 = _e2516.z;
                                        } else {
                                            let _e2518 = local_604;
                                            local_606 = _e2518.w;
                                        }
                                    }
                                }
                                let _e2520 = local_606;
                                local_679 = _e2520;
                                let _e2521 = local_677;
                                let _e2523 = local_656[_e2521];
                                let _e2525 = (12i + (2i * _e2523));
                                let _e2528 = v_info_0_1;
                                let _e2529 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e2532 = local_599;
                                let _e2535 = vec2<i32>(vec2<i32>(_e2529).x, _e2532.y);
                                let _e2536 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e2541 = vec2<i32>(_e2535.x, vec2<i32>(_e2536).y);
                                local_599 = _e2541;
                                let _e2547 = (((_e2528.y * _e2541.x) + _e2528.x) + (_e2525 >> bitcast<u32>(2i)));
                                let _e2556 = vec2<i32>((_e2547 - (i32(floor((f32(_e2547) / f32(_e2541.x)))) * _e2541.x)), (_e2547 / _e2541.x));
                                let _e2559 = vec3<i32>(_e2556.x, _e2556.y, 0i);
                                let _e2562 = textureLoad(u_layer_tex_0_image, _e2559.xy, _e2559.z);
                                local_600 = _e2562;
                                let _e2563 = (_e2525 & 3i);
                                local_601 = _e2563;
                                if (_e2563 == 0i) {
                                    let _e2565 = local_600;
                                    local_602 = _e2565.x;
                                } else {
                                    let _e2567 = local_601;
                                    if (_e2567 == 1i) {
                                        let _e2569 = local_600;
                                        local_602 = _e2569.y;
                                    } else {
                                        let _e2571 = local_601;
                                        if (_e2571 == 2i) {
                                            let _e2573 = local_600;
                                            local_602 = _e2573.z;
                                        } else {
                                            let _e2575 = local_600;
                                            local_602 = _e2575.w;
                                        }
                                    }
                                }
                                let _e2577 = local_602;
                                let _e2578 = local_679;
                                if (_e2578 < _e2577) {
                                    local_680 = 1i;
                                } else {
                                    local_680 = -1i;
                                }
                                let _e2580 = local_678;
                                local_675 = _e2580;
                                let _e2581 = local_680;
                                local_676 = _e2581;
                                let _e2582 = local_677;
                                local_677 = (_e2582 + 1i);
                                continue;
                            }
                        } else {
                            local_676 = 1i;
                        }
                        let _e2584 = local_650;
                        let _e2586 = local_659[_e2584];
                        if _e2586 {
                            let _e2587 = local_645;
                            if _e2587 {
                                let _e2588 = local_650;
                                let _e2590 = local_660[_e2588];
                                local_681 = _e2590;
                            } else {
                                local_681 = false;
                            }
                            let _e2591 = local_681;
                            if _e2591 {
                                local_682 = true;
                            } else {
                                let _e2592 = local_645;
                                if !(_e2592) {
                                    let _e2594 = local_649;
                                    local_682 = _e2594;
                                } else {
                                    local_682 = false;
                                }
                            }
                            let _e2595 = local_682;
                            if _e2595 {
                                local_677 = -1i;
                            } else {
                                local_677 = 1i;
                            }
                        } else {
                            let _e2596 = local_649;
                            if _e2596 {
                                local_681 = true;
                            } else {
                                let _e2597 = local_665;
                                local_681 = _e2597;
                            }
                            let _e2598 = local_681;
                            if _e2598 {
                                local_677 = -1i;
                            } else {
                                let _e2599 = local_676;
                                local_677 = _e2599;
                            }
                        }
                        let _e2600 = local_650;
                        let _e2601 = local_677;
                        local_683[_e2600] = _e2601;
                        let _e2603 = local_645;
                        if _e2603 {
                            let _e2604 = local_650;
                            let _e2606 = local_662[_e2604];
                            local_680 = _e2606;
                        } else {
                            let _e2607 = local_650;
                            let _e2609 = local_661[_e2607];
                            local_680 = _e2609;
                        }
                        let _e2610 = local_650;
                        let _e2612 = local_659[_e2610];
                        if !(_e2612) {
                            local_681 = true;
                        } else {
                            let _e2614 = local_680;
                            local_681 = (_e2614 == 63i);
                        }
                        let _e2616 = local_681;
                        if _e2616 {
                            local_684 = -2i;
                        } else {
                            let _e2617 = local_680;
                            if (_e2617 == 62i) {
                                local_684 = -1i;
                            } else {
                                let _e2619 = local_680;
                                local_684 = _e2619;
                            }
                        }
                        let _e2620 = local_650;
                        let _e2621 = local_684;
                        local_685[_e2620] = _e2621;
                        let _e2623 = local_664;
                        if _e2623 {
                            let _e2624 = local_650;
                            let _e2626 = local_656[_e2624];
                            let _e2628 = (12i + (2i * _e2626));
                            let _e2631 = v_info_0_1;
                            let _e2632 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2635 = local_595;
                            let _e2638 = vec2<i32>(vec2<i32>(_e2632).x, _e2635.y);
                            let _e2639 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2644 = vec2<i32>(_e2638.x, vec2<i32>(_e2639).y);
                            local_595 = _e2644;
                            let _e2650 = (((_e2631.y * _e2644.x) + _e2631.x) + (_e2628 >> bitcast<u32>(2i)));
                            let _e2659 = vec2<i32>((_e2650 - (i32(floor((f32(_e2650) / f32(_e2644.x)))) * _e2644.x)), (_e2650 / _e2644.x));
                            let _e2662 = vec3<i32>(_e2659.x, _e2659.y, 0i);
                            let _e2665 = textureLoad(u_layer_tex_0_image, _e2662.xy, _e2662.z);
                            local_596 = _e2665;
                            let _e2666 = (_e2628 & 3i);
                            local_597 = _e2666;
                            if (_e2666 == 0i) {
                                let _e2668 = local_596;
                                local_598 = _e2668.x;
                            } else {
                                let _e2670 = local_597;
                                if (_e2670 == 1i) {
                                    let _e2672 = local_596;
                                    local_598 = _e2672.y;
                                } else {
                                    let _e2674 = local_597;
                                    if (_e2674 == 2i) {
                                        let _e2676 = local_596;
                                        local_598 = _e2676.z;
                                    } else {
                                        let _e2678 = local_596;
                                        local_598 = _e2678.w;
                                    }
                                }
                            }
                            let _e2680 = local_598;
                            local_686 = _e2680;
                            let _e2681 = local_650;
                            let _e2683 = local_656[_e2681];
                            let _e2686 = (12i + ((2i * _e2683) + 1i));
                            let _e2689 = v_info_0_1;
                            let _e2690 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2693 = local_591;
                            let _e2696 = vec2<i32>(vec2<i32>(_e2690).x, _e2693.y);
                            let _e2697 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e2702 = vec2<i32>(_e2696.x, vec2<i32>(_e2697).y);
                            local_591 = _e2702;
                            let _e2708 = (((_e2689.y * _e2702.x) + _e2689.x) + (_e2686 >> bitcast<u32>(2i)));
                            let _e2717 = vec2<i32>((_e2708 - (i32(floor((f32(_e2708) / f32(_e2702.x)))) * _e2702.x)), (_e2708 / _e2702.x));
                            let _e2720 = vec3<i32>(_e2717.x, _e2717.y, 0i);
                            let _e2723 = textureLoad(u_layer_tex_0_image, _e2720.xy, _e2720.z);
                            local_592 = _e2723;
                            let _e2724 = (_e2686 & 3i);
                            local_593 = _e2724;
                            if (_e2724 == 0i) {
                                let _e2726 = local_592;
                                local_594 = _e2726.x;
                            } else {
                                let _e2728 = local_593;
                                if (_e2728 == 1i) {
                                    let _e2730 = local_592;
                                    local_594 = _e2730.y;
                                } else {
                                    let _e2732 = local_593;
                                    if (_e2732 == 2i) {
                                        let _e2734 = local_592;
                                        local_594 = _e2734.z;
                                    } else {
                                        let _e2736 = local_592;
                                        local_594 = _e2736.w;
                                    }
                                }
                            }
                            let _e2738 = local_594;
                            local_687 = _e2738;
                            let _e2739 = local_650;
                            let _e2741 = local_657[_e2739];
                            if _e2741 {
                                let _e2742 = local_648;
                                local_682 = _e2742;
                            } else {
                                local_682 = false;
                            }
                            let _e2743 = local_682;
                            if _e2743 {
                                let _e2744 = local_99;
                                local_688 = (_e2744 == 0i);
                            } else {
                                local_688 = false;
                            }
                            let _e2746 = local_688;
                            if _e2746 {
                                let _e2747 = local_650;
                                let _e2749 = local_653[_e2747];
                                local_689[_e2747] = _e2749;
                            } else {
                                let _e2751 = local_650;
                                let _e2752 = local_686;
                                let _e2753 = local_800;
                                local_689[_e2751] = (round((_e2752 * _e2753)) / _e2753);
                                let _e2759 = local_657[_e2751];
                                if _e2759 {
                                    let _e2760 = local_687;
                                    let _e2761 = local_686;
                                    let _e2763 = local_800;
                                    let _e2766 = local_673;
                                    local_690 = (abs(((_e2760 - _e2761) * _e2763)) >= _e2766);
                                } else {
                                    local_690 = false;
                                }
                                let _e2768 = local_690;
                                if _e2768 {
                                    let _e2769 = local_650;
                                    let _e2771 = local_689[_e2769];
                                    let _e2772 = local_687;
                                    let _e2773 = local_686;
                                    local_689[_e2769] = (_e2771 + (_e2772 - _e2773));
                                }
                            }
                        } else {
                            let _e2777 = local_650;
                            let _e2779 = local_653[_e2777];
                            let _e2780 = local_800;
                            local_689[_e2777] = (round((_e2779 * _e2780)) / _e2780);
                        }
                        let _e2785 = local_650;
                        local_650 = (_e2785 + 1i);
                        continue;
                    }
                    let _e2787 = local_800;
                    local_691 = (1f / _e2787);
                    let _e2789 = local_646;
                    if _e2789 {
                        let _e2790 = local_104;
                        local_676 = _e2790;
                    } else {
                        let _e2791 = local_100;
                        local_676 = _e2791;
                    }
                    let _e2792 = local_646;
                    if _e2792 {
                        let _e2793 = local_95;
                        local_673 = _e2793;
                    } else {
                        let _e2794 = local_93;
                        local_673 = _e2794;
                    }
                    let _e2795 = local_646;
                    if _e2795 {
                        let _e2796 = local_94;
                        local_675 = _e2796;
                    } else {
                        let _e2797 = local_92;
                        local_675 = _e2797;
                    }
                    let _e2798 = local_646;
                    if _e2798 {
                        let _e2799 = local_105;
                        local_645 = (_e2799 == 1i);
                    } else {
                        let _e2801 = local_101;
                        local_645 = (_e2801 != 0i);
                    }
                    let _e2803 = local_646;
                    if _e2803 {
                        let _e2804 = local_103;
                        local_649 = (_e2804 == 1i);
                    } else {
                        local_649 = false;
                    }
                    local_664 = false;
                    local_692 = 0f;
                    local_693 = 0f;
                    local_694 = 0f;
                    local_695 = 0f;
                    local_696 = 0f;
                    local_677 = 0i;
                    local_650 = 0i;
                    local_680 = 0i;
                    loop {
                        let _e2806 = local_650;
                        if (_e2806 < 32i) {
                        } else {
                            break;
                        }
                        let _e2808 = local_650;
                        let _e2809 = local_647;
                        if (_e2808 >= _e2809) {
                            break;
                        }
                        let _e2811 = local_650;
                        let _e2813 = local_655[_e2811];
                        local_697 = _e2813;
                        let _e2815 = local_655[_e2811];
                        if (_e2815 < 0i) {
                            local_665 = true;
                        } else {
                            let _e2817 = local_697;
                            let _e2818 = local_650;
                            local_665 = (_e2817 <= _e2818);
                        }
                        let _e2820 = local_665;
                        if _e2820 {
                            let _e2821 = local_664;
                            local_667 = _e2821;
                            let _e2822 = local_650;
                            local_650 = (_e2822 + 1i);
                            continue;
                        }
                        let _e2824 = local_650;
                        let _e2826 = local_654[_e2824];
                        local_699 = _e2826;
                        let _e2827 = local_798;
                        local_700 = _e2827;
                        let _e2828 = local_673;
                        local_701 = _e2828;
                        if (_e2827 > 0f) {
                            let _e2830 = local_699;
                            let _e2831 = local_700;
                            let _e2834 = local_701;
                            local_589 = (abs((_e2830 - _e2831)) <= (_e2834 * _e2831));
                        } else {
                            local_589 = false;
                        }
                        let _e2837 = local_589;
                        if _e2837 {
                            let _e2838 = local_700;
                            local_590 = _e2838;
                        } else {
                            let _e2839 = local_699;
                            local_590 = _e2839;
                        }
                        let _e2840 = local_590;
                        local_698 = _e2840;
                        let _e2841 = local_650;
                        let _e2843 = local_654[_e2841];
                        local_702 = _e2843;
                        let _e2844 = local_676;
                        if (_e2844 == 2i) {
                            local_666 = true;
                        } else {
                            let _e2846 = local_676;
                            if (_e2846 == 1i) {
                                let _e2848 = local_698;
                                let _e2849 = local_800;
                                let _e2851 = local_675;
                                local_666 = ((_e2848 * _e2849) < _e2851);
                            } else {
                                local_666 = false;
                            }
                        }
                        let _e2853 = local_666;
                        if _e2853 {
                            let _e2854 = local_698;
                            let _e2855 = local_800;
                            let _e2859 = local_691;
                            local_703 = (max(round((_e2854 * _e2855)), 1f) * _e2859);
                        } else {
                            let _e2861 = local_702;
                            local_703 = _e2861;
                        }
                        let _e2862 = local_649;
                        if _e2862 {
                            let _e2863 = local_664;
                            if _e2863 {
                                let _e2864 = local_650;
                                let _e2865 = local_692;
                                let _e2867 = local_653[_e2864];
                                let _e2868 = local_693;
                                let _e2870 = local_800;
                                let _e2873 = local_691;
                                local_689[_e2864] = (_e2865 + (round(((_e2867 - _e2868) * _e2870)) * _e2873));
                                let _e2877 = local_694;
                                local_704 = _e2877;
                                let _e2878 = local_695;
                                local_705 = _e2878;
                                let _e2879 = local_664;
                                local_667 = _e2879;
                            } else {
                                let _e2880 = local_650;
                                let _e2882 = local_653[_e2880];
                                let _e2883 = local_800;
                                let _e2886 = (round((_e2882 * _e2883)) / _e2883);
                                local_689[_e2880] = _e2886;
                                local_704 = _e2886;
                                let _e2889 = local_653[_e2880];
                                local_705 = _e2889;
                                local_667 = true;
                            }
                            let _e2890 = local_697;
                            let _e2891 = local_650;
                            let _e2893 = local_689[_e2891];
                            let _e2894 = local_703;
                            local_689[_e2890] = (_e2893 + _e2894);
                            let _e2897 = local_704;
                            let _e2899 = local_653[_e2891];
                            let _e2900 = local_705;
                            let _e2902 = local_800;
                            let _e2905 = local_691;
                            let _e2909 = local_680;
                            let _e2912 = local_689[_e2891];
                            local_704 = _e2912;
                            let _e2914 = local_653[_e2891];
                            local_705 = _e2914;
                            local_706 = _e2897;
                            local_707 = _e2900;
                            local_708 = ((_e2897 + (round(((_e2899 - _e2900) * _e2902)) * _e2905)) + _e2894);
                            local_684 = _e2890;
                            local_709 = (_e2909 + 1i);
                        } else {
                            let _e2915 = local_646;
                            if _e2915 {
                                let _e2916 = local_105;
                                local_667 = (_e2916 != 0i);
                            } else {
                                let _e2918 = local_101;
                                local_667 = (_e2918 != 0i);
                            }
                            let _e2920 = local_667;
                            if _e2920 {
                                let _e2921 = local_650;
                                let _e2923 = local_656[_e2921];
                                local_668 = (_e2923 >= 0i);
                            } else {
                                local_668 = false;
                            }
                            let _e2925 = local_667;
                            if _e2925 {
                                let _e2926 = local_697;
                                let _e2928 = local_656[_e2926];
                                local_681 = (_e2928 >= 0i);
                            } else {
                                local_681 = false;
                            }
                            let _e2930 = local_645;
                            if !(_e2930) {
                                let _e2932 = local_650;
                                let _e2934 = local_653[_e2932];
                                local_689[_e2932] = _e2934;
                            }
                            let _e2936 = local_681;
                            if _e2936 {
                                let _e2937 = local_668;
                                local_682 = !(_e2937);
                            } else {
                                local_682 = false;
                            }
                            let _e2939 = local_682;
                            if _e2939 {
                                let _e2940 = local_645;
                                local_688 = _e2940;
                            } else {
                                local_688 = false;
                            }
                            let _e2941 = local_688;
                            if _e2941 {
                                let _e2942 = local_650;
                                let _e2943 = local_697;
                                let _e2945 = local_689[_e2943];
                                let _e2946 = local_703;
                                local_689[_e2942] = (_e2945 - _e2946);
                            } else {
                                let _e2949 = local_697;
                                let _e2950 = local_650;
                                let _e2952 = local_689[_e2950];
                                let _e2953 = local_703;
                                local_689[_e2949] = (_e2952 + _e2953);
                            }
                            let _e2956 = local_664;
                            local_667 = _e2956;
                            let _e2957 = local_692;
                            local_704 = _e2957;
                            let _e2958 = local_693;
                            local_705 = _e2958;
                            let _e2959 = local_694;
                            local_706 = _e2959;
                            let _e2960 = local_695;
                            local_707 = _e2960;
                            let _e2961 = local_696;
                            local_708 = _e2961;
                            let _e2962 = local_677;
                            local_684 = _e2962;
                            let _e2963 = local_680;
                            local_709 = _e2963;
                        }
                        let _e2964 = local_650;
                        local_663[_e2964] = true;
                        let _e2966 = local_697;
                        local_663[_e2966] = true;
                        let _e2968 = local_704;
                        local_692 = _e2968;
                        let _e2969 = local_705;
                        local_693 = _e2969;
                        let _e2970 = local_706;
                        local_694 = _e2970;
                        let _e2971 = local_707;
                        local_695 = _e2971;
                        let _e2972 = local_708;
                        local_696 = _e2972;
                        let _e2973 = local_684;
                        local_677 = _e2973;
                        let _e2974 = local_709;
                        local_680 = _e2974;
                        let _e2976 = local_667;
                        local_664 = _e2976;
                        local_650 = (_e2964 + 1i);
                        continue;
                    }
                    let _e2977 = local_649;
                    if _e2977 {
                        let _e2978 = local_680;
                        local_645 = (_e2978 > 1i);
                    } else {
                        local_645 = false;
                    }
                    let _e2980 = local_645;
                    if _e2980 {
                        let _e2981 = local_696;
                        let _e2982 = local_677;
                        let _e2984 = local_689[_e2982];
                        local_710 = (_e2981 - _e2984);
                        local_650 = 0i;
                        loop {
                            let _e2986 = local_650;
                            if (_e2986 < 32i) {
                            } else {
                                break;
                            }
                            let _e2988 = local_650;
                            let _e2989 = local_647;
                            if (_e2988 >= _e2989) {
                                break;
                            }
                            let _e2991 = local_650;
                            let _e2993 = local_663[_e2991];
                            if _e2993 {
                                let _e2994 = local_650;
                                let _e2996 = local_689[_e2994];
                                let _e2997 = local_710;
                                local_689[_e2994] = (_e2996 + _e2997);
                            }
                            let _e3000 = local_650;
                            local_650 = (_e3000 + 1i);
                            continue;
                        }
                    }
                    let _e3002 = local_676;
                    if (_e3002 == 1i) {
                        let _e3004 = local_675;
                        local_673 = _e3004;
                    } else {
                        local_673 = 1.6f;
                    }
                    local_650 = 0i;
                    loop {
                        let _e3005 = local_650;
                        if (_e3005 < 32i) {
                        } else {
                            break;
                        }
                        let _e3007 = local_650;
                        let _e3008 = local_647;
                        if (_e3007 >= _e3008) {
                            break;
                        }
                        let _e3010 = local_646;
                        if _e3010 {
                            let _e3011 = local_105;
                            local_667 = (_e3011 != 0i);
                        } else {
                            let _e3013 = local_101;
                            local_667 = (_e3013 != 0i);
                        }
                        let _e3015 = local_667;
                        if !(_e3015) {
                            local_645 = true;
                        } else {
                            let _e3017 = local_650;
                            let _e3019 = local_656[_e3017];
                            local_645 = (_e3019 < 0i);
                        }
                        let _e3021 = local_645;
                        if _e3021 {
                            local_649 = true;
                        } else {
                            let _e3022 = local_650;
                            let _e3024 = local_657[_e3022];
                            local_649 = !(_e3024);
                        }
                        let _e3026 = local_649;
                        if _e3026 {
                            local_664 = true;
                        } else {
                            let _e3027 = local_650;
                            let _e3029 = local_663[_e3027];
                            local_664 = _e3029;
                        }
                        let _e3030 = local_664;
                        if _e3030 {
                            let _e3031 = local_650;
                            local_650 = (_e3031 + 1i);
                            continue;
                        }
                        let _e3033 = local_650;
                        let _e3035 = local_683[_e3033];
                        local_711 = (_e3035 > 0i);
                        let _e3038 = local_685[_e3033];
                        local_712 = _e3038;
                        let _e3040 = local_685[_e3033];
                        if (_e3040 >= 0i) {
                            let _e3042 = local_711;
                            if _e3042 {
                                let _e3043 = local_650;
                                let _e3045 = local_653[_e3043];
                                let _e3046 = local_712;
                                let _e3048 = local_653[_e3046];
                                local_675 = (_e3045 - _e3048);
                            } else {
                                let _e3050 = local_712;
                                let _e3052 = local_653[_e3050];
                                let _e3053 = local_650;
                                let _e3055 = local_653[_e3053];
                                local_675 = (_e3052 - _e3055);
                            }
                            let _e3057 = local_712;
                            local_684 = _e3057;
                            let _e3058 = local_675;
                            local_703 = _e3058;
                        } else {
                            let _e3059 = local_712;
                            if (_e3059 == -2i) {
                                local_703 = 340282350000000000000000000000000000000f;
                                let _e3061 = local_712;
                                local_684 = _e3061;
                                local_709 = 0i;
                                loop {
                                    let _e3062 = local_709;
                                    if (_e3062 < 32i) {
                                    } else {
                                        break;
                                    }
                                    let _e3064 = local_709;
                                    let _e3065 = local_647;
                                    if (_e3064 >= _e3065) {
                                        break;
                                    }
                                    let _e3067 = local_709;
                                    let _e3068 = local_650;
                                    if (_e3067 == _e3068) {
                                        local_665 = true;
                                    } else {
                                        let _e3070 = local_709;
                                        let _e3072 = local_683[_e3070];
                                        let _e3073 = local_650;
                                        let _e3075 = local_683[_e3073];
                                        local_665 = (_e3072 == _e3075);
                                    }
                                    let _e3077 = local_665;
                                    if _e3077 {
                                        let _e3078 = local_709;
                                        local_709 = (_e3078 + 1i);
                                        continue;
                                    }
                                    let _e3080 = local_711;
                                    if _e3080 {
                                        let _e3081 = local_650;
                                        let _e3083 = local_653[_e3081];
                                        let _e3084 = local_709;
                                        let _e3086 = local_653[_e3084];
                                        local_704 = (_e3083 - _e3086);
                                    } else {
                                        let _e3088 = local_709;
                                        let _e3090 = local_653[_e3088];
                                        let _e3091 = local_650;
                                        let _e3093 = local_653[_e3091];
                                        local_704 = (_e3090 - _e3093);
                                    }
                                    let _e3095 = local_704;
                                    if (_e3095 <= 0f) {
                                        local_666 = true;
                                    } else {
                                        let _e3097 = local_704;
                                        let _e3098 = local_703;
                                        local_666 = (_e3097 >= _e3098);
                                    }
                                    let _e3100 = local_666;
                                    if _e3100 {
                                        let _e3101 = local_709;
                                        local_709 = (_e3101 + 1i);
                                        continue;
                                    }
                                    let _e3103 = local_704;
                                    local_703 = _e3103;
                                    let _e3104 = local_709;
                                    local_684 = _e3104;
                                    local_709 = (_e3104 + 1i);
                                    continue;
                                }
                            } else {
                                let _e3106 = local_712;
                                local_684 = _e3106;
                                local_703 = 340282350000000000000000000000000000000f;
                            }
                        }
                        let _e3107 = local_684;
                        if (_e3107 < 0i) {
                            local_665 = true;
                        } else {
                            let _e3109 = local_684;
                            let _e3111 = local_663[_e3109];
                            local_665 = _e3111;
                        }
                        let _e3112 = local_665;
                        if _e3112 {
                            local_666 = true;
                        } else {
                            let _e3113 = local_684;
                            let _e3115 = local_656[_e3113];
                            local_666 = (_e3115 >= 0i);
                        }
                        let _e3117 = local_666;
                        if _e3117 {
                            local_668 = true;
                        } else {
                            let _e3118 = local_703;
                            let _e3119 = local_800;
                            let _e3121 = local_673;
                            local_668 = ((_e3118 * _e3119) >= _e3121);
                        }
                        let _e3123 = local_668;
                        if _e3123 {
                            let _e3124 = local_650;
                            local_650 = (_e3124 + 1i);
                            continue;
                        }
                        let _e3126 = local_684;
                        let _e3128 = local_658[_e3126];
                        if _e3128 {
                            let _e3129 = local_703;
                            local_704 = _e3129;
                        } else {
                            let _e3130 = local_703;
                            let _e3131 = local_800;
                            let _e3135 = local_691;
                            local_704 = (max(round((_e3130 * _e3131)), 1f) * _e3135);
                        }
                        let _e3137 = local_711;
                        if _e3137 {
                            let _e3138 = local_650;
                            let _e3140 = local_689[_e3138];
                            let _e3141 = local_704;
                            local_675 = (_e3140 - _e3141);
                        } else {
                            let _e3143 = local_650;
                            let _e3145 = local_689[_e3143];
                            let _e3146 = local_704;
                            local_675 = (_e3145 + _e3146);
                        }
                        let _e3148 = local_684;
                        let _e3149 = local_675;
                        local_689[_e3148] = _e3149;
                        local_663[_e3148] = true;
                        let _e3152 = local_650;
                        local_650 = (_e3152 + 1i);
                        continue;
                    }
                    local_650 = 0i;
                    loop {
                        let _e3154 = local_650;
                        if (_e3154 < 32i) {
                        } else {
                            break;
                        }
                        let _e3156 = local_650;
                        let _e3157 = local_647;
                        if (_e3156 >= _e3157) {
                            break;
                        }
                        let _e3159 = local_646;
                        if _e3159 {
                            let _e3160 = local_105;
                            local_667 = (_e3160 != 0i);
                        } else {
                            let _e3162 = local_101;
                            local_667 = (_e3162 != 0i);
                        }
                        let _e3164 = local_650;
                        let _e3166 = local_663[_e3164];
                        if !(_e3166) {
                            let _e3168 = local_667;
                            if _e3168 {
                                let _e3169 = local_650;
                                let _e3171 = local_656[_e3169];
                                local_645 = (_e3171 >= 0i);
                            } else {
                                local_645 = false;
                            }
                            let _e3173 = local_645;
                            local_645 = !(_e3173);
                        } else {
                            local_645 = false;
                        }
                        let _e3175 = local_645;
                        if _e3175 {
                            let _e3176 = local_650;
                            local_650 = (_e3176 + 1i);
                            continue;
                        }
                        let _e3178 = local_801;
                        let _e3179 = local_650;
                        let _e3181 = local_653[_e3179];
                        local_802[_e3178] = _e3181;
                        let _e3184 = local_689[_e3179];
                        local_803[_e3178] = _e3184;
                        let _e3186 = local_667;
                        if _e3186 {
                            let _e3187 = local_650;
                            let _e3189 = local_656[_e3187];
                            local_649 = (_e3189 >= 0i);
                        } else {
                            local_649 = false;
                        }
                        let _e3191 = local_801;
                        let _e3192 = local_649;
                        local_713[_e3191] = _e3192;
                        let _e3194 = local_650;
                        let _e3196 = local_658[_e3194];
                        local_714[_e3191] = _e3196;
                        local_801 = (_e3191 + 1i);
                        local_650 = (_e3194 + 1i);
                        continue;
                    }
                    let _e3200 = local_646;
                    if _e3200 {
                        let _e3201 = local_102;
                        local_645 = (_e3201 == 1i);
                    } else {
                        local_645 = false;
                    }
                    let _e3203 = local_645;
                    if _e3203 {
                        let _e3204 = local_801;
                        local_645 = (_e3204 > 0i);
                    } else {
                        local_645 = false;
                    }
                    let _e3206 = local_645;
                    if _e3206 {
                        let _e3207 = local_801;
                        local_645 = (_e3207 < 32i);
                    } else {
                        local_645 = false;
                    }
                    let _e3209 = local_645;
                    if _e3209 {
                        let _e3210 = local_799;
                        let _e3212 = local_802[0i];
                        let _e3213 = local_691;
                        local_645 = (_e3210 < (_e3212 - (0.25f * _e3213)));
                    } else {
                        local_645 = false;
                    }
                    let _e3217 = local_645;
                    if _e3217 {
                        local_650 = 31i;
                        loop {
                            let _e3218 = local_650;
                            if (_e3218 > 0i) {
                            } else {
                                break;
                            }
                            let _e3220 = local_650;
                            let _e3221 = local_801;
                            if (_e3220 <= _e3221) {
                                let _e3223 = local_650;
                                let _e3224 = (_e3223 - 1i);
                                let _e3226 = local_802[_e3224];
                                local_802[_e3223] = _e3226;
                                let _e3229 = local_803[_e3224];
                                local_803[_e3223] = _e3229;
                                let _e3232 = local_713[_e3224];
                                local_713[_e3223] = _e3232;
                                let _e3235 = local_714[_e3224];
                                local_714[_e3223] = _e3235;
                            }
                            let _e3237 = local_650;
                            local_650 = (_e3237 - 1i);
                            continue;
                        }
                        let _e3239 = local_799;
                        local_802[0i] = _e3239;
                        let _e3241 = local_800;
                        local_803[0i] = (round((_e3239 * _e3241)) / _e3241);
                        local_713[0i] = false;
                        local_714[0i] = false;
                        let _e3248 = local_801;
                        local_801 = (_e3248 + 1i);
                    }
                    local_684 = 31i;
                    loop {
                        let _e3250 = local_684;
                        if (_e3250 > 0i) {
                        } else {
                            break;
                        }
                        let _e3252 = local_684;
                        let _e3253 = local_801;
                        if (_e3252 >= _e3253) {
                            local_645 = true;
                        } else {
                            let _e3255 = local_684;
                            let _e3257 = local_713[_e3255];
                            local_645 = !(_e3257);
                        }
                        let _e3259 = local_645;
                        if _e3259 {
                            let _e3260 = local_684;
                            local_684 = (_e3260 - 1i);
                            continue;
                        }
                        local_709 = 31i;
                        loop {
                            let _e3262 = local_709;
                            if (_e3262 > 0i) {
                            } else {
                                break;
                            }
                            let _e3264 = local_709;
                            let _e3265 = local_684;
                            if (_e3264 > _e3265) {
                                let _e3267 = local_709;
                                local_709 = (_e3267 - 1i);
                                continue;
                            }
                            let _e3269 = local_709;
                            let _e3270 = (_e3269 - 1i);
                            local_715 = _e3270;
                            let _e3272 = local_713[_e3270];
                            if _e3272 {
                                break;
                            }
                            let _e3273 = local_715;
                            let _e3275 = local_714[_e3273];
                            if _e3275 {
                                local_673 = 0.000001f;
                            } else {
                                let _e3276 = local_691;
                                local_673 = _e3276;
                            }
                            let _e3277 = local_715;
                            let _e3279 = local_803[_e3277];
                            let _e3280 = local_709;
                            let _e3282 = local_803[_e3280];
                            let _e3283 = local_673;
                            local_803[_e3277] = min(_e3279, (_e3282 - _e3283));
                            local_709 = (_e3280 - 1i);
                            continue;
                        }
                        let _e3288 = local_684;
                        local_684 = (_e3288 - 1i);
                        continue;
                    }
                    local_650 = 1i;
                    loop {
                        let _e3290 = local_650;
                        if (_e3290 < 32i) {
                        } else {
                            break;
                        }
                        let _e3292 = local_650;
                        let _e3293 = local_801;
                        if (_e3292 >= _e3293) {
                            break;
                        }
                        let _e3295 = local_650;
                        let _e3297 = local_803[_e3295];
                        let _e3300 = local_803[(_e3295 - 1i)];
                        if (_e3297 <= _e3300) {
                            let _e3302 = local_650;
                            let _e3305 = local_803[(_e3302 - 1i)];
                            let _e3306 = local_691;
                            local_803[_e3302] = (_e3305 + _e3306);
                        }
                        let _e3309 = local_650;
                        local_650 = (_e3309 + 1i);
                        continue;
                    }
                    let _e3311 = local_98;
                    if (_e3311 != 0i) {
                        let _e3313 = local_800;
                        let _e3314 = local_97;
                        local_645 = (_e3313 > _e3314);
                    } else {
                        local_645 = false;
                    }
                    let _e3316 = local_645;
                    if _e3316 {
                        let _e3317 = local_96;
                        let _e3318 = local_97;
                        let _e3319 = (_e3317 - _e3318);
                        local_716 = _e3319;
                        if (_e3319 <= 0f) {
                            local_645 = true;
                        } else {
                            let _e3321 = local_800;
                            let _e3322 = local_96;
                            local_645 = (_e3321 >= _e3322);
                        }
                        let _e3324 = local_645;
                        if _e3324 {
                            local_673 = 1f;
                        } else {
                            let _e3325 = local_800;
                            let _e3326 = local_97;
                            let _e3328 = local_716;
                            local_673 = ((_e3325 - _e3326) / _e3328);
                        }
                        local_650 = 0i;
                        loop {
                            let _e3330 = local_650;
                            if (_e3330 < 32i) {
                            } else {
                                break;
                            }
                            let _e3332 = local_650;
                            let _e3333 = local_801;
                            if (_e3332 >= _e3333) {
                                break;
                            }
                            let _e3335 = local_650;
                            let _e3337 = local_803[_e3335];
                            let _e3339 = local_802[_e3335];
                            let _e3341 = local_803[_e3335];
                            let _e3343 = local_673;
                            local_803[_e3335] = (_e3337 + ((_e3339 - _e3341) * _e3343));
                            local_650 = (_e3335 + 1i);
                            continue;
                        }
                    }
                    local_650 = 0i;
                    loop {
                        let _e3348 = local_650;
                        if (_e3348 < 32i) {
                        } else {
                            break;
                        }
                        let _e3350 = local_650;
                        let _e3351 = local_801;
                        if (_e3350 >= _e3351) {
                            break;
                        }
                        let _e3353 = local_650;
                        let _e3355 = local_802[_e3353];
                        if !((abs(_e3355) <= 340282300000000000000000000000000000000f)) {
                            local_645 = true;
                        } else {
                            let _e3359 = local_650;
                            let _e3361 = local_803[_e3359];
                            local_645 = !((abs(_e3361) <= 340282300000000000000000000000000000000f));
                        }
                        let _e3365 = local_645;
                        if _e3365 {
                            local_801 = 0i;
                            local_643 = true;
                            local_644 = false;
                            break;
                        }
                        let _e3366 = local_650;
                        local_650 = (_e3366 + 1i);
                        continue;
                    }
                    let _e3368 = local_643;
                    if _e3368 {
                        break;
                    }
                    local_643 = true;
                    local_644 = true;
                    break;
                }
            }
            let _e3369 = local_644;
            let _e3370 = local_801;
            local_783 = _e3370;
            let _e3371 = local_802;
            local_169 = _e3371[0];
            local_168 = _e3371[1];
            local_167 = _e3371[2];
            local_166 = _e3371[3];
            local_165 = _e3371[4];
            local_164 = _e3371[5];
            local_163 = _e3371[6];
            local_162 = _e3371[7];
            local_161 = _e3371[8];
            local_160 = _e3371[9];
            local_159 = _e3371[10];
            local_158 = _e3371[11];
            local_157 = _e3371[12];
            local_156 = _e3371[13];
            local_155 = _e3371[14];
            local_154 = _e3371[15];
            local_153 = _e3371[16];
            local_152 = _e3371[17];
            local_151 = _e3371[18];
            local_150 = _e3371[19];
            local_149 = _e3371[20];
            local_148 = _e3371[21];
            local_147 = _e3371[22];
            local_146 = _e3371[23];
            local_145 = _e3371[24];
            local_144 = _e3371[25];
            local_143 = _e3371[26];
            local_142 = _e3371[27];
            local_141 = _e3371[28];
            local_140 = _e3371[29];
            local_139 = _e3371[30];
            local_138 = _e3371[31];
            let _e3404 = local_803;
            local_137 = _e3404[0];
            local_136 = _e3404[1];
            local_135 = _e3404[2];
            local_134 = _e3404[3];
            local_133 = _e3404[4];
            local_132 = _e3404[5];
            local_131 = _e3404[6];
            local_130 = _e3404[7];
            local_129 = _e3404[8];
            local_128 = _e3404[9];
            local_127 = _e3404[10];
            local_126 = _e3404[11];
            local_125 = _e3404[12];
            local_124 = _e3404[13];
            local_123 = _e3404[14];
            local_122 = _e3404[15];
            local_121 = _e3404[16];
            local_120 = _e3404[17];
            local_119 = _e3404[18];
            local_118 = _e3404[19];
            local_117 = _e3404[20];
            local_116 = _e3404[21];
            local_115 = _e3404[22];
            local_114 = _e3404[23];
            local_113 = _e3404[24];
            local_112 = _e3404[25];
            local_111 = _e3404[26];
            local_110 = _e3404[27];
            local_109 = _e3404[28];
            local_108 = _e3404[29];
            local_107 = _e3404[30];
            local_106 = _e3404[31];
            if !(_e3369) {
                local_783 = 0i;
            }
            let _e3438 = local_783;
            local_804 = _e3438;
            let _e3439 = local_138;
            let _e3440 = local_139;
            let _e3441 = local_140;
            let _e3442 = local_141;
            let _e3443 = local_142;
            let _e3444 = local_143;
            let _e3445 = local_144;
            let _e3446 = local_145;
            let _e3447 = local_146;
            let _e3448 = local_147;
            let _e3449 = local_148;
            let _e3450 = local_149;
            let _e3451 = local_150;
            let _e3452 = local_151;
            let _e3453 = local_152;
            let _e3454 = local_153;
            let _e3455 = local_154;
            let _e3456 = local_155;
            let _e3457 = local_156;
            let _e3458 = local_157;
            let _e3459 = local_158;
            let _e3460 = local_159;
            let _e3461 = local_160;
            let _e3462 = local_161;
            let _e3463 = local_162;
            let _e3464 = local_163;
            let _e3465 = local_164;
            let _e3466 = local_165;
            let _e3467 = local_166;
            let _e3468 = local_167;
            let _e3469 = local_168;
            let _e3470 = local_169;
            local_805 = array<f32, 32>(_e3470, _e3469, _e3468, _e3467, _e3466, _e3465, _e3464, _e3463, _e3462, _e3461, _e3460, _e3459, _e3458, _e3457, _e3456, _e3455, _e3454, _e3453, _e3452, _e3451, _e3450, _e3449, _e3448, _e3447, _e3446, _e3445, _e3444, _e3443, _e3442, _e3441, _e3440, _e3439);
            let _e3472 = local_106;
            let _e3473 = local_107;
            let _e3474 = local_108;
            let _e3475 = local_109;
            let _e3476 = local_110;
            let _e3477 = local_111;
            let _e3478 = local_112;
            let _e3479 = local_113;
            let _e3480 = local_114;
            let _e3481 = local_115;
            let _e3482 = local_116;
            let _e3483 = local_117;
            let _e3484 = local_118;
            let _e3485 = local_119;
            let _e3486 = local_120;
            let _e3487 = local_121;
            let _e3488 = local_122;
            let _e3489 = local_123;
            let _e3490 = local_124;
            let _e3491 = local_125;
            let _e3492 = local_126;
            let _e3493 = local_127;
            let _e3494 = local_128;
            let _e3495 = local_129;
            let _e3496 = local_130;
            let _e3497 = local_131;
            let _e3498 = local_132;
            let _e3499 = local_133;
            let _e3500 = local_134;
            let _e3501 = local_135;
            let _e3502 = local_136;
            let _e3503 = local_137;
            local_806 = array<f32, 32>(_e3503, _e3502, _e3501, _e3500, _e3499, _e3498, _e3497, _e3496, _e3495, _e3494, _e3493, _e3492, _e3491, _e3490, _e3489, _e3488, _e3487, _e3486, _e3485, _e3484, _e3483, _e3482, _e3481, _e3480, _e3479, _e3478, _e3477, _e3476, _e3475, _e3474, _e3473, _e3472);
            let _e3505 = local_767;
            local_807 = _e3505.x;
            switch bitcast<i32>(0u) {
                default: {
                    local_808 = 1f;
                    let _e3508 = local_804;
                    if (_e3508 == 0i) {
                        let _e3510 = local_807;
                        local_578 = _e3510;
                        break;
                    }
                    let _e3511 = local_807;
                    let _e3513 = local_806[0i];
                    if (_e3511 <= _e3513) {
                        let _e3516 = local_805[0i];
                        let _e3517 = local_807;
                        let _e3520 = local_806[0i];
                        local_578 = ((_e3516 + _e3517) - _e3520);
                        break;
                    }
                    let _e3522 = local_804;
                    let _e3523 = (_e3522 - 1i);
                    local_579 = _e3523;
                    let _e3524 = local_807;
                    let _e3526 = local_806[_e3523];
                    if (_e3524 >= _e3526) {
                        let _e3528 = local_579;
                        let _e3530 = local_805[_e3528];
                        let _e3531 = local_807;
                        let _e3534 = local_806[_e3528];
                        local_578 = ((_e3530 + _e3531) - _e3534);
                        break;
                    }
                    local_580 = 0i;
                    loop {
                        let _e3536 = local_580;
                        if (_e3536 < 31i) {
                        } else {
                            local_581 = 0i;
                            break;
                        }
                        let _e3538 = local_580;
                        let _e3539 = (_e3538 + 1i);
                        local_582 = _e3539;
                        let _e3540 = local_804;
                        if (_e3539 >= _e3540) {
                            local_583 = true;
                        } else {
                            let _e3542 = local_582;
                            let _e3544 = local_806[_e3542];
                            let _e3545 = local_807;
                            local_583 = (_e3544 >= _e3545);
                        }
                        let _e3547 = local_583;
                        if _e3547 {
                            let _e3548 = local_580;
                            local_581 = _e3548;
                            break;
                        }
                        let _e3549 = local_582;
                        local_580 = _e3549;
                        continue;
                    }
                    let _e3550 = local_581;
                    let _e3551 = (_e3550 + 1i);
                    local_584 = _e3550;
                    let _e3553 = local_806[_e3551];
                    let _e3555 = local_806[_e3550];
                    let _e3556 = (_e3553 - _e3555);
                    local_585 = _e3556;
                    local_586 = _e3550;
                    let _e3558 = local_805[_e3551];
                    let _e3560 = local_805[_e3550];
                    local_587 = (_e3558 - _e3560);
                    if (abs(_e3556) > 0.000001f) {
                        let _e3564 = local_587;
                        let _e3565 = local_585;
                        local_588 = (_e3564 / _e3565);
                    } else {
                        local_588 = 1f;
                    }
                    let _e3567 = local_588;
                    local_808 = _e3567;
                    let _e3568 = local_586;
                    let _e3570 = local_805[_e3568];
                    let _e3571 = local_807;
                    let _e3572 = local_584;
                    let _e3574 = local_806[_e3572];
                    local_578 = (_e3570 + ((_e3571 - _e3574) * _e3567));
                    break;
                }
            }
            let _e3578 = local_578;
            let _e3579 = local_808;
            local_786 = _e3579;
            let _e3580 = local_767;
            local_767 = vec2<f32>(_e3578, _e3580.y);
        }
        let _e3584 = local_778;
        if _e3584 {
            let _e3585 = local_789;
            local_778 = _e3585;
        } else {
            local_778 = false;
        }
        let _e3586 = local_778;
        if _e3586 {
            local_809 = 1i;
            let _e3587 = local_779;
            local_810 = _e3587;
            let _e3588 = local_771;
            local_811 = _e3588;
            let _e3589 = local_791;
            local_812 = _e3589;
            local_813 = 0f;
            let _e3590 = local_770;
            local_814 = _e3590;
            let _e3591 = local_185;
            let _e3592 = local_186;
            let _e3593 = local_187;
            let _e3594 = local_188;
            let _e3595 = local_189;
            let _e3596 = local_190;
            let _e3597 = local_191;
            let _e3598 = local_192;
            let _e3599 = local_193;
            let _e3600 = local_194;
            let _e3601 = local_195;
            let _e3602 = local_196;
            let _e3603 = local_197;
            let _e3604 = local_198;
            let _e3605 = local_199;
            local_26 = _e3605;
            local_25 = _e3604;
            local_24 = _e3603;
            local_23 = _e3602;
            local_22 = _e3601;
            local_21 = _e3600;
            local_20 = _e3599;
            local_19 = _e3598;
            local_18 = _e3597;
            local_17 = _e3596;
            local_16 = _e3595;
            local_15 = _e3594;
            local_14 = _e3593;
            local_13 = _e3592;
            local_12 = _e3591;
            local_504 = false;
            switch bitcast<i32>(0u) {
                default: {
                    local_815 = 0i;
                    let _e3607 = local_814;
                    if !((abs(_e3607) <= 340282300000000000000000000000000000000f)) {
                        local_506 = true;
                    } else {
                        let _e3611 = local_814;
                        local_506 = (_e3611 <= 0f);
                    }
                    let _e3613 = local_506;
                    if _e3613 {
                        local_506 = true;
                    } else {
                        let _e3614 = local_811;
                        local_506 = (_e3614 < 0i);
                    }
                    let _e3616 = local_506;
                    if _e3616 {
                        local_506 = true;
                    } else {
                        let _e3617 = local_811;
                        local_506 = (_e3617 > 32i);
                    }
                    let _e3619 = local_506;
                    if _e3619 {
                        local_506 = true;
                    } else {
                        let _e3620 = local_812;
                        local_506 = !((abs(_e3620) <= 340282300000000000000000000000000000000f));
                    }
                    let _e3624 = local_506;
                    if _e3624 {
                        local_506 = true;
                    } else {
                        let _e3625 = local_812;
                        local_506 = (_e3625 < 0f);
                    }
                    let _e3627 = local_506;
                    if _e3627 {
                        local_504 = true;
                        local_505 = false;
                        break;
                    }
                    let _e3628 = local_809;
                    let _e3629 = (_e3628 == 0i);
                    local_507 = _e3629;
                    if _e3629 {
                        let _e3630 = local_26;
                        local_506 = (_e3630 == 0i);
                    } else {
                        local_506 = false;
                    }
                    let _e3632 = local_506;
                    if _e3632 {
                        let _e3633 = local_25;
                        local_506 = (_e3633 == 0i);
                    } else {
                        local_506 = false;
                    }
                    let _e3635 = local_506;
                    if _e3635 {
                        let _e3636 = local_24;
                        local_506 = (_e3636 == 0i);
                    } else {
                        local_506 = false;
                    }
                    let _e3638 = local_506;
                    if _e3638 {
                        let _e3639 = local_23;
                        local_506 = (_e3639 == 0i);
                    } else {
                        local_506 = false;
                    }
                    let _e3641 = local_506;
                    if _e3641 {
                        local_506 = true;
                    } else {
                        let _e3642 = local_809;
                        if (_e3642 == 1i) {
                            let _e3644 = local_22;
                            local_506 = (_e3644 == 0i);
                        } else {
                            local_506 = false;
                        }
                        let _e3646 = local_506;
                        if _e3646 {
                            let _e3647 = local_21;
                            local_506 = (_e3647 == 0i);
                        } else {
                            local_506 = false;
                        }
                        let _e3649 = local_506;
                        if _e3649 {
                            let _e3650 = local_20;
                            local_506 = (_e3650 == 0i);
                        } else {
                            local_506 = false;
                        }
                    }
                    let _e3652 = local_506;
                    if _e3652 {
                        local_504 = true;
                        local_505 = true;
                        break;
                    }
                    let _e3653 = local_810;
                    let _e3654 = (_e3653 + 0i);
                    let _e3657 = v_info_0_1;
                    let _e3658 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e3661 = local_500;
                    let _e3664 = vec2<i32>(vec2<i32>(_e3658).x, _e3661.y);
                    let _e3665 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e3670 = vec2<i32>(_e3664.x, vec2<i32>(_e3665).y);
                    local_500 = _e3670;
                    let _e3676 = (((_e3657.y * _e3670.x) + _e3657.x) + (_e3654 >> bitcast<u32>(2i)));
                    let _e3685 = vec2<i32>((_e3676 - (i32(floor((f32(_e3676) / f32(_e3670.x)))) * _e3670.x)), (_e3676 / _e3670.x));
                    let _e3688 = vec3<i32>(_e3685.x, _e3685.y, 0i);
                    let _e3691 = textureLoad(u_layer_tex_0_image, _e3688.xy, _e3688.z);
                    local_501 = _e3691;
                    let _e3692 = (_e3654 & 3i);
                    local_502 = _e3692;
                    if (_e3692 == 0i) {
                        let _e3694 = local_501;
                        local_503 = _e3694.x;
                    } else {
                        let _e3696 = local_502;
                        if (_e3696 == 1i) {
                            let _e3698 = local_501;
                            local_503 = _e3698.y;
                        } else {
                            let _e3700 = local_502;
                            if (_e3700 == 2i) {
                                let _e3702 = local_501;
                                local_503 = _e3702.z;
                            } else {
                                let _e3704 = local_501;
                                local_503 = _e3704.w;
                            }
                        }
                    }
                    let _e3706 = local_503;
                    let _e3707 = i32(_e3706);
                    local_508 = _e3707;
                    if (_e3707 <= 0i) {
                        local_506 = true;
                    } else {
                        let _e3709 = local_508;
                        local_506 = (_e3709 > 32i);
                    }
                    let _e3711 = local_506;
                    if _e3711 {
                        let _e3712 = local_508;
                        local_504 = true;
                        local_505 = (_e3712 == 0i);
                        break;
                    }
                    let _e3714 = local_809;
                    let _e3715 = (_e3714 == 1i);
                    local_509 = _e3715;
                    if _e3715 {
                        let _e3716 = local_22;
                        local_506 = (_e3716 == 2i);
                    } else {
                        local_506 = false;
                    }
                    let _e3718 = local_507;
                    if _e3718 {
                        let _e3719 = local_23;
                        local_510 = (_e3719 == 1i);
                    } else {
                        local_510 = false;
                    }
                    let _e3721 = local_510;
                    if _e3721 {
                        let _e3722 = local_813;
                        local_510 = !((abs(_e3722) <= 340282300000000000000000000000000000000f));
                    } else {
                        local_510 = false;
                    }
                    let _e3726 = local_510;
                    if _e3726 {
                        local_504 = true;
                        local_505 = false;
                        break;
                    }
                    local_511 = 0i;
                    loop {
                        let _e3727 = local_511;
                        if (_e3727 < 32i) {
                        } else {
                            break;
                        }
                        let _e3729 = local_511;
                        let _e3730 = local_508;
                        if (_e3729 >= _e3730) {
                            break;
                        }
                        let _e3732 = local_810;
                        let _e3734 = local_511;
                        let _e3736 = ((_e3732 + 1i) + (4i * _e3734));
                        local_512 = _e3736;
                        let _e3737 = (_e3736 + 0i);
                        let _e3740 = v_info_0_1;
                        let _e3741 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3744 = local_496;
                        let _e3747 = vec2<i32>(vec2<i32>(_e3741).x, _e3744.y);
                        let _e3748 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3753 = vec2<i32>(_e3747.x, vec2<i32>(_e3748).y);
                        local_496 = _e3753;
                        let _e3759 = (((_e3740.y * _e3753.x) + _e3740.x) + (_e3737 >> bitcast<u32>(2i)));
                        let _e3768 = vec2<i32>((_e3759 - (i32(floor((f32(_e3759) / f32(_e3753.x)))) * _e3753.x)), (_e3759 / _e3753.x));
                        let _e3771 = vec3<i32>(_e3768.x, _e3768.y, 0i);
                        let _e3774 = textureLoad(u_layer_tex_0_image, _e3771.xy, _e3771.z);
                        local_497 = _e3774;
                        let _e3775 = (_e3737 & 3i);
                        local_498 = _e3775;
                        if (_e3775 == 0i) {
                            let _e3777 = local_497;
                            local_499 = _e3777.x;
                        } else {
                            let _e3779 = local_498;
                            if (_e3779 == 1i) {
                                let _e3781 = local_497;
                                local_499 = _e3781.y;
                            } else {
                                let _e3783 = local_498;
                                if (_e3783 == 2i) {
                                    let _e3785 = local_497;
                                    local_499 = _e3785.z;
                                } else {
                                    let _e3787 = local_497;
                                    local_499 = _e3787.w;
                                }
                            }
                        }
                        let _e3789 = local_499;
                        local_513 = _e3789;
                        let _e3790 = local_511;
                        local_514[_e3790] = _e3789;
                        let _e3792 = local_512;
                        let _e3793 = (_e3792 + 1i);
                        let _e3796 = v_info_0_1;
                        let _e3797 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3800 = local_492;
                        let _e3803 = vec2<i32>(vec2<i32>(_e3797).x, _e3800.y);
                        let _e3804 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3809 = vec2<i32>(_e3803.x, vec2<i32>(_e3804).y);
                        local_492 = _e3809;
                        let _e3815 = (((_e3796.y * _e3809.x) + _e3796.x) + (_e3793 >> bitcast<u32>(2i)));
                        let _e3824 = vec2<i32>((_e3815 - (i32(floor((f32(_e3815) / f32(_e3809.x)))) * _e3809.x)), (_e3815 / _e3809.x));
                        let _e3827 = vec3<i32>(_e3824.x, _e3824.y, 0i);
                        let _e3830 = textureLoad(u_layer_tex_0_image, _e3827.xy, _e3827.z);
                        local_493 = _e3830;
                        let _e3831 = (_e3793 & 3i);
                        local_494 = _e3831;
                        if (_e3831 == 0i) {
                            let _e3833 = local_493;
                            local_495 = _e3833.x;
                        } else {
                            let _e3835 = local_494;
                            if (_e3835 == 1i) {
                                let _e3837 = local_493;
                                local_495 = _e3837.y;
                            } else {
                                let _e3839 = local_494;
                                if (_e3839 == 2i) {
                                    let _e3841 = local_493;
                                    local_495 = _e3841.z;
                                } else {
                                    let _e3843 = local_493;
                                    local_495 = _e3843.w;
                                }
                            }
                        }
                        let _e3845 = local_495;
                        let _e3846 = local_511;
                        local_515[_e3846] = _e3845;
                        let _e3848 = local_512;
                        let _e3849 = (_e3848 + 2i);
                        let _e3852 = v_info_0_1;
                        let _e3853 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3856 = local_488;
                        let _e3859 = vec2<i32>(vec2<i32>(_e3853).x, _e3856.y);
                        let _e3860 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3865 = vec2<i32>(_e3859.x, vec2<i32>(_e3860).y);
                        local_488 = _e3865;
                        let _e3871 = (((_e3852.y * _e3865.x) + _e3852.x) + (_e3849 >> bitcast<u32>(2i)));
                        let _e3880 = vec2<i32>((_e3871 - (i32(floor((f32(_e3871) / f32(_e3865.x)))) * _e3865.x)), (_e3871 / _e3865.x));
                        let _e3883 = vec3<i32>(_e3880.x, _e3880.y, 0i);
                        let _e3886 = textureLoad(u_layer_tex_0_image, _e3883.xy, _e3883.z);
                        local_489 = _e3886;
                        let _e3887 = (_e3849 & 3i);
                        local_490 = _e3887;
                        if (_e3887 == 0i) {
                            let _e3889 = local_489;
                            local_491 = _e3889.x;
                        } else {
                            let _e3891 = local_490;
                            if (_e3891 == 1i) {
                                let _e3893 = local_489;
                                local_491 = _e3893.y;
                            } else {
                                let _e3895 = local_490;
                                if (_e3895 == 2i) {
                                    let _e3897 = local_489;
                                    local_491 = _e3897.z;
                                } else {
                                    let _e3899 = local_489;
                                    local_491 = _e3899.w;
                                }
                            }
                        }
                        let _e3901 = local_491;
                        let _e3902 = bitcast<u32>(_e3901);
                        let _e3903 = local_511;
                        local_516[_e3903] = (bitcast<i32>((_e3902 << bitcast<u32>(16u))) >> bitcast<u32>(16i));
                        local_517[_e3903] = (bitcast<i32>(_e3902) >> bitcast<u32>(16i));
                        let _e3914 = local_512;
                        let _e3915 = (_e3914 + 3i);
                        let _e3918 = v_info_0_1;
                        let _e3919 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3922 = local_484;
                        let _e3925 = vec2<i32>(vec2<i32>(_e3919).x, _e3922.y);
                        let _e3926 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e3931 = vec2<i32>(_e3925.x, vec2<i32>(_e3926).y);
                        local_484 = _e3931;
                        let _e3937 = (((_e3918.y * _e3931.x) + _e3918.x) + (_e3915 >> bitcast<u32>(2i)));
                        let _e3946 = vec2<i32>((_e3937 - (i32(floor((f32(_e3937) / f32(_e3931.x)))) * _e3931.x)), (_e3937 / _e3931.x));
                        let _e3949 = vec3<i32>(_e3946.x, _e3946.y, 0i);
                        let _e3952 = textureLoad(u_layer_tex_0_image, _e3949.xy, _e3949.z);
                        local_485 = _e3952;
                        let _e3953 = (_e3915 & 3i);
                        local_486 = _e3953;
                        if (_e3953 == 0i) {
                            let _e3955 = local_485;
                            local_487 = _e3955.x;
                        } else {
                            let _e3957 = local_486;
                            if (_e3957 == 1i) {
                                let _e3959 = local_485;
                                local_487 = _e3959.y;
                            } else {
                                let _e3961 = local_486;
                                if (_e3961 == 2i) {
                                    let _e3963 = local_485;
                                    local_487 = _e3963.z;
                                } else {
                                    let _e3965 = local_485;
                                    local_487 = _e3965.w;
                                }
                            }
                        }
                        let _e3967 = local_487;
                        let _e3968 = bitcast<u32>(_e3967);
                        let _e3969 = local_511;
                        local_518[_e3969] = ((_e3968 & 1u) != 0u);
                        local_519[_e3969] = ((_e3968 & 2u) != 0u);
                        local_520[_e3969] = ((_e3968 & 4u) != 0u);
                        local_521[_e3969] = ((_e3968 & 8u) != 0u);
                        local_522[_e3969] = bitcast<i32>(((_e3968 >> bitcast<u32>(4u)) & 63u));
                        local_523[_e3969] = bitcast<i32>(((_e3968 >> bitcast<u32>(10u)) & 63u));
                        local_524[_e3969] = false;
                        let _e3993 = local_513;
                        if !((abs(_e3993) <= 340282300000000000000000000000000000000f)) {
                            local_510 = true;
                        } else {
                            let _e3997 = local_511;
                            let _e3999 = local_515[_e3997];
                            local_510 = !((abs(_e3999) <= 340282300000000000000000000000000000000f));
                        }
                        let _e4003 = local_510;
                        if _e4003 {
                            local_525 = true;
                        } else {
                            let _e4004 = local_511;
                            let _e4006 = local_515[_e4004];
                            local_525 = (_e4006 < 0f);
                        }
                        let _e4008 = local_525;
                        if _e4008 {
                            local_526 = true;
                        } else {
                            let _e4009 = local_511;
                            let _e4011 = local_516[_e4009];
                            local_526 = (_e4011 < -1i);
                        }
                        let _e4013 = local_526;
                        if _e4013 {
                            local_527 = true;
                        } else {
                            let _e4014 = local_511;
                            let _e4016 = local_516[_e4014];
                            let _e4017 = local_508;
                            local_527 = (_e4016 >= _e4017);
                        }
                        let _e4019 = local_527;
                        if _e4019 {
                            local_528 = true;
                        } else {
                            let _e4020 = local_511;
                            let _e4022 = local_517[_e4020];
                            local_528 = (_e4022 < -1i);
                        }
                        let _e4024 = local_528;
                        if _e4024 {
                            local_529 = true;
                        } else {
                            let _e4025 = local_511;
                            let _e4027 = local_517[_e4025];
                            let _e4028 = local_811;
                            local_529 = (_e4027 >= _e4028);
                        }
                        let _e4030 = local_529;
                        if _e4030 {
                            local_504 = true;
                            local_505 = false;
                            break;
                        }
                        let _e4031 = local_511;
                        local_511 = (_e4031 + 1i);
                        continue;
                    }
                    let _e4033 = local_504;
                    if _e4033 {
                        break;
                    }
                    local_511 = 0i;
                    loop {
                        let _e4034 = local_511;
                        if (_e4034 < 32i) {
                        } else {
                            break;
                        }
                        let _e4036 = local_511;
                        let _e4037 = local_811;
                        if (_e4036 >= _e4037) {
                            break;
                        }
                        let _e4039 = local_511;
                        let _e4040 = (2i * _e4039);
                        local_530 = _e4040;
                        let _e4041 = (12i + _e4040);
                        let _e4044 = v_info_0_1;
                        let _e4045 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e4048 = local_480;
                        let _e4051 = vec2<i32>(vec2<i32>(_e4045).x, _e4048.y);
                        let _e4052 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e4057 = vec2<i32>(_e4051.x, vec2<i32>(_e4052).y);
                        local_480 = _e4057;
                        let _e4063 = (((_e4044.y * _e4057.x) + _e4044.x) + (_e4041 >> bitcast<u32>(2i)));
                        let _e4072 = vec2<i32>((_e4063 - (i32(floor((f32(_e4063) / f32(_e4057.x)))) * _e4057.x)), (_e4063 / _e4057.x));
                        let _e4075 = vec3<i32>(_e4072.x, _e4072.y, 0i);
                        let _e4078 = textureLoad(u_layer_tex_0_image, _e4075.xy, _e4075.z);
                        local_481 = _e4078;
                        let _e4079 = (_e4041 & 3i);
                        local_482 = _e4079;
                        if (_e4079 == 0i) {
                            let _e4081 = local_481;
                            local_483 = _e4081.x;
                        } else {
                            let _e4083 = local_482;
                            if (_e4083 == 1i) {
                                let _e4085 = local_481;
                                local_483 = _e4085.y;
                            } else {
                                let _e4087 = local_482;
                                if (_e4087 == 2i) {
                                    let _e4089 = local_481;
                                    local_483 = _e4089.z;
                                } else {
                                    let _e4091 = local_481;
                                    local_483 = _e4091.w;
                                }
                            }
                        }
                        let _e4093 = local_483;
                        local_531 = _e4093;
                        let _e4094 = local_530;
                        let _e4096 = (12i + (_e4094 + 1i));
                        let _e4099 = v_info_0_1;
                        let _e4100 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e4103 = local_476;
                        let _e4106 = vec2<i32>(vec2<i32>(_e4100).x, _e4103.y);
                        let _e4107 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e4112 = vec2<i32>(_e4106.x, vec2<i32>(_e4107).y);
                        local_476 = _e4112;
                        let _e4118 = (((_e4099.y * _e4112.x) + _e4099.x) + (_e4096 >> bitcast<u32>(2i)));
                        let _e4127 = vec2<i32>((_e4118 - (i32(floor((f32(_e4118) / f32(_e4112.x)))) * _e4112.x)), (_e4118 / _e4112.x));
                        let _e4130 = vec3<i32>(_e4127.x, _e4127.y, 0i);
                        let _e4133 = textureLoad(u_layer_tex_0_image, _e4130.xy, _e4130.z);
                        local_477 = _e4133;
                        let _e4134 = (_e4096 & 3i);
                        local_478 = _e4134;
                        if (_e4134 == 0i) {
                            let _e4136 = local_477;
                            local_479 = _e4136.x;
                        } else {
                            let _e4138 = local_478;
                            if (_e4138 == 1i) {
                                let _e4140 = local_477;
                                local_479 = _e4140.y;
                            } else {
                                let _e4142 = local_478;
                                if (_e4142 == 2i) {
                                    let _e4144 = local_477;
                                    local_479 = _e4144.z;
                                } else {
                                    let _e4146 = local_477;
                                    local_479 = _e4146.w;
                                }
                            }
                        }
                        let _e4148 = local_479;
                        local_532 = _e4148;
                        let _e4149 = local_531;
                        if !((abs(_e4149) <= 340282300000000000000000000000000000000f)) {
                            local_510 = true;
                        } else {
                            let _e4153 = local_532;
                            local_510 = !((abs(_e4153) <= 340282300000000000000000000000000000000f));
                        }
                        let _e4157 = local_510;
                        if _e4157 {
                            local_504 = true;
                            local_505 = false;
                            break;
                        }
                        let _e4158 = local_511;
                        local_511 = (_e4158 + 1i);
                        continue;
                    }
                    let _e4160 = local_504;
                    if _e4160 {
                        break;
                    }
                    local_511 = 0i;
                    loop {
                        let _e4161 = local_511;
                        if (_e4161 < 32i) {
                        } else {
                            break;
                        }
                        let _e4163 = local_511;
                        let _e4164 = local_508;
                        if (_e4163 >= _e4164) {
                            break;
                        }
                        let _e4166 = local_511;
                        let _e4168 = local_516[_e4166];
                        if (_e4168 >= 0i) {
                            let _e4170 = local_511;
                            let _e4172 = local_516[_e4170];
                            local_533 = _e4172;
                            let _e4174 = local_516[_e4170];
                            let _e4175 = local_508;
                            if (_e4174 >= _e4175) {
                                local_510 = true;
                            } else {
                                let _e4177 = local_533;
                                let _e4178 = local_511;
                                local_510 = (_e4177 == _e4178);
                            }
                            let _e4180 = local_510;
                            if _e4180 {
                                local_525 = true;
                            } else {
                                let _e4181 = local_533;
                                let _e4183 = local_516[_e4181];
                                let _e4184 = local_511;
                                local_525 = (_e4183 != _e4184);
                            }
                            let _e4186 = local_525;
                            if _e4186 {
                                local_526 = true;
                            } else {
                                let _e4187 = local_533;
                                let _e4189 = local_514[_e4187];
                                local_526 = !((abs(_e4189) <= 340282300000000000000000000000000000000f));
                            }
                            let _e4193 = local_526;
                            if _e4193 {
                                local_527 = true;
                            } else {
                                let _e4194 = local_533;
                                let _e4196 = local_514[_e4194];
                                let _e4197 = local_511;
                                let _e4199 = local_514[_e4197];
                                local_527 = (_e4196 == _e4199);
                            }
                            let _e4201 = local_527;
                            if _e4201 {
                                local_528 = true;
                            } else {
                                let _e4202 = local_533;
                                let _e4204 = local_515[_e4202];
                                local_528 = !((abs(_e4204) <= 340282300000000000000000000000000000000f));
                            }
                            let _e4208 = local_528;
                            if _e4208 {
                                local_529 = true;
                            } else {
                                let _e4209 = local_533;
                                let _e4211 = local_515[_e4209];
                                let _e4212 = local_511;
                                let _e4214 = local_515[_e4212];
                                local_529 = (_e4211 != _e4214);
                            }
                            let _e4216 = local_529;
                            if _e4216 {
                                local_504 = true;
                                local_505 = false;
                                break;
                            }
                        }
                        let _e4217 = local_511;
                        local_511 = (_e4217 + 1i);
                        continue;
                    }
                    let _e4219 = local_504;
                    if _e4219 {
                        break;
                    }
                    let _e4220 = local_509;
                    if _e4220 {
                        let _e4221 = local_20;
                        local_510 = (_e4221 == 1i);
                    } else {
                        local_510 = false;
                    }
                    let _e4223 = local_510;
                    if _e4223 {
                        let _e4224 = local_12;
                        local_534 = _e4224;
                    } else {
                        local_534 = 0f;
                    }
                    local_511 = 0i;
                    loop {
                        let _e4225 = local_511;
                        if (_e4225 < 32i) {
                        } else {
                            break;
                        }
                        let _e4227 = local_511;
                        let _e4228 = local_508;
                        if (_e4227 >= _e4228) {
                            break;
                        }
                        let _e4230 = local_511;
                        let _e4232 = local_516[_e4230];
                        if (_e4232 >= 0i) {
                            let _e4234 = local_511;
                            let _e4236 = local_516[_e4234];
                            let _e4238 = local_514[_e4236];
                            let _e4240 = local_514[_e4234];
                            local_510 = (_e4238 > _e4240);
                        } else {
                            local_510 = false;
                        }
                        let _e4242 = local_506;
                        if _e4242 {
                            let _e4243 = local_511;
                            let _e4245 = local_517[_e4243];
                            local_525 = (_e4245 >= 0i);
                        } else {
                            local_525 = false;
                        }
                        let _e4247 = local_525;
                        if _e4247 {
                            let _e4248 = local_511;
                            let _e4250 = local_517[_e4248];
                            let _e4253 = (12i + ((2i * _e4250) + 1i));
                            let _e4256 = v_info_0_1;
                            let _e4257 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4260 = local_472;
                            let _e4263 = vec2<i32>(vec2<i32>(_e4257).x, _e4260.y);
                            let _e4264 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4269 = vec2<i32>(_e4263.x, vec2<i32>(_e4264).y);
                            local_472 = _e4269;
                            let _e4275 = (((_e4256.y * _e4269.x) + _e4256.x) + (_e4253 >> bitcast<u32>(2i)));
                            let _e4284 = vec2<i32>((_e4275 - (i32(floor((f32(_e4275) / f32(_e4269.x)))) * _e4269.x)), (_e4275 / _e4269.x));
                            let _e4287 = vec3<i32>(_e4284.x, _e4284.y, 0i);
                            let _e4290 = textureLoad(u_layer_tex_0_image, _e4287.xy, _e4287.z);
                            local_473 = _e4290;
                            let _e4291 = (_e4253 & 3i);
                            local_474 = _e4291;
                            if (_e4291 == 0i) {
                                let _e4293 = local_473;
                                local_475 = _e4293.x;
                            } else {
                                let _e4295 = local_474;
                                if (_e4295 == 1i) {
                                    let _e4297 = local_473;
                                    local_475 = _e4297.y;
                                } else {
                                    let _e4299 = local_474;
                                    if (_e4299 == 2i) {
                                        let _e4301 = local_473;
                                        local_475 = _e4301.z;
                                    } else {
                                        let _e4303 = local_473;
                                        local_475 = _e4303.w;
                                    }
                                }
                            }
                            let _e4305 = local_475;
                            local_535 = _e4305;
                            let _e4306 = local_511;
                            let _e4308 = local_517[_e4306];
                            let _e4310 = (12i + (2i * _e4308));
                            let _e4313 = v_info_0_1;
                            let _e4314 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4317 = local_468;
                            let _e4320 = vec2<i32>(vec2<i32>(_e4314).x, _e4317.y);
                            let _e4321 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4326 = vec2<i32>(_e4320.x, vec2<i32>(_e4321).y);
                            local_468 = _e4326;
                            let _e4332 = (((_e4313.y * _e4326.x) + _e4313.x) + (_e4310 >> bitcast<u32>(2i)));
                            let _e4341 = vec2<i32>((_e4332 - (i32(floor((f32(_e4332) / f32(_e4326.x)))) * _e4326.x)), (_e4332 / _e4326.x));
                            let _e4344 = vec3<i32>(_e4341.x, _e4341.y, 0i);
                            let _e4347 = textureLoad(u_layer_tex_0_image, _e4344.xy, _e4344.z);
                            local_469 = _e4347;
                            let _e4348 = (_e4310 & 3i);
                            local_470 = _e4348;
                            if (_e4348 == 0i) {
                                let _e4350 = local_469;
                                local_471 = _e4350.x;
                            } else {
                                let _e4352 = local_470;
                                if (_e4352 == 1i) {
                                    let _e4354 = local_469;
                                    local_471 = _e4354.y;
                                } else {
                                    let _e4356 = local_470;
                                    if (_e4356 == 2i) {
                                        let _e4358 = local_469;
                                        local_471 = _e4358.z;
                                    } else {
                                        let _e4360 = local_469;
                                        local_471 = _e4360.w;
                                    }
                                }
                            }
                            let _e4362 = local_471;
                            let _e4363 = local_535;
                            local_526 = (_e4363 < _e4362);
                        } else {
                            local_526 = false;
                        }
                        let _e4365 = local_511;
                        let _e4367 = local_520[_e4365];
                        if !(_e4367) {
                            let _e4369 = local_511;
                            let _e4371 = local_516[_e4369];
                            local_527 = (_e4371 < 0i);
                        } else {
                            local_527 = false;
                        }
                        let _e4373 = local_527;
                        if _e4373 {
                            let _e4374 = local_525;
                            local_528 = !(_e4374);
                        } else {
                            local_528 = false;
                        }
                        let _e4376 = local_528;
                        if _e4376 {
                            let _e4377 = local_506;
                            local_529 = _e4377;
                        } else {
                            local_529 = false;
                        }
                        let _e4378 = local_529;
                        if _e4378 {
                            local_536 = 340282350000000000000000000000000000000f;
                            local_537 = 1i;
                            local_538 = 0i;
                            loop {
                                let _e4379 = local_538;
                                if (_e4379 < 32i) {
                                } else {
                                    break;
                                }
                                let _e4381 = local_538;
                                let _e4382 = local_508;
                                if (_e4381 >= _e4382) {
                                    break;
                                }
                                let _e4384 = local_538;
                                let _e4386 = local_517[_e4384];
                                if (_e4386 < 0i) {
                                    let _e4388 = local_538;
                                    local_538 = (_e4388 + 1i);
                                    continue;
                                }
                                let _e4390 = local_538;
                                let _e4392 = local_514[_e4390];
                                let _e4393 = local_511;
                                let _e4395 = local_514[_e4393];
                                let _e4397 = abs((_e4392 - _e4395));
                                local_539 = _e4397;
                                let _e4398 = local_536;
                                if (_e4397 >= _e4398) {
                                    let _e4400 = local_538;
                                    local_538 = (_e4400 + 1i);
                                    continue;
                                }
                                let _e4402 = local_538;
                                let _e4404 = local_517[_e4402];
                                let _e4407 = (12i + ((2i * _e4404) + 1i));
                                let _e4410 = v_info_0_1;
                                let _e4411 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e4414 = local_464;
                                let _e4417 = vec2<i32>(vec2<i32>(_e4411).x, _e4414.y);
                                let _e4418 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e4423 = vec2<i32>(_e4417.x, vec2<i32>(_e4418).y);
                                local_464 = _e4423;
                                let _e4429 = (((_e4410.y * _e4423.x) + _e4410.x) + (_e4407 >> bitcast<u32>(2i)));
                                let _e4438 = vec2<i32>((_e4429 - (i32(floor((f32(_e4429) / f32(_e4423.x)))) * _e4423.x)), (_e4429 / _e4423.x));
                                let _e4441 = vec3<i32>(_e4438.x, _e4438.y, 0i);
                                let _e4444 = textureLoad(u_layer_tex_0_image, _e4441.xy, _e4441.z);
                                local_465 = _e4444;
                                let _e4445 = (_e4407 & 3i);
                                local_466 = _e4445;
                                if (_e4445 == 0i) {
                                    let _e4447 = local_465;
                                    local_467 = _e4447.x;
                                } else {
                                    let _e4449 = local_466;
                                    if (_e4449 == 1i) {
                                        let _e4451 = local_465;
                                        local_467 = _e4451.y;
                                    } else {
                                        let _e4453 = local_466;
                                        if (_e4453 == 2i) {
                                            let _e4455 = local_465;
                                            local_467 = _e4455.z;
                                        } else {
                                            let _e4457 = local_465;
                                            local_467 = _e4457.w;
                                        }
                                    }
                                }
                                let _e4459 = local_467;
                                local_540 = _e4459;
                                let _e4460 = local_538;
                                let _e4462 = local_517[_e4460];
                                let _e4464 = (12i + (2i * _e4462));
                                let _e4467 = v_info_0_1;
                                let _e4468 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e4471 = local_460;
                                let _e4474 = vec2<i32>(vec2<i32>(_e4468).x, _e4471.y);
                                let _e4475 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e4480 = vec2<i32>(_e4474.x, vec2<i32>(_e4475).y);
                                local_460 = _e4480;
                                let _e4486 = (((_e4467.y * _e4480.x) + _e4467.x) + (_e4464 >> bitcast<u32>(2i)));
                                let _e4495 = vec2<i32>((_e4486 - (i32(floor((f32(_e4486) / f32(_e4480.x)))) * _e4480.x)), (_e4486 / _e4480.x));
                                let _e4498 = vec3<i32>(_e4495.x, _e4495.y, 0i);
                                let _e4501 = textureLoad(u_layer_tex_0_image, _e4498.xy, _e4498.z);
                                local_461 = _e4501;
                                let _e4502 = (_e4464 & 3i);
                                local_462 = _e4502;
                                if (_e4502 == 0i) {
                                    let _e4504 = local_461;
                                    local_463 = _e4504.x;
                                } else {
                                    let _e4506 = local_462;
                                    if (_e4506 == 1i) {
                                        let _e4508 = local_461;
                                        local_463 = _e4508.y;
                                    } else {
                                        let _e4510 = local_462;
                                        if (_e4510 == 2i) {
                                            let _e4512 = local_461;
                                            local_463 = _e4512.z;
                                        } else {
                                            let _e4514 = local_461;
                                            local_463 = _e4514.w;
                                        }
                                    }
                                }
                                let _e4516 = local_463;
                                let _e4517 = local_540;
                                if (_e4517 < _e4516) {
                                    local_541 = 1i;
                                } else {
                                    local_541 = -1i;
                                }
                                let _e4519 = local_539;
                                local_536 = _e4519;
                                let _e4520 = local_541;
                                local_537 = _e4520;
                                let _e4521 = local_538;
                                local_538 = (_e4521 + 1i);
                                continue;
                            }
                        } else {
                            local_537 = 1i;
                        }
                        let _e4523 = local_511;
                        let _e4525 = local_520[_e4523];
                        if _e4525 {
                            let _e4526 = local_506;
                            if _e4526 {
                                let _e4527 = local_511;
                                let _e4529 = local_521[_e4527];
                                local_542 = _e4529;
                            } else {
                                local_542 = false;
                            }
                            let _e4530 = local_542;
                            if _e4530 {
                                local_543 = true;
                            } else {
                                let _e4531 = local_506;
                                if !(_e4531) {
                                    let _e4533 = local_510;
                                    local_543 = _e4533;
                                } else {
                                    local_543 = false;
                                }
                            }
                            let _e4534 = local_543;
                            if _e4534 {
                                local_538 = -1i;
                            } else {
                                local_538 = 1i;
                            }
                        } else {
                            let _e4535 = local_510;
                            if _e4535 {
                                local_542 = true;
                            } else {
                                let _e4536 = local_526;
                                local_542 = _e4536;
                            }
                            let _e4537 = local_542;
                            if _e4537 {
                                local_538 = -1i;
                            } else {
                                let _e4538 = local_537;
                                local_538 = _e4538;
                            }
                        }
                        let _e4539 = local_511;
                        let _e4540 = local_538;
                        local_544[_e4539] = _e4540;
                        let _e4542 = local_506;
                        if _e4542 {
                            let _e4543 = local_511;
                            let _e4545 = local_523[_e4543];
                            local_541 = _e4545;
                        } else {
                            let _e4546 = local_511;
                            let _e4548 = local_522[_e4546];
                            local_541 = _e4548;
                        }
                        let _e4549 = local_511;
                        let _e4551 = local_520[_e4549];
                        if !(_e4551) {
                            local_542 = true;
                        } else {
                            let _e4553 = local_541;
                            local_542 = (_e4553 == 63i);
                        }
                        let _e4555 = local_542;
                        if _e4555 {
                            local_545 = -2i;
                        } else {
                            let _e4556 = local_541;
                            if (_e4556 == 62i) {
                                local_545 = -1i;
                            } else {
                                let _e4558 = local_541;
                                local_545 = _e4558;
                            }
                        }
                        let _e4559 = local_511;
                        let _e4560 = local_545;
                        local_546[_e4559] = _e4560;
                        let _e4562 = local_525;
                        if _e4562 {
                            let _e4563 = local_511;
                            let _e4565 = local_517[_e4563];
                            let _e4567 = (12i + (2i * _e4565));
                            let _e4570 = v_info_0_1;
                            let _e4571 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4574 = local_456;
                            let _e4577 = vec2<i32>(vec2<i32>(_e4571).x, _e4574.y);
                            let _e4578 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4583 = vec2<i32>(_e4577.x, vec2<i32>(_e4578).y);
                            local_456 = _e4583;
                            let _e4589 = (((_e4570.y * _e4583.x) + _e4570.x) + (_e4567 >> bitcast<u32>(2i)));
                            let _e4598 = vec2<i32>((_e4589 - (i32(floor((f32(_e4589) / f32(_e4583.x)))) * _e4583.x)), (_e4589 / _e4583.x));
                            let _e4601 = vec3<i32>(_e4598.x, _e4598.y, 0i);
                            let _e4604 = textureLoad(u_layer_tex_0_image, _e4601.xy, _e4601.z);
                            local_457 = _e4604;
                            let _e4605 = (_e4567 & 3i);
                            local_458 = _e4605;
                            if (_e4605 == 0i) {
                                let _e4607 = local_457;
                                local_459 = _e4607.x;
                            } else {
                                let _e4609 = local_458;
                                if (_e4609 == 1i) {
                                    let _e4611 = local_457;
                                    local_459 = _e4611.y;
                                } else {
                                    let _e4613 = local_458;
                                    if (_e4613 == 2i) {
                                        let _e4615 = local_457;
                                        local_459 = _e4615.z;
                                    } else {
                                        let _e4617 = local_457;
                                        local_459 = _e4617.w;
                                    }
                                }
                            }
                            let _e4619 = local_459;
                            local_547 = _e4619;
                            let _e4620 = local_511;
                            let _e4622 = local_517[_e4620];
                            let _e4625 = (12i + ((2i * _e4622) + 1i));
                            let _e4628 = v_info_0_1;
                            let _e4629 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4632 = local_452;
                            let _e4635 = vec2<i32>(vec2<i32>(_e4629).x, _e4632.y);
                            let _e4636 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4641 = vec2<i32>(_e4635.x, vec2<i32>(_e4636).y);
                            local_452 = _e4641;
                            let _e4647 = (((_e4628.y * _e4641.x) + _e4628.x) + (_e4625 >> bitcast<u32>(2i)));
                            let _e4656 = vec2<i32>((_e4647 - (i32(floor((f32(_e4647) / f32(_e4641.x)))) * _e4641.x)), (_e4647 / _e4641.x));
                            let _e4659 = vec3<i32>(_e4656.x, _e4656.y, 0i);
                            let _e4662 = textureLoad(u_layer_tex_0_image, _e4659.xy, _e4659.z);
                            local_453 = _e4662;
                            let _e4663 = (_e4625 & 3i);
                            local_454 = _e4663;
                            if (_e4663 == 0i) {
                                let _e4665 = local_453;
                                local_455 = _e4665.x;
                            } else {
                                let _e4667 = local_454;
                                if (_e4667 == 1i) {
                                    let _e4669 = local_453;
                                    local_455 = _e4669.y;
                                } else {
                                    let _e4671 = local_454;
                                    if (_e4671 == 2i) {
                                        let _e4673 = local_453;
                                        local_455 = _e4673.z;
                                    } else {
                                        let _e4675 = local_453;
                                        local_455 = _e4675.w;
                                    }
                                }
                            }
                            let _e4677 = local_455;
                            local_548 = _e4677;
                            let _e4678 = local_511;
                            let _e4680 = local_518[_e4678];
                            if _e4680 {
                                let _e4681 = local_509;
                                local_543 = _e4681;
                            } else {
                                local_543 = false;
                            }
                            let _e4682 = local_543;
                            if _e4682 {
                                let _e4683 = local_20;
                                local_549 = (_e4683 == 0i);
                            } else {
                                local_549 = false;
                            }
                            let _e4685 = local_549;
                            if _e4685 {
                                let _e4686 = local_511;
                                let _e4688 = local_514[_e4686];
                                local_550[_e4686] = _e4688;
                            } else {
                                let _e4690 = local_511;
                                let _e4691 = local_547;
                                let _e4692 = local_814;
                                local_550[_e4690] = (round((_e4691 * _e4692)) / _e4692);
                                let _e4698 = local_518[_e4690];
                                if _e4698 {
                                    let _e4699 = local_548;
                                    let _e4700 = local_547;
                                    let _e4702 = local_814;
                                    let _e4705 = local_534;
                                    local_551 = (abs(((_e4699 - _e4700) * _e4702)) >= _e4705);
                                } else {
                                    local_551 = false;
                                }
                                let _e4707 = local_551;
                                if _e4707 {
                                    let _e4708 = local_511;
                                    let _e4710 = local_550[_e4708];
                                    let _e4711 = local_548;
                                    let _e4712 = local_547;
                                    local_550[_e4708] = (_e4710 + (_e4711 - _e4712));
                                }
                            }
                        } else {
                            let _e4716 = local_511;
                            let _e4718 = local_514[_e4716];
                            let _e4719 = local_814;
                            local_550[_e4716] = (round((_e4718 * _e4719)) / _e4719);
                        }
                        let _e4724 = local_511;
                        local_511 = (_e4724 + 1i);
                        continue;
                    }
                    let _e4726 = local_814;
                    local_552 = (1f / _e4726);
                    let _e4728 = local_507;
                    if _e4728 {
                        let _e4729 = local_25;
                        local_537 = _e4729;
                    } else {
                        let _e4730 = local_21;
                        local_537 = _e4730;
                    }
                    let _e4731 = local_507;
                    if _e4731 {
                        let _e4732 = local_16;
                        local_534 = _e4732;
                    } else {
                        let _e4733 = local_14;
                        local_534 = _e4733;
                    }
                    let _e4734 = local_507;
                    if _e4734 {
                        let _e4735 = local_15;
                        local_536 = _e4735;
                    } else {
                        let _e4736 = local_13;
                        local_536 = _e4736;
                    }
                    let _e4737 = local_507;
                    if _e4737 {
                        let _e4738 = local_26;
                        local_506 = (_e4738 == 1i);
                    } else {
                        let _e4740 = local_22;
                        local_506 = (_e4740 != 0i);
                    }
                    let _e4742 = local_507;
                    if _e4742 {
                        let _e4743 = local_24;
                        local_510 = (_e4743 == 1i);
                    } else {
                        local_510 = false;
                    }
                    local_525 = false;
                    local_553 = 0f;
                    local_554 = 0f;
                    local_555 = 0f;
                    local_556 = 0f;
                    local_557 = 0f;
                    local_538 = 0i;
                    local_511 = 0i;
                    local_541 = 0i;
                    loop {
                        let _e4745 = local_511;
                        if (_e4745 < 32i) {
                        } else {
                            break;
                        }
                        let _e4747 = local_511;
                        let _e4748 = local_508;
                        if (_e4747 >= _e4748) {
                            break;
                        }
                        let _e4750 = local_511;
                        let _e4752 = local_516[_e4750];
                        local_558 = _e4752;
                        let _e4754 = local_516[_e4750];
                        if (_e4754 < 0i) {
                            local_526 = true;
                        } else {
                            let _e4756 = local_558;
                            let _e4757 = local_511;
                            local_526 = (_e4756 <= _e4757);
                        }
                        let _e4759 = local_526;
                        if _e4759 {
                            let _e4760 = local_525;
                            local_528 = _e4760;
                            let _e4761 = local_511;
                            local_511 = (_e4761 + 1i);
                            continue;
                        }
                        let _e4763 = local_511;
                        let _e4765 = local_515[_e4763];
                        local_560 = _e4765;
                        let _e4766 = local_812;
                        local_561 = _e4766;
                        let _e4767 = local_534;
                        local_562 = _e4767;
                        if (_e4766 > 0f) {
                            let _e4769 = local_560;
                            let _e4770 = local_561;
                            let _e4773 = local_562;
                            local_450 = (abs((_e4769 - _e4770)) <= (_e4773 * _e4770));
                        } else {
                            local_450 = false;
                        }
                        let _e4776 = local_450;
                        if _e4776 {
                            let _e4777 = local_561;
                            local_451 = _e4777;
                        } else {
                            let _e4778 = local_560;
                            local_451 = _e4778;
                        }
                        let _e4779 = local_451;
                        local_559 = _e4779;
                        let _e4780 = local_511;
                        let _e4782 = local_515[_e4780];
                        local_563 = _e4782;
                        let _e4783 = local_537;
                        if (_e4783 == 2i) {
                            local_527 = true;
                        } else {
                            let _e4785 = local_537;
                            if (_e4785 == 1i) {
                                let _e4787 = local_559;
                                let _e4788 = local_814;
                                let _e4790 = local_536;
                                local_527 = ((_e4787 * _e4788) < _e4790);
                            } else {
                                local_527 = false;
                            }
                        }
                        let _e4792 = local_527;
                        if _e4792 {
                            let _e4793 = local_559;
                            let _e4794 = local_814;
                            let _e4798 = local_552;
                            local_564 = (max(round((_e4793 * _e4794)), 1f) * _e4798);
                        } else {
                            let _e4800 = local_563;
                            local_564 = _e4800;
                        }
                        let _e4801 = local_510;
                        if _e4801 {
                            let _e4802 = local_525;
                            if _e4802 {
                                let _e4803 = local_511;
                                let _e4804 = local_553;
                                let _e4806 = local_514[_e4803];
                                let _e4807 = local_554;
                                let _e4809 = local_814;
                                let _e4812 = local_552;
                                local_550[_e4803] = (_e4804 + (round(((_e4806 - _e4807) * _e4809)) * _e4812));
                                let _e4816 = local_555;
                                local_565 = _e4816;
                                let _e4817 = local_556;
                                local_566 = _e4817;
                                let _e4818 = local_525;
                                local_528 = _e4818;
                            } else {
                                let _e4819 = local_511;
                                let _e4821 = local_514[_e4819];
                                let _e4822 = local_814;
                                let _e4825 = (round((_e4821 * _e4822)) / _e4822);
                                local_550[_e4819] = _e4825;
                                local_565 = _e4825;
                                let _e4828 = local_514[_e4819];
                                local_566 = _e4828;
                                local_528 = true;
                            }
                            let _e4829 = local_558;
                            let _e4830 = local_511;
                            let _e4832 = local_550[_e4830];
                            let _e4833 = local_564;
                            local_550[_e4829] = (_e4832 + _e4833);
                            let _e4836 = local_565;
                            let _e4838 = local_514[_e4830];
                            let _e4839 = local_566;
                            let _e4841 = local_814;
                            let _e4844 = local_552;
                            let _e4848 = local_541;
                            let _e4851 = local_550[_e4830];
                            local_565 = _e4851;
                            let _e4853 = local_514[_e4830];
                            local_566 = _e4853;
                            local_567 = _e4836;
                            local_568 = _e4839;
                            local_569 = ((_e4836 + (round(((_e4838 - _e4839) * _e4841)) * _e4844)) + _e4833);
                            local_545 = _e4829;
                            local_570 = (_e4848 + 1i);
                        } else {
                            let _e4854 = local_507;
                            if _e4854 {
                                let _e4855 = local_26;
                                local_528 = (_e4855 != 0i);
                            } else {
                                let _e4857 = local_22;
                                local_528 = (_e4857 != 0i);
                            }
                            let _e4859 = local_528;
                            if _e4859 {
                                let _e4860 = local_511;
                                let _e4862 = local_517[_e4860];
                                local_529 = (_e4862 >= 0i);
                            } else {
                                local_529 = false;
                            }
                            let _e4864 = local_528;
                            if _e4864 {
                                let _e4865 = local_558;
                                let _e4867 = local_517[_e4865];
                                local_542 = (_e4867 >= 0i);
                            } else {
                                local_542 = false;
                            }
                            let _e4869 = local_506;
                            if !(_e4869) {
                                let _e4871 = local_511;
                                let _e4873 = local_514[_e4871];
                                local_550[_e4871] = _e4873;
                            }
                            let _e4875 = local_542;
                            if _e4875 {
                                let _e4876 = local_529;
                                local_543 = !(_e4876);
                            } else {
                                local_543 = false;
                            }
                            let _e4878 = local_543;
                            if _e4878 {
                                let _e4879 = local_506;
                                local_549 = _e4879;
                            } else {
                                local_549 = false;
                            }
                            let _e4880 = local_549;
                            if _e4880 {
                                let _e4881 = local_511;
                                let _e4882 = local_558;
                                let _e4884 = local_550[_e4882];
                                let _e4885 = local_564;
                                local_550[_e4881] = (_e4884 - _e4885);
                            } else {
                                let _e4888 = local_558;
                                let _e4889 = local_511;
                                let _e4891 = local_550[_e4889];
                                let _e4892 = local_564;
                                local_550[_e4888] = (_e4891 + _e4892);
                            }
                            let _e4895 = local_525;
                            local_528 = _e4895;
                            let _e4896 = local_553;
                            local_565 = _e4896;
                            let _e4897 = local_554;
                            local_566 = _e4897;
                            let _e4898 = local_555;
                            local_567 = _e4898;
                            let _e4899 = local_556;
                            local_568 = _e4899;
                            let _e4900 = local_557;
                            local_569 = _e4900;
                            let _e4901 = local_538;
                            local_545 = _e4901;
                            let _e4902 = local_541;
                            local_570 = _e4902;
                        }
                        let _e4903 = local_511;
                        local_524[_e4903] = true;
                        let _e4905 = local_558;
                        local_524[_e4905] = true;
                        let _e4907 = local_565;
                        local_553 = _e4907;
                        let _e4908 = local_566;
                        local_554 = _e4908;
                        let _e4909 = local_567;
                        local_555 = _e4909;
                        let _e4910 = local_568;
                        local_556 = _e4910;
                        let _e4911 = local_569;
                        local_557 = _e4911;
                        let _e4912 = local_545;
                        local_538 = _e4912;
                        let _e4913 = local_570;
                        local_541 = _e4913;
                        let _e4915 = local_528;
                        local_525 = _e4915;
                        local_511 = (_e4903 + 1i);
                        continue;
                    }
                    let _e4916 = local_510;
                    if _e4916 {
                        let _e4917 = local_541;
                        local_506 = (_e4917 > 1i);
                    } else {
                        local_506 = false;
                    }
                    let _e4919 = local_506;
                    if _e4919 {
                        let _e4920 = local_557;
                        let _e4921 = local_538;
                        let _e4923 = local_550[_e4921];
                        local_571 = (_e4920 - _e4923);
                        local_511 = 0i;
                        loop {
                            let _e4925 = local_511;
                            if (_e4925 < 32i) {
                            } else {
                                break;
                            }
                            let _e4927 = local_511;
                            let _e4928 = local_508;
                            if (_e4927 >= _e4928) {
                                break;
                            }
                            let _e4930 = local_511;
                            let _e4932 = local_524[_e4930];
                            if _e4932 {
                                let _e4933 = local_511;
                                let _e4935 = local_550[_e4933];
                                let _e4936 = local_571;
                                local_550[_e4933] = (_e4935 + _e4936);
                            }
                            let _e4939 = local_511;
                            local_511 = (_e4939 + 1i);
                            continue;
                        }
                    }
                    let _e4941 = local_537;
                    if (_e4941 == 1i) {
                        let _e4943 = local_536;
                        local_534 = _e4943;
                    } else {
                        local_534 = 1.6f;
                    }
                    local_511 = 0i;
                    loop {
                        let _e4944 = local_511;
                        if (_e4944 < 32i) {
                        } else {
                            break;
                        }
                        let _e4946 = local_511;
                        let _e4947 = local_508;
                        if (_e4946 >= _e4947) {
                            break;
                        }
                        let _e4949 = local_507;
                        if _e4949 {
                            let _e4950 = local_26;
                            local_528 = (_e4950 != 0i);
                        } else {
                            let _e4952 = local_22;
                            local_528 = (_e4952 != 0i);
                        }
                        let _e4954 = local_528;
                        if !(_e4954) {
                            local_506 = true;
                        } else {
                            let _e4956 = local_511;
                            let _e4958 = local_517[_e4956];
                            local_506 = (_e4958 < 0i);
                        }
                        let _e4960 = local_506;
                        if _e4960 {
                            local_510 = true;
                        } else {
                            let _e4961 = local_511;
                            let _e4963 = local_518[_e4961];
                            local_510 = !(_e4963);
                        }
                        let _e4965 = local_510;
                        if _e4965 {
                            local_525 = true;
                        } else {
                            let _e4966 = local_511;
                            let _e4968 = local_524[_e4966];
                            local_525 = _e4968;
                        }
                        let _e4969 = local_525;
                        if _e4969 {
                            let _e4970 = local_511;
                            local_511 = (_e4970 + 1i);
                            continue;
                        }
                        let _e4972 = local_511;
                        let _e4974 = local_544[_e4972];
                        local_572 = (_e4974 > 0i);
                        let _e4977 = local_546[_e4972];
                        local_573 = _e4977;
                        let _e4979 = local_546[_e4972];
                        if (_e4979 >= 0i) {
                            let _e4981 = local_572;
                            if _e4981 {
                                let _e4982 = local_511;
                                let _e4984 = local_514[_e4982];
                                let _e4985 = local_573;
                                let _e4987 = local_514[_e4985];
                                local_536 = (_e4984 - _e4987);
                            } else {
                                let _e4989 = local_573;
                                let _e4991 = local_514[_e4989];
                                let _e4992 = local_511;
                                let _e4994 = local_514[_e4992];
                                local_536 = (_e4991 - _e4994);
                            }
                            let _e4996 = local_573;
                            local_545 = _e4996;
                            let _e4997 = local_536;
                            local_564 = _e4997;
                        } else {
                            let _e4998 = local_573;
                            if (_e4998 == -2i) {
                                local_564 = 340282350000000000000000000000000000000f;
                                let _e5000 = local_573;
                                local_545 = _e5000;
                                local_570 = 0i;
                                loop {
                                    let _e5001 = local_570;
                                    if (_e5001 < 32i) {
                                    } else {
                                        break;
                                    }
                                    let _e5003 = local_570;
                                    let _e5004 = local_508;
                                    if (_e5003 >= _e5004) {
                                        break;
                                    }
                                    let _e5006 = local_570;
                                    let _e5007 = local_511;
                                    if (_e5006 == _e5007) {
                                        local_526 = true;
                                    } else {
                                        let _e5009 = local_570;
                                        let _e5011 = local_544[_e5009];
                                        let _e5012 = local_511;
                                        let _e5014 = local_544[_e5012];
                                        local_526 = (_e5011 == _e5014);
                                    }
                                    let _e5016 = local_526;
                                    if _e5016 {
                                        let _e5017 = local_570;
                                        local_570 = (_e5017 + 1i);
                                        continue;
                                    }
                                    let _e5019 = local_572;
                                    if _e5019 {
                                        let _e5020 = local_511;
                                        let _e5022 = local_514[_e5020];
                                        let _e5023 = local_570;
                                        let _e5025 = local_514[_e5023];
                                        local_565 = (_e5022 - _e5025);
                                    } else {
                                        let _e5027 = local_570;
                                        let _e5029 = local_514[_e5027];
                                        let _e5030 = local_511;
                                        let _e5032 = local_514[_e5030];
                                        local_565 = (_e5029 - _e5032);
                                    }
                                    let _e5034 = local_565;
                                    if (_e5034 <= 0f) {
                                        local_527 = true;
                                    } else {
                                        let _e5036 = local_565;
                                        let _e5037 = local_564;
                                        local_527 = (_e5036 >= _e5037);
                                    }
                                    let _e5039 = local_527;
                                    if _e5039 {
                                        let _e5040 = local_570;
                                        local_570 = (_e5040 + 1i);
                                        continue;
                                    }
                                    let _e5042 = local_565;
                                    local_564 = _e5042;
                                    let _e5043 = local_570;
                                    local_545 = _e5043;
                                    local_570 = (_e5043 + 1i);
                                    continue;
                                }
                            } else {
                                let _e5045 = local_573;
                                local_545 = _e5045;
                                local_564 = 340282350000000000000000000000000000000f;
                            }
                        }
                        let _e5046 = local_545;
                        if (_e5046 < 0i) {
                            local_526 = true;
                        } else {
                            let _e5048 = local_545;
                            let _e5050 = local_524[_e5048];
                            local_526 = _e5050;
                        }
                        let _e5051 = local_526;
                        if _e5051 {
                            local_527 = true;
                        } else {
                            let _e5052 = local_545;
                            let _e5054 = local_517[_e5052];
                            local_527 = (_e5054 >= 0i);
                        }
                        let _e5056 = local_527;
                        if _e5056 {
                            local_529 = true;
                        } else {
                            let _e5057 = local_564;
                            let _e5058 = local_814;
                            let _e5060 = local_534;
                            local_529 = ((_e5057 * _e5058) >= _e5060);
                        }
                        let _e5062 = local_529;
                        if _e5062 {
                            let _e5063 = local_511;
                            local_511 = (_e5063 + 1i);
                            continue;
                        }
                        let _e5065 = local_545;
                        let _e5067 = local_519[_e5065];
                        if _e5067 {
                            let _e5068 = local_564;
                            local_565 = _e5068;
                        } else {
                            let _e5069 = local_564;
                            let _e5070 = local_814;
                            let _e5074 = local_552;
                            local_565 = (max(round((_e5069 * _e5070)), 1f) * _e5074);
                        }
                        let _e5076 = local_572;
                        if _e5076 {
                            let _e5077 = local_511;
                            let _e5079 = local_550[_e5077];
                            let _e5080 = local_565;
                            local_536 = (_e5079 - _e5080);
                        } else {
                            let _e5082 = local_511;
                            let _e5084 = local_550[_e5082];
                            let _e5085 = local_565;
                            local_536 = (_e5084 + _e5085);
                        }
                        let _e5087 = local_545;
                        let _e5088 = local_536;
                        local_550[_e5087] = _e5088;
                        local_524[_e5087] = true;
                        let _e5091 = local_511;
                        local_511 = (_e5091 + 1i);
                        continue;
                    }
                    local_511 = 0i;
                    loop {
                        let _e5093 = local_511;
                        if (_e5093 < 32i) {
                        } else {
                            break;
                        }
                        let _e5095 = local_511;
                        let _e5096 = local_508;
                        if (_e5095 >= _e5096) {
                            break;
                        }
                        let _e5098 = local_507;
                        if _e5098 {
                            let _e5099 = local_26;
                            local_528 = (_e5099 != 0i);
                        } else {
                            let _e5101 = local_22;
                            local_528 = (_e5101 != 0i);
                        }
                        let _e5103 = local_511;
                        let _e5105 = local_524[_e5103];
                        if !(_e5105) {
                            let _e5107 = local_528;
                            if _e5107 {
                                let _e5108 = local_511;
                                let _e5110 = local_517[_e5108];
                                local_506 = (_e5110 >= 0i);
                            } else {
                                local_506 = false;
                            }
                            let _e5112 = local_506;
                            local_506 = !(_e5112);
                        } else {
                            local_506 = false;
                        }
                        let _e5114 = local_506;
                        if _e5114 {
                            let _e5115 = local_511;
                            local_511 = (_e5115 + 1i);
                            continue;
                        }
                        let _e5117 = local_815;
                        let _e5118 = local_511;
                        let _e5120 = local_514[_e5118];
                        local_816[_e5117] = _e5120;
                        let _e5123 = local_550[_e5118];
                        local_817[_e5117] = _e5123;
                        let _e5125 = local_528;
                        if _e5125 {
                            let _e5126 = local_511;
                            let _e5128 = local_517[_e5126];
                            local_510 = (_e5128 >= 0i);
                        } else {
                            local_510 = false;
                        }
                        let _e5130 = local_815;
                        let _e5131 = local_510;
                        local_574[_e5130] = _e5131;
                        let _e5133 = local_511;
                        let _e5135 = local_519[_e5133];
                        local_575[_e5130] = _e5135;
                        local_815 = (_e5130 + 1i);
                        local_511 = (_e5133 + 1i);
                        continue;
                    }
                    let _e5139 = local_507;
                    if _e5139 {
                        let _e5140 = local_23;
                        local_506 = (_e5140 == 1i);
                    } else {
                        local_506 = false;
                    }
                    let _e5142 = local_506;
                    if _e5142 {
                        let _e5143 = local_815;
                        local_506 = (_e5143 > 0i);
                    } else {
                        local_506 = false;
                    }
                    let _e5145 = local_506;
                    if _e5145 {
                        let _e5146 = local_815;
                        local_506 = (_e5146 < 32i);
                    } else {
                        local_506 = false;
                    }
                    let _e5148 = local_506;
                    if _e5148 {
                        let _e5149 = local_813;
                        let _e5151 = local_816[0i];
                        let _e5152 = local_552;
                        local_506 = (_e5149 < (_e5151 - (0.25f * _e5152)));
                    } else {
                        local_506 = false;
                    }
                    let _e5156 = local_506;
                    if _e5156 {
                        local_511 = 31i;
                        loop {
                            let _e5157 = local_511;
                            if (_e5157 > 0i) {
                            } else {
                                break;
                            }
                            let _e5159 = local_511;
                            let _e5160 = local_815;
                            if (_e5159 <= _e5160) {
                                let _e5162 = local_511;
                                let _e5163 = (_e5162 - 1i);
                                let _e5165 = local_816[_e5163];
                                local_816[_e5162] = _e5165;
                                let _e5168 = local_817[_e5163];
                                local_817[_e5162] = _e5168;
                                let _e5171 = local_574[_e5163];
                                local_574[_e5162] = _e5171;
                                let _e5174 = local_575[_e5163];
                                local_575[_e5162] = _e5174;
                            }
                            let _e5176 = local_511;
                            local_511 = (_e5176 - 1i);
                            continue;
                        }
                        let _e5178 = local_813;
                        local_816[0i] = _e5178;
                        let _e5180 = local_814;
                        local_817[0i] = (round((_e5178 * _e5180)) / _e5180);
                        local_574[0i] = false;
                        local_575[0i] = false;
                        let _e5187 = local_815;
                        local_815 = (_e5187 + 1i);
                    }
                    local_545 = 31i;
                    loop {
                        let _e5189 = local_545;
                        if (_e5189 > 0i) {
                        } else {
                            break;
                        }
                        let _e5191 = local_545;
                        let _e5192 = local_815;
                        if (_e5191 >= _e5192) {
                            local_506 = true;
                        } else {
                            let _e5194 = local_545;
                            let _e5196 = local_574[_e5194];
                            local_506 = !(_e5196);
                        }
                        let _e5198 = local_506;
                        if _e5198 {
                            let _e5199 = local_545;
                            local_545 = (_e5199 - 1i);
                            continue;
                        }
                        local_570 = 31i;
                        loop {
                            let _e5201 = local_570;
                            if (_e5201 > 0i) {
                            } else {
                                break;
                            }
                            let _e5203 = local_570;
                            let _e5204 = local_545;
                            if (_e5203 > _e5204) {
                                let _e5206 = local_570;
                                local_570 = (_e5206 - 1i);
                                continue;
                            }
                            let _e5208 = local_570;
                            let _e5209 = (_e5208 - 1i);
                            local_576 = _e5209;
                            let _e5211 = local_574[_e5209];
                            if _e5211 {
                                break;
                            }
                            let _e5212 = local_576;
                            let _e5214 = local_575[_e5212];
                            if _e5214 {
                                local_534 = 0.000001f;
                            } else {
                                let _e5215 = local_552;
                                local_534 = _e5215;
                            }
                            let _e5216 = local_576;
                            let _e5218 = local_817[_e5216];
                            let _e5219 = local_570;
                            let _e5221 = local_817[_e5219];
                            let _e5222 = local_534;
                            local_817[_e5216] = min(_e5218, (_e5221 - _e5222));
                            local_570 = (_e5219 - 1i);
                            continue;
                        }
                        let _e5227 = local_545;
                        local_545 = (_e5227 - 1i);
                        continue;
                    }
                    local_511 = 1i;
                    loop {
                        let _e5229 = local_511;
                        if (_e5229 < 32i) {
                        } else {
                            break;
                        }
                        let _e5231 = local_511;
                        let _e5232 = local_815;
                        if (_e5231 >= _e5232) {
                            break;
                        }
                        let _e5234 = local_511;
                        let _e5236 = local_817[_e5234];
                        let _e5239 = local_817[(_e5234 - 1i)];
                        if (_e5236 <= _e5239) {
                            let _e5241 = local_511;
                            let _e5244 = local_817[(_e5241 - 1i)];
                            let _e5245 = local_552;
                            local_817[_e5241] = (_e5244 + _e5245);
                        }
                        let _e5248 = local_511;
                        local_511 = (_e5248 + 1i);
                        continue;
                    }
                    let _e5250 = local_19;
                    if (_e5250 != 0i) {
                        let _e5252 = local_814;
                        let _e5253 = local_18;
                        local_506 = (_e5252 > _e5253);
                    } else {
                        local_506 = false;
                    }
                    let _e5255 = local_506;
                    if _e5255 {
                        let _e5256 = local_17;
                        let _e5257 = local_18;
                        let _e5258 = (_e5256 - _e5257);
                        local_577 = _e5258;
                        if (_e5258 <= 0f) {
                            local_506 = true;
                        } else {
                            let _e5260 = local_814;
                            let _e5261 = local_17;
                            local_506 = (_e5260 >= _e5261);
                        }
                        let _e5263 = local_506;
                        if _e5263 {
                            local_534 = 1f;
                        } else {
                            let _e5264 = local_814;
                            let _e5265 = local_18;
                            let _e5267 = local_577;
                            local_534 = ((_e5264 - _e5265) / _e5267);
                        }
                        local_511 = 0i;
                        loop {
                            let _e5269 = local_511;
                            if (_e5269 < 32i) {
                            } else {
                                break;
                            }
                            let _e5271 = local_511;
                            let _e5272 = local_815;
                            if (_e5271 >= _e5272) {
                                break;
                            }
                            let _e5274 = local_511;
                            let _e5276 = local_817[_e5274];
                            let _e5278 = local_816[_e5274];
                            let _e5280 = local_817[_e5274];
                            let _e5282 = local_534;
                            local_817[_e5274] = (_e5276 + ((_e5278 - _e5280) * _e5282));
                            local_511 = (_e5274 + 1i);
                            continue;
                        }
                    }
                    local_511 = 0i;
                    loop {
                        let _e5287 = local_511;
                        if (_e5287 < 32i) {
                        } else {
                            break;
                        }
                        let _e5289 = local_511;
                        let _e5290 = local_815;
                        if (_e5289 >= _e5290) {
                            break;
                        }
                        let _e5292 = local_511;
                        let _e5294 = local_816[_e5292];
                        if !((abs(_e5294) <= 340282300000000000000000000000000000000f)) {
                            local_506 = true;
                        } else {
                            let _e5298 = local_511;
                            let _e5300 = local_817[_e5298];
                            local_506 = !((abs(_e5300) <= 340282300000000000000000000000000000000f));
                        }
                        let _e5304 = local_506;
                        if _e5304 {
                            local_815 = 0i;
                            local_504 = true;
                            local_505 = false;
                            break;
                        }
                        let _e5305 = local_511;
                        local_511 = (_e5305 + 1i);
                        continue;
                    }
                    let _e5307 = local_504;
                    if _e5307 {
                        break;
                    }
                    local_504 = true;
                    local_505 = true;
                    break;
                }
            }
            let _e5308 = local_505;
            let _e5309 = local_815;
            local_785 = _e5309;
            let _e5310 = local_816;
            local_90 = _e5310[0];
            local_89 = _e5310[1];
            local_88 = _e5310[2];
            local_87 = _e5310[3];
            local_86 = _e5310[4];
            local_85 = _e5310[5];
            local_84 = _e5310[6];
            local_83 = _e5310[7];
            local_82 = _e5310[8];
            local_81 = _e5310[9];
            local_80 = _e5310[10];
            local_79 = _e5310[11];
            local_78 = _e5310[12];
            local_77 = _e5310[13];
            local_76 = _e5310[14];
            local_75 = _e5310[15];
            local_74 = _e5310[16];
            local_73 = _e5310[17];
            local_72 = _e5310[18];
            local_71 = _e5310[19];
            local_70 = _e5310[20];
            local_69 = _e5310[21];
            local_68 = _e5310[22];
            local_67 = _e5310[23];
            local_66 = _e5310[24];
            local_65 = _e5310[25];
            local_64 = _e5310[26];
            local_63 = _e5310[27];
            local_62 = _e5310[28];
            local_61 = _e5310[29];
            local_60 = _e5310[30];
            local_59 = _e5310[31];
            let _e5343 = local_817;
            local_58 = _e5343[0];
            local_57 = _e5343[1];
            local_56 = _e5343[2];
            local_55 = _e5343[3];
            local_54 = _e5343[4];
            local_53 = _e5343[5];
            local_52 = _e5343[6];
            local_51 = _e5343[7];
            local_50 = _e5343[8];
            local_49 = _e5343[9];
            local_48 = _e5343[10];
            local_47 = _e5343[11];
            local_46 = _e5343[12];
            local_45 = _e5343[13];
            local_44 = _e5343[14];
            local_43 = _e5343[15];
            local_42 = _e5343[16];
            local_41 = _e5343[17];
            local_40 = _e5343[18];
            local_39 = _e5343[19];
            local_38 = _e5343[20];
            local_37 = _e5343[21];
            local_36 = _e5343[22];
            local_35 = _e5343[23];
            local_34 = _e5343[24];
            local_33 = _e5343[25];
            local_32 = _e5343[26];
            local_31 = _e5343[27];
            local_30 = _e5343[28];
            local_29 = _e5343[29];
            local_28 = _e5343[30];
            local_27 = _e5343[31];
            if !(_e5308) {
                local_785 = 0i;
            }
            let _e5377 = local_785;
            local_818 = _e5377;
            let _e5378 = local_59;
            let _e5379 = local_60;
            let _e5380 = local_61;
            let _e5381 = local_62;
            let _e5382 = local_63;
            let _e5383 = local_64;
            let _e5384 = local_65;
            let _e5385 = local_66;
            let _e5386 = local_67;
            let _e5387 = local_68;
            let _e5388 = local_69;
            let _e5389 = local_70;
            let _e5390 = local_71;
            let _e5391 = local_72;
            let _e5392 = local_73;
            let _e5393 = local_74;
            let _e5394 = local_75;
            let _e5395 = local_76;
            let _e5396 = local_77;
            let _e5397 = local_78;
            let _e5398 = local_79;
            let _e5399 = local_80;
            let _e5400 = local_81;
            let _e5401 = local_82;
            let _e5402 = local_83;
            let _e5403 = local_84;
            let _e5404 = local_85;
            let _e5405 = local_86;
            let _e5406 = local_87;
            let _e5407 = local_88;
            let _e5408 = local_89;
            let _e5409 = local_90;
            local_819 = array<f32, 32>(_e5409, _e5408, _e5407, _e5406, _e5405, _e5404, _e5403, _e5402, _e5401, _e5400, _e5399, _e5398, _e5397, _e5396, _e5395, _e5394, _e5393, _e5392, _e5391, _e5390, _e5389, _e5388, _e5387, _e5386, _e5385, _e5384, _e5383, _e5382, _e5381, _e5380, _e5379, _e5378);
            let _e5411 = local_27;
            let _e5412 = local_28;
            let _e5413 = local_29;
            let _e5414 = local_30;
            let _e5415 = local_31;
            let _e5416 = local_32;
            let _e5417 = local_33;
            let _e5418 = local_34;
            let _e5419 = local_35;
            let _e5420 = local_36;
            let _e5421 = local_37;
            let _e5422 = local_38;
            let _e5423 = local_39;
            let _e5424 = local_40;
            let _e5425 = local_41;
            let _e5426 = local_42;
            let _e5427 = local_43;
            let _e5428 = local_44;
            let _e5429 = local_45;
            let _e5430 = local_46;
            let _e5431 = local_47;
            let _e5432 = local_48;
            let _e5433 = local_49;
            let _e5434 = local_50;
            let _e5435 = local_51;
            let _e5436 = local_52;
            let _e5437 = local_53;
            let _e5438 = local_54;
            let _e5439 = local_55;
            let _e5440 = local_56;
            let _e5441 = local_57;
            let _e5442 = local_58;
            local_820 = array<f32, 32>(_e5442, _e5441, _e5440, _e5439, _e5438, _e5437, _e5436, _e5435, _e5434, _e5433, _e5432, _e5431, _e5430, _e5429, _e5428, _e5427, _e5426, _e5425, _e5424, _e5423, _e5422, _e5421, _e5420, _e5419, _e5418, _e5417, _e5416, _e5415, _e5414, _e5413, _e5412, _e5411);
            let _e5444 = local_767;
            local_821 = _e5444.y;
            switch bitcast<i32>(0u) {
                default: {
                    local_822 = 1f;
                    let _e5447 = local_818;
                    if (_e5447 == 0i) {
                        let _e5449 = local_821;
                        local_439 = _e5449;
                        break;
                    }
                    let _e5450 = local_821;
                    let _e5452 = local_820[0i];
                    if (_e5450 <= _e5452) {
                        let _e5455 = local_819[0i];
                        let _e5456 = local_821;
                        let _e5459 = local_820[0i];
                        local_439 = ((_e5455 + _e5456) - _e5459);
                        break;
                    }
                    let _e5461 = local_818;
                    let _e5462 = (_e5461 - 1i);
                    local_440 = _e5462;
                    let _e5463 = local_821;
                    let _e5465 = local_820[_e5462];
                    if (_e5463 >= _e5465) {
                        let _e5467 = local_440;
                        let _e5469 = local_819[_e5467];
                        let _e5470 = local_821;
                        let _e5473 = local_820[_e5467];
                        local_439 = ((_e5469 + _e5470) - _e5473);
                        break;
                    }
                    local_441 = 0i;
                    loop {
                        let _e5475 = local_441;
                        if (_e5475 < 31i) {
                        } else {
                            local_442 = 0i;
                            break;
                        }
                        let _e5477 = local_441;
                        let _e5478 = (_e5477 + 1i);
                        local_443 = _e5478;
                        let _e5479 = local_818;
                        if (_e5478 >= _e5479) {
                            local_444 = true;
                        } else {
                            let _e5481 = local_443;
                            let _e5483 = local_820[_e5481];
                            let _e5484 = local_821;
                            local_444 = (_e5483 >= _e5484);
                        }
                        let _e5486 = local_444;
                        if _e5486 {
                            let _e5487 = local_441;
                            local_442 = _e5487;
                            break;
                        }
                        let _e5488 = local_443;
                        local_441 = _e5488;
                        continue;
                    }
                    let _e5489 = local_442;
                    let _e5490 = (_e5489 + 1i);
                    local_445 = _e5489;
                    let _e5492 = local_820[_e5490];
                    let _e5494 = local_820[_e5489];
                    let _e5495 = (_e5492 - _e5494);
                    local_446 = _e5495;
                    local_447 = _e5489;
                    let _e5497 = local_819[_e5490];
                    let _e5499 = local_819[_e5489];
                    local_448 = (_e5497 - _e5499);
                    if (abs(_e5495) > 0.000001f) {
                        let _e5503 = local_448;
                        let _e5504 = local_446;
                        local_449 = (_e5503 / _e5504);
                    } else {
                        local_449 = 1f;
                    }
                    let _e5506 = local_449;
                    local_822 = _e5506;
                    let _e5507 = local_447;
                    let _e5509 = local_819[_e5507];
                    let _e5510 = local_821;
                    let _e5511 = local_445;
                    let _e5513 = local_820[_e5511];
                    local_439 = (_e5509 + ((_e5510 - _e5513) * _e5506));
                    break;
                }
            }
            let _e5517 = local_439;
            let _e5518 = local_822;
            local_787 = _e5518;
            let _e5519 = local_767;
            local_767 = vec2<f32>(_e5519.x, _e5517);
        }
    }
    let _e5523 = local_788;
    if !(_e5523) {
        let _e5525 = local_204;
        let _e5526 = local_205;
        let _e5527 = local_206;
        let _e5528 = local_207;
        local_11 = _e5528;
        local_10 = _e5527;
        local_9 = _e5526;
        local_8 = _e5525;
        let _e5529 = (0i + 11i);
        let _e5532 = v_info_0_1;
        let _e5533 = textureDimensions(u_layer_tex_0_image, 0i);
        let _e5536 = local_435;
        let _e5539 = vec2<i32>(vec2<i32>(_e5533).x, _e5536.y);
        let _e5540 = textureDimensions(u_layer_tex_0_image, 0i);
        let _e5545 = vec2<i32>(_e5539.x, vec2<i32>(_e5540).y);
        local_435 = _e5545;
        let _e5551 = (((_e5532.y * _e5545.x) + _e5532.x) + (_e5529 >> bitcast<u32>(2i)));
        let _e5560 = vec2<i32>((_e5551 - (i32(floor((f32(_e5551) / f32(_e5545.x)))) * _e5545.x)), (_e5551 / _e5545.x));
        let _e5563 = vec3<i32>(_e5560.x, _e5560.y, 0i);
        let _e5566 = textureLoad(u_layer_tex_0_image, _e5563.xy, _e5563.z);
        local_436 = _e5566;
        let _e5567 = (_e5529 & 3i);
        local_437 = _e5567;
        if (_e5567 == 0i) {
            let _e5569 = local_436;
            local_438 = _e5569.x;
        } else {
            let _e5571 = local_437;
            if (_e5571 == 1i) {
                let _e5573 = local_436;
                local_438 = _e5573.y;
            } else {
                let _e5575 = local_437;
                if (_e5575 == 2i) {
                    let _e5577 = local_436;
                    local_438 = _e5577.z;
                } else {
                    let _e5579 = local_436;
                    local_438 = _e5579.w;
                }
            }
        }
        let _e5581 = local_438;
        let _e5582 = local_783;
        local_823 = _e5582;
        let _e5583 = local_8;
        let _e5584 = local_9;
        let _e5585 = local_10;
        let _e5586 = local_11;
        local_7 = _e5586;
        local_6 = _e5585;
        local_5 = _e5584;
        local_4 = _e5583;
        let _e5587 = v_ah_x_sources_0_1;
        local_824 = _e5587;
        let _e5588 = local_775;
        local_825 = _e5588;
        local_826 = _e5581;
        let _e5589 = local_767;
        local_827 = _e5589.x;
        switch bitcast<i32>(0u) {
            default: {
                local_828 = 1f;
                let _e5592 = local_823;
                if (_e5592 == 0i) {
                    let _e5594 = local_827;
                    local_406 = _e5594;
                    break;
                }
                let _e5595 = local_4;
                let _e5596 = local_5;
                let _e5597 = local_6;
                let _e5598 = local_7;
                local_408 = array<vec4<f32>, 4>(_e5598, _e5597, _e5596, _e5595);
                let _e5605 = local_408[(0i >> bitcast<u32>(2i))][(0i & 3i)];
                local_407 = _e5605;
                let _e5606 = local_825;
                local_410 = _e5606;
                let _e5607 = local_826;
                local_411 = _e5607;
                let _e5608 = local_824;
                local_404 = _e5608;
                let _e5612 = local_404[(0i >> bitcast<u32>(2i))];
                let _e5618 = ((_e5612 >> bitcast<u32>(bitcast<u32>(((0i & 3i) * 8i)))) & 255u);
                local_403 = _e5618;
                if (_e5618 == 32u) {
                    let _e5620 = local_411;
                    local_405 = _e5620;
                } else {
                    let _e5621 = local_410;
                    let _e5623 = local_403;
                    let _e5627 = (((_e5621 + 1i) + (4i * bitcast<i32>(_e5623))) + 0i);
                    let _e5630 = v_info_0_1;
                    let _e5631 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e5634 = local_399;
                    let _e5637 = vec2<i32>(vec2<i32>(_e5631).x, _e5634.y);
                    let _e5638 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e5643 = vec2<i32>(_e5637.x, vec2<i32>(_e5638).y);
                    local_399 = _e5643;
                    let _e5649 = (((_e5630.y * _e5643.x) + _e5630.x) + (_e5627 >> bitcast<u32>(2i)));
                    let _e5658 = vec2<i32>((_e5649 - (i32(floor((f32(_e5649) / f32(_e5643.x)))) * _e5643.x)), (_e5649 / _e5643.x));
                    let _e5661 = vec3<i32>(_e5658.x, _e5658.y, 0i);
                    let _e5664 = textureLoad(u_layer_tex_0_image, _e5661.xy, _e5661.z);
                    local_400 = _e5664;
                    let _e5665 = (_e5627 & 3i);
                    local_401 = _e5665;
                    if (_e5665 == 0i) {
                        let _e5667 = local_400;
                        local_402 = _e5667.x;
                    } else {
                        let _e5669 = local_401;
                        if (_e5669 == 1i) {
                            let _e5671 = local_400;
                            local_402 = _e5671.y;
                        } else {
                            let _e5673 = local_401;
                            if (_e5673 == 2i) {
                                let _e5675 = local_400;
                                local_402 = _e5675.z;
                            } else {
                                let _e5677 = local_400;
                                local_402 = _e5677.w;
                            }
                        }
                    }
                    let _e5679 = local_402;
                    local_405 = _e5679;
                }
                let _e5680 = local_405;
                local_409 = _e5680;
                let _e5681 = local_827;
                let _e5682 = local_407;
                if (_e5681 <= _e5682) {
                    let _e5684 = local_409;
                    let _e5685 = local_827;
                    let _e5687 = local_407;
                    local_406 = ((_e5684 + _e5685) - _e5687);
                    break;
                }
                let _e5689 = local_823;
                let _e5690 = (_e5689 - 1i);
                let _e5691 = local_4;
                let _e5692 = local_5;
                let _e5693 = local_6;
                let _e5694 = local_7;
                local_413 = array<vec4<f32>, 4>(_e5694, _e5693, _e5692, _e5691);
                let _e5701 = local_413[(_e5690 >> bitcast<u32>(2i))][(_e5690 & 3i)];
                local_412 = _e5701;
                let _e5702 = local_825;
                local_415 = _e5702;
                let _e5703 = local_826;
                local_416 = _e5703;
                let _e5704 = local_824;
                local_397 = _e5704;
                let _e5708 = local_397[(_e5690 >> bitcast<u32>(2i))];
                let _e5714 = ((_e5708 >> bitcast<u32>(bitcast<u32>(((_e5690 & 3i) * 8i)))) & 255u);
                local_396 = _e5714;
                if (_e5714 == 32u) {
                    let _e5716 = local_416;
                    local_398 = _e5716;
                } else {
                    let _e5717 = local_415;
                    let _e5719 = local_396;
                    let _e5723 = (((_e5717 + 1i) + (4i * bitcast<i32>(_e5719))) + 0i);
                    let _e5726 = v_info_0_1;
                    let _e5727 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e5730 = local_392;
                    let _e5733 = vec2<i32>(vec2<i32>(_e5727).x, _e5730.y);
                    let _e5734 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e5739 = vec2<i32>(_e5733.x, vec2<i32>(_e5734).y);
                    local_392 = _e5739;
                    let _e5745 = (((_e5726.y * _e5739.x) + _e5726.x) + (_e5723 >> bitcast<u32>(2i)));
                    let _e5754 = vec2<i32>((_e5745 - (i32(floor((f32(_e5745) / f32(_e5739.x)))) * _e5739.x)), (_e5745 / _e5739.x));
                    let _e5757 = vec3<i32>(_e5754.x, _e5754.y, 0i);
                    let _e5760 = textureLoad(u_layer_tex_0_image, _e5757.xy, _e5757.z);
                    local_393 = _e5760;
                    let _e5761 = (_e5723 & 3i);
                    local_394 = _e5761;
                    if (_e5761 == 0i) {
                        let _e5763 = local_393;
                        local_395 = _e5763.x;
                    } else {
                        let _e5765 = local_394;
                        if (_e5765 == 1i) {
                            let _e5767 = local_393;
                            local_395 = _e5767.y;
                        } else {
                            let _e5769 = local_394;
                            if (_e5769 == 2i) {
                                let _e5771 = local_393;
                                local_395 = _e5771.z;
                            } else {
                                let _e5773 = local_393;
                                local_395 = _e5773.w;
                            }
                        }
                    }
                    let _e5775 = local_395;
                    local_398 = _e5775;
                }
                let _e5776 = local_398;
                local_414 = _e5776;
                let _e5777 = local_827;
                let _e5778 = local_412;
                if (_e5777 >= _e5778) {
                    let _e5780 = local_414;
                    let _e5781 = local_827;
                    let _e5783 = local_412;
                    local_406 = ((_e5780 + _e5781) - _e5783);
                    break;
                }
                local_417 = 0i;
                loop {
                    let _e5785 = local_417;
                    if (_e5785 < 15i) {
                    } else {
                        local_418 = 0i;
                        break;
                    }
                    let _e5787 = local_417;
                    let _e5788 = (_e5787 + 1i);
                    local_419 = _e5788;
                    let _e5789 = local_823;
                    if (_e5788 >= _e5789) {
                        local_420 = true;
                    } else {
                        let _e5791 = local_4;
                        let _e5792 = local_5;
                        let _e5793 = local_6;
                        let _e5794 = local_7;
                        local_421 = array<vec4<f32>, 4>(_e5794, _e5793, _e5792, _e5791);
                        let _e5796 = local_419;
                        let _e5802 = local_421[(_e5796 >> bitcast<u32>(2i))][(_e5796 & 3i)];
                        let _e5803 = local_827;
                        local_420 = (_e5802 >= _e5803);
                    }
                    let _e5805 = local_420;
                    if _e5805 {
                        let _e5806 = local_417;
                        local_418 = _e5806;
                        break;
                    }
                    let _e5807 = local_419;
                    local_417 = _e5807;
                    continue;
                }
                let _e5808 = local_4;
                let _e5809 = local_5;
                let _e5810 = local_6;
                let _e5811 = local_7;
                local_423 = array<vec4<f32>, 4>(_e5811, _e5810, _e5809, _e5808);
                let _e5813 = local_418;
                let _e5819 = local_423[(_e5813 >> bitcast<u32>(2i))][(_e5813 & 3i)];
                local_422 = _e5819;
                let _e5820 = (_e5813 + 1i);
                local_424 = _e5820;
                local_426 = array<vec4<f32>, 4>(_e5811, _e5810, _e5809, _e5808);
                let _e5827 = local_426[(_e5820 >> bitcast<u32>(2i))][(_e5820 & 3i)];
                local_425 = _e5827;
                let _e5828 = local_825;
                local_428 = _e5828;
                let _e5829 = local_826;
                local_429 = _e5829;
                let _e5830 = local_824;
                local_390 = _e5830;
                let _e5834 = local_390[(_e5813 >> bitcast<u32>(2i))];
                let _e5840 = ((_e5834 >> bitcast<u32>(bitcast<u32>(((_e5813 & 3i) * 8i)))) & 255u);
                local_389 = _e5840;
                if (_e5840 == 32u) {
                    let _e5842 = local_429;
                    local_391 = _e5842;
                } else {
                    let _e5843 = local_428;
                    let _e5845 = local_389;
                    let _e5849 = (((_e5843 + 1i) + (4i * bitcast<i32>(_e5845))) + 0i);
                    let _e5852 = v_info_0_1;
                    let _e5853 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e5856 = local_385;
                    let _e5859 = vec2<i32>(vec2<i32>(_e5853).x, _e5856.y);
                    let _e5860 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e5865 = vec2<i32>(_e5859.x, vec2<i32>(_e5860).y);
                    local_385 = _e5865;
                    let _e5871 = (((_e5852.y * _e5865.x) + _e5852.x) + (_e5849 >> bitcast<u32>(2i)));
                    let _e5880 = vec2<i32>((_e5871 - (i32(floor((f32(_e5871) / f32(_e5865.x)))) * _e5865.x)), (_e5871 / _e5865.x));
                    let _e5883 = vec3<i32>(_e5880.x, _e5880.y, 0i);
                    let _e5886 = textureLoad(u_layer_tex_0_image, _e5883.xy, _e5883.z);
                    local_386 = _e5886;
                    let _e5887 = (_e5849 & 3i);
                    local_387 = _e5887;
                    if (_e5887 == 0i) {
                        let _e5889 = local_386;
                        local_388 = _e5889.x;
                    } else {
                        let _e5891 = local_387;
                        if (_e5891 == 1i) {
                            let _e5893 = local_386;
                            local_388 = _e5893.y;
                        } else {
                            let _e5895 = local_387;
                            if (_e5895 == 2i) {
                                let _e5897 = local_386;
                                local_388 = _e5897.z;
                            } else {
                                let _e5899 = local_386;
                                local_388 = _e5899.w;
                            }
                        }
                    }
                    let _e5901 = local_388;
                    local_391 = _e5901;
                }
                let _e5902 = local_391;
                local_427 = _e5902;
                let _e5903 = local_825;
                local_430 = _e5903;
                let _e5904 = local_826;
                local_431 = _e5904;
                let _e5905 = local_824;
                let _e5906 = local_424;
                local_383 = _e5905;
                let _e5910 = local_383[(_e5906 >> bitcast<u32>(2i))];
                let _e5916 = ((_e5910 >> bitcast<u32>(bitcast<u32>(((_e5906 & 3i) * 8i)))) & 255u);
                local_382 = _e5916;
                if (_e5916 == 32u) {
                    let _e5918 = local_431;
                    local_384 = _e5918;
                } else {
                    let _e5919 = local_430;
                    let _e5921 = local_382;
                    let _e5925 = (((_e5919 + 1i) + (4i * bitcast<i32>(_e5921))) + 0i);
                    let _e5928 = v_info_0_1;
                    let _e5929 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e5932 = local_378;
                    let _e5935 = vec2<i32>(vec2<i32>(_e5929).x, _e5932.y);
                    let _e5936 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e5941 = vec2<i32>(_e5935.x, vec2<i32>(_e5936).y);
                    local_378 = _e5941;
                    let _e5947 = (((_e5928.y * _e5941.x) + _e5928.x) + (_e5925 >> bitcast<u32>(2i)));
                    let _e5956 = vec2<i32>((_e5947 - (i32(floor((f32(_e5947) / f32(_e5941.x)))) * _e5941.x)), (_e5947 / _e5941.x));
                    let _e5959 = vec3<i32>(_e5956.x, _e5956.y, 0i);
                    let _e5962 = textureLoad(u_layer_tex_0_image, _e5959.xy, _e5959.z);
                    local_379 = _e5962;
                    let _e5963 = (_e5925 & 3i);
                    local_380 = _e5963;
                    if (_e5963 == 0i) {
                        let _e5965 = local_379;
                        local_381 = _e5965.x;
                    } else {
                        let _e5967 = local_380;
                        if (_e5967 == 1i) {
                            let _e5969 = local_379;
                            local_381 = _e5969.y;
                        } else {
                            let _e5971 = local_380;
                            if (_e5971 == 2i) {
                                let _e5973 = local_379;
                                local_381 = _e5973.z;
                            } else {
                                let _e5975 = local_379;
                                local_381 = _e5975.w;
                            }
                        }
                    }
                    let _e5977 = local_381;
                    local_384 = _e5977;
                }
                let _e5978 = local_384;
                let _e5979 = local_425;
                let _e5980 = local_422;
                let _e5981 = (_e5979 - _e5980);
                local_432 = _e5981;
                let _e5982 = local_427;
                local_433 = (_e5978 - _e5982);
                if (abs(_e5981) > 0.000001f) {
                    let _e5986 = local_433;
                    let _e5987 = local_432;
                    local_434 = (_e5986 / _e5987);
                } else {
                    local_434 = 1f;
                }
                let _e5989 = local_434;
                local_828 = _e5989;
                let _e5990 = local_427;
                let _e5991 = local_827;
                let _e5992 = local_422;
                local_406 = (_e5990 + ((_e5991 - _e5992) * _e5989));
                break;
            }
        }
        let _e5996 = local_406;
        let _e5997 = local_828;
        local_786 = _e5997;
        let _e5998 = local_767;
        local_767 = vec2<f32>(_e5996, _e5998.y);
    }
    let _e6002 = local_789;
    if !(_e6002) {
        let _e6004 = local_785;
        local_829 = _e6004;
        let _e6005 = local_208;
        let _e6006 = local_209;
        let _e6007 = local_210;
        let _e6008 = local_211;
        local_3 = _e6008;
        local_2 = _e6007;
        local_1 = _e6006;
        local = _e6005;
        let _e6009 = v_ah_y_sources_0_1;
        local_830 = _e6009;
        let _e6010 = local_779;
        local_831 = _e6010;
        local_832 = 0f;
        let _e6011 = local_767;
        local_833 = _e6011.y;
        switch bitcast<i32>(0u) {
            default: {
                local_834 = 1f;
                let _e6014 = local_829;
                if (_e6014 == 0i) {
                    let _e6016 = local_833;
                    local_349 = _e6016;
                    break;
                }
                let _e6017 = local;
                let _e6018 = local_1;
                let _e6019 = local_2;
                let _e6020 = local_3;
                local_351 = array<vec4<f32>, 4>(_e6020, _e6019, _e6018, _e6017);
                let _e6027 = local_351[(0i >> bitcast<u32>(2i))][(0i & 3i)];
                local_350 = _e6027;
                let _e6028 = local_831;
                local_353 = _e6028;
                let _e6029 = local_832;
                local_354 = _e6029;
                let _e6030 = local_830;
                local_347 = _e6030;
                let _e6034 = local_347[(0i >> bitcast<u32>(2i))];
                let _e6040 = ((_e6034 >> bitcast<u32>(bitcast<u32>(((0i & 3i) * 8i)))) & 255u);
                local_346 = _e6040;
                if (_e6040 == 32u) {
                    let _e6042 = local_354;
                    local_348 = _e6042;
                } else {
                    let _e6043 = local_353;
                    let _e6045 = local_346;
                    let _e6049 = (((_e6043 + 1i) + (4i * bitcast<i32>(_e6045))) + 0i);
                    let _e6052 = v_info_0_1;
                    let _e6053 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e6056 = local_342;
                    let _e6059 = vec2<i32>(vec2<i32>(_e6053).x, _e6056.y);
                    let _e6060 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e6065 = vec2<i32>(_e6059.x, vec2<i32>(_e6060).y);
                    local_342 = _e6065;
                    let _e6071 = (((_e6052.y * _e6065.x) + _e6052.x) + (_e6049 >> bitcast<u32>(2i)));
                    let _e6080 = vec2<i32>((_e6071 - (i32(floor((f32(_e6071) / f32(_e6065.x)))) * _e6065.x)), (_e6071 / _e6065.x));
                    let _e6083 = vec3<i32>(_e6080.x, _e6080.y, 0i);
                    let _e6086 = textureLoad(u_layer_tex_0_image, _e6083.xy, _e6083.z);
                    local_343 = _e6086;
                    let _e6087 = (_e6049 & 3i);
                    local_344 = _e6087;
                    if (_e6087 == 0i) {
                        let _e6089 = local_343;
                        local_345 = _e6089.x;
                    } else {
                        let _e6091 = local_344;
                        if (_e6091 == 1i) {
                            let _e6093 = local_343;
                            local_345 = _e6093.y;
                        } else {
                            let _e6095 = local_344;
                            if (_e6095 == 2i) {
                                let _e6097 = local_343;
                                local_345 = _e6097.z;
                            } else {
                                let _e6099 = local_343;
                                local_345 = _e6099.w;
                            }
                        }
                    }
                    let _e6101 = local_345;
                    local_348 = _e6101;
                }
                let _e6102 = local_348;
                local_352 = _e6102;
                let _e6103 = local_833;
                let _e6104 = local_350;
                if (_e6103 <= _e6104) {
                    let _e6106 = local_352;
                    let _e6107 = local_833;
                    let _e6109 = local_350;
                    local_349 = ((_e6106 + _e6107) - _e6109);
                    break;
                }
                let _e6111 = local_829;
                let _e6112 = (_e6111 - 1i);
                let _e6113 = local;
                let _e6114 = local_1;
                let _e6115 = local_2;
                let _e6116 = local_3;
                local_356 = array<vec4<f32>, 4>(_e6116, _e6115, _e6114, _e6113);
                let _e6123 = local_356[(_e6112 >> bitcast<u32>(2i))][(_e6112 & 3i)];
                local_355 = _e6123;
                let _e6124 = local_831;
                local_358 = _e6124;
                let _e6125 = local_832;
                local_359 = _e6125;
                let _e6126 = local_830;
                local_340 = _e6126;
                let _e6130 = local_340[(_e6112 >> bitcast<u32>(2i))];
                let _e6136 = ((_e6130 >> bitcast<u32>(bitcast<u32>(((_e6112 & 3i) * 8i)))) & 255u);
                local_339 = _e6136;
                if (_e6136 == 32u) {
                    let _e6138 = local_359;
                    local_341 = _e6138;
                } else {
                    let _e6139 = local_358;
                    let _e6141 = local_339;
                    let _e6145 = (((_e6139 + 1i) + (4i * bitcast<i32>(_e6141))) + 0i);
                    let _e6148 = v_info_0_1;
                    let _e6149 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e6152 = local_335;
                    let _e6155 = vec2<i32>(vec2<i32>(_e6149).x, _e6152.y);
                    let _e6156 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e6161 = vec2<i32>(_e6155.x, vec2<i32>(_e6156).y);
                    local_335 = _e6161;
                    let _e6167 = (((_e6148.y * _e6161.x) + _e6148.x) + (_e6145 >> bitcast<u32>(2i)));
                    let _e6176 = vec2<i32>((_e6167 - (i32(floor((f32(_e6167) / f32(_e6161.x)))) * _e6161.x)), (_e6167 / _e6161.x));
                    let _e6179 = vec3<i32>(_e6176.x, _e6176.y, 0i);
                    let _e6182 = textureLoad(u_layer_tex_0_image, _e6179.xy, _e6179.z);
                    local_336 = _e6182;
                    let _e6183 = (_e6145 & 3i);
                    local_337 = _e6183;
                    if (_e6183 == 0i) {
                        let _e6185 = local_336;
                        local_338 = _e6185.x;
                    } else {
                        let _e6187 = local_337;
                        if (_e6187 == 1i) {
                            let _e6189 = local_336;
                            local_338 = _e6189.y;
                        } else {
                            let _e6191 = local_337;
                            if (_e6191 == 2i) {
                                let _e6193 = local_336;
                                local_338 = _e6193.z;
                            } else {
                                let _e6195 = local_336;
                                local_338 = _e6195.w;
                            }
                        }
                    }
                    let _e6197 = local_338;
                    local_341 = _e6197;
                }
                let _e6198 = local_341;
                local_357 = _e6198;
                let _e6199 = local_833;
                let _e6200 = local_355;
                if (_e6199 >= _e6200) {
                    let _e6202 = local_357;
                    let _e6203 = local_833;
                    let _e6205 = local_355;
                    local_349 = ((_e6202 + _e6203) - _e6205);
                    break;
                }
                local_360 = 0i;
                loop {
                    let _e6207 = local_360;
                    if (_e6207 < 15i) {
                    } else {
                        local_361 = 0i;
                        break;
                    }
                    let _e6209 = local_360;
                    let _e6210 = (_e6209 + 1i);
                    local_362 = _e6210;
                    let _e6211 = local_829;
                    if (_e6210 >= _e6211) {
                        local_363 = true;
                    } else {
                        let _e6213 = local;
                        let _e6214 = local_1;
                        let _e6215 = local_2;
                        let _e6216 = local_3;
                        local_364 = array<vec4<f32>, 4>(_e6216, _e6215, _e6214, _e6213);
                        let _e6218 = local_362;
                        let _e6224 = local_364[(_e6218 >> bitcast<u32>(2i))][(_e6218 & 3i)];
                        let _e6225 = local_833;
                        local_363 = (_e6224 >= _e6225);
                    }
                    let _e6227 = local_363;
                    if _e6227 {
                        let _e6228 = local_360;
                        local_361 = _e6228;
                        break;
                    }
                    let _e6229 = local_362;
                    local_360 = _e6229;
                    continue;
                }
                let _e6230 = local;
                let _e6231 = local_1;
                let _e6232 = local_2;
                let _e6233 = local_3;
                local_366 = array<vec4<f32>, 4>(_e6233, _e6232, _e6231, _e6230);
                let _e6235 = local_361;
                let _e6241 = local_366[(_e6235 >> bitcast<u32>(2i))][(_e6235 & 3i)];
                local_365 = _e6241;
                let _e6242 = (_e6235 + 1i);
                local_367 = _e6242;
                local_369 = array<vec4<f32>, 4>(_e6233, _e6232, _e6231, _e6230);
                let _e6249 = local_369[(_e6242 >> bitcast<u32>(2i))][(_e6242 & 3i)];
                local_368 = _e6249;
                let _e6250 = local_831;
                local_371 = _e6250;
                let _e6251 = local_832;
                local_372 = _e6251;
                let _e6252 = local_830;
                local_333 = _e6252;
                let _e6256 = local_333[(_e6235 >> bitcast<u32>(2i))];
                let _e6262 = ((_e6256 >> bitcast<u32>(bitcast<u32>(((_e6235 & 3i) * 8i)))) & 255u);
                local_332 = _e6262;
                if (_e6262 == 32u) {
                    let _e6264 = local_372;
                    local_334 = _e6264;
                } else {
                    let _e6265 = local_371;
                    let _e6267 = local_332;
                    let _e6271 = (((_e6265 + 1i) + (4i * bitcast<i32>(_e6267))) + 0i);
                    let _e6274 = v_info_0_1;
                    let _e6275 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e6278 = local_328;
                    let _e6281 = vec2<i32>(vec2<i32>(_e6275).x, _e6278.y);
                    let _e6282 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e6287 = vec2<i32>(_e6281.x, vec2<i32>(_e6282).y);
                    local_328 = _e6287;
                    let _e6293 = (((_e6274.y * _e6287.x) + _e6274.x) + (_e6271 >> bitcast<u32>(2i)));
                    let _e6302 = vec2<i32>((_e6293 - (i32(floor((f32(_e6293) / f32(_e6287.x)))) * _e6287.x)), (_e6293 / _e6287.x));
                    let _e6305 = vec3<i32>(_e6302.x, _e6302.y, 0i);
                    let _e6308 = textureLoad(u_layer_tex_0_image, _e6305.xy, _e6305.z);
                    local_329 = _e6308;
                    let _e6309 = (_e6271 & 3i);
                    local_330 = _e6309;
                    if (_e6309 == 0i) {
                        let _e6311 = local_329;
                        local_331 = _e6311.x;
                    } else {
                        let _e6313 = local_330;
                        if (_e6313 == 1i) {
                            let _e6315 = local_329;
                            local_331 = _e6315.y;
                        } else {
                            let _e6317 = local_330;
                            if (_e6317 == 2i) {
                                let _e6319 = local_329;
                                local_331 = _e6319.z;
                            } else {
                                let _e6321 = local_329;
                                local_331 = _e6321.w;
                            }
                        }
                    }
                    let _e6323 = local_331;
                    local_334 = _e6323;
                }
                let _e6324 = local_334;
                local_370 = _e6324;
                let _e6325 = local_831;
                local_373 = _e6325;
                let _e6326 = local_832;
                local_374 = _e6326;
                let _e6327 = local_830;
                let _e6328 = local_367;
                local_326 = _e6327;
                let _e6332 = local_326[(_e6328 >> bitcast<u32>(2i))];
                let _e6338 = ((_e6332 >> bitcast<u32>(bitcast<u32>(((_e6328 & 3i) * 8i)))) & 255u);
                local_325 = _e6338;
                if (_e6338 == 32u) {
                    let _e6340 = local_374;
                    local_327 = _e6340;
                } else {
                    let _e6341 = local_373;
                    let _e6343 = local_325;
                    let _e6347 = (((_e6341 + 1i) + (4i * bitcast<i32>(_e6343))) + 0i);
                    let _e6350 = v_info_0_1;
                    let _e6351 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e6354 = local_321;
                    let _e6357 = vec2<i32>(vec2<i32>(_e6351).x, _e6354.y);
                    let _e6358 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e6363 = vec2<i32>(_e6357.x, vec2<i32>(_e6358).y);
                    local_321 = _e6363;
                    let _e6369 = (((_e6350.y * _e6363.x) + _e6350.x) + (_e6347 >> bitcast<u32>(2i)));
                    let _e6378 = vec2<i32>((_e6369 - (i32(floor((f32(_e6369) / f32(_e6363.x)))) * _e6363.x)), (_e6369 / _e6363.x));
                    let _e6381 = vec3<i32>(_e6378.x, _e6378.y, 0i);
                    let _e6384 = textureLoad(u_layer_tex_0_image, _e6381.xy, _e6381.z);
                    local_322 = _e6384;
                    let _e6385 = (_e6347 & 3i);
                    local_323 = _e6385;
                    if (_e6385 == 0i) {
                        let _e6387 = local_322;
                        local_324 = _e6387.x;
                    } else {
                        let _e6389 = local_323;
                        if (_e6389 == 1i) {
                            let _e6391 = local_322;
                            local_324 = _e6391.y;
                        } else {
                            let _e6393 = local_323;
                            if (_e6393 == 2i) {
                                let _e6395 = local_322;
                                local_324 = _e6395.z;
                            } else {
                                let _e6397 = local_322;
                                local_324 = _e6397.w;
                            }
                        }
                    }
                    let _e6399 = local_324;
                    local_327 = _e6399;
                }
                let _e6400 = local_327;
                let _e6401 = local_368;
                let _e6402 = local_365;
                let _e6403 = (_e6401 - _e6402);
                local_375 = _e6403;
                let _e6404 = local_370;
                local_376 = (_e6400 - _e6404);
                if (abs(_e6403) > 0.000001f) {
                    let _e6408 = local_376;
                    let _e6409 = local_375;
                    local_377 = (_e6408 / _e6409);
                } else {
                    local_377 = 1f;
                }
                let _e6411 = local_377;
                local_834 = _e6411;
                let _e6412 = local_370;
                let _e6413 = local_833;
                let _e6414 = local_365;
                local_349 = (_e6412 + ((_e6413 - _e6414) * _e6411));
                break;
            }
        }
        let _e6418 = local_349;
        let _e6419 = local_834;
        local_787 = _e6419;
        let _e6420 = local_767;
        local_767 = vec2<f32>(_e6420.x, _e6418);
    }
    let _e6424 = local_768;
    let _e6425 = local_786;
    let _e6426 = local_787;
    let _e6428 = (_e6424 * vec2<f32>(_e6425, _e6426));
    let _e6436 = local_765;
    let _e6437 = local_764;
    let _e6438 = vec2<i32>(_e6436, _e6437);
    let _e6439 = local_767;
    local_836 = _e6439;
    local_837 = vec2<f32>((1f / max(_e6428.x, 0.000015258789f)), (1f / max(_e6428.y, 0.000015258789f)));
    let _e6440 = local_763;
    local_838 = _e6440;
    let _e6441 = local_762;
    let _e6442 = local_766;
    local_839 = _e6442;
    local_287 = _e6438.y;
    let _e6449 = ((_e6439.y * _e6441.y) + _e6441.w);
    let _e6453 = max((abs((_e6428.y * _e6441.y)) * 0.5f), 0.00001f);
    let _e6456 = clamp(i32((_e6449 - _e6453)), 0i, _e6438.y);
    let _e6460 = max(_e6456, clamp(i32((_e6449 + _e6453)), 0i, _e6438.y));
    local_203 = _e6456;
    local_202 = _e6460;
    let _e6467 = ((_e6439.x * _e6441.x) + _e6441.z);
    let _e6471 = max((abs((_e6428.x * _e6441.x)) * 0.5f), 0.00001f);
    let _e6474 = clamp(i32((_e6467 - _e6471)), 0i, _e6438.x);
    local_201 = _e6474;
    local_200 = max(_e6474, clamp(i32((_e6467 + _e6471)), 0i, _e6438.x));
    local_288 = 0f;
    local_289 = 0f;
    local_290 = (_e6456 != _e6460);
    local_291 = _e6456;
    loop {
        let _e6480 = local_291;
        let _e6481 = local_202;
        if (_e6480 <= _e6481) {
        } else {
            break;
        }
        let _e6483 = local_291;
        let _e6485 = local_838;
        let _e6488 = (_e6485.x + bitcast<i32>(bitcast<u32>(_e6483)));
        let _e6490 = vec2<i32>(_e6488, _e6485.y);
        let _e6497 = vec2<i32>(_e6490.x, (_e6490.y + (_e6488 >> bitcast<u32>(12i))));
        let _e6502 = vec2<i32>((_e6497.x & 4095i), _e6497.y);
        let _e6503 = local_839;
        let _e6506 = vec4<i32>(_e6502.x, _e6502.y, _e6503, 0i);
        let _e6507 = _e6506.xyz;
        let _e6514 = textureLoad(u_band_tex_0_image, vec2<i32>(_e6507.x, _e6507.y), i32(_e6507.z), _e6506.w);
        let _e6515 = _e6514.xy;
        let _e6519 = (_e6485.x + bitcast<i32>(_e6515.y));
        let _e6521 = vec2<i32>(_e6519, _e6485.y);
        let _e6528 = vec2<i32>(_e6521.x, (_e6521.y + (_e6519 >> bitcast<u32>(12i))));
        local_292 = vec2<i32>((_e6528.x & 4095i), _e6528.y);
        local_293 = bitcast<i32>(_e6515.x);
        local_294 = 0i;
        loop {
            let _e6536 = local_294;
            let _e6537 = local_293;
            if (_e6536 < _e6537) {
            } else {
                break;
            }
            let _e6539 = local_294;
            let _e6541 = local_292;
            let _e6544 = (_e6541.x + bitcast<i32>(bitcast<u32>(_e6539)));
            let _e6546 = vec2<i32>(_e6544, _e6541.y);
            let _e6553 = vec2<i32>(_e6546.x, (_e6546.y + (_e6544 >> bitcast<u32>(12i))));
            let _e6558 = vec2<i32>((_e6553.x & 4095i), _e6553.y);
            let _e6559 = local_839;
            let _e6562 = vec4<i32>(_e6558.x, _e6558.y, _e6559, 0i);
            let _e6563 = _e6562.xyz;
            let _e6570 = textureLoad(u_band_tex_0_image, vec2<i32>(_e6563.x, _e6563.y), i32(_e6563.z), _e6562.w);
            local_295 = _e6570.xy;
            let _e6572 = local_290;
            if _e6572 {
                let _e6573 = local_295;
                let _e6574 = local_291;
                let _e6575 = local_203;
                local_296 = !((_e6574 == max(bitcast<i32>((_e6573.x >> bitcast<u32>(12u))), _e6575)));
            } else {
                local_296 = false;
            }
            let _e6583 = local_296;
            if _e6583 {
                let _e6584 = local_294;
                local_294 = (_e6584 + 1i);
                continue;
            }
            let _e6586 = local_295;
            let _e6594 = local_288;
            local_297 = _e6594;
            let _e6595 = local_289;
            local_298 = _e6595;
            let _e6596 = local_836;
            local_299 = _e6596;
            let _e6597 = local_837;
            local_300 = _e6597;
            local_301 = vec2<i32>(bitcast<i32>((_e6586.x & 4095u)), bitcast<i32>((_e6586.y & 16383u)));
            let _e6598 = local_839;
            local_302 = _e6598;
            switch bitcast<i32>(0u) {
                default: {
                    let _e6600 = local_301;
                    let _e6601 = local_302;
                    let _e6604 = vec4<i32>(_e6600.x, _e6600.y, _e6601, 0i);
                    let _e6605 = _e6604.xyz;
                    let _e6612 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e6605.x, _e6605.y), i32(_e6605.z), _e6604.w);
                    let _e6614 = (_e6600.x + 1i);
                    let _e6616 = vec2<i32>(_e6614, _e6600.y);
                    let _e6623 = vec2<i32>(_e6616.x, (_e6616.y + (_e6614 >> bitcast<u32>(12i))));
                    let _e6628 = vec2<i32>((_e6623.x & 4095i), _e6623.y);
                    let _e6631 = vec4<i32>(_e6628.x, _e6628.y, _e6601, 0i);
                    let _e6637 = local_299;
                    let _e6643 = (vec4<f32>(_e6612.x, _e6612.y, _e6612.z, _e6612.w) - vec4<f32>(_e6637.x, _e6637.y, _e6637.x, _e6637.y));
                    local_279 = _e6643;
                    let _e6644 = _e6631.xyz;
                    let _e6651 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e6644.x, _e6644.y), i32(_e6644.z), _e6631.w);
                    let _e6653 = (_e6651.xy - _e6637);
                    local_280 = _e6653;
                    let _e6654 = local_300;
                    local_281 = _e6654.x;
                    if ((max(max(_e6643.x, _e6643.z), _e6653.x) * _e6654.x) < -0.5f) {
                        local_278 = false;
                        break;
                    }
                    let _e6663 = local_279;
                    local_283 = _e6663.y;
                    local_284 = _e6663.w;
                    let _e6666 = local_280;
                    local_275 = _e6666.y;
                    if (abs(_e6666.y) <= 0.000015258789f) {
                        local_274 = 0f;
                    } else {
                        let _e6670 = local_275;
                        local_274 = _e6670;
                    }
                    let _e6671 = local_274;
                    let _e6676 = local_284;
                    local_276 = _e6676;
                    if (abs(_e6676) <= 0.000015258789f) {
                        local_273 = 0f;
                    } else {
                        let _e6679 = local_276;
                        local_273 = _e6679;
                    }
                    let _e6680 = local_273;
                    let _e6685 = local_283;
                    local_277 = _e6685;
                    if (abs(_e6685) <= 0.000015258789f) {
                        local_272 = 0f;
                    } else {
                        let _e6688 = local_277;
                        local_272 = _e6688;
                    }
                    let _e6689 = local_272;
                    let _e6699 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e6671) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e6680) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e6689) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                    local_282 = _e6699;
                    if (_e6699 != 0u) {
                        let _e6701 = local_279;
                        local_286 = _e6701;
                        let _e6702 = local_280;
                        let _e6703 = _e6701.xy;
                        let _e6704 = _e6701.zw;
                        let _e6707 = ((_e6703 - (_e6704 * 2f)) + _e6702);
                        local_258 = _e6707;
                        local_259 = (_e6703 - _e6704);
                        local_260 = _e6707.y;
                        if (abs(_e6707.y) < 0.000015258789f) {
                            let _e6712 = local_259;
                            local_261 = _e6712.y;
                            if (abs(_e6712.y) < 0.000015258789f) {
                                local_262 = 0f;
                            } else {
                                let _e6716 = local_286;
                                let _e6719 = local_261;
                                local_262 = ((_e6716.y * 0.5f) / _e6719);
                            }
                            let _e6721 = local_262;
                            local_263 = _e6721;
                        } else {
                            let _e6722 = local_259;
                            local_264 = _e6722.y;
                            let _e6724 = local_286;
                            local_265 = _e6724.y;
                            let _e6726 = local_260;
                            let _e6727 = (_e6726 * _e6724.y);
                            let _e6729 = ((_e6722.y * _e6722.y) - _e6727);
                            local_267 = _e6729;
                            if (_e6729 <= (max((_e6722.y * _e6722.y), abs(_e6727)) * 0.000003f)) {
                                local_257 = 0f;
                            } else {
                                let _e6735 = local_267;
                                local_257 = sqrt(_e6735);
                            }
                            let _e6737 = local_257;
                            local_266 = _e6737;
                            let _e6738 = local_264;
                            if (_e6738 >= 0f) {
                                let _e6740 = local_264;
                                let _e6741 = local_266;
                                let _e6742 = (_e6740 + _e6741);
                                local_268 = _e6742;
                                let _e6743 = local_260;
                                local_269 = (_e6742 / _e6743);
                                if (abs(_e6742) < 0.000015258789f) {
                                    local_262 = 0f;
                                } else {
                                    let _e6747 = local_265;
                                    let _e6748 = local_268;
                                    local_262 = (_e6747 / _e6748);
                                }
                                let _e6750 = local_269;
                                local_263 = _e6750;
                            } else {
                                let _e6751 = local_264;
                                let _e6752 = local_266;
                                let _e6753 = (_e6751 - _e6752);
                                local_270 = _e6753;
                                let _e6754 = local_260;
                                local_271 = (_e6753 / _e6754);
                                if (abs(_e6753) < 0.000015258789f) {
                                    local_262 = 0f;
                                } else {
                                    let _e6758 = local_265;
                                    let _e6759 = local_270;
                                    local_262 = (_e6758 / _e6759);
                                }
                                let _e6761 = local_262;
                                let _e6762 = local_271;
                                local_262 = _e6762;
                                local_263 = _e6761;
                            }
                        }
                        let _e6763 = local_258;
                        let _e6765 = local_259;
                        let _e6767 = (_e6765.x * 2f);
                        let _e6768 = local_286;
                        let _e6770 = local_262;
                        let _e6775 = local_263;
                        let _e6781 = local_281;
                        local_285 = (vec2<f32>(((((_e6763.x * _e6770) - _e6767) * _e6770) + _e6768.x), ((((_e6763.x * _e6775) - _e6767) * _e6775) + _e6768.x)) * _e6781);
                        let _e6783 = local_282;
                        if ((_e6783 & 1u) != 0u) {
                            let _e6786 = local_285;
                            let _e6788 = local_297;
                            local_297 = (_e6788 + clamp((_e6786.x + 0.5f), 0f, 1f));
                            let _e6792 = local_298;
                            local_298 = max(_e6792, clamp((1f - (abs(_e6786.x) * 2f)), 0f, 1f));
                        }
                        let _e6798 = local_282;
                        if (_e6798 > 1u) {
                            let _e6800 = local_285;
                            let _e6802 = local_297;
                            local_297 = (_e6802 - clamp((_e6800.y + 0.5f), 0f, 1f));
                            let _e6806 = local_298;
                            local_298 = max(_e6806, clamp((1f - (abs(_e6800.y) * 2f)), 0f, 1f));
                        }
                    }
                    local_278 = true;
                    break;
                }
            }
            let _e6812 = local_278;
            let _e6813 = local_297;
            local_288 = _e6813;
            let _e6814 = local_298;
            local_289 = _e6814;
            if !(_e6812) {
                break;
            }
            let _e6816 = local_294;
            local_294 = (_e6816 + 1i);
            continue;
        }
        let _e6818 = local_291;
        local_291 = (_e6818 + 1i);
        continue;
    }
    local_303 = 0f;
    local_304 = 0f;
    let _e6820 = local_201;
    let _e6821 = local_200;
    local_305 = (_e6820 != _e6821);
    local_291 = _e6820;
    loop {
        let _e6823 = local_291;
        let _e6824 = local_200;
        if (_e6823 <= _e6824) {
        } else {
            break;
        }
        let _e6826 = local_287;
        let _e6828 = local_291;
        let _e6831 = local_838;
        let _e6834 = (_e6831.x + bitcast<i32>(bitcast<u32>(((_e6826 + 1i) + _e6828))));
        let _e6836 = vec2<i32>(_e6834, _e6831.y);
        let _e6843 = vec2<i32>(_e6836.x, (_e6836.y + (_e6834 >> bitcast<u32>(12i))));
        let _e6848 = vec2<i32>((_e6843.x & 4095i), _e6843.y);
        let _e6849 = local_839;
        let _e6852 = vec4<i32>(_e6848.x, _e6848.y, _e6849, 0i);
        let _e6853 = _e6852.xyz;
        let _e6860 = textureLoad(u_band_tex_0_image, vec2<i32>(_e6853.x, _e6853.y), i32(_e6853.z), _e6852.w);
        let _e6861 = _e6860.xy;
        let _e6865 = (_e6831.x + bitcast<i32>(_e6861.y));
        let _e6867 = vec2<i32>(_e6865, _e6831.y);
        let _e6874 = vec2<i32>(_e6867.x, (_e6867.y + (_e6865 >> bitcast<u32>(12i))));
        local_306 = vec2<i32>((_e6874.x & 4095i), _e6874.y);
        local_307 = bitcast<i32>(_e6861.x);
        local_294 = 0i;
        loop {
            let _e6882 = local_294;
            let _e6883 = local_307;
            if (_e6882 < _e6883) {
            } else {
                break;
            }
            let _e6885 = local_294;
            let _e6887 = local_306;
            let _e6890 = (_e6887.x + bitcast<i32>(bitcast<u32>(_e6885)));
            let _e6892 = vec2<i32>(_e6890, _e6887.y);
            let _e6899 = vec2<i32>(_e6892.x, (_e6892.y + (_e6890 >> bitcast<u32>(12i))));
            let _e6904 = vec2<i32>((_e6899.x & 4095i), _e6899.y);
            let _e6905 = local_839;
            let _e6908 = vec4<i32>(_e6904.x, _e6904.y, _e6905, 0i);
            let _e6909 = _e6908.xyz;
            let _e6916 = textureLoad(u_band_tex_0_image, vec2<i32>(_e6909.x, _e6909.y), i32(_e6909.z), _e6908.w);
            local_308 = _e6916.xy;
            let _e6918 = local_305;
            if _e6918 {
                let _e6919 = local_308;
                let _e6920 = local_291;
                let _e6921 = local_201;
                local_296 = !((_e6920 == max(bitcast<i32>((_e6919.x >> bitcast<u32>(12u))), _e6921)));
            } else {
                local_296 = false;
            }
            let _e6929 = local_296;
            if _e6929 {
                let _e6930 = local_294;
                local_294 = (_e6930 + 1i);
                continue;
            }
            let _e6932 = local_308;
            let _e6940 = local_303;
            local_309 = _e6940;
            let _e6941 = local_304;
            local_310 = _e6941;
            let _e6942 = local_836;
            local_311 = _e6942;
            let _e6943 = local_837;
            local_312 = _e6943;
            local_313 = vec2<i32>(bitcast<i32>((_e6932.x & 4095u)), bitcast<i32>((_e6932.y & 16383u)));
            let _e6944 = local_839;
            local_314 = _e6944;
            switch bitcast<i32>(0u) {
                default: {
                    let _e6946 = local_313;
                    let _e6947 = local_314;
                    let _e6950 = vec4<i32>(_e6946.x, _e6946.y, _e6947, 0i);
                    let _e6951 = _e6950.xyz;
                    let _e6958 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e6951.x, _e6951.y), i32(_e6951.z), _e6950.w);
                    let _e6960 = (_e6946.x + 1i);
                    let _e6962 = vec2<i32>(_e6960, _e6946.y);
                    let _e6969 = vec2<i32>(_e6962.x, (_e6962.y + (_e6960 >> bitcast<u32>(12i))));
                    let _e6974 = vec2<i32>((_e6969.x & 4095i), _e6969.y);
                    let _e6977 = vec4<i32>(_e6974.x, _e6974.y, _e6947, 0i);
                    let _e6983 = local_311;
                    let _e6989 = (vec4<f32>(_e6958.x, _e6958.y, _e6958.z, _e6958.w) - vec4<f32>(_e6983.x, _e6983.y, _e6983.x, _e6983.y));
                    local_249 = _e6989;
                    let _e6990 = _e6977.xyz;
                    let _e6997 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e6990.x, _e6990.y), i32(_e6990.z), _e6977.w);
                    let _e6999 = (_e6997.xy - _e6983);
                    local_250 = _e6999;
                    let _e7000 = local_312;
                    local_251 = _e7000.y;
                    if ((max(max(_e6989.y, _e6989.w), _e6999.y) * _e7000.y) < -0.5f) {
                        local_248 = false;
                        break;
                    }
                    let _e7009 = local_249;
                    local_253 = _e7009.x;
                    local_254 = _e7009.z;
                    let _e7012 = local_250;
                    local_245 = _e7012.x;
                    if (abs(_e7012.x) <= 0.000015258789f) {
                        local_244 = 0f;
                    } else {
                        let _e7016 = local_245;
                        local_244 = _e7016;
                    }
                    let _e7017 = local_244;
                    let _e7022 = local_254;
                    local_246 = _e7022;
                    if (abs(_e7022) <= 0.000015258789f) {
                        local_243 = 0f;
                    } else {
                        let _e7025 = local_246;
                        local_243 = _e7025;
                    }
                    let _e7026 = local_243;
                    let _e7031 = local_253;
                    local_247 = _e7031;
                    if (abs(_e7031) <= 0.000015258789f) {
                        local_242 = 0f;
                    } else {
                        let _e7034 = local_247;
                        local_242 = _e7034;
                    }
                    let _e7035 = local_242;
                    let _e7045 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e7017) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e7026) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e7035) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                    local_252 = _e7045;
                    if (_e7045 != 0u) {
                        let _e7047 = local_249;
                        local_256 = _e7047;
                        let _e7048 = local_250;
                        let _e7049 = _e7047.xy;
                        let _e7050 = _e7047.zw;
                        let _e7053 = ((_e7049 - (_e7050 * 2f)) + _e7048);
                        local_228 = _e7053;
                        local_229 = (_e7049 - _e7050);
                        local_230 = _e7053.x;
                        if (abs(_e7053.x) < 0.000015258789f) {
                            let _e7058 = local_229;
                            local_231 = _e7058.x;
                            if (abs(_e7058.x) < 0.000015258789f) {
                                local_232 = 0f;
                            } else {
                                let _e7062 = local_256;
                                let _e7065 = local_231;
                                local_232 = ((_e7062.x * 0.5f) / _e7065);
                            }
                            let _e7067 = local_232;
                            local_233 = _e7067;
                        } else {
                            let _e7068 = local_229;
                            local_234 = _e7068.x;
                            let _e7070 = local_256;
                            local_235 = _e7070.x;
                            let _e7072 = local_230;
                            let _e7073 = (_e7072 * _e7070.x);
                            let _e7075 = ((_e7068.x * _e7068.x) - _e7073);
                            local_237 = _e7075;
                            if (_e7075 <= (max((_e7068.x * _e7068.x), abs(_e7073)) * 0.000003f)) {
                                local_227 = 0f;
                            } else {
                                let _e7081 = local_237;
                                local_227 = sqrt(_e7081);
                            }
                            let _e7083 = local_227;
                            local_236 = _e7083;
                            let _e7084 = local_234;
                            if (_e7084 >= 0f) {
                                let _e7086 = local_234;
                                let _e7087 = local_236;
                                let _e7088 = (_e7086 + _e7087);
                                local_238 = _e7088;
                                let _e7089 = local_230;
                                local_239 = (_e7088 / _e7089);
                                if (abs(_e7088) < 0.000015258789f) {
                                    local_232 = 0f;
                                } else {
                                    let _e7093 = local_235;
                                    let _e7094 = local_238;
                                    local_232 = (_e7093 / _e7094);
                                }
                                let _e7096 = local_239;
                                local_233 = _e7096;
                            } else {
                                let _e7097 = local_234;
                                let _e7098 = local_236;
                                let _e7099 = (_e7097 - _e7098);
                                local_240 = _e7099;
                                let _e7100 = local_230;
                                local_241 = (_e7099 / _e7100);
                                if (abs(_e7099) < 0.000015258789f) {
                                    local_232 = 0f;
                                } else {
                                    let _e7104 = local_235;
                                    let _e7105 = local_240;
                                    local_232 = (_e7104 / _e7105);
                                }
                                let _e7107 = local_232;
                                let _e7108 = local_241;
                                local_232 = _e7108;
                                local_233 = _e7107;
                            }
                        }
                        let _e7109 = local_228;
                        let _e7111 = local_229;
                        let _e7113 = (_e7111.y * 2f);
                        let _e7114 = local_256;
                        let _e7116 = local_232;
                        let _e7121 = local_233;
                        let _e7127 = local_251;
                        local_255 = (vec2<f32>(((((_e7109.y * _e7116) - _e7113) * _e7116) + _e7114.y), ((((_e7109.y * _e7121) - _e7113) * _e7121) + _e7114.y)) * _e7127);
                        let _e7129 = local_252;
                        if ((_e7129 & 1u) != 0u) {
                            let _e7132 = local_255;
                            let _e7134 = local_309;
                            local_309 = (_e7134 - clamp((_e7132.x + 0.5f), 0f, 1f));
                            let _e7138 = local_310;
                            local_310 = max(_e7138, clamp((1f - (abs(_e7132.x) * 2f)), 0f, 1f));
                        }
                        let _e7144 = local_252;
                        if (_e7144 > 1u) {
                            let _e7146 = local_255;
                            let _e7148 = local_309;
                            local_309 = (_e7148 + clamp((_e7146.y + 0.5f), 0f, 1f));
                            let _e7152 = local_310;
                            local_310 = max(_e7152, clamp((1f - (abs(_e7146.y) * 2f)), 0f, 1f));
                        }
                    }
                    local_248 = true;
                    break;
                }
            }
            let _e7158 = local_248;
            let _e7159 = local_309;
            local_303 = _e7159;
            let _e7160 = local_310;
            local_304 = _e7160;
            if !(_e7158) {
                break;
            }
            let _e7162 = local_294;
            local_294 = (_e7162 + 1i);
            continue;
        }
        let _e7164 = local_291;
        local_291 = (_e7164 + 1i);
        continue;
    }
    let _e7166 = local_288;
    let _e7167 = local_289;
    let _e7169 = local_303;
    let _e7170 = local_304;
    local_315 = (((_e7166 * _e7167) + (_e7169 * _e7170)) / max((_e7167 + _e7170), 0.000015258789f));
    local_316 = 0i;
    switch bitcast<i32>(0u) {
        default: {
            let _e7177 = local_316;
            if (_e7177 == 1i) {
                let _e7179 = local_315;
                local_226 = (1f - abs(((fract((_e7179 * 0.5f)) * 2f) - 1f)));
                break;
            }
            let _e7186 = local_315;
            local_226 = abs(_e7186);
            break;
        }
    }
    let _e7188 = local_226;
    let _e7189 = local_288;
    local_317 = _e7189;
    local_318 = 0i;
    switch bitcast<i32>(0u) {
        default: {
            let _e7191 = local_318;
            if (_e7191 == 1i) {
                let _e7193 = local_317;
                local_225 = (1f - abs(((fract((_e7193 * 0.5f)) * 2f) - 1f)));
                break;
            }
            let _e7200 = local_317;
            local_225 = abs(_e7200);
            break;
        }
    }
    let _e7202 = local_225;
    let _e7203 = local_303;
    local_319 = _e7203;
    local_320 = 0i;
    switch bitcast<i32>(0u) {
        default: {
            let _e7205 = local_320;
            if (_e7205 == 1i) {
                let _e7207 = local_319;
                local_224 = (1f - abs(((fract((_e7207 * 0.5f)) * 2f) - 1f)));
                break;
            }
            let _e7214 = local_319;
            local_224 = abs(_e7214);
            break;
        }
    }
    let _e7216 = local_224;
    local_221 = clamp(max(_e7188, min(_e7202, _e7216)), 0f, 1f);
    let _e7221 = PushConstants_0_.coverage_exponent_0_;
    let _e7222 = max(_e7221, 0.000015258789f);
    local_222 = _e7222;
    if (abs((_e7222 - 1f)) <= 0.000001f) {
        let _e7226 = local_221;
        local_223 = _e7226;
    } else {
        let _e7227 = local_221;
        let _e7228 = local_222;
        local_223 = pow(_e7227, _e7228);
    }
    let _e7230 = local_223;
    local_835 = _e7230;
    if (_e7230 < 0.003921569f) {
        discard;
    }
    let _e7232 = v_paint_0_1;
    let _e7233 = local_835;
    let _e7235 = (_e7232.w * _e7233);
    let _e7237 = (_e7232.xyz * _e7235);
    local_840 = vec4<f32>(_e7237.x, _e7237.y, _e7237.z, _e7235);
    let _e7243 = PushConstants_0_.mask_output_0_;
    if (_e7243 != 0i) {
        let _e7245 = local_840;
        local_841 = vec4(_e7245.w);
    } else {
        let _e7249 = PushConstants_0_.output_srgb_0_;
        if (_e7249 != 0i) {
            let _e7251 = local_840;
            local_842 = _e7251;
            switch bitcast<i32>(0u) {
                default: {
                    let _e7253 = local_842;
                    local_219 = _e7253.w;
                    if (_e7253.w <= 0f) {
                        local_218 = vec4<f32>(0f, 0f, 0f, 0f);
                        break;
                    }
                    let _e7256 = local_842;
                    let _e7258 = local_219;
                    let _e7260 = (_e7256.xyz * (1f / _e7258));
                    local_220 = _e7260;
                    let _e7262 = max(_e7260.x, 0f);
                    local_215 = _e7262;
                    if (_e7262 <= 0.0031308f) {
                        let _e7264 = local_215;
                        local_214 = (_e7264 * 12.92f);
                    } else {
                        let _e7266 = local_215;
                        local_214 = ((1.055f * pow(_e7266, 0.41666666f)) - 0.055f);
                    }
                    let _e7270 = local_214;
                    let _e7271 = local_220;
                    let _e7273 = max(_e7271.y, 0f);
                    local_216 = _e7273;
                    if (_e7273 <= 0.0031308f) {
                        let _e7275 = local_216;
                        local_213 = (_e7275 * 12.92f);
                    } else {
                        let _e7277 = local_216;
                        local_213 = ((1.055f * pow(_e7277, 0.41666666f)) - 0.055f);
                    }
                    let _e7281 = local_213;
                    let _e7282 = local_220;
                    let _e7284 = max(_e7282.z, 0f);
                    local_217 = _e7284;
                    if (_e7284 <= 0.0031308f) {
                        let _e7286 = local_217;
                        local_212 = (_e7286 * 12.92f);
                    } else {
                        let _e7288 = local_217;
                        local_212 = ((1.055f * pow(_e7288, 0.41666666f)) - 0.055f);
                    }
                    let _e7292 = local_212;
                    let _e7294 = local_219;
                    let _e7295 = (vec3<f32>(_e7270, _e7281, _e7292) * _e7294);
                    local_218 = vec4<f32>(_e7295.x, _e7295.y, _e7295.z, _e7294);
                    break;
                }
            }
            let _e7300 = local_218;
            local_841 = _e7300;
        } else {
            let _e7301 = local_840;
            local_841 = _e7301;
        }
    }
    let _e7302 = local_841;
    _S115_ = _e7302;
    let _e7303 = _S115_;
    entryPointParam_main_frag_color_0_ = _e7303;
    return;
}

@fragment 
fn main(@location(2) @interpolate(flat) v_info_0_: vec2<i32>, @location(1) v_texcoord_layer_0_: vec3<f32>, @location(13) @interpolate(flat) v_ah_x_sources_0_: vec4<u32>, @location(14) @interpolate(flat) v_ah_y_sources_0_: vec4<u32>, @location(3) @interpolate(flat) v_policy0_0_: vec4<u32>, @location(4) @interpolate(flat) v_policy1_0_: vec3<u32>, @location(0) v_paint_0_: vec4<f32>, @location(5) @interpolate(flat) v_ah_x_targets0_0_: vec4<f32>, @location(6) @interpolate(flat) v_ah_x_targets1_0_: vec4<f32>, @location(7) @interpolate(flat) v_ah_x_targets2_0_: vec4<f32>, @location(8) @interpolate(flat) v_ah_x_targets3_0_: vec4<f32>, @location(9) @interpolate(flat) v_ah_y_targets0_0_: vec4<f32>, @location(10) @interpolate(flat) v_ah_y_targets1_0_: vec4<f32>, @location(11) @interpolate(flat) v_ah_y_targets2_0_: vec4<f32>, @location(12) @interpolate(flat) v_ah_y_targets3_0_: vec4<f32>) -> @location(0) vec4<f32> {
    v_info_0_1 = v_info_0_;
    v_texcoord_layer_0_1 = v_texcoord_layer_0_;
    v_ah_x_sources_0_1 = v_ah_x_sources_0_;
    v_ah_y_sources_0_1 = v_ah_y_sources_0_;
    v_policy0_0_1 = v_policy0_0_;
    v_policy1_0_1 = v_policy1_0_;
    v_paint_0_1 = v_paint_0_;
    v_ah_x_targets0_0_1 = v_ah_x_targets0_0_;
    v_ah_x_targets1_0_1 = v_ah_x_targets1_0_;
    v_ah_x_targets2_0_1 = v_ah_x_targets2_0_;
    v_ah_x_targets3_0_1 = v_ah_x_targets3_0_;
    v_ah_y_targets0_0_1 = v_ah_y_targets0_0_;
    v_ah_y_targets1_0_1 = v_ah_y_targets1_0_;
    v_ah_y_targets2_0_1 = v_ah_y_targets2_0_;
    v_ah_y_targets3_0_1 = v_ah_y_targets3_0_;
    main_1();
    let _e31 = entryPointParam_main_frag_color_0_;
    return _e31;
}
