import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class Alpha1BuilderSshSafetyContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = (ROOT / "scripts/build-neutronos-alpha1-image.sh").read_text(encoding="utf-8")

    def test_no_process_killing_or_host_service_mutation(self):
        for token in ("fuser", "pkill", "killall", "systemctl start", "systemctl stop",
                      "systemctl restart", "nmcli", "networkctl", "nsenter"):
            self.assertNotIn(token, self.text)
        self.assertNotRegex(self.text, r"(?m)^\s*kill(?:\s|[-])")
        self.assertNotRegex(self.text, r"(?m)^\s*(?:reboot|shutdown|poweroff)(?:\s|$)")

    def test_private_mount_namespace_is_mandatory_for_build_phase(self):
        self.assertIn("unshare --mount --propagation private", self.text)
        self.assertIn("Entering private mount namespace", self.text)
        self.assertIn("NEUTRONOS_BUILDER_MOUNT_NS", self.text)
        self.assertIn("recover_stale_release_resources", self.text)

    def test_host_run_is_never_bound_and_image_run_is_private(self):
        self.assertNotIn('mount --bind /run', self.text)
        self.assertNotIn('mount --rbind /run', self.text)
        self.assertIn('mount -t tmpfs -o mode=755 tmpfs "$ROOT/run"', self.text)
        self.assertIn("policy-rc.d", self.text)

    def test_stale_run_uses_mount_detach_not_process_identity(self):
        self.assertIn('known_pseudo_mount "$target" "$source" "$fstype"', self.text)
        self.assertIn('umount -l "$target"', self.text)
        self.assertNotIn("release_busy_holders", self.text)
        self.assertNotIn("builder_process", self.text)

    def test_exact_image_and_live_root_guards_remain(self):
        self.assertIn('IMAGE="$PROJECT/NeutronOS.a1.img"', self.text)
        self.assertIn('[[ "$r" != / && "$r" != "$PROJECT"', self.text)
        self.assertIn('losetup -j "$IMAGE"', self.text)
        self.assertIn('Root partition already expanded — skipping partition resize', self.text)
        self.assertNotIn("-j3", self.text)


if __name__ == "__main__":
    unittest.main()
