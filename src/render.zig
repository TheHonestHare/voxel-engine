const std = @import("std");
const mach = @import("mach");
const config = @import("config");
const App = @import("./app.zig");
const group = @import("./bindgroups.zig");
const gpu = mach.gpu;
const core = mach.core;
const math = mach.math;
// TODO: move all bindgroup logic into bindgroups.zig etc
// TODO: check if its ok to destroy pipeline layout on creation
pub var camera = @import("./camera.zig"){};
pub var gpu_world: @import("./gpu_world.zig") = undefined;
const log = std.log.scoped(.render);

// BIND GROUPS FOR RAYTRACING:
// 0: Camera: camera_uniform
// 1: screen_tex: texture_storage_2d<rgba8unorm, write>

var screen_dimensions: gpu.Extent3D = undefined;
var screen_buffer: *gpu.Texture = undefined;
var screen_buffer_view: *gpu.TextureView = undefined;

var raytrace_pipeline: *gpu.ComputePipeline = undefined;
var raytrace_bindgroup: *gpu.BindGroup = undefined;
var raytrace_bindgroup_layout: *gpu.BindGroupLayout = undefined;

var render_pipeline: *gpu.RenderPipeline = undefined;
var render_bindgroup: *gpu.BindGroup = undefined;
var render_bindgroup_layout: *gpu.BindGroupLayout = undefined;

// TODO: This function should actually return an error rather than panicking
// TODO: create seperate functions that only loads and destroy shaders (hotreloading)
pub fn init() !void {
    const bindgroups = create_bindgroups() catch unreachable;
    const camera_bindgroup_layout = bindgroups;
    defer camera_bindgroup_layout.release();
    core.setCursorMode(.disabled);

    create_raytrace_pipeline("./shaders/raytrace.wgsl", camera_bindgroup_layout) catch
        if (config.validate)
    {
        core.setCursorMode(.normal);
        create_raytrace_pipeline("./shaders/fallback_raytrace.wgsl", camera_bindgroup_layout) catch {
            log.err("failed to initialise fallback", .{});
            std.debug.panic("fallback failed to compile", .{});
        };
    } else unreachable;

    // TODO: this should be under config.validate
    create_render_pipeline() catch {
        log.err("failed to create render pipeline", .{});
        std.debug.panic("render pipeline could not be created", .{});
    };

    camera.set_fov(math.pi / 2.0);
}

fn create_bindgroups() !*gpu.BindGroupLayout {
    screen_dimensions = .{ .height = core.descriptor.height, .width = core.descriptor.width };
    gen_screen_textures();

    const camera_bindgroup_layout = camera.init_bindgroup();
    gpu_world.init();
    return camera_bindgroup_layout;
}

fn create_raytrace_pipeline(comptime path: [:0]const u8, camera_bindgroup_layout: *gpu.BindGroupLayout) !void {
    var compute_module = blk: {
        const shaderbuff = try get_shader_source(core.allocator, path);
        defer free_shader_source(core.allocator, shaderbuff);
        if (config.validate) core.device.pushErrorScope(gpu.ErrorFilter.validation);
        const temp = core.device.createShaderModuleWGSL(if (config.validate) "screen compute shader" else null, shaderbuff);
        errdefer temp.release();
        if (config.validate) {
            var valid = true;
            core.device.popErrorScope(&valid, error_callback);
            core.device.tick();
            if (!valid) return error.ShaderError;
        }
        break :blk temp;
    };
    defer compute_module.release();

    raytrace_pipeline = blk: {
        const layout = blk2: {
            const descriptor = gpu.PipelineLayout.Descriptor.init(.{
                .bind_group_layouts = &.{ camera_bindgroup_layout, raytrace_bindgroup_layout, gpu_world.bindgroup_layout },
            });
            // TODO add validation
            break :blk2 core.device.createPipelineLayout(&descriptor);
        };
        defer layout.release();

        const descriptor: gpu.ComputePipeline.Descriptor = .{
            .layout = layout,
            .compute = .{
                .module = compute_module,
                .entry_point = "main",
            },
        };
        if (config.validate) core.device.pushErrorScope(gpu.ErrorFilter.validation);
        const temp = core.device.createComputePipeline(&descriptor);
        errdefer temp.release();
        var valid = true;
        if (config.validate) {
            core.device.popErrorScope(&valid, error_callback);
            core.device.tick();
            if (!valid) return error.ShaderError;
        }
        break :blk temp;
    };
}

fn create_render_pipeline() !void {
    var shader_module = blk: {
        const shaderbuff = try get_shader_source(core.allocator, "./shaders/render.wgsl");
        defer free_shader_source(core.allocator, shaderbuff);
        if (config.validate) core.device.pushErrorScope(gpu.ErrorFilter.validation);
        const temp = core.device.createShaderModuleWGSL(if (config.validate) "rendering shader" else null, shaderbuff);
        errdefer temp.release();
        if (config.validate) {
            var valid = true;
            core.device.popErrorScope(&valid, error_callback);
            if (!valid) return error.ShaderError;
        }
        break :blk temp;
    };
    defer shader_module.release();

    const blend: gpu.BlendState = .{};
    const colour_target: gpu.ColorTargetState = .{
        .format = core.descriptor.format,
        .blend = &blend,
    };
    const frag = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{colour_target},
    });
    const vert: gpu.VertexState = .{
        .module = shader_module,
        .entry_point = "vert_main",
    };
    render_pipeline = blk: {
        const layout = blk2: {
            const descriptor = gpu.PipelineLayout.Descriptor.init(.{
                .bind_group_layouts = &.{render_bindgroup_layout},
            });
            // TODO add documentation
            break :blk2 core.device.createPipelineLayout(&descriptor);
        };
        defer layout.release();

        const descriptor: gpu.RenderPipeline.Descriptor = .{
            .label = "render pipeline",
            .fragment = &frag,
            .vertex = vert,
            .primitive = .{
                .cull_mode = .back,
                .front_face = .ccw,
                .topology = .triangle_strip,
            },
            .layout = layout,
        };

        if (config.validate) core.device.pushErrorScope(gpu.ErrorFilter.validation);
        const temp = core.device.createRenderPipeline(&descriptor);
        errdefer temp.release();
        var valid = true;
        if (config.validate) {
            core.device.popErrorScope(&valid, error_callback);
            if (!valid) return error.ShaderError;
        }
        break :blk temp;
    };
}

fn gen_screen_textures() void {
    screen_buffer = blk: {
        const descriptor: gpu.Texture.Descriptor = .{
            .size = .{ .width = core.descriptor.width, .height = core.descriptor.height },
            .dimension = .dimension_2d,
            .format = .rgba8_unorm,
            .usage = .{ .copy_dst = true, .storage_binding = true, .texture_binding = true },
            .label = "screen texture",
        };
        break :blk core.device.createTexture(&descriptor);
    };
    screen_buffer_view = screen_buffer.createView(&.{});

    raytrace_bindgroup_layout = blk: {
        const descriptor: gpu.BindGroupLayout.Descriptor = .{ .entry_count = 1, .entries = &[_]gpu.BindGroupLayout.Entry{gpu.BindGroupLayout.Entry.storageTexture(0, .{ .compute = true }, .write_only, .rgba8_unorm, .dimension_2d)}, .label = "raytracing bindgroup layout" };
        break :blk core.device.createBindGroupLayout(&descriptor);
    };

    raytrace_bindgroup = blk: {
        const descriptor: gpu.BindGroup.Descriptor = .{ .layout = raytrace_bindgroup_layout, .entry_count = 1, .entries = &[_]gpu.BindGroup.Entry{gpu.BindGroup.Entry.textureView(0, screen_buffer_view)}, .label = "raytracing bindgroup" };
        break :blk core.device.createBindGroup(&descriptor);
    };

    render_bindgroup_layout = blk: {
        const descriptor: gpu.BindGroupLayout.Descriptor = .{ .entry_count = 1, .entries = &[_]gpu.BindGroupLayout.Entry{gpu.BindGroupLayout.Entry.texture(0, .{ .fragment = true }, .float, .dimension_2d, false)}, .label = "rendering bindgroup layout" };
        break :blk core.device.createBindGroupLayout(&descriptor);
    };

    render_bindgroup = blk: {
        const descriptor: gpu.BindGroup.Descriptor = .{ .layout = render_bindgroup_layout, .entry_count = 1, .entries = &[_]gpu.BindGroup.Entry{gpu.BindGroup.Entry.textureView(0, screen_buffer_view)}, .label = "rendering bindgroup" };
        break :blk core.device.createBindGroup(&descriptor);
    };
}

fn deinit_screen_textures() void {
    screen_buffer.destroy();
    screen_buffer_view.release();
    raytrace_bindgroup.release();
    raytrace_bindgroup_layout.release();
    render_bindgroup.release();
    render_bindgroup_layout.release();
}

pub fn deinit() void {
    render_pipeline.release();
    raytrace_pipeline.release();

    deinit_screen_textures();

    camera.deinit();
}

pub fn update(game: *App.Mod, core_mod: *mach.Core.Mod) void {
    const queue = core.queue;
    const canvas_texture = core.swap_chain.getCurrentTexture().?;
    defer canvas_texture.release();
    const new_dimensions: gpu.Extent3D = .{ .width = canvas_texture.getWidth(), .height = canvas_texture.getHeight() };
    if (!std.meta.eql(new_dimensions, screen_dimensions)) {
        log.info("detected window size change (width {d} height {d})", .{ canvas_texture.getWidth(), canvas_texture.getHeight() });
        deinit_screen_textures();
        screen_dimensions = new_dimensions;
        gen_screen_textures();
    }

    const render_pass_desc = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &[_]gpu.RenderPassColorAttachment{.{
            .view = canvas_texture.createView(&.{}),
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
        }},
    });
    const encoder = core.device.createCommandEncoder(null);
    defer encoder.release();

    const time = game.state().timer.read() / 2.0;
    _ = time; // autofix
    //log.debug("CameraX: {d} {d} {d}",.{camera.uniform.plane_X.x(), camera.uniform.plane_X.y(), camera.uniform.plane_X.z()});

    {
        queue.writeBuffer(camera.buff, 0, (&camera.uniform)[0..1]);
        const compute_pass = encoder.beginComputePass(null);
        defer {
            compute_pass.end();
            compute_pass.release();
        }
        compute_pass.setPipeline(raytrace_pipeline);
        compute_pass.setBindGroup(0, camera.bindgroup, null);
        compute_pass.setBindGroup(1, raytrace_bindgroup, null);
        compute_pass.setBindGroup(2, gpu_world.bindgroup, null);

        compute_pass.dispatchWorkgroups(screen_dimensions.width / 8 + 1, screen_dimensions.height / 8 + 1, 1);
    }
    {
        const render_pass = encoder.beginRenderPass(&render_pass_desc);
        defer {
            render_pass.end();
            render_pass.release();
        }
        render_pass.setPipeline(render_pipeline);
        render_pass.setBindGroup(0, render_bindgroup, null);
        render_pass.draw(4, 1, 0, 0);
    }
    var command = encoder.finish(null);
    defer command.release();
    queue.submit(&[_]*gpu.CommandBuffer{command});
    core_mod.schedule(.present_frame);
}

inline fn error_callback(valid: *bool, error_type: gpu.ErrorType, message: [*:0]const u8) void {
    if (error_type != .no_error) {
        log.err("Error occured while creating pipeline\n{s}\n" ++ (.{'='} ** 20), .{message});
        valid.* = false;
    }
}
fn get_shader_source(allocator: std.mem.Allocator, comptime path: [:0]const u8) ![:0]const u8 {
    if (config.dev) {
        return (try std.fs.cwd().readFileAllocOptions(allocator, path, std.math.maxInt(usize), null, 1, 0))[0.. :0];
    } else {
        return @embedFile("./assets/" ++ path);
    }
}

fn free_shader_source(allocator: std.mem.Allocator, buff: [:0]const u8) void {
    if (config.dev) allocator.free(buff);
}
