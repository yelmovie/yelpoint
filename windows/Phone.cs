using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace YelPoint {
// Shows an Android phone or tablet plugged in over USB, either its screen or its back camera
// as a document camera. Runs the bundled scrcpy and adb (Apache 2.0, see THIRD-PARTY-NOTICES.txt).
// Their keys, logs and temp files live in YelPoint's data folder.
internal sealed class PhoneLink {
    readonly string tools,home;
    readonly Control owner;
    readonly Timer timer=new Timer{Interval=2000};
    bool polling,adbStarted;
    // A poll that never came back is given up after this long, so detection cannot stop for good.
    DateTime pollStarted;
    int pollTicket;
    // Bumped by every start and stop, so a window queued to reopen does not come back after 끄기.
    int generation;
    DateTime startedAt;
    Process mirror;
    public PhoneDevice Device;
    public bool Camera,Light;
    public int Rotation;
    public event Action Changed;
    // Called when the scrcpy window closes by itself. true means it never really started.
    public event Action<bool> Closed;
    // Raised once a phone recording is finished and its MP4 is complete.
    public event Action<string> Recorded;
    // The MP4 the running scrcpy is recording to, if any.
    public string RecordingPath{get;private set;}
    public bool Recording{get{return RecordingPath!=null&&Running;}}
    public PhoneLink(Control owner,string dataDirectory){
        this.owner=owner;
        tools=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"scrcpy");
        home=Path.Combine(dataDirectory,"android");
        Directory.CreateDirectory(Path.Combine(home,"tmp"));
        timer.Tick+=(s,e)=>Poll();
    }
    public bool Available{get{return File.Exists(Path.Combine(tools,"scrcpy.exe"))&&File.Exists(Path.Combine(tools,"adb.exe"));}}
    public bool Running{get{try{return mirror!=null&&!mirror.HasExited;}catch(InvalidOperationException){return false;}}}
    public bool Watching{get{return timer.Enabled;}}
    public string LogFolder{get{return Path.Combine(home,"tmp");}}
    public void Watch(bool on){
        if(on&&!timer.Enabled&&Available){timer.Start();Poll();}
        else if(!on&&timer.Enabled)timer.Stop();
    }
    ProcessStartInfo Info(string file,string arguments){
        var info=new ProcessStartInfo(Path.Combine(tools,file),arguments){UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=tools};
        string temp=Path.Combine(home,"tmp");
        // adb keeps its key under the user folder and its log in TEMP.
        info.EnvironmentVariables["HOME"]=home;info.EnvironmentVariables["USERPROFILE"]=home;
        info.EnvironmentVariables["ANDROID_USER_HOME"]=Path.Combine(home,".android");
        info.EnvironmentVariables["TMP"]=temp;info.EnvironmentVariables["TEMP"]=temp;
        info.EnvironmentVariables["ADB"]=Path.Combine(tools,"adb.exe");
        info.EnvironmentVariables["SCRCPY_SERVER_PATH"]=Path.Combine(tools,"scrcpy-server");
        return info;
    }
    // The adb server is started separately so no long-lived process holds the output pipe.
    public string Adb(string arguments,int timeout=10000){
        if(!Available)return null;
        try{
            if(!adbStarted){adbStarted=true;using(var server=Process.Start(Info("adb.exe","start-server")))server.WaitForExit(15000);}
            var info=Info("adb.exe",arguments);info.RedirectStandardOutput=true;info.StandardOutputEncoding=System.Text.Encoding.UTF8;
            using(var p=Process.Start(info)){
                // Read beside the wait: a hung adb is killed after the timeout (ten seconds unless asked) instead of blocking ReadToEnd forever.
                var output=p.StandardOutput.ReadToEndAsync();
                if(!p.WaitForExit(timeout)){try{p.Kill();}catch(Exception){}return null;}
                return output.Wait(3000)?output.Result:null;
            }
        }catch(Exception){return null;}
    }
    void Poll(){
        if(polling&&(DateTime.Now-pollStarted).TotalSeconds<40)return;
        polling=true;pollStarted=DateTime.Now;int ticket=++pollTicket;
        Task.Run(()=>Adb("devices -l")).ContinueWith(t=>{
            string output=t.Status==TaskStatus.RanToCompletion?t.Result:null;
            Action done=()=>{
                if(ticket!=pollTicket)return;polling=false;
                // No answer from adb (it hung or failed) keeps what was known, rather than looking unplugged.
                if(output==null)return;var next=PhoneModel.Parse(output);
                if(next.State!=Device.State||next.Serial!=Device.Serial){Device=next;Raise();}
            };
            try{if(owner.IsHandleCreated&&!owner.IsDisposed)owner.BeginInvoke(done);}catch(InvalidOperationException){}
        });
    }
    void Raise(){var h=Changed;if(h!=null)h();}
    // The phone's newest 60 gallery videos. null when the phone could not be read. Call it off the UI thread.
    public List<PhoneVideo> ListVideos(string serial){
        var output=Adb("-s "+PhoneModel.Quote(serial)+" shell content query --uri content://media/external/video/media --projection _display_name:_data:date_added:_size:duration",20000);
        if(output==null)return null;var all=PhoneModel.Videos(output);return all.GetRange(0,Math.Min(60,all.Count));
    }
    // Copies one gallery video to target unchanged, through target.part so a broken copy never looks finished.
    // Skips the copy when a file of the same size is already there. Call it off the UI thread.
    public bool Pull(string serial,PhoneVideo video,string target){
        try{
            var old=new FileInfo(target);if(old.Exists&&video.Bytes>0&&old.Length==video.Bytes)return true;
            string partial=target+".part";if(File.Exists(partial))File.Delete(partial);
            // A minute plus about 4 MB a second, so a big video over a slow cable is not cut off.
            int timeout=(int)Math.Min(int.MaxValue,60000+Math.Max(0,video.Bytes)/4000);
            bool done=Adb("-s "+PhoneModel.Quote(serial)+" pull "+PhoneModel.Quote(video.Path)+" "+PhoneModel.Quote(partial),timeout)!=null;
            var got=new FileInfo(partial);
            if(!done||!got.Exists||got.Length==0){if(got.Exists)File.Delete(partial);return false;}
            if(File.Exists(target))File.Delete(target);File.Move(partial,target);return true;
        }catch(Exception){return false;}
    }
    public bool Start(bool camera,string record=null){
        if(Device.State!=PhoneState.Ready||!Available)return false;
        int ticket=++generation;var old=mirror;
        // A recording is closed gently so scrcpy finishes the MP4; the new window opens once it has gone.
        if(old!=null&&RecordingPath!=null){
            var path=RecordingPath;mirror=null;RecordingPath=null;Camera=camera;Raise();
            Finish(old,path,()=>{if(ticket!=generation||(Device.State==PhoneState.Ready&&Launch(camera,record)))return;var closed=Closed;if(closed!=null)closed(true);Raise();});
            return true;
        }
        mirror=null;
        // The phone keeps the camera until the old scrcpy has really gone, so wait for it (briefly) before the next one.
        if(old!=null)try{if(!old.HasExited){old.Kill();old.WaitForExit(3000);}}catch(Exception){}
        return Launch(camera,record);
    }
    bool Launch(bool camera,string record){
        Camera=camera;
        string title=camera?Look.Tr("YelPoint · 실물화상기","YelPoint · Document camera"):"YelPoint · "+Device.Name;
        var p=new Process{StartInfo=Info("scrcpy.exe",PhoneModel.Arguments(Device.Serial,camera,Rotation,Light,title,record)),EnableRaisingEvents=true};
        p.Exited+=(s,e)=>{
            if(!owner.IsHandleCreated)return;
            owner.BeginInvoke(new Action(()=>{
                if(mirror!=p)return;mirror=null;
                // The window was closed while recording: scrcpy has already finished the file.
                if(RecordingPath!=null){var path=RecordingPath;RecordingPath=null;RaiseRecorded(path);}
                var closed=Closed;if(closed!=null)closed((DateTime.Now-startedAt).TotalSeconds<5);Raise();
            }));
        };
        try{p.Start();}catch(Exception){p.Dispose();return false;}
        mirror=p;RecordingPath=record;startedAt=DateTime.Now;Raise();return true;
    }
    public void Restart(){if(Running)Start(Camera);}
    public void Stop(bool notify=true){
        generation++;var p=mirror;mirror=null;
        if(p!=null&&RecordingPath!=null){var path=RecordingPath;RecordingPath=null;Finish(p,path,null);}
        else try{if(p!=null&&!p.HasExited)p.Kill();}catch(Exception){}
        if(notify)Raise();
    }
    // Ends the recording and keeps showing the phone. Closing the window lets scrcpy write the end
    // of the MP4; the window reopens only after it has exited (the camera cannot be opened twice).
    public void StopRecording(){
        var p=mirror;var path=RecordingPath;if(p==null||path==null)return;
        bool camera=Camera;mirror=null;RecordingPath=null;int ticket=++generation;Raise();
        Finish(p,path,()=>{if(ticket==generation)Start(camera);});
    }
    void Finish(Process p,string path,Action next){
        Task.Run(()=>{
            try{if(!p.HasExited){p.CloseMainWindow();if(!p.WaitForExit(6000))p.Kill();}}catch(Exception){}
        }).ContinueWith(t=>{
            if(!owner.IsHandleCreated)return;
            owner.BeginInvoke(new Action(()=>{RaiseRecorded(path);if(next!=null)next();}));
        });
    }
    void RaiseRecorded(string path){var h=Recorded;if(h!=null)h(path);}
    // The scrcpy window's client area in screen pixels.
    public Rectangle? WindowArea(){
        if(!Running)return null;
        mirror.Refresh();var handle=mirror.MainWindowHandle;if(handle==IntPtr.Zero)return null;
        Native.RECT client;if(!PhoneNative.GetClientRect(handle,out client))return null;
        var origin=new Native.POINT(0,0);if(!PhoneNative.ClientToScreen(handle,ref origin))return null;
        return new Rectangle(origin.X,origin.Y,client.Right-client.Left,client.Bottom-client.Top);
    }
    public void Shutdown(){
        // Give a recording a moment to be written before the app quits.
        var recordingTask=Recording?mirror:null;
        if(recordingTask!=null){mirror=null;RecordingPath=null;try{recordingTask.CloseMainWindow();if(!recordingTask.WaitForExit(4000))recordingTask.Kill();}catch(Exception){}}
        Stop(false);Watch(false);timer.Dispose();
        if(adbStarted)try{using(var p=Process.Start(Info("adb.exe","kill-server")))p.WaitForExit(5000);}catch(Exception){}
    }
}

internal static class PhoneNative {
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window,out Native.RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window,ref Native.POINT point);
}

internal sealed class PhoneForm:FloatingForm {
    readonly Controller app;
    public readonly Label Status;
    readonly ToolButton auto;
    public readonly ToolButton ScreenButton,CameraButton,RotateButton,LightButton,FreezeButton,RecordButton,CloseButton,ImportButton;
    public PhoneForm(Controller app){
        this.app=app;Size=new Size(S(790),S(86));
        Status=new Label{Bounds=new Rectangle(S(14),S(9),S(566),S(22)),ForeColor=Look.Paper,BackColor=Look.Dock,Font=Look.Pixels(13*ScaleFactor),AutoEllipsis=true};Controls.Add(Status);
        // A lime pill when on, so it reads at a glance on the dark panel.
        auto=new ToolButton(Look.Tr("꽂으면 바로 띄우기","Open when plugged in"),"circle"){Bounds=new Rectangle(S(590),S(5),S(190),S(30)),AccessibleName=Look.Tr("다음부터 케이블만 꽂으면 폰 화면이 바로 떠요","Next time, the phone screen opens as soon as you plug in")};
        auto.Click+=(s,e)=>{app.Preferences.PhoneAuto=app.Preferences.PhoneAuto!=true;app.Save();app.RefreshTools();Sync();};Controls.Add(auto);
        ScreenButton=Add(Look.Tr("화면","Screen"),"phone",8,82,Look.Tr("폰 화면 띄우기","Show the phone screen"),()=>app.ShowPhone(false));
        CameraButton=Add(Look.Tr("카메라","Camera"),"camera",92,92,Look.Tr("폰 카메라를 실물화상기로","Use the phone camera as a document camera"),()=>app.ShowPhone(true));
        RotateButton=Add(Look.Tr("회전","Rotate"),"rotate",186,82,Look.Tr("90도 돌리기","Rotate 90°"),()=>app.RotatePhone());
        LightButton=Add(Look.Tr("조명","Light"),"light",270,82,Look.Tr("카메라 플래시 켜고 끄기","Turn the camera light on or off"),()=>app.TogglePhoneLight());
        FreezeButton=Add(Look.Tr("멈춤","Freeze"),"pause",354,82,Look.Tr("지금 장면을 멈춰 두고 그 위에 필기","Freeze this view and write on it"),()=>app.FreezePhone());
        RecordButton=Add(Look.Tr("녹화","Record"),"record",438,82,Look.Tr("폰 화면만 MP4로 녹화","Record just the phone to an MP4"),()=>app.TogglePhoneRecording());
        CloseButton=Add(Look.Tr("끄기","Close"),"off",522,82,Look.Tr("폰 창 닫기","Close the phone window"),()=>app.ClosePhone());
        ImportButton=Add(Look.Tr("영상 가져오기","Get Videos"),"save",606,128,Look.Tr("폰 갤러리 영상을 원본 그대로 가져와서 자막 넣기","Copy a gallery video from the phone and add subtitles"),()=>app.ShowPhoneVideos());
        Add("","help",736,46,Look.Tr("처음 연결하는 방법","How to connect the first time"),()=>app.PhoneHelp());
    }
    ToolButton Add(string title,string symbol,int x,int width,string name,Action action){var b=new ToolButton(title,symbol){Bounds=new Rectangle(S(x),S(36),S(width),S(40)),AccessibleName=name};b.Click+=(s,e)=>{if(b.Enabled)action();};Controls.Add(b);return b;}
    public void Sync(){
        var link=app.Phone;bool ready=link.Device.State==PhoneState.Ready,running=link.Running;string before=Status.Text;
        if(!link.Available)Status.Text=Look.Tr("폰 연결 도구를 찾지 못했어요. 다시 설치해 주세요.","The phone tools are missing. Reinstall the app.");
        else if(link.Device.State==PhoneState.None)Status.Text=Look.Tr("안드로이드 폰·태블릿을 USB 케이블로 꽂아 주세요. 처음이면 ?를 눌러 주세요.","Plug in an Android phone or tablet. First time? Press ?.");
        else if(link.Device.State==PhoneState.Unauthorized)Status.Text=Look.Tr("폰에 뜬 ‘USB 디버깅 허용’에서 ‘허용’을 눌러 주세요.","Tap Allow on the phone’s USB debugging prompt.");
        else if(link.Device.State==PhoneState.Offline)Status.Text=Look.Tr("연결을 확인하는 중이에요. 안 되면 케이블을 뺐다 꽂아 보세요.","Checking the connection. If it hangs, replug the cable.");
        else if(link.Recording)Status.Text=Look.Tr("● 녹화 중 · 정지하면 data\\captures 폴더에 저장돼요","● Recording · Stop saves it to data\\captures");
        else if(running)Status.Text=link.Camera?Look.Tr("카메라를 실물화상기로 쓰는 중이에요. 멈춤을 누르면 그 위에 필기할 수 있어요.","Document camera on. Freeze to write on it."):Look.Tr(link.Device.Name+" 화면을 보여 주는 중이에요.","Showing "+link.Device.Name+".");
        else Status.Text=Look.Tr(link.Device.Name+" 연결됨 · 화면이나 카메라를 눌러 주세요.",link.Device.Name+" connected · choose Screen or Camera.");
        ScreenButton.Enabled=CameraButton.Enabled=ImportButton.Enabled=ready;
        ScreenButton.Selected=running&&!link.Camera;CameraButton.Selected=running&&link.Camera;
        RotateButton.Enabled=FreezeButton.Enabled=CloseButton.Enabled=running;
        LightButton.Enabled=running&&link.Camera;LightButton.Selected=running&&link.Camera&&link.Light;
        bool autoOn=app.Preferences.PhoneAuto==true;auto.Selected=autoOn;auto.Symbol=autoOn?"checked":"circle";
        RecordButton.Enabled=running;RecordButton.Selected=link.Recording;RecordButton.Text=link.Recording?Look.Tr("정지","Stop"):Look.Tr("녹화","Record");RecordButton.Symbol=link.Recording?"stop":"record";
        foreach(Control c in Controls)c.Invalidate();
        // Standing, the status line wraps to fit its text, so a new line of text lays the column out again.
        if(Stacked&&Status.Text!=before)app.PositionChildren();
    }
}

// Lists the phone's gallery videos in big rows; one press copies the chosen one and opens subtitles.
internal sealed class PhoneVideoForm:Form {
    readonly Controller app;
    readonly ListBox list;
    readonly Label status;
    readonly Button get;
    List<PhoneVideo> videos=new List<PhoneVideo>();
    string serial;
    bool busy;
    int ticket;
    // scale is the DPI factor of the display it opens on.
    public PhoneVideoForm(Controller app,float scale){
        this.app=app;Func<float,int> px=v=>Look.Px(v,scale);
        Text=Look.Tr("폰 영상 가져오기","Get Videos from the Phone");Icon=Look.Icon();AutoScaleMode=AutoScaleMode.None;FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;MinimizeBox=false;
        // In front of the always-on-top phone panel it was opened from.
        StartPosition=FormStartPosition.CenterScreen;TopMost=true;Font=Look.Pixels(13*scale);ClientSize=new Size(px(600),px(470));
        Controls.Add(new Label{Text=Look.Tr("자막을 넣을 영상을 고르세요","Choose a video to add subtitles to"),Font=Look.Pixels(18*scale,FontStyle.Bold),Bounds=new Rectangle(px(20),px(16),px(560),px(30))});
        status=new Label{ForeColor=Color.DimGray,AutoEllipsis=true,Bounds=new Rectangle(px(20),px(50),px(560),px(22))};Controls.Add(status);
        list=new ListBox{DrawMode=DrawMode.OwnerDrawFixed,ItemHeight=Math.Min(255,px(40)),Font=Look.Pixels(15*scale),IntegralHeight=false,Bounds=new Rectangle(px(20),px(80),px(560),px(318)),AccessibleName=Look.Tr("폰 영상 목록","Videos on the phone")};
        list.DrawItem+=(s,e)=>{
            if(e.Index<0)return;bool chosen=(e.State&DrawItemState.Selected)!=0;
            using(var b=new SolidBrush(chosen?SystemColors.Highlight:e.Index%2==1?Color.FromArgb(244,245,242):SystemColors.Window))e.Graphics.FillRectangle(b,e.Bounds);
            TextRenderer.DrawText(e.Graphics,Convert.ToString(list.Items[e.Index]),list.Font,new Rectangle(e.Bounds.X+px(10),e.Bounds.Y,e.Bounds.Width-px(12),e.Bounds.Height),chosen?SystemColors.HighlightText:SystemColors.WindowText,TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
        };
        list.DoubleClick+=(s,e)=>Get();Controls.Add(list);
        get=new Button{Text=Look.Tr("가져와서 자막 넣기","Get it and add subtitles"),Font=Look.Pixels(15*scale,FontStyle.Bold),Bounds=new Rectangle(px(380),px(414),px(200),px(38)),Enabled=false};get.Click+=(s,e)=>Get();Controls.Add(get);AcceptButton=get;
        var close=new Button{Text=Look.Tr("닫기","Close"),Bounds=new Rectangle(px(266),px(414),px(102),px(38))};close.Click+=(s,e)=>Close();Controls.Add(close);CancelButton=close;
    }
    void Post(Action action){try{if(IsHandleCreated&&!IsDisposed)BeginInvoke(action);}catch(InvalidOperationException){}}
    // Shows the window and reads the list again, off the UI thread.
    public void Open(string serial){
        if(!Visible)Show();Activate();if(busy)return;
        this.serial=serial;Present(null,true);int mine=++ticket;var link=app.Phone;
        System.Threading.Tasks.Task.Run(()=>link.ListVideos(serial)).ContinueWith(t=>{var found=t.Status==System.Threading.Tasks.TaskStatus.RanToCompletion?t.Result:null;Post(()=>{if(mine==ticket&&!busy)Present(found,false);});});
    }
    // found is null while loading or when the phone could not be read.
    void Present(List<PhoneVideo> found,bool loading){
        videos=found??new List<PhoneVideo>();list.BeginUpdate();list.Items.Clear();foreach(var v in videos)list.Items.Add(PhoneModel.VideoLabel(v));list.EndUpdate();
        if(videos.Count>0)list.SelectedIndex=0;get.Enabled=videos.Count>0;
        status.Text=loading?Look.Tr("폰에서 영상 목록을 읽는 중이에요…","Reading the phone's videos…"):found==null?Look.Tr("폰을 읽지 못했어요. 폰 잠금을 풀고 케이블을 다시 꽂아 주세요.","Could not read the phone. Unlock it and plug it in again."):videos.Count==0?Look.Tr("폰에 영상이 없어요.","There are no videos on the phone."):Look.Tr("맨 위가 가장 최근 영상이에요. 고른 뒤 ‘가져와서 자막 넣기’를 눌러 주세요.","The newest is at the top. Choose one, then press Get it.");
    }
    void Get(){
        if(busy||list.SelectedIndex<0||list.SelectedIndex>=videos.Count)return;
        var video=videos[list.SelectedIndex];string failed=Look.Tr("가져오지 못했어요. 폰 잠금을 풀고 케이블을 확인한 뒤 다시 눌러 주세요.","Could not copy it. Unlock the phone, check the cable and try again."),target;
        try{Directory.CreateDirectory(app.CapturesPath);target=Path.Combine(app.CapturesPath,PhoneModel.VideoFileName(video.Name));}catch(Exception){status.Text=failed;return;}
        busy=true;get.Enabled=false;list.Enabled=false;UseWaitCursor=true;status.Text=Look.Tr("가져오는 중이에요… 영상이 크면 조금 걸려요.","Copying… big videos take a little while.");
        string from=serial;var link=app.Phone;
        System.Threading.Tasks.Task.Run(()=>link.Pull(from,video,target)).ContinueWith(t=>{
            bool ok=t.Status==System.Threading.Tasks.TaskStatus.RanToCompletion&&t.Result;
            Post(()=>{busy=false;UseWaitCursor=false;list.Enabled=true;get.Enabled=videos.Count>0;if(!ok){status.Text=failed;return;}Close();app.PhoneVideoImported(target);});
        });
    }
}
}
