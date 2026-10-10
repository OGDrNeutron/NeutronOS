#!/usr/bin/python3
"""Gemini-only evdev -> uinput gamepad service. Never synthesizes keyboard keys.

Socket commands may only switch an already connected gamepad's input ownership;
there is no subprocess execution, package installation, or arbitrary file API.
"""
from __future__ import annotations
import hashlib, array, ctypes, errno, fcntl, glob, grp, json, os, pwd, selectors, socket, stat, struct, time
from pathlib import Path

EV_SYN, EV_KEY, EV_ABS, SYN_REPORT, SYN_DROPPED = 0, 1, 3, 0, 3
BTN_MODE, BTN_GAMEPAD, ABS_MAX, KEY_MAX = 316, 304, 63, 767
EVENT = struct.Struct('@llHHi')
ABSINFO = struct.Struct('6i')
INPUT_ID = struct.Struct('4H')
ROOT = Path('/run/neutronos-controller-proxy')
DEVICES = Path('/dev/neutronos-controller-proxy')

def ioc(direction, type_, nr, size): return direction << 30 | size << 16 | ord(type_) << 8 | nr

def read_ioctl(fd, nr, size):
    data = bytearray(size); fcntl.ioctl(fd, ioc(2, 'E', nr, size), data, True); return bytes(data)

def optional_unique(fd):
    # A legitimate USB controller can omit EVIOCGUNIQ entirely.
    try:return read_ioctl(fd,8,256).split(b'\0')[0]
    except OSError as error:
        if error.errno in (errno.ENOENT,errno.ENODATA,errno.ENOTTY):return b''
        raise

def bits(fd, kind, maximum):
    raw = read_ioctl(fd, 0x20 + kind, (maximum + 8)//8)
    return [i for i in range(maximum+1) if raw[i//8] & 1 << (i%8)]

def neutral(code, info):
    _, minimum, maximum, _, _, _ = info
    if code in (2, 5, 9, 10): return minimum
    if code in (16, 17, 18, 19, 20, 21, 22, 23): return 0
    return (minimum + maximum + 1)//2

def controller_identity(input_id, unique, name):
    # Ignore transport and firmware version when the device exposes a stable unique ID.
    _, vendor, product, _ = INPUT_ID.unpack(input_id)
    return hashlib.sha256(struct.pack('2H',vendor,product)+(unique or name.encode())).hexdigest()

def idle_axis(code, value, info):
    return abs(value-neutral(code,info)) <= (max(1,info[4]) if code not in (2,5,9,10,16,17) else 0)

class Gesture:
    def __init__(self): self.down = {}; self.fired = set()
    def event(self, device, value, now):
        if value == 1 and device not in self.down: self.down[device] = now
        elif value == 0: self.disconnect(device)
    def disconnect(self, device): self.down.pop(device, None); self.fired.discard(device)
    def poll(self, now):
        ready = [d for d,t in self.down.items() if d not in self.fired and now-t >= 3.0]
        self.fired.update(ready); return ready

class FocusGate:
    """Release everything on a transition; held controls must neutralize first."""
    def __init__(self, axes):
        self.axes = axes; self.values = {}; self.buttons = set(); self.blocked = set(); self.modal = False
    def switch(self, modal):
        self.modal = modal
        self.blocked.update((EV_KEY, code) for code in self.buttons)
        self.blocked.update((EV_ABS, code) for code,value in self.values.items() if not idle_axis(code,value,self.axes[code]))
        return [(EV_KEY, code, 0) for code in self.buttons] + [(EV_ABS,code,neutral(code,info)) for code,info in self.axes.items()]
    def event(self, type_, code, value):
        if type_ == EV_KEY:
            if value == 1: self.buttons.add(code)
            elif value == 0: self.buttons.discard(code)
        elif type_ == EV_ABS: self.values[code] = value
        else: return not self.modal
        token = (type_,code)
        if token in self.blocked:
            idle = idle_axis(code,value,self.axes[code]) if type_ == EV_ABS else value == 0
            if idle: self.blocked.discard(token)
            return False
        return not self.modal

class Pad:
    def __init__(self, path, slot, nodes, profile):
        self.path, self.slot, self.fd, self.ui = path,slot,-1,-1
        self.nodes=[];self.nav={};self.dropped=False;self.map=profile.get('buttons',{});self.invert=profile.get('invertAxes',[])
        try:
            self.fd=os.open(path,os.O_RDONLY|os.O_NONBLOCK|os.O_CLOEXEC)
            self.keys=bits(self.fd,EV_KEY,KEY_MAX)
            if not any(304 <= k <= 318 for k in self.keys): raise ValueError('Not a gamepad')
            self.axes={code:ABSINFO.unpack(read_ioctl(self.fd,0x40+code,24)) for code in bits(self.fd,EV_ABS,ABS_MAX)}
            effective=[int(self.map.get(str(k),k)) for k in self.keys if k!=BTN_MODE]
            if len(set(effective))!=len(effective) or any(k not in self.keys for k in effective):raise ValueError('Remap must use distinct supported physical controls')
            self.gate=FocusGate(self.axes)
            self.name=read_ioctl(self.fd,6,256).split(b'\0')[0].decode(errors='replace')
            unique=optional_unique(self.fd)
            self.identity=controller_identity(read_ioctl(self.fd,2,8),unique,self.name)
            self.slot=int(profile.get('assignments',{}).get(self.identity,slot))
            input_id=read_ioctl(self.fd,2,8)
            self.ui=os.open('/dev/uinput',os.O_WRONLY|os.O_NONBLOCK|os.O_CLOEXEC)
            for type_ in (EV_KEY,EV_ABS): fcntl.ioctl(self.ui,ioc(1,'U',100,4),type_)
            # Keep the physical button layout for SDL/Wine mapping indices.
            # Home stays permanently released: its events are intercepted in read().
            for code in self.keys:fcntl.ioctl(self.ui,ioc(1,'U',101,4),code)
            for code,info in self.axes.items():
                fcntl.ioctl(self.ui,ioc(1,'U',103,4),code)
                setup=struct.pack('H2x6i',code,*info)
                fcntl.ioctl(self.ui,ioc(1,'U',4,len(setup)),setup)
            name=f'Gemini P{self.slot+1}: {self.name}'.encode()[:79]
            setup=input_id+name.ljust(80,b'\0')+struct.pack('I',0)
            fcntl.ioctl(self.ui,ioc(1,'U',3,len(setup)),setup)
            fcntl.ioctl(self.ui,ioc(0,'U',1,0))
            sysname=bytearray(128);fcntl.ioctl(self.ui,ioc(2,'U',44,len(sysname)),sysname,True)
            self.sysname=bytes(sysname).split(b'\0')[0].decode()
            # Create the virtual pad before grabbing the registered physical pad.
            fcntl.ioctl(self.fd,ioc(1,'E',0x90,4),1)
            self.sample_state()
            self.publish_nodes(nodes)
        except Exception:
            self.close();raise
    def sample_state(self):
        current=read_ioctl(self.fd,0x18,(KEY_MAX+8)//8)
        self.gate.buttons={k for k in self.keys if k!=BTN_MODE and current[k//8]&1<<(k%8)}
        self.gate.values={c:ABSINFO.unpack(read_ioctl(self.fd,0x40+c,24))[0] for c in self.axes}
        self.gate.switch(self.gate.modal)
    def publish_nodes(self, nodes):
        for p in Path('/sys/devices/virtual/input',self.sysname).glob('*'):
            if not (p.name.startswith('event') or p.name.startswith('js')):continue
            dev=Path('/dev/input',p.name)
            if not dev.exists():continue
            info=dev.stat();dest=nodes/p.name
            # Link only this uinput pad's kernel-created node on the same devtmpfs.
            # /run is nodev; no mknod or broader device permission is required.
            if not dest.exists():os.link(dev,dest,follow_symlinks=False)
            owned=dest.lstat()
            if not stat.S_ISCHR(owned.st_mode) or owned.st_ino!=info.st_ino or owned.st_dev!=info.st_dev:raise OSError(errno.EINVAL,'Unexpected proxy device alias')
            gid=grp.getgrnam('neutronos').gr_gid
            # udev can apply its default group after UI_DEV_CREATE. Reconcile only
            # this pad's owned virtual inode so private user namespaces retain access.
            if owned.st_uid!=0 or owned.st_gid!=gid:os.chown(dest,0,gid)
            if dest not in self.nodes:self.nodes.append(dest)
    def emit(self, type_, code, value): os.write(self.ui,EVENT.pack(0,0,type_,code,value))
    def synchronize(self):self.emit(EV_SYN,SYN_REPORT,0)
    def switch(self, modal):
        self.nav.clear()
        for t,c,v in self.gate.switch(modal):self.emit(t,int(self.map.get(str(c),c)) if t==EV_KEY else c,v)
        self.synchronize()
    def close(self):
        if self.fd >= 0:
            try:fcntl.ioctl(self.fd,ioc(1,'E',0x90,4),0)
            except OSError:pass
            os.close(self.fd);self.fd=-1
        if self.ui >= 0:
            try:fcntl.ioctl(self.ui,ioc(0,'U',2,0))
            except OSError:pass
            os.close(self.ui);self.ui=-1
        for p in self.nodes:p.unlink(missing_ok=True)
    def modal_action(self, t,c,v):
        if t==EV_KEY and v in (0,1):
            action={304:'primary',305:'cancel',307:'secondary',308:'context',315:'system',310:'l1',311:'r1'}.get(c)
            return [(action,v==1)] if action else []
        if t==EV_ABS and c in (0,1,16,17):
            info=self.axes[c];center=neutral(c,info);threshold=0 if c in (16,17) else max(1,(info[2]-info[1])*0.25)
            direction=1 if v>center+threshold else -1 if v<center-threshold else 0
            before=self.nav.get(c,0);self.nav[c]=direction
            if direction!=before:
                def action(d):return ('right' if d>0 else 'left') if c in (0,16) else ('down' if d>0 else 'up')
                return ([(action(before),False)] if before else [])+([(action(direction),True)] if direction else [])
        return []
    def read(self, service):
        payload=os.read(self.fd,EVENT.size*64)
        if not payload:raise OSError(errno.ENODEV,'Controller disconnected')
        for offset in range(0,len(payload)-EVENT.size+1,EVENT.size):
            _,_,t,c,v=EVENT.unpack_from(payload,offset)
            if t==EV_SYN and c==SYN_DROPPED:
                # Never guess after kernel queue overflow: neutralize then resample.
                service.gesture.disconnect(self.fd)
                self.switch(self.gate.modal)
                service.send({"event":"inputReset","slot":self.slot})
                self.dropped=True
                continue
            if self.dropped:
                if t==EV_SYN and c==SYN_REPORT:
                    self.switch(self.gate.modal);self.sample_state();self.dropped=False
                continue
            if t==EV_KEY and c==BTN_MODE:
                service.gesture.event(self.fd,v,time.monotonic());continue
            if self.gate.modal and (t,c) not in self.gate.blocked:
                actions=self.modal_action(t,c,v)
                for action,pressed in actions:service.send({'event':'action','action':action,'pressed':pressed,'slot':self.slot})
            forward=self.gate.event(t,c,v)
            if forward and t in (EV_KEY,EV_ABS,EV_SYN):
                target=int(self.map.get(str(c),c)) if t==EV_KEY else c
                if t==EV_KEY and (target not in self.keys or target==BTN_MODE):target=c
                if t==EV_ABS and c in self.invert:v=self.axes[c][1]+self.axes[c][2]-v
                self.emit(t,target,v)

def trusted_shell_peer(pid,uid,expected_uid):
    if uid!=expected_uid:return False
    try:
        return (Path(f"/proc/{pid}").stat().st_uid==uid and
                Path(f"/proc/{pid}/exe").resolve()==Path("/opt/neutronos/build/NeutronShell") and
                any(line.endswith(":/system.slice/neutronos.service") for line in Path(f"/proc/{pid}/cgroup").read_text().splitlines()))
    except OSError:return False

class Service:
    def __init__(self):
        self.selector=selectors.DefaultSelector();self.client=None;self.pads={};self.gesture=Gesture();self.modal=False;self.focus="idle";self.active=False;self.profile={};self.buffer=b'';self.last_scan=0
        self.uid=pwd.getpwnam('neutronos').pw_uid;gid=grp.getgrnam('neutronos').gr_gid
        ROOT.mkdir(mode=0o750,exist_ok=True);os.chown(ROOT,0,gid)
        self.nodes=DEVICES;self.nodes.mkdir(mode=0o750,exist_ok=True);os.chown(self.nodes,0,gid)
        for p in self.nodes.iterdir():
            if stat.S_ISCHR(p.lstat().st_mode):p.unlink()
        address=ROOT/'control.sock';address.unlink(missing_ok=True)
        self.server=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);self.server.bind(str(address));os.chmod(address,0o660);os.chown(address,0,gid);self.server.listen(1);self.server.setblocking(False)
        self.selector.register(self.server,selectors.EVENT_READ,'accept')
    def send(self, message):
        if self.client:
            try:self.client.sendall(json.dumps(message,separators=(',',':')).encode()+b'\n')
            except OSError:self.stop()
    def stop(self):
        for fd,pad in list(self.pads.items()):
            self.selector.unregister(fd);self.gesture.disconnect(fd);pad.close()
        self.pads.clear();self.modal=False;self.focus="idle";self.active=False
        if self.client:
            try:self.selector.unregister(self.client)
            except (KeyError,ValueError):pass
            self.client.close();self.client=None
        self.buffer=b''
    def scan(self):
        self.last_scan=time.monotonic();known={p.path for p in self.pads.values()}
        for path in glob.glob('/dev/input/event*'):
            if path in known:continue
            # Exclude our virtual pads and every other uinput device to prevent loops.
            if os.path.realpath('/sys/class/input/'+Path(path).name).startswith('/sys/devices/virtual/input/'):continue
            try:
                used={p.slot for p in self.pads.values()};slot=next((i for i in range(16) if i not in used),None)
                if slot is None:continue
                pad=Pad(path,slot,self.nodes,self.profile)
                if pad.slot in used:pad.close();continue
                pad.switch(self.modal)
                self.pads[pad.fd]=pad;self.selector.register(pad.fd,selectors.EVENT_READ,'pad')
                self.send({'event':'connected','name':pad.name,'slot':pad.slot,'identity':pad.identity,'transport':INPUT_ID.unpack(read_ioctl(pad.fd,2,8))[0]})
            except (OSError,ValueError):continue
        for pad in self.pads.values():pad.publish_nodes(self.nodes)
    def command(self, message):
        if not isinstance(message,dict):raise ValueError('Invalid command')
        command=message.get('command')
        if command=='begin':
            profile=message.get('profile',{})
            if self.pads:raise ValueError('Input session already active')
            if not isinstance(profile,dict):raise ValueError('Invalid controller profile')
            buttons=profile.get('buttons',{});inverted=profile.get('invertAxes',[])
            if not isinstance(buttons,dict) or len(buttons)>32 or any(not str(k).isdigit() or not isinstance(v,int) or not 288<=int(k)<=318 or not 288<=v<=318 or int(k)==BTN_MODE or v==BTN_MODE for k,v in buttons.items()):raise ValueError('Invalid button mapping')
            if len(set(buttons.values()))!=len(buttons):raise ValueError('Button mapping must be one-to-one')
            if not isinstance(inverted,list) or any(type(a)!=int or a not in (0,1,3,4) for a in inverted):raise ValueError('Invalid analog mapping')
            assignments=profile.get('assignments',{})
            if not isinstance(assignments,dict) or len(assignments)>16 or any(not isinstance(k,str) or len(k)!=64 or type(v)!=int or not 0<=v<16 for k,v in assignments.items()) or len(set(assignments.values()))!=len(assignments):raise ValueError('Invalid player assignments')
            self.profile=profile;self.active=True;self.focus='game';self.scan();self.send({'event':'ready','controllers':len(self.pads),'devices':str(self.nodes)})
        elif command in ('modal','resume','background'):
            self.focus={'modal':'menu','resume':'game','background':'background'}[command]
            self.modal=command!='resume'
            for pad in self.pads.values():pad.switch(self.modal)
            self.send({'event':'focus','modal':self.modal})
        elif command=='end':self.stop()
        else:raise ValueError('Unsupported controller command')
    def run(self):
        try:
            while True:
                for key,_ in self.selector.select(0.025):
                    if key.data=='accept':
                        peer,_=self.server.accept()
                        pid,uid,_=struct.unpack('3i',peer.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12))
                        if not trusted_shell_peer(pid,uid,self.uid) or self.client:peer.close();continue
                        peer.setblocking(False);self.client=peer;self.selector.register(peer,selectors.EVENT_READ,'command')
                    elif key.data=='command':
                        try:
                            chunk=self.client.recv(8192)
                            if not chunk:self.stop();continue
                            self.buffer+=chunk
                            if len(self.buffer)>65536:raise ValueError('Command too large')
                            while b'\n' in self.buffer:
                                line,self.buffer=self.buffer.split(b'\n',1);self.command(json.loads(line))
                        except (OSError,ValueError,KeyError):self.stop()
                    elif key.data=='pad':
                        try:self.pads[key.fd].read(self)
                        except OSError:
                            pad=self.pads.pop(key.fd);self.selector.unregister(key.fd);self.gesture.disconnect(key.fd);pad.close();self.send({'event':'disconnected','slot':pad.slot})
                if self.client and self.active and time.monotonic()-self.last_scan>1:self.scan()
                if self.client and self.active and self.focus!='menu' and self.gesture.poll(time.monotonic()):
                    self.modal=True;self.focus='menu'
                    for pad in self.pads.values():pad.switch(True)
                    self.send({'event':'homeHold','seconds':3})
        finally:self.stop();self.server.close()

if __name__=='__main__':Service().run()
