using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace YelPoint {
// Type or paste an address, press Enter, and it shows big in the middle of the screen.
internal sealed class QrForm:FloatingForm {
    public readonly TextBox Field;
    public QrForm(Controller app){
        Size=new Size(S(560),S(48));
        Field=new TextBox{Bounds=new Rectangle(S(12),S(12),S(392),S(24)),Font=Look.Pixels(14*ScaleFactor),BorderStyle=BorderStyle.FixedSingle,AccessibleName=Look.Tr("QR로 만들 주소","Address for the QR code")};
        Field.KeyDown+=(s,e)=>{if(e.KeyCode==Keys.Enter){e.SuppressKeyPress=true;app.ShowQr(Field.Text);if(!Visible)RestoreForeground();}};
        Controls.Add(Field);
        var show=new ToolButton(Look.Tr("크게 보기","Show"),"qr"){Bounds=new Rectangle(S(412),S(4),S(100),S(40)),AccessibleName=Look.Tr("QR 코드를 화면 가운데 크게 띄우기","Show the QR code big in the middle of the screen")};show.Click+=(s,e)=>{app.ShowQr(Field.Text);if(!Visible)RestoreForeground();};Controls.Add(show);
        var close=new ToolButton("","off"){Bounds=new Rectangle(S(514),S(4),S(40),S(40)),AccessibleName=Look.Tr("QR 창 닫기","Close the QR window")};close.Click+=(s,e)=>app.CloseQr();Controls.Add(close);
    }
}

// The big white card: the code, and the address under it for anyone who would rather type it.
internal sealed class QrWindow:Form {
    readonly Controller app;
    bool[,] code;string text="";Point grab;bool dragging;
    // The DPI factor of the display it opened on, for the caption, margins and close button.
    float scale=1;
    int P(float value){return Look.Px(value,scale);}
    public QrWindow(Controller app){
        this.app=app;FormBorderStyle=FormBorderStyle.None;StartPosition=FormStartPosition.Manual;ShowInTaskbar=false;TopMost=true;BackColor=Color.White;KeyPreview=true;
        SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.UserPaint,true);
        KeyDown+=(s,e)=>{if(e.KeyCode==Keys.Escape)app.CloseQr();};
    }
    public bool Show(string address,Rectangle area){
        var next=QrCode.Encode(address);if(next==null)return false;
        code=next;text=address;scale=Native.ScaleOf(area);
        int side=(int)Math.Min(Math.Min(area.Height*0.82,area.Width*0.6),900*scale);
        Bounds=new Rectangle(area.X+(area.Width-(side-P(70)))/2,area.Y+(area.Height-side)/2-P(30),side-P(70),side);
        using(var path=Round(new Rectangle(0,0,Width,Height),P(26)))Region=new Region(path);
        Show();Activate();Invalidate();return true;
    }
    Rectangle CloseRect{get{return new Rectangle(Width-P(52),P(12),P(40),P(40));}}
    static GraphicsPath Round(Rectangle r,int radius){var p=new GraphicsPath();int d=radius*2;p.AddArc(r.X,r.Y,d,d,180,90);p.AddArc(r.Right-d,r.Y,d,d,270,90);p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.X,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;}
    protected override void OnPaint(PaintEventArgs e){
        var g=e.Graphics;g.Clear(Color.White);if(code==null)return;
        int pad=P(40),caption=P(70),n=code.GetLength(0),quiet=2;
        int side=Math.Min(Width-pad*2,Height-pad-caption-P(10));int cell=side/(n+quiet*2);int drawn=cell*(n+quiet*2);
        int left=(Width-drawn)/2+cell*quiet,top=pad+(side-drawn)/2+cell*quiet;
        g.SmoothingMode=SmoothingMode.None;
        using(var dark=new SolidBrush(Color.Black))for(int y=0;y<n;y++)for(int x=0;x<n;x++)if(code[y,x])g.FillRectangle(dark,left+x*cell,top+y*cell,cell,cell);
        g.SmoothingMode=SmoothingMode.AntiAlias;
        string address=text.Replace("https://","").Replace("http://","");
        using(var font=Look.Pixels(24*scale))using(var brush=new SolidBrush(Look.Dock))
            g.DrawString(address,font,brush,new RectangleF(pad,pad+side+P(18),Width-pad*2,P(40)),new StringFormat{Alignment=StringAlignment.Center,Trimming=StringTrimming.EllipsisCharacter,FormatFlags=StringFormatFlags.NoWrap});
        var c=CloseRect;using(var b=new SolidBrush(Color.FromArgb(20,0,0,0)))g.FillEllipse(b,c);
        int cross=P(13);using(var pen=new Pen(Look.Dock,3*scale){StartCap=LineCap.Round,EndCap=LineCap.Round}){g.DrawLine(pen,c.Left+cross,c.Top+cross,c.Right-cross,c.Bottom-cross);g.DrawLine(pen,c.Right-cross,c.Top+cross,c.Left+cross,c.Bottom-cross);}
    }
    protected override void OnMouseDown(MouseEventArgs e){if(CloseRect.Contains(e.Location)){app.CloseQr();return;}grab=e.Location;dragging=true;}
    protected override void OnMouseMove(MouseEventArgs e){if(dragging)Location=new Point(Left+e.X-grab.X,Top+e.Y-grab.Y);}
    protected override void OnMouseUp(MouseEventArgs e){dragging=false;}
}
}
