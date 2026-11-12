#version 140

in highp vec4 var_position;
in mediump vec3 var_normal;
in mediump vec2 var_texcoord0;
in mediump vec4 var_light;

out vec4 out_fragColor;

uniform mediump sampler2D tex0;

uniform fs_uniforms
{
    mediump vec4 tint;
    mediump vec4 skin_offset;
};

void main()
{
    // Shift UV for 24 hull skins; glTF V=0 is top, so moving down rows subtracts V in GL space
    vec2 uv = vec2(var_texcoord0.x + skin_offset.x, var_texcoord0.y - skin_offset.y);
    vec4 base = texture(tex0, uv);

    vec3 n = normalize(var_normal);
    vec3 l = normalize(var_light.xyz);
    float ndl = max(dot(n, l), 0.0);
    // Hemisphere + key light + subtle rim for crisp low-poly readability
    vec3 view_dir = normalize(-var_position.xyz);
    float rim = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0) * 0.22;
    float light_factor = clamp(0.38 + ndl * 0.68 + rim + skin_offset.z, 0.0, 1.4);

    vec3 flash = max(tint.rgb - vec3(1.0), vec3(0.0));
    vec3 lit = base.rgb * min(tint.rgb, vec3(1.0)) * light_factor + flash;
    out_fragColor = vec4(lit, base.a * tint.w);
}
