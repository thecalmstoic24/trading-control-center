"""Build a self-contained PowerShell installer; no credentials or local config are included."""
import base64
import hashlib
from pathlib import Path
import zipfile
import io

ROOT = Path(__file__).resolve().parents[1]
baseline = ROOT / 'agent' / 'Paired_VM_Agent_v10_4.ps1'
source = baseline.read_text(encoding='utf-8-sig')
anchor = '[void]$form.ShowDialog()'
assert source.count(anchor) == 1
bridge = (ROOT / 'agent' / 'ControlBridge.ps1').read_text(encoding='utf-8-sig')
from upgrade_v14 import upgrade
source = upgrade(source)
extension = (ROOT / 'agent' / 'ControlV14.ps1').read_text(encoding='utf-8-sig')
bridge = extension + '\n' + bridge
output = source.replace(anchor, bridge + '\n' + anchor)
target = ROOT / 'agent' / 'Control_VM_Agent_v14.ps1'
target.write_text(output, encoding='utf-8-sig')  # Windows PowerShell 5.1 needs BOM for Unicode.
assert output.replace(bridge + '\n' + anchor, anchor) == source

files = [target, ROOT / 'agent' / 'ControlGateway.cs', ROOT / 'agent' / 'AirtableWorker.ps1']
files += sorted((ROOT / 'coordinator').glob('*.py'))
files += sorted((ROOT / 'coordinator' / 'static').glob('*'))
files += sorted((ROOT / 'install').glob('*.ps1'))
archive = io.BytesIO()
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for path in files:
        data = path.read_bytes()
        if path.suffix == '.ps1' and not data.startswith(b'\xef\xbb\xbf'):
            data = b'\xef\xbb\xbf' + data
        info = zipfile.ZipInfo(path.relative_to(ROOT).as_posix(), date_time=(2026, 9, 14, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, data)
payload = archive.getvalue()
sha = hashlib.sha256(payload).hexdigest()
b64 = base64.b64encode(payload).decode()
wrapper = '''# Trading Control Center v14 preview - self-contained Windows setup
$ErrorActionPreference = 'Stop'
try {
    $bytes = [Convert]::FromBase64String('__PAYLOAD__')
    $hasher = [Security.Cryptography.SHA256]::Create()
    $actual = ([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    $hasher.Dispose()
    if ($actual -cne '__SHA__') { throw 'Installer payload checksum mismatch.' }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('TradingSetup-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp | Out-Null
    $archive = Join-Path $temp 'package.zip'
    [IO.File]::WriteAllBytes($archive, $bytes)
    Expand-Archive -LiteralPath $archive -DestinationPath $temp -Force
    & (Join-Path $temp 'install\\Install.ps1')
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host 'Press Enter to close'
} finally {
    if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
'''.replace('__PAYLOAD__', b64).replace('__SHA__', sha)
release = ROOT / 'release'
release.mkdir(exist_ok=True)
installer = release / 'Setup_Trading_Control_Center_v14_0_2.ps1'
installer.write_text(wrapper, encoding='utf-8-sig')
print('Payload SHA256:', sha)
print('Installer SHA256:', hashlib.sha256(installer.read_bytes()).hexdigest())
print('Packaged files:', len(files))
