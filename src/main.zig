const win32 = @import("zigwin32").everything;
pub const UNICODE = true;

// Followed examples from: https://github.com/marlersoft/zigwin32gen

var color: win32.ROP_CODE = win32.WHITENESS;

fn mainWindowCallback(
    Window: win32.HWND,
    message: u32,
    w_param: win32.WPARAM,
    l_param: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    var result: win32.LRESULT = 0;
    switch (message) {
        win32.WM_SIZE => {
            win32.OutputDebugStringA("WM_SIZE\n");
        },
        win32.WM_DESTROY => {
            win32.OutputDebugStringA("WM_DESTROY\n");
        },
        win32.WM_CLOSE => {
            win32.OutputDebugStringA("WM_CLOSE\n");
        },
        win32.WM_ACTIVATEAPP => {
            win32.OutputDebugStringA("WM_ACTIVATEAPP\n");
        },
        win32.WM_PAINT => {
            var Paint: win32.PAINTSTRUCT = undefined;
            const DeviceContext = win32.BeginPaint(Window, &Paint);
            const x = Paint.rcPaint.left;
            const y = Paint.rcPaint.top;
            const width = Paint.rcPaint.right - Paint.rcPaint.left;
            const height = Paint.rcPaint.bottom - Paint.rcPaint.top;
            if (color == win32.WHITENESS) {
                color = win32.BLACKNESS;
            } else {
                color = win32.WHITENESS;
            }
            _ = win32.PatBlt(DeviceContext, x, y, width, height, color);
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
            while (true) {
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
