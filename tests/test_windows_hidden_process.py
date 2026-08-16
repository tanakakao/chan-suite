from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class WindowsHiddenProcessTest(unittest.TestCase):
    def test_managed_processes_are_hidden_and_logged(self) -> None:
        text = (ROOT / "deploy" / "start_all.ps1").read_text(encoding="utf-8")

        self.assertIn("-WindowStyle Hidden", text)
        self.assertIn("-RedirectStandardOutput $stdoutPath", text)
        self.assertIn("-RedirectStandardError $stderrPath", text)


if __name__ == "__main__":
    unittest.main()
