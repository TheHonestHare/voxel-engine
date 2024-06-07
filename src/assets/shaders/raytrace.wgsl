// TODO: make override
const BRICK_SIZE = 8;

struct Camera {
    position: vec3<f32>,  //camera position
    plane_X: vec3<f32>, // vec from screen origin to right w.r.t orientation, normalized
    plane_Y: vec3<f32>, // vec from screen origin to top of screen w.r.t. orientation, normalized
    lookat: vec3<f32>, //vector from eye to screen origin, scaled by screen_dist
};

struct WorldHeader {
    size: vec3<u32>,
}
// TODO: rename brick to bitmap or smth
alias Brick = array<u32, BRICK_SIZE * BRICK_SIZE * BRICK_SIZE / 32>;

struct Bricks {
    bits: array<Brick>,
}

@group(0) @binding(0) var<uniform> camera: Camera;
@group(1) @binding(0) var screen_tex: texture_storage_2d<rgba8unorm, write>;
@group(2) @binding(0) var<uniform> world_header: WorldHeader;
@group(2) @binding(1) var<storage, read> bitmasks: Bricks;

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
    // TODO: This MIGHT not have to be normalized
    let rd = normalize(camera.lookat + (camera.plane_X * uv.x + camera.plane_Y * uv.y));

    var yes = dda_brickmaps(ro, rd);
    col = yes.col;

    return vec4<f32>(col, 1.0);
}

struct OutDDA {
    dist: f32,
    col: vec3<f32>,
}
//dir must be normalized
fn dda(origin: vec3<f32>, dir: vec3<f32>) -> OutDDA {
    // how far along a ray will go for 1 unit step in each of the axis's
    let step_len: vec3<f32> = 1.0 / abs(dir);
    // checks the sign bit of dir; false if negative
    let step_mask = !vec3<bool>(bitcast<vec3<u32>>(dir) & vec3<u32>(0x80000000));
    // what direction to step voxels in
    let step_dir = select(vec3<f32>(-1), vec3<f32>(1), step_mask);

    let origin_floor = floor(origin);
    var curr_vox: vec3<i32> = vec3<i32>(origin_floor);
    var ray_len: vec3<f32> = select(origin - origin_floor, origin_floor + 1.0 - origin, step_mask) * step_len;
    var side: vec3<bool> = vec3<bool>(false);

    var t: f32;
    for(var i: i32 = 0; i < 500; i += 1) {
        if(min(ray_len.x, min(ray_len.y, ray_len.z)) == ray_len.x){
            curr_vox.x += i32(step_dir.x);
            ray_len.x += step_len.x;
            t = ray_len.x - step_len.x;
            side = vec3<bool>(true, false, false);
        }else if(min(ray_len.x, min(ray_len.y, ray_len.z)) == ray_len.y){
            curr_vox.y += i32(step_dir.y);
            ray_len.y += step_len.y;
            t = ray_len.y - step_len.y;
            side = vec3<bool>(false, true, false);
        }else if(min(ray_len.x, min(ray_len.y, ray_len.z)) == ray_len.z){
            curr_vox.z += i32(step_dir.z);
            ray_len.z += step_len.z;
            t = ray_len.z - step_len.z;
            side = vec3<bool>(false, false, true);
        }
        let curr = get_voxel(curr_vox);
        if(curr == 1) { return OutDDA(t, vec3<f32>(0.0)); }
        if(curr > 1) {
            if(side.x) { return OutDDA(t, floor(fract(vec3<f32>(origin.yz + t * dir.yz, 0.0)) * 8.0) / 8.0); };
            if(side.y) { return OutDDA(t, floor(fract(vec3<f32>(origin.xz + t * dir.xz, 0.0)) * 8.0) / 8.0); };
            return OutDDA(t, floor(fract(vec3<f32>(origin.xy + t * dir.xy, 0.0)) * 8.0) / 8.0);
        }
    }
    return OutDDA(t, vec3<f32>(0.0));
}

fn get_voxel(pos: vec3<i32>) -> i32 {
    const HALF_BRICK_SIZE = BRICK_SIZE / 2;
    if(any(pos < vec3i(0, 0, 0))) { return 1; }
    if(any(pos > vec3<i32>(world_header.size * BRICK_SIZE + 1))) { return 1;}
    let pos_u = vec3<u32>(pos);
    let pos_scaled = pos_u / BRICK_SIZE;
    let sub_brick_pos = pos_u - pos_scaled * BRICK_SIZE;
    // TODO: replace getting correct brick with an array of pointers and maybe get rid of modulo
    // TODO: this code looks brick size independant, actually will only work on 8 bc makes assumptions like 32 bits takes up half of a layer
    let bitmask = bitmasks.bits[dot(pos_scaled, vec3<u32>(1, BRICK_SIZE * BRICK_SIZE, BRICK_SIZE))][8 / (32 / BRICK_SIZE) * sub_brick_pos.y + u32(sub_brick_pos.z > (32 / BRICK_SIZE) - 1)];
    if(bool(bitmask & u32(1 << (HALF_BRICK_SIZE * sub_brick_pos.z + sub_brick_pos.x)))) { return (pos.x % HALF_BRICK_SIZE + pos.y % HALF_BRICK_SIZE / 2 + pos.z % HALF_BRICK_SIZE) + 2; }
    return 0;
}


// dir must be normalized (TODO: check if thats true)
fn dda_brickmaps(origin: vec3<f32>, dir: vec3<f32>) -> OutDDA {
    // how far along a ray will go for 1 unit step in each of the axis's
    let step_len: vec3<f32> = 1.0 / abs(dir);
    // checks the sign bit of dir; false if negative
    let step_mask = !vec3<bool>(bitcast<vec3<u32>>(dir) & vec3<u32>(0x80000000));
    // what direction to step voxels in
    let step_dir = select(vec3<f32>(-1), vec3<f32>(1), step_mask);

    let origin_floor = floor(origin);
    // TODO: decide if voxel coordinates will always be positive and maybe change to u32
    //       if always positive, this can just be vec3<i32>(origin)
    var ray_len: vec3<f32> = select(origin - floor(origin), ceil(origin) - origin, step_mask) * step_len;
    var side: vec3<bool> = vec3<bool>(false);
    var brick_coords: vec3<i32> = vec3<i32>(floor(origin / BRICK_SIZE));
    var brick: Brick;

    var t: f32 = 0;
    //currently scuffed near 0
    var curr_vox: vec3<i32> = abs(vec3<i32>(floor(origin))) % BRICK_SIZE;
    for(var i: u32 = 0; i < 500/8; i += 1) {
        if(!brick_exists(brick_coords)) { return OutDDA(0, vec3f(0.0)); }
        brick = get_brick(brick_coords);
        for(var j: u32 = 1; j < BRICK_SIZE * 3; j += 1) {
            if(any(curr_vox < vec3<i32>(0)) || any(curr_vox > vec3<i32>(BRICK_SIZE - 1))) { 
                brick_coords += vec3<i32>(side) * vec3<i32>(step_dir);
                curr_vox = select(curr_vox, BRICK_SIZE - select(vec3i(0), vec3i(1), curr_vox == vec3i(7)) - abs(curr_vox), side);
                break;
            }
            if(is_solid(brick, curr_vox)) { return OutDDA(0, colours[2]); }
            dda_step_brickmap(&ray_len, step_dir, step_len, &curr_vox, &side);
        }
    }
    
    return OutDDA(0, vec3<f32>(0.0));
}

fn brick_exists(pos: vec3<i32>) -> bool {
    return !(any(pos < vec3i(0, 0, 0)) || any(vec3<u32>(pos) >= world_header.size));
}

fn get_brick(pos: vec3<i32>) -> Brick {
    return bitmasks.bits[dot(pos, vec3<i32>(1, BRICK_SIZE * BRICK_SIZE, BRICK_SIZE))];
}

// https://www.shadertoy.com/view/4dX3zl
fn dda_step_brickmap(ray_len_ptr: ptr<function, vec3<f32>>, step_dir: vec3<f32>, step_len: vec3<f32>, curr_vox_ptr: ptr<function, vec3<i32>>, side_ptr: ptr<function, vec3<bool>>) {
    *side_ptr = (*ray_len_ptr).xyz <= min((*ray_len_ptr).yzx, (*ray_len_ptr).zxy);
    *curr_vox_ptr += vec3<i32>(*side_ptr) * vec3<i32>(step_dir);
    *ray_len_ptr += vec3<f32>(*side_ptr) * step_len;
}
/*
fn uv_face(ray_end_pos: vec3<f32>, side: vec3<bool>) -> vec2<f32> {

    if(side.x) { return vec3<f32>(fract(vec3<f32>(origin.yz + t * dir.yz), 0.0)); }
    if(side.y) { return vec3<f32>(fract(vec3<f32>(origin.xz + t * dir.xz), 0.0)); }
     { return vec3<f32>(fract(vec3<f32>(origin.xy + t * dir.xy), 0.0)); } // SIDE_Z
     
     
    return vec3<f32>(fract(vec3<f32>(origin.yz + t * dir.yz), 0.0));
}*/

fn is_solid(brick: Brick, curr_vox: vec3<i32>) -> bool {
    // TODO: remove this assert?
    if(any(curr_vox < vec3<i32>(0)) || any(curr_vox > vec3<i32>(BRICK_SIZE - 1))) { return false; }

    return bool(brick[8 / (32 / BRICK_SIZE) * u32(curr_vox.y) + u32(curr_vox.z > (32 / BRICK_SIZE) - 1)] & u32(1 << (BRICK_SIZE / 2 * u32(curr_vox.z) + u32(curr_vox.x))));
}

const colours = array<vec3<f32>, 11>(
    vec3<f32>(0.0,0.0,0.0),
    vec3<f32>(1.0,0.0,0.0),
    vec3<f32>(1.0,0.5,0.0),
    vec3<f32>(1.0,1.0,0.0),
    vec3<f32>(0.0,1.0,0.0),
    vec3<f32>(0.0,0.2,0.8),
    vec3<f32>(0.2,0.0,0.8),
    vec3<f32>(0.5,0.0,0.5),
    vec3<f32>(0.5,0.5,0.5),
    vec3<f32>(1.0,1.0,1.0),
    vec3<f32>(0.5,1.0,0.5),
);

fn rot2d(ang: f32) -> mat2x2<f32> {
    let s = sin(ang);
    let c = cos(ang);
    return mat2x2<f32>(c, s, -s, c);
}