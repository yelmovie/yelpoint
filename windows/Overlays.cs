using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace YelPoint {
internal class LayeredForm:Form {
    private bool through=true;
    public LayeredForm(){FormBorderStyle=FormBorderStyle.None;StartPosition=FormStartPosition.Manual;ShowInTaskbar=false;TopMost=true;AutoScaleMode=AutoScaleMode.None;}
    protected override bool ShowWithoutActivation {get{return true;}}
    protected override CreateParams CreateParams{get{var p=base.CreateParams;p.ExStyle|=Native.WS_EX_LAYERED|Native.WS_EX_TOOLWINDOW|Native.WS_EX_NOACTIVATE;if(through)p.ExStyle|=Native.WS_EX_TRANSPARENT;return p;}}
    public void ClickThrough(bool value){if(through==value)return;through=value;if(IsHandleCreated){long flags=Native.GetWindowLong(Handle,-20).ToInt64();if(value)flags|=Native.WS_EX_TRANSPARENT;else flags&=~Native.WS_EX_TRANSPARENT;Native.SetWindowLong(Handle,-20,new IntPtr(flags));}}
    // false when Windows refused this frame; the caller simply draws again on the next tick.
    public bool Publish(Bitmap bitmap){
        IntPtr screen=Native.GetDC(IntPtr.Zero),dc=Native.CreateCompatibleDC(screen),hb=IntPtr.Zero,old=IntPtr.Zero;
        try{
            hb=bitmap.GetHbitmap(Color.FromArgb(0));old=Native.SelectObject(dc,hb);
            var dest=new Native.POINT(Left,Top);var origin=new Native.POINT(0,0);var size=new Native.SIZE(bitmap.Width,bitmap.Height);var blend=new Native.BLEND{Operation=0,Flags=0,Alpha=255,Format=1};
            return Native.UpdateLayeredWindow(Handle,screen,ref dest,ref size,dc,ref origin,0,ref blend,2);
        }finally{if(old!=IntPtr.Zero)Native.SelectObject(dc,old);if(hb!=IntPtr.Zero)Native.DeleteObject(hb);Native.DeleteDC(dc);Native.ReleaseDC(IntPtr.Zero,screen);}
    }
    // The same, from a memory DC that already holds the picture, so nothing is copied first.
    protected bool Publish(IntPtr source,int width,int height){
        IntPtr screen=Native.GetDC(IntPtr.Zero);
        try{var dest=new Native.POINT(Left,Top);var origin=new Native.POINT(0,0);var size=new Native.SIZE(width,height);var blend=new Native.BLEND{Operation=0,Flags=0,Alpha=255,Format=1};return Native.UpdateLayeredWindow(Handle,screen,ref dest,ref size,source,ref origin,0,ref blend,2);}
        finally{Native.ReleaseDC(IntPtr.Zero,screen);}
    }
    // Each overlay sets its own size and position for the display it is on, so WinForms must not
    // stretch it to Windows' suggested rectangle when it crosses to a display with another DPI.
    protected override void WndProc(ref Message m){if(m.Msg==Native.WM_MOUSEACTIVATE){m.Result=new IntPtr(Native.MA_NOACTIVATE);return;}if(m.Msg==0x2E0){m.Result=IntPtr.Zero;return;}base.WndProc(ref m);}
}

internal sealed class InkWindow:LayeredForm {
    public readonly List<Stroke> Strokes=new List<Stroke>();
    public Stroke Active;
    public bool Dirty=true;
    readonly Controller app;
    // One DIB section kept selected in a memory DC for the window's life: GDI+ draws straight into its
    // pixels and UpdateLayeredWindow reads them from the DC, with no per-frame HBITMAP copy.
    Bitmap buffer;
    IntPtr surfaceDc,surfaceBitmap,surfaceOld;
    Size surfaceSize;
    bool drawingInput;
    Point selectionStart;
    public Rectangle? Selection;
    Point lastSpot=new Point(int.MinValue,int.MinValue);
    // A pinned image being moved by its grip while the pen layer is on top.
    StickerForm moving;
    Point movingGrab;
    public InkWindow(Controller app,Screen screen){this.app=app;Bounds=screen.Bounds;MakeBuffer();Cursor=Cursors.Cross;}
    // This display's DPI factor; ink, hints and grab distances are drawn at that size.
    public float UiScale{get{return Native.ScaleOf(Bounds);}}
    void MakeBuffer(){
        FreeBuffer();surfaceSize=Size;IntPtr bits=IntPtr.Zero;
        var header=new RecorderNative.BITMAPINFOHEADER{Size=Marshal.SizeOf(typeof(RecorderNative.BITMAPINFOHEADER)),Width=Width,Height=-Height,Planes=1,BitCount=32};
        surfaceDc=Native.CreateCompatibleDC(IntPtr.Zero);
        if(surfaceDc!=IntPtr.Zero)surfaceBitmap=RecorderNative.CreateDIBSection(surfaceDc,ref header,0,out bits,IntPtr.Zero,0);
        if(surfaceBitmap!=IntPtr.Zero&&bits!=IntPtr.Zero){surfaceOld=Native.SelectObject(surfaceDc,surfaceBitmap);buffer=new Bitmap(Width,Height,Width*4,PixelFormat.Format32bppPArgb,bits);}
        // Without a DIB section the old, slower path still works.
        else{FreeBuffer();surfaceSize=Size;buffer=new Bitmap(Width,Height,PixelFormat.Format32bppPArgb);}
    }
    void FreeBuffer(){
        if(buffer!=null){buffer.Dispose();buffer=null;}
        if(surfaceOld!=IntPtr.Zero){Native.SelectObject(surfaceDc,surfaceOld);surfaceOld=IntPtr.Zero;}
        if(surfaceBitmap!=IntPtr.Zero){Native.DeleteObject(surfaceBitmap);surfaceBitmap=IntPtr.Zero;}
        if(surfaceDc!=IntPtr.Zero){Native.DeleteDC(surfaceDc);surfaceDc=IntPtr.Zero;}
    }
    public void SetInput(bool enabled){if(drawingInput!=enabled){drawingInput=enabled;Dirty=true;}ClickThrough(!enabled);}
    public void Finish(){if(Active!=null){Active.Created=app.Now;if(!app.AdoptStroke(this,Active))Strokes.Add(Active);Active=null;Dirty=true;}Capture=false;}
    protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);
        // The pen layer sits over pasted captures, so it opens their menu for them.
        if(e.Button==MouseButtons.Right){var sticker=app.StickerAt(PointToScreen(e.Location));if(sticker!=null)sticker.ContextMenuStrip.Show(Cursor.Position);return;}
        if(app.Selecting&&e.Button==MouseButtons.Left){selectionStart=e.Location;Selection=new Rectangle(e.Location,new Size(0,0));Capture=true;Dirty=true;return;}if(app.SpotEditing&&e.Button==MouseButtons.Left){app.SpotDown(this,e.Location);Capture=true;return;}if(!app.Pen||app.Passthrough||e.Button!=MouseButtons.Left)return;
        // The ✕ and the move grip of a pinned image still work while the pen is on.
        var at=new Point(Left+e.X,Top+e.Y);bool close;var handle=app.StickerHandle(at,out close);
        if(handle!=null){if(close)app.RemoveSticker(handle);else{moving=handle;movingGrab=new Point(at.X-handle.Left,at.Y-handle.Top);Capture=true;}return;}
        app.ColorBar.Hide();Active=new Stroke{Color=app.InkColor,Width=app.Preferences.PenWidth*UiScale,Created=app.Now,Fades=app.Preferences.FadingInk};Active.Points.Add(e.Location);app.UndoHistory.Add(this);Capture=true;Dirty=true;}
    protected override void OnMouseMove(MouseEventArgs e){base.OnMouseMove(e);if(moving!=null){if(!moving.IsDisposed)moving.Location=new Point(Left+e.X-movingGrab.X,Top+e.Y-movingGrab.Y);return;}if(Selection.HasValue){Selection=Rectangle.FromLTRB(Math.Min(selectionStart.X,e.X),Math.Min(selectionStart.Y,e.Y),Math.Max(selectionStart.X,e.X),Math.Max(selectionStart.Y,e.Y));Dirty=true;return;}if(app.SpotDragging){app.SpotMove(e.Location);return;}if(Active==null)return;var last=Active.Points[Active.Points.Count-1];if(Math.Abs(last.X-e.X)+Math.Abs(last.Y-e.Y)<1)return;Active.Points.Add(e.Location);Dirty=true;}
    protected override void OnMouseUp(MouseEventArgs e){base.OnMouseUp(e);if(moving!=null){moving=null;Capture=false;return;}if(Selection.HasValue){var area=Selection.Value;Selection=null;Capture=false;Dirty=true;if(app.Selecting)app.FinishSelection(this,area);return;}if(app.SpotDragging){Capture=false;app.SpotUp();return;}Finish();Capture=false;}
    // A dark pill near the top of the display that says what to do next.
    void Hint(Graphics g,string hint,float k){
        using(var font=Look.Pixels(18*k,FontStyle.Bold))using(var text=new SolidBrush(Look.Paper)){var size=g.MeasureString(hint,font);float pad=20*k,height=48*k;var pill=new RectangleF((Width-size.Width)/2-pad,36*k,size.Width+pad*2,height);Look.FillRound(g,Look.Dock,pill,14*k);g.DrawString(hint,font,text,pill.Left+pad,pill.Top+(height-size.Height)/2);}
    }
    public void Render(Point cursor){
        if(Strokes.RemoveAll(s=>s.Alpha(app.Now)<=0)>0)Dirty=true;
        var spot=app.Preferences.Spotlight&&Bounds.Contains(cursor)?new Point(cursor.X-Left,cursor.Y-Top):new Point(int.MinValue,int.MinValue);
        if(spot!=lastSpot){Dirty=true;lastSpot=spot;}
        if(Strokes.Any(s=>s.Fades&&app.Now-s.Created>=3.4))Dirty=true;
        if(!Dirty)return;
        if(buffer==null||surfaceSize!=Size)MakeBuffer();float k=UiScale;
        using(var g=Graphics.FromImage(buffer)){
            // Alpha-zero pixels pass mouse input through even without
            // WS_EX_TRANSPARENT. A 1/255 input surface exists only while drawing.
            g.Clear(drawingInput?Color.FromArgb(1,0,0,0):Color.Transparent);g.SmoothingMode=SmoothingMode.AntiAlias;
            if(app.Preferences.Spotlight){
                using(var path=new GraphicsPath(FillMode.Alternate)){path.AddRectangle(new Rectangle(0,0,Width,Height));if(Bounds.Contains(cursor)){float radius=app.Preferences.SpotlightRadius*k;path.AddEllipse(cursor.X-Left-radius,cursor.Y-Top-radius,radius*2,radius*2);}using(var b=new SolidBrush(Color.FromArgb(125,0,0,0)))g.FillPath(b,path);}
            }
            foreach(var stroke in Strokes)stroke.Draw(g,app.Now);if(Active!=null)Active.Draw(g,Active.Created);
            if(app.SpotView==this&&app.SpotArea.HasValue){using(var path=new GraphicsPath())using(var p=new Pen(Look.SpotLine,3*k)){app.AddSpot(path);g.DrawPath(p,path);}}
            if(app.Selecting){using(var path=new GraphicsPath(FillMode.Alternate)){path.AddRectangle(new Rectangle(0,0,Width,Height));if(Selection.HasValue)path.AddRectangle(Selection.Value);using(var b=new SolidBrush(Color.FromArgb(72,0,0,0)))g.FillPath(b,path);}if(Selection.HasValue)using(var p=new Pen(Look.Lime,2*k))g.DrawRectangle(p,Selection.Value);
                if(!Selection.HasValue)Hint(g,Look.Tr("드래그해서 캡처 · 바로 클립보드에 복사 · Esc 취소","Drag to capture · copied straight to the clipboard · Esc to cancel"),k);}
            // Picking a shape changes nothing on screen until a drag, so say what to do.
            if(app.SpotEditing&&!app.SpotDragging)Hint(g,app.SpotArea.HasValue?Look.Tr("빨간 선을 끌면 크기 조절 · 안쪽을 끌면 이동 · 바깥 클릭이나 Esc로 완료","Drag the red line to resize · drag inside to move · click outside or Esc when done"):Look.Tr("드래그해서 보여 줄 곳을 그리세요 · Esc 취소","Drag to draw the spot · Esc to cancel"),k);
        }
        Dirty=!(surfaceDc!=IntPtr.Zero&&surfaceOld!=IntPtr.Zero?Publish(surfaceDc,buffer.Width,buffer.Height):Publish(buffer));
    }
    protected override void Dispose(bool disposing){if(disposing)FreeBuffer();base.Dispose(disposing);}
}

// The ring that follows the pointer, sized for the display it is on.
internal sealed class HaloWindow:LayeredForm {
    float scale=1;
    int radius=16;
    int Side{get{return Look.Px(116,scale);}}
    public HaloWindow(){Size=new Size(116,116);}
    public void Render(int radius){this.radius=radius;int side=Side;float r=radius*scale;using(var b=new Bitmap(side,side,PixelFormat.Format32bppPArgb))using(var g=Graphics.FromImage(b)){g.SmoothingMode=SmoothingMode.AntiAlias;using(var brush=new SolidBrush(Color.FromArgb(85,245,211,84)))g.FillEllipse(brush,side/2-r,side/2-r,r*2,r*2);Publish(b);}}
    public void Follow(Point p){float next=Native.ScaleAt(p);if(next!=scale){scale=next;Render(radius);}int side=Side;Native.SetWindowPos(Handle,Native.Topmost,p.X-side/2,p.Y-side/2,side,side,0x10);}
}

internal sealed class PulseWindow:LayeredForm {
    public readonly double StartedAt;
    readonly bool right;
    readonly float scale;
    readonly int side;
    public PulseWindow(Point p,bool right,double created){StartedAt=created;this.right=right;scale=Native.ScaleAt(p);side=Look.Px(110,scale);Bounds=new Rectangle(p.X-side/2,p.Y-side/2,side,side);}
    public void Render(double now){float t=(float)Math.Max(0,Math.Min(1,(now-StartedAt)/.55)),r=(15+t*30)*scale,c=side/2;using(var b=new Bitmap(side,side,PixelFormat.Format32bppPArgb))using(var g=Graphics.FromImage(b)){g.SmoothingMode=SmoothingMode.AntiAlias;using(var p=new Pen(Color.FromArgb(Math.Max(0,(int)(220*(1-t))),right?Color.DodgerBlue:Color.Orange),3*scale))g.DrawEllipse(p,c-r,c-r,r*2,r*2);Publish(b);}}
}

// Pressed shortcuts and short notices. It grows to fit the text, up to the width it is given.
internal sealed class KeyWindow:LayeredForm {
    public KeyWindow(){Size=new Size(300,54);}
    public void Render(string text,float scale,int widest){using(var font=Look.Pixels(17f*96f/72f*scale)){
        SizeF size;using(var probe=new Bitmap(1,1))using(var g=Graphics.FromImage(probe))size=g.MeasureString(text,font);
        int height=Look.Px(54,scale),width=Math.Max(Look.Px(60,scale),Math.Min(widest,(int)Math.Ceiling(size.Width+28*scale)+2));
        if(Width!=width||Height!=height)Size=new Size(width,height);
        using(var b=new Bitmap(width,height,PixelFormat.Format32bppPArgb))using(var g=Graphics.FromImage(b)){
            g.SmoothingMode=SmoothingMode.AntiAlias;Look.FillRound(g,Look.Dock,new RectangleF(0,0,Math.Min(width-2,size.Width+28*scale),48*scale),12*scale);using(var brush=new SolidBrush(Look.Paper))g.DrawString(text,font,brush,14*scale,8*scale);Publish(b);
        }
    }}
}

// The countdown, floating on its own. Drag to move, drag the bottom-right corner to resize.
internal sealed class BadgeWindow:LayeredForm {
    readonly Controller app;
    string shown;
    bool shownAlert,resizing;
    double shownScale;
    float shownPop=-1;
    Point start;
    int startWidth;
    public double Zoom=1;
    // The DPI factor of the display the clock is on; Zoom is the size the teacher chose on top of it.
    public float Dpi=1;
    float shownDpi;
    public BadgeWindow(Controller app){this.app=app;Size=new Size(196,76);ClickThrough(false);Cursor=Cursors.SizeAll;}
    public void Render(string text,bool alert,float pop){
        if(text==shown&&alert==shownAlert&&Zoom==shownScale&&Dpi==shownDpi&&pop==shownPop)return;shown=text;shownAlert=alert;shownScale=Zoom;shownDpi=Dpi;shownPop=pop;
        double z=Zoom*Dpi;int w=(int)Math.Round(196*z),h=(int)Math.Round(76*z);if(Width!=w||Height!=h)Size=new Size(w,h);
        using(var b=new Bitmap(w,h,PixelFormat.Format32bppPArgb))using(var g=Graphics.FromImage(b))using(var font=Look.Pixels((float)(38*z),FontStyle.Bold))using(var format=new StringFormat{Alignment=StringAlignment.Center,LineAlignment=StringAlignment.Center}){
            g.SmoothingMode=SmoothingMode.AntiAlias;int alpha=(int)(255*(1-pop));float shrink=1-.85f*pop*pop;
            g.TranslateTransform(w/2f,h/2f);g.ScaleTransform(shrink,shrink);g.TranslateTransform(-w/2f,-h/2f);
            Look.FillRound(g,Color.FromArgb(alpha,alert?Look.Ink[0]:Look.Dock),new RectangleF(0,0,w,h),(float)(16*z));
            using(var brush=new SolidBrush(Color.FromArgb(alpha,Look.Paper)))g.DrawString(text,font,brush,new RectangleF(0,0,w,h),format);
            g.ResetTransform();
            if(pop>0){using(var dot=new SolidBrush(Color.FromArgb(alpha,Look.Lime))){for(int i=0;i<10;i++){double angle=i/10.0*2*Math.PI;float reach=(.15f+.35f*pop)*h,size=(float)(3*z*(1-pop*.5));float x=w/2f+(float)Math.Cos(angle)*reach*2.2f,y=h/2f+(float)Math.Sin(angle)*reach;g.FillEllipse(dot,x-size,y-size,size*2,size*2);}}}
            else using(var grip=new Pen(Color.FromArgb(90,Look.Paper),1.5f*Dpi)){foreach(float inset in new[]{6f,11f})g.DrawLine(grip,w-(float)(inset*z),h-(float)(4*z),w-(float)(4*z),h-(float)(inset*z));}
            Publish(b);
        }
    }
    protected override void OnMouseDown(MouseEventArgs e){
        base.OnMouseDown(e);if(e.Button!=MouseButtons.Left)return;
        int corner=Look.Px(26,Dpi);if(e.X>Width-corner&&e.Y>Height-corner){resizing=true;start=Cursor.Position;startWidth=Width;Capture=true;return;}
        Native.ReleaseCapture();Native.SendMessage(Handle,0xA1,new IntPtr(2),IntPtr.Zero);app.ClockMoved();
    }
    protected override void OnMouseMove(MouseEventArgs e){base.OnMouseMove(e);if(!resizing)return;Zoom=Look.ClockScaleFor((int)Math.Round((startWidth+Cursor.Position.X-start.X)/Dpi));app.ClockResized();}
    protected override void OnMouseUp(MouseEventArgs e){base.OnMouseUp(e);if(!resizing)return;resizing=false;Capture=false;app.ClockMoved();}
}

internal sealed class LensWindow:Form {
    IntPtr magnifier;
    bool transformReady;
    public bool Ready {get{return magnifier!=IntPtr.Zero&&transformReady;}}
    double zoom;
    // The DPI factor the lens is sized for; it follows the pointer from display to display.
    float scale=1;
    public void SetZoom(double level){zoom=level;if(magnifier==IntPtr.Zero)return;var matrix=new Native.MAGTRANSFORM{Values=new float[]{(float)zoom,0,0,0,(float)zoom,0,0,0,1}};transformReady=Native.MagSetWindowTransform(magnifier,ref matrix);}
    public LensWindow(double level){zoom=level;FormBorderStyle=FormBorderStyle.None;StartPosition=FormStartPosition.Manual;ShowInTaskbar=false;TopMost=true;AutoScaleMode=AutoScaleMode.None;Size=new Size(240,164);BackColor=Look.Lime;}
    protected override bool ShowWithoutActivation {get{return true;}}
    protected override CreateParams CreateParams{get{var p=base.CreateParams;p.ExStyle|=Native.WS_EX_LAYERED|Native.WS_EX_TOOLWINDOW|Native.WS_EX_NOACTIVATE|Native.WS_EX_TRANSPARENT;return p;}}
    // Follow sizes the lens for each display itself.
    protected override void WndProc(ref Message m){if(m.Msg==0x2E0){m.Result=IntPtr.Zero;return;}base.WndProc(ref m);}
    protected override void OnHandleCreated(EventArgs e){base.OnHandleCreated(e);Native.SetLayeredWindowAttributes(Handle,0,255,2);magnifier=Native.CreateWindowEx(0,"Magnifier","",0x40000000|0x10000000,3,3,234,158,Handle,IntPtr.Zero,Native.GetModuleHandle(null),IntPtr.Zero);if(magnifier!=IntPtr.Zero){var matrix=new Native.MAGTRANSFORM{Values=new float[]{(float)zoom,0,0,0,(float)zoom,0,0,0,1}};transformReady=Native.MagSetWindowTransform(magnifier,ref matrix);}}
    public bool Exclude(IEnumerable<IntPtr> windows){if(!Ready)return false;var list=windows.Where(h=>h!=IntPtr.Zero).Distinct().ToArray();return Native.MagSetWindowFilterList(magnifier,0,list.Length,list);}
    public bool Follow(Point point){
        if(!Ready)return false;var s=Screen.FromPoint(point).Bounds;float k=Native.ScaleAt(point);
        int width=Look.Px(240,k),height=Look.Px(164,k),inset=Look.Px(3,k);
        if(k!=scale){scale=k;Native.SetWindowPos(magnifier,IntPtr.Zero,inset,inset,width-inset*2,height-inset*2,0x14);}
        int w=(int)((width-inset*2)/zoom),h=(int)((height-inset*2)/zoom);
        int x=Math.Max(s.Left,Math.Min(s.Right-w,point.X-w/2)),y=Math.Max(s.Top,Math.Min(s.Bottom-h,point.Y-h/2));
        int lx=Math.Max(s.Left+Look.Px(12,k),Math.Min(s.Right-width-Look.Px(12,k),point.X+Look.Px(28,k))),ly=Math.Max(s.Top+Look.Px(12,k),Math.Min(s.Bottom-height-Look.Px(86,k),point.Y+Look.Px(20,k)));
        Native.SetWindowPos(Handle,Native.Topmost,lx,ly,width,height,0x10);
        bool result=Native.MagSetWindowSource(magnifier,new Native.RECT(x,y,w,h));Invalidate(true);return result;
    }
}
}
