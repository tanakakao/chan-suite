from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MALCHAN_EXTRAS = "--extra web --extra models --extra materials --extra inverse --extra visualization"


class SetupContractTest(unittest.TestCase):
    def test_windows_malchan_setup_includes_materials_extra(self) -> None:
        text = (ROOT / "deploy" / "setup_all.bat").read_text(encoding="utf-8")
        self.assertIn(f'call :setup_python "malchan" "{MALCHAN_EXTRAS}"', text)

    def test_posix_malchan_setup_includes_materials_extra(self) -> None:
        text = (ROOT / "deploy" / "setup_all.sh").read_text(encoding="utf-8")
        self.assertIn(
            f'uv sync --locked --python "$PYTHON_VERSION" {MALCHAN_EXTRAS}',
            text,
        )


if __name__ == "__main__":
    unittest.main()
