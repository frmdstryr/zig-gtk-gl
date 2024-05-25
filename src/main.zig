const std = @import("std");
const gtk = @import("gtk");
const gio = @import("gio");
const gdk = @import("gdk");
const gl = @import("zgl");
const c = @cImport({
    //@cInclude("GL/glx.h");
    @cInclude("EGL/egl.h");
});


pub fn getProcAddress(comptime data: anytype, name: [:0]const u8) ?gl.binding.FunctionPointer {
    _ = data;
    //return c.glXGetProcAddress(name);
    return c.eglGetProcAddress(name);
}

const App = struct {
    const Self = @This();
    app: *gtk.Application,
    program: ?gl.Program = null,
    vertex_array: ?gl.VertexArray = null,

    pub fn onRealize(area: *gtk.GLArea, data: ?*Self) callconv(.C) void {
        const self: *Self = data.?;
        area.makeCurrent();
        if (area.getError()) |err| {
            _ = err;
            std.log.err("Error initialzing GL", .{});
            return;
        }


        const vertex_shader = gl.Shader.create(.vertex);
        defer vertex_shader.delete();
        vertex_shader.source(1, &[1][]const u8{
            \\#version 330
            \\layout (location = 0) in vec4 position;
            \\layout (location = 1) in vec4 color;
            \\uniform vec2 offset;
            \\smooth out vec4 theColor;
            \\void main() {
            \\    vec4 totalOffset = vec4(offset.x, offset.y, 0.0, 0.0);
            \\    gl_Position = position + totalOffset;
            \\    theColor = color;
            \\}
        });
        vertex_shader.compile();

        const fragment_shader = gl.Shader.create(.fragment);
        defer fragment_shader.delete();
        fragment_shader.source(1, &[1][]const u8{
            \\#version 330 core
            \\smooth in vec4 theColor;
            \\out vec4 outputColor;
            \\void main() {
            \\       outputColor = theColor;
            \\};
        });
        fragment_shader.compile();

        const program = gl.Program.create();
        self.program = program;
        //defer program.delete();
        program.attach(vertex_shader);
        program.attach(fragment_shader);
        program.link();

        const vertices = [_]f32{
            0.0,    0.5, 0.0, 1.0,
            0.5, -0.366, 0.0, 1.0,
            -0.5, -0.366, 0.0, 1.0,
            1.0,    0.0, 0.0, 1.0,
            1.0,    1.0, 0.0, 1.0,
            1.0,    1.0, 1.0, 1.0,
        };
//         const indices = [_]u32{ // note that we start from 0!
//             0, 1, 3, // first Triangle
//             1, 2, 3, // second Triangle
//         };
        self.vertex_array = gl.VertexArray.create();

        if (self.vertex_array) |vertex_array| {
            vertex_array.bind();
            var vertex_buffer = gl.Buffer.create();
            defer vertex_buffer.delete();
            vertex_buffer.bind(.array_buffer);
            vertex_buffer.data(f32, &vertices, .static_draw);

//             var index_buffer = gl.Buffer.create();
//             defer index_buffer.delete();
//             index_buffer.bind(.element_array_buffer);
//             index_buffer.data(u32, &indices, .static_draw);

            gl.enableVertexAttribArray(0);
            gl.vertexAttribPointer(0, 4, .float, false, 4*@sizeOf(f32), 0);
            gl.enableVertexAttribArray(1);
            gl.vertexAttribPointer(1, 4, .float, false, 4*@sizeOf(f32), 48);
            // vertex_array.attribFormat(0, 3, .float, false, 0);
            gl.bindVertexArray(.invalid);
        }
    }

    pub fn onUnrealize(area: *gtk.GLArea, data: ?*Self) callconv(.C) void {
        const self: *Self = data.?;
        _ = area;
        if (self.program) |program| {
            program.delete();
            self.program = null;
        }
        if (self.vertex_array) |buf| {
            buf.delete();
            self.vertex_array = null;
        }
    }

    pub fn onRender(area: *gtk.GLArea, context: *gdk.GLContext, data: ?*Self) callconv(.C) bool {
        const self: *Self = data.?;
       // _ = area;
        _ = context;
        gl.clearColor(0, 0, 0, 1.0);
        gl.clear(.{.color=true});
        const program = self.program.?;
        program.use();

        const duration: f32 = 5;
        const scale = std.math.pi * 2 / duration;
        const dt: f32 = @floatFromInt(area.getFrameClock().?.getFrameTime());
        const t = @mod(dt/std.time.ns_per_ms, duration);
        gl.uniform2f(
            gl.getUniformLocation(program, "offset").?,
            @sin(t*scale)*0.5,
            @cos(t*scale)*0.5
        );
        if (self.vertex_array) |vertex_array| {
            vertex_array.bind();
            //self.vertex_array.?.enableVertexAttribute(0);
            //gl.drawElements(.triangles, 6, .unsigned_int, 0);
            gl.drawArrays(.triangles, 0, 3);
        }
        return true;
    }

    pub fn onTick(widget: *gtk.Widget, frame_clock: *gdk.FrameClock, user_data: ?*anyopaque) callconv(.C) bool {
        const area: *gtk.GLArea = @ptrCast(widget);
        const self: *Self = @ptrCast(@alignCast(user_data.?));
        _= frame_clock;
        _ = self;
        area.queueDraw();
        return true;
    }

    pub fn onDestroyNotify(data: ?*anyopaque) callconv(.C) void {
        _ = data;
    }

    pub fn activate(app: *gtk.Application, data: ?*Self) callconv(.C) void {
        const self: *Self = data.?;
        const window = gtk.ApplicationWindow.new(app).?;
        window.setTitle("Hello!");
        window.setDefaultSize(320, 320);

        const header_bar = gtk.HeaderBar.new().?;
        window.setTitlebar(header_bar.asWidget());

        const area = gtk.GLArea.new().?;
        area.setVexpand(true);
        area.setHexpand(true);
        _ = area.connectRealize(Self, &onRealize, self, .Default);
        _ = area.connectUnrealize(Self, &onUnrealize, self, .Default);
        _ = area.connectRender(Self, &onRender, self, .Default);
        _ = area.addTickCallback(&onTick, self, &onDestroyNotify);
        window.setChild(area.asWidget());
        window.show();
    }

};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var app = gtk.Application.new("zig.gtk.example", gio.ApplicationFlags.FlagsNone).?;
    defer app.unref();

    try gl.binding.load(void, getProcAddress);
    var instance = App{.app=app};
    _ = app.connectActivate(App, &App.activate, &instance, .Default);
    return @intCast(app.run(@intCast(args.len), @ptrCast(args.ptr)));
}
