import errno, importlib.util, pathlib, unittest
from unittest.mock import patch
MODULE=pathlib.Path(__file__).parents[2]/'deployment/usr/local/lib/neutronos/neutronos-controller-proxy.py'
spec=importlib.util.spec_from_file_location('gemini_input',MODULE);proxy=importlib.util.module_from_spec(spec);spec.loader.exec_module(proxy)
class ControllerTests(unittest.TestCase):
 def test_continuous_hold(self):
  g=proxy.Gesture();g.event('usb',1,10)
  self.assertEqual(g.poll(10.1),[]);self.assertEqual(g.poll(12.999),[]);self.assertEqual(g.poll(13),['usb']);self.assertEqual(g.poll(14),[])
  g.event('usb',0,14);g.event('usb',1,15);self.assertEqual(g.poll(17.9),[]);self.assertEqual(g.poll(18),['usb'])
 def test_repeated_events_do_not_reset_or_stitch_holds(self):
  g=proxy.Gesture();g.event('a',1,0);g.event('a',1,1);g.event('a',2,2);self.assertEqual(g.poll(3),['a'])
  g.event('a',0,4);g.event('a',1,5);g.event('a',0,7.9);g.event('a',1,8);self.assertEqual(g.poll(10),[])
 def test_transport_change_and_multiplayer_holds(self):
  g=proxy.Gesture();g.event('usb',1,0);g.disconnect('usb');g.event('bluetooth',1,2);g.event('player2',1,3)
  self.assertEqual(g.poll(4),[]);self.assertEqual(g.poll(5),['bluetooth']);self.assertEqual(g.poll(6),['player2'])
 def test_modal_releases_and_no_stuck_buttons(self):
  axes={0:(0,-32768,32767,0,128,0),2:(0,0,255,0,0,0),16:(0,-1,1,0,0,0)};gate=proxy.FocusGate(axes)
  self.assertTrue(gate.event(proxy.EV_KEY,304,1));self.assertTrue(gate.event(proxy.EV_ABS,0,32767));self.assertTrue(gate.event(proxy.EV_ABS,2,140))
  release=gate.switch(True);self.assertIn((proxy.EV_KEY,304,0),release);self.assertIn((proxy.EV_ABS,2,0),release)
  self.assertFalse(gate.event(proxy.EV_KEY,305,1));gate.switch(False)
  self.assertFalse(gate.event(proxy.EV_KEY,305,1));self.assertFalse(gate.event(proxy.EV_KEY,305,0));self.assertTrue(gate.event(proxy.EV_KEY,305,1))
  self.assertFalse(gate.event(proxy.EV_ABS,2,140));self.assertFalse(gate.event(proxy.EV_ABS,2,0));self.assertTrue(gate.event(proxy.EV_ABS,2,141))
 def test_analog_ranges_preserved(self):
  axes={0:(0,-32768,32767,0,128,0),2:(0,0,1023,0,0,0)};gate=proxy.FocusGate(axes)
  for value in (0,1,125,512,1023):self.assertTrue(gate.event(proxy.EV_ABS,2,value));self.assertEqual(gate.values[2],value)
 def test_identity_across_transport(self):
  usb=proxy.INPUT_ID.pack(3,1356,3302,1);bt=proxy.INPUT_ID.pack(5,1356,3302,2)
  self.assertEqual(proxy.controller_identity(usb,b'AA:BB','USB Pad'),proxy.controller_identity(bt,b'AA:BB','Bluetooth Pad'))
  self.assertNotEqual(proxy.controller_identity(usb,b'AA:BB','Pad'),proxy.controller_identity(bt,b'CC:DD','Pad'))
 def test_stick_deadzone_unblocks_transition(self):
  gate=proxy.FocusGate({0:(0,-32768,32767,0,128,0)})
  gate.event(proxy.EV_ABS,0,20000);gate.switch(True);gate.switch(False)
  self.assertFalse(gate.event(proxy.EV_ABS,0,30));self.assertTrue(gate.event(proxy.EV_ABS,0,20000))
 def test_overflow_cancels_uncertain_home_hold(self):
  pad=object.__new__(proxy.Pad);pad.fd=42;pad.slot=0;pad.dropped=False;pad.gate=type('Gate',(),{'modal':False})();pad.switch=lambda modal:None
  service=type('Sink',(),{})();service.events=[];service.send=service.events.append;service.gesture=proxy.Gesture();service.gesture.event(42,1,0)
  frame=proxy.EVENT.pack(0,0,proxy.EV_SYN,proxy.SYN_DROPPED,0)
  with patch.object(proxy.os,'read',return_value=frame):pad.read(service)
  self.assertTrue(pad.dropped);self.assertEqual(service.gesture.poll(4),[]);self.assertEqual(service.events,[{"event":"inputReset","slot":0}])
 def test_controller_without_unique_id(self):
  with patch.object(proxy,'read_ioctl',side_effect=OSError(errno.ENOENT,'No unique ID')):
   self.assertEqual(proxy.optional_unique(4),b'')
  with patch.object(proxy,'read_ioctl',side_effect=OSError(errno.EIO,'Device error')):
   with self.assertRaises(OSError):proxy.optional_unique(4)
 def test_neutral_per_axis(self):
  self.assertEqual(proxy.neutral(0,(0,-32768,32767,0,0,0)),0);self.assertEqual(proxy.neutral(0,(128,0,255,0,0,0)),128)
  self.assertEqual(proxy.neutral(2,(0,0,255,0,0,0)),0);self.assertEqual(proxy.neutral(16,(1,-1,1,0,0,0)),0)
if __name__=='__main__':unittest.main(verbosity=2)
