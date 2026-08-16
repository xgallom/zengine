//!
//! The zengine
//!

const std = @import("std");
const log = std.log.scoped(.zengine);
const assert = std.debug.assert;

pub const allocators = @import("allocators.zig");
pub const ext = @import("ext");
pub const anim = @import("anim.zig");
pub const audio = @import("audio.zig");
pub const ChunkAllocator = @import("ChunkAllocator.zig");
pub const containers = @import("containers.zig");
pub const controls = @import("controls.zig");
pub const ecs = @import("ecs.zig");
pub const Engine = @import("Engine.zig");
pub const Event = @import("Event.zig");
pub const fs = @import("fs.zig");
pub const gfx = @import("gfx.zig");
pub const global = @import("global.zig");
pub const math = @import("math.zig");
pub const Options = @import("options.zig").Options;
pub const options = @import("options.zig").options;
pub const perf = @import("perf.zig");
pub const sched = @import("sched.zig");
pub const sdl_allocator = @import("sdl_allocator.zig");
pub const str = @import("str.zig");
pub const time = @import("time.zig");
pub const TypeId = @import("type_id.zig").TypeId;
pub const typeId = @import("type_id.zig").typeId;
pub const ui = @import("ui.zig");
pub const Window = @import("Window.zig");

var global_self: ?*Zengine = null;
const c = ext;

pub const Zengine = struct {
    engine: *Engine,
    audio: *audio.System,
    scene: if (options.has_scene) *gfx.Scene else ?*gfx.Scene,
    renderer: if (options.has_renderer) *gfx.Renderer else ?*gfx.Renderer,
    ui: if (options.has_ui) *ui.UI else ?*ui.UI,
    handlers: Handlers = .{},

    const Self = @This();
    pub const main_section = perf.section(@This()).sub(.main);
    pub const sections = main_section.sections(&.{ .init, .load, .frame });

    pub inline fn get() *Self {
        assert(global_self != null);
        return global_self.?;
    }

    pub fn createHeadless(handlers: Handlers) !*Self {
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

        if (handlers.register) |register| try register();
        // try gfx.register();

        try global.init();
        errdefer global.deinit();

        main_section.begin();
        sections.sub(.init).begin();

        const audio_sys = try audio.System.create();
        errdefer audio_sys.deinit();

        const self = try allocators.global().create(Self);
        self.* = .{
            .engine = engine,
            .audio = audio_sys,
            .scene = null,
            .renderer = null,
            .ui = null,
            .handlers = handlers,
        };
        global_self = self;

        if (handlers.init) |init| try init(self);

        try perf.commitGraph();
        sections.sub(.init).end();

        return self;
    }

    pub fn create(
        handlers: Handlers,
        win_info: *const Window.CreateInfo.Nullable,
        p_init: std.process.Init.Minimal,
    ) !*Self {
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

        if (handlers.register) |register| try register();
        try gfx.register();

        try global.init(p_init);
        errdefer global.deinit();

        main_section.begin();
        sections.sub(.init).begin();
        const main_win = try engine.createMainWindow(win_info);
        try main_win.show();
        try main_win.raise();

        const audio_sys = try audio.System.create();
        errdefer audio_sys.deinit();

        while (true) {
            const win_size = main_win.logicalSize();
            if (win_size[0] != 0 and win_size[1] != 0) break;
            Event.pump();
            while (Event.poll(engine)) |_| {}
            sleep(1);
        }

        const renderer = if (comptime options.has_renderer)
            try gfx.Renderer.create(engine)
        else
            null;
        errdefer renderer.deinit();

        // const scene = if (comptime options.has_scene) try gfx.Scene.create(renderer) else {};
        const scene = if (comptime options.has_scene) try gfx.Scene.create(renderer) else null;
        errdefer if (comptime options.has_scene) scene.deinit();

        const ui_ptr = if (comptime options.has_ui) try ui.UI.create(renderer) else {};
        errdefer if (comptime options.has_ui) ui_ptr.deinit();

        const self = try allocators.global().create(Self);
        self.* = .{
            .engine = engine,
            .audio = audio_sys,
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
        if (comptime options.has_renderer) self.renderer.deinit();
        self.audio.deinit();
        global.deinit();
        perf.deinit();
        self.engine.deinit();
        global_self = null;
    }

    pub fn run(self: *Self) !void {
        sections.sub(.load).begin();
        defer if (self.handlers.unload) |unload| unload(self) catch unreachable;
        if (self.handlers.load) |load| {
            if (!try load(self)) return;
        }
        sections.sub(.load).end();

        if (self.handlers.run) |run_h| {
            try run_h(self);
            return;
        }

        return while (true) {
            defer perf.reset();
            const section = sections.sub(.frame);
            main_section.push();
            section.begin();

            section.sub(.init).begin();
            global.startFrame();
            defer global.finishFrame();
            defer allocators.frameReset();
            const now = global.engineNow();
            perf.update(now);
            perf.updateStats(now, false);
            section.sub(.init).end();

            {
                section.sub(.input).begin();
                defer section.sub(.input).end();
                if (self.handlers.input) |input| {
                    @branchHint(.likely);
                    if (!try input(self)) return;
                }
            }

            {
                section.sub(.update).begin();
                defer section.sub(.update).end();
                if (self.handlers.resize) |resize| {
                    if (self.engine.state.resized) {
                        @branchHint(.unlikely);
                        if (!try resize(self)) return;
                        self.engine.state.resized = false;
                    }
                }

                if (self.handlers.update) |update| {
                    @branchHint(.likely);
                    if (!try update(self)) return;
                }
            }

            section.sub(.render).begin();
            if (self.handlers.render) |render| {
                @branchHint(.likely);
                try render(self);
            }
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
        register: ?*const fn () anyerror!void = null,
        init: ?*const fn (self: *Self) anyerror!void = null,
        load: ?*const fn (self: *Self) anyerror!bool = null,
        unload: ?*const fn (self: *Self) anyerror!void = null,
        resize: ?*const fn (self: *Self) anyerror!bool = null,
        input: ?*const fn (self: *const Self) anyerror!bool = null,
        update: ?*const fn (self: *Self) anyerror!bool = null,
        render: ?*const fn (self: *const Self) anyerror!void = null,
        run: ?*const fn (self: *Self) anyerror!void = null,
    };
};

pub fn sleep(ms: u32) void {
    c.SDL_Delay(ms);
}

pub fn sleepNano(ns: u64) void {
    c.SDL_DelayNS(ns);
}

var is_done_waiting: u32 = 0;
pub fn waitForDebugger() void {
    log.info("Waiting for debugger to attach...", .{});
    while (@atomicLoad(u32, &is_done_waiting, .seq_cst) == 0) std.atomic.spinLoopHint();
    log.info("Done", .{});
}

test {
    std.testing.log_level = .debug;
    std.testing.refAllDecls(@This());
}
