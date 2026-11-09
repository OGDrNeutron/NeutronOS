"""NeutronOS Gemini Manager: private FastAPI API behind Tailscale-only Nginx mTLS.

NEVER expose this service directly to the Internet. Deploy on a loopback port;
Nginx MUST require valid client certificates and reject non-tailnet clients.
"""
from __future__ import annotations

import asyncio
import hmac
import json
import os
import pty
import re
import secrets
import shutil
import signal
import socket
import subprocess
import time
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile, WebSocket
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from starlette.websockets import WebSocketDisconnect

HOSTNAME = os.getenv('MANAGER_HOSTNAME', 'neutronos.neutronprojects.com').lower()
BASE = Path(__file__).resolve().parent.parent
WEB = BASE / 'web'
IDLE_SECONDS = 1800
MAX_UPLOAD = 128 * 1024 * 1024
SESSIONS: dict[str,dict] = {}
MEDIA = Path('/NeutronMedia')
USER_DATA = Path(os.getenv('MANAGER_USER_DATA_PATH','/NeutronOS/drneutron'))
ROOTS = (MEDIA, Path(os.getenv('MANAGER_FILES_HOME', '/var/lib/neutron-manager')))

# Only fixed, explicitly recognized service identifiers are controllable.
SERVICES = {
    'jellyfin': ('Jellyfin', 'docker', 'jellyfin', 'Media Server · Movies · Shows · Live', 'play', 'purple'),
    'qbittorrent': ('qBittorrent', 'docker', 'qbittorrent', 'Torrents · Downloads · Automation', 'download', 'blue'),
    'torrentlab': ('TorrentLab', 'systemd', 'torrentlab2.service', 'Media Tools · Convert · Subtitles · Metadata', 'flask', 'red'),
    'neutronstream': ('NeutronStream', 'systemd', 'neutronstream.service', 'Streaming · Remote Access · Live', 'pc', 'cyan'),
    'neutronai': ('NeutronAI', 'systemd', 'neutronllm-http.service', 'Qwen · Ornith · DeepSeek', 'atom', 'red'),
}
# Docker service identity names can be overridden after local verification.
DOCKER_NAMES = {id: os.getenv('MANAGER_CONTAINER_'+id.upper(), unit) for id,(_,kind,unit,*_) in SERVICES.items() if kind=='docker'}

PROXY_SECRET = os.getenv('MANAGER_PROXY_SECRET', '')
READ_ONLY = os.getenv('MANAGER_READ_ONLY','1') != '0'
app = FastAPI(docs_url=None,redoc_url=None,openapi_url=None)

def trusted_proxy(headers):
    supplied = headers.get('x-neutron-proxy-secret', '')
    return (len(PROXY_SECRET) >= 32 and
            len(supplied) == len(PROXY_SECRET) and
            hmac.compare_digest(PROXY_SECRET, supplied) and
            headers.get('x-neutron-client-verified', '') == 'SUCCESS')

def require_mutations_enabled():
    if READ_ONLY:
        denied('Administration is locked pending verified deployment', 403)



def denied(reason='Permission denied',code=403):
    raise HTTPException(code,reason)


def run(argv, timeout=5):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def output(argv, timeout=5):
    result = run(argv,timeout)
    return result.stdout.strip() if result and result.returncode==0 else ''


def session_for(request):
    token=request.cookies.get('__Host-nm','')
    session=SESSIONS.get(token)
    if session and time.monotonic()-session['last']<IDLE_SECONDS:
        return token,session
    SESSIONS.pop(token,None)
    return None,None


def verify(request: Request,write=False):
    # Nginx MUST exclusively bind Tailnet HTTPS and perform mTLS. This further
    # requires its non-client-configurable mTLS verification header.
    peer=request.client.host if request.client else ''
    host=request.headers.get('host','').split(':')[0].lower()
    if peer not in ('127.0.0.1','::1') or host!=HOSTNAME:
        denied()
    if not trusted_proxy(request.headers):
        denied('Verified client certificate and trusted ingress required')
    if request.method not in ('GET','HEAD'):
        origin=request.headers.get('origin','')
        if origin!=f'https://{HOSTNAME}':
            denied('Origin check failed')
    token,session=session_for(request)
    if not session:
        denied('Session expired',401)
    if write:
        supplied=request.headers.get('x-csrf-token','')
        if not hmac.compare_digest(session['csrf'],supplied):
            denied('CSRF check failed')
        session['last']=time.monotonic()
    return token,session


def verify_entry(request: Request):
    peer=request.client.host if request.client else ''
    host=request.headers.get('host','').split(':')[0].lower()
    if peer not in ('127.0.0.1','::1') or host!=HOSTNAME or not trusted_proxy(request.headers):
        denied()


@app.middleware('http')
async def security_headers(request: Request,call_next):
    response=await call_next(request)
    response.headers['Cache-Control']='no-store'
    response.headers['X-Content-Type-Options']='nosniff'
    response.headers['Referrer-Policy']='no-referrer'
    response.headers['X-Frame-Options']='DENY'
    response.headers['Permissions-Policy']='camera=(), microphone=(), geolocation=()'
    response.headers['Content-Security-Policy']=(
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
        "connect-src 'self' wss:; font-src 'self'; object-src 'none'; frame-ancestors 'none'; "
        "base-uri 'none'; form-action 'self'")
    return response


@app.get('/api/session')
async def get_session(request: Request):
    verify_entry(request)
    token,session=session_for(request)
    if session is None:
        token=secrets.token_urlsafe(48)
        session={'csrf':secrets.token_urlsafe(32),'last':time.monotonic()}
        SESSIONS[token]=session
    response=JSONResponse({'csrf':session['csrf'],'idle_timeout_seconds':IDLE_SECONDS})
    response.set_cookie('__Host-nm',token,max_age=IDLE_SECONDS,path='/',
                        secure=True,httponly=True,samesite='strict')
    return response


@app.post('/api/activity')
async def activity(request: Request):
    token,_=verify(request,write=True)
    response=JSONResponse({'ok':True})
    response.set_cookie('__Host-nm',token,max_age=IDLE_SECONDS,path='/',
                        secure=True,httponly=True,samesite='strict')
    return response


def meminfo():
    items={}
    with open('/proc/meminfo',encoding='utf-8') as f:
        for line in f:
            name,_,value=line.partition(':')
            items[name]=int(value.strip().split()[0])*1024
    return items


def disk_gb(root:Path):
    if not root.exists():
        return 0.,0.
    u=shutil.disk_usage(root)
    return round(u.used/1e9,1),round(u.total/1e9,1)


def uptime():
    try:
        sec=int(float(Path('/proc/uptime').read_text().split()[0]))
        d,r=divmod(sec,86400)
        h,r=divmod(r,3600)
        m=r//60
        return f'{d} days, {h} hours' if d else f'{h} hours, {m} min'
    except Exception:
        return 'Unavailable'


def cpu_snapshot():
    values=Path('/proc/stat').read_text().splitlines()[0].split()[1:]
    nums=[int(v) for v in values]
    return sum(nums),nums[3]+nums[4]


def cpu_model():
    try:
        for line in Path('/proc/cpuinfo').read_text().splitlines():
            if line.startswith('model name'):
                return line.partition(':')[2].strip()
    except OSError:
        pass
    return 'Unavailable'


@app.get('/api/status')
async def status(request:Request):
    verify(request)
    mem=meminfo()
    used=mem['MemTotal']-mem.get('MemAvailable',0)
    a=cpu_snapshot()
    await asyncio.sleep(.12)
    b=cpu_snapshot()
    delta_total=b[0]-a[0]
    pct=max(0,min(100,round(100*(1-(b[1]-a[1])/delta_total)))) if delta_total>0 else 0
    user_used,user_total=disk_gb(USER_DATA)
    # Critical: don't measure the unmounted /NeutronMedia directory as if it were the drive.
    media_mount=MEDIA.is_mount()
    media_used,media_total=(disk_gb(MEDIA) if media_mount else (0,0))
    gpu=output(['/usr/bin/lspci'],3)
    gpu_lines=[v.strip() for v in gpu.splitlines() if 'VGA compatible' in v or 'Display controller' in v]
    kernel=output(['/usr/bin/uname','-r']) or os.uname().release
    ip=output(['/usr/bin/tailscale','ip','-4'],3) or 'Unavailable'
    try:
        import platform
        architecture=platform.machine()
    except Exception:
        architecture='Unknown'
    try:
        avgs=os.getloadavg()
        load=' / '.join(f'{v:.2f}' for v in avgs)
    except Exception:
        load='Unavailable'
    memory_gb=mem['MemTotal']/1e9
    return {
        'read_only':READ_ONLY,
        'name':'Gemini','version':os.getenv('MANAGER_OS_VERSION','NeutronOS Gemini'),
        'os':'NeutronOS Gemini','online':True,'cpu_pct':pct,
        'ram_used_gb':round(used/1e9,1),'ram_total_gb':round(memory_gb,1),
        'user_used_gb':user_used,'user_total_gb':user_total,
        'media_used_tb':round(media_used/1e12,2),'media_total_tb':round(media_total/1e12,2),
        'media_mounted':media_mount,'kernel':kernel,'uptime':uptime(),
        'cpu_model':cpu_model(),'gpu':gpu_lines[0].split(': ',1)[-1] if gpu_lines else 'Unavailable',
        'cores':f'{os.cpu_count()} logical threads','architecture':architecture,'ip':ip,
        'local_ip':os.getenv('MANAGER_LAN_IP','Unavailable'),'load':load,
        'swap':f'{(mem.get("SwapTotal",0)-mem.get("SwapFree",0))/1e9:.1f} / {mem.get("SwapTotal",0)/1e9:.1f} GB',
        'power_enabled':os.getenv('MANAGER_ENABLE_POWER')=='1',
    }


def service_state(id,kind,unit):
    if kind=='docker':
        name=DOCKER_NAMES[id]
        if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}',name):
            return 'unavailable'
        result=run(['/usr/bin/sudo','-n','/usr/bin/docker','inspect','--format','{{.State.Status}}',name],4)
        if result and result.returncode==0:
            return result.stdout.strip().lower()
        return 'unavailable'
    # NeutronStream may use another unit, set MANAGER_STREAM_SERVICE locally.
    if id=='neutronstream':
        unit=os.getenv('MANAGER_STREAM_SERVICE',unit)
    result=run(['/usr/bin/systemctl','is-active',unit],4)
    state=result.stdout.strip().lower() if result else 'unavailable'
    if id=='neutronstream' and state!='active':
        # Earlier Gemini installation runs NeutronStream on TCP 8765 without
        # necessarily having a neutronstream.service systemd unit.
        try:
            with socket.create_connection(('127.0.0.1',8765),timeout=.25):
                return 'running'
        except OSError:
            pass
    return state


@app.get('/api/services')
async def services(request:Request):
    verify(request)
    result=[]
    for id,(name,kind,unit,summary,icon,color) in SERVICES.items():
        result.append({'id':id,'name':name,'kind':kind,'unit':unit,
                       'summary':summary,'icon':icon,'color':color,
                       'state':service_state(id,kind,unit)})
    return result


@app.post('/api/services/{identifier}/{action}')
async def service_action(identifier:str,action:str,request:Request):
    verify(request,write=True)
    require_mutations_enabled()
    if identifier not in SERVICES or action not in ('start','stop','restart'):
        denied('Unknown service or operation')
    name,kind,unit,*_=SERVICES[identifier]
    if kind=='docker':
        container=DOCKER_NAMES[identifier]
        cmd=['/usr/bin/sudo','-n','/usr/bin/docker',action,container]
    else:
        if identifier=='neutronstream':
            unit=os.getenv('MANAGER_STREAM_SERVICE','')
            if not unit or not re.fullmatch(r'[a-zA-Z0-9_.@-]+\.service',unit):
                denied('NeutronStream service unit not configured')
        cmd=['/usr/bin/sudo','-n','/usr/bin/systemctl',action,unit]
    result=run(cmd,30)
    if not result or result.returncode!=0:
        denied((result.stderr.strip() if result else 'Operation unavailable')[:250],409)
    return {'ok':True}


APP_STYLES={
 'neutronai':('NeutronAI','atom','red'), 'torrentlab':('TorrentLab','flask','green'),
 'games':('Games','play','blue'), 'jellyfin':('Jellyfin','play','violet'),
 'qbittorrent':('qBittorrent','download','cyan'),
 'neutronstream':('NeutronStream','pc','cyan'), 'browser':('Browser','globe','blue'),
 'terminal':('Terminal','term','violet'), 'files':('Files / SFTP','folder','cyan'),
 'settings':('Settings','gear','red'),'store':('App Store','stack','green'),
 'security':('Security','shield','violet'),'remote':('Remote Systems','pc','cyan'),
 'docker':('Docker','cube','blue'),'controller':('Controllers','gear','red'),
}


@app.get('/api/apps')
async def apps(request:Request):
    verify(request)
    # Shallow directory scan only, no indexing of game files or media libraries.
    found=set()
    for root in (Path('/NeutronOS/qml/apps'),Path('/NeutronOS/drneutron/apps')):
        if root.is_dir():
            for entry in root.iterdir():
                if entry.is_dir() and re.fullmatch('[a-zA-Z0-9._-]{1,80}',entry.name):
                    found.add(entry.name.lower())
    found.update(['neutronai','torrentlab','jellyfin','qbittorrent','neutronstream','terminal','files','docker'])
    ordered=list(dict.fromkeys([*APP_STYLES.keys(),*sorted(found)]))
    result=[]
    for identifier in ordered:
        label,ico,color=APP_STYLES.get(identifier,(identifier.replace('-',' ').title(),'gear','blue'))
        result.append({'id':identifier,'name':label,'icon':ico,'color':color,'installed':identifier in found})
    return result


@app.get('/api/tools')
async def tool_urls(request:Request):
    verify(request)
    result={}
    for id in (*APP_STYLES.keys(), 'sftp'):
        value=os.getenv('MANAGER_TOOL_'+id.upper().replace('-','_'),'').strip()
        # Only same-origin relative routes or HTTPS urls to approved Neutron Projects domains.
        if value.startswith('/') and not value.startswith('//') and '\\' not in value:
            result[id]=value
        elif value.startswith('https://') and re.fullmatch(r'https://[a-zA-Z0-9.-]+(?::[0-9]{1,5})?(/[a-zA-Z0-9_./%+-]*)?',value):
            host=value[8:].split('/',1)[0].split(':')[0].lower()
            if host=='neutronos.neutronprojects.com' or host.endswith('.neutronprojects.com'):
                result[id]=value
    return result


class PowerRequest(BaseModel):
    action:str


@app.post('/api/system/power')
async def power(request:Request,payload:PowerRequest):
    verify(request,write=True)
    require_mutations_enabled()
    if os.getenv('MANAGER_ENABLE_POWER')!='1':
        denied('Remote power controls are disabled')
    action=payload.action
    if action=='shell':
        unit=os.getenv('MANAGER_SHELL_SERVICE','')
        if not unit or not re.fullmatch(r'neutron[a-zA-Z0-9_-]*\.service',unit):
            denied('Shell service not approved',400)
        cmd=['/usr/bin/sudo','-n','/usr/bin/systemctl','restart',unit]
    elif action=='reboot':
        cmd=['/usr/bin/sudo','-n','/usr/bin/systemctl','reboot']
    elif action=='shutdown':
        cmd=['/usr/bin/sudo','-n','/usr/bin/systemctl','poweroff']
    else:
        denied('Unrecognized power action',400)
    result=run(cmd,10)
    if not result or result.returncode!=0:
        denied((result.stderr.strip() if result else 'Power operation unavailable')[:250] or 'Power operation blocked',409)
    return {'ok':True}


def file_path(raw:str,strict:bool=True):
    if not raw.startswith('/'):
        denied('Absolute path required')
    rawpath=Path(raw)
    if MEDIA in rawpath.parents or rawpath==MEDIA:
        if not MEDIA.is_mount():
            denied('NeutronMedia not mounted',503)
    try:
        path=rawpath.resolve(strict=strict)
    except (OSError,RuntimeError):
        denied('Invalid path',400)
    if not any(path==root or root in path.parents for root in ROOTS):
        denied('Outside allowed file roots')
    return path


@app.get('/api/files')
async def files(request:Request,path:str='/NeutronMedia'):
    verify(request)
    folder=file_path(path)
    if not folder.is_dir():
        denied('Not a directory',400)
    try:
        entries=[]
        for entry in sorted(folder.iterdir(),key=lambda a:(not a.is_dir(),a.name.lower()))[:500]:
            try:
                resolved=file_path(str(entry))
                entries.append({'name':entry.name,'directory':resolved.is_dir(),
                                'path':str(resolved),'size':resolved.stat().st_size if resolved.is_file() else 0})
            except (HTTPException,OSError):
                pass
        return {'path':str(folder),'entries':entries}
    except OSError:
        denied('Folder access denied',403)


@app.get('/api/download')
async def download(request:Request,path:str):
    verify(request)
    target=file_path(path)
    if not target.is_file():
        denied('Not a regular file',400)
    return FileResponse(target,media_type='application/octet-stream',filename=target.name)


@app.post('/api/upload')
async def upload(request:Request,path:str=Form(...),file:UploadFile=File(...)):
    verify(request,write=True)
    require_mutations_enabled()
    folder=file_path(path)
    if not folder.is_dir():
        denied('Invalid upload directory',400)
    filename=Path(file.filename or '').name
    if not filename or filename in ('.','..'):
        denied('Invalid filename',400)
    target=folder/filename
    try:
        fd=os.open(target,os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
    except FileExistsError:
        denied('File already exists',409)
    except OSError:
        denied('Folder is not writable',403)
    count=0
    try:
        with os.fdopen(fd,'wb') as out:
            while True:
                chunk=await file.read(65536)
                if not chunk:
                    break
                count+=len(chunk)
                if count>MAX_UPLOAD:
                    denied('Upload exceeds 128 MB',413)
                out.write(chunk)
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    return {'ok':True,'size':count}


@app.websocket('/api/terminal')
async def terminal(ws:WebSocket):
    peer=ws.client.host if ws.client else ''
    token=ws.cookies.get('__Host-nm','')
    entry=SESSIONS.get(token)
    if (peer not in ('127.0.0.1','::1') or ws.headers.get('host','').split(':')[0].lower()!=HOSTNAME
        or ws.headers.get('origin','')!=f'https://{HOSTNAME}'
        or not trusted_proxy(ws.headers) or READ_ONLY
        or not entry or time.monotonic()-entry['last']>=IDLE_SECONDS):
        await ws.close(code=1008)
        return
    await ws.accept()
    try:
        hello=await asyncio.wait_for(ws.receive_text(),timeout=10)
        auth=json.loads(hello)
        if (not isinstance(auth,dict) or auth.get('type')!='auth'
            or not isinstance(auth.get('csrf'),str)
            or not hmac.compare_digest(auth['csrf'],entry['csrf'])):
            await ws.close(code=1008)
            return
    except (ValueError,asyncio.TimeoutError,WebSocketDisconnect):
        await ws.close(code=1008)
        return
    pid,fd=pty.fork()
    if pid==0:
        os.chdir(str(Path.home()))
        os.execv('/bin/bash',['/bin/bash','--noprofile','--norc','-i'])
    async def writer():
        while True:
            chunk=await asyncio.to_thread(os.read,fd,4096)
            if not chunk:return
            await ws.send_text(chunk.decode('utf-8','replace'))
    async def reader():
        while True:
            chunk=await ws.receive_text()
            if len(chunk)>8192:
                await ws.close(code=1009)
                return
            entry['last']=time.monotonic()
            await asyncio.to_thread(os.write,fd,chunk.encode('utf-8'))
    async def idle_killer():
        while True:
            await asyncio.sleep(5)
            if time.monotonic()-entry['last']>=IDLE_SECONDS:
                await ws.close(code=1008)
                return
    tasks=[asyncio.create_task(x()) for x in (writer,reader,idle_killer)]
    try:
        await asyncio.wait(tasks,return_when=asyncio.FIRST_COMPLETED)
    finally:
        for task in tasks: task.cancel()
        try:os.killpg(pid,signal.SIGHUP)
        except ProcessLookupError:pass
        try:os.close(fd)
        except OSError:pass
        try:os.waitpid(pid,os.WNOHANG)
        except ChildProcessError:pass


# Nginx must also demand mTLS on the static HTML and JS before passing any requests.
app.mount('/',StaticFiles(directory=str(WEB),html=True),name='web')
