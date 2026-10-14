import unittest
from pathlib import Path

from check_scores import category_score, config_for, gate_failures
from tests import recorded


class ManifestTest(unittest.TestCase):
    def setUp(self):
        self.manifest = recorded.scores()

    def test_compares_the_clean_and_fully_planted_configurations(self):
        self.assertEqual(self.manifest["clean"], "/planted?defects=none")
        self.assertEqual(self.manifest["planted"], "/planted")
        self.assertEqual(self.manifest["category"], "a11y")

    def test_margin_is_above_the_recorded_run_to_run_spread(self):
        spread = recorded.fixture_variance()["scores"][self.manifest["category"]]
        self.assertGreater(self.manifest["margin"], round(spread["max"] - spread["min"], 4))

    def test_every_planted_defect_lives_on_the_planted_route(self):
        self.assertEqual({entry["route"] for entry in recorded.planted()}, {self.manifest["planted"]})


class GateTest(unittest.TestCase):
    def test_exactly_the_margin_below_clean_passes(self):
        self.assertEqual(gate_failures(1.0, 0.95, 0.05), [])

    def test_less_than_the_margin_below_clean_fails_naming_both_scores(self):
        failures = gate_failures(1.0, 0.9501, 0.05)
        self.assertEqual(len(failures), 1)
        self.assertIn("0.9501", failures[0])
        self.assertIn("1.0", failures[0])

    def test_equal_scores_fail(self):
        self.assertEqual(len(gate_failures(0.9, 0.9, 0.05)), 1)

    def test_a_planted_score_above_clean_fails(self):
        self.assertEqual(len(gate_failures(0.8, 0.9, 0.05)), 1)

    def test_separation_is_relative_to_clean_in_the_same_run(self):
        self.assertEqual(gate_failures(0.9, 0.8, 0.05), [])
        self.assertEqual(len(gate_failures(0.82, 0.8, 0.05)), 1)

    def test_a_wrong_margin_fails_a_run_that_the_recorded_margin_passes(self):
        self.assertEqual(gate_failures(1.0, 0.9, 0.05), [])
        self.assertEqual(len(gate_failures(1.0, 0.9, 0.2)), 1)


class CategoryScoreTest(unittest.TestCase):
    def test_reads_the_category_score_flighthouse_computed(self):
        self.assertEqual(category_score(recorded.e2e_report(), "a11y", "/"), 0.7265)

    def test_unmeasured_category_fails_naming_the_route(self):
        with self.assertRaises(SystemExit) as raised:
            category_score(recorded.e2e_report(), "responsiveness", "/planted")
        self.assertIn("/planted", str(raised.exception.code))
        self.assertIn("responsiveness", str(raised.exception.code))


class ConfigTest(unittest.TestCase):
    def test_config_audits_one_route_on_the_prebuilt_fixture(self):
        config = config_for("/planted?defects=none", Path("/fixture"), Path("/work/report"), Path("/work"))
        self.assertEqual(config["web"]["routes"], ["/planted?defects=none"])
        self.assertEqual(config["web"]["build"], {"command": ["true"], "outputDir": "build/web"})
        self.assertEqual(config["reportDir"], "/work/report")
        self.assertEqual(config["baseline"], "/work/flighthouse-baseline.json")


if __name__ == "__main__":
    unittest.main()
