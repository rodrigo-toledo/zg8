const std = @import("std");
const zg8 = @import("zg8");
const fonts = @import("font.zig");

pub fn main() !void {
    var cpu = Cpu.init();
    cpu.loadRom("demo.ch8") catch |err| switch (err) {
        error.RomTooLarge => undefined,
        else => undefined,
    };
    std.debug.print("{d} Memory dump {any}", .{ rand(), cpu.memory });
}

const start_address = 0x200;
const font_start_address = 0x50;
const mem_size = 4096;
const keys = 16;
const stack_levels = 16;
const video_rows = 64;
const video_columns = 32;
const register_count = 16;

const Cpu = struct {
    registers: [register_count]u8,
    memory: [mem_size]u8,
    index: u16,
    pc: u16 = start_address,
    stack: [stack_levels]u16,
    sp: u4,
    delay_timer: u8,
    sound_timer: u8,
    keypad: [keys]u8,
    video: [video_rows][video_columns]bool, // guide uses u32 for compat with SDL
    opcode: u16,

    pub fn init() Cpu {
        // TODO: not sure if this can be const, we'll see
        var mem = std.mem.zeroes([mem_size]u8);

        @memcpy(mem[font_start_address .. font_start_address + fonts.font_set.len], &fonts.font_set);
        return Cpu{
            // std.mem.zeroes is a helper that returns a zeroed-out
            // version of whatever type you ask for.
            .registers = std.mem.zeroes([register_count]u8),
            .memory = mem,
            .index = 0,
            .pc = start_address, // CHIP-8 programs always start here
            .stack = std.mem.zeroes([stack_levels]u16),
            .sp = 0,
            .delay_timer = 0,
            .sound_timer = 0,
            .keypad = std.mem.zeroes([keys]u8),
            .video = std.mem.zeroes([video_rows][video_columns]bool), // guide uses u32 for compat with SDL
            .opcode = 0,
        };
    }
    pub fn loadRom(self: *Cpu, filename: []const u8) !void { // 1. Open the file
        var file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        // 2. Get file size and verify it fits
        const stat = try file.stat();
        if (stat.size > self.memory.len - start_address) {
            return error.RomTooLarge;
        }

        // 3. Define the slice of memory where the ROM lives
        const target_memory = self.memory[start_address .. start_address + stat.size];

        // 4. Read Loop (The "Systems" Way)
        // We loop because the OS might not give us all bytes in one shot.
        var total_read: usize = 0;
        while (total_read < target_memory.len) {
            // Ask to read into the *remaining* part of the slice
            const bytes_read = try file.read(target_memory[total_read..]);

            // If read returns 0, it means the file ended unexpectedly
            if (bytes_read == 0) {
                return error.EndOfStream;
            }

            total_read += bytes_read;
        }

        std.debug.print("Successfully loaded {d} bytes.\n", .{total_read});
    }

    pub fn step(self: *Cpu) !void {
        // Fetch
        const pc = self.pc;
        const high = self.memory[pc];
        const low = self.memory[pc + 1];
        const opcode = (@as(u16, high) << 8) | low;
        self.pc += 2;

        // Decode & Execute in one flat structure
        switch (opcode) {
            // 1. Handle specific "Fixed" opcodes first
            0x00E0 => self.clearScreen(),
            0x00EE => self.returnFromSubroutine(),
            0x1000...0x1FFF => self.jump(opcode),

            else => return error.UnknownOpcode,
        }
    }

    pub fn clearScreen(self: *Cpu) !void {
        self.video = std.mem.zeroes([video_rows][video_columns]bool);
    }

    pub fn returnFromSubroutine(self: *Cpu) !void {
        self.sp -= 1;
        self.pc = self.stack[self.sp];
    }

    pub fn jump(self: *Cpu, opcode: Opcode) !void {
        self.pc = Decode.nnn(opcode);
    }
};
fn rand() u8 {
    return std.crypto.random.int(u8);
}

const Opcode = u16;

// Helper struct to namespace your decoding logic
const Decode = struct {

    // Extracts the top 4 bits (0x1000 -> 0x1)
    fn kind(op: Opcode) u4 {
        return @as(u4, @intCast((op & 0xF000) >> 12));
    }

    // 0x0X00 -> Return X (The second nibble)
    fn x(op: Opcode) u8 {
        return @as(u8, @intCast((op & 0x0F00) >> 8));
    }

    // 0x00Y0 -> Return Y (The third nibble)
    fn y(op: Opcode) u8 {
        return @as(u8, @intCast((op & 0x00F0) >> 4));
    }

    // 0x000N -> Return N (The fourth nibble, height/value)
    fn n(op: Opcode) u8 {
        return @as(u8, @intCast(op & 0x000F));
    }

    // 0x00NN -> Return NN (The last byte, 8-bit immediate)
    fn nn(op: Opcode) u8 {
        return @as(u8, @intCast(op & 0x00FF));
    }

    // 0x0NNN -> Return NNN (The address, 12-bit immediate)
    fn nnn(op: Opcode) u16 {
        return op & 0x0FFF;
    }
};

test "Opcode test" {
    const opcode = 0xABCD;

    try std.testing.expectEqual(Decode.kind(opcode), 0xA);
    try std.testing.expectEqual(Decode.x(opcode), 0xB);
    try std.testing.expectEqual(Decode.y(opcode), 0xC);
    try std.testing.expectEqual(Decode.n(opcode), 0xD);
    try std.testing.expectEqual(Decode.nn(opcode), 0xCD);
    try std.testing.expectEqual(Decode.nnn(opcode), 0xBCD);
}

// (Recommended) Key mapping
//Keypad       Keyboard
//+-+-+-+-+    +-+-+-+-+
//|1|2|3|C|    |1|2|3|4|
//+-+-+-+-+    +-+-+-+-+
//|4|5|6|D|    |Q|W|E|R|
//+-+-+-+-+ => +-+-+-+-+
//|7|8|9|E|    |A|S|D|F|
//+-+-+-+-+    +-+-+-+-+
//|A|0|B|F|    |Z|X|C|V|
//+-+-+-+-+    +-+-+-+-+

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
