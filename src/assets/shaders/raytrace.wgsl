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
// origin is the position scaled to size of voxel
// TODO: try removing curr_brick, might be slowing down
// TODO: implement empty brick skipping
// TODO: precompute masks to determine if any voxels exist in the path a ray could traverse
fn dda_brickmaps(origin: vec3<f32>, dir_raw: vec3<f32>) -> OutDDA {
    let dir = select(dir_raw, dir_raw + 0.0001, dir_raw == vec3<f32>(0));
    // how far along a ray will go for 1 unit step in each of the axis's
    let step_len: vec3<f32> = 1.0 / abs(dir);
    // checks the sign bit of dir; false if negative
    let step_mask = !vec3<bool>(bitcast<vec3<u32>>(dir) & vec3<u32>(0x80000000));
    // what direction to step in
    let step_dir = select(vec3<i32>(-1), vec3<i32>(1), step_mask);
    let origin_brick = origin / BRICK_SIZE;

    var pos_brick: vec3<i32> = vec3<i32>(floor(origin_brick));
    var curr_brick: i32;
    
    var ray_len_brick: vec3<f32> = select(origin_brick - floor(origin_brick), ceil(origin_brick) - origin_brick, step_mask) * step_len;
    var side_brick: vec3<bool> = side_mask(ray_len_brick);
    
    var t_brick: f32 = 0;
    while(t_brick < 200 / BRICK_SIZE) {
        if(!brick_exists(pos_brick)) { break; }
        curr_brick = get_brick(pos_brick);
        let intersect = select(origin_brick + dir * t_brick - vec3<f32>(pos_brick), origin_brick - vec3<f32>(pos_brick), all(floor(origin_brick) == vec3<f32>(pos_brick))) * BRICK_SIZE;

        // TODO: this shouldn't have to be var
        var origin_vox: vec3<f32> = clamp(intersect, vec3<f32>(0.0001), vec3<f32>(BRICK_SIZE - 0.0001));
        // for some reason origin_vox being whole number will cause blocks to incorrectly appear in the origin brick
        origin_vox = select(origin_vox, origin_vox + 0.0001, origin_vox == floor(origin_vox));
        var pos_vox: vec3<i32> = vec3<i32>(floor(origin_vox));
        var ray_len_vox: vec3<f32> = select(origin_vox - floor(origin_vox), ceil(origin_vox) - origin_vox, step_mask) * step_len;
        var side_vox = side_brick;
        var t_vox: f32 = 0;
        while(!( any( pos_vox < vec3<i32>(0) ) || any( pos_vox > vec3<i32>(BRICK_SIZE - 1) ) )) {
            if(is_solid(curr_brick, pos_vox)) { return OutDDA(0, uv_face(vec3<f32>(origin_vox + t_vox * dir), side_vox)); }
            side_vox = side_mask(ray_len_vox);
            pos_vox += vec3<i32>(side_vox) * step_dir;
            t_vox = dot(ray_len_vox, vec3<f32>(side_vox));
            ray_len_vox += vec3<f32>(side_vox) * step_len;
        }

        side_brick = side_mask(ray_len_brick);
        pos_brick += vec3<i32>(side_brick) * step_dir;
        t_brick = dot(ray_len_brick, vec3<f32>(side_brick));
        ray_len_brick += vec3<f32>(side_brick) * step_len;
    }
    return OutDDA(0, vec3<f32>(0.0));
}

// https://www.shadertoy.com/view/lfyGRW
fn side_mask(side_dist: vec3<f32>) -> vec3<bool> {
    /*let min_side = min(side_dist.x, min(side_dist.y, side_dist.z));
    if(min_side == side_dist.x) { return vec3<bool>(true, false, false); }
    else if(min_side == side_dist.y) { return vec3<bool>(false, true, false);}
    else { return vec3<bool>(false, false, true); }*/
    var mask: vec3<bool>;
    let b1 = side_dist.xyz < side_dist.yzx;
    let b2 = side_dist.xyz <= side_dist.zxy;
    mask.z = b1.z && b2.z;
    mask.x = b1.x && b2.x;
    mask.y = b1.y && b2.y;
    if(!any(mask)) { mask.z = true; }
    return mask;
}

fn brick_exists(pos: vec3<i32>) -> bool {
    return !(any(pos < vec3i(0, 0, 0)) || any(vec3<u32>(pos) >= world_header.size));
}

fn get_brick(pos: vec3<i32>) -> i32 {
    return dot(pos, vec3<i32>(1, BRICK_SIZE * BRICK_SIZE, BRICK_SIZE));
}


fn uv_face(ray_end_pos: vec3<f32>, side: vec3<bool>) -> vec3<f32> {

    if(side.x) { return vec3<f32>(fract(ray_end_pos.yz), 0.0); }
    if(side.y) { return vec3<f32>(fract(ray_end_pos.xz), 0.0); }
    { return vec3<f32>(fract(ray_end_pos.xy), 0.0); } // SIDE_Z
}

fn is_solid(brick: i32, curr_vox: vec3<i32>) -> bool {
    // TODO: remove this assert?
    if(any(curr_vox < vec3<i32>(0)) || any(curr_vox > vec3<i32>(BRICK_SIZE - 1))) { return false; }

    return bool(bitmasks.bits[brick][8 / (32 / BRICK_SIZE) * u32(curr_vox.y) + u32(curr_vox.z > (32 / BRICK_SIZE) - 1)] & u32(1 << (BRICK_SIZE / 2 * u32(curr_vox.z) + u32(curr_vox.x))));
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