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
            0x00E0 => self.Op00E0(),
            0x00EE => self.Op00EE(),
            0x1000...0x1FFF => self.Op1nnn(opcode),
            0x2000...0x2FFF => self.Op2nnn(opcode),

            else => return error.UnknownOpcode,
        }
    }
    // Op codes implementation

    /// 00E0 - CLS
    /// Clear the display.
    pub fn Op00E0(self: *Cpu) !void {
        self.video = std.mem.zeroes([video_rows][video_columns]bool);
    }

    ///00EE - RET
    ///Return from a subroutine.
    ///The interpreter sets the program counter to the address at the top of the stack, then subtracts 1 from the stack pointer.
    pub fn Op00EE(self: *Cpu) !void {
        self.sp -= 1;
        self.pc = self.stack[self.sp];
    }

    ///1nnn - JP addr
    ///Jump to location nnn.
    ///
    ///The interpreter sets the program counter to nnn.
    pub fn Op1nnn(self: *Cpu, opcode: Opcode) !void {
        self.pc = Decode.nnn(opcode);
    }

    /// 2nnn - CALL addr
    ///Call subroutine at nnn.
    ///
    ///The interpreter increments the stack pointer, then puts the current PC on the top of the stack. The PC is then set to nnn.
    pub fn Op2nnn(self: *Cpu, opcode: Opcode) !void {
        self.sp += 1;
        self.stack[self.sp] = self.pc;

        self.pc = Decode.nnn(opcode);
    }

    ///3xkk - SE Vx, byte
    ///Skip next instruction if Vx = kk.
    ///
    ///The interpreter compares register Vx to kk, and if they are equal, increments the program counter by 2.
    pub fn Op3xkk(self: *Cpu, opcode: Opcode) !void {
        if (self.registers[Decode.x(opcode)] == Decode.nn(opcode)) {
            self.pc += 2;
        }
    }
    ///4xkk - SNE Vx, byte
    ///Skip next instruction if Vx != kk.
    ///
    ///The interpreter compares register Vx to kk, and if they are not equal, increments the program counter by 2.
    pub fn Op4xkk(self: *Cpu, opcode: Opcode) !void {}
    ///5xy0 - SE Vx, Vy
    ///Skip next instruction if Vx = Vy.
    ///
    ///The interpreter compares register Vx to register Vy, and if they are equal, increments the program counter by 2.
    pub fn Op5xy0(self: *Cpu, opcode: Opcode) !void {}
    ///6xkk - LD Vx, byte
    ///Set Vx = kk.
    ///
    ///The interpreter puts the value kk into register Vx.
    pub fn Op6xkk(self: *Cpu, opcode: Opcode) !void {}
    ///7xkk - ADD Vx, byte
    ///Set Vx = Vx + kk.
    ///
    ///Adds the value kk to the value of register Vx, then stores the result in Vx.
    pub fn Op7xkk(self: *Cpu, opcode: Opcode) !void {}
    ///8xy0 - LD Vx, Vy
    ///Set Vx = Vy.
    ///
    ///Stores the value of register Vy in register Vx.
    pub fn Op8xy0(self: *Cpu, opcode: Opcode) !void {}
    ///8xy1 - OR Vx, Vy
    ///Set Vx = Vx OR Vy.
    ///
    ///Performs a bitwise OR on the values of Vx and Vy, then stores the result in Vx. A bitwise OR compares the corrseponding bits from two values, and if either bit is 1, then the same bit in the result is also 1. Otherwise, it is 0.
    pub fn Op8xy1(self: *Cpu, opcode: Opcode) !void {}
    ///8xy2 - AND Vx, Vy
    ///Set Vx = Vx AND Vy.
    ///
    ///Performs a bitwise AND on the values of Vx and Vy, then stores the result in Vx. A bitwise AND compares the corrseponding bits from two values, and if both bits are 1, then the same bit in the result is also 1. Otherwise, it is 0.
    pub fn Op8xy2(self: *Cpu, opcode: Opcode) !void {}
    ///8xy3 - XOR Vx, Vy
    ///Set Vx = Vx XOR Vy.
    ///
    ///Performs a bitwise exclusive OR on the values of Vx and Vy, then stores the result in Vx. An exclusive OR compares the corrseponding bits from two values, and if the bits are not both the same, then the corresponding bit in the result is set to 1. Otherwise, it is 0.
    pub fn Op8xy3(self: *Cpu, opcode: Opcode) !void {}
    ///8xy4 - ADD Vx, Vy
    ///Set Vx = Vx + Vy, set VF = carry.
    ///
    ///The values of Vx and Vy are added together. If the result is greater than 8 bits (i.e., > 255,) VF is set to 1, otherwise 0. Only the lowest 8 bits of the result are kept, and stored in Vx.
    pub fn Op8xy4(self: *Cpu, opcode: Opcode) !void {}
    ///8xy5 - SUB Vx, Vy
    ///Set Vx = Vx - Vy, set VF = NOT borrow.
    ///
    ///If Vx > Vy, then VF is set to 1, otherwise 0. Then Vy is subtracted from Vx, and the results stored in Vx.
    pub fn Op8xy5(self: *Cpu, opcode: Opcode) !void {}
    ///8xy6 - SHR Vx {, Vy}
    ///Set Vx = Vx SHR 1.
    ///
    ///If the least-significant bit of Vx is 1, then VF is set to 1, otherwise 0. Then Vx is divided by 2.
    pub fn Op8xy6(self: *Cpu, opcode: Opcode) !void {}
    ///8xy7 - SUBN Vx, Vy
    ///Set Vx = Vy - Vx, set VF = NOT borrow.
    ///
    ///If Vy > Vx, then VF is set to 1, otherwise 0. Then Vx is subtracted from Vy, and the results stored in Vx.
    pub fn Op8xy7(self: *Cpu, opcode: Opcode) !void {}
    ///8xyE - SHL Vx {, Vy}
    ///Set Vx = Vx SHL 1.
    ///
    ///If the most-significant bit of Vx is 1, then VF is set to 1, otherwise to 0. Then Vx is multiplied by 2.
    pub fn Op8xyE(self: *Cpu, opcode: Opcode) !void {}
    ///9xy0 - SNE Vx, Vy
    ///Skip next instruction if Vx != Vy.
    ///
    ///The values of Vx and Vy are compared, and if they are not equal, the program counter is increased by 2.
    pub fn Op9xy0(self: *Cpu, opcode: Opcode) !void {}
    ///Annn - LD I, addr
    ///Set I = nnn.
    ///
    ///The value of register I is set to nnn.
    pub fn OpAnnn(self: *Cpu, opcode: Opcode) !void {}
    ///Bnnn - JP V0, addr
    ///Jump to location nnn + V0.
    ///
    ///The program counter is set to nnn plus the value of V0.
    pub fn OpBnnn(self: *Cpu, opcode: Opcode) !void {}
    ///Cxkk - RND Vx, byte
    ///Set Vx = random byte AND kk.
    ///
    ///The interpreter generates a random number from 0 to 255, which is then ANDed with the value kk. The results are stored in Vx. See instruction 8xy2 for more information on AND.
    pub fn OpCxkk(self: *Cpu, opcode: Opcode) !void {}
    ///Dxyn - DRW Vx, Vy, nibble
    ///Display n-byte sprite starting at memory location I at (Vx, Vy), set VF = collision.
    ///
    ///The interpreter reads n bytes from memory, starting at the address stored in I. These bytes are then displayed as sprites on screen at coordinates (Vx, Vy). Sprites are XORed onto the existing screen. If this causes any pixels to be erased, VF is set to 1, otherwise it is set to 0. If the sprite is positioned so part of it is outside the coordinates of the display, it wraps around to the opposite side of the screen. See instruction 8xy3 for more information on XOR, and section 2.4, Display, for more information on the Chip-8 screen and sprites.
    pub fn OpDxyn(self: *Cpu, opcode: Opcode) !void {}
    ///Ex9E - SKP Vx
    ///Skip next instruction if key with the value of Vx is pressed.
    ///
    ///Checks the keyboard, and if the key corresponding to the value of Vx is currently in the down position, PC is increased by 2.
    pub fn OpEx9E(self: *Cpu, opcode: Opcode) !void {}
    ///ExA1 - SKNP Vx
    ///Skip next instruction if key with the value of Vx is not pressed.
    ///
    ///Checks the keyboard, and if the key corresponding to the value of Vx is currently in the up position, PC is increased by 2.
    pub fn OpExA1(self: *Cpu, opcode: Opcode) !void {}
    ///Fx07 - LD Vx, DT
    ///Set Vx = delay timer value.
    ///
    ///The value of DT is placed into Vx.
    pub fn OpFx07(self: *Cpu, opcode: Opcode) !void {}
    ///Fx0A - LD Vx, K
    ///Wait for a key press, store the value of the key in Vx.
    ///
    ///All execution stops until a key is pressed, then the value of that key is stored in Vx.
    pub fn OpFx0A(self: *Cpu, opcode: Opcode) !void {}
    ///Fx15 - LD DT, Vx
    ///Set delay timer = Vx.
    ///
    ///DT is set equal to the value of Vx.
    pub fn OpFx15(self: *Cpu, opcode: Opcode) !void {}
    ///Fx18 - LD ST, Vx
    ///Set sound timer = Vx.
    ///
    ///ST is set equal to the value of Vx.
    pub fn OpFx18(self: *Cpu, opcode: Opcode) !void {}
    ///Fx1E - ADD I, Vx
    ///Set I = I + Vx.
    ///
    ///The values of I and Vx are added, and the results are stored in I.
    pub fn OpFx1E(self: *Cpu, opcode: Opcode) !void {}
    ///Fx29 - LD F, Vx
    ///Set I = location of sprite for digit Vx.
    ///
    ///The value of I is set to the location for the hexadecimal sprite corresponding to the value of Vx. See section 2.4, Display, for more information on the Chip-8 hexadecimal font.
    pub fn OpFx29(self: *Cpu, opcode: Opcode) !void {}
    ///Fx33 - LD B, Vx
    ///Store BCD representation of Vx in memory locations I, I+1, and I+2.
    ///
    ///The interpreter takes the decimal value of Vx, and places the hundreds digit in memory at location in I, the tens digit at location I+1, and the ones digit at location I+2.
    pub fn OpFx33(self: *Cpu, opcode: Opcode) !void {}
    ///Fx55 - LD [I], Vx
    ///Store registers V0 through Vx in memory starting at location I.
    ///
    ///The interpreter copies the values of registers V0 through Vx into memory, starting at the address in I.
    pub fn OpFx55(self: *Cpu, opcode: Opcode) !void {}
    ///Fx65 - LD Vx, [I]
    ///Read registers V0 through Vx from memory starting at location I.
    ///
    ///The interpreter reads values from memory starting at location I into registers V0 through Vx.};
    pub fn OpFx65(self: *Cpu, opcode: Opcode) !void {}
    fn rand() u8 {
        return std.crypto.random.int(u8);
    }
};

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
