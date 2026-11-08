using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

namespace YelPoint {
// Slot order follows the Media Foundation headers. A* slots are never called;
// they only hold vtable positions, and trailing methods we don't use are omitted.
[ComImport,Guid("44ae0fa8-ea31-4109-8d2e-4cae4997c555"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMFMediaType {
    void A00();void A01();void A02();void A03();void A04();void A05();void A06();void A07();void A08();void A09();
    void A10();void A11();void A12();void A13();void A14();void A15();void A16();void A17();
    void SetUINT32([MarshalAs(UnmanagedType.LPStruct)]Guid key,int value);
    void SetUINT64([MarshalAs(UnmanagedType.LPStruct)]Guid key,long value);
    void A20();
    void SetGUID([MarshalAs(UnmanagedType.LPStruct)]Guid key,[MarshalAs(UnmanagedType.LPStruct)]Guid value);
}

[ComImport,Guid("045fa593-8799-42b8-bc8d-8968c6453507"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMFMediaBuffer {
    void Lock(out IntPtr buffer,out int maxLength,out int currentLength);
    void Unlock();
    void GetCurrentLength(out int length);
    void SetCurrentLength(int length);
}

[ComImport,Guid("c40a00f2-b93a-4d80-ae8c-5a1c634f58e4"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMFSample {
    void A00();void A01();void A02();void A03();void A04();void A05();void A06();void A07();void A08();void A09();
    void A10();void A11();void A12();void A13();void A14();void A15();void A16();void A17();void A18();void A19();
    void A20();void A21();void A22();void A23();void A24();void A25();void A26();void A27();void A28();void A29();
    void GetSampleFlags(out int flags);
    void SetSampleFlags(int flags);
    void GetSampleTime(out long time);
    void SetSampleTime(long time);
    void GetSampleDuration(out long duration);
    void SetSampleDuration(long duration);
    void GetBufferCount(out int count);
    void GetBufferByIndex(int index,out IMFMediaBuffer buffer);
    void ConvertToContiguousBuffer(out IMFMediaBuffer buffer);
    void AddBuffer(IMFMediaBuffer buffer);
}

[ComImport,Guid("3137f1cd-fe5e-4805-a5d8-fb477448cb3d"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IMFSinkWriter {
    void AddStream(IMFMediaType type,out int stream);
    void SetInputMediaType(int stream,IMFMediaType type,IntPtr encodingParameters);
    void BeginWriting();
    void WriteSample(int stream,IMFSample sample);
    void SendStreamTick(int stream,long time);
    void PlaceMarker(int stream,IntPtr context);
    void NotifyEndOfSegment(int stream);
    void Flush(int stream);
    void Complete(); // IMFSinkWriter::Finalize
}

internal static class RecorderNative {
    [StructLayout(LayoutKind.Sequential)] public struct BITMAPINFOHEADER {public int Size,Width,Height;public short Planes,BitCount;public int Compression,SizeImage,XPels,YPels,ClrUsed,ClrImportant;}
    [StructLayout(LayoutKind.Sequential)] public struct CURSORINFO {public int Size,Flags;public IntPtr Cursor;public Native.POINT Position;}
    [StructLayout(LayoutKind.Sequential)] public struct ICONINFO {public bool IsIcon;public int HotspotX,HotspotY;public IntPtr Mask,Color;}
    [StructLayout(LayoutKind.Sequential,Pack=2)] public struct WAVEFORMATEX {public short FormatTag,Channels;public int SamplesPerSecond,AverageBytesPerSecond;public short BlockAlign,BitsPerSample,ExtraSize;}
    [StructLayout(LayoutKind.Sequential)] public struct WAVEHDR {public IntPtr Data;public int BufferLength,BytesRecorded;public IntPtr User;public int Flags,Loops;public IntPtr Next,Reserved;}
    [DllImport("mfplat.dll")] public static extern int MFStartup(int version,int flags);
    [DllImport("mfplat.dll")] public static extern int MFShutdown();
    [DllImport("mfplat.dll")] public static extern int MFCreateMediaType(out IMFMediaType type);
    [DllImport("mfplat.dll")] public static extern int MFCreateSample(out IMFSample sample);
    [DllImport("mfplat.dll")] public static extern int MFCreateMemoryBuffer(int length,out IMFMediaBuffer buffer);
    [DllImport("mfreadwrite.dll",CharSet=CharSet.Unicode)] public static extern int MFCreateSinkWriterFromURL(string url,IntPtr stream,IntPtr attributes,out IMFSinkWriter writer);
    [DllImport("kernel32.dll",EntryPoint="RtlMoveMemory")] public static extern void CopyMemory(IntPtr destination,IntPtr source,UIntPtr length);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateDIBSection(IntPtr dc,ref BITMAPINFOHEADER info,int usage,out IntPtr bits,IntPtr section,int offset);
    [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr dest,int x,int y,int width,int height,IntPtr source,int sx,int sy,int operation);
    [DllImport("gdi32.dll")] public static extern bool StretchBlt(IntPtr dest,int x,int y,int width,int height,IntPtr source,int sx,int sy,int sw,int sh,int operation);
    [DllImport("gdi32.dll")] public static extern int SetStretchBltMode(IntPtr dc,int mode);
    [DllImport("user32.dll")] public static extern bool GetCursorInfo(ref CURSORINFO info);
    [DllImport("user32.dll")] public static extern bool GetIconInfo(IntPtr icon,out ICONINFO info);
    [DllImport("user32.dll")] public static extern bool DrawIconEx(IntPtr dc,int x,int y,IntPtr icon,int width,int height,int step,IntPtr brush,int flags);
    [DllImport("user32.dll")] public static extern bool SetWindowDisplayAffinity(IntPtr window,uint affinity);
    [DllImport("winmm.dll")] public static extern int waveInOpen(out IntPtr handle,int device,ref WAVEFORMATEX format,IntPtr callback,IntPtr instance,int flags);
    [DllImport("winmm.dll")] public static extern int waveInPrepareHeader(IntPtr handle,IntPtr header,int size);
    [DllImport("winmm.dll")] public static extern int waveInUnprepareHeader(IntPtr handle,IntPtr header,int size);
    [DllImport("winmm.dll")] public static extern int waveInAddBuffer(IntPtr handle,IntPtr header,int size);
    [DllImport("winmm.dll")] public static extern int waveInStart(IntPtr handle);
    [DllImport("winmm.dll")] public static extern int waveInReset(IntPtr handle);
    [DllImport("winmm.dll")] public static extern int waveInClose(IntPtr handle);
}

// Polled rather than called back, so every sample reaches the writer on one thread.
internal sealed class Microphone {
    public const int Rate=48000;
    // 16 buffers of 100 ms: 1.6 s of room while a large frame is being written.
    const int BufferBytes=Rate*2/10,Count=16,Done=1;
    readonly IntPtr[] headers=new IntPtr[Count],data=new IntPtr[Count];
    readonly int headerSize=Marshal.SizeOf(typeof(RecorderNative.WAVEHDR)),flagsOffset=Marshal.OffsetOf(typeof(RecorderNative.WAVEHDR),"Flags").ToInt32(),recordedOffset=Marshal.OffsetOf(typeof(RecorderNative.WAVEHDR),"BytesRecorded").ToInt32();
    IntPtr handle;
    int next;
    Microphone(IntPtr handle){this.handle=handle;}
    public static Microphone Open(){
        var format=new RecorderNative.WAVEFORMATEX{FormatTag=1,Channels=1,SamplesPerSecond=Rate,AverageBytesPerSecond=Rate*2,BlockAlign=2,BitsPerSample=16};
        IntPtr handle;if(RecorderNative.waveInOpen(out handle,-1,ref format,IntPtr.Zero,IntPtr.Zero,0)!=0)return null;
        var mic=new Microphone(handle);
        for(int i=0;i<Count;i++){
            mic.data[i]=Marshal.AllocHGlobal(BufferBytes);mic.headers[i]=Marshal.AllocHGlobal(mic.headerSize);
            Marshal.StructureToPtr(new RecorderNative.WAVEHDR{Data=mic.data[i],BufferLength=BufferBytes},mic.headers[i],false);
            if(RecorderNative.waveInPrepareHeader(handle,mic.headers[i],mic.headerSize)!=0||RecorderNative.waveInAddBuffer(handle,mic.headers[i],mic.headerSize)!=0){mic.Close();return null;}
        }
        return mic;
    }
    public void Start(){RecorderNative.waveInStart(handle);}
    // true when every buffer was full: the device had nowhere to put sound for a while, so some was lost.
    public bool Drain(Action<IntPtr,int> write){
        int drained=0;
        while((Marshal.ReadInt32(headers[next],flagsOffset)&Done)!=0){
            int bytes=Marshal.ReadInt32(headers[next],recordedOffset);if(bytes>0)write(data[next],bytes);
            Marshal.WriteInt32(headers[next],flagsOffset,Marshal.ReadInt32(headers[next],flagsOffset)&~Done);
            RecorderNative.waveInAddBuffer(handle,headers[next],headerSize);next=(next+1)%Count;drained++;
        }
        return drained>=Count;
    }
    public void Close(){
        if(handle==IntPtr.Zero)return;RecorderNative.waveInReset(handle);
        for(int i=0;i<Count;i++){if(headers[i]!=IntPtr.Zero){RecorderNative.waveInUnprepareHeader(handle,headers[i],headerSize);Marshal.FreeHGlobal(headers[i]);}if(data[i]!=IntPtr.Zero)Marshal.FreeHGlobal(data[i]);}
        RecorderNative.waveInClose(handle);handle=IntPtr.Zero;
    }
}

// Records one display to MP4. All COM objects live on this class's own MTA thread.
internal sealed class ScreenRecorder {
    const int Fps=15,Version=0x00020070,CopyBits=0x00CC0020|0x40000000;
    const long Second=10000000;
    static readonly Guid MajorType=new Guid("48eba18e-f8c9-4687-bf11-0a74c9f96a8f"),Subtype=new Guid("f7e34c9a-42e8-4714-b74b-cb29d72c35e5"),Bitrate=new Guid("20332624-fb0d-4d9e-bd0d-cbf6786c102e"),Interlace=new Guid("e2724bb8-e676-4806-b4b2-a8d6efb44ccd"),FrameSize=new Guid("1652c33d-d6b2-4012-b834-72030849a37d"),FrameRate=new Guid("c459a2e8-3d2c-4e44-b132-fee5156c7bb0"),PixelAspect=new Guid("c6376a1e-8d0a-4027-be45-6d9a0ad39bb6");
    static readonly Guid Channels=new Guid("37e48bf5-645e-4c5b-89de-ada9e29b696a"),SampleRate=new Guid("5faeeae7-0290-4c31-9e8a-c534f68d9dba"),BitsPerSample=new Guid("f2deb57f-40fa-4764-aa33-ed4f2d1ff669"),BytesPerSecond=new Guid("1aab75c8-cfef-451c-ab95-ac034b8e1731"),BlockAlignment=new Guid("322de230-9eeb-43bd-ab7a-ff412251541d");
    static readonly Guid Video=new Guid("73646976-0000-0010-8000-00aa00389b71"),Audio=new Guid("73647561-0000-0010-8000-00aa00389b71"),H264=new Guid("34363248-0000-0010-8000-00aa00389b71"),Rgb32=new Guid("00000016-0000-0010-8000-00aa00389b71"),Aac=new Guid("00001610-0000-0010-8000-00aa00389b71"),Pcm=new Guid("00000001-0000-0010-8000-00aa00389b71");
    readonly Rectangle source;
    readonly Size size;
    readonly string path;
    readonly Action<bool> started;
    readonly Action<string> finished;
    readonly ManualResetEvent stop=new ManualResetEvent(false),done=new ManualResetEvent(false);
    IMFSinkWriter writer;
    int videoStream,audioStream;
    public ScreenRecorder(Rectangle source,string path,Action<bool> started,Action<string> finished){this.source=source;size=Look.RecordSize(source.Size);this.path=path;this.started=started;this.finished=finished;}
    public void Start(){var thread=new Thread(Run){IsBackground=true,Name="YelPoint recorder"};thread.SetApartmentState(ApartmentState.MTA);thread.Start();}
    public void Stop(){stop.Set();}
    public bool Wait(int milliseconds){return done.WaitOne(milliseconds);}
    static void Check(int result,string step){if(result<0)throw new COMException(step,result);}
    static IMFMediaType NewType(Guid major,Guid subtype){IMFMediaType type;Check(RecorderNative.MFCreateMediaType(out type),"media type");type.SetGUID(MajorType,major);type.SetGUID(Subtype,subtype);return type;}
    static void Release(object item){if(item!=null)Marshal.ReleaseComObject(item);}
    void Describe(IMFMediaType type){type.SetUINT32(Interlace,2);type.SetUINT64(FrameSize,(long)size.Width<<32|(uint)size.Height);type.SetUINT64(FrameRate,(long)Fps<<32|1);type.SetUINT64(PixelAspect,1L<<32|1);}
    void Open(bool sound){
        IMFSinkWriter created;Check(RecorderNative.MFCreateSinkWriterFromURL(path,IntPtr.Zero,IntPtr.Zero,out created),"sink writer");writer=created;
        IMFMediaType output=null,input=null;
        try{
            output=NewType(Video,H264);output.SetUINT32(Bitrate,size.Width*size.Height*3);Describe(output);writer.AddStream(output,out videoStream);
            input=NewType(Video,Rgb32);Describe(input);writer.SetInputMediaType(videoStream,input,IntPtr.Zero);
        }finally{Release(output);Release(input);}
        if(sound){
            output=input=null;
            try{
                output=NewType(Audio,Aac);output.SetUINT32(Channels,1);output.SetUINT32(SampleRate,Microphone.Rate);output.SetUINT32(BitsPerSample,16);output.SetUINT32(BytesPerSecond,16000);writer.AddStream(output,out audioStream);
                input=NewType(Audio,Pcm);input.SetUINT32(Channels,1);input.SetUINT32(SampleRate,Microphone.Rate);input.SetUINT32(BitsPerSample,16);input.SetUINT32(BlockAlignment,2);input.SetUINT32(BytesPerSecond,Microphone.Rate*2);writer.SetInputMediaType(audioStream,input,IntPtr.Zero);
            }finally{Release(output);Release(input);}
        }
        writer.BeginWriting();
    }
    void CloseWriter(){Release(writer);writer=null;}
    void Write(int stream,IntPtr bytes,int length,long time,long duration){
        IMFMediaBuffer buffer=null;IMFSample sample=null;
        try{
            Check(RecorderNative.MFCreateMemoryBuffer(length,out buffer),"media buffer");
            IntPtr target;int max,current;buffer.Lock(out target,out max,out current);
            try{RecorderNative.CopyMemory(target,bytes,(UIntPtr)(uint)length);}finally{buffer.Unlock();}
            buffer.SetCurrentLength(length);
            Check(RecorderNative.MFCreateSample(out sample),"sample");sample.AddBuffer(buffer);sample.SetSampleTime(time);sample.SetSampleDuration(duration);writer.WriteSample(stream,sample);
        }finally{Release(sample);Release(buffer);}
    }
    void DrawCursor(IntPtr dc){
        var info=new RecorderNative.CURSORINFO{Size=Marshal.SizeOf(typeof(RecorderNative.CURSORINFO))};
        if(!RecorderNative.GetCursorInfo(ref info)||(info.Flags&1)==0)return;
        RecorderNative.ICONINFO icon;if(!RecorderNative.GetIconInfo(info.Cursor,out icon))return;
        double scale=(double)size.Width/source.Width;
        RecorderNative.DrawIconEx(dc,(int)((info.Position.X-source.X)*scale)-icon.HotspotX,(int)((info.Position.Y-source.Y)*scale)-icon.HotspotY,info.Cursor,0,0,0,IntPtr.Zero,3);
        if(icon.Mask!=IntPtr.Zero)Native.DeleteObject(icon.Mask);if(icon.Color!=IntPtr.Zero)Native.DeleteObject(icon.Color);
    }
    void Run(){
        string error=null;bool startedUp=false,opened=false;Microphone mic=null;
        IntPtr screen=IntPtr.Zero,memory=IntPtr.Zero,bitmap=IntPtr.Zero,previous=IntPtr.Zero;
        try{
            Check(RecorderNative.MFStartup(Version,0),"Media Foundation");startedUp=true;
            mic=Microphone.Open();
            try{Open(mic!=null);}
            catch(COMException){if(mic==null)throw;CloseWriter();mic.Close();mic=null;File.Delete(path);Open(false);}
            opened=true;
            // A bottom-up DIB is already the row order Media Foundation assumes for RGB32.
            var header=new RecorderNative.BITMAPINFOHEADER{Size=Marshal.SizeOf(typeof(RecorderNative.BITMAPINFOHEADER)),Width=size.Width,Height=size.Height,Planes=1,BitCount=32};
            screen=Native.GetDC(IntPtr.Zero);memory=Native.CreateCompatibleDC(screen);IntPtr bits;bitmap=RecorderNative.CreateDIBSection(memory,ref header,0,out bits,IntPtr.Zero,0);
            if(bitmap==IntPtr.Zero||bits==IntPtr.Zero)throw new InvalidOperationException(Look.Tr("화면 버퍼를 만들지 못했어요.","Could not create the screen buffer."));
            previous=Native.SelectObject(memory,bitmap);RecorderNative.SetStretchBltMode(memory,4);
            bool stretch=size.Width<source.Width-1;int frameBytes=size.Width*size.Height*4;long frame=Second/Fps,nextFrame=0,audioAt=0;
            var clock=Stopwatch.StartNew();if(mic!=null)mic.Start();
            if(started!=null)started(mic!=null);
            // Sound is stamped on the clock the video uses. It runs on sample counts, and after sound was
            // lost it jumps forward to the clock, so it does not fall behind the picture.
            Action<IntPtr,int> writeAudio=(data,length)=>{long duration=(long)(length/2)*Second/Microphone.Rate;Write(audioStream,data,length,audioAt,duration);audioAt+=duration;};
            do{
                long now=clock.Elapsed.Ticks;
                if(now>=nextFrame){
                    if(stretch)RecorderNative.StretchBlt(memory,0,0,size.Width,size.Height,screen,source.X,source.Y,source.Width,source.Height,CopyBits);
                    else RecorderNative.BitBlt(memory,0,0,size.Width,size.Height,screen,source.X,source.Y,CopyBits);
                    DrawCursor(memory);Write(videoStream,bits,frameBytes,now,frame);nextFrame=Math.Max(nextFrame+frame,now+frame/2);
                }
                if(mic!=null&&mic.Drain(writeAudio))audioAt=Math.Max(audioAt,clock.Elapsed.Ticks);
            }while(!stop.WaitOne(5));
            if(mic!=null)mic.Drain(writeAudio);
        }
        catch(Exception e){error=e.Message;}
        finally{
            try{
                if(mic!=null)mic.Close();
                if(previous!=IntPtr.Zero)Native.SelectObject(memory,previous);if(bitmap!=IntPtr.Zero)Native.DeleteObject(bitmap);if(memory!=IntPtr.Zero)Native.DeleteDC(memory);if(screen!=IntPtr.Zero)Native.ReleaseDC(IntPtr.Zero,screen);
                if(writer!=null){if(opened&&error==null)writer.Complete();CloseWriter();}
                if(startedUp)RecorderNative.MFShutdown();
            }
            catch(Exception e){if(error==null)error=e.Message;}
            done.Set();if(finished!=null)finished(error);
        }
    }
}
}
