const std = @import("std");
const zg8 = @import("zg8");

pub fn main() !void {
    var cpu = Cpu.init();
    cpu.loadRom("asdf") catch |err| switch (err) {
        error.RomTooLarge => undefined,
        else => undefined,
    };
}

const START_ADDRESS = 0x200;
const Cpu = struct {
    registers: [16]u8,
    memory: [4096]u8,
    index: u16,
    pc: u16 = START_ADDRESS,
    stack: [16]u16,
    sp: u4,
    delay_timer: u8,
    sound_timer: u8,
    keypad: [16]u8,
    video: [64][32]bool, // guide uses u32 for compat with SDL
    opcode: u16,

    pub fn init() Cpu {
        return Cpu{
            // std.mem.zeroes is a helper that returns a zeroed-out
            // version of whatever type you ask for.
            .registers = std.mem.zeroes([16]u8),
            .memory = std.mem.zeroes([4096]u8),
            .index = 0,
            .pc = START_ADDRESS, // CHIP-8 programs always start here
            .stack = std.mem.zeroes([16]u16),
            .sp = 0,
            .delay_timer = 0,
            .sound_timer = 0,
            .keypad = std.mem.zeroes([16]u8),
            .video = std.mem.zeroes([64][32]bool), // guide uses u32 for compat with SDL
            .opcode = 0,
        };
    }
    pub fn loadRom(self: *Cpu, filename: []const u8) !void { // 1. Open the file
        var file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        // 2. Get file size and verify it fits
        const stat = try file.stat();
        if (stat.size > self.memory.len - 0x200) {
            return error.RomTooLarge;
        }

        // 3. Define the slice of memory where the ROM lives
        const target_memory = self.memory[0x200 .. 0x200 + stat.size];

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
};

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
