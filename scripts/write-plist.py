import plistlib
import sys
with open(sys.argv[1], 'wb') as file:
    plistlib.dump({
        'CFBundleName': 'YelPoint', 'CFBundleDisplayName': 'YelPoint',
        'CFBundleIdentifier': 'studio.yelpoint.app', 'CFBundleExecutable': 'YelPoint',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '1',
        'CFBundleIconFile': 'YelPoint', 'LSMinimumSystemVersion': '14.0',
        'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
        'NSScreenCaptureUsageDescription': '돋보기 확대와 화면 캡처·녹화를 위해 필요해.',
        'NSMicrophoneUsageDescription': '화면 녹화에 목소리를 함께 넣기 위해 필요해.',
        'NSSpeechRecognitionUsageDescription': '녹화한 영상의 말소리로 자막 초안을 만들기 위해 필요해.',
        'NSHumanReadableCopyright': '© yelsam.lab',
    }, file)
