from pathlib import Path
import sys,time,selectors
sys.path.insert(0,'/opt/neutronos/tests/gemini')
from controller_sdl055 import p,Source
assert Path('/sys/class/dmi/id/product_name').read_text().strip()=='Standard PC (Q35 + ICH9, 2009)'
source=Source(9)
class ExplicitFixtureService(p.Service):
 def scan(self):
  self.last_scan=time.monotonic()
  if not self.pads:
   pad=p.Pad(source.path,0,self.nodes,self.profile);pad.switch(self.modal);self.pads[pad.fd]=pad;self.selector.register(pad.fd,selectors.EVENT_READ,'pad');self.send({'event':'connected','name':pad.name,'slot':pad.slot,'identity':pad.identity,'transport':3})
  for pad in self.pads.values():pad.publish_nodes(self.nodes)
try:ExplicitFixtureService().run()
finally:source.close()
