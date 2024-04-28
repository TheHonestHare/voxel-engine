const vertices = array<vec2<f32>,4>(
    vec2<f32>(-1.0, 1.0),
    vec2<f32>(-1.0,-1.0),
    vec2<f32>( 1.0, 1.0),
    vec2<f32>( 1.0,-1.0),
);

@group(0) @binding(0) var screen_tex: texture_2d<f32>;

@vertex fn vert_main(@builtin(vertex_index) index: u32) -> @builtin(position) vec4<f32> {
    let vertices1 = vertices;
    return vec4<f32>(vertices1[index], 0., 1.);
}

@fragment fn frag_main(@builtin(position) coords: vec4<f32>) -> @location(0) vec4<f32> {
    return vec4<f32>(textureLoad(screen_tex, vec2<u32>(coords.xy), 0));
}