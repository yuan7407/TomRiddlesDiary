//
//  CoverShaders.metal
//  模块：Features/Book（界面层；SwiftUI 的 colorEffect 着色器）
//
//  文件职责：外屏旧书封面（计划 S 组）的三种材质——皮面、做旧的黄铜、磨损的烫金。
//
//  为什么用着色器、不用照片：一，照片素材有版权；二，程序生成的皮纹在任何分辨率下都是清楚的；
//  三，在 GPU 上每像素算一次，整屏 1398 × 2034 像素也不费事，翻封面时不掉帧。
//  所有颜色、颗粒大小从 Swift 那边传进来（唯一定义处是 `CoverLook`）；
//  这里出现的数字都是噪声算法本身的常数（哈希乘子、平滑曲线、法线放大倍数），注释里写了各自管什么。
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// ── 噪声 ──（算法常数：经典的 sin 哈希乘子）

static float hash1(float2 p, float seed) {
    return fract(sin(dot(p, float2(12.9898, 78.233)) + seed) * 43758.5453);
}

static float2 hash2(float2 p, float seed) {
    float2 q = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return fract(sin(q + seed) * 43758.5453);
}

static float valueNoise(float2 p, float seed) {
    float2 i = floor(p), f = fract(p);
    float a = hash1(i, seed), b = hash1(i + float2(1, 0), seed);
    float c = hash1(i + float2(0, 1), seed), d = hash1(i + float2(1, 1), seed);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// 四层叠起来的噪声：大起伏上带小起伏。
static float fbm(float2 p, float seed) {
    float v = 0.0, amplitude = 0.5;
    for (int k = 0; k < 4; k++) {
        v += amplitude * valueNoise(p, seed + float(k) * 17.0);
        p *= 2.03;
        amplitude *= 0.5;
    }
    return v;
}

/// 蜂窝噪声：到最近两个胞心的距离 (F1, F2)。F2 − F1 接近 0 的地方就是两颗皮粒之间的折痕。
static float2 cells(float2 p, float seed) {
    float2 i = floor(p), f = fract(p);
    float d1 = 8.0, d2 = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 g = float2(x, y);
            float2 r = g + hash2(i + g, seed) - f;
            float d = dot(r, r);
            if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
        }
    }
    return float2(sqrt(d1), sqrt(d2));
}

/// 皮面的高低：每颗皮粒中间鼓、边上是折痕；再叠一层更细的颗粒。坐标先被低频噪声扭一下，皮粒才不像蜂巢那样规整。
static float grainHeight(float2 p, float cell, float seed) {
    float2 q = p / cell;
    q += (float2(fbm(q * 0.35, seed + 3.0), fbm(q * 0.35, seed + 9.0)) - 0.5) * 0.9;
    float2 c = cells(q, seed);
    float crease = smoothstep(0.0, 0.34, c.y - c.x);
    float dome = 1.0 - c.x * 0.6;
    float2 c2 = cells(q * 2.7, seed + 41.0);
    float fine = smoothstep(0.0, 0.25, c2.y - c2.x);
    return crease * dome * 0.8 + fine * 0.2;
}

/// 光从左上方来（和纸、护角的影子同一个方向）。
constant float3 kLight = float3(-0.55, -0.7, 0.75);

// ── 皮面 ──

/// - size: 这块皮多大（点）；cell: 一颗皮粒多大（点）。
/// - grooveX: 书脊压槽的横坐标（点）；传负数就没有压槽（名牌那块小皮片用）。
/// - edgeWear: 离边多远以内会被磨旧（点）；mottle: 色块起伏的强弱。
[[ stitchable ]] half4 leather(float2 p, half4 color, float2 size, float cell, float seed,
                               half4 base, half4 lightTone, half4 creaseTone, half4 wornTone,
                               float grooveX, float edgeWear, float mottle) {
    // 法线：高度场在 x、y 方向各差 0.75 点的差分（2.2 是把起伏放大到看得见的倍数）。
    float h = grainHeight(p, cell, seed);
    float hx = grainHeight(p + float2(0.75, 0.0), cell, seed);
    float hy = grainHeight(p + float2(0.0, 0.75), cell, seed);
    float3 n = normalize(float3((h - hx) * 2.2, (h - hy) * 2.2, 1.0));
    float3 L = normalize(kLight);
    float diffuse = clamp(dot(n, L), 0.0, 1.0);
    float spec = pow(clamp(dot(n, normalize(L + float3(0, 0, 1))), 0.0, 1.0), 28.0);

    // 大片的明暗：参考图上的皮面浅一块深一块。
    float m = fbm(p / (size.x * 0.28), seed + 5.0);
    half3 col = mix(base.rgb, lightTone.rgb, half(smoothstep(0.35, 0.85, m) * mottle));
    // 折痕只压暗一点：参考图的皮纹是软的鼓粒，不是裂纹。
    col = mix(col, creaseTone.rgb, half((1.0 - smoothstep(0.0, 0.5, h)) * 0.4));
    col *= half(0.78 + 0.34 * diffuse);
    col += half3(spec * 0.06);
    // 一大片柔和的反光：像台灯照在皮面左上方（参考图左上与中间偏亮）。
    float2 sheenCenter = size * float2(0.38, 0.3);
    float sheen = exp(-length((p - sheenCenter) / size) * 3.2);
    col += half3(sheen * 0.07 * (0.6 + 0.4 * diffuse));

    // 边上被手磨旧：越靠边越灰，磨得不均匀。
    float edge = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
    float wear = (1.0 - smoothstep(0.0, edgeWear, edge)) * (0.45 + 0.55 * fbm(p * 0.08, seed + 13.0));
    col = mix(col, wornTone.rgb, half(wear * 0.65));

    // 暗角：中间受光，四周暗一点。
    float2 d = p / size - 0.5;
    col *= half(1.0 - 0.3 * smoothstep(0.25, 0.85, length(d * float2(1.0, 0.8))));

    // 书脊压槽：一道凹下去的暗线，右边那条棱被光照到。
    if (grooveX >= 0.0) {
        float g = p.x - grooveX;
        col *= half(1.0 - 0.5 * exp(-(g * g) / 6.0));
        col += half3(0.06 * exp(-((g - 3.0) * (g - 3.0)) / 3.0));
        // 压槽左边那条（书脊上）更旧一点
        col = mix(col, wornTone.rgb * 0.8h, half(0.18 * (1.0 - smoothstep(grooveX - 4.0, grooveX, p.x))));
    }
    return half4(col * color.a, color.a);
}

// ── 做旧的黄铜 ──

/// 在已经画好的黄铜（渐变 + 斜面光）上加：氧化斑、铜绿、细划痕、凸起处磨亮。只改颜色，不改透明度。
[[ stitchable ]] half4 agedBrass(float2 p, half4 color, float seed, half4 patina, half4 polished) {
    if (color.a < 0.002h) { return color; }
    half3 c = color.rgb / color.a;
    // 大片的发暗与铜绿
    float stain = smoothstep(0.38, 0.75, fbm(p * 0.07, seed));
    c = mix(c, patina.rgb, half(stain * 0.65));
    // 小的氧化斑点
    float spots = smoothstep(0.62, 0.78, fbm(p * 0.35, seed + 7.0));
    c = mix(c, patina.rgb * 0.7h, half(spots * 0.6));
    // 顺着一个方向的细划痕（把噪声在一个方向拉长）
    float2 r = float2(p.x * 0.8 + p.y * 0.6, -p.x * 0.6 + p.y * 0.8);
    float scratch = smoothstep(0.9, 0.97, valueNoise(r * float2(0.05, 1.6), seed + 3.0));
    c = mix(c, polished.rgb, half(scratch * 0.5));
    // 磨亮的地方：亮的更亮（凸起处总被摸）
    float lum = dot(float3(c), float3(0.3, 0.59, 0.11));
    c = mix(c, polished.rgb, half(smoothstep(0.62, 0.85, lum) * 0.35 * fbm(p * 0.12, seed + 11.0)));
    return half4(c * color.a, color.a);
}

// ── 磨损的烫金 ──

/// 金字上一点点磨掉的地方露出底下的黑皮：按噪声把透明度挖掉一些，颜色也深浅不一。
[[ stitchable ]] half4 wornGold(float2 p, half4 color, float seed, float wear) {
    if (color.a < 0.002h) { return color; }
    float n = fbm(p * 0.45, seed);
    float speck = smoothstep(0.1, 0.0, valueNoise(p * 1.7, seed + 5.0) - (1.0 - wear) * 0.9 + 0.05);
    float keep = 1.0 - wear * smoothstep(0.55, 0.75, n) - speck * 0.5;
    keep = clamp(keep, 0.15, 1.0);
    half3 c = color.rgb / color.a;
    c *= half(0.85 + 0.3 * fbm(p * 0.2, seed + 2.0));
    half a = color.a * half(keep);
    return half4(c * a, a);
}
