"""Structural checks only; Windows UI, audio and recording behavior still need real Windows tests."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
sources = [
    root / "windows",
    root / "reports/windows-store-preparation/candidate-source",
    root / "reports/windows-store-preparation/prepared-20261109/candidate-source",
]
for source in sources:
    if not source.is_dir():
        continue
    text = (source / "Controller.cs").read_text()
    recording = text.split("public void ToggleRecording(){", 1)[1].split("void StopRecording()", 1)[0]
    stop = recording.index("if(recorder!=null){StopRecording();return;}")
    guard = recording.index("if(Exiting||modal)return;")
    bounds = recording.index("var recordingBounds=Screen.FromControl(Toolbar).Bounds;")
    consent = recording.index("if(!Ask(")
    abort = recording.index("cancelByDefault:true)||Exiting)return;")
    directory = recording.index("Directory.CreateDirectory")
    recorder = recording.index("new ScreenRecorder(recordingBounds,path,")
    start = recording.index("active.Start()")
    assert stop < guard < bounds < consent < abort < directory < recorder < start, source
    for phrase in ["모니터 전체", "기본 마이크", "주변 소리", "오디오 준비에 실패", "소리 없이", "취소",
                   "entire display", "default microphone", "surrounding sounds", "audio setup fails", "Cancel"]:
        assert phrase in recording, (source, phrase)
    assert "new ScreenRecorder(Screen.FromControl(Toolbar)" not in recording, source
    assert "SetModal(true)" in text and "SetModal(false)" in text, source
    assert "public bool Ask(string title,string text,bool ask=true,bool cancelByDefault=false)" in text, source
    assert "Native.Box(text,title,ask,cancelByDefault:cancelByDefault)" in text, source
    native = (source / "Native.cs").read_text()
    assert "yesNo?(cancelByDefault?0x101u:0x4u):0u" in native, source
    assert "==(yesNo&&cancelByDefault?1:6)" in native, source
    print("PASS consent order, disclosure, captured bounds, cancel default and unchanged legacy default:", source)
print("These checks do not execute a Windows message box, screen capture or microphone.")
