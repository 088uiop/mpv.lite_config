/*
LICENSE:
  --- RAW ver.
  http://avisynth.nl/index.php/GrainFactory3
*/

//!PARAM STR_G1
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 30.0
6.0

//!PARAM STR_G2
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 30.0
5.0

//!PARAM STR_G3
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 30.0
4.0

//!PARAM SIZE_G1
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 4.0
1.2

//!PARAM SIZE_G2
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 4.0
1.0

//!PARAM SIZE_G3
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 4.0
0.8

//!PARAM TH1
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 255.0
24.0

//!PARAM TH2
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 255.0
56.0

//!PARAM TH3
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 255.0
128.0

//!PARAM TH4
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 255.0
160.0

//!PARAM STR_ALL
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!HOOK NATIVE
//!BIND HOOKED
//!SAVE NOISE_BASE
//!DESC [kGrainFactory_RT] Gen Base Gauss Noise
//!WHEN STR_ALL

float permute(float x) {
    x = (34.0 * x + 1.0) * x;
    return fract(x * 1.0/289.0) * 289.0;
}

float seed(vec2 pos) {
    const float phi = 1.61803398874989;
    vec3 m = vec3(fract(phi * pos), random) + vec3(1.0);
    return permute(permute(m.x) + m.y) + m.z;
}

float rand(inout float state) {
    state = permute(state);
    return fract(state * 1.0/41.0);
}

float rand_gaussian(inout float state) {
    const float a0 = 0.151015505647689;
    const float a1 = -0.5303572634357367;
    const float a2 = 1.365020122861334;
    const float b0 = 0.132089632343748;
    const float b1 = -0.7607324991323768;
    float p = 0.95 * rand(state) + 0.025;
    float q = p - 0.5;
    float r = q * q;
    float g = q * (a2 + (a1 * r + a0) / (r*r + b1*r + b0));
    g *= 0.255121822830526;
    return g;
}

vec4 hook() {
    vec2 pos = HOOKED_pos * HOOKED_size;
    float state = seed(pos);
    float noise = rand_gaussian(state);
    return vec4(0.5 + noise * 0.5, 0.0, 0.0, 1.0);
}

//!HOOK OUTPUT
//!BIND NOISE_BASE
//!SAVE GRAIN_LARGE
//!DESC [kGrainFactory_RT] Large Grain
//!WHEN STR_ALL

vec4 hook() {
    float sum = 0.0;
    float weight = 0.0;
    float sigma = max(SIZE_G1 - 0.5, 0.5);
    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            float d = sqrt(float(x*x + y*y));
            float w = exp(-d * d / (2.0 * sigma * sigma));
            sum += NOISE_BASE_texOff(vec2(x, y)).x * w;
            weight += w;
        }
    }
    float blurred = sum / weight;
    float grain = (blurred - 0.5) * 2.0;
    grain *= STR_G1 / 100.0;
    return vec4(grain * 0.5 + 0.5, 0.0, 0.0, 1.0);
}

//!HOOK OUTPUT
//!BIND NOISE_BASE
//!SAVE GRAIN_MEDIUM
//!DESC [kGrainFactory_RT] Medium Grain
//!WHEN STR_ALL

vec4 hook() {
    float sum = 0.0;
    float weight = 0.0;
    float sigma = max(SIZE_G2 - 0.5, 0.3);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float d = sqrt(float(x*x + y*y));
            float w = exp(-d * d / (2.0 * sigma * sigma));
            sum += NOISE_BASE_texOff(vec2(x, y)).x * w;
            weight += w;
        }
    }
    float blurred = sum / weight;
    float grain = (blurred - 0.5) * 2.0;
    grain *= STR_G2 / 100.0;
    return vec4(grain * 0.5 + 0.5, 0.0, 0.0, 1.0);
}

//!HOOK OUTPUT
//!BIND NOISE_BASE
//!SAVE GRAIN_SMALL
//!DESC [kGrainFactory_RT] Small Grain
//!WHEN STR_ALL

vec4 hook() {
    float noise = NOISE_BASE_texOff(vec2(0)).x;
    float grain;
    if (SIZE_G3 >= 0.9) {
        grain = (noise - 0.5) * 2.0;
    } else {
        float sum = 0.0;
        float weight = 0.0;
        float sigma = 0.3;
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                float d = sqrt(float(x*x + y*y));
                float w = exp(-d * d / (2.0 * sigma * sigma));
                sum += NOISE_BASE_texOff(vec2(x, y)).x * w;
                weight += w;
            }
        }
        grain = (sum / weight - 0.5) * 2.0;
    }
    grain *= STR_G3 / 100.0;
    return vec4(grain * 0.5 + 0.5, 0.0, 0.0, 1.0);
}

//!HOOK OUTPUT
//!BIND HOOKED
//!BIND GRAIN_LARGE
//!BIND GRAIN_MEDIUM
//!BIND GRAIN_SMALL
//!DESC [kGrainFactory_RT] Blend & Apply Grain
//!WHEN STR_ALL

vec4 hook() {
    vec4 color = HOOKED_tex(HOOKED_pos);
    float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));

    float g1 = (GRAIN_LARGE_tex(HOOKED_pos).x - 0.5) * 2.0;
    float g2 = (GRAIN_MEDIUM_tex(HOOKED_pos).x - 0.5) * 2.0;
    float g3 = (GRAIN_SMALL_tex(HOOKED_pos).x - 0.5) * 2.0;

    float th1 = TH1 / 255.0;
    float th2 = TH2 / 255.0;
    float th3 = TH3 / 255.0;
    float th4 = TH4 / 255.0;

    float mask1 = clamp((luma - th1) / max(th2 - th1, 0.0001), 0.0, 1.0);
    float mask2 = clamp((luma - th3) / max(th4 - th3, 0.0001), 0.0, 1.0);

    float grain12 = mix(g1, g2, mask1);
    float grain = mix(grain12, g3, mask2);

    float offset = grain * STR_ALL;
    vec3 result = color.rgb - vec3(offset);

    return vec4(clamp(result, 0.0, 1.0), color.a);
}