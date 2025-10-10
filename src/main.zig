const win32 = @import("zigwin32").everything;
pub const UNICODE = true;

// Followed examples from: https://github.com/marlersoft/zigwin32gen

var running: bool = true;
const Win32OffscreenBuffer = struct {
    Info: win32.BITMAPINFO,
    memory: ?*anyopaque,
    width: i32,
    height: i32,
    pitch: i32,
};

var GlobalBackBuffer: Win32OffscreenBuffer = .{
    .Info = undefined,
    .memory = undefined,
    .width = undefined,
    .height = undefined,
    .pitch = undefined,
};

fn win32GetWindowDimension(Window: win32.HWND) struct { width: i32, height: i32 } {
    var ClientRect: win32.RECT = undefined;
    _ = win32.GetClientRect(Window, &ClientRect);
    const width = ClientRect.right - ClientRect.left;
    const height = ClientRect.bottom - ClientRect.top;
    return .{ .width = width, .height = height };
}

fn renderWeirdGradient(Buffer: *Win32OffscreenBuffer, x_offset: usize, y_offset: usize) void {
    var x: usize = 0;
    var y: usize = 0;
    var row: [*]u8 = @ptrCast(Buffer.memory);
    while (y < Buffer.height) : (y += 1) {
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        while (x < Buffer.width) : (x += 1) {
            const blue: u8 = (@as(u8, @intCast((x + x_offset) % 255)));
            const green: u8 = (@as(u8, @intCast((y + y_offset) % 255)));

            pixel[x] = (@as(u16, green) << 8 | blue);
        }
        x = 0;
        row += @as(usize, @intCast(Buffer.pitch));
    }
}

fn win32ResizeDIBSection(Buffer: *Win32OffscreenBuffer, width: i32, height: i32) void {
    // TODO: Bulletproof this.
    // Maybe don't free first, free after, then free first if that fails.
    if (Buffer.memory) |mem| {
        _ = win32.VirtualFree(mem, 0, win32.MEM_RELEASE);
    }

    Buffer.width = width;
    Buffer.height = height;
    // When the biHeight field is negative, this is a the clue to
    // Windows to treat this bitmap as top-down, not bottom-up, meaning that
    // the first three bytes of the image are the color for the top left pixel
    // in the bitmap, not the bottom left!
    Buffer.Info = .{
        .bmiHeader = .{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = Buffer.width,
            .biHeight = -Buffer.height,
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

    const bytes_per_pixel: i32 = 4;
    const bitmap_memory_size: i32 = width * height * bytes_per_pixel;
    Buffer.memory = win32.VirtualAlloc(
        null,
        @intCast(bitmap_memory_size),
        win32.MEM_COMMIT,
        win32.PAGE_READWRITE,
    );
    Buffer.pitch = width * bytes_per_pixel;
}

fn win32DisplayBufferInWindow(
    DeviceContext: ?win32.HDC,
    window_width: i32,
    window_height: i32,
    Buffer: *Win32OffscreenBuffer,
) void {
    // TODO: Aspect ratio correction.
    // TODO: Play with stretch modes.
    _ = win32.StretchDIBits(
        DeviceContext,
        0,
        0,
        window_width,
        window_height,
        0,
        0,
        Buffer.width,
        Buffer.height,
        Buffer.memory,
        &Buffer.Info,
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
        win32.WM_SIZE => {},
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
            const Dimensions = win32GetWindowDimension(Window);
            win32DisplayBufferInWindow(DeviceContext, Dimensions.width, Dimensions.height, &GlobalBackBuffer);
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
        .style = .{ .HREDRAW = 1, .VREDRAW = 1, .OWNDC = 1 },
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
    win32ResizeDIBSection(&GlobalBackBuffer, 1920, 1080);

    var WindowStyle = win32.WS_OVERLAPPEDWINDOW;
    WindowStyle.VISIBLE = 1;

    if (win32.RegisterClassW(&WindowClass) != 0) {
        const WindowHandle: ?win32.HWND = win32.CreateWindowExW(
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
        if (WindowHandle) |Window| {
            // Since we specified CS_OWNDC, we can just get one device context and use it forever
            // because we are not sharing it with anyone.
            const DeviceContext: ?win32.HDC = win32.GetDC(Window);

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

                renderWeirdGradient(&GlobalBackBuffer, x_offset, y_offset);
                const Dimensions = win32GetWindowDimension(Window);
                win32DisplayBufferInWindow(
                    DeviceContext,
                    Dimensions.width,
                    Dimensions.height,
                    &GlobalBackBuffer,
                );
                _ = win32.ReleaseDC(Window, DeviceContext);
                x_offset +%= 1;
                y_offset +%= 2;
            }
        } else {
            // TODO: Logging
        }
    } else {
        // TODO: Logging
    }
    return 0;
}
