//!
//! The zengine
//!

const std = @import("std");
const assert = std.debug.assert;

pub const allocators = @import("allocators.zig");
pub const ChunkAllocator = @import("ChunkAllocator.zig");
pub const containers = @import("containers.zig");
pub const controls = @import("controls.zig");
pub const ecs = @import("ecs.zig");
pub const Engine = @import("Engine.zig");
pub const Event = @import("Event.zig");
pub const ext = @import("ext.zig");
pub const fs = @import("fs.zig");
pub const gfx = @import("gfx.zig");
pub const global = @import("global.zig");
pub const math = @import("math.zig");
pub const Options = @import("options.zig").Options;
pub const options = @import("options.zig").options;
pub const perf = @import("perf.zig");
pub const scheduler = @import("scheduler.zig");
pub const sdl_allocator = @import("sdl_allocator.zig");
pub const str = @import("str.zig");
pub const time = @import("time.zig");
pub const TypeId = @import("type_id.zig").TypeId;
pub const typeId = @import("type_id.zig").typeId;
pub const ui = @import("ui.zig");
pub const Window = @import("Window.zig");

var global_self: ?*Zengine = null;

pub const Zengine = struct {
    engine: *Engine,
    // scene: if (options.has_scene) *gfx.Scene else void,
    scene: *gfx.Scene,
    renderer: *gfx.Renderer,
    ui: if (options.has_ui) *ui.UI else void,
    handlers: Handlers = .{},

    const Self = @This();
    pub const main_section = perf.section(@This()).sub(.main);
    pub const sections = main_section.sections(&.{ .init, .load, .frame });

    pub inline fn get() *Self {
        assert(global_self != null);
        return global_self.?;
    }

    pub fn create(handlers: Handlers) !*Self {
        assert(global_self == null);
        const engine = try Engine.create();
        errdefer engine.deinit();

        try perf.init();
        errdefer perf.deinit();

        try main_section.register();
        try sections.register();
        try sections.sub(.load)
            .sections(&.{ .gfx, .scene, .ui })
            .register();
        try sections.sub(.frame)
            .sections(&.{ .init, .input, .update, .render })
            .register();

        try gfx.register();

        try global.init();
        errdefer global.deinit();

        main_section.begin();
        sections.sub(.init).begin();

        _ = try engine.createMainWindow();

        const renderer = try gfx.Renderer.create(engine);
        errdefer renderer.deinit();

        // const scene = if (comptime options.has_scene) try gfx.Scene.create(renderer) else {};
        const scene = if (comptime options.has_scene) try gfx.Scene.create(renderer) else undefined;
        errdefer if (comptime options.has_scene) scene.deinit();

        const ui_ptr = if (comptime options.has_ui) try ui.UI.create(renderer) else {};
        errdefer if (comptime options.has_ui) ui_ptr.deinit();

        const self = try allocators.global().create(Self);
        self.* = .{
            .engine = engine,
            .scene = scene,
            .renderer = renderer,
            .ui = ui_ptr,
            .handlers = handlers,
        };
        global_self = self;

        if (handlers.init) |init| try init(self);

        try perf.commitGraph();
        sections.sub(.init).end();

        return self;
    }

    pub fn deinit(self: *Self) void {
        assert(self == global_self);
        perf.releaseGraph();
        if (comptime options.has_ui) self.ui.deinit();
        if (comptime options.has_scene) self.scene.deinit();
        self.renderer.deinit();
        global.deinit();
        perf.deinit();
        self.engine.deinit();
        global_self = null;
    }

    pub fn run(self: *const Self) !void {
        sections.sub(.load).begin();
        defer if (self.handlers.unload) |unload| unload(self);
        if (self.handlers.load) |load| {
            if (!try load(self)) return;
        }
        sections.sub(.load).end();

        return while (true) {
            defer perf.reset();

            const section = sections.sub(.frame);
            main_section.push();
            section.begin();

            section.sub(.init).begin();

            defer allocators.frameReset();

            global.startFrame();
            defer global.finishFrame();

            const now = global.engineNow();
            perf.update(now);
            perf.updateStats(now, false);

            section.sub(.init).end();
            section.sub(.input).begin();

            if (self.handlers.input) |input| {
                if (!try input(self)) return;
            }

            section.sub(.input).end();
            section.sub(.update).begin();

            if (self.handlers.update) |update| {
                if (!try update(self)) return;
            }

            section.sub(.update).end();
            section.sub(.render).begin();

            if (self.handlers.render) |render| try render(self);

            section.sub(.render).end();

            if (global.isFirstFrame()) {
                @branchHint(.cold);
                main_section.end();
                perf.updateStats(0, true);
            }

            section.end();
            main_section.pop();
        };
    }

    pub const Handlers = struct {
        init: ?*const fn (self: *const Self) anyerror!void = null,
        load: ?*const fn (self: *const Self) anyerror!bool = null,
        unload: ?*const fn (self: *const Self) void = null,
        input: ?*const fn (self: *const Self) anyerror!bool = null,
        update: ?*const fn (self: *const Self) anyerror!bool = null,
        render: ?*const fn (self: *const Self) anyerror!void = null,
    };
};

test {
    std.testing.refAllDecls(@This());
}
