using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace YelPoint {
// Small, fast, repeatable random numbers, so a stroke redraws the same grain after an undo.
internal struct ChalkRandom {
    ulong state;
    public ChalkRandom(ulong seed){state=seed;}
    public ulong Next(){unchecked{state+=0x9E3779B97F4A7C15UL;ulong z=state;z=(z^(z>>30))*0xBF58476D1CE4E5B9UL;z=(z^(z>>27))*0x94D049BB133111EBUL;return z^(z>>31);}}
    public float Unit(){return (float)((Next()>>11)/(double)(1UL<<53));}
}

internal sealed class ChalkMark {
    public int Kind; // 0 stroke, 1 text, 2 erase
    public List<PointF> Points=new List<PointF>();
    public string Text;public PointF At;public int Color,Font;public float Width,Size;public ulong Seed;
    public float Grain=1; // the board's DPI factor when it was drawn, so the grain density stays the same
}

// A green chalkboard in a wooden frame with a chalk tray. Draw, write Korean or English, erase, save.
internal sealed class BoardForm:Form {
    public static readonly Color[] Chalks={Color.FromArgb(245,242,232),Color.FromArgb(247,219,107),Color.FromArgb(245,168,186),Color.FromArgb(158,212,240),Color.FromArgb(186,227,161)};
    // The DPI factor of the display the board opened on; frame, tray, chalk and text grow with it.
    public float UiScale=1;
    int P(float value){return Look.Px(value,UiScale);}
    int Frame{get{return P(22);}}
    int Tray{get{return P(76);}}
    readonly Controller app;
    public readonly List<ChalkMark> Marks=new List<ChalkMark>();
    List<ChalkMark> wiped;
    public int ChalkColor;public bool Thick;public int Tool; // 0 chalk, 1 text, 2 eraser
    public int Letters; // index into LetterNames: handwriting, sans, serif
    bool exporting; // saving a PNG: leave the tray buttons out
    Bitmap ink,surface;ChalkMark current;TextBox editor;PointF editorPoint;
    // Board lettering, all SIL OFL 1.1 and embedded in the program. Each covers Korean and English.
    static readonly string[] LetterFiles={"NanumPenScript-Regular.ttf","NanumGothic-Bold.ttf","NanumMyeongjo-Bold.ttf"};
    public static readonly string[][] LetterNames={new[]{"손글씨","Handwriting"},new[]{"고딕","Sans"},new[]{"명조","Serif"}};
    static readonly float[] LetterScale={1f,0.78f,0.78f}; // handwriting runs small
    static readonly PrivateFontCollection[] fonts=new PrivateFontCollection[3];
    public BoardForm(Controller app){
        this.app=app;FormBorderStyle=FormBorderStyle.None;StartPosition=FormStartPosition.Manual;ShowInTaskbar=false;TopMost=true;KeyPreview=true;Text=Look.Tr("YelPoint 칠판","YelPoint Board");
        SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.UserPaint,true);
        KeyDown+=(s,e)=>{if(editor!=null)return;if(e.KeyCode==Keys.Escape)app.CloseBoard();else if(e.Control&&e.KeyCode==Keys.Z)Undo();};
    }
    Rectangle BoardRect{get{return new Rectangle(Frame,Frame,ClientSize.Width-Frame*2,ClientSize.Height-Frame-Tray);}}
    Rectangle TrayRect{get{return new Rectangle(0,ClientSize.Height-Tray,ClientSize.Width,Tray);}}
    float StrokeWidth{get{return (Thick?14:6)*UiScale;}}
    float TextSize{get{return (Thick?84:56)*UiScale;}}
    // Opens on a work area. A new DPI changes the frame and tray, so the board surface is made again.
    public void Place(Rectangle area,float scale){
        bool changed=scale!=UiScale;UiScale=scale;if(changed&&surface!=null){surface.Dispose();surface=null;}
        if(Bounds!=area)Bounds=area;else if(changed)RedrawInk();
    }
    // Nanum Pen Script, Nanum Gothic Bold or Nanum Myeongjo Bold, each in its own collection.
    public static FontFamily ChalkFamily(int style=0){
        if(style<0||style>=LetterFiles.Length)style=0;
        if(fonts[style]==null){
            fonts[style]=new PrivateFontCollection();
            using(var stream=System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream(LetterFiles[style])){
                // The memory stays allocated for the life of the program, as AddMemoryFont requires.
                if(stream!=null){var bytes=new byte[stream.Length];stream.Read(bytes,0,bytes.Length);var memory=Marshal.AllocCoTaskMem(bytes.Length);Marshal.Copy(bytes,0,memory,bytes.Length);fonts[style].AddMemoryFont(memory,bytes.Length);}
            }
        }
        return fonts[style].Families.Length>0?fonts[style].Families[0]:new FontFamily("Malgun Gothic");
    }
    // The Bold-only files have no Regular style, so take whichever style the family has.
    public static Font ChalkFont(int style,float size){
        var family=ChalkFamily(style);
        var look=family.IsStyleAvailable(FontStyle.Regular)?FontStyle.Regular:FontStyle.Bold;
        return new Font(family,size*LetterScale[style<0||style>=LetterScale.Length?0:style],look,GraphicsUnit.Pixel);
    }
    protected override void OnResize(EventArgs e){base.OnResize(e);if(surface!=null){surface.Dispose();surface=null;}RedrawInk();}
    void RedrawInk(){
        var r=BoardRect;if(r.Width<10||r.Height<10)return;
        if(ink==null||ink.Width!=r.Width||ink.Height!=r.Height){if(ink!=null)ink.Dispose();ink=new Bitmap(r.Width,r.Height,System.Drawing.Imaging.PixelFormat.Format32bppPArgb);}
        using(var g=Graphics.FromImage(ink)){g.Clear(Color.Transparent);g.SmoothingMode=SmoothingMode.AntiAlias;foreach(var m in Marks)Render(m,g);}
        Invalidate();
    }
    // Piece by piece with the same seeds Extend used, so a full redraw after undo looks exactly like the live drawing.
    void Render(ChalkMark m,Graphics g){
        if(m.Kind==1){var random=new ChalkRandom(m.Seed);ChalkText(m,ref random,g);return;}
        for(int i=0;i<m.Points.Count;i++){
            var piece=new List<PointF>{m.Points[Math.Max(0,i-1)],m.Points[i]};
            if(m.Kind==2)Erase(piece,m.Width,g);else{var random=new ChalkRandom(m.Seed+(ulong)(i+1));ChalkLine(piece,Chalks[m.Color],m.Width,m.Grain,ref random,g);}
        }
    }
    // Chalk is a spray of grains, denser in the middle, with gaps where the board shows.
    static void ChalkLine(List<PointF> points,Color color,float width,float density,ref ChalkRandom random,Graphics g){
        if(points.Count==0)return;
        var path=points.Count==1?new List<PointF>{points[0],points[0]}:points;
        using(var brush=new SolidBrush(color))for(int i=1;i<path.Count;i++){
            var a=path[i-1];var b=path[i];float length=(float)Math.Sqrt((b.X-a.X)*(b.X-a.X)+(b.Y-a.Y)*(b.Y-a.Y));
            int steps=Math.Max(1,(int)(length/Math.Max(1,width/density*0.3f)));
            for(int s=0;s<steps;s++){
                float t=s/(float)steps,px=a.X+(b.X-a.X)*t,py=a.Y+(b.Y-a.Y)*t;
                for(int k=0;k<(int)(width*2.2f);k++){
                    if(random.Unit()<0.18f)continue;
                    double angle=random.Unit()*Math.PI*2;float r=width*0.5f*(float)Math.Sqrt(random.Unit());float grain=0.5f+random.Unit()*1.6f;
                    brush.Color=Color.FromArgb((int)(255*(0.25f+random.Unit()*0.6f)),color);
                    g.FillRectangle(brush,px+(float)Math.Cos(angle)*r-grain/2,py+(float)Math.Sin(angle)*r-grain/2,grain,grain);
                }
            }
        }
    }
    static void ChalkText(ChalkMark m,ref ChalkRandom random,Graphics g){
        g.TextRenderingHint=TextRenderingHint.AntiAlias;
        using(var font=ChalkFont(m.Font,m.Size))using(var brush=new SolidBrush(Color.FromArgb(237,Chalks[m.Color]))){
            var size=g.MeasureString(m.Text,font);g.DrawString(m.Text,font,brush,m.At);
            // Rub some grains out so the letters look written in chalk.
            var old=g.CompositingMode;g.CompositingMode=CompositingMode.SourceCopy;
            using(var clear=new SolidBrush(Color.Transparent))for(int i=0;i<(int)(size.Width*size.Height*0.035f);i++){float grain=0.6f+random.Unit()*1.4f;g.FillRectangle(clear,m.At.X+random.Unit()*size.Width,m.At.Y+random.Unit()*size.Height,grain,grain);}
            g.CompositingMode=old;
        }
    }
    static void Erase(List<PointF> points,float width,Graphics g){
        var old=g.CompositingMode;g.CompositingMode=CompositingMode.SourceCopy;
        using(var pen=new Pen(Color.Transparent,width){StartCap=LineCap.Round,EndCap=LineCap.Round,LineJoin=LineJoin.Round})
            if(points.Count==1)using(var b=new SolidBrush(Color.Transparent))g.FillEllipse(b,points[0].X-width/2,points[0].Y-width/2,width,width);else g.DrawLines(pen,points.ToArray());
        g.CompositingMode=old;
    }
    Bitmap MakeSurface(Size size){
        var bmp=new Bitmap(size.Width,size.Height);var random=new ChalkRandom(7);
        using(var g=Graphics.FromImage(bmp)){
            using(var b=new LinearGradientBrush(new Rectangle(Point.Empty,size),Color.FromArgb(51,97,79),Color.FromArgb(38,77,64),70f))g.FillRectangle(b,0,0,size.Width,size.Height);
            for(int i=0;i<size.Width*size.Height/26000;i++){
                float cx=random.Unit()*size.Width,cy=random.Unit()*size.Height,rad=60+random.Unit()*220;
                using(var path=new GraphicsPath()){path.AddEllipse(cx-rad*1.6f,cy-rad*0.7f,rad*3.2f,rad*1.4f);using(var pb=new PathGradientBrush(path){CenterColor=Color.FromArgb(9,255,255,255),SurroundColors=new[]{Color.FromArgb(0,255,255,255)}})g.FillPath(pb,path);}
            }
            using(var dust=new SolidBrush(Color.White))for(int i=0;i<size.Width*size.Height/220;i++){dust.Color=Color.FromArgb((int)(255*(0.02f+random.Unit()*0.04f)),255,255,255);g.FillRectangle(dust,random.Unit()*size.Width,random.Unit()*size.Height,1.2f,1.2f);}
        }
        return bmp;
    }
    static void Wood(Graphics g,Rectangle r,float light,ulong seed){
        using(var b=new LinearGradientBrush(r,Color.FromArgb((int)(140*light),(int)(84*light),(int)(46*light)),Color.FromArgb((int)(102*light),(int)(56*light),(int)(28*light)),90f))g.FillRectangle(b,r);
        var random=new ChalkRandom(seed);
        using(var pen=new Pen(Color.FromArgb(64,77,41,20),0.6f))for(int i=0;i<r.Height/4;i++){float y=r.Top+i*4+random.Unit()*2;g.DrawBezier(pen,r.Left,y,r.Left+r.Width*0.3f,y+random.Unit()*4-2,r.Left+r.Width*0.7f,y+random.Unit()*4-2,r.Right,y+random.Unit()*3);}
    }
    struct TrayItem{public string Id,Title;public Rectangle Rect;}
    List<TrayItem> TrayItems(Graphics g){
        var titles=new[]{new[]{"thick",Thick?Look.Tr("굵게","Thick"):Look.Tr("가늘게","Thin")},new[]{"text",Look.Tr("글씨","Text")},new[]{"font",Look.Tr(LetterNames[Letters][0],LetterNames[Letters][1])},new[]{"eraser",Look.Tr("지우개","Eraser")},new[]{"undo",Look.Tr("되돌리기","Undo")},new[]{"wipe",Look.Tr("모두 지우기","Wipe")},new[]{"save",Look.Tr("PNG 저장","Save PNG")},new[]{"close",Look.Tr("닫기","Close")}};
        var list=new List<TrayItem>();int x=ClientSize.Width-P(18);
        using(var font=Look.Pixels(15*UiScale)){for(int i=titles.Length-1;i>=0;i--){int w=(int)g.MeasureString(titles[i][1],font).Width+P(30);x-=w;list.Insert(0,new TrayItem{Id=titles[i][0],Title=titles[i][1],Rect=new Rectangle(x,TrayRect.Top+P(20),w,P(40))});x-=P(8);}}
        return list;
    }
    Rectangle ChalkRect(int i){return new Rectangle(P(40+i*70),TrayRect.Top+P(i==ChalkColor&&Tool==0?24:32),P(54),P(16));}
    protected override void OnPaint(PaintEventArgs e){
        var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;var board=BoardRect;
        Wood(g,ClientRectangle,1,3);
        if(surface==null&&board.Width>10&&board.Height>10)surface=MakeSurface(board.Size);
        using(var shade=new SolidBrush(Color.FromArgb(100,0,0,0)))g.FillRectangle(shade,Rectangle.Inflate(board,2,2));
        if(surface!=null)g.DrawImageUnscaled(surface,board.Location);
        if(ink!=null)g.DrawImageUnscaled(ink,board.Location);
        var tray=TrayRect;tray.Inflate(-P(6),-P(4));Wood(g,tray,1.15f,9);
        using(var dust=new SolidBrush(Color.FromArgb(20,255,255,255)))g.FillRectangle(dust,P(30),TrayRect.Top+P(44),P(380),P(10));
        for(int i=0;i<Chalks.Length;i++){
            var r=ChalkRect(i);
            if(i==ChalkColor&&Tool==0)using(var glow=new SolidBrush(Color.FromArgb(90,Chalks[i])))FillRound(g,glow,Rectangle.Inflate(r,P(5),P(5)),P(10));
            using(var b=new SolidBrush(Chalks[i]))FillRound(g,b,r,P(7));
            using(var b=new SolidBrush(Color.FromArgb(30,0,0,0)))g.FillRectangle(b,r.Left+P(3),r.Top+r.Height/2+P(2),r.Width-P(6),r.Height/2-P(3));
        }
        if(!exporting)using(var font=Look.Pixels(15*UiScale))foreach(var item in TrayItems(g)){
            bool selected=item.Id=="text"&&Tool==1||item.Id=="eraser"&&Tool==2||item.Id=="thick"&&Thick;
            using(var b=new SolidBrush(selected?Color.FromArgb(217,255,255,255):Color.FromArgb(56,0,0,0)))FillRound(g,b,item.Rect,P(10));
            using(var b=new SolidBrush(selected?Color.FromArgb(64,38,20):Color.FromArgb(235,255,255,255)))g.DrawString(item.Title,font,b,item.Rect,new StringFormat{Alignment=StringAlignment.Center,LineAlignment=StringAlignment.Center});
        }
    }
    static void FillRound(Graphics g,Brush b,Rectangle r,int radius){using(var p=new GraphicsPath()){int d=radius*2;p.AddArc(r.X,r.Y,d,d,180,90);p.AddArc(r.Right-d,r.Y,d,d,270,90);p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.X,r.Bottom-d,d,d,90,90);p.CloseFigure();g.FillPath(b,p);}}
    PointF BoardPoint(Point p){return new PointF(p.X-BoardRect.Left,p.Y-BoardRect.Top);}
    protected override void OnMouseDown(MouseEventArgs e){
        if(TrayRect.Contains(e.Location)){TrayClick(e.Location);return;}
        if(!BoardRect.Contains(e.Location))return;
        var b=BoardPoint(e.Location);
        if(Tool==1){if(editor!=null)FinishText();else BeginText(b);return;}
        FinishText();
        current=new ChalkMark{Kind=Tool==2?2:0,Color=ChalkColor,Width=Tool==2?StrokeWidth*5:StrokeWidth,Seed=(ulong)DateTime.Now.Ticks,Grain=UiScale};
        Extend(b);
    }
    protected override void OnMouseMove(MouseEventArgs e){if(current!=null&&e.Button==MouseButtons.Left)Extend(BoardPoint(e.Location));}
    // The stroke is already on the ink layer, drawn piece by piece; only undo, wipe and resize redraw everything.
    protected override void OnMouseUp(MouseEventArgs e){if(current==null)return;Marks.Add(current);current=null;wiped=null;}
    // Draws only the newest piece, so long strokes stay smooth.
    void Extend(PointF p){
        if(ink==null)RedrawInk();if(ink==null)return;
        var last=current.Points.Count>0?current.Points[current.Points.Count-1]:p;
        if(current.Points.Count>1&&Math.Abs(p.X-last.X)+Math.Abs(p.Y-last.Y)<2)return;
        current.Points.Add(p);var piece=new List<PointF>{last,p};
        using(var g=Graphics.FromImage(ink)){g.SmoothingMode=SmoothingMode.AntiAlias;if(current.Kind==2)Erase(piece,current.Width,g);else{var random=new ChalkRandom(current.Seed+(ulong)current.Points.Count);ChalkLine(piece,Chalks[current.Color],current.Width,current.Grain,ref random,g);}}
        var board=BoardRect;int pad=(int)current.Width+4;
        Invalidate(new Rectangle((int)Math.Min(last.X,p.X)+board.Left-pad,(int)Math.Min(last.Y,p.Y)+board.Top-pad,(int)Math.Abs(p.X-last.X)+pad*2,(int)Math.Abs(p.Y-last.Y)+pad*2));
    }
    void TrayClick(Point p){
        for(int i=0;i<Chalks.Length;i++)if(Rectangle.Inflate(ChalkRect(i),P(6),P(10)).Contains(p)){FinishText();ChalkColor=i;Tool=0;Invalidate();return;}
        using(var g=CreateGraphics())foreach(var item in TrayItems(g)){
            if(!item.Rect.Contains(p))continue;
            if(item.Id=="thick")Thick=!Thick;
            else if(item.Id=="text"){FinishText();Tool=Tool==1?0:1;}
            else if(item.Id=="font"){FinishText();Letters=(Letters+1)%LetterFiles.Length;Tool=1;}
            else if(item.Id=="eraser"){FinishText();Tool=Tool==2?0:2;}
            else if(item.Id=="undo")Undo();
            else if(item.Id=="wipe")Wipe();
            else if(item.Id=="save")app.SaveBoard(this);
            else app.CloseBoard();
            Invalidate();return;
        }
    }
    public void Undo(){FinishText();if(wiped!=null){Marks.AddRange(wiped);wiped=null;}else if(Marks.Count>0)Marks.RemoveAt(Marks.Count-1);RedrawInk();}
    public void Wipe(){FinishText();if(Marks.Count==0)return;wiped=new List<ChalkMark>(Marks);Marks.Clear();RedrawInk();}
    // Text goes through a real text box, so Korean and English input methods both work.
    void BeginText(PointF p){
        editor=new TextBox{BorderStyle=BorderStyle.None,BackColor=Color.FromArgb(44,86,70),ForeColor=Chalks[ChalkColor],Font=new Font("Malgun Gothic",TextSize*0.6f,GraphicsUnit.Pixel),ImeMode=ImeMode.On};
        editor.Bounds=new Rectangle((int)p.X+BoardRect.Left,(int)p.Y+BoardRect.Top,Math.Max(P(240),BoardRect.Right-(int)p.X-BoardRect.Left-P(20)),(int)(TextSize*0.9f));
        editor.KeyDown+=(s,e)=>{if(e.KeyCode==Keys.Enter){e.SuppressKeyPress=true;FinishText();}else if(e.KeyCode==Keys.Escape){e.SuppressKeyPress=true;editor.Text="";FinishText();}};
        editorPoint=p;Controls.Add(editor);editor.Focus();
    }
    public void FinishText(){
        if(editor==null)return;var box=editor;editor=null;string text=box.Text.Trim();Controls.Remove(box);box.Dispose();Focus();
        if(text.Length>0)WriteText(text,editorPoint);
    }
    public void WriteText(string text,PointF at){
        var mark=new ChalkMark{Kind=1,Text=text,At=at,Color=ChalkColor,Font=Letters,Size=TextSize,Seed=(ulong)(Marks.Count+1)*7919};Marks.Add(mark);wiped=null;
        // Only the new words are drawn onto the ink layer.
        if(ink==null){RedrawInk();return;}using(var g=Graphics.FromImage(ink)){g.SmoothingMode=SmoothingMode.AntiAlias;Render(mark,g);}Invalidate();
    }
    public Bitmap Snapshot(){FinishText();var bmp=new Bitmap(ClientSize.Width,ClientSize.Height);exporting=true;try{DrawToBitmap(bmp,ClientRectangle);}finally{exporting=false;}return bmp;}
    protected override void Dispose(bool disposing){if(disposing){if(ink!=null)ink.Dispose();if(surface!=null)surface.Dispose();}base.Dispose(disposing);}
}
}
