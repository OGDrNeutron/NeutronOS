#!/usr/bin/python3
"""Disposable Gemini VM only: real evdev/uinput -> SDL2, synthetic source pads.

This is runtime integration evidence, not a physical controller/game-title test.
Production discovery continues to reject all uinput sources; this harness opens
only its own explicit source fixture with production Pad, without modifying it.
"""
from pathlib import Path
import traceback,ctypes,fcntl,importlib.util,json,os,pwd,secrets,select,signal,struct,subprocess,sys,time
W=Path('/opt/neutronos/tests/controller055')
spec=importlib.util.spec_from_file_location('proxy',Path('/usr/local/lib/neutronos/neutronos-controller-proxy.py'));p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
REPORT=W/'validation/controller-sdl-runtime.json'
SNAPSHOT=W/'validation/controller-sdl-snapshot.json'
EXPECTED_TOKEN=None

def consumer():
    token=sys.argv[sys.argv.index('--token')+1]
    s=ctypes.CDLL('libSDL2-2.0.so.0')
    s.SDL_GetError.restype=ctypes.c_char_p
    s.SDL_GameControllerOpen.argtypes=[ctypes.c_int];s.SDL_GameControllerOpen.restype=ctypes.c_void_p
    s.SDL_GameControllerGetAxis.argtypes=[ctypes.c_void_p,ctypes.c_int];s.SDL_GameControllerGetAxis.restype=ctypes.c_int16
    s.SDL_GameControllerGetButton.argtypes=[ctypes.c_void_p,ctypes.c_int];s.SDL_GameControllerGetButton.restype=ctypes.c_uint8
    s.SDL_GameControllerName.argtypes=[ctypes.c_void_p];s.SDL_GameControllerName.restype=ctypes.c_char_p
    s.SDL_GameControllerGetAttached.argtypes=[ctypes.c_void_p]
    s.SDL_GameControllerClose.argtypes=[ctypes.c_void_p]
    s.SDL_SetHint.argtypes=[ctypes.c_char_p,ctypes.c_char_p]
    s.SDL_SetHint(b'SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS',b'1')
    if s.SDL_Init(0x2000|0x200|0x4000)!=0:raise RuntimeError(s.SDL_GetError())
    input_diagnostics=[]
    for node in Path('/dev/input').glob('event*'):
        try:
            fd=os.open(node,os.O_RDONLY|os.O_NONBLOCK);input_diagnostics.append({'path':str(node),'keys':p.bits(fd,p.EV_KEY,p.KEY_MAX)});os.close(fd)
        except OSError as error:input_diagnostics.append({'path':str(node),'error':str(error)})
    s.SDL_GameControllerGetJoystick.argtypes=[ctypes.c_void_p];s.SDL_GameControllerGetJoystick.restype=ctypes.c_void_p
    s.SDL_JoystickInstanceID.argtypes=[ctypes.c_void_p]
    opened=[]
    try:
        for index in range(s.SDL_NumJoysticks()):
            if s.SDL_IsGameController(index):
                device=s.SDL_GameControllerOpen(index)
                if device:opened.append(device)
        deadline=time.monotonic()+35
        while time.monotonic()<deadline:
            s.SDL_PumpEvents();s.SDL_GameControllerUpdate()
            for device in list(opened):
                if not s.SDL_GameControllerGetAttached(device):s.SDL_GameControllerClose(device);opened.remove(device)
            known={s.SDL_JoystickInstanceID(s.SDL_GameControllerGetJoystick(d)) for d in opened}
            for index in range(s.SDL_NumJoysticks()):
                if s.SDL_JoystickGetDeviceInstanceID(index) not in known and s.SDL_IsGameController(index):
                    device=s.SDL_GameControllerOpen(index)
                    if device:opened.append(device)
            state={'inputDiagnostics':input_diagnostics,'inputOwnership':[{"path":str(n),"gid":n.stat().st_gid,"mode":oct(n.stat().st_mode & 0o777)} for n in Path('/dev/input').glob('event*')],'inputNodes':[f.name for f in Path('/dev/input').glob('*')],'sdlError':s.SDL_GetError().decode(),'joysticks':s.SDL_NumJoysticks(),'gameControllers':len(opened),'pads':[{'name':s.SDL_GameControllerName(d).decode(),'axes':[s.SDL_GameControllerGetAxis(d,i) for i in range(6)],'buttons':[s.SDL_GameControllerGetButton(d,i) for i in range(15)]} for d in opened]}
            state.update(sessionToken=token,producerPid=os.getpid(),capturedMonotonic=time.monotonic())
            temp=SNAPSHOT.with_suffix('.tmp');temp.write_text(json.dumps(state));temp.replace(SNAPSHOT);time.sleep(.02)
    finally:
        for device in opened:s.SDL_GameControllerClose(device)
        s.SDL_Quit()

class Source:
    def __init__(self,number,bus=3):
        self.keys=(304,305,307,308,310,311,314,315,316,317,318)
        self.axes={0:(0,-32768,32767,0,128,0),1:(0,-32768,32767,0,128,0),2:(0,0,255,0,0,0),3:(0,-32768,32767,0,128,0),4:(0,-32768,32767,0,128,0),5:(0,0,255,0,0,0),16:(0,-1,1,0,0,0),17:(0,-1,1,0,0,0)}
        self.fd=os.open('/dev/uinput',os.O_WRONLY|os.O_NONBLOCK)
        for kind in (p.EV_KEY,p.EV_ABS):fcntl.ioctl(self.fd,p.ioc(1,'U',100,4),kind)
        for code in self.keys:fcntl.ioctl(self.fd,p.ioc(1,'U',101,4),code)
        for code,info in self.axes.items():
            fcntl.ioctl(self.fd,p.ioc(1,'U',103,4),code);value=struct.pack('H2x6i',code,*info);fcntl.ioctl(self.fd,p.ioc(1,'U',4,len(value)),value)
        name=f'Gemini fixture Xbox {number}'.encode();data=p.INPUT_ID.pack(bus,0x045e,0x028e,0x0114)+name.ljust(80,b'\0')+struct.pack('I',0)
        fcntl.ioctl(self.fd,p.ioc(1,'U',3,len(data)),data);fcntl.ioctl(self.fd,p.ioc(0,'U',1,0));data=bytearray(128);fcntl.ioctl(self.fd,p.ioc(2,'U',44,128),data,True);self.sysname=bytes(data).split(b'\0')[0].decode()
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            found=list(Path('/sys/devices/virtual/input',self.sysname).glob('event*'))
            if found and Path('/dev/input',found[0].name).exists():self.path='/dev/input/'+found[0].name;break
            time.sleep(.05)
        else:raise RuntimeError('Fixture evdev node not created')
    def send(self,events):
        for kind,code,value in events:os.write(self.fd,p.EVENT.pack(0,0,kind,code,value))
        os.write(self.fd,p.EVENT.pack(0,0,p.EV_SYN,p.SYN_REPORT,0))
    def close(self):fcntl.ioctl(self.fd,p.ioc(0,'U',2,0));os.close(self.fd)

class Sink:
    def __init__(self):self.gesture=p.Gesture();self.actions=[]
    def send(self,event):self.actions.append(event)

def snapshot():
    try:
        state=json.loads(SNAPSHOT.read_text())
        return state if EXPECTED_TOKEN is None or state.get('sessionToken')==EXPECTED_TOKEN else {}
    except (FileNotFoundError,json.JSONDecodeError):return {}
def main():
    global EXPECTED_TOKEN
    EXPECTED_TOKEN=secrets.token_hex(12)
    if os.geteuid()!=0:raise SystemExit('Run only through the existing disposable VM root test console')
    sources=[];pads=[];child=None;checks=[];samples=[];sink=Sink()
    def check(name,value):checks.append({'name':name,'passed':bool(value)})
    def forward(events,index=0):
        sources[index].send(events);deadline=time.monotonic()+.4
        while time.monotonic()<deadline:
            if select.select([pads[index].fd],[],[],.02)[0]:pads[index].read(sink)
        state=snapshot();samples.append(state);return state.get('pads',[])
    try:
        nodes=p.DEVICES;nodes.mkdir(parents=True,exist_ok=True);p.ROOT.mkdir(parents=True,exist_ok=True);os.chmod(p.ROOT,0o750);os.chmod(nodes,0o750);account=pwd.getpwnam('neutronos');os.chown(p.ROOT,0,account.pw_gid);os.chown(nodes,0,account.pw_gid)
        # Only the private test-output directory is writable by the SDL consumer.
        SNAPSHOT.parent.mkdir(parents=True,exist_ok=True);os.chown(SNAPSHOT.parent,account.pw_uid,account.pw_gid);os.chmod(SNAPSHOT.parent,0o750)
        for index in range(2):
            source=Source(index);sources.append(source);pads.append(p.Pad(source.path,index,nodes,{}));pads[-1].switch(False)
        time.sleep(.5)
        for pad in pads:pad.publish_nodes(nodes)
        # The actual game-side namespace exposes proxy input nodes exclusively.
        command=['runuser','-u','neutronos','--','env','SDL_JOYSTICK_HIDAPI=0','SDL_JOYSTICK_DISABLE_UDEV=1','bwrap','--unshare-all','--ro-bind','/usr','/usr','--symlink','usr/bin','/bin','--symlink','usr/lib','/lib','--symlink','usr/lib64','/lib64','--dev','/dev','--proc','/proc','--ro-bind','/sys','/sys','--dev-bind',str(nodes),'/dev/input','--bind',str(W),str(W),'--',sys.executable,str(Path(__file__).resolve()),'--consumer']
        command.extend(['--token',EXPECTED_TOKEN])
        child=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        deadline=time.monotonic()+5
        while time.monotonic()<deadline and snapshot().get('gameControllers',0)!=2:time.sleep(.05)
        state=snapshot();samples.append(state);check('SDL2 sees exactly two game controllers',state.get('gameControllers')==state.get('joysticks')==2)
        if not checks[-1]['passed']:raise RuntimeError('SDL controller discovery failed')
        state=forward([(p.EV_ABS,0,16384),(p.EV_ABS,1,-16384),(p.EV_ABS,3,-12000),(p.EV_ABS,4,12000),(p.EV_ABS,2,128),(p.EV_ABS,5,64)])
        a=state[0]['axes'];check('both sticks retain signed intermediate movement',a[0]>12000 and a[1]<-12000 and a[2]<-9000 and a[3]>9000);check('both triggers preserve intermediate analog values',10000<a[4]<24000 and 4000<a[5]<14000)
        state=forward([(p.EV_ABS,0,-20000)],1);check('multiplayer axes remain independent',state[0]['axes'][0]>12000 and state[1]['axes'][0]<-16000)
        for code,button in ((304,0),(305,1),(307,2),(308,3),(310,9),(311,10),(314,4),(315,6),(317,7),(318,8)):
            state=forward([(p.EV_KEY,code,1)]);check(f'evdev button {code} reaches SDL control {button}',state[0]['buttons'][button]==1);forward([(p.EV_KEY,code,0)])
        state=forward([(p.EV_ABS,16,-1),(p.EV_ABS,17,1)]);check('D-pad reaches SDL controller buttons',state[0]['buttons'][13]==state[0]['buttons'][12]==1)
        forward([(p.EV_KEY,316,1)]);check('short Home is absent from gameplay',snapshot()['pads'][0]['buttons'][5]==0 and not sink.gesture.poll(time.monotonic()))
        time.sleep(3);check('continuous three-second Home hold fires once',len(sink.gesture.poll(time.monotonic()))==1 and not sink.gesture.poll(time.monotonic()));forward([(p.EV_KEY,316,0)])
        forward([(p.EV_KEY,304,1)]);pads[0].switch(True);time.sleep(.15);state=snapshot()['pads'][0];check('modal transition releases gameplay buttons and axes',not any(state['buttons']) and all(abs(v)<=1 for v in state['axes']))
        forward([(p.EV_KEY,305,1)]);check('modal receives controller action without gameplay input',any(e.get('action')=='cancel' for e in sink.actions) and not any(snapshot()['pads'][0]['buttons']))
        pads[0].switch(False);state=forward([(p.EV_KEY,304,1)]);check('held control stays blocked after Resume',not state[0]['buttons'][0]);forward([(p.EV_KEY,304,0),(p.EV_KEY,305,0),(p.EV_ABS,0,0),(p.EV_ABS,1,0),(p.EV_ABS,2,0),(p.EV_ABS,3,0),(p.EV_ABS,4,0),(p.EV_ABS,5,0),(p.EV_ABS,16,0),(p.EV_ABS,17,0)]);state=forward([(p.EV_KEY,304,1),(p.EV_ABS,0,16000)]);check('Resume restores controls without reconnect',state[0]['buttons'][0]==1 and state[0]['axes'][0]>12000)
        identity=pads[0].identity;pads[0].close();sources[0].close();sources[0]=None
        deadline=time.monotonic()+4
        while time.monotonic()<deadline and snapshot().get('gameControllers')!=1:time.sleep(.05)
        check('SDL sees disconnection without duplicated device',snapshot().get('gameControllers')==1)
        sources[0]=Source(0,bus=5);pads[0]=p.Pad(sources[0].path,0,nodes,{});pads[0].switch(False);time.sleep(.2);pads[0].publish_nodes(nodes)
        check('transport identity remains stable',pads[0].identity==identity)
        deadline=time.monotonic()+4
        while time.monotonic()<deadline and snapshot().get('gameControllers')!=2:
            pads[0].publish_nodes(nodes);time.sleep(.05)
        samples.append({'proxyNodeOwnership':[{'path':str(n),'uid':n.stat().st_uid,'gid':n.stat().st_gid,'mode':oct(n.stat().st_mode & 0o777)} for n in nodes.glob('*')]})
        check('SDL discovers reconnected pad in private namespace',snapshot().get('gameControllers')==2)
        state=forward([(p.EV_ABS,0,14000),(p.EV_KEY,304,1)])
        check('reconnected pad restores analog and face button input',len(state)==2 and state[-1]['axes'][0]>10000 and state[-1]['buttons'][0]==1)
    except Exception as error:check('integration completed',False);samples.append({'error':str(error),'traceback':traceback.format_exc()})
    finally:
        if child:
            child.terminate()
            try:out,err=child.communicate(timeout=3)
            except subprocess.TimeoutExpired:child.kill();out,err=child.communicate()
            samples.append({'consumerExit':child.returncode,'stderr':err.decode()})
        for pad in pads:pad.close()
        for source in sources:
            if source:source.close()
        report={'passed':all(c['passed'] for c in checks),'checks':checks,'samples':samples,'environment':'Disposable Gemini VM; production Pad; actual Linux evdev/uinput and installed SDL2; bwrap game-side namespace','physicalControllerTest':False,'actualGameTitleTest':False,'productionDiscoveryReplaced':False,'testDiscovery':'Only explicit synthetic source nodes; production virtual-device rejection untouched'}
        REPORT.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':checks}));return 0 if report['passed'] else 1
def isolated_main():
    # The preserved guest shell predates the staged proxy-device ignore hook.
    # Prevent its system navigation from consuming our synthetic button events.
    # Suspend only that guest process, then destroy all fixture pads before Resume.
    if W!=Path('/tmp/gemini-games-review') or os.geteuid()!=0:
        raise RuntimeError('Synthetic integration is restricted to the disposable guest test directory')
    product=Path('/sys/class/dmi/id/product_name').read_text().strip()
    if product!='Standard PC (Q35 + ICH9, 2009)':
        raise RuntimeError('Expected existing Q35 disposable VM')
    pid=int(subprocess.check_output(['systemctl','show','neutronos.service','--property=MainPID','--value']))
    if pid<2 or Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[0]!=b'/opt/neutronos/build/NeutronShell':
        raise RuntimeError('Expected original guest shell process')
    status=Path(f'/proc/{pid}/status').read_text()
    if '\nState:\tT' in status:raise RuntimeError('Guest shell already suspended; preserve its state')
    boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    os.kill(pid,signal.SIGSTOP)
    try:
        deadline=time.monotonic()+3
        while '\nState:\tT' not in Path(f'/proc/{pid}/status').read_text():
            if time.monotonic()>deadline:raise RuntimeError('Guest shell did not suspend')
            time.sleep(.02)
        result=main()
    finally:
        os.kill(pid,signal.SIGCONT)
    stable=Path('/proc/sys/kernel/random/boot_id').read_text().strip()==boot
    report=json.loads(REPORT.read_text())
    report.update(sessionToken=EXPECTED_TOKEN,guestShellIsolation={'pid':pid,'mechanism':'SIGSTOP only the disposable guest NeutronShell during synthetic pad lifetime; SIGCONT after pad destruction','restored':True,'bootId':boot,'bootUnchanged':stable,'serviceRestarted':False,'physicalDevicesTouched':False})
    report['passed']=report['passed'] and stable
    REPORT.write_text(json.dumps(report,indent=2)+'\n')
    return result if stable else 1
if __name__=='__main__':
    assert Path('/sys/class/dmi/id/product_name').read_text().strip()=='Standard PC (Q35 + ICH9, 2009)'
    raise SystemExit(consumer() if '--consumer' in sys.argv else main())
