using System;using System.IO;using System.Drawing;using System.Windows.Forms;using YelPoint;
class CaptureTests {
 static void Check(bool yes,string message){if(!yes)throw new Exception(message);}
 [STAThread] static int Main(){Controller app=null;IDataObject clipboard=null;try{
 Application.EnableVisualStyles();clipboard=Clipboard.GetDataObject();
 var storage=new Storage(@"D:\rea\spotmouse\.build\windows-105\capture-test-data");app=new Controller(storage);Application.DoEvents();
 app.FinishSelection(app.Ink[0],new Rectangle(100,100,300,200));Application.DoEvents();
 Check(app.Stickers.Count==1,"Capture did not open editor");Check(app.Pen&&app.CapturePen,"Capture pen not enabled");var sticker=app.Stickers[0];Check(sticker.Visible&&sticker.Bar.Visible,"Editor controls not visible");
 var stroke=new Stroke{Color=Color.Red,Width=8};stroke.Points.Add(new PointF(25,30));stroke.Points.Add(new PointF(100,30));sticker.AddStroke(stroke);
 Check(app.CopySticker(sticker,false),"Copy failed");using(var image=(Bitmap)Clipboard.GetImage()){Check(image!=null&&image.Width==300&&image.Height==200,"Clipboard dimensions");var pixel=image.GetPixel(50,28);Check(pixel.R>200&&pixel.G<80,"Annotation missing from clipboard");}
 app.SaveCapture(sticker);Check(Directory.GetFiles(storage.CapturesPath,"*.png").Length==1,"PNG save missing");Check(sticker.UndoLast(),"Undo failed");Check(!sticker.HasInk,"Undo did not remove ink");
 File.WriteAllText(@"D:\rea\spotmouse\.build\windows-105\capture-result.txt","PASS");Console.WriteLine("PASS capture opens visible editor; capture-only pen; annotation composite; clipboard copy; PNG save; undo");return 0;
 }catch(Exception e){File.WriteAllText(@"D:\rea\spotmouse\.build\windows-105\capture-result.txt",e.ToString());Console.WriteLine(e);return 1;}finally{if(app!=null)app.Exit();if(clipboard!=null)try{Clipboard.SetDataObject(clipboard,true);}catch{}}}
}
