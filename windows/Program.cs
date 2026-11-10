using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using System.Reflection;
using Microsoft.Win32;

[assembly:AssemblyTitle("YelPoint")]
[assembly:AssemblyDescription("Simple teaching tools: cursor highlight, magnifier and screen pen")]
[assembly:AssemblyProduct("YelPoint")]
[assembly:AssemblyCopyright("© yelsam.lab")]
[assembly:AssemblyVersion("1.0.3.0")]
[assembly:AssemblyFileVersion("1.0.3.0")]

namespace YelPoint {
internal static class Program {
    [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int RegisterWindowMessage(string name);
    [DllImport("user32.dll")]static extern bool PostMessage(IntPtr hwnd,int message,IntPtr w,IntPtr l);
    public static readonly int ShowMessageId=RegisterWindowMessage("studio.yelpoint.show-toolbar");
    public const string InstanceName="Local\\studio.yelpoint.app";
    [STAThread]static int Main(){
        var args=Environment.GetCommandLineArgs();
        if(args.Contains("--self-test")){var p=new Preferences{PenColor=99,PenWidth=90};p.Validate();if(p.PenColor!=2||p.PenWidth!=4)return 1;return 0;}
        try{Native.SetProcessDpiAwarenessContext(new IntPtr(-4));}catch(EntryPointNotFoundException){Native.SetProcessDPIAware();}
        Native.SetCurrentProcessExplicitAppUserModelID("studio.yelpoint.app");
        if(args.Contains("--uninstall")||args.Contains("--remove"))return Uninstaller.Run(args);
        // A language change starts this copy before the old one has finished quitting (saving a recording can take a while).
        int previous=Look.WaitPid(args);if(previous>0)WaitFor(previous,true);
        bool created;using(var mutex=new Mutex(true,InstanceName,out created)){
            if(!created){PostMessage(new IntPtr(0xffff),ShowMessageId,IntPtr.Zero,IntPtr.Zero);return 0;}
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            Controller app=null;Storage storage=null;
            // One failed action must not end the lesson: note it in data\yelpoint-error.log, stay quiet and keep running.
            Application.ThreadException+=(s,e)=>{try{string log=Path.Combine(storage!=null?storage.DirectoryPath:Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"data"),"yelpoint-error.log");var old=new FileInfo(log);if(!old.Exists||old.Length<1048576)File.AppendAllText(log,DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")+" "+e.Exception+Environment.NewLine+Environment.NewLine);}catch(Exception){}};
            try{storage=new Storage();app=new Controller(storage);Application.Run(app);return 0;}
            catch(Exception e){if(app!=null&&!app.Exiting)app.Exit();MessageBox.Show(Look.Tr("YelPoint 폴더를 쓸 수 있는 드라이브나 폴더에 두고 다시 실행해 주세요.\n","Put the YelPoint folder on a writable drive or folder and start it again.\n")+e.Message,Look.Tr("YelPoint 시작 실패","YelPoint could not start"),MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
        }
    }
    // Waits up to 30 seconds for that process to end. With sameApp, only a YelPoint process is waited for, in case the id was reused.
    public static void WaitFor(int pid,bool sameApp){
        try{using(var other=Process.GetProcessById(pid))using(var self=Process.GetCurrentProcess()){if(!sameApp||string.Equals(other.ProcessName,self.ProcessName,StringComparison.OrdinalIgnoreCase))other.WaitForExit(30000);}}
        catch(ArgumentException){}catch(InvalidOperationException){}catch(System.ComponentModel.Win32Exception){}
    }
}

// Windows Settings → Apps runs "YelPoint.exe --uninstall" (see Installer.cs). It removes the program
// files, the shortcuts and the Apps entry for this user, and keeps the data folder.
// A running exe cannot delete itself, so a copy in TEMP does the removing after this one has quit.
internal static class Uninstaller {
    const string Key=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\YelPoint";
    static readonly string[] Files={"YelPoint.exe","YelPoint.exe.config","사용법.txt","THIRD-PARTY-NOTICES.txt"};
    static string Title{get{return Look.Tr("YelPoint 제거","Uninstall YelPoint");}}
    public static int Run(string[] args){
        // There are no settings to read yet, so it follows the Windows language, as setup does.
        Look.English=System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName!="ko";
        int at=Array.IndexOf(args,"--remove");
        if(at>=0){
            if(at+1>=args.Length)return 1;
            int pid=Look.WaitPid(args);if(pid>0)Program.WaitFor(pid,false);
            return Remove(args[at+1],false);
        }
        string folder=AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        if(!Native.Box(Look.Tr("YelPoint를 이 컴퓨터에서 제거할까요?\n\n설정과 저장한 캡처·녹화가 있는 data 폴더는 남겨 둬요.\n","Remove YelPoint from this computer?\n\nThe data folder with your settings, captures and recordings is kept.\n")+folder,Title,true,true))return 0;
        if(Running()){Native.Box(Look.Tr("YelPoint가 켜져 있어요. 도구막대의 전원 버튼으로 종료한 뒤 다시 제거해 주세요.","YelPoint is still running. Quit it with the power button on the toolbar, then uninstall again."),Title,false);return 1;}
        try{
            string copy=Path.Combine(Path.GetTempPath(),"YelPoint-Uninstall-"+Guid.NewGuid().ToString("N")+".exe");File.Copy(Application.ExecutablePath,copy);
            using(var self=Process.GetCurrentProcess())Process.Start(new ProcessStartInfo(copy,"--remove "+PhoneModel.Quote(folder)+" --wait-pid "+self.Id){UseShellExecute=false,WorkingDirectory=Path.GetTempPath()});
            return 0;
        }
        // The copy could not start (a school policy may block TEMP): remove everything but this program.
        catch(Exception){return Remove(folder,true);}
    }
    static bool Running(){
        try{using(Mutex.OpenExisting(Program.InstanceName)){}return true;}
        catch(WaitHandleCannotBeOpenedException){return false;}
        catch(UnauthorizedAccessException){return true;}
    }
    // Deletes only YelPoint's own files by name, never the folder as a whole, so data stays.
    static int Remove(string folder,bool keepSelf){
        try{folder=Path.GetFullPath(folder);}catch(Exception){return 1;}
        if(!File.Exists(Path.Combine(folder,"YelPoint.exe"))){Native.Box(Look.Tr("YelPoint 프로그램을 찾지 못했어요. 이미 제거됐을 수 있어요.\n","YelPoint was not found there. It may already be removed.\n")+folder,Title,false);return 1;}
        bool complete=true;
        foreach(var name in Files)if(!(keepSelf&&name=="YelPoint.exe"))complete&=Delete(Path.Combine(folder,name));
        string tools=Path.Combine(folder,"scrcpy");
        try{if(Directory.Exists(tools))Directory.Delete(tools,true);}catch(Exception){complete=false;}
        foreach(var link in new[]{Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),"YelPoint.lnk"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"YelPoint.lnk")})Delete(link);
        try{Registry.CurrentUser.DeleteSubKeyTree(Key,false);}catch(Exception){}
        // Only an empty folder goes; with data in it, it stays.
        try{Directory.Delete(folder);}catch(Exception){}
        string data=Path.Combine(folder,"data");
        string kept=Directory.Exists(data)?Look.Tr("\n\n설정과 저장한 캡처·녹화는 여기에 남겨 뒀어요:\n","\n\nYour settings, captures and recordings are still here:\n")+data:"";
        if(keepSelf)Native.Box(Look.Tr("YelPoint를 거의 다 제거했어요. 실행 중인 YelPoint.exe 하나만 남았으니 직접 지워 주세요:\n","YelPoint is almost removed. Only the running YelPoint.exe is left; please delete it yourself:\n")+folder+kept,Title,false);
        else if(complete)Native.Box(Look.Tr("YelPoint를 제거했어요.","YelPoint was removed.")+kept,Title,false);
        else Native.Box(Look.Tr("일부 파일을 지우지 못했어요. 컴퓨터를 다시 켠 뒤 이 폴더에서 data를 뺀 나머지를 지워 주세요:\n","Some files could not be removed. Restart the computer, then delete everything in this folder except data:\n")+folder+kept,Title,false);
        return complete?0:1;
    }
    static bool Delete(string path){try{if(File.Exists(path))File.Delete(path);return true;}catch(Exception){return false;}}
}
}
