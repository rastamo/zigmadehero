const win32 = @import("zigwin32").everything;
pub const UNICODE = true;

// Followed examples from: https://github.com/marlersoft/zigwin32gen

var running: bool = true;
var BitmapInfo: win32.BITMAPINFO = undefined;
var bitmap_memory: ?*anyopaque = undefined;
var bitmap_width: i32 = undefined;
var bitmap_height: i32 = undefined;
const bytes_per_pixel: i32 = 4;

fn renderWeirdGradient(x_offset: usize, y_offset: usize) void {
    const width = bitmap_width;
    const height = bitmap_height;

    const pitch = @as(usize, @intCast(width)) * bytes_per_pixel;
    var x: usize = 0;
    var y: usize = 0;
    var row: [*]u8 = @ptrCast(bitmap_memory);
    while (y < height) : (y += 1) {
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        while (x < width) : (x += 1) {
            const blue: u8 = (@as(u8, @intCast((x + x_offset) % 255)));
            const green: u8 = (@as(u8, @intCast((y + y_offset) % 255)));

            pixel[x] = (@as(u16, green) << 8 | blue);
        }
        x = 0;
        row += pitch;
    }
}

fn win32ResizeDIBSection(width: i32, height: i32) void {
    // TODO: Bulletproof this.
    // Maybe don't free first, free after, then free first if that fails.

    if (bitmap_memory) |mem| {
        _ = win32.VirtualFree(mem, 0, win32.MEM_RELEASE);
    }

    bitmap_width = width;
    bitmap_height = height;

    BitmapInfo = .{
        .bmiHeader = .{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = bitmap_width,
            .biHeight = -bitmap_height,
            .biPlanes = 1,
            .biBitCount = 32,
            .biCompression = win32.BI_RGB,
            .biSizeImage = 0,
            .biXPelsPerMeter = 0,
            .biYPelsPerMeter = 0,
            .biClrUsed = 0,
            .biClrImportant = 0,
        },
        .bmiColors = undefined,
    };

    const bitmap_memory_size: i32 = width * height * bytes_per_pixel;
    bitmap_memory = win32.VirtualAlloc(null, @intCast(bitmap_memory_size), win32.MEM_COMMIT, win32.PAGE_READWRITE);
}

fn win32UpdateWindow(DeviceContext: ?win32.HDC, WindowRect: *win32.RECT) void {
    const window_width = WindowRect.right - WindowRect.left;
    const window_height = WindowRect.bottom - WindowRect.top;
    _ = win32.StretchDIBits(
        DeviceContext,
        0,
        0,
        bitmap_width,
        bitmap_height,
        0,
        0,
        window_width,
        window_height,
        bitmap_memory,
        &BitmapInfo,
        win32.DIB_RGB_COLORS,
        win32.SRCCOPY,
    );
}

fn mainWindowCallback(
    Window: win32.HWND,
    message: u32,
    w_param: win32.WPARAM,
    l_param: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    var result: win32.LRESULT = 0;
    switch (message) {
        win32.WM_SIZE => {
            var ClientRect: win32.RECT = undefined;
            _ = win32.GetClientRect(Window, &ClientRect);
            const width = ClientRect.right - ClientRect.left;
            const height = ClientRect.bottom - ClientRect.top;
            win32ResizeDIBSection(width, height);
        },
        win32.WM_CLOSE => {
            // TODO: Handle this with a message to the user?
            running = false;
        },
        win32.WM_ACTIVATEAPP => {
            win32.OutputDebugStringA("WM_ACTIVATEAPP\n");
        },
        win32.WM_DESTROY => {
            // TODO: Handle this as an error - recreate window?
            running = false;
        },
        win32.WM_PAINT => {
            var Paint: win32.PAINTSTRUCT = undefined;
            const DeviceContext: ?win32.HDC = win32.BeginPaint(Window, &Paint);
            var ClientRect: win32.RECT = undefined;
            _ = win32.GetClientRect(Window, &ClientRect);
            win32UpdateWindow(DeviceContext, &ClientRect);
            _ = win32.EndPaint(Window, &Paint);
        },
        else => {
            // win32.OutputDebugStringA("default\n");
            result = win32.DefWindowProcW(Window, message, w_param, l_param);
        },
    }
    return result;
}

pub export fn wWinMain(
    instance: win32.HINSTANCE,
    _: ?win32.HINSTANCE,
    _: [*:0]u16,
    _: u32,
) callconv(.winapi) c_int {
    const WindowClass: win32.WNDCLASSW = .{
        .style = .{ .OWNDC = 1, .HREDRAW = 1, .VREDRAW = 1 },
        .lpfnWndProc = mainWindowCallback,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = win32.L("HandmadeHeroWindowClass"),
    };

    var WindowStyle = win32.WS_OVERLAPPEDWINDOW;
    WindowStyle.VISIBLE = 1;

    if (win32.RegisterClassW(&WindowClass) != 0) {
        const Window: ?win32.HWND = win32.CreateWindowExW(
            .{},
            WindowClass.lpszClassName,
            win32.L("Handmade Hero"),
            WindowStyle,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            null,
            null,
            instance,
            null,
        );
        if (Window) |_| {
            var x_offset: usize = 0;
            var y_offset: usize = 0;
            while (running) {
                var message: win32.MSG = undefined;
                while (win32.PeekMessageW(&message, null, 0, 0, win32.PM_REMOVE) != 0) {
                    if (message.message == win32.WM_QUIT) {
                        running = false;
                    }
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessageW(&message);
                }

                renderWeirdGradient(x_offset, y_offset);
                const DeviceContext: ?win32.HDC = win32.GetDC(Window);
                var ClientRect: win32.RECT = undefined;
                _ = win32.GetClientRect(Window, &ClientRect);
                win32UpdateWindow(DeviceContext, &ClientRect);
                _ = win32.ReleaseDC(Window, DeviceContext);
                x_offset +%= 1;
                y_offset +%= 1;
            }
        } else {
            // TODO: Logging
        }
    } else {
        // TODO: Logging
    }
    return 0;
}
