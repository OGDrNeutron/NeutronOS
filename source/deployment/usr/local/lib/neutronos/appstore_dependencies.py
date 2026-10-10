"""APT-backed NAPP requirements. Called only by the authenticated root helper.

No application code, maintainer scripts, arbitrary apt arguments or automatic
removal are accepted. APT's graph and manual marks remain authoritative.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

PACKAGE = re.compile(r'^[a-z0-9][a-z0-9+.-]*(?::[a-z0-9][a-z0-9-]*)?$')
APP = re.compile(r'^[a-z0-9][a-z0-9._-]{0,95}$')
RUNTIME = re.compile(r'^(?:wine|libwine|fonts-wine|proton|dosbox|scummvm|dxvk|vkd3d|libvkd3d|winetricks)(?:[0-9.+:\-]|$)')

class Dependencies:
    def __init__(self, state=Path('/var/lib/neutronos/app-store')):
        self.state = Path(state)
        self.origin = self.state/'dependency-origins.json'

    @staticmethod
    def command(args, check=True):
        env = dict(os.environ, LC_ALL='C', DEBIAN_FRONTEND='noninteractive')
        result = subprocess.run(args, env=env, text=True, capture_output=True, timeout=1800)
        if check and result.returncode:
            raise RuntimeError('Dependency operation failed: '+result.stderr.strip()[-1600:])
        return result

    @staticmethod
    def name(app):
        if not APP.fullmatch(app): raise ValueError('Invalid app identity')
        return 'neutronos-appdeps-'+hashlib.sha256(app.encode()).hexdigest()[:32]

    def installed(self):
        result = self.command(['dpkg-query','-W','-f=${binary:Package}\t${Status}\n'])
        return {line.split('\t')[0] for line in result.stdout.splitlines() if line.endswith('\tinstall ok installed')}

    def ledger(self):
        if not self.origin.exists(): return {'schema':1,'introduced':[]}
        if self.origin.is_symlink() or self.origin.stat().st_uid != os.geteuid():
            raise RuntimeError('Unsafe dependency provenance file')
        data = json.loads(self.origin.read_text())
        if data.get('schema') != 1 or not isinstance(data.get('introduced'),list):
            raise RuntimeError('Invalid dependency provenance')
        return data

    def remember(self, packages):
        data = self.ledger()
        data['introduced'] = sorted(set(data['introduced']) | set(packages))
        self.state.mkdir(parents=True,exist_ok=True)
        fd, path = tempfile.mkstemp(prefix='.dependency-origins-',dir=self.state)
        try:
            with os.fdopen(fd,'w') as handle:
                json.dump(data,handle,sort_keys=True);handle.write('\n');handle.flush();os.fsync(handle.fileno())
            os.chmod(path,0o600);os.replace(path,self.origin)
        finally:
            Path(path).unlink(missing_ok=True)

    def require(self, app, dependencies, *, install_missing=True):
        deps = sorted(set(dependencies))
        if any(not isinstance(p,str) or not PACKAGE.fullmatch(p) for p in deps):
            raise ValueError('Invalid signed Debian requirement')
        before = self.installed()
        def present(p):return p in before or any(q.split(':')[0]==p for q in before)
        missing = [p for p in deps if not present(p)]
        if missing and not install_missing:
            raise RuntimeError('Rollback requires unavailable Debian dependencies: '+', '.join(missing))
        if missing:
            try:
                # Fresh release images deliberately omit APT indexes. Refresh
                # configured signed repository metadata only inside the user's
                # authorized missing-dependency transaction; never upgrade.
                self.command(['apt-get','update','--error-on=any'])
                self.command(['apt-get','install','-y','--no-remove','--no-upgrade','--no-install-recommends','--mark-auto',*missing])
            finally:
                introduced = self.installed()-before
                self.remember(introduced)
                protected = sorted(p for p in introduced if RUNTIME.match(p))
                if protected:self.command(['apt-mark','manual',*protected])
        # A root-created metadata-only package cannot execute lifecycle code.
        name = self.name(app)
        with tempfile.TemporaryDirectory(prefix='appdeps-',dir=self.state) as directory:
            root = Path(directory)/'root';(root/'DEBIAN').mkdir(parents=True)
            # The production state directory is setgid/sticky. Do not inherit
            # those bits into a Debian control directory or the archive root.
            root.chmod(0o755);(root/'DEBIAN').chmod(0o755)
            control = 'Package: '+name+'\nVersion: 1.'+str(int(hashlib.sha256('\n'.join(deps).encode()).hexdigest()[:12],16))+'\nArchitecture: all\nSection: metapackages\nPriority: optional\nMaintainer: NeutronOS App Store\nDescription: Verified NAPP dependency ownership for '+app+'\n'
            if deps:control += 'Depends: '+', '.join(deps)+'\n'
            (root/'DEBIAN/control').write_text(control)
            archive = str(Path(directory)/'requirements.deb')
            self.command(['dpkg-deb','--build','--root-owner-group',str(root),archive])
            self.command(['dpkg','--force-downgrade','--install',archive])
            self.command(['apt-mark','manual',name])
        return {'mechanism':'apt-metapackage-v1','package':name,'dependencies':deps,'installed':missing}

    def release(self, app):
        name = self.name(app)
        if name in self.installed():self.command(['dpkg','--remove',name])

    def restore(self, app, prior):
        if isinstance(prior,dict) and prior.get('dependencyOwnership',{}).get('mechanism')=='apt-metapackage-v1':
            self.require(app,prior.get('dependencies',[]),install_missing=False)
        else:self.release(app)

    def eligibility(self):
        # Simulation only. Never execute this plan automatically. Limit ownership
        # to newly introduced packages; preserve pre-existing Debian/OS packages.
        result = self.command(['apt-get','--simulate','autoremove'],check=False)
        if result.returncode:return {'known':False,'eligible':[],'error':result.stderr.strip()[-1200:]}
        actual = set(re.findall(r'^Remv ([a-z0-9][a-z0-9+.:\-]*)\b',result.stdout,re.M))
        introduced = set(self.ledger()['introduced'])
        eligible = sorted(p for p in actual if (p in introduced or any(q.split(':')[0]==p for q in introduced)) and not RUNTIME.match(p))
        return {'known':True,'eligible':eligible,'automaticallyRemoved':[],
                'policy':'APT simulation; only App Store-introduced orphan dependencies. Removal requires separate review. Optional gaming runtimes are retained.'}
