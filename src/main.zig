const win32 = @import("zigwin32").everything;
pub const UNICODE = true;

// Followed examples from: https://github.com/marlersoft/zigwin32gen

var running: bool = true;
var secondary_buffer: ?*win32.IDirectSoundBuffer = undefined;
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

// NOTE: XInputGetState & XInputSetState // //
fn XInputGetStateStub(
    _: u32,
    _: ?*win32.XINPUT_STATE,
) callconv(.winapi) isize {
    return @intFromEnum(win32.ERROR_DEVICE_NOT_CONNECTED);
}
var win32XInputGetState: *const fn (
    u32,
    ?*win32.XINPUT_STATE,
) callconv(.winapi) isize = XInputGetStateStub;

fn XInputSetStateStub(
    _: u32,
    _: ?*win32.XINPUT_VIBRATION,
) callconv(.winapi) isize {
    return @intFromEnum(win32.ERROR_DEVICE_NOT_CONNECTED);
}
var win32XInputSetState: *const fn (
    u32,
    ?*win32.XINPUT_VIBRATION,
) callconv(.winapi) isize = XInputSetStateStub;

fn win32LoadXInput() void {
    // TODO: Test this on Windows 8
    var XInputLibrary = win32.LoadLibraryA("xinput1_4.dll");
    if (XInputLibrary) |_| {} else {
        // TODO: Diagnostic
        XInputLibrary = win32.LoadLibraryA("xinput1_3.dll");
    }

    if (XInputLibrary) |library| {
        if (win32.GetProcAddress(library, "XInputGetState")) |procedure| {
            win32XInputGetState = @as(@TypeOf(win32XInputGetState), @ptrCast(procedure));
        }

        if (win32.GetProcAddress(library, "XInputSetState")) |procedure| {
            win32XInputSetState = @as(@TypeOf(win32XInputSetState), @ptrCast(procedure));
        }
    }
}
// // // // // // // // // // // // // // // //

fn win32InitDSound(
    window: win32.HWND,
    samples_per_second: u32,
    buffer_size: u32,
) void {
    // Load the library
    const DSoundLibrary = win32.LoadLibraryA("dsound.dll");
    if (DSoundLibrary) |library| {
        // Get a DirectSound object! - cooperative
        if (win32.GetProcAddress(library, "DirectSoundCreate")) |procedure| {
            const win32DirectSoundCreate = @as(
                *const @TypeOf(win32.DirectSoundCreate),
                @ptrCast(procedure),
            );
            var direct_sound: ?*win32.IDirectSound = undefined;
            if (win32.SUCCEEDED(win32DirectSoundCreate(null, &direct_sound, null))) {
                if (direct_sound) |ds| {
                    var wave_format: win32.WAVEFORMATEX = .{
                        .cbSize = 0,
                        .nAvgBytesPerSec = 0,
                        .nBlockAlign = 0,
                        .nChannels = 2,
                        .nSamplesPerSec = samples_per_second,
                        .wBitsPerSample = 16,
                        .wFormatTag = win32.WAVE_FORMAT_PCM,
                    };
                    wave_format.nBlockAlign = (wave_format.nChannels *% wave_format.wBitsPerSample) / 8;
                    wave_format.nAvgBytesPerSec = wave_format.nSamplesPerSec *% wave_format.nBlockAlign;

                    if (win32.SUCCEEDED(ds.SetCooperativeLevel(
                        window,
                        win32.DSSCL_PRIORITY,
                    ))) {
                        var buffer_description: win32.DSBUFFERDESC = .{
                            .dwSize = @sizeOf(win32.DSBUFFERDESC),
                            .dwFlags = win32.DSBCAPS_PRIMARYBUFFER,
                            .dwBufferBytes = 0,
                            .dwReserved = 0,
                            .lpwfxFormat = null,
                            .guid3DAlgorithm = win32.Guid.initString("00000000-0000-0000-0000-000000000000"),
                        };

                        // TODO: DSBCAPS_GLOBALFOCUS
                        var primary_buffer: ?*win32.IDirectSoundBuffer = undefined;
                        if (win32.SUCCEEDED(ds.CreateSoundBuffer(
                            &buffer_description,
                            &primary_buffer,
                            null,
                        ))) {
                            if (win32.SUCCEEDED(primary_buffer.?.SetFormat(&wave_format))) {
                                win32.OutputDebugStringA("Primary buffer format was set.\n");
                            } else {
                                // TODO: Diagnostic
                            }
                        } else {
                            // TODO: Diagnostic
                        }
                    } else {
                        //TODO: Diagnostic
                    }
                    // TODO: DSBCAPS_GETCURRENTPOSITION2
                    var buffer_description: win32.DSBUFFERDESC = .{
                        .dwSize = @sizeOf(win32.DSBUFFERDESC),
                        .dwFlags = 0,
                        .dwBufferBytes = buffer_size,
                        .dwReserved = 0,
                        .lpwfxFormat = &wave_format,
                        .guid3DAlgorithm = win32.Guid.initString("00000000-0000-0000-0000-000000000000"),
                    };

                    if (win32.SUCCEEDED(ds.CreateSoundBuffer(
                        &buffer_description,
                        &secondary_buffer,
                        null,
                    ))) {
                        win32.OutputDebugStringA("Secondary buffer format was set.\n");
                    } else {
                        // TODO: Diagnostic
                    }
                }
            }
        } else {
            // TODO: Diagnostic
        }
    } else {
        // TODO: Diagnostic
    }
}

fn win32GetWindowDimension(Window: win32.HWND) struct { width: i32, height: i32 } {
    var ClientRect: win32.RECT = undefined;
    _ = win32.GetClientRect(Window, &ClientRect);
    const width = ClientRect.right - ClientRect.left;
    const height = ClientRect.bottom - ClientRect.top;
    return .{ .width = width, .height = height };
}

fn renderWeirdGradient(Buffer: *Win32OffscreenBuffer, x_offset: i32, y_offset: i32) void {
    var x: usize = 0;
    var y: usize = 0;
    var row: [*]u8 = @ptrCast(Buffer.memory);
    while (y < Buffer.height) : (y += 1) {
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        while (x < Buffer.width) : (x += 1) {
            const blue: u8 = @truncate(@abs(@as(i32, @intCast(x)) + x_offset));
            const green: u8 = @truncate(@abs(@as(i32, @intCast(y)) + y_offset));

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
    Buffer: *Win32OffscreenBuffer,
    DeviceContext: ?win32.HDC,
    window_width: i32,
    window_height: i32,
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
        win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYDOWN, win32.WM_KEYUP => {
            const vk_code = w_param;
            const was_down: bool = l_param & (1 << 30) != 0;
            const is_down: bool = l_param & (1 << 31) == 0;
            const alt_key_was_down = l_param & (1 << 29) != 0;
            if (was_down != is_down) {
                switch (vk_code) {
                    @intFromEnum(win32.VK_A) => {
                        running = false;
                    },
                    @intFromEnum(win32.VK_S) => {
                        running = false;
                    },
                    @intFromEnum(win32.VK_D) => {
                        running = false;
                    },
                    @intFromEnum(win32.VK_Q) => {
                        running = false;
                    },
                    @intFromEnum(win32.VK_E) => {
                        running = false;
                    },
                    @intFromEnum(win32.VK_UP) => {
                        running = false;
                    },
                    @intFromEnum(win32.VK_LEFT) => {
                        running = false;
                    },
                    @intFromEnum(win32.VK_DOWN) => {
                        running = false;
                    },
                    @intFromEnum(win32.VK_RIGHT) => {
                        running = false;
                    },
                    @intFromEnum(win32.VK_ESCAPE) => {
                        running = false;
                    },
                    @intFromEnum(win32.VK_SPACE) => {
                        if (is_down) {
                            win32.OutputDebugStringA("Is Down!\n");
                        }
                        if (was_down) {
                            win32.OutputDebugStringA("Was Down!\n");
                        }
                    },
                    @intFromEnum(win32.VK_F4) => {
                        if (alt_key_was_down) {
                            running = false;
                        }
                    },
                    else => {
                        win32.OutputDebugStringA("Key not handled\n");
                    },
                }
            }
        },
        win32.WM_PAINT => {
            var Paint: win32.PAINTSTRUCT = undefined;
            const DeviceContext: ?win32.HDC = win32.BeginPaint(Window, &Paint);
            const Dimensions = win32GetWindowDimension(Window);
            win32DisplayBufferInWindow(
                &GlobalBackBuffer,
                DeviceContext,
                Dimensions.width,
                Dimensions.height,
            );
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
    win32LoadXInput();

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

            // Graphics test
            var x_offset: i32 = 0;
            var y_offset: i32 = 0;

            // Sound test
            const samples_per_second: i32 = 48000;
            const tone_hz: i32 = 256;
            const tone_volume = 2000;
            var running_sample_index: u32 = 0;
            const square_wave_period: i32 = samples_per_second / tone_hz;
            const half_square_wave_period: i32 = square_wave_period / 2;
            const bytes_per_sample: i32 = @sizeOf(i16) * 2;
            const secondary_buffer_size: i32 = samples_per_second * bytes_per_sample;

            var is_sound_playing: bool = false;

            win32InitDSound(Window, samples_per_second, secondary_buffer_size);
            while (running) {
                var message: win32.MSG = undefined;
                while (win32.PeekMessageW(&message, null, 0, 0, win32.PM_REMOVE) != 0) {
                    if (message.message == win32.WM_QUIT) {
                        running = false;
                    }
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessageW(&message);
                }
                // TODO: Should we poll this more frequently?
                for (0..win32.XUSER_MAX_COUNT) |controller_index| {
                    var ControllerState: win32.XINPUT_STATE = undefined;
                    const index = @as(u32, @intCast(controller_index));
                    const state = win32XInputGetState(index, &ControllerState);
                    if (state == @intFromEnum(win32.ERROR_SUCCESS)) {
                        // This controller is plugged in.
                        // TODO: See if ControllerState.dwPacketNumber increments.
                        const Pad = &ControllerState.Gamepad;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_UP) > 0;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_DOWN) > 0;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_LEFT) > 0;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_RIGHT) > 0;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_START) > 0;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_BACK) > 0;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_LEFT_SHOULDER) > 0;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_RIGHT_SHOULDER) > 0;
                        const a_button = (Pad.wButtons & win32.XINPUT_GAMEPAD_A) > 0;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_B) > 0;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_X) > 0;
                        _ = (Pad.wButtons & win32.XINPUT_GAMEPAD_Y) > 0;

                        const stick_x = Pad.sThumbLX;
                        const stick_y = Pad.sThumbLY;
                        x_offset +%= stick_x >> 12;
                        y_offset +%= stick_y >> 12;
                        if (a_button) {
                            var vibration: win32.XINPUT_VIBRATION = .{
                                .wRightMotorSpeed = 60000,
                                .wLeftMotorSpeed = 60000,
                            };
                            win32.OutputDebugStringA("A BUTTON\n");
                            _ = win32XInputSetState(index, &vibration);
                        }
                    } else {
                        // The controller is not available.
                    }
                }

                renderWeirdGradient(&GlobalBackBuffer, x_offset, y_offset);

                // DirectSound output test
                var play_cursor: u32 = 0;
                var write_cursor: u32 = 0;

                if (win32.SUCCEEDED(secondary_buffer.?.GetCurrentPosition(&play_cursor, &write_cursor))) {
                    const byte_to_lock: u32 = @rem(running_sample_index * bytes_per_sample, secondary_buffer_size);
                    var bytes_to_write: u32 = undefined;
                    if (byte_to_lock == play_cursor) {
                        bytes_to_write = secondary_buffer_size;
                    } else if (byte_to_lock > play_cursor) {
                        bytes_to_write = @as(u32, @intCast(secondary_buffer_size)) - byte_to_lock;
                        bytes_to_write += play_cursor;
                    } else {
                        bytes_to_write = play_cursor - byte_to_lock;
                    }

                    // TODO: More strenuous test!
                    // TODO: Switch to a sine wave
                    var region1: ?*anyopaque = null;
                    var region1_size: u32 = 0;
                    var region2: ?*anyopaque = null;
                    var region2_size: u32 = 0;
                    if (win32.SUCCEEDED(secondary_buffer.?.Lock(
                        byte_to_lock,
                        bytes_to_write,
                        &region1,
                        &region1_size,
                        &region2,
                        &region2_size,
                        0,
                    ))) {

                        // TODO: Assert that region1_size/region2_size is valid.
                        // TODO: Collapse these two loops
                        if (region1) |region| {
                            var sample_out: [*]i16 = @ptrCast(@alignCast(region));
                            var sample_index: u32 = 0;
                            const region1_sample_count = @divExact(region1_size, bytes_per_sample);
                            while (sample_index < region1_sample_count) {
                                const sample_value: i16 = switch (@divFloor(running_sample_index, half_square_wave_period) % 2) {
                                    0 => tone_volume,
                                    else => -tone_volume,
                                };
                                sample_out += 1;
                                sample_out[0] = sample_value;
                                sample_out += 1;
                                sample_out[0] = sample_value;

                                sample_index += 1;
                                running_sample_index += 1;
                            }
                        }

                        if (region2) |region| {
                            var sample_out: [*]i16 = @ptrCast(@alignCast(region));
                            var sample_index: u32 = 0;
                            const region2_sample_count = @divExact(region2_size, bytes_per_sample);
                            while (sample_index < region2_sample_count) {
                                const sample_value: i16 = switch (@divFloor(running_sample_index, half_square_wave_period) % 2) {
                                    0 => tone_volume,
                                    else => -tone_volume,
                                };
                                sample_out += 1;
                                sample_out[0] = sample_value;
                                sample_out += 1;
                                sample_out[0] = sample_value;

                                sample_index += 1;
                                running_sample_index += 1;
                            }
                        }
                        _ = secondary_buffer.?.Unlock(region1, region1_size, region2, region2_size);
                    }
                }

                if (!is_sound_playing) {
                    _ = secondary_buffer.?.Play(0, 0, win32.DSBPLAY_LOOPING);
                    is_sound_playing = true;
                }
                const Dimensions = win32GetWindowDimension(Window);
                win32DisplayBufferInWindow(
                    &GlobalBackBuffer,
                    DeviceContext,
                    Dimensions.width,
                    Dimensions.height,
                );
                _ = win32.ReleaseDC(Window, DeviceContext);
            }
        } else {
            // TODO: Logging
        }
    } else {
        // TODO: Logging
    }
    return 0;
}
