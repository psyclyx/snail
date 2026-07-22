#version 330

layout(std140) uniform SnailLinearResolveParams_std140
{
    int mode;
} pc;

uniform sampler2D SPIRV_Cross_Combinedu_dst_texu_dst_sampler;
uniform sampler2D SPIRV_Cross_Combinedu_linear_texu_linear_sampler;

in vec2 snail_io0;
layout(location = 0) out vec4 entryPointParam_fragmentMain;

void main()
{
    do
    {
        if (pc.mode == 0)
        {
            vec4 sampled = texture(SPIRV_Cross_Combinedu_dst_texu_dst_sampler, snail_io0);
            vec4 _194;
            do
            {
                float _198 = sampled.w;
                if (_198 <= 0.0)
                {
                    _194 = vec4(0.0);
                    break;
                }
                vec3 _205 = clamp(sampled.xyz * (1.0 / _198), vec3(0.0), vec3(1.0));
                float _214 = _205.x;
                float _221;
                if (_214 <= 0.040449999272823333740234375)
                {
                    _221 = _214 * 0.077399380505084991455078125;
                }
                else
                {
                    _221 = pow((_214 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
                }
                float _216 = _205.y;
                float _233;
                if (_216 <= 0.040449999272823333740234375)
                {
                    _233 = _216 * 0.077399380505084991455078125;
                }
                else
                {
                    _233 = pow((_216 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
                }
                float _218 = _205.z;
                float _245;
                if (_218 <= 0.040449999272823333740234375)
                {
                    _245 = _218 * 0.077399380505084991455078125;
                }
                else
                {
                    _245 = pow((_218 + 0.054999999701976776123046875) * 0.947867333889007568359375, 2.400000095367431640625);
                }
                _194 = vec4(vec3(_221, _233, _245) * _198, _198);
                break;
            } while(false);
            entryPointParam_fragmentMain = _194;
            break;
        }
        vec4 sampled_1 = texture(SPIRV_Cross_Combinedu_linear_texu_linear_sampler, snail_io0);
        vec4 _261;
        do
        {
            float _265 = sampled_1.w;
            if (_265 <= 0.0)
            {
                _261 = vec4(0.0);
                break;
            }
            vec3 _271 = sampled_1.xyz * (1.0 / _265);
            float _280 = max(_271.x, 0.0);
            float _289;
            if (_280 <= 0.003130800090730190277099609375)
            {
                _289 = _280 * 12.9200000762939453125;
            }
            else
            {
                _289 = (1.05499994754791259765625 * pow(_280, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
            }
            float _283 = max(_271.y, 0.0);
            float _301;
            if (_283 <= 0.003130800090730190277099609375)
            {
                _301 = _283 * 12.9200000762939453125;
            }
            else
            {
                _301 = (1.05499994754791259765625 * pow(_283, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
            }
            float _286 = max(_271.z, 0.0);
            float _313;
            if (_286 <= 0.003130800090730190277099609375)
            {
                _313 = _286 * 12.9200000762939453125;
            }
            else
            {
                _313 = (1.05499994754791259765625 * pow(_286, 0.4166666567325592041015625)) - 0.054999999701976776123046875;
            }
            _261 = vec4(vec3(_289, _301, _313) * _265, _265);
            break;
        } while(false);
        entryPointParam_fragmentMain = _261;
        break;
    } while(false);
}

