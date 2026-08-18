from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class FrontendLauncherContractTest(unittest.TestCase):
    def test_windows_launcher_passes_vite_options_without_extra_separator(self) -> None:
        text = (ROOT / "deploy" / "start_all.ps1").read_text(encoding="utf-8")

        self.assertNotIn("'run', 'dev', '--', '--host'", text)
        self.assertIn(
            "@('run', 'dev', '--host', $resolvedProfile.BindHost, '--port', [string]$port, '--strictPort')",
            text,
        )

    def test_posix_launcher_passes_vite_options_without_extra_separator(self) -> None:
        text = (ROOT / "deploy" / "start_all.sh").read_text(encoding="utf-8")

        self.assertNotIn('pnpm run dev -- --host "$BIND_HOST"', text)
        self.assertIn(
            'pnpm run dev --host "$BIND_HOST" --port "$port" --strictPort',
            text,
        )

    def test_windows_launcher_passes_public_portal_url_to_all_app_frontends(self) -> None:
        text = (ROOT / "deploy" / "start_all.ps1").read_text(encoding="utf-8")

        self.assertIn(
            "Get-ChanSuiteUrl -PublicHost $resolvedProfile.PublicHost -Port $portal.frontendPort",
            text,
        )
        self.assertEqual(text.count("$frontendEnvironment['VITE_PORTAL_URL'] = $portalUrl"), 4)

    def test_posix_launcher_passes_public_portal_url_to_all_app_frontends(self) -> None:
        text = (ROOT / "deploy" / "start_all.sh").read_text(encoding="utf-8")

        self.assertIn(
            'COMMON_PORTAL="VITE_PORTAL_URL=http://$PUBLIC_HOST:$PORTAL_FRONTEND"',
            text,
        )
        self.assertEqual(text.count('"$COMMON_PORTAL"'), 4)


if __name__ == "__main__":
    unittest.main()
