using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace YelPoint {
internal sealed class ToolButton:Control {
    public bool Selected;
    public string Symbol;
    public float LabelSize=13f;
    public ToolButton(string label,string symbol){Text=label;Symbol=symbol;TabStop=true;AccessibleName=label.Length==0?symbol:label;AccessibleRole=AccessibleRole.PushButton;SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.Selectable,true);}
    protected override void OnKeyDown(KeyEventArgs e){if(e.KeyCode==Keys.Space||e.KeyCode==Keys.Enter){OnClick(EventArgs.Empty);e.Handled=true;}base.OnKeyDown(e);}
    protected override void OnPaint(PaintEventArgs e){
        var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;g.Clear(Parent.BackColor);
        if(Selected)Look.FillRound(g,Look.Lime,new RectangleF(1,1,Width-2,Height-2),11*Height/44f);
        Color c=Selected?Look.Dock:Look.Paper;if(!Enabled)c=Color.FromArgb(90,c);float scale=Height/44f;
        using(var font=Look.Pixels(LabelSize*scale)){
            var text=g.MeasureString(Text,font);float iw=17*scale,total=iw+(Text.Length==0?0:text.Width+6*scale),x=(Width-total)/2;
            DrawSymbol(g,Symbol,c,new RectangleF(x,(Height-iw)/2,iw,iw));
            if(Text.Length>0)using(var b=new SolidBrush(c))g.DrawString(Text,font,b,x+iw+6*scale,(Height-text.Height)/2);
        }
        if(Focused)ControlPaint.DrawFocusRectangle(g,new Rectangle(3,3,Width-6,Height-6));
    }
    internal static void DrawSymbol(Graphics g,string name,Color color,RectangleF r){
        var save=g.Save();g.TranslateTransform(r.X,r.Y);g.ScaleTransform(r.Width/18,r.Height/18);
        using(var pen=new Pen(color,1.5f)){pen.StartCap=pen.EndCap=LineCap.Round;pen.LineJoin=LineJoin.Round;
            if(name=="highlight"){var points=new[]{new PointF(3,2),new PointF(5,16),new PointF(8,11),new PointF(14,11)};g.DrawPolygon(pen,points);}
            else if(name=="zoom"){g.DrawEllipse(pen,2,2,10,10);g.DrawLine(pen,11,11,16,16);}
            else if(name=="pen"){g.DrawPolygon(pen,new[]{new PointF(3,12),new PointF(12,3),new PointF(15,6),new PointF(6,15),new PointF(2,16)});g.DrawLine(pen,10,5,13,8);}
            else if(name=="more"){g.DrawLines(pen,new[]{new PointF(5,7),new PointF(9,11),new PointF(13,7)});}
            else if(name=="settings"){for(int i=0;i<3;i++){int y=4+i*5;g.DrawLine(pen,2,y,16,y);using(var b=new SolidBrush(color))g.FillEllipse(b,4+i*3,y-2,4,4);}}
            else if(name=="hide"){g.DrawEllipse(pen,2,5,14,8);g.DrawEllipse(pen,7,7,4,4);g.DrawLine(pen,3,15,15,3);}
            else if(name=="captions"){g.DrawRectangle(pen,1.5f,3,15,11);g.DrawLine(pen,4,7.5f,8,7.5f);g.DrawLine(pen,10,7.5f,14,7.5f);g.DrawLine(pen,4,10.5f,11,10.5f);}
            else if(name=="board"){g.DrawRectangle(pen,1.5f,3,15,10);g.DrawLine(pen,4,7,9,7);g.DrawLine(pen,4,10,12,10);g.DrawLine(pen,5,15.5f,13,15.5f);}
            else if(name=="qr"){foreach(var c in new[]{new[]{1,1},new[]{11,1},new[]{1,11}})g.DrawRectangle(pen,c[0],c[1],6,6);using(var b=new SolidBrush(color)){g.FillRectangle(b,3,3,2,2);g.FillRectangle(b,13,3,2,2);g.FillRectangle(b,3,13,2,2);g.FillRectangle(b,11,11,2,2);g.FillRectangle(b,15,11,2,2);g.FillRectangle(b,13,13,2,2);g.FillRectangle(b,11,15,2,2);g.FillRectangle(b,15,15,2,2);}}
            else if(name=="phone"){g.DrawRectangle(pen,5,1.5f,8,15);g.DrawLine(pen,8,14,10,14);}
            else if(name=="camera"){g.DrawRectangle(pen,1.5f,5,15,10);g.DrawEllipse(pen,6,7,6,6);g.DrawLine(pen,6,5,7.5f,2.5f);g.DrawLine(pen,7.5f,2.5f,10.5f,2.5f);g.DrawLine(pen,10.5f,2.5f,12,5);}
            else if(name=="rotate"){g.DrawArc(pen,3,3,12,12,-60,300);g.DrawLines(pen,new[]{new PointF(12,1.5f),new PointF(12.5f,4.5f),new PointF(9.5f,5)});}
            else if(name=="light"){g.DrawPolygon(pen,new[]{new PointF(5,2),new PointF(13,2),new PointF(12,7),new PointF(11,8),new PointF(11,16),new PointF(7,16),new PointF(7,8),new PointF(6,7)});g.DrawLine(pen,9,10,9,12);}
            else if(name=="help"){g.DrawEllipse(pen,2,2,14,14);g.DrawArc(pen,6.5f,5,5,4.5f,180,250);g.DrawLine(pen,9,9.5f,9,10.5f);using(var b=new SolidBrush(color))g.FillEllipse(b,8.1f,12.4f,1.8f,1.8f);}
            else if(name=="power"){g.DrawArc(pen,3,3,12,12,-50,280);g.DrawLine(pen,9,1.5f,9,8);}
            else if(name=="spot"){using(var dash=new Pen(color,1.5f){DashStyle=DashStyle.Dash})g.DrawEllipse(dash,2,2,14,14);}
            else if(name=="rect")g.DrawRectangle(pen,2,4,14,10);
            else if(name=="circle")g.DrawEllipse(pen,2,2,14,14);
            else if(name=="checked"){using(var b=new SolidBrush(color))g.FillEllipse(b,1.5f,1.5f,15,15);using(var tick=new Pen(Look.Lime,2f){StartCap=LineCap.Round,EndCap=LineCap.Round,LineJoin=LineJoin.Round})g.DrawLines(tick,new[]{new PointF(5,9.5f),new PointF(8,12.5f),new PointF(13,6)});}
            else if(name=="oval")g.DrawEllipse(pen,1,4,16,10);
            else if(name=="off"){g.DrawLine(pen,4,4,14,14);g.DrawLine(pen,14,4,4,14);}
            else if(name=="record"){g.DrawEllipse(pen,2,2,14,14);using(var b=new SolidBrush(color))g.FillEllipse(b,6,6,6,6);}
            else if(name=="stop"){using(var b=new SolidBrush(color))g.FillRectangle(b,4,4,10,10);}
            else if(name=="timer"){g.DrawEllipse(pen,3,4,12,12);g.DrawLine(pen,9,10,9,7);g.DrawLine(pen,7,2,11,2);}
            else if(name=="capture"||name=="area"){foreach(var c in new[]{new[]{2,6,2,2,6,2},new[]{12,2,16,2,16,6},new[]{16,12,16,16,12,16},new[]{6,16,2,16,2,12}})g.DrawLines(pen,new[]{new PointF(c[0],c[1]),new PointF(c[2],c[3]),new PointF(c[4],c[5])});if(name=="capture")g.DrawEllipse(pen,6,6,6,6);}
            else if(name=="paste"){g.DrawRectangle(pen,4,4,10,12);g.DrawRectangle(pen,7,2,4,3);}
            else if(name=="save"){g.DrawLine(pen,9,2,9,11);g.DrawLines(pen,new[]{new PointF(5,7),new PointF(9,11),new PointF(13,7)});g.DrawLines(pen,new[]{new PointF(3,12),new PointF(3,16),new PointF(15,16),new PointF(15,12)});}
            else if(name=="play"){using(var b=new SolidBrush(color))g.FillPolygon(b,new[]{new PointF(5,3),new PointF(15,9),new PointF(5,15)});}
            else if(name=="pause"){using(var b=new SolidBrush(color)){g.FillRectangle(b,4,3,4,12);g.FillRectangle(b,10,3,4,12);}}
            else if(name=="reset"){g.DrawArc(pen,3,3,12,12,-60,300);g.DrawLines(pen,new[]{new PointF(12,1),new PointF(12,5),new PointF(16,5)});}
            else if(name=="undo"){g.DrawArc(pen,4,5,11,10,200,270);g.DrawLines(pen,new[]{new PointF(3,3),new PointF(3,8),new PointF(8,8)});}
            else if(name=="text"){g.DrawLine(pen,3,3,15,3);g.DrawLine(pen,9,3,9,15);g.DrawLine(pen,6.5f,15,11.5f,15);}
            else if(name=="clear"){g.DrawRectangle(pen,5,5,8,11);g.DrawLine(pen,3,4,15,4);g.DrawLine(pen,7,2,11,2);g.DrawLine(pen,8,8,8,13);g.DrawLine(pen,10,8,10,13);}
            else {using(var b=new SolidBrush(color))g.FillEllipse(b,6,6,6,6);}
        }g.Restore(save);
    }
}

// Standard buttons, check boxes and links call SetFocus on click, which would wake the panel
// and take the keyboard from the lesson app. These never take focus.
internal sealed class QuietButton:Button {public QuietButton(){SetStyle(ControlStyles.Selectable,false);}}
internal sealed class QuietCheckBox:CheckBox {public QuietCheckBox(){SetStyle(ControlStyles.Selectable,false);}}
internal sealed class QuietLink:LinkLabel {protected override void WndProc(ref Message m){if(m.Msg==0x201||m.Msg==0x203){if(Links.Count>0)OnLinkClicked(new LinkLabelLinkClickedEventArgs(Links[0]));return;}base.WndProc(ref m);}}

internal class FloatingForm:Form {
    protected float ScaleFactor=1f;
    // A pinned capture is sized in screen pixels and must stay 1:1 on every display, so it is never rescaled.
    protected bool KeepPixels;
    public event EventHandler ScaleChanged;
    public FloatingForm(){FormBorderStyle=FormBorderStyle.None;StartPosition=FormStartPosition.Manual;ShowInTaskbar=false;TopMost=true;AutoScaleMode=AutoScaleMode.None;ScaleFactor=DeviceDpi/96f;BackColor=Look.Dock;}
    public int S(float value){return (int)Math.Round(value*ScaleFactor);}
    protected override void OnHandleCreated(EventArgs e){base.OnHandleCreated(e);if(!KeepPixels)Rescale(Native.GetDpiForWindow(Handle)/96f,null);}
    void Rescale(float next,Rectangle? suggested){
        if(next<.5f||Math.Abs(next-ScaleFactor)<.001f)return;
        float ratio=next/ScaleFactor;SuspendLayout();
        foreach(Control control in Controls){var r=control.Bounds;control.Bounds=new Rectangle((int)Math.Round(r.X*ratio),(int)Math.Round(r.Y*ratio),(int)Math.Round(r.Width*ratio),(int)Math.Round(r.Height*ratio));if(control.Font.Unit==GraphicsUnit.Pixel){var old=control.Font;control.Font=new Font(old.FontFamily,old.Size*ratio,old.Style,GraphicsUnit.Pixel);old.Dispose();}}
        ScaleFactor=next;Size=new Size((int)Math.Round(Width*ratio),(int)Math.Round(Height*ratio));
        if(suggested.HasValue)Location=suggested.Value.Location;ResumeLayout(false);Invalidate(true);var changed=ScaleChanged;if(changed!=null)changed(this,EventArgs.Empty);
    }
    protected override bool ShowWithoutActivation {get{return true;}}
    // A text box here has to take the keyboard to be typed in. This is the window that had it before; Enter hands it back.
    IntPtr lessonWindow;
    public void RememberForeground(){var w=Native.GetForegroundWindow();if(w!=Handle)lessonWindow=w;}
    public void RestoreForeground(){var w=lessonWindow;lessonWindow=IntPtr.Zero;if(w!=IntPtr.Zero&&w!=Handle)Native.SetForegroundWindow(w);}
    protected override CreateParams CreateParams{get{var p=base.CreateParams;p.ExStyle|=Native.WS_EX_NOACTIVATE;if(!ShowInTaskbar)p.ExStyle|=Native.WS_EX_TOOLWINDOW;return p;}}
    protected override void OnSizeChanged(EventArgs e){base.OnSizeChanged(e);if(Width>0&&Height>0){var old=Region;using(var p=Look.Round(new RectangleF(0,0,Width,Height),S(16)))Region=new Region(p);if(old!=null)old.Dispose();}}
    // Standing toolbar: the panel stands too, its controls flowed into rows of a narrow column (width at 96 DPI), as on the Mac.
    // The flat layout is kept in 96-DPI units from the first call, so lying flat restores it exactly, even after a DPI change.
    Control[] stackControls;RectangleF[] stackFlat;SizeF stackSize;
    public bool Stacked{get;private set;}
    public void Stack(bool vertical,int width){
        if(stackControls==null){stackControls=new Control[Controls.Count];Controls.CopyTo(stackControls,0);stackFlat=new RectangleF[stackControls.Length];for(int i=0;i<stackControls.Length;i++){var r=stackControls[i].Bounds;stackFlat[i]=new RectangleF(r.X/ScaleFactor,r.Y/ScaleFactor,r.Width/ScaleFactor,r.Height/ScaleFactor);}stackSize=new SizeF(Width/ScaleFactor,Height/ScaleFactor);}
        Stacked=vertical;int n=stackControls.Length;var flat=new Rectangle[n];for(int i=0;i<n;i++)flat[i]=new Rectangle(S(stackFlat[i].X),S(stackFlat[i].Y),S(stackFlat[i].Width),S(stackFlat[i].Height));
        if(!vertical){Settle(flat,new Size(S(stackSize.Width),S(stackSize.Height)));return;}
        int pad=S(6),room=S(width)-pad*2;var order=Look.ReadingOrder(flat,S(20));var sizes=new Size[n];
        for(int k=0;k<n;k++){
            var c=stackControls[order[k]];var f=flat[order[k]];sizes[k]=new Size(Math.Min(f.Width,room),f.Height);
            // A long status line (the phone's) wraps onto up to three lines instead of being cut off.
            if(c is Label&&f.Width>room){int line=TextRenderer.MeasureText("가",c.Font).Height,fit=TextRenderer.MeasureText(c.Text,c.Font,new Size(room,10000),TextFormatFlags.WordBreak|TextFormatFlags.TextBoxControl).Height;sizes[k]=new Size(room,Math.Min(Math.Max(f.Height,fit),Math.Max(f.Height,line*3)));}
        }
        int height;var placed=Look.Flow(sizes,S(width),pad,S(4),out height);var bounds=new Rectangle[n];for(int k=0;k<n;k++)bounds[order[k]]=placed[k];Settle(bounds,new Size(S(width),height));
    }
    // Called on every toolbar move, so it repaints only when something changed.
    void Settle(Rectangle[] bounds,Size size){bool changed=size!=Size;for(int i=0;i<bounds.Length;i++)if(stackControls[i].Bounds!=bounds[i]){stackControls[i].Bounds=bounds[i];changed=true;}if(changed){Size=size;Invalidate();}}
    // The short slide and fade that clicks a panel into place when it opens. Only Location and Opacity change, so it never takes focus.
    System.Windows.Forms.Timer slide;Point slideTo,slideFrom;System.Diagnostics.Stopwatch slideClock;bool slideFade;
    // Where the panel rests, even mid-slide.
    public Rectangle Home{get{return new Rectangle(slide!=null?slideTo:Location,Size);}}
    public void MoveTo(Point p){if(slide!=null)slideTo=p;else Location=p;}
    public void SlideIn(Size offset,bool fade){
        EndSlide();slideTo=Location;slideFrom=new Point(offset.Width,offset.Height);slideFade=fade;slideClock=System.Diagnostics.Stopwatch.StartNew();
        Location=slideTo+offset;if(fade)Opacity=0;slide=new System.Windows.Forms.Timer{Interval=10};slide.Tick+=(s,e)=>StepSlide();slide.Start();
    }
    void StepSlide(){
        double t=Math.Min(1,slideClock.Elapsed.TotalSeconds/.14),eased=1-Math.Pow(1-t,3);
        if(t>=1){EndSlide();return;}
        Location=new Point(slideTo.X+(int)Math.Round(slideFrom.X*(1-eased)),slideTo.Y+(int)Math.Round(slideFrom.Y*(1-eased)));if(slideFade)Opacity=eased;
    }
    // Lands at once: the end of the slide, or when the panel is hidden mid-slide.
    void EndSlide(){if(slide==null)return;slide.Stop();slide.Dispose();slide=null;Location=slideTo;if(slideFade){Opacity=1;Invalidate(true);}}
    protected override void OnVisibleChanged(EventArgs e){if(!Visible)EndSlide();base.OnVisibleChanged(e);}
    protected override void Dispose(bool disposing){if(disposing&&slide!=null){slide.Stop();slide.Dispose();slide=null;}base.Dispose(disposing);}
    protected override void WndProc(ref Message m){if(m.Msg==Native.WM_MOUSEACTIVATE){RememberForeground();m.Result=new IntPtr(Native.MA_NOACTIVATE);return;}if(m.Msg==0x2E0){var r=(Native.RECT)System.Runtime.InteropServices.Marshal.PtrToStructure(m.LParam,typeof(Native.RECT));if(!KeepPixels)Rescale((m.WParam.ToInt64()&0xffff)/96f,new Rectangle(r.Left,r.Top,r.Right-r.Left,r.Bottom-r.Top));m.Result=IntPtr.Zero;return;}base.WndProc(ref m);}
}

internal sealed class ToolbarForm:FloatingForm {
    readonly Controller app;
    public readonly ToolButton Highlight,Zoom,Pen,PenOptions,Clock,Grab,CaptureOptions,SpotButton,PhoneButton,QrButton,BoardButton,Settings,HideButton,QuitButton;
    public bool Vertical{get;private set;}
    public ToolbarForm(Controller app){
        this.app=app;Text="YelPoint";Icon=Look.Icon();ShowInTaskbar=true;Size=new Size(S(866),S(56));
        Highlight=Add(Look.Tr("강조","Highlight"),"highlight",20,84,()=>app.Toggle("highlight"));Zoom=Add(Look.Tr("돋보기","Zoom"),"zoom",106,86,()=>app.Toggle("zoom"));Pen=Add(Look.Tr("펜","Pen"),"pen",194,42,()=>app.Toggle("pen"));PenOptions=Add("","more",236,22,()=>app.TogglePenOptions());Clock=Add(Look.Tr("타이머","Timer"),"timer",260,86,()=>app.Toggle("timer"));Grab=Add(Look.Tr("캡처","Capture"),"capture",348,66,()=>app.QuickCapture());CaptureOptions=Add("","more",414,22,()=>app.Toggle("capture"));SpotButton=Add(Look.Tr("스팟","Spot"),"spot",438,76,()=>app.Toggle("spot"));PhoneButton=Add(Look.Tr("폰","Phone"),"phone",516,70,()=>app.Toggle("phone"));PhoneButton.AccessibleName=Look.Tr("안드로이드 폰·태블릿 화면과 실물화상기","Android phone or tablet screen and document camera");QrButton=Add("QR","qr",588,60,()=>app.Toggle("qr"));QrButton.AccessibleName=Look.Tr("주소를 QR 코드로 크게 보여 주기","Show an address as a big QR code");BoardButton=Add(Look.Tr("칠판","Board"),"board",650,70,()=>app.Toggle("board"));BoardButton.AccessibleName=Look.Tr("분필로 쓰는 큰 칠판","A big chalkboard to draw and write on");Settings=Add("","settings",732,38,()=>app.Toggle("settings"));HideButton=Add("","hide",772,38,()=>app.Toggle("hide"));HideButton.AccessibleName=Look.Tr("도구막대 숨기기","Hide toolbar");QuitButton=Add("","power",812,38,()=>app.Quit());QuitButton.AccessibleName=Look.Tr("YelPoint 종료","Quit YelPoint");
        Pen.LabelSize=10f;Grab.LabelSize=11f;Grab.AccessibleName=Look.Tr("영역 캡처 · 미리보기 없이 클립보드에 복사","Capture an area straight to the clipboard");
        PenOptions.AccessibleName=Look.Tr("펜 색과 굵기 열기·닫기","Show or hide pen color and width");CaptureOptions.AccessibleName=Look.Tr("캡처 옵션 · 동영상 녹화·저장","Capture options · video recording and save");
        var tips=new ToolTip{ShowAlways=true};tips.SetToolTip(PenOptions,PenOptions.AccessibleName);tips.SetToolTip(CaptureOptions,CaptureOptions.AccessibleName);Disposed+=(s,e)=>tips.Dispose();
        Settings.AccessibleName=Look.Tr("간단 설정","Settings");
        var menu=new ContextMenuStrip();menu.Items.Add(Look.Tr("사용법","How to Use"),null,(s,e)=>app.Help());menu.Items.Add(Look.Tr("YelPoint 종료","Quit YelPoint"),null,(s,e)=>app.Quit());ContextMenuStrip=menu;
        Move+=(s,e)=>app.PositionChildren();
    }
    public void ArrangeTools(bool vertical){
        // Slim, as on the Mac: 866×56 lying flat, 92×536 standing. The three icon buttons sit higher and shorter, leaving room for the © line.
        Vertical=vertical;Size=vertical?new Size(S(92),S(536)):new Size(S(866),S(56));
        var tools=new[]{Highlight,Zoom,Pen,Clock,Grab,SpotButton,PhoneButton,QrButton,BoardButton};int[] left={20,106,194,260,348,438,516,588,650},width={84,86,64,86,88,76,70,60,70};
        for(int i=0;i<tools.Length;i++)tools[i].Bounds=vertical?new Rectangle(S(6),S(16+i*45),S(80),S(43)):new Rectangle(S(left[i]),S(6),S(width[i]),S(44));
        var penBounds=Pen.Bounds;Pen.Width-=S(22);PenOptions.Bounds=new Rectangle(Pen.Right,penBounds.Top,S(22),penBounds.Height);
        var captureBounds=Grab.Bounds;Grab.Width-=S(22);CaptureOptions.Bounds=new Rectangle(Grab.Right,captureBounds.Top,S(22),captureBounds.Height);
        Settings.Bounds=vertical?new Rectangle(S(6),S(430),S(38),S(40)):new Rectangle(S(732),S(4),S(38),S(34));
        HideButton.Bounds=vertical?new Rectangle(S(48),S(430),S(38),S(40)):new Rectangle(S(772),S(4),S(38),S(34));
        QuitButton.Bounds=vertical?new Rectangle(S(27),S(476),S(38),S(38)):new Rectangle(S(812),S(4),S(38),S(34));
        Invalidate(true);app.PositionChildren();
    }
    Point pressed;
    bool dragging;
    // Moved here rather than by Windows, so the bar can change shape mid-drag.
    void Press(){pressed=Cursor.Position;dragging=false;app.BeginToolbarDrag(pressed);}
    void Follow(){var p=Cursor.Position;if(!dragging&&Math.Abs(p.X-pressed.X)+Math.Abs(p.Y-pressed.Y)<4)return;dragging=true;app.DragToolbar(p);}
    void Release(){if(dragging)app.EndToolbarDrag();dragging=false;}
    // Buttons cover nearly the whole bar, so a drag that starts on one moves the bar.
    // Click fires before MouseUp, so a finished drag is still marked when it arrives.
    ToolButton Add(string label,string symbol,int x,int width,Action action){
        var b=new ToolButton(label,symbol){Bounds=new Rectangle(S(x),S(9),S(width),S(44))};b.Click+=(s,e)=>{if(!dragging)action();};
        b.MouseDown+=(s,e)=>{if(e.Button==MouseButtons.Left)Press();};
        b.MouseMove+=(s,e)=>{if(e.Button==MouseButtons.Left)Follow();};
        b.MouseUp+=(s,e)=>{if(e.Button==MouseButtons.Left)Release();};
        Controls.Add(b);return b;
    }
    public void RefreshButtons(){Highlight.Selected=app.Preferences.Highlight;Zoom.Selected=app.Zoom;Pen.Selected=app.Pen;PenOptions.Selected=app.PenOptionsOpen;CaptureOptions.Selected=app.CaptureBar.Visible;Clock.Selected=app.TimerPanel.Visible||app.Countdown.Active;Grab.Selected=app.CaptureBar.Visible||app.Selecting||app.Recording;Grab.Text=app.Recording?Look.Tr("정지","Stop"):Look.Tr("캡처","Capture");Grab.Symbol=app.Recording?"stop":"capture";SpotButton.Selected=app.SpotBar.Visible||app.SpotArea.HasValue;PhoneButton.Selected=app.PhoneBar.Visible||app.Phone.Running;QrButton.Selected=app.QrBar.Visible||app.QrShowing;BoardButton.Selected=app.BoardOpen;Settings.Selected=app.Settings.Visible;foreach(Control c in Controls)c.Invalidate();}
    protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;using(var b=new SolidBrush(Color.FromArgb(100,Look.Paper))){if(Vertical){for(int x=39;x<=51;x+=6)for(int y=3;y<=8;y+=5)e.Graphics.FillEllipse(b,S(x),S(y),S(2),S(2));}else{for(int x=8;x<=13;x+=5)for(int y=21;y<=33;y+=6)e.Graphics.FillEllipse(b,S(x),S(y),S(2),S(2));}}using(var p=new Pen(Color.FromArgb(50,Look.Paper))){if(Vertical)e.Graphics.DrawLine(p,S(12),S(424),S(80),S(424));else e.Graphics.DrawLine(p,S(726),S(17),S(726),S(39));}using(var font=CreditFont())using(var b=new SolidBrush(Color.FromArgb(184,Look.Paper)))e.Graphics.DrawString(Credit,font,b,CreditRect(e.Graphics).Location);}
    // © mark centered under the power button; a click opens the blog and suggestion popup.
    const string Credit="© yelsam.lab";
    Font CreditFont(){return Look.Pixels(12.5f*ScaleFactor,FontStyle.Bold);}
    Rectangle CreditRect(Graphics g){using(var font=CreditFont()){var size=Size.Ceiling(g.MeasureString(Credit,font));var power=QuitButton.Bounds;int x=Math.Min(power.Left+power.Width/2-size.Width/2,ClientSize.Width-size.Width-S(4));return new Rectangle(x,power.Bottom-S(1),size.Width,size.Height);}}
    protected override void OnMouseDown(MouseEventArgs e){if(e.Button==MouseButtons.Left)Press();base.OnMouseDown(e);}
    protected override void OnMouseMove(MouseEventArgs e){if(e.Button==MouseButtons.Left)Follow();base.OnMouseMove(e);}
    protected override void OnMouseUp(MouseEventArgs e){
        bool clicked=e.Button==MouseButtons.Left&&!dragging;
        if(e.Button==MouseButtons.Left)Release();base.OnMouseUp(e);
        if(!clicked)return;Rectangle credit;using(var g=CreateGraphics())credit=CreditRect(g);credit.Inflate(S(6),S(3));
        if(credit.Contains(e.Location))app.CreditMenu().Show(this,new Point(credit.Left,credit.Bottom));
    }
    protected override void WndProc(ref Message m){
        if(m.Msg==Native.WM_HOTKEY){app.Hotkey(m.WParam.ToInt32());return;}
        if(m.Msg==Controller.ShowMessageId){app.ShowToolbar();return;}
        base.WndProc(ref m);
    }
    // Asked after the close message has been handled, not inside it.
    protected override void OnFormClosing(FormClosingEventArgs e){if(!app.Exiting&&e.CloseReason==CloseReason.UserClosing){e.Cancel=true;BeginInvoke(new Action(app.Quit));return;}base.OnFormClosing(e);}
}

// What the toolbar shrinks to. Click to expand, drag to move.
internal sealed class MiniForm:FloatingForm {
    readonly Controller app;
    Point start;
    bool pressed;
    public MiniForm(Controller app){this.app=app;Size=new Size(S(46),S(46));AccessibleName=Look.Tr("도구막대 보이기","Show toolbar");}
    protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;ToolButton.DrawSymbol(e.Graphics,"highlight",Look.Lime,new RectangleF(S(12),S(12),S(22),S(22)));}
    protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);if(e.Button==MouseButtons.Left){start=Cursor.Position;pressed=true;}}
    protected override void OnMouseMove(MouseEventArgs e){
        base.OnMouseMove(e);if(!pressed)return;var p=Cursor.Position;if(Math.Abs(p.X-start.X)+Math.Abs(p.Y-start.Y)<4)return;
        pressed=false;Native.ReleaseCapture();Native.SendMessage(Handle,0xA1,new IntPtr(2),IntPtr.Zero);app.MiniDropped();
    }
    protected override void OnMouseUp(MouseEventArgs e){base.OnMouseUp(e);if(pressed){pressed=false;app.SetToolbarHidden(false);}}
}

internal sealed class PenForm:FloatingForm {
    readonly Controller app;
    WidthSlider slider;
    WheelButton wheel;
    readonly QuietButton[] dots=new QuietButton[3];
    public void RefreshInk(){wheel.Invalidate();slider.Invalidate();Invalidate();}
    public PenForm(Controller app){
        this.app=app;Size=new Size(S(407),S(48));
        for(int i=0;i<3;i++){int color=i;var b=dots[i]=new QuietButton{FlatStyle=FlatStyle.Flat,Text="●",Font=Look.Pixels(23*ScaleFactor),ForeColor=Look.Ink[i],BackColor=Look.Dock,Bounds=new Rectangle(S(9+i*35),S(6),S(31),S(35)),TabStop=true,AccessibleName=new[]{Look.Tr("주황색","Orange"),Look.Tr("파란색","Blue"),Look.Tr("초록색","Green")}[i]};b.FlatAppearance.BorderSize=0;b.Click+=(s,e)=>{app.Preferences.PenColor=color;app.Preferences.InkRGB=-1;app.Save();RefreshInk();};Controls.Add(b);}
        wheel=new WheelButton(app){Bounds=new Rectangle(S(115),S(10),S(27),S(27))};wheel.Click+=(s,e)=>app.ToggleColors();Controls.Add(wheel);
        slider=new WidthSlider(app){Bounds=new Rectangle(S(150),S(4),S(160),S(40))};Controls.Add(slider);Add("undo",316,()=>app.Undo());Add("clear",361,()=>app.Clear());
    }
    ToolButton Add(string symbol,int x,Action action){var b=new ToolButton("",symbol){Bounds=new Rectangle(S(x),S(4),S(38),S(40)),AccessibleName=symbol=="undo"?Look.Tr("되돌리기","Undo"):Look.Tr("모두 지우기","Clear all")};b.Click+=(s,e)=>action();Controls.Add(b);return b;}
    // Around whichever control is chosen, wherever the layout put it (flat or standing).
    protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);Rectangle chosen=app.Preferences.InkRGB<0?dots[app.Preferences.PenColor].Bounds:wheel.Bounds;using(var p=new Pen(Look.Lime))e.Graphics.DrawEllipse(p,chosen.Left+chosen.Width/2f-S(16),chosen.Top+chosen.Height/2f-S(16),S(32),S(32));}
}

// The knob is drawn at the real pen width, in the current ink.
internal sealed class WidthSlider:Control {
    readonly Controller app;
    bool dragging;
    public WidthSlider(Controller app){this.app=app;TabStop=true;AccessibleName=Look.Tr("펜 굵기","Pen width");AccessibleRole=AccessibleRole.Slider;SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.Selectable,true);}
    float Factor{get{return Height/40f;}}
    float TrackStart{get{return 16*Factor;}}
    float TrackEnd{get{return Width-44*Factor;}}
    protected override void OnPaint(PaintEventArgs e){
        var g=e.Graphics;g.Clear(Parent.BackColor);g.SmoothingMode=SmoothingMode.AntiAlias;float scale=Factor,mid=Height/2f,width=app.Preferences.PenWidth;
        Look.FillRound(g,Color.FromArgb(77,Look.Paper),new RectangleF(TrackStart,mid-1.5f*scale,TrackEnd-TrackStart,3*scale),1.5f*scale);
        float x=TrackStart+(width-1)/29*(TrackEnd-TrackStart),size=Math.Max(12,width)*scale;
        using(var b=new SolidBrush(app.InkColor))g.FillEllipse(b,x-size/2,mid-size/2,size,size);using(var p=new Pen(Look.Paper,2*scale))g.DrawEllipse(p,x-size/2,mid-size/2,size,size);
        using(var font=Look.Pixels(13*scale,FontStyle.Bold))using(var b=new SolidBrush(Look.Paper)){string text=app.Preferences.PenWidth.ToString();var measured=g.MeasureString(text,font);g.DrawString(text,font,b,Width-14*scale-measured.Width,mid-measured.Height/2);}
        if(Focused)ControlPaint.DrawFocusRectangle(g,new Rectangle(1,1,Width-2,Height-2));
    }
    void Pick(int x){app.Preferences.PenWidth=Look.PenWidthAt((x-TrackStart)/(TrackEnd-TrackStart));Invalidate();}
    protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);if(e.Button!=MouseButtons.Left)return;dragging=true;Pick(e.X);}
    protected override void OnMouseMove(MouseEventArgs e){base.OnMouseMove(e);if(dragging)Pick(e.X);}
    protected override void OnMouseUp(MouseEventArgs e){base.OnMouseUp(e);if(dragging){dragging=false;app.Save();}}
    protected override bool IsInputKey(Keys key){return key==Keys.Left||key==Keys.Right||base.IsInputKey(key);}
    protected override void OnKeyDown(KeyEventArgs e){if(e.KeyCode==Keys.Left||e.KeyCode==Keys.Right){app.Preferences.PenWidth=Math.Max(1,Math.Min(30,app.Preferences.PenWidth+(e.KeyCode==Keys.Left?-1:1)));app.Save();Invalidate();e.Handled=true;}base.OnKeyDown(e);}
}

internal static class ColorWheel {
    static Bitmap image;
    // Hue runs around the rim, saturation from centre to rim, as Look.WheelPick reads it back.
    public static Bitmap Image{get{
        if(image!=null)return image;const int size=336;double radius=size/2.0;var b=new Bitmap(size,size,System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        // Built once, in one pass over an array: SetPixel for every pixel stalled the UI thread long enough to cost the mouse hook.
        var pixels=new int[size*size];
        for(int y=0;y<size;y++)for(int x=0;x<size;x++){double dx=x+.5-radius,dy=radius-y-.5,hue,saturation,alpha=Math.Max(0,Math.Min(1,radius-Math.Sqrt(dx*dx+dy*dy)));Look.WheelPick(dx,dy,radius,out hue,out saturation);int rgb=Look.Hsv(hue,saturation,1);pixels[y*size+x]=(int)(255*alpha)<<24|rgb;}
        var data=b.LockBits(new Rectangle(0,0,size,size),System.Drawing.Imaging.ImageLockMode.WriteOnly,System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        try{for(int y=0;y<size;y++)System.Runtime.InteropServices.Marshal.Copy(pixels,y*size,data.Scan0+y*data.Stride,size);}finally{b.UnlockBits(data);}
        image=b;return image;
    }}
}

internal sealed class WheelButton:Control {
    readonly Controller app;
    public WheelButton(Controller app){this.app=app;TabStop=true;AccessibleName=Look.Tr("색상환에서 색 고르기","Pick a color from the wheel");AccessibleRole=AccessibleRole.PushButton;SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.Selectable,true);}
    protected override void OnKeyDown(KeyEventArgs e){if(e.KeyCode==Keys.Space||e.KeyCode==Keys.Enter){OnClick(EventArgs.Empty);e.Handled=true;}base.OnKeyDown(e);}
    protected override void OnPaint(PaintEventArgs e){var g=e.Graphics;g.Clear(Parent.BackColor);g.SmoothingMode=SmoothingMode.AntiAlias;g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.DrawImage(ColorWheel.Image,0,0,Width,Height);float inset=Width*.3f;using(var b=new SolidBrush(app.InkColor))g.FillEllipse(b,inset,inset,Width-inset*2,Height-inset*2);}
}

internal sealed class ColorWheelForm:FloatingForm {
    readonly Controller app;
    double hue,saturation=1,value=1;
    bool tracking,onBar;
    public ColorWheelForm(Controller app){this.app=app;DoubleBuffered=true;Size=new Size(S(196),S(232));AccessibleName=Look.Tr("펜 색상환과 밝기 막대","Pen color wheel and brightness");}
    Rectangle WheelArea{get{return new Rectangle(S(14),S(14),S(168),S(168));}}
    Rectangle BarArea{get{return new Rectangle(S(14),S(198),S(168),S(18));}}
    public void Sync(){var c=app.InkColor;double max=Math.Max(c.R,Math.Max(c.G,c.B))/255.0;value=max;saturation=c.GetSaturation()==0||max==0?0:1-Math.Min(c.R,Math.Min(c.G,c.B))/255.0/max;hue=c.GetHue()/360.0;Invalidate();}
    protected override void OnPaint(PaintEventArgs e){
        base.OnPaint(e);var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;g.InterpolationMode=InterpolationMode.HighQualityBicubic;var wheel=WheelArea;var bar=BarArea;g.DrawImage(ColorWheel.Image,wheel);
        int rgb=Look.Hsv(hue,saturation,1);using(var brush=new LinearGradientBrush(bar,Color.Black,Color.FromArgb(255,(rgb>>16)&255,(rgb>>8)&255,rgb&255),LinearGradientMode.Horizontal))using(var path=Look.Round(bar,bar.Height/2f))g.FillPath(brush,path);
        double angle=hue*2*Math.PI,distance=saturation*wheel.Width/2.0;float mark=S(7);
        using(var p=new Pen(Color.White,S(2))){g.DrawEllipse(p,(float)(wheel.Left+wheel.Width/2.0+Math.Cos(angle)*distance)-mark,(float)(wheel.Top+wheel.Height/2.0-Math.Sin(angle)*distance)-mark,mark*2,mark*2);g.DrawEllipse(p,(float)(bar.Left+value*bar.Width)-mark,bar.Top+bar.Height/2f-mark,mark*2,mark*2);}
    }
    void Pick(Point p){
        if(onBar){var bar=BarArea;value=Math.Max(0,Math.Min(1,(p.X-bar.Left)/(double)bar.Width));}
        else{var wheel=WheelArea;Look.WheelPick(p.X-(wheel.Left+wheel.Width/2.0),wheel.Top+wheel.Height/2.0-p.Y,wheel.Width/2.0,out hue,out saturation);}
        app.SetInk(Look.Hsv(hue,saturation,value));Invalidate();
    }
    protected override void OnMouseDown(MouseEventArgs e){base.OnMouseDown(e);if(e.Button!=MouseButtons.Left)return;var bar=BarArea;bar.Inflate(S(6),S(8));onBar=bar.Contains(e.Location);tracking=true;Pick(e.Location);}
    protected override void OnMouseMove(MouseEventArgs e){base.OnMouseMove(e);if(tracking)Pick(e.Location);}
    protected override void OnMouseUp(MouseEventArgs e){base.OnMouseUp(e);if(tracking){tracking=false;app.Save();}}
}

internal sealed class ZoomForm:FloatingForm {
    readonly Controller app;
    readonly List<Button> buttons=new List<Button>();
    public ZoomForm(Controller app){
        this.app=app;Size=new Size(S(286),S(48));int index=0;
        foreach(double value in Look.ZoomLevels){double level=value;var b=new QuietButton{FlatStyle=FlatStyle.Flat,Text=level+"×",Font=Look.Pixels(13*ScaleFactor,FontStyle.Bold),Bounds=new Rectangle(S(8+index*54),S(7),S(54),S(34)),AccessibleName=Look.Tr("배율","Zoom")+" "+level};b.FlatAppearance.BorderSize=0;b.Click+=(s,e)=>app.SetZoom(level);buttons.Add(b);Controls.Add(b);index++;}
        Sync();
    }
    public void Sync(){for(int i=0;i<buttons.Count;i++){bool selected=Look.ZoomLevels[i]==app.Preferences.Zoom;buttons[i].BackColor=selected?Look.Lime:Look.Dock;buttons[i].ForeColor=selected?Look.Dock:Look.Paper;}}
}

internal sealed class TimerForm:FloatingForm {
    readonly Controller app;
    readonly TextBox minutes;
    readonly ToolButton start;
    readonly List<Button> minuteButtons=new List<Button>();
    public TimerForm(Controller app){
        this.app=app;Size=new Size(S(388),S(48));
        Step("−",8,30,Look.Tr("1분 줄이기","1 minute less"),m=>m-1);Step("+",94,30,Look.Tr("1분 늘리기","1 minute more"),m=>m+1);
        int index=0;foreach(int value in new[]{5,10,30,60}){int minutes=value;Step(minutes.ToString(),136+index*40,38,minutes+Look.Tr("분으로 맞추기"," minutes"),m=>minutes);index++;}
        minutes=new TextBox{Font=Look.Pixels(14*ScaleFactor,FontStyle.Bold),ForeColor=Look.Paper,BackColor=Color.FromArgb(56,68,61),BorderStyle=BorderStyle.None,TextAlign=HorizontalAlignment.Center,MaxLength=2,Bounds=new Rectangle(S(38),S(14),S(32),S(22)),AccessibleName=Look.Tr("분 입력","Minutes")};
        minutes.KeyDown+=(s,e)=>{if(e.KeyCode==Keys.Enter){Commit();e.SuppressKeyPress=true;RestoreForeground();}};minutes.Leave+=(s,e)=>Commit();
        // The toolbar never takes focus, so the box asks for it when clicked.
        minutes.MouseDown+=(s,e)=>{Activate();minutes.Focus();};Controls.Add(minutes);
        Controls.Add(new Label{Text=Look.Tr("분","min"),Font=Look.Pixels(11*ScaleFactor),ForeColor=Look.Paper,BackColor=Look.Dock,TextAlign=ContentAlignment.MiddleLeft,Bounds=new Rectangle(S(71),S(14),S(23),S(22))});
        start=new ToolButton("","play"){Bounds=new Rectangle(S(302),S(4),S(38),S(40))};start.Click+=(s,e)=>app.TimerStartPause();Controls.Add(start);
        var reset=new ToolButton("","reset"){Bounds=new Rectangle(S(342),S(4),S(38),S(40)),AccessibleName=Look.Tr("타이머 초기화","Reset timer")};reset.Click+=(s,e)=>app.TimerReset();Controls.Add(reset);
        Sync();
    }
    void Step(string title,int x,int width,string name,Func<int,int> minutes){var b=new QuietButton{FlatStyle=FlatStyle.Flat,Text=title,Font=Look.Pixels(13*ScaleFactor,FontStyle.Bold),ForeColor=Look.Paper,BackColor=Look.Dock,Bounds=new Rectangle(S(x),S(8),S(width),S(32)),AccessibleName=name};b.FlatAppearance.BorderSize=0;b.Click+=(s,e)=>{app.SetTimer(minutes(app.Countdown.Minutes));this.minutes.Text=app.Countdown.Minutes.ToString();};minuteButtons.Add(b);Controls.Add(b);}
    void Commit(){int value;if(int.TryParse(minutes.Text.Trim(),out value))app.SetTimer(value);else Sync();}
    public void Sync(){if(!minutes.Focused)minutes.Text=app.Countdown.Minutes.ToString();minutes.Enabled=!app.Countdown.Locked;start.Symbol=app.Countdown.Running?"pause":"play";start.AccessibleName=app.Countdown.Running?Look.Tr("일시정지","Pause"):Look.Tr("시작","Start");start.Invalidate();foreach(var b in minuteButtons)b.Enabled=!app.Countdown.Locked;}
}

internal sealed class CaptureForm:FloatingForm {
    readonly Controller app;
    // Held by field, never found by its title, so renaming a button cannot break it.
    readonly ToolButton record,videos;
    public CaptureForm(Controller app){
        this.app=app;Size=new Size(S(446),S(48));
        Add(Look.Tr("사진","Photo"),"area",8,Look.Tr("사진 캡처 · Ctrl+Alt+5 · 드래그해서 영역 선택","Photo capture · Ctrl+Alt+5 · drag to select an area"),()=>app.BeginSelection());Add(Look.Tr("띄우기","Pin"),"paste",94,Look.Tr("필요할 때만 복사한 이미지를 화면에 띄우고 필기","Only when needed: pin the copied image and draw on it"),()=>app.PasteSticker());Add(Look.Tr("저장","Save"),"save",180,Look.Tr("마지막 캡처를 data\\captures에 저장","Save the last capture"),()=>app.SaveCapture());record=Add(Look.Tr("동영상","Video"),"record",266,Look.Tr("화면 녹화 시작·정지","Start or stop recording"),()=>app.ToggleRecording());videos=Add(Look.Tr("내 영상","My Videos"),"play",352,Look.Tr("녹화한 영상 보기 · 자막 넣기","Watch your recordings and add subtitles"),()=>app.ShowMyVideos());
    }
    ToolButton Add(string title,string symbol,int x,string name,Action action){var b=new ToolButton(title,symbol){Bounds=new Rectangle(S(x),S(4),S(86),S(40)),AccessibleName=name};b.Click+=(s,e)=>action();Controls.Add(b);return b;}
    // Locked while recording, so a stray click next to Stop cannot open another window.
    public void Sync(){videos.Enabled=!app.Recording;record.Selected=app.Recording;record.Text=app.Recording?Look.Tr("정지","Stop"):Look.Tr("동영상","Video");record.Symbol=app.Recording?"stop":"record";record.Invalidate();}
}

internal sealed class SpotForm:FloatingForm {
    readonly Controller app;
    readonly ToolButton[] shapes=new ToolButton[3];
    public SpotForm(Controller app){
        this.app=app;Size=new Size(S(360),S(48));
        shapes[0]=Add(Look.Tr("사각","Rect"),"rect",8,()=>app.BeginSpot(SpotShape.Rectangle));shapes[1]=Add(Look.Tr("원","Circle"),"circle",94,()=>app.BeginSpot(SpotShape.Circle));shapes[2]=Add(Look.Tr("타원","Ellipse"),"oval",180,()=>app.BeginSpot(SpotShape.Ellipse));Add(Look.Tr("끄기","Off"),"off",266,()=>app.ClearSpot());
    }
    ToolButton Add(string title,string symbol,int x,Action action){var b=new ToolButton(title,symbol){Bounds=new Rectangle(S(x),S(4),S(86),S(40)),AccessibleName=title==Look.Tr("끄기","Off")?Look.Tr("스팟 끄기","Turn spot off"):title+Look.Tr(" 스팟 그리기"," spot")};b.Click+=(s,e)=>action();Controls.Add(b);return b;}
    public void Sync(){for(int i=0;i<3;i++){shapes[i].Selected=app.EditShape==(SpotShape)i;shapes[i].Invalidate();}}
}

internal sealed class StickerForm:FloatingForm {
    readonly Image image;
    readonly Controller app;
    // Ink and typed notes on this image. They move with it and are saved and copied with it.
    public readonly List<Stroke> Strokes=new List<Stroke>();
    sealed class Note{public string Text;public PointF At;public Color Color;public float Size;}
    readonly List<Note> notes=new List<Note>();
    // true for a note, false for a stroke, in the order they were added, for undo.
    readonly List<bool> order=new List<bool>();
    Point menuPoint;
    TextBox editor;
    Stroke activeStroke;
    readonly QuietButton close;
    public void AddStroke(Stroke stroke){Strokes.Add(stroke);order.Add(false);Invalidate();}
    public bool UndoLast(){if(order.Count==0)return false;bool note=order[order.Count-1];order.RemoveAt(order.Count-1);if(note)notes.RemoveAt(notes.Count-1);else Strokes.RemoveAt(Strokes.Count-1);Invalidate();return true;}
    public void ClearInk(){Strokes.Clear();notes.Clear();order.Clear();Invalidate();}
    public bool HasInk{get{return order.Count>0;}}
    // A copy of the ink, so 모두 지우기 can be undone.
    sealed class SavedInk{public List<Stroke> Strokes;public List<Note> Notes;public List<bool> Order;}
    public object SaveInk(){return new SavedInk{Strokes=new List<Stroke>(Strokes),Notes=new List<Note>(notes),Order=new List<bool>(order)};}
    public void RestoreInk(object saved){var ink=saved as SavedInk;if(ink==null)return;Strokes.Clear();Strokes.AddRange(ink.Strokes);notes.Clear();notes.AddRange(ink.Notes);order.Clear();order.AddRange(ink.Order);Invalidate();}
    // The ✕ and the move grip in this window's coordinates. The pen layer looks them up too.
    public Rectangle CloseArea{get{return close.Bounds;}}
    public Rectangle GripArea{get{return new Rectangle(S(6),S(6),S(24),S(24));}}
    // The labelled buttons under this image (StickerBar); closed with it.
    public StickerBar Bar;
    // 글자 on the button bar: a note at the left middle of the image.
    public void BeginNoteAtLeft(Color color){menuPoint=new Point(S(12),Height/2);BeginNote(color);}
    public void BeginNote(Color color){
        if(editor!=null)return;
        editor=new TextBox{Font=Look.Pixels(24*ScaleFactor,FontStyle.Bold),ForeColor=color,BackColor=Color.White,BorderStyle=BorderStyle.None,Bounds=new Rectangle(menuPoint.X,Math.Max(0,menuPoint.Y-S(16)),S(240),S(32))};
        editor.KeyDown+=(s,e)=>{if(e.KeyCode==Keys.Enter){CommitNote();e.SuppressKeyPress=true;RestoreForeground();}};editor.Leave+=(s,e)=>CommitNote();
        Controls.Add(editor);editor.BringToFront();RememberForeground();Activate();editor.Focus();
    }
    public void FinishNote(){CommitNote();}
    void CommitNote(){
        if(editor==null)return;var box=editor;editor=null;string text=box.Text.Trim();
        if(text.Length>0){notes.Add(new Note{Text=text,At=box.Location,Color=box.ForeColor,Size=box.Font.Size});order.Add(true);app.NoteAdded(this);}
        Controls.Remove(box);box.Dispose();Invalidate();
    }
    void DrawInk(Graphics g){foreach(var stroke in Strokes)stroke.Draw(g,0);if(activeStroke!=null)activeStroke.Draw(g,0);foreach(var note in notes)using(var font=Look.Pixels(note.Size,FontStyle.Bold))using(var brush=new SolidBrush(note.Color))g.DrawString(note.Text,font,brush,note.At);}
    // scale is the DPI factor of the display it is pinned on, for the frame, ✕ and grip only.
    public StickerForm(Controller app,Image image,Size size,float scale){
        KeepPixels=true;ScaleFactor=scale;
        this.app=app;this.image=image;BackColor=Look.Lime;DoubleBuffered=true;Size=size;
        close=new QuietButton{FlatStyle=FlatStyle.Flat,Text="✕",Font=Look.Pixels(12*ScaleFactor),ForeColor=Look.Paper,BackColor=Look.Dock,Bounds=new Rectangle(Math.Max(0,size.Width-S(30)),S(6),S(24),S(24)),AccessibleName=Look.Tr("붙인 이미지 닫기","Close pasted image")};close.FlatAppearance.BorderSize=0;close.Click+=(s,e)=>app.RemoveSticker(this);Controls.Add(close);
        var menu=new ContextMenuStrip();menu.Opening+=(s,e)=>menuPoint=PointToClient(Cursor.Position);
        menu.Items.Add(Look.Tr("글자 넣기","Add text"),null,(s,e)=>BeginNote(app.InkColor));
        menu.Items.Add(Look.Tr("복사하기","Copy"),null,(s,e)=>app.CopySticker(this));
        menu.Items.Add(Look.Tr("복사해서 바로 붙여넣기","Copy and paste into the app"),null,(s,e)=>app.PasteInto(this));menu.Items.Add(new ToolStripSeparator());menu.Items.Add(Look.Tr("저장","Save"),null,(s,e)=>app.SaveCapture(this));menu.Items.Add(new ToolStripSeparator());menu.Items.Add(Look.Tr("닫기","Close"),null,(s,e)=>app.RemoveSticker(this));ContextMenuStrip=menu;
    }
    protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);
        // At 1:1 a smoothing filter only softens the capture, so it copies pixels as they are.
        bool exact=image.Width==Width-S(4)&&image.Height==Height-S(4);
        e.Graphics.InterpolationMode=exact?InterpolationMode.NearestNeighbor:InterpolationMode.HighQualityBicubic;e.Graphics.PixelOffsetMode=exact?PixelOffsetMode.Half:PixelOffsetMode.Default;
        e.Graphics.DrawImage(image,S(2),S(2),Width-S(4),Height-S(4));e.Graphics.PixelOffsetMode=PixelOffsetMode.Default;e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;DrawInk(e.Graphics);
        // A round grip with four arrows at the top-left; it moves the image even while the pen is on.
        var grip=GripArea;using(var b=new SolidBrush(Look.Dock))e.Graphics.FillEllipse(b,grip);
        using(var p=new Pen(Look.Paper,Math.Max(1.5f,1.5f*ScaleFactor)){StartCap=LineCap.Round,EndCap=LineCap.Round,LineJoin=LineJoin.Round}){
            float cx=grip.Left+grip.Width/2f,cy=grip.Top+grip.Height/2f,r=grip.Width*.3f,h=grip.Width*.12f;
            e.Graphics.DrawLine(p,cx-r,cy,cx+r,cy);e.Graphics.DrawLine(p,cx,cy-r,cx,cy+r);
            foreach(var d in new[]{new PointF(-1,0),new PointF(1,0),new PointF(0,-1),new PointF(0,1)}){float tx=cx+d.X*r,ty=cy+d.Y*r;e.Graphics.DrawLines(p,new[]{new PointF(tx-d.X*h+d.Y*h,ty-d.Y*h+d.X*h),new PointF(tx,ty),new PointF(tx-d.X*h-d.Y*h,ty-d.Y*h-d.X*h)});}
        }}
    // The image at its own resolution with the ink drawn on top.
    public Bitmap Composite(){
        var b=new Bitmap(image.Width,image.Height);
        using(var g=Graphics.FromImage(b)){g.InterpolationMode=InterpolationMode.NearestNeighbor;g.PixelOffsetMode=PixelOffsetMode.Half;g.DrawImage(image,0,0,image.Width,image.Height);g.PixelOffsetMode=PixelOffsetMode.Default;g.SmoothingMode=SmoothingMode.AntiAlias;g.ScaleTransform(image.Width/(float)(Width-S(4)),image.Height/(float)(Height-S(4)));g.TranslateTransform(-S(2),-S(2));DrawInk(g);}
        return b;
    }
    bool DrawingOnCapture{get{return app.Pen&&app.CapturePen&&!app.Passthrough&&!app.Selecting&&!app.SpotEditing;}}
    public void RefreshPenCursor(){Cursor=DrawingOnCapture?Cursors.Cross:Cursors.Default;}
    public void FinishStroke(){
        if(activeStroke==null)return;var stroke=activeStroke;activeStroke=null;Capture=false;
        AddStroke(stroke);app.UndoHistory.Add(this);app.Clip(this);
    }
    protected override void OnMouseDown(MouseEventArgs e){
        base.OnMouseDown(e);if(e.Button!=MouseButtons.Left)return;
        if(DrawingOnCapture&&!GripArea.Contains(e.Location)){
            FinishNote();app.ColorBar.Hide();
            activeStroke=new Stroke{Color=app.InkColor,Width=app.Preferences.PenWidth*ScaleFactor,Created=app.Now,Fades=false};
            activeStroke.Points.Add(e.Location);Capture=true;Invalidate();return;
        }
        Native.ReleaseCapture();Native.SendMessage(Handle,0xA1,new IntPtr(2),IntPtr.Zero);
    }
    protected override void OnMouseMove(MouseEventArgs e){
        base.OnMouseMove(e);if(activeStroke==null)return;var last=activeStroke.Points[activeStroke.Points.Count-1];
        if(Math.Abs(last.X-e.X)+Math.Abs(last.Y-e.Y)<1)return;activeStroke.Points.Add(e.Location);Invalidate();
    }
    protected override void OnMouseUp(MouseEventArgs e){base.OnMouseUp(e);if(e.Button==MouseButtons.Left)FinishStroke();}
    protected override void OnMouseCaptureChanged(EventArgs e){base.OnMouseCaptureChanged(e);if(!Capture)FinishStroke();}
    protected override void Dispose(bool disposing){if(disposing){image.Dispose();if(Bar!=null)Bar.Dispose();}base.Dispose(disposing);}
}

// 복사됨 · 저장 · 글자 · 붙여넣기 · 닫기 just under a pinned image. A window of its own at the
// toolbar's level, so it sits above the pen layer and works while drawing. It never takes focus.
internal sealed class StickerBar:FloatingForm {
    readonly StickerForm sticker;
    public StickerBar(Controller app,StickerForm sticker,float scale){
        ScaleFactor=scale;this.sticker=sticker;Size=new Size(S(5*82+8),S(44));AccessibleName=Look.Tr("붙인 이미지 버튼","Pinned image buttons");
        Add(0,Look.Tr("복사","Copy"),"checked",Look.Tr("펜을 유지한 채 복사 · 다른 앱을 클릭하고 Ctrl+V","Copy and keep drawing · click another app and Ctrl+V"),()=>app.CopySticker(sticker)).Selected=true;
        Add(1,Look.Tr("저장","Save"),"save",Look.Tr("PNG로 저장","Save as PNG"),()=>app.SaveCapture(sticker));
        Add(2,Look.Tr("글자","Text"),"text",Look.Tr("그림 위에 글자 쓰기","Type on the image"),()=>sticker.BeginNoteAtLeft(app.InkColor));
        Add(3,Look.Tr("붙여넣기","Paste"),"paste",Look.Tr("앞에 있는 앱에 바로 붙여넣기","Paste into the app in front"),()=>app.PasteInto(sticker));
        Add(4,Look.Tr("닫기","Close"),"off",Look.Tr("이 그림 닫기","Close this image"),()=>app.RemoveSticker(sticker));
        // Follows the image, and finds its place again after a DPI change resizes it.
        sticker.Move+=(s,e)=>Place();sticker.Resize+=(s,e)=>Place();ScaleChanged+=(s,e)=>Place();
    }
    ToolButton Add(int i,string title,string symbol,string name,Action action){var b=new ToolButton(title,symbol){Bounds=new Rectangle(S(4+i*82),S(2),S(82),S(40)),AccessibleName=name};b.Click+=(s,e)=>{if(!sticker.IsDisposed)action();};Controls.Add(b);return b;}
    public void Place(){if(sticker.IsDisposed||IsDisposed)return;Location=Look.BarOrigin(sticker.Bounds,Size,Screen.FromRectangle(sticker.Bounds).WorkingArea,S(6),S(4));}
}

// Shortcut keys as a small two-column table: key on the left, what it does on the right.
internal sealed class ShortcutTable:Control {
    static string[][] Rows{get{return new[]{
        new[]{"Ctrl+Alt 1~6",Look.Tr("1 강조 · 2 돋보기 · 3 펜\n4 타이머 · 5 캡처 · 6 스팟","1 Highlight · 2 Zoom · 3 Pen\n4 Timer · 5 Capture · 6 Spot")},
        new[]{"Ctrl+Alt 0",Look.Tr("도구막대 숨기기 · 다시 보이기","Hide or show the toolbar")},
        new[]{"Esc",Look.Tr("쓰던 도구 끄고 평소 마우스로","Tools off, back to the mouse")},
        new[]{Look.Tr("Alt 꾹","Hold Alt"),Look.Tr("필기 중에 아래 화면 클릭","Click through the ink")},
        new[]{Look.Tr("Ctrl+휠","Ctrl+wheel"),Look.Tr("위로 크게 · 아래로 작게\n(강조 원 · 스팟 크기)","Up larger · down smaller\n(pointer ring, spot)")}};}}
    readonly float scale;
    int KeyWidth{get{return (int)(86*scale);}}
    public ShortcutTable(int width,float scale){
        this.scale=scale;DoubleBuffered=true;BackColor=Look.Paper;
        using(var font=Look.Pixels(11*scale)){int height=(int)(18*scale);foreach(var row in Rows)height+=RowHeight(row[1],font,width)+(int)(5*scale);Size=new Size(width,height);}
    }
    int RowHeight(string text,Font font,int width){return Math.Max((int)(18*scale),TextRenderer.MeasureText(text,font,new Size(width-KeyWidth-(int)(8*scale),400),TextFormatFlags.WordBreak).Height+2);}
    protected override void OnPaint(PaintEventArgs e){
        var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;
        using(var title=Look.Pixels(11.5f*scale,FontStyle.Bold))TextRenderer.DrawText(g,Look.Tr("단축키","Shortcut keys"),title,new Point(0,0),Look.Dock);
        int y=(int)(18*scale),gap=(int)(5*scale),chipHeight=(int)(18*scale);bool first=true;
        using(var font=Look.Pixels(11*scale))using(var bold=Look.Pixels(11*scale,FontStyle.Bold))using(var chip=new SolidBrush(Color.FromArgb(23,Look.Dock)))using(var line=new Pen(Color.FromArgb(20,Look.Dock)))
        foreach(var row in Rows){
            int height=RowHeight(row[1],font,Width);
            if(!first)g.DrawLine(line,0,y-gap/2,Width,y-gap/2);first=false;
            var key=new Rectangle(0,y+(height-chipHeight)/2,KeyWidth,chipHeight);
            using(var path=new GraphicsPath()){int d=(int)(10*scale);path.AddArc(key.X,key.Y,d,d,180,90);path.AddArc(key.Right-d,key.Y,d,d,270,90);path.AddArc(key.Right-d,key.Bottom-d,d,d,0,90);path.AddArc(key.X,key.Bottom-d,d,d,90,90);path.CloseFigure();g.FillPath(chip,path);}
            TextRenderer.DrawText(g,row[0],bold,key,Look.Dock,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter);
            TextRenderer.DrawText(g,row[1],font,new Rectangle(KeyWidth+(int)(8*scale),y+1,Width-KeyWidth-(int)(8*scale),height),Color.FromArgb(217,Look.Dock),TextFormatFlags.WordBreak);
            y+=height+gap;
        }
    }
}

internal sealed class SettingsForm:FloatingForm {
    readonly Controller app;
    readonly CheckBox keys,fade,spot;
    public readonly Label Hint;
    bool syncing;
    public SettingsForm(Controller app){
        this.app=app;BackColor=Look.Paper;Size=new Size(S(294),S(276));
        Controls.Add(new Label{Text="YelPoint",Font=Look.Pixels(15*ScaleFactor,FontStyle.Bold),ForeColor=Look.Dock,Bounds=new Rectangle(S(18),S(14),S(100),S(25))});
        var credit=new QuietLink{Text=Look.Tr("© yelsam.lab · 블로그·제안","© yelsam.lab · Blog·Ideas"),Font=Look.Pixels(11*ScaleFactor),TextAlign=ContentAlignment.MiddleRight,LinkColor=Look.Dock,ActiveLinkColor=Look.Dock,LinkBehavior=LinkBehavior.HoverUnderline,Bounds=new Rectangle(S(120),S(16),S(156),S(20)),AccessibleName=Look.Tr("yelsam.lab 블로그와 제안","yelsam.lab blog and suggestions")};credit.LinkClicked+=(s,e)=>app.CreditMenu().Show(credit,new Point(0,credit.Height));Controls.Add(credit);
        keys=Add(Look.Tr("단축키 표시","Show shortcut keys"),49,()=>app.Preferences.KeyboardHUD=keys.Checked);
        fade=Add(Look.Tr("필기 자동 지우기 (4초)","Fade ink after 4 seconds"),80,()=>app.Preferences.FadingInk=fade.Checked);
        spot=Add(Look.Tr("주변 어둡게","Dim around pointer"),111,()=>{app.Preferences.Spotlight=spot.Checked;app.DirtyInk();});
        var table=new ShortcutTable(S(262),ScaleFactor){Location=new Point(S(18),S(140))};Controls.Add(table);
        int y=table.Bottom+S(4);
        // Replaced by a warning if a shortcut or the click display could not start.
        Hint=new Label{Text=Look.Tr("단축키가 안 되면 도구막대 버튼을 눌러 주세요.","If a shortcut does not work, use the toolbar buttons."),Font=Look.Pixels(11*ScaleFactor),ForeColor=Color.FromArgb(180,Look.Dock),Bounds=new Rectangle(S(18),y,S(262),S(30))};Controls.Add(Hint);
        y+=S(34);
        Controls.Add(new Label{Text="언어 / Language",Font=Look.Pixels(11*ScaleFactor),ForeColor=Look.Dock,Bounds=new Rectangle(S(18),y+S(3),S(104),S(20))});
        var korean=new QuietButton{Text="한국어",Bounds=new Rectangle(S(124),y,S(72),S(26)),Font=Look.Pixels(12*ScaleFactor),Enabled=Look.English};korean.Click+=(s,e)=>app.SetLanguage(false);Controls.Add(korean);
        var english=new QuietButton{Text="English",Bounds=new Rectangle(S(202),y,S(72),S(26)),Font=Look.Pixels(12*ScaleFactor),Enabled=!Look.English};english.Click+=(s,e)=>app.SetLanguage(true);Controls.Add(english);
        y+=S(34);
        var help=new QuietButton{Text=Look.Tr("사용법","How to Use"),Bounds=new Rectangle(S(18),y,S(116),S(28)),Font=Look.Pixels(12*ScaleFactor)};help.Click+=(s,e)=>app.Help();Controls.Add(help);
        var quit=new QuietButton{Text=Look.Tr("종료","Quit"),Bounds=new Rectangle(S(158),y,S(116),S(28)),Font=Look.Pixels(12*ScaleFactor)};quit.Click+=(s,e)=>app.Quit();Controls.Add(quit);
        Size=new Size(S(294),y+S(41));
    }
    CheckBox Add(string title,int y,Action apply){var check=new QuietCheckBox{Text=title,Bounds=new Rectangle(S(18),S(y),S(260),S(26)),Font=Look.Pixels(12*ScaleFactor),ForeColor=Look.Dock};check.CheckedChanged+=(s,e)=>{if(syncing)return;apply();app.ConfigureKeys();app.Save();};Controls.Add(check);return check;}
    public void Sync(){syncing=true;keys.Checked=app.Preferences.KeyboardHUD;fade.Checked=app.Preferences.FadingInk;spot.Checked=app.Preferences.Spotlight;syncing=false;}
}
}
