import unittest
from pathlib import Path

from check_toggles import (
    actual_keys,
    config_for,
    config_name,
    expected_keys,
    new_findings,
    toggled_entry,
)
from tests import recorded
from tests.recorded import finding, findings_for


class ConfigTest(unittest.TestCase):
    def config(self, defects):
        return config_for(defects, Path("/fixture"), Path("/work/report"), Path("/work/baseline.json"))

    def test_no_defects_requests_the_named_empty_set(self):
        self.assertEqual(self.config([])["web"]["routes"], ["/planted?defects=none"])
        self.assertEqual(config_name([]), "defects-none.yaml")

    def test_one_defect_requests_only_that_toggle(self):
        self.assertEqual(self.config(["label"])["web"]["routes"], ["/planted?defects=label"])
        self.assertEqual(config_name(["label"]), "defects-label.yaml")

    def test_several_defects_join_with_commas_and_dashes(self):
        self.assertEqual(
            self.config(["label", "image-alt"])["web"]["routes"],
            ["/planted?defects=label,image-alt"],
        )
        self.assertEqual(config_name(["label", "image-alt"]), "defects-label-image-alt.yaml")

    def test_every_config_shares_one_report_and_baseline(self):
        clean, toggled = self.config([]), self.config(["label"])
        for key in ["app", "reportDir", "baseline", "gate"]:
            self.assertEqual(clean[key], toggled[key], key)
        self.assertEqual(clean["reportDir"], "/work/report")
        self.assertEqual(clean["baseline"], "/work/baseline.json")
        self.assertEqual(clean["web"]["projectDir"], "/fixture")

    def test_score_drops_never_fail_the_gate_so_only_findings_do(self):
        self.assertEqual(self.config([])["gate"], {"maxScoreDrop": {"overall": 100, "perf": 100}})

    def test_config_reuses_the_prebuilt_fixture(self):
        self.assertEqual(self.config([])["web"]["build"], {"command": ["true"], "outputDir": "build/web"})


class NewFindingsTest(unittest.TestCase):
    def setUp(self):
        self.entry = toggled_entry(recorded.planted())
        self.known = [finding("lighthouse", "cache-insight", "/planted", category="perf")]

    def test_toggles_the_first_detectable_defect(self):
        self.assertEqual(self.entry["toggle"], "label")

    def test_expects_one_finding_per_source(self):
        self.assertEqual(
            expected_keys(self.entry),
            {("axe", "label", "/planted"), ("lighthouse", "label", "/planted")},
        )

    def test_only_the_toggled_defect_is_new(self):
        current = self.known + findings_for(self.entry)
        self.assertEqual(actual_keys(new_findings(current, self.known, self.entry["category"])), expected_keys(self.entry))

    def test_a_new_finding_in_another_category_is_noise(self):
        current = self.known + findings_for(self.entry) + [finding("lighthouse", "max-potential-fid", "/planted", category="perf")]
        self.assertEqual(actual_keys(new_findings(current, self.known, self.entry["category"])), expected_keys(self.entry))

    def test_needs_review_findings_are_not_new(self):
        current = self.known + [finding("axe", "color-contrast", "/planted", message="Needs review: x")]
        self.assertEqual(new_findings(current, self.known, self.entry["category"]), [])

    def test_an_extra_finding_makes_the_sets_differ(self):
        current = self.known + findings_for(self.entry) + [finding("axe", "button-name", "/planted")]
        self.assertNotEqual(actual_keys(new_findings(current, self.known, self.entry["category"])), expected_keys(self.entry))

    def test_a_missing_source_makes_the_sets_differ(self):
        current = self.known + findings_for(self.entry)[:1]
        self.assertNotEqual(actual_keys(new_findings(current, self.known, self.entry["category"])), expected_keys(self.entry))

    def test_findings_are_matched_to_the_baseline_by_fingerprint(self):
        renamed = {**self.known[0], "message": "a reworded message"}
        self.assertEqual(new_findings([renamed], self.known, "perf"), [])


if __name__ == "__main__":
    unittest.main()
