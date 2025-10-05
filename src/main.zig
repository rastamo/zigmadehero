const win32 = @import("zigwin32").everything;
pub const UNICODE = true;

// Followed examples from: https://github.com/marlersoft/zigwin32gen

var running: bool = true;
var BitmapInfo: win32.BITMAPINFO = undefined;
var bitmapmemory: ?*anyopaque = undefined;
var BitmapHandle: ?win32.HBITMAP = undefined;
var BitmapDeviceContext: ?win32.HDC = undefined;

fn win32ResizeDIBSection(width: i32, height: i32) void {
    // TODO: Bulletproof this.
    // Maybe don't free first, free after, then free first if that fails.

    if (BitmapHandle) |handle| {
        _ = win32.DeleteObject(handle);
    }
    if (BitmapDeviceContext == null) {
        // TODO: Should we recreate these under certain special cirumstances.
        BitmapDeviceContext = win32.CreateCompatibleDC(undefined);
    }
    BitmapInfo = .{
        .bmiHeader = .{
            .biSize = @sizeOf(win32.BITMAPINFOHEADER),
            .biWidth = width,
            .biHeight = height,
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
    // TODO: Based on ssylvan's suggestion, maybe we can just allocate this ourselves?
    _ = win32.CreateDIBSection(
        BitmapDeviceContext,
        &BitmapInfo,
        win32.DIB_RGB_COLORS,
        &bitmapmemory,
        null,
        0,
    );
}

fn win32UpdateWindow(DeviceContext: ?win32.HDC, x: i32, y: i32, width: i32, height: i32) void {
    _ = win32.StretchDIBits(
        DeviceContext,
        x,
        y,
        width,
        height,
        x,
        y,
        width,
        height,
        bitmapmemory,
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
            const x = Paint.rcPaint.left;
            const y = Paint.rcPaint.top;
            const width = Paint.rcPaint.right - Paint.rcPaint.left;
            const height = Paint.rcPaint.bottom - Paint.rcPaint.top;
            win32UpdateWindow(DeviceContext, x, y, width, height);
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
        if (WindowHandle) |_| {
            while (running) {
                var message: win32.MSG = undefined;
                const message_result: win32.BOOL = win32.GetMessageW(&message, null, 0, 0);
                if (message_result > 0) {
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessageW(&message);
                } else {
                    break;
                }
            }
        } else {
            // TODO: Logging
        }
    } else {
        // TODO: Logging
    }
    return 0;
}
