#!/usr/bin/env python3
"""Return display-service-created human files to their passwd owner."""
import os
from pathlib import Path
import pwd
import stat
import sys
sys.dont_write_bytecode = True
import subprocess
import importlib.util


def reconcile_home(home, human_uid, human_gid, service_uid):
    """Use descriptors and inode checks; never follow links or cross filesystems."""
    root_fd = os.open(home, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    changed = 0
    try:
        device = os.fstat(root_fd).st_dev
        for relative, directories, files, directory_fd in os.fwalk('.', dir_fd=root_fd, follow_symlinks=False):
            info = os.fstat(directory_fd)
            if info.st_dev != device:
                directories[:] = []
                continue
            if info.st_uid == service_uid:
                os.fchown(directory_fd, human_uid, human_gid)
                if relative != '.' and not any(part in ('.ssh', '.gnupg') for part in Path(relative).parts):
                    anchored = '/proc/' + str(os.getpid()) + '/fd/' + str(directory_fd)
                    subprocess.run(['/usr/bin/setfacl', '-m', 'u:' + str(service_uid) + ':rwx,d:u:' + str(service_uid) + ':rwx', anchored], check=True)
                changed += 1
            if relative == './installed':
                directories[:] = [name for name in directories if name != 'docker-data']
            safe_directories = []
            for name in directories:
                try:
                    info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                    if stat.S_ISDIR(info.st_mode) and info.st_dev == device:
                        safe_directories.append(name)
                except FileNotFoundError:
                    continue
            directories[:] = safe_directories
            for name in files:
                fd = None
                try:
                    info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                    if info.st_uid != service_uid or info.st_dev != device or info.st_nlink != 1 or not stat.S_ISREG(info.st_mode):
                        continue
                    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd)
                    actual = os.fstat(fd)
                    if actual.st_nlink == 1 and (actual.st_dev, actual.st_ino, actual.st_uid) == (info.st_dev, info.st_ino, service_uid):
                        os.fchown(fd, human_uid, human_gid)
                        if not any(part in ('.ssh', '.gnupg') for part in Path(relative).parts):
                            anchored = '/proc/' + str(os.getpid()) + '/fd/' + str(fd)
                            subprocess.run(['/usr/bin/setfacl', '-m', 'u:' + str(service_uid) + ':rw', anchored], check=True)
                        changed += 1
                except FileNotFoundError:
                    continue
                finally:
                    if fd is not None:
                        os.close(fd)
    finally:
        os.close(root_fd)
    return changed


def main():
    if os.geteuid() != 0 or len(sys.argv) != 1:
        raise SystemExit('root required; no path arguments accepted')
    if not os.path.ismount('/NeutronOS'):
        raise SystemExit('canonical USER DATA must be mounted')
    service = pwd.getpwnam('neutronos')
    if service.pw_uid >= 1000 or not service.pw_shell.endswith(('nologin', 'false')):
        raise SystemExit('unexpected service identity')
    for human in pwd.getpwall():
        if human.pw_uid < 1000 or human.pw_uid == service.pw_uid:
            continue
        if (human.pw_dir != '/NeutronOS/' + human.pw_name or
                human.pw_shell.endswith(('nologin', 'false'))):
            continue
        home = Path(human.pw_dir)
        if home.is_dir() and not home.is_symlink():
            # HOME itself allows traversal only; never inherit service access to .ssh.
            subprocess.run(['/usr/bin/setfacl', '-m', f'u:{service.pw_uid}:--x', str(home)], check=True)
            for leaf in ('apps', 'Downloads', 'Documents', 'Pictures', 'Videos', 'Music', 'Games', 'cache'):
                directory = home / leaf
                if directory.is_symlink():
                    raise SystemExit('human storage directory must not be a symlink')
                directory.mkdir(mode=0o700, exist_ok=True)
                if directory.stat().st_dev != home.stat().st_dev:
                    raise SystemExit('human storage must remain on DATA')
                descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
                try:
                    os.fchown(descriptor, human.pw_uid, human.pw_gid)
                    anchored = '/proc/' + str(os.getpid()) + '/fd/' + str(descriptor)
                    subprocess.run(['/usr/bin/setfacl', '-m', f'u:{service.pw_uid}:rwx,d:u:{service.pw_uid}:rwx', anchored], check=True)
                finally:
                    os.close(descriptor)
            reconcile_home(home, human.pw_uid, human.pw_gid, service.pw_uid)


if __name__ == '__main__':
    main()
