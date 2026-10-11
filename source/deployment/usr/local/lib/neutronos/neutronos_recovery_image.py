"""Signed full-image companion to the overlay applier. No ZIP limits apply.

Device writes require externally booted recovery, a blank unmounted whole disk,
an exact target identity confirmation and an exclusive block-device descriptor.
There is intentionally no force option or regular-file installation override.
"""
from __future__ import annotations
import base64,hashlib,json,lzma,os,platform,re,shutil,stat,struct,subprocess,tempfile,time,urllib.parse,urllib.request,zlib
from pathlib import Path

SCHEMA='neutronos.recovery-image.v1'
MAX_IMAGE=8*1024**3
MAX_RAW=128*1024**3
REPOSITORY='OGDrNeutron/NeutronOS'


def strict_json(raw):
    def pairs(items):
        out={}
        for key,value in items:
            if key in out: raise ValueError('Duplicate JSON key')
            out[key]=value
        return out
    return json.loads(raw,object_pairs_hook=pairs,parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Invalid number')))


def valid_asset_url(url):
    parsed=urllib.parse.urlsplit(url)
    return (parsed.scheme=='https' and parsed.hostname=='github.com' and parsed.port in (None,443)
            and not parsed.username and not parsed.password and not parsed.query and not parsed.fragment
            and re.fullmatch(r'/OGDrNeutron/NeutronOS/releases/download/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.img\.xz',parsed.path) is not None)


class AssetRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        parsed=urllib.parse.urlsplit(newurl)
        if (parsed.scheme!='https' or parsed.hostname not in ('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com')
                or parsed.port not in (None,443) or parsed.username or parsed.password):
            raise ValueError('Recovery image redirect left the approved GitHub asset hosts')
        return super().redirect_request(req,fp,code,msg,headers,newurl)


def inspect_gpt(handle,raw_bytes,expected):
    """Independent GPT CRC/extent verification on an already authenticated raw image."""
    if raw_bytes%512 or raw_bytes<4*1024*1024: raise ValueError('Invalid disk image size')
    def read_at(offset,count):
        handle.seek(offset);data=handle.read(count)
        if len(data)!=count: raise ValueError('Truncated image structure')
        return data
    protective=read_at(0,512)
    if protective[510:512]!=b'\x55\xaa' or protective[450]!=0xee: raise ValueError('Missing protective GPT MBR')
    headers=[]
    for sector in (1,raw_bytes//512-1):
        data=read_at(sector*512,512)
        if data[:8]!=b'EFI PART': raise ValueError('Missing GPT header')
        size=struct.unpack_from('<I',data,12)[0]
        if not 92<=size<=512: raise ValueError('Invalid GPT header size')
        crc=struct.unpack_from('<I',data,16)[0];check=bytearray(data[:size]);check[16:20]=b'\0'*4
        if zlib.crc32(check)&0xffffffff!=crc: raise ValueError('GPT header CRC mismatch')
        current,backup,first,last=struct.unpack_from('<QQQQ',data,24)
        entry_sector,count,entry_size,entry_crc=struct.unpack_from('<QIII',data,72)
        if (current!=sector or backup!=(raw_bytes//512-1 if sector==1 else 1) or first<2 or last>=raw_bytes//512-1
                or count<1 or count>1024 or entry_size!=128 or entry_sector*512+count*entry_size>raw_bytes):
            raise ValueError('Invalid GPT extents')
        entries=read_at(entry_sector*512,count*entry_size)
        if zlib.crc32(entries)&0xffffffff!=entry_crc: raise ValueError('GPT entry CRC mismatch')
        headers.append((data[56:72],first,last,entries))
    if headers[0]!=headers[1]: raise ValueError('GPT primary/backup mismatch')
    parts=[]
    entries=headers[0][3]
    for offset in range(0,len(entries),128):
        entry=entries[offset:offset+128]
        if entry[:16]==b'\0'*16: continue
        first,last=struct.unpack_from('<QQ',entry,32)
        if first<headers[0][1] or last>headers[0][2] or first>last: raise ValueError('Partition leaves usable GPT range')
        if any(first<=p['lastSector'] and last>=p['firstSector'] for p in parts): raise ValueError('Overlapping image partitions')
        parts.append({'firstSector':first,'lastSector':last,'typeGuid':__import__('uuid').UUID(bytes_le=entry[:16]).__str__()})
    if parts!=expected: raise ValueError('Image partitions differ from signed metadata')
    # Supported image conventions are EFI/FAT and Linux/ext4, in that order.
    if len(parts)!=2 or parts[0]['typeGuid']!='c12a7328-f81f-11d2-ba4b-00a0c93ec93b' or parts[1]['typeGuid']!='0fc63daf-8483-4772-8e79-3d69d8477de4':
        raise ValueError('Unsupported Gemini image partition layout')
    if read_at(parts[0]['firstSector']*512+510,2)!=b'\x55\xaa' or read_at(parts[1]['firstSector']*512+1024+56,2)!=b'\x53\xef':
        raise ValueError('Image filesystem signatures do not match EFI/ext4')
    return parts



def inspect_boot_identities(handle):
    """Read GPT partition and filesystem identities without modifying the image."""
    import uuid
    handle.seek(512);header=handle.read(512)
    # Preserve the generic flasher's support for non-GPT third-party images.
    if header[:8]!=b'EFI PART':return {'uuid':set(),'partuuid':set()}
    size=struct.unpack_from('<I',header,12)[0]
    if not 92<=size<=512:raise ValueError('Invalid GPT boot identity header')
    check=bytearray(header[:size]);check[16:20]=b'\0'*4
    if zlib.crc32(check)&0xffffffff!=struct.unpack_from('<I',header,16)[0]:raise ValueError('Invalid GPT boot identity checksum')
    start,count,width,crc=struct.unpack_from('<QIII',header,72)
    if count<1 or count>1024 or width!=128:raise ValueError('Unsupported GPT boot identity table')
    handle.seek(start*512);entries=handle.read(count*width)
    if len(entries)!=count*width or zlib.crc32(entries)&0xffffffff!=crc:raise ValueError('Invalid GPT boot identity table checksum')
    result={'uuid':set(),'partuuid':set()}
    partitions=[]
    for offset in range(0,len(entries),width):
        row=entries[offset:offset+width]
        if row[:16]==b'\0'*16:continue
        result['partuuid'].add(str(uuid.UUID(bytes_le=row[16:32])).lower())
        partitions.append(struct.unpack_from('<Q',row,32)[0])
    for first in sorted(partitions):
        handle.seek(first*512);sample=handle.read(2048)
        if len(sample)!=2048:raise ValueError('Truncated filesystem identity sample')
        if sample[1080:1082]==b'\x53\xef':
            result['uuid'].add(str(uuid.UUID(bytes=sample[1128:1144])).lower())
        elif sample[82:87]==b'FAT32' or sample[54:59]==b'FAT16':
            offset=67 if sample[82:87]==b'FAT32' else 39
            serial=struct.unpack_from('<I',sample,offset)[0]
            result['uuid'].add(f'{serial>>16:04x}-{serial&65535:04x}')
    return result


def reject_boot_identity_collisions(identities,nodes,target):
    """Fail before disk writes if another connected installation shares an ID."""
    def visit(rows,excluded=False):
        for row in rows:
            skip=excluded or os.path.realpath(str(row.get('path','')))==os.path.realpath(target)
            if not skip:
                for kind in ('uuid','partuuid'):
                    value=str(row.get(kind) or '').strip().lower()
                    if value and value in identities[kind]:
                        raise ValueError('Duplicate boot '+kind.upper()+' on another connected disk; refusing an ambiguous clone. A separately authorized unique-identity installation is required. No disk identifiers were changed.')
            visit(row.get('children') or [],skip)
    visit(nodes)


def iter_decoded(handle,expected_bytes,expected_sha):
    decoder=lzma.LZMADecompressor(format=lzma.FORMAT_XZ,memlimit=256*1024**2)
    digest=hashlib.sha256();count=0;deadline=time.monotonic()+3600
    while True:
        compressed=handle.read(1024*1024) if decoder.needs_input else b''
        if not compressed and decoder.needs_input:break
        data=decoder.decompress(compressed,max_length=1024*1024)
        count+=len(data)
        if count>expected_bytes or time.monotonic()>deadline:raise ValueError('Decoded image exceeds its signed size or verification deadline')
        digest.update(data)
        yield data
        if decoder.eof:
            if decoder.unused_data or handle.read(1):raise ValueError('Trailing or concatenated XZ data is not accepted')
            break
    if not decoder.eof or count!=expected_bytes or digest.hexdigest()!=expected_sha:
        raise ValueError('Decoded image size, integrity or SHA-256 failed')


def decode_xz(source,destination,expected_bytes,expected_sha):
    # File-output helper for isolated verifier tests; production retains no raw copy.
    with source.open('rb') as inp,destination.open('xb') as out:
        for data in iter_decoded(inp,expected_bytes,expected_sha):out.write(data)
        out.flush();os.fsync(out.fileno())


class StructureSamples:
    """Bounded seekable windows for GPT/FAT/ext4 inspection during a full hash pass."""
    def __init__(self,size,partitions):
        self.offset=0
        regions=[(0,min(2*1024**2,size)),(max(0,size-2*1024**2),size)]
        for row in partitions:
            first=row['firstSector']*512
            if first<0 or first+2048>size:raise ValueError('Signed filesystem sample leaves the image')
            regions.append((first,first+2048))
        self.windows=[(first,last,bytearray(last-first)) for first,last in regions]
    def accept(self,offset,data):
        end=offset+len(data)
        for first,last,buffer in self.windows:
            a=max(offset,first);b=min(end,last)
            if a<b:buffer[a-first:b-first]=data[a-offset:b-offset]
    def seek(self,offset):self.offset=offset
    def read(self,count):
        for first,last,buffer in self.windows:
            if first<=self.offset and self.offset+count<=last:
                result=bytes(buffer[self.offset-first:self.offset-first+count]);self.offset+=count;return result
        raise ValueError('GPT requires data outside the bounded structure windows')


def verify_stream(source,image,partitions):
    samples=StructureSamples(image['rawBytes'],partitions);offset=0
    with source.open('rb') as handle:
        for data in iter_decoded(handle,image['rawBytes'],image['rawSHA256']):
            samples.accept(offset,data);offset+=len(data)
    inspect_gpt(samples,image['rawBytes'],partitions)


class ImageRecovery:
    def __init__(self,core):
        self.c=core
        self.test=bool(os.environ.get('NEUTRONOS_UPDATE_TEST_ROOT'))
        self.repository=Path(os.environ.get('NEUTRONOS_UPDATE_TEST_REPOSITORY','')) if self.test else Path('/var/lib/neutronos/update-mainline/repository')
        if not str(self.repository) or str(self.repository)=='.': self.repository=Path('/var/lib/neutronos/update-mainline/repository')
        self.cache=core['production_paths']()[2]/'images' if self.test else Path('/var/cache/neutronos-recovery-images')

    def deny(self,message): raise self.c['Denied'](message)

    def regular(self,path,maximum=None):
        info=path.lstat()
        if (not stat.S_ISREG(info.st_mode) or info.st_uid!=0 or info.st_mode&0o022
                or maximum is not None and info.st_size>maximum): self.deny('Image metadata/cache has unsafe ownership, type, mode or size')
        return info

    def signed_manifest(self,relative,signature_relative):
        paths=[self.repository/p for p in (relative,signature_relative)]
        for p in paths:
            if self.repository.resolve() not in p.resolve().parents: self.deny('Image manifest path escaped Mainline mirror')
        raw=paths[0].read_bytes()
        if not raw or len(raw)>1024*1024: self.deny('Image manifest size is invalid')
        signature=paths[1].read_bytes()
        if len(signature)>32768:self.deny('Image signature exceeds the safety limit')
        self.c['verify_signature'](raw,base64.b64decode(signature.strip(),validate=True))
        manifest=strict_json(raw)
        if (manifest.get('format')!=SCHEMA or manifest.get('schema')!=1 or manifest.get('algorithm')!='OpenPGP'
                or manifest.get('product')!='NeutronOS' or manifest.get('codename')!='Gemini' or manifest.get('channel')!='mainline'
                or manifest.get('architecture')!='amd64' or manifest.get('firmware')!='uefi-x86_64'
                or manifest.get('imageProtocol')!=1 or manifest.get('sectorSize')!=512
                or manifest.get('externalBootRequired') is not True or manifest.get('blankTargetRequired') is not True):
            self.deny('Recovery image identity, protocol or compatibility is unsupported')
        self.c['safe_version'](manifest.get('version',''))
        image=manifest.get('image',{})
        for key in ('sha256','rawSHA256'):
            if not re.fullmatch('[0-9a-f]{64}',str(image.get(key,''))): self.deny('Image checksum is invalid')
        for key,limit in (('bytes',MAX_IMAGE),('rawBytes',MAX_RAW)):
            value=image.get(key)
            if type(value) is not int or not 0<value<=limit:self.deny('Image size is invalid')
        if (not valid_asset_url(image.get('url','')) or Path(urllib.parse.urlsplit(image['url']).path).name!=image.get('name')
                or image.get('compression')!='xz' or image['rawBytes']%512
                or type(manifest.get('minimumTargetBytes')) is not int
                or not image['rawBytes']<=manifest['minimumTargetBytes']<=MAX_RAW): self.deny('Image transport or target geometry is invalid')
        parts=manifest.get('partitions')
        if not isinstance(parts,list) or len(parts)!=2: self.deny('Signed image partition layout is missing')
        if platform.machine().lower() not in ('amd64','x86_64'): self.deny('This Gemini image requires an amd64 Recovery environment')
        return manifest

    def catalog(self):
        index=strict_json((self.repository/'mainline.json').read_bytes())
        if index.get('schema')!=1 or index.get('channel')!='mainline': self.deny('Mainline image index is unsupported')
        releases=[]
        for row in index.get('recoveryImages',[]):
            if row.get('live') is not True:continue
            try:
                m=self.signed_manifest(row['metadata'],row['signature'])
                if m['version']!=row['version'] or m['image']['sha256']!=row['sha256']:continue
                releases.append({'version':m['version'],'name':'NeutronOS Gemini '+m['version'],'path':row['metadata'],'signature':row['signature'],
                                 'size':m['image']['bytes'],'sha256':m['image']['sha256'],'profile':'FULL IMAGE · OFFLINE / BLANK TARGET','verified':True,'kind':'image'})
            except (self.c['Denied'],OSError,ValueError,TypeError,KeyError):continue
        releases.sort(key=lambda row:self.c['version_tuple'](row['version']),reverse=True)
        return releases

    def select(self,relative):
        selected=next((r for r in self.catalog() if r['path']==relative),None)
        if selected is None:self.deny('Selected image is not in the authenticated LIVE Mainline catalog')
        return self.signed_manifest(selected['path'],selected['signature'])

    def ensure_cache(self):
        if self.cache.is_symlink():self.deny('Unsafe image cache root')
        self.cache.mkdir(parents=True,exist_ok=True,mode=0o700)
        stop=self.c['production_paths']()[2] if self.test else Path('/var/cache')
        for directory in (self.cache,*self.cache.parents):
            if directory==stop:break
            info=directory.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid!=0 or info.st_mode&0o022:self.deny('Image cache ancestry is not root-owned and protected')

    def paths(self,m):
        self.ensure_cache()
        folder=self.cache/m['image']['sha256'];folder.mkdir(parents=True,exist_ok=True,mode=0o700)
        if folder.is_symlink() or folder.stat().st_uid!=0 or folder.stat().st_mode&0o022:self.deny('Unsafe image cache directory')
        return folder,folder/m['image']['name'],folder/'verified.img'

    def verify(self,relative):
        m=self.select(relative);folder,compressed,raw=self.paths(m);self.regular(compressed,m['image']['bytes'])
        if compressed.stat().st_size!=m['image']['bytes'] or self.c['sha256'](compressed)!=m['image']['sha256']:self.deny('Compressed image size or SHA-256 mismatch')
        verify_stream(compressed,m['image'],m['partitions'])
        self.c['atomic_json'](folder/'verified.json',{'version':m['version'],'sha256':m['image']['sha256'],'rawSHA256':m['image']['rawSHA256'],'verifiedUtc':self.c['now'](),'verification':'bounded streaming XZ/raw SHA-256 and GPT/filesystem samples','rawImageCached':False})
        return m,compressed

    def download(self,relative):
        m=self.select(relative);folder,compressed,_=self.paths(m)
        if not compressed.exists():
            if shutil.disk_usage(folder).free < m['image']['bytes']+512*1024**2:self.deny('Insufficient protected cache space for the compressed image and safety reserve')
            partial=folder/'download.partial';partial.unlink(missing_ok=True)
            cancel=self.cache/'cancel';cancel.unlink(missing_ok=True)
            expected=m['image']['bytes'];count=0;digest=hashlib.sha256();deadline=time.monotonic()+3600
            opener=urllib.request.build_opener(AssetRedirect())
            try:
                with opener.open(urllib.request.Request(m['image']['url'],headers={'User-Agent':'NeutronOS-Recovery/1'}),timeout=20) as response,partial.open('xb') as out:
                    if response.status!=200:self.deny('Image download did not return HTTP 200')
                    while block:=response.read(1024*1024):
                        if cancel.exists() or time.monotonic()>deadline:self.deny('Image download cancelled or timed out')
                        count+=len(block)
                        if count>expected:self.deny('Image download exceeded signed size')
                        digest.update(block);out.write(block)
                        print(f'PROGRESS:{min(70,int(count*70/expected))}:Downloading authenticated full image…',flush=True)
                    out.flush();os.fsync(out.fileno())
                if count!=expected or digest.hexdigest()!=m['image']['sha256']:self.deny('Image download size or SHA-256 mismatch')
                partial.chmod(0o600);os.replace(partial,compressed)
            finally:partial.unlink(missing_ok=True)
        print('PROGRESS:75:Verifying XZ, raw image and partition structure…',flush=True)
        self.verify(relative);print('PROGRESS:100:Full image verified. Offline target selection is required.',flush=True)

    def offline(self):
        # Test-root seams deliberately do not bypass any real-device guard.
        if self.test:self.deny('Real device installation is disabled in isolated test-root mode')
        marker=Path('/run/neutronos/offline-recovery.json');self.regular(marker,4096)
        if strict_json(marker.read_bytes()).get('active') is not True or 'neutronos.offline_recovery=1' not in Path('/proc/cmdline').read_text().split():
            self.deny('Full-image installation requires an explicitly booted external offline Recovery environment')

    def target_rows(self,m):
        self.offline()
        data=json.loads(subprocess.run(['/usr/bin/lsblk','--json','--bytes','--paths','--output','PATH,TYPE,SIZE,MODEL,SERIAL,WWN,MAJ:MIN,MOUNTPOINTS,RO,LOG-SEC'],capture_output=True,text=True,check=True,timeout=15).stdout)
        mounted={line.split()[2] for line in Path('/proc/self/mountinfo').read_text().splitlines()}
        swap_devices=set()
        for line in Path('/proc/swaps').read_text().splitlines()[1:]:
            info=Path(line.split()[0]).stat();swap_devices.add(f'{os.major(info.st_rdev)}:{os.minor(info.st_rdev)}')
        def descendants(node):
            return [node]+[child for row in node.get('children',[]) for child in descendants(row)]
        result=[]
        for disk in data.get('blockdevices',[]):
            members=descendants(disk);dev=disk.get('maj:min','');path=disk.get('path','')
            if (disk.get('type')!='disk' or disk.get('ro') or int(disk.get('size',0))<m['minimumTargetBytes']
                    or int(disk.get('log-sec',0))!=512 or not (disk.get('serial') or disk.get('wwn'))):continue
            # Reject every mounted/swap-backed descendant and stacked holder.
            if any(row.get('maj:min') in mounted|swap_devices or any(row.get('mountpoints') or [])
                   or any((Path('/sys/dev/block')/row['maj:min']/'holders').iterdir()) for row in members):continue
            if len(members)!=1:continue  # Existing partition/data disks require a separate backup/restore plan.
            info=Path(path).lstat()
            if not stat.S_ISBLK(info.st_mode) or f'{os.major(info.st_rdev)}:{os.minor(info.st_rdev)}'!=dev:continue
            probe=subprocess.run(['/usr/sbin/wipefs','--no-act','--json',path],capture_output=True,text=True,check=True,timeout=15)
            if json.loads(probe.stdout).get('signatures'):continue
            identity={k:disk.get(k) for k in ('path','size','serial','wwn','maj:min','log-sec')}
            fingerprint=hashlib.sha256(json.dumps(identity,sort_keys=True).encode()).hexdigest()
            result.append({'path':path,'size':int(disk['size']),'serial':str(disk.get('serial') or disk.get('wwn')),
                           'name':str(disk.get('model') or path)+' · '+str(disk.get('serial') or disk.get('wwn')),
                           'fingerprint':fingerprint,'profile':'BLANK DISK · ALL CONTENTS REPLACED','verified':True,'kind':'image-target'})
        return result

    def targets(self,relative):return self.target_rows(self.select(relative))

    def install(self,relative,target,fingerprint):
        m,raw=self.verify(relative)
        selected=next((row for row in self.target_rows(m) if row['path']==target and row['fingerprint']==fingerprint),None)
        if selected is None:self.deny('Target is active, mounted, nonblank, incompatible or its identity changed')
        folder,_,_=self.paths(m);journal=folder/'installation.json'
        with lzma.open(raw,'rb') as image:
            identities=inspect_boot_identities(image)
        devices=json.loads(subprocess.run(['/usr/bin/lsblk','--json','--paths','--output','PATH,UUID,PARTUUID'],capture_output=True,text=True,check=True,timeout=15).stdout)
        reject_boot_identity_collisions(identities,devices.get('blockdevices',[]),target)
        with raw.open('rb') as source:
            descriptor=os.open(target,os.O_RDWR|os.O_EXCL|os.O_NOFOLLOW|os.O_CLOEXEC)
            try:
                info=os.fstat(descriptor)
                if not stat.S_ISBLK(info.st_mode) or not selected in self.target_rows(m):self.deny('Target identity or usage changed before installation')
                self.c['atomic_json'](journal,{'status':'WRITING','target':selected,'version':m['version'],'startedUtc':self.c['now'](),'automaticRollback':False})
                written=0
                for block in iter_decoded(source,m['image']['rawBytes'],m['image']['rawSHA256']):
                    view=memoryview(block)
                    while view:
                        n=os.write(descriptor,view)
                        if n<=0:raise OSError('Short image write')
                        view=view[n:]
                    written+=len(block)
                    print(f'PROGRESS:{int(written*80/m["image"]["rawBytes"])}:Installing to the confirmed offline disk…',flush=True)
                os.fsync(descriptor);os.lseek(descriptor,0,os.SEEK_SET);digest=hashlib.sha256();remaining=m['image']['rawBytes']
                while remaining:
                    block=os.read(descriptor,min(4*1024*1024,remaining))
                    if not block:raise OSError('Short image readback')
                    digest.update(block);remaining-=len(block)
                if digest.hexdigest()!=m['image']['rawSHA256']:self.deny('Written disk image failed SHA-256 readback; retain external Recovery media')
                self.c['atomic_json'](journal,{'status':'VERIFIED','target':selected,'version':m['version'],'rawSHA256':digest.hexdigest(),'completedUtc':self.c['now'](),'automaticRollback':False})
                print('PROGRESS:100:Full image installed and verified on the offline target.',flush=True)
            finally:os.close(descriptor)

    def dispatch(self,action,args):
        if action=='image-catalog' and not args:print(json.dumps({'images':self.catalog()}));return
        if action=='image-cancel' and not args:
            self.ensure_cache();self.c['atomic_bytes'](self.cache/'cancel',b'cancel',0o600);return
        if action=='image-download' and len(args)==1:self.download(args[0]);return
        if action=='image-verify' and len(args)==1:
            self.verify(args[0]);print('Authenticated full image verification passed.');return
        if action=='image-targets' and len(args)==1:print(json.dumps({'targets':self.targets(args[0])}));return
        if action=='image-install' and len(args)==3:self.install(*args);return
        self.deny('Unsupported full-image Recovery operation')
