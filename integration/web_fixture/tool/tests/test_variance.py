import unittest

from tests import recorded
from variance import spread, summarize


def completed_run(index, planted, scores, detected):
    return {
        "run": index,
        "scores": scores,
        "detected": {entry["defect"]: entry["defect"] in detected for entry in planted},
        "toolVersions": {"lighthouse": "13.5.0"},
    }


class SpreadTest(unittest.TestCase):
    def test_min_median_and_max_rounded_to_four_places(self):
        self.assertEqual(
            spread([0.71234, 0.5, 0.9]),
            {"min": 0.5, "median": 0.7123, "max": 0.9},
        )

    def test_unmeasured_values_are_skipped(self):
        self.assertEqual(spread([None, 0.4, 0.6]), {"min": 0.4, "median": 0.5, "max": 0.6})

    def test_nothing_measured_is_all_null(self):
        self.assertEqual(spread([None, None]), {"min": None, "median": None, "max": None})
        self.assertEqual(spread([]), {"min": None, "median": None, "max": None})


class SummarizeTest(unittest.TestCase):
    def setUp(self):
        self.planted = recorded.planted()
        self.detectable = {entry["defect"] for entry in self.planted if entry["detectable"]}

    def test_scores_spread_across_completed_runs_and_count_failed_runs(self):
        runs = [
            completed_run(1, self.planted, {"overall": 0.8, "responsiveness": None}, self.detectable),
            {"run": 2, "failed": "collect exited 2", "output": []},
            completed_run(2, self.planted, {"overall": 0.6, "responsiveness": None}, self.detectable),
        ]
        result = summarize(self.planted, runs)
        self.assertEqual(result["runs"], 3)
        self.assertEqual(result["failedRuns"], 1)
        self.assertEqual(
            result["scores"]["overall"],
            {"min": 0.6, "median": 0.7, "max": 0.8, "failures": 1, "values": [0.8, 0.6]},
        )
        self.assertEqual(
            result["scores"]["responsiveness"],
            {"min": None, "median": None, "max": None, "failures": 1, "values": [None, None]},
        )

    def test_a_detection_that_disagrees_with_the_manifest_is_a_failure(self):
        label = "text field without a label"
        contrast = "light gray text on white"
        runs = [
            completed_run(1, self.planted, {"overall": 0.8}, self.detectable),
            completed_run(2, self.planted, {"overall": 0.8}, self.detectable - {label} | {contrast}),
        ]
        detections = summarize(self.planted, runs)["detections"]
        self.assertEqual(
            detections[label],
            {"min": 0.0, "median": 0.5, "max": 1.0, "expected": True, "detected": 1, "failures": 1},
        )
        self.assertEqual(detections[contrast]["detected"], 1)
        self.assertEqual(detections[contrast]["failures"], 1)
        self.assertEqual(detections["two buttons both named Save"]["failures"], 0)

    def test_every_run_failing_has_no_scores(self):
        runs = [{"run": 1, "failed": "collect exited 2", "output": []}]
        result = summarize(self.planted, runs)
        self.assertEqual(result["scores"], {})
        self.assertEqual(result["failedRuns"], 1)
        self.assertTrue(all(row["failures"] == 1 for row in result["detections"].values()))


if __name__ == "__main__":
    unittest.main()
