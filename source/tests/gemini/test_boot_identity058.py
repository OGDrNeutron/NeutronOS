"""Boot collision prevention uses only in-memory images; never a block device."""
import importlib.util,io,json,struct,unittest,uuid,zlib
from pathlib import Path
S=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('recovery_images',S/'deployment/usr/local/lib/neutronos/neutronos_recovery_image.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
ROOT='9e2d396c-2750-4b80-9f12-0cae15609ce7'
PART='f3ff7ea9-2f98-4aff-9f98-ffd91f3b6e67'
def fixture():
 data=bytearray(16384);entries=bytearray(256)
 entries[:16]=uuid.UUID('0fc63daf-8483-4772-8e79-3d69d8477de4').bytes_le
 entries[16:32]=uuid.UUID(PART).bytes_le;struct.pack_into('<QQ',entries,32,8,15)
 entries[128:144]=uuid.UUID('c12a7328-f81f-11d2-ba4b-00a0c93ec93b').bytes_le
 entries[144:160]=uuid.uuid4().bytes_le;struct.pack_into('<QQ',entries,160,16,31)
 data[1024:1280]=entries;header=bytearray(512);header[:8]=b'EFI PART';struct.pack_into('<I',header,12,92)
 struct.pack_into('<QIII',header,72,2,2,128,zlib.crc32(entries)&0xffffffff)
 struct.pack_into('<I',header,16,zlib.crc32(header[:92])&0xffffffff);data[512:1024]=header
 data[4096+1080:4096+1082]=b'\x53\xef';data[4096+1128:4096+1144]=uuid.UUID(ROOT).bytes
 data[8192+82:8192+87]=b'FAT32';struct.pack_into('<I',data,8192+67,0xFBD22941)
 return data
class BootIdentity(unittest.TestCase):
 def test_reads_actual_uuid_and_partuuid_formats(self):
  ids=m.inspect_boot_identities(io.BytesIO(fixture()));self.assertEqual(ids['uuid'],{ROOT,'fbd2-2941'});self.assertIn(PART,ids['partuuid'])
 def test_duplicate_root_uuid_rejected_before_writes(self):
  ids=m.inspect_boot_identities(io.BytesIO(fixture()))
  with self.assertRaisesRegex(ValueError,'Duplicate boot UUID'):m.reject_boot_identity_collisions(ids,[{'path':'/dev/nvme0n1','children':[{'path':'/dev/nvme0n1p2','uuid':ROOT.upper()}]}],'/dev/test-target')
 def test_duplicate_partuuid_rejected_without_fs_uuid(self):
  ids=m.inspect_boot_identities(io.BytesIO(fixture()))
  with self.assertRaisesRegex(ValueError,'Duplicate boot PARTUUID'):m.reject_boot_identity_collisions(ids,[{'path':'/dev/other','partuuid':PART}],'/dev/test-target')
 def test_duplicate_efi_uuid_rejected(self):
  with self.assertRaisesRegex(ValueError,'Duplicate boot UUID'):m.reject_boot_identity_collisions(m.inspect_boot_identities(io.BytesIO(fixture())),[{'path':'/dev/other','uuid':'FBD2-2941'}],'/dev/test-target')
 def test_selected_offline_target_is_excluded(self):
  m.reject_boot_identity_collisions(m.inspect_boot_identities(io.BytesIO(fixture())),[{'path':'/dev/test-target','children':[{'path':'/dev/test-target1','uuid':ROOT}]}],'/dev/test-target')
 def test_unique_other_disks_accepted(self):
  m.reject_boot_identity_collisions(m.inspect_boot_identities(io.BytesIO(fixture())),[{'path':'/dev/other','uuid':str(uuid.uuid4())}],'/dev/test-target')
 def test_corrupt_gpt_rejected(self):
  image=fixture();image[600]^=1
  with self.assertRaisesRegex(ValueError,'checksum'):m.inspect_boot_identities(io.BytesIO(image))
 def test_truncated_filesystem_rejected(self):
  with self.assertRaisesRegex(ValueError,'Truncated'):m.inspect_boot_identities(io.BytesIO(fixture()[:9000]))
if __name__=='__main__':unittest.main(verbosity=2)
