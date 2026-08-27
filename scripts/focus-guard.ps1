<#
.SYNOPSIS
    Keeps Minecraft in control when the Xeneon Edge touchscreen is tapped.

.DESCRIPTION
    The Edge is a real Windows display, so a touch teleports the cursor onto it
    and gives the touched window (the iCUE dashboard) foreground focus - which
    minimizes exclusive-fullscreen games and always steals input. This guard
    listens for foreground changes and, when focus moves from Minecraft to a
    window on the Edge (detected by its 32:9 ultra-wide shape), it immediately
    hands focus back to Minecraft and snaps the cursor to where it was. The
    touched widget still receives its tap first.

    Deliberate focus changes are untouched: the guard only reacts when the
    window losing focus was Minecraft, and only for the ultra-wide monitor.
    Clicking on the other monitors behaves exactly as before.

    Runs forever; intended to be registered as a hidden at-logon scheduled task
    via install-tasks.ps1. Costs nothing while Minecraft isn't running.
#>
$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class FocusGuard
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    public delegate void WinEventDelegate(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmod, WinEventDelegate proc, uint idProcess, uint idThread, uint flags);
    [DllImport("user32.dll")] public static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO info);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder name, int maxCount);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT pt);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern int GetMessage(out MSG msg, IntPtr hWnd, uint filterMin, uint filterMax);
    [DllImport("user32.dll")] public static extern bool TranslateMessage(ref MSG msg);
    [DllImport("user32.dll")] public static extern IntPtr DispatchMessage(ref MSG msg);

    const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    const uint WINEVENT_OUTOFCONTEXT = 0x0000;
    const uint MONITOR_DEFAULTTONEAREST = 2;
    const byte VK_MENU = 0xA4;
    const uint KEYEVENTF_KEYUP = 0x0002;

    static POINT lastSafeCursor;
    static bool haveSafeCursor;
    static IntPtr prevForeground = IntPtr.Zero;
    static WinEventDelegate hookDelegate; // held so the GC never collects the callback

    // The Edge is the only ~32:9 monitor in the setup (2560x720). Ratio-based so
    // DPI scaling doesn't matter; the 27" monitors are 16:9 and never match.
    static bool IsEdgeMonitor(IntPtr hMonitor)
    {
        if (hMonitor == IntPtr.Zero) return false;
        MONITORINFO info = new MONITORINFO();
        info.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (!GetMonitorInfo(hMonitor, ref info)) return false;
        int w = info.rcMonitor.Right - info.rcMonitor.Left;
        int h = info.rcMonitor.Bottom - info.rcMonitor.Top;
        if (h <= 0) return false;
        return w * 10 >= h * 30;
    }

    static bool IsMinecraftWindow(IntPtr hWnd)
    {
        if (hWnd == IntPtr.Zero || !IsWindowVisible(hWnd)) return false;
        StringBuilder cls = new StringBuilder(64);
        GetClassName(hWnd, cls, 64);
        string c = cls.ToString();
        if (c == "GLFW30" || c.StartsWith("LWJGL")) return true; // vanilla + modded MC (LWJGL3/GLFW)
        StringBuilder title = new StringBuilder(128);
        GetWindowText(hWnd, title, 128);
        return title.ToString().StartsWith("Minecraft");
    }

    static void ForceForeground(IntPtr target)
    {
        uint pid;
        uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        uint targetThread = GetWindowThreadProcessId(target, out pid);
        uint self = GetCurrentThreadId();
        AttachThreadInput(self, fgThread, true);
        AttachThreadInput(self, targetThread, true);
        // A tap of ALT releases the foreground lock when the attach trick is not enough.
        keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        BringWindowToTop(target);
        SetForegroundWindow(target);
        AttachThreadInput(self, fgThread, false);
        AttachThreadInput(self, targetThread, false);
    }

    static void OnForeground(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint thread, uint time)
    {
        try
        {
            IntPtr lostFocus = prevForeground;
            prevForeground = hwnd;

            if (!IsMinecraftWindow(lostFocus)) return;
            if (IsMinecraftWindow(hwnd)) return;
            if (!IsEdgeMonitor(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST))) return;

            Thread.Sleep(60); // let the tap fully land on the widget first
            ForceForeground(lostFocus);
            prevForeground = lostFocus;

            POINT now;
            if (haveSafeCursor && GetCursorPos(out now) && IsEdgeMonitor(MonitorFromPoint(now, MONITOR_DEFAULTTONEAREST)))
            {
                SetCursorPos(lastSafeCursor.X, lastSafeCursor.Y);
            }
        }
        catch { }
    }

    public static void Run()
    {
        prevForeground = GetForegroundWindow();

        Thread cursorTracker = new Thread(delegate()
        {
            while (true)
            {
                POINT p;
                if (GetCursorPos(out p) && !IsEdgeMonitor(MonitorFromPoint(p, MONITOR_DEFAULTTONEAREST)))
                {
                    lastSafeCursor = p;
                    haveSafeCursor = true;
                }
                Thread.Sleep(100);
            }
        });
        cursorTracker.IsBackground = true;
        cursorTracker.Start();

        hookDelegate = new WinEventDelegate(OnForeground);
        IntPtr hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, IntPtr.Zero, hookDelegate, 0, 0, WINEVENT_OUTOFCONTEXT);
        if (hook == IntPtr.Zero) throw new InvalidOperationException("SetWinEventHook failed");

        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0)
        {
            TranslateMessage(ref msg);
            DispatchMessage(ref msg);
        }
        UnhookWinEvent(hook);
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp
[FocusGuard]::Run()
