import ast,datetime,importlib.util,json,subprocess,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('napp055',ROOT/'scripts/neutronos-napp-verify.py');napp=importlib.util.module_from_spec(spec);spec.loader.exec_module(napp)
class NativeRequirements(unittest.TestCase):
 def test_signed_runtime_requirements_fail_closed(self):
  with tempfile.TemporaryDirectory() as directory:
   root=Path(directory);v=root/'version';c=root/'caps'
   v.write_text(json.dumps({'version':'0.5.5'}));c.write_text(json.dumps({'schema':1,'capabilities':{'package-session':1},'qtVersion':'6.8.2'}))
   def check(req):napp.validate_os_requirements({'osRequirements':req},version_path=v,capability_path=c,require_owner=False)
   check({'minimumVersion':'0.5.5','capabilities':{'package-session':1},'qtVersion':'6.8.2'})
   for req in [{'minimumVersion':'0.5.6'},{'capabilities':{'missing':1}},{'capabilities':{'package-session':2}},{'capabilities':{'package-session':True}},{'qtVersion':'6.9.0'},{'minimumVersion':'unknown'}]:
    with self.subTest(requirements=req),self.assertRaises(napp.Rejected):check(req)
   c.unlink()
   with self.assertRaises(napp.Rejected):check({'capabilities':{'package-session':1}})
 def test_simulation_matches_actual_daemon_scoring(self):
  tree=ast.parse((ROOT/'deployment/usr/local/lib/neutronos/neutron-securityd.py').read_text());method=next(n for n in ast.walk(tree) if isinstance(n,ast.FunctionDef) and n.name=='calculate_score')
  env={'datetime':datetime.datetime,'timezone':datetime.timezone,'timedelta':datetime.timedelta,'parse_time':lambda s:datetime.datetime.fromisoformat(s) if s else None}
  exec(compile(ast.Module(body=[method],type_ignores=[]),'actual-daemon-score','exec'),env)
  now=datetime.datetime.now(datetime.timezone.utc);old=(now-datetime.timedelta(days=2)).isoformat();recent=now.isoformat()
  cases=[([],0,'SECURE'),([{'severity':2,'timestamp':recent}],1,'DEGRADED'),([{'severity':5,'timestamp':recent}]*8,8,'CRITICAL'),([{'severity':5,'timestamp':old},{'severity':4,'acknowledged':True,'timestamp':recent}],0,'SECURE'),([{'severity':i,'timestamp':recent} for i in range(1,6)],3,'SECURE')]
  expected=[env['calculate_score'](SimpleNamespace(events=e,failed_services=list(range(f)),firewall_health={'protectionState':s})) for e,f,s in cases]
  script=(ROOT/'qml/gemini/SecurityScoreSimulation.js').read_text().replace('.pragma library','')+'\nconsole.log(JSON.stringify('+json.dumps(cases)+'.map(c=>preview("Balanced",c[0],c[1],c[2]).score)))'
  actual=json.loads(subprocess.check_output(['node','-e',script],text=True));self.assertEqual(actual,expected)
if __name__=='__main__':unittest.main()
