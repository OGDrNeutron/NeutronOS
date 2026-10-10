#!/usr/bin/env python3
"""First boot user-data partitioning for the verified Gemini GPT image layout.

The command line never accepts a disk path. The installation disk is derived
from the mounted root filesystem; explicit disk arguments exist only in the
importable functions used with disposable loop images in release tests.
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import stat
import subprocess
import sys
import tempfile

BOOT_START = 2048
BOOT_SECTORS = 1048576
ROOT_START = 1050624
# Last usable sector of the 16 GiB build image is 33554398; its final 33
# sectors belong to the GPT backup. DATA starts at the next MiB boundary.
ROOT_SECTORS = 32503775
MIN_DISK_BYTES = 20 * 1024**3
MIN_DATA_BYTES = 4 * 1024**3
MOUNTPOINT = Path('/NeutronOS')
STATE = Path('/var/lib/neutronos/storage-setup/transaction.json')
FSTAB = Path('/etc/fstab')
ESP_TYPE = 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'
LINUX_TYPE = '0fc63daf-8483-4772-8e79-3d69d8477de4'


class StorageError(Exception):
    pass


def progress(stage, message):
    print(json.dumps({'event': 'progress', 'stage': stage, 'message': message},
                     separators=(',', ':')), flush=True)


def command(args, *, input_text=None, timeout=60, check=True):
    result = subprocess.run(args, input=input_text, text=True, capture_output=True,
                            timeout=timeout, check=False)
    if check and result.returncode:
        raise StorageError(f'{Path(args[0]).name} failed: '
                           f'{(result.stderr or result.stdout).strip()[-500:]}')
    return result.stdout.strip()


def atomic_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    parent = path.parent.stat(follow_symlinks=False)
    if not stat.S_ISDIR(parent.st_mode) or parent.st_uid != 0 or parent.st_mode & 0o022:
        raise StorageError('storage transaction directory is not root controlled')
    fd, staged = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(payload, stream, sort_keys=True, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(staged, 0o600)
        os.chown(staged, 0, 0)
        os.replace(staged, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(staged):
            os.unlink(staged)


def read_state(path):
    try:
        parent = path.parent.stat(follow_symlinks=False)
        if not stat.S_ISDIR(parent.st_mode) or parent.st_uid != 0 or parent.st_mode & 0o022:
            raise StorageError('storage transaction directory is not root controlled')
        info = path.stat(follow_symlinks=False)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o077:
            raise StorageError('storage transaction record has unsafe ownership or permissions')
        return json.loads(path.read_text(encoding='utf-8'))
    except FileNotFoundError:
        return None
    except (ValueError, OSError) as exc:
        raise StorageError(f'storage transaction record is invalid: {exc}') from exc


def partition_path(disk, number):
    disk = Path(disk)
    return Path(str(disk) + ('p' if disk.name[-1].isdigit() else '') + str(number))


def live_installation_disk():
    root_mount = next((line for line in Path('/proc/self/mountinfo').read_text().splitlines()
                       if line.split()[4] == '/'), None)
    if not root_mount:
        raise StorageError('root filesystem mount is unavailable')
    major_minor = root_mount.split()[2]
    sys_partition = (Path('/sys/dev/block') / major_minor).resolve(strict=True)
    if (not (sys_partition / 'partition').is_file() or
            (sys_partition / 'partition').read_text().strip() != '2'):
        raise StorageError('root filesystem is not the expected partition 2')
    disk = Path('/dev') / sys_partition.parent.name
    if not disk.is_block_device() or partition_path(disk, 2).resolve() != (Path('/dev') / sys_partition.name).resolve():
        raise StorageError('installation disk cannot be established from mounted root')
    return disk, partition_path(disk, 2), partition_path(disk, 1)


def fs_type(device):
    return command(['/usr/sbin/blkid', '-s', 'TYPE', '-o', 'value', str(device)], check=False)


def fs_uuid(device):
    return command(['/usr/sbin/blkid', '-s', 'UUID', '-o', 'value', str(device)], check=False)


def fs_label(device):
    return command(['/usr/sbin/blkid', '-s', 'LABEL', '-o', 'value', str(device)], check=False)


def align_up(value, alignment):
    return (value + alignment - 1) // alignment * alignment


def disk_plan(disk, root_partition, boot_partition, *, state_path=STATE,
              fstab_path=FSTAB, mountpoint=MOUNTPOINT):
    disk, root_partition, boot_partition = map(Path, (disk, root_partition, boot_partition))
    if not disk.is_block_device() or not root_partition.is_block_device() or not boot_partition.is_block_device():
        raise StorageError('installation drive partitions are unavailable')
    table = json.loads(command(['/usr/sbin/sfdisk', '--json', str(disk)]))['partitiontable']
    disk_bytes = int(command(['/usr/sbin/blockdev', '--getsize64', str(disk)]))
    sector = int(table.get('sectorsize', 0))
    parts = table.get('partitions', [])
    if table.get('label') != 'gpt' or sector != 512 or not re.fullmatch(r'[0-9a-fA-F-]{36}', table.get('id', '')):
        raise StorageError('unsupported installation partition table or logical sector size')
    if disk_bytes % sector:
        raise StorageError('installation drive size is not a whole logical sector')
    if len(parts) not in (2, 3):
        raise StorageError('unexpected partition count; no storage changes are permitted')
    expected = ((BOOT_START, BOOT_SECTORS, ESP_TYPE), (ROOT_START, ROOT_SECTORS, LINUX_TYPE))
    for number, values in enumerate(expected, start=1):
        part = parts[number - 1]
        if (part.get('start'), part.get('size'), str(part.get('type')).lower()) != values:
            raise StorageError(f'partition {number} differs from the verified Gemini layout')
        if Path(part.get('node', '')).resolve() != partition_path(disk, number).resolve():
            raise StorageError(f'partition {number} belongs to an unexpected device')
    if fs_type(boot_partition) not in ('vfat', 'fat', 'msdos') or fs_type(root_partition) != 'ext4':
        raise StorageError('boot or NeutronOS system filesystem differs from the verified layout')
    if disk_bytes // sector <= ROOT_START + ROOT_SECTORS:
        raise StorageError('installation drive has no verified space after the system partition')
    alignment = 1024 * 1024 // sector
    data_start = align_up(ROOT_START + ROOT_SECTORS, alignment)
    # Leave 32 GPT entry sectors and the backup header intact. Alignment
    # applies to the start; using the last usable sector avoids wasting a MiB.
    data_end_exclusive = disk_bytes // sector - 33
    data_sectors = data_end_exclusive - data_start
    if data_sectors <= 0:
        raise StorageError('there is no aligned space available for user data')
    identity = {'diskId': table['id'].lower(), 'diskBytes': disk_bytes,
                'sectorBytes': sector, 'bootStart': BOOT_START, 'bootSectors': BOOT_SECTORS,
                'rootStart': ROOT_START, 'rootSectors': ROOT_SECTORS,
                'dataStart': data_start, 'dataSectors': data_sectors}
    fingerprint = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    state = read_state(state_path)
    data_device = partition_path(disk, 3)
    if state and state.get('fingerprint') != fingerprint:
        raise StorageError('storage transaction record does not match the installation drive')
    if len(parts) == 3:
        part = parts[2]
        if not state:
            raise StorageError('an existing third partition is not managed by NeutronOS; no changes are permitted')
        if (part.get('start'), part.get('size'), str(part.get('type')).lower()) != (data_start, data_sectors, LINUX_TYPE):
            raise StorageError('existing user-data partition differs from the recorded plan')
        kind = fs_type(data_device) if data_device.is_block_device() else ''
        if kind and (kind != 'ext4' or fs_label(data_device) != 'NEUTRON_DATA'):
            raise StorageError('existing third partition contains an unexpected filesystem')
        status = 'existing' if kind == 'ext4' else 'interrupted'
    else:
        if state and state.get('phase') not in ('planned',):
            raise StorageError('storage record expects a partition that is no longer present')
        status = 'available'
    if disk_bytes < MIN_DISK_BYTES or data_sectors * sector < MIN_DATA_BYTES:
        if len(parts) == 2:
            status = 'insufficient'
    if status == 'existing':
        uuid = fs_uuid(data_device)
        fstab = fstab_path.read_text() if fstab_path.exists() else ''
        mounted = command(['/usr/bin/findmnt', '-n', '-o', 'UUID', '--mountpoint', str(mountpoint)], check=False)
        if not uuid or ('UUID=' + uuid + ' ' + str(mountpoint) + ' ') not in fstab or mounted != uuid:
            status = 'interrupted'
    return {'status': status, 'fingerprint': fingerprint,
            'disk': str(disk), 'diskBytes': disk_bytes, 'systemBytes': ROOT_SECTORS * sector,
            'availableBytes': data_sectors * sector, 'sectorBytes': sector,
            'boot': {'device': str(boot_partition), 'start': BOOT_START, 'sectors': BOOT_SECTORS},
            'system': {'device': str(root_partition), 'start': ROOT_START, 'sectors': ROOT_SECTORS},
            'data': {'device': str(data_device), 'start': data_start, 'sectors': data_sectors},
            'mountpoint': str(mountpoint)}


def append_fstab(fstab_path, uuid, mountpoint):
    text = fstab_path.read_text()
    for row in text.splitlines():
        fields = row.split()
        if fields and not row.lstrip().startswith('#') and (fields[0] == 'UUID=' + uuid or
                (len(fields) > 1 and fields[1] == str(mountpoint))):
            if len(fields) > 1 and fields[0] == 'UUID=' + uuid and fields[1] == str(mountpoint):
                return
            raise StorageError('fstab already uses the user-data UUID or mount location')
    entry = f'UUID={uuid} {mountpoint} ext4 defaults,nofail,x-systemd.device-timeout=15s 0 2\n'
    fd, staged = tempfile.mkstemp(prefix='.fstab-neutronos-', dir=fstab_path.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(text.rstrip('\n') + '\n' + entry)
            output.flush(); os.fsync(output.fileno())
        old = fstab_path.stat()
        os.chmod(staged, stat.S_IMODE(old.st_mode))
        os.chown(staged, old.st_uid, old.st_gid)
        os.replace(staged, fstab_path)
    finally:
        if os.path.exists(staged):
            os.unlink(staged)


def provision_disk(disk, root_partition, boot_partition, fingerprint, username,
                   *, state_path=STATE, fstab_path=FSTAB, mountpoint=MOUNTPOINT):
    if not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', username) or username in ('root', 'neutronos', 'neutronos', 'nobody'):
        raise StorageError('invalid human account identity')
    # The Setup guard mounts DATA before useradd, so no home is ever hidden
    # beneath the new mount. Existing accounts must satisfy the same policy.
    try:
        user = pwd.getpwnam(username)
    except KeyError:
        user = None
    if user and (user.pw_uid < 1000 or user.pw_dir != str(mountpoint / username) or user.pw_shell.endswith(('nologin', 'false'))):
        raise StorageError('user-data owner must be the canonical interactive account')
    progress('validating', 'Validating installation drive')
    plan = disk_plan(disk, root_partition, boot_partition, state_path=state_path,
                     fstab_path=fstab_path, mountpoint=mountpoint)
    if plan['fingerprint'] != fingerprint:
        raise StorageError('installation drive changed after the proposed layout was shown')
    if plan['status'] == 'insufficient':
        raise StorageError('actual installation drive capacity is insufficient for user data')
    if plan['status'] == 'existing':
        progress('complete', 'Complete')
        if user:
            prepare_user(username, mountpoint=mountpoint)
        return dict(plan, success=True, message='User data partition is already mounted')
    state = read_state(state_path)
    if state is None:
        state = {'fingerprint': fingerprint, 'phase': 'planned', 'username': username}
        atomic_json(state_path, state)
    elif state.get('username') != username:
        raise StorageError('storage transaction belongs to a different account')
    data_device = Path(plan['data']['device'])
    if plan['status'] == 'available':
        progress('partition', 'Creating user-data partition')
        # A flashed image retains a backup GPT at the original image end.
        # Relocate it only after the drive identity and exact layout passed.
        command(['/usr/sbin/sfdisk', '--relocate', 'gpt-bak-std', str(disk)])
        spec = f"start={plan['data']['start']}, size={plan['data']['sectors']}, type={LINUX_TYPE}\n"
        command(['/usr/sbin/sfdisk', '--append', '--no-reread', '--no-tell-kernel',
                 '--wipe', 'never', '--wipe-partitions', 'never', str(disk)],
                input_text=spec, timeout=45)
        state['phase'] = 'partitioned'; atomic_json(state_path, state)
    command(['/usr/bin/partx', '--add', '--nr', '3', str(disk)], check=False)
    command(['/usr/bin/udevadm', 'settle', '--timeout=15'], check=False)
    if not data_device.is_block_device():
        raise StorageError('new partition is not visible to the kernel; confirm again after reboot')
    after = disk_plan(disk, root_partition, boot_partition, state_path=state_path,
                      fstab_path=fstab_path, mountpoint=mountpoint)
    if after['status'] not in ('interrupted', 'existing'):
        raise StorageError('new partition did not match the confirmed layout')
    kind = fs_type(data_device)
    if not kind:
        progress('filesystem', 'Creating filesystem')
        signatures = command(['/usr/sbin/wipefs', '--no-act', '--noheadings', str(data_device)])
        if signatures:
            raise StorageError('new partition contains an unexpected signature; refusing to format')
        command(['/usr/sbin/mkfs.ext4', '-F', '-L', 'NEUTRON_DATA', '-m', '0', str(data_device)],
                timeout=180)
    elif kind != 'ext4' or fs_label(data_device) != 'NEUTRON_DATA':
        raise StorageError('existing partition contains an unexpected filesystem')
    uuid = fs_uuid(data_device)
    if not re.fullmatch(r'[0-9a-fA-F-]{36}', uuid or ''):
        raise StorageError('new ext4 filesystem UUID could not be verified')
    state['phase'] = 'formatted'; state['uuid'] = uuid; atomic_json(state_path, state)
    progress('mount', 'Configuring persistent mount')
    mounted_uuid = command(['/usr/bin/findmnt', '-n', '-o', 'UUID', '--mountpoint', str(mountpoint)], check=False)
    if mounted_uuid and mounted_uuid != uuid:
        raise StorageError('another filesystem is mounted at the user-data location')
    if mountpoint.exists() and (mountpoint.is_symlink() or not mountpoint.is_dir()):
        raise StorageError('user-data mount location is linked or not a directory')
    if not mounted_uuid and mountpoint.exists() and any(mountpoint.iterdir()):
        raise StorageError('user-data mount location is populated; refusing to hide files')
    mountpoint.mkdir(parents=True, exist_ok=True)
    append_fstab(fstab_path, uuid, mountpoint)
    if not command(['/usr/bin/findmnt', '-n', '-o', 'UUID', '--mountpoint', str(mountpoint)], check=False):
        command(['/usr/bin/mount', '-t', 'ext4', str(data_device), str(mountpoint)])
    if command(['/usr/bin/findmnt', '-n', '-o', 'UUID', '--mountpoint', str(mountpoint)]) != uuid:
        raise StorageError('user-data filesystem mount verification failed')
    os.chown(mountpoint, 0, 0)
    os.chmod(mountpoint, 0o755)
    if user:
        prepare_user(username, mountpoint=mountpoint)
    state['phase'] = 'mounted'; atomic_json(state_path, state)
    progress('verify', 'Verifying storage')
    result = disk_plan(disk, root_partition, boot_partition, state_path=state_path,
                       fstab_path=fstab_path, mountpoint=mountpoint)
    if result['status'] != 'existing':
        raise StorageError('user-data filesystem did not pass final verification')
    progress('complete', 'Complete')
    return dict(result, success=True, message='User data partition created and mounted')


def prepare_user(username, *, mountpoint=MOUNTPOINT):
    """Create only the named human's canonical home and applications leaf.

    This action never chooses a disk, partitions, formats or hides existing
    directories. It can run after useradd and again after mounting DATA.
    """
    if not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', username):
        raise StorageError('invalid interactive account name')
    user = pwd.getpwnam(username)
    home = mountpoint / username
    if (user.pw_uid < 1000 or user.pw_dir != str(home) or
            user.pw_shell.endswith(('nologin', 'false'))):
        raise StorageError('user-data owner must be the canonical interactive account')
    if mountpoint.is_symlink() or (mountpoint.exists() and not mountpoint.is_dir()):
        raise StorageError('user-data root is linked or not a directory')
    mountpoint.mkdir(parents=True, exist_ok=True)
    parent = mountpoint.stat(follow_symlinks=False)
    if parent.st_uid != 0 or parent.st_mode & 0o022:
        raise StorageError('user-data root is not root controlled')
    for directory in (home, home / 'apps'):
        if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
            raise StorageError('human data directory is linked or not a directory')
        directory.mkdir(exist_ok=True)
        # The human may own an existing apps directory. Never follow a link
        # swapped in between inspection and the privileged ownership change.
        descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fchown(descriptor, user.pw_uid, user.pw_gid)
            os.fchmod(descriptor, 0o700)
        finally:
            os.close(descriptor)
    return {'success': True, 'home': str(home), 'apps': str(home / 'apps')}


def main(argv):
    if os.geteuid() != 0 or len(argv) < 2:
        raise StorageError('root and a storage action are required')
    lock_fd = os.open('/run/neutronos-storage-setup.lock',
                      os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        lock_info = os.fstat(lock_fd)
        if not stat.S_ISREG(lock_info.st_mode) or lock_info.st_uid != 0 or lock_info.st_mode & 0o077:
            raise StorageError('storage lock has unsafe ownership or permissions')
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        return locked_main(argv)
    finally:
        os.close(lock_fd)


def locked_main(argv):
    if argv[1] == 'prepare-user' and len(argv) == 3:
        print(json.dumps(prepare_user(argv[2]), sort_keys=True, separators=(',', ':')))
        return 0
    disk, root, boot = live_installation_disk()
    if argv[1] == 'inspect' and len(argv) == 2:
        result = disk_plan(disk, root, boot)
    elif argv[1] == 'provision' and len(argv) == 4:
        if not re.fullmatch(r'[0-9a-f]{64}', argv[2]) or not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', argv[3]):
            raise StorageError('invalid storage confirmation or account')
        result = provision_disk(disk, root, boot, argv[2], argv[3])
    else:
        raise StorageError('unsupported storage action')
    print(json.dumps(result, sort_keys=True, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main(sys.argv))
    except (StorageError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'success': False, 'message': str(error)}, separators=(',', ':')))
        raise SystemExit(1)
