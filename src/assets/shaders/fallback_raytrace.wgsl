@group(1) @binding(0) var screen_tex: texture_storage_2d<rgba8unorm, write>;

struct Camera {
    position: vec3<f32>,
    orient: vec3<f32>
};

@group(0) @binding(0) var<uniform> camera: Camera;

@compute @workgroup_size(8,8,1)
fn main(@builtin(local_invocation_id) local_id: vec3<u32>,
        @builtin(workgroup_id) workgroup_id: vec3<u32>
) { 
    let coords = workgroup_id.xy * 8 + local_id.xy;
    let dimensions = textureDimensions(screen_tex);
    if(coords.x <= dimensions.x && coords.y <= dimensions.y) {
        textureStore(screen_tex, coords, vec4<f32>(vec2<f32>(dimensions.xy),0.,1.));
    }
}