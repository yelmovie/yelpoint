using System;
using System.Runtime.InteropServices;

namespace YelPoint {
internal static class Native {
    public const int WS_EX_LAYERED=0x80000, WS_EX_TRANSPARENT=0x20, WS_EX_TOOLWINDOW=0x80, WS_EX_NOACTIVATE=0x08000000;
    public const int WM_HOTKEY=0x0312, WM_MOUSEACTIVATE=0x21, MA_NOACTIVATE=3;
    public static readonly IntPtr Topmost=new IntPtr(-1);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; public POINT(int x,int y){X=x;Y=y;} }
    [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int Width,Height; public SIZE(int w,int h){Width=w;Height=h;} }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; public RECT(int x,int y,int w,int h){Left=x;Top=y;Right=x+w;Bottom=y+h;} }
    [StructLayout(LayoutKind.Sequential,Pack=1)] public struct BLEND { public byte Operation,Flags,Alpha,Format; }
    [StructLayout(LayoutKind.Sequential)] public struct MOUSE { public POINT Point; public uint Data,Flags,Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] public struct KEY { public uint Code,ScanCode,Flags,Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] public struct MAGTRANSFORM { [MarshalAs(UnmanagedType.ByValArray,SizeConst=9)] public float[] Values; }
    public delegate IntPtr Hook(int code,IntPtr message,IntPtr data);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr window,IntPtr dc);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr dc,IntPtr obj);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll",SetLastError=true)] public static extern bool UpdateLayeredWindow(IntPtr window,IntPtr screen,ref POINT dest,ref SIZE size,IntPtr source,ref POINT origin,int key,ref BLEND blend,int flags);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr window,uint colorKey,byte alpha,uint flags);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] public static extern IntPtr GetWindowLong(IntPtr window,int index);
    [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW")] public static extern IntPtr SetWindowLong(IntPtr window,int index,IntPtr value);
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr window,int id,uint modifiers,uint key);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr window,int id);
    [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SetWindowsHookEx(int type,Hook callback,IntPtr module,uint thread);
    [DllImport("user32.dll")] public static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr message,IntPtr data);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr GetModuleHandle(string module);
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window,int message,IntPtr wParam,IntPtr lParam);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr CreateWindowEx(int exStyle,string className,string name,int style,int x,int y,int width,int height,IntPtr parent,IntPtr menu,IntPtr instance,IntPtr param);
    [DllImport("Magnification.dll")] public static extern bool MagInitialize();
    [DllImport("Magnification.dll")] public static extern bool MagUninitialize();
    [DllImport("Magnification.dll")] public static extern bool MagSetWindowTransform(IntPtr window,ref MAGTRANSFORM matrix);
    [DllImport("Magnification.dll")] public static extern bool MagSetWindowSource(IntPtr window,RECT source);
    [DllImport("Magnification.dll")] public static extern bool MagSetWindowFilterList(IntPtr window,uint mode,int count,[In] IntPtr[] handles);
    public static bool Held(int key){return (GetAsyncKeyState(key)&0x8000)!=0;}
    [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(POINT point,uint flags);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr monitor,int type,out uint x,out uint y);
    // The DPI factor of the display under p, read fresh each time: a window's own DeviceDpi goes stale
    // because FloatingForm handles WM_DPICHANGED itself.
    public static float ScaleAt(System.Drawing.Point p){
        try{uint x,y;var monitor=MonitorFromPoint(new POINT(p.X,p.Y),2);if(monitor!=IntPtr.Zero&&GetDpiForMonitor(monitor,0,out x,out y)==0)return Look.DpiScale(x);}
        catch(DllNotFoundException){}catch(EntryPointNotFoundException){}
        return 1f;
    }
    public static float ScaleOf(System.Drawing.Rectangle r){return ScaleAt(new System.Drawing.Point(r.Left+r.Width/2,r.Top+r.Height/2));}
    [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="MessageBoxW")] static extern int MessageBoxW(IntPtr owner,string text,string caption,uint type);
    // Topmost and brought forward, so a box raised while every YelPoint window is hidden
    // cannot open behind the lesson app and leave the app looking frozen. true for Yes.
    public static bool Box(string text,string caption,bool yesNo,bool question=false){return MessageBoxW(IntPtr.Zero,text,caption,(yesNo?0x4u:0u)|(question?0x20u:0x40u)|0x40000u|0x10000u)==6;}
}
}
