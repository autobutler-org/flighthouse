import unittest

from check_planted import classify, detected_by_all, reported
from tests import recorded
from tests.recorded import finding, findings_for


def names(entries):
    return [entry["defect"] for entry in entries]


class DetectionTest(unittest.TestCase):
    def setUp(self):
        self.planted = recorded.planted()
        self.label = next(entry for entry in self.planted if entry["rule"] == "label")

    def test_reported_matches_source_rule_route_and_category(self):
        self.assertTrue(reported(self.label, "axe", [finding("axe", "label", "/planted")]))

    def test_reported_rejects_a_mismatch_in_any_field(self):
        for mismatch in [
            finding("lighthouse", "label", "/planted"),
            finding("axe", "image-alt", "/planted"),
            finding("axe", "label", "/public"),
            finding("axe", "label", "/planted", category="best-practices"),
        ]:
            self.assertFalse(reported(self.label, "axe", [mismatch]), mismatch)

    def test_needs_review_finding_is_not_a_detection(self):
        needs_review = finding("axe", "label", "/planted", message="Needs review: check it")
        self.assertFalse(reported(self.label, "axe", [needs_review]))

    def test_detection_needs_every_listed_source(self):
        self.assertFalse(detected_by_all(self.label, [finding("axe", "label", "/planted")]))
        self.assertTrue(detected_by_all(self.label, findings_for(self.label)))

    def test_entry_without_sources_is_never_detected(self):
        duplicate = next(entry for entry in self.planted if not entry["sources"])
        self.assertFalse(detected_by_all(duplicate, [finding("axe", None, "/planted")]))


class ClassifyTest(unittest.TestCase):
    def setUp(self):
        self.planted = recorded.planted()
        self.detectable = [entry for entry in self.planted if entry["detectable"]]
        self.everything = [found for entry in self.detectable for found in findings_for(entry)]

    def test_every_detectable_defect_found_passes(self):
        detected, missing, surprises = classify(self.planted, self.everything)
        self.assertEqual(names(detected), names(self.detectable))
        self.assertEqual(missing, [])
        self.assertEqual(surprises, [])

    def test_detectable_defect_missing_one_source_is_missing(self):
        findings = [
            found
            for found in self.everything
            if not (found["rule"] == "label" and found["source"] == "lighthouse")
        ]
        _, missing, surprises = classify(self.planted, findings)
        self.assertEqual(names(missing), ["text field without a label"])
        self.assertEqual(surprises, [])

    def test_undetectable_defect_reported_by_one_source_is_a_surprise(self):
        contrast = next(entry for entry in self.planted if entry["rule"] == "color-contrast")
        findings = self.everything + [finding("lighthouse", "color-contrast", "/planted")]
        detected, missing, surprises = classify(self.planted, findings)
        self.assertEqual(names(surprises), [contrast["defect"]])
        self.assertNotIn(contrast["defect"], names(detected))
        self.assertEqual(missing, [])

    def test_undetectable_defect_marked_needs_review_is_not_a_surprise(self):
        findings = self.everything + [
            finding("axe", "color-contrast", "/planted", message="Needs review: color contrast")
        ]
        _, _, surprises = classify(self.planted, findings)
        self.assertEqual(surprises, [])

    def test_no_findings_misses_every_detectable_defect(self):
        detected, missing, surprises = classify(self.planted, [])
        self.assertEqual(detected, [])
        self.assertEqual(names(missing), names(self.detectable))
        self.assertEqual(surprises, [])


if __name__ == "__main__":
    unittest.main()
