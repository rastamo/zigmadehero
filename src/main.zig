const win32 = @import("zigwin32").everything;
pub const UNICODE = true;

// Followed examples from: https://github.com/marlersoft/zigwin32gen

pub export fn wWinMain(
    _: ?win32.HINSTANCE,
    _: ?win32.HINSTANCE,
    _: [*:0]u16,
    _: u32,
) callconv(.winapi) c_int {
    _ = win32.MessageBoxA(
        null,
        "This is Handmade Hero.",
        "Handmade Hero",
        win32.MB_ICONINFORMATION, // MB_OK is default.
    );

    return 0;
}
