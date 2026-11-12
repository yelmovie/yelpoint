using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

[assembly: AssemblyTitle("YelPoint Setup")]
[assembly: AssemblyDescription("YelPoint Setup")]
[assembly: AssemblyProduct("YelPoint")]
[assembly: AssemblyCopyright("© yelsam.lab")]
[assembly: AssemblyVersion("1.0.5.0")]
[assembly: AssemblyFileVersion("1.0.5.0")]

namespace YelPointSetup {
// Setup runs before the app has a language setting, so it follows Windows.
internal static class Lang {
    static readonly bool Korean=System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName=="ko";
    public static string T(string korean,string english){return Korean?korean:english;}
}
internal static class Program {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    static extern int SetCurrentProcessExplicitAppUserModelID(string id);

    [STAThread]
    static int Main() {
        SetCurrentProcessExplicitAppUserModelID("studio.yelpoint.setup");
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        try {
            Application.Run(new SetupForm());
            return 0;
        } catch (Exception error) {
            MessageBox.Show(Lang.T("설치를 시작하지 못했어요. 설치 파일이 있는 드라이브를 확인한 뒤 다시 실행해 주세요.\n\n","Setup could not start. Check the drive and run it again.\n\n")+error.Message,
                Lang.T("YelPoint 설치","YelPoint Setup"), MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}

internal sealed class SetupForm : Form {
    static readonly Color Paper=Color.FromArgb(248,248,242);
    static readonly Color DockColor=Color.FromArgb(32,43,37);
    static readonly Color Lime=Color.FromArgb(215,239,171);
    readonly TextBox folder;
    readonly Button browse,install,cancel;
    readonly CheckBox runAfter,desktop;
    readonly Label heading,description,status;
    readonly PictureBox logo;
    bool installing,complete;
    string installedPath;

    public SetupForm() {
        Text=Lang.T("YelPoint 설치","YelPoint Setup");
        BackColor=Paper;
        ForeColor=DockColor;
        Font=new Font("Malgun Gothic",9F,FontStyle.Regular,GraphicsUnit.Point);
        AutoScaleMode=AutoScaleMode.Dpi;
        ClientSize=new Size(508,372);
        FormBorderStyle=FormBorderStyle.FixedDialog;
        MaximizeBox=false;
        MinimizeBox=true;
        StartPosition=FormStartPosition.CenterScreen;
        using (var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("YelPoint.ico")) {
            Icon=stream==null ? SystemIcons.Application : (Icon)new Icon(stream).Clone();
        }
        logo=new PictureBox {Image=Icon.ToBitmap(),SizeMode=PictureBoxSizeMode.Zoom,Bounds=new Rectangle(28,26,58,58)};
        Controls.Add(logo);
        heading=new Label {Text="YelPoint",Font=new Font("Malgun Gothic",20F,FontStyle.Bold),AutoSize=false,Bounds=new Rectangle(102,25,370,36)};
        description=new Label {Text=Lang.T("강조 · 돋보기 · 펜 · 타이머 · 캡처 · 스팟, 필요한 순간에 바로.","Highlight, Zoom, Pen, Timer, Capture and Spot, right when you need them."),Bounds=new Rectangle(104,65,370,23)};
        Controls.Add(heading);Controls.Add(description);
        Controls.Add(new Label {Text=Lang.T("설치 폴더","Install folder"),Bounds=new Rectangle(29,115,440,22)});
        folder=new TextBox {Bounds=new Rectangle(30,141,354,28)};
        browse=new Button {Text=Lang.T("찾아보기","Browse"),Bounds=new Rectangle(393,140,86,30),FlatStyle=FlatStyle.System};
        folder.Text=DefaultFolder();
        browse.Click+=(s,e)=>ChooseFolder();
        Controls.Add(folder);Controls.Add(browse);
        status=new Label {Text=folder.Text.Length==0
                ? Lang.T("설치할 폴더를 골라 주세요.","Choose a folder to install to.")
                : Lang.T("설정과 임시 파일도 이 폴더의 data에 저장돼요.","Settings and temporary files are also kept in this folder under data."),
            Bounds=new Rectangle(30,184,448,47),ForeColor=Color.FromArgb(91,109,95)};
        Controls.Add(status);
        runAfter=new CheckBox {Text=Lang.T("설치가 끝나면 YelPoint 실행","Start YelPoint when finished"),Checked=true,Bounds=new Rectangle(30,238,448,25)};
        Controls.Add(runAfter);
        desktop=new CheckBox {Text=Lang.T("바탕 화면에 바로 가기 만들기","Add a desktop shortcut"),Checked=true,Bounds=new Rectangle(30,264,448,25)};
        Controls.Add(desktop);
        install=new Button {Text=Lang.T("설치","Install"),Bounds=new Rectangle(270,312,102,33),FlatStyle=FlatStyle.Flat,BackColor=Lime,ForeColor=DockColor};
        install.FlatAppearance.BorderSize=0;
        cancel=new Button {Text=Lang.T("닫기","Close"),Bounds=new Rectangle(382,312,97,33),DialogResult=DialogResult.Cancel};
        install.Click+=(s,e)=>{if(complete)LaunchApp();else InstallApp();};
        cancel.Click+=(s,e)=>Close();
        Controls.Add(install);Controls.Add(cancel);
        AcceptButton=install;CancelButton=cancel;
        FormClosing+=(s,e)=>{if(installing)e.Cancel=true;};
    }

    // Beside setup when it runs from a USB drive, so the program travels with it; otherwise this
    // user's own app folder, which needs no administrator.
    static string DefaultFolder() {
        string root=Path.GetPathRoot(AppDomain.CurrentDomain.BaseDirectory);
        // A USB SSD commonly reports DriveType.Fixed. Query the physical bus too.
        if(Disk.IsExternal(root))return Path.Combine(root,"YelPoint");
        string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return string.IsNullOrEmpty(local) ? "" : Path.Combine(local,"YelPoint");
    }

    void ChooseFolder() {
        using (var dialog=new FolderBrowserDialog()) {
            dialog.Description=Lang.T("YelPoint를 설치할 폴더를 골라 주세요.","Choose a folder for YelPoint.");
            dialog.ShowNewFolderButton=true;
            if(Directory.Exists(folder.Text))dialog.SelectedPath=folder.Text;
            if(dialog.ShowDialog(this)==DialogResult.OK) {
                folder.Text=dialog.SelectedPath;
            }
        }
    }

    void InstallApp() {
        string target;
        try {
            target=ValidateFolder(folder.Text);
        } catch (Exception error) {
            MessageBox.Show(this,error.Message,Lang.T("설치 위치 확인","Check install location"),MessageBoxButtons.OK,MessageBoxIcon.Information);
            return;
        }
        string executable=Path.Combine(target,"YelPoint.exe");
        if (File.Exists(executable)) {
            if (MessageBox.Show(this,Lang.T("이 폴더의 YelPoint 프로그램 파일을 교체할까요?\n기존 data 폴더와 설정은 그대로 유지돼요.","Replace the YelPoint program files in this folder?\nYour data folder and settings stay as they are."),
                Lang.T("YelPoint 업데이트","Update YelPoint"),MessageBoxButtons.OKCancel,MessageBoxIcon.Question)!=DialogResult.OK)return;
        }
        installing=true;SetBusy(true);
        status.Text=Lang.T("선택한 폴더에 설치하고 있어요…","Installing to the selected folder…");status.Refresh();
        try {
            string retainedBackup=Installer.Install(target);
            installedPath=target;complete=true;
            string registered=Installer.Register(target,desktop.Checked);
            heading.Text=Lang.T("준비됐어요!","Ready!");
            description.Text=Lang.T("YelPoint를 실행하고 작업표시줄에 넣어 주세요.","Start YelPoint and pin it to the taskbar.");
            folder.Text=target;folder.ReadOnly=true;browse.Enabled=false;
            runAfter.Visible=false;desktop.Visible=false;status.Height=118;
            status.Text=Lang.T("시작 메뉴에서 열 수 있어요. 실행된 YelPoint 아이콘 우클릭 → 작업 표시줄에 고정","Open it from the Start menu. Right-click the running YelPoint icon → Pin to taskbar");
            if(registered!=null)status.Text+="\n"+registered;
            if(retainedBackup!=null)status.Text+=Lang.T("\n이전 파일 백업: ","\nPrevious files backed up: ")+retainedBackup;
            install.Text=Lang.T("YelPoint 실행","Start YelPoint");
            if(runAfter.Checked)LaunchApp();
        } catch (Exception error) {
            status.Text=Lang.T("설치를 마치지 못했어요. 아래 내용을 확인해 주세요.","Setup could not finish. Please check the details below.");
            MessageBox.Show(this,error.Message,Lang.T("YelPoint 설치","YelPoint Setup"),MessageBoxButtons.OK,MessageBoxIcon.Error);
        } finally {
            installing=false;SetBusy(false);
        }
    }

    static string ValidateFolder(string text) {
        if(string.IsNullOrWhiteSpace(text))throw new IOException(Lang.T("설치할 폴더를 골라 주세요.","Choose a folder to install to."));
        string target=Path.GetFullPath(text.Trim().Trim('"'));
        string root=Path.GetPathRoot(target);
        if(string.IsNullOrEmpty(root)||root.StartsWith("\\\\",StringComparison.Ordinal))
            throw new IOException(Lang.T("이 컴퓨터나 연결된 드라이브의 폴더를 골라 주세요. 네트워크 폴더에는 설치할 수 없어요.","Choose a folder on this computer or a connected drive. Network folders cannot be used."));
        var drive=new DriveInfo(root);
        if(!drive.IsReady)throw new IOException(Lang.T("선택한 드라이브가 연결돼 있지 않아요. 드라이브 연결을 확인해 주세요.","The selected drive is not connected. Check the drive."));
        if(drive.DriveType!=DriveType.Fixed&&drive.DriveType!=DriveType.Removable)
            throw new IOException(Lang.T("설치할 수 있는 디스크가 아니에요. 이 컴퓨터나 USB 드라이브의 폴더를 골라 주세요.","This disk cannot be used. Choose a folder on this computer or a USB drive."));
        if(Disk.IsReadOnly(root))throw new IOException(Lang.T("이 드라이브는 읽기 전용이에요. 쓸 수 있는 드라이브의 폴더를 골라 주세요.","This drive is read-only. Choose a folder on a writable drive."));
        if(drive.AvailableFreeSpace<Installer.RequiredFreeSpace())
            throw new IOException(Lang.T("설치와 이전 파일 백업에 필요한 공간이 부족해요. 저장 공간을 확인해 주세요.","Not enough space to install and back up old files."));
        if(string.Equals(target.TrimEnd(Path.DirectorySeparatorChar),root.TrimEnd(Path.DirectorySeparatorChar),StringComparison.OrdinalIgnoreCase))
            throw new IOException(Lang.T("드라이브 바로 아래에 YelPoint 폴더를 만들거나 선택해 주세요.","Create or choose a YelPoint folder at the top of the drive."));
        string current=Path.GetFullPath(Assembly.GetExecutingAssembly().Location);
        if(string.Equals(Path.Combine(target,"YelPoint.exe"),current,StringComparison.OrdinalIgnoreCase))
            throw new IOException(Lang.T("설치 프로그램과 다른 폴더를 선택해 주세요.","Choose a different folder from the installer."));
        Disk.CheckWritable(target);
        return target;
    }

    void SetBusy(bool busy) {
        folder.Enabled=!busy;browse.Enabled=!busy&&!complete;runAfter.Enabled=!busy;desktop.Enabled=!busy;
        install.Enabled=!busy;cancel.Enabled=!busy;UseWaitCursor=busy;
    }

    void LaunchApp() {
        if(string.IsNullOrEmpty(installedPath))return;
        try {
            string temporary=Path.Combine(installedPath,"data","tmp");Directory.CreateDirectory(temporary);
            var info=new ProcessStartInfo(Path.Combine(installedPath,"YelPoint.exe")) {
                WorkingDirectory=installedPath,UseShellExecute=false
            };
            info.EnvironmentVariables["TEMP"]=temporary;info.EnvironmentVariables["TMP"]=temporary;
            Process.Start(info);
        } catch(Exception error) {
            MessageBox.Show(this,Lang.T("설치는 끝났지만 앱을 열지 못했어요.\n설치 폴더의 YelPoint.exe를 직접 실행해 주세요.\n\n","Setup finished but the app could not open.\nRun YelPoint.exe from the install folder.\n\n")+error.Message,
                Lang.T("YelPoint 실행","Start YelPoint"),MessageBoxButtons.OK,MessageBoxIcon.Information);
        }
    }
    protected override void Dispose(bool disposing) {
        if(disposing){if(logo.Image!=null)logo.Image.Dispose();if(Icon!=null)Icon.Dispose();}
        base.Dispose(disposing);
    }
}

internal static class Installer {
    // scrcpy 5.0.1 (Apache 2.0) for the Android phone screen and document camera, unmodified.
    static readonly string[] ScrcpyFiles={"scrcpy.exe","scrcpy-server","adb.exe","AdbWinApi.dll","AdbWinUsbApi.dll","SDL3.dll","avcodec-63.dll","avformat-63.dll","avutil-61.dll","swresample-7.dll","libusb-1.0.dll","LICENSE.txt"};
    static readonly string[] Names=new[]{"YelPoint.exe","YelPoint.exe.config","사용법.txt","THIRD-PARTY-NOTICES.txt"}.Concat(ScrcpyFiles.Select(f=>Path.Combine("scrcpy",f))).ToArray();
    // The short guide installed as 사용법.txt, in the Windows language. Both versions say the same things.
    static readonly string Guide=Lang.T(
        "YelPoint 수업 도구\r\n\r\n"+
        "1. 시작 메뉴나 바탕 화면의 YelPoint를 눌러 실행해 주세요.\r\n"+
        "2. 작업표시줄의 YelPoint 아이콘을 우클릭하고 '작업 표시줄에 고정'을 누르면 다음부터 바로 열 수 있어요.\r\n"+
        "3. 도구막대에서 강조 · 돋보기 · 펜 · 타이머 · 캡처 · 스팟 · 폰 · QR · 칠판을 골라 쓰면 돼요.\r\n\r\n"+
        "강조: 커서 주변 링과 왼쪽·오른쪽 클릭 표시\r\n"+
        "돋보기: 커서 부근을 1.5~5배로 확대\r\n"+
        "펜: 화면 위에 필기. 색 3개와 색상환, 굵기, 되돌리기, 모두 지우기(되돌리기로 되살릴 수 있어요)\r\n"+
        "타이머: 1~60분 카운트다운. 시계는 끌어서 옮기고 모서리를 끌어 크기를 바꿔요\r\n"+
        "캡처: 영역을 캡처하면 그 자리에 붙어서 바로 필기할 수 있어요. 붙이기 · 저장 · 화면 녹화 · 자막 넣기\r\n"+
        "스팟: 사각·원·타원으로 보여 줄 곳을 빨간 선으로 표시해요\r\n"+
        "폰: USB로 꽂은 안드로이드 폰·태블릿 화면이나 카메라(실물화상기)를 띄워요. 처음에는 폰에서 USB 디버깅을 켜야 해요. 방법은 폰 패널의 ? 버튼에 있어요\r\n"+
        "QR: 주소를 넣으면 화면 가운데에 큰 QR 코드를 보여 줘요\r\n"+
        "칠판: 분필로 쓰고 지우는 큰 칠판이에요. 글씨 넣기와 PNG 저장도 돼요\r\n\r\n"+
        "단축키: Ctrl+Alt+1 강조 / 2 돋보기 / 3 펜 / 4 타이머 / 5 캡처 / 6 스팟 / 0 도구막대 숨기기·보이기\r\n"+
        "Esc: 펜·돋보기·캡처·스팟·QR을 끄고 평소 마우스로 돌아와요. 그린 내용은 남아 있어요.\r\n"+
        "Alt 누르는 동안: 필기 중 클릭과 스크롤이 아래 앱으로 통과해요.\r\n"+
        "Ctrl+휠: 스팟, 주변 어둡게 원, 강조 링 크기를 바꿔요.\r\n"+
        "도구막대는 끌어서 옮길 수 있어요. 왼쪽·오른쪽 끝에 닿으면 세로로 서요.\r\n"+
        "설정: 단축키 표시 / 필기 자동 지우기 / 주변 어둡게 / 언어\r\n\r\n"+
        "종료: 도구막대 맨 끝의 전원 버튼 또는 알림 영역 아이콘 우클릭 → 종료\r\n"+
        "설정과 저장한 캡처·녹화는 이 폴더의 data에 있어요.\r\n"+
        "제거: Windows 설정 → 앱 → 설치된 앱에서 YelPoint를 제거해 주세요. data 폴더는 남겨 둬요.\r\n"+
        "data까지 지우면 설정과 저장한 캡처·녹화도 지워져요.\r\n\r\n"+
        "Windows 10/11 64비트 · .NET Framework 4.8 필요\r\n",
        "YelPoint teaching tool\r\n\r\n"+
        "1. Start YelPoint from the Start menu or the desktop.\r\n"+
        "2. Right-click the YelPoint taskbar icon and choose Pin to taskbar to open it straight away next time.\r\n"+
        "3. Choose Highlight, Zoom, Pen, Timer, Capture, Spot, Phone, QR or Board on the toolbar.\r\n\r\n"+
        "Highlight: a ring around the pointer and left/right click marks\r\n"+
        "Zoom: magnifies near the pointer, 1.5× to 5×\r\n"+
        "Pen: write on the screen. 3 colors and a color wheel, width, undo, clear all (Undo brings it back)\r\n"+
        "Timer: 1 to 60 minute countdown. Drag the clock to move it, drag its corner to resize\r\n"+
        "Capture: grab an area and it stays pinned so you can write on it. Paste, save, record the screen, add subtitles\r\n"+
        "Spot: mark a rectangle, circle or ellipse with a red line\r\n"+
        "Phone: show an Android phone or tablet plugged in over USB, or its camera as a document camera. The phone needs USB debugging turned on first; the ? button on the phone panel shows how\r\n"+
        "QR: type an address to show a big QR code in the middle of the screen\r\n"+
        "Board: a big chalkboard to draw, write and erase on. Save it as PNG\r\n\r\n"+
        "Shortcuts: Ctrl+Alt+1 Highlight / 2 Zoom / 3 Pen / 4 Timer / 5 Capture / 6 Spot / 0 Hide or show the toolbar\r\n"+
        "Esc: turns off Pen, Zoom, Capture, Spot or QR and gives the mouse back. Your ink stays.\r\n"+
        "While holding Alt: clicks and scrolling pass through to the app below.\r\n"+
        "Ctrl+wheel: resizes the spot, the dim circle or the pointer ring.\r\n"+
        "Drag the toolbar to move it. At a side edge it stands up.\r\n"+
        "Settings: shortcut display / fading ink / dim around pointer / language\r\n\r\n"+
        "Quit: the power button at the end of the toolbar, or right-click the tray icon → Quit\r\n"+
        "Settings, saved captures and recordings are in this folder under data.\r\n"+
        "Uninstall: Windows Settings → Apps → Installed apps → YelPoint. The data folder is kept.\r\n"+
        "Deleting data as well removes your settings, captures and recordings.\r\n\r\n"+
        "Windows 10/11 64-bit · .NET Framework 4.8 required\r\n");

    sealed class Entry {
        public string Destination,Staged,Backup;
        public bool Replaced;
    }

    static byte[] ReadResource(string name) {
        using(var source=Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
            if(source==null)throw new IOException(Lang.T("설치 파일의 구성 요소가 빠져 있어요. 설치 파일을 다시 받아 주세요.","The installer is incomplete. Please download it again."));
            using(var memory=new MemoryStream()){source.CopyTo(memory);return memory.ToArray();}
        }
    }

    public static long RequiredFreeSpace() {
        using(var exe=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.exe"))
        using(var config=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.config")) {
            if(exe==null||config==null)throw new IOException(Lang.T("설치 파일을 확인할 수 없어요.","Could not verify the installer."));
            // Includes staging, an ordinary prior release, and portable settings headroom.
            return Math.Max(96L*1024*1024,(exe.Length+config.Length)*4+64L*1024*1024);
        }
    }

    public static string Install(string target) {
        var contents=new[]{ReadResource("payload.exe"),ReadResource("payload.config"),new UTF8Encoding(true).GetBytes(Guide),ReadResource("notices.txt")}.Concat(ScrcpyFiles.Select(f=>ReadResource("scrcpy/"+f))).ToArray();
        if(contents[0].Length<2||contents[0][0]!=77||contents[0][1]!=90)
            throw new IOException(Lang.T("프로그램 파일이 올바르지 않아요. 설치 파일을 다시 받아 주세요.","The program file is invalid. Please download the installer again."));
        Directory.CreateDirectory(target);
        string stage=Path.Combine(target,".YelPoint-install-"+Guid.NewGuid().ToString("N"));
        var entries=new List<Entry>();
        bool committed=false,rollbackComplete=true;
        try {
            Directory.CreateDirectory(stage);
            try{File.SetAttributes(stage,FileAttributes.Hidden|FileAttributes.Directory);}catch(IOException){}
            catch(UnauthorizedAccessException){}
            // Staging itself is the write test; no temp files are created elsewhere.
            for(int i=0;i<Names.Length;i++) {
                var entry=new Entry {Destination=Path.Combine(target,Names[i]),Staged=Path.Combine(stage,"new-"+i),Backup=Path.Combine(stage,"previous-"+i)};
                using(var file=new FileStream(entry.Staged,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
                    file.Write(contents[i],0,contents[i].Length);file.Flush(true);
                }
                entries.Add(entry);
            }
            foreach(var entry in entries) {
                if(!File.Exists(entry.Destination))continue;
                // Detect a running/locked executable before replacing any file.
                try{using(var file=File.Open(entry.Destination,FileMode.Open,FileAccess.ReadWrite,FileShare.None)){}}
                catch(IOException error){throw new IOException(Lang.T("YelPoint를 종료한 뒤 설치를 다시 눌러 주세요.\n프로그램 파일이 사용 중이에요.","Quit YelPoint, then press Install again.\nThe program file is in use."),error);}
            }
            try {
                foreach(var entry in entries) {
                    if(File.Exists(entry.Destination))File.Move(entry.Destination,entry.Backup);
                    Directory.CreateDirectory(Path.GetDirectoryName(entry.Destination));
                    File.Move(entry.Staged,entry.Destination);entry.Replaced=true;
                }
                committed=true;
            } catch(Exception installError) {
                for(int i=entries.Count-1;i>=0;i--) {
                    var entry=entries[i];
                    try {
                        if(entry.Replaced&&File.Exists(entry.Destination))File.Delete(entry.Destination);
                        if(File.Exists(entry.Backup))File.Move(entry.Backup,entry.Destination);
                    } catch {rollbackComplete=false;}
                }
                string detail=rollbackComplete
                    ? Lang.T("이전 프로그램 파일로 복원했어요. 드라이브 연결과 파일 사용 여부를 확인한 뒤 다시 시도해 주세요.","The previous files were restored. Check the drive and that files are not in use, then try again.")
                    : Lang.T("이전 파일 일부를 바로 복원하지 못했어요. 백업을 보관했으니 이 폴더를 확인해 주세요:\n","Some old files could not be restored. A backup was kept in this folder:\n")+stage;
                throw new IOException(detail+"\n\n"+installError.Message,installError);
            }
        } finally {
            if(committed||rollbackComplete) {
                try{if(Directory.Exists(stage))Directory.Delete(stage,true);}
                catch { /* A completed install can keep its backup for later removal. */ }
            }
        }
        return Directory.Exists(stage)?stage:null;
    }

    // For this user only, so no administrator is needed: a Start menu shortcut, an optional desktop
    // shortcut, and an entry in Settings → Apps that runs "YelPoint.exe --uninstall" (see Program.cs).
    // Returns a note for the window when part of it could not be made; the program itself is installed.
    public const string UninstallKey=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\YelPoint";
    public static string Register(string target,bool desktop) {
        string exe=Path.Combine(target,"YelPoint.exe");var notes=new List<string>();
        try{Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"YelPoint.lnk"),exe,target);}
        catch(Exception){notes.Add(Lang.T("시작 메뉴 바로 가기를 만들지 못했어요.","Could not add the Start menu shortcut."));}
        if(desktop)try{Shortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"YelPoint.lnk"),exe,target);}
        catch(Exception){notes.Add(Lang.T("바탕 화면 바로 가기를 만들지 못했어요.","Could not add the desktop shortcut."));}
        try {
            long size=0;foreach(var name in Names){var file=new FileInfo(Path.Combine(target,name));if(file.Exists)size+=file.Length;}
            using(var key=Registry.CurrentUser.CreateSubKey(UninstallKey)) {
                key.SetValue("DisplayName","YelPoint");key.SetValue("DisplayIcon",exe+",0");key.SetValue("DisplayVersion","1.0.0");key.SetValue("Publisher","yelsam.lab");
                key.SetValue("InstallLocation",target);key.SetValue("UninstallString","\""+exe+"\" --uninstall");
                key.SetValue("NoModify",1,RegistryValueKind.DWord);key.SetValue("NoRepair",1,RegistryValueKind.DWord);key.SetValue("EstimatedSize",(int)Math.Min(int.MaxValue,size/1024),RegistryValueKind.DWord);
            }
        } catch(Exception){notes.Add(Lang.T("앱 목록에 제거 항목을 넣지 못했어요. 지울 때는 YelPoint를 종료하고 폴더에서 data를 뺀 나머지를 지워 주세요.","Could not add the entry to Apps. To remove YelPoint, quit it and delete everything in its folder except data."));}
        return notes.Count==0?null:string.Join("\n",notes);
    }
    static void Shortcut(string link,string exe,string folder) {
        Directory.CreateDirectory(Path.GetDirectoryName(link));
        var shell=(IShellLinkW)new ShellLink();
        try {
            shell.SetPath(exe);shell.SetWorkingDirectory(folder);shell.SetIconLocation(exe,0);
            shell.SetDescription(Lang.T("강조 · 돋보기 · 펜 · 타이머 · 캡처 · 스팟 · 폰 · QR · 칠판","Highlight, Zoom, Pen, Timer, Capture, Spot, Phone, QR and Board"));
            ((System.Runtime.InteropServices.ComTypes.IPersistFile)shell).Save(link,true);
        } finally {Marshal.ReleaseComObject(shell);}
    }
}

// The Windows shell's shortcut object. Slot order follows ShObjIdl.h; only the setters are called.
[ComImport,Guid("00021401-0000-0000-C000-000000000046")]
internal class ShellLink {}
[ComImport,Guid("000214F9-0000-0000-C000-000000000046"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IShellLinkW {
    void GetPath([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder file,int length,IntPtr data,int flags);
    void GetIDList(out IntPtr list);
    void SetIDList(IntPtr list);
    void GetDescription([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder name,int length);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)]string name);
    void GetWorkingDirectory([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder directory,int length);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)]string directory);
    void GetArguments([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder arguments,int length);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)]string arguments);
    void GetHotkey(out short key);
    void SetHotkey(short key);
    void GetShowCmd(out int command);
    void SetShowCmd(int command);
    void GetIconLocation([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder path,int length,out int index);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)]string path,int index);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)]string path,int reserved);
    void Resolve(IntPtr window,int flags);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)]string file);
}

internal static class Disk {
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    static extern SafeFileHandle CreateFile(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll",SetLastError=true)]
    static extern bool DeviceIoControl(SafeFileHandle device,uint code,byte[] input,int inputLength,byte[] output,int outputLength,out int returned,IntPtr overlapped);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
    static extern bool GetVolumeInformation(string root,StringBuilder name,int nameLength,out uint serial,out uint maxLength,out uint flags,StringBuilder format,int formatLength);

    public static bool IsExternal(string root) {
        try {
            var drive=new DriveInfo(root);if(!drive.IsReady)return false;
            if(drive.DriveType==DriveType.Removable)return true;
            if(drive.DriveType!=DriveType.Fixed||root.Length<2)return false;
            using(var device=CreateFile("\\\\.\\"+root.Substring(0,2),0,3,IntPtr.Zero,3,0,IntPtr.Zero)) {
                if(device.IsInvalid)return false;
                var query=new byte[12];var descriptor=new byte[512];int read;
                if(!DeviceIoControl(device,0x002D1400,query,query.Length,descriptor,descriptor.Length,out read,IntPtr.Zero)||read<32)return false;
                int bus=BitConverter.ToInt32(descriptor,28);
                // BusType1394, USB, SD and MMC are external/removable connections.
                return bus==4||bus==7||bus==12||bus==13;
            }
        } catch{return false;}
    }
    public static bool IsReadOnly(string root) {
        uint serial,maxLength,flags;
        if(!GetVolumeInformation(root,null,0,out serial,out maxLength,out flags,null,0))
            throw new IOException(Lang.T("드라이브 정보를 읽지 못했어요. 드라이브 연결을 확인해 주세요.","Could not read the drive. Check the drive."),new Win32Exception(Marshal.GetLastWin32Error()));
        return (flags&0x00080000)!=0;
    }
    // Writes and removes a small file there first, so a folder such as Program Files, which only an
    // administrator may change, gets a plain answer instead of "Access denied" halfway through.
    public static void CheckWritable(string target) {
        bool made=!Directory.Exists(target);
        try {
            Directory.CreateDirectory(target);
            using(new FileStream(Path.Combine(target,".yelpoint-write-test-"+Guid.NewGuid().ToString("N")),FileMode.CreateNew,FileAccess.Write,FileShare.None,1,FileOptions.DeleteOnClose)){}
        } catch(Exception error) {
            if(error is UnauthorizedAccessException||error is IOException||error is NotSupportedException||error is System.Security.SecurityException)
                throw new IOException(Lang.T("이 폴더에는 설치할 수 없어요. 쓰기 권한이 없는 폴더예요.\nProgram Files 같은 폴더는 관리자만 바꿀 수 있어요. 처음에 나온 기본 위치나 문서 폴더 아래를 골라 주세요.","YelPoint cannot be installed in this folder because it is not writable.\nFolders such as Program Files need an administrator. Use the suggested folder or one under Documents."),error);
            throw;
        } finally {
            if(made)try{Directory.Delete(target);}catch{ /* Not empty or already gone: leave it. */ }
        }
    }
}
}
