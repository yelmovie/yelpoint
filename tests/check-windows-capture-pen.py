"""Source invariants; use Windows runtime harness for functional validation."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
for source in (root / "windows",):
    c = (source / "Controller.cs").read_text()
    t = (source / "Toolbar.cs").read_text()
    copy = c.split("public bool CopySticker(", 1)[1].split("public void PasteInto", 1)[0]
    assert 'Toggle("pen")' not in copy and 'Pen=false' not in copy, source
    assert 'sticker.FinishStroke();sticker.FinishNote();' in copy, source
    assert 'if(Pen&&!CapturePen){CapturePen=true;RefreshTools();}' in copy, source
    assert c.count('(Pen&&!CapturePen&&!Passthrough)||Selecting||SpotEditing') == 2, source
    capture = c.split('public void FinishSelection(', 1)[1].split('// Hands a finished stroke', 1)[0]
    assert 'AddSticker(' not in capture and 'Pen=true' not in capture, source
    assert 'Clipboard.SetImage(image)' in capture and 'lastCapture=image' in capture, source
    assert 'RecorderNative.BitBlt(' in capture and 'CopyFromScreen(' not in capture, source
    assert 'Present(CaptureBar)' not in capture, source
    assert 'bool pinForAnnotation=true' in capture and 'if(pinForAnnotation){PinCapturedImage(view,area);return;}' in capture, source
    assert 'pinForAnnotation:true' in c, source
    assert 'finally{if(!stored&&image!=null)image.Dispose();foreach(var f in controls)if(!f.IsDisposed)f.Show();}' in capture, source
    assert 'if(PenOptionsOpen&&!Preferences.ToolbarHidden)Present(Penbar)' in c, source
    assert 'if(Pen&&!Preferences.ToolbarHidden)Present(Penbar)' not in c, source
    assert 'TogglePenOptions()' in c and 'pendingPanelDismiss=false;PenOptionsOpen=false;' in c, source
    assert 'bool active=(Pen&&!CapturePen)||Zoom||Selecting||SpotEditing||QrShowing;' in c, source
    assert 'OfferSubtitles' not in c, source
    assert 'QuickCapture(){if(Recording)ToggleRecording();else BeginSelection();}' in c, source
    assert 'else if(image==null&&Stickers.Count>0)' in c, source
    assert 'else if(id==5){BeginSelection();}' in c, source
    capture = c.split('else if(name=="capture")', 1)[1].split('else if(name=="board")', 1)[0]
    assert 'Present(CaptureBar)' in capture and 'BeginSelection' not in capture, source
    assert 'app.Pen&&app.CapturePen&&!app.Passthrough&&!app.Selecting&&!app.SpotEditing' in t, source
    finish = t.split('public void FinishStroke(){', 1)[1].split('protected override void OnMouseDown', 1)[0]
    assert finish.index('activeStroke=null') < finish.index('Capture=false'), source
    assert 'app.UndoHistory.Add(this);app.Clip(this)' in finish, source
    assert 'protected override void OnMouseCaptureChanged' in t, source
    assert 'sticker.ClearInk();Clip(sticker);' in c, source
    assert 'Look.Tr("사진","Photo")' in t and 'Look.Tr("동영상","Video")' in t, source
    print("PASS immediate annotation capture, explicit pen options, outside dismissal, direct capture, manual ink and recording source invariants:", source)
