import importlib.util,sys,tempfile,unittest,itertools,json
from pathlib import Path
from datetime import datetime,timezone,timedelta
D=Path(__file__).resolve().parents[2]/'deployment/usr/local/lib/neutronos'
sys.path.insert(0,str(D));sp=importlib.util.spec_from_file_location('security058',D/'neutron-securityd.py');m=importlib.util.module_from_spec(sp);sys.modules[sp.name]=m;sp.loader.exec_module(m)
class Policy(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.c=m.SecurityCore.__new__(m.SecurityCore);self.c.state_dir=Path(self.tmp.name)
  self.c.config={'enforcementEnabled':True,'learningMode':False,'recovery':{'configured':True}}
  self.c.events=[];self.c.integrity_changes=[];self.c.firewall_health={'protectionState':'HEALTHY'}
 def tearDown(self):self.tmp.cleanup()
 def event(self,severity=1,**kw):
  return dict({'id':'one','timestamp':datetime.now(timezone.utc).isoformat(),'category':'test','severity':severity,'message':'subject'},**kw)
 def test_all_configuration_combinations_and_cumulative_penalties(self):
  for recovery,enforcement,learning in itertools.product((False,True),repeat=3):
   self.c.config={'recovery':{'configured':recovery},'enforcementEnabled':enforcement,'learningMode':learning}
   self.assertEqual(self.c.calculate_score(),100-(0 if recovery else 10)-(0 if enforcement else 15)-(5 if learning else 0))
 def test_event_severity_rules(self):
  for level,penalty in [(1,1),(2,2),(3,4),(4,8),(5,15)]:
   self.c.events=[self.event(level)];self.assertEqual(self.c.calculate_score(),100-penalty)
 def test_acknowledgement_never_clears_penalty_resolution_does(self):
  self.c.events=[self.event(5,acknowledged=True)];self.assertEqual(self.c.calculate_score(),85)
  self.c.events[0]['resolved']=True;self.assertEqual(self.c.calculate_score(),100)
 def test_deduplicated_incidents_take_highest_severity(self):
  self.c.events=[self.event(1,incidentKey='same'),self.event(5,incidentKey='same')];self.assertEqual(self.c.calculate_score(),85)
 def test_decay_and_persistent_critical(self):
  for level,hours in [(1,1),(2,2),(3,7),(4,25),(5,240)]:
   e=self.event(level);e['timestamp']=(datetime.now(timezone.utc)-timedelta(hours=hours)).isoformat();self.c.events=[e];self.assertEqual(self.c.calculate_score(),85 if level==5 else 100)
 def test_integrity_reads_changes_and_incident_grouping(self):
  self.c.integrity_changes=[{'path':'/etc/test/config','change':'read'}];self.assertEqual(self.c.calculate_score(),93)
  self.c.integrity_changes=[{'path':'/etc/test/config','change':'modified'},{'path':'/etc/test/other','change':'removed'}];self.assertEqual(self.c.calculate_score(),85)
 def test_integrity_notification_not_double_counted(self):
  self.c.integrity_changes=[{'path':'/etc/test/config','change':'modified'}]
  self.c.events=[self.event(5,category='integrity',source='file-integrity',title='Protected file changed')];self.assertEqual(self.c.calculate_score(),85)
 def test_caps_and_cumulative_deductions(self):
  self.c.config={'enforcementEnabled':False,'learningMode':True,'recovery':{'configured':False}}
  self.c.events=[self.event(5,incidentKey=str(i)) for i in range(10)]
  self.c.integrity_changes=[{'path':f'/etc/area{i}/config','change':'modified'} for i in range(10)]
  b=self.c.calculate_score_breakdown();self.assertEqual((b['posturePenalty'],b['integrityPenalty'],b['eventPenalty'],b['score']),(30,60,40,0))
 def test_firewall_protection_penalties(self):
  for state,score in [('HEALTHY',100),('DEGRADED',92),('CRITICAL',85)]:
   self.c.firewall_health={'protectionState':state};self.assertEqual(self.c.calculate_score(),score)
 def test_authentication_severity_and_privileged_escalation(self):
  for count,severity in [(1,1),(2,2),(5,3),(15,4),(25,5)]:
   self.assertEqual(self.c.authentication_score_severity({'attempts':count,'category':'authentication'}),severity)
   self.assertEqual(self.c.authentication_score_severity({'attempts':count,'category':'privilege'}),min(5,severity+1))
 def test_commissioning_cutoff_and_expected_events(self):
  (self.c.state_dir/'commissioning.json').write_text(json.dumps({'notBefore':datetime.now(timezone.utc).isoformat()}))
  e=self.event(5);e['timestamp']=(datetime.now(timezone.utc)-timedelta(days=1)).isoformat();self.c.events=[e];self.assertEqual(self.c.calculate_score(),100)
  self.c.events=[self.event(5,expected=True)];self.assertEqual(self.c.calculate_score(),100)
 def test_reference_policy_restored_exactly(self):
  reference=Path('/NeutronMedia/NeutronOS-Gemini/reference/installed/local/lib/neutronos/neutron-securityd.py').read_text()
  start='    def commissioning_cutoff(';end='    def write_state('
  actual=(D/'neutron-securityd.py').read_text()
  self.assertEqual(actual[actual.index(start):actual.index(end,actual.index(start))],reference[reference.index(start):reference.index(end,reference.index(start))])
if __name__=='__main__':unittest.main(verbosity=2)
