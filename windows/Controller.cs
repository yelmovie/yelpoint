using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace YelPoint {
internal sealed class Controller:ApplicationContext {
    public Preferences Preferences;
    public bool Pen,Zoom,Passthrough,Exiting,Selecting;
    // Capture ink belongs to the pinned images. Other apps remain clickable while this pen stays on.
    public bool CapturePen;
    public bool PenOptionsOpen{get;private set;}
    bool pendingPanelDismiss;
    public readonly Countdown Countdown=new Countdown();
    public TimerForm TimerPanel;
    public CaptureForm CaptureBar;
    public PhoneForm PhoneBar;
    public QrForm QrBar;
    QrWindow qrWindow;
    BoardForm board;
    public bool BoardOpen{get{return board!=null&&board.Visible;}}
    public bool QrShowing{get{return qrWindow!=null&&qrWindow.Visible;}}
    public PhoneLink Phone;
    // The teacher closed the phone window; do not reopen it until the phone is unplugged.
    bool phoneDismissed;
    // Whether the phone was ready at the last change, so only becoming ready opens it by itself.
    bool phoneWasReady;
    public ColorWheelForm ColorBar;
    public SpotForm SpotBar;
    public ZoomForm ZoomBar;
    MiniForm mini;
    ScreenRecorder recorder;
    public bool Recording{get{return recorder!=null;}}
    public SpotShape? EditShape;
    public InkWindow SpotView;
    public RectangleF? SpotArea;
    SpotShape spotShape;
    enum SpotAction {None,Move,Resize,Draw}
    SpotAction spotAction;
    int spotHandle;
    PointF spotPoint;
    RectangleF? spotPrevious;
    SpotShape spotPreviousShape;
    InkWindow spotPreviousView;
    public bool SpotEditing{get{return EditShape.HasValue;}}
    public bool SpotDragging{get{return spotAction!=SpotAction.None;}}
    public Color InkColor{get{int c=Preferences.InkRGB;return c<0?Look.Ink[Preferences.PenColor]:Color.FromArgb(255,(c>>16)&255,(c>>8)&255,c&255);}}
    int pendingPointerSteps;
    public readonly List<StickerForm> Stickers=new List<StickerForm>();
    Image lastCapture;
    BadgeWindow badge;
    Cursor captureCursor;
    System.Media.SoundPlayer pop;
    public ToolbarForm Toolbar;
    public PenForm Penbar;
    public SettingsForm Settings;
    public readonly List<InkWindow> Ink=new List<InkWindow>();
    public readonly List<object> UndoHistory=new List<object>();
    public static readonly int ShowMessageId=Program.ShowMessageId;
    readonly Storage storage;
    readonly Stopwatch watch=Stopwatch.StartNew();
    readonly Timer timer=new Timer{Interval=25};
    readonly List<PulseWindow> pulses=new List<PulseWindow>();
    struct PendingClick {public Point Point;public bool Right;}
    readonly Queue<PendingClick> pendingClicks=new Queue<PendingClick>();
    string pendingKey,lastKey;
    double lastKeyAt;
    Point previousPointer=new Point(int.MinValue,int.MinValue);
    HaloWindow halo;
    LensWindow lens;
    KeyWindow keyboard;
    NotifyIcon tray;
    Native.Hook mouseCallback,keyCallback;
    IntPtr mouseHook,keyHook;
    bool escapeRegistered,modal,magAvailable;
    double keyUntil;
    // Last tick, last mouse-hook call, last time the hooks were put back. See Tick.
    double lastTick,hookSeen,hookFixed;
    bool hookDue;
    public double Now{get{return watch.Elapsed.TotalSeconds;}}
    public Controller(Storage storage){
        this.storage=storage;Preferences=storage.Load();Look.English=Preferences.English;
        magAvailable=Native.MagInitialize();
        Toolbar=new ToolbarForm(this);Penbar=new PenForm(this);Settings=new SettingsForm(this);TimerPanel=new TimerForm(this);CaptureBar=new CaptureForm(this);PhoneBar=new PhoneForm(this);QrBar=new QrForm(this);qrWindow=new QrWindow(this);board=new BoardForm(this);ColorBar=new ColorWheelForm(this);SpotBar=new SpotForm(this);ZoomBar=new ZoomForm(this);mini=new MiniForm(this);halo=new HaloWindow();keyboard=new KeyWindow();badge=new BadgeWindow(this);captureCursor=MakeCaptureCursor();
        // Synthesised for this app, see assets/pop.wav.
        var popStream=System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("pop.wav");if(popStream!=null){pop=new System.Media.SoundPlayer(popStream);pop.Load();}
        Toolbar.ScaleChanged+=(s,e)=>PositionChildren();Penbar.ScaleChanged+=(s,e)=>PositionChildren();Settings.ScaleChanged+=(s,e)=>PositionChildren();TimerPanel.ScaleChanged+=(s,e)=>PositionChildren();CaptureBar.ScaleChanged+=(s,e)=>PositionChildren();ColorBar.ScaleChanged+=(s,e)=>PositionChildren();SpotBar.ScaleChanged+=(s,e)=>PositionChildren();ZoomBar.ScaleChanged+=(s,e)=>PositionChildren();PhoneBar.ScaleChanged+=(s,e)=>PositionChildren();QrBar.ScaleChanged+=(s,e)=>PositionChildren();
        Phone=new PhoneLink(Toolbar,storage.DirectoryPath);Phone.Changed+=PhoneChanged;Phone.Closed+=PhoneClosed;Phone.Recorded+=PhoneRecorded;
        MainForm=Toolbar;RebuildScreens();PlaceToolbar();
        halo.Show();halo.Render(Preferences.HaloRadius);
        mouseCallback=MouseEvent;mouseHook=Native.SetWindowsHookEx(14,mouseCallback,Native.GetModuleHandle(null),0);hookSeen=Now;
        if(mouseHook==IntPtr.Zero)Settings.Hint.Text=Look.Tr("클릭 표시를 시작하지 못했어요.\n앱을 다시 실행해 주세요.","Could not start click display.\nPlease restart the app.");
        ConfigureKeys();
        for(int i=1;i<=7;i++)if(!Native.RegisterHotKey(Toolbar.Handle,i,0x4000|0x0001|0x0002,i==7?(uint)'0':(uint)('0'+i)))Settings.Hint.Text=Look.Tr("단축키 일부가 다른 앱과 겹쳐요.\n도구막대 버튼으로 사용할 수 있어요.","Some shortcuts clash with another app.\nYou can use the toolbar buttons instead.");
        tray=new NotifyIcon{Icon=Look.Icon(),Text="YelPoint",Visible=true};
        var menu=new ContextMenuStrip();menu.Items.Add(Look.Tr("도구막대 보기","Show Toolbar"),null,(s,e)=>ShowToolbar());menu.Items.Add(Look.Tr("사용법","How to Use"),null,(s,e)=>Help());menu.Items.Add(Look.Tr("종료","Quit"),null,(s,e)=>Quit());tray.ContextMenuStrip=menu;tray.DoubleClick+=(s,e)=>ShowToolbar();
        SystemEvents.DisplaySettingsChanged+=DisplayChanged;SystemEvents.PowerModeChanged+=PowerChanged;
        timer.Tick+=(s,e)=>Tick();timer.Start();RefreshTools();
        if(smokeTest){var smoke=new Timer{Interval=1500};smoke.Tick+=(s,e)=>{smoke.Stop();smoke.Dispose();Exit();};smoke.Start();}
    }
    // The way back if the toolbar is lost: unhide it at the default spot.
    public void ShowToolbar(){if(Exiting)return;Preferences.ToolbarVertical=false;Toolbar.ArrangeTools(false);CenterToolbar();SetToolbarHidden(false);}
    void CenterToolbar(){var area=Screen.FromPoint(Cursor.Position).WorkingArea;Toolbar.Location=new Point(area.Left+(area.Width-Toolbar.Width)/2,area.Bottom-Toolbar.Height-18);}
    // Restores the spot and hidden state the user left.
    void PlaceToolbar(){if(Exiting)return;Toolbar.ArrangeTools(Preferences.ToolbarVertical);if(Preferences.ToolbarPlaced)Toolbar.Location=new Point(Preferences.ToolbarX,Preferences.ToolbarY);else CenterToolbar();SetToolbarHidden(Preferences.ToolbarHidden);}
    static void KeepOnScreen(Form form){form.Location=Look.Clamp(form.Bounds,Screen.FromRectangle(form.Bounds).WorkingArea);}
    void RememberToolbar(){Preferences.ToolbarPlaced=true;Preferences.ToolbarX=Toolbar.Left;Preferences.ToolbarY=Toolbar.Top;Save();}
    Point dragGrab;
    int dragSide,dragFlipX;
    Rectangle dragArea;
    void SetToolbarShape(bool vertical){Preferences.ToolbarVertical=vertical;Toolbar.ArrangeTools(vertical);}
    public void BeginToolbarDrag(Point p){dragGrab=new Point(p.X-Toolbar.Left,p.Y-Toolbar.Top);dragArea=Screen.FromPoint(p).WorkingArea;dragFlipX=p.X;dragSide=Toolbar.Vertical?(Toolbar.Left+Toolbar.Width/2<dragArea.Left+dragArea.Width/2?-1:1):0;}
    // The bar stands up the moment it reaches a side edge and lies flat again once pulled inward.
    public void DragToolbar(Point p){
        var area=Screen.FromPoint(p).WorkingArea;
        if(dragSide!=0){
            if(area==dragArea&&!Look.LiesFlat(dragSide,dragFlipX,p.X)){PinToolbar(area,p.Y);return;}
            SetToolbarShape(false);var flat=Look.FlatOrigin(p,Toolbar.Size,area);Toolbar.Location=flat;dragGrab=new Point(p.X-flat.X,p.Y-flat.Y);dragSide=0;return;
        }
        Toolbar.Location=new Point(p.X-dragGrab.X,p.Y-dragGrab.Y);
        int edge=Look.ToolbarEdge(Toolbar.Bounds,p.X,area);if(edge==0)return;
        SetToolbarShape(true);dragSide=edge;dragFlipX=p.X;dragArea=area;PinToolbar(area,p.Y);
    }
    void PinToolbar(Rectangle area,int y){Toolbar.Location=Look.Clamp(new Rectangle(dragSide<0?area.Left+8:area.Right-Toolbar.Width-8,y-Toolbar.Height/2,Toolbar.Width,Toolbar.Height),area);}
    public void EndToolbarDrag(){KeepOnScreen(Toolbar);PositionChildren();RememberToolbar();}
    // The hidden toolbar follows, so tools keep choosing the display the user is on.
    public void MiniDropped(){KeepOnScreen(mini);Toolbar.Location=new Point(mini.Left,mini.Top-8);RememberToolbar();}
    public void SetToolbarHidden(bool hidden){
        Preferences.ToolbarHidden=hidden;
        if(hidden){HidePanels();mini.Location=new Point(Toolbar.Left,Toolbar.Top+8);KeepOnScreen(mini);Toolbar.Hide();mini.Show();}
        else{mini.Hide();KeepOnScreen(Toolbar);Toolbar.Show();PositionChildren();}
        RefreshTools();Save();
    }
    public void PositionChildren(){
        if(Toolbar==null||Penbar==null||Settings==null||TimerPanel==null||CaptureBar==null||ColorBar==null||SpotBar==null||ZoomBar==null||PhoneBar==null||QrBar==null)return;
        var area=Screen.FromControl(Toolbar).WorkingArea;var bar=Toolbar.Bounds;bool vertical=Toolbar.Vertical;int gap=Toolbar.S(4);
        // Standing bar: every panel stands too, in a narrow column (96-DPI widths, as on the Mac). The settings card already does.
        // Each attaches like a magnet beside or above the button that opened it.
        var panels=new FloatingForm[]{Penbar,Settings,TimerPanel,CaptureBar,SpotBar,ZoomBar,PhoneBar,QrBar};var openers=new ToolButton[]{Toolbar.PenOptions,Toolbar.Settings,Toolbar.Clock,Toolbar.CaptureOptions,Toolbar.SpotButton,Toolbar.Zoom,Toolbar.PhoneButton,Toolbar.QrButton};int[] columns={140,0,140,116,102,128,212,232};
        for(int i=0;i<panels.Length;i++){
            if(columns[i]>0)panels[i].Stack(vertical,columns[i]);var b=openers[i].Bounds;var opener=new Rectangle(bar.Left+b.Left,bar.Top+b.Top,b.Width,b.Height);
            panels[i].MoveTo(vertical?Look.SideOrigin(bar,panels[i].Size,area,gap,opener):Look.ChildOrigin(bar,panels[i].Size,area,gap,opener));
        }
        var pen=Rectangle.Union(bar,Penbar.Home);ColorBar.MoveTo(vertical?Look.SideOrigin(pen,ColorBar.Size,area,gap):Look.ChildOrigin(pen,ColorBar.Size,area,gap));
    }
    // Opens a panel against the toolbar with a short slide and fade, so it clicks into place. Already open, it just stays.
    readonly bool smokeTest=Environment.GetCommandLineArgs().Contains("--smoke-test");
    void Present(FloatingForm child){
        if(child.Visible||smokeTest){child.Show();return;}
        PositionChildren();var home=child.Home;var bar=Toolbar.Bounds;int step=Toolbar.S(12);
        // Starts 12 px toward the toolbar, fully transparent.
        child.SlideIn(Toolbar.Vertical?new Size(home.Left+home.Width/2>bar.Left+bar.Width/2?-step:step,0):new Size(0,home.Top+home.Height/2<bar.Top+bar.Height/2?step:-step),true);
        child.Show();
    }
    public void TogglePenOptions(){
        if(Exiting||modal)return;bool open=!PenOptionsOpen;Finish();HidePanels();
        PenOptionsOpen=open;RefreshTools();DirtyInk();
    }
    // The main camera is one click to select. Recording and less-used actions live under its arrow.
    public void QuickCapture(){if(Recording)ToggleRecording();else BeginSelection();}
    public void CloseToolPanels(){if(Exiting||modal)return;HidePanels();RefreshTools();}
    public void Toggle(string name){
        if(Exiting||modal)return;
        if(name=="highlight"){Preferences.Highlight=!Preferences.Highlight;Save();}
        else if(name=="pen"){Finish();Pen=!Pen;CapturePen=false;if(Pen){StopZoom();RaiseOverlays();}HidePanels();}
        else if(name=="zoom"){
            if(Zoom)StopZoom();else if(!magAvailable)Message(Look.Tr("돋보기를 시작하지 못했어요","Could not start the magnifier"),Look.Tr("이 Windows에서 확대 기능을 시작할 수 없어요. 강조와 펜은 사용할 수 있어요.","Magnification is not available on this Windows. Highlight and Pen still work."));
            else{Finish();Pen=false;HidePanels();lens=new LensWindow(Preferences.Zoom);lens.Show();if(!lens.Ready||!UpdateExclusions()){lens.Dispose();lens=null;Message(Look.Tr("돋보기를 시작하지 못했어요","Could not start the magnifier"),Look.Tr("Windows 확대 기능을 만들지 못했어요. 앱을 다시 실행해 주세요.","Could not create the Windows magnifier. Please restart the app."));}else{Zoom=true;}}
        }
        else if(name=="settings"){if(Settings.Visible)Settings.Hide();else{Finish();Pen=false;HidePanels();Settings.Sync();Present(Settings);}}
        else if(name=="timer"){if(TimerPanel.Visible)TimerPanel.Hide();else{Finish();Pen=false;HidePanels();TimerPanel.Sync();Present(TimerPanel);}}
        else if(name=="hide")SetToolbarHidden(!Preferences.ToolbarHidden);
        else if(name=="spot"){if(SpotBar.Visible){EditShape=null;SpotBar.Hide();}else{Finish();Pen=false;HidePanels();Present(SpotBar);}}
        // Show still capture and video recording together, rather than hiding recording behind an extra click.
        else if(name=="capture"){if(CaptureBar.Visible)CaptureBar.Hide();else{Finish();HidePanels();StopZoom();CaptureBar.Sync();Present(CaptureBar);}}
        else if(name=="board"){if(BoardOpen)CloseBoard();else OpenBoard();}
        else if(name=="qr"){if(QrBar.Visible||QrShowing)CloseQr();else{Finish();Pen=false;HidePanels();QrBar.Field.Text=Preferences.QrText??"";Present(QrBar);QrBar.RememberForeground();QrBar.Activate();QrBar.Field.Focus();QrBar.Field.SelectAll();}}
        else if(name=="phone"){if(PhoneBar.Visible)PhoneBar.Hide();else{Finish();Pen=false;HidePanels();PhoneBar.Sync();Present(PhoneBar);}}
        RefreshTools();DirtyInk();
    }
    public void Hotkey(int id){if(Exiting||modal)return;if(id==99){Finish();Pen=false;StopZoom();HidePanels();qrWindow.Hide();RefreshTools();DirtyInk();}else if(id==5){BeginSelection();}else if(id>=1&&id<=7)Toggle(new[]{"highlight","zoom","pen","timer","capture","spot","hide"}[id-1]);}
    void HidePanels(){pendingPanelDismiss=false;PenOptionsOpen=false;Penbar.Hide();ColorBar.Hide();if(Selecting)SelectionCursor(false);Selecting=false;EditShape=null;spotAction=SpotAction.None;foreach(var view in Ink)view.Selection=null;Settings.Hide();TimerPanel.Hide();CaptureBar.Hide();SpotBar.Hide();PhoneBar.Hide();QrBar.Hide();DirtyInk();}
    public void BeginSpot(SpotShape shape){
        if(Exiting||modal)return;Finish();Pen=false;StopZoom();EditShape=shape;
        if(SpotArea.HasValue){spotShape=shape;if(shape==SpotShape.Circle){var r=SpotArea.Value;float side=Math.Max(r.Width,r.Height);SpotArea=new RectangleF(r.Left+r.Width/2-side/2,r.Top+r.Height/2-side/2,side,side);}}
        RefreshTools();DirtyInk();
    }
    public void ClearSpot(){SpotArea=null;SpotView=null;EditShape=null;spotAction=SpotAction.None;RefreshTools();DirtyInk();}
    public void AddSpot(System.Drawing.Drawing2D.GraphicsPath path){if(spotShape==SpotShape.Rectangle)path.AddRectangle(SpotArea.Value);else path.AddEllipse(SpotArea.Value);}
    public void SpotDown(InkWindow view,Point p){
        if(!EditShape.HasValue)return;
        if(SpotView==view&&SpotArea.HasValue){
            int handle=Spot.HandleAt(p,spotShape,SpotArea.Value,10*view.UiScale);if(handle>=0){spotAction=SpotAction.Resize;spotHandle=handle;return;}
            if(Spot.Contains(spotShape,SpotArea.Value,p)){spotAction=SpotAction.Move;spotPoint=new PointF(p.X-SpotArea.Value.Left,p.Y-SpotArea.Value.Top);return;}
        }
        spotPrevious=SpotArea;spotPreviousShape=spotShape;spotPreviousView=SpotView;var other=SpotView;
        spotAction=SpotAction.Draw;spotPoint=p;spotShape=EditShape.Value;SpotView=view;SpotArea=new RectangleF(p,new SizeF(0,0));view.Dirty=true;if(other!=null)other.Dirty=true;
    }
    public void SpotMove(Point p){
        if(!SpotArea.HasValue)return;bool square=spotShape==SpotShape.Circle;var r=SpotArea.Value;
        if(spotAction==SpotAction.Move)SpotArea=new RectangleF(p.X-spotPoint.X,p.Y-spotPoint.Y,r.Width,r.Height);
        else if(spotAction==SpotAction.Resize)SpotArea=Spot.Resized(r,spotHandle,p,square);
        else if(spotAction==SpotAction.Draw)SpotArea=Spot.FromDrag(spotPoint,p,square);
        DirtyInk();
    }
    // A click outside the shape keeps the old spot and hands the mouse back to other apps.
    public void SpotUp(){
        bool cancelled=spotAction==SpotAction.Draw&&SpotArea.HasValue&&Math.Min(SpotArea.Value.Width,SpotArea.Value.Height)<Spot.MinimumSize;spotAction=SpotAction.None;
        if(cancelled){SpotArea=spotPrevious;spotShape=spotPreviousShape;SpotView=spotPreviousView;EditShape=null;RefreshTools();}
        DirtyInk();
    }
    public void SetTimer(int minutes){Countdown.Set(minutes);TimerChanged();}
    public void TimerStartPause(){Countdown.StartOrPause(Now);TimerChanged();}
    public void TimerReset(){Countdown.Reset();TimerChanged();}
    void TimerChanged(){TimerPanel.Sync();Toolbar.RefreshButtons();}
    void Toast(string text){pendingKey=text;}
    // Where the user left it, or the top-right corner of the toolbar's display.
    void PlaceClock(){
        var work=Screen.FromControl(Toolbar).WorkingArea;badge.Zoom=Preferences.ClockScale;badge.Dpi=Preferences.ClockPlaced?Native.ScaleAt(new Point(Preferences.ClockX,Preferences.ClockY)):Native.ScaleOf(work);
        double z=badge.Zoom*badge.Dpi;int w=(int)Math.Round(196*z),h=(int)Math.Round(76*z);
        badge.Bounds=Preferences.ClockPlaced?new Rectangle(Preferences.ClockX,Preferences.ClockY,w,h):new Rectangle(work.Right-w-Look.Px(24,badge.Dpi),work.Top+Look.Px(16,badge.Dpi),w,h);KeepOnScreen(badge);
    }
    public void ClockResized(){string clock=Countdown.Badge(Now);if(clock!=null)badge.Render(clock,Countdown.Alert(Now),Countdown.Pop(Now));}
    // Dragged to another display: redraw it at that display's size.
    public void ClockMoved(){float dpi=Native.ScaleOf(badge.Bounds);if(dpi!=badge.Dpi){badge.Dpi=dpi;ClockResized();}KeepOnScreen(badge);Preferences.ClockPlaced=true;Preferences.ClockX=badge.Left;Preferences.ClockY=badge.Top;Preferences.ClockScale=badge.Zoom;Save();}
    public void SetZoom(double level){Preferences.Zoom=level;Save();if(lens!=null)lens.SetZoom(level);ZoomBar.Sync();}
    // Every form takes its text at launch, so a language change restarts the app.
    public void SetLanguage(bool english){
        if(english==Look.English)return;Preferences.English=english;Save();
        // The new copy waits for this one to finish quitting before it takes the single-instance lock. No cmd.exe, which schools may block.
        try{using(var self=Process.GetCurrentProcess())Process.Start(new ProcessStartInfo(Application.ExecutablePath,"--wait-pid "+self.Id){UseShellExecute=false,WorkingDirectory=Path.GetDirectoryName(Application.ExecutablePath)});}
        catch(System.ComponentModel.Win32Exception e){Message(Look.Tr("다시 시작하지 못했어요","Could not restart"),Look.Tr("YelPoint를 종료한 뒤 다시 실행하면 바뀐 언어로 열려요.\n","Quit YelPoint and start it again to see the new language.\n")+e.Message);return;}
        Exit();
    }
    // The largest thing on screen wins: shape spot, then the dimming circle, then the pointer.
    void ResizeFocus(int steps){if(SpotArea.HasValue)SpotArea=Spot.Scaled(SpotArea.Value,steps);else if(Preferences.Spotlight)Preferences.ResizeDimming(steps);else{Preferences.ResizePointer(steps);halo.Render(Preferences.HaloRadius);}DirtyInk();}
    // Windows 10 2004 and later leave these out of screen grabs; older systems just keep them in.
    void HideControlsFromCapture(bool hidden){foreach(var form in new Form[]{Toolbar,Penbar,Settings,TimerPanel,CaptureBar,ColorBar,SpotBar,ZoomBar,mini,PhoneBar,QrBar}.Concat(StickerBars))RecorderNative.SetWindowDisplayAffinity(form.Handle,hidden?0x11u:0u);}
    // The button bars under pinned images. They are controls, not content: left out of captures and recordings.
    IEnumerable<Form> StickerBars{get{return Stickers.Where(s=>s.Bar!=null&&!s.Bar.IsDisposed).Select(s=>(Form)s.Bar).ToList();}}
    public void ToggleRecording(){
        if(recorder!=null){StopRecording();return;}
        if(Exiting||modal)return;
        // Ask before touching recording files or opening the microphone. Capture exactly the disclosed display.
        var recordingBounds=Screen.FromControl(Toolbar).Bounds;
        string recordingScope=recordingBounds.Width+" × "+recordingBounds.Height;
        if(!Ask(Look.Tr("화면·마이크 녹화를 시작할까요?","Start screen and microphone recording?"),Look.Tr(
            "도구막대가 있는 모니터 전체 ("+recordingScope+")를 녹화해요. 선택 영역만 녹화하는 것은 아니에요.\n\n사용 가능한 기본 마이크의 목소리와 주변 소리도 함께 녹음해요. 마이크를 사용할 수 없거나 오디오 준비에 실패하면 소리 없이 녹화될 수 있어요. 컴퓨터의 재생음은 직접 녹음하지 않아요.\n\n학생·다른 사람의 개인정보와 화면 내용을 확인해 주세요. 확인을 누르면 녹화를 시작하고, 취소하면 시작하지 않아요.",
            "The entire display containing the toolbar ("+recordingScope+") will be recorded, not just a selected area.\n\nYour available default microphone will also record your voice and surrounding sounds. Recording may be silent if the microphone is unavailable or audio setup fails. Computer playback audio is not captured directly.\n\nCheck the screen for private information about students and other people. Choose OK to start, or Cancel to leave recording off."),cancelByDefault:true)||Exiting)return;
        string path;
        try{Directory.CreateDirectory(storage.CapturesPath);path=Path.Combine(storage.CapturesPath,Look.MediaName("mp4",DateTime.Now));}
        catch(IOException e){Message(Look.Tr("녹화를 시작하지 못했어요","Could not start recording"),Look.Tr("드라이브 연결과 저장 공간을 확인해 주세요.\n","Check the drive connection and free space.\n")+e.Message);return;}
        catch(UnauthorizedAccessException e){Message(Look.Tr("녹화를 시작하지 못했어요","Could not start recording"),Look.Tr("드라이브 연결과 저장 공간을 확인해 주세요.\n","Check the drive connection and free space.\n")+e.Message);return;}
        ScreenRecorder active=null;
        active=new ScreenRecorder(recordingBounds,path,
            sound=>QueueUI(()=>Toast(sound?Look.Tr("녹화 시작 · 마이크 켜짐","Recording · Mic on"):Look.Tr("녹화 시작 · 소리 없음","Recording · No sound"))),
            error=>QueueUI(()=>{if(recorder==active){recorder=null;HideControlsFromCapture(false);RefreshTools();}if(error!=null)Message(Look.Tr("녹화를 저장하지 못했어요","Could not save the recording"),error);else{Toast(Look.Tr("녹화를 저장했어요 · data\\captures","Recording saved · data\\captures"));}}));
        recorder=active;HidePanels();HideControlsFromCapture(true);active.Start();RefreshTools();
    }
    void StopRecording(){if(recorder==null)return;recorder.Stop();recorder=null;HideControlsFromCapture(false);RefreshTools();}
    public void ToggleColors(){if(ColorBar.Visible)ColorBar.Hide();else{ColorBar.Sync();PositionChildren();ColorBar.Show();}}
    public void SetInk(int rgb){Preferences.InkRGB=rgb;Penbar.RefreshInk();}
    // Stickers sit below the ink so the pen can write on them; controls stay on top.
    void RaiseOverlays(){foreach(var form in Ink.Cast<Form>().Concat(StickerBars).Concat(new Form[]{Toolbar,Penbar,Settings,TimerPanel,CaptureBar,ColorBar,SpotBar,ZoomBar,mini,PhoneBar,QrBar,qrWindow}))if(form.IsHandleCreated)Native.SetWindowPos(form.Handle,Native.Topmost,0,0,0,0,0x13);}
    public void BeginSelection(){if(Exiting||modal)return;Finish();Pen=false;StopZoom();HidePanels();Selecting=true;SelectionCursor(true);RefreshTools();DirtyInk();}
    void SelectionCursor(bool on){foreach(var view in Ink)view.Cursor=on?captureCursor:Cursors.Cross;}
    // A crosshair with a camera badge, so capture mode is obvious before the drag starts.
    static Cursor MakeCaptureCursor(){
        using(var b=new Bitmap(32,32,PixelFormat.Format32bppArgb)){
            using(var g=Graphics.FromImage(b)){
                g.SmoothingMode=SmoothingMode.AntiAlias;
                foreach(var pen in new[]{new Pen(Color.FromArgb(180,0,0,0),3.5f),new Pen(Color.White,1.6f)}){using(pen){g.DrawLine(pen,2,16,12,16);g.DrawLine(pen,20,16,30,16);g.DrawLine(pen,16,2,16,12);g.DrawLine(pen,16,20,16,30);}}
                Look.FillRound(g,Look.Dock,new RectangleF(18,19,13,10),2.5f);Look.FillRound(g,Look.Lime,new RectangleF(19,20,11,8),2);using(var lens=new SolidBrush(Look.Dock))g.FillEllipse(lens,22,21.5f,5,5);
            }
            return new Cursor(b.GetHicon());
        }
    }
    public StickerForm StickerAt(Point p){return Stickers.LastOrDefault(f=>f.Visible&&f.Bounds.Contains(p));}
    // The ✕ (close) or the move grip of the pinned image under p, which still work while the pen layer lies over it.
    public StickerForm StickerHandle(Point p,out bool close){
        close=false;var sticker=StickerAt(p);if(sticker==null)return null;var local=new Point(p.X-sticker.Left,p.Y-sticker.Top);
        var area=sticker.CloseArea;area.Inflate(4,4);if(area.Contains(local)){close=true;return sticker;}
        area=sticker.GripArea;area.Inflate(4,4);return area.Contains(local)?sticker:null;
    }
    public void NoteAdded(StickerForm sticker){UndoHistory.Add(sticker);Clip(sticker);}
    // Keeps the clipboard on the image with its ink, so Ctrl+V always pastes what is on screen.
    public void Clip(StickerForm sticker){using(var merged=sticker.Composite()){try{Clipboard.SetImage(merged);}catch(ExternalException){}}}
    // Copy the finished image without switching off its pen. Capture-scoped drawing leaves other apps clickable.
    public bool CopySticker(StickerForm sticker,bool announce=true){
        sticker.FinishStroke();sticker.FinishNote();
        using(var merged=sticker.Composite()){
            try{Clipboard.SetImage(merged);}
            catch(ExternalException e){Message(Look.Tr("클립보드에 복사하지 못했어요","Could not copy to the clipboard"),e.Message);return false;}
        }
        if(Pen&&!CapturePen){CapturePen=true;RefreshTools();}
        if(announce)Toast(Look.Tr("복사했어요 · 붙여넣을 곳을 클릭하고 Ctrl+V","Copied · click where it goes, then Ctrl+V"));
        return true;
    }
    // Copies, then presses Ctrl+V in the app in front. YelPoint's windows never take focus,
    // so that is still the lesson app.
    public void PasteInto(StickerForm sticker){
        if(!CopySticker(sticker,false))return;
        var wait=new Timer{Interval=200};
        wait.Tick+=(s,e)=>{wait.Stop();wait.Dispose();if(Exiting)return;if(Form.ActiveForm!=null){Toast(Look.Tr("복사했어요 · 붙여넣을 곳을 클릭하고 Ctrl+V","Copied · click where it goes, then Ctrl+V"));return;}SendKeys.SendWait("^v");Toast(Look.Tr("붙여넣었어요","Pasted"));};
        wait.Start();
    }
    // Phone Freeze explicitly asks for a fixed image to annotate; ordinary screenshots never use this path.
    void PinCapturedImage(InkWindow view,Rectangle area){
        if(lastCapture==null)return;float k=view.UiScale;int edge=Look.Px(2,k),both=Look.Px(4,k);
        AddSticker((Image)lastCapture.Clone(),new Rectangle(view.Left+area.X-edge,view.Top+area.Y-edge,area.Width+both,area.Height+both),k);
        Pen=true;CapturePen=true;RaiseOverlays();RefreshTools();
    }
    public void FinishSelection(InkWindow view,Rectangle area,bool pinForAnnotation=false){
        Selecting=false;SelectionCursor(false);pendingClicks.Clear();DirtyInk();RefreshTools();
        if(area.Width<4||area.Height<4)return;
        var controls=new Form[]{Toolbar,Penbar,Settings,TimerPanel,CaptureBar,ColorBar,SpotBar,ZoomBar,mini,halo,PhoneBar,QrBar}.Concat(StickerBars).Where(f=>f.Visible).ToArray();foreach(var f in controls)f.Hide();
        Bitmap image=null;bool stored=false,copied=true;Exception captureError=null;
        try{
            image=new Bitmap(area.Width,area.Height,PixelFormat.Format32bppArgb);
            System.Threading.Thread.Sleep(80);
            // CaptureBlt keeps the layered ink and timer windows in the image.
            using(var g=Graphics.FromImage(image))g.CopyFromScreen(view.Left+area.X,view.Top+area.Y,0,0,area.Size,CopyPixelOperation.SourceCopy|CopyPixelOperation.CaptureBlt);
            // Keep the last capture in memory even if another app has locked the clipboard.
            try{Clipboard.SetImage(image);}catch(ExternalException){copied=false;}
            if(lastCapture!=null)lastCapture.Dispose();lastCapture=image;stored=true;
        }
        catch(Exception e) when(e is System.ComponentModel.Win32Exception||e is ExternalException||e is ArgumentException||e is OutOfMemoryException){captureError=e;}
        finally{if(!stored&&image!=null)image.Dispose();foreach(var f in controls)if(!f.IsDisposed)f.Show();}
        if(captureError!=null){Message(Look.Tr("캡처하지 못했어요","Could not capture"),captureError.Message);return;}
        if(pinForAnnotation){PinCapturedImage(view,area);return;}
        // A normal capture is a clipboard action, never a new window or a drawing-mode switch.
        Pen=false;CapturePen=false;RefreshTools();
        Toast(copied?Look.Tr("복사했어요 · Ctrl+V","Copied · Ctrl+V"):Look.Tr("복사하지 못했어요 · 캡처 ▾ → 저장으로 그림을 보관할 수 있어요","Could not copy · Capture ▾ → Save keeps the image"));
    }

    // Hands a finished stroke that began on a pinned image over to that image.
    public bool AdoptStroke(InkWindow view,Stroke stroke){
        if(stroke.Points.Count==0)return false;var start=new Point(view.Left+(int)stroke.Points[0].X,view.Top+(int)stroke.Points[0].Y);
        var sticker=Stickers.LastOrDefault(f=>f.Visible&&f.Bounds.Contains(start));if(sticker==null)return false;
        for(int i=0;i<stroke.Points.Count;i++)stroke.Points[i]=new PointF(stroke.Points[i].X+view.Left-sticker.Left,stroke.Points[i].Y+view.Top-sticker.Top);
        stroke.Fades=false;sticker.AddStroke(stroke);Clip(sticker);
        int last=UndoHistory.LastIndexOf(view);if(last>=0)UndoHistory[last]=sticker;
        return true;
    }
    public void PasteSticker(){
        Image image;
        try{if(!Clipboard.ContainsImage()){Message(Look.Tr("붙일 이미지가 없어요","No image to paste"),Look.Tr("먼저 영역을 캡처하거나 이미지를 복사해 주세요.","Capture an area or copy an image first."));return;}image=Clipboard.GetImage();}
        catch(ExternalException){Message(Look.Tr("클립보드를 읽지 못했어요","Could not read the clipboard"),Look.Tr("다른 앱이 클립보드를 쓰고 있을 수 있어요. 잠시 뒤 다시 눌러 주세요.","Another app may be using the clipboard. Try again in a moment."));return;}
        if(image==null){Message(Look.Tr("붙일 이미지가 없어요","No image to paste"),Look.Tr("복사한 이미지를 읽지 못했어요.","Could not read the copied image."));return;}
        Finish();HidePanels();StopZoom();AddSticker(image,null,Native.ScaleAt(Cursor.Position));
        Pen=true;CapturePen=true;RaiseOverlays();RefreshTools();
    }
    void AddSticker(Image image,Rectangle? at,float scale){
        // The display under the pointer, so pasting works on any monitor.
        var area=Screen.FromPoint(Cursor.Position).WorkingArea;var size=at.HasValue?at.Value.Size:Look.Fit(image.Size,new Size(area.Width*7/10,area.Height*7/10));int offset=Stickers.Count%6*28;
        var sticker=new StickerForm(this,image,size,scale);sticker.Location=at.HasValue?at.Value.Location:new Point(area.Left+(area.Width-size.Width)/2+offset,area.Top+(area.Height-size.Height)/2+offset);sticker.Show();Stickers.Add(sticker);
        sticker.Bar=new StickerBar(this,sticker,scale);sticker.Bar.Place();sticker.Bar.Show();if(Recording)RecorderNative.SetWindowDisplayAffinity(sticker.Bar.Handle,0x11u);
        RaiseOverlays();UpdateExclusions();
    }
    public void RemoveSticker(StickerForm sticker){if(Stickers.Remove(sticker)){if(sticker.Bar!=null)sticker.Bar.Hide();sticker.Hide();Toolbar.BeginInvoke(new Action(()=>{sticker.Dispose();UpdateExclusions();}));}}
    public void SaveCapture(StickerForm from=null){
        Image image=lastCapture;bool owned=false;
        if(from!=null){image=from.Composite();owned=true;}
        else if(image==null&&Stickers.Count>0){image=Stickers[Stickers.Count-1].Composite();owned=true;}
        else if(image==null){try{if(Clipboard.ContainsImage()){image=Clipboard.GetImage();owned=image!=null;}}catch(ExternalException){Message(Look.Tr("클립보드를 읽지 못했어요","Could not read the clipboard"),Look.Tr("다른 앱이 클립보드를 쓰고 있을 수 있어요. 잠시 뒤 다시 눌러 주세요.","Another app may be using the clipboard. Try again in a moment."));return;}}
        if(image==null){Message(Look.Tr("저장할 캡처가 없어요","No capture to save"),Look.Tr("먼저 영역을 캡처해 주세요.","Capture an area first."));return;}
        try{Directory.CreateDirectory(storage.CapturesPath);image.Save(Path.Combine(storage.CapturesPath,Look.MediaName("png",DateTime.Now)),ImageFormat.Png);Toast(Look.Tr("저장했어요 · data\\captures","Saved · data\\captures"));}
        catch(IOException e){Message(Look.Tr("저장하지 못했어요","Could not save"),Look.Tr("드라이브 연결과 저장 공간을 확인해 주세요.\n","Check the drive connection and free space.\n")+e.Message);}
        catch(UnauthorizedAccessException e){Message(Look.Tr("저장하지 못했어요","Could not save"),Look.Tr("드라이브 연결과 저장 공간을 확인해 주세요.\n","Check the drive connection and free space.\n")+e.Message);}
        catch(ExternalException e){Message(Look.Tr("저장하지 못했어요","Could not save"),Look.Tr("드라이브 연결과 저장 공간을 확인해 주세요.\n","Check the drive connection and free space.\n")+e.Message);}
        finally{if(owned)image.Dispose();}
    }
    void StopZoom(){Zoom=false;if(lens!=null){lens.Hide();lens.Dispose();lens=null;}}
    public void Finish(){foreach(var view in Ink)view.Finish();foreach(var sticker in Stickers.ToArray())if(!sticker.IsDisposed)sticker.FinishStroke();}
    public void RefreshTools(){
        if(Exiting||modal)return;
        if(PenOptionsOpen&&!Preferences.ToolbarHidden)Present(Penbar);else{Penbar.Hide();ColorBar.Hide();}
        if(Zoom&&!Preferences.ToolbarHidden){ZoomBar.Sync();Present(ZoomBar);}else ZoomBar.Hide();
        // Only while a mode holds the mouse or the QR card is up; an open panel must not take Esc from slideshows or videos.
        bool active=(Pen&&!CapturePen)||Zoom||Selecting||SpotEditing||QrShowing;
        if(active&&!escapeRegistered){escapeRegistered=Native.RegisterHotKey(Toolbar.Handle,99,0x4000,0x1B);if(!escapeRegistered)Settings.Hint.Text=Look.Tr("Esc 키가 다른 앱과 겹쳐요.\n펜·돋보기 버튼을 다시 누르면 돌아와요.","Esc clashes with another app.\nPress the Pen or Zoom button again to go back.");}
        if(!active&&escapeRegistered){Native.UnregisterHotKey(Toolbar.Handle,99);escapeRegistered=false;}
        Passthrough=Native.Held(0x12);
        foreach(var view in Ink){view.SetInput((Pen&&!CapturePen&&!Passthrough)||Selecting||SpotEditing);view.Render(Cursor.Position);}
        foreach(var sticker in Stickers)sticker.RefreshPenCursor();
        SpotBar.Sync();CaptureBar.Sync();PhoneBar.Sync();Phone.Watch(PhoneBar.Visible||Preferences.PhoneAuto==true);Toolbar.RefreshButtons();
    }
    void Tick(){
        double now=Now;if(now-lastTick>1)hookDue=true;lastTick=now;
        if(Exiting||modal)return;if(pendingPanelDismiss){pendingPanelDismiss=false;CloseToolPanels();}Native.POINT native;if(!Native.GetCursorPos(out native))return;var p=new Point(native.X,native.Y);
        // Windows quietly removes a low-level hook that once answered too slowly, and click marks and
        // Ctrl+wheel stop with no error. After a stall, or when the pointer moves with no hook call,
        // hook in again; it costs nothing when the old hook still works.
        if(p!=previousPointer&&previousPointer.X!=int.MinValue&&now-hookSeen>2)hookDue=true;
        if(hookDue&&now-hookFixed>3){hookDue=false;hookFixed=now;InstallHooks();}
        Passthrough=Native.Held(0x12);
        // Application.Run shows MainForm even if it starts hidden.
        if(Preferences.ToolbarHidden&&Toolbar.Visible)Toolbar.Hide();
        foreach(var view in Ink){view.SetInput((Pen&&!CapturePen&&!Passthrough)||Selecting||SpotEditing);view.Render(p);}
        if(pendingPointerSteps!=0){ResizeFocus(pendingPointerSteps);pendingPointerSteps=0;}
        bool wasActive=Countdown.Active,wasLocked=Countdown.Locked;if(Countdown.Update(Now)){if(pop!=null)pop.Play();else System.Media.SystemSounds.Exclamation.Play();}
        if(wasActive!=Countdown.Active||wasLocked!=Countdown.Locked)TimerChanged();
        string clock=Countdown.Badge(Now);if(clock==null){if(badge.Visible)badge.Hide();}else{if(!badge.Visible){PlaceClock();badge.Show();}badge.Render(clock,Countdown.Alert(Now),Countdown.Pop(Now));}
        if(Preferences.Highlight&&!Pen&&!Selecting&&!SpotEditing){bool wasHidden=!halo.Visible;if(wasHidden){halo.Show();halo.Render(Preferences.HaloRadius);}if(wasHidden||p!=previousPointer)halo.Follow(p);}else halo.Hide();
        bool changed=false;
        while(pendingClicks.Count>0){var click=pendingClicks.Dequeue();if(!Preferences.Highlight||Pen)continue;if(pulses.Count>=12){pulses[0].Dispose();pulses.RemoveAt(0);}var pulse=new PulseWindow(click.Point,click.Right,Now);pulses.Add(pulse);pulse.Show();pulse.Render(Now);changed=true;}
        for(int i=pulses.Count-1;i>=0;i--){if(Now-pulses[i].StartedAt>=.55){pulses[i].Dispose();pulses.RemoveAt(i);changed=true;}else pulses[i].Render(Now);}
        if(changed&&lens!=null&&!UpdateExclusions()){StopZoom();RefreshTools();}
        if(pendingKey!=null){string text=pendingKey;pendingKey=null;var s=Screen.FromControl(Toolbar).WorkingArea;float k=Native.ScaleOf(s);keyboard.Location=new Point(s.Left+Look.Px(24,k),s.Bottom-Look.Px(74,k));keyboard.Show();keyboard.Render(text,k,s.Width-Look.Px(48,k));keyUntil=Now+1.5;}
        if(Zoom&&lens!=null&&!lens.Follow(p)){StopZoom();RefreshTools();Message(Look.Tr("돋보기가 중지됐어요","Magnifier stopped"),Look.Tr("화면 구성이 바뀌었거나 확대 기능을 사용할 수 없어요. 돋보기를 다시 눌러 주세요.","The display changed or magnification is unavailable. Press Zoom again."));}
        if(keyboard.Visible&&Now>keyUntil)keyboard.Hide();
        previousPointer=p;
    }
    IntPtr MouseEvent(int code,IntPtr message,IntPtr data){
        hookSeen=Now;
        // The wheel resizes over the highlight button, or with Ctrl held while a spot, the dim circle or the ring is showing.
        // Otherwise Ctrl+wheel goes on to the app in front, so its own zoom keeps working.
        if(code>=0&&!Exiting&&!modal&&message.ToInt32()==0x20A){
            var wheel=(Native.MOUSE)Marshal.PtrToStructure(data,typeof(Native.MOUSE));var at=new Point(wheel.Point.X,wheel.Point.Y);
            bool sizing=SpotArea.HasValue||SpotEditing||Preferences.Spotlight||Preferences.Highlight;
            if((sizing&&Native.Held(0x11))||(Toolbar.Visible&&Toolbar.Highlight.RectangleToScreen(Toolbar.Highlight.ClientRectangle).Contains(at))){pendingPointerSteps+=(short)(wheel.Data>>16)>0?1:-1;return new IntPtr(1);}
        }
        // Dismiss small panels after an outside click without consuming the click or turning off the tool.
        if(code>=0&&!Exiting&&!modal&&!Selecting&&!SpotEditing&&(message.ToInt32()==0x201||message.ToInt32()==0x204)){
            bool open=PenOptionsOpen||Settings.Visible||TimerPanel.Visible||CaptureBar.Visible||SpotBar.Visible||PhoneBar.Visible||QrBar.Visible;
            if(open){var info=(Native.MOUSE)Marshal.PtrToStructure(data,typeof(Native.MOUSE));var at=new Point(info.Point.X,info.Point.Y);
                bool own=new Form[]{Toolbar,Penbar,Settings,TimerPanel,CaptureBar,ColorBar,SpotBar,ZoomBar,mini,PhoneBar,QrBar}.Any(f=>f.Visible&&f.Bounds.Contains(at));
                if(!own)pendingPanelDismiss=true;
            }
        }
        // Native hooks must return promptly. Only copy event data here; create
        // windows and paint on the next UI timer tick.
        if(code>=0&&!Exiting&&!modal&&!Pen&&!Selecting&&!SpotEditing&&Preferences.Highlight&&(message.ToInt32()==0x201||message.ToInt32()==0x204)){
            var info=(Native.MOUSE)Marshal.PtrToStructure(data,typeof(Native.MOUSE));var p=new Point(info.Point.X,info.Point.Y);
            bool own=new Form[]{Toolbar,Penbar,Settings,TimerPanel,CaptureBar,ColorBar,SpotBar,ZoomBar,mini,PhoneBar,QrBar,qrWindow}.Concat(StickerBars).Any(f=>f.Visible&&f.Bounds.Contains(p));
            if(!own){if(pendingClicks.Count>=12)pendingClicks.Dequeue();pendingClicks.Enqueue(new PendingClick{Point=p,Right=message.ToInt32()==0x204});}
        }return Native.CallNextHookEx(mouseHook,code,message,data);
    }
    // Puts the mouse hook, and the key hook when it is on, back on top of the chain.
    void InstallHooks(){
        if(mouseHook!=IntPtr.Zero)Native.UnhookWindowsHookEx(mouseHook);mouseHook=Native.SetWindowsHookEx(14,mouseCallback,Native.GetModuleHandle(null),0);
        if(keyHook!=IntPtr.Zero&&keyCallback!=null){Native.UnhookWindowsHookEx(keyHook);keyHook=Native.SetWindowsHookEx(13,keyCallback,Native.GetModuleHandle(null),0);}
        hookSeen=Now;
    }
    public void ConfigureKeys(){
        if(Preferences.KeyboardHUD&&keyHook!=IntPtr.Zero)return;
        if(keyHook!=IntPtr.Zero){Native.UnhookWindowsHookEx(keyHook);keyHook=IntPtr.Zero;}
        if(!Preferences.KeyboardHUD){pendingKey=null;keyboard.Hide();return;}
        keyCallback=KeyboardEvent;keyHook=Native.SetWindowsHookEx(13,keyCallback,Native.GetModuleHandle(null),0);
    }
    IntPtr KeyboardEvent(int code,IntPtr message,IntPtr data){
        if(code>=0&&!Exiting&&!modal&&(message.ToInt32()==0x100||message.ToInt32()==0x104)){
            var info=(Native.KEY)Marshal.PtrToStructure(data,typeof(Native.KEY));uint key=info.Code;
            bool ctrl=Native.Held(0x11),alt=Native.Held(0x12),win=Native.Held(0x5B)||Native.Held(0x5C);
            if((ctrl||alt||win)&&((key>=0x30&&key<=0x39)||(key>=0x41&&key<=0x5A)||(key>=0x70&&key<=0x7B))){
                string label=(ctrl?"Ctrl + ":"")+(alt?"Alt + ":"")+(win?"Win + ":"")+(Native.Held(0x10)?"Shift + ":"")+(key>=0x70?"F"+(key-0x6F):((char)key).ToString());
                if(label!=lastKey||Now-lastKeyAt>.15){pendingKey=label;lastKey=label;lastKeyAt=Now;}
            }
        }return Native.CallNextHookEx(keyHook,code,message,data);
    }
    bool UpdateExclusions(){if(lens==null)return true;var handles=new List<IntPtr>{Toolbar.Handle,Penbar.Handle,Settings.Handle,TimerPanel.Handle,CaptureBar.Handle,ColorBar.Handle,SpotBar.Handle,ZoomBar.Handle,mini.Handle,PhoneBar.Handle,QrBar.Handle,halo.Handle,keyboard.Handle,badge.Handle,lens.Handle};handles.AddRange(Ink.Select(f=>f.Handle));handles.AddRange(Stickers.Select(f=>f.Handle));handles.AddRange(StickerBars.Select(f=>f.Handle));handles.AddRange(pulses.Select(f=>f.Handle));return lens.Exclude(handles);}
    public void DirtyInk(){foreach(var view in Ink)view.Dirty=true;}
    void RebuildScreens(){
        Selecting=false;EditShape=null;spotAction=SpotAction.None;SpotArea=null;SpotView=null;spotPreviousView=null;Finish();var old=Ink.GroupBy(f=>f.Bounds).ToDictionary(g=>g.Key,g=>g.First().Strokes.ToList());foreach(var view in Ink)view.Dispose();Ink.Clear();UndoHistory.Clear();
        foreach(var screen in Screen.AllScreens){var view=new InkWindow(this,screen);List<Stroke> strokes;if(old.TryGetValue(screen.Bounds,out strokes))view.Strokes.AddRange(strokes);Ink.Add(view);view.Show();view.Render(Cursor.Position);}UpdateExclusions();
    }
    void QueueUI(Action action){if(Exiting||Toolbar.IsDisposed||!Toolbar.IsHandleCreated)return;try{Toolbar.BeginInvoke(new Action(()=>{if(!Exiting)action();}));}catch(InvalidOperationException){}}
    void DisplayChanged(object sender,EventArgs e){QueueUI(()=>{StopZoom();Pen=false;RebuildScreens();PlaceToolbar();RefreshTools();});}
    void PowerChanged(object sender,PowerModeChangedEventArgs e){if(e.Mode==PowerModes.Suspend)QueueUI(()=>{StopRecording();Finish();Pen=false;StopZoom();RefreshTools();});}
    public void Undo(){
        while(UndoHistory.Count>0){
            var target=UndoHistory[UndoHistory.Count-1];UndoHistory.RemoveAt(UndoHistory.Count-1);
            var view=target as InkWindow;if(view!=null&&!view.IsDisposed&&view.Strokes.Count>0){view.Strokes.RemoveAt(view.Strokes.Count-1);view.Dirty=true;break;}
            var sticker=target as StickerForm;if(sticker!=null&&!sticker.IsDisposed&&sticker.UndoLast()){Clip(sticker);break;}
            var cleared=target as ClearedInk;
            if(cleared!=null){
                foreach(var pair in cleared.Views)if(!pair.Key.IsDisposed){pair.Key.Strokes.InsertRange(0,pair.Value);pair.Key.Dirty=true;}
                foreach(var pair in cleared.Stickers)if(!pair.Key.IsDisposed&&Stickers.Contains(pair.Key)){pair.Key.RestoreInk(pair.Value);Clip(pair.Key);}
                UndoHistory.Clear();UndoHistory.AddRange(cleared.History);Toast(Look.Tr("지운 필기를 되살렸어요","Ink restored"));break;
            }
        }
    }
    // Everything 모두 지우기 removed, so one stray click on the trash button costs nothing.
    sealed class ClearedInk{
        public readonly List<KeyValuePair<InkWindow,List<Stroke>>> Views=new List<KeyValuePair<InkWindow,List<Stroke>>>();
        public readonly List<KeyValuePair<StickerForm,object>> Stickers=new List<KeyValuePair<StickerForm,object>>();
        public List<object> History;
    }
    public void Clear(){
        Finish();var saved=new ClearedInk{History=new List<object>(UndoHistory)};
        foreach(var view in Ink){if(view.Strokes.Count>0)saved.Views.Add(new KeyValuePair<InkWindow,List<Stroke>>(view,new List<Stroke>(view.Strokes)));view.Strokes.Clear();view.Active=null;view.Dirty=true;}
        foreach(var sticker in Stickers){if(sticker.HasInk)saved.Stickers.Add(new KeyValuePair<StickerForm,object>(sticker,sticker.SaveInk()));sticker.ClearInk();Clip(sticker);}
        UndoHistory.Clear();
        if(saved.Views.Count>0||saved.Stickers.Count>0){UndoHistory.Add(saved);Toast(Look.Tr("모두 지웠어요 · 되돌리기로 되살릴 수 있어요","Cleared · Undo brings it back"));}
    }
    public void Save(){try{Preferences.Validate();storage.Save(Preferences);}catch(Exception e){Message(Look.Tr("설정 저장 실패","Could not save settings"),Look.Tr("드라이브 연결과 저장 공간을 확인해 주세요.\n","Check the drive connection and free space.\n")+e.Message);}}
    public void Message(string title,string text){Ask(title,text,false);}
    // Existing questions use Yes/No. Recording consent uses OK/Cancel with Cancel as the default.
    public bool Ask(string title,string text,bool ask=true,bool cancelByDefault=false){
        if(Exiting||modal)return false;SetModal(true);bool yes=false;Finish();pendingClicks.Clear();pendingKey=null;
        var windows=Ink.Cast<Form>().Concat(new Form[]{Toolbar,Penbar,Settings,TimerPanel,CaptureBar,ColorBar,SpotBar,ZoomBar,mini,halo,keyboard,badge}).Concat(pulses).Concat(Stickers).Concat(StickerBars).ToArray();var visible=windows.Where(f=>!f.IsDisposed&&f.Visible).ToArray();foreach(var f in visible)f.Hide();if(lens!=null)lens.Hide();
        try{yes=Native.Box(text,title,ask,cancelByDefault:cancelByDefault);}finally{if(!Exiting){foreach(var f in visible)if(!f.IsDisposed)f.Show();if(lens!=null&&!lens.IsDisposed)lens.Show();}SetModal(false);}
        return yes;
    }
    // While a box or a file window is open, Esc belongs to it, so the global Esc key lets go.
    void SetModal(bool on){
        modal=on;
        if(on&&escapeRegistered){Native.UnregisterHotKey(Toolbar.Handle,99);escapeRegistered=false;}
        if(!on&&!Exiting)RefreshTools();
    }
    // The power button sits beside hide; one slip must not wipe the lesson's ink.
    public void Quit(){
        if(Exiting)return;
        bool inkOnScreen=Ink.Any(v=>v.Strokes.Count>0||v.Active!=null)||Stickers.Count>0;
        if(!inkOnScreen&&recorder==null&&!Phone.Running){Exit();return;}
        string detail=recorder!=null||Phone.Recording?Look.Tr("녹화는 저장하고 끝내요. 화면의 필기와 붙인 이미지는 사라져요.","The recording is saved first. Ink and pinned images on screen will be gone."):Look.Tr("화면의 필기와 붙인 이미지가 사라져요. 잠깐 치우려면 눈 버튼으로 숨기세요.","Ink and pinned images on screen will be gone. To tuck it away, use the eye button instead.");
        if(Ask("YelPoint",Look.Tr("YelPoint를 종료할까요?","Quit YelPoint?")+"\n\n"+detail))Exit();
    }
    // These ship inside the exe so the installer stays a single payload.
    string Extract(string name){
        using(var source=System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream(name)){
            if(source==null)return null;
            string path=Path.Combine(storage.DirectoryPath,name);var saved=new FileInfo(path);
            if(!saved.Exists||saved.Length!=source.Length)using(var file=File.Create(path))source.CopyTo(file);
            return path;
        }
    }
    // A browser page, because default video apps have no section list.
    bool OpenGuide(){
        try{
            string language=Look.English?"en":"ko";if(Extract("guide-"+language+".mp4")==null)return false;
            using(var source=System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("guide.html")){
                if(source==null)return false;
                string page=Path.Combine(storage.DirectoryPath,"guide.html");
                using(var reader=new StreamReader(source,System.Text.Encoding.UTF8))File.WriteAllText(page,reader.ReadToEnd().Replace("__LANG__",language),new System.Text.UTF8Encoding(false));
                Process.Start(page);return true;
            }
        }
        catch(IOException){return false;}
        catch(UnauthorizedAccessException){return false;}
        catch(System.ComponentModel.Win32Exception){return false;}
    }
    // Opens a mail to Yelsam; without a mail app, copies the address instead.
    public void Suggest(){
        try{Process.Start("mailto:"+Look.SuggestAddress+"?subject="+Uri.EscapeDataString(Look.Tr("YelPoint 제안","YelPoint suggestion")));}
        catch(Exception){try{Clipboard.SetText(Look.SuggestAddress);}catch(Exception){}Toast(Look.Tr("메일 주소를 복사했어요 · ","Address copied · ")+Look.SuggestAddress);}
    }
    // The small © yelsam.lab popup: the blog, and a mail with suggestions.
    public ContextMenuStrip CreditMenu(){
        var menu=new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("© yelsam.lab"){Enabled=false});
        menu.Items.Add(Look.Tr("옐샘 블로그 둘러보기","Visit Yelsam's blog"),null,(s,e)=>OpenBlog());
        menu.Items.Add(Look.Tr("옐샘에게 제안하기","Send Yelsam a suggestion"),null,(s,e)=>Suggest());
        return menu;
    }
    public void OpenBlog(){try{Process.Start(Look.BlogUrl);}catch(System.ComponentModel.Win32Exception e){Message(Look.Tr("블로그를 열지 못했어요","Could not open the blog"),e.Message);}}
    public void Help(){if(OpenGuide())return;Message(Look.Tr("YelPoint 사용법","How to Use YelPoint"),Look.Tr(
        "강조: 커서 주변 링과 왼쪽·오른쪽 클릭 표시\n돋보기: 커서 부근을 실시간으로 1.5~5배 확대\n펜: 누르면 바로 필기. 옆 ▾를 눌렀을 때만 색·굵기·되돌리기·모두 지우기 창이 열려요\n타이머: 1~60분 카운트다운. 분을 직접 넣을 수 있고, 시계는 끌어서 옮기고 모서리를 끌어 크기를 바꿔요\n캡처: 누르고 영역을 고르면 미리보기 없이 바로 클립보드에 복사해요. Ctrl+V로 붙여넣으세요. 옆 ▾에서 동영상 녹화·저장·내 영상을 열어요. 그림 위에 필기가 필요할 때만 띄우기를 누르세요\n스팟: 사각·원·타원으로 보여 줄 곳을 빨간 선으로 표시. 선을 끌어 크기 조절, 바깥 클릭으로 완료\n폰: USB로 꽂은 안드로이드 폰·태블릿 화면이나 카메라(실물화상기)를 띄워요. 처음이면 폰 패널의 ?를 눌러 주세요\nQR: 주소를 넣으면 화면 가운데에 큰 QR 코드를 보여 줘요\n칠판: 분필로 쓰고 지우는 큰 칠판. 글씨 넣기와 PNG 저장도 돼요\n\nCtrl+Alt+1 강조 · 2 돋보기 · 3 펜 · 4 타이머 · 5 캡처 · 6 스팟 · 0 도구막대 숨기기\nEsc: 펜·돋보기·캡처·스팟·QR을 끄고 평소 마우스로 (필기는 남아요)\nAlt를 누르는 동안: 필기 중 클릭·스크롤 통과\nCtrl+휠: 위로 크게, 아래로 작게 (스팟 → 주변 어둡게 원 → 강조 링 순서)\n도구막대는 끌어서 옮길 수 있어요. 왼쪽·오른쪽 끝에 닿으면 세로로 서요.\n\n작업표시줄 아이콘 우클릭 → 작업 표시줄에 고정\n설정과 저장한 캡처·녹화는 설치 폴더의 data에 있어요.",
        "Highlight: a ring around the pointer and left/right click marks\nZoom: live magnifier near the pointer, 1.5× to 5×\nPen: 3 colors and a color wheel, width (1 to 30), undo, clear all (Undo brings it back)\nTimer: 1 to 60 minute countdown. Type minutes; drag the clock to move it, drag its corner to resize\nCapture: one click to select an area and copy it, without opening a preview. Use the arrow for recording or to pin an image. Paste, save, record the screen, My Videos (watch, add subtitles)\nSpot: mark a rectangle, circle or ellipse with a red line. Drag the line to resize, click outside when done\nPhone: show an Android phone or tablet plugged in over USB, or its camera as a document camera. First time? Press ? on the phone panel\nQR: type an address to show a big QR code in the middle of the screen\nBoard: a big chalkboard to draw, write and erase on. Save it as PNG\n\nCtrl+Alt+1 Highlight · 2 Zoom · 3 Pen · 4 Timer · 5 Capture · 6 Spot · 0 Hide bar\nEsc: turn off Pen, Zoom, Capture, Spot or QR and get the mouse back (ink stays)\nHold Alt: clicks pass through while drawing\nCtrl+wheel: up larger, down smaller (spot, then dim circle, then pointer ring)\nDrag the toolbar to move it. At a side edge it stands up.\n\nRight-click the taskbar icon → Pin to taskbar\nSettings, saved captures and recordings are in the data folder."));}

    // ---- Subtitles (see Subtitles.cs) ----
    SubtitleForm subtitles;
    public void OpenSubtitles(string path){
        if(subtitles!=null&&!subtitles.IsDisposed)subtitles.Close();
        subtitles=new SubtitleForm(path,Path.Combine(storage.DirectoryPath,"tmp"),Native.ScaleAt(Cursor.Position));subtitles.Show();subtitles.Activate();
    }
    // An MP4 from anywhere, for 내 영상's ‘다른 영상 고르기…’. true once the editor has opened.
    public bool ChooseVideoForSubtitles(IWin32Window owner){
        if(Exiting||modal)return false;bool chosen=false;
        using(var dialog=new OpenFileDialog{Filter=Look.Tr("동영상 (MP4)","Videos (MP4)")+"|*.mp4",InitialDirectory=storage.CapturesPath,Title=Look.Tr("자막을 넣을 영상을 골라 주세요","Choose a video to add subtitles to")}){
            // Owned by the always-on-top window it came from, so the file window opens in front of it.
            SetModal(true);try{if(dialog.ShowDialog(owner)==DialogResult.OK){OpenSubtitles(dialog.FileName);chosen=true;}}finally{SetModal(false);}
        }
        return chosen;
    }
    // ---- 내 영상: every recording in data\captures (see Subtitles.cs) ----
    MyVideosForm myVideos;
    public void ShowMyVideos(){
        if(Exiting||modal||Recording)return;
        if(myVideos==null||myVideos.IsDisposed)myVideos=new MyVideosForm(this,Native.ScaleAt(Cursor.Position));
        myVideos.Open();
    }
    // ---- Chalkboard (see Board.cs) ----
    void OpenBoard(){
        Finish();Pen=false;StopZoom();HidePanels();
        var area=Screen.FromControl(Toolbar).WorkingArea;float k=Native.ScaleOf(area);area.Inflate(-Look.Px(16,k),-Look.Px(16,k));board.Place(area,k);
        // The pinned images stay under the board, so their button bars wait until it closes.
        foreach(var bar in StickerBars)bar.Hide();
        board.Show();board.Activate();RaiseOverlays();RefreshTools();DirtyInk();
    }
    public void CloseBoard(){board.FinishText();board.Hide();foreach(var bar in StickerBars)bar.Show();RefreshTools();}
    public void SaveBoard(BoardForm from){
        try{Directory.CreateDirectory(storage.CapturesPath);using(var image=from.Snapshot())image.Save(Path.Combine(storage.CapturesPath,Look.MediaName("png",DateTime.Now).Replace("YelPoint-","YelPoint-board-")),ImageFormat.Png);Toast(Look.Tr("칠판을 PNG로 저장했어요 · data\\captures","Board saved as PNG · data\\captures"));}
        catch(Exception e){Message(Look.Tr("저장하지 못했어요","Could not save"),e.Message);}
    }
    // ---- QR code for an address (see Qr.cs) ----
    public void ShowQr(string raw){
        string text=(raw??"").Trim();
        if(text.Length==0){Toast(Look.Tr("주소를 먼저 넣어 주세요","Type an address first"));return;}
        if(!qrWindow.Show(text,Screen.FromControl(Toolbar).WorkingArea)){Message(Look.Tr("QR을 만들지 못했어요","Could not make the QR code"),Look.Tr("주소가 너무 길어요. 짧은 주소로 바꿔서 넣어 주세요.","The address is too long. Try a shorter one."));return;}
        Preferences.QrText=text;Save();QrBar.Hide();RefreshTools();
    }
    public void CloseQr(){qrWindow.Hide();QrBar.Hide();RefreshTools();}
    // ---- Android phone or tablet (see Phone.cs) ----
    void PhoneChanged(){
        PhoneBar.Sync();Toolbar.RefreshButtons();
        // Only the moment a phone becomes ready (plugged in, or allowed) opens it by itself.
        // Closing the window, a recording ending or a cable on its way out never reopens it.
        bool ready=Phone.Device.State==PhoneState.Ready,open=ready&&!phoneWasReady&&Preferences.PhoneAuto==true&&!Phone.Running&&!phoneDismissed;
        phoneWasReady=ready;
        if(Phone.Device.State==PhoneState.None)phoneDismissed=false;
        if(open)ShowPhone(false);
    }
    public void ShowPhone(bool camera){
        if(!camera)Phone.Light=false;
        if(!Phone.Start(camera)){Message(Look.Tr("폰을 띄우지 못했어요","Could not open the phone"),Look.Tr("케이블을 다시 꽂고 한 번 더 눌러 주세요.","Replug the cable and try again."));return;}
        phoneDismissed=false;
        if(Preferences.PhoneAuto==null){Preferences.PhoneAuto=true;Save();}
        Toast(camera?Look.Tr("실물화상기를 켰어요","Document camera is on"):Look.Tr("폰 화면을 띄웠어요","Phone screen is open"));RefreshTools();
    }
    public void RotatePhone(){Phone.Rotation=(Phone.Rotation+90)%360;Phone.Restart();}
    public void TogglePhoneLight(){Phone.Light=!Phone.Light;Phone.Restart();}
    public void TogglePhoneRecording(){
        if(Phone.Recording){Phone.StopRecording();return;}
        string path;
        try{Directory.CreateDirectory(storage.CapturesPath);path=Path.Combine(storage.CapturesPath,Look.MediaName("mp4",DateTime.Now).Replace("YelPoint-","YelPoint-phone-"));}
        catch(Exception e){Message(Look.Tr("녹화를 시작하지 못했어요","Could not start recording"),e.Message);return;}
        if(!Phone.Start(Phone.Camera,path)){Message(Look.Tr("녹화를 시작하지 못했어요","Could not start recording"),Look.Tr("케이블을 다시 꽂고 한 번 더 눌러 주세요.","Replug the cable and try again."));return;}
        Toast(Look.Tr("폰 화면 녹화를 시작했어요","Recording the phone"));
    }
    void PhoneRecorded(string path){
        long size=0;try{if(File.Exists(path))size=new FileInfo(path).Length;}catch(Exception){}
        if(size==0){try{File.Delete(path);}catch(Exception){}Message(Look.Tr("폰 녹화를 저장하지 못했어요","Could not save the phone recording"),Look.Tr("폰 화면이 너무 짧게 열렸거나 연결이 끊겼어요. 다시 녹화해 주세요.","The phone was open too briefly or got unplugged. Please record again."));return;}
        Toast(Look.Tr("폰 녹화를 저장했어요 · data\\captures","Phone recording saved · data\\captures"));
    }
    public void ClosePhone(){phoneDismissed=true;Phone.Stop();}
    // ---- 영상 가져오기: a gallery video copied from the phone, then subtitles ----
    PhoneVideoForm phoneVideos;
    public string CapturesPath{get{return storage.CapturesPath;}}
    public void ShowPhoneVideos(){
        if(Exiting||modal)return;
        if(Phone.Device.State!=PhoneState.Ready){Message(Look.Tr("폰을 먼저 연결해 주세요","Connect the phone first"),Look.Tr("폰을 케이블로 꽂으면 ‘영상 가져오기’를 쓸 수 있어요.","Plug in the phone to get its videos."));return;}
        if(phoneVideos==null||phoneVideos.IsDisposed)phoneVideos=new PhoneVideoForm(this,Native.ScaleAt(Cursor.Position));
        phoneVideos.Open(Phone.Device.Serial);
    }
    public void PhoneVideoImported(string path){if(Exiting)return;Toast(Look.Tr("폰 영상을 가져왔어요 · data\\captures","Video copied · data\\captures"));OpenSubtitles(path);}
    void PhoneClosed(bool early){
        // Closed with the window's own button counts as "not now", the same as 끄기.
        phoneDismissed=true;
        if(early&&Phone.Camera)Message(Look.Tr("카메라를 열지 못했어요","Could not open the camera"),Look.Tr("폰 카메라 연결은 안드로이드 12 이상에서 돼요. 다른 앱이 카메라를 쓰고 있으면 닫고 다시 눌러 주세요.","Camera mode needs Android 12 or later. Close any app using the camera and try again."));
        else Toast(Look.Tr("폰 창이 닫혔어요","The phone window closed"));
    }
    // Pins the current phone view as a capture, so it can be written on and saved.
    public void FreezePhone(){
        var area=Phone.WindowArea();if(area==null)return;
        var center=new Point(area.Value.X+area.Value.Width/2,area.Value.Y+area.Value.Height/2);
        var view=Ink.FirstOrDefault(v=>v.Bounds.Contains(center));if(view==null)return;
        FinishSelection(view,new Rectangle(area.Value.X-view.Left,area.Value.Y-view.Top,area.Value.Width,area.Value.Height),pinForAnnotation:true);
    }
    public void PhoneHelp(){
        if(Ask(Look.Tr("안드로이드 폰·태블릿 처음 연결하기","Connecting an Android phone or tablet"),Look.Tr(
            "★ 폰마다 설정 방법이 달라요. 아래대로 안 되면 ‘내 폰 이름 + USB 디버깅’(예: ‘갤럭시 Z폴드5 USB 디버깅’)으로 검색해 보세요.\n\n처음 한 번만 하면 돼요. 단, 개발자 옵션과 USB 디버깅은 켜 둔 채로 두세요. 아래는 갤럭시 기준이에요.\n\n1. 폰 설정 → 휴대전화 정보 → 소프트웨어 정보 → ‘빌드번호’를 7번 눌러 주세요. 화면은 그대로이고 ‘개발자 모드를 켰습니다’ 알림만 잠깐 떠요.\n2. 설정 첫 화면 맨 아래에 새로 생긴 ‘개발자 옵션’ → ‘USB 디버깅’을 켜 주세요.\n3. 폰 기본 케이블로 컴퓨터에 바로 꽂고, 폰에 뜬 ‘USB 디버깅 허용’에서 ‘항상 허용’을 눌러 주세요.\n\n그다음부터는 꽂기만 해도 폰 화면이 바로 떠요.\n\n안 될 때\n· USB 디버깅이 회색이면: 설정 → 보안 및 개인정보 보호 → ‘자동 차단’을 꺼 주세요.\n· 아무 반응이 없으면: 충전 전용 케이블이거나 허브·어댑터를 거친 경우예요. 폰 기본 케이블로 컴퓨터에 바로 꽂아 주세요.\n· 허용 창이 안 뜨면: 폰 잠금을 풀고 케이블을 뺐다 다시 꽂아 주세요.\n· 전에는 됐는데 다시 안 되면: 폰 잠금을 풀고 개발자 옵션 → USB 디버깅이 켜져 있는지 봐 주세요. 꺼져 있으면 다시 켜고 케이블을 다시 꽂은 뒤 ‘항상 허용’을 눌러 주세요.\n· 처음 꽂을 때 윈도우가 폰 드라이버를 설치할 수 있어요. 잠시 기다려 주세요.\n\n실물화상기: ‘카메라’를 누르고 폰을 거치대에 아래로 향하게 두세요. 회전·조명·멈춤으로 맞춰 주세요. 안드로이드 12 이상에서 돼요.\n학교에서 관리하는 기기는 개발자 옵션이 막혀 있을 수 있어요.\n\n사진과 함께 보는 자세한 방법은 옐샘 블로그에 있어요.\n\n블로그 안내를 열까요?",
            "★ Every phone sets this up a little differently. If these steps do not match, search for your phone's name plus \"USB debugging\" (for example \"Galaxy Z Fold5 USB debugging\").\n\nOnly once, as long as developer options and USB debugging stay on. These steps are for a Galaxy phone.\n\n1. Settings → About phone → Software information → tap Build number 7 times. The screen stays the same; a short note says developer mode is on.\n2. At the bottom of Settings, open the new Developer options → turn on USB debugging.\n3. Plug the phone straight into the computer with its own cable and tap Always allow on the phone.\n\nAfter that the screen opens as soon as you plug in.\n\nIf it does not work\n· USB debugging greyed out: Settings → Security and privacy → turn off Auto Blocker.\n· Nothing happens: the cable may be charge-only, or a hub or adapter is in the way. Plug straight in with the phone's own cable.\n· No Allow prompt: unlock the phone, then unplug and plug in again.\n· Worked before but not now: unlock the phone and check that Developer options → USB debugging is still on. If it is off, turn it on, plug in again and tap Always allow.\n· Windows may install a phone driver the first time. Give it a moment.\n\nDocument camera: press Camera and point the phone down from a stand. Use Rotate, Light and Freeze. Needs Android 12 or later.\nSchool-managed devices may block developer options.\n\nA step-by-step guide with photos is on Yelsam's blog (in Korean).\n\nOpen the guide?"))){try{Process.Start(Look.PhoneGuideUrl);}catch(System.ComponentModel.Win32Exception e){Message(Look.Tr("블로그를 열지 못했어요","Could not open the blog"),e.Message);}}
    }
    public void Exit(){if(Exiting)return;Exiting=true;if(recorder!=null){recorder.Stop();recorder.Wait(5000);}timer.Stop();timer.Dispose();Phone.Shutdown();StopZoom();SystemEvents.DisplaySettingsChanged-=DisplayChanged;SystemEvents.PowerModeChanged-=PowerChanged;
        if(mouseHook!=IntPtr.Zero)Native.UnhookWindowsHookEx(mouseHook);if(keyHook!=IntPtr.Zero)Native.UnhookWindowsHookEx(keyHook);for(int id=1;id<=7;id++)Native.UnregisterHotKey(Toolbar.Handle,id);if(escapeRegistered)Native.UnregisterHotKey(Toolbar.Handle,99);
        try{storage.Save(Preferences);}catch{}
        tray.Visible=false;tray.Dispose();foreach(var f in Ink)f.Dispose();foreach(var f in pulses)f.Dispose();foreach(var f in Stickers)f.Dispose();if(lastCapture!=null)lastCapture.Dispose();halo.Dispose();keyboard.Dispose();badge.Dispose();if(pop!=null)pop.Dispose();captureCursor.Dispose();Penbar.Dispose();Settings.Dispose();TimerPanel.Dispose();CaptureBar.Dispose();ColorBar.Dispose();SpotBar.Dispose();ZoomBar.Dispose();PhoneBar.Dispose();QrBar.Dispose();qrWindow.Dispose();board.Dispose();mini.Dispose();Toolbar.Dispose();if(magAvailable)Native.MagUninitialize();ExitThread();}
}
}
