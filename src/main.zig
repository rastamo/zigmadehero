const win32 = @import("zigwin32").everything;
pub const UNICODE = true;

pub fn main() !void {
    _ = win32.MessageBoxA(null, "Hello, Win32!", "Testing window", win32.MB_ICONINFORMATION);
}
