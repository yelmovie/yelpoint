using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;

namespace YelPoint {
internal static class Look {
    public static bool English;
    public static string Tr(string korean,string english){return English?english:korean;}
    public static readonly double[] ZoomLevels={1.5,2,3,4,5};
    public static readonly Color Dock=Color.FromArgb(32,43,37), Paper=Color.FromArgb(248,248,242), Lime=Color.FromArgb(215,239,171), SpotLine=Color.FromArgb(230,31,31);
    public const string BlogUrl="https://blog.naver.com/profile/intro.naver?blogId=yelsam_lab";
    public const string PhoneGuideUrl="https://blog.naver.com/yelsam_lab/224469355120";
    public const string SuggestAddress="bongbiyobi@gmail.com";
    public static readonly Color[] Ink={Color.FromArgb(237,104,79),Color.FromArgb(49,121,221),Color.FromArgb(37,149,103)};
    public static Font Font(float size,FontStyle style=FontStyle.Regular){return new Font("Malgun Gothic",size,style,GraphicsUnit.Point);}
    public static Font Pixels(float size,FontStyle style=FontStyle.Regular){return new Font("Malgun Gothic",size,style,GraphicsUnit.Pixel);}
    public static Icon Icon(){using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("YelPoint.ico"))return stream==null?SystemIcons.Application:(Icon)new Icon(stream).Clone();}
    public static GraphicsPath Round(RectangleF r,float radius){var p=new GraphicsPath();float d=Math.Min(radius*2,Math.Min(r.Width,r.Height));p.AddArc(r.X,r.Y,d,d,180,90);p.AddArc(r.Right-d,r.Y,d,d,270,90);p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.X,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;}
    public static void FillRound(Graphics g,Color color,RectangleF r,float radius){using(var p=Round(r,radius))using(var b=new SolidBrush(color))g.FillPath(b,p);}
    public static Size Fit(Size image,Size limit){if(image.Width<=0||image.Height<=0)return new Size(80,80);double ratio=Math.Min(1,Math.Min((double)limit.Width/image.Width,(double)limit.Height/image.Height));return new Size(Math.Max(1,(int)(image.Width*ratio)),Math.Max(1,(int)(image.Height*ratio)));}
    public static int PenWidthAt(double fraction){return 1+(int)Math.Round(Math.Max(0,Math.Min(1,fraction))*29,MidpointRounding.AwayFromZero);}
    public static int Hsv(double hue,double saturation,double value){
        double h=(hue-Math.Floor(hue))*6,f=h-Math.Floor(h),p=value*(1-saturation),q=value*(1-saturation*f),t=value*(1-saturation*(1-f));
        double[][] sectors={new[]{value,t,p},new[]{q,value,p},new[]{p,value,t},new[]{p,q,value},new[]{t,p,value},new[]{value,p,q}};var c=sectors[(int)h%6];
        return (int)Math.Round(c[0]*255)<<16|(int)Math.Round(c[1]*255)<<8|(int)Math.Round(c[2]*255);
    }
    // dy points up. Beyond the rim the pick stays on the rim.
    public static void WheelPick(double dx,double dy,double radius,out double hue,out double saturation){double angle=Math.Atan2(dy,dx)/(2*Math.PI);hue=angle<0?angle+1:angle;saturation=Math.Min(1,Math.Sqrt(dx*dx+dy*dy)/radius);}
    public static Point Clamp(Rectangle frame,Rectangle area){return new Point(Math.Max(area.Left,Math.Min(area.Right-frame.Width,frame.Left)),Math.Max(area.Top,Math.Min(area.Bottom-frame.Height,frame.Top)));}
    // Above a flat toolbar (below it when there is no room), centred on the button that opened it. gap is 4 at 96 DPI, so panels attach like magnets.
    public static Point ChildOrigin(Rectangle anchor,Size child,Rectangle area,int gap,Rectangle? opener=null){var centre=opener??anchor;int y=anchor.Top-child.Height-gap;if(y<area.Top)y=anchor.Bottom+gap;return Clamp(new Rectangle(centre.Left+(centre.Width-child.Width)/2,y,child.Width,child.Height),area);}
    // -1 or 1 when a dragged toolbar is released at the left or right edge, otherwise 0.
    // The bar itself counts: held by its far end, it reaches the edge long before the pointer.
    public static int ToolbarEdge(Rectangle frame,int x,Rectangle area){
        bool left=frame.Left<=area.Left+24||x<=area.Left+60,right=frame.Right>=area.Right-24||x>=area.Right-60;
        if(left&&right)return x<area.Left+area.Width/2?-1:1;
        return left?-1:right?1:0;
    }
    // A standing toolbar waits this far inward before lying flat, so it cannot flicker at the edge.
    public static bool LiesFlat(int side,int flipX,int x){return (side<0?x-flipX:flipX-x)>=120;}
    // Under the pointer but clear of both side edges, so it does not stand straight back up.
    public static Point FlatOrigin(Point p,Size size,Rectangle area){return new Point(Math.Min(area.Right-size.Width-60,Math.Max(area.Left+60,p.X-size.Width/2)),p.Y-size.Height/2);}
    // A pinned image's button bar: just under it, or above it when there is no room below; kept on screen.
    public static Point BarOrigin(Rectangle sticker,Size bar,Rectangle area,int gap,int margin){
        int y=sticker.Bottom+gap;if(y+bar.Height>area.Bottom)y=Math.Max(area.Top,sticker.Top-gap-bar.Height);
        return new Point(Math.Max(area.Left+margin,Math.Min(area.Right-bar.Width-margin,sticker.Left)),y);
    }
    // Beside a standing toolbar, on the side with more room, its top level with the button that opened it.
    public static Point SideOrigin(Rectangle anchor,Size child,Rectangle area,int gap,Rectangle? opener=null){int x=anchor.Left+anchor.Width/2<area.Left+area.Width/2?anchor.Right+gap:anchor.Left-child.Width-gap;return Clamp(new Rectangle(x,opener.HasValue?opener.Value.Top:anchor.Top+(anchor.Height-child.Height)/2,child.Width,child.Height),area);}
    // A panel beside a standing toolbar stands too (as on the Mac): the order its controls are read in when flat,
    // top row first (vertical centres bucketed to row), then left to right.
    public static int[] ReadingOrder(Rectangle[] frames,float row){
        var order=new int[frames.Length];for(int i=0;i<order.Length;i++)order[i]=i;Func<int,double> band=i=>Math.Round((frames[i].Top+frames[i].Height/2.0)/row,MidpointRounding.AwayFromZero);
        Array.Sort(order,(a,b)=>{int c=band(a).CompareTo(band(b));if(c==0)c=frames[a].Left.CompareTo(frames[b].Left);return c!=0?c:a.CompareTo(b);});return order;
    }
    // Then flowed left to right into rows that fit width-2*pad, each row centred and each control centred in its row.
    // A control keeps its height and is no wider than the room. height is 2*pad, the rows, and gap between rows.
    public static Rectangle[] Flow(Size[] sizes,int width,int pad,int gap,out int height){
        int room=width-pad*2;var rows=new List<List<int>>{new List<int>()};var used=new List<int>{0};var fitted=new Size[sizes.Length];
        for(int i=0;i<sizes.Length;i++){
            fitted[i]=new Size(Math.Min(sizes[i].Width,room),sizes[i].Height);int last=rows.Count-1;
            if(rows[last].Count>0&&used[last]+gap+fitted[i].Width>room){rows.Add(new List<int>());used.Add(0);last++;}
            used[last]+=(rows[last].Count==0?0:gap)+fitted[i].Width;rows[last].Add(i);
        }
        var placed=new Rectangle[sizes.Length];int top=pad;
        for(int r=0;r<rows.Count;r++){
            int rowHeight=0;foreach(int i in rows[r])rowHeight=Math.Max(rowHeight,fitted[i].Height);
            int x=(int)Math.Round((width-used[r])/2.0,MidpointRounding.AwayFromZero);
            foreach(int i in rows[r]){placed[i]=new Rectangle(x,top+(rowHeight-fitted[i].Height)/2,fitted[i].Width,fitted[i].Height);x+=fitted[i].Width+gap;}
            top+=rowHeight+(r<rows.Count-1?gap:0);
        }
        height=top+pad;return placed;
    }
    public static double ClockScaleFor(int width){return Math.Max(118,Math.Min(1176,width))/196.0;}
    public static Size RecordSize(Size pixels){double ratio=Math.Min(1,3840.0/Math.Max(1,pixels.Width));return new Size((int)(pixels.Width*ratio)&~1,(int)(pixels.Height*ratio)&~1);}
    public static string MediaName(string extension,DateTime date){return "YelPoint-"+date.ToString("yyyyMMdd-HHmmss",System.Globalization.CultureInfo.InvariantCulture)+"."+extension;}
    // A monitor's DPI as a factor of the 96-DPI design size. Nonsense readings count as 100%.
    public static float DpiScale(uint dpi){return dpi<48||dpi>960?1f:dpi/96f;}
    // A 96-DPI size in pixels on a display with this factor.
    public static int Px(float value,float scale){return (int)Math.Round(value*scale);}
    // The process id after --wait-pid, or 0. A restart waits for that copy to quit first.
    public static int WaitPid(string[] args){var list=args??new string[0];int at=Array.IndexOf(list,"--wait-pid"),pid;return at>=0&&at+1<list.Length&&int.TryParse(list[at+1],System.Globalization.NumberStyles.None,System.Globalization.CultureInfo.InvariantCulture,out pid)&&pid>0?pid:0;}
}

[DataContract] internal class Preferences {
    [DataMember] public bool Highlight=true;
    [DataMember] public bool FadingInk=false;
    [DataMember] public bool KeyboardHUD=false;
    [DataMember] public bool Spotlight=false;
    [DataMember] public int PenColor=0;
    [DataMember] public int PenWidth=4;
    [DataMember] public int HaloRadius=16;
    [DataMember] public int InkRGB=-1;
    [DataMember] public int SpotlightRadius=105;
    [DataMember] public bool ToolbarPlaced=false;
    [DataMember] public int ToolbarX=0;
    [DataMember] public int ToolbarY=0;
    [DataMember] public bool ToolbarHidden=false;
    [DataMember] public bool ToolbarVertical=false;
    [DataMember] public bool English=false;
    [DataMember] public double Zoom=2;
    [DataMember] public bool ClockPlaced=false;
    [DataMember] public int ClockX=0;
    [DataMember] public int ClockY=0;
    [DataMember] public double ClockScale=1;
    // Set after the first phone connection, so later plug-ins open the phone screen straight away.
    [DataMember] public bool? PhoneAuto;
    [DataMember] public string QrText;
    [OnDeserializing] void SetDefaults(StreamingContext context){Highlight=true;PenWidth=4;HaloRadius=16;InkRGB=-1;SpotlightRadius=105;Zoom=2;ClockScale=1;}
    public void ResizeDimming(int steps){SpotlightRadius=Math.Min(400,Math.Max(30,SpotlightRadius+steps*8));}
    public void ResizePointer(int steps){HaloRadius=Math.Min(48,Math.Max(6,HaloRadius+steps*2));}
    public void Validate(){PenColor=Math.Min(2,Math.Max(0,PenColor));if(PenWidth<1||PenWidth>30)PenWidth=4;HaloRadius=Math.Min(48,Math.Max(6,HaloRadius));SpotlightRadius=Math.Min(400,Math.Max(30,SpotlightRadius));Zoom=Math.Min(5,Math.Max(1.5,Zoom));ClockScale=Math.Min(6,Math.Max(.6,ClockScale));if(InkRGB<-1||InkRGB>0xFFFFFF)InkRGB=-1;}
}

internal enum SpotShape {Rectangle,Circle,Ellipse}

internal static class Spot {
    public const float MinimumSize=24;
    // The part of the outline under p, or -1. Parts walk round from the low-x, low-y
    // corner, alternating corner and edge, so 0 is a corner, 1 an edge, up to 7.
    // reach is 10 at 96 DPI and grows with the display, so the line stays easy to grab on a 4K board.
    public static int HandleAt(PointF p,SpotShape shape,RectangleF r,float reach=10){
        if(shape==SpotShape.Rectangle){
            if(p.X<r.Left-reach||p.X>r.Right+reach||p.Y<r.Top-reach||p.Y>r.Bottom+reach)return -1;
            int column=Math.Abs(p.X-r.Left)<=reach?0:Math.Abs(p.X-r.Right)<=reach?2:1,row=Math.Abs(p.Y-r.Top)<=reach?0:Math.Abs(p.Y-r.Bottom)<=reach?2:1;
            return new[]{0,1,2,7,-1,3,6,5,4}[row*3+column];
        }
        if(r.Width<=0||r.Height<=0)return -1;
        double x=(p.X-r.Left-r.Width/2)/(r.Width/2),y=(p.Y-r.Top-r.Height/2)/(r.Height/2);
        if(Math.Abs(Math.Sqrt(x*x+y*y)-1)*Math.Min(r.Width,r.Height)/2>reach)return -1;
        double angle=Math.Atan2(y,x)*180/Math.PI;if(angle<0)angle+=360;
        return new[]{3,4,5,6,7,0,1,2}[(int)Math.Round(angle/45,MidpointRounding.AwayFromZero)%8];
    }
    public static bool Contains(SpotShape shape,RectangleF r,PointF p){if(shape==SpotShape.Rectangle)return r.Contains(p);if(r.Width<=0||r.Height<=0)return false;float x=(p.X-r.Left-r.Width/2)/(r.Width/2),y=(p.Y-r.Top-r.Height/2)/(r.Height/2);return x*x+y*y<=1;}
    public static RectangleF FromDrag(PointF a,PointF b,bool square){
        float dx=b.X-a.X,dy=b.Y-a.Y;if(square){float side=Math.Max(Math.Abs(dx),Math.Abs(dy));dx=dx<0?-side:side;dy=dy<0?-side:side;}
        return new RectangleF(Math.Min(a.X,a.X+dx),Math.Min(a.Y,a.Y+dy),Math.Abs(dx),Math.Abs(dy));
    }
    // Grows or shrinks about the centre, keeping the proportions.
    public static RectangleF Scaled(RectangleF r,int steps){float scale=Math.Max(1+.05f*steps,MinimumSize/Math.Max(1,Math.Min(r.Width,r.Height))),width=r.Width*scale,height=r.Height*scale;return new RectangleF(r.Left+r.Width/2-width/2,r.Top+r.Height/2-height/2,width,height);}
    public static RectangleF Resized(RectangleF r,int handle,PointF p,bool square){
        bool lowX=handle==0||handle==6||handle==7,highX=handle>=2&&handle<=4,lowY=handle<=2,highY=handle>=4&&handle<=6;
        float x0=r.Left,x1=r.Right,y0=r.Top,y1=r.Bottom;
        if(lowX)x0=Math.Min(p.X,x1-MinimumSize);if(highX)x1=Math.Max(p.X,x0+MinimumSize);if(lowY)y0=Math.Min(p.Y,y1-MinimumSize);if(highY)y1=Math.Max(p.Y,y0+MinimumSize);
        if(square){
            bool movesX=lowX||highX,movesY=lowY||highY;float side=movesX&&movesY?Math.Max(x1-x0,y1-y0):movesX?x1-x0:y1-y0;
            if(lowX)x0=x1-side;else if(highX)x1=x0+side;else{x0=(x0+x1-side)/2;x1=x0+side;}
            if(lowY)y0=y1-side;else if(highY)y1=y0+side;else{y0=(y0+y1-side)/2;y1=y0+side;}
        }
        return RectangleF.FromLTRB(x0,y0,x1,y1);
    }
}

internal sealed class Countdown {
    public const int MaxMinutes=60;
    // "Time's up!" stays this long so a class with the sound off still sees it.
    public const double HoldSeconds=5;
    // Long enough for the pop, then the clock is gone.
    const double AlertSeconds=.45;
    enum Phase {Idle,Running,Paused,Finished}
    Phase phase=Phase.Idle;
    double mark;
    public int Minutes{get;private set;}
    public Countdown(){Minutes=10;}
    public bool Running{get{return phase==Phase.Running;}}
    public bool Locked{get{return phase==Phase.Running||phase==Phase.Paused;}}
    public bool Active{get{return phase!=Phase.Idle;}}
    public void Set(int minutes){if(Locked)return;Minutes=Math.Min(MaxMinutes,Math.Max(1,minutes));phase=Phase.Idle;}
    public void StartOrPause(double now){
        if(phase==Phase.Running){mark=Math.Max(0,mark-now);phase=Phase.Paused;}
        else if(phase==Phase.Paused){mark=now+mark;phase=Phase.Running;}
        else{mark=now+Minutes*60;phase=Phase.Running;}
    }
    public void Reset(){phase=Phase.Idle;}
    // Returns true once, at the moment the time runs out.
    public bool Update(double now){
        if(phase==Phase.Running&&now>=mark){phase=Phase.Finished;mark=now;return true;}
        if(phase==Phase.Finished&&now>=mark+HoldSeconds+AlertSeconds)phase=Phase.Idle;
        return false;
    }
    public string Badge(double now){
        if(phase==Phase.Idle)return null;if(phase==Phase.Finished)return Look.Tr("시간 끝!","Time's up!");
        int seconds=(int)Math.Ceiling(Math.Max(0,phase==Phase.Running?mark-now:mark));return string.Format("{0:00}:{1:00}",seconds/60,seconds%60);
    }
    public bool Alert(double now){return phase==Phase.Finished;}
    // 0 to 1 through the pop that ends the countdown.
    public float Pop(double now){return phase==Phase.Finished?(float)Math.Max(0,Math.Min(1,(now-mark-HoldSeconds)/AlertSeconds)):0;}
}

internal sealed class Storage {
    public readonly string DirectoryPath,FilePath;
    public string CapturesPath{get{return Path.Combine(DirectoryPath,"captures");}}
    public Storage(string directoryPath=null){
        DirectoryPath=directoryPath??Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"data");
        Directory.CreateDirectory(DirectoryPath);
        string temp=Path.Combine(DirectoryPath,"tmp");Directory.CreateDirectory(temp);
        Environment.SetEnvironmentVariable("TMP",temp);Environment.SetEnvironmentVariable("TEMP",temp);
        FilePath=Path.Combine(DirectoryPath,"settings.json");
    }
    public Preferences Load(){
        try{using(var f=File.OpenRead(FilePath)){var p=(Preferences)new DataContractJsonSerializer(typeof(Preferences)).ReadObject(f)??new Preferences();p.Validate();return p;}}
        catch(FileNotFoundException){return new Preferences();}catch(SerializationException){return new Preferences();}catch(System.Xml.XmlException){return new Preferences();}
    }
    public void Save(Preferences p){
        string tmp=FilePath+".new";
        using(var f=File.Create(tmp))new DataContractJsonSerializer(typeof(Preferences)).WriteObject(f,p);
        if(!File.Exists(FilePath)){File.Move(tmp,FilePath);return;}
        try{File.Replace(tmp,FilePath,null);}
        catch(IOException){ReplaceByRename(tmp);}
        catch(PlatformNotSupportedException){ReplaceByRename(tmp);}
    }
    // Some removable file systems cannot ReplaceFile. Keep the old file until
    // the new one has been renamed successfully, and restore it on failure.
    void ReplaceByRename(string tmp){
        string backup=FilePath+".previous";
        if(File.Exists(backup))File.Delete(backup);
        File.Move(FilePath,backup);
        try{File.Move(tmp,FilePath);File.Delete(backup);}
        catch{if(!File.Exists(FilePath)&&File.Exists(backup))File.Move(backup,FilePath);throw;}
    }
}

internal sealed class Stroke {
    public readonly List<PointF> Points=new List<PointF>();
    public Color Color;
    public float Width;
    public double Created;
    public bool Fades;
    public float Alpha(double now){return Fades?(float)Math.Max(0,Math.Min(1,(Created+4-now)/.6)):1;}
    public void Draw(Graphics g,double now){
        if(Points.Count==0)return;
        using(var p=new Pen(Color.FromArgb((int)(255*Alpha(now)),Color),Width)){p.StartCap=p.EndCap=LineCap.Round;p.LineJoin=LineJoin.Round;if(Points.Count==1)g.DrawLine(p,Points[0],new PointF(Points[0].X+.1f,Points[0].Y+.1f));else g.DrawLines(p,Points.ToArray());}
    }
}

// ---- Android phone or tablet over USB (scrcpy) ----
internal enum PhoneState{None,Unauthorized,Offline,Ready}
internal struct PhoneDevice{public PhoneState State;public string Serial,Name;}
// One video in the phone's gallery, from Android's media list. Added is in Unix seconds.
internal struct PhoneVideo{public string Name,Path;public long Added,Bytes;public double Seconds;}
internal static class PhoneModel {
    static readonly System.Text.RegularExpressions.Regex VideoRow=new System.Text.RegularExpressions.Regex(@"^Row: \d+ _display_name=(.*), _data=(/.*), date_added=(\d+), _size=(\d+), duration=(\S*)$");
    // Reads `adb shell content query --uri content://media/external/video/media` output, newest first.
    // Names may hold ", " and duration may be NULL.
    public static List<PhoneVideo> Videos(string output){
        var videos=new List<PhoneVideo>();var c=System.Globalization.CultureInfo.InvariantCulture;
        foreach(var line in (output??"").Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries)){
            var m=VideoRow.Match(line);if(!m.Success)continue;long added,bytes;double ms;
            long.TryParse(m.Groups[3].Value,System.Globalization.NumberStyles.None,c,out added);long.TryParse(m.Groups[4].Value,System.Globalization.NumberStyles.None,c,out bytes);
            if(!double.TryParse(m.Groups[5].Value,System.Globalization.NumberStyles.Float,c,out ms))ms=0;
            var v=new PhoneVideo{Name=m.Groups[1].Value,Path=m.Groups[2].Value,Added=added,Bytes=bytes,Seconds=ms/1000};
            // Newest first; equal dates keep the phone's order.
            int at=videos.Count;while(at>0&&videos[at-1].Added<v.Added)at--;videos.Insert(at,v);
        }
        return videos;
    }
    // "11월 6일 오후 7:44 · 1분 5초 · 63MB", short enough to read at a glance.
    public static string VideoLabel(PhoneVideo v){return VideoLabel(v,DateTimeOffset.FromUnixTimeSeconds(v.Added).LocalDateTime);}
    public static string VideoLabel(PhoneVideo v,DateTime when){
        string date=When(when);
        int total=(int)Math.Round(v.Seconds,MidpointRounding.AwayFromZero);
        string length=total>=60?Look.Tr(total/60+"분 "+total%60+"초",total/60+" min "+total%60+" s"):Look.Tr(total+"초",total+" s");
        long megabytes=Math.Max(1,(long)Math.Round(v.Bytes/1e6,MidpointRounding.AwayFromZero));
        return date+" · "+length+" · "+megabytes+"MB";
    }
    // "11월 6일 오후 7:44" or "Nov 6, 7:44 PM".
    public static string When(DateTime when){
        int hour=when.Hour%12==0?12:when.Hour%12;
        return Look.English?when.ToString("MMM d, h:mm tt",System.Globalization.CultureInfo.GetCultureInfo("en-US")):string.Format("{0}월 {1}일 {2} {3}:{4:00}",when.Month,when.Day,when.Hour<12?"오전":"오후",hour,when.Minute);
    }
    // The copy's name in the captures folder; characters Windows does not allow in a file name become _.
    public static string VideoFileName(string name){
        var b=new System.Text.StringBuilder((name??"").Trim());for(int i=0;i<b.Length;i++)if(b[i]<32||"<>:\"/\\|?*".IndexOf(b[i])>=0)b[i]='_';
        string safe=b.ToString().TrimEnd('.',' ');if(safe.Length==0)safe="video.mp4";
        // Only a video type, so a name such as x.exe or x.lnk from the phone cannot become something that runs when opened.
        if(Array.IndexOf(new[]{".mp4",".m4v",".mov",".3gp",".3g2",".mkv",".webm"},Path.GetExtension(safe).ToLowerInvariant())<0)safe+=".mp4";
        return "YelPoint-phone-video-"+safe;
    }
    // Reads `adb devices -l`. A ready device wins over one still waiting for permission.
    public static PhoneDevice Parse(string output){
        bool waiting=false,offline=false;
        foreach(var raw in (output??"").Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries)){
            if(raw.StartsWith("List of devices")||raw.StartsWith("*"))continue;
            var fields=raw.Split(new[]{' ','\t'},StringSplitOptions.RemoveEmptyEntries);if(fields.Length<2)continue;
            if(fields[1]=="device"){string name=fields[0];foreach(var f in fields)if(f.StartsWith("model:"))name=f.Substring(6);return new PhoneDevice{State=PhoneState.Ready,Serial=fields[0],Name=name.Replace('_',' ')};}
            if(fields[1]=="unauthorized")waiting=true;else if(fields[1]=="offline")offline=true;
        }
        return new PhoneDevice{State=waiting?PhoneState.Unauthorized:offline?PhoneState.Offline:PhoneState.None};
    }
    // One scrcpy window per mode. The camera turns into a document camera: back lens, no sound.
    public static string Arguments(string serial,bool camera,int rotation,bool light,string title,string record=null){
        var args=new List<string>{"--serial="+serial,"--window-title="+title,"--always-on-top","--display-orientation="+(((rotation%360)+360)%360),"--max-size=1920"};
        if(camera){args.AddRange(new[]{"--video-source=camera","--camera-facing=back","--no-audio","--camera-fps=30"});if(light)args.Add("--camera-torch");}
        else args.Add("--stay-awake");
        // Records what the window shows (and the phone's sound on Android 11+) to an MP4.
        if(record!=null)args.Add("--record="+record);
        return string.Join(" ",args.ConvertAll(Quote));
    }
    // Windows command-line quoting for one argument.
    public static string Quote(string arg){
        if(arg.Length>0&&arg.IndexOfAny(new[]{' ','\t','"'})<0)return arg;
        var b=new System.Text.StringBuilder("\"");int slashes=0;
        foreach(char c in arg){if(c=='\\'){slashes++;continue;}if(c=='"'){b.Append('\\',slashes*2+1);b.Append('"');}else{b.Append('\\',slashes);b.Append(c);}slashes=0;}
        b.Append('\\',slashes*2);b.Append('"');return b.ToString();
    }
}

// ---- 내 영상: the MP4s in the captures folder ----
internal struct SavedVideo{public string Path;public DateTime Written;public long Bytes;public bool Subtitles;}
internal static class MyVideos {
    // What made the video, read from its file name.
    public static string Kind(string fileName){
        string name=Name(fileName);const StringComparison k=StringComparison.OrdinalIgnoreCase;
        if(name.StartsWith("YelPoint-phone-video-",k))return Look.Tr("폰에서 가져온 영상","Video from the phone");
        if(name.StartsWith("YelPoint-phone-",k))return Look.Tr("폰 화면 녹화","Phone recording");
        if(Burned(name))return Look.Tr("자막 넣은 영상","Video with subtitles");
        if(name.StartsWith("YelPoint-",k))return Look.Tr("화면 녹화","Screen recording");
        return Look.Tr("영상","Video");
    }
    // The name after the last \ or /, the same on every system the tests run on.
    static string Name(string path){string p=path??"";return p.Substring(p.LastIndexOfAny(new[]{'\\','/'})+1);}
    // A video with the subtitles already in the picture (made on a Mac); it is watched, not edited.
    public static bool Burned(string fileName){return (fileName??"").EndsWith(".subtitled.mp4",StringComparison.OrdinalIgnoreCase);}
    // Newest first; the same time falls back to the name, which holds the time for YelPoint's own files.
    public static void NewestFirst(List<SavedVideo> videos){videos.Sort((a,b)=>{int c=b.Written.CompareTo(a.Written);return c!=0?c:string.Compare(Name(b.Path),Name(a.Path),StringComparison.OrdinalIgnoreCase);});}
    // Line 1: "11월 6일 오후 7:44 · 1분 5초 · 63MB". seconds is 0 while the length is unknown, and then it is left out.
    public static string Label(SavedVideo v,double seconds){
        if(seconds>0)return PhoneModel.VideoLabel(new PhoneVideo{Seconds=seconds,Bytes=v.Bytes},v.Written);
        return PhoneModel.When(v.Written)+" · "+Math.Max(1,(long)Math.Round(v.Bytes/1e6,MidpointRounding.AwayFromZero))+"MB";
    }
    // Line 2: "화면 녹화 · 자막 있음".
    public static string Detail(SavedVideo v){return Kind(v.Path)+(v.Subtitles?Look.Tr(" · 자막 있음"," · Has subtitles"):"");}
}

// ---- QR code for a web address: byte mode, error correction M, versions 1 to 10 ----
internal static class QrCode {
    static readonly int[] Total={0,26,44,70,100,134,172,196,242,292,346};
    static readonly int[] EccPerBlock={0,10,16,26,18,24,16,18,22,22,26};
    // Pairs of (block count, data codewords per block).
    static readonly int[][] Blocks={null,new[]{1,16},new[]{1,28},new[]{1,44},new[]{2,32},new[]{2,43},new[]{4,27},new[]{4,31},new[]{2,38,2,39},new[]{3,36,2,37},new[]{4,43,1,44}};
    static readonly int[][] Align={null,new int[0],new[]{6,18},new[]{6,22},new[]{6,26},new[]{6,30},new[]{6,34},new[]{6,22,38},new[]{6,24,42},new[]{6,26,46},new[]{6,28,50}};
    public const int MaxBytes=213;
    static int BlockCount(int v){int n=0;for(int i=0;i<Blocks[v].Length;i+=2)n+=Blocks[v][i];return n;}
    // Dark modules as [row, column]. Null when the text is empty or longer than MaxBytes in UTF-8.
    public static bool[,] Encode(string text){
        var data=System.Text.Encoding.UTF8.GetBytes(text??"");if(data.Length==0)return null;
        int version=0,dataCodewords=0;
        for(int v=1;v<=10;v++){int cw=Total[v]-EccPerBlock[v]*BlockCount(v);if(4+(v<10?8:16)+8*data.Length<=cw*8){version=v;dataCodewords=cw;break;}}
        if(version==0)return null;
        var bits=new List<bool>();
        Action<int,int> put=(value,count)=>{for(int i=count-1;i>=0;i--)bits.Add(((value>>i)&1)!=0);};
        put(4,4);put(data.Length,version<10?8:16);foreach(var b in data)put(b,8);
        put(0,Math.Min(4,dataCodewords*8-bits.Count));
        while(bits.Count%8!=0)bits.Add(false);
        var codewords=new List<byte>();
        for(int i=0;i<bits.Count;i+=8){int v=0;for(int j=0;j<8;j++)v=(v<<1)|(bits[i+j]?1:0);codewords.Add((byte)v);}
        for(int pad=0;codewords.Count<dataCodewords;pad++)codewords.Add(pad%2==0?(byte)0xEC:(byte)0x11);
        int ecc=EccPerBlock[version];var divisor=Divisor(ecc);
        var dataBlocks=new List<byte[]>();int offset=0;
        for(int g=0;g<Blocks[version].Length;g+=2)for(int k=0;k<Blocks[version][g];k++){dataBlocks.Add(codewords.GetRange(offset,Blocks[version][g+1]).ToArray());offset+=Blocks[version][g+1];}
        var eccBlocks=dataBlocks.ConvertAll(b=>Remainder(b,divisor));
        var stream=new List<byte>();int longest=0;foreach(var b in dataBlocks)longest=Math.Max(longest,b.Length);
        for(int i=0;i<longest;i++)foreach(var b in dataBlocks)if(i<b.Length)stream.Add(b[i]);
        for(int i=0;i<ecc;i++)foreach(var b in eccBlocks)stream.Add(b[i]);
        var q=new Matrix(17+4*version);
        q.DrawFunctions(version,Align[version]);
        q.DrawCodewords(stream);
        int best=0;long bestPenalty=long.MaxValue;
        for(int mask=0;mask<8;mask++){q.ApplyMask(mask);q.DrawFormat(mask);long p=q.Penalty();if(p<bestPenalty){bestPenalty=p;best=mask;}q.ApplyMask(mask);}
        q.ApplyMask(best);q.DrawFormat(best);
        return q.Dark;
    }
    static int Multiply(int x,int y){int z=0;for(int i=7;i>=0;i--){z=(z<<1)^((z>>7)*0x11D);z^=((y>>i)&1)*x;}return z;}
    static byte[] Divisor(int degree){
        var result=new byte[degree];result[degree-1]=1;int root=1;
        for(int i=0;i<degree;i++){for(int j=0;j<degree;j++){result[j]=(byte)Multiply(result[j],root);if(j+1<degree)result[j]^=result[j+1];}root=Multiply(root,2);}
        return result;
    }
    static byte[] Remainder(byte[] data,byte[] divisor){
        var result=new byte[divisor.Length];
        foreach(var b in data){int factor=b^result[0];Array.Copy(result,1,result,0,result.Length-1);result[result.Length-1]=0;for(int i=0;i<result.Length;i++)result[i]^=(byte)Multiply(divisor[i],factor);}
        return result;
    }
    sealed class Matrix {
        public readonly int Size;public readonly bool[,] Dark;readonly bool[,] function;
        public Matrix(int size){Size=size;Dark=new bool[size,size];function=new bool[size,size];}
        void Set(int x,int y,bool dark){Dark[y,x]=dark;function[y,x]=true;}
        public void DrawFunctions(int version,int[] align){
            for(int i=0;i<Size;i++){Set(6,i,i%2==0);Set(i,6,i%2==0);}
            foreach(var c in new[]{new[]{3,3},new[]{Size-4,3},new[]{3,Size-4}})
                for(int dy=-4;dy<=4;dy++)for(int dx=-4;dx<=4;dx++){int x=c[0]+dx,y=c[1]+dy;if(x<0||y<0||x>=Size||y>=Size)continue;int d=Math.Max(Math.Abs(dx),Math.Abs(dy));Set(x,y,d!=2&&d!=4);}
            int n=align.Length;
            for(int i=0;i<n;i++)for(int j=0;j<n;j++){
                if(i==0&&j==0||i==0&&j==n-1||i==n-1&&j==0)continue;
                for(int dy=-2;dy<=2;dy++)for(int dx=-2;dx<=2;dx++)Set(align[i]+dx,align[j]+dy,Math.Max(Math.Abs(dx),Math.Abs(dy))!=1);
            }
            DrawFormat(0);
            if(version>=7){
                int rem=version;for(int i=0;i<12;i++)rem=(rem<<1)^((rem>>11)*0x1F25);int bits=version<<12|rem;
                for(int i=0;i<18;i++){bool bit=((bits>>i)&1)!=0;int a=Size-11+i%3,b=i/3;Set(a,b,bit);Set(b,a,bit);}
            }
        }
        // Error correction M has format bits 00.
        public void DrawFormat(int mask){
            int data=0<<3|mask,rem=data;for(int i=0;i<10;i++)rem=(rem<<1)^((rem>>9)*0x537);int bits=(data<<10|rem)^0x5412;
            Func<int,bool> bit=i=>((bits>>i)&1)!=0;
            for(int i=0;i<=5;i++)Set(8,i,bit(i));
            Set(8,7,bit(6));Set(8,8,bit(7));Set(7,8,bit(8));
            for(int i=9;i<15;i++)Set(14-i,8,bit(i));
            for(int i=0;i<8;i++)Set(Size-1-i,8,bit(i));
            for(int i=8;i<15;i++)Set(8,Size-15+i,bit(i));
            Set(8,Size-8,true);
        }
        public void DrawCodewords(List<byte> stream){
            int i=0;
            for(int right=Size-1;right>=1;right-=2){
                if(right==6)right=5;
                for(int vert=0;vert<Size;vert++)for(int j=0;j<2;j++){
                    int x=right-j;bool upward=((right+1)&2)==0;int y=upward?Size-1-vert:vert;
                    if(!function[y,x]&&i<stream.Count*8){Dark[y,x]=((stream[i>>3]>>(7-(i&7)))&1)!=0;i++;}
                }
            }
        }
        public void ApplyMask(int mask){
            for(int y=0;y<Size;y++)for(int x=0;x<Size;x++){
                if(function[y,x])continue;bool flip;
                switch(mask){
                    case 0:flip=(x+y)%2==0;break;case 1:flip=y%2==0;break;case 2:flip=x%3==0;break;case 3:flip=(x+y)%3==0;break;
                    case 4:flip=(x/3+y/2)%2==0;break;case 5:flip=x*y%2+x*y%3==0;break;case 6:flip=(x*y%2+x*y%3)%2==0;break;default:flip=((x+y)%2+x*y%3)%2==0;break;
                }
                if(flip)Dark[y,x]=!Dark[y,x];
            }
        }
        public long Penalty(){
            long result=0;int dark=0;
            for(int pass=0;pass<2;pass++)for(int a=0;a<Size;a++){
                int run=0;bool color=false;var line=new bool[Size];
                for(int b=0;b<Size;b++){
                    bool m=pass==0?Dark[a,b]:Dark[b,a];line[b]=m;
                    if(b>0&&m==color)run++;else{if(run>=5)result+=3+run-5;color=m;run=1;}
                }
                if(run>=5)result+=3+run-5;
                for(int b=0;b+11<=Size;b++){
                    bool p1=!line[b]&&!line[b+1]&&!line[b+2]&&!line[b+3]&&line[b+4]&&!line[b+5]&&line[b+6]&&line[b+7]&&line[b+8]&&!line[b+9]&&line[b+10];
                    bool p2=line[b]&&!line[b+1]&&line[b+2]&&line[b+3]&&line[b+4]&&!line[b+5]&&line[b+6]&&!line[b+7]&&!line[b+8]&&!line[b+9]&&!line[b+10];
                    if(p1||p2)result+=40;
                }
            }
            for(int y=0;y<Size;y++)for(int x=0;x<Size;x++){
                if(Dark[y,x])dark++;
                if(x+1<Size&&y+1<Size&&Dark[y,x]==Dark[y,x+1]&&Dark[y,x]==Dark[y+1,x]&&Dark[y,x]==Dark[y+1,x+1])result+=3;
            }
            int total=Size*Size;long k=(Math.Abs(dark*20L-total*10L)+total-1)/total-1;result+=Math.Max(0,k)*10;
            return result;
        }
    }
}

// ---- Subtitles for a recording ----
[DataContract] internal sealed class Cue {
    [DataMember] public double Start;[DataMember] public double End;[DataMember] public string Text="";
}
internal static class Subtitles {
    // SubRip text, which most players and YouTube read.
    public static string Srt(List<Cue> cues){
        var sorted=new List<Cue>(cues);sorted.Sort((a,b)=>a.Start.CompareTo(b.Start));
        var b=new System.Text.StringBuilder();
        for(int i=0;i<sorted.Count;i++){if(i>0)b.Append('\n');b.Append(i+1).Append('\n').Append(Stamp(sorted[i].Start)).Append(" --> ").Append(Stamp(sorted[i].End)).Append('\n').Append(sorted[i].Text).Append('\n');}
        return b.ToString();
    }
    static string Stamp(double t){long ms=(long)Math.Round(Math.Max(0,t)*1000);return string.Format(System.Globalization.CultureInfo.InvariantCulture,"{0:00}:{1:00}:{2:00},{3:000}",ms/3600000,ms/60000%60,ms/1000%60,ms%1000);}
    // "1:02.5" or "62.5" in seconds; null when it cannot be read.
    public static double? Parse(string text){
        var parts=(text??"").Trim().Split(':');double m,s;var c=System.Globalization.CultureInfo.InvariantCulture;
        if(parts.Length==2&&double.TryParse(parts[0],System.Globalization.NumberStyles.Float,c,out m)&&double.TryParse(parts[1],System.Globalization.NumberStyles.Float,c,out s))return m*60+s;
        if(parts.Length==1&&double.TryParse(parts[0],System.Globalization.NumberStyles.Float,c,out s))return s;
        return null;
    }
    // Typing starts a line a moment before now, since people type after they hear it, but never before the previous line ends.
    public static double TypingStart(List<Cue> cues,double now){
        now=Math.Max(0,now);double previousEnd=0;foreach(var c in cues)if(c.Start<now)previousEnd=Math.Max(previousEnd,c.End);
        return Math.Max(previousEnd,now-1);
    }
    // Long enough to read (0.22 s a character, 2 to 7 s), cut at the next line, and at least half a second.
    public static double CueEnd(List<Cue> cues,double start,string text){
        double end=start+Math.Max(2,Math.Min(7,new System.Globalization.StringInfo(text??"").LengthInTextElements*.22));
        foreach(var c in cues)if(c.Start>start+.05)end=Math.Min(end,c.Start);
        return Math.Max(end,start+.5);
    }
    // Older versions added this line as a placeholder; it is never a real subtitle.
    public static bool Placeholder(Cue c){return c==null||c.Text=="자막을 입력하세요"||c.Text=="Type the subtitle";}
    public static string Clock(double t){return string.Format(System.Globalization.CultureInfo.InvariantCulture,"{0}:{1:00.0}",(int)t/60,t%60);}
}
}
