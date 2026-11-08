using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Serialization.Json;
using System.Windows.Forms;

namespace YelPoint {
// Subtitles for one recording: watch it, type lines at the right moments, save an .srt beside the video.
// Players such as VLC, the Windows media apps and YouTube pick up a same-name .srt.
internal sealed class SubtitleForm:Form {
    readonly string video,sidecar,page;
    readonly List<Cue> cues=new List<Cue>();
    readonly WebBrowser web=new WebBrowser{Dock=DockStyle.Top,ScriptErrorsSuppressed=true,IsWebBrowserContextMenuEnabled=false,AllowWebBrowserDrop=false};
    readonly DataGridView grid=new DataGridView{Dock=DockStyle.Fill,AllowUserToAddRows=false,RowHeadersVisible=false,SelectionMode=DataGridViewSelectionMode.FullRowSelect,AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill};
    readonly Label status=new Label{Dock=DockStyle.Top,ForeColor=Color.DimGray};
    // Type here while the video plays: the first key pauses it and Enter drops the line at that moment.
    readonly TextBox entry=new TextBox{BorderStyle=BorderStyle.FixedSingle};
    readonly ToolButton play;
    readonly Timer clock=new Timer{Interval=200};
    bool filling,quiet;
    // Where the line being typed starts, and the line loaded into the box to fix.
    double? typingFrom;
    Cue editing;
    string shown;
    // scale is the DPI factor of the display it opens on; the window and its text are laid out for it.
    public SubtitleForm(string videoPath,string temp,float scale){
        video=videoPath;sidecar=Path.ChangeExtension(videoPath,".subtitles.json");Func<float,int> px=v=>Look.Px(v,scale);
        web.Height=px(390);status.Height=px(44);status.Padding=new Padding(px(8),px(4),px(8),0);
        Text=Look.Tr("자막 넣기 · ","Subtitles · ")+Path.GetFileName(videoPath);Size=new Size(px(980),px(720));MinimumSize=new Size(px(760),px(560));StartPosition=FormStartPosition.CenterScreen;Font=Look.Pixels(13*scale);
        try{using(var f=File.OpenRead(sidecar))cues.AddRange((List<Cue>)new DataContractJsonSerializer(typeof(List<Cue>)).ReadObject(f));}catch(Exception){}
        cues.RemoveAll(Subtitles.Placeholder);
        // ▶/⏸, 3초 뒤로 and the typing box, right under the video. These buttons never take the keyboard from the box.
        var row=new Panel{Dock=DockStyle.Top,Height=px(56),BackColor=Look.Dock};
        play=new ToolButton(Look.Tr("재생","Play"),"play"){Bounds=new Rectangle(px(8),px(8),px(100),px(40)),AccessibleName=Look.Tr("재생 · 멈춤","Play or pause")};play.Click+=(s,e)=>{Script("toggle");SyncPlay(true);entry.Focus();};row.Controls.Add(play);
        var back=new ToolButton(Look.Tr("3초 뒤로","Back 3 s"),"undo"){Bounds=new Rectangle(px(112),px(8),px(116),px(40)),AccessibleName=Look.Tr("3초 뒤로","Back 3 seconds")};back.Click+=(s,e)=>{Script("back",3.0);entry.Focus();};row.Controls.Add(back);
        entry.Font=Look.Pixels(20*scale);entry.AccessibleName=Look.Tr("자막 입력","Subtitle");entry.Location=new Point(px(236),px(10));
        entry.HandleCreated+=(s,e)=>SubtitleNative.SendMessage(entry.Handle,0x1501,new IntPtr(1),Look.Tr("영상을 보다가 여기에 자막을 쓰고 Enter · 쓰기 시작하면 영상이 잠깐 멈춰요","Type the subtitle here while it plays, then Enter · the video pauses as you type"));
        entry.TextChanged+=(s,e)=>Typed();
        row.Controls.Add(entry);row.Resize+=(s,e)=>{entry.Width=Math.Max(px(120),row.ClientSize.Width-entry.Left-px(10));entry.Top=(row.ClientSize.Height-entry.Height)/2;};
        var bar=new FlowLayoutPanel{Dock=DockStyle.Top,Height=px(48),Padding=new Padding(px(6))};
        Func<string,EventHandler,Button> button=(t,h)=>{var b=new Button{Text=t,AutoSize=true,Height=px(32)};b.Click+=h;bar.Controls.Add(b);return b;};
        button(Look.Tr("＋ 지금 위치에 자막","+ Add here"),(s,e)=>AddHere());
        button(Look.Tr("－ 지우기","− Delete"),(s,e)=>RemoveSelected());
        // The main save. Windows cannot write the subtitles into the video itself.
        button(Look.Tr("SRT 저장","Save SRT"),(s,e)=>SaveSrt()).Font=Look.Pixels(13*scale,FontStyle.Bold);
        button(Look.Tr("영상 폴더 열기","Open folder"),(s,e)=>{try{Process.Start(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"explorer.exe"),"/select,\""+video+"\"");}catch(Exception){}});
        status.Text=Look.Tr("영상을 틀고, 말이 나오면 위 칸에 자막을 쓰고 Enter. 그 장면에 들어가고 영상이 다시 재생돼요. 아래 표에서 줄을 누르면 그 장면으로 가서 고칠 수 있어요.","Play the video. When someone speaks, type the subtitle in the box above and press Enter. It goes in at that moment and the video plays on. Click a line in the table below to jump there and fix it.");
        grid.Columns.Add("start",Look.Tr("시작","Start"));grid.Columns.Add("end",Look.Tr("끝","End"));grid.Columns.Add("text",Look.Tr("자막","Subtitle"));
        grid.Columns[0].FillWeight=12;grid.Columns[1].FillWeight=12;grid.Columns[2].FillWeight=76;
        grid.CellEndEdit+=(s,e)=>Edited(e.RowIndex,e.ColumnIndex);
        grid.CellClick+=(s,e)=>Pick(e.RowIndex,e.ColumnIndex);
        Controls.Add(grid);Controls.Add(status);Controls.Add(bar);Controls.Add(row);Controls.Add(web);
        // The video grows with the window; the rows under it keep their height.
        Resize+=(s,e)=>web.Height=Math.Max(px(200),ClientSize.Height-px(56+48+44+150));
        // A small page with an HTML5 player; IE=edge makes the built-in browser use its modern engine.
        // The current line is drawn over the picture like a burned-in subtitle: white bold text in a dark rounded box,
        // centred at the bottom and wrapped inside the video.
        page=Path.Combine(temp,"subtitle-player.html");
        try{File.WriteAllText(page,"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\"><style>html,body{margin:0;height:100%;background:#000;overflow:hidden}video{position:absolute;left:0;top:0;width:100%;height:100%}#cap{position:absolute;left:0;bottom:56px;width:100%;text-align:center;pointer-events:none}#cap span{display:inline-block;max-width:100%;box-sizing:border-box;background:rgba(0,0,0,.72);color:#fff;font-weight:bold;font-family:'Malgun Gothic',sans-serif;line-height:1.35;padding:.18em .6em;border-radius:.35em;white-space:pre-wrap;word-wrap:break-word;word-break:keep-all}</style></head><body><video id=\"v\" controls src=\""+new Uri(video).AbsoluteUri+"\"></video><div id=\"cap\"></div><script>var v=document.getElementById('v'),c=document.getElementById('cap');function now(){return v.currentTime||0}function paused(){return v.paused}function seek(t){v.pause();v.currentTime=t}function pause(){v.pause()}function toggle(){if(v.paused)v.play();else v.pause()}function back(s){v.currentTime=Math.max(0,(v.currentTime||0)-s)}function playFrom(t){v.currentTime=t;v.play()}function layout(){var W=document.documentElement.clientWidth,H=document.documentElement.clientHeight,w=W,h=H,x=0,y=0;if(v.videoWidth>0&&v.videoHeight>0){var k=Math.min(W/v.videoWidth,H/v.videoHeight);w=v.videoWidth*k;h=v.videoHeight*k;x=(W-w)/2;y=(H-h)/2}c.style.fontSize=Math.max(14,Math.round(h*.055))+'px';c.style.left=Math.round(x+w*.05)+'px';c.style.width=Math.round(w*.9)+'px';c.style.bottom=Math.round(Math.max(H-y-h+h*.06,48))+'px'}function caption(t){c.innerHTML=t?'<span>'+t.replace(/&/g,'&amp;').replace(/</g,'&lt;')+'</span>':'';layout()}window.onresize=layout;v.addEventListener('loadedmetadata',layout);</script></body></html>",new System.Text.UTF8Encoding(false));}
        catch(Exception){status.Text=Look.Tr("재생 화면을 저장하지 못했어요. 드라이브 연결과 저장 공간을 확인해 주세요.","Could not save the player page. Check the drive connection and free space.");}
        web.DocumentCompleted+=(s,e)=>shown=null;
        web.Navigate(page);
        clock.Tick+=(s,e)=>{ShowCaption();SyncPlay(false);};
        Shown+=(s,e)=>entry.Focus();
        clock.Start();Fill();
    }
    object Script(string name,params object[] args){try{return web.Document==null?null:web.Document.InvokeScript(name,args);}catch(Exception){return null;}}
    double Now(){var v=Script("now");try{return v==null?0:Convert.ToDouble(v,System.Globalization.CultureInfo.InvariantCulture);}catch(Exception){return 0;}}
    bool playing;
    // The ▶/⏸ button follows the player, which can also be paused from its own controls.
    void SyncPlay(bool force){var v=Script("paused");bool now=v is bool&&!(bool)v;if(now==playing&&!force)return;playing=now;play.Symbol=now?"pause":"play";play.Text=now?Look.Tr("멈춤","Pause"):Look.Tr("재생","Play");play.Invalidate();}
    // While typing or fixing a line the box is shown on the video; otherwise the line at the current time.
    void ShowCaption(){
        string text="";
        if(typingFrom.HasValue||editing!=null)text=entry.Text.Trim();
        else{var t=Now();foreach(var c in cues)if(t>=c.Start&&t<c.End){text=c.Text;break;}}
        if(text==shown)return;shown=text;Script("caption",text);
    }
    void SetEntry(string text){quiet=true;entry.Text=text;entry.SelectionStart=entry.Text.Length;quiet=false;}
    // People type after they hear it, so the line starts a moment earlier, never before the previous line ends.
    void Typed(){
        if(quiet)return;
        if(!typingFrom.HasValue&&editing==null&&entry.Text.Length>0){typingFrom=Subtitles.TypingStart(cues,Now());Script("pause");SyncPlay(true);}
        ShowCaption();
    }
    // Enter and Esc in the box. Enter waits a moment so a Korean syllable still being composed is in the text.
    protected override bool ProcessCmdKey(ref Message msg,Keys keyData){
        if(entry.Focused&&keyData==Keys.Enter){BeginInvoke(new Action(Commit));return true;}
        if(entry.Focused&&keyData==Keys.Escape){Cancel();return true;}
        return base.ProcessCmdKey(ref msg,keyData);
    }
    void Commit(){
        if(IsDisposed)return;string text=entry.Text.Trim();
        if(editing!=null){
            int at=cues.IndexOf(editing);if(at>=0){if(text.Length==0)cues.RemoveAt(at);else cues[at].Text=text;}
            editing=null;SetEntry("");Fill();
            status.Text=text.Length==0?Look.Tr("자막을 지웠어요.","Subtitle deleted."):Look.Tr("자막을 고쳤어요.","Subtitle updated.");ShowCaption();return;
        }
        if(text.Length==0)return;
        double start=typingFrom??Math.Max(0,Now());
        // Long enough to read, and never running into the next line.
        cues.Add(new Cue{Start=start,End=Subtitles.CueEnd(cues,start,text),Text=text});
        typingFrom=null;SetEntry("");Fill();
        status.Text=Look.Tr(Subtitles.Clock(start)+"에 넣었어요. 계속 보면서 다음 자막을 쓰세요.","Added at "+Subtitles.Clock(start)+". Keep watching and type the next one.");
        Script("playFrom",start);SyncPlay(true);entry.Focus();ShowCaption();
    }
    void Cancel(){typingFrom=null;editing=null;SetEntry("");grid.ClearSelection();ShowCaption();}
    // A line in the table: jump there and load it into the box to fix. Enter saves it, an empty box deletes it, Esc leaves it.
    // The time columns keep the keyboard, so a start or end can still be typed in the table.
    void Pick(int row,int column){
        if(filling||row<0||row>=cues.Count)return;var cue=cues[row];
        Script("seek",cue.Start+.01);SyncPlay(true);typingFrom=null;editing=cue;SetEntry(cue.Text);
        if(column!=0&&column!=1)entry.Focus();
        status.Text=Look.Tr("위 칸에서 고치고 Enter. 지우려면 칸을 비우고 Enter, 그대로 두려면 Esc.","Fix it above and press Enter. Empty it and press Enter to delete, or Esc to leave it.");ShowCaption();
    }
    void Fill(){
        filling=true;cues.Sort((a,b)=>a.Start.CompareTo(b.Start));grid.Rows.Clear();
        foreach(var c in cues)grid.Rows.Add(Subtitles.Clock(c.Start),Subtitles.Clock(c.End),c.Text);
        grid.ClearSelection();filling=false;shown=null;
        try{using(var f=File.Create(sidecar))new DataContractJsonSerializer(typeof(List<Cue>)).WriteObject(f,cues);}catch(Exception){}
    }
    void AddHere(){Script("pause");SyncPlay(true);editing=null;SetEntry("");grid.ClearSelection();typingFrom=Math.Max(0,Now());entry.Focus();status.Text=Look.Tr("이 장면에 넣을 자막을 위 칸에 쓰고 Enter를 눌러 주세요.","Type the subtitle for this moment above and press Enter.");}
    void RemoveSelected(){var rows=new List<int>();foreach(DataGridViewRow r in grid.SelectedRows)rows.Add(r.Index);rows.Sort();for(int i=rows.Count-1;i>=0;i--)if(rows[i]<cues.Count){if(cues[rows[i]]==editing){editing=null;SetEntry("");}cues.RemoveAt(rows[i]);}Fill();}
    void Edited(int row,int column){
        if(filling||row<0||row>=cues.Count)return;var value=Convert.ToString(grid.Rows[row].Cells[column].Value)??"";
        if(column==2)cues[row].Text=value;else{var t=Subtitles.Parse(value);if(t.HasValue){if(column==0)cues[row].Start=t.Value;else cues[row].End=t.Value;}}
        BeginInvoke(new Action(Fill));
    }
    void SaveSrt(){
        grid.EndEdit();var target=Path.ChangeExtension(video,".srt");
        try{File.WriteAllText(target,Subtitles.Srt(cues),new System.Text.UTF8Encoding(false));status.Text=Look.Tr("SRT를 저장했어요 · ","Saved SRT · ")+Path.GetFileName(target);}
        catch(Exception e){status.Text=Look.Tr("SRT를 저장하지 못했어요. 영상이 있는 폴더와 저장 공간을 확인해 주세요. · ","Could not save the SRT. Check the video's folder and free space. · ")+e.Message;}
    }
    protected override void OnFormClosed(FormClosedEventArgs e){clock.Stop();clock.Dispose();Script("pause");try{File.Delete(page);}catch(Exception){}base.OnFormClosed(e);}
}

// 내 영상: every MP4 in data\captures, newest first, with a picture and its length from Windows.
// One press opens the subtitle editor on it.
internal sealed class MyVideosForm:Form {
    readonly Controller app;
    readonly ListBox list;
    readonly Label status,empty;
    readonly Button watch,folder;
    readonly Font small;
    readonly Func<float,int> px;
    List<SavedVideo> videos=new List<SavedVideo>();
    // Pictures and lengths outlive the window, keyed by path, time and size so a changed file is read again. UI thread only.
    sealed class Shot{public Bitmap Image;public double Seconds;}
    static readonly Dictionary<string,Shot> shots=new Dictionary<string,Shot>(StringComparer.OrdinalIgnoreCase);
    volatile int ticket;
    // scale is the DPI factor of the display it opens on.
    public MyVideosForm(Controller app,float scale){
        this.app=app;px=v=>Look.Px(v,scale);
        Text=Look.Tr("내 영상","My Videos");Icon=Look.Icon();AutoScaleMode=AutoScaleMode.None;FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;MinimizeBox=false;
        // In front of the always-on-top capture bar it was opened from.
        StartPosition=FormStartPosition.CenterScreen;TopMost=true;Font=Look.Pixels(13*scale);ClientSize=new Size(px(640),px(520));small=Look.Pixels(13*scale);
        Controls.Add(new Label{Text=Look.Tr("녹화한 영상","Your videos"),Font=Look.Pixels(18*scale,FontStyle.Bold),Bounds=new Rectangle(px(20),px(16),px(600),px(30))});
        status=new Label{ForeColor=Color.DimGray,AutoEllipsis=true,Bounds=new Rectangle(px(20),px(50),px(600),px(22))};Controls.Add(status);
        empty=new Label{Text=Look.Tr("아직 녹화한 영상이 없어요. 캡처 메뉴의 ‘화면 녹화’나 폰 패널의 ‘녹화’·‘영상 가져오기’로 만들 수 있어요.","No videos yet. Make one with Record on the Capture bar, or with Record or Get Videos on the phone panel."),Font=Look.Pixels(15*scale),ForeColor=Color.DimGray,BackColor=SystemColors.Window,TextAlign=ContentAlignment.MiddleCenter,Padding=new Padding(px(24)),Bounds=new Rectangle(px(21),px(81),px(598),px(364)),Visible=false};Controls.Add(empty);
        list=new ListBox{DrawMode=DrawMode.OwnerDrawFixed,ItemHeight=Math.Min(255,px(72)),Font=Look.Pixels(15*scale),IntegralHeight=false,Bounds=new Rectangle(px(20),px(80),px(600),px(366)),AccessibleName=Look.Tr("녹화한 영상 목록","Your videos")};
        list.DrawItem+=(s,e)=>Draw(e);list.DoubleClick+=(s,e)=>Watch();Controls.Add(list);
        watch=new Button{Text=Look.Tr("보기 · 자막 넣기","Watch · Subtitles"),Font=Look.Pixels(15*scale,FontStyle.Bold),Bounds=new Rectangle(px(430),px(464),px(190),px(38)),Enabled=false};watch.Click+=(s,e)=>Watch();Controls.Add(watch);AcceptButton=watch;
        var close=new Button{Text=Look.Tr("닫기","Close"),Bounds=new Rectangle(px(326),px(464),px(96),px(38))};close.Click+=(s,e)=>Close();Controls.Add(close);CancelButton=close;
        var other=new Button{Text=Look.Tr("다른 영상 고르기…","Choose another…"),Bounds=new Rectangle(px(20),px(464),px(150),px(38))};other.Click+=(s,e)=>{if(app.ChooseVideoForSubtitles(this))Close();};Controls.Add(other);
        folder=new Button{Text=Look.Tr("폴더에서 보기","Show in folder"),Bounds=new Rectangle(px(178),px(464),px(130),px(38))};folder.Click+=(s,e)=>ShowInFolder();Controls.Add(folder);
        empty.BringToFront();
    }
    bool Post(Action action){try{if(IsHandleCreated&&!IsDisposed){BeginInvoke(action);return true;}}catch(Exception){}return false;}
    static string Key(SavedVideo v){return v.Path+"|"+v.Written.Ticks+"|"+v.Bytes;}
    // Shows the window and lists the folder again; pictures and lengths follow from a background thread.
    public void Open(){
        if(!Visible)Show();Activate();
        var found=new List<SavedVideo>();
        try{
            var dir=new DirectoryInfo(app.CapturesPath);
            // "*.mp4" also matches longer extensions on Windows, so the ending is checked again.
            if(dir.Exists)foreach(var f in dir.GetFiles("*.mp4"))if(f.Name.EndsWith(".mp4",StringComparison.OrdinalIgnoreCase)&&!f.Name.StartsWith("._"))found.Add(new SavedVideo{Path=f.FullName,Written=f.LastWriteTime,Bytes=f.Length,Subtitles=File.Exists(Path.ChangeExtension(f.FullName,".srt"))});
        }catch(Exception){}
        MyVideos.NewestFirst(found);videos=found;
        list.BeginUpdate();list.Items.Clear();foreach(var v in videos)list.Items.Add(Path.GetFileName(v.Path));list.EndUpdate();
        if(videos.Count>0)list.SelectedIndex=0;watch.Enabled=videos.Count>0;empty.Visible=videos.Count==0;
        status.Text=videos.Count>0?Look.Tr("영상을 고르고 ‘보기 · 자막 넣기’를 누르세요","Pick a video, then press Watch · Subtitles"):"";
        if(videos.Count>0)list.Focus();
        // Pictures of files that are gone are let go.
        var keep=new HashSet<string>(videos.ConvertAll(Key),StringComparer.OrdinalIgnoreCase);
        foreach(var key in new List<string>(shots.Keys))if(!keep.Contains(key)){var old=shots[key];shots.Remove(key);if(old.Image!=null)old.Image.Dispose();}
        var missing=videos.FindAll(v=>!shots.ContainsKey(Key(v)));int mine=++ticket;
        if(missing.Count>0)Fetch(missing,mine);
    }
    // One STA thread asks the Windows shell for each picture and length in turn, newest first.
    // Any failure leaves the plain tile; nothing here can stop the window.
    void Fetch(List<SavedVideo> missing,int mine){
        var worker=new System.Threading.Thread(()=>{
            try{
                foreach(var v in missing){
                    if(mine!=ticket)return;
                    double seconds=ShellVideo.Seconds(v.Path);Bitmap image=ShellVideo.Picture(v.Path,256);string key=Key(v);
                    if(!Post(()=>{if(IsDisposed||shots.ContainsKey(key)){if(image!=null)image.Dispose();return;}shots[key]=new Shot{Image=image,Seconds=seconds};list.Invalidate();})&&image!=null)image.Dispose();
                }
            }catch(Exception){}
        }){IsBackground=true,Name="YelPoint video pictures"};
        try{worker.SetApartmentState(System.Threading.ApartmentState.STA);worker.Start();}catch(Exception){}
    }
    void Draw(DrawItemEventArgs e){
        if(e.Index<0||e.Index>=videos.Count)return;var v=videos[e.Index];var g=e.Graphics;bool chosen=(e.State&DrawItemState.Selected)!=0;
        using(var b=new SolidBrush(chosen?SystemColors.Highlight:e.Index%2==1?Color.FromArgb(244,245,242):SystemColors.Window))g.FillRectangle(b,e.Bounds);
        Shot shot;shots.TryGetValue(Key(v),out shot);
        // A dark tile; the picture fits inside it keeping its shape, or a ▶ stands in for it.
        var tile=new Rectangle(e.Bounds.X+px(10),e.Bounds.Y+(e.Bounds.Height-px(64))/2,px(112),px(64));
        using(var b=new SolidBrush(Color.FromArgb(28,30,29)))g.FillRectangle(b,tile);
        if(shot!=null&&shot.Image!=null){
            var picture=shot.Image.Size;double k=Math.Min((double)tile.Width/Math.Max(1,picture.Width),(double)tile.Height/Math.Max(1,picture.Height));var fit=new Size(Math.Max(1,(int)(picture.Width*k)),Math.Max(1,(int)(picture.Height*k)));
            var state=g.Save();g.InterpolationMode=System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;g.PixelOffsetMode=System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
            try{g.DrawImage(shot.Image,new Rectangle(tile.X+(tile.Width-fit.Width)/2,tile.Y+(tile.Height-fit.Height)/2,fit.Width,fit.Height));}catch(Exception){}
            g.Restore(state);
        }
        else{var state=g.Save();g.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;int side=px(26);ToolButton.DrawSymbol(g,"play",Color.FromArgb(225,228,222),new RectangleF(tile.X+(tile.Width-side)/2f,tile.Y+(tile.Height-side)/2f,side,side));g.Restore(state);}
        int x=tile.Right+px(14),w=Math.Max(1,e.Bounds.Right-x-px(10)),half=e.Bounds.Height/2;var flags=TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix|TextFormatFlags.SingleLine;
        TextRenderer.DrawText(g,MyVideos.Label(v,shot==null?0:shot.Seconds),list.Font,new Rectangle(x,e.Bounds.Y+half-px(26),w,px(26)),chosen?SystemColors.HighlightText:SystemColors.WindowText,flags|TextFormatFlags.Bottom);
        TextRenderer.DrawText(g,MyVideos.Detail(v),small,new Rectangle(x,e.Bounds.Y+half+px(2),w,px(22)),chosen?SystemColors.HighlightText:Color.DimGray,flags|TextFormatFlags.Top);
    }
    SavedVideo? Chosen(){int i=list.SelectedIndex;return i>=0&&i<videos.Count?videos[i]:(SavedVideo?)null;}
    // A video with burned-in subtitles plays in the usual player; any other opens in the subtitle editor.
    void Watch(){
        var v=Chosen();if(v==null)return;string path=v.Value.Path;
        if(!File.Exists(path)){Open();status.Text=Look.Tr("그 영상을 찾지 못했어요. 목록을 다시 읽었어요.","That video is gone. The list has been read again.");return;}
        if(MyVideos.Burned(path)){
            try{Process.Start(path);}catch(Exception){status.Text=Look.Tr("영상을 열 앱을 찾지 못했어요. ‘폴더에서 보기’로 열어 보세요.","No app could open it. Try Show in folder.");return;}
            Close();return;
        }
        Close();app.OpenSubtitles(path);
    }
    void ShowInFolder(){
        var v=Chosen();
        try{if(v!=null&&File.Exists(v.Value.Path))Process.Start(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"explorer.exe"),"/select,\""+v.Value.Path+"\"");else{Directory.CreateDirectory(app.CapturesPath);Process.Start(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"explorer.exe"),"\""+app.CapturesPath+"\"");}}catch(Exception){}
    }
    protected override void OnFormClosed(FormClosedEventArgs e){ticket++;base.OnFormClosed(e);}
    protected override void Dispose(bool disposing){if(disposing)small.Dispose();base.Dispose(disposing);}
}

// The picture and length Windows Explorer shows for a video. Call it off the UI thread, on an STA thread.
internal static class ShellVideo {
    [ComImport,Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItemImageFactory{[PreserveSig]int GetImage(Native.SIZE size,int flags,out IntPtr bitmap);}
    [ComImport,Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore{[PreserveSig]int GetCount(out uint count);[PreserveSig]int GetAt(uint index,out PropertyKey key);[PreserveSig]int GetValue(ref PropertyKey key,out PropVariant value);[PreserveSig]int SetValue(ref PropertyKey key,ref PropVariant value);[PreserveSig]int Commit();}
    [StructLayout(LayoutKind.Sequential)] struct PropertyKey{public Guid Format;public uint Id;}
    // PROPVARIANT on x64: the type, three reserved words, then 16 bytes of value.
    [StructLayout(LayoutKind.Sequential)] struct PropVariant{public ushort Type,Reserved1,Reserved2,Reserved3;public long Value;public IntPtr Extra;}
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern int SHCreateItemFromParsingName(string path,IntPtr bindContext,ref Guid iid,[MarshalAs(UnmanagedType.Interface)]out IShellItemImageFactory item);
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern int SHGetPropertyStoreFromParsingName(string path,IntPtr bindContext,int flags,ref Guid iid,[MarshalAs(UnmanagedType.Interface)]out IPropertyStore store);
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant value);
    // Only a real picture of the video (SIIGBF_THUMBNAILONLY), never the file-type icon. null when there is none.
    public static Bitmap Picture(string path,int size){
        IShellItemImageFactory item=null;IntPtr handle=IntPtr.Zero;
        try{
            var iid=typeof(IShellItemImageFactory).GUID;
            if(SHCreateItemFromParsingName(path,IntPtr.Zero,ref iid,out item)<0||item==null)return null;
            if(item.GetImage(new Native.SIZE(size,size),0x8,out handle)<0||handle==IntPtr.Zero)return null;
            return Image.FromHbitmap(handle);
        }catch(Exception){return null;}
        finally{if(handle!=IntPtr.Zero)Native.DeleteObject(handle);if(item!=null)try{Marshal.ReleaseComObject(item);}catch(Exception){}}
    }
    // System.Media.Duration in seconds, or 0 when Windows does not know it.
    public static double Seconds(string path){
        IPropertyStore store=null;
        try{
            var iid=typeof(IPropertyStore).GUID;
            if(SHGetPropertyStoreFromParsingName(path,IntPtr.Zero,0,ref iid,out store)<0||store==null)return 0;
            var key=new PropertyKey{Format=new Guid("64440490-4c8b-11d1-8b70-080036b11a03"),Id=3};PropVariant value;
            if(store.GetValue(ref key,out value)<0)return 0;
            // VT_UI8, in 100-nanosecond units.
            double seconds=value.Type==21&&value.Value>0?value.Value/1e7:0;PropVariantClear(ref value);return seconds;
        }catch(Exception){return 0;}
        finally{if(store!=null)try{Marshal.ReleaseComObject(store);}catch(Exception){}}
    }
}

internal static class SubtitleNative {
    // EM_SETCUEBANNER: grey hint text in the empty box.
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr window,int message,IntPtr wParam,string lParam);
}
}
