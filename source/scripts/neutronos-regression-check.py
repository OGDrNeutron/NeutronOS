#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, re, shutil, sys
from pathlib import Path

ERRORS=[]; WARNINGS=[]; PASSES=[]
def ok(m): PASSES.append(m); print(f'[PASS] {m}')
def warn(m): WARNINGS.append(m); print(f'[WARN] {m}')
def fail(m): ERRORS.append(m); print(f'[FAIL] {m}')
def read(p):
    try: return p.read_text(encoding='utf-8')
    except Exception as e: fail(f'Cannot read {p}: {e}'); return ''

def check_markers(root: Path, rel: str, markers: list[str]):
    p=root/rel
    if not p.is_file(): fail(f'Missing {rel}'); return ''
    text=read(p)
    missing=[m for m in markers if m not in text]
    if missing: fail(f'{rel} missing integration marker(s): '+', '.join(missing))
    else: ok(rel)
    return text

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('root')
    ap.add_argument('--allow-partial', action='store_true')
    ap.add_argument('--runtime', action='store_true')
    ap.add_argument('--report')
    a=ap.parse_args(); root=Path(a.root).expanduser().resolve()
    if not root.is_dir(): print('Root not found',file=sys.stderr); return 2

    version_path=root/'config/version.json'
    try: version=json.loads(version_path.read_text())
    except Exception as e: fail(f'Invalid config/version.json: {e}'); version={}
    # Patch 60I introduced this contract. Canonical SemVer releases supersede
    # the legacy top-level patch counter but continue to satisfy the baseline.
    semantic = re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', str(version.get('version', '')))
    canonical = version.get('product') == 'NeutronOS' and semantic and version.get('releaseId')
    legacy_patch = version.get('patch', version.get('legacyPatch', {}).get('patch', -1))
    if canonical: ok('Canonical release identity satisfies Patch 60I-or-later prerequisite')
    elif int(legacy_patch) >= 60: ok('Patch 60I-or-later version prerequisite')
    else: fail('Expected canonical release identity or Patch 60I-or-later metadata')

    cmake=read(root/'CMakeLists.txt')
    refs=sorted(set(re.findall(r'\b(src/[A-Za-z0-9_./-]+\.(?:cpp|h))\b',cmake)))
    missing=[r for r in refs if not (root/r).is_file()]
    if missing and not a.allow_partial: fail('CMake source files missing: '+', '.join(missing))
    elif missing: warn(f'Partial source bundle omits {len(missing)} CMake files')
    else: ok(f'CMake references {len(refs)} existing source files')

    apps=[]; ids={}
    for manifest in sorted((root/'qml/apps').glob('*/app.json')):
        try: data=json.loads(manifest.read_text())
        except Exception as e: fail(f'Invalid {manifest.relative_to(root)}: {e}'); continue
        app_id=str(data.get('id','')).strip(); app_type=str(data.get('type','qml')).lower()
        if not app_id: fail(f'{manifest.relative_to(root)} has no id'); continue
        if app_id in ids: fail(f'Duplicate app id {app_id}: {ids[app_id]} and {manifest}')
        ids[app_id]=str(manifest.relative_to(root)); apps.append(data)
        if app_type=='qml':
            src=str(data.get('qmlSource') or data.get('entry') or '').strip()
            if src.startswith('qml/apps/'): candidate=root/src
            elif src.startswith('apps/'): candidate=root/'qml'/src
            else: candidate=root/'qml/apps'/src
            if not candidate.is_file():
                if a.allow_partial: warn(f'{app_id} entry point omitted from partial bundle: {candidate.relative_to(root)}')
                else: fail(f'{app_id} entry point missing: {candidate.relative_to(root)}')
    if apps: ok(f'Parsed {len(apps)} unique app manifests')
    else: fail('No app manifests found')

    apphost=check_markers(root,'qml/apps/AppHost.qml',['qmlLaunchTimeoutMs: 12000','id: qmlLaunchWatchdog','Timed out while loading'])
    browser=check_markers(root,'qml/apps/browser/BrowserView.qml',['WebEngineView','settings.fullScreenSupportEnabled'])
    if re.search(r'^\s*fullscreenSupportEnabled\s*:',browser,re.M): fail('Browser still assigns fullscreenSupportEnabled directly to WebEngineView')
    else: ok('Browser fullscreen setting is scoped through WebEngine settings')
    check_markers(root,'qml/apps/settings/Main.qml',['Update & Recovery','Backup & Restore','CPU Profile','Advanced controls remain fully visible'])
    check_markers(root,'src/MusicPlayerManager.cpp',['canonicalHomeForRoot','defaultMusicPath','scanAllMedia','setVisualizationConsumerActive'])
    check_markers(root,'src/MediaOptimizerManager.cpp',['allowedBatchSizes{100, 250, 500, 1000, 2500, 0}','Scan batch complete','QSaveFile saveFile(cachePath)'])
    check_markers(root,'src/GalleryManager.cpp',['Screenshots','Recordings','Video'])
    check_markers(root,'src/CaptureManager.cpp',['Screenshots','Recordings'])
    check_markers(root,'qml/apps/texteditor/Main.qml',['Untitled','Check Syntax','Auto Correct'])
    check_markers(root,'qml/apps/appstore/Main.qml',['Discover','Updates','Installed apps are managed in Settings'])

    audit=root/'scripts/neutronos-qml-audit.py'
    if audit.is_file(): ok('QML audit script installed')
    else: fail('QML audit script missing')

    if a.runtime:
        for binary in ['build/NeutronShell','build/NeutronBrowser']:
            p=root/binary
            if p.is_file() and p.stat().st_mode & 0o111: ok(f'Runtime binary executable: {binary}')
            else: fail(f'Runtime binary missing or not executable: {binary}')
        for cmd in ['cmake','ffmpeg','ffprobe','mpv']:
            if shutil.which(cmd): ok(f'Dependency available: {cmd}')
            else: warn(f'Optional/runtime dependency missing: {cmd}')
        home=root.parent
        for rel in ['Music','Pictures','Videos','Pictures/NeutronOS/Screenshots','Videos/NeutronOS/Recordings']:
            p=home/rel
            if p.is_dir(): ok(f'Media directory: {p}')
            else: warn(f'Media directory will be created when needed: {p}')

    summary={'root':str(root),'passes':PASSES,'warnings':WARNINGS,'errors':ERRORS}
    if a.report:
        rp=Path(a.report).expanduser(); rp.parent.mkdir(parents=True,exist_ok=True)
        rp.write_text(json.dumps(summary,indent=2)+'\n')
        print(f'Report: {rp}')
    print(f'\nRegression result: {len(PASSES)} passed, {len(WARNINGS)} warnings, {len(ERRORS)} errors')
    return 1 if ERRORS else 0
if __name__=='__main__': raise SystemExit(main())
