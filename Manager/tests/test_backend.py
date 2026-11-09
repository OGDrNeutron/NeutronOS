"""Minimum local API security smoke checks; does not modify Gemini."""
import asyncio
import os
import importlib.util
from pathlib import Path
import httpx

os.environ['MANAGER_PROXY_SECRET']='test-only-fixed-reverse-proxy-secret-64-characters-aaaaaaaaaaaaaaaa'
os.environ['MANAGER_READ_ONLY']='1'

APP=Path(__file__).resolve().parents[1]/'server'/'app.py'
spec=importlib.util.spec_from_file_location('neutron_manager',APP)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
BASE='https://neutronos.neutronprojects.com'

async def smoke():
    transport=httpx.ASGITransport(app=mod.app,client=('127.0.0.1',12345))
    async with httpx.AsyncClient(transport=transport,base_url=BASE) as client:
        # No Nginx-verified mTLS identity.
        r=await client.get('/api/session');assert r.status_code==403,r.text
        hdr={'X-Neutron-Client-Verified':'SUCCESS'}
        r=await client.get('/api/session',headers=hdr);assert r.status_code==403,'Forged mTLS header must be rejected'
        hdr['X-Neutron-Proxy-Secret']=os.environ['MANAGER_PROXY_SECRET']
        r=await client.get('/api/session',headers=hdr);assert r.status_code==200,r.text
        csrf=r.json()['csrf'];assert len(csrf)>20
        r=await client.get('/api/status',headers=hdr);assert r.status_code==200,r.text
        assert 'cpu_pct' in r.json() and 'user_used_gb' in r.json()
        r=await client.get('/api/services',headers=hdr);assert r.status_code==200
        r=await client.get('/api/apps',headers=hdr);assert r.status_code==200
        assert isinstance(r.json(),list)
        # A request without a valid CSRF token cannot change a service.
        w=dict(hdr,Origin=BASE)
        r=await client.post('/api/services/torrentlab/restart',headers=w)
        assert r.status_code==403,r.text
        w['X-CSRF-Token']=csrf
        r=await client.post('/api/system/power',headers=w,json={'action':'shutdown'})
        assert r.status_code==403,r.text
        print('PASS: Proxy secret + mTLS header enforced, live read routes, CSRF, all mutations locked.')

if __name__=='__main__':
    asyncio.run(smoke())
