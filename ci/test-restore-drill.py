#!/usr/bin/env python3
"""Fixture-only checks: no real Docker, restic repository or secrets."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

MOCK = r'''#!/usr/bin/env python3
import gzip, json, os, pathlib, signal, sqlite3, sys
a=sys.argv[1:]; role=os.environ['DRILL_ROLE']; mode=os.environ['DRILL_MODE']
state=pathlib.Path(os.environ['DRILL_STATE']); command=pathlib.Path(sys.argv[0]).name
def pos(flag): return a[a.index(flag)+1]
if command == 'restic-peer':
    if 'snapshots' in a:
        print(json.dumps([{'id':'a'*64,'hostname':'wrong' if mode=='wrong-host' else ('bandit-lab' if role=='lab' else 'bandit')}]))
    else:
        assert '--verify' in a and '--no-lock' in a and '--no-cache' in a
        root=pathlib.Path(pos('--target')); root.mkdir()
        if mode=='restore-failure': sys.exit(1)
        if role=='laptop':
            p=root/'home/vino/Documents/a.txt'; p.parent.mkdir(parents=True); p.write_text('fixture')
        else:
            stage=root/'var/backup/restic-staging-peer'
            (root/'srv/containers/aiia/content-data').mkdir(parents=True)
            for rel in ['vaultwarden/db.sqlite3','mrija/mail_index.sqlite']:
                p=stage/rel; p.parent.mkdir(parents=True); db=sqlite3.connect(p); db.execute('create table fixture(x)'); db.close()
                if rel.startswith('vaultwarden'):
                    db=sqlite3.connect(p); db.execute('create table users(id)'); db.execute('insert into users values (1)'); db.commit(); db.close()
            for p in [stage/'aiia/mysql.sql.gz',root/'var/backup/postgresql/all.sql.gz']:
                p.parent.mkdir(parents=True,exist_ok=True)
                with gzip.open(p,'wt') as f: f.write('CREATE TABLE fixture(x INT);')
            w=stage/'minecraft'; (w/'world/region').mkdir(parents=True); (w/'plugins').mkdir()
            for p in [w/'server.properties',w/'paper-fixture.jar',w/'world/region/r.0.0.mca']: p.write_text('fixture')
            if mode=='symlink': (stage/'escape').symlink_to('/srv/live')
    sys.exit()
if command=='sleep': sys.exit()
with (state/'calls.jsonl').open('a') as f: f.write(json.dumps(a)+'\n')
if a[0]=='image': sys.exit()
if a[0]=='run':
    name=pos('--name'); assert name.startswith('restore-drill-')
    assert '--pull' in a and pos('--pull')=='never'
    assert not any(x in ['-p','-P','--publish','--publish-all','--volumes-from','--privileged'] for x in a)
    if '-v' in a:
        mount=pos('-v'); assert mount.startswith(os.environ['TMPDIR']+'/restore-drill-') and mount.endswith(':/data')
        assert not pathlib.Path(mount[:-6]+'/plugins').exists()
    if 'mysql' in name or 'postgres' in name: assert pos('--network')=='none' and '--tmpfs' in a
    (state/name).touch()
    if mode=='signal': os.kill(os.getppid(), signal.SIGTERM)
    print(name); sys.exit()
if a[0]=='rm':
    name=a[-1]; assert name.startswith('restore-drill-')
    if mode=='cleanup-failure': sys.exit(1)
    (state/name).unlink(missing_ok=True); sys.exit()
if a[0]=='logs':
    print('ERROR] fixture failure' if mode=='mc-error' else ('waiting' if mode in ['mc-timeout','mc-exit'] else 'Done (1s)'))
elif a[0]=='inspect': print('false' if mode=='mc-exit' else 'true')
elif a[0]=='exec':
    name=a[2] if a[1]=='-i' else a[1]; assert name.startswith('restore-drill-')
    if a[1]=='-i':
        data=sys.stdin.read(); assert data
        if 'mysql' in name:
            assert 'SELECT COUNT(*)' in data and '-N' in a
            print('0' if mode=='empty-db' else '3')
        sys.exit(1 if mode=='import-failure' else 0)
    if '-e' in a or '-Atc' in a: print('0' if mode=='empty-db' else '3')
elif a[0]!='stop': raise AssertionError(a)
'''

script = Path(sys.argv[1] if len(sys.argv) > 1 else 'tools/restore-drill.sh').resolve()
with tempfile.TemporaryDirectory(prefix='drill-fixture-') as temp:
    base = Path(temp)
    commands = base / 'bin'
    commands.mkdir()
    for name in ['restic-peer', 'docker', 'sleep']:
        p = commands / name
        p.write_text(MOCK)
        p.chmod(0o755)
    for role, mode, ok in [
        ('laptop','ok',True), ('lab','ok',True), ('lab','wrong-host',False),
        ('lab','restore-failure',False), ('lab','symlink',False),
        ('lab','import-failure',False), ('lab','empty-db',False),
        ('lab','mc-timeout',False), ('lab','mc-error',False), ('lab','cleanup-failure',False),
        ('lab','mc-exit',False), ('lab','signal',False),
    ]:
        root = base / f'{role}-{mode}'
        root.mkdir()
        state = root / 'state'
        state.mkdir()
        scratch = root / 'scratch'
        scratch.mkdir()
        env = os.environ | {'PATH':str(commands)+':'+os.environ['PATH'], 'TMPDIR':str(scratch),
            'DRILL_ROLE':role,'DRILL_MODE':mode,'DRILL_STATE':str(state),
            'PG_IMAGE':'postgres:16@sha256:'+'b'*64}
        result = subprocess.run(['bash',str(script),role],env=env,capture_output=True,text=True,timeout=30)
        assert (result.returncode == 0) == ok, (role,mode,result.stdout,result.stderr)
        if mode == 'cleanup-failure':
            assert 'cleanup failed' in result.stderr and list(scratch.iterdir())
        else:
            assert not list(scratch.iterdir()), (role,mode,'scratch leaked')
            assert not list(state.glob('restore-drill-*')), (role,mode,'container leaked')
        if role == 'laptop' or mode in ['wrong-host','restore-failure','symlink']:
            assert not (state/'calls.jsonl').exists(), 'Docker used before input checks'
print('ok: 12 fixture cases; scratch/container cleanup, isolation, SIGTERM and failure propagation')
