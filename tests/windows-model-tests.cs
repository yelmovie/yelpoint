using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using YelPoint;

internal static class WindowsModelTests {
    static void Require(bool value,string message){if(!value)throw new Exception(message);}
    static void Main(string[] args){
        if(args.Length!=1||!Path.IsPathRooted(args[0]))throw new Exception("Supply an external test directory.");
        string directory=Path.Combine(args[0],"windows-model-settings");
        Directory.CreateDirectory(directory);
        var storage=new Storage(directory);
        var original=new Preferences{Highlight=false,FadingInk=true,KeyboardHUD=true,PenColor=1,PenWidth=7};
        storage.Save(original);var loaded=storage.Load();
        Require(!loaded.Highlight&&loaded.FadingInk&&loaded.KeyboardHUD&&loaded.PenColor==1&&loaded.PenWidth==7,"First save/load lost preferences.");
        original.PenColor=2;original.PenWidth=2;storage.Save(original);loaded=storage.Load();
        Require(loaded.PenColor==2&&loaded.PenWidth==2,"Second atomic save failed.");
        File.WriteAllText(storage.FilePath,"{\"FadingInk\":true}");loaded=storage.Load();
        Require(loaded.Highlight&&loaded.FadingInk&&loaded.PenWidth==4,"Missing fields did not retain safe defaults.");
        File.WriteAllText(storage.FilePath,"{\"PenColor\":99,\"PenWidth\":500}");loaded=storage.Load();
        Require(loaded.PenColor==2&&loaded.PenWidth==4,"Invalid pen settings were not clamped.");
        File.WriteAllText(storage.FilePath,"{broken");loaded=storage.Load();
        Require(loaded.Highlight&&loaded.PenWidth==4,"Corrupt JSON did not recover.");
        File.WriteAllText(storage.FilePath,"null");loaded=storage.Load();
        Require(loaded.Highlight&&loaded.PenWidth==4,"JSON null did not recover.");
        storage.Save(original);string previous=File.ReadAllText(storage.FilePath);
        var fallback=typeof(Storage).GetMethod("ReplaceByRename",BindingFlags.NonPublic|BindingFlags.Instance);
        try{fallback.Invoke(storage,new object[]{Path.Combine(directory,"does-not-exist.json")});throw new Exception("Expected a failed rename.");}
        catch(TargetInvocationException e){Require(e.InnerException is IOException,"Unexpected fallback failure.");}
        Require(File.ReadAllText(storage.FilePath)==previous,"Failed rename did not restore the original preferences.");
        var stroke=new Stroke{Created=10,Fades=true,Color=System.Drawing.Color.Orange,Width=4};
        Require(stroke.Alpha(10)==1&&stroke.Alpha(13.3)==1&&Math.Abs(stroke.Alpha(13.7)-.5)<.001&&stroke.Alpha(14.1)==0,"Ink fade timing was wrong.");
        stroke.Fades=false;Require(stroke.Alpha(1000)==1,"Persistent ink faded.");
        var countdown=new Countdown();countdown.Set(99);Require(countdown.Minutes==60,"Timer exceeded 60 minutes.");countdown.Set(0);Require(countdown.Minutes==1,"Timer went below 1 minute.");
        countdown.Set(60);countdown.StartOrPause(100);Require(countdown.Badge(100)=="60:00"&&countdown.Badge(100.5)=="60:00"&&countdown.Badge(101)=="59:59","Timer label is wrong.");
        countdown.Set(5);Require(countdown.Minutes==60,"Running timer changed length.");countdown.StartOrPause(160);Require(countdown.Badge(900)=="59:00"&&!countdown.Update(9000),"Paused timer kept counting.");
        countdown.StartOrPause(1000);Require(!countdown.Update(4539)&&countdown.Update(4540),"Timer did not finish.");Require(countdown.Badge(4540.2)=="시간 끝!"&&countdown.Pop(4540.2)==0&&countdown.Alert(4540.2),"Time's up did not hold before the pop.");Require(!countdown.Update(4544.9)&&countdown.Active&&countdown.Badge(4544.9)=="시간 끝!"&&countdown.Pop(4544.9)==0,"Time's up left before 5 seconds.");Require(countdown.Pop(4545.2)>0&&countdown.Pop(4545.2)<1&&countdown.Active,"Pop did not follow the hold.");Require(!countdown.Update(4545.5)&&!countdown.Active&&countdown.Badge(4545.5)==null,"Clock did not leave after the pop.");
        Require(Look.ClockScaleFor(392)==2&&Look.ClockScaleFor(10)==118/196.0&&Look.ClockScaleFor(99999)==6,"Clock size is wrong.");
        Require(Look.Fit(new System.Drawing.Size(2000,500),new System.Drawing.Size(1000,800))==new System.Drawing.Size(1000,250),"Sticker was not fitted.");Require(Look.Fit(new System.Drawing.Size(200,100),new System.Drawing.Size(1000,800))==new System.Drawing.Size(200,100),"Small sticker was enlarged.");
        Require(Look.MediaName("png",new DateTime(2026,11,4,20,45,1))=="YelPoint-20261104-204501.png","Capture file name is wrong.");
        File.WriteAllText(storage.FilePath,"{\"PenColor\":1,\"PenWidth\":7}");loaded=storage.Load();Require(loaded.HaloRadius==16&&loaded.InkRGB==-1&&loaded.PenColor==1,"Older settings lost defaults.");
        File.WriteAllText(storage.FilePath,"{\"HaloRadius\":500,\"InkRGB\":99999999}");loaded=storage.Load();Require(loaded.HaloRadius==48&&loaded.InkRGB==-1,"Pointer or ink settings were not clamped.");
        var pointer=new Preferences();pointer.ResizePointer(100);Require(pointer.HaloRadius==48,"Pointer exceeded its maximum.");pointer.ResizePointer(-100);Require(pointer.HaloRadius==6,"Pointer went below its minimum.");
        Require(Look.Hsv(0,1,1)==0xFF0000&&Look.Hsv(1.0/3,1,1)==0x00FF00&&Look.Hsv(2.0/3,1,.5)==0x000080&&Look.Hsv(.4,0,1)==0xFFFFFF,"HSV conversion is wrong.");
        double hue,saturation;Look.WheelPick(0,-200,100,out hue,out saturation);Require(hue==.75&&saturation==1,"Wheel pick is wrong.");
        var box=new System.Drawing.RectangleF(100,100,200,100);Require(Spot.HandleAt(new System.Drawing.PointF(301,201),SpotShape.Rectangle,box)==4&&Spot.HandleAt(new System.Drawing.PointF(200,100),SpotShape.Rectangle,box)==1&&Spot.HandleAt(new System.Drawing.PointF(200,150),SpotShape.Rectangle,box)==-1,"Rectangle outline hit test is wrong.");Require(Spot.HandleAt(new System.Drawing.PointF(300,150),SpotShape.Ellipse,box)==3&&Spot.HandleAt(new System.Drawing.PointF(200,100),SpotShape.Ellipse,box)==1&&Spot.HandleAt(new System.Drawing.PointF(200,150),SpotShape.Ellipse,box)==-1,"Ellipse outline hit test is wrong.");
        Require(Spot.Resized(box,3,new System.Drawing.PointF(500,150),false).Width==400&&Spot.Resized(box,3,new System.Drawing.PointF(0,0),false).Width==24,"Spot resize is wrong.");
        var corner=Spot.Resized(new System.Drawing.RectangleF(100,100,100,100),4,new System.Drawing.PointF(400,220),true);Require(corner.Width==300&&corner.Height==300&&corner.Left==100,"Circle corner resize is wrong.");
        Require(Spot.FromDrag(new System.Drawing.PointF(50,50),new System.Drawing.PointF(10,80),true)==new System.Drawing.RectangleF(10,50,40,40),"Circle drag is wrong.");
        Require(Spot.Contains(SpotShape.Ellipse,box,new System.Drawing.PointF(200,150))&&!Spot.Contains(SpotShape.Ellipse,box,new System.Drawing.PointF(105,105))&&Spot.Contains(SpotShape.Rectangle,box,new System.Drawing.PointF(105,105)),"Spot hit test is wrong.");
        var recording=Look.RecordSize(new System.Drawing.Size(5121,2881));Require(recording.Width==3840&&recording.Height%2==0,"Recording size is wrong.");Require(Look.RecordSize(new System.Drawing.Size(1367,769))==new System.Drawing.Size(1366,768),"Odd recording size was not trimmed.");
        var dimming=new Preferences();dimming.ResizeDimming(-1);Require(dimming.SpotlightRadius==97,"Dimming circle step is wrong.");dimming.ResizeDimming(-100);Require(dimming.SpotlightRadius==30,"Dimming circle went below its minimum.");dimming.ResizeDimming(1000);Require(dimming.SpotlightRadius==400,"Dimming circle exceeded its maximum.");
        var grown=Spot.Scaled(box,2);Require(Math.Abs(grown.Width-220)<.01&&Math.Abs(grown.Height-110)<.01&&Math.Abs(grown.Left+grown.Width/2-200)<.01,"Spot scaling is wrong.");
        Require(Look.PenWidthAt(-1)==1&&Look.PenWidthAt(2)==30&&Look.PenWidthAt(.5)==16,"Pen width slider is wrong.");var thick=new Preferences{PenWidth=23};thick.Validate();Require(thick.PenWidth==23,"Slider pen width was rejected.");
        var work=new System.Drawing.Rectangle(0,0,1920,1040);Require(Look.Clamp(new System.Drawing.Rectangle(-500,-500,676,62),work)==new System.Drawing.Point(0,0)&&Look.Clamp(new System.Drawing.Rectangle(5000,5000,676,62),work)==new System.Drawing.Point(1244,978),"Toolbar clamp is wrong.");
        Require(Look.ChildOrigin(new System.Drawing.Rectangle(300,0,676,62),new System.Drawing.Size(388,48),work,4).Y==66&&Look.ChildOrigin(new System.Drawing.Rectangle(300,900,676,62),new System.Drawing.Size(388,48),work,4).Y==848,"Panel side is wrong.");
        File.WriteAllText(storage.FilePath,"{\"ToolbarPlaced\":true,\"ToolbarX\":-300,\"ToolbarY\":40,\"ToolbarHidden\":true}");loaded=storage.Load();Require(loaded.ToolbarPlaced&&loaded.ToolbarX==-300&&loaded.ToolbarY==40&&loaded.ToolbarHidden,"Toolbar spot did not load.");
        var flat=new System.Drawing.Rectangle(600,300,676,62);Require(Look.ToolbarEdge(flat,30,work)==-1&&Look.ToolbarEdge(flat,1890,work)==1&&Look.ToolbarEdge(flat,960,work)==0,"Toolbar edge is wrong.");Require(Look.ToolbarEdge(new System.Drawing.Rectangle(1244,159,676,62),1260,work)==1&&Look.ToolbarEdge(new System.Drawing.Rectangle(0,159,676,62),660,work)==-1,"Bar touching the edge was missed.");Require(Look.ToolbarEdge(new System.Drawing.Rectangle(200,300,104,356),250,work)==0,"Standing bar pulled inside stayed up.");var side=Look.SideOrigin(new System.Drawing.Rectangle(8,300,104,356),new System.Drawing.Size(388,48),work,4);Require(side.X==116&&side.Y==454,"Side panel is wrong.");Require(Look.SideOrigin(new System.Drawing.Rectangle(1808,300,104,356),new System.Drawing.Size(388,48),work,4).X==1416,"Right side panel is wrong.");
        Require(!Look.LiesFlat(1,1260,1200)&&Look.LiesFlat(1,1260,1140)&&!Look.LiesFlat(1,1260,1900)&&Look.LiesFlat(-1,30,150),"Flat threshold is wrong.");var size=new System.Drawing.Size(676,62);var flatLeft=Look.FlatOrigin(new System.Drawing.Point(150,500),size,work);var flatRight=Look.FlatOrigin(new System.Drawing.Point(1770,500),size,work);Require(Look.ToolbarEdge(new System.Drawing.Rectangle(flatLeft,size),150,work)==0&&Look.ToolbarEdge(new System.Drawing.Rectangle(flatRight,size),1770,work)==0,"Flat toolbar would snap straight back.");
        Require(Look.Tr("가","a")=="가","Korean is not the default.");Look.English=true;Require(Look.Tr("가","a")=="a","English text missing.");Look.English=false;
        File.WriteAllText(storage.FilePath,"{\"Zoom\":9,\"English\":true}");loaded=storage.Load();Require(loaded.Zoom==5&&loaded.English,"Zoom or language did not load.");File.WriteAllText(storage.FilePath,"{}");Require(storage.Load().Zoom==2,"Zoom default is wrong.");
        Require(PhoneModel.Parse("List of devices attached\r\n").State==PhoneState.None,"Empty adb list is wrong.");
        Require(PhoneModel.Parse("List of devices attached\r\nR5CT1\tunauthorized usb:1-1\r\n").State==PhoneState.Unauthorized,"Unauthorized phone is wrong.");
        var ready=PhoneModel.Parse("List of devices attached\r\nR5CT1 unauthorized usb:1-1\r\nR3CW9 device usb:1-2 product:dm3q model:SM_S918N device:dm3q transport_id:2\r\n");
        Require(ready.State==PhoneState.Ready&&ready.Serial=="R3CW9"&&ready.Name=="SM S918N","Ready phone is wrong.");
        Require(PhoneModel.Parse("* daemon started successfully\nList of devices attached\nX offline\n").State==PhoneState.Offline,"Offline phone is wrong.");
        var camera=PhoneModel.Arguments("R3CW9",true,-90,true,"YelPoint · 실물화상기");
        Require(camera.Contains("--video-source=camera")&&camera.Contains("--camera-torch")&&camera.Contains("--display-orientation=270")&&camera.Contains("\"--window-title=YelPoint · 실물화상기\""),"Camera arguments are wrong.");
        var screen=PhoneModel.Arguments("R3CW9",false,450,true,"t");
        Require(screen.Contains("--display-orientation=90")&&!screen.Contains("torch")&&screen.Contains("--stay-awake"),"Screen arguments are wrong.");
        Require(PhoneModel.Arguments("R3CW9",false,0,false,"t",@"D:\Y P\data\captures\p.mp4").EndsWith("\"--record=D:\\Y P\\data\\captures\\p.mp4\"")&&!screen.Contains("--record"),"Recording argument is wrong.");
        Require(PhoneModel.Quote("a b\\")=="\"a b\\\\\""&&PhoneModel.Quote("x\"y")=="\"x\\\"y\"","Argument quoting is wrong.");
        Require(QrCode.Encode("")==null&&QrCode.Encode(new string('a',214))==null&&QrCode.Encode(new string('a',213)).GetLength(0)==57,"QR length limits are wrong.");
        Require(QrCode.Encode("https://example.com").GetLength(0)==25,"QR version choice is wrong.");
        // The matrices go to the analysis folder, where a macOS QR reader checks they decode (scripts/check-qr.swift).
        if(args.Length>0){var lines=new List<string>();foreach(var sample in new[]{"https://example.com","https://blog.naver.com/PostList.naver?blogId=yelsam_lab&skinType=&skinId=&from=menu&userSelectMenu=true","https://예시.한국/수업?반=3-2&날짜=2026-11-07","https://docs.google.com/forms/d/e/1FAIpQLSf-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/viewform?usp=sf_link&entry.123456789=%ED%95%99%EC%83%9D"}){var m=QrCode.Encode(sample);lines.Add("#"+sample);for(int y=0;y<m.GetLength(0);y++){var row=new System.Text.StringBuilder();for(int x=0;x<m.GetLength(1);x++)row.Append(m[y,x]?'1':'0');lines.Add(row.ToString());}}System.IO.File.WriteAllLines(System.IO.Path.Combine(args[0],"qr-samples.txt"),lines);}
        Require(Subtitles.Srt(new List<Cue>{new Cue{Start=61.5,End=63,Text="가"},new Cue{Start=0.2,End=1.2,Text="첫 줄"}})=="1\n00:00:00,200 --> 00:00:01,200\n첫 줄\n\n2\n00:01:01,500 --> 00:01:03,000\n가\n","SRT text is wrong.");
        Require(Subtitles.Parse("1:02.5")==62.5&&Subtitles.Parse("7")==7&&Subtitles.Parse("x")==null&&Subtitles.Clock(62.5)=="1:02.5","Subtitle times are wrong.");
        Require(Look.DpiScale(96)==1&&Look.DpiScale(144)==1.5f&&Look.DpiScale(192)==2&&Look.DpiScale(0)==1&&Look.DpiScale(5000)==1,"DPI factor is wrong.");
        Require(Look.Px(116,1)==116&&Look.Px(110,1.5f)==165&&Look.Px(240,2)==480&&Look.Px(2,1.25f)==2&&Look.Px(4,1.25f)==5&&Look.Px(196*1.5f,2)==588,"DPI pixel size is wrong.");
        Require(Spot.HandleAt(new System.Drawing.PointF(315,150),SpotShape.Rectangle,box)==-1&&Spot.HandleAt(new System.Drawing.PointF(315,150),SpotShape.Rectangle,box,20)==3,"Spot reach does not grow with DPI.");
        Require(Look.WaitPid(new[]{"YelPoint.exe","--wait-pid","4242"})==4242&&Look.WaitPid(new[]{"YelPoint.exe"})==0&&Look.WaitPid(new[]{"x","--wait-pid"})==0&&Look.WaitPid(new[]{"x","--wait-pid","-3"})==0&&Look.WaitPid(new[]{"x","--wait-pid","abc"})==0&&Look.WaitPid(null)==0,"Wait-pid argument is wrong.");
        var gallery=PhoneModel.Videos("Row: 0 _display_name=a, b.mp4, _data=/storage/emulated/0/DCIM/Camera/a, b.mp4, date_added=1793961854, _size=12299884, duration=5707\r\nRow: 1 _display_name=new.mp4, _data=/storage/emulated/0/Movies/new.mp4, date_added=1793999999, _size=63007066, duration=NULL\r\njunk line\r\n");
        Require(gallery.Count==2&&gallery[0].Name=="new.mp4"&&gallery[1].Path.EndsWith("/a, b.mp4")&&gallery[1].Name=="a, b.mp4"&&gallery[1].Seconds==5.707&&gallery[0].Seconds==0&&gallery[0].Bytes==63007066&&gallery[1].Added==1793961854,"Phone gallery list is wrong.");
        Require(PhoneModel.VideoLabel(gallery[1]).EndsWith(" · 6초 · 12MB")&&PhoneModel.Videos("").Count==0&&PhoneModel.Videos(null).Count==0,"Phone video label is wrong.");
        Require(PhoneModel.VideoLabel(new PhoneVideo{Seconds=65,Bytes=63007066},new DateTime(2026,11,6,19,44,0))=="11월 6일 오후 7:44 · 1분 5초 · 63MB"&&PhoneModel.VideoLabel(new PhoneVideo{Seconds=.2,Bytes=10},new DateTime(2026,1,2,0,5,0))=="1월 2일 오전 12:05 · 0초 · 1MB","Phone video label text is wrong.");
        Look.English=true;Require(PhoneModel.VideoLabel(new PhoneVideo{Seconds=65,Bytes=63007066},new DateTime(2026,11,6,19,44,0))=="Nov 6, 7:44 PM · 1 min 5 s · 63MB","English phone video label is wrong.");Look.English=false;
        Require(PhoneModel.VideoFileName("20261106_194415.mp4")=="YelPoint-phone-video-20261106_194415.mp4"&&PhoneModel.VideoFileName("a:b?.mp4")=="YelPoint-phone-video-a_b_.mp4"&&PhoneModel.VideoFileName(" ")=="YelPoint-phone-video-video.mp4","Phone video file name is wrong.");
        Require(PhoneModel.VideoFileName("..\\../x.exe")=="YelPoint-phone-video-.._.._x.exe.mp4"&&PhoneModel.VideoFileName("C:\\Windows\\a.MKV")=="YelPoint-phone-video-C__Windows_a.MKV"&&PhoneModel.VideoFileName("x\0y\n")=="YelPoint-phone-video-x_y.mp4"&&PhoneModel.VideoFileName("a.lnk. ")=="YelPoint-phone-video-a.lnk.mp4"&&PhoneModel.VideoFileName(null)=="YelPoint-phone-video-video.mp4","Phone video file name can leave the folder or is not a video.");
        var screenArea=new System.Drawing.Rectangle(0,0,1920,1040);var barSize=new System.Drawing.Size(418,44);
        Require(Look.BarOrigin(new System.Drawing.Rectangle(100,100,400,300),barSize,screenArea,6,4)==new System.Drawing.Point(100,406)&&Look.BarOrigin(new System.Drawing.Rectangle(100,900,400,130),barSize,screenArea,6,4)==new System.Drawing.Point(100,850)&&Look.BarOrigin(new System.Drawing.Rectangle(1800,100,100,100),barSize,screenArea,6,4).X==1498&&Look.BarOrigin(screenArea,barSize,screenArea,6,4)==new System.Drawing.Point(4,0),"Sticker bar place is wrong.");
        var timed=new List<Cue>{new Cue{Start=0,End=3,Text="a"},new Cue{Start=5,End=8,Text="b"}};
        Require(Subtitles.TypingStart(timed,6)==8&&Subtitles.TypingStart(timed,10)==9&&Subtitles.TypingStart(timed,.5)==3&&Subtitles.TypingStart(timed,-2)==0,"Typed subtitle start is wrong.");
        Require(Subtitles.CueEnd(timed,-1,"가나다")==0&&Subtitles.CueEnd(new List<Cue>(),0,"가나다")==2&&Subtitles.CueEnd(new List<Cue>(),0,new string('가',40))==7&&Math.Abs(Subtitles.CueEnd(new List<Cue>(),0,new string('가',20))-4.4)<1e-9&&Subtitles.CueEnd(timed,4,"가나다라마")==5&&Math.Abs(Subtitles.CueEnd(timed,4.7,"가")-5.2)<1e-9,"Typed subtitle end is wrong.");
        Require(Subtitles.Placeholder(new Cue{Text="자막을 입력하세요"})&&Subtitles.Placeholder(new Cue{Text="Type the subtitle"})&&!Subtitles.Placeholder(new Cue{Text="안녕"}),"Placeholder subtitle was kept.");
        Require(MyVideos.Kind(@"D:\c\YelPoint-phone-video-20261106_194415.mp4")=="폰에서 가져온 영상"&&MyVideos.Kind("YelPoint-phone-20261108-090000.mp4")=="폰 화면 녹화"&&MyVideos.Kind("수업.subtitled.mp4")=="자막 넣은 영상"&&MyVideos.Kind("YelPoint-20261108-090000.SUBTITLED.MP4")=="자막 넣은 영상"&&MyVideos.Kind("yelpoint-20261108-090000.mp4")=="화면 녹화"&&MyVideos.Kind("수업.mp4")=="영상"&&MyVideos.Kind(null)=="영상","My Videos kind is wrong.");
        Require(MyVideos.Burned("a.subtitled.mp4")&&!MyVideos.Burned("a.mp4")&&!MyVideos.Burned(null),"Burned-in subtitle name is wrong.");
        var saved=new List<SavedVideo>{new SavedVideo{Path=@"C:\c\YelPoint-20261101-080000.mp4",Written=new DateTime(2026,11,1,8,0,0)},new SavedVideo{Path=@"C:\c\b.mp4",Written=new DateTime(2026,11,7,9,0,0)},new SavedVideo{Path=@"C:\c\a.mp4",Written=new DateTime(2026,11,7,9,0,0)},new SavedVideo{Path=@"C:\c\new.mp4",Written=new DateTime(2026,11,8,7,0,0)}};
        MyVideos.NewestFirst(saved);Require(saved[0].Path.EndsWith("new.mp4")&&saved[1].Path.EndsWith("b.mp4")&&saved[2].Path.EndsWith("a.mp4")&&saved[3].Path.EndsWith("080000.mp4"),"My Videos order is wrong.");
        var clip=new SavedVideo{Path=@"C:\c\YelPoint-phone-1.mp4",Written=new DateTime(2026,11,6,19,44,0),Bytes=63007066,Subtitles=true};
        Require(MyVideos.Label(clip,65)=="11월 6일 오후 7:44 · 1분 5초 · 63MB"&&MyVideos.Label(clip,0)=="11월 6일 오후 7:44 · 63MB"&&MyVideos.Label(new SavedVideo{Written=new DateTime(2026,1,2,0,5,0),Bytes=10},0)=="1월 2일 오전 12:05 · 1MB","My Videos label is wrong.");
        Require(MyVideos.Detail(clip)=="폰 화면 녹화 · 자막 있음"&&MyVideos.Detail(new SavedVideo{Path="x.mp4"})=="영상","My Videos detail is wrong.");
        Look.English=true;Require(MyVideos.Label(clip,0)=="Nov 6, 7:44 PM · 63MB"&&MyVideos.Detail(clip)=="Phone recording · Has subtitles"&&MyVideos.Kind("YelPoint-1.mp4")=="Screen recording","English My Videos text is wrong.");Look.English=false;
        // Panels attach like magnets: 4 px from the toolbar, level with or centred on the button that opened them (the Mac case is x 116, top at the opener's top).
        var standing=new System.Drawing.Rectangle(8,300,104,356);var column=new System.Drawing.Size(140,120);
        Require(Look.SideOrigin(standing,column,work,4,new System.Drawing.Rectangle(14,477,80,43))==new System.Drawing.Point(116,477)&&Look.SideOrigin(standing,column,work,4,new System.Drawing.Rectangle(14,1000,80,43))==new System.Drawing.Point(116,920)&&Look.SideOrigin(new System.Drawing.Rectangle(1808,300,104,356),column,work,4,new System.Drawing.Rectangle(1814,400,80,43))==new System.Drawing.Point(1664,400)&&Look.SideOrigin(standing,column,work,6).X==118,"Standing panel does not follow its button.");
        var lying=new System.Drawing.Rectangle(300,900,866,56);
        Require(Look.ChildOrigin(lying,column,work,4,new System.Drawing.Rectangle(494,906,64,44))==new System.Drawing.Point(456,776)&&Look.ChildOrigin(lying,column,work,4,new System.Drawing.Rectangle(0,906,64,44)).X==0&&Look.ChildOrigin(new System.Drawing.Rectangle(300,0,866,56),column,work,4,new System.Drawing.Rectangle(494,6,64,44))==new System.Drawing.Point(456,60)&&Look.ChildOrigin(lying,column,work,4).X==663,"Flat panel is not centred on its button.");
        // A standing panel: reading order, then rows that fit the column.
        var phoneFlat=new[]{new System.Drawing.Rectangle(92,36,92,40),new System.Drawing.Rectangle(590,5,190,30),new System.Drawing.Rectangle(8,36,82,40),new System.Drawing.Rectangle(14,9,566,22)};
        Require(string.Join(",",Look.ReadingOrder(phoneFlat,20))=="3,1,2,0"&&string.Join(",",Look.ReadingOrder(new[]{new System.Drawing.Rectangle(94,8,30,32),new System.Drawing.Rectangle(38,14,32,22),new System.Drawing.Rectangle(8,8,30,32)},20))=="2,1,0","Reading order is wrong.");
        int stackHeight;var zoomSize=new System.Drawing.Size(54,34);var zoomed=Look.Flow(new[]{zoomSize,zoomSize,zoomSize,zoomSize,zoomSize},128,6,4,out stackHeight);
        Require(stackHeight==122&&zoomed[0]==new System.Drawing.Rectangle(8,6,54,34)&&zoomed[1]==new System.Drawing.Rectangle(66,6,54,34)&&zoomed[3]==new System.Drawing.Rectangle(66,44,54,34)&&zoomed[4]==new System.Drawing.Rectangle(37,82,54,34),"Zoom column is wrong.");
        var timed2=Look.Flow(new[]{new System.Drawing.Size(30,32),new System.Drawing.Size(32,22),new System.Drawing.Size(23,22),new System.Drawing.Size(30,32)},140,6,4,out stackHeight);
        Require(stackHeight==44&&timed2[0]==new System.Drawing.Rectangle(7,6,30,32)&&timed2[1]==new System.Drawing.Rectangle(41,11,32,22)&&timed2[2]==new System.Drawing.Rectangle(77,11,23,22)&&timed2[3]==new System.Drawing.Rectangle(104,6,30,32),"Row is not centred.");
        var qrStack=Look.Flow(new[]{new System.Drawing.Size(392,24),new System.Drawing.Size(100,40),new System.Drawing.Size(40,40)},232,6,4,out stackHeight);
        Require(stackHeight==80&&qrStack[0]==new System.Drawing.Rectangle(6,6,220,24)&&qrStack[1]==new System.Drawing.Rectangle(44,34,100,40)&&qrStack[2]==new System.Drawing.Rectangle(148,34,40,40),"Wide control was not fitted to the column.");
        Require(Look.Flow(new System.Drawing.Size[0],100,6,4,out stackHeight).Length==0&&stackHeight==12,"Empty column is wrong.");
        Console.WriteLine("PASS: standing panel reading order and row flow, magnet panel placement by opening button, My Videos kind, order and row text, phone gallery list and labels, sticker bar place, typed subtitle timing, placeholder lines, DPI factor and pixel sizes, spot reach, wait-pid argument, time's-up hold, QR encoding, phone detection and scrcpy arguments, language, zoom levels, live toolbar shape, standing toolbar, toolbar bounds, pen width slider, Ctrl wheel sizes, recording size, spot geometry, pointer size, color wheel, older settings, countdown, sticker fit, capture names, external save/load, replacement save, missing/invalid/corrupt/null JSON, failed-rename rollback, fading/persistent ink");
    }
}
