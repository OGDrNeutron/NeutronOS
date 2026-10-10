#!/usr/bin/env python3
"""Gemini Games app-owned installer and local compatibility manager.

No sudo, apt, downloads, shell command interpolation or security bypasses.
The native backend supplies a validated human home and invokes this as the
unprivileged shell user. All game execution takes place in bubblewrap.
"""
from __future__ import annotations
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid

ENVIRONMENT = {'WINEDEBUG','WINEDLLOVERRIDES','DXVK_LOG_LEVEL','DXVK_HUD',
               'VKD3D_CONFIG','PROTON_USE_WINED3D','PROTON_NO_ESYNC',
               'PROTON_NO_FSYNC','MESA_GL_VERSION_OVERRIDE','MESA_GLSL_VERSION_OVERRIDE'}
RUNTIMES = {'wine':('wine','wine64'), 'proton':('proton',),
            'dosbox':('dosbox','dosbox-x'), 'scummvm':('scummvm',)}

def emit(**data):
    print(json.dumps(data,separators=(',',':')),flush=True)

def digest(path):
    with Path(path).open('rb') as handle:return hashlib.file_digest(handle,'sha256').hexdigest()

def atomic(path, data, mode=0o600):
    path = Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.'+path.name+'-',dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as handle:
            # mkstemp already creates 0600. Do not chmod the temporary file
            # after the human-storage owner service can legitimately chown it.
            if mode!=0o600:os.fchmod(handle.fileno(),mode)
            handle.write(data);handle.flush();os.fsync(handle.fileno())
        os.replace(temporary,path)
        fd = os.open(path.parent,os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)
    finally:Path(temporary).unlink(missing_ok=True)

def jsonwrite(path,data):atomic(path,(json.dumps(data,indent=2,sort_keys=True)+'\n').encode())

def execute(args, timeout=30):
    return subprocess.run(args,text=True,capture_output=True,timeout=timeout,check=False)

def mount_options(point):
    # mountinfo remains authoritative even after a FUSE server has died, when
    # stat/ismount can fail with ENOTCONN.
    escaped=str(point).replace('\\','\\134').replace(' ','\\040').replace('\t','\\011').replace('\n','\\012')
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        fields=line.split()
        if len(fields)>6 and fields[4]==escaped:return fields[5].split(',')
    return None

def pe_arch(path):
    with Path(path).open('rb') as handle:
        header=handle.read(64)
        if header[:2] != b'MZ':return ''
        if len(header)<64:return 'dos'
        offset=int.from_bytes(header[60:64],'little')
        if offset>Path(path).stat().st_size:return 'dos'
        handle.seek(offset);pe=handle.read(6)
        if pe[:4]!=b'PE\0\0':return 'dos'
        return {0x14c:'i386',0x8664:'amd64'}.get(int.from_bytes(pe[4:6],'little'),'unsupported')

def file_kind(path):
    path=Path(path)
    with path.open('rb') as handle:header=handle.read(65536)
    if path.suffix.lower()=='.iso':
        if any(header[offset+1:offset+6]==b'CD001' for offset in range(16*2048,min(len(header)-6,32*2048),2048)):return 'iso9660'
        raise ValueError('Unsupported disc format. Only ISO9660/Joliet/Rock Ridge ISO images are mounted; UDF-only or other disc formats are not supported.')
    if path.suffix.lower()=='.msi' and header.startswith(bytes.fromhex('d0cf11e0a1b11ae1')):return 'msi'
    if path.suffix.lower()=='.exe':
        arch=pe_arch(path)
        if arch=='unsupported':raise ValueError('Windows executable architecture is not supported on Gemini AMD64.')
        if arch:return 'dos' if arch=='dos' else 'exe'
    if path.suffix.lower()=='.com' and 0<len(header)<=65536:return 'dos'
    raise ValueError('Choose a verified EXE/MSI installer, DOS program, or an ISO9660 disc image.')

class Manager:
    def __init__(self, home):
        home=Path(home)
        if not home.is_absolute() or home.resolve()!=home or not home.is_dir():raise ValueError('Validated human home is unavailable or redirected.')
        self.home=home
        self.state=home/'apps/gemini-games'
        for p in (home/'apps',self.state):
            if p.is_symlink() or (p.exists() and p.resolve()!=p):raise ValueError('Games state is redirected.')
            p.mkdir(mode=0o700,exist_ok=True)
        self.records=self.state/'installations.json'
        self.mounts=[];self.mount_directory=None;self.cancelled=False;self.child=None

    def authorized(self,path, *, directory=False, writable=False):
        path=Path(path)
        if not path.is_absolute():raise ValueError('Use an absolute path.')
        real=path.resolve(strict=True)
        bases=(self.home,Path('/media'),Path('/run/media'),Path('/mnt'),Path('/NeutronMedia'),Path('/srv/neutronos/user-data'),*(point for point,_,_ in self.mounts))
        if not any(base.exists() and real.is_relative_to(base.resolve()) for base in bases):raise ValueError('Location is outside authorized Home and mounted-volume access.')
        if directory and not real.is_dir():raise ValueError('Folder is unavailable.')
        if not directory and not real.is_file():raise ValueError('File is unavailable.')
        if not os.access(real,os.R_OK|(os.X_OK if directory else 0)|(os.W_OK if writable else 0)):raise ValueError('Permission denied for this location.')
        return real

    def safe_state(self, relative):
        p=self.state/relative
        if not p.is_relative_to(self.state) or '..' in p.parts:raise ValueError('Unsafe app-state location.')
        for parent in [p,*p.parents]:
            if parent==self.state.parent:break
            if parent.is_symlink():raise ValueError('App-state symlinks are not allowed.')
        return p

    def load(self):
        if not self.records.exists():return {}
        if self.records.is_symlink():raise ValueError('Installation metadata is redirected.')
        data=json.loads(self.records.read_text())
        if data.get('schema')!=1 or not isinstance(data.get('games'),dict):raise ValueError('Installation metadata is invalid.')
        return data['games']

    def save(self,games):jsonwrite(self.records,{'schema':1,'games':games})

    def game(self,identity):
        if not re.fullmatch(r'[a-f0-9]{64}',str(identity)):raise ValueError('Invalid managed-game identity.')
        game=self.load().get(identity)
        if not game:raise ValueError('Managed game was not found.')
        return game

    def game_root(self,game):
        root=self.authorized(game['root'],directory=True)
        if game.get('mode')=='managed':
            relative='prefixes/'+game['id']+('/pfx/drive_c' if game.get('configuration',{}).get('runtime')=='proton' else '/drive_c')
            expected=self.safe_state(relative)
            if root!=expected:raise ValueError('Managed game folder is redirected outside its isolated prefix.')
        return root

    def runtime(self, config, kind='exe'):
        rid=str(config.get('runtime','wine'))
        if rid not in RUNTIMES:raise ValueError('Select Wine, Proton, DOSBox or ScummVM.')
        if kind in ('exe','msi','iso9660') and rid not in ('wine','proton'):raise ValueError('Windows installers require Wine or Proton; DOSBox and ScummVM do not run Windows installers.')
        requested=str(config.get('runtimeProgram') or '')
        program=requested or next((p for n in RUNTIMES[rid] if (p:=shutil.which(n))), '')
        if program:
            path=Path(program)
            if path.name not in RUNTIMES[rid]:raise ValueError('Selected executable does not match the chosen runtime. Select its Wine, Proton, DOSBox or ScummVM launcher.')
            if not path.is_absolute() or not path.is_file() or not os.access(path,os.X_OK):program=''
            elif not str(path.resolve()).startswith(('/usr/','/opt/')):self.authorized(path)
        return rid,program

    def discover(self):
        rows=[]
        for rid,names in RUNTIMES.items():
            candidates=[Path(p) for n in names if (p:=shutil.which(n))]
            if rid=='wine':
                for root in (self.home/'.local/share/lutris/runners/wine',self.home/'.local/share/PlayOnLinux/wine/linux-amd64',self.home/'.wine-versions'):
                    if root.is_dir():candidates.extend(root.glob('*/bin/wine'));candidates.extend(root.glob('*/bin/wine64'))
            if rid=='proton':
                for root in (self.home/'.steam/steam/steamapps/common',self.home/'.local/share/Steam/steamapps/common',self.home/'.steam/root/compatibilitytools.d',self.home/'.local/share/Steam/compatibilitytools.d'):
                    if root.is_dir():candidates.extend(root.glob('*/proton'))
            seen=set()
            for path in candidates:
                if not path.is_file() or not os.access(path,os.X_OK) or str(path.resolve()) in seen:continue
                seen.add(str(path.resolve()))
                if rid=='proton':
                    version_file=path.parent/'version';version=version_file.read_text()[:200].strip() if version_file.is_file() else path.parent.name
                elif str(path.resolve()).startswith(('/usr/','/opt/')):
                    try:
                        result=execute([str(path),'--version'],5);version=(result.stdout or result.stderr).strip().split('\n')[0][:200]
                    except (OSError,subprocess.TimeoutExpired):version='Version unavailable'
                else:
                    # Discovery must never execute an unapproved user-supplied runtime.
                    version=path.parent.parent.name+' · local version unverified'
                rows.append({'id':rid,'program':str(path),'version':version,'installed':True,'source':'Installed locally','compatibility':'Requires per-title validation'})
            if not seen:rows.append({'id':rid,'program':'','version':'Not installed','installed':False,'source':'Select an approved signed App Store provider; no automatic download'})
        return rows

    def browse(self,path):
        if not path:
            entries=[{'path':str(self.home),'name':'Home','kind':'home','available':True}]
            for base in ('/media','/run/media','/mnt','/NeutronMedia'):
                root=Path(base)
                if root.is_dir():entries.append({'path':base,'name':root.name,'kind':'drive','available':os.access(root,os.R_OK|os.X_OK)})
            return {'path':'','parent':'','entries':entries}
        root=self.authorized(path,directory=True)
        entries=[]
        for entry in sorted(root.iterdir(),key=lambda p:(not p.is_dir(),p.name.casefold())):
            if entry.name.startswith('.'):continue
            try:
                target=self.authorized(entry,directory=entry.is_dir())
                if target.is_dir():kind='folder'
                elif target.is_file():kind='file'
                else:continue
                entries.append({'path':str(target),'name':entry.name,'kind':kind,'available':True})
            except (OSError,ValueError):continue
            if len(entries)>4000:raise ValueError('Folder is too large; choose a subfolder or enter an exact path.')
        parent=''
        try:parent=str(self.authorized(root.parent,directory=True))
        except (OSError,ValueError):pass
        return {'path':str(root),'parent':parent,'entries':entries}

    def config(self, raw, root, kind='exe'):
        c=dict(raw);rid,program=self.runtime(c,kind)
        args=c.get('arguments',[]);env=c.get('environment',{})
        if not isinstance(args,list) or len(args)>64 or any(not isinstance(a,str) or len(a)>4096 or '\0' in a for a in args):raise ValueError('Arguments must be an array of up to 64 strings.')
        if not isinstance(env,dict) or any(k not in ENVIRONMENT or not isinstance(v,str) or len(v)>4096 or '\0' in v for k,v in env.items()):raise ValueError('Unsupported environment override; use the listed per-game compatibility options.')
        cwd=self.authorized(c.get('workingDirectory') or str(root),directory=True)
        if not cwd.is_relative_to(root):raise ValueError('Working directory must be inside the selected game folder.')
        graphics=c.get('graphics','wined3d')
        if graphics not in ('wined3d','dxvk','vkd3d'):raise ValueError('Unsupported graphics configuration.')
        if graphics in ('dxvk','vkd3d'):
            tool=shutil.which('vulkaninfo')
            if not tool:raise ValueError('Vulkan capability is unknown. Keep WineD3D until a Vulkan device is verified.')
            probe=execute([tool,'--summary'],10)
            if probe.returncode or 'deviceName' not in probe.stdout:raise ValueError('No usable Vulkan device was reported. Keep WineD3D.')
            if not c.get('graphicsComponentsConfirmed'):raise ValueError('DXVK/VKD3D must already be installed in the selected runtime or prefix. Review local DLL components explicitly; Games does not download them.')
        if rid=='proton' and graphics=='wined3d':env['PROTON_USE_WINED3D']='1'
        c.update(runtime=rid,runtimeProgram=program or str(raw.get('runtimeProgram') or ''),arguments=args,environment=env,workingDirectory=str(cwd),graphics=graphics)
        return c

    def register(self,request):
        requested=Path(request['path'])
        scumm=requested.is_dir() and request.get('configuration',{}).get('runtime')=='scummvm'
        if scumm:
            root=self.authorized(requested,directory=True)
            identity=hashlib.sha256(('scummvm:'+str(root)).encode()).hexdigest()
            path=self.safe_state('descriptors/'+identity+'/game.json')
            jsonwrite(path,{'kind':'scummvm','dataDirectory':str(root)})
            kind='scummvm'
        else:
            path=self.authorized(request['path'])
            kind=file_kind(path)
            if kind in ('iso9660','msi'):raise ValueError('Use Install Game for disc images and MSI packages.')
            root=self.authorized(request.get('root') or str(path.parent),directory=True)
            if not path.is_relative_to(root):raise ValueError('Launch executable must belong to the selected game folder.')
            identity=hashlib.sha256(str(path).encode()).hexdigest()
        c=self.config(request.get('configuration',{}),root,kind)
        if kind=='dos' and c['runtime']!='dosbox':raise ValueError('Select DOSBox for this DOS executable.')
        if kind=='scummvm' and (c['runtime']!='scummvm' or not c.get('scummvmGameId')):raise ValueError('ScummVM requires a manually selected data folder and supported game ID.')
        games=self.load();old=games.get(identity,{})
        game={**old,'id':identity,'path':str(path),'title':request.get('title') or (root.name if scumm else path.stem),'mode':'import','root':str(root),'kind':'dos' if kind=='dos' else 'scummvm' if kind=='scummvm' else 'windows','architecture':'' if scumm else pe_arch(path),'configuration':c,'status':'ready','registeredAt':time.time()}
        games[identity]=game;self.save(games)
        return {'game':game,'message':'Game imported. Original files are unchanged; a missing runtime will be requested only on launch.'}

    def configure(self,request):
        games=self.load();game=self.game(request['id']);root=self.game_root(game)
        if game.get('mode')=='pending-installation':raise ValueError('Finish the pending installation first. Choose Reinstall to select its runtime and review the installer again.')
        c=self.config(request['configuration'],root,'dos' if game['kind']=='dos' else 'scummvm' if game['kind']=='scummvm' else 'exe')
        if game.get('mode')=='managed' and c['runtime']!=game.get('configuration',{}).get('runtime'):
            raise ValueError('Managed prefixes cannot switch between Wine and Proton in place. Create a separate installation; installed runtime versions within the same family can be selected safely.')
        selected=request.get('executable')
        if selected:
            p=self.authorized(selected)
            if not p.is_relative_to(root):raise ValueError('Executable must be inside this game folder.')
            kind=file_kind(p)
            if kind not in ('exe','dos'):raise ValueError('Choose a supported launch executable.')
            game.update(path=str(p),architecture=pe_arch(p),status='ready')
        for key in ('prefix','compatDataPath'):
            if key in game.get('configuration',{}):c[key]=game['configuration'][key]
        game['configuration']=c;games[game['id']]=game;self.save(games);return {'game':game}

    def mounted_ro(self,mount):
        return 'ro' in (mount_options(mount) or [])

    def temporary_mount_directory(self):
        if self.mount_directory is None:
            # Private mount views must stay outside human DATA: its unchanged
            # ownership reconciler deliberately cannot traverse private FUSE.
            base=Path(os.environ.get('XDG_RUNTIME_DIR') or tempfile.gettempdir())
            if not base.is_dir() or base.is_symlink() or base.stat().st_uid!=os.geteuid() or base.stat().st_mode&0o077:base=Path(tempfile.gettempdir())
            self.mount_directory=Path(tempfile.mkdtemp(prefix='neutronos-games-'+hashlib.sha256(str(self.home).encode()).hexdigest()[:8]+'-',dir=base))
        return self.mount_directory

    def fuse_process(self,point,command,log):
        # A private supervisor survives forced termination of its owning game
        # group long enough to unmount. It never gains privileges.
        return subprocess.Popen(['/usr/bin/python3',str(Path(__file__).resolve()),'--fuse-owner',str(os.getpid()),str(point),'--',*command],stdout=log,stderr=log,close_fds=True,start_new_session=True)

    def prefix_view(self,prefix):
        prefix=self.safe_state(prefix.relative_to(self.state))
        if not prefix.is_dir():raise ValueError('Isolated runtime prefix is unavailable.')
        program=shutil.which('bindfs')
        if not program:raise ValueError('Required private prefix filesystem support is unavailable. Update Games through the App Store; no optional runtime will be installed.')
        parent=self.temporary_mount_directory()
        point=Path(tempfile.mkdtemp(prefix='prefix-',dir=parent));log=self.safe_state('prefix-view.log').open('ab')
        command=[program,'-f','--no-allow-other','--force-user='+str(os.geteuid()),'--force-group='+str(os.getegid()),'--realistic-permissions','--chmod-ignore','--chown-deny','--chgrp-deny','-o','nodev,nosuid',str(prefix),str(point)]
        process=self.fuse_process(point,command,log);self.mounts.append((point,process,log))
        for _ in range(100):
            if os.path.ismount(point) and point.stat().st_uid==os.geteuid():return point
            if process.poll() is not None:break
            time.sleep(.05)
        raise ValueError('Private Wine prefix view failed. Review prefix-view.log; original ownership and Security are unchanged.')

    def mount(self,image):
        image=self.authorized(image)
        if file_kind(image)!='iso9660':raise ValueError('Unsupported disc format.')
        program=shutil.which('fuseiso')
        if not program or not Path('/dev/fuse').exists():raise ValueError('Read-only ISO mounting is unavailable. Install the declared FUSE support through the App Store; Games will not use privileged mounting.')
        parent=self.temporary_mount_directory()
        point=Path(tempfile.mkdtemp(prefix='disc-',dir=parent));log=self.safe_state('iso-mount.log').open('ab')
        process=self.fuse_process(point,[program,'-n','-f','-o','ro,nodev,nosuid',str(image),str(point)],log)
        self.mounts.append((point,process,log))
        for _ in range(100):
            if self.mounted_ro(point):return point
            if process.poll() is not None:break
            time.sleep(.05)
        raise ValueError('ISO mount failed or did not report read-only access. Review iso-mount.log; no privileged fallback is used.')

    def cleanup(self):
        errors=[]
        for point,process,log in reversed(self.mounts):
            if mount_options(point) is not None:
                unmount=shutil.which('fusermount') or shutil.which('fusermount3')
                result=execute([unmount,'-u',str(point)]) if unmount else None
                if not result or result.returncode:errors.append(str(point));continue
            if process.poll() is None:
                process.terminate()
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:process.kill();process.wait()
            log.close()
            with contextlib.suppress(OSError):point.rmdir()
        self.mounts=[]
        if self.mount_directory is not None and not errors:
            with contextlib.suppress(OSError):self.mount_directory.rmdir()
            self.mount_directory=None
        if errors:raise ValueError('Temporary mount cleanup needs attention; mounts remain at '+', '.join(errors))

    def discover_executables(self,root, *, installers=False):
        root=self.authorized(root,directory=True);out=[];count=0
        for base,dirs,files in os.walk(root,followlinks=False):
            dirs[:]=[d for d in dirs if not (Path(base)/d).is_symlink() and d.casefold() not in ('windows','users','$recycle.bin','internet explorer','windows media player','windows nt','common files')]
            for name in files:
                count+=1
                if count>100000:raise ValueError('Scan limit reached; choose an executable manually.')
                p=Path(base)/name
                if p.suffix.lower() not in ('.exe','.msi','.com') or p.is_symlink():continue
                try:k=file_kind(p)
                except (OSError,ValueError):continue
                if k not in ('exe','msi','dos'):continue
                common=name.casefold() in ('setup.exe','install.exe','installer.exe') or k=='msi'
                utility=any(v in name.casefold() for v in ('unins','uninstall','redist','vcredist','dxsetup','crashreport'))
                if installers and not common and k!='exe':continue
                if not installers and utility:continue
                out.append({'path':str(p),'name':str(p.relative_to(root)),'kind':k,'commonInstaller':common,'architecture':pe_arch(p) if k!='msi' else 'unknown'})
        return sorted(out,key=lambda x:(not x['commonInstaller'] if installers else False,x['name'].casefold()))[:1000]

    def inspect(self,request):
        source=self.authorized(request['path'],directory=Path(request['path']).is_dir())
        if source.is_dir():return {'kind':'folder','candidates':self.discover_executables(source),'root':str(source)}
        kind=file_kind(source)
        if kind=='iso9660':
            try:
                point=self.mount(source)
                return {'kind':kind,'candidates':[{**v,'path':str(Path(v['path']).relative_to(point))} for v in self.discover_executables(point,installers=True)],'source':str(source),'readOnly':True}
            finally:self.cleanup()
        return {'kind':kind,'source':str(source),'candidates':[{'path':str(source),'name':source.name,'kind':kind,'architecture':pe_arch(source) if kind!='msi' else 'unknown'}]}

    def sandbox(self, game, program, arguments, binds, *, installer=False):
        bwrap=shutil.which('bwrap')
        if not bwrap:raise ValueError('Required bubblewrap sandbox is unavailable.')
        prefix=self.safe_state('prefixes/'+game['id']);prefix.mkdir(parents=True,mode=0o700,exist_ok=True)
        runtime_home=self.safe_state('runtime/'+game['id']);runtime_home.mkdir(parents=True,mode=0o700,exist_ok=True)
        c=game['configuration'];rid=c['runtime'];env={'PATH':'/usr/local/bin:/usr/bin:/bin','LANG':os.environ.get('LANG','C.UTF-8'),'HOME':str(runtime_home),'XDG_CONFIG_HOME':str(runtime_home/'config'),'XDG_CACHE_HOME':str(runtime_home/'cache'),'XDG_DATA_HOME':str(runtime_home/'data')}
        env.update(c.get('environment',{}))
        for name in ('DISPLAY','WAYLAND_DISPLAY','XDG_RUNTIME_DIR','PIPEWIRE_RUNTIME_DIR','PULSE_SERVER','XAUTHORITY'):
            if name in os.environ:env[name]=os.environ[name]
        args=[bwrap,'--die-with-parent','--unshare-all','--cap-drop','ALL','--clearenv','--proc','/proc','--dev','/dev','--tmpfs','/tmp','--dir','/run']
        for path in ('/usr','/etc','/sys','/bin','/lib','/lib64'):
            if Path(path).exists():args+=['--ro-bind',path,path]
        writable=[prefix,runtime_home]
        view=self.prefix_view(prefix) if rid in ('wine','proton') else None
        for path in writable:args+=['--bind',str(view if path==prefix and view else path),str(path)]
        for path in dict.fromkeys(map(str,binds)):
            if not any(Path(path).is_relative_to(w) for w in writable):args+=['--ro-bind',path,path]
        if not str(Path(program).resolve()).startswith('/usr/'):
            runtime_root=Path(program).parent.parent if rid=='wine' and Path(program).parent.name=='bin' else Path(program).parent
            args+=['--ro-bind',str(runtime_root),str(runtime_root)]
        for path in ('/dev/dri','/dev/snd'):
            if Path(path).exists():args+=['--dev-bind',path,path]
        for name in ('XDG_RUNTIME_DIR','PIPEWIRE_RUNTIME_DIR'):
            path=os.environ.get(name,'')
            if path and Path(path).is_dir():args+=['--bind',path,path]
        if os.environ.get('DISPLAY') and Path('/tmp/.X11-unix').is_dir():args+=['--ro-bind','/tmp/.X11-unix','/tmp/.X11-unix']
        if os.environ.get('XAUTHORITY') and Path(os.environ['XAUTHORITY']).is_file():args+=['--ro-bind',os.environ['XAUTHORITY'],os.environ['XAUTHORITY']]
        if c.get('network',False):args+=['--share-net']
        env['WINEPREFIX']=str(prefix/'pfx') if rid=='proton' else str(prefix)
        if rid=='proton':
            env['STEAM_COMPAT_DATA_PATH']=str(prefix)
            steam=c.get('steamClientPath','')
            if not steam or not Path(steam).is_dir():raise ValueError('Proton requires an existing Steam client path. Select it in compatibility settings; no client is installed automatically.')
            steam=self.authorized(steam,directory=True);env['STEAM_COMPAT_CLIENT_INSTALL_PATH']=str(steam);args+=['--ro-bind',str(steam),str(steam)]
        for key,value in env.items():args+=['--setenv',key,str(value)]
        if installer and rid=='wine':
            wineserver=Path(program).parent/'wineserver'
            if not wineserver.is_file() and str(Path(program).resolve()).startswith('/usr/'):
                found=shutil.which('wineserver');wineserver=Path(found) if found else wineserver
            if not wineserver.is_file():raise ValueError('The selected Wine installation has no matching wineserver; safe installer lifetime tracking is unavailable.')
            # Fixed app-owned Python runner waits for this prefix's Wine server.
            runner=Path(__file__).resolve();args+=['--ro-bind',str(runner),str(runner),'--','/usr/bin/python3',str(runner),'--wait-wine',str(wineserver),program,*arguments]
        else:args+=['--',program,*arguments]
        return args,env,prefix

    def cancel(self,*_):
        self.cancelled=True
        if self.child and self.child.poll() is None:
            with contextlib.suppress(ProcessLookupError):os.killpg(self.child.pid,signal.SIGTERM)

    def inventory(self,root):
        out={}
        for base,dirs,files in os.walk(root,followlinks=False):
            dirs[:]=[d for d in dirs if not (Path(base)/d).is_symlink() and d.casefold() not in ('windows','users','programdata','internet explorer','windows media player','windows nt','common files')]
            for name in files:
                path=Path(base)/name
                if path.is_symlink() or not path.is_file():continue
                relative=str(path.relative_to(root));out[relative]={'sha256':digest(path),'size':path.stat().st_size}
                if len(out)>200000:raise ValueError('Installation inventory exceeds the safe managed-file limit.')
        return out

    def uninstall_plan(self,request):
        game=self.game(request['id'])
        if game['mode']!='managed':raise ValueError('Imported games are removed from the library only; their files are never uninstalled.')
        root=self.game_root(game)
        expected=self.safe_state('prefixes/'+game['id'])
        if not root.is_relative_to(expected):raise ValueError('Managed uninstall is limited to this game’s own prefix.')
        remove=[];retained=[]
        for relative,entry in game.get('installedFiles',{}).items():
            path=root/relative
            if Path(relative).is_absolute() or '..' in Path(relative).parts:raise ValueError('Invalid installation file inventory.')
            if not path.exists():continue
            if path.is_symlink() or not path.resolve().is_relative_to(root):retained.append({'path':str(path),'reason':'redirected file'});continue
            lower=relative.casefold()
            save=any(part in lower.split('/') for part in ('save','saves','saved games','userdata','profiles','screenshots','documents')) or path.suffix.lower() in ('.sav','.save','.dat','.ini','.cfg','.json','.log','.db')
            if save:retained.append({'path':str(path),'reason':'save or personal configuration'})
            elif digest(path)!=entry['sha256']:retained.append({'path':str(path),'reason':'changed since installation; retain user changes or patches'})
            else:remove.append({'path':str(path),'sha256':entry['sha256'],'size':entry['size']})
        preview={'id':game['id'],'remove':remove,'retained':retained,'prefixRetained':str(expected),'message':'Only unchanged recorded installation files will be removed. Saves, unknown files, imported files, patches and the prefix are retained.'}
        preview['token']=hashlib.sha256(json.dumps(preview,sort_keys=True).encode()).hexdigest()
        return {'uninstallPlan':preview}

    def uninstall(self,request):
        if request.get('approved') is not True:raise ValueError('Explicit managed uninstall approval is required.')
        plan=self.uninstall_plan(request)['uninstallPlan']
        if request.get('token')!=plan['token']:raise ValueError('Installation files changed after review. Review the removal list again.')
        game=self.game(request['id']);removed=[]
        for entry in plan['remove']:
            path=Path(entry['path'])
            # Recheck immediately before each exact unlink; no directory deletion.
            if path.is_symlink() or digest(path)!=entry['sha256']:raise ValueError('A removal target changed. Remaining files were retained.')
            path.unlink();removed.append(str(path))
        game['status']='uninstalled-files-retained';game['lastUninstall']={'removed':removed,'retained':plan['retained'],'time':time.time()}
        games=self.load();games[game['id']]=game;self.save(games)
        return {'removedId':game['id'],'removedFiles':removed,'retained':plan['retained'],'message':'Managed game files uninstalled. Saves, changed files and prefix state are retained for reinstall or repair.'}

    def prepare_wine_drives(self,prefix):
        relative=prefix.relative_to(self.state)
        drive=self.safe_state(relative/'drive_c');drive.mkdir(parents=True,exist_ok=True)
        devices=self.safe_state(relative/'dosdevices');devices.mkdir(parents=True,exist_ok=True)
        # Creating dosdevices before wineboot suppresses Wine's default links.
        # Establish them explicitly without replacing a user-supplied mapping.
        for name,target in [('c:',drive),('z:',Path('/'))]:
            link=devices/name
            if link.exists() or link.is_symlink():
                if not link.is_symlink() or link.resolve()!=target.resolve():raise ValueError('Wine '+name+' mapping is redirected. Restore the isolated prefix mapping before installing.')
            else:link.symlink_to('../drive_c' if name=='c:' else '/')
        return devices

    def install(self,request):
        if request.get('approved') is not True:raise ValueError('Explicit installer approval is required.')
        identity=request.get('id') or hashlib.sha256(uuid.uuid4().bytes).hexdigest()
        existing=self.game(identity) if request.get('id') else None
        source=self.authorized(request.get('path') or existing['source'])
        images=request['discs'] if 'discs' in request else (existing or {}).get('discs') or []
        if not isinstance(images,list) or any(not isinstance(p,str) for p in images):raise ValueError('Disc images must be a list of local paths.')
        if source.suffix.lower()=='.iso' and str(source) not in images:images=[str(source),*images]
        if len(images)>24:raise ValueError('Select at most 24 disc images.')
        kind=file_kind(source)
        raw=request.get('configuration') or (existing or {}).get('configuration') or {}
        rid,program=self.runtime(raw,kind)
        if not program:
            # Keep the requested game visible without creating a prefix, mounting
            # discs, running an installer or changing system runtime packages.
            game=existing or {'id':identity,'title':request.get('title') or source.stem,'mode':'pending-installation','kind':'windows','source':str(source),'discs':images,'installer':str(request.get('installer') or source),'path':str(source),'root':str(source.parent),'status':'runtime-missing','architecture':'','configuration':self.config(raw,source.parent,kind)}
            games=self.load();games[identity]=game;self.save(games)
            return {'game':game,'runtimeMissing':True,'runtime':rid,'message':'Game saved as a pending installation. Review and explicitly approve a compatible runtime, then review the installer again. No runtime or prefix was installed.'}
        pending=existing and existing.get('mode')=='pending-installation'
        game=(existing if not pending else None) or {'id':identity,'title':request.get('title') or source.stem,'mode':'managed','kind':'windows','source':str(source),'discs':images,'path':str(source),'root':str(self.safe_state('prefixes/'+identity)/('pfx/drive_c' if rid=='proton' else 'drive_c')),'status':'needs-executable','architecture':''}
        if existing and not pending:
            self.game_root(existing)
            if rid!=existing.get('configuration',{}).get('runtime'):raise ValueError('Choose the existing prefix runtime family or create a separate installation.')
        prefix=self.safe_state('prefixes/'+identity);prefix.mkdir(parents=True,mode=0o700,exist_ok=True)
        game_root=Path(game['root']);game_root.mkdir(parents=True,exist_ok=True)
        game['configuration']=self.config(raw,game_root,kind)
        game['configuration'].update(prefix=str(prefix/'pfx') if rid=='proton' else str(prefix),compatDataPath=str(prefix))
        if not existing or pending:game['installer']=str(request.get('installer') or source)
        games=self.load();games[identity]=game;self.save(games)
        before_inventory=self.inventory(game_root)
        mounts=[];code=None
        try:
            for image in images:
                mounted=self.mount(image);mounts.append(mounted)
            installer=source
            if mounts:
                relative=Path(request.get('installer') or '')
                if relative.is_absolute() or '..' in relative.parts or str(relative)=='.':raise ValueError('Choose one installer from the mounted-disc candidates.')
                installer=(mounts[0]/relative).resolve(strict=True)
                if not installer.is_relative_to(mounts[0]):raise ValueError('Installer escapes the selected read-only disc.')
            installer_kind=file_kind(installer)
            if installer_kind not in ('exe','msi'):raise ValueError('Select a Windows EXE or MSI installer.')
            dosdevices=self.prepare_wine_drives(prefix/'pfx' if rid=='proton' else prefix)
            for i,mount in enumerate(mounts):
                link=dosdevices/(chr(ord('d')+i)+':')
                if link.exists() or link.is_symlink():
                    if not link.is_symlink():raise ValueError('A Wine disc mapping is occupied by a real file.')
                    link.unlink()
                link.symlink_to(mount)
            mode=request.get('mode','install')
            if mode not in ('install','reinstall','repair','uninstall'):raise ValueError('Unknown installer operation.')
            if installer_kind=='msi':arguments=['msiexec',{'uninstall':'/x'}.get(mode,'/i'),str(installer)]
            else:arguments=[str(installer)]
            installer_arguments=request.get('installerArguments',[])
            if not isinstance(installer_arguments,list):raise ValueError('Installer arguments must be an array of strings.')
            arguments+=installer_arguments
            if installer_kind=='msi' and not any(str(a).lower().startswith('/l') for a in installer_arguments):
                msi_log=self.safe_state('runtime/'+identity+'/msi-install.log')
                msi_log.parent.mkdir(parents=True,exist_ok=True)
                arguments+=['/L*V','Z:'+str(msi_log).replace('/','\\')]
            if any(not isinstance(a,str) or len(a)>4096 or '\0' in a for a in arguments) or len(arguments)>64:raise ValueError('Invalid installer arguments.')
            # Wine 10's /f path calls the product-code API with a filename.
            # MSI maintenance properties support the actual package path.
            if installer_kind=='msi' and mode in ('repair','reinstall'):
                arguments+=['REINSTALL=ALL','REINSTALLMODE='+('amus' if mode=='repair' else 'vomus')]
            if rid=='proton':arguments=['waitforexitandrun',*arguments]
            binds=[installer.parent,*mounts]
            control=self.safe_state('runtime/'+identity+'/installer-input')
            control.parent.mkdir(parents=True,exist_ok=True);atomic(control,b'')
            host=Path(__file__).resolve().parent/'GeminiInstallerHost.exe'
            if not host.is_file():raise ValueError('The signed Games installer input host is missing.')
            def windows_path(path):return 'Z:'+str(path).replace('/','\\')
            if rid=='wine':
                arguments=[str(host),windows_path(control),*[windows_path(a) if a.startswith('/') and Path(a).exists() else a for a in arguments]]
                binds.append(host.parent)
            args,env,prefix=self.sandbox(game,program,arguments,binds,installer=True)
            log=self.safe_state('runtime/'+identity+'/installer.log')
            emit(event='progress',stage='Installing',detail='The installer is running in this game’s isolated prefix. Mounted discs stay read-only until it finishes.',gameId=identity,log=str(log),indeterminate=True,discs=[str(p) for p in mounts])
            signal.signal(signal.SIGTERM,self.cancel);signal.signal(signal.SIGINT,self.cancel)
            with log.open('ab') as output:
                self.child=subprocess.Popen(args,cwd=installer.parent,stdout=output,stderr=output,start_new_session=True,close_fds=True)
                started=time.monotonic();last=0;term_at=None
                # Non-blocking cancellation commands from the native manager.
                selector=selectors.DefaultSelector()
                try:selector.register(sys.stdin,selectors.EVENT_READ)
                except (ValueError,PermissionError):pass
                while self.child.poll() is None:
                    for key,_ in selector.select(timeout=.1):
                        line=key.fileobj.readline()
                        if not line:selector.unregister(key.fileobj);continue
                        try:command=json.loads(line)
                        except ValueError:continue
                        if command.get('action')=='cancel':self.cancel()
                        elif command.get('action')=='controller' and rid=='wine':
                            action=command.get('control','')
                            if action in ('primary','up','down','left','right','l1','r1'):
                                with control.open('a') as handle:handle.write(action+'\n')
                            elif action=='text':
                                text=command.get('text','')
                                if isinstance(text,str) and len(text)<=4096:
                                    with control.open('a') as handle:handle.write('text:'+text.encode('utf-8').hex()+'\n')
                    if self.cancelled:
                        if term_at is None:term_at=time.monotonic()
                        elif time.monotonic()-term_at>8:
                            with contextlib.suppress(ProcessLookupError):os.killpg(self.child.pid,signal.SIGKILL)
                    now=time.monotonic()
                    if now-last>=1:
                        emit(event='progress',stage='Cancelling' if self.cancelled else 'Installing',detail='Elapsed '+str(int(now-started))+' seconds. Installer output is recorded in '+str(log),indeterminate=True,log=str(log));last=now
                selector.close();code=self.child.wait()
            emit(event='progress',stage='Indexing installed files',detail='Recording exact application-owned files for safe uninstall; saves remain separate.',indeterminate=True)
            after_inventory=self.inventory(game_root)
            prior_owned=game.get('installedFiles',{})
            game['installedFiles']={path:row for path,row in after_inventory.items() if path not in before_inventory or path in prior_owned}
            game['lastInstallExitCode']=code;game['lastInstallOperation']=mode
            game['status']='cancelled' if self.cancelled else 'installed-awaiting-selection' if code==0 else 'installation-failed'
            if mode=='uninstall' and code==0:game['status']='uninstaller-completed-files-retained'
            candidates=self.discover_executables(game_root)
            if code==0 and mode!='uninstall' and len(candidates)==1:
                game.update(path=candidates[0]['path'],architecture=candidates[0]['architecture'],status='ready')
                game['configuration']['workingDirectory']=str(Path(game['path']).parent)
            games=self.load();games[identity]=game;self.save(games)
            return {'game':game,'candidates':candidates,'installerExitCode':code,'cancelled':self.cancelled,'success':code==0 and not self.cancelled,'message':'Installation finished; select the launch executable.' if code==0 else 'Installation cancelled; prefix retained for repair.' if self.cancelled else 'Installer failed. Review the installer log; files and saves are retained.','log':str(log)}
        finally:
            if self.child and self.child.poll() is None:
                self.cancel()
                try:self.child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    with contextlib.suppress(ProcessLookupError):os.killpg(self.child.pid,signal.SIGKILL)
                    self.child.wait()
            if 'control' in locals():control.unlink(missing_ok=True)
            self.cleanup()

    def remove(self,request):
        if request.get('approved') is not True:raise ValueError('Explicit library removal approval is required.')
        games=self.load();game=self.game(request['id']);del games[game['id']];self.save(games)
        return {'removedId':game['id'],'message':'Removed from the Games library. Original files, installation prefixes, patch backups and user saves are retained.'}

    def patch_preview(self,request):
        game=self.game(request['id']);root=self.game_root(game)
        source=self.authorized(request['source']);target=self.authorized(request['target'],writable=True)
        if not target.is_relative_to(root) or target==source:raise ValueError('Patch target must be an existing file inside this game folder, separate from the local patch file.')
        if target.is_symlink() or source.is_symlink():raise ValueError('Patch symlinks are not supported.')
        preview={'id':game['id'],'source':str(source),'target':str(target),'originalSHA256':digest(target),'patchSHA256':digest(source),'size':source.stat().st_size,'warning':'Untrusted replacement files may execute code. Only apply a local patch you trust. Security remains enabled.'}
        preview['token']=hashlib.sha256(json.dumps(preview,sort_keys=True).encode()).hexdigest()
        return {'preview':preview}

    def patch_apply(self,request):
        if request.get('approved') is not True:raise ValueError('Explicit patch confirmation is required.')
        preview=self.patch_preview(request)['preview']
        if request.get('token')!=preview['token']:raise ValueError('Patch or target changed after review. Review the files again before confirming.')
        original=Path(preview['target']).read_bytes();replacement=Path(preview['source']).read_bytes()
        if hashlib.sha256(original).hexdigest()!=preview['originalSHA256'] or hashlib.sha256(replacement).hexdigest()!=preview['patchSHA256']:raise ValueError('Patch content changed after review. Review the files again.')
        key=hashlib.sha256(preview['target'].encode()).hexdigest();directory=self.safe_state('patches/'+preview['id']+'/'+key);directory.mkdir(parents=True,mode=0o700,exist_ok=True)
        metadata=directory/'patch.json';backup=directory/'original'
        if metadata.exists():
            previous=json.loads(metadata.read_text())
            if previous.get('active'):raise ValueError('Restore the active patch before replacing it.')
            if digest(backup)!=previous['originalSHA256']:raise ValueError('Original patch backup is damaged.')
            if digest(preview['target'])!=previous['originalSHA256']:raise ValueError('Game changed since the previous rollback. Choose a new installation before applying this patch.')
        else:
            target=Path(preview['target']);atomic(backup,original,target.stat().st_mode&0o777)
        meta={**preview,'backup':str(backup),'active':False,'mode':Path(preview['target']).stat().st_mode&0o777}
        jsonwrite(metadata,meta)
        atomic(preview['target'],replacement,meta['mode'])
        meta['active']=True;jsonwrite(metadata,meta)
        return {'patch':meta,'message':'Local patch applied. Original retained for rollback.'}

    def patch_restore(self,request):
        if request.get('approved') is not True:raise ValueError('Explicit patch rollback confirmation is required.')
        game=self.game(request['id']);root=self.game_root(game);target=self.authorized(request['target'],writable=True)
        if not target.is_relative_to(root):raise ValueError('Rollback target is outside this game.')
        key=hashlib.sha256(str(target).encode()).hexdigest();directory=self.safe_state('patches/'+game['id']+'/'+key)
        meta=json.loads((directory/'patch.json').read_text());backup=directory/'original'
        if meta['target']!=str(target) or digest(backup)!=meta['originalSHA256']:raise ValueError('Patch backup verification failed.')
        if digest(target)!=meta['patchSHA256']:raise ValueError('Patched file changed since application. Restore is blocked to preserve those changes.')
        atomic(target,backup.read_bytes(),meta['mode']);meta['active']=False;jsonwrite(directory/'patch.json',meta)
        return {'message':'Original game file restored and verified.','restoredSHA256':digest(target)}

    def patches(self,identity):
        self.game(identity);root=self.safe_state('patches/'+identity)
        return [json.loads(p.read_text()) for p in root.glob('*/patch.json')] if root.exists() else []

    def status(self,request):
        return {'games':list(self.load().values()),'runtimes':self.discover(),
                'environmentOptions':sorted(ENVIRONMENT),'noAutomaticRuntimeInstallation':True}

    def dispatch(self,request):
        action=request.get('action')
        handlers={'status':self.status,'browse':lambda r:self.browse(r.get('path','')),'inspect':self.inspect,
                  'import':self.register,'configure':self.configure,'install':self.install,'remove':self.remove,
                  'patch-preview':self.patch_preview,'patch-apply':self.patch_apply,'patch-restore':self.patch_restore,
                  'patches':lambda r:{'patches':self.patches(r['id'])},'uninstall-plan':self.uninstall_plan,'uninstall':self.uninstall}
        if action not in handlers:raise ValueError('Unsupported Games operation.')
        lock=self.safe_state('installations.lock')
        with lock.open('a') as handle:
            fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
            return handlers[action](request)


def fuse_owner(args):
    parent=int(args[0]);point=Path(args[1]);assert args[2]=='--'
    if os.getppid()!=parent:return 1
    stopping=False
    def stop(*_):
        nonlocal stopping
        stopping=True
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    child=subprocess.Popen(args[3:],close_fds=True)
    try:
        while child.poll() is None and os.getppid()==parent and not stopping:time.sleep(.1)
        unmount=shutil.which('fusermount') or shutil.which('fusermount3')
        for _ in range(100):
            if mount_options(point) is None:break
            if unmount and execute([unmount,'-u',str(point)]).returncode==0:break
            time.sleep(.1)
    finally:
        if child.poll() is None:
            child.terminate()
            try:child.wait(timeout=5)
            except subprocess.TimeoutExpired:child.kill();child.wait()
        with contextlib.suppress(OSError):point.rmdir()
        if point.parent.name.startswith('neutronos-games-'):
            with contextlib.suppress(OSError):point.parent.rmdir()
    return child.returncode


def prefix_run(args):
    home,prefix_text,separator,program,*command=args
    if separator!='--' or program!=shutil.which('bwrap'):raise ValueError('Unsupported private runtime runner.')
    manager=Manager(home);prefix=Path(prefix_text)
    relative=prefix.relative_to(manager.state)
    if len(relative.parts)!=2 or relative.parts[0]!='prefixes' or not re.fullmatch(r'[a-f0-9]{64}',relative.parts[1]):raise ValueError('Runtime prefix must belong to this game.')
    try:
        view=manager.prefix_view(prefix)
        for i in range(len(command)-2):
            if command[i]=='--bind' and Path(command[i+1]).is_relative_to(prefix):
                command[i+1]=str(view/Path(command[i+1]).relative_to(prefix))
        delimiter=command.index('--');runtime=command[delimiter+1]
        if Path(runtime).name in RUNTIMES['wine']:
            server=Path(runtime).parent/'wineserver'
            if not server.is_file() and str(Path(runtime).resolve()).startswith('/usr/'):
                server=Path(shutil.which('wineserver') or str(server))
            if not server.is_file():raise ValueError('Matching wineserver is unavailable.')
            runner=str(Path(__file__).resolve())
            command[delimiter:]=['--ro-bind',runner,runner,'--','/usr/bin/python3',runner,'--wait-wine',str(server),*command[delimiter+1:]]
        child=subprocess.Popen([program,*command],close_fds=True)
        def cancel(*_):
            if child.poll() is None:child.terminate()
        signal.signal(signal.SIGTERM,cancel);signal.signal(signal.SIGINT,cancel)
        return child.wait()
    finally:manager.cleanup()


def wait_wine(args):
    server,program,*arguments=args
    child=subprocess.Popen([program,*arguments],close_fds=True)
    cancelled=False
    def cancel(*_):
        nonlocal cancelled
        cancelled=True
        subprocess.run([server,'-k'],check=False)
        if child.poll() is None:child.terminate()
    signal.signal(signal.SIGTERM,cancel);signal.signal(signal.SIGINT,cancel)
    code=child.wait()
    waiter=subprocess.run([server,'-w'],check=False)
    return 130 if cancelled else code if code else waiter.returncode


def main():
    if len(sys.argv)>1 and sys.argv[1]=='--wait-wine':return wait_wine(sys.argv[2:])
    if len(sys.argv)>1 and sys.argv[1]=='--fuse-owner':return fuse_owner(sys.argv[2:])
    if len(sys.argv)>1 and sys.argv[1]=='--prefix-run':
        if os.geteuid()==0:raise ValueError('Games runtime cannot run as root.')
        return prefix_run(sys.argv[2:])
    parser=argparse.ArgumentParser();parser.add_argument('--home',required=True);args=parser.parse_args()
    if os.geteuid()==0:raise ValueError('Games installation and patch operations cannot run as root.')
    raw=sys.stdin.readline(1048577)
    if len(raw)>1048576:raise ValueError('Games request is too large.')
    request=json.loads(raw);manager=Manager(args.home)
    try:
        result=manager.dispatch(request)
        result.setdefault('success',True);emit(event='result',**result)
        return 0 if result['success'] else 1
    except (ValueError,OSError,RuntimeError,subprocess.SubprocessError) as exc:
        emit(event='result',success=False,message=str(exc));return 1
    finally:manager.cleanup()

if __name__=='__main__':
    try:raise SystemExit(main())
    except (ValueError,OSError) as exc:emit(event='result',success=False,message=str(exc));raise SystemExit(1)
