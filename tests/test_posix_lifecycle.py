from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PosixLifecycleContractTest(unittest.TestCase):
    def test_start_records_managed_process_identity(self) -> None:
        text = (ROOT / "deploy" / "start_all.sh").read_text(encoding="utf-8")

        self.assertIn('printf \'%s\\n\' "$pid" >"$LOGS_DIR/$name.pid"', text)
        self.assertIn('pwd -P >"$LOGS_DIR/$name.cwd"', text)
        self.assertIn("'chan-suite-v1' >\"$LOGS_DIR/$name.managed\"", text)
        self.assertIn("awk '{print $22}' \"/proc/$pid/stat\"", text)

    def test_start_waits_for_all_application_ports(self) -> None:
        text = (ROOT / "deploy" / "start_all.sh").read_text(encoding="utf-8")

        self.assertIn("STARTUP_TIMEOUT=${CHAN_STARTUP_TIMEOUT:-60}", text)
        self.assertIn("wait_for_readiness()", text)
        self.assertIn('add_readiness_target "$name" "$port"', text)
        self.assertIn('start_frontend chan-portal', text)
        self.assertIn('add_readiness_target bochan-backend', text)
        self.assertIn('add_readiness_target malchan-backend', text)
        self.assertIn('add_readiness_target cauchan-backend', text)
        self.assertIn('add_readiness_target dchan-backend', text)
        self.assertIn("[READY] All application ports are listening.", text)
        self.assertIn('sh "$SCRIPT_DIR/stop_all.sh"', text)
        self.assertIn("[OK] All applications are ready.", text)

    def test_stop_validates_identity_before_signalling(self) -> None:
        text = (ROOT / "deploy" / "stop_all.sh").read_text(encoding="utf-8")

        self.assertIn('readlink "/proc/$pid/cwd"', text)
        self.assertIn("awk '{print $22}' \"/proc/$pid/stat\"", text)
        self.assertIn('"$SUITE_ROOT"/apps/*', text)
        self.assertIn('kill -TERM $targets', text)
        self.assertNotIn("fuser -k", text)
        self.assertNotIn("lsof -t", text)

    def test_status_supports_local_and_intranet_profiles(self) -> None:
        text = (ROOT / "deploy" / "status.sh").read_text(encoding="utf-8")

        self.assertIn("Local)", text)
        self.assertIn("Intranet)", text)
        self.assertIn("frontend url", text)
        self.assertIn("backend url", text)

    def test_readme_documents_linux_status_and_stop(self) -> None:
        text = (ROOT / "README.md").read_text(encoding="utf-8")

        self.assertIn("sh ./deploy/status.sh", text)
        self.assertIn("sh ./deploy/status.sh Intranet chan-server", text)
        self.assertIn("sh ./deploy/stop_all.sh", text)


if __name__ == "__main__":
    unittest.main()
