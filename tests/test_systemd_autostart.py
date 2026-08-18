from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "deploy" / "systemd" / "install.sh"
UNINSTALLER = ROOT / "deploy" / "systemd" / "uninstall.sh"


class SystemdAutostartContractTest(unittest.TestCase):
    def test_installer_renders_expected_intranet_unit(self) -> None:
        result = subprocess.run(
            ["sh", str(INSTALLER), "--dry-run", "Intranet", "ci-host"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = result.stdout

        self.assertIn("Wants=network-online.target", output)
        self.assertIn("After=network-online.target", output)
        self.assertIn("Type=oneshot", output)
        self.assertIn("RemainAfterExit=yes", output)
        self.assertIn("ExecStart=/bin/sh", output)
        self.assertIn("deploy/start_all.sh\" Intranet ci-host", output)
        self.assertIn("ExecStop=/bin/sh", output)
        self.assertIn("deploy/stop_all.sh\"", output)
        self.assertIn("Restart=on-failure", output)
        self.assertIn("RestartSec=10", output)
        self.assertIn("KillMode=control-group", output)
        self.assertIn("NoNewPrivileges=true", output)
        self.assertIn("WantedBy=multi-user.target", output)

    def test_installer_requires_host_for_intranet(self) -> None:
        result = subprocess.run(
            ["sh", str(INSTALLER), "--dry-run", "Intranet"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires server-host", result.stdout)

    def test_installer_renders_local_without_public_host_argument(self) -> None:
        result = subprocess.run(
            ["sh", str(INSTALLER), "--dry-run", "Local"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )

        self.assertIn("deploy/start_all.sh\" Local", result.stdout)
        self.assertNotIn("Intranet ci-host", result.stdout)

    def test_uninstaller_exists(self) -> None:
        self.assertTrue(UNINSTALLER.is_file())


if __name__ == "__main__":
    unittest.main()
