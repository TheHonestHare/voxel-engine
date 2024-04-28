struct Camera {
    position: vec3<f32>,  //camera position
    plane_X: vec3<f32>, // vec from screen origin to right w.r.t orientation, normalized
    plane_Y: vec3<f32>, // vec from screen origin to top of screen w.r.t. orientation, normalized
    lookat: vec3<f32>, //vector from eye to screen origin, scaled by screen_dist
};

@group(0) @binding(0) var<uniform> camera: Camera;
@group(1) @binding(0) var screen_tex: texture_storage_2d<rgba8unorm, write>;

const max_dist: f32 = 1000.;

const pi: f32 = 3.14159265358979323846264338327950288419716939937510;

@compute @workgroup_size(8,8,1)
fn main(@builtin(local_invocation_id) local_id: vec3<u32>,
        @builtin(workgroup_id) workgroup_id: vec3<u32>
) { 
    let coords = workgroup_id.xy * 8u + local_id.xy;
    let dimensions = textureDimensions(screen_tex);
    if(coords.x <= dimensions.x && coords.y <= dimensions.y) {
        let col = raytrace(vec2<f32>(coords), vec2<f32>(dimensions.xy));
        textureStore(screen_tex, coords, col);
    }
}

fn raytrace(coords: vec2<f32>, res: vec2<f32>) -> vec4<f32> {

    var uv: vec2<f32> = (2. * coords - res.xy) / res.y;
    var col: vec3<f32> = vec3<f32>(0.,0.,0.);

    uv.y = -uv.y; // coordinates of texture start at top left, going down is +y but thats confusing for me

    let ro = camera.position;
    // check if you supposed to add or sub
    let rd = normalize(camera.lookat + (camera.plane_X * uv.x + camera.plane_Y * uv.y));

    var w: vec3<f32> = ro;
    var t: f32 = 0.;
    var yes = dda(ro, rd);
    col = yes.col;

    return vec4<f32>(col, 1.0);
}

struct OutDDA {
    dist: f32,
    col: vec3<f32>,
}
//dir must be normalized
fn dda(origin: vec3<f32>, dir: vec3<f32>) -> OutDDA {
    let step_len: vec3<f32> = 1.0 / abs(dir);
    let step_mask = dir > vec3<f32>(0.0);
    let step_dir = select(vec3<f32>(-1), vec3<f32>(1), step_mask);

    let origin_floor = floor(origin);
    var curr_vox: vec3<i32> = vec3<i32>(origin_floor);
    var ray_len: vec3<f32> = select(origin - origin_floor, origin_floor + 1.0 - origin, step_mask) * step_len;

    var t: f32;
    for(var i: i32 = 0; i < 500; i += 1) {
        if(min(ray_len.x, min(ray_len.y, ray_len.z)) == ray_len.x){
            curr_vox.x += i32(step_dir.x);
            ray_len.x += step_len.x;
            t = ray_len.x - step_len.x;
        }else if(min(ray_len.x, min(ray_len.y, ray_len.z)) == ray_len.y){
            curr_vox.y += i32(step_dir.y);
            ray_len.y += step_len.y;
            t = ray_len.y - step_len.y;
        }else if(min(ray_len.x, min(ray_len.y, ray_len.z)) == ray_len.z){
            curr_vox.z += i32(step_dir.z);
            ray_len.z += step_len.z;
            t = ray_len.z - step_len.z;
        }
        if(get_voxel(curr_vox) == 1) { return OutDDA(t, vec3<f32>(1.0)); }
    }
    return OutDDA(t, vec3<f32>(0.0));
}

fn get_voxel(pos: vec3<i32>) -> i32 {
    // smiley :)
    // if(all(pos == vec3<i32>(0))) { return 1; }
    // if(all(pos == vec3<i32>(0, 0, 3))) { return 1; }
    // if(all(pos == vec3<i32>(0,-2, 4))) { return 1; }
    // if(all(pos == vec3<i32>(0,-3, 3))) { return 1; }
    // if(all(pos == vec3<i32>(0,-3, 2))) { return 1; }
    // if(all(pos == vec3<i32>(0,-3, 1))) { return 1; }
    // if(all(pos == vec3<i32>(0,-3, 0))) { return 1; }
    // if(all(pos == vec3<i32>(0,-2,-1))) { return 1; }

    if(pos.x == 1 && pos.y == 1) {return 1;}
    return 0;
}

fn rot2d(ang: f32) -> mat2x2<f32> {
    let s = sin(ang);
    let c = cos(ang);
    return mat2x2<f32>(c, s, -s, c);
}