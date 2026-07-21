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
@group(1) @binding(1) 
var u_band_tex_0_sampler: sampler;
@group(0) @binding(1) 
var u_band_tex_0_image: texture_2d_array<u32>;
@group(2) @binding(0) 
var<uniform> PushConstants_0_: block_SLANG_ParameterGroup_PushConstants_0_;
@group(1) @binding(3) 
var u_image_tex_0_sampler: sampler;
@group(0) @binding(3) 
var u_image_tex_0_image: texture_2d_array<f32>;
var<private> gl_FragCoord_1: vec4<f32>;
var<private> v_texcoord_0_1: vec2<f32>;
var<private> v_glyph_0_1: vec4<i32>;
var<private> v_banding_0_1: vec4<f32>;
var<private> v_tint_0_1: vec4<f32>;
var<private> entryPointParam_main_frag_color_0_: vec4<f32>;

fn main_1() {
    var local: f32;
    var local_1: vec4<f32>;
    var local_2: f32;
    var local_3: vec4<f32>;
    var local_4: f32;
    var local_5: vec4<f32>;
    var local_6: f32;
    var local_7: vec4<f32>;
    var local_8: f32;
    var local_9: vec4<f32>;
    var local_10: f32;
    var local_11: vec4<f32>;
    var local_12: i32;
    var local_13: i32;
    var local_14: vec3<f32>;
    var local_15: vec2<f32>;
    var local_16: vec2<f32>;
    var local_17: vec2<f32>;
    var local_18: vec2<f32>;
    var local_19: i32;
    var local_20: vec3<f32>;
    var local_21: vec2<f32>;
    var local_22: vec2<f32>;
    var local_23: vec2<f32>;
    var local_24: vec2<f32>;
    var local_25: i32;
    var local_26: vec2<f32>;
    var local_27: vec2<f32>;
    var local_28: vec2<f32>;
    var local_29: vec2<f32>;
    var local_30: i32;
    var local_31: vec3<f32>;
    var local_32: vec2<f32>;
    var local_33: vec2<f32>;
    var local_34: vec2<f32>;
    var local_35: vec2<f32>;
    var local_36: i32;
    var local_37: vec2<f32>;
    var local_38: vec2<f32>;
    var local_39: vec2<f32>;
    var local_40: vec2<f32>;
    var local_41: i32;
    var local_42: vec2<f32>;
    var local_43: vec2<f32>;
    var local_44: vec2<f32>;
    var local_45: vec2<f32>;
    var local_46: i32;
    var local_47: vec2<f32>;
    var local_48: vec2<f32>;
    var local_49: vec2<f32>;
    var local_50: vec2<f32>;
    var local_51: i32;
    var local_52: vec2<f32>;
    var local_53: vec2<f32>;
    var local_54: vec2<f32>;
    var local_55: vec2<f32>;
    var local_56: i32;
    var local_57: vec3<f32>;
    var local_58: vec2<f32>;
    var local_59: vec2<f32>;
    var local_60: vec2<f32>;
    var local_61: vec2<f32>;
    var local_62: i32;
    var local_63: vec3<f32>;
    var local_64: vec2<f32>;
    var local_65: vec2<f32>;
    var local_66: vec2<f32>;
    var local_67: vec2<f32>;
    var local_68: i32;
    var local_69: vec2<f32>;
    var local_70: vec2<f32>;
    var local_71: vec2<f32>;
    var local_72: vec2<f32>;
    var local_73: i32;
    var local_74: vec3<f32>;
    var local_75: vec2<f32>;
    var local_76: vec2<f32>;
    var local_77: vec2<f32>;
    var local_78: vec2<f32>;
    var local_79: i32;
    var local_80: vec2<f32>;
    var local_81: vec2<f32>;
    var local_82: vec2<f32>;
    var local_83: vec2<f32>;
    var local_84: i32;
    var local_85: vec2<f32>;
    var local_86: vec2<f32>;
    var local_87: vec2<f32>;
    var local_88: vec2<f32>;
    var local_89: i32;
    var local_90: vec2<f32>;
    var local_91: vec2<f32>;
    var local_92: vec2<f32>;
    var local_93: vec2<f32>;
    var local_94: i32;
    var local_95: vec2<f32>;
    var local_96: vec2<f32>;
    var local_97: vec2<f32>;
    var local_98: vec2<f32>;
    var local_99: i32;
    var local_100: f32;
    var local_101: vec4<f32>;
    var local_102: i32;
    var local_103: i32;
    var local_104: vec3<f32>;
    var local_105: vec2<f32>;
    var local_106: vec2<f32>;
    var local_107: vec2<f32>;
    var local_108: vec2<f32>;
    var local_109: i32;
    var local_110: vec3<f32>;
    var local_111: vec2<f32>;
    var local_112: vec2<f32>;
    var local_113: vec2<f32>;
    var local_114: vec2<f32>;
    var local_115: i32;
    var local_116: vec2<f32>;
    var local_117: vec2<f32>;
    var local_118: vec2<f32>;
    var local_119: vec2<f32>;
    var local_120: i32;
    var local_121: vec3<f32>;
    var local_122: vec2<f32>;
    var local_123: vec2<f32>;
    var local_124: vec2<f32>;
    var local_125: vec2<f32>;
    var local_126: i32;
    var local_127: vec2<f32>;
    var local_128: vec2<f32>;
    var local_129: vec2<f32>;
    var local_130: vec2<f32>;
    var local_131: i32;
    var local_132: vec2<f32>;
    var local_133: vec2<f32>;
    var local_134: vec2<f32>;
    var local_135: vec2<f32>;
    var local_136: i32;
    var local_137: vec2<f32>;
    var local_138: vec2<f32>;
    var local_139: vec2<f32>;
    var local_140: vec2<f32>;
    var local_141: i32;
    var local_142: vec2<f32>;
    var local_143: vec2<f32>;
    var local_144: vec2<f32>;
    var local_145: vec2<f32>;
    var local_146: i32;
    var local_147: vec3<f32>;
    var local_148: vec2<f32>;
    var local_149: vec2<f32>;
    var local_150: vec2<f32>;
    var local_151: vec2<f32>;
    var local_152: i32;
    var local_153: vec3<f32>;
    var local_154: vec2<f32>;
    var local_155: vec2<f32>;
    var local_156: vec2<f32>;
    var local_157: vec2<f32>;
    var local_158: i32;
    var local_159: vec2<f32>;
    var local_160: vec2<f32>;
    var local_161: vec2<f32>;
    var local_162: vec2<f32>;
    var local_163: i32;
    var local_164: vec3<f32>;
    var local_165: vec2<f32>;
    var local_166: vec2<f32>;
    var local_167: vec2<f32>;
    var local_168: vec2<f32>;
    var local_169: i32;
    var local_170: vec2<f32>;
    var local_171: vec2<f32>;
    var local_172: vec2<f32>;
    var local_173: vec2<f32>;
    var local_174: i32;
    var local_175: vec2<f32>;
    var local_176: vec2<f32>;
    var local_177: vec2<f32>;
    var local_178: vec2<f32>;
    var local_179: i32;
    var local_180: vec2<f32>;
    var local_181: vec2<f32>;
    var local_182: vec2<f32>;
    var local_183: vec2<f32>;
    var local_184: i32;
    var local_185: vec2<f32>;
    var local_186: vec2<f32>;
    var local_187: vec2<f32>;
    var local_188: vec2<f32>;
    var local_189: i32;
    var local_190: f32;
    var local_191: vec4<f32>;
    var _S118_: vec4<f32>;
    var local_192: f32;
    var local_193: f32;
    var local_194: f32;
    var local_195: f32;
    var local_196: f32;
    var local_197: f32;
    var local_198: vec4<f32>;
    var local_199: f32;
    var local_200: vec3<f32>;
    var local_201: f32;
    var local_202: f32;
    var local_203: f32;
    var local_204: f32;
    var local_205: f32;
    var local_206: f32;
    var local_207: f32;
    var local_208: f32;
    var local_209: f32;
    var local_210: f32;
    var local_211: f32;
    var local_212: f32;
    var local_213: vec4<f32>;
    var local_214: f32;
    var local_215: bool;
    var local_216: vec3<f32>;
    var local_217: vec3<f32>;
    var local_218: vec4<f32>;
    var local_219: vec3<i32>;
    var local_220: f32;
    var local_221: i32;
    var local_222: f32;
    var local_223: f32;
    var local_224: f32;
    var local_225: i32;
    var local_226: f32;
    var local_227: f32;
    var local_228: vec2<i32>;
    var local_229: vec2<i32>;
    var local_230: f32;
    var local_231: i32;
    var local_232: f32;
    var local_233: f32;
    var local_234: f32;
    var local_235: i32;
    var local_236: f32;
    var local_237: f32;
    var local_238: f32;
    var local_239: i32;
    var local_240: f32;
    var local_241: f32;
    var local_242: vec2<i32>;
    var local_243: vec2<i32>;
    var local_244: vec2<i32>;
    var local_245: vec2<i32>;
    var local_246: i32;
    var local_247: vec4<f32>;
    var local_248: vec4<f32>;
    var local_249: vec4<f32>;
    var local_250: vec2<f32>;
    var local_251: vec2<f32>;
    var local_252: f32;
    var local_253: f32;
    var local_254: f32;
    var local_255: f32;
    var local_256: f32;
    var local_257: f32;
    var local_258: f32;
    var local_259: f32;
    var local_260: vec4<f32>;
    var local_261: vec4<f32>;
    var local_262: vec3<f32>;
    var local_263: f32;
    var local_264: f32;
    var local_265: f32;
    var local_266: f32;
    var local_267: vec2<f32>;
    var local_268: i32;
    var local_269: i32;
    var local_270: f32;
    var local_271: f32;
    var local_272: f32;
    var local_273: f32;
    var local_274: f32;
    var local_275: f32;
    var local_276: bool;
    var local_277: bool;
    var local_278: bool;
    var local_279: f32;
    var local_280: f32;
    var local_281: f32;
    var local_282: i32;
    var local_283: f32;
    var local_284: bool;
    var local_285: f32;
    var local_286: f32;
    var local_287: f32;
    var local_288: bool;
    var local_289: f32;
    var local_290: f32;
    var local_291: f32;
    var local_292: f32;
    var local_293: bool;
    var local_294: f32;
    var local_295: bool;
    var local_296: bool;
    var local_297: f32;
    var local_298: f32;
    var local_299: f32;
    var local_300: f32;
    var local_301: f32;
    var local_302: f32;
    var local_303: f32;
    var local_304: vec2<f32>;
    var local_305: bool;
    var local_306: f32;
    var local_307: f32;
    var local_308: f32;
    var local_309: f32;
    var local_310: f32;
    var local_311: f32;
    var local_312: f32;
    var local_313: f32;
    var local_314: f32;
    var local_315: f32;
    var local_316: f32;
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
    var local_328: f32;
    var local_329: f32;
    var local_330: f32;
    var local_331: f32;
    var local_332: f32;
    var local_333: f32;
    var local_334: f32;
    var local_335: f32;
    var local_336: f32;
    var local_337: f32;
    var local_338: f32;
    var local_339: f32;
    var local_340: f32;
    var local_341: f32;
    var local_342: f32;
    var local_343: f32;
    var local_344: f32;
    var local_345: f32;
    var local_346: f32;
    var local_347: f32;
    var local_348: f32;
    var local_349: f32;
    var local_350: f32;
    var local_351: bool;
    var local_352: f32;
    var local_353: bool;
    var local_354: bool;
    var local_355: f32;
    var local_356: f32;
    var local_357: f32;
    var local_358: f32;
    var local_359: f32;
    var local_360: f32;
    var local_361: f32;
    var local_362: vec2<f32>;
    var local_363: bool;
    var local_364: f32;
    var local_365: f32;
    var local_366: f32;
    var local_367: f32;
    var local_368: f32;
    var local_369: f32;
    var local_370: f32;
    var local_371: f32;
    var local_372: f32;
    var local_373: f32;
    var local_374: f32;
    var local_375: f32;
    var local_376: f32;
    var local_377: f32;
    var local_378: u32;
    var local_379: f32;
    var local_380: f32;
    var local_381: i32;
    var local_382: f32;
    var local_383: f32;
    var local_384: i32;
    var local_385: f32;
    var local_386: f32;
    var local_387: bool;
    var local_388: f32;
    var local_389: i32;
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
    var local_402: f32;
    var local_403: f32;
    var local_404: bool;
    var local_405: f32;
    var local_406: f32;
    var local_407: f32;
    var local_408: f32;
    var local_409: f32;
    var local_410: f32;
    var local_411: f32;
    var local_412: f32;
    var local_413: f32;
    var local_414: f32;
    var local_415: f32;
    var local_416: f32;
    var local_417: f32;
    var local_418: f32;
    var local_419: bool;
    var local_420: f32;
    var local_421: f32;
    var local_422: f32;
    var local_423: f32;
    var local_424: f32;
    var local_425: f32;
    var local_426: f32;
    var local_427: f32;
    var local_428: f32;
    var local_429: f32;
    var local_430: f32;
    var local_431: f32;
    var local_432: f32;
    var local_433: f32;
    var local_434: f32;
    var local_435: f32;
    var local_436: f32;
    var local_437: f32;
    var local_438: f32;
    var local_439: f32;
    var local_440: f32;
    var local_441: f32;
    var local_442: f32;
    var local_443: f32;
    var local_444: f32;
    var local_445: f32;
    var local_446: f32;
    var local_447: f32;
    var local_448: f32;
    var local_449: f32;
    var local_450: f32;
    var local_451: f32;
    var local_452: f32;
    var local_453: f32;
    var local_454: f32;
    var local_455: f32;
    var local_456: f32;
    var local_457: f32;
    var local_458: f32;
    var local_459: f32;
    var local_460: f32;
    var local_461: f32;
    var local_462: f32;
    var local_463: f32;
    var local_464: f32;
    var local_465: f32;
    var local_466: f32;
    var local_467: f32;
    var local_468: f32;
    var local_469: f32;
    var local_470: f32;
    var local_471: f32;
    var local_472: f32;
    var local_473: f32;
    var local_474: f32;
    var local_475: f32;
    var local_476: f32;
    var local_477: f32;
    var local_478: f32;
    var local_479: bool;
    var local_480: f32;
    var local_481: f32;
    var local_482: f32;
    var local_483: f32;
    var local_484: f32;
    var local_485: f32;
    var local_486: f32;
    var local_487: u32;
    var local_488: f32;
    var local_489: f32;
    var local_490: f32;
    var local_491: f32;
    var local_492: vec2<f32>;
    var local_493: f32;
    var local_494: f32;
    var local_495: f32;
    var local_496: f32;
    var local_497: f32;
    var local_498: f32;
    var local_499: f32;
    var local_500: f32;
    var local_501: f32;
    var local_502: f32;
    var local_503: f32;
    var local_504: f32;
    var local_505: f32;
    var local_506: f32;
    var local_507: f32;
    var local_508: bool;
    var local_509: f32;
    var local_510: f32;
    var local_511: vec2<f32>;
    var local_512: f32;
    var local_513: bool;
    var local_514: f32;
    var local_515: f32;
    var local_516: vec2<f32>;
    var local_517: f32;
    var local_518: bool;
    var local_519: f32;
    var local_520: f32;
    var local_521: bool;
    var local_522: i32;
    var local_523: vec2<i32>;
    var local_524: i32;
    var local_525: i32;
    var local_526: vec2<u32>;
    var local_527: vec2<i32>;
    var local_528: i32;
    var local_529: f32;
    var local_530: f32;
    var local_531: vec2<f32>;
    var local_532: f32;
    var local_533: bool;
    var local_534: bool;
    var local_535: bool;
    var local_536: bool;
    var local_537: f32;
    var local_538: f32;
    var local_539: f32;
    var local_540: i32;
    var local_541: f32;
    var local_542: bool;
    var local_543: f32;
    var local_544: f32;
    var local_545: f32;
    var local_546: bool;
    var local_547: f32;
    var local_548: f32;
    var local_549: f32;
    var local_550: f32;
    var local_551: bool;
    var local_552: f32;
    var local_553: bool;
    var local_554: bool;
    var local_555: f32;
    var local_556: f32;
    var local_557: f32;
    var local_558: f32;
    var local_559: f32;
    var local_560: f32;
    var local_561: f32;
    var local_562: vec2<f32>;
    var local_563: bool;
    var local_564: f32;
    var local_565: f32;
    var local_566: f32;
    var local_567: f32;
    var local_568: f32;
    var local_569: f32;
    var local_570: f32;
    var local_571: f32;
    var local_572: f32;
    var local_573: f32;
    var local_574: f32;
    var local_575: f32;
    var local_576: f32;
    var local_577: f32;
    var local_578: f32;
    var local_579: f32;
    var local_580: f32;
    var local_581: f32;
    var local_582: f32;
    var local_583: f32;
    var local_584: f32;
    var local_585: f32;
    var local_586: f32;
    var local_587: f32;
    var local_588: f32;
    var local_589: f32;
    var local_590: f32;
    var local_591: f32;
    var local_592: f32;
    var local_593: f32;
    var local_594: f32;
    var local_595: f32;
    var local_596: f32;
    var local_597: f32;
    var local_598: f32;
    var local_599: f32;
    var local_600: f32;
    var local_601: f32;
    var local_602: f32;
    var local_603: f32;
    var local_604: f32;
    var local_605: f32;
    var local_606: f32;
    var local_607: f32;
    var local_608: f32;
    var local_609: bool;
    var local_610: f32;
    var local_611: bool;
    var local_612: bool;
    var local_613: f32;
    var local_614: f32;
    var local_615: f32;
    var local_616: f32;
    var local_617: f32;
    var local_618: f32;
    var local_619: f32;
    var local_620: vec2<f32>;
    var local_621: bool;
    var local_622: f32;
    var local_623: f32;
    var local_624: f32;
    var local_625: f32;
    var local_626: f32;
    var local_627: f32;
    var local_628: f32;
    var local_629: f32;
    var local_630: f32;
    var local_631: f32;
    var local_632: f32;
    var local_633: f32;
    var local_634: f32;
    var local_635: f32;
    var local_636: u32;
    var local_637: f32;
    var local_638: f32;
    var local_639: i32;
    var local_640: f32;
    var local_641: f32;
    var local_642: i32;
    var local_643: f32;
    var local_644: f32;
    var local_645: bool;
    var local_646: f32;
    var local_647: i32;
    var local_648: f32;
    var local_649: f32;
    var local_650: f32;
    var local_651: f32;
    var local_652: f32;
    var local_653: f32;
    var local_654: f32;
    var local_655: f32;
    var local_656: f32;
    var local_657: f32;
    var local_658: f32;
    var local_659: f32;
    var local_660: f32;
    var local_661: f32;
    var local_662: bool;
    var local_663: f32;
    var local_664: f32;
    var local_665: f32;
    var local_666: f32;
    var local_667: f32;
    var local_668: f32;
    var local_669: f32;
    var local_670: f32;
    var local_671: f32;
    var local_672: f32;
    var local_673: f32;
    var local_674: f32;
    var local_675: f32;
    var local_676: f32;
    var local_677: bool;
    var local_678: f32;
    var local_679: f32;
    var local_680: f32;
    var local_681: f32;
    var local_682: f32;
    var local_683: f32;
    var local_684: f32;
    var local_685: f32;
    var local_686: f32;
    var local_687: f32;
    var local_688: f32;
    var local_689: f32;
    var local_690: f32;
    var local_691: f32;
    var local_692: f32;
    var local_693: f32;
    var local_694: f32;
    var local_695: f32;
    var local_696: f32;
    var local_697: f32;
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
    var local_709: f32;
    var local_710: f32;
    var local_711: f32;
    var local_712: f32;
    var local_713: f32;
    var local_714: f32;
    var local_715: f32;
    var local_716: f32;
    var local_717: f32;
    var local_718: f32;
    var local_719: f32;
    var local_720: f32;
    var local_721: f32;
    var local_722: f32;
    var local_723: f32;
    var local_724: f32;
    var local_725: f32;
    var local_726: f32;
    var local_727: f32;
    var local_728: f32;
    var local_729: f32;
    var local_730: f32;
    var local_731: f32;
    var local_732: f32;
    var local_733: f32;
    var local_734: f32;
    var local_735: f32;
    var local_736: f32;
    var local_737: bool;
    var local_738: f32;
    var local_739: f32;
    var local_740: f32;
    var local_741: f32;
    var local_742: f32;
    var local_743: f32;
    var local_744: f32;
    var local_745: u32;
    var local_746: f32;
    var local_747: f32;
    var local_748: f32;
    var local_749: f32;
    var local_750: vec2<f32>;
    var local_751: f32;
    var local_752: f32;
    var local_753: f32;
    var local_754: f32;
    var local_755: f32;
    var local_756: f32;
    var local_757: f32;
    var local_758: f32;
    var local_759: f32;
    var local_760: f32;
    var local_761: f32;
    var local_762: f32;
    var local_763: f32;
    var local_764: f32;
    var local_765: f32;
    var local_766: bool;
    var local_767: f32;
    var local_768: f32;
    var local_769: vec2<f32>;
    var local_770: f32;
    var local_771: bool;
    var local_772: f32;
    var local_773: f32;
    var local_774: vec2<f32>;
    var local_775: f32;
    var local_776: bool;
    var local_777: f32;
    var local_778: f32;
    var local_779: bool;
    var local_780: i32;
    var local_781: vec2<i32>;
    var local_782: i32;
    var local_783: i32;
    var local_784: vec2<u32>;
    var local_785: vec2<i32>;
    var local_786: i32;
    var local_787: f32;
    var local_788: f32;
    var local_789: vec2<f32>;
    var local_790: f32;
    var local_791: bool;
    var local_792: i32;
    var local_793: vec2<f32>;
    var local_794: vec2<f32>;
    var local_795: f32;
    var local_796: vec2<i32>;
    var local_797: i32;
    var local_798: i32;
    var local_799: i32;
    var local_800: i32;
    var local_801: bool;
    var local_802: vec2<f32>;
    var local_803: f32;
    var local_804: vec2<i32>;
    var local_805: i32;
    var local_806: i32;
    var local_807: i32;
    var local_808: i32;
    var local_809: bool;
    var local_810: f32;
    var local_811: f32;
    var local_812: f32;
    var local_813: i32;
    var local_814: f32;
    var local_815: i32;
    var local_816: f32;
    var local_817: i32;
    var local_818: vec2<i32>;
    var local_819: f32;
    var local_820: f32;
    var local_821: f32;
    var local_822: f32;
    var local_823: f32;
    var local_824: f32;
    var local_825: vec4<f32>;
    var local_826: f32;
    var local_827: vec3<f32>;
    var local_828: f32;
    var local_829: f32;
    var local_830: f32;
    var local_831: f32;
    var local_832: f32;
    var local_833: f32;
    var local_834: f32;
    var local_835: f32;
    var local_836: f32;
    var local_837: f32;
    var local_838: f32;
    var local_839: f32;
    var local_840: vec4<f32>;
    var local_841: f32;
    var local_842: bool;
    var local_843: vec3<f32>;
    var local_844: vec3<f32>;
    var local_845: vec4<f32>;
    var local_846: vec3<i32>;
    var local_847: f32;
    var local_848: i32;
    var local_849: f32;
    var local_850: f32;
    var local_851: f32;
    var local_852: i32;
    var local_853: f32;
    var local_854: f32;
    var local_855: vec2<i32>;
    var local_856: vec2<i32>;
    var local_857: f32;
    var local_858: i32;
    var local_859: f32;
    var local_860: f32;
    var local_861: f32;
    var local_862: i32;
    var local_863: f32;
    var local_864: f32;
    var local_865: f32;
    var local_866: i32;
    var local_867: f32;
    var local_868: f32;
    var local_869: vec2<i32>;
    var local_870: vec2<i32>;
    var local_871: vec2<i32>;
    var local_872: vec2<i32>;
    var local_873: i32;
    var local_874: vec4<f32>;
    var local_875: vec4<f32>;
    var local_876: vec4<f32>;
    var local_877: vec2<f32>;
    var local_878: vec2<f32>;
    var local_879: f32;
    var local_880: f32;
    var local_881: f32;
    var local_882: f32;
    var local_883: f32;
    var local_884: f32;
    var local_885: f32;
    var local_886: f32;
    var local_887: vec4<f32>;
    var local_888: vec4<f32>;
    var local_889: vec3<f32>;
    var local_890: f32;
    var local_891: f32;
    var local_892: f32;
    var local_893: f32;
    var local_894: vec2<f32>;
    var local_895: i32;
    var local_896: i32;
    var local_897: f32;
    var local_898: f32;
    var local_899: f32;
    var local_900: f32;
    var local_901: f32;
    var local_902: f32;
    var local_903: bool;
    var local_904: bool;
    var local_905: bool;
    var local_906: f32;
    var local_907: f32;
    var local_908: f32;
    var local_909: i32;
    var local_910: f32;
    var local_911: bool;
    var local_912: f32;
    var local_913: f32;
    var local_914: f32;
    var local_915: bool;
    var local_916: f32;
    var local_917: f32;
    var local_918: f32;
    var local_919: f32;
    var local_920: bool;
    var local_921: f32;
    var local_922: bool;
    var local_923: bool;
    var local_924: f32;
    var local_925: f32;
    var local_926: f32;
    var local_927: f32;
    var local_928: f32;
    var local_929: f32;
    var local_930: f32;
    var local_931: vec2<f32>;
    var local_932: bool;
    var local_933: f32;
    var local_934: f32;
    var local_935: f32;
    var local_936: f32;
    var local_937: f32;
    var local_938: f32;
    var local_939: f32;
    var local_940: f32;
    var local_941: f32;
    var local_942: f32;
    var local_943: f32;
    var local_944: f32;
    var local_945: f32;
    var local_946: f32;
    var local_947: f32;
    var local_948: f32;
    var local_949: f32;
    var local_950: f32;
    var local_951: f32;
    var local_952: f32;
    var local_953: f32;
    var local_954: f32;
    var local_955: f32;
    var local_956: f32;
    var local_957: f32;
    var local_958: f32;
    var local_959: f32;
    var local_960: f32;
    var local_961: f32;
    var local_962: f32;
    var local_963: f32;
    var local_964: f32;
    var local_965: f32;
    var local_966: f32;
    var local_967: f32;
    var local_968: f32;
    var local_969: f32;
    var local_970: f32;
    var local_971: f32;
    var local_972: f32;
    var local_973: f32;
    var local_974: f32;
    var local_975: f32;
    var local_976: f32;
    var local_977: f32;
    var local_978: bool;
    var local_979: f32;
    var local_980: bool;
    var local_981: bool;
    var local_982: f32;
    var local_983: f32;
    var local_984: f32;
    var local_985: f32;
    var local_986: f32;
    var local_987: f32;
    var local_988: f32;
    var local_989: vec2<f32>;
    var local_990: bool;
    var local_991: f32;
    var local_992: f32;
    var local_993: f32;
    var local_994: f32;
    var local_995: f32;
    var local_996: f32;
    var local_997: f32;
    var local_998: f32;
    var local_999: f32;
    var local_1000: f32;
    var local_1001: f32;
    var local_1002: f32;
    var local_1003: f32;
    var local_1004: f32;
    var local_1005: u32;
    var local_1006: f32;
    var local_1007: f32;
    var local_1008: i32;
    var local_1009: f32;
    var local_1010: f32;
    var local_1011: i32;
    var local_1012: f32;
    var local_1013: f32;
    var local_1014: bool;
    var local_1015: f32;
    var local_1016: i32;
    var local_1017: f32;
    var local_1018: f32;
    var local_1019: f32;
    var local_1020: f32;
    var local_1021: f32;
    var local_1022: f32;
    var local_1023: f32;
    var local_1024: f32;
    var local_1025: f32;
    var local_1026: f32;
    var local_1027: f32;
    var local_1028: f32;
    var local_1029: f32;
    var local_1030: f32;
    var local_1031: bool;
    var local_1032: f32;
    var local_1033: f32;
    var local_1034: f32;
    var local_1035: f32;
    var local_1036: f32;
    var local_1037: f32;
    var local_1038: f32;
    var local_1039: f32;
    var local_1040: f32;
    var local_1041: f32;
    var local_1042: f32;
    var local_1043: f32;
    var local_1044: f32;
    var local_1045: f32;
    var local_1046: bool;
    var local_1047: f32;
    var local_1048: f32;
    var local_1049: f32;
    var local_1050: f32;
    var local_1051: f32;
    var local_1052: f32;
    var local_1053: f32;
    var local_1054: f32;
    var local_1055: f32;
    var local_1056: f32;
    var local_1057: f32;
    var local_1058: f32;
    var local_1059: f32;
    var local_1060: f32;
    var local_1061: f32;
    var local_1062: f32;
    var local_1063: f32;
    var local_1064: f32;
    var local_1065: f32;
    var local_1066: f32;
    var local_1067: f32;
    var local_1068: f32;
    var local_1069: f32;
    var local_1070: f32;
    var local_1071: f32;
    var local_1072: f32;
    var local_1073: f32;
    var local_1074: f32;
    var local_1075: f32;
    var local_1076: f32;
    var local_1077: f32;
    var local_1078: f32;
    var local_1079: f32;
    var local_1080: f32;
    var local_1081: f32;
    var local_1082: f32;
    var local_1083: f32;
    var local_1084: f32;
    var local_1085: f32;
    var local_1086: f32;
    var local_1087: f32;
    var local_1088: f32;
    var local_1089: f32;
    var local_1090: f32;
    var local_1091: f32;
    var local_1092: f32;
    var local_1093: f32;
    var local_1094: f32;
    var local_1095: f32;
    var local_1096: f32;
    var local_1097: f32;
    var local_1098: f32;
    var local_1099: f32;
    var local_1100: f32;
    var local_1101: f32;
    var local_1102: f32;
    var local_1103: f32;
    var local_1104: f32;
    var local_1105: f32;
    var local_1106: bool;
    var local_1107: f32;
    var local_1108: f32;
    var local_1109: f32;
    var local_1110: f32;
    var local_1111: f32;
    var local_1112: f32;
    var local_1113: f32;
    var local_1114: u32;
    var local_1115: f32;
    var local_1116: f32;
    var local_1117: f32;
    var local_1118: f32;
    var local_1119: vec2<f32>;
    var local_1120: f32;
    var local_1121: f32;
    var local_1122: f32;
    var local_1123: f32;
    var local_1124: f32;
    var local_1125: f32;
    var local_1126: f32;
    var local_1127: f32;
    var local_1128: f32;
    var local_1129: f32;
    var local_1130: f32;
    var local_1131: f32;
    var local_1132: f32;
    var local_1133: f32;
    var local_1134: f32;
    var local_1135: bool;
    var local_1136: f32;
    var local_1137: f32;
    var local_1138: vec2<f32>;
    var local_1139: f32;
    var local_1140: bool;
    var local_1141: f32;
    var local_1142: f32;
    var local_1143: vec2<f32>;
    var local_1144: f32;
    var local_1145: bool;
    var local_1146: f32;
    var local_1147: f32;
    var local_1148: bool;
    var local_1149: i32;
    var local_1150: vec2<i32>;
    var local_1151: i32;
    var local_1152: i32;
    var local_1153: vec2<u32>;
    var local_1154: vec2<i32>;
    var local_1155: i32;
    var local_1156: f32;
    var local_1157: f32;
    var local_1158: vec2<f32>;
    var local_1159: f32;
    var local_1160: bool;
    var local_1161: bool;
    var local_1162: bool;
    var local_1163: bool;
    var local_1164: f32;
    var local_1165: f32;
    var local_1166: f32;
    var local_1167: i32;
    var local_1168: f32;
    var local_1169: bool;
    var local_1170: f32;
    var local_1171: f32;
    var local_1172: f32;
    var local_1173: bool;
    var local_1174: f32;
    var local_1175: f32;
    var local_1176: f32;
    var local_1177: f32;
    var local_1178: bool;
    var local_1179: f32;
    var local_1180: bool;
    var local_1181: bool;
    var local_1182: f32;
    var local_1183: f32;
    var local_1184: f32;
    var local_1185: f32;
    var local_1186: f32;
    var local_1187: f32;
    var local_1188: f32;
    var local_1189: vec2<f32>;
    var local_1190: bool;
    var local_1191: f32;
    var local_1192: f32;
    var local_1193: f32;
    var local_1194: f32;
    var local_1195: f32;
    var local_1196: f32;
    var local_1197: f32;
    var local_1198: f32;
    var local_1199: f32;
    var local_1200: f32;
    var local_1201: f32;
    var local_1202: f32;
    var local_1203: f32;
    var local_1204: f32;
    var local_1205: f32;
    var local_1206: f32;
    var local_1207: f32;
    var local_1208: f32;
    var local_1209: f32;
    var local_1210: f32;
    var local_1211: f32;
    var local_1212: f32;
    var local_1213: f32;
    var local_1214: f32;
    var local_1215: f32;
    var local_1216: f32;
    var local_1217: f32;
    var local_1218: f32;
    var local_1219: f32;
    var local_1220: f32;
    var local_1221: f32;
    var local_1222: f32;
    var local_1223: f32;
    var local_1224: f32;
    var local_1225: f32;
    var local_1226: f32;
    var local_1227: f32;
    var local_1228: f32;
    var local_1229: f32;
    var local_1230: f32;
    var local_1231: f32;
    var local_1232: f32;
    var local_1233: f32;
    var local_1234: f32;
    var local_1235: f32;
    var local_1236: bool;
    var local_1237: f32;
    var local_1238: bool;
    var local_1239: bool;
    var local_1240: f32;
    var local_1241: f32;
    var local_1242: f32;
    var local_1243: f32;
    var local_1244: f32;
    var local_1245: f32;
    var local_1246: f32;
    var local_1247: vec2<f32>;
    var local_1248: bool;
    var local_1249: f32;
    var local_1250: f32;
    var local_1251: f32;
    var local_1252: f32;
    var local_1253: f32;
    var local_1254: f32;
    var local_1255: f32;
    var local_1256: f32;
    var local_1257: f32;
    var local_1258: f32;
    var local_1259: f32;
    var local_1260: f32;
    var local_1261: f32;
    var local_1262: f32;
    var local_1263: u32;
    var local_1264: f32;
    var local_1265: f32;
    var local_1266: i32;
    var local_1267: f32;
    var local_1268: f32;
    var local_1269: i32;
    var local_1270: f32;
    var local_1271: f32;
    var local_1272: bool;
    var local_1273: f32;
    var local_1274: i32;
    var local_1275: f32;
    var local_1276: f32;
    var local_1277: f32;
    var local_1278: f32;
    var local_1279: f32;
    var local_1280: f32;
    var local_1281: f32;
    var local_1282: f32;
    var local_1283: f32;
    var local_1284: f32;
    var local_1285: f32;
    var local_1286: f32;
    var local_1287: f32;
    var local_1288: f32;
    var local_1289: bool;
    var local_1290: f32;
    var local_1291: f32;
    var local_1292: f32;
    var local_1293: f32;
    var local_1294: f32;
    var local_1295: f32;
    var local_1296: f32;
    var local_1297: f32;
    var local_1298: f32;
    var local_1299: f32;
    var local_1300: f32;
    var local_1301: f32;
    var local_1302: f32;
    var local_1303: f32;
    var local_1304: bool;
    var local_1305: f32;
    var local_1306: f32;
    var local_1307: f32;
    var local_1308: f32;
    var local_1309: f32;
    var local_1310: f32;
    var local_1311: f32;
    var local_1312: f32;
    var local_1313: f32;
    var local_1314: f32;
    var local_1315: f32;
    var local_1316: f32;
    var local_1317: f32;
    var local_1318: f32;
    var local_1319: f32;
    var local_1320: f32;
    var local_1321: f32;
    var local_1322: f32;
    var local_1323: f32;
    var local_1324: f32;
    var local_1325: f32;
    var local_1326: f32;
    var local_1327: f32;
    var local_1328: f32;
    var local_1329: f32;
    var local_1330: f32;
    var local_1331: f32;
    var local_1332: f32;
    var local_1333: f32;
    var local_1334: f32;
    var local_1335: f32;
    var local_1336: f32;
    var local_1337: f32;
    var local_1338: f32;
    var local_1339: f32;
    var local_1340: f32;
    var local_1341: f32;
    var local_1342: f32;
    var local_1343: f32;
    var local_1344: f32;
    var local_1345: f32;
    var local_1346: f32;
    var local_1347: f32;
    var local_1348: f32;
    var local_1349: f32;
    var local_1350: f32;
    var local_1351: f32;
    var local_1352: f32;
    var local_1353: f32;
    var local_1354: f32;
    var local_1355: f32;
    var local_1356: f32;
    var local_1357: f32;
    var local_1358: f32;
    var local_1359: f32;
    var local_1360: f32;
    var local_1361: f32;
    var local_1362: f32;
    var local_1363: f32;
    var local_1364: bool;
    var local_1365: f32;
    var local_1366: f32;
    var local_1367: f32;
    var local_1368: f32;
    var local_1369: f32;
    var local_1370: f32;
    var local_1371: f32;
    var local_1372: u32;
    var local_1373: f32;
    var local_1374: f32;
    var local_1375: f32;
    var local_1376: f32;
    var local_1377: vec2<f32>;
    var local_1378: f32;
    var local_1379: f32;
    var local_1380: f32;
    var local_1381: f32;
    var local_1382: f32;
    var local_1383: f32;
    var local_1384: f32;
    var local_1385: f32;
    var local_1386: f32;
    var local_1387: f32;
    var local_1388: f32;
    var local_1389: f32;
    var local_1390: f32;
    var local_1391: f32;
    var local_1392: f32;
    var local_1393: bool;
    var local_1394: f32;
    var local_1395: f32;
    var local_1396: vec2<f32>;
    var local_1397: f32;
    var local_1398: bool;
    var local_1399: f32;
    var local_1400: f32;
    var local_1401: vec2<f32>;
    var local_1402: f32;
    var local_1403: bool;
    var local_1404: f32;
    var local_1405: f32;
    var local_1406: bool;
    var local_1407: i32;
    var local_1408: vec2<i32>;
    var local_1409: i32;
    var local_1410: i32;
    var local_1411: vec2<u32>;
    var local_1412: vec2<i32>;
    var local_1413: i32;
    var local_1414: f32;
    var local_1415: f32;
    var local_1416: vec2<f32>;
    var local_1417: f32;
    var local_1418: bool;
    var local_1419: i32;
    var local_1420: vec2<f32>;
    var local_1421: vec2<f32>;
    var local_1422: f32;
    var local_1423: vec2<i32>;
    var local_1424: i32;
    var local_1425: i32;
    var local_1426: i32;
    var local_1427: i32;
    var local_1428: bool;
    var local_1429: vec2<f32>;
    var local_1430: f32;
    var local_1431: vec2<i32>;
    var local_1432: i32;
    var local_1433: i32;
    var local_1434: i32;
    var local_1435: i32;
    var local_1436: bool;
    var local_1437: f32;
    var local_1438: f32;
    var local_1439: f32;
    var local_1440: i32;
    var local_1441: f32;
    var local_1442: i32;
    var local_1443: f32;
    var local_1444: i32;
    var local_1445: vec2<i32>;
    var local_1446: vec2<i32>;
    var local_1447: i32;
    var local_1448: i32;
    var local_1449: vec4<f32>;
    var local_1450: f32;
    var local_1451: f32;
    var local_1452: f32;
    var local_1453: i32;
    var local_1454: vec2<i32>;
    var local_1455: vec4<f32>;
    var local_1456: f32;
    var local_1457: vec2<f32>;
    var local_1458: vec2<f32>;
    var local_1459: vec2<i32>;
    var local_1460: i32;
    var local_1461: i32;
    var local_1462: vec2<f32>;
    var local_1463: vec2<i32>;
    var local_1464: vec4<f32>;
    var local_1465: bool;
    var local_1466: bool;
    var local_1467: f32;
    var local_1468: f32;
    var local_1469: bool;
    var local_1470: f32;
    var local_1471: f32;
    var local_1472: vec2<f32>;
    var local_1473: vec2<f32>;
    var local_1474: i32;
    var local_1475: vec2<i32>;
    var local_1476: vec4<f32>;
    var local_1477: f32;
    var local_1478: i32;
    var local_1479: vec2<f32>;
    var local_1480: vec2<f32>;
    var local_1481: vec2<f32>;
    var local_1482: vec2<i32>;
    var local_1483: i32;
    var local_1484: vec4<f32>;
    var local_1485: vec4<f32>;
    var local_1486: vec4<f32>;
    var local_1487: vec4<f32>;
    var local_1488: f32;
    var local_1489: vec2<f32>;
    var local_1490: vec2<f32>;
    var local_1491: vec2<i32>;
    var local_1492: i32;
    var local_1493: i32;
    var local_1494: vec2<f32>;
    var local_1495: vec2<i32>;
    var local_1496: vec4<f32>;
    var local_1497: vec4<f32>;
    var local_1498: vec4<f32>;
    var local_1499: vec4<f32>;
    var local_1500: i32;

    local_1500 = 1i;
    switch bitcast<i32>(0u) {
        default: {
            let _e1591 = v_texcoord_0_1;
            let _e1592 = fwidth(_e1591);
            local_1472 = _e1592;
            local_1473 = (vec2<f32>(1f, 1f) / max(_e1592, vec2<f32>(0.000015258789f, 0.000015258789f)));
            let _e1596 = v_glyph_0_1[3u];
            local_1474 = (_e1596 & 255i);
            let _e1599 = v_glyph_0_1[3u];
            if (((_e1599 >> bitcast<u32>(8i)) & 255i) != 255i) {
                discard;
            }
            let _e1604 = local_1474;
            let _e1605 = local_1500;
            if (_e1604 != _e1605) {
                discard;
            }
            let _e1607 = v_glyph_0_1;
            let _e1608 = _e1607.xy;
            local_1475 = _e1608;
            let _e1611 = vec3<i32>(_e1608.x, _e1608.y, 0i);
            let _e1614 = textureLoad(u_layer_tex_0_image, _e1611.xy, _e1611.z);
            local_1476 = _e1614;
            local_1477 = _e1614.w;
            if (_e1614.w >= 0f) {
                discard;
            }
            let _e1618 = PushConstants_0_.layer_base_0_;
            let _e1620 = v_banding_0_1[3u];
            local_1478 = (_e1618 + i32(_e1620));
            let _e1623 = local_1477;
            if (i32((0.5f - _e1623)) == 5i) {
                let _e1627 = v_texcoord_0_1;
                local_1479 = _e1627;
                let _e1628 = local_1472;
                local_1480 = _e1628;
                let _e1629 = local_1473;
                local_1481 = _e1629;
                let _e1630 = local_1475;
                local_1482 = _e1630;
                let _e1631 = local_1476;
                let _e1632 = local_1478;
                local_1483 = _e1632;
                let _e1633 = v_tint_0_1;
                local_1484 = _e1633;
                local_1447 = i32((_e1631.x + 0.5f));
                local_1448 = i32((_e1631.y + 0.5f));
                local_1449 = vec4<f32>(0f, 0f, 0f, 0f);
                local_1450 = 0f;
                local_1451 = 0f;
                local_11 = vec4<f32>(0f, 0f, 0f, 0f);
                local_10 = 0f;
                local_9 = vec4<f32>(0f, 0f, 0f, 0f);
                local_8 = 0f;
                local_1452 = 0f;
                local_1453 = 0i;
                loop {
                    let _e1640 = local_1453;
                    let _e1641 = local_1447;
                    if (_e1640 < _e1641) {
                    } else {
                        break;
                    }
                    let _e1643 = local_1453;
                    let _e1646 = local_1482;
                    let _e1647 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e1650 = local_1446;
                    let _e1653 = vec2<i32>(vec2<i32>(_e1647).x, _e1650.y);
                    let _e1654 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e1659 = vec2<i32>(_e1653.x, vec2<i32>(_e1654).y);
                    local_1446 = _e1659;
                    let _e1665 = (((_e1646.y * _e1659.x) + _e1646.x) + (1i + (_e1643 * 6i)));
                    let _e1674 = vec2<i32>((_e1665 - (i32(floor((f32(_e1665) / f32(_e1659.x)))) * _e1659.x)), (_e1665 / _e1659.x));
                    local_1454 = _e1674;
                    let _e1677 = vec3<i32>(_e1674.x, _e1674.y, 0i);
                    let _e1680 = textureLoad(u_layer_tex_0_image, _e1677.xy, _e1677.z);
                    local_1455 = _e1680;
                    let _e1681 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e1684 = local_1445;
                    let _e1687 = vec2<i32>(vec2<i32>(_e1681).x, _e1684.y);
                    let _e1688 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e1693 = vec2<i32>(_e1687.x, vec2<i32>(_e1688).y);
                    local_1445 = _e1693;
                    let _e1699 = (((_e1674.y * _e1693.x) + _e1674.x) + 1i);
                    let _e1708 = vec2<i32>((_e1699 - (i32(floor((f32(_e1699) / f32(_e1693.x)))) * _e1693.x)), (_e1699 / _e1693.x));
                    let _e1711 = vec3<i32>(_e1708.x, _e1708.y, 0i);
                    let _e1713 = i32(_e1680.x);
                    let _e1715 = bitcast<i32>(_e1680.z);
                    let _e1719 = vec2<i32>((_e1713 & 32767i), i32(_e1680.y));
                    let _e1724 = vec2<i32>(((_e1715 >> bitcast<u32>(16i)) & 65535i), (_e1715 & 65535i));
                    let _e1727 = textureLoad(u_layer_tex_0_image, _e1711.xy, _e1711.z);
                    let _e1731 = local_1479;
                    local_1457 = _e1731;
                    let _e1732 = local_1480;
                    let _e1733 = local_1481;
                    local_1458 = _e1733;
                    local_1459 = _e1719;
                    let _e1734 = local_1483;
                    local_1460 = _e1734;
                    local_1461 = ((_e1713 >> bitcast<u32>(15i)) & 1i);
                    local_1419 = _e1724.y;
                    let _e1741 = ((_e1731.y * _e1727.y) + _e1727.w);
                    let _e1745 = max((abs((_e1732.y * _e1727.y)) * 0.5f), 0.00001f);
                    let _e1748 = clamp(i32((_e1741 - _e1745)), 0i, _e1724.y);
                    let _e1752 = max(_e1748, clamp(i32((_e1741 + _e1745)), 0i, _e1724.y));
                    let _e1759 = ((_e1731.x * _e1727.x) + _e1727.z);
                    let _e1763 = max((abs((_e1732.x * _e1727.x)) * 0.5f), 0.00001f);
                    let _e1766 = clamp(i32((_e1759 - _e1763)), 0i, _e1724.x);
                    local_13 = _e1766;
                    local_12 = max(_e1766, clamp(i32((_e1759 + _e1763)), 0i, _e1724.x));
                    local_1421 = _e1731;
                    local_1422 = _e1733.x;
                    local_1423 = _e1719;
                    local_1424 = 0i;
                    local_1425 = _e1748;
                    local_1426 = _e1752;
                    local_1427 = _e1734;
                    local_1428 = true;
                    local_1404 = 0f;
                    local_1405 = 0f;
                    local_1406 = (_e1748 != _e1752);
                    local_1407 = _e1748;
                    loop {
                        let _e1773 = local_1407;
                        let _e1774 = local_1426;
                        if (_e1773 <= _e1774) {
                        } else {
                            break;
                        }
                        let _e1776 = local_1424;
                        let _e1777 = local_1407;
                        let _e1780 = local_1423;
                        let _e1783 = (_e1780.x + bitcast<i32>(bitcast<u32>((_e1776 + _e1777))));
                        let _e1785 = vec2<i32>(_e1783, _e1780.y);
                        let _e1792 = vec2<i32>(_e1785.x, (_e1785.y + (_e1783 >> bitcast<u32>(12i))));
                        let _e1797 = vec2<i32>((_e1792.x & 4095i), _e1792.y);
                        let _e1798 = local_1427;
                        let _e1801 = vec4<i32>(_e1797.x, _e1797.y, _e1798, 0i);
                        let _e1802 = _e1801.xyz;
                        let _e1809 = textureLoad(u_band_tex_0_image, vec2<i32>(_e1802.x, _e1802.y), i32(_e1802.z), _e1801.w);
                        let _e1810 = _e1809.xy;
                        let _e1814 = (_e1780.x + bitcast<i32>(_e1810.y));
                        let _e1816 = vec2<i32>(_e1814, _e1780.y);
                        let _e1823 = vec2<i32>(_e1816.x, (_e1816.y + (_e1814 >> bitcast<u32>(12i))));
                        local_1408 = vec2<i32>((_e1823.x & 4095i), _e1823.y);
                        local_1409 = bitcast<i32>(_e1810.x);
                        local_1410 = 0i;
                        loop {
                            let _e1831 = local_1410;
                            let _e1832 = local_1409;
                            if (_e1831 < _e1832) {
                            } else {
                                break;
                            }
                            let _e1834 = local_1410;
                            let _e1836 = local_1408;
                            let _e1839 = (_e1836.x + bitcast<i32>(bitcast<u32>(_e1834)));
                            let _e1841 = vec2<i32>(_e1839, _e1836.y);
                            let _e1848 = vec2<i32>(_e1841.x, (_e1841.y + (_e1839 >> bitcast<u32>(12i))));
                            let _e1853 = vec2<i32>((_e1848.x & 4095i), _e1848.y);
                            let _e1854 = local_1427;
                            let _e1857 = vec4<i32>(_e1853.x, _e1853.y, _e1854, 0i);
                            let _e1858 = _e1857.xyz;
                            let _e1865 = textureLoad(u_band_tex_0_image, vec2<i32>(_e1858.x, _e1858.y), i32(_e1858.z), _e1857.w);
                            local_1411 = _e1865.xy;
                            let _e1867 = local_1406;
                            if _e1867 {
                                let _e1868 = local_1407;
                                let _e1869 = local_1411;
                                let _e1874 = local_1425;
                                if (_e1868 != max(bitcast<i32>((_e1869.x >> bitcast<u32>(12u))), _e1874)) {
                                    let _e1877 = local_1410;
                                    local_1410 = (_e1877 + 1i);
                                    continue;
                                }
                            }
                            let _e1879 = local_1411;
                            let _e1886 = vec2<i32>(bitcast<i32>((_e1879.x & 4095u)), bitcast<i32>((_e1879.y & 16383u)));
                            let _e1890 = bitcast<i32>((_e1879.y >> bitcast<u32>(14u)));
                            local_1412 = _e1886;
                            let _e1891 = local_1427;
                            local_1413 = _e1891;
                            let _e1894 = vec4<i32>(_e1886.x, _e1886.y, _e1891, 0i);
                            let _e1895 = _e1894.xyz;
                            let _e1902 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e1895.x, _e1895.y), i32(_e1895.z), _e1894.w);
                            let _e1904 = (_e1886.x + 1i);
                            let _e1906 = vec2<i32>(_e1904, _e1886.y);
                            let _e1913 = vec2<i32>(_e1906.x, (_e1906.y + (_e1904 >> bitcast<u32>(12i))));
                            let _e1918 = vec2<i32>((_e1913.x & 4095i), _e1913.y);
                            let _e1921 = vec4<i32>(_e1918.x, _e1918.y, _e1891, 0i);
                            let _e1922 = _e1921.xyz;
                            let _e1929 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e1922.x, _e1922.y), i32(_e1922.z), _e1921.w);
                            local_25 = _e1890;
                            local_24 = _e1902.xy;
                            local_23 = _e1902.zw;
                            local_22 = _e1929.xy;
                            local_21 = _e1929.zw;
                            if (_e1890 == 1i) {
                                let _e1935 = local_1412;
                                let _e1937 = (_e1935.x + 2i);
                                let _e1939 = vec2<i32>(_e1937, _e1935.y);
                                let _e1946 = vec2<i32>(_e1939.x, (_e1939.y + (_e1937 >> bitcast<u32>(12i))));
                                let _e1951 = vec2<i32>((_e1946.x & 4095i), _e1946.y);
                                let _e1952 = local_1413;
                                let _e1955 = vec4<i32>(_e1951.x, _e1951.y, _e1952, 0i);
                                let _e1956 = _e1955.xyz;
                                let _e1963 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e1956.x, _e1956.y), i32(_e1956.z), _e1955.w);
                                local_20 = vec3<f32>(_e1963.w, _e1963.x, _e1963.y);
                            } else {
                                local_20 = vec3<f32>(1f, 1f, 1f);
                            }
                            let _e1968 = local_20;
                            let _e1969 = local_21;
                            let _e1970 = local_22;
                            let _e1971 = local_23;
                            let _e1972 = local_24;
                            let _e1973 = local_25;
                            let _e1974 = local_1404;
                            local_1414 = _e1974;
                            let _e1975 = local_1405;
                            local_1415 = _e1975;
                            let _e1976 = local_1421;
                            local_1416 = _e1976;
                            let _e1977 = local_1422;
                            local_1417 = _e1977;
                            local_19 = _e1973;
                            local_18 = _e1972;
                            local_17 = _e1971;
                            local_16 = _e1970;
                            local_15 = _e1969;
                            local_14 = _e1968;
                            let _e1978 = local_1428;
                            local_1418 = _e1978;
                            switch bitcast<i32>(0u) {
                                default: {
                                    let _e1980 = local_1418;
                                    if _e1980 {
                                        let _e1981 = local_15;
                                        let _e1982 = local_16;
                                        let _e1983 = local_17;
                                        let _e1984 = local_18;
                                        let _e1985 = local_19;
                                        local_46 = _e1985;
                                        local_45 = _e1984;
                                        local_44 = _e1983;
                                        local_43 = _e1982;
                                        local_42 = _e1981;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e1987 = local_46;
                                                if (_e1987 == 3i) {
                                                    let _e1989 = local_45;
                                                    let _e1991 = local_43;
                                                    local_1363 = max(_e1989.x, _e1991.x);
                                                    break;
                                                }
                                                let _e1994 = local_46;
                                                if (_e1994 == 2i) {
                                                    let _e1996 = local_45;
                                                    let _e1998 = local_44;
                                                    let _e2001 = local_43;
                                                    let _e2003 = local_42;
                                                    local_1363 = max(max(_e1996.x, _e1998.x), max(_e2001.x, _e2003.x));
                                                    break;
                                                }
                                                let _e2007 = local_45;
                                                let _e2009 = local_44;
                                                let _e2012 = local_43;
                                                local_1363 = max(max(_e2007.x, _e2009.x), _e2012.x);
                                                break;
                                            }
                                        }
                                        let _e2015 = local_1363;
                                        let _e2016 = local_1416;
                                        local_1365 = (_e2015 - _e2016.x);
                                    } else {
                                        let _e2019 = local_15;
                                        let _e2020 = local_16;
                                        let _e2021 = local_17;
                                        let _e2022 = local_18;
                                        let _e2023 = local_19;
                                        local_41 = _e2023;
                                        local_40 = _e2022;
                                        local_39 = _e2021;
                                        local_38 = _e2020;
                                        local_37 = _e2019;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e2025 = local_41;
                                                if (_e2025 == 3i) {
                                                    let _e2027 = local_40;
                                                    let _e2029 = local_38;
                                                    local_1362 = max(_e2027.y, _e2029.y);
                                                    break;
                                                }
                                                let _e2032 = local_41;
                                                if (_e2032 == 2i) {
                                                    let _e2034 = local_40;
                                                    let _e2036 = local_39;
                                                    let _e2039 = local_38;
                                                    let _e2041 = local_37;
                                                    local_1362 = max(max(_e2034.y, _e2036.y), max(_e2039.y, _e2041.y));
                                                    break;
                                                }
                                                let _e2045 = local_40;
                                                let _e2047 = local_39;
                                                let _e2050 = local_38;
                                                local_1362 = max(max(_e2045.y, _e2047.y), _e2050.y);
                                                break;
                                            }
                                        }
                                        let _e2053 = local_1362;
                                        let _e2054 = local_1416;
                                        local_1365 = (_e2053 - _e2054.y);
                                    }
                                    let _e2057 = local_1365;
                                    let _e2058 = local_1417;
                                    if ((_e2057 * _e2058) < -0.5f) {
                                        local_1364 = false;
                                        break;
                                    }
                                    let _e2061 = local_19;
                                    if (_e2061 == 0i) {
                                        let _e2063 = local_1416;
                                        let _e2065 = local_18;
                                        local_1366 = (_e2065.x - _e2063.x);
                                        local_1367 = (_e2065.y - _e2063.y);
                                        let _e2071 = local_17;
                                        local_1368 = (_e2071.x - _e2063.x);
                                        local_1369 = (_e2071.y - _e2063.y);
                                        let _e2076 = local_16;
                                        local_1370 = (_e2076.x - _e2063.x);
                                        local_1371 = (_e2076.y - _e2063.y);
                                        let _e2081 = local_1418;
                                        if _e2081 {
                                            let _e2082 = local_1367;
                                            local_1373 = _e2082;
                                            let _e2083 = local_1369;
                                            local_1374 = _e2083;
                                            let _e2084 = local_1371;
                                            local_1359 = _e2084;
                                            if (abs(_e2084) <= 0.000015258789f) {
                                                local_1358 = 0f;
                                            } else {
                                                let _e2087 = local_1359;
                                                local_1358 = _e2087;
                                            }
                                            let _e2088 = local_1358;
                                            let _e2093 = local_1374;
                                            local_1360 = _e2093;
                                            if (abs(_e2093) <= 0.000015258789f) {
                                                local_1357 = 0f;
                                            } else {
                                                let _e2096 = local_1360;
                                                local_1357 = _e2096;
                                            }
                                            let _e2097 = local_1357;
                                            let _e2102 = local_1373;
                                            local_1361 = _e2102;
                                            if (abs(_e2102) <= 0.000015258789f) {
                                                local_1356 = 0f;
                                            } else {
                                                let _e2105 = local_1361;
                                                local_1356 = _e2105;
                                            }
                                            let _e2106 = local_1356;
                                            local_1372 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e2088) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e2097) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e2106) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                        } else {
                                            let _e2117 = local_1366;
                                            local_1375 = _e2117;
                                            let _e2118 = local_1368;
                                            local_1376 = _e2118;
                                            let _e2119 = local_1370;
                                            local_1353 = _e2119;
                                            if (abs(_e2119) <= 0.000015258789f) {
                                                local_1352 = 0f;
                                            } else {
                                                let _e2122 = local_1353;
                                                local_1352 = _e2122;
                                            }
                                            let _e2123 = local_1352;
                                            let _e2128 = local_1376;
                                            local_1354 = _e2128;
                                            if (abs(_e2128) <= 0.000015258789f) {
                                                local_1351 = 0f;
                                            } else {
                                                let _e2131 = local_1354;
                                                local_1351 = _e2131;
                                            }
                                            let _e2132 = local_1351;
                                            let _e2137 = local_1375;
                                            local_1355 = _e2137;
                                            if (abs(_e2137) <= 0.000015258789f) {
                                                local_1350 = 0f;
                                            } else {
                                                let _e2140 = local_1355;
                                                local_1350 = _e2140;
                                            }
                                            let _e2141 = local_1350;
                                            local_1372 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e2123) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e2132) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e2141) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                        }
                                        let _e2152 = local_1372;
                                        if (_e2152 == 0u) {
                                            local_1364 = true;
                                            break;
                                        }
                                        let _e2154 = local_1418;
                                        if _e2154 {
                                            let _e2155 = local_1366;
                                            local_1378 = _e2155;
                                            let _e2156 = local_1367;
                                            local_1379 = _e2156;
                                            let _e2157 = local_1368;
                                            let _e2158 = local_1369;
                                            let _e2159 = local_1370;
                                            let _e2160 = local_1371;
                                            let _e2161 = local_1417;
                                            local_1380 = _e2161;
                                            local_1338 = ((_e2155 - (_e2157 * 2f)) + _e2159);
                                            let _e2167 = ((_e2156 - (_e2158 * 2f)) + _e2160);
                                            local_1339 = _e2167;
                                            local_1340 = (_e2155 - _e2157);
                                            local_1341 = (_e2156 - _e2158);
                                            if (abs(_e2167) < 0.000015258789f) {
                                                let _e2172 = local_1341;
                                                if (abs(_e2172) < 0.000015258789f) {
                                                    local_1342 = 0f;
                                                } else {
                                                    let _e2175 = local_1379;
                                                    let _e2177 = local_1341;
                                                    local_1342 = ((_e2175 * 0.5f) / _e2177);
                                                }
                                                let _e2179 = local_1342;
                                                local_1343 = _e2179;
                                            } else {
                                                let _e2180 = local_1339;
                                                let _e2181 = local_1379;
                                                let _e2182 = (_e2180 * _e2181);
                                                let _e2183 = local_1341;
                                                let _e2185 = ((_e2183 * _e2183) - _e2182);
                                                local_1345 = _e2185;
                                                if (_e2185 <= (max((_e2183 * _e2183), abs(_e2182)) * 0.000003f)) {
                                                    local_1337 = 0f;
                                                } else {
                                                    let _e2191 = local_1345;
                                                    local_1337 = sqrt(_e2191);
                                                }
                                                let _e2193 = local_1337;
                                                local_1344 = _e2193;
                                                let _e2194 = local_1341;
                                                if (_e2194 >= 0f) {
                                                    let _e2196 = local_1341;
                                                    let _e2197 = local_1344;
                                                    let _e2198 = (_e2196 + _e2197);
                                                    local_1346 = _e2198;
                                                    let _e2199 = local_1339;
                                                    local_1347 = (_e2198 / _e2199);
                                                    if (abs(_e2198) < 0.000015258789f) {
                                                        local_1342 = 0f;
                                                    } else {
                                                        let _e2203 = local_1379;
                                                        let _e2204 = local_1346;
                                                        local_1342 = (_e2203 / _e2204);
                                                    }
                                                    let _e2206 = local_1347;
                                                    local_1343 = _e2206;
                                                } else {
                                                    let _e2207 = local_1341;
                                                    let _e2208 = local_1344;
                                                    let _e2209 = (_e2207 - _e2208);
                                                    local_1348 = _e2209;
                                                    let _e2210 = local_1339;
                                                    local_1349 = (_e2209 / _e2210);
                                                    if (abs(_e2209) < 0.000015258789f) {
                                                        local_1342 = 0f;
                                                    } else {
                                                        let _e2214 = local_1379;
                                                        let _e2215 = local_1348;
                                                        local_1342 = (_e2214 / _e2215);
                                                    }
                                                    let _e2217 = local_1342;
                                                    let _e2218 = local_1349;
                                                    local_1342 = _e2218;
                                                    local_1343 = _e2217;
                                                }
                                            }
                                            let _e2219 = local_1340;
                                            let _e2220 = (_e2219 * 2f);
                                            let _e2221 = local_1338;
                                            let _e2222 = local_1342;
                                            let _e2226 = local_1378;
                                            let _e2228 = local_1380;
                                            let _e2230 = local_1343;
                                            local_1377 = vec2<f32>((((((_e2221 * _e2222) - _e2220) * _e2222) + _e2226) * _e2228), (((((_e2221 * _e2230) - _e2220) * _e2230) + _e2226) * _e2228));
                                        } else {
                                            let _e2237 = local_1366;
                                            local_1381 = _e2237;
                                            let _e2238 = local_1367;
                                            local_1382 = _e2238;
                                            let _e2239 = local_1368;
                                            let _e2240 = local_1369;
                                            let _e2241 = local_1370;
                                            let _e2242 = local_1371;
                                            let _e2243 = local_1417;
                                            local_1383 = _e2243;
                                            let _e2246 = ((_e2237 - (_e2239 * 2f)) + _e2241);
                                            local_1325 = _e2246;
                                            local_1326 = ((_e2238 - (_e2240 * 2f)) + _e2242);
                                            local_1327 = (_e2237 - _e2239);
                                            local_1328 = (_e2238 - _e2240);
                                            if (abs(_e2246) < 0.000015258789f) {
                                                let _e2254 = local_1327;
                                                if (abs(_e2254) < 0.000015258789f) {
                                                    local_1329 = 0f;
                                                } else {
                                                    let _e2257 = local_1381;
                                                    let _e2259 = local_1327;
                                                    local_1329 = ((_e2257 * 0.5f) / _e2259);
                                                }
                                                let _e2261 = local_1329;
                                                local_1330 = _e2261;
                                            } else {
                                                let _e2262 = local_1325;
                                                let _e2263 = local_1381;
                                                let _e2264 = (_e2262 * _e2263);
                                                let _e2265 = local_1327;
                                                let _e2267 = ((_e2265 * _e2265) - _e2264);
                                                local_1332 = _e2267;
                                                if (_e2267 <= (max((_e2265 * _e2265), abs(_e2264)) * 0.000003f)) {
                                                    local_1324 = 0f;
                                                } else {
                                                    let _e2273 = local_1332;
                                                    local_1324 = sqrt(_e2273);
                                                }
                                                let _e2275 = local_1324;
                                                local_1331 = _e2275;
                                                let _e2276 = local_1327;
                                                if (_e2276 >= 0f) {
                                                    let _e2278 = local_1327;
                                                    let _e2279 = local_1331;
                                                    let _e2280 = (_e2278 + _e2279);
                                                    local_1333 = _e2280;
                                                    let _e2281 = local_1325;
                                                    local_1334 = (_e2280 / _e2281);
                                                    if (abs(_e2280) < 0.000015258789f) {
                                                        local_1329 = 0f;
                                                    } else {
                                                        let _e2285 = local_1381;
                                                        let _e2286 = local_1333;
                                                        local_1329 = (_e2285 / _e2286);
                                                    }
                                                    let _e2288 = local_1334;
                                                    local_1330 = _e2288;
                                                } else {
                                                    let _e2289 = local_1327;
                                                    let _e2290 = local_1331;
                                                    let _e2291 = (_e2289 - _e2290);
                                                    local_1335 = _e2291;
                                                    let _e2292 = local_1325;
                                                    local_1336 = (_e2291 / _e2292);
                                                    if (abs(_e2291) < 0.000015258789f) {
                                                        local_1329 = 0f;
                                                    } else {
                                                        let _e2296 = local_1381;
                                                        let _e2297 = local_1335;
                                                        local_1329 = (_e2296 / _e2297);
                                                    }
                                                    let _e2299 = local_1329;
                                                    let _e2300 = local_1336;
                                                    local_1329 = _e2300;
                                                    local_1330 = _e2299;
                                                }
                                            }
                                            let _e2301 = local_1328;
                                            let _e2302 = (_e2301 * 2f);
                                            let _e2303 = local_1326;
                                            let _e2304 = local_1329;
                                            let _e2308 = local_1382;
                                            let _e2310 = local_1383;
                                            let _e2312 = local_1330;
                                            local_1377 = vec2<f32>((((((_e2303 * _e2304) - _e2302) * _e2304) + _e2308) * _e2310), (((((_e2303 * _e2312) - _e2302) * _e2312) + _e2308) * _e2310));
                                        }
                                        let _e2319 = local_1372;
                                        if ((_e2319 & 1u) != 0u) {
                                            let _e2322 = local_1377;
                                            local_1384 = _e2322.x;
                                            let _e2324 = local_1418;
                                            if _e2324 {
                                                local_1365 = 1f;
                                            } else {
                                                local_1365 = -1f;
                                            }
                                            let _e2325 = local_1414;
                                            let _e2326 = local_1415;
                                            let _e2327 = local_1384;
                                            let _e2328 = local_1365;
                                            local_1414 = (_e2325 + (_e2328 * clamp((_e2327 + 0.5f), 0f, 1f)));
                                            local_1415 = max(_e2326, clamp((1f - (abs(_e2327) * 2f)), 0f, 1f));
                                        }
                                        let _e2338 = local_1372;
                                        if (_e2338 > 1u) {
                                            let _e2340 = local_1377;
                                            local_1385 = _e2340.y;
                                            let _e2342 = local_1418;
                                            if _e2342 {
                                                local_1365 = -1f;
                                            } else {
                                                local_1365 = 1f;
                                            }
                                            let _e2343 = local_1414;
                                            let _e2344 = local_1415;
                                            let _e2345 = local_1385;
                                            let _e2346 = local_1365;
                                            local_1414 = (_e2343 + (_e2346 * clamp((_e2345 + 0.5f), 0f, 1f)));
                                            local_1415 = max(_e2344, clamp((1f - (abs(_e2345) * 2f)), 0f, 1f));
                                        }
                                        local_1364 = true;
                                        break;
                                    }
                                    let _e2356 = local_19;
                                    if (_e2356 == 3i) {
                                        let _e2358 = local_1416;
                                        let _e2361 = local_18;
                                        let _e2366 = local_16;
                                        let _e2371 = local_1414;
                                        local_1386 = _e2371;
                                        let _e2372 = local_1415;
                                        local_1387 = _e2372;
                                        local_1388 = (_e2361.x - _e2358.x);
                                        local_1389 = (_e2361.y - _e2358.y);
                                        local_1390 = (_e2366.x - _e2358.x);
                                        local_1391 = (_e2366.y - _e2358.y);
                                        let _e2373 = local_1417;
                                        local_1392 = _e2373;
                                        let _e2374 = local_1418;
                                        local_1393 = _e2374;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e2376 = local_1393;
                                                if _e2376 {
                                                    let _e2377 = local_1389;
                                                    local_1316 = _e2377;
                                                } else {
                                                    let _e2378 = local_1388;
                                                    local_1316 = _e2378;
                                                }
                                                let _e2379 = local_1393;
                                                if _e2379 {
                                                    let _e2380 = local_1391;
                                                    local_1317 = _e2380;
                                                } else {
                                                    let _e2381 = local_1390;
                                                    local_1317 = _e2381;
                                                }
                                                let _e2382 = local_1316;
                                                local_1318 = _e2382;
                                                if (abs(_e2382) <= 0.000015258789f) {
                                                    local_1315 = 0f;
                                                } else {
                                                    let _e2385 = local_1318;
                                                    local_1315 = _e2385;
                                                }
                                                let _e2386 = local_1315;
                                                let _e2388 = local_1317;
                                                local_1319 = _e2388;
                                                if (abs(_e2388) <= 0.000015258789f) {
                                                    local_1314 = 0f;
                                                } else {
                                                    let _e2391 = local_1319;
                                                    local_1314 = _e2391;
                                                }
                                                let _e2392 = local_1314;
                                                if ((_e2386 < 0f) == (_e2392 < 0f)) {
                                                    break;
                                                }
                                                let _e2395 = local_1317;
                                                let _e2396 = local_1316;
                                                let _e2397 = (_e2395 - _e2396);
                                                local_1320 = _e2397;
                                                if (abs(_e2397) < 0.0000000001f) {
                                                    break;
                                                }
                                                let _e2400 = local_1316;
                                                let _e2402 = local_1320;
                                                local_1321 = clamp((-(_e2400) / _e2402), 0f, 1f);
                                                let _e2405 = local_1393;
                                                if _e2405 {
                                                    let _e2406 = local_1391;
                                                    let _e2407 = local_1389;
                                                    local_1322 = (_e2406 - _e2407);
                                                } else {
                                                    let _e2409 = local_1388;
                                                    let _e2410 = local_1390;
                                                    local_1322 = (_e2409 - _e2410);
                                                }
                                                let _e2412 = local_1322;
                                                if (abs(_e2412) <= 0.00001f) {
                                                    break;
                                                }
                                                let _e2415 = local_1393;
                                                if _e2415 {
                                                    let _e2416 = local_1388;
                                                    let _e2417 = local_1390;
                                                    let _e2419 = local_1321;
                                                    local_1316 = (_e2416 + ((_e2417 - _e2416) * _e2419));
                                                } else {
                                                    let _e2422 = local_1389;
                                                    let _e2423 = local_1391;
                                                    let _e2425 = local_1321;
                                                    local_1316 = (_e2422 + ((_e2423 - _e2422) * _e2425));
                                                }
                                                let _e2428 = local_1316;
                                                let _e2429 = local_1392;
                                                local_1323 = (_e2428 * _e2429);
                                                let _e2431 = local_1322;
                                                if (_e2431 > 0f) {
                                                    local_1316 = 1f;
                                                } else {
                                                    local_1316 = -1f;
                                                }
                                                let _e2433 = local_1386;
                                                let _e2434 = local_1387;
                                                let _e2435 = local_1323;
                                                let _e2436 = local_1316;
                                                local_1386 = (_e2433 + (_e2436 * clamp((_e2435 + 0.5f), 0f, 1f)));
                                                local_1387 = max(_e2434, clamp((1f - (abs(_e2435) * 2f)), 0f, 1f));
                                                break;
                                            }
                                        }
                                        let _e2446 = local_1386;
                                        local_1414 = _e2446;
                                        let _e2447 = local_1387;
                                        local_1415 = _e2447;
                                        local_1364 = true;
                                        break;
                                    }
                                    let _e2448 = local_19;
                                    if (_e2448 == 1i) {
                                        let _e2450 = local_1414;
                                        local_1394 = _e2450;
                                        let _e2451 = local_1415;
                                        local_1395 = _e2451;
                                        let _e2452 = local_14;
                                        let _e2453 = local_15;
                                        let _e2454 = local_16;
                                        let _e2455 = local_17;
                                        let _e2456 = local_18;
                                        let _e2457 = local_19;
                                        local_36 = _e2457;
                                        local_35 = _e2456;
                                        local_34 = _e2455;
                                        local_33 = _e2454;
                                        local_32 = _e2453;
                                        local_31 = _e2452;
                                        let _e2458 = local_1416;
                                        local_1396 = _e2458;
                                        let _e2459 = local_1417;
                                        local_1397 = _e2459;
                                        let _e2460 = local_1418;
                                        local_1398 = _e2460;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e2462 = local_32;
                                                let _e2463 = local_33;
                                                let _e2464 = local_34;
                                                let _e2465 = local_35;
                                                let _e2466 = local_36;
                                                local_51 = _e2466;
                                                local_50 = _e2465;
                                                local_49 = _e2464;
                                                local_48 = _e2463;
                                                local_47 = _e2462;
                                                let _e2467 = local_1396;
                                                local_1247 = _e2467;
                                                let _e2468 = local_1398;
                                                local_1248 = _e2468;
                                                switch bitcast<i32>(0u) {
                                                    default: {
                                                        let _e2470 = local_1248;
                                                        if _e2470 {
                                                            let _e2471 = local_1247;
                                                            local_1240 = _e2471.y;
                                                        } else {
                                                            let _e2473 = local_1247;
                                                            local_1240 = _e2473.x;
                                                        }
                                                        let _e2475 = local_51;
                                                        if (_e2475 == 2i) {
                                                            let _e2477 = local_1248;
                                                            if _e2477 {
                                                                let _e2478 = local_50;
                                                                local_1241 = _e2478.y;
                                                            } else {
                                                                let _e2480 = local_50;
                                                                local_1241 = _e2480.x;
                                                            }
                                                            let _e2482 = local_1248;
                                                            if _e2482 {
                                                                let _e2483 = local_49;
                                                                local_1242 = _e2483.y;
                                                            } else {
                                                                let _e2485 = local_49;
                                                                local_1242 = _e2485.x;
                                                            }
                                                            let _e2487 = local_1248;
                                                            if _e2487 {
                                                                let _e2488 = local_48;
                                                                local_1243 = _e2488.y;
                                                            } else {
                                                                let _e2490 = local_48;
                                                                local_1243 = _e2490.x;
                                                            }
                                                            let _e2492 = local_1248;
                                                            if _e2492 {
                                                                let _e2493 = local_47;
                                                                local_1244 = _e2493.y;
                                                            } else {
                                                                let _e2495 = local_47;
                                                                local_1244 = _e2495.x;
                                                            }
                                                            let _e2497 = local_1241;
                                                            let _e2498 = local_1242;
                                                            let _e2499 = local_1243;
                                                            let _e2500 = local_1244;
                                                            let _e2501 = local_1240;
                                                            local_1245 = _e2501;
                                                            local_1237 = max(max(_e2497, _e2498), max(_e2499, _e2500));
                                                            if ((min(min(_e2497, _e2498), min(_e2499, _e2500)) - _e2501) <= 0.000015258789f) {
                                                                let _e2510 = local_1237;
                                                                let _e2511 = local_1245;
                                                                local_1238 = ((_e2510 - _e2511) >= -0.000015258789f);
                                                            } else {
                                                                local_1238 = false;
                                                            }
                                                            let _e2514 = local_1238;
                                                            local_1239 = _e2514;
                                                            break;
                                                        }
                                                        let _e2515 = local_1248;
                                                        if _e2515 {
                                                            let _e2516 = local_50;
                                                            local_1241 = _e2516.y;
                                                        } else {
                                                            let _e2518 = local_50;
                                                            local_1241 = _e2518.x;
                                                        }
                                                        let _e2520 = local_1248;
                                                        if _e2520 {
                                                            let _e2521 = local_49;
                                                            local_1242 = _e2521.y;
                                                        } else {
                                                            let _e2523 = local_49;
                                                            local_1242 = _e2523.x;
                                                        }
                                                        let _e2525 = local_1248;
                                                        if _e2525 {
                                                            let _e2526 = local_48;
                                                            local_1243 = _e2526.y;
                                                        } else {
                                                            let _e2528 = local_48;
                                                            local_1243 = _e2528.x;
                                                        }
                                                        let _e2530 = local_1241;
                                                        let _e2531 = local_1242;
                                                        let _e2532 = local_1243;
                                                        let _e2533 = local_1240;
                                                        local_1246 = _e2533;
                                                        local_1235 = max(max(_e2530, _e2531), _e2532);
                                                        if ((min(min(_e2530, _e2531), _e2532) - _e2533) <= 0.000015258789f) {
                                                            let _e2540 = local_1235;
                                                            let _e2541 = local_1246;
                                                            local_1236 = ((_e2540 - _e2541) >= -0.000015258789f);
                                                        } else {
                                                            local_1236 = false;
                                                        }
                                                        let _e2544 = local_1236;
                                                        local_1239 = _e2544;
                                                        break;
                                                    }
                                                }
                                                let _e2545 = local_1239;
                                                if !(_e2545) {
                                                    break;
                                                }
                                                let _e2547 = local_1398;
                                                if _e2547 {
                                                    let _e2548 = local_1396;
                                                    local_1249 = _e2548.y;
                                                } else {
                                                    let _e2550 = local_1396;
                                                    local_1249 = _e2550.x;
                                                }
                                                let _e2552 = local_1398;
                                                if _e2552 {
                                                    let _e2553 = local_1396;
                                                    local_1250 = _e2553.x;
                                                } else {
                                                    let _e2555 = local_1396;
                                                    local_1250 = _e2555.y;
                                                }
                                                let _e2557 = local_1398;
                                                if _e2557 {
                                                    let _e2558 = local_35;
                                                    local_1251 = _e2558.y;
                                                } else {
                                                    let _e2560 = local_35;
                                                    local_1251 = _e2560.x;
                                                }
                                                let _e2562 = local_1398;
                                                if _e2562 {
                                                    let _e2563 = local_34;
                                                    local_1252 = _e2563.y;
                                                } else {
                                                    let _e2565 = local_34;
                                                    local_1252 = _e2565.x;
                                                }
                                                let _e2567 = local_1398;
                                                if _e2567 {
                                                    let _e2568 = local_33;
                                                    local_1253 = _e2568.y;
                                                } else {
                                                    let _e2570 = local_33;
                                                    local_1253 = _e2570.x;
                                                }
                                                let _e2572 = local_1398;
                                                if _e2572 {
                                                    let _e2573 = local_35;
                                                    local_1254 = _e2573.x;
                                                } else {
                                                    let _e2575 = local_35;
                                                    local_1254 = _e2575.y;
                                                }
                                                let _e2577 = local_1398;
                                                if _e2577 {
                                                    let _e2578 = local_34;
                                                    local_1255 = _e2578.x;
                                                } else {
                                                    let _e2580 = local_34;
                                                    local_1255 = _e2580.y;
                                                }
                                                let _e2582 = local_1398;
                                                if _e2582 {
                                                    let _e2583 = local_33;
                                                    local_1256 = _e2583.x;
                                                } else {
                                                    let _e2585 = local_33;
                                                    local_1256 = _e2585.y;
                                                }
                                                let _e2587 = local_31;
                                                local_1257 = _e2587.x;
                                                let _e2589 = local_1251;
                                                let _e2590 = local_1249;
                                                let _e2592 = (_e2587.x * (_e2589 - _e2590));
                                                local_1258 = _e2592;
                                                local_1259 = _e2587.y;
                                                let _e2594 = local_1252;
                                                let _e2596 = (_e2587.y * (_e2594 - _e2590));
                                                local_1260 = _e2596;
                                                local_1261 = _e2587.z;
                                                let _e2598 = local_1253;
                                                let _e2600 = (_e2587.z * (_e2598 - _e2590));
                                                local_1262 = _e2600;
                                                local_1264 = _e2592;
                                                local_1265 = _e2596;
                                                local_1232 = _e2600;
                                                if (abs(_e2600) <= 0.000015258789f) {
                                                    local_1231 = 0f;
                                                } else {
                                                    let _e2603 = local_1232;
                                                    local_1231 = _e2603;
                                                }
                                                let _e2604 = local_1231;
                                                let _e2609 = local_1265;
                                                local_1233 = _e2609;
                                                if (abs(_e2609) <= 0.000015258789f) {
                                                    local_1230 = 0f;
                                                } else {
                                                    let _e2612 = local_1233;
                                                    local_1230 = _e2612;
                                                }
                                                let _e2613 = local_1230;
                                                let _e2618 = local_1264;
                                                local_1234 = _e2618;
                                                if (abs(_e2618) <= 0.000015258789f) {
                                                    local_1229 = 0f;
                                                } else {
                                                    let _e2621 = local_1234;
                                                    local_1229 = _e2621;
                                                }
                                                let _e2622 = local_1229;
                                                let _e2632 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e2604) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e2613) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e2622) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                                local_1263 = _e2632;
                                                if (_e2632 == 0u) {
                                                    break;
                                                }
                                                let _e2634 = local_1263;
                                                if (_e2634 == 257u) {
                                                    local_1266 = 2i;
                                                } else {
                                                    local_1266 = 1i;
                                                }
                                                let _e2636 = local_1258;
                                                let _e2637 = local_1260;
                                                let _e2640 = local_1262;
                                                let _e2641 = ((_e2636 - (2f * _e2637)) + _e2640);
                                                local_1267 = _e2641;
                                                local_1268 = (2f * (_e2637 - _e2636));
                                                if (abs(_e2641) < 0.000015258789f) {
                                                    let _e2646 = local_1268;
                                                    if (abs(_e2646) >= 0.000015258789f) {
                                                        let _e2649 = local_1258;
                                                        let _e2651 = local_1268;
                                                        local_1269 = 1i;
                                                        local_1270 = (-(_e2649) / _e2651);
                                                    } else {
                                                        local_1269 = 0i;
                                                        local_1270 = 0f;
                                                    }
                                                    let _e2653 = local_1270;
                                                    local_1270 = 0f;
                                                    local_1271 = _e2653;
                                                } else {
                                                    let _e2654 = local_1268;
                                                    let _e2656 = local_1267;
                                                    let _e2658 = local_1258;
                                                    let _e2662 = sqrt(max(((_e2654 * _e2654) - ((4f * _e2656) * _e2658)), 0f));
                                                    let _e2663 = (0.5f / _e2656);
                                                    let _e2664 = -(_e2654);
                                                    local_1269 = 2i;
                                                    local_1270 = ((_e2664 + _e2662) * _e2663);
                                                    local_1271 = ((_e2664 - _e2662) * _e2663);
                                                }
                                                let _e2669 = local_1269;
                                                if (_e2669 == 0i) {
                                                    break;
                                                }
                                                let _e2671 = local_1266;
                                                if (_e2671 == 1i) {
                                                    let _e2673 = local_1269;
                                                    if (_e2673 == 2i) {
                                                        let _e2675 = local_1270;
                                                        let _e2680 = local_1271;
                                                        local_1272 = (max(max(0f, -(_e2675)), (_e2675 - 1f)) < max(max(0f, -(_e2680)), (_e2680 - 1f)));
                                                    } else {
                                                        local_1272 = false;
                                                    }
                                                    let _e2686 = local_1272;
                                                    if _e2686 {
                                                        let _e2687 = local_1270;
                                                        local_1273 = _e2687;
                                                    } else {
                                                        let _e2688 = local_1271;
                                                        local_1273 = _e2688;
                                                    }
                                                    let _e2689 = local_1273;
                                                    local_1273 = clamp(_e2689, 0f, 1f);
                                                    local_1274 = 1i;
                                                    local_1275 = 0f;
                                                } else {
                                                    let _e2691 = local_1270;
                                                    let _e2693 = local_1271;
                                                    local_1273 = clamp(_e2693, 0f, 1f);
                                                    local_1274 = 2i;
                                                    local_1275 = clamp(_e2691, 0f, 1f);
                                                }
                                                let _e2695 = local_1251;
                                                let _e2696 = local_1257;
                                                let _e2697 = (_e2695 * _e2696);
                                                local_1276 = _e2697;
                                                let _e2698 = local_1252;
                                                let _e2700 = local_1259;
                                                let _e2703 = local_1253;
                                                let _e2704 = local_1261;
                                                local_1277 = ((_e2697 - ((2f * _e2698) * _e2700)) + (_e2703 * _e2704));
                                                local_1278 = (2f * ((_e2698 * _e2700) - _e2697));
                                                let _e2710 = local_1254;
                                                let _e2711 = (_e2710 * _e2696);
                                                local_1279 = _e2711;
                                                let _e2712 = local_1255;
                                                let _e2716 = local_1256;
                                                local_1280 = ((_e2711 - ((2f * _e2712) * _e2700)) + (_e2716 * _e2704));
                                                local_1281 = (2f * ((_e2712 * _e2700) - _e2711));
                                                local_1282 = ((_e2696 - (2f * _e2700)) + _e2704);
                                                local_1283 = (2f * (_e2700 - _e2696));
                                                let _e2727 = local_1394;
                                                local_1284 = _e2727;
                                                let _e2728 = local_1395;
                                                local_1285 = _e2728;
                                                let _e2729 = local_1273;
                                                local_1286 = _e2729;
                                                let _e2730 = local_1250;
                                                local_1287 = _e2730;
                                                let _e2731 = local_1397;
                                                local_1288 = _e2731;
                                                let _e2732 = local_1398;
                                                local_1289 = _e2732;
                                                let _e2733 = local_1277;
                                                local_1290 = _e2733;
                                                let _e2734 = local_1278;
                                                local_1291 = _e2734;
                                                let _e2735 = local_1276;
                                                local_1292 = _e2735;
                                                let _e2736 = local_1280;
                                                local_1293 = _e2736;
                                                let _e2737 = local_1281;
                                                local_1294 = _e2737;
                                                let _e2738 = local_1279;
                                                local_1295 = _e2738;
                                                let _e2739 = local_1282;
                                                local_1296 = _e2739;
                                                let _e2740 = local_1283;
                                                local_1297 = _e2740;
                                                let _e2741 = local_1257;
                                                local_1298 = _e2741;
                                                switch bitcast<i32>(0u) {
                                                    default: {
                                                        let _e2743 = local_1296;
                                                        let _e2744 = local_1286;
                                                        let _e2746 = local_1297;
                                                        let _e2749 = local_1298;
                                                        let _e2751 = max(((((_e2743 * _e2744) + _e2746) * _e2744) + _e2749), 0.000015258789f);
                                                        let _e2752 = local_1293;
                                                        let _e2754 = local_1294;
                                                        let _e2757 = local_1295;
                                                        local_1225 = (((((_e2752 * _e2744) + _e2754) * _e2744) + _e2757) / _e2751);
                                                        let _e2760 = local_1290;
                                                        let _e2763 = local_1291;
                                                        let _e2769 = local_1292;
                                                        local_1226 = ((((((2f * _e2760) * _e2744) + _e2763) * _e2751) - (((((_e2760 * _e2744) + _e2763) * _e2744) + _e2769) * (((2f * _e2743) * _e2744) + _e2746))) / (_e2751 * _e2751));
                                                        let _e2778 = local_1289;
                                                        if !(_e2778) {
                                                            let _e2780 = local_1226;
                                                            local_1227 = -(_e2780);
                                                        } else {
                                                            let _e2782 = local_1226;
                                                            local_1227 = _e2782;
                                                        }
                                                        let _e2783 = local_1227;
                                                        if (abs(_e2783) <= 0.00001f) {
                                                            break;
                                                        }
                                                        let _e2786 = local_1225;
                                                        let _e2787 = local_1287;
                                                        let _e2789 = local_1288;
                                                        local_1228 = ((_e2786 - _e2787) * _e2789);
                                                        let _e2791 = local_1227;
                                                        if (_e2791 > 0f) {
                                                            local_1227 = 1f;
                                                        } else {
                                                            local_1227 = -1f;
                                                        }
                                                        let _e2793 = local_1284;
                                                        let _e2794 = local_1285;
                                                        let _e2795 = local_1228;
                                                        let _e2796 = local_1227;
                                                        local_1284 = (_e2793 + (_e2796 * clamp((_e2795 + 0.5f), 0f, 1f)));
                                                        local_1285 = max(_e2794, clamp((1f - (abs(_e2795) * 2f)), 0f, 1f));
                                                        break;
                                                    }
                                                }
                                                let _e2806 = local_1284;
                                                local_1394 = _e2806;
                                                let _e2807 = local_1285;
                                                local_1395 = _e2807;
                                                let _e2808 = local_1274;
                                                if (_e2808 == 2i) {
                                                    let _e2810 = local_1394;
                                                    local_1299 = _e2810;
                                                    let _e2811 = local_1395;
                                                    local_1300 = _e2811;
                                                    let _e2812 = local_1275;
                                                    local_1301 = _e2812;
                                                    let _e2813 = local_1250;
                                                    local_1302 = _e2813;
                                                    let _e2814 = local_1397;
                                                    local_1303 = _e2814;
                                                    let _e2815 = local_1398;
                                                    local_1304 = _e2815;
                                                    let _e2816 = local_1277;
                                                    local_1305 = _e2816;
                                                    let _e2817 = local_1278;
                                                    local_1306 = _e2817;
                                                    let _e2818 = local_1276;
                                                    local_1307 = _e2818;
                                                    let _e2819 = local_1280;
                                                    local_1308 = _e2819;
                                                    let _e2820 = local_1281;
                                                    local_1309 = _e2820;
                                                    let _e2821 = local_1279;
                                                    local_1310 = _e2821;
                                                    let _e2822 = local_1282;
                                                    local_1311 = _e2822;
                                                    let _e2823 = local_1283;
                                                    local_1312 = _e2823;
                                                    let _e2824 = local_1257;
                                                    local_1313 = _e2824;
                                                    switch bitcast<i32>(0u) {
                                                        default: {
                                                            let _e2826 = local_1311;
                                                            let _e2827 = local_1301;
                                                            let _e2829 = local_1312;
                                                            let _e2832 = local_1313;
                                                            let _e2834 = max(((((_e2826 * _e2827) + _e2829) * _e2827) + _e2832), 0.000015258789f);
                                                            let _e2835 = local_1308;
                                                            let _e2837 = local_1309;
                                                            let _e2840 = local_1310;
                                                            local_1221 = (((((_e2835 * _e2827) + _e2837) * _e2827) + _e2840) / _e2834);
                                                            let _e2843 = local_1305;
                                                            let _e2846 = local_1306;
                                                            let _e2852 = local_1307;
                                                            local_1222 = ((((((2f * _e2843) * _e2827) + _e2846) * _e2834) - (((((_e2843 * _e2827) + _e2846) * _e2827) + _e2852) * (((2f * _e2826) * _e2827) + _e2829))) / (_e2834 * _e2834));
                                                            let _e2861 = local_1304;
                                                            if !(_e2861) {
                                                                let _e2863 = local_1222;
                                                                local_1223 = -(_e2863);
                                                            } else {
                                                                let _e2865 = local_1222;
                                                                local_1223 = _e2865;
                                                            }
                                                            let _e2866 = local_1223;
                                                            if (abs(_e2866) <= 0.00001f) {
                                                                break;
                                                            }
                                                            let _e2869 = local_1221;
                                                            let _e2870 = local_1302;
                                                            let _e2872 = local_1303;
                                                            local_1224 = ((_e2869 - _e2870) * _e2872);
                                                            let _e2874 = local_1223;
                                                            if (_e2874 > 0f) {
                                                                local_1223 = 1f;
                                                            } else {
                                                                local_1223 = -1f;
                                                            }
                                                            let _e2876 = local_1299;
                                                            let _e2877 = local_1300;
                                                            let _e2878 = local_1224;
                                                            let _e2879 = local_1223;
                                                            local_1299 = (_e2876 + (_e2879 * clamp((_e2878 + 0.5f), 0f, 1f)));
                                                            local_1300 = max(_e2877, clamp((1f - (abs(_e2878) * 2f)), 0f, 1f));
                                                            break;
                                                        }
                                                    }
                                                    let _e2889 = local_1299;
                                                    local_1394 = _e2889;
                                                    let _e2890 = local_1300;
                                                    local_1395 = _e2890;
                                                }
                                                break;
                                            }
                                        }
                                        let _e2891 = local_1394;
                                        local_1414 = _e2891;
                                        let _e2892 = local_1395;
                                        local_1415 = _e2892;
                                        local_1364 = true;
                                        break;
                                    }
                                    let _e2893 = local_1414;
                                    local_1399 = _e2893;
                                    let _e2894 = local_1415;
                                    local_1400 = _e2894;
                                    let _e2895 = local_15;
                                    let _e2896 = local_16;
                                    let _e2897 = local_17;
                                    let _e2898 = local_18;
                                    let _e2899 = local_19;
                                    local_30 = _e2899;
                                    local_29 = _e2898;
                                    local_28 = _e2897;
                                    local_27 = _e2896;
                                    local_26 = _e2895;
                                    let _e2900 = local_1416;
                                    local_1401 = _e2900;
                                    let _e2901 = local_1417;
                                    local_1402 = _e2901;
                                    let _e2902 = local_1418;
                                    local_1403 = _e2902;
                                    switch bitcast<i32>(0u) {
                                        default: {
                                            let _e2904 = local_26;
                                            let _e2905 = local_27;
                                            let _e2906 = local_28;
                                            let _e2907 = local_29;
                                            let _e2908 = local_30;
                                            local_56 = _e2908;
                                            local_55 = _e2907;
                                            local_54 = _e2906;
                                            local_53 = _e2905;
                                            local_52 = _e2904;
                                            let _e2909 = local_1401;
                                            local_1189 = _e2909;
                                            let _e2910 = local_1403;
                                            local_1190 = _e2910;
                                            switch bitcast<i32>(0u) {
                                                default: {
                                                    let _e2912 = local_1190;
                                                    if _e2912 {
                                                        let _e2913 = local_1189;
                                                        local_1182 = _e2913.y;
                                                    } else {
                                                        let _e2915 = local_1189;
                                                        local_1182 = _e2915.x;
                                                    }
                                                    let _e2917 = local_56;
                                                    if (_e2917 == 2i) {
                                                        let _e2919 = local_1190;
                                                        if _e2919 {
                                                            let _e2920 = local_55;
                                                            local_1183 = _e2920.y;
                                                        } else {
                                                            let _e2922 = local_55;
                                                            local_1183 = _e2922.x;
                                                        }
                                                        let _e2924 = local_1190;
                                                        if _e2924 {
                                                            let _e2925 = local_54;
                                                            local_1184 = _e2925.y;
                                                        } else {
                                                            let _e2927 = local_54;
                                                            local_1184 = _e2927.x;
                                                        }
                                                        let _e2929 = local_1190;
                                                        if _e2929 {
                                                            let _e2930 = local_53;
                                                            local_1185 = _e2930.y;
                                                        } else {
                                                            let _e2932 = local_53;
                                                            local_1185 = _e2932.x;
                                                        }
                                                        let _e2934 = local_1190;
                                                        if _e2934 {
                                                            let _e2935 = local_52;
                                                            local_1186 = _e2935.y;
                                                        } else {
                                                            let _e2937 = local_52;
                                                            local_1186 = _e2937.x;
                                                        }
                                                        let _e2939 = local_1183;
                                                        let _e2940 = local_1184;
                                                        let _e2941 = local_1185;
                                                        let _e2942 = local_1186;
                                                        let _e2943 = local_1182;
                                                        local_1187 = _e2943;
                                                        local_1179 = max(max(_e2939, _e2940), max(_e2941, _e2942));
                                                        if ((min(min(_e2939, _e2940), min(_e2941, _e2942)) - _e2943) <= 0.000015258789f) {
                                                            let _e2952 = local_1179;
                                                            let _e2953 = local_1187;
                                                            local_1180 = ((_e2952 - _e2953) >= -0.000015258789f);
                                                        } else {
                                                            local_1180 = false;
                                                        }
                                                        let _e2956 = local_1180;
                                                        local_1181 = _e2956;
                                                        break;
                                                    }
                                                    let _e2957 = local_1190;
                                                    if _e2957 {
                                                        let _e2958 = local_55;
                                                        local_1183 = _e2958.y;
                                                    } else {
                                                        let _e2960 = local_55;
                                                        local_1183 = _e2960.x;
                                                    }
                                                    let _e2962 = local_1190;
                                                    if _e2962 {
                                                        let _e2963 = local_54;
                                                        local_1184 = _e2963.y;
                                                    } else {
                                                        let _e2965 = local_54;
                                                        local_1184 = _e2965.x;
                                                    }
                                                    let _e2967 = local_1190;
                                                    if _e2967 {
                                                        let _e2968 = local_53;
                                                        local_1185 = _e2968.y;
                                                    } else {
                                                        let _e2970 = local_53;
                                                        local_1185 = _e2970.x;
                                                    }
                                                    let _e2972 = local_1183;
                                                    let _e2973 = local_1184;
                                                    let _e2974 = local_1185;
                                                    let _e2975 = local_1182;
                                                    local_1188 = _e2975;
                                                    local_1177 = max(max(_e2972, _e2973), _e2974);
                                                    if ((min(min(_e2972, _e2973), _e2974) - _e2975) <= 0.000015258789f) {
                                                        let _e2982 = local_1177;
                                                        let _e2983 = local_1188;
                                                        local_1178 = ((_e2982 - _e2983) >= -0.000015258789f);
                                                    } else {
                                                        local_1178 = false;
                                                    }
                                                    let _e2986 = local_1178;
                                                    local_1181 = _e2986;
                                                    break;
                                                }
                                            }
                                            let _e2987 = local_1181;
                                            if !(_e2987) {
                                                break;
                                            }
                                            let _e2989 = local_1403;
                                            if _e2989 {
                                                let _e2990 = local_1401;
                                                local_1191 = _e2990.y;
                                            } else {
                                                let _e2992 = local_1401;
                                                local_1191 = _e2992.x;
                                            }
                                            let _e2994 = local_1403;
                                            if _e2994 {
                                                let _e2995 = local_1401;
                                                local_1192 = _e2995.x;
                                            } else {
                                                let _e2997 = local_1401;
                                                local_1192 = _e2997.y;
                                            }
                                            let _e2999 = local_1403;
                                            if _e2999 {
                                                let _e3000 = local_29;
                                                local_1193 = _e3000.y;
                                            } else {
                                                let _e3002 = local_29;
                                                local_1193 = _e3002.x;
                                            }
                                            let _e3004 = local_1403;
                                            if _e3004 {
                                                let _e3005 = local_28;
                                                local_1194 = _e3005.y;
                                            } else {
                                                let _e3007 = local_28;
                                                local_1194 = _e3007.x;
                                            }
                                            let _e3009 = local_1403;
                                            if _e3009 {
                                                let _e3010 = local_27;
                                                local_1195 = _e3010.y;
                                            } else {
                                                let _e3012 = local_27;
                                                local_1195 = _e3012.x;
                                            }
                                            let _e3014 = local_1403;
                                            if _e3014 {
                                                let _e3015 = local_26;
                                                local_1196 = _e3015.y;
                                            } else {
                                                let _e3017 = local_26;
                                                local_1196 = _e3017.x;
                                            }
                                            let _e3019 = local_1403;
                                            if _e3019 {
                                                let _e3020 = local_29;
                                                local_1197 = _e3020.x;
                                            } else {
                                                let _e3022 = local_29;
                                                local_1197 = _e3022.y;
                                            }
                                            let _e3024 = local_1403;
                                            if _e3024 {
                                                let _e3025 = local_28;
                                                local_1198 = _e3025.x;
                                            } else {
                                                let _e3027 = local_28;
                                                local_1198 = _e3027.y;
                                            }
                                            let _e3029 = local_1403;
                                            if _e3029 {
                                                let _e3030 = local_27;
                                                local_1199 = _e3030.x;
                                            } else {
                                                let _e3032 = local_27;
                                                local_1199 = _e3032.y;
                                            }
                                            let _e3034 = local_1403;
                                            if _e3034 {
                                                let _e3035 = local_26;
                                                local_1200 = _e3035.x;
                                            } else {
                                                let _e3037 = local_26;
                                                local_1200 = _e3037.y;
                                            }
                                            let _e3039 = local_1194;
                                            let _e3040 = (3f * _e3039);
                                            let _e3041 = local_1195;
                                            let _e3042 = (3f * _e3041);
                                            let _e3043 = local_1193;
                                            let _e3046 = local_1196;
                                            local_1201 = (((_e3040 - _e3043) - _e3042) + _e3046);
                                            local_1202 = (((3f * _e3043) - (6f * _e3039)) + _e3042);
                                            local_1203 = ((-3f * _e3043) + _e3040);
                                            let _e3054 = local_1191;
                                            let _e3055 = (_e3043 - _e3054);
                                            local_1204 = _e3055;
                                            local_1205 = (_e3046 - _e3054);
                                            local_1206 = _e3055;
                                            if (abs(_e3055) <= 0.000015258789f) {
                                                local_1176 = 0f;
                                            } else {
                                                let _e3059 = local_1206;
                                                local_1176 = _e3059;
                                            }
                                            let _e3060 = local_1176;
                                            let _e3062 = local_1205;
                                            local_1207 = _e3062;
                                            if (abs(_e3062) <= 0.000015258789f) {
                                                local_1175 = 0f;
                                            } else {
                                                let _e3065 = local_1207;
                                                local_1175 = _e3065;
                                            }
                                            let _e3066 = local_1175;
                                            if ((_e3060 < 0f) == (_e3066 < 0f)) {
                                                break;
                                            }
                                            local_1208 = 0f;
                                            let _e3069 = local_1204;
                                            if (abs(_e3069) <= 0.000015258789f) {
                                                local_1208 = 0f;
                                            } else {
                                                let _e3072 = local_1205;
                                                if (abs(_e3072) <= 0.000015258789f) {
                                                    local_1208 = 1f;
                                                } else {
                                                    let _e3075 = local_1201;
                                                    local_1209 = _e3075;
                                                    let _e3076 = local_1202;
                                                    local_1210 = _e3076;
                                                    let _e3077 = local_1203;
                                                    local_1211 = _e3077;
                                                    let _e3078 = local_1204;
                                                    local_1212 = _e3078;
                                                    let _e3079 = local_1205;
                                                    local_1213 = _e3079;
                                                    switch bitcast<i32>(0u) {
                                                        default: {
                                                            let _e3081 = local_1212;
                                                            if (_e3081 < -0.000015258789f) {
                                                                let _e3083 = local_1213;
                                                                local_1162 = (_e3083 < -0.000015258789f);
                                                            } else {
                                                                local_1162 = false;
                                                            }
                                                            let _e3085 = local_1162;
                                                            if _e3085 {
                                                                local_1162 = true;
                                                            } else {
                                                                let _e3086 = local_1212;
                                                                if (_e3086 > 0.000015258789f) {
                                                                    let _e3088 = local_1213;
                                                                    local_1162 = (_e3088 > 0.000015258789f);
                                                                } else {
                                                                    local_1162 = false;
                                                                }
                                                            }
                                                            let _e3090 = local_1162;
                                                            if _e3090 {
                                                                local_1161 = false;
                                                                break;
                                                            }
                                                            let _e3091 = local_1213;
                                                            let _e3092 = local_1212;
                                                            local_1163 = (_e3091 >= _e3092);
                                                            local_1164 = 0.5f;
                                                            local_1165 = 0f;
                                                            local_1166 = 1f;
                                                            local_1167 = 0i;
                                                            loop {
                                                                let _e3094 = local_1167;
                                                                if (_e3094 < 16i) {
                                                                } else {
                                                                    break;
                                                                }
                                                                let _e3096 = local_1209;
                                                                let _e3097 = local_1164;
                                                                let _e3099 = local_1210;
                                                                let _e3102 = local_1211;
                                                                let _e3105 = local_1212;
                                                                local_1168 = ((((((_e3096 * _e3097) + _e3099) * _e3097) + _e3102) * _e3097) + _e3105);
                                                                let _e3107 = local_1163;
                                                                if _e3107 {
                                                                    let _e3108 = local_1168;
                                                                    local_1162 = (_e3108 < 0f);
                                                                } else {
                                                                    local_1162 = false;
                                                                }
                                                                let _e3110 = local_1162;
                                                                if _e3110 {
                                                                    local_1169 = true;
                                                                } else {
                                                                    let _e3111 = local_1163;
                                                                    if !(_e3111) {
                                                                        let _e3113 = local_1168;
                                                                        local_1169 = (_e3113 > 0f);
                                                                    } else {
                                                                        local_1169 = false;
                                                                    }
                                                                }
                                                                let _e3115 = local_1169;
                                                                if _e3115 {
                                                                    let _e3116 = local_1164;
                                                                    local_1165 = _e3116;
                                                                } else {
                                                                    let _e3117 = local_1164;
                                                                    local_1166 = _e3117;
                                                                }
                                                                let _e3118 = local_1209;
                                                                let _e3120 = local_1164;
                                                                let _e3122 = local_1210;
                                                                let _e3126 = local_1211;
                                                                let _e3127 = (((((3f * _e3118) * _e3120) + (2f * _e3122)) * _e3120) + _e3126);
                                                                local_1170 = _e3127;
                                                                let _e3128 = local_1165;
                                                                let _e3129 = local_1166;
                                                                local_1171 = ((_e3128 + _e3129) * 0.5f);
                                                                if (abs(_e3127) >= 0.000001f) {
                                                                    let _e3134 = local_1164;
                                                                    let _e3135 = local_1168;
                                                                    let _e3136 = local_1170;
                                                                    let _e3138 = (_e3134 - (_e3135 / _e3136));
                                                                    local_1172 = _e3138;
                                                                    let _e3139 = local_1165;
                                                                    if (_e3138 > _e3139) {
                                                                        let _e3141 = local_1172;
                                                                        let _e3142 = local_1166;
                                                                        local_1173 = (_e3141 < _e3142);
                                                                    } else {
                                                                        local_1173 = false;
                                                                    }
                                                                    let _e3144 = local_1173;
                                                                    if _e3144 {
                                                                        let _e3145 = local_1172;
                                                                        local_1174 = _e3145;
                                                                    } else {
                                                                        let _e3146 = local_1171;
                                                                        local_1174 = _e3146;
                                                                    }
                                                                } else {
                                                                    let _e3147 = local_1171;
                                                                    local_1174 = _e3147;
                                                                }
                                                                let _e3148 = local_1167;
                                                                let _e3150 = local_1174;
                                                                local_1164 = _e3150;
                                                                local_1167 = (_e3148 + 1i);
                                                                continue;
                                                            }
                                                            let _e3151 = local_1164;
                                                            local_1214 = _e3151;
                                                            local_1161 = true;
                                                            break;
                                                        }
                                                    }
                                                    let _e3152 = local_1161;
                                                    let _e3153 = local_1214;
                                                    local_1208 = _e3153;
                                                    if !(_e3152) {
                                                        break;
                                                    }
                                                }
                                            }
                                            let _e3155 = local_1198;
                                            let _e3156 = (3f * _e3155);
                                            let _e3157 = local_1199;
                                            let _e3158 = (3f * _e3157);
                                            let _e3159 = local_1197;
                                            let _e3162 = local_1200;
                                            local_1215 = (((_e3156 - _e3159) - _e3158) + _e3162);
                                            local_1216 = (((3f * _e3159) - (6f * _e3155)) + _e3158);
                                            local_1217 = ((-3f * _e3159) + _e3156);
                                            let _e3170 = local_1208;
                                            if (_e3170 == 1f) {
                                                let _e3172 = local_1200;
                                                local_1218 = _e3172;
                                            } else {
                                                let _e3173 = local_1215;
                                                let _e3174 = local_1208;
                                                let _e3176 = local_1216;
                                                let _e3179 = local_1217;
                                                let _e3182 = local_1197;
                                                local_1218 = ((((((_e3173 * _e3174) + _e3176) * _e3174) + _e3179) * _e3174) + _e3182);
                                            }
                                            let _e3184 = local_1403;
                                            if _e3184 {
                                                let _e3185 = local_1196;
                                                let _e3186 = local_1193;
                                                local_1219 = (_e3185 - _e3186);
                                            } else {
                                                let _e3188 = local_1193;
                                                let _e3189 = local_1196;
                                                local_1219 = (_e3188 - _e3189);
                                            }
                                            let _e3191 = local_1218;
                                            let _e3192 = local_1192;
                                            let _e3194 = local_1402;
                                            local_1220 = ((_e3191 - _e3192) * _e3194);
                                            let _e3196 = local_1219;
                                            if (_e3196 > 0f) {
                                                local_1191 = 1f;
                                            } else {
                                                local_1191 = -1f;
                                            }
                                            let _e3198 = local_1399;
                                            let _e3199 = local_1400;
                                            let _e3200 = local_1220;
                                            let _e3201 = local_1191;
                                            local_1399 = (_e3198 + (_e3201 * clamp((_e3200 + 0.5f), 0f, 1f)));
                                            local_1400 = max(_e3199, clamp((1f - (abs(_e3200) * 2f)), 0f, 1f));
                                            break;
                                        }
                                    }
                                    let _e3211 = local_1399;
                                    local_1414 = _e3211;
                                    let _e3212 = local_1400;
                                    local_1415 = _e3212;
                                    local_1364 = true;
                                    break;
                                }
                            }
                            let _e3213 = local_1364;
                            let _e3214 = local_1414;
                            local_1404 = _e3214;
                            let _e3215 = local_1415;
                            local_1405 = _e3215;
                            if !(_e3213) {
                                break;
                            }
                            let _e3217 = local_1410;
                            local_1410 = (_e3217 + 1i);
                            continue;
                        }
                        let _e3219 = local_1407;
                        local_1407 = (_e3219 + 1i);
                        continue;
                    }
                    let _e3221 = local_1404;
                    let _e3222 = local_1405;
                    local_1420 = vec2<f32>(_e3221, _e3222);
                    let _e3224 = local_1419;
                    let _e3226 = local_1457;
                    local_1429 = _e3226;
                    let _e3227 = local_1458;
                    local_1430 = _e3227.y;
                    let _e3229 = local_1459;
                    local_1431 = _e3229;
                    local_1432 = (_e3224 + 1i);
                    let _e3230 = local_13;
                    local_1433 = _e3230;
                    let _e3231 = local_12;
                    local_1434 = _e3231;
                    let _e3232 = local_1460;
                    local_1435 = _e3232;
                    local_1436 = false;
                    local_1146 = 0f;
                    local_1147 = 0f;
                    local_1148 = (_e3230 != _e3231);
                    local_1149 = _e3230;
                    loop {
                        let _e3234 = local_1149;
                        let _e3235 = local_1434;
                        if (_e3234 <= _e3235) {
                        } else {
                            break;
                        }
                        let _e3237 = local_1432;
                        let _e3238 = local_1149;
                        let _e3241 = local_1431;
                        let _e3244 = (_e3241.x + bitcast<i32>(bitcast<u32>((_e3237 + _e3238))));
                        let _e3246 = vec2<i32>(_e3244, _e3241.y);
                        let _e3253 = vec2<i32>(_e3246.x, (_e3246.y + (_e3244 >> bitcast<u32>(12i))));
                        let _e3258 = vec2<i32>((_e3253.x & 4095i), _e3253.y);
                        let _e3259 = local_1435;
                        let _e3262 = vec4<i32>(_e3258.x, _e3258.y, _e3259, 0i);
                        let _e3263 = _e3262.xyz;
                        let _e3270 = textureLoad(u_band_tex_0_image, vec2<i32>(_e3263.x, _e3263.y), i32(_e3263.z), _e3262.w);
                        let _e3271 = _e3270.xy;
                        let _e3275 = (_e3241.x + bitcast<i32>(_e3271.y));
                        let _e3277 = vec2<i32>(_e3275, _e3241.y);
                        let _e3284 = vec2<i32>(_e3277.x, (_e3277.y + (_e3275 >> bitcast<u32>(12i))));
                        local_1150 = vec2<i32>((_e3284.x & 4095i), _e3284.y);
                        local_1151 = bitcast<i32>(_e3271.x);
                        local_1152 = 0i;
                        loop {
                            let _e3292 = local_1152;
                            let _e3293 = local_1151;
                            if (_e3292 < _e3293) {
                            } else {
                                break;
                            }
                            let _e3295 = local_1152;
                            let _e3297 = local_1150;
                            let _e3300 = (_e3297.x + bitcast<i32>(bitcast<u32>(_e3295)));
                            let _e3302 = vec2<i32>(_e3300, _e3297.y);
                            let _e3309 = vec2<i32>(_e3302.x, (_e3302.y + (_e3300 >> bitcast<u32>(12i))));
                            let _e3314 = vec2<i32>((_e3309.x & 4095i), _e3309.y);
                            let _e3315 = local_1435;
                            let _e3318 = vec4<i32>(_e3314.x, _e3314.y, _e3315, 0i);
                            let _e3319 = _e3318.xyz;
                            let _e3326 = textureLoad(u_band_tex_0_image, vec2<i32>(_e3319.x, _e3319.y), i32(_e3319.z), _e3318.w);
                            local_1153 = _e3326.xy;
                            let _e3328 = local_1148;
                            if _e3328 {
                                let _e3329 = local_1149;
                                let _e3330 = local_1153;
                                let _e3335 = local_1433;
                                if (_e3329 != max(bitcast<i32>((_e3330.x >> bitcast<u32>(12u))), _e3335)) {
                                    let _e3338 = local_1152;
                                    local_1152 = (_e3338 + 1i);
                                    continue;
                                }
                            }
                            let _e3340 = local_1153;
                            let _e3347 = vec2<i32>(bitcast<i32>((_e3340.x & 4095u)), bitcast<i32>((_e3340.y & 16383u)));
                            let _e3351 = bitcast<i32>((_e3340.y >> bitcast<u32>(14u)));
                            local_1154 = _e3347;
                            let _e3352 = local_1435;
                            local_1155 = _e3352;
                            let _e3355 = vec4<i32>(_e3347.x, _e3347.y, _e3352, 0i);
                            let _e3356 = _e3355.xyz;
                            let _e3363 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e3356.x, _e3356.y), i32(_e3356.z), _e3355.w);
                            let _e3365 = (_e3347.x + 1i);
                            let _e3367 = vec2<i32>(_e3365, _e3347.y);
                            let _e3374 = vec2<i32>(_e3367.x, (_e3367.y + (_e3365 >> bitcast<u32>(12i))));
                            let _e3379 = vec2<i32>((_e3374.x & 4095i), _e3374.y);
                            let _e3382 = vec4<i32>(_e3379.x, _e3379.y, _e3352, 0i);
                            let _e3383 = _e3382.xyz;
                            let _e3390 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e3383.x, _e3383.y), i32(_e3383.z), _e3382.w);
                            local_68 = _e3351;
                            local_67 = _e3363.xy;
                            local_66 = _e3363.zw;
                            local_65 = _e3390.xy;
                            local_64 = _e3390.zw;
                            if (_e3351 == 1i) {
                                let _e3396 = local_1154;
                                let _e3398 = (_e3396.x + 2i);
                                let _e3400 = vec2<i32>(_e3398, _e3396.y);
                                let _e3407 = vec2<i32>(_e3400.x, (_e3400.y + (_e3398 >> bitcast<u32>(12i))));
                                let _e3412 = vec2<i32>((_e3407.x & 4095i), _e3407.y);
                                let _e3413 = local_1155;
                                let _e3416 = vec4<i32>(_e3412.x, _e3412.y, _e3413, 0i);
                                let _e3417 = _e3416.xyz;
                                let _e3424 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e3417.x, _e3417.y), i32(_e3417.z), _e3416.w);
                                local_63 = vec3<f32>(_e3424.w, _e3424.x, _e3424.y);
                            } else {
                                local_63 = vec3<f32>(1f, 1f, 1f);
                            }
                            let _e3429 = local_63;
                            let _e3430 = local_64;
                            let _e3431 = local_65;
                            let _e3432 = local_66;
                            let _e3433 = local_67;
                            let _e3434 = local_68;
                            let _e3435 = local_1146;
                            local_1156 = _e3435;
                            let _e3436 = local_1147;
                            local_1157 = _e3436;
                            let _e3437 = local_1429;
                            local_1158 = _e3437;
                            let _e3438 = local_1430;
                            local_1159 = _e3438;
                            local_62 = _e3434;
                            local_61 = _e3433;
                            local_60 = _e3432;
                            local_59 = _e3431;
                            local_58 = _e3430;
                            local_57 = _e3429;
                            let _e3439 = local_1436;
                            local_1160 = _e3439;
                            switch bitcast<i32>(0u) {
                                default: {
                                    let _e3441 = local_1160;
                                    if _e3441 {
                                        let _e3442 = local_58;
                                        let _e3443 = local_59;
                                        let _e3444 = local_60;
                                        let _e3445 = local_61;
                                        let _e3446 = local_62;
                                        local_89 = _e3446;
                                        local_88 = _e3445;
                                        local_87 = _e3444;
                                        local_86 = _e3443;
                                        local_85 = _e3442;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e3448 = local_89;
                                                if (_e3448 == 3i) {
                                                    let _e3450 = local_88;
                                                    let _e3452 = local_86;
                                                    local_1105 = max(_e3450.x, _e3452.x);
                                                    break;
                                                }
                                                let _e3455 = local_89;
                                                if (_e3455 == 2i) {
                                                    let _e3457 = local_88;
                                                    let _e3459 = local_87;
                                                    let _e3462 = local_86;
                                                    let _e3464 = local_85;
                                                    local_1105 = max(max(_e3457.x, _e3459.x), max(_e3462.x, _e3464.x));
                                                    break;
                                                }
                                                let _e3468 = local_88;
                                                let _e3470 = local_87;
                                                let _e3473 = local_86;
                                                local_1105 = max(max(_e3468.x, _e3470.x), _e3473.x);
                                                break;
                                            }
                                        }
                                        let _e3476 = local_1105;
                                        let _e3477 = local_1158;
                                        local_1107 = (_e3476 - _e3477.x);
                                    } else {
                                        let _e3480 = local_58;
                                        let _e3481 = local_59;
                                        let _e3482 = local_60;
                                        let _e3483 = local_61;
                                        let _e3484 = local_62;
                                        local_84 = _e3484;
                                        local_83 = _e3483;
                                        local_82 = _e3482;
                                        local_81 = _e3481;
                                        local_80 = _e3480;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e3486 = local_84;
                                                if (_e3486 == 3i) {
                                                    let _e3488 = local_83;
                                                    let _e3490 = local_81;
                                                    local_1104 = max(_e3488.y, _e3490.y);
                                                    break;
                                                }
                                                let _e3493 = local_84;
                                                if (_e3493 == 2i) {
                                                    let _e3495 = local_83;
                                                    let _e3497 = local_82;
                                                    let _e3500 = local_81;
                                                    let _e3502 = local_80;
                                                    local_1104 = max(max(_e3495.y, _e3497.y), max(_e3500.y, _e3502.y));
                                                    break;
                                                }
                                                let _e3506 = local_83;
                                                let _e3508 = local_82;
                                                let _e3511 = local_81;
                                                local_1104 = max(max(_e3506.y, _e3508.y), _e3511.y);
                                                break;
                                            }
                                        }
                                        let _e3514 = local_1104;
                                        let _e3515 = local_1158;
                                        local_1107 = (_e3514 - _e3515.y);
                                    }
                                    let _e3518 = local_1107;
                                    let _e3519 = local_1159;
                                    if ((_e3518 * _e3519) < -0.5f) {
                                        local_1106 = false;
                                        break;
                                    }
                                    let _e3522 = local_62;
                                    if (_e3522 == 0i) {
                                        let _e3524 = local_1158;
                                        let _e3526 = local_61;
                                        local_1108 = (_e3526.x - _e3524.x);
                                        local_1109 = (_e3526.y - _e3524.y);
                                        let _e3532 = local_60;
                                        local_1110 = (_e3532.x - _e3524.x);
                                        local_1111 = (_e3532.y - _e3524.y);
                                        let _e3537 = local_59;
                                        local_1112 = (_e3537.x - _e3524.x);
                                        local_1113 = (_e3537.y - _e3524.y);
                                        let _e3542 = local_1160;
                                        if _e3542 {
                                            let _e3543 = local_1109;
                                            local_1115 = _e3543;
                                            let _e3544 = local_1111;
                                            local_1116 = _e3544;
                                            let _e3545 = local_1113;
                                            local_1101 = _e3545;
                                            if (abs(_e3545) <= 0.000015258789f) {
                                                local_1100 = 0f;
                                            } else {
                                                let _e3548 = local_1101;
                                                local_1100 = _e3548;
                                            }
                                            let _e3549 = local_1100;
                                            let _e3554 = local_1116;
                                            local_1102 = _e3554;
                                            if (abs(_e3554) <= 0.000015258789f) {
                                                local_1099 = 0f;
                                            } else {
                                                let _e3557 = local_1102;
                                                local_1099 = _e3557;
                                            }
                                            let _e3558 = local_1099;
                                            let _e3563 = local_1115;
                                            local_1103 = _e3563;
                                            if (abs(_e3563) <= 0.000015258789f) {
                                                local_1098 = 0f;
                                            } else {
                                                let _e3566 = local_1103;
                                                local_1098 = _e3566;
                                            }
                                            let _e3567 = local_1098;
                                            local_1114 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e3549) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e3558) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e3567) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                        } else {
                                            let _e3578 = local_1108;
                                            local_1117 = _e3578;
                                            let _e3579 = local_1110;
                                            local_1118 = _e3579;
                                            let _e3580 = local_1112;
                                            local_1095 = _e3580;
                                            if (abs(_e3580) <= 0.000015258789f) {
                                                local_1094 = 0f;
                                            } else {
                                                let _e3583 = local_1095;
                                                local_1094 = _e3583;
                                            }
                                            let _e3584 = local_1094;
                                            let _e3589 = local_1118;
                                            local_1096 = _e3589;
                                            if (abs(_e3589) <= 0.000015258789f) {
                                                local_1093 = 0f;
                                            } else {
                                                let _e3592 = local_1096;
                                                local_1093 = _e3592;
                                            }
                                            let _e3593 = local_1093;
                                            let _e3598 = local_1117;
                                            local_1097 = _e3598;
                                            if (abs(_e3598) <= 0.000015258789f) {
                                                local_1092 = 0f;
                                            } else {
                                                let _e3601 = local_1097;
                                                local_1092 = _e3601;
                                            }
                                            let _e3602 = local_1092;
                                            local_1114 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e3584) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e3593) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e3602) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                        }
                                        let _e3613 = local_1114;
                                        if (_e3613 == 0u) {
                                            local_1106 = true;
                                            break;
                                        }
                                        let _e3615 = local_1160;
                                        if _e3615 {
                                            let _e3616 = local_1108;
                                            local_1120 = _e3616;
                                            let _e3617 = local_1109;
                                            local_1121 = _e3617;
                                            let _e3618 = local_1110;
                                            let _e3619 = local_1111;
                                            let _e3620 = local_1112;
                                            let _e3621 = local_1113;
                                            let _e3622 = local_1159;
                                            local_1122 = _e3622;
                                            local_1080 = ((_e3616 - (_e3618 * 2f)) + _e3620);
                                            let _e3628 = ((_e3617 - (_e3619 * 2f)) + _e3621);
                                            local_1081 = _e3628;
                                            local_1082 = (_e3616 - _e3618);
                                            local_1083 = (_e3617 - _e3619);
                                            if (abs(_e3628) < 0.000015258789f) {
                                                let _e3633 = local_1083;
                                                if (abs(_e3633) < 0.000015258789f) {
                                                    local_1084 = 0f;
                                                } else {
                                                    let _e3636 = local_1121;
                                                    let _e3638 = local_1083;
                                                    local_1084 = ((_e3636 * 0.5f) / _e3638);
                                                }
                                                let _e3640 = local_1084;
                                                local_1085 = _e3640;
                                            } else {
                                                let _e3641 = local_1081;
                                                let _e3642 = local_1121;
                                                let _e3643 = (_e3641 * _e3642);
                                                let _e3644 = local_1083;
                                                let _e3646 = ((_e3644 * _e3644) - _e3643);
                                                local_1087 = _e3646;
                                                if (_e3646 <= (max((_e3644 * _e3644), abs(_e3643)) * 0.000003f)) {
                                                    local_1079 = 0f;
                                                } else {
                                                    let _e3652 = local_1087;
                                                    local_1079 = sqrt(_e3652);
                                                }
                                                let _e3654 = local_1079;
                                                local_1086 = _e3654;
                                                let _e3655 = local_1083;
                                                if (_e3655 >= 0f) {
                                                    let _e3657 = local_1083;
                                                    let _e3658 = local_1086;
                                                    let _e3659 = (_e3657 + _e3658);
                                                    local_1088 = _e3659;
                                                    let _e3660 = local_1081;
                                                    local_1089 = (_e3659 / _e3660);
                                                    if (abs(_e3659) < 0.000015258789f) {
                                                        local_1084 = 0f;
                                                    } else {
                                                        let _e3664 = local_1121;
                                                        let _e3665 = local_1088;
                                                        local_1084 = (_e3664 / _e3665);
                                                    }
                                                    let _e3667 = local_1089;
                                                    local_1085 = _e3667;
                                                } else {
                                                    let _e3668 = local_1083;
                                                    let _e3669 = local_1086;
                                                    let _e3670 = (_e3668 - _e3669);
                                                    local_1090 = _e3670;
                                                    let _e3671 = local_1081;
                                                    local_1091 = (_e3670 / _e3671);
                                                    if (abs(_e3670) < 0.000015258789f) {
                                                        local_1084 = 0f;
                                                    } else {
                                                        let _e3675 = local_1121;
                                                        let _e3676 = local_1090;
                                                        local_1084 = (_e3675 / _e3676);
                                                    }
                                                    let _e3678 = local_1084;
                                                    let _e3679 = local_1091;
                                                    local_1084 = _e3679;
                                                    local_1085 = _e3678;
                                                }
                                            }
                                            let _e3680 = local_1082;
                                            let _e3681 = (_e3680 * 2f);
                                            let _e3682 = local_1080;
                                            let _e3683 = local_1084;
                                            let _e3687 = local_1120;
                                            let _e3689 = local_1122;
                                            let _e3691 = local_1085;
                                            local_1119 = vec2<f32>((((((_e3682 * _e3683) - _e3681) * _e3683) + _e3687) * _e3689), (((((_e3682 * _e3691) - _e3681) * _e3691) + _e3687) * _e3689));
                                        } else {
                                            let _e3698 = local_1108;
                                            local_1123 = _e3698;
                                            let _e3699 = local_1109;
                                            local_1124 = _e3699;
                                            let _e3700 = local_1110;
                                            let _e3701 = local_1111;
                                            let _e3702 = local_1112;
                                            let _e3703 = local_1113;
                                            let _e3704 = local_1159;
                                            local_1125 = _e3704;
                                            let _e3707 = ((_e3698 - (_e3700 * 2f)) + _e3702);
                                            local_1067 = _e3707;
                                            local_1068 = ((_e3699 - (_e3701 * 2f)) + _e3703);
                                            local_1069 = (_e3698 - _e3700);
                                            local_1070 = (_e3699 - _e3701);
                                            if (abs(_e3707) < 0.000015258789f) {
                                                let _e3715 = local_1069;
                                                if (abs(_e3715) < 0.000015258789f) {
                                                    local_1071 = 0f;
                                                } else {
                                                    let _e3718 = local_1123;
                                                    let _e3720 = local_1069;
                                                    local_1071 = ((_e3718 * 0.5f) / _e3720);
                                                }
                                                let _e3722 = local_1071;
                                                local_1072 = _e3722;
                                            } else {
                                                let _e3723 = local_1067;
                                                let _e3724 = local_1123;
                                                let _e3725 = (_e3723 * _e3724);
                                                let _e3726 = local_1069;
                                                let _e3728 = ((_e3726 * _e3726) - _e3725);
                                                local_1074 = _e3728;
                                                if (_e3728 <= (max((_e3726 * _e3726), abs(_e3725)) * 0.000003f)) {
                                                    local_1066 = 0f;
                                                } else {
                                                    let _e3734 = local_1074;
                                                    local_1066 = sqrt(_e3734);
                                                }
                                                let _e3736 = local_1066;
                                                local_1073 = _e3736;
                                                let _e3737 = local_1069;
                                                if (_e3737 >= 0f) {
                                                    let _e3739 = local_1069;
                                                    let _e3740 = local_1073;
                                                    let _e3741 = (_e3739 + _e3740);
                                                    local_1075 = _e3741;
                                                    let _e3742 = local_1067;
                                                    local_1076 = (_e3741 / _e3742);
                                                    if (abs(_e3741) < 0.000015258789f) {
                                                        local_1071 = 0f;
                                                    } else {
                                                        let _e3746 = local_1123;
                                                        let _e3747 = local_1075;
                                                        local_1071 = (_e3746 / _e3747);
                                                    }
                                                    let _e3749 = local_1076;
                                                    local_1072 = _e3749;
                                                } else {
                                                    let _e3750 = local_1069;
                                                    let _e3751 = local_1073;
                                                    let _e3752 = (_e3750 - _e3751);
                                                    local_1077 = _e3752;
                                                    let _e3753 = local_1067;
                                                    local_1078 = (_e3752 / _e3753);
                                                    if (abs(_e3752) < 0.000015258789f) {
                                                        local_1071 = 0f;
                                                    } else {
                                                        let _e3757 = local_1123;
                                                        let _e3758 = local_1077;
                                                        local_1071 = (_e3757 / _e3758);
                                                    }
                                                    let _e3760 = local_1071;
                                                    let _e3761 = local_1078;
                                                    local_1071 = _e3761;
                                                    local_1072 = _e3760;
                                                }
                                            }
                                            let _e3762 = local_1070;
                                            let _e3763 = (_e3762 * 2f);
                                            let _e3764 = local_1068;
                                            let _e3765 = local_1071;
                                            let _e3769 = local_1124;
                                            let _e3771 = local_1125;
                                            let _e3773 = local_1072;
                                            local_1119 = vec2<f32>((((((_e3764 * _e3765) - _e3763) * _e3765) + _e3769) * _e3771), (((((_e3764 * _e3773) - _e3763) * _e3773) + _e3769) * _e3771));
                                        }
                                        let _e3780 = local_1114;
                                        if ((_e3780 & 1u) != 0u) {
                                            let _e3783 = local_1119;
                                            local_1126 = _e3783.x;
                                            let _e3785 = local_1160;
                                            if _e3785 {
                                                local_1107 = 1f;
                                            } else {
                                                local_1107 = -1f;
                                            }
                                            let _e3786 = local_1156;
                                            let _e3787 = local_1157;
                                            let _e3788 = local_1126;
                                            let _e3789 = local_1107;
                                            local_1156 = (_e3786 + (_e3789 * clamp((_e3788 + 0.5f), 0f, 1f)));
                                            local_1157 = max(_e3787, clamp((1f - (abs(_e3788) * 2f)), 0f, 1f));
                                        }
                                        let _e3799 = local_1114;
                                        if (_e3799 > 1u) {
                                            let _e3801 = local_1119;
                                            local_1127 = _e3801.y;
                                            let _e3803 = local_1160;
                                            if _e3803 {
                                                local_1107 = -1f;
                                            } else {
                                                local_1107 = 1f;
                                            }
                                            let _e3804 = local_1156;
                                            let _e3805 = local_1157;
                                            let _e3806 = local_1127;
                                            let _e3807 = local_1107;
                                            local_1156 = (_e3804 + (_e3807 * clamp((_e3806 + 0.5f), 0f, 1f)));
                                            local_1157 = max(_e3805, clamp((1f - (abs(_e3806) * 2f)), 0f, 1f));
                                        }
                                        local_1106 = true;
                                        break;
                                    }
                                    let _e3817 = local_62;
                                    if (_e3817 == 3i) {
                                        let _e3819 = local_1158;
                                        let _e3822 = local_61;
                                        let _e3827 = local_59;
                                        let _e3832 = local_1156;
                                        local_1128 = _e3832;
                                        let _e3833 = local_1157;
                                        local_1129 = _e3833;
                                        local_1130 = (_e3822.x - _e3819.x);
                                        local_1131 = (_e3822.y - _e3819.y);
                                        local_1132 = (_e3827.x - _e3819.x);
                                        local_1133 = (_e3827.y - _e3819.y);
                                        let _e3834 = local_1159;
                                        local_1134 = _e3834;
                                        let _e3835 = local_1160;
                                        local_1135 = _e3835;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e3837 = local_1135;
                                                if _e3837 {
                                                    let _e3838 = local_1131;
                                                    local_1058 = _e3838;
                                                } else {
                                                    let _e3839 = local_1130;
                                                    local_1058 = _e3839;
                                                }
                                                let _e3840 = local_1135;
                                                if _e3840 {
                                                    let _e3841 = local_1133;
                                                    local_1059 = _e3841;
                                                } else {
                                                    let _e3842 = local_1132;
                                                    local_1059 = _e3842;
                                                }
                                                let _e3843 = local_1058;
                                                local_1060 = _e3843;
                                                if (abs(_e3843) <= 0.000015258789f) {
                                                    local_1057 = 0f;
                                                } else {
                                                    let _e3846 = local_1060;
                                                    local_1057 = _e3846;
                                                }
                                                let _e3847 = local_1057;
                                                let _e3849 = local_1059;
                                                local_1061 = _e3849;
                                                if (abs(_e3849) <= 0.000015258789f) {
                                                    local_1056 = 0f;
                                                } else {
                                                    let _e3852 = local_1061;
                                                    local_1056 = _e3852;
                                                }
                                                let _e3853 = local_1056;
                                                if ((_e3847 < 0f) == (_e3853 < 0f)) {
                                                    break;
                                                }
                                                let _e3856 = local_1059;
                                                let _e3857 = local_1058;
                                                let _e3858 = (_e3856 - _e3857);
                                                local_1062 = _e3858;
                                                if (abs(_e3858) < 0.0000000001f) {
                                                    break;
                                                }
                                                let _e3861 = local_1058;
                                                let _e3863 = local_1062;
                                                local_1063 = clamp((-(_e3861) / _e3863), 0f, 1f);
                                                let _e3866 = local_1135;
                                                if _e3866 {
                                                    let _e3867 = local_1133;
                                                    let _e3868 = local_1131;
                                                    local_1064 = (_e3867 - _e3868);
                                                } else {
                                                    let _e3870 = local_1130;
                                                    let _e3871 = local_1132;
                                                    local_1064 = (_e3870 - _e3871);
                                                }
                                                let _e3873 = local_1064;
                                                if (abs(_e3873) <= 0.00001f) {
                                                    break;
                                                }
                                                let _e3876 = local_1135;
                                                if _e3876 {
                                                    let _e3877 = local_1130;
                                                    let _e3878 = local_1132;
                                                    let _e3880 = local_1063;
                                                    local_1058 = (_e3877 + ((_e3878 - _e3877) * _e3880));
                                                } else {
                                                    let _e3883 = local_1131;
                                                    let _e3884 = local_1133;
                                                    let _e3886 = local_1063;
                                                    local_1058 = (_e3883 + ((_e3884 - _e3883) * _e3886));
                                                }
                                                let _e3889 = local_1058;
                                                let _e3890 = local_1134;
                                                local_1065 = (_e3889 * _e3890);
                                                let _e3892 = local_1064;
                                                if (_e3892 > 0f) {
                                                    local_1058 = 1f;
                                                } else {
                                                    local_1058 = -1f;
                                                }
                                                let _e3894 = local_1128;
                                                let _e3895 = local_1129;
                                                let _e3896 = local_1065;
                                                let _e3897 = local_1058;
                                                local_1128 = (_e3894 + (_e3897 * clamp((_e3896 + 0.5f), 0f, 1f)));
                                                local_1129 = max(_e3895, clamp((1f - (abs(_e3896) * 2f)), 0f, 1f));
                                                break;
                                            }
                                        }
                                        let _e3907 = local_1128;
                                        local_1156 = _e3907;
                                        let _e3908 = local_1129;
                                        local_1157 = _e3908;
                                        local_1106 = true;
                                        break;
                                    }
                                    let _e3909 = local_62;
                                    if (_e3909 == 1i) {
                                        let _e3911 = local_1156;
                                        local_1136 = _e3911;
                                        let _e3912 = local_1157;
                                        local_1137 = _e3912;
                                        let _e3913 = local_57;
                                        let _e3914 = local_58;
                                        let _e3915 = local_59;
                                        let _e3916 = local_60;
                                        let _e3917 = local_61;
                                        let _e3918 = local_62;
                                        local_79 = _e3918;
                                        local_78 = _e3917;
                                        local_77 = _e3916;
                                        local_76 = _e3915;
                                        local_75 = _e3914;
                                        local_74 = _e3913;
                                        let _e3919 = local_1158;
                                        local_1138 = _e3919;
                                        let _e3920 = local_1159;
                                        local_1139 = _e3920;
                                        let _e3921 = local_1160;
                                        local_1140 = _e3921;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e3923 = local_75;
                                                let _e3924 = local_76;
                                                let _e3925 = local_77;
                                                let _e3926 = local_78;
                                                let _e3927 = local_79;
                                                local_94 = _e3927;
                                                local_93 = _e3926;
                                                local_92 = _e3925;
                                                local_91 = _e3924;
                                                local_90 = _e3923;
                                                let _e3928 = local_1138;
                                                local_989 = _e3928;
                                                let _e3929 = local_1140;
                                                local_990 = _e3929;
                                                switch bitcast<i32>(0u) {
                                                    default: {
                                                        let _e3931 = local_990;
                                                        if _e3931 {
                                                            let _e3932 = local_989;
                                                            local_982 = _e3932.y;
                                                        } else {
                                                            let _e3934 = local_989;
                                                            local_982 = _e3934.x;
                                                        }
                                                        let _e3936 = local_94;
                                                        if (_e3936 == 2i) {
                                                            let _e3938 = local_990;
                                                            if _e3938 {
                                                                let _e3939 = local_93;
                                                                local_983 = _e3939.y;
                                                            } else {
                                                                let _e3941 = local_93;
                                                                local_983 = _e3941.x;
                                                            }
                                                            let _e3943 = local_990;
                                                            if _e3943 {
                                                                let _e3944 = local_92;
                                                                local_984 = _e3944.y;
                                                            } else {
                                                                let _e3946 = local_92;
                                                                local_984 = _e3946.x;
                                                            }
                                                            let _e3948 = local_990;
                                                            if _e3948 {
                                                                let _e3949 = local_91;
                                                                local_985 = _e3949.y;
                                                            } else {
                                                                let _e3951 = local_91;
                                                                local_985 = _e3951.x;
                                                            }
                                                            let _e3953 = local_990;
                                                            if _e3953 {
                                                                let _e3954 = local_90;
                                                                local_986 = _e3954.y;
                                                            } else {
                                                                let _e3956 = local_90;
                                                                local_986 = _e3956.x;
                                                            }
                                                            let _e3958 = local_983;
                                                            let _e3959 = local_984;
                                                            let _e3960 = local_985;
                                                            let _e3961 = local_986;
                                                            let _e3962 = local_982;
                                                            local_987 = _e3962;
                                                            local_979 = max(max(_e3958, _e3959), max(_e3960, _e3961));
                                                            if ((min(min(_e3958, _e3959), min(_e3960, _e3961)) - _e3962) <= 0.000015258789f) {
                                                                let _e3971 = local_979;
                                                                let _e3972 = local_987;
                                                                local_980 = ((_e3971 - _e3972) >= -0.000015258789f);
                                                            } else {
                                                                local_980 = false;
                                                            }
                                                            let _e3975 = local_980;
                                                            local_981 = _e3975;
                                                            break;
                                                        }
                                                        let _e3976 = local_990;
                                                        if _e3976 {
                                                            let _e3977 = local_93;
                                                            local_983 = _e3977.y;
                                                        } else {
                                                            let _e3979 = local_93;
                                                            local_983 = _e3979.x;
                                                        }
                                                        let _e3981 = local_990;
                                                        if _e3981 {
                                                            let _e3982 = local_92;
                                                            local_984 = _e3982.y;
                                                        } else {
                                                            let _e3984 = local_92;
                                                            local_984 = _e3984.x;
                                                        }
                                                        let _e3986 = local_990;
                                                        if _e3986 {
                                                            let _e3987 = local_91;
                                                            local_985 = _e3987.y;
                                                        } else {
                                                            let _e3989 = local_91;
                                                            local_985 = _e3989.x;
                                                        }
                                                        let _e3991 = local_983;
                                                        let _e3992 = local_984;
                                                        let _e3993 = local_985;
                                                        let _e3994 = local_982;
                                                        local_988 = _e3994;
                                                        local_977 = max(max(_e3991, _e3992), _e3993);
                                                        if ((min(min(_e3991, _e3992), _e3993) - _e3994) <= 0.000015258789f) {
                                                            let _e4001 = local_977;
                                                            let _e4002 = local_988;
                                                            local_978 = ((_e4001 - _e4002) >= -0.000015258789f);
                                                        } else {
                                                            local_978 = false;
                                                        }
                                                        let _e4005 = local_978;
                                                        local_981 = _e4005;
                                                        break;
                                                    }
                                                }
                                                let _e4006 = local_981;
                                                if !(_e4006) {
                                                    break;
                                                }
                                                let _e4008 = local_1140;
                                                if _e4008 {
                                                    let _e4009 = local_1138;
                                                    local_991 = _e4009.y;
                                                } else {
                                                    let _e4011 = local_1138;
                                                    local_991 = _e4011.x;
                                                }
                                                let _e4013 = local_1140;
                                                if _e4013 {
                                                    let _e4014 = local_1138;
                                                    local_992 = _e4014.x;
                                                } else {
                                                    let _e4016 = local_1138;
                                                    local_992 = _e4016.y;
                                                }
                                                let _e4018 = local_1140;
                                                if _e4018 {
                                                    let _e4019 = local_78;
                                                    local_993 = _e4019.y;
                                                } else {
                                                    let _e4021 = local_78;
                                                    local_993 = _e4021.x;
                                                }
                                                let _e4023 = local_1140;
                                                if _e4023 {
                                                    let _e4024 = local_77;
                                                    local_994 = _e4024.y;
                                                } else {
                                                    let _e4026 = local_77;
                                                    local_994 = _e4026.x;
                                                }
                                                let _e4028 = local_1140;
                                                if _e4028 {
                                                    let _e4029 = local_76;
                                                    local_995 = _e4029.y;
                                                } else {
                                                    let _e4031 = local_76;
                                                    local_995 = _e4031.x;
                                                }
                                                let _e4033 = local_1140;
                                                if _e4033 {
                                                    let _e4034 = local_78;
                                                    local_996 = _e4034.x;
                                                } else {
                                                    let _e4036 = local_78;
                                                    local_996 = _e4036.y;
                                                }
                                                let _e4038 = local_1140;
                                                if _e4038 {
                                                    let _e4039 = local_77;
                                                    local_997 = _e4039.x;
                                                } else {
                                                    let _e4041 = local_77;
                                                    local_997 = _e4041.y;
                                                }
                                                let _e4043 = local_1140;
                                                if _e4043 {
                                                    let _e4044 = local_76;
                                                    local_998 = _e4044.x;
                                                } else {
                                                    let _e4046 = local_76;
                                                    local_998 = _e4046.y;
                                                }
                                                let _e4048 = local_74;
                                                local_999 = _e4048.x;
                                                let _e4050 = local_993;
                                                let _e4051 = local_991;
                                                let _e4053 = (_e4048.x * (_e4050 - _e4051));
                                                local_1000 = _e4053;
                                                local_1001 = _e4048.y;
                                                let _e4055 = local_994;
                                                let _e4057 = (_e4048.y * (_e4055 - _e4051));
                                                local_1002 = _e4057;
                                                local_1003 = _e4048.z;
                                                let _e4059 = local_995;
                                                let _e4061 = (_e4048.z * (_e4059 - _e4051));
                                                local_1004 = _e4061;
                                                local_1006 = _e4053;
                                                local_1007 = _e4057;
                                                local_974 = _e4061;
                                                if (abs(_e4061) <= 0.000015258789f) {
                                                    local_973 = 0f;
                                                } else {
                                                    let _e4064 = local_974;
                                                    local_973 = _e4064;
                                                }
                                                let _e4065 = local_973;
                                                let _e4070 = local_1007;
                                                local_975 = _e4070;
                                                if (abs(_e4070) <= 0.000015258789f) {
                                                    local_972 = 0f;
                                                } else {
                                                    let _e4073 = local_975;
                                                    local_972 = _e4073;
                                                }
                                                let _e4074 = local_972;
                                                let _e4079 = local_1006;
                                                local_976 = _e4079;
                                                if (abs(_e4079) <= 0.000015258789f) {
                                                    local_971 = 0f;
                                                } else {
                                                    let _e4082 = local_976;
                                                    local_971 = _e4082;
                                                }
                                                let _e4083 = local_971;
                                                let _e4093 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e4065) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e4074) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e4083) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                                local_1005 = _e4093;
                                                if (_e4093 == 0u) {
                                                    break;
                                                }
                                                let _e4095 = local_1005;
                                                if (_e4095 == 257u) {
                                                    local_1008 = 2i;
                                                } else {
                                                    local_1008 = 1i;
                                                }
                                                let _e4097 = local_1000;
                                                let _e4098 = local_1002;
                                                let _e4101 = local_1004;
                                                let _e4102 = ((_e4097 - (2f * _e4098)) + _e4101);
                                                local_1009 = _e4102;
                                                local_1010 = (2f * (_e4098 - _e4097));
                                                if (abs(_e4102) < 0.000015258789f) {
                                                    let _e4107 = local_1010;
                                                    if (abs(_e4107) >= 0.000015258789f) {
                                                        let _e4110 = local_1000;
                                                        let _e4112 = local_1010;
                                                        local_1011 = 1i;
                                                        local_1012 = (-(_e4110) / _e4112);
                                                    } else {
                                                        local_1011 = 0i;
                                                        local_1012 = 0f;
                                                    }
                                                    let _e4114 = local_1012;
                                                    local_1012 = 0f;
                                                    local_1013 = _e4114;
                                                } else {
                                                    let _e4115 = local_1010;
                                                    let _e4117 = local_1009;
                                                    let _e4119 = local_1000;
                                                    let _e4123 = sqrt(max(((_e4115 * _e4115) - ((4f * _e4117) * _e4119)), 0f));
                                                    let _e4124 = (0.5f / _e4117);
                                                    let _e4125 = -(_e4115);
                                                    local_1011 = 2i;
                                                    local_1012 = ((_e4125 + _e4123) * _e4124);
                                                    local_1013 = ((_e4125 - _e4123) * _e4124);
                                                }
                                                let _e4130 = local_1011;
                                                if (_e4130 == 0i) {
                                                    break;
                                                }
                                                let _e4132 = local_1008;
                                                if (_e4132 == 1i) {
                                                    let _e4134 = local_1011;
                                                    if (_e4134 == 2i) {
                                                        let _e4136 = local_1012;
                                                        let _e4141 = local_1013;
                                                        local_1014 = (max(max(0f, -(_e4136)), (_e4136 - 1f)) < max(max(0f, -(_e4141)), (_e4141 - 1f)));
                                                    } else {
                                                        local_1014 = false;
                                                    }
                                                    let _e4147 = local_1014;
                                                    if _e4147 {
                                                        let _e4148 = local_1012;
                                                        local_1015 = _e4148;
                                                    } else {
                                                        let _e4149 = local_1013;
                                                        local_1015 = _e4149;
                                                    }
                                                    let _e4150 = local_1015;
                                                    local_1015 = clamp(_e4150, 0f, 1f);
                                                    local_1016 = 1i;
                                                    local_1017 = 0f;
                                                } else {
                                                    let _e4152 = local_1012;
                                                    let _e4154 = local_1013;
                                                    local_1015 = clamp(_e4154, 0f, 1f);
                                                    local_1016 = 2i;
                                                    local_1017 = clamp(_e4152, 0f, 1f);
                                                }
                                                let _e4156 = local_993;
                                                let _e4157 = local_999;
                                                let _e4158 = (_e4156 * _e4157);
                                                local_1018 = _e4158;
                                                let _e4159 = local_994;
                                                let _e4161 = local_1001;
                                                let _e4164 = local_995;
                                                let _e4165 = local_1003;
                                                local_1019 = ((_e4158 - ((2f * _e4159) * _e4161)) + (_e4164 * _e4165));
                                                local_1020 = (2f * ((_e4159 * _e4161) - _e4158));
                                                let _e4171 = local_996;
                                                let _e4172 = (_e4171 * _e4157);
                                                local_1021 = _e4172;
                                                let _e4173 = local_997;
                                                let _e4177 = local_998;
                                                local_1022 = ((_e4172 - ((2f * _e4173) * _e4161)) + (_e4177 * _e4165));
                                                local_1023 = (2f * ((_e4173 * _e4161) - _e4172));
                                                local_1024 = ((_e4157 - (2f * _e4161)) + _e4165);
                                                local_1025 = (2f * (_e4161 - _e4157));
                                                let _e4188 = local_1136;
                                                local_1026 = _e4188;
                                                let _e4189 = local_1137;
                                                local_1027 = _e4189;
                                                let _e4190 = local_1015;
                                                local_1028 = _e4190;
                                                let _e4191 = local_992;
                                                local_1029 = _e4191;
                                                let _e4192 = local_1139;
                                                local_1030 = _e4192;
                                                let _e4193 = local_1140;
                                                local_1031 = _e4193;
                                                let _e4194 = local_1019;
                                                local_1032 = _e4194;
                                                let _e4195 = local_1020;
                                                local_1033 = _e4195;
                                                let _e4196 = local_1018;
                                                local_1034 = _e4196;
                                                let _e4197 = local_1022;
                                                local_1035 = _e4197;
                                                let _e4198 = local_1023;
                                                local_1036 = _e4198;
                                                let _e4199 = local_1021;
                                                local_1037 = _e4199;
                                                let _e4200 = local_1024;
                                                local_1038 = _e4200;
                                                let _e4201 = local_1025;
                                                local_1039 = _e4201;
                                                let _e4202 = local_999;
                                                local_1040 = _e4202;
                                                switch bitcast<i32>(0u) {
                                                    default: {
                                                        let _e4204 = local_1038;
                                                        let _e4205 = local_1028;
                                                        let _e4207 = local_1039;
                                                        let _e4210 = local_1040;
                                                        let _e4212 = max(((((_e4204 * _e4205) + _e4207) * _e4205) + _e4210), 0.000015258789f);
                                                        let _e4213 = local_1035;
                                                        let _e4215 = local_1036;
                                                        let _e4218 = local_1037;
                                                        local_967 = (((((_e4213 * _e4205) + _e4215) * _e4205) + _e4218) / _e4212);
                                                        let _e4221 = local_1032;
                                                        let _e4224 = local_1033;
                                                        let _e4230 = local_1034;
                                                        local_968 = ((((((2f * _e4221) * _e4205) + _e4224) * _e4212) - (((((_e4221 * _e4205) + _e4224) * _e4205) + _e4230) * (((2f * _e4204) * _e4205) + _e4207))) / (_e4212 * _e4212));
                                                        let _e4239 = local_1031;
                                                        if !(_e4239) {
                                                            let _e4241 = local_968;
                                                            local_969 = -(_e4241);
                                                        } else {
                                                            let _e4243 = local_968;
                                                            local_969 = _e4243;
                                                        }
                                                        let _e4244 = local_969;
                                                        if (abs(_e4244) <= 0.00001f) {
                                                            break;
                                                        }
                                                        let _e4247 = local_967;
                                                        let _e4248 = local_1029;
                                                        let _e4250 = local_1030;
                                                        local_970 = ((_e4247 - _e4248) * _e4250);
                                                        let _e4252 = local_969;
                                                        if (_e4252 > 0f) {
                                                            local_969 = 1f;
                                                        } else {
                                                            local_969 = -1f;
                                                        }
                                                        let _e4254 = local_1026;
                                                        let _e4255 = local_1027;
                                                        let _e4256 = local_970;
                                                        let _e4257 = local_969;
                                                        local_1026 = (_e4254 + (_e4257 * clamp((_e4256 + 0.5f), 0f, 1f)));
                                                        local_1027 = max(_e4255, clamp((1f - (abs(_e4256) * 2f)), 0f, 1f));
                                                        break;
                                                    }
                                                }
                                                let _e4267 = local_1026;
                                                local_1136 = _e4267;
                                                let _e4268 = local_1027;
                                                local_1137 = _e4268;
                                                let _e4269 = local_1016;
                                                if (_e4269 == 2i) {
                                                    let _e4271 = local_1136;
                                                    local_1041 = _e4271;
                                                    let _e4272 = local_1137;
                                                    local_1042 = _e4272;
                                                    let _e4273 = local_1017;
                                                    local_1043 = _e4273;
                                                    let _e4274 = local_992;
                                                    local_1044 = _e4274;
                                                    let _e4275 = local_1139;
                                                    local_1045 = _e4275;
                                                    let _e4276 = local_1140;
                                                    local_1046 = _e4276;
                                                    let _e4277 = local_1019;
                                                    local_1047 = _e4277;
                                                    let _e4278 = local_1020;
                                                    local_1048 = _e4278;
                                                    let _e4279 = local_1018;
                                                    local_1049 = _e4279;
                                                    let _e4280 = local_1022;
                                                    local_1050 = _e4280;
                                                    let _e4281 = local_1023;
                                                    local_1051 = _e4281;
                                                    let _e4282 = local_1021;
                                                    local_1052 = _e4282;
                                                    let _e4283 = local_1024;
                                                    local_1053 = _e4283;
                                                    let _e4284 = local_1025;
                                                    local_1054 = _e4284;
                                                    let _e4285 = local_999;
                                                    local_1055 = _e4285;
                                                    switch bitcast<i32>(0u) {
                                                        default: {
                                                            let _e4287 = local_1053;
                                                            let _e4288 = local_1043;
                                                            let _e4290 = local_1054;
                                                            let _e4293 = local_1055;
                                                            let _e4295 = max(((((_e4287 * _e4288) + _e4290) * _e4288) + _e4293), 0.000015258789f);
                                                            let _e4296 = local_1050;
                                                            let _e4298 = local_1051;
                                                            let _e4301 = local_1052;
                                                            local_963 = (((((_e4296 * _e4288) + _e4298) * _e4288) + _e4301) / _e4295);
                                                            let _e4304 = local_1047;
                                                            let _e4307 = local_1048;
                                                            let _e4313 = local_1049;
                                                            local_964 = ((((((2f * _e4304) * _e4288) + _e4307) * _e4295) - (((((_e4304 * _e4288) + _e4307) * _e4288) + _e4313) * (((2f * _e4287) * _e4288) + _e4290))) / (_e4295 * _e4295));
                                                            let _e4322 = local_1046;
                                                            if !(_e4322) {
                                                                let _e4324 = local_964;
                                                                local_965 = -(_e4324);
                                                            } else {
                                                                let _e4326 = local_964;
                                                                local_965 = _e4326;
                                                            }
                                                            let _e4327 = local_965;
                                                            if (abs(_e4327) <= 0.00001f) {
                                                                break;
                                                            }
                                                            let _e4330 = local_963;
                                                            let _e4331 = local_1044;
                                                            let _e4333 = local_1045;
                                                            local_966 = ((_e4330 - _e4331) * _e4333);
                                                            let _e4335 = local_965;
                                                            if (_e4335 > 0f) {
                                                                local_965 = 1f;
                                                            } else {
                                                                local_965 = -1f;
                                                            }
                                                            let _e4337 = local_1041;
                                                            let _e4338 = local_1042;
                                                            let _e4339 = local_966;
                                                            let _e4340 = local_965;
                                                            local_1041 = (_e4337 + (_e4340 * clamp((_e4339 + 0.5f), 0f, 1f)));
                                                            local_1042 = max(_e4338, clamp((1f - (abs(_e4339) * 2f)), 0f, 1f));
                                                            break;
                                                        }
                                                    }
                                                    let _e4350 = local_1041;
                                                    local_1136 = _e4350;
                                                    let _e4351 = local_1042;
                                                    local_1137 = _e4351;
                                                }
                                                break;
                                            }
                                        }
                                        let _e4352 = local_1136;
                                        local_1156 = _e4352;
                                        let _e4353 = local_1137;
                                        local_1157 = _e4353;
                                        local_1106 = true;
                                        break;
                                    }
                                    let _e4354 = local_1156;
                                    local_1141 = _e4354;
                                    let _e4355 = local_1157;
                                    local_1142 = _e4355;
                                    let _e4356 = local_58;
                                    let _e4357 = local_59;
                                    let _e4358 = local_60;
                                    let _e4359 = local_61;
                                    let _e4360 = local_62;
                                    local_73 = _e4360;
                                    local_72 = _e4359;
                                    local_71 = _e4358;
                                    local_70 = _e4357;
                                    local_69 = _e4356;
                                    let _e4361 = local_1158;
                                    local_1143 = _e4361;
                                    let _e4362 = local_1159;
                                    local_1144 = _e4362;
                                    let _e4363 = local_1160;
                                    local_1145 = _e4363;
                                    switch bitcast<i32>(0u) {
                                        default: {
                                            let _e4365 = local_69;
                                            let _e4366 = local_70;
                                            let _e4367 = local_71;
                                            let _e4368 = local_72;
                                            let _e4369 = local_73;
                                            local_99 = _e4369;
                                            local_98 = _e4368;
                                            local_97 = _e4367;
                                            local_96 = _e4366;
                                            local_95 = _e4365;
                                            let _e4370 = local_1143;
                                            local_931 = _e4370;
                                            let _e4371 = local_1145;
                                            local_932 = _e4371;
                                            switch bitcast<i32>(0u) {
                                                default: {
                                                    let _e4373 = local_932;
                                                    if _e4373 {
                                                        let _e4374 = local_931;
                                                        local_924 = _e4374.y;
                                                    } else {
                                                        let _e4376 = local_931;
                                                        local_924 = _e4376.x;
                                                    }
                                                    let _e4378 = local_99;
                                                    if (_e4378 == 2i) {
                                                        let _e4380 = local_932;
                                                        if _e4380 {
                                                            let _e4381 = local_98;
                                                            local_925 = _e4381.y;
                                                        } else {
                                                            let _e4383 = local_98;
                                                            local_925 = _e4383.x;
                                                        }
                                                        let _e4385 = local_932;
                                                        if _e4385 {
                                                            let _e4386 = local_97;
                                                            local_926 = _e4386.y;
                                                        } else {
                                                            let _e4388 = local_97;
                                                            local_926 = _e4388.x;
                                                        }
                                                        let _e4390 = local_932;
                                                        if _e4390 {
                                                            let _e4391 = local_96;
                                                            local_927 = _e4391.y;
                                                        } else {
                                                            let _e4393 = local_96;
                                                            local_927 = _e4393.x;
                                                        }
                                                        let _e4395 = local_932;
                                                        if _e4395 {
                                                            let _e4396 = local_95;
                                                            local_928 = _e4396.y;
                                                        } else {
                                                            let _e4398 = local_95;
                                                            local_928 = _e4398.x;
                                                        }
                                                        let _e4400 = local_925;
                                                        let _e4401 = local_926;
                                                        let _e4402 = local_927;
                                                        let _e4403 = local_928;
                                                        let _e4404 = local_924;
                                                        local_929 = _e4404;
                                                        local_921 = max(max(_e4400, _e4401), max(_e4402, _e4403));
                                                        if ((min(min(_e4400, _e4401), min(_e4402, _e4403)) - _e4404) <= 0.000015258789f) {
                                                            let _e4413 = local_921;
                                                            let _e4414 = local_929;
                                                            local_922 = ((_e4413 - _e4414) >= -0.000015258789f);
                                                        } else {
                                                            local_922 = false;
                                                        }
                                                        let _e4417 = local_922;
                                                        local_923 = _e4417;
                                                        break;
                                                    }
                                                    let _e4418 = local_932;
                                                    if _e4418 {
                                                        let _e4419 = local_98;
                                                        local_925 = _e4419.y;
                                                    } else {
                                                        let _e4421 = local_98;
                                                        local_925 = _e4421.x;
                                                    }
                                                    let _e4423 = local_932;
                                                    if _e4423 {
                                                        let _e4424 = local_97;
                                                        local_926 = _e4424.y;
                                                    } else {
                                                        let _e4426 = local_97;
                                                        local_926 = _e4426.x;
                                                    }
                                                    let _e4428 = local_932;
                                                    if _e4428 {
                                                        let _e4429 = local_96;
                                                        local_927 = _e4429.y;
                                                    } else {
                                                        let _e4431 = local_96;
                                                        local_927 = _e4431.x;
                                                    }
                                                    let _e4433 = local_925;
                                                    let _e4434 = local_926;
                                                    let _e4435 = local_927;
                                                    let _e4436 = local_924;
                                                    local_930 = _e4436;
                                                    local_919 = max(max(_e4433, _e4434), _e4435);
                                                    if ((min(min(_e4433, _e4434), _e4435) - _e4436) <= 0.000015258789f) {
                                                        let _e4443 = local_919;
                                                        let _e4444 = local_930;
                                                        local_920 = ((_e4443 - _e4444) >= -0.000015258789f);
                                                    } else {
                                                        local_920 = false;
                                                    }
                                                    let _e4447 = local_920;
                                                    local_923 = _e4447;
                                                    break;
                                                }
                                            }
                                            let _e4448 = local_923;
                                            if !(_e4448) {
                                                break;
                                            }
                                            let _e4450 = local_1145;
                                            if _e4450 {
                                                let _e4451 = local_1143;
                                                local_933 = _e4451.y;
                                            } else {
                                                let _e4453 = local_1143;
                                                local_933 = _e4453.x;
                                            }
                                            let _e4455 = local_1145;
                                            if _e4455 {
                                                let _e4456 = local_1143;
                                                local_934 = _e4456.x;
                                            } else {
                                                let _e4458 = local_1143;
                                                local_934 = _e4458.y;
                                            }
                                            let _e4460 = local_1145;
                                            if _e4460 {
                                                let _e4461 = local_72;
                                                local_935 = _e4461.y;
                                            } else {
                                                let _e4463 = local_72;
                                                local_935 = _e4463.x;
                                            }
                                            let _e4465 = local_1145;
                                            if _e4465 {
                                                let _e4466 = local_71;
                                                local_936 = _e4466.y;
                                            } else {
                                                let _e4468 = local_71;
                                                local_936 = _e4468.x;
                                            }
                                            let _e4470 = local_1145;
                                            if _e4470 {
                                                let _e4471 = local_70;
                                                local_937 = _e4471.y;
                                            } else {
                                                let _e4473 = local_70;
                                                local_937 = _e4473.x;
                                            }
                                            let _e4475 = local_1145;
                                            if _e4475 {
                                                let _e4476 = local_69;
                                                local_938 = _e4476.y;
                                            } else {
                                                let _e4478 = local_69;
                                                local_938 = _e4478.x;
                                            }
                                            let _e4480 = local_1145;
                                            if _e4480 {
                                                let _e4481 = local_72;
                                                local_939 = _e4481.x;
                                            } else {
                                                let _e4483 = local_72;
                                                local_939 = _e4483.y;
                                            }
                                            let _e4485 = local_1145;
                                            if _e4485 {
                                                let _e4486 = local_71;
                                                local_940 = _e4486.x;
                                            } else {
                                                let _e4488 = local_71;
                                                local_940 = _e4488.y;
                                            }
                                            let _e4490 = local_1145;
                                            if _e4490 {
                                                let _e4491 = local_70;
                                                local_941 = _e4491.x;
                                            } else {
                                                let _e4493 = local_70;
                                                local_941 = _e4493.y;
                                            }
                                            let _e4495 = local_1145;
                                            if _e4495 {
                                                let _e4496 = local_69;
                                                local_942 = _e4496.x;
                                            } else {
                                                let _e4498 = local_69;
                                                local_942 = _e4498.y;
                                            }
                                            let _e4500 = local_936;
                                            let _e4501 = (3f * _e4500);
                                            let _e4502 = local_937;
                                            let _e4503 = (3f * _e4502);
                                            let _e4504 = local_935;
                                            let _e4507 = local_938;
                                            local_943 = (((_e4501 - _e4504) - _e4503) + _e4507);
                                            local_944 = (((3f * _e4504) - (6f * _e4500)) + _e4503);
                                            local_945 = ((-3f * _e4504) + _e4501);
                                            let _e4515 = local_933;
                                            let _e4516 = (_e4504 - _e4515);
                                            local_946 = _e4516;
                                            local_947 = (_e4507 - _e4515);
                                            local_948 = _e4516;
                                            if (abs(_e4516) <= 0.000015258789f) {
                                                local_918 = 0f;
                                            } else {
                                                let _e4520 = local_948;
                                                local_918 = _e4520;
                                            }
                                            let _e4521 = local_918;
                                            let _e4523 = local_947;
                                            local_949 = _e4523;
                                            if (abs(_e4523) <= 0.000015258789f) {
                                                local_917 = 0f;
                                            } else {
                                                let _e4526 = local_949;
                                                local_917 = _e4526;
                                            }
                                            let _e4527 = local_917;
                                            if ((_e4521 < 0f) == (_e4527 < 0f)) {
                                                break;
                                            }
                                            local_950 = 0f;
                                            let _e4530 = local_946;
                                            if (abs(_e4530) <= 0.000015258789f) {
                                                local_950 = 0f;
                                            } else {
                                                let _e4533 = local_947;
                                                if (abs(_e4533) <= 0.000015258789f) {
                                                    local_950 = 1f;
                                                } else {
                                                    let _e4536 = local_943;
                                                    local_951 = _e4536;
                                                    let _e4537 = local_944;
                                                    local_952 = _e4537;
                                                    let _e4538 = local_945;
                                                    local_953 = _e4538;
                                                    let _e4539 = local_946;
                                                    local_954 = _e4539;
                                                    let _e4540 = local_947;
                                                    local_955 = _e4540;
                                                    switch bitcast<i32>(0u) {
                                                        default: {
                                                            let _e4542 = local_954;
                                                            if (_e4542 < -0.000015258789f) {
                                                                let _e4544 = local_955;
                                                                local_904 = (_e4544 < -0.000015258789f);
                                                            } else {
                                                                local_904 = false;
                                                            }
                                                            let _e4546 = local_904;
                                                            if _e4546 {
                                                                local_904 = true;
                                                            } else {
                                                                let _e4547 = local_954;
                                                                if (_e4547 > 0.000015258789f) {
                                                                    let _e4549 = local_955;
                                                                    local_904 = (_e4549 > 0.000015258789f);
                                                                } else {
                                                                    local_904 = false;
                                                                }
                                                            }
                                                            let _e4551 = local_904;
                                                            if _e4551 {
                                                                local_903 = false;
                                                                break;
                                                            }
                                                            let _e4552 = local_955;
                                                            let _e4553 = local_954;
                                                            local_905 = (_e4552 >= _e4553);
                                                            local_906 = 0.5f;
                                                            local_907 = 0f;
                                                            local_908 = 1f;
                                                            local_909 = 0i;
                                                            loop {
                                                                let _e4555 = local_909;
                                                                if (_e4555 < 16i) {
                                                                } else {
                                                                    break;
                                                                }
                                                                let _e4557 = local_951;
                                                                let _e4558 = local_906;
                                                                let _e4560 = local_952;
                                                                let _e4563 = local_953;
                                                                let _e4566 = local_954;
                                                                local_910 = ((((((_e4557 * _e4558) + _e4560) * _e4558) + _e4563) * _e4558) + _e4566);
                                                                let _e4568 = local_905;
                                                                if _e4568 {
                                                                    let _e4569 = local_910;
                                                                    local_904 = (_e4569 < 0f);
                                                                } else {
                                                                    local_904 = false;
                                                                }
                                                                let _e4571 = local_904;
                                                                if _e4571 {
                                                                    local_911 = true;
                                                                } else {
                                                                    let _e4572 = local_905;
                                                                    if !(_e4572) {
                                                                        let _e4574 = local_910;
                                                                        local_911 = (_e4574 > 0f);
                                                                    } else {
                                                                        local_911 = false;
                                                                    }
                                                                }
                                                                let _e4576 = local_911;
                                                                if _e4576 {
                                                                    let _e4577 = local_906;
                                                                    local_907 = _e4577;
                                                                } else {
                                                                    let _e4578 = local_906;
                                                                    local_908 = _e4578;
                                                                }
                                                                let _e4579 = local_951;
                                                                let _e4581 = local_906;
                                                                let _e4583 = local_952;
                                                                let _e4587 = local_953;
                                                                let _e4588 = (((((3f * _e4579) * _e4581) + (2f * _e4583)) * _e4581) + _e4587);
                                                                local_912 = _e4588;
                                                                let _e4589 = local_907;
                                                                let _e4590 = local_908;
                                                                local_913 = ((_e4589 + _e4590) * 0.5f);
                                                                if (abs(_e4588) >= 0.000001f) {
                                                                    let _e4595 = local_906;
                                                                    let _e4596 = local_910;
                                                                    let _e4597 = local_912;
                                                                    let _e4599 = (_e4595 - (_e4596 / _e4597));
                                                                    local_914 = _e4599;
                                                                    let _e4600 = local_907;
                                                                    if (_e4599 > _e4600) {
                                                                        let _e4602 = local_914;
                                                                        let _e4603 = local_908;
                                                                        local_915 = (_e4602 < _e4603);
                                                                    } else {
                                                                        local_915 = false;
                                                                    }
                                                                    let _e4605 = local_915;
                                                                    if _e4605 {
                                                                        let _e4606 = local_914;
                                                                        local_916 = _e4606;
                                                                    } else {
                                                                        let _e4607 = local_913;
                                                                        local_916 = _e4607;
                                                                    }
                                                                } else {
                                                                    let _e4608 = local_913;
                                                                    local_916 = _e4608;
                                                                }
                                                                let _e4609 = local_909;
                                                                let _e4611 = local_916;
                                                                local_906 = _e4611;
                                                                local_909 = (_e4609 + 1i);
                                                                continue;
                                                            }
                                                            let _e4612 = local_906;
                                                            local_956 = _e4612;
                                                            local_903 = true;
                                                            break;
                                                        }
                                                    }
                                                    let _e4613 = local_903;
                                                    let _e4614 = local_956;
                                                    local_950 = _e4614;
                                                    if !(_e4613) {
                                                        break;
                                                    }
                                                }
                                            }
                                            let _e4616 = local_940;
                                            let _e4617 = (3f * _e4616);
                                            let _e4618 = local_941;
                                            let _e4619 = (3f * _e4618);
                                            let _e4620 = local_939;
                                            let _e4623 = local_942;
                                            local_957 = (((_e4617 - _e4620) - _e4619) + _e4623);
                                            local_958 = (((3f * _e4620) - (6f * _e4616)) + _e4619);
                                            local_959 = ((-3f * _e4620) + _e4617);
                                            let _e4631 = local_950;
                                            if (_e4631 == 1f) {
                                                let _e4633 = local_942;
                                                local_960 = _e4633;
                                            } else {
                                                let _e4634 = local_957;
                                                let _e4635 = local_950;
                                                let _e4637 = local_958;
                                                let _e4640 = local_959;
                                                let _e4643 = local_939;
                                                local_960 = ((((((_e4634 * _e4635) + _e4637) * _e4635) + _e4640) * _e4635) + _e4643);
                                            }
                                            let _e4645 = local_1145;
                                            if _e4645 {
                                                let _e4646 = local_938;
                                                let _e4647 = local_935;
                                                local_961 = (_e4646 - _e4647);
                                            } else {
                                                let _e4649 = local_935;
                                                let _e4650 = local_938;
                                                local_961 = (_e4649 - _e4650);
                                            }
                                            let _e4652 = local_960;
                                            let _e4653 = local_934;
                                            let _e4655 = local_1144;
                                            local_962 = ((_e4652 - _e4653) * _e4655);
                                            let _e4657 = local_961;
                                            if (_e4657 > 0f) {
                                                local_933 = 1f;
                                            } else {
                                                local_933 = -1f;
                                            }
                                            let _e4659 = local_1141;
                                            let _e4660 = local_1142;
                                            let _e4661 = local_962;
                                            let _e4662 = local_933;
                                            local_1141 = (_e4659 + (_e4662 * clamp((_e4661 + 0.5f), 0f, 1f)));
                                            local_1142 = max(_e4660, clamp((1f - (abs(_e4661) * 2f)), 0f, 1f));
                                            break;
                                        }
                                    }
                                    let _e4672 = local_1141;
                                    local_1156 = _e4672;
                                    let _e4673 = local_1142;
                                    local_1157 = _e4673;
                                    local_1106 = true;
                                    break;
                                }
                            }
                            let _e4674 = local_1106;
                            let _e4675 = local_1156;
                            local_1146 = _e4675;
                            let _e4676 = local_1157;
                            local_1147 = _e4676;
                            if !(_e4674) {
                                break;
                            }
                            let _e4678 = local_1152;
                            local_1152 = (_e4678 + 1i);
                            continue;
                        }
                        let _e4680 = local_1149;
                        local_1149 = (_e4680 + 1i);
                        continue;
                    }
                    let _e4682 = local_1146;
                    let _e4683 = local_1147;
                    let _e4684 = vec2<f32>(_e4682, _e4683);
                    let _e4685 = local_1420;
                    local_1437 = _e4685.x;
                    local_1438 = _e4684.x;
                    local_1439 = (((_e4685.x * _e4685.y) + (_e4684.x * _e4684.y)) / max((_e4685.y + _e4684.y), 0.000015258789f));
                    let _e4696 = local_1461;
                    local_1440 = _e4696;
                    switch bitcast<i32>(0u) {
                        default: {
                            let _e4698 = local_1440;
                            if (_e4698 == 1i) {
                                let _e4700 = local_1439;
                                local_902 = (1f - abs(((fract((_e4700 * 0.5f)) * 2f) - 1f)));
                                break;
                            }
                            let _e4707 = local_1439;
                            local_902 = abs(_e4707);
                            break;
                        }
                    }
                    let _e4709 = local_902;
                    let _e4710 = local_1437;
                    local_1441 = _e4710;
                    let _e4711 = local_1461;
                    local_1442 = _e4711;
                    switch bitcast<i32>(0u) {
                        default: {
                            let _e4713 = local_1442;
                            if (_e4713 == 1i) {
                                let _e4715 = local_1441;
                                local_901 = (1f - abs(((fract((_e4715 * 0.5f)) * 2f) - 1f)));
                                break;
                            }
                            let _e4722 = local_1441;
                            local_901 = abs(_e4722);
                            break;
                        }
                    }
                    let _e4724 = local_901;
                    let _e4725 = local_1438;
                    local_1443 = _e4725;
                    let _e4726 = local_1461;
                    local_1444 = _e4726;
                    switch bitcast<i32>(0u) {
                        default: {
                            let _e4728 = local_1444;
                            if (_e4728 == 1i) {
                                let _e4730 = local_1443;
                                local_900 = (1f - abs(((fract((_e4730 * 0.5f)) * 2f) - 1f)));
                                break;
                            }
                            let _e4737 = local_1443;
                            local_900 = abs(_e4737);
                            break;
                        }
                    }
                    let _e4739 = local_900;
                    local_897 = clamp(max(_e4709, min(_e4724, _e4739)), 0f, 1f);
                    let _e4744 = PushConstants_0_.coverage_exponent_0_;
                    let _e4745 = max(_e4744, 0.000015258789f);
                    local_898 = _e4745;
                    if (abs((_e4745 - 1f)) <= 0.000001f) {
                        let _e4749 = local_897;
                        local_899 = _e4749;
                    } else {
                        let _e4750 = local_897;
                        let _e4751 = local_898;
                        local_899 = pow(_e4750, _e4751);
                    }
                    let _e4753 = local_899;
                    local_1456 = _e4753;
                    let _e4754 = local_1479;
                    local_1462 = _e4754;
                    let _e4755 = local_1454;
                    local_1463 = _e4755;
                    let _e4756 = local_1455;
                    local_1464 = _e4756;
                    switch bitcast<i32>(0u) {
                        default: {
                            let _e4758 = local_1464;
                            let _e4761 = i32((0.5f - _e4758.w));
                            local_873 = _e4761;
                            let _e4762 = local_1463;
                            let _e4763 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4766 = local_872;
                            let _e4769 = vec2<i32>(vec2<i32>(_e4763).x, _e4766.y);
                            let _e4770 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4775 = vec2<i32>(_e4769.x, vec2<i32>(_e4770).y);
                            local_872 = _e4775;
                            let _e4781 = (((_e4762.y * _e4775.x) + _e4762.x) + 2i);
                            let _e4790 = vec2<i32>((_e4781 - (i32(floor((f32(_e4781) / f32(_e4775.x)))) * _e4775.x)), (_e4781 / _e4775.x));
                            let _e4793 = vec3<i32>(_e4790.x, _e4790.y, 0i);
                            let _e4796 = textureLoad(u_layer_tex_0_image, _e4793.xy, _e4793.z);
                            local_874 = _e4796;
                            if (_e4761 == 1i) {
                                let _e4798 = local_874;
                                local_101 = _e4798;
                                local_100 = 0f;
                                break;
                            }
                            let _e4799 = local_1463;
                            let _e4800 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4803 = local_871;
                            let _e4806 = vec2<i32>(vec2<i32>(_e4800).x, _e4803.y);
                            let _e4807 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4812 = vec2<i32>(_e4806.x, vec2<i32>(_e4807).y);
                            local_871 = _e4812;
                            let _e4818 = (((_e4799.y * _e4812.x) + _e4799.x) + 3i);
                            let _e4827 = vec2<i32>((_e4818 - (i32(floor((f32(_e4818) / f32(_e4812.x)))) * _e4812.x)), (_e4818 / _e4812.x));
                            let _e4830 = vec3<i32>(_e4827.x, _e4827.y, 0i);
                            let _e4833 = textureLoad(u_layer_tex_0_image, _e4830.xy, _e4830.z);
                            local_875 = _e4833;
                            let _e4834 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4837 = local_870;
                            let _e4840 = vec2<i32>(vec2<i32>(_e4834).x, _e4837.y);
                            let _e4841 = textureDimensions(u_layer_tex_0_image, 0i);
                            let _e4846 = vec2<i32>(_e4840.x, vec2<i32>(_e4841).y);
                            local_870 = _e4846;
                            let _e4852 = (((_e4799.y * _e4846.x) + _e4799.x) + 4i);
                            let _e4861 = vec2<i32>((_e4852 - (i32(floor((f32(_e4852) / f32(_e4846.x)))) * _e4846.x)), (_e4852 / _e4846.x));
                            let _e4864 = vec3<i32>(_e4861.x, _e4861.y, 0i);
                            let _e4867 = textureLoad(u_layer_tex_0_image, _e4864.xy, _e4864.z);
                            local_876 = _e4867;
                            let _e4868 = local_873;
                            if (_e4868 == 2i) {
                                let _e4870 = local_874;
                                let _e4871 = _e4870.xy;
                                local_877 = _e4871;
                                let _e4873 = (_e4870.zw - _e4871);
                                local_878 = _e4873;
                                let _e4874 = dot(_e4873, _e4873);
                                local_879 = _e4874;
                                if (_e4874 > 0.0000000001f) {
                                    let _e4876 = local_1462;
                                    let _e4877 = local_877;
                                    let _e4879 = local_878;
                                    let _e4881 = local_879;
                                    local_880 = (dot((_e4876 - _e4877), _e4879) / _e4881);
                                } else {
                                    local_880 = 0f;
                                }
                                let _e4883 = local_1463;
                                let _e4884 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e4887 = local_869;
                                let _e4890 = vec2<i32>(vec2<i32>(_e4884).x, _e4887.y);
                                let _e4891 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e4896 = vec2<i32>(_e4890.x, vec2<i32>(_e4891).y);
                                local_869 = _e4896;
                                let _e4902 = (((_e4883.y * _e4896.x) + _e4883.x) + 5i);
                                let _e4911 = vec2<i32>((_e4902 - (i32(floor((f32(_e4902) / f32(_e4896.x)))) * _e4896.x)), (_e4902 / _e4896.x));
                                let _e4914 = vec3<i32>(_e4911.x, _e4911.y, 0i);
                                let _e4917 = textureLoad(u_layer_tex_0_image, _e4914.xy, _e4914.z);
                                let _e4918 = local_880;
                                local_881 = _e4918;
                                local_882 = _e4917.x;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e4921 = local_882;
                                        let _e4923 = i32((_e4921 + 0.5f));
                                        local_866 = _e4923;
                                        if (_e4923 == 1i) {
                                            let _e4925 = local_881;
                                            local_865 = fract(_e4925);
                                            break;
                                        }
                                        let _e4927 = local_866;
                                        if (_e4927 == 2i) {
                                            let _e4929 = local_881;
                                            let _e4933 = (_e4929 - (floor((_e4929 / 2f)) * 2f));
                                            local_867 = _e4933;
                                            if (_e4933 < 0f) {
                                                let _e4935 = local_867;
                                                local_868 = (_e4935 + 2f);
                                            } else {
                                                let _e4937 = local_867;
                                                local_868 = _e4937;
                                            }
                                            let _e4938 = local_868;
                                            local_865 = (1f - abs((_e4938 - 1f)));
                                            break;
                                        }
                                        let _e4942 = local_881;
                                        local_865 = clamp(_e4942, 0f, 1f);
                                        break;
                                    }
                                }
                                let _e4944 = local_865;
                                let _e4945 = local_875;
                                let _e4946 = local_876;
                                local_101 = mix(_e4945, _e4946, vec4(_e4944));
                                local_100 = 1f;
                                break;
                            }
                            let _e4949 = local_873;
                            if (_e4949 == 3i) {
                                let _e4951 = local_1462;
                                let _e4952 = local_874;
                                local_883 = (length((_e4951 - _e4952.xy)) / max(abs(_e4952.z), 0.000015258789f));
                                local_884 = _e4952.w;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e4962 = local_884;
                                        let _e4964 = i32((_e4962 + 0.5f));
                                        local_862 = _e4964;
                                        if (_e4964 == 1i) {
                                            let _e4966 = local_883;
                                            local_861 = fract(_e4966);
                                            break;
                                        }
                                        let _e4968 = local_862;
                                        if (_e4968 == 2i) {
                                            let _e4970 = local_883;
                                            let _e4974 = (_e4970 - (floor((_e4970 / 2f)) * 2f));
                                            local_863 = _e4974;
                                            if (_e4974 < 0f) {
                                                let _e4976 = local_863;
                                                local_864 = (_e4976 + 2f);
                                            } else {
                                                let _e4978 = local_863;
                                                local_864 = _e4978;
                                            }
                                            let _e4979 = local_864;
                                            local_861 = (1f - abs((_e4979 - 1f)));
                                            break;
                                        }
                                        let _e4983 = local_883;
                                        local_861 = clamp(_e4983, 0f, 1f);
                                        break;
                                    }
                                }
                                let _e4985 = local_861;
                                let _e4986 = local_875;
                                let _e4987 = local_876;
                                local_101 = mix(_e4986, _e4987, vec4(_e4985));
                                local_100 = 1f;
                                break;
                            }
                            let _e4990 = local_873;
                            if (_e4990 == 6i) {
                                let _e4992 = local_1462;
                                let _e4993 = local_874;
                                let _e4995 = (_e4992 - _e4993.xy);
                                local_885 = ((atan2(_e4995.y, _e4995.x) - _e4993.z) * 0.15915494f);
                                local_886 = _e4993.w;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e5004 = local_886;
                                        let _e5006 = i32((_e5004 + 0.5f));
                                        local_858 = _e5006;
                                        if (_e5006 == 1i) {
                                            let _e5008 = local_885;
                                            local_857 = fract(_e5008);
                                            break;
                                        }
                                        let _e5010 = local_858;
                                        if (_e5010 == 2i) {
                                            let _e5012 = local_885;
                                            let _e5016 = (_e5012 - (floor((_e5012 / 2f)) * 2f));
                                            local_859 = _e5016;
                                            if (_e5016 < 0f) {
                                                let _e5018 = local_859;
                                                local_860 = (_e5018 + 2f);
                                            } else {
                                                let _e5020 = local_859;
                                                local_860 = _e5020;
                                            }
                                            let _e5021 = local_860;
                                            local_857 = (1f - abs((_e5021 - 1f)));
                                            break;
                                        }
                                        let _e5025 = local_885;
                                        local_857 = clamp(_e5025, 0f, 1f);
                                        break;
                                    }
                                }
                                let _e5027 = local_857;
                                let _e5028 = local_875;
                                let _e5029 = local_876;
                                local_101 = mix(_e5028, _e5029, vec4(_e5027));
                                local_100 = 1f;
                                break;
                            }
                            let _e5032 = local_873;
                            if (_e5032 == 4i) {
                                let _e5034 = local_1463;
                                let _e5035 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e5038 = local_856;
                                let _e5041 = vec2<i32>(vec2<i32>(_e5035).x, _e5038.y);
                                let _e5042 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e5047 = vec2<i32>(_e5041.x, vec2<i32>(_e5042).y);
                                local_856 = _e5047;
                                let _e5053 = (((_e5034.y * _e5047.x) + _e5034.x) + 3i);
                                let _e5062 = vec2<i32>((_e5053 - (i32(floor((f32(_e5053) / f32(_e5047.x)))) * _e5047.x)), (_e5053 / _e5047.x));
                                let _e5065 = vec3<i32>(_e5062.x, _e5062.y, 0i);
                                let _e5068 = textureLoad(u_layer_tex_0_image, _e5065.xy, _e5065.z);
                                local_887 = _e5068;
                                let _e5069 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e5072 = local_855;
                                let _e5075 = vec2<i32>(vec2<i32>(_e5069).x, _e5072.y);
                                let _e5076 = textureDimensions(u_layer_tex_0_image, 0i);
                                let _e5081 = vec2<i32>(_e5075.x, vec2<i32>(_e5076).y);
                                local_855 = _e5081;
                                let _e5087 = (((_e5034.y * _e5081.x) + _e5034.x) + 5i);
                                let _e5096 = vec2<i32>((_e5087 - (i32(floor((f32(_e5087) / f32(_e5081.x)))) * _e5081.x)), (_e5087 / _e5081.x));
                                let _e5099 = vec3<i32>(_e5096.x, _e5096.y, 0i);
                                let _e5102 = textureLoad(u_layer_tex_0_image, _e5099.xy, _e5099.z);
                                local_888 = _e5102;
                                let _e5103 = local_1462;
                                let _e5106 = vec3<f32>(_e5103.x, _e5103.y, 1f);
                                local_889 = _e5106;
                                let _e5107 = local_874;
                                local_890 = dot(_e5106, vec3<f32>(_e5107.x, _e5107.y, _e5107.z));
                                local_891 = _e5102.z;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e5115 = local_891;
                                        let _e5117 = i32((_e5115 + 0.5f));
                                        local_852 = _e5117;
                                        if (_e5117 == 1i) {
                                            let _e5119 = local_890;
                                            local_851 = fract(_e5119);
                                            break;
                                        }
                                        let _e5121 = local_852;
                                        if (_e5121 == 2i) {
                                            let _e5123 = local_890;
                                            let _e5127 = (_e5123 - (floor((_e5123 / 2f)) * 2f));
                                            local_853 = _e5127;
                                            if (_e5127 < 0f) {
                                                let _e5129 = local_853;
                                                local_854 = (_e5129 + 2f);
                                            } else {
                                                let _e5131 = local_853;
                                                local_854 = _e5131;
                                            }
                                            let _e5132 = local_854;
                                            local_851 = (1f - abs((_e5132 - 1f)));
                                            break;
                                        }
                                        let _e5136 = local_890;
                                        local_851 = clamp(_e5136, 0f, 1f);
                                        break;
                                    }
                                }
                                let _e5138 = local_851;
                                let _e5139 = local_888;
                                let _e5142 = local_889;
                                let _e5143 = local_887;
                                local_892 = dot(_e5142, vec3<f32>(_e5143.x, _e5143.y, _e5143.z));
                                local_893 = _e5139.w;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e5151 = local_893;
                                        let _e5153 = i32((_e5151 + 0.5f));
                                        local_848 = _e5153;
                                        if (_e5153 == 1i) {
                                            let _e5155 = local_892;
                                            local_847 = fract(_e5155);
                                            break;
                                        }
                                        let _e5157 = local_848;
                                        if (_e5157 == 2i) {
                                            let _e5159 = local_892;
                                            let _e5163 = (_e5159 - (floor((_e5159 / 2f)) * 2f));
                                            local_849 = _e5163;
                                            if (_e5163 < 0f) {
                                                let _e5165 = local_849;
                                                local_850 = (_e5165 + 2f);
                                            } else {
                                                let _e5167 = local_849;
                                                local_850 = _e5167;
                                            }
                                            let _e5168 = local_850;
                                            local_847 = (1f - abs((_e5168 - 1f)));
                                            break;
                                        }
                                        let _e5172 = local_892;
                                        local_847 = clamp(_e5172, 0f, 1f);
                                        break;
                                    }
                                }
                                let _e5174 = local_847;
                                let _e5175 = local_888;
                                let _e5179 = local_874;
                                let _e5183 = local_887;
                                local_894 = vec2<f32>((_e5138 * _e5139.x), (_e5174 * _e5175.y));
                                local_895 = i32((_e5179.w + 0.5f));
                                local_896 = i32((_e5183.w + 0.5f));
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e5188 = local_896;
                                        if (_e5188 == 1i) {
                                            let _e5190 = textureDimensions(u_image_tex_0_image, 0i);
                                            let _e5193 = local_846;
                                            let _e5197 = vec3<i32>(vec2<i32>(_e5190).x, _e5193.y, _e5193.z);
                                            let _e5198 = textureDimensions(u_image_tex_0_image, 0i);
                                            let _e5204 = vec3<i32>(_e5197.x, vec2<i32>(_e5198).y, _e5197.z);
                                            let _e5205 = textureDimensions(u_image_tex_0_image, 0i);
                                            let _e5211 = vec3<i32>(_e5204.x, _e5204.y, vec2<i32>(_e5205).y);
                                            local_846 = _e5211;
                                            let _e5212 = _e5211.xy;
                                            let _e5213 = local_894;
                                            let _e5218 = clamp(vec2<i32>((_e5213 * vec2<f32>(_e5212))), vec2<i32>(0i, 0i), (_e5212 - vec2<i32>(1i, 1i)));
                                            let _e5219 = local_895;
                                            let _e5222 = vec4<i32>(_e5218.x, _e5218.y, _e5219, 0i);
                                            let _e5223 = _e5222.xyz;
                                            let _e5230 = textureLoad(u_image_tex_0_image, vec2<i32>(_e5223.x, _e5223.y), i32(_e5223.z), _e5222.w);
                                            local_845 = _e5230;
                                            break;
                                        }
                                        let _e5231 = local_894;
                                        let _e5232 = local_895;
                                        let _e5236 = vec3<f32>(_e5231.x, _e5231.y, f32(_e5232));
                                        let _e5242 = textureSample(u_image_tex_0_image, u_image_tex_0_sampler, vec2<f32>(_e5236.x, _e5236.y), i32(_e5236.z));
                                        local_845 = _e5242;
                                        break;
                                    }
                                }
                                let _e5243 = local_845;
                                local_101 = _e5243;
                                local_100 = 0f;
                                break;
                            }
                            local_101 = vec4<f32>(1f, 0f, 1f, 1f);
                            local_100 = 0f;
                            break;
                        }
                    }
                    let _e5244 = local_100;
                    let _e5245 = local_101;
                    local_6 = _e5244;
                    let _e5246 = local_1484;
                    local_7 = (_e5245 * _e5246);
                    let _e5248 = local_1448;
                    if (_e5248 == 1i) {
                        let _e5250 = local_1447;
                        local_1465 = (_e5250 >= 2i);
                    } else {
                        local_1465 = false;
                    }
                    let _e5252 = local_1465;
                    if _e5252 {
                        let _e5253 = local_1453;
                        local_1466 = (_e5253 < 2i);
                    } else {
                        local_1466 = false;
                    }
                    let _e5255 = local_1466;
                    if _e5255 {
                        let _e5256 = local_1453;
                        if (_e5256 == 0i) {
                            let _e5258 = local_1456;
                            local_1467 = _e5258;
                            let _e5259 = local_1451;
                            local_1468 = _e5259;
                            let _e5260 = local_6;
                            let _e5261 = local_7;
                            local_5 = _e5261;
                            local_4 = _e5260;
                            let _e5262 = local_8;
                            let _e5263 = local_9;
                            local_3 = _e5263;
                            local_2 = _e5262;
                        } else {
                            let _e5264 = local_1450;
                            local_1467 = _e5264;
                            let _e5265 = local_1456;
                            local_1468 = _e5265;
                            let _e5266 = local_10;
                            let _e5267 = local_11;
                            local_5 = _e5267;
                            local_4 = _e5266;
                            let _e5268 = local_6;
                            let _e5269 = local_7;
                            local_3 = _e5269;
                            local_2 = _e5268;
                        }
                        let _e5270 = local_1467;
                        local_1450 = _e5270;
                        let _e5271 = local_1468;
                        local_1451 = _e5271;
                        let _e5272 = local_4;
                        let _e5273 = local_5;
                        local_11 = _e5273;
                        local_10 = _e5272;
                        let _e5274 = local_2;
                        let _e5275 = local_3;
                        local_9 = _e5275;
                        local_8 = _e5274;
                        let _e5276 = local_1453;
                        local_1453 = (_e5276 + 1i);
                        continue;
                    }
                    let _e5278 = local_6;
                    if (_e5278 > 0.5f) {
                        let _e5280 = local_1456;
                        local_1469 = (_e5280 > 0.000001f);
                    } else {
                        local_1469 = false;
                    }
                    let _e5282 = local_1469;
                    if _e5282 {
                        local_1467 = 1f;
                    } else {
                        let _e5283 = local_1452;
                        local_1467 = _e5283;
                    }
                    let _e5284 = local_7;
                    let _e5285 = local_1456;
                    let _e5287 = (_e5284.w * _e5285);
                    let _e5289 = (_e5284.xyz * _e5287);
                    let _e5293 = vec4<f32>(_e5289.x, _e5289.y, _e5289.z, _e5287);
                    let _e5294 = local_1449;
                    local_1449 = (_e5293 + (_e5294 * (1f - _e5293.w)));
                    let _e5299 = local_1467;
                    local_1452 = _e5299;
                    let _e5300 = local_1453;
                    local_1453 = (_e5300 + 1i);
                    continue;
                }
                let _e5302 = local_1448;
                if (_e5302 == 1i) {
                    let _e5304 = local_1447;
                    local_1465 = (_e5304 >= 2i);
                } else {
                    local_1465 = false;
                }
                let _e5306 = local_1465;
                if _e5306 {
                    let _e5307 = local_1450;
                    let _e5308 = local_1451;
                    let _e5309 = min(_e5307, _e5308);
                    local_1470 = _e5309;
                    local_1471 = max((_e5307 - _e5309), 0f);
                    let _e5312 = local_10;
                    if (_e5312 > 0.5f) {
                        let _e5314 = local_1471;
                        local_1465 = (_e5314 > 0.000001f);
                    } else {
                        local_1465 = false;
                    }
                    let _e5316 = local_1465;
                    if _e5316 {
                        local_1452 = 1f;
                    }
                    let _e5317 = local_8;
                    if (_e5317 > 0.5f) {
                        let _e5319 = local_1470;
                        local_1465 = (_e5319 > 0.000001f);
                    } else {
                        local_1465 = false;
                    }
                    let _e5321 = local_1465;
                    if _e5321 {
                        local_1452 = 1f;
                    }
                    let _e5322 = local_1449;
                    let _e5323 = local_11;
                    let _e5324 = local_1471;
                    let _e5326 = (_e5323.w * _e5324);
                    let _e5328 = (_e5323.xyz * _e5326);
                    let _e5333 = local_9;
                    let _e5334 = local_1470;
                    let _e5336 = (_e5333.w * _e5334);
                    let _e5338 = (_e5333.xyz * _e5336);
                    local_1449 = (_e5322 + ((vec4<f32>(_e5328.x, _e5328.y, _e5328.z, _e5326) + vec4<f32>(_e5338.x, _e5338.y, _e5338.z, _e5336)) * (1f - _e5322.w)));
                }
                let _e5348 = local_1449;
                let _e5349 = local_1452;
                local_1 = _e5348;
                local = _e5349;
                if (_e5348.w < 0.003921569f) {
                    discard;
                }
                let _e5352 = local;
                if (_e5352 > 0.5f) {
                    let _e5354 = local_1;
                    local_1486 = _e5354;
                    switch bitcast<i32>(0u) {
                        default: {
                            let _e5356 = local_1486;
                            local_841 = _e5356.w;
                            if (_e5356.w <= 0f) {
                                local_842 = true;
                            } else {
                                let _e5360 = PushConstants_0_.dither_scale_0_;
                                local_842 = (_e5360 <= 0f);
                            }
                            let _e5362 = local_842;
                            if _e5362 {
                                let _e5363 = local_1486;
                                local_840 = _e5363;
                                break;
                            }
                            let _e5364 = local_1486;
                            let _e5365 = _e5364.xyz;
                            local_843 = _e5365;
                            let _e5367 = max(_e5365.x, 0f);
                            local_837 = _e5367;
                            if (_e5367 <= 0.0031308f) {
                                let _e5369 = local_837;
                                local_836 = (_e5369 * 12.92f);
                            } else {
                                let _e5371 = local_837;
                                local_836 = ((1.055f * pow(_e5371, 0.41666666f)) - 0.055f);
                            }
                            let _e5375 = local_836;
                            let _e5376 = local_843;
                            let _e5378 = max(_e5376.y, 0f);
                            local_838 = _e5378;
                            if (_e5378 <= 0.0031308f) {
                                let _e5380 = local_838;
                                local_835 = (_e5380 * 12.92f);
                            } else {
                                let _e5382 = local_838;
                                local_835 = ((1.055f * pow(_e5382, 0.41666666f)) - 0.055f);
                            }
                            let _e5386 = local_835;
                            let _e5387 = local_843;
                            let _e5389 = max(_e5387.z, 0f);
                            local_839 = _e5389;
                            if (_e5389 <= 0.0031308f) {
                                let _e5391 = local_839;
                                local_834 = (_e5391 * 12.92f);
                            } else {
                                let _e5393 = local_839;
                                local_834 = ((1.055f * pow(_e5393, 0.41666666f)) - 0.055f);
                            }
                            let _e5397 = local_834;
                            let _e5399 = gl_FragCoord_1;
                            let _e5406 = local_841;
                            let _e5409 = PushConstants_0_.dither_scale_0_;
                            let _e5414 = clamp((vec3<f32>(_e5375, _e5386, _e5397) + vec3(((fract((52.982918f * fract(dot(_e5399.xy, vec2<f32>(0.06711056f, 0.00583715f))))) - 0.5f) * (clamp(_e5406, 0f, 1f) * _e5409)))), vec3<f32>(0f, 0f, 0f), vec3<f32>(1f, 1f, 1f));
                            local_844 = _e5414;
                            local_831 = _e5414.x;
                            if (_e5414.x <= 0.04045f) {
                                let _e5417 = local_831;
                                local_830 = (_e5417 * 0.07739938f);
                            } else {
                                let _e5419 = local_831;
                                local_830 = pow(((_e5419 + 0.055f) * 0.94786733f), 2.4f);
                            }
                            let _e5423 = local_830;
                            let _e5424 = local_844;
                            local_832 = _e5424.y;
                            if (_e5424.y <= 0.04045f) {
                                let _e5427 = local_832;
                                local_829 = (_e5427 * 0.07739938f);
                            } else {
                                let _e5429 = local_832;
                                local_829 = pow(((_e5429 + 0.055f) * 0.94786733f), 2.4f);
                            }
                            let _e5433 = local_829;
                            let _e5434 = local_844;
                            local_833 = _e5434.z;
                            if (_e5434.z <= 0.04045f) {
                                let _e5437 = local_833;
                                local_828 = (_e5437 * 0.07739938f);
                            } else {
                                let _e5439 = local_833;
                                local_828 = pow(((_e5439 + 0.055f) * 0.94786733f), 2.4f);
                            }
                            let _e5443 = local_828;
                            let _e5444 = vec3<f32>(_e5423, _e5433, _e5443);
                            let _e5445 = local_841;
                            local_840 = vec4<f32>(_e5444.x, _e5444.y, _e5444.z, _e5445);
                            break;
                        }
                    }
                    let _e5450 = local_840;
                    local_1485 = _e5450;
                } else {
                    let _e5451 = local_1;
                    local_1485 = _e5451;
                }
                let _e5453 = PushConstants_0_.mask_output_0_;
                if (_e5453 != 0i) {
                    let _e5455 = local_1485;
                    local_1485 = vec4(_e5455.w);
                } else {
                    let _e5459 = PushConstants_0_.output_srgb_0_;
                    if (_e5459 != 0i) {
                        let _e5461 = local_1485;
                        local_1487 = _e5461;
                        switch bitcast<i32>(0u) {
                            default: {
                                let _e5463 = local_1487;
                                local_826 = _e5463.w;
                                if (_e5463.w <= 0f) {
                                    local_825 = vec4<f32>(0f, 0f, 0f, 0f);
                                    break;
                                }
                                let _e5466 = local_1487;
                                let _e5468 = local_826;
                                let _e5470 = (_e5466.xyz * (1f / _e5468));
                                local_827 = _e5470;
                                let _e5472 = max(_e5470.x, 0f);
                                local_822 = _e5472;
                                if (_e5472 <= 0.0031308f) {
                                    let _e5474 = local_822;
                                    local_821 = (_e5474 * 12.92f);
                                } else {
                                    let _e5476 = local_822;
                                    local_821 = ((1.055f * pow(_e5476, 0.41666666f)) - 0.055f);
                                }
                                let _e5480 = local_821;
                                let _e5481 = local_827;
                                let _e5483 = max(_e5481.y, 0f);
                                local_823 = _e5483;
                                if (_e5483 <= 0.0031308f) {
                                    let _e5485 = local_823;
                                    local_820 = (_e5485 * 12.92f);
                                } else {
                                    let _e5487 = local_823;
                                    local_820 = ((1.055f * pow(_e5487, 0.41666666f)) - 0.055f);
                                }
                                let _e5491 = local_820;
                                let _e5492 = local_827;
                                let _e5494 = max(_e5492.z, 0f);
                                local_824 = _e5494;
                                if (_e5494 <= 0.0031308f) {
                                    let _e5496 = local_824;
                                    local_819 = (_e5496 * 12.92f);
                                } else {
                                    let _e5498 = local_824;
                                    local_819 = ((1.055f * pow(_e5498, 0.41666666f)) - 0.055f);
                                }
                                let _e5502 = local_819;
                                let _e5504 = local_826;
                                let _e5505 = (vec3<f32>(_e5480, _e5491, _e5502) * _e5504);
                                local_825 = vec4<f32>(_e5505.x, _e5505.y, _e5505.z, _e5504);
                                break;
                            }
                        }
                        let _e5510 = local_825;
                        local_1485 = _e5510;
                    }
                }
                let _e5511 = local_1485;
                _S118_ = _e5511;
                break;
            }
            let _e5512 = local_1475;
            let _e5513 = textureDimensions(u_layer_tex_0_image, 0i);
            let _e5516 = local_818;
            let _e5519 = vec2<i32>(vec2<i32>(_e5513).x, _e5516.y);
            let _e5520 = textureDimensions(u_layer_tex_0_image, 0i);
            let _e5525 = vec2<i32>(_e5519.x, vec2<i32>(_e5520).y);
            local_818 = _e5525;
            let _e5531 = (((_e5512.y * _e5525.x) + _e5512.x) + 1i);
            let _e5540 = vec2<i32>((_e5531 - (i32(floor((f32(_e5531) / f32(_e5525.x)))) * _e5525.x)), (_e5531 / _e5525.x));
            let _e5543 = vec3<i32>(_e5540.x, _e5540.y, 0i);
            let _e5544 = local_1476;
            let _e5546 = i32(_e5544.x);
            let _e5548 = bitcast<i32>(_e5544.z);
            let _e5552 = vec2<i32>((_e5546 & 32767i), i32(_e5544.y));
            let _e5557 = vec2<i32>(((_e5548 >> bitcast<u32>(16i)) & 65535i), (_e5548 & 65535i));
            let _e5560 = textureLoad(u_layer_tex_0_image, _e5543.xy, _e5543.z);
            let _e5564 = v_texcoord_0_1;
            local_1489 = _e5564;
            let _e5565 = local_1472;
            let _e5566 = local_1473;
            local_1490 = _e5566;
            local_1491 = _e5552;
            let _e5567 = local_1478;
            local_1492 = _e5567;
            local_1493 = ((_e5546 >> bitcast<u32>(15i)) & 1i);
            local_792 = _e5557.y;
            let _e5574 = ((_e5564.y * _e5560.y) + _e5560.w);
            let _e5578 = max((abs((_e5565.y * _e5560.y)) * 0.5f), 0.00001f);
            let _e5581 = clamp(i32((_e5574 - _e5578)), 0i, _e5557.y);
            let _e5585 = max(_e5581, clamp(i32((_e5574 + _e5578)), 0i, _e5557.y));
            let _e5592 = ((_e5564.x * _e5560.x) + _e5560.z);
            let _e5596 = max((abs((_e5565.x * _e5560.x)) * 0.5f), 0.00001f);
            let _e5599 = clamp(i32((_e5592 - _e5596)), 0i, _e5557.x);
            local_103 = _e5599;
            local_102 = max(_e5599, clamp(i32((_e5592 + _e5596)), 0i, _e5557.x));
            local_794 = _e5564;
            local_795 = _e5566.x;
            local_796 = _e5552;
            local_797 = 0i;
            local_798 = _e5581;
            local_799 = _e5585;
            local_800 = _e5567;
            local_801 = true;
            local_777 = 0f;
            local_778 = 0f;
            local_779 = (_e5581 != _e5585);
            local_780 = _e5581;
            loop {
                let _e5606 = local_780;
                let _e5607 = local_799;
                if (_e5606 <= _e5607) {
                } else {
                    break;
                }
                let _e5609 = local_797;
                let _e5610 = local_780;
                let _e5613 = local_796;
                let _e5616 = (_e5613.x + bitcast<i32>(bitcast<u32>((_e5609 + _e5610))));
                let _e5618 = vec2<i32>(_e5616, _e5613.y);
                let _e5625 = vec2<i32>(_e5618.x, (_e5618.y + (_e5616 >> bitcast<u32>(12i))));
                let _e5630 = vec2<i32>((_e5625.x & 4095i), _e5625.y);
                let _e5631 = local_800;
                let _e5634 = vec4<i32>(_e5630.x, _e5630.y, _e5631, 0i);
                let _e5635 = _e5634.xyz;
                let _e5642 = textureLoad(u_band_tex_0_image, vec2<i32>(_e5635.x, _e5635.y), i32(_e5635.z), _e5634.w);
                let _e5643 = _e5642.xy;
                let _e5647 = (_e5613.x + bitcast<i32>(_e5643.y));
                let _e5649 = vec2<i32>(_e5647, _e5613.y);
                let _e5656 = vec2<i32>(_e5649.x, (_e5649.y + (_e5647 >> bitcast<u32>(12i))));
                local_781 = vec2<i32>((_e5656.x & 4095i), _e5656.y);
                local_782 = bitcast<i32>(_e5643.x);
                local_783 = 0i;
                loop {
                    let _e5664 = local_783;
                    let _e5665 = local_782;
                    if (_e5664 < _e5665) {
                    } else {
                        break;
                    }
                    let _e5667 = local_783;
                    let _e5669 = local_781;
                    let _e5672 = (_e5669.x + bitcast<i32>(bitcast<u32>(_e5667)));
                    let _e5674 = vec2<i32>(_e5672, _e5669.y);
                    let _e5681 = vec2<i32>(_e5674.x, (_e5674.y + (_e5672 >> bitcast<u32>(12i))));
                    let _e5686 = vec2<i32>((_e5681.x & 4095i), _e5681.y);
                    let _e5687 = local_800;
                    let _e5690 = vec4<i32>(_e5686.x, _e5686.y, _e5687, 0i);
                    let _e5691 = _e5690.xyz;
                    let _e5698 = textureLoad(u_band_tex_0_image, vec2<i32>(_e5691.x, _e5691.y), i32(_e5691.z), _e5690.w);
                    local_784 = _e5698.xy;
                    let _e5700 = local_779;
                    if _e5700 {
                        let _e5701 = local_780;
                        let _e5702 = local_784;
                        let _e5707 = local_798;
                        if (_e5701 != max(bitcast<i32>((_e5702.x >> bitcast<u32>(12u))), _e5707)) {
                            let _e5710 = local_783;
                            local_783 = (_e5710 + 1i);
                            continue;
                        }
                    }
                    let _e5712 = local_784;
                    let _e5719 = vec2<i32>(bitcast<i32>((_e5712.x & 4095u)), bitcast<i32>((_e5712.y & 16383u)));
                    let _e5723 = bitcast<i32>((_e5712.y >> bitcast<u32>(14u)));
                    local_785 = _e5719;
                    let _e5724 = local_800;
                    local_786 = _e5724;
                    let _e5727 = vec4<i32>(_e5719.x, _e5719.y, _e5724, 0i);
                    let _e5728 = _e5727.xyz;
                    let _e5735 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e5728.x, _e5728.y), i32(_e5728.z), _e5727.w);
                    let _e5737 = (_e5719.x + 1i);
                    let _e5739 = vec2<i32>(_e5737, _e5719.y);
                    let _e5746 = vec2<i32>(_e5739.x, (_e5739.y + (_e5737 >> bitcast<u32>(12i))));
                    let _e5751 = vec2<i32>((_e5746.x & 4095i), _e5746.y);
                    let _e5754 = vec4<i32>(_e5751.x, _e5751.y, _e5724, 0i);
                    let _e5755 = _e5754.xyz;
                    let _e5762 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e5755.x, _e5755.y), i32(_e5755.z), _e5754.w);
                    local_115 = _e5723;
                    local_114 = _e5735.xy;
                    local_113 = _e5735.zw;
                    local_112 = _e5762.xy;
                    local_111 = _e5762.zw;
                    if (_e5723 == 1i) {
                        let _e5768 = local_785;
                        let _e5770 = (_e5768.x + 2i);
                        let _e5772 = vec2<i32>(_e5770, _e5768.y);
                        let _e5779 = vec2<i32>(_e5772.x, (_e5772.y + (_e5770 >> bitcast<u32>(12i))));
                        let _e5784 = vec2<i32>((_e5779.x & 4095i), _e5779.y);
                        let _e5785 = local_786;
                        let _e5788 = vec4<i32>(_e5784.x, _e5784.y, _e5785, 0i);
                        let _e5789 = _e5788.xyz;
                        let _e5796 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e5789.x, _e5789.y), i32(_e5789.z), _e5788.w);
                        local_110 = vec3<f32>(_e5796.w, _e5796.x, _e5796.y);
                    } else {
                        local_110 = vec3<f32>(1f, 1f, 1f);
                    }
                    let _e5801 = local_110;
                    let _e5802 = local_111;
                    let _e5803 = local_112;
                    let _e5804 = local_113;
                    let _e5805 = local_114;
                    let _e5806 = local_115;
                    let _e5807 = local_777;
                    local_787 = _e5807;
                    let _e5808 = local_778;
                    local_788 = _e5808;
                    let _e5809 = local_794;
                    local_789 = _e5809;
                    let _e5810 = local_795;
                    local_790 = _e5810;
                    local_109 = _e5806;
                    local_108 = _e5805;
                    local_107 = _e5804;
                    local_106 = _e5803;
                    local_105 = _e5802;
                    local_104 = _e5801;
                    let _e5811 = local_801;
                    local_791 = _e5811;
                    switch bitcast<i32>(0u) {
                        default: {
                            let _e5813 = local_791;
                            if _e5813 {
                                let _e5814 = local_105;
                                let _e5815 = local_106;
                                let _e5816 = local_107;
                                let _e5817 = local_108;
                                let _e5818 = local_109;
                                local_136 = _e5818;
                                local_135 = _e5817;
                                local_134 = _e5816;
                                local_133 = _e5815;
                                local_132 = _e5814;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e5820 = local_136;
                                        if (_e5820 == 3i) {
                                            let _e5822 = local_135;
                                            let _e5824 = local_133;
                                            local_736 = max(_e5822.x, _e5824.x);
                                            break;
                                        }
                                        let _e5827 = local_136;
                                        if (_e5827 == 2i) {
                                            let _e5829 = local_135;
                                            let _e5831 = local_134;
                                            let _e5834 = local_133;
                                            let _e5836 = local_132;
                                            local_736 = max(max(_e5829.x, _e5831.x), max(_e5834.x, _e5836.x));
                                            break;
                                        }
                                        let _e5840 = local_135;
                                        let _e5842 = local_134;
                                        let _e5845 = local_133;
                                        local_736 = max(max(_e5840.x, _e5842.x), _e5845.x);
                                        break;
                                    }
                                }
                                let _e5848 = local_736;
                                let _e5849 = local_789;
                                local_738 = (_e5848 - _e5849.x);
                            } else {
                                let _e5852 = local_105;
                                let _e5853 = local_106;
                                let _e5854 = local_107;
                                let _e5855 = local_108;
                                let _e5856 = local_109;
                                local_131 = _e5856;
                                local_130 = _e5855;
                                local_129 = _e5854;
                                local_128 = _e5853;
                                local_127 = _e5852;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e5858 = local_131;
                                        if (_e5858 == 3i) {
                                            let _e5860 = local_130;
                                            let _e5862 = local_128;
                                            local_735 = max(_e5860.y, _e5862.y);
                                            break;
                                        }
                                        let _e5865 = local_131;
                                        if (_e5865 == 2i) {
                                            let _e5867 = local_130;
                                            let _e5869 = local_129;
                                            let _e5872 = local_128;
                                            let _e5874 = local_127;
                                            local_735 = max(max(_e5867.y, _e5869.y), max(_e5872.y, _e5874.y));
                                            break;
                                        }
                                        let _e5878 = local_130;
                                        let _e5880 = local_129;
                                        let _e5883 = local_128;
                                        local_735 = max(max(_e5878.y, _e5880.y), _e5883.y);
                                        break;
                                    }
                                }
                                let _e5886 = local_735;
                                let _e5887 = local_789;
                                local_738 = (_e5886 - _e5887.y);
                            }
                            let _e5890 = local_738;
                            let _e5891 = local_790;
                            if ((_e5890 * _e5891) < -0.5f) {
                                local_737 = false;
                                break;
                            }
                            let _e5894 = local_109;
                            if (_e5894 == 0i) {
                                let _e5896 = local_789;
                                let _e5898 = local_108;
                                local_739 = (_e5898.x - _e5896.x);
                                local_740 = (_e5898.y - _e5896.y);
                                let _e5904 = local_107;
                                local_741 = (_e5904.x - _e5896.x);
                                local_742 = (_e5904.y - _e5896.y);
                                let _e5909 = local_106;
                                local_743 = (_e5909.x - _e5896.x);
                                local_744 = (_e5909.y - _e5896.y);
                                let _e5914 = local_791;
                                if _e5914 {
                                    let _e5915 = local_740;
                                    local_746 = _e5915;
                                    let _e5916 = local_742;
                                    local_747 = _e5916;
                                    let _e5917 = local_744;
                                    local_732 = _e5917;
                                    if (abs(_e5917) <= 0.000015258789f) {
                                        local_731 = 0f;
                                    } else {
                                        let _e5920 = local_732;
                                        local_731 = _e5920;
                                    }
                                    let _e5921 = local_731;
                                    let _e5926 = local_747;
                                    local_733 = _e5926;
                                    if (abs(_e5926) <= 0.000015258789f) {
                                        local_730 = 0f;
                                    } else {
                                        let _e5929 = local_733;
                                        local_730 = _e5929;
                                    }
                                    let _e5930 = local_730;
                                    let _e5935 = local_746;
                                    local_734 = _e5935;
                                    if (abs(_e5935) <= 0.000015258789f) {
                                        local_729 = 0f;
                                    } else {
                                        let _e5938 = local_734;
                                        local_729 = _e5938;
                                    }
                                    let _e5939 = local_729;
                                    local_745 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e5921) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e5930) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e5939) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                } else {
                                    let _e5950 = local_739;
                                    local_748 = _e5950;
                                    let _e5951 = local_741;
                                    local_749 = _e5951;
                                    let _e5952 = local_743;
                                    local_726 = _e5952;
                                    if (abs(_e5952) <= 0.000015258789f) {
                                        local_725 = 0f;
                                    } else {
                                        let _e5955 = local_726;
                                        local_725 = _e5955;
                                    }
                                    let _e5956 = local_725;
                                    let _e5961 = local_749;
                                    local_727 = _e5961;
                                    if (abs(_e5961) <= 0.000015258789f) {
                                        local_724 = 0f;
                                    } else {
                                        let _e5964 = local_727;
                                        local_724 = _e5964;
                                    }
                                    let _e5965 = local_724;
                                    let _e5970 = local_748;
                                    local_728 = _e5970;
                                    if (abs(_e5970) <= 0.000015258789f) {
                                        local_723 = 0f;
                                    } else {
                                        let _e5973 = local_728;
                                        local_723 = _e5973;
                                    }
                                    let _e5974 = local_723;
                                    local_745 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e5956) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e5965) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e5974) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                }
                                let _e5985 = local_745;
                                if (_e5985 == 0u) {
                                    local_737 = true;
                                    break;
                                }
                                let _e5987 = local_791;
                                if _e5987 {
                                    let _e5988 = local_739;
                                    local_751 = _e5988;
                                    let _e5989 = local_740;
                                    local_752 = _e5989;
                                    let _e5990 = local_741;
                                    let _e5991 = local_742;
                                    let _e5992 = local_743;
                                    let _e5993 = local_744;
                                    let _e5994 = local_790;
                                    local_753 = _e5994;
                                    local_711 = ((_e5988 - (_e5990 * 2f)) + _e5992);
                                    let _e6000 = ((_e5989 - (_e5991 * 2f)) + _e5993);
                                    local_712 = _e6000;
                                    local_713 = (_e5988 - _e5990);
                                    local_714 = (_e5989 - _e5991);
                                    if (abs(_e6000) < 0.000015258789f) {
                                        let _e6005 = local_714;
                                        if (abs(_e6005) < 0.000015258789f) {
                                            local_715 = 0f;
                                        } else {
                                            let _e6008 = local_752;
                                            let _e6010 = local_714;
                                            local_715 = ((_e6008 * 0.5f) / _e6010);
                                        }
                                        let _e6012 = local_715;
                                        local_716 = _e6012;
                                    } else {
                                        let _e6013 = local_712;
                                        let _e6014 = local_752;
                                        let _e6015 = (_e6013 * _e6014);
                                        let _e6016 = local_714;
                                        let _e6018 = ((_e6016 * _e6016) - _e6015);
                                        local_718 = _e6018;
                                        if (_e6018 <= (max((_e6016 * _e6016), abs(_e6015)) * 0.000003f)) {
                                            local_710 = 0f;
                                        } else {
                                            let _e6024 = local_718;
                                            local_710 = sqrt(_e6024);
                                        }
                                        let _e6026 = local_710;
                                        local_717 = _e6026;
                                        let _e6027 = local_714;
                                        if (_e6027 >= 0f) {
                                            let _e6029 = local_714;
                                            let _e6030 = local_717;
                                            let _e6031 = (_e6029 + _e6030);
                                            local_719 = _e6031;
                                            let _e6032 = local_712;
                                            local_720 = (_e6031 / _e6032);
                                            if (abs(_e6031) < 0.000015258789f) {
                                                local_715 = 0f;
                                            } else {
                                                let _e6036 = local_752;
                                                let _e6037 = local_719;
                                                local_715 = (_e6036 / _e6037);
                                            }
                                            let _e6039 = local_720;
                                            local_716 = _e6039;
                                        } else {
                                            let _e6040 = local_714;
                                            let _e6041 = local_717;
                                            let _e6042 = (_e6040 - _e6041);
                                            local_721 = _e6042;
                                            let _e6043 = local_712;
                                            local_722 = (_e6042 / _e6043);
                                            if (abs(_e6042) < 0.000015258789f) {
                                                local_715 = 0f;
                                            } else {
                                                let _e6047 = local_752;
                                                let _e6048 = local_721;
                                                local_715 = (_e6047 / _e6048);
                                            }
                                            let _e6050 = local_715;
                                            let _e6051 = local_722;
                                            local_715 = _e6051;
                                            local_716 = _e6050;
                                        }
                                    }
                                    let _e6052 = local_713;
                                    let _e6053 = (_e6052 * 2f);
                                    let _e6054 = local_711;
                                    let _e6055 = local_715;
                                    let _e6059 = local_751;
                                    let _e6061 = local_753;
                                    let _e6063 = local_716;
                                    local_750 = vec2<f32>((((((_e6054 * _e6055) - _e6053) * _e6055) + _e6059) * _e6061), (((((_e6054 * _e6063) - _e6053) * _e6063) + _e6059) * _e6061));
                                } else {
                                    let _e6070 = local_739;
                                    local_754 = _e6070;
                                    let _e6071 = local_740;
                                    local_755 = _e6071;
                                    let _e6072 = local_741;
                                    let _e6073 = local_742;
                                    let _e6074 = local_743;
                                    let _e6075 = local_744;
                                    let _e6076 = local_790;
                                    local_756 = _e6076;
                                    let _e6079 = ((_e6070 - (_e6072 * 2f)) + _e6074);
                                    local_698 = _e6079;
                                    local_699 = ((_e6071 - (_e6073 * 2f)) + _e6075);
                                    local_700 = (_e6070 - _e6072);
                                    local_701 = (_e6071 - _e6073);
                                    if (abs(_e6079) < 0.000015258789f) {
                                        let _e6087 = local_700;
                                        if (abs(_e6087) < 0.000015258789f) {
                                            local_702 = 0f;
                                        } else {
                                            let _e6090 = local_754;
                                            let _e6092 = local_700;
                                            local_702 = ((_e6090 * 0.5f) / _e6092);
                                        }
                                        let _e6094 = local_702;
                                        local_703 = _e6094;
                                    } else {
                                        let _e6095 = local_698;
                                        let _e6096 = local_754;
                                        let _e6097 = (_e6095 * _e6096);
                                        let _e6098 = local_700;
                                        let _e6100 = ((_e6098 * _e6098) - _e6097);
                                        local_705 = _e6100;
                                        if (_e6100 <= (max((_e6098 * _e6098), abs(_e6097)) * 0.000003f)) {
                                            local_697 = 0f;
                                        } else {
                                            let _e6106 = local_705;
                                            local_697 = sqrt(_e6106);
                                        }
                                        let _e6108 = local_697;
                                        local_704 = _e6108;
                                        let _e6109 = local_700;
                                        if (_e6109 >= 0f) {
                                            let _e6111 = local_700;
                                            let _e6112 = local_704;
                                            let _e6113 = (_e6111 + _e6112);
                                            local_706 = _e6113;
                                            let _e6114 = local_698;
                                            local_707 = (_e6113 / _e6114);
                                            if (abs(_e6113) < 0.000015258789f) {
                                                local_702 = 0f;
                                            } else {
                                                let _e6118 = local_754;
                                                let _e6119 = local_706;
                                                local_702 = (_e6118 / _e6119);
                                            }
                                            let _e6121 = local_707;
                                            local_703 = _e6121;
                                        } else {
                                            let _e6122 = local_700;
                                            let _e6123 = local_704;
                                            let _e6124 = (_e6122 - _e6123);
                                            local_708 = _e6124;
                                            let _e6125 = local_698;
                                            local_709 = (_e6124 / _e6125);
                                            if (abs(_e6124) < 0.000015258789f) {
                                                local_702 = 0f;
                                            } else {
                                                let _e6129 = local_754;
                                                let _e6130 = local_708;
                                                local_702 = (_e6129 / _e6130);
                                            }
                                            let _e6132 = local_702;
                                            let _e6133 = local_709;
                                            local_702 = _e6133;
                                            local_703 = _e6132;
                                        }
                                    }
                                    let _e6134 = local_701;
                                    let _e6135 = (_e6134 * 2f);
                                    let _e6136 = local_699;
                                    let _e6137 = local_702;
                                    let _e6141 = local_755;
                                    let _e6143 = local_756;
                                    let _e6145 = local_703;
                                    local_750 = vec2<f32>((((((_e6136 * _e6137) - _e6135) * _e6137) + _e6141) * _e6143), (((((_e6136 * _e6145) - _e6135) * _e6145) + _e6141) * _e6143));
                                }
                                let _e6152 = local_745;
                                if ((_e6152 & 1u) != 0u) {
                                    let _e6155 = local_750;
                                    local_757 = _e6155.x;
                                    let _e6157 = local_791;
                                    if _e6157 {
                                        local_738 = 1f;
                                    } else {
                                        local_738 = -1f;
                                    }
                                    let _e6158 = local_787;
                                    let _e6159 = local_788;
                                    let _e6160 = local_757;
                                    let _e6161 = local_738;
                                    local_787 = (_e6158 + (_e6161 * clamp((_e6160 + 0.5f), 0f, 1f)));
                                    local_788 = max(_e6159, clamp((1f - (abs(_e6160) * 2f)), 0f, 1f));
                                }
                                let _e6171 = local_745;
                                if (_e6171 > 1u) {
                                    let _e6173 = local_750;
                                    local_758 = _e6173.y;
                                    let _e6175 = local_791;
                                    if _e6175 {
                                        local_738 = -1f;
                                    } else {
                                        local_738 = 1f;
                                    }
                                    let _e6176 = local_787;
                                    let _e6177 = local_788;
                                    let _e6178 = local_758;
                                    let _e6179 = local_738;
                                    local_787 = (_e6176 + (_e6179 * clamp((_e6178 + 0.5f), 0f, 1f)));
                                    local_788 = max(_e6177, clamp((1f - (abs(_e6178) * 2f)), 0f, 1f));
                                }
                                local_737 = true;
                                break;
                            }
                            let _e6189 = local_109;
                            if (_e6189 == 3i) {
                                let _e6191 = local_789;
                                let _e6194 = local_108;
                                let _e6199 = local_106;
                                let _e6204 = local_787;
                                local_759 = _e6204;
                                let _e6205 = local_788;
                                local_760 = _e6205;
                                local_761 = (_e6194.x - _e6191.x);
                                local_762 = (_e6194.y - _e6191.y);
                                local_763 = (_e6199.x - _e6191.x);
                                local_764 = (_e6199.y - _e6191.y);
                                let _e6206 = local_790;
                                local_765 = _e6206;
                                let _e6207 = local_791;
                                local_766 = _e6207;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e6209 = local_766;
                                        if _e6209 {
                                            let _e6210 = local_762;
                                            local_689 = _e6210;
                                        } else {
                                            let _e6211 = local_761;
                                            local_689 = _e6211;
                                        }
                                        let _e6212 = local_766;
                                        if _e6212 {
                                            let _e6213 = local_764;
                                            local_690 = _e6213;
                                        } else {
                                            let _e6214 = local_763;
                                            local_690 = _e6214;
                                        }
                                        let _e6215 = local_689;
                                        local_691 = _e6215;
                                        if (abs(_e6215) <= 0.000015258789f) {
                                            local_688 = 0f;
                                        } else {
                                            let _e6218 = local_691;
                                            local_688 = _e6218;
                                        }
                                        let _e6219 = local_688;
                                        let _e6221 = local_690;
                                        local_692 = _e6221;
                                        if (abs(_e6221) <= 0.000015258789f) {
                                            local_687 = 0f;
                                        } else {
                                            let _e6224 = local_692;
                                            local_687 = _e6224;
                                        }
                                        let _e6225 = local_687;
                                        if ((_e6219 < 0f) == (_e6225 < 0f)) {
                                            break;
                                        }
                                        let _e6228 = local_690;
                                        let _e6229 = local_689;
                                        let _e6230 = (_e6228 - _e6229);
                                        local_693 = _e6230;
                                        if (abs(_e6230) < 0.0000000001f) {
                                            break;
                                        }
                                        let _e6233 = local_689;
                                        let _e6235 = local_693;
                                        local_694 = clamp((-(_e6233) / _e6235), 0f, 1f);
                                        let _e6238 = local_766;
                                        if _e6238 {
                                            let _e6239 = local_764;
                                            let _e6240 = local_762;
                                            local_695 = (_e6239 - _e6240);
                                        } else {
                                            let _e6242 = local_761;
                                            let _e6243 = local_763;
                                            local_695 = (_e6242 - _e6243);
                                        }
                                        let _e6245 = local_695;
                                        if (abs(_e6245) <= 0.00001f) {
                                            break;
                                        }
                                        let _e6248 = local_766;
                                        if _e6248 {
                                            let _e6249 = local_761;
                                            let _e6250 = local_763;
                                            let _e6252 = local_694;
                                            local_689 = (_e6249 + ((_e6250 - _e6249) * _e6252));
                                        } else {
                                            let _e6255 = local_762;
                                            let _e6256 = local_764;
                                            let _e6258 = local_694;
                                            local_689 = (_e6255 + ((_e6256 - _e6255) * _e6258));
                                        }
                                        let _e6261 = local_689;
                                        let _e6262 = local_765;
                                        local_696 = (_e6261 * _e6262);
                                        let _e6264 = local_695;
                                        if (_e6264 > 0f) {
                                            local_689 = 1f;
                                        } else {
                                            local_689 = -1f;
                                        }
                                        let _e6266 = local_759;
                                        let _e6267 = local_760;
                                        let _e6268 = local_696;
                                        let _e6269 = local_689;
                                        local_759 = (_e6266 + (_e6269 * clamp((_e6268 + 0.5f), 0f, 1f)));
                                        local_760 = max(_e6267, clamp((1f - (abs(_e6268) * 2f)), 0f, 1f));
                                        break;
                                    }
                                }
                                let _e6279 = local_759;
                                local_787 = _e6279;
                                let _e6280 = local_760;
                                local_788 = _e6280;
                                local_737 = true;
                                break;
                            }
                            let _e6281 = local_109;
                            if (_e6281 == 1i) {
                                let _e6283 = local_787;
                                local_767 = _e6283;
                                let _e6284 = local_788;
                                local_768 = _e6284;
                                let _e6285 = local_104;
                                let _e6286 = local_105;
                                let _e6287 = local_106;
                                let _e6288 = local_107;
                                let _e6289 = local_108;
                                let _e6290 = local_109;
                                local_126 = _e6290;
                                local_125 = _e6289;
                                local_124 = _e6288;
                                local_123 = _e6287;
                                local_122 = _e6286;
                                local_121 = _e6285;
                                let _e6291 = local_789;
                                local_769 = _e6291;
                                let _e6292 = local_790;
                                local_770 = _e6292;
                                let _e6293 = local_791;
                                local_771 = _e6293;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e6295 = local_122;
                                        let _e6296 = local_123;
                                        let _e6297 = local_124;
                                        let _e6298 = local_125;
                                        let _e6299 = local_126;
                                        local_141 = _e6299;
                                        local_140 = _e6298;
                                        local_139 = _e6297;
                                        local_138 = _e6296;
                                        local_137 = _e6295;
                                        let _e6300 = local_769;
                                        local_620 = _e6300;
                                        let _e6301 = local_771;
                                        local_621 = _e6301;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e6303 = local_621;
                                                if _e6303 {
                                                    let _e6304 = local_620;
                                                    local_613 = _e6304.y;
                                                } else {
                                                    let _e6306 = local_620;
                                                    local_613 = _e6306.x;
                                                }
                                                let _e6308 = local_141;
                                                if (_e6308 == 2i) {
                                                    let _e6310 = local_621;
                                                    if _e6310 {
                                                        let _e6311 = local_140;
                                                        local_614 = _e6311.y;
                                                    } else {
                                                        let _e6313 = local_140;
                                                        local_614 = _e6313.x;
                                                    }
                                                    let _e6315 = local_621;
                                                    if _e6315 {
                                                        let _e6316 = local_139;
                                                        local_615 = _e6316.y;
                                                    } else {
                                                        let _e6318 = local_139;
                                                        local_615 = _e6318.x;
                                                    }
                                                    let _e6320 = local_621;
                                                    if _e6320 {
                                                        let _e6321 = local_138;
                                                        local_616 = _e6321.y;
                                                    } else {
                                                        let _e6323 = local_138;
                                                        local_616 = _e6323.x;
                                                    }
                                                    let _e6325 = local_621;
                                                    if _e6325 {
                                                        let _e6326 = local_137;
                                                        local_617 = _e6326.y;
                                                    } else {
                                                        let _e6328 = local_137;
                                                        local_617 = _e6328.x;
                                                    }
                                                    let _e6330 = local_614;
                                                    let _e6331 = local_615;
                                                    let _e6332 = local_616;
                                                    let _e6333 = local_617;
                                                    let _e6334 = local_613;
                                                    local_618 = _e6334;
                                                    local_610 = max(max(_e6330, _e6331), max(_e6332, _e6333));
                                                    if ((min(min(_e6330, _e6331), min(_e6332, _e6333)) - _e6334) <= 0.000015258789f) {
                                                        let _e6343 = local_610;
                                                        let _e6344 = local_618;
                                                        local_611 = ((_e6343 - _e6344) >= -0.000015258789f);
                                                    } else {
                                                        local_611 = false;
                                                    }
                                                    let _e6347 = local_611;
                                                    local_612 = _e6347;
                                                    break;
                                                }
                                                let _e6348 = local_621;
                                                if _e6348 {
                                                    let _e6349 = local_140;
                                                    local_614 = _e6349.y;
                                                } else {
                                                    let _e6351 = local_140;
                                                    local_614 = _e6351.x;
                                                }
                                                let _e6353 = local_621;
                                                if _e6353 {
                                                    let _e6354 = local_139;
                                                    local_615 = _e6354.y;
                                                } else {
                                                    let _e6356 = local_139;
                                                    local_615 = _e6356.x;
                                                }
                                                let _e6358 = local_621;
                                                if _e6358 {
                                                    let _e6359 = local_138;
                                                    local_616 = _e6359.y;
                                                } else {
                                                    let _e6361 = local_138;
                                                    local_616 = _e6361.x;
                                                }
                                                let _e6363 = local_614;
                                                let _e6364 = local_615;
                                                let _e6365 = local_616;
                                                let _e6366 = local_613;
                                                local_619 = _e6366;
                                                local_608 = max(max(_e6363, _e6364), _e6365);
                                                if ((min(min(_e6363, _e6364), _e6365) - _e6366) <= 0.000015258789f) {
                                                    let _e6373 = local_608;
                                                    let _e6374 = local_619;
                                                    local_609 = ((_e6373 - _e6374) >= -0.000015258789f);
                                                } else {
                                                    local_609 = false;
                                                }
                                                let _e6377 = local_609;
                                                local_612 = _e6377;
                                                break;
                                            }
                                        }
                                        let _e6378 = local_612;
                                        if !(_e6378) {
                                            break;
                                        }
                                        let _e6380 = local_771;
                                        if _e6380 {
                                            let _e6381 = local_769;
                                            local_622 = _e6381.y;
                                        } else {
                                            let _e6383 = local_769;
                                            local_622 = _e6383.x;
                                        }
                                        let _e6385 = local_771;
                                        if _e6385 {
                                            let _e6386 = local_769;
                                            local_623 = _e6386.x;
                                        } else {
                                            let _e6388 = local_769;
                                            local_623 = _e6388.y;
                                        }
                                        let _e6390 = local_771;
                                        if _e6390 {
                                            let _e6391 = local_125;
                                            local_624 = _e6391.y;
                                        } else {
                                            let _e6393 = local_125;
                                            local_624 = _e6393.x;
                                        }
                                        let _e6395 = local_771;
                                        if _e6395 {
                                            let _e6396 = local_124;
                                            local_625 = _e6396.y;
                                        } else {
                                            let _e6398 = local_124;
                                            local_625 = _e6398.x;
                                        }
                                        let _e6400 = local_771;
                                        if _e6400 {
                                            let _e6401 = local_123;
                                            local_626 = _e6401.y;
                                        } else {
                                            let _e6403 = local_123;
                                            local_626 = _e6403.x;
                                        }
                                        let _e6405 = local_771;
                                        if _e6405 {
                                            let _e6406 = local_125;
                                            local_627 = _e6406.x;
                                        } else {
                                            let _e6408 = local_125;
                                            local_627 = _e6408.y;
                                        }
                                        let _e6410 = local_771;
                                        if _e6410 {
                                            let _e6411 = local_124;
                                            local_628 = _e6411.x;
                                        } else {
                                            let _e6413 = local_124;
                                            local_628 = _e6413.y;
                                        }
                                        let _e6415 = local_771;
                                        if _e6415 {
                                            let _e6416 = local_123;
                                            local_629 = _e6416.x;
                                        } else {
                                            let _e6418 = local_123;
                                            local_629 = _e6418.y;
                                        }
                                        let _e6420 = local_121;
                                        local_630 = _e6420.x;
                                        let _e6422 = local_624;
                                        let _e6423 = local_622;
                                        let _e6425 = (_e6420.x * (_e6422 - _e6423));
                                        local_631 = _e6425;
                                        local_632 = _e6420.y;
                                        let _e6427 = local_625;
                                        let _e6429 = (_e6420.y * (_e6427 - _e6423));
                                        local_633 = _e6429;
                                        local_634 = _e6420.z;
                                        let _e6431 = local_626;
                                        let _e6433 = (_e6420.z * (_e6431 - _e6423));
                                        local_635 = _e6433;
                                        local_637 = _e6425;
                                        local_638 = _e6429;
                                        local_605 = _e6433;
                                        if (abs(_e6433) <= 0.000015258789f) {
                                            local_604 = 0f;
                                        } else {
                                            let _e6436 = local_605;
                                            local_604 = _e6436;
                                        }
                                        let _e6437 = local_604;
                                        let _e6442 = local_638;
                                        local_606 = _e6442;
                                        if (abs(_e6442) <= 0.000015258789f) {
                                            local_603 = 0f;
                                        } else {
                                            let _e6445 = local_606;
                                            local_603 = _e6445;
                                        }
                                        let _e6446 = local_603;
                                        let _e6451 = local_637;
                                        local_607 = _e6451;
                                        if (abs(_e6451) <= 0.000015258789f) {
                                            local_602 = 0f;
                                        } else {
                                            let _e6454 = local_607;
                                            local_602 = _e6454;
                                        }
                                        let _e6455 = local_602;
                                        let _e6465 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e6437) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e6446) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e6455) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                        local_636 = _e6465;
                                        if (_e6465 == 0u) {
                                            break;
                                        }
                                        let _e6467 = local_636;
                                        if (_e6467 == 257u) {
                                            local_639 = 2i;
                                        } else {
                                            local_639 = 1i;
                                        }
                                        let _e6469 = local_631;
                                        let _e6470 = local_633;
                                        let _e6473 = local_635;
                                        let _e6474 = ((_e6469 - (2f * _e6470)) + _e6473);
                                        local_640 = _e6474;
                                        local_641 = (2f * (_e6470 - _e6469));
                                        if (abs(_e6474) < 0.000015258789f) {
                                            let _e6479 = local_641;
                                            if (abs(_e6479) >= 0.000015258789f) {
                                                let _e6482 = local_631;
                                                let _e6484 = local_641;
                                                local_642 = 1i;
                                                local_643 = (-(_e6482) / _e6484);
                                            } else {
                                                local_642 = 0i;
                                                local_643 = 0f;
                                            }
                                            let _e6486 = local_643;
                                            local_643 = 0f;
                                            local_644 = _e6486;
                                        } else {
                                            let _e6487 = local_641;
                                            let _e6489 = local_640;
                                            let _e6491 = local_631;
                                            let _e6495 = sqrt(max(((_e6487 * _e6487) - ((4f * _e6489) * _e6491)), 0f));
                                            let _e6496 = (0.5f / _e6489);
                                            let _e6497 = -(_e6487);
                                            local_642 = 2i;
                                            local_643 = ((_e6497 + _e6495) * _e6496);
                                            local_644 = ((_e6497 - _e6495) * _e6496);
                                        }
                                        let _e6502 = local_642;
                                        if (_e6502 == 0i) {
                                            break;
                                        }
                                        let _e6504 = local_639;
                                        if (_e6504 == 1i) {
                                            let _e6506 = local_642;
                                            if (_e6506 == 2i) {
                                                let _e6508 = local_643;
                                                let _e6513 = local_644;
                                                local_645 = (max(max(0f, -(_e6508)), (_e6508 - 1f)) < max(max(0f, -(_e6513)), (_e6513 - 1f)));
                                            } else {
                                                local_645 = false;
                                            }
                                            let _e6519 = local_645;
                                            if _e6519 {
                                                let _e6520 = local_643;
                                                local_646 = _e6520;
                                            } else {
                                                let _e6521 = local_644;
                                                local_646 = _e6521;
                                            }
                                            let _e6522 = local_646;
                                            local_646 = clamp(_e6522, 0f, 1f);
                                            local_647 = 1i;
                                            local_648 = 0f;
                                        } else {
                                            let _e6524 = local_643;
                                            let _e6526 = local_644;
                                            local_646 = clamp(_e6526, 0f, 1f);
                                            local_647 = 2i;
                                            local_648 = clamp(_e6524, 0f, 1f);
                                        }
                                        let _e6528 = local_624;
                                        let _e6529 = local_630;
                                        let _e6530 = (_e6528 * _e6529);
                                        local_649 = _e6530;
                                        let _e6531 = local_625;
                                        let _e6533 = local_632;
                                        let _e6536 = local_626;
                                        let _e6537 = local_634;
                                        local_650 = ((_e6530 - ((2f * _e6531) * _e6533)) + (_e6536 * _e6537));
                                        local_651 = (2f * ((_e6531 * _e6533) - _e6530));
                                        let _e6543 = local_627;
                                        let _e6544 = (_e6543 * _e6529);
                                        local_652 = _e6544;
                                        let _e6545 = local_628;
                                        let _e6549 = local_629;
                                        local_653 = ((_e6544 - ((2f * _e6545) * _e6533)) + (_e6549 * _e6537));
                                        local_654 = (2f * ((_e6545 * _e6533) - _e6544));
                                        local_655 = ((_e6529 - (2f * _e6533)) + _e6537);
                                        local_656 = (2f * (_e6533 - _e6529));
                                        let _e6560 = local_767;
                                        local_657 = _e6560;
                                        let _e6561 = local_768;
                                        local_658 = _e6561;
                                        let _e6562 = local_646;
                                        local_659 = _e6562;
                                        let _e6563 = local_623;
                                        local_660 = _e6563;
                                        let _e6564 = local_770;
                                        local_661 = _e6564;
                                        let _e6565 = local_771;
                                        local_662 = _e6565;
                                        let _e6566 = local_650;
                                        local_663 = _e6566;
                                        let _e6567 = local_651;
                                        local_664 = _e6567;
                                        let _e6568 = local_649;
                                        local_665 = _e6568;
                                        let _e6569 = local_653;
                                        local_666 = _e6569;
                                        let _e6570 = local_654;
                                        local_667 = _e6570;
                                        let _e6571 = local_652;
                                        local_668 = _e6571;
                                        let _e6572 = local_655;
                                        local_669 = _e6572;
                                        let _e6573 = local_656;
                                        local_670 = _e6573;
                                        let _e6574 = local_630;
                                        local_671 = _e6574;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e6576 = local_669;
                                                let _e6577 = local_659;
                                                let _e6579 = local_670;
                                                let _e6582 = local_671;
                                                let _e6584 = max(((((_e6576 * _e6577) + _e6579) * _e6577) + _e6582), 0.000015258789f);
                                                let _e6585 = local_666;
                                                let _e6587 = local_667;
                                                let _e6590 = local_668;
                                                local_598 = (((((_e6585 * _e6577) + _e6587) * _e6577) + _e6590) / _e6584);
                                                let _e6593 = local_663;
                                                let _e6596 = local_664;
                                                let _e6602 = local_665;
                                                local_599 = ((((((2f * _e6593) * _e6577) + _e6596) * _e6584) - (((((_e6593 * _e6577) + _e6596) * _e6577) + _e6602) * (((2f * _e6576) * _e6577) + _e6579))) / (_e6584 * _e6584));
                                                let _e6611 = local_662;
                                                if !(_e6611) {
                                                    let _e6613 = local_599;
                                                    local_600 = -(_e6613);
                                                } else {
                                                    let _e6615 = local_599;
                                                    local_600 = _e6615;
                                                }
                                                let _e6616 = local_600;
                                                if (abs(_e6616) <= 0.00001f) {
                                                    break;
                                                }
                                                let _e6619 = local_598;
                                                let _e6620 = local_660;
                                                let _e6622 = local_661;
                                                local_601 = ((_e6619 - _e6620) * _e6622);
                                                let _e6624 = local_600;
                                                if (_e6624 > 0f) {
                                                    local_600 = 1f;
                                                } else {
                                                    local_600 = -1f;
                                                }
                                                let _e6626 = local_657;
                                                let _e6627 = local_658;
                                                let _e6628 = local_601;
                                                let _e6629 = local_600;
                                                local_657 = (_e6626 + (_e6629 * clamp((_e6628 + 0.5f), 0f, 1f)));
                                                local_658 = max(_e6627, clamp((1f - (abs(_e6628) * 2f)), 0f, 1f));
                                                break;
                                            }
                                        }
                                        let _e6639 = local_657;
                                        local_767 = _e6639;
                                        let _e6640 = local_658;
                                        local_768 = _e6640;
                                        let _e6641 = local_647;
                                        if (_e6641 == 2i) {
                                            let _e6643 = local_767;
                                            local_672 = _e6643;
                                            let _e6644 = local_768;
                                            local_673 = _e6644;
                                            let _e6645 = local_648;
                                            local_674 = _e6645;
                                            let _e6646 = local_623;
                                            local_675 = _e6646;
                                            let _e6647 = local_770;
                                            local_676 = _e6647;
                                            let _e6648 = local_771;
                                            local_677 = _e6648;
                                            let _e6649 = local_650;
                                            local_678 = _e6649;
                                            let _e6650 = local_651;
                                            local_679 = _e6650;
                                            let _e6651 = local_649;
                                            local_680 = _e6651;
                                            let _e6652 = local_653;
                                            local_681 = _e6652;
                                            let _e6653 = local_654;
                                            local_682 = _e6653;
                                            let _e6654 = local_652;
                                            local_683 = _e6654;
                                            let _e6655 = local_655;
                                            local_684 = _e6655;
                                            let _e6656 = local_656;
                                            local_685 = _e6656;
                                            let _e6657 = local_630;
                                            local_686 = _e6657;
                                            switch bitcast<i32>(0u) {
                                                default: {
                                                    let _e6659 = local_684;
                                                    let _e6660 = local_674;
                                                    let _e6662 = local_685;
                                                    let _e6665 = local_686;
                                                    let _e6667 = max(((((_e6659 * _e6660) + _e6662) * _e6660) + _e6665), 0.000015258789f);
                                                    let _e6668 = local_681;
                                                    let _e6670 = local_682;
                                                    let _e6673 = local_683;
                                                    local_594 = (((((_e6668 * _e6660) + _e6670) * _e6660) + _e6673) / _e6667);
                                                    let _e6676 = local_678;
                                                    let _e6679 = local_679;
                                                    let _e6685 = local_680;
                                                    local_595 = ((((((2f * _e6676) * _e6660) + _e6679) * _e6667) - (((((_e6676 * _e6660) + _e6679) * _e6660) + _e6685) * (((2f * _e6659) * _e6660) + _e6662))) / (_e6667 * _e6667));
                                                    let _e6694 = local_677;
                                                    if !(_e6694) {
                                                        let _e6696 = local_595;
                                                        local_596 = -(_e6696);
                                                    } else {
                                                        let _e6698 = local_595;
                                                        local_596 = _e6698;
                                                    }
                                                    let _e6699 = local_596;
                                                    if (abs(_e6699) <= 0.00001f) {
                                                        break;
                                                    }
                                                    let _e6702 = local_594;
                                                    let _e6703 = local_675;
                                                    let _e6705 = local_676;
                                                    local_597 = ((_e6702 - _e6703) * _e6705);
                                                    let _e6707 = local_596;
                                                    if (_e6707 > 0f) {
                                                        local_596 = 1f;
                                                    } else {
                                                        local_596 = -1f;
                                                    }
                                                    let _e6709 = local_672;
                                                    let _e6710 = local_673;
                                                    let _e6711 = local_597;
                                                    let _e6712 = local_596;
                                                    local_672 = (_e6709 + (_e6712 * clamp((_e6711 + 0.5f), 0f, 1f)));
                                                    local_673 = max(_e6710, clamp((1f - (abs(_e6711) * 2f)), 0f, 1f));
                                                    break;
                                                }
                                            }
                                            let _e6722 = local_672;
                                            local_767 = _e6722;
                                            let _e6723 = local_673;
                                            local_768 = _e6723;
                                        }
                                        break;
                                    }
                                }
                                let _e6724 = local_767;
                                local_787 = _e6724;
                                let _e6725 = local_768;
                                local_788 = _e6725;
                                local_737 = true;
                                break;
                            }
                            let _e6726 = local_787;
                            local_772 = _e6726;
                            let _e6727 = local_788;
                            local_773 = _e6727;
                            let _e6728 = local_105;
                            let _e6729 = local_106;
                            let _e6730 = local_107;
                            let _e6731 = local_108;
                            let _e6732 = local_109;
                            local_120 = _e6732;
                            local_119 = _e6731;
                            local_118 = _e6730;
                            local_117 = _e6729;
                            local_116 = _e6728;
                            let _e6733 = local_789;
                            local_774 = _e6733;
                            let _e6734 = local_790;
                            local_775 = _e6734;
                            let _e6735 = local_791;
                            local_776 = _e6735;
                            switch bitcast<i32>(0u) {
                                default: {
                                    let _e6737 = local_116;
                                    let _e6738 = local_117;
                                    let _e6739 = local_118;
                                    let _e6740 = local_119;
                                    let _e6741 = local_120;
                                    local_146 = _e6741;
                                    local_145 = _e6740;
                                    local_144 = _e6739;
                                    local_143 = _e6738;
                                    local_142 = _e6737;
                                    let _e6742 = local_774;
                                    local_562 = _e6742;
                                    let _e6743 = local_776;
                                    local_563 = _e6743;
                                    switch bitcast<i32>(0u) {
                                        default: {
                                            let _e6745 = local_563;
                                            if _e6745 {
                                                let _e6746 = local_562;
                                                local_555 = _e6746.y;
                                            } else {
                                                let _e6748 = local_562;
                                                local_555 = _e6748.x;
                                            }
                                            let _e6750 = local_146;
                                            if (_e6750 == 2i) {
                                                let _e6752 = local_563;
                                                if _e6752 {
                                                    let _e6753 = local_145;
                                                    local_556 = _e6753.y;
                                                } else {
                                                    let _e6755 = local_145;
                                                    local_556 = _e6755.x;
                                                }
                                                let _e6757 = local_563;
                                                if _e6757 {
                                                    let _e6758 = local_144;
                                                    local_557 = _e6758.y;
                                                } else {
                                                    let _e6760 = local_144;
                                                    local_557 = _e6760.x;
                                                }
                                                let _e6762 = local_563;
                                                if _e6762 {
                                                    let _e6763 = local_143;
                                                    local_558 = _e6763.y;
                                                } else {
                                                    let _e6765 = local_143;
                                                    local_558 = _e6765.x;
                                                }
                                                let _e6767 = local_563;
                                                if _e6767 {
                                                    let _e6768 = local_142;
                                                    local_559 = _e6768.y;
                                                } else {
                                                    let _e6770 = local_142;
                                                    local_559 = _e6770.x;
                                                }
                                                let _e6772 = local_556;
                                                let _e6773 = local_557;
                                                let _e6774 = local_558;
                                                let _e6775 = local_559;
                                                let _e6776 = local_555;
                                                local_560 = _e6776;
                                                local_552 = max(max(_e6772, _e6773), max(_e6774, _e6775));
                                                if ((min(min(_e6772, _e6773), min(_e6774, _e6775)) - _e6776) <= 0.000015258789f) {
                                                    let _e6785 = local_552;
                                                    let _e6786 = local_560;
                                                    local_553 = ((_e6785 - _e6786) >= -0.000015258789f);
                                                } else {
                                                    local_553 = false;
                                                }
                                                let _e6789 = local_553;
                                                local_554 = _e6789;
                                                break;
                                            }
                                            let _e6790 = local_563;
                                            if _e6790 {
                                                let _e6791 = local_145;
                                                local_556 = _e6791.y;
                                            } else {
                                                let _e6793 = local_145;
                                                local_556 = _e6793.x;
                                            }
                                            let _e6795 = local_563;
                                            if _e6795 {
                                                let _e6796 = local_144;
                                                local_557 = _e6796.y;
                                            } else {
                                                let _e6798 = local_144;
                                                local_557 = _e6798.x;
                                            }
                                            let _e6800 = local_563;
                                            if _e6800 {
                                                let _e6801 = local_143;
                                                local_558 = _e6801.y;
                                            } else {
                                                let _e6803 = local_143;
                                                local_558 = _e6803.x;
                                            }
                                            let _e6805 = local_556;
                                            let _e6806 = local_557;
                                            let _e6807 = local_558;
                                            let _e6808 = local_555;
                                            local_561 = _e6808;
                                            local_550 = max(max(_e6805, _e6806), _e6807);
                                            if ((min(min(_e6805, _e6806), _e6807) - _e6808) <= 0.000015258789f) {
                                                let _e6815 = local_550;
                                                let _e6816 = local_561;
                                                local_551 = ((_e6815 - _e6816) >= -0.000015258789f);
                                            } else {
                                                local_551 = false;
                                            }
                                            let _e6819 = local_551;
                                            local_554 = _e6819;
                                            break;
                                        }
                                    }
                                    let _e6820 = local_554;
                                    if !(_e6820) {
                                        break;
                                    }
                                    let _e6822 = local_776;
                                    if _e6822 {
                                        let _e6823 = local_774;
                                        local_564 = _e6823.y;
                                    } else {
                                        let _e6825 = local_774;
                                        local_564 = _e6825.x;
                                    }
                                    let _e6827 = local_776;
                                    if _e6827 {
                                        let _e6828 = local_774;
                                        local_565 = _e6828.x;
                                    } else {
                                        let _e6830 = local_774;
                                        local_565 = _e6830.y;
                                    }
                                    let _e6832 = local_776;
                                    if _e6832 {
                                        let _e6833 = local_119;
                                        local_566 = _e6833.y;
                                    } else {
                                        let _e6835 = local_119;
                                        local_566 = _e6835.x;
                                    }
                                    let _e6837 = local_776;
                                    if _e6837 {
                                        let _e6838 = local_118;
                                        local_567 = _e6838.y;
                                    } else {
                                        let _e6840 = local_118;
                                        local_567 = _e6840.x;
                                    }
                                    let _e6842 = local_776;
                                    if _e6842 {
                                        let _e6843 = local_117;
                                        local_568 = _e6843.y;
                                    } else {
                                        let _e6845 = local_117;
                                        local_568 = _e6845.x;
                                    }
                                    let _e6847 = local_776;
                                    if _e6847 {
                                        let _e6848 = local_116;
                                        local_569 = _e6848.y;
                                    } else {
                                        let _e6850 = local_116;
                                        local_569 = _e6850.x;
                                    }
                                    let _e6852 = local_776;
                                    if _e6852 {
                                        let _e6853 = local_119;
                                        local_570 = _e6853.x;
                                    } else {
                                        let _e6855 = local_119;
                                        local_570 = _e6855.y;
                                    }
                                    let _e6857 = local_776;
                                    if _e6857 {
                                        let _e6858 = local_118;
                                        local_571 = _e6858.x;
                                    } else {
                                        let _e6860 = local_118;
                                        local_571 = _e6860.y;
                                    }
                                    let _e6862 = local_776;
                                    if _e6862 {
                                        let _e6863 = local_117;
                                        local_572 = _e6863.x;
                                    } else {
                                        let _e6865 = local_117;
                                        local_572 = _e6865.y;
                                    }
                                    let _e6867 = local_776;
                                    if _e6867 {
                                        let _e6868 = local_116;
                                        local_573 = _e6868.x;
                                    } else {
                                        let _e6870 = local_116;
                                        local_573 = _e6870.y;
                                    }
                                    let _e6872 = local_567;
                                    let _e6873 = (3f * _e6872);
                                    let _e6874 = local_568;
                                    let _e6875 = (3f * _e6874);
                                    let _e6876 = local_566;
                                    let _e6879 = local_569;
                                    local_574 = (((_e6873 - _e6876) - _e6875) + _e6879);
                                    local_575 = (((3f * _e6876) - (6f * _e6872)) + _e6875);
                                    local_576 = ((-3f * _e6876) + _e6873);
                                    let _e6887 = local_564;
                                    let _e6888 = (_e6876 - _e6887);
                                    local_577 = _e6888;
                                    local_578 = (_e6879 - _e6887);
                                    local_579 = _e6888;
                                    if (abs(_e6888) <= 0.000015258789f) {
                                        local_549 = 0f;
                                    } else {
                                        let _e6892 = local_579;
                                        local_549 = _e6892;
                                    }
                                    let _e6893 = local_549;
                                    let _e6895 = local_578;
                                    local_580 = _e6895;
                                    if (abs(_e6895) <= 0.000015258789f) {
                                        local_548 = 0f;
                                    } else {
                                        let _e6898 = local_580;
                                        local_548 = _e6898;
                                    }
                                    let _e6899 = local_548;
                                    if ((_e6893 < 0f) == (_e6899 < 0f)) {
                                        break;
                                    }
                                    local_581 = 0f;
                                    let _e6902 = local_577;
                                    if (abs(_e6902) <= 0.000015258789f) {
                                        local_581 = 0f;
                                    } else {
                                        let _e6905 = local_578;
                                        if (abs(_e6905) <= 0.000015258789f) {
                                            local_581 = 1f;
                                        } else {
                                            let _e6908 = local_574;
                                            local_582 = _e6908;
                                            let _e6909 = local_575;
                                            local_583 = _e6909;
                                            let _e6910 = local_576;
                                            local_584 = _e6910;
                                            let _e6911 = local_577;
                                            local_585 = _e6911;
                                            let _e6912 = local_578;
                                            local_586 = _e6912;
                                            switch bitcast<i32>(0u) {
                                                default: {
                                                    let _e6914 = local_585;
                                                    if (_e6914 < -0.000015258789f) {
                                                        let _e6916 = local_586;
                                                        local_535 = (_e6916 < -0.000015258789f);
                                                    } else {
                                                        local_535 = false;
                                                    }
                                                    let _e6918 = local_535;
                                                    if _e6918 {
                                                        local_535 = true;
                                                    } else {
                                                        let _e6919 = local_585;
                                                        if (_e6919 > 0.000015258789f) {
                                                            let _e6921 = local_586;
                                                            local_535 = (_e6921 > 0.000015258789f);
                                                        } else {
                                                            local_535 = false;
                                                        }
                                                    }
                                                    let _e6923 = local_535;
                                                    if _e6923 {
                                                        local_534 = false;
                                                        break;
                                                    }
                                                    let _e6924 = local_586;
                                                    let _e6925 = local_585;
                                                    local_536 = (_e6924 >= _e6925);
                                                    local_537 = 0.5f;
                                                    local_538 = 0f;
                                                    local_539 = 1f;
                                                    local_540 = 0i;
                                                    loop {
                                                        let _e6927 = local_540;
                                                        if (_e6927 < 16i) {
                                                        } else {
                                                            break;
                                                        }
                                                        let _e6929 = local_582;
                                                        let _e6930 = local_537;
                                                        let _e6932 = local_583;
                                                        let _e6935 = local_584;
                                                        let _e6938 = local_585;
                                                        local_541 = ((((((_e6929 * _e6930) + _e6932) * _e6930) + _e6935) * _e6930) + _e6938);
                                                        let _e6940 = local_536;
                                                        if _e6940 {
                                                            let _e6941 = local_541;
                                                            local_535 = (_e6941 < 0f);
                                                        } else {
                                                            local_535 = false;
                                                        }
                                                        let _e6943 = local_535;
                                                        if _e6943 {
                                                            local_542 = true;
                                                        } else {
                                                            let _e6944 = local_536;
                                                            if !(_e6944) {
                                                                let _e6946 = local_541;
                                                                local_542 = (_e6946 > 0f);
                                                            } else {
                                                                local_542 = false;
                                                            }
                                                        }
                                                        let _e6948 = local_542;
                                                        if _e6948 {
                                                            let _e6949 = local_537;
                                                            local_538 = _e6949;
                                                        } else {
                                                            let _e6950 = local_537;
                                                            local_539 = _e6950;
                                                        }
                                                        let _e6951 = local_582;
                                                        let _e6953 = local_537;
                                                        let _e6955 = local_583;
                                                        let _e6959 = local_584;
                                                        let _e6960 = (((((3f * _e6951) * _e6953) + (2f * _e6955)) * _e6953) + _e6959);
                                                        local_543 = _e6960;
                                                        let _e6961 = local_538;
                                                        let _e6962 = local_539;
                                                        local_544 = ((_e6961 + _e6962) * 0.5f);
                                                        if (abs(_e6960) >= 0.000001f) {
                                                            let _e6967 = local_537;
                                                            let _e6968 = local_541;
                                                            let _e6969 = local_543;
                                                            let _e6971 = (_e6967 - (_e6968 / _e6969));
                                                            local_545 = _e6971;
                                                            let _e6972 = local_538;
                                                            if (_e6971 > _e6972) {
                                                                let _e6974 = local_545;
                                                                let _e6975 = local_539;
                                                                local_546 = (_e6974 < _e6975);
                                                            } else {
                                                                local_546 = false;
                                                            }
                                                            let _e6977 = local_546;
                                                            if _e6977 {
                                                                let _e6978 = local_545;
                                                                local_547 = _e6978;
                                                            } else {
                                                                let _e6979 = local_544;
                                                                local_547 = _e6979;
                                                            }
                                                        } else {
                                                            let _e6980 = local_544;
                                                            local_547 = _e6980;
                                                        }
                                                        let _e6981 = local_540;
                                                        let _e6983 = local_547;
                                                        local_537 = _e6983;
                                                        local_540 = (_e6981 + 1i);
                                                        continue;
                                                    }
                                                    let _e6984 = local_537;
                                                    local_587 = _e6984;
                                                    local_534 = true;
                                                    break;
                                                }
                                            }
                                            let _e6985 = local_534;
                                            let _e6986 = local_587;
                                            local_581 = _e6986;
                                            if !(_e6985) {
                                                break;
                                            }
                                        }
                                    }
                                    let _e6988 = local_571;
                                    let _e6989 = (3f * _e6988);
                                    let _e6990 = local_572;
                                    let _e6991 = (3f * _e6990);
                                    let _e6992 = local_570;
                                    let _e6995 = local_573;
                                    local_588 = (((_e6989 - _e6992) - _e6991) + _e6995);
                                    local_589 = (((3f * _e6992) - (6f * _e6988)) + _e6991);
                                    local_590 = ((-3f * _e6992) + _e6989);
                                    let _e7003 = local_581;
                                    if (_e7003 == 1f) {
                                        let _e7005 = local_573;
                                        local_591 = _e7005;
                                    } else {
                                        let _e7006 = local_588;
                                        let _e7007 = local_581;
                                        let _e7009 = local_589;
                                        let _e7012 = local_590;
                                        let _e7015 = local_570;
                                        local_591 = ((((((_e7006 * _e7007) + _e7009) * _e7007) + _e7012) * _e7007) + _e7015);
                                    }
                                    let _e7017 = local_776;
                                    if _e7017 {
                                        let _e7018 = local_569;
                                        let _e7019 = local_566;
                                        local_592 = (_e7018 - _e7019);
                                    } else {
                                        let _e7021 = local_566;
                                        let _e7022 = local_569;
                                        local_592 = (_e7021 - _e7022);
                                    }
                                    let _e7024 = local_591;
                                    let _e7025 = local_565;
                                    let _e7027 = local_775;
                                    local_593 = ((_e7024 - _e7025) * _e7027);
                                    let _e7029 = local_592;
                                    if (_e7029 > 0f) {
                                        local_564 = 1f;
                                    } else {
                                        local_564 = -1f;
                                    }
                                    let _e7031 = local_772;
                                    let _e7032 = local_773;
                                    let _e7033 = local_593;
                                    let _e7034 = local_564;
                                    local_772 = (_e7031 + (_e7034 * clamp((_e7033 + 0.5f), 0f, 1f)));
                                    local_773 = max(_e7032, clamp((1f - (abs(_e7033) * 2f)), 0f, 1f));
                                    break;
                                }
                            }
                            let _e7044 = local_772;
                            local_787 = _e7044;
                            let _e7045 = local_773;
                            local_788 = _e7045;
                            local_737 = true;
                            break;
                        }
                    }
                    let _e7046 = local_737;
                    let _e7047 = local_787;
                    local_777 = _e7047;
                    let _e7048 = local_788;
                    local_778 = _e7048;
                    if !(_e7046) {
                        break;
                    }
                    let _e7050 = local_783;
                    local_783 = (_e7050 + 1i);
                    continue;
                }
                let _e7052 = local_780;
                local_780 = (_e7052 + 1i);
                continue;
            }
            let _e7054 = local_777;
            let _e7055 = local_778;
            local_793 = vec2<f32>(_e7054, _e7055);
            let _e7057 = local_792;
            let _e7059 = local_1489;
            local_802 = _e7059;
            let _e7060 = local_1490;
            local_803 = _e7060.y;
            let _e7062 = local_1491;
            local_804 = _e7062;
            local_805 = (_e7057 + 1i);
            let _e7063 = local_103;
            local_806 = _e7063;
            let _e7064 = local_102;
            local_807 = _e7064;
            let _e7065 = local_1492;
            local_808 = _e7065;
            local_809 = false;
            local_519 = 0f;
            local_520 = 0f;
            local_521 = (_e7063 != _e7064);
            local_522 = _e7063;
            loop {
                let _e7067 = local_522;
                let _e7068 = local_807;
                if (_e7067 <= _e7068) {
                } else {
                    break;
                }
                let _e7070 = local_805;
                let _e7071 = local_522;
                let _e7074 = local_804;
                let _e7077 = (_e7074.x + bitcast<i32>(bitcast<u32>((_e7070 + _e7071))));
                let _e7079 = vec2<i32>(_e7077, _e7074.y);
                let _e7086 = vec2<i32>(_e7079.x, (_e7079.y + (_e7077 >> bitcast<u32>(12i))));
                let _e7091 = vec2<i32>((_e7086.x & 4095i), _e7086.y);
                let _e7092 = local_808;
                let _e7095 = vec4<i32>(_e7091.x, _e7091.y, _e7092, 0i);
                let _e7096 = _e7095.xyz;
                let _e7103 = textureLoad(u_band_tex_0_image, vec2<i32>(_e7096.x, _e7096.y), i32(_e7096.z), _e7095.w);
                let _e7104 = _e7103.xy;
                let _e7108 = (_e7074.x + bitcast<i32>(_e7104.y));
                let _e7110 = vec2<i32>(_e7108, _e7074.y);
                let _e7117 = vec2<i32>(_e7110.x, (_e7110.y + (_e7108 >> bitcast<u32>(12i))));
                local_523 = vec2<i32>((_e7117.x & 4095i), _e7117.y);
                local_524 = bitcast<i32>(_e7104.x);
                local_525 = 0i;
                loop {
                    let _e7125 = local_525;
                    let _e7126 = local_524;
                    if (_e7125 < _e7126) {
                    } else {
                        break;
                    }
                    let _e7128 = local_525;
                    let _e7130 = local_523;
                    let _e7133 = (_e7130.x + bitcast<i32>(bitcast<u32>(_e7128)));
                    let _e7135 = vec2<i32>(_e7133, _e7130.y);
                    let _e7142 = vec2<i32>(_e7135.x, (_e7135.y + (_e7133 >> bitcast<u32>(12i))));
                    let _e7147 = vec2<i32>((_e7142.x & 4095i), _e7142.y);
                    let _e7148 = local_808;
                    let _e7151 = vec4<i32>(_e7147.x, _e7147.y, _e7148, 0i);
                    let _e7152 = _e7151.xyz;
                    let _e7159 = textureLoad(u_band_tex_0_image, vec2<i32>(_e7152.x, _e7152.y), i32(_e7152.z), _e7151.w);
                    local_526 = _e7159.xy;
                    let _e7161 = local_521;
                    if _e7161 {
                        let _e7162 = local_522;
                        let _e7163 = local_526;
                        let _e7168 = local_806;
                        if (_e7162 != max(bitcast<i32>((_e7163.x >> bitcast<u32>(12u))), _e7168)) {
                            let _e7171 = local_525;
                            local_525 = (_e7171 + 1i);
                            continue;
                        }
                    }
                    let _e7173 = local_526;
                    let _e7180 = vec2<i32>(bitcast<i32>((_e7173.x & 4095u)), bitcast<i32>((_e7173.y & 16383u)));
                    let _e7184 = bitcast<i32>((_e7173.y >> bitcast<u32>(14u)));
                    local_527 = _e7180;
                    let _e7185 = local_808;
                    local_528 = _e7185;
                    let _e7188 = vec4<i32>(_e7180.x, _e7180.y, _e7185, 0i);
                    let _e7189 = _e7188.xyz;
                    let _e7196 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e7189.x, _e7189.y), i32(_e7189.z), _e7188.w);
                    let _e7198 = (_e7180.x + 1i);
                    let _e7200 = vec2<i32>(_e7198, _e7180.y);
                    let _e7207 = vec2<i32>(_e7200.x, (_e7200.y + (_e7198 >> bitcast<u32>(12i))));
                    let _e7212 = vec2<i32>((_e7207.x & 4095i), _e7207.y);
                    let _e7215 = vec4<i32>(_e7212.x, _e7212.y, _e7185, 0i);
                    let _e7216 = _e7215.xyz;
                    let _e7223 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e7216.x, _e7216.y), i32(_e7216.z), _e7215.w);
                    local_158 = _e7184;
                    local_157 = _e7196.xy;
                    local_156 = _e7196.zw;
                    local_155 = _e7223.xy;
                    local_154 = _e7223.zw;
                    if (_e7184 == 1i) {
                        let _e7229 = local_527;
                        let _e7231 = (_e7229.x + 2i);
                        let _e7233 = vec2<i32>(_e7231, _e7229.y);
                        let _e7240 = vec2<i32>(_e7233.x, (_e7233.y + (_e7231 >> bitcast<u32>(12i))));
                        let _e7245 = vec2<i32>((_e7240.x & 4095i), _e7240.y);
                        let _e7246 = local_528;
                        let _e7249 = vec4<i32>(_e7245.x, _e7245.y, _e7246, 0i);
                        let _e7250 = _e7249.xyz;
                        let _e7257 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e7250.x, _e7250.y), i32(_e7250.z), _e7249.w);
                        local_153 = vec3<f32>(_e7257.w, _e7257.x, _e7257.y);
                    } else {
                        local_153 = vec3<f32>(1f, 1f, 1f);
                    }
                    let _e7262 = local_153;
                    let _e7263 = local_154;
                    let _e7264 = local_155;
                    let _e7265 = local_156;
                    let _e7266 = local_157;
                    let _e7267 = local_158;
                    let _e7268 = local_519;
                    local_529 = _e7268;
                    let _e7269 = local_520;
                    local_530 = _e7269;
                    let _e7270 = local_802;
                    local_531 = _e7270;
                    let _e7271 = local_803;
                    local_532 = _e7271;
                    local_152 = _e7267;
                    local_151 = _e7266;
                    local_150 = _e7265;
                    local_149 = _e7264;
                    local_148 = _e7263;
                    local_147 = _e7262;
                    let _e7272 = local_809;
                    local_533 = _e7272;
                    switch bitcast<i32>(0u) {
                        default: {
                            let _e7274 = local_533;
                            if _e7274 {
                                let _e7275 = local_148;
                                let _e7276 = local_149;
                                let _e7277 = local_150;
                                let _e7278 = local_151;
                                let _e7279 = local_152;
                                local_179 = _e7279;
                                local_178 = _e7278;
                                local_177 = _e7277;
                                local_176 = _e7276;
                                local_175 = _e7275;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e7281 = local_179;
                                        if (_e7281 == 3i) {
                                            let _e7283 = local_178;
                                            let _e7285 = local_176;
                                            local_478 = max(_e7283.x, _e7285.x);
                                            break;
                                        }
                                        let _e7288 = local_179;
                                        if (_e7288 == 2i) {
                                            let _e7290 = local_178;
                                            let _e7292 = local_177;
                                            let _e7295 = local_176;
                                            let _e7297 = local_175;
                                            local_478 = max(max(_e7290.x, _e7292.x), max(_e7295.x, _e7297.x));
                                            break;
                                        }
                                        let _e7301 = local_178;
                                        let _e7303 = local_177;
                                        let _e7306 = local_176;
                                        local_478 = max(max(_e7301.x, _e7303.x), _e7306.x);
                                        break;
                                    }
                                }
                                let _e7309 = local_478;
                                let _e7310 = local_531;
                                local_480 = (_e7309 - _e7310.x);
                            } else {
                                let _e7313 = local_148;
                                let _e7314 = local_149;
                                let _e7315 = local_150;
                                let _e7316 = local_151;
                                let _e7317 = local_152;
                                local_174 = _e7317;
                                local_173 = _e7316;
                                local_172 = _e7315;
                                local_171 = _e7314;
                                local_170 = _e7313;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e7319 = local_174;
                                        if (_e7319 == 3i) {
                                            let _e7321 = local_173;
                                            let _e7323 = local_171;
                                            local_477 = max(_e7321.y, _e7323.y);
                                            break;
                                        }
                                        let _e7326 = local_174;
                                        if (_e7326 == 2i) {
                                            let _e7328 = local_173;
                                            let _e7330 = local_172;
                                            let _e7333 = local_171;
                                            let _e7335 = local_170;
                                            local_477 = max(max(_e7328.y, _e7330.y), max(_e7333.y, _e7335.y));
                                            break;
                                        }
                                        let _e7339 = local_173;
                                        let _e7341 = local_172;
                                        let _e7344 = local_171;
                                        local_477 = max(max(_e7339.y, _e7341.y), _e7344.y);
                                        break;
                                    }
                                }
                                let _e7347 = local_477;
                                let _e7348 = local_531;
                                local_480 = (_e7347 - _e7348.y);
                            }
                            let _e7351 = local_480;
                            let _e7352 = local_532;
                            if ((_e7351 * _e7352) < -0.5f) {
                                local_479 = false;
                                break;
                            }
                            let _e7355 = local_152;
                            if (_e7355 == 0i) {
                                let _e7357 = local_531;
                                let _e7359 = local_151;
                                local_481 = (_e7359.x - _e7357.x);
                                local_482 = (_e7359.y - _e7357.y);
                                let _e7365 = local_150;
                                local_483 = (_e7365.x - _e7357.x);
                                local_484 = (_e7365.y - _e7357.y);
                                let _e7370 = local_149;
                                local_485 = (_e7370.x - _e7357.x);
                                local_486 = (_e7370.y - _e7357.y);
                                let _e7375 = local_533;
                                if _e7375 {
                                    let _e7376 = local_482;
                                    local_488 = _e7376;
                                    let _e7377 = local_484;
                                    local_489 = _e7377;
                                    let _e7378 = local_486;
                                    local_474 = _e7378;
                                    if (abs(_e7378) <= 0.000015258789f) {
                                        local_473 = 0f;
                                    } else {
                                        let _e7381 = local_474;
                                        local_473 = _e7381;
                                    }
                                    let _e7382 = local_473;
                                    let _e7387 = local_489;
                                    local_475 = _e7387;
                                    if (abs(_e7387) <= 0.000015258789f) {
                                        local_472 = 0f;
                                    } else {
                                        let _e7390 = local_475;
                                        local_472 = _e7390;
                                    }
                                    let _e7391 = local_472;
                                    let _e7396 = local_488;
                                    local_476 = _e7396;
                                    if (abs(_e7396) <= 0.000015258789f) {
                                        local_471 = 0f;
                                    } else {
                                        let _e7399 = local_476;
                                        local_471 = _e7399;
                                    }
                                    let _e7400 = local_471;
                                    local_487 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e7382) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e7391) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e7400) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                } else {
                                    let _e7411 = local_481;
                                    local_490 = _e7411;
                                    let _e7412 = local_483;
                                    local_491 = _e7412;
                                    let _e7413 = local_485;
                                    local_468 = _e7413;
                                    if (abs(_e7413) <= 0.000015258789f) {
                                        local_467 = 0f;
                                    } else {
                                        let _e7416 = local_468;
                                        local_467 = _e7416;
                                    }
                                    let _e7417 = local_467;
                                    let _e7422 = local_491;
                                    local_469 = _e7422;
                                    if (abs(_e7422) <= 0.000015258789f) {
                                        local_466 = 0f;
                                    } else {
                                        let _e7425 = local_469;
                                        local_466 = _e7425;
                                    }
                                    let _e7426 = local_466;
                                    let _e7431 = local_490;
                                    local_470 = _e7431;
                                    if (abs(_e7431) <= 0.000015258789f) {
                                        local_465 = 0f;
                                    } else {
                                        let _e7434 = local_470;
                                        local_465 = _e7434;
                                    }
                                    let _e7435 = local_465;
                                    local_487 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e7417) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e7426) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e7435) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                }
                                let _e7446 = local_487;
                                if (_e7446 == 0u) {
                                    local_479 = true;
                                    break;
                                }
                                let _e7448 = local_533;
                                if _e7448 {
                                    let _e7449 = local_481;
                                    local_493 = _e7449;
                                    let _e7450 = local_482;
                                    local_494 = _e7450;
                                    let _e7451 = local_483;
                                    let _e7452 = local_484;
                                    let _e7453 = local_485;
                                    let _e7454 = local_486;
                                    let _e7455 = local_532;
                                    local_495 = _e7455;
                                    local_453 = ((_e7449 - (_e7451 * 2f)) + _e7453);
                                    let _e7461 = ((_e7450 - (_e7452 * 2f)) + _e7454);
                                    local_454 = _e7461;
                                    local_455 = (_e7449 - _e7451);
                                    local_456 = (_e7450 - _e7452);
                                    if (abs(_e7461) < 0.000015258789f) {
                                        let _e7466 = local_456;
                                        if (abs(_e7466) < 0.000015258789f) {
                                            local_457 = 0f;
                                        } else {
                                            let _e7469 = local_494;
                                            let _e7471 = local_456;
                                            local_457 = ((_e7469 * 0.5f) / _e7471);
                                        }
                                        let _e7473 = local_457;
                                        local_458 = _e7473;
                                    } else {
                                        let _e7474 = local_454;
                                        let _e7475 = local_494;
                                        let _e7476 = (_e7474 * _e7475);
                                        let _e7477 = local_456;
                                        let _e7479 = ((_e7477 * _e7477) - _e7476);
                                        local_460 = _e7479;
                                        if (_e7479 <= (max((_e7477 * _e7477), abs(_e7476)) * 0.000003f)) {
                                            local_452 = 0f;
                                        } else {
                                            let _e7485 = local_460;
                                            local_452 = sqrt(_e7485);
                                        }
                                        let _e7487 = local_452;
                                        local_459 = _e7487;
                                        let _e7488 = local_456;
                                        if (_e7488 >= 0f) {
                                            let _e7490 = local_456;
                                            let _e7491 = local_459;
                                            let _e7492 = (_e7490 + _e7491);
                                            local_461 = _e7492;
                                            let _e7493 = local_454;
                                            local_462 = (_e7492 / _e7493);
                                            if (abs(_e7492) < 0.000015258789f) {
                                                local_457 = 0f;
                                            } else {
                                                let _e7497 = local_494;
                                                let _e7498 = local_461;
                                                local_457 = (_e7497 / _e7498);
                                            }
                                            let _e7500 = local_462;
                                            local_458 = _e7500;
                                        } else {
                                            let _e7501 = local_456;
                                            let _e7502 = local_459;
                                            let _e7503 = (_e7501 - _e7502);
                                            local_463 = _e7503;
                                            let _e7504 = local_454;
                                            local_464 = (_e7503 / _e7504);
                                            if (abs(_e7503) < 0.000015258789f) {
                                                local_457 = 0f;
                                            } else {
                                                let _e7508 = local_494;
                                                let _e7509 = local_463;
                                                local_457 = (_e7508 / _e7509);
                                            }
                                            let _e7511 = local_457;
                                            let _e7512 = local_464;
                                            local_457 = _e7512;
                                            local_458 = _e7511;
                                        }
                                    }
                                    let _e7513 = local_455;
                                    let _e7514 = (_e7513 * 2f);
                                    let _e7515 = local_453;
                                    let _e7516 = local_457;
                                    let _e7520 = local_493;
                                    let _e7522 = local_495;
                                    let _e7524 = local_458;
                                    local_492 = vec2<f32>((((((_e7515 * _e7516) - _e7514) * _e7516) + _e7520) * _e7522), (((((_e7515 * _e7524) - _e7514) * _e7524) + _e7520) * _e7522));
                                } else {
                                    let _e7531 = local_481;
                                    local_496 = _e7531;
                                    let _e7532 = local_482;
                                    local_497 = _e7532;
                                    let _e7533 = local_483;
                                    let _e7534 = local_484;
                                    let _e7535 = local_485;
                                    let _e7536 = local_486;
                                    let _e7537 = local_532;
                                    local_498 = _e7537;
                                    let _e7540 = ((_e7531 - (_e7533 * 2f)) + _e7535);
                                    local_440 = _e7540;
                                    local_441 = ((_e7532 - (_e7534 * 2f)) + _e7536);
                                    local_442 = (_e7531 - _e7533);
                                    local_443 = (_e7532 - _e7534);
                                    if (abs(_e7540) < 0.000015258789f) {
                                        let _e7548 = local_442;
                                        if (abs(_e7548) < 0.000015258789f) {
                                            local_444 = 0f;
                                        } else {
                                            let _e7551 = local_496;
                                            let _e7553 = local_442;
                                            local_444 = ((_e7551 * 0.5f) / _e7553);
                                        }
                                        let _e7555 = local_444;
                                        local_445 = _e7555;
                                    } else {
                                        let _e7556 = local_440;
                                        let _e7557 = local_496;
                                        let _e7558 = (_e7556 * _e7557);
                                        let _e7559 = local_442;
                                        let _e7561 = ((_e7559 * _e7559) - _e7558);
                                        local_447 = _e7561;
                                        if (_e7561 <= (max((_e7559 * _e7559), abs(_e7558)) * 0.000003f)) {
                                            local_439 = 0f;
                                        } else {
                                            let _e7567 = local_447;
                                            local_439 = sqrt(_e7567);
                                        }
                                        let _e7569 = local_439;
                                        local_446 = _e7569;
                                        let _e7570 = local_442;
                                        if (_e7570 >= 0f) {
                                            let _e7572 = local_442;
                                            let _e7573 = local_446;
                                            let _e7574 = (_e7572 + _e7573);
                                            local_448 = _e7574;
                                            let _e7575 = local_440;
                                            local_449 = (_e7574 / _e7575);
                                            if (abs(_e7574) < 0.000015258789f) {
                                                local_444 = 0f;
                                            } else {
                                                let _e7579 = local_496;
                                                let _e7580 = local_448;
                                                local_444 = (_e7579 / _e7580);
                                            }
                                            let _e7582 = local_449;
                                            local_445 = _e7582;
                                        } else {
                                            let _e7583 = local_442;
                                            let _e7584 = local_446;
                                            let _e7585 = (_e7583 - _e7584);
                                            local_450 = _e7585;
                                            let _e7586 = local_440;
                                            local_451 = (_e7585 / _e7586);
                                            if (abs(_e7585) < 0.000015258789f) {
                                                local_444 = 0f;
                                            } else {
                                                let _e7590 = local_496;
                                                let _e7591 = local_450;
                                                local_444 = (_e7590 / _e7591);
                                            }
                                            let _e7593 = local_444;
                                            let _e7594 = local_451;
                                            local_444 = _e7594;
                                            local_445 = _e7593;
                                        }
                                    }
                                    let _e7595 = local_443;
                                    let _e7596 = (_e7595 * 2f);
                                    let _e7597 = local_441;
                                    let _e7598 = local_444;
                                    let _e7602 = local_497;
                                    let _e7604 = local_498;
                                    let _e7606 = local_445;
                                    local_492 = vec2<f32>((((((_e7597 * _e7598) - _e7596) * _e7598) + _e7602) * _e7604), (((((_e7597 * _e7606) - _e7596) * _e7606) + _e7602) * _e7604));
                                }
                                let _e7613 = local_487;
                                if ((_e7613 & 1u) != 0u) {
                                    let _e7616 = local_492;
                                    local_499 = _e7616.x;
                                    let _e7618 = local_533;
                                    if _e7618 {
                                        local_480 = 1f;
                                    } else {
                                        local_480 = -1f;
                                    }
                                    let _e7619 = local_529;
                                    let _e7620 = local_530;
                                    let _e7621 = local_499;
                                    let _e7622 = local_480;
                                    local_529 = (_e7619 + (_e7622 * clamp((_e7621 + 0.5f), 0f, 1f)));
                                    local_530 = max(_e7620, clamp((1f - (abs(_e7621) * 2f)), 0f, 1f));
                                }
                                let _e7632 = local_487;
                                if (_e7632 > 1u) {
                                    let _e7634 = local_492;
                                    local_500 = _e7634.y;
                                    let _e7636 = local_533;
                                    if _e7636 {
                                        local_480 = -1f;
                                    } else {
                                        local_480 = 1f;
                                    }
                                    let _e7637 = local_529;
                                    let _e7638 = local_530;
                                    let _e7639 = local_500;
                                    let _e7640 = local_480;
                                    local_529 = (_e7637 + (_e7640 * clamp((_e7639 + 0.5f), 0f, 1f)));
                                    local_530 = max(_e7638, clamp((1f - (abs(_e7639) * 2f)), 0f, 1f));
                                }
                                local_479 = true;
                                break;
                            }
                            let _e7650 = local_152;
                            if (_e7650 == 3i) {
                                let _e7652 = local_531;
                                let _e7655 = local_151;
                                let _e7660 = local_149;
                                let _e7665 = local_529;
                                local_501 = _e7665;
                                let _e7666 = local_530;
                                local_502 = _e7666;
                                local_503 = (_e7655.x - _e7652.x);
                                local_504 = (_e7655.y - _e7652.y);
                                local_505 = (_e7660.x - _e7652.x);
                                local_506 = (_e7660.y - _e7652.y);
                                let _e7667 = local_532;
                                local_507 = _e7667;
                                let _e7668 = local_533;
                                local_508 = _e7668;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e7670 = local_508;
                                        if _e7670 {
                                            let _e7671 = local_504;
                                            local_431 = _e7671;
                                        } else {
                                            let _e7672 = local_503;
                                            local_431 = _e7672;
                                        }
                                        let _e7673 = local_508;
                                        if _e7673 {
                                            let _e7674 = local_506;
                                            local_432 = _e7674;
                                        } else {
                                            let _e7675 = local_505;
                                            local_432 = _e7675;
                                        }
                                        let _e7676 = local_431;
                                        local_433 = _e7676;
                                        if (abs(_e7676) <= 0.000015258789f) {
                                            local_430 = 0f;
                                        } else {
                                            let _e7679 = local_433;
                                            local_430 = _e7679;
                                        }
                                        let _e7680 = local_430;
                                        let _e7682 = local_432;
                                        local_434 = _e7682;
                                        if (abs(_e7682) <= 0.000015258789f) {
                                            local_429 = 0f;
                                        } else {
                                            let _e7685 = local_434;
                                            local_429 = _e7685;
                                        }
                                        let _e7686 = local_429;
                                        if ((_e7680 < 0f) == (_e7686 < 0f)) {
                                            break;
                                        }
                                        let _e7689 = local_432;
                                        let _e7690 = local_431;
                                        let _e7691 = (_e7689 - _e7690);
                                        local_435 = _e7691;
                                        if (abs(_e7691) < 0.0000000001f) {
                                            break;
                                        }
                                        let _e7694 = local_431;
                                        let _e7696 = local_435;
                                        local_436 = clamp((-(_e7694) / _e7696), 0f, 1f);
                                        let _e7699 = local_508;
                                        if _e7699 {
                                            let _e7700 = local_506;
                                            let _e7701 = local_504;
                                            local_437 = (_e7700 - _e7701);
                                        } else {
                                            let _e7703 = local_503;
                                            let _e7704 = local_505;
                                            local_437 = (_e7703 - _e7704);
                                        }
                                        let _e7706 = local_437;
                                        if (abs(_e7706) <= 0.00001f) {
                                            break;
                                        }
                                        let _e7709 = local_508;
                                        if _e7709 {
                                            let _e7710 = local_503;
                                            let _e7711 = local_505;
                                            let _e7713 = local_436;
                                            local_431 = (_e7710 + ((_e7711 - _e7710) * _e7713));
                                        } else {
                                            let _e7716 = local_504;
                                            let _e7717 = local_506;
                                            let _e7719 = local_436;
                                            local_431 = (_e7716 + ((_e7717 - _e7716) * _e7719));
                                        }
                                        let _e7722 = local_431;
                                        let _e7723 = local_507;
                                        local_438 = (_e7722 * _e7723);
                                        let _e7725 = local_437;
                                        if (_e7725 > 0f) {
                                            local_431 = 1f;
                                        } else {
                                            local_431 = -1f;
                                        }
                                        let _e7727 = local_501;
                                        let _e7728 = local_502;
                                        let _e7729 = local_438;
                                        let _e7730 = local_431;
                                        local_501 = (_e7727 + (_e7730 * clamp((_e7729 + 0.5f), 0f, 1f)));
                                        local_502 = max(_e7728, clamp((1f - (abs(_e7729) * 2f)), 0f, 1f));
                                        break;
                                    }
                                }
                                let _e7740 = local_501;
                                local_529 = _e7740;
                                let _e7741 = local_502;
                                local_530 = _e7741;
                                local_479 = true;
                                break;
                            }
                            let _e7742 = local_152;
                            if (_e7742 == 1i) {
                                let _e7744 = local_529;
                                local_509 = _e7744;
                                let _e7745 = local_530;
                                local_510 = _e7745;
                                let _e7746 = local_147;
                                let _e7747 = local_148;
                                let _e7748 = local_149;
                                let _e7749 = local_150;
                                let _e7750 = local_151;
                                let _e7751 = local_152;
                                local_169 = _e7751;
                                local_168 = _e7750;
                                local_167 = _e7749;
                                local_166 = _e7748;
                                local_165 = _e7747;
                                local_164 = _e7746;
                                let _e7752 = local_531;
                                local_511 = _e7752;
                                let _e7753 = local_532;
                                local_512 = _e7753;
                                let _e7754 = local_533;
                                local_513 = _e7754;
                                switch bitcast<i32>(0u) {
                                    default: {
                                        let _e7756 = local_165;
                                        let _e7757 = local_166;
                                        let _e7758 = local_167;
                                        let _e7759 = local_168;
                                        let _e7760 = local_169;
                                        local_184 = _e7760;
                                        local_183 = _e7759;
                                        local_182 = _e7758;
                                        local_181 = _e7757;
                                        local_180 = _e7756;
                                        let _e7761 = local_511;
                                        local_362 = _e7761;
                                        let _e7762 = local_513;
                                        local_363 = _e7762;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e7764 = local_363;
                                                if _e7764 {
                                                    let _e7765 = local_362;
                                                    local_355 = _e7765.y;
                                                } else {
                                                    let _e7767 = local_362;
                                                    local_355 = _e7767.x;
                                                }
                                                let _e7769 = local_184;
                                                if (_e7769 == 2i) {
                                                    let _e7771 = local_363;
                                                    if _e7771 {
                                                        let _e7772 = local_183;
                                                        local_356 = _e7772.y;
                                                    } else {
                                                        let _e7774 = local_183;
                                                        local_356 = _e7774.x;
                                                    }
                                                    let _e7776 = local_363;
                                                    if _e7776 {
                                                        let _e7777 = local_182;
                                                        local_357 = _e7777.y;
                                                    } else {
                                                        let _e7779 = local_182;
                                                        local_357 = _e7779.x;
                                                    }
                                                    let _e7781 = local_363;
                                                    if _e7781 {
                                                        let _e7782 = local_181;
                                                        local_358 = _e7782.y;
                                                    } else {
                                                        let _e7784 = local_181;
                                                        local_358 = _e7784.x;
                                                    }
                                                    let _e7786 = local_363;
                                                    if _e7786 {
                                                        let _e7787 = local_180;
                                                        local_359 = _e7787.y;
                                                    } else {
                                                        let _e7789 = local_180;
                                                        local_359 = _e7789.x;
                                                    }
                                                    let _e7791 = local_356;
                                                    let _e7792 = local_357;
                                                    let _e7793 = local_358;
                                                    let _e7794 = local_359;
                                                    let _e7795 = local_355;
                                                    local_360 = _e7795;
                                                    local_352 = max(max(_e7791, _e7792), max(_e7793, _e7794));
                                                    if ((min(min(_e7791, _e7792), min(_e7793, _e7794)) - _e7795) <= 0.000015258789f) {
                                                        let _e7804 = local_352;
                                                        let _e7805 = local_360;
                                                        local_353 = ((_e7804 - _e7805) >= -0.000015258789f);
                                                    } else {
                                                        local_353 = false;
                                                    }
                                                    let _e7808 = local_353;
                                                    local_354 = _e7808;
                                                    break;
                                                }
                                                let _e7809 = local_363;
                                                if _e7809 {
                                                    let _e7810 = local_183;
                                                    local_356 = _e7810.y;
                                                } else {
                                                    let _e7812 = local_183;
                                                    local_356 = _e7812.x;
                                                }
                                                let _e7814 = local_363;
                                                if _e7814 {
                                                    let _e7815 = local_182;
                                                    local_357 = _e7815.y;
                                                } else {
                                                    let _e7817 = local_182;
                                                    local_357 = _e7817.x;
                                                }
                                                let _e7819 = local_363;
                                                if _e7819 {
                                                    let _e7820 = local_181;
                                                    local_358 = _e7820.y;
                                                } else {
                                                    let _e7822 = local_181;
                                                    local_358 = _e7822.x;
                                                }
                                                let _e7824 = local_356;
                                                let _e7825 = local_357;
                                                let _e7826 = local_358;
                                                let _e7827 = local_355;
                                                local_361 = _e7827;
                                                local_350 = max(max(_e7824, _e7825), _e7826);
                                                if ((min(min(_e7824, _e7825), _e7826) - _e7827) <= 0.000015258789f) {
                                                    let _e7834 = local_350;
                                                    let _e7835 = local_361;
                                                    local_351 = ((_e7834 - _e7835) >= -0.000015258789f);
                                                } else {
                                                    local_351 = false;
                                                }
                                                let _e7838 = local_351;
                                                local_354 = _e7838;
                                                break;
                                            }
                                        }
                                        let _e7839 = local_354;
                                        if !(_e7839) {
                                            break;
                                        }
                                        let _e7841 = local_513;
                                        if _e7841 {
                                            let _e7842 = local_511;
                                            local_364 = _e7842.y;
                                        } else {
                                            let _e7844 = local_511;
                                            local_364 = _e7844.x;
                                        }
                                        let _e7846 = local_513;
                                        if _e7846 {
                                            let _e7847 = local_511;
                                            local_365 = _e7847.x;
                                        } else {
                                            let _e7849 = local_511;
                                            local_365 = _e7849.y;
                                        }
                                        let _e7851 = local_513;
                                        if _e7851 {
                                            let _e7852 = local_168;
                                            local_366 = _e7852.y;
                                        } else {
                                            let _e7854 = local_168;
                                            local_366 = _e7854.x;
                                        }
                                        let _e7856 = local_513;
                                        if _e7856 {
                                            let _e7857 = local_167;
                                            local_367 = _e7857.y;
                                        } else {
                                            let _e7859 = local_167;
                                            local_367 = _e7859.x;
                                        }
                                        let _e7861 = local_513;
                                        if _e7861 {
                                            let _e7862 = local_166;
                                            local_368 = _e7862.y;
                                        } else {
                                            let _e7864 = local_166;
                                            local_368 = _e7864.x;
                                        }
                                        let _e7866 = local_513;
                                        if _e7866 {
                                            let _e7867 = local_168;
                                            local_369 = _e7867.x;
                                        } else {
                                            let _e7869 = local_168;
                                            local_369 = _e7869.y;
                                        }
                                        let _e7871 = local_513;
                                        if _e7871 {
                                            let _e7872 = local_167;
                                            local_370 = _e7872.x;
                                        } else {
                                            let _e7874 = local_167;
                                            local_370 = _e7874.y;
                                        }
                                        let _e7876 = local_513;
                                        if _e7876 {
                                            let _e7877 = local_166;
                                            local_371 = _e7877.x;
                                        } else {
                                            let _e7879 = local_166;
                                            local_371 = _e7879.y;
                                        }
                                        let _e7881 = local_164;
                                        local_372 = _e7881.x;
                                        let _e7883 = local_366;
                                        let _e7884 = local_364;
                                        let _e7886 = (_e7881.x * (_e7883 - _e7884));
                                        local_373 = _e7886;
                                        local_374 = _e7881.y;
                                        let _e7888 = local_367;
                                        let _e7890 = (_e7881.y * (_e7888 - _e7884));
                                        local_375 = _e7890;
                                        local_376 = _e7881.z;
                                        let _e7892 = local_368;
                                        let _e7894 = (_e7881.z * (_e7892 - _e7884));
                                        local_377 = _e7894;
                                        local_379 = _e7886;
                                        local_380 = _e7890;
                                        local_347 = _e7894;
                                        if (abs(_e7894) <= 0.000015258789f) {
                                            local_346 = 0f;
                                        } else {
                                            let _e7897 = local_347;
                                            local_346 = _e7897;
                                        }
                                        let _e7898 = local_346;
                                        let _e7903 = local_380;
                                        local_348 = _e7903;
                                        if (abs(_e7903) <= 0.000015258789f) {
                                            local_345 = 0f;
                                        } else {
                                            let _e7906 = local_348;
                                            local_345 = _e7906;
                                        }
                                        let _e7907 = local_345;
                                        let _e7912 = local_379;
                                        local_349 = _e7912;
                                        if (abs(_e7912) <= 0.000015258789f) {
                                            local_344 = 0f;
                                        } else {
                                            let _e7915 = local_349;
                                            local_344 = _e7915;
                                        }
                                        let _e7916 = local_344;
                                        let _e7926 = ((11892u >> bitcast<u32>((((bitcast<u32>(_e7898) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e7907) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e7916) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
                                        local_378 = _e7926;
                                        if (_e7926 == 0u) {
                                            break;
                                        }
                                        let _e7928 = local_378;
                                        if (_e7928 == 257u) {
                                            local_381 = 2i;
                                        } else {
                                            local_381 = 1i;
                                        }
                                        let _e7930 = local_373;
                                        let _e7931 = local_375;
                                        let _e7934 = local_377;
                                        let _e7935 = ((_e7930 - (2f * _e7931)) + _e7934);
                                        local_382 = _e7935;
                                        local_383 = (2f * (_e7931 - _e7930));
                                        if (abs(_e7935) < 0.000015258789f) {
                                            let _e7940 = local_383;
                                            if (abs(_e7940) >= 0.000015258789f) {
                                                let _e7943 = local_373;
                                                let _e7945 = local_383;
                                                local_384 = 1i;
                                                local_385 = (-(_e7943) / _e7945);
                                            } else {
                                                local_384 = 0i;
                                                local_385 = 0f;
                                            }
                                            let _e7947 = local_385;
                                            local_385 = 0f;
                                            local_386 = _e7947;
                                        } else {
                                            let _e7948 = local_383;
                                            let _e7950 = local_382;
                                            let _e7952 = local_373;
                                            let _e7956 = sqrt(max(((_e7948 * _e7948) - ((4f * _e7950) * _e7952)), 0f));
                                            let _e7957 = (0.5f / _e7950);
                                            let _e7958 = -(_e7948);
                                            local_384 = 2i;
                                            local_385 = ((_e7958 + _e7956) * _e7957);
                                            local_386 = ((_e7958 - _e7956) * _e7957);
                                        }
                                        let _e7963 = local_384;
                                        if (_e7963 == 0i) {
                                            break;
                                        }
                                        let _e7965 = local_381;
                                        if (_e7965 == 1i) {
                                            let _e7967 = local_384;
                                            if (_e7967 == 2i) {
                                                let _e7969 = local_385;
                                                let _e7974 = local_386;
                                                local_387 = (max(max(0f, -(_e7969)), (_e7969 - 1f)) < max(max(0f, -(_e7974)), (_e7974 - 1f)));
                                            } else {
                                                local_387 = false;
                                            }
                                            let _e7980 = local_387;
                                            if _e7980 {
                                                let _e7981 = local_385;
                                                local_388 = _e7981;
                                            } else {
                                                let _e7982 = local_386;
                                                local_388 = _e7982;
                                            }
                                            let _e7983 = local_388;
                                            local_388 = clamp(_e7983, 0f, 1f);
                                            local_389 = 1i;
                                            local_390 = 0f;
                                        } else {
                                            let _e7985 = local_385;
                                            let _e7987 = local_386;
                                            local_388 = clamp(_e7987, 0f, 1f);
                                            local_389 = 2i;
                                            local_390 = clamp(_e7985, 0f, 1f);
                                        }
                                        let _e7989 = local_366;
                                        let _e7990 = local_372;
                                        let _e7991 = (_e7989 * _e7990);
                                        local_391 = _e7991;
                                        let _e7992 = local_367;
                                        let _e7994 = local_374;
                                        let _e7997 = local_368;
                                        let _e7998 = local_376;
                                        local_392 = ((_e7991 - ((2f * _e7992) * _e7994)) + (_e7997 * _e7998));
                                        local_393 = (2f * ((_e7992 * _e7994) - _e7991));
                                        let _e8004 = local_369;
                                        let _e8005 = (_e8004 * _e7990);
                                        local_394 = _e8005;
                                        let _e8006 = local_370;
                                        let _e8010 = local_371;
                                        local_395 = ((_e8005 - ((2f * _e8006) * _e7994)) + (_e8010 * _e7998));
                                        local_396 = (2f * ((_e8006 * _e7994) - _e8005));
                                        local_397 = ((_e7990 - (2f * _e7994)) + _e7998);
                                        local_398 = (2f * (_e7994 - _e7990));
                                        let _e8021 = local_509;
                                        local_399 = _e8021;
                                        let _e8022 = local_510;
                                        local_400 = _e8022;
                                        let _e8023 = local_388;
                                        local_401 = _e8023;
                                        let _e8024 = local_365;
                                        local_402 = _e8024;
                                        let _e8025 = local_512;
                                        local_403 = _e8025;
                                        let _e8026 = local_513;
                                        local_404 = _e8026;
                                        let _e8027 = local_392;
                                        local_405 = _e8027;
                                        let _e8028 = local_393;
                                        local_406 = _e8028;
                                        let _e8029 = local_391;
                                        local_407 = _e8029;
                                        let _e8030 = local_395;
                                        local_408 = _e8030;
                                        let _e8031 = local_396;
                                        local_409 = _e8031;
                                        let _e8032 = local_394;
                                        local_410 = _e8032;
                                        let _e8033 = local_397;
                                        local_411 = _e8033;
                                        let _e8034 = local_398;
                                        local_412 = _e8034;
                                        let _e8035 = local_372;
                                        local_413 = _e8035;
                                        switch bitcast<i32>(0u) {
                                            default: {
                                                let _e8037 = local_411;
                                                let _e8038 = local_401;
                                                let _e8040 = local_412;
                                                let _e8043 = local_413;
                                                let _e8045 = max(((((_e8037 * _e8038) + _e8040) * _e8038) + _e8043), 0.000015258789f);
                                                let _e8046 = local_408;
                                                let _e8048 = local_409;
                                                let _e8051 = local_410;
                                                local_340 = (((((_e8046 * _e8038) + _e8048) * _e8038) + _e8051) / _e8045);
                                                let _e8054 = local_405;
                                                let _e8057 = local_406;
                                                let _e8063 = local_407;
                                                local_341 = ((((((2f * _e8054) * _e8038) + _e8057) * _e8045) - (((((_e8054 * _e8038) + _e8057) * _e8038) + _e8063) * (((2f * _e8037) * _e8038) + _e8040))) / (_e8045 * _e8045));
                                                let _e8072 = local_404;
                                                if !(_e8072) {
                                                    let _e8074 = local_341;
                                                    local_342 = -(_e8074);
                                                } else {
                                                    let _e8076 = local_341;
                                                    local_342 = _e8076;
                                                }
                                                let _e8077 = local_342;
                                                if (abs(_e8077) <= 0.00001f) {
                                                    break;
                                                }
                                                let _e8080 = local_340;
                                                let _e8081 = local_402;
                                                let _e8083 = local_403;
                                                local_343 = ((_e8080 - _e8081) * _e8083);
                                                let _e8085 = local_342;
                                                if (_e8085 > 0f) {
                                                    local_342 = 1f;
                                                } else {
                                                    local_342 = -1f;
                                                }
                                                let _e8087 = local_399;
                                                let _e8088 = local_400;
                                                let _e8089 = local_343;
                                                let _e8090 = local_342;
                                                local_399 = (_e8087 + (_e8090 * clamp((_e8089 + 0.5f), 0f, 1f)));
                                                local_400 = max(_e8088, clamp((1f - (abs(_e8089) * 2f)), 0f, 1f));
                                                break;
                                            }
                                        }
                                        let _e8100 = local_399;
                                        local_509 = _e8100;
                                        let _e8101 = local_400;
                                        local_510 = _e8101;
                                        let _e8102 = local_389;
                                        if (_e8102 == 2i) {
                                            let _e8104 = local_509;
                                            local_414 = _e8104;
                                            let _e8105 = local_510;
                                            local_415 = _e8105;
                                            let _e8106 = local_390;
                                            local_416 = _e8106;
                                            let _e8107 = local_365;
                                            local_417 = _e8107;
                                            let _e8108 = local_512;
                                            local_418 = _e8108;
                                            let _e8109 = local_513;
                                            local_419 = _e8109;
                                            let _e8110 = local_392;
                                            local_420 = _e8110;
                                            let _e8111 = local_393;
                                            local_421 = _e8111;
                                            let _e8112 = local_391;
                                            local_422 = _e8112;
                                            let _e8113 = local_395;
                                            local_423 = _e8113;
                                            let _e8114 = local_396;
                                            local_424 = _e8114;
                                            let _e8115 = local_394;
                                            local_425 = _e8115;
                                            let _e8116 = local_397;
                                            local_426 = _e8116;
                                            let _e8117 = local_398;
                                            local_427 = _e8117;
                                            let _e8118 = local_372;
                                            local_428 = _e8118;
                                            switch bitcast<i32>(0u) {
                                                default: {
                                                    let _e8120 = local_426;
                                                    let _e8121 = local_416;
                                                    let _e8123 = local_427;
                                                    let _e8126 = local_428;
                                                    let _e8128 = max(((((_e8120 * _e8121) + _e8123) * _e8121) + _e8126), 0.000015258789f);
                                                    let _e8129 = local_423;
                                                    let _e8131 = local_424;
                                                    let _e8134 = local_425;
                                                    local_336 = (((((_e8129 * _e8121) + _e8131) * _e8121) + _e8134) / _e8128);
                                                    let _e8137 = local_420;
                                                    let _e8140 = local_421;
                                                    let _e8146 = local_422;
                                                    local_337 = ((((((2f * _e8137) * _e8121) + _e8140) * _e8128) - (((((_e8137 * _e8121) + _e8140) * _e8121) + _e8146) * (((2f * _e8120) * _e8121) + _e8123))) / (_e8128 * _e8128));
                                                    let _e8155 = local_419;
                                                    if !(_e8155) {
                                                        let _e8157 = local_337;
                                                        local_338 = -(_e8157);
                                                    } else {
                                                        let _e8159 = local_337;
                                                        local_338 = _e8159;
                                                    }
                                                    let _e8160 = local_338;
                                                    if (abs(_e8160) <= 0.00001f) {
                                                        break;
                                                    }
                                                    let _e8163 = local_336;
                                                    let _e8164 = local_417;
                                                    let _e8166 = local_418;
                                                    local_339 = ((_e8163 - _e8164) * _e8166);
                                                    let _e8168 = local_338;
                                                    if (_e8168 > 0f) {
                                                        local_338 = 1f;
                                                    } else {
                                                        local_338 = -1f;
                                                    }
                                                    let _e8170 = local_414;
                                                    let _e8171 = local_415;
                                                    let _e8172 = local_339;
                                                    let _e8173 = local_338;
                                                    local_414 = (_e8170 + (_e8173 * clamp((_e8172 + 0.5f), 0f, 1f)));
                                                    local_415 = max(_e8171, clamp((1f - (abs(_e8172) * 2f)), 0f, 1f));
                                                    break;
                                                }
                                            }
                                            let _e8183 = local_414;
                                            local_509 = _e8183;
                                            let _e8184 = local_415;
                                            local_510 = _e8184;
                                        }
                                        break;
                                    }
                                }
                                let _e8185 = local_509;
                                local_529 = _e8185;
                                let _e8186 = local_510;
                                local_530 = _e8186;
                                local_479 = true;
                                break;
                            }
                            let _e8187 = local_529;
                            local_514 = _e8187;
                            let _e8188 = local_530;
                            local_515 = _e8188;
                            let _e8189 = local_148;
                            let _e8190 = local_149;
                            let _e8191 = local_150;
                            let _e8192 = local_151;
                            let _e8193 = local_152;
                            local_163 = _e8193;
                            local_162 = _e8192;
                            local_161 = _e8191;
                            local_160 = _e8190;
                            local_159 = _e8189;
                            let _e8194 = local_531;
                            local_516 = _e8194;
                            let _e8195 = local_532;
                            local_517 = _e8195;
                            let _e8196 = local_533;
                            local_518 = _e8196;
                            switch bitcast<i32>(0u) {
                                default: {
                                    let _e8198 = local_159;
                                    let _e8199 = local_160;
                                    let _e8200 = local_161;
                                    let _e8201 = local_162;
                                    let _e8202 = local_163;
                                    local_189 = _e8202;
                                    local_188 = _e8201;
                                    local_187 = _e8200;
                                    local_186 = _e8199;
                                    local_185 = _e8198;
                                    let _e8203 = local_516;
                                    local_304 = _e8203;
                                    let _e8204 = local_518;
                                    local_305 = _e8204;
                                    switch bitcast<i32>(0u) {
                                        default: {
                                            let _e8206 = local_305;
                                            if _e8206 {
                                                let _e8207 = local_304;
                                                local_297 = _e8207.y;
                                            } else {
                                                let _e8209 = local_304;
                                                local_297 = _e8209.x;
                                            }
                                            let _e8211 = local_189;
                                            if (_e8211 == 2i) {
                                                let _e8213 = local_305;
                                                if _e8213 {
                                                    let _e8214 = local_188;
                                                    local_298 = _e8214.y;
                                                } else {
                                                    let _e8216 = local_188;
                                                    local_298 = _e8216.x;
                                                }
                                                let _e8218 = local_305;
                                                if _e8218 {
                                                    let _e8219 = local_187;
                                                    local_299 = _e8219.y;
                                                } else {
                                                    let _e8221 = local_187;
                                                    local_299 = _e8221.x;
                                                }
                                                let _e8223 = local_305;
                                                if _e8223 {
                                                    let _e8224 = local_186;
                                                    local_300 = _e8224.y;
                                                } else {
                                                    let _e8226 = local_186;
                                                    local_300 = _e8226.x;
                                                }
                                                let _e8228 = local_305;
                                                if _e8228 {
                                                    let _e8229 = local_185;
                                                    local_301 = _e8229.y;
                                                } else {
                                                    let _e8231 = local_185;
                                                    local_301 = _e8231.x;
                                                }
                                                let _e8233 = local_298;
                                                let _e8234 = local_299;
                                                let _e8235 = local_300;
                                                let _e8236 = local_301;
                                                let _e8237 = local_297;
                                                local_302 = _e8237;
                                                local_294 = max(max(_e8233, _e8234), max(_e8235, _e8236));
                                                if ((min(min(_e8233, _e8234), min(_e8235, _e8236)) - _e8237) <= 0.000015258789f) {
                                                    let _e8246 = local_294;
                                                    let _e8247 = local_302;
                                                    local_295 = ((_e8246 - _e8247) >= -0.000015258789f);
                                                } else {
                                                    local_295 = false;
                                                }
                                                let _e8250 = local_295;
                                                local_296 = _e8250;
                                                break;
                                            }
                                            let _e8251 = local_305;
                                            if _e8251 {
                                                let _e8252 = local_188;
                                                local_298 = _e8252.y;
                                            } else {
                                                let _e8254 = local_188;
                                                local_298 = _e8254.x;
                                            }
                                            let _e8256 = local_305;
                                            if _e8256 {
                                                let _e8257 = local_187;
                                                local_299 = _e8257.y;
                                            } else {
                                                let _e8259 = local_187;
                                                local_299 = _e8259.x;
                                            }
                                            let _e8261 = local_305;
                                            if _e8261 {
                                                let _e8262 = local_186;
                                                local_300 = _e8262.y;
                                            } else {
                                                let _e8264 = local_186;
                                                local_300 = _e8264.x;
                                            }
                                            let _e8266 = local_298;
                                            let _e8267 = local_299;
                                            let _e8268 = local_300;
                                            let _e8269 = local_297;
                                            local_303 = _e8269;
                                            local_292 = max(max(_e8266, _e8267), _e8268);
                                            if ((min(min(_e8266, _e8267), _e8268) - _e8269) <= 0.000015258789f) {
                                                let _e8276 = local_292;
                                                let _e8277 = local_303;
                                                local_293 = ((_e8276 - _e8277) >= -0.000015258789f);
                                            } else {
                                                local_293 = false;
                                            }
                                            let _e8280 = local_293;
                                            local_296 = _e8280;
                                            break;
                                        }
                                    }
                                    let _e8281 = local_296;
                                    if !(_e8281) {
                                        break;
                                    }
                                    let _e8283 = local_518;
                                    if _e8283 {
                                        let _e8284 = local_516;
                                        local_306 = _e8284.y;
                                    } else {
                                        let _e8286 = local_516;
                                        local_306 = _e8286.x;
                                    }
                                    let _e8288 = local_518;
                                    if _e8288 {
                                        let _e8289 = local_516;
                                        local_307 = _e8289.x;
                                    } else {
                                        let _e8291 = local_516;
                                        local_307 = _e8291.y;
                                    }
                                    let _e8293 = local_518;
                                    if _e8293 {
                                        let _e8294 = local_162;
                                        local_308 = _e8294.y;
                                    } else {
                                        let _e8296 = local_162;
                                        local_308 = _e8296.x;
                                    }
                                    let _e8298 = local_518;
                                    if _e8298 {
                                        let _e8299 = local_161;
                                        local_309 = _e8299.y;
                                    } else {
                                        let _e8301 = local_161;
                                        local_309 = _e8301.x;
                                    }
                                    let _e8303 = local_518;
                                    if _e8303 {
                                        let _e8304 = local_160;
                                        local_310 = _e8304.y;
                                    } else {
                                        let _e8306 = local_160;
                                        local_310 = _e8306.x;
                                    }
                                    let _e8308 = local_518;
                                    if _e8308 {
                                        let _e8309 = local_159;
                                        local_311 = _e8309.y;
                                    } else {
                                        let _e8311 = local_159;
                                        local_311 = _e8311.x;
                                    }
                                    let _e8313 = local_518;
                                    if _e8313 {
                                        let _e8314 = local_162;
                                        local_312 = _e8314.x;
                                    } else {
                                        let _e8316 = local_162;
                                        local_312 = _e8316.y;
                                    }
                                    let _e8318 = local_518;
                                    if _e8318 {
                                        let _e8319 = local_161;
                                        local_313 = _e8319.x;
                                    } else {
                                        let _e8321 = local_161;
                                        local_313 = _e8321.y;
                                    }
                                    let _e8323 = local_518;
                                    if _e8323 {
                                        let _e8324 = local_160;
                                        local_314 = _e8324.x;
                                    } else {
                                        let _e8326 = local_160;
                                        local_314 = _e8326.y;
                                    }
                                    let _e8328 = local_518;
                                    if _e8328 {
                                        let _e8329 = local_159;
                                        local_315 = _e8329.x;
                                    } else {
                                        let _e8331 = local_159;
                                        local_315 = _e8331.y;
                                    }
                                    let _e8333 = local_309;
                                    let _e8334 = (3f * _e8333);
                                    let _e8335 = local_310;
                                    let _e8336 = (3f * _e8335);
                                    let _e8337 = local_308;
                                    let _e8340 = local_311;
                                    local_316 = (((_e8334 - _e8337) - _e8336) + _e8340);
                                    local_317 = (((3f * _e8337) - (6f * _e8333)) + _e8336);
                                    local_318 = ((-3f * _e8337) + _e8334);
                                    let _e8348 = local_306;
                                    let _e8349 = (_e8337 - _e8348);
                                    local_319 = _e8349;
                                    local_320 = (_e8340 - _e8348);
                                    local_321 = _e8349;
                                    if (abs(_e8349) <= 0.000015258789f) {
                                        local_291 = 0f;
                                    } else {
                                        let _e8353 = local_321;
                                        local_291 = _e8353;
                                    }
                                    let _e8354 = local_291;
                                    let _e8356 = local_320;
                                    local_322 = _e8356;
                                    if (abs(_e8356) <= 0.000015258789f) {
                                        local_290 = 0f;
                                    } else {
                                        let _e8359 = local_322;
                                        local_290 = _e8359;
                                    }
                                    let _e8360 = local_290;
                                    if ((_e8354 < 0f) == (_e8360 < 0f)) {
                                        break;
                                    }
                                    local_323 = 0f;
                                    let _e8363 = local_319;
                                    if (abs(_e8363) <= 0.000015258789f) {
                                        local_323 = 0f;
                                    } else {
                                        let _e8366 = local_320;
                                        if (abs(_e8366) <= 0.000015258789f) {
                                            local_323 = 1f;
                                        } else {
                                            let _e8369 = local_316;
                                            local_324 = _e8369;
                                            let _e8370 = local_317;
                                            local_325 = _e8370;
                                            let _e8371 = local_318;
                                            local_326 = _e8371;
                                            let _e8372 = local_319;
                                            local_327 = _e8372;
                                            let _e8373 = local_320;
                                            local_328 = _e8373;
                                            switch bitcast<i32>(0u) {
                                                default: {
                                                    let _e8375 = local_327;
                                                    if (_e8375 < -0.000015258789f) {
                                                        let _e8377 = local_328;
                                                        local_277 = (_e8377 < -0.000015258789f);
                                                    } else {
                                                        local_277 = false;
                                                    }
                                                    let _e8379 = local_277;
                                                    if _e8379 {
                                                        local_277 = true;
                                                    } else {
                                                        let _e8380 = local_327;
                                                        if (_e8380 > 0.000015258789f) {
                                                            let _e8382 = local_328;
                                                            local_277 = (_e8382 > 0.000015258789f);
                                                        } else {
                                                            local_277 = false;
                                                        }
                                                    }
                                                    let _e8384 = local_277;
                                                    if _e8384 {
                                                        local_276 = false;
                                                        break;
                                                    }
                                                    let _e8385 = local_328;
                                                    let _e8386 = local_327;
                                                    local_278 = (_e8385 >= _e8386);
                                                    local_279 = 0.5f;
                                                    local_280 = 0f;
                                                    local_281 = 1f;
                                                    local_282 = 0i;
                                                    loop {
                                                        let _e8388 = local_282;
                                                        if (_e8388 < 16i) {
                                                        } else {
                                                            break;
                                                        }
                                                        let _e8390 = local_324;
                                                        let _e8391 = local_279;
                                                        let _e8393 = local_325;
                                                        let _e8396 = local_326;
                                                        let _e8399 = local_327;
                                                        local_283 = ((((((_e8390 * _e8391) + _e8393) * _e8391) + _e8396) * _e8391) + _e8399);
                                                        let _e8401 = local_278;
                                                        if _e8401 {
                                                            let _e8402 = local_283;
                                                            local_277 = (_e8402 < 0f);
                                                        } else {
                                                            local_277 = false;
                                                        }
                                                        let _e8404 = local_277;
                                                        if _e8404 {
                                                            local_284 = true;
                                                        } else {
                                                            let _e8405 = local_278;
                                                            if !(_e8405) {
                                                                let _e8407 = local_283;
                                                                local_284 = (_e8407 > 0f);
                                                            } else {
                                                                local_284 = false;
                                                            }
                                                        }
                                                        let _e8409 = local_284;
                                                        if _e8409 {
                                                            let _e8410 = local_279;
                                                            local_280 = _e8410;
                                                        } else {
                                                            let _e8411 = local_279;
                                                            local_281 = _e8411;
                                                        }
                                                        let _e8412 = local_324;
                                                        let _e8414 = local_279;
                                                        let _e8416 = local_325;
                                                        let _e8420 = local_326;
                                                        let _e8421 = (((((3f * _e8412) * _e8414) + (2f * _e8416)) * _e8414) + _e8420);
                                                        local_285 = _e8421;
                                                        let _e8422 = local_280;
                                                        let _e8423 = local_281;
                                                        local_286 = ((_e8422 + _e8423) * 0.5f);
                                                        if (abs(_e8421) >= 0.000001f) {
                                                            let _e8428 = local_279;
                                                            let _e8429 = local_283;
                                                            let _e8430 = local_285;
                                                            let _e8432 = (_e8428 - (_e8429 / _e8430));
                                                            local_287 = _e8432;
                                                            let _e8433 = local_280;
                                                            if (_e8432 > _e8433) {
                                                                let _e8435 = local_287;
                                                                let _e8436 = local_281;
                                                                local_288 = (_e8435 < _e8436);
                                                            } else {
                                                                local_288 = false;
                                                            }
                                                            let _e8438 = local_288;
                                                            if _e8438 {
                                                                let _e8439 = local_287;
                                                                local_289 = _e8439;
                                                            } else {
                                                                let _e8440 = local_286;
                                                                local_289 = _e8440;
                                                            }
                                                        } else {
                                                            let _e8441 = local_286;
                                                            local_289 = _e8441;
                                                        }
                                                        let _e8442 = local_282;
                                                        let _e8444 = local_289;
                                                        local_279 = _e8444;
                                                        local_282 = (_e8442 + 1i);
                                                        continue;
                                                    }
                                                    let _e8445 = local_279;
                                                    local_329 = _e8445;
                                                    local_276 = true;
                                                    break;
                                                }
                                            }
                                            let _e8446 = local_276;
                                            let _e8447 = local_329;
                                            local_323 = _e8447;
                                            if !(_e8446) {
                                                break;
                                            }
                                        }
                                    }
                                    let _e8449 = local_313;
                                    let _e8450 = (3f * _e8449);
                                    let _e8451 = local_314;
                                    let _e8452 = (3f * _e8451);
                                    let _e8453 = local_312;
                                    let _e8456 = local_315;
                                    local_330 = (((_e8450 - _e8453) - _e8452) + _e8456);
                                    local_331 = (((3f * _e8453) - (6f * _e8449)) + _e8452);
                                    local_332 = ((-3f * _e8453) + _e8450);
                                    let _e8464 = local_323;
                                    if (_e8464 == 1f) {
                                        let _e8466 = local_315;
                                        local_333 = _e8466;
                                    } else {
                                        let _e8467 = local_330;
                                        let _e8468 = local_323;
                                        let _e8470 = local_331;
                                        let _e8473 = local_332;
                                        let _e8476 = local_312;
                                        local_333 = ((((((_e8467 * _e8468) + _e8470) * _e8468) + _e8473) * _e8468) + _e8476);
                                    }
                                    let _e8478 = local_518;
                                    if _e8478 {
                                        let _e8479 = local_311;
                                        let _e8480 = local_308;
                                        local_334 = (_e8479 - _e8480);
                                    } else {
                                        let _e8482 = local_308;
                                        let _e8483 = local_311;
                                        local_334 = (_e8482 - _e8483);
                                    }
                                    let _e8485 = local_333;
                                    let _e8486 = local_307;
                                    let _e8488 = local_517;
                                    local_335 = ((_e8485 - _e8486) * _e8488);
                                    let _e8490 = local_334;
                                    if (_e8490 > 0f) {
                                        local_306 = 1f;
                                    } else {
                                        local_306 = -1f;
                                    }
                                    let _e8492 = local_514;
                                    let _e8493 = local_515;
                                    let _e8494 = local_335;
                                    let _e8495 = local_306;
                                    local_514 = (_e8492 + (_e8495 * clamp((_e8494 + 0.5f), 0f, 1f)));
                                    local_515 = max(_e8493, clamp((1f - (abs(_e8494) * 2f)), 0f, 1f));
                                    break;
                                }
                            }
                            let _e8505 = local_514;
                            local_529 = _e8505;
                            let _e8506 = local_515;
                            local_530 = _e8506;
                            local_479 = true;
                            break;
                        }
                    }
                    let _e8507 = local_479;
                    let _e8508 = local_529;
                    local_519 = _e8508;
                    let _e8509 = local_530;
                    local_520 = _e8509;
                    if !(_e8507) {
                        break;
                    }
                    let _e8511 = local_525;
                    local_525 = (_e8511 + 1i);
                    continue;
                }
                let _e8513 = local_522;
                local_522 = (_e8513 + 1i);
                continue;
            }
            let _e8515 = local_519;
            let _e8516 = local_520;
            let _e8517 = vec2<f32>(_e8515, _e8516);
            let _e8518 = local_793;
            local_810 = _e8518.x;
            local_811 = _e8517.x;
            local_812 = (((_e8518.x * _e8518.y) + (_e8517.x * _e8517.y)) / max((_e8518.y + _e8517.y), 0.000015258789f));
            let _e8529 = local_1493;
            local_813 = _e8529;
            switch bitcast<i32>(0u) {
                default: {
                    let _e8531 = local_813;
                    if (_e8531 == 1i) {
                        let _e8533 = local_812;
                        local_275 = (1f - abs(((fract((_e8533 * 0.5f)) * 2f) - 1f)));
                        break;
                    }
                    let _e8540 = local_812;
                    local_275 = abs(_e8540);
                    break;
                }
            }
            let _e8542 = local_275;
            let _e8543 = local_810;
            local_814 = _e8543;
            let _e8544 = local_1493;
            local_815 = _e8544;
            switch bitcast<i32>(0u) {
                default: {
                    let _e8546 = local_815;
                    if (_e8546 == 1i) {
                        let _e8548 = local_814;
                        local_274 = (1f - abs(((fract((_e8548 * 0.5f)) * 2f) - 1f)));
                        break;
                    }
                    let _e8555 = local_814;
                    local_274 = abs(_e8555);
                    break;
                }
            }
            let _e8557 = local_274;
            let _e8558 = local_811;
            local_816 = _e8558;
            let _e8559 = local_1493;
            local_817 = _e8559;
            switch bitcast<i32>(0u) {
                default: {
                    let _e8561 = local_817;
                    if (_e8561 == 1i) {
                        let _e8563 = local_816;
                        local_273 = (1f - abs(((fract((_e8563 * 0.5f)) * 2f) - 1f)));
                        break;
                    }
                    let _e8570 = local_816;
                    local_273 = abs(_e8570);
                    break;
                }
            }
            let _e8572 = local_273;
            local_270 = clamp(max(_e8542, min(_e8557, _e8572)), 0f, 1f);
            let _e8577 = PushConstants_0_.coverage_exponent_0_;
            let _e8578 = max(_e8577, 0.000015258789f);
            local_271 = _e8578;
            if (abs((_e8578 - 1f)) <= 0.000001f) {
                let _e8582 = local_270;
                local_272 = _e8582;
            } else {
                let _e8583 = local_270;
                let _e8584 = local_271;
                local_272 = pow(_e8583, _e8584);
            }
            let _e8586 = local_272;
            local_1488 = _e8586;
            if (_e8586 < 0.003921569f) {
                discard;
            }
            let _e8588 = v_texcoord_0_1;
            local_1494 = _e8588;
            let _e8589 = local_1475;
            local_1495 = _e8589;
            let _e8590 = local_1476;
            local_1496 = _e8590;
            switch bitcast<i32>(0u) {
                default: {
                    let _e8592 = local_1496;
                    let _e8595 = i32((0.5f - _e8592.w));
                    local_246 = _e8595;
                    let _e8596 = local_1495;
                    let _e8597 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e8600 = local_245;
                    let _e8603 = vec2<i32>(vec2<i32>(_e8597).x, _e8600.y);
                    let _e8604 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e8609 = vec2<i32>(_e8603.x, vec2<i32>(_e8604).y);
                    local_245 = _e8609;
                    let _e8615 = (((_e8596.y * _e8609.x) + _e8596.x) + 2i);
                    let _e8624 = vec2<i32>((_e8615 - (i32(floor((f32(_e8615) / f32(_e8609.x)))) * _e8609.x)), (_e8615 / _e8609.x));
                    let _e8627 = vec3<i32>(_e8624.x, _e8624.y, 0i);
                    let _e8630 = textureLoad(u_layer_tex_0_image, _e8627.xy, _e8627.z);
                    local_247 = _e8630;
                    if (_e8595 == 1i) {
                        let _e8632 = local_247;
                        local_191 = _e8632;
                        local_190 = 0f;
                        break;
                    }
                    let _e8633 = local_1495;
                    let _e8634 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e8637 = local_244;
                    let _e8640 = vec2<i32>(vec2<i32>(_e8634).x, _e8637.y);
                    let _e8641 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e8646 = vec2<i32>(_e8640.x, vec2<i32>(_e8641).y);
                    local_244 = _e8646;
                    let _e8652 = (((_e8633.y * _e8646.x) + _e8633.x) + 3i);
                    let _e8661 = vec2<i32>((_e8652 - (i32(floor((f32(_e8652) / f32(_e8646.x)))) * _e8646.x)), (_e8652 / _e8646.x));
                    let _e8664 = vec3<i32>(_e8661.x, _e8661.y, 0i);
                    let _e8667 = textureLoad(u_layer_tex_0_image, _e8664.xy, _e8664.z);
                    local_248 = _e8667;
                    let _e8668 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e8671 = local_243;
                    let _e8674 = vec2<i32>(vec2<i32>(_e8668).x, _e8671.y);
                    let _e8675 = textureDimensions(u_layer_tex_0_image, 0i);
                    let _e8680 = vec2<i32>(_e8674.x, vec2<i32>(_e8675).y);
                    local_243 = _e8680;
                    let _e8686 = (((_e8633.y * _e8680.x) + _e8633.x) + 4i);
                    let _e8695 = vec2<i32>((_e8686 - (i32(floor((f32(_e8686) / f32(_e8680.x)))) * _e8680.x)), (_e8686 / _e8680.x));
                    let _e8698 = vec3<i32>(_e8695.x, _e8695.y, 0i);
                    let _e8701 = textureLoad(u_layer_tex_0_image, _e8698.xy, _e8698.z);
                    local_249 = _e8701;
                    let _e8702 = local_246;
                    if (_e8702 == 2i) {
                        let _e8704 = local_247;
                        let _e8705 = _e8704.xy;
                        local_250 = _e8705;
                        let _e8707 = (_e8704.zw - _e8705);
                        local_251 = _e8707;
                        let _e8708 = dot(_e8707, _e8707);
                        local_252 = _e8708;
                        if (_e8708 > 0.0000000001f) {
                            let _e8710 = local_1494;
                            let _e8711 = local_250;
                            let _e8713 = local_251;
                            let _e8715 = local_252;
                            local_253 = (dot((_e8710 - _e8711), _e8713) / _e8715);
                        } else {
                            local_253 = 0f;
                        }
                        let _e8717 = local_1495;
                        let _e8718 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e8721 = local_242;
                        let _e8724 = vec2<i32>(vec2<i32>(_e8718).x, _e8721.y);
                        let _e8725 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e8730 = vec2<i32>(_e8724.x, vec2<i32>(_e8725).y);
                        local_242 = _e8730;
                        let _e8736 = (((_e8717.y * _e8730.x) + _e8717.x) + 5i);
                        let _e8745 = vec2<i32>((_e8736 - (i32(floor((f32(_e8736) / f32(_e8730.x)))) * _e8730.x)), (_e8736 / _e8730.x));
                        let _e8748 = vec3<i32>(_e8745.x, _e8745.y, 0i);
                        let _e8751 = textureLoad(u_layer_tex_0_image, _e8748.xy, _e8748.z);
                        let _e8752 = local_253;
                        local_254 = _e8752;
                        local_255 = _e8751.x;
                        switch bitcast<i32>(0u) {
                            default: {
                                let _e8755 = local_255;
                                let _e8757 = i32((_e8755 + 0.5f));
                                local_239 = _e8757;
                                if (_e8757 == 1i) {
                                    let _e8759 = local_254;
                                    local_238 = fract(_e8759);
                                    break;
                                }
                                let _e8761 = local_239;
                                if (_e8761 == 2i) {
                                    let _e8763 = local_254;
                                    let _e8767 = (_e8763 - (floor((_e8763 / 2f)) * 2f));
                                    local_240 = _e8767;
                                    if (_e8767 < 0f) {
                                        let _e8769 = local_240;
                                        local_241 = (_e8769 + 2f);
                                    } else {
                                        let _e8771 = local_240;
                                        local_241 = _e8771;
                                    }
                                    let _e8772 = local_241;
                                    local_238 = (1f - abs((_e8772 - 1f)));
                                    break;
                                }
                                let _e8776 = local_254;
                                local_238 = clamp(_e8776, 0f, 1f);
                                break;
                            }
                        }
                        let _e8778 = local_238;
                        let _e8779 = local_248;
                        let _e8780 = local_249;
                        local_191 = mix(_e8779, _e8780, vec4(_e8778));
                        local_190 = 1f;
                        break;
                    }
                    let _e8783 = local_246;
                    if (_e8783 == 3i) {
                        let _e8785 = local_1494;
                        let _e8786 = local_247;
                        local_256 = (length((_e8785 - _e8786.xy)) / max(abs(_e8786.z), 0.000015258789f));
                        local_257 = _e8786.w;
                        switch bitcast<i32>(0u) {
                            default: {
                                let _e8796 = local_257;
                                let _e8798 = i32((_e8796 + 0.5f));
                                local_235 = _e8798;
                                if (_e8798 == 1i) {
                                    let _e8800 = local_256;
                                    local_234 = fract(_e8800);
                                    break;
                                }
                                let _e8802 = local_235;
                                if (_e8802 == 2i) {
                                    let _e8804 = local_256;
                                    let _e8808 = (_e8804 - (floor((_e8804 / 2f)) * 2f));
                                    local_236 = _e8808;
                                    if (_e8808 < 0f) {
                                        let _e8810 = local_236;
                                        local_237 = (_e8810 + 2f);
                                    } else {
                                        let _e8812 = local_236;
                                        local_237 = _e8812;
                                    }
                                    let _e8813 = local_237;
                                    local_234 = (1f - abs((_e8813 - 1f)));
                                    break;
                                }
                                let _e8817 = local_256;
                                local_234 = clamp(_e8817, 0f, 1f);
                                break;
                            }
                        }
                        let _e8819 = local_234;
                        let _e8820 = local_248;
                        let _e8821 = local_249;
                        local_191 = mix(_e8820, _e8821, vec4(_e8819));
                        local_190 = 1f;
                        break;
                    }
                    let _e8824 = local_246;
                    if (_e8824 == 6i) {
                        let _e8826 = local_1494;
                        let _e8827 = local_247;
                        let _e8829 = (_e8826 - _e8827.xy);
                        local_258 = ((atan2(_e8829.y, _e8829.x) - _e8827.z) * 0.15915494f);
                        local_259 = _e8827.w;
                        switch bitcast<i32>(0u) {
                            default: {
                                let _e8838 = local_259;
                                let _e8840 = i32((_e8838 + 0.5f));
                                local_231 = _e8840;
                                if (_e8840 == 1i) {
                                    let _e8842 = local_258;
                                    local_230 = fract(_e8842);
                                    break;
                                }
                                let _e8844 = local_231;
                                if (_e8844 == 2i) {
                                    let _e8846 = local_258;
                                    let _e8850 = (_e8846 - (floor((_e8846 / 2f)) * 2f));
                                    local_232 = _e8850;
                                    if (_e8850 < 0f) {
                                        let _e8852 = local_232;
                                        local_233 = (_e8852 + 2f);
                                    } else {
                                        let _e8854 = local_232;
                                        local_233 = _e8854;
                                    }
                                    let _e8855 = local_233;
                                    local_230 = (1f - abs((_e8855 - 1f)));
                                    break;
                                }
                                let _e8859 = local_258;
                                local_230 = clamp(_e8859, 0f, 1f);
                                break;
                            }
                        }
                        let _e8861 = local_230;
                        let _e8862 = local_248;
                        let _e8863 = local_249;
                        local_191 = mix(_e8862, _e8863, vec4(_e8861));
                        local_190 = 1f;
                        break;
                    }
                    let _e8866 = local_246;
                    if (_e8866 == 4i) {
                        let _e8868 = local_1495;
                        let _e8869 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e8872 = local_229;
                        let _e8875 = vec2<i32>(vec2<i32>(_e8869).x, _e8872.y);
                        let _e8876 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e8881 = vec2<i32>(_e8875.x, vec2<i32>(_e8876).y);
                        local_229 = _e8881;
                        let _e8887 = (((_e8868.y * _e8881.x) + _e8868.x) + 3i);
                        let _e8896 = vec2<i32>((_e8887 - (i32(floor((f32(_e8887) / f32(_e8881.x)))) * _e8881.x)), (_e8887 / _e8881.x));
                        let _e8899 = vec3<i32>(_e8896.x, _e8896.y, 0i);
                        let _e8902 = textureLoad(u_layer_tex_0_image, _e8899.xy, _e8899.z);
                        local_260 = _e8902;
                        let _e8903 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e8906 = local_228;
                        let _e8909 = vec2<i32>(vec2<i32>(_e8903).x, _e8906.y);
                        let _e8910 = textureDimensions(u_layer_tex_0_image, 0i);
                        let _e8915 = vec2<i32>(_e8909.x, vec2<i32>(_e8910).y);
                        local_228 = _e8915;
                        let _e8921 = (((_e8868.y * _e8915.x) + _e8868.x) + 5i);
                        let _e8930 = vec2<i32>((_e8921 - (i32(floor((f32(_e8921) / f32(_e8915.x)))) * _e8915.x)), (_e8921 / _e8915.x));
                        let _e8933 = vec3<i32>(_e8930.x, _e8930.y, 0i);
                        let _e8936 = textureLoad(u_layer_tex_0_image, _e8933.xy, _e8933.z);
                        local_261 = _e8936;
                        let _e8937 = local_1494;
                        let _e8940 = vec3<f32>(_e8937.x, _e8937.y, 1f);
                        local_262 = _e8940;
                        let _e8941 = local_247;
                        local_263 = dot(_e8940, vec3<f32>(_e8941.x, _e8941.y, _e8941.z));
                        local_264 = _e8936.z;
                        switch bitcast<i32>(0u) {
                            default: {
                                let _e8949 = local_264;
                                let _e8951 = i32((_e8949 + 0.5f));
                                local_225 = _e8951;
                                if (_e8951 == 1i) {
                                    let _e8953 = local_263;
                                    local_224 = fract(_e8953);
                                    break;
                                }
                                let _e8955 = local_225;
                                if (_e8955 == 2i) {
                                    let _e8957 = local_263;
                                    let _e8961 = (_e8957 - (floor((_e8957 / 2f)) * 2f));
                                    local_226 = _e8961;
                                    if (_e8961 < 0f) {
                                        let _e8963 = local_226;
                                        local_227 = (_e8963 + 2f);
                                    } else {
                                        let _e8965 = local_226;
                                        local_227 = _e8965;
                                    }
                                    let _e8966 = local_227;
                                    local_224 = (1f - abs((_e8966 - 1f)));
                                    break;
                                }
                                let _e8970 = local_263;
                                local_224 = clamp(_e8970, 0f, 1f);
                                break;
                            }
                        }
                        let _e8972 = local_224;
                        let _e8973 = local_261;
                        let _e8976 = local_262;
                        let _e8977 = local_260;
                        local_265 = dot(_e8976, vec3<f32>(_e8977.x, _e8977.y, _e8977.z));
                        local_266 = _e8973.w;
                        switch bitcast<i32>(0u) {
                            default: {
                                let _e8985 = local_266;
                                let _e8987 = i32((_e8985 + 0.5f));
                                local_221 = _e8987;
                                if (_e8987 == 1i) {
                                    let _e8989 = local_265;
                                    local_220 = fract(_e8989);
                                    break;
                                }
                                let _e8991 = local_221;
                                if (_e8991 == 2i) {
                                    let _e8993 = local_265;
                                    let _e8997 = (_e8993 - (floor((_e8993 / 2f)) * 2f));
                                    local_222 = _e8997;
                                    if (_e8997 < 0f) {
                                        let _e8999 = local_222;
                                        local_223 = (_e8999 + 2f);
                                    } else {
                                        let _e9001 = local_222;
                                        local_223 = _e9001;
                                    }
                                    let _e9002 = local_223;
                                    local_220 = (1f - abs((_e9002 - 1f)));
                                    break;
                                }
                                let _e9006 = local_265;
                                local_220 = clamp(_e9006, 0f, 1f);
                                break;
                            }
                        }
                        let _e9008 = local_220;
                        let _e9009 = local_261;
                        let _e9013 = local_247;
                        let _e9017 = local_260;
                        local_267 = vec2<f32>((_e8972 * _e8973.x), (_e9008 * _e9009.y));
                        local_268 = i32((_e9013.w + 0.5f));
                        local_269 = i32((_e9017.w + 0.5f));
                        switch bitcast<i32>(0u) {
                            default: {
                                let _e9022 = local_269;
                                if (_e9022 == 1i) {
                                    let _e9024 = textureDimensions(u_image_tex_0_image, 0i);
                                    let _e9027 = local_219;
                                    let _e9031 = vec3<i32>(vec2<i32>(_e9024).x, _e9027.y, _e9027.z);
                                    let _e9032 = textureDimensions(u_image_tex_0_image, 0i);
                                    let _e9038 = vec3<i32>(_e9031.x, vec2<i32>(_e9032).y, _e9031.z);
                                    let _e9039 = textureDimensions(u_image_tex_0_image, 0i);
                                    let _e9045 = vec3<i32>(_e9038.x, _e9038.y, vec2<i32>(_e9039).y);
                                    local_219 = _e9045;
                                    let _e9046 = _e9045.xy;
                                    let _e9047 = local_267;
                                    let _e9052 = clamp(vec2<i32>((_e9047 * vec2<f32>(_e9046))), vec2<i32>(0i, 0i), (_e9046 - vec2<i32>(1i, 1i)));
                                    let _e9053 = local_268;
                                    let _e9056 = vec4<i32>(_e9052.x, _e9052.y, _e9053, 0i);
                                    let _e9057 = _e9056.xyz;
                                    let _e9064 = textureLoad(u_image_tex_0_image, vec2<i32>(_e9057.x, _e9057.y), i32(_e9057.z), _e9056.w);
                                    local_218 = _e9064;
                                    break;
                                }
                                let _e9065 = local_267;
                                let _e9066 = local_268;
                                let _e9070 = vec3<f32>(_e9065.x, _e9065.y, f32(_e9066));
                                let _e9076 = textureSample(u_image_tex_0_image, u_image_tex_0_sampler, vec2<f32>(_e9070.x, _e9070.y), i32(_e9070.z));
                                local_218 = _e9076;
                                break;
                            }
                        }
                        let _e9077 = local_218;
                        local_191 = _e9077;
                        local_190 = 0f;
                        break;
                    }
                    local_191 = vec4<f32>(1f, 0f, 1f, 1f);
                    local_190 = 0f;
                    break;
                }
            }
            let _e9078 = local_190;
            let _e9079 = local_191;
            let _e9080 = v_tint_0_1;
            let _e9081 = (_e9079 * _e9080);
            let _e9082 = local_1488;
            let _e9084 = (_e9081.w * _e9082);
            let _e9086 = (_e9081.xyz * _e9084);
            local_1497 = vec4<f32>(_e9086.x, _e9086.y, _e9086.z, _e9084);
            if (_e9078 > 0.5f) {
                let _e9092 = local_1497;
                local_1498 = _e9092;
                switch bitcast<i32>(0u) {
                    default: {
                        let _e9094 = local_1498;
                        local_214 = _e9094.w;
                        if (_e9094.w <= 0f) {
                            local_215 = true;
                        } else {
                            let _e9098 = PushConstants_0_.dither_scale_0_;
                            local_215 = (_e9098 <= 0f);
                        }
                        let _e9100 = local_215;
                        if _e9100 {
                            let _e9101 = local_1498;
                            local_213 = _e9101;
                            break;
                        }
                        let _e9102 = local_1498;
                        let _e9103 = _e9102.xyz;
                        local_216 = _e9103;
                        let _e9105 = max(_e9103.x, 0f);
                        local_210 = _e9105;
                        if (_e9105 <= 0.0031308f) {
                            let _e9107 = local_210;
                            local_209 = (_e9107 * 12.92f);
                        } else {
                            let _e9109 = local_210;
                            local_209 = ((1.055f * pow(_e9109, 0.41666666f)) - 0.055f);
                        }
                        let _e9113 = local_209;
                        let _e9114 = local_216;
                        let _e9116 = max(_e9114.y, 0f);
                        local_211 = _e9116;
                        if (_e9116 <= 0.0031308f) {
                            let _e9118 = local_211;
                            local_208 = (_e9118 * 12.92f);
                        } else {
                            let _e9120 = local_211;
                            local_208 = ((1.055f * pow(_e9120, 0.41666666f)) - 0.055f);
                        }
                        let _e9124 = local_208;
                        let _e9125 = local_216;
                        let _e9127 = max(_e9125.z, 0f);
                        local_212 = _e9127;
                        if (_e9127 <= 0.0031308f) {
                            let _e9129 = local_212;
                            local_207 = (_e9129 * 12.92f);
                        } else {
                            let _e9131 = local_212;
                            local_207 = ((1.055f * pow(_e9131, 0.41666666f)) - 0.055f);
                        }
                        let _e9135 = local_207;
                        let _e9137 = gl_FragCoord_1;
                        let _e9144 = local_214;
                        let _e9147 = PushConstants_0_.dither_scale_0_;
                        let _e9152 = clamp((vec3<f32>(_e9113, _e9124, _e9135) + vec3(((fract((52.982918f * fract(dot(_e9137.xy, vec2<f32>(0.06711056f, 0.00583715f))))) - 0.5f) * (clamp(_e9144, 0f, 1f) * _e9147)))), vec3<f32>(0f, 0f, 0f), vec3<f32>(1f, 1f, 1f));
                        local_217 = _e9152;
                        local_204 = _e9152.x;
                        if (_e9152.x <= 0.04045f) {
                            let _e9155 = local_204;
                            local_203 = (_e9155 * 0.07739938f);
                        } else {
                            let _e9157 = local_204;
                            local_203 = pow(((_e9157 + 0.055f) * 0.94786733f), 2.4f);
                        }
                        let _e9161 = local_203;
                        let _e9162 = local_217;
                        local_205 = _e9162.y;
                        if (_e9162.y <= 0.04045f) {
                            let _e9165 = local_205;
                            local_202 = (_e9165 * 0.07739938f);
                        } else {
                            let _e9167 = local_205;
                            local_202 = pow(((_e9167 + 0.055f) * 0.94786733f), 2.4f);
                        }
                        let _e9171 = local_202;
                        let _e9172 = local_217;
                        local_206 = _e9172.z;
                        if (_e9172.z <= 0.04045f) {
                            let _e9175 = local_206;
                            local_201 = (_e9175 * 0.07739938f);
                        } else {
                            let _e9177 = local_206;
                            local_201 = pow(((_e9177 + 0.055f) * 0.94786733f), 2.4f);
                        }
                        let _e9181 = local_201;
                        let _e9182 = vec3<f32>(_e9161, _e9171, _e9181);
                        let _e9183 = local_214;
                        local_213 = vec4<f32>(_e9182.x, _e9182.y, _e9182.z, _e9183);
                        break;
                    }
                }
                let _e9188 = local_213;
                local_1485 = _e9188;
            } else {
                let _e9189 = local_1497;
                local_1485 = _e9189;
            }
            let _e9191 = PushConstants_0_.mask_output_0_;
            if (_e9191 != 0i) {
                let _e9193 = local_1485;
                local_1485 = vec4(_e9193.w);
            } else {
                let _e9197 = PushConstants_0_.output_srgb_0_;
                if (_e9197 != 0i) {
                    let _e9199 = local_1485;
                    local_1499 = _e9199;
                    switch bitcast<i32>(0u) {
                        default: {
                            let _e9201 = local_1499;
                            local_199 = _e9201.w;
                            if (_e9201.w <= 0f) {
                                local_198 = vec4<f32>(0f, 0f, 0f, 0f);
                                break;
                            }
                            let _e9204 = local_1499;
                            let _e9206 = local_199;
                            let _e9208 = (_e9204.xyz * (1f / _e9206));
                            local_200 = _e9208;
                            let _e9210 = max(_e9208.x, 0f);
                            local_195 = _e9210;
                            if (_e9210 <= 0.0031308f) {
                                let _e9212 = local_195;
                                local_194 = (_e9212 * 12.92f);
                            } else {
                                let _e9214 = local_195;
                                local_194 = ((1.055f * pow(_e9214, 0.41666666f)) - 0.055f);
                            }
                            let _e9218 = local_194;
                            let _e9219 = local_200;
                            let _e9221 = max(_e9219.y, 0f);
                            local_196 = _e9221;
                            if (_e9221 <= 0.0031308f) {
                                let _e9223 = local_196;
                                local_193 = (_e9223 * 12.92f);
                            } else {
                                let _e9225 = local_196;
                                local_193 = ((1.055f * pow(_e9225, 0.41666666f)) - 0.055f);
                            }
                            let _e9229 = local_193;
                            let _e9230 = local_200;
                            let _e9232 = max(_e9230.z, 0f);
                            local_197 = _e9232;
                            if (_e9232 <= 0.0031308f) {
                                let _e9234 = local_197;
                                local_192 = (_e9234 * 12.92f);
                            } else {
                                let _e9236 = local_197;
                                local_192 = ((1.055f * pow(_e9236, 0.41666666f)) - 0.055f);
                            }
                            let _e9240 = local_192;
                            let _e9242 = local_199;
                            let _e9243 = (vec3<f32>(_e9218, _e9229, _e9240) * _e9242);
                            local_198 = vec4<f32>(_e9243.x, _e9243.y, _e9243.z, _e9242);
                            break;
                        }
                    }
                    let _e9248 = local_198;
                    local_1485 = _e9248;
                }
            }
            let _e9249 = local_1485;
            _S118_ = _e9249;
            break;
        }
    }
    let _e9250 = _S118_;
    entryPointParam_main_frag_color_0_ = _e9250;
    return;
}

@fragment 
fn main(@builtin(position) gl_FragCoord: vec4<f32>, @location(1) v_texcoord_0_: vec2<f32>, @location(3) @interpolate(flat) v_glyph_0_: vec4<i32>, @location(2) @interpolate(flat) v_banding_0_: vec4<f32>, @location(4) v_tint_0_: vec4<f32>) -> @location(0) vec4<f32> {
    gl_FragCoord_1 = gl_FragCoord;
    v_texcoord_0_1 = v_texcoord_0_;
    v_glyph_0_1 = v_glyph_0_;
    v_banding_0_1 = v_banding_0_;
    v_tint_0_1 = v_tint_0_;
    main_1();
    let _e11 = entryPointParam_main_frag_color_0_;
    return _e11;
}
