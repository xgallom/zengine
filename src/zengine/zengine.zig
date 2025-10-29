//!
//! The zengine
//!

const std = @import("std");

pub const allocators = @import("allocators.zig");
pub const containers = @import("containers.zig");
pub const controls = @import("controls.zig");
pub const ecs = @import("ecs.zig");
pub const Engine = @import("Engine.zig");
pub const ext = @import("ext.zig");
pub const fs = @import("fs.zig");
pub const gfx = @import("gfx.zig");
pub const global = @import("global.zig");
pub const math = @import("math.zig");
pub const Options = @import("options.zig").Options;
pub const options = @import("options.zig").options;
pub const perf = @import("perf.zig");
pub const Scene = @import("Scene.zig");
pub const scheduler = @import("scheduler.zig");
pub const sdl_allocator = @import("sdl_allocator.zig");
pub const time = @import("time.zig");
pub const ui = @import("ui.zig");
pub const Window = @import("Window.zig");

pub const ZEngine = struct {
    engine: *Engine,
    scene: *Scene,
    renderer: *gfx.Renderer,
    ui: *ui.UI,
    handlers: Handlers = .{},

    const Self = @This();
    pub const main_section = perf.section(@This()).sub(.main);
    pub const sections = main_section.sections(&.{ .init, .load, .frame });

    pub fn init(handlers: Handlers) !Self {
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

        try global.init();
        errdefer global.deinit();

        main_section.begin();
        sections.sub(.init).begin();

        try engine.initMainWindow();

        const renderer = try gfx.Renderer.create(engine);
        errdefer renderer.deinit(engine);

        const scene = try Scene.create();
        errdefer scene.deinit();

        const ui_ptr = try ui.UI.create(engine, renderer);
        errdefer ui_ptr.deinit();

        try perf.commitGraph();

        sections.sub(.init).end();

        return .{
            .engine = engine,
            .scene = scene,
            .renderer = renderer,
            .ui = ui_ptr,
            .handlers = handlers,
        };
    }

    pub fn deinit(self: *Self) void {
        defer self.engine.deinit();
        defer perf.deinit();
        defer global.deinit();
        defer self.renderer.deinit(self.engine);
        defer self.scene.deinit();
        defer self.ui.deinit();
        defer perf.releaseGraph();
    }

    pub fn run(self: *const Self) !void {
        sections.sub(.load).begin();
        if (self.handlers.load) |load| if (!try load(self)) return;
        sections.sub(.load).end();

        defer if (self.handlers.unload) |unload| unload(self);

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
        load: ?*const fn (self: *const ZEngine) anyerror!bool = null,
        unload: ?*const fn (self: *const ZEngine) void = null,
        input: ?*const fn (self: *const ZEngine) anyerror!bool = null,
        update: ?*const fn (self: *const ZEngine) anyerror!bool = null,
        render: ?*const fn (self: *const ZEngine) anyerror!void = null,
    };
};

test {
    std.testing.refAllDecls(@This());
}
