import unittest
from pathlib import Path

from check_performance import (
    check_separation,
    config_for,
    control_route,
    range_results,
    recorded_manifest,
    score_range,
    scores_from_report,
)
from tests import recorded


def scores_within(manifest):
    return {entry["route"]: entry["min"] for entry in manifest["routes"]}


def outside(manifest, scores):
    return [entry["route"] for entry, _, _, _, within in range_results(manifest, scores) if not within]


class ScoreRangeTest(unittest.TestCase):
    def setUp(self):
        self.manifest = recorded.performance()
        self.tolerance = self.manifest["tolerance"]
        self.entries = {entry["route"]: entry for entry in self.manifest["routes"]}

    def test_recorded_tolerance_widens_a_slowed_route_on_both_sides(self):
        self.assertEqual(score_range(self.entries["/perf/heavy"], self.tolerance), (0.3025, 0.7245))

    def test_zero_tolerance_is_the_recorded_min_and_max(self):
        self.assertEqual(score_range(self.entries["/perf/janky"], 0), (0.497, 0.5425))

    def test_control_route_has_no_upper_bound_below_a_perfect_score(self):
        self.assertEqual(score_range(self.entries["/perf/control"], self.tolerance), (0.617, 1.0))
        self.assertEqual(score_range(self.entries["/perf/control"], 0), (0.717, 1.0))

    def test_bounds_are_rounded_to_four_places(self):
        entry = {"min": 0.3, "max": 0.7, "control": False}
        self.assertEqual(score_range(entry, 0.1), (0.2, 0.8))

    def test_every_recorded_sample_is_within_its_range_without_tolerance(self):
        manifest = {**self.manifest, "tolerance": 0}
        for entry in manifest["routes"]:
            for sample in entry["scores"]:
                scores = {**scores_within(manifest), entry["route"]: sample}
                self.assertEqual(outside(manifest, scores), [], f"{entry['route']} {sample}")

    def test_scores_on_the_bounds_are_within(self):
        scores = {
            "/perf/control": 0.617,
            "/perf/heavy": 0.7245,
            "/perf/janky": 0.397,
        }
        self.assertEqual(outside(self.manifest, scores), [])

    def test_scores_just_past_the_bounds_are_outside(self):
        scores = {
            "/perf/control": 0.6169,
            "/perf/heavy": 0.7246,
            "/perf/janky": 0.3969,
        }
        self.assertEqual(outside(self.manifest, scores), ["/perf/control", "/perf/heavy", "/perf/janky"])

    def test_control_scoring_above_its_recorded_max_is_within(self):
        scores = {**scores_within(self.manifest), "/perf/control": 0.99}
        self.assertEqual(outside(self.manifest, scores), [])

    def test_slowed_route_scoring_above_its_recorded_max_plus_tolerance_is_outside(self):
        scores = {**scores_within(self.manifest), "/perf/janky": 0.65}
        self.assertEqual(outside(self.manifest, scores), ["/perf/janky"])

    def test_tolerance_decides_whether_a_score_is_within(self):
        scores = {**scores_within(self.manifest), "/perf/heavy": 0.35}
        self.assertEqual(outside(self.manifest, scores), [])
        self.assertEqual(outside({**self.manifest, "tolerance": 0}, scores), ["/perf/heavy"])


class SeparationTest(unittest.TestCase):
    def setUp(self):
        self.manifest = recorded.performance()
        self.control = control_route(self.manifest)

    def test_control_route_is_the_one_marked_control(self):
        self.assertEqual(self.control, "/perf/control")

    def test_every_recorded_run_separates_by_the_tolerance(self):
        runs = zip(*(entry["scores"] for entry in self.manifest["routes"]))
        routes = [entry["route"] for entry in self.manifest["routes"]]
        for run in runs:
            check_separation(dict(zip(routes, run)), self.control, self.manifest["tolerance"])

    def test_exactly_the_tolerance_below_the_control_separates(self):
        check_separation({"/perf/control": 0.7, "/perf/heavy": 0.6}, self.control, 0.1)

    def test_less_than_the_tolerance_below_the_control_fails_naming_the_route(self):
        with self.assertRaises(SystemExit) as raised:
            check_separation(
                {"/perf/control": 0.7, "/perf/heavy": 0.5, "/perf/janky": 0.6001},
                self.control,
                0.1,
            )
        self.assertIn("/perf/janky", str(raised.exception.code))
        self.assertNotIn("/perf/heavy", str(raised.exception.code))

    def test_zero_tolerance_only_requires_a_lower_score(self):
        check_separation({"/perf/control": 0.7, "/perf/heavy": 0.7}, self.control, 0)
        with self.assertRaises(SystemExit):
            check_separation({"/perf/control": 0.7, "/perf/heavy": 0.7001}, self.control, 0)


class ScoresFromReportTest(unittest.TestCase):
    def test_weights_rule_outcomes_and_measured_tool_scores_per_route(self):
        scores = scores_from_report(recorded.e2e_report(), ["/", "/login"])
        self.assertEqual(scores, {"/": 1.0, "/login": 0.6})

    def test_ignores_other_categories_zero_weights_and_unmeasured_scores(self):
        data = {
            "ruleOutcomes": [
                {"category": "perf", "route": "/a", "weight": 1.0, "passed": False},
                {"category": "a11y", "route": "/a", "weight": 9.0, "passed": True},
            ],
            "measurements": [
                {"category": "perf", "route": "/a", "weight": 3.0, "toolScore": 0.5},
                {"category": "perf", "route": "/a", "weight": 0.0, "toolScore": 1.0},
                {"category": "perf", "route": "/a", "weight": 5.0, "toolScore": None},
                {"category": "perf", "route": "/b", "weight": 5.0, "toolScore": 1.0},
            ],
        }
        self.assertEqual(scores_from_report(data, ["/a"]), {"/a": 0.375})

    def test_route_without_weighted_performance_fails_naming_it(self):
        with self.assertRaises(SystemExit) as raised:
            scores_from_report(recorded.e2e_report(), ["/", "/missing"])
        self.assertIn("/missing", str(raised.exception.code))


class RecordTest(unittest.TestCase):
    def test_recording_sets_each_route_range_from_its_samples(self):
        manifest = recorded.performance()
        samples = {
            "/perf/control": [0.8, 0.7],
            "/perf/heavy": [0.4, 0.45],
            "/perf/janky": [0.5, 0.5],
        }
        stamp = {"date": "2026-10-13", "runs": 2, "machine": "m", "lighthouse": "13.5.0"}
        updated = recorded_manifest(manifest, samples, stamp)
        self.assertEqual(updated["recorded"], stamp)
        self.assertEqual(updated["tolerance"], manifest["tolerance"])
        self.assertEqual(
            [(entry["route"], entry["scores"], entry["min"], entry["max"]) for entry in updated["routes"]],
            [
                ("/perf/control", [0.8, 0.7], 0.7, 0.8),
                ("/perf/heavy", [0.4, 0.45], 0.4, 0.45),
                ("/perf/janky", [0.5, 0.5], 0.5, 0.5),
            ],
        )
        self.assertEqual(manifest, recorded.performance())


class ConfigTest(unittest.TestCase):
    def test_config_measures_every_manifest_route_on_the_prebuilt_fixture(self):
        routes = [entry["route"] for entry in recorded.performance()["routes"]]
        config = config_for(Path("/fixture"), Path("/work/report"), Path("/work"), routes)
        self.assertEqual(config["web"]["routes"], ["/perf/control", "/perf/heavy", "/perf/janky"])
        self.assertEqual(config["web"]["build"], {"command": ["true"], "outputDir": "build/web"})
        self.assertEqual(config["reportDir"], "/work/report")
        self.assertEqual(config["baseline"], "/work/flighthouse-baseline.json")


if __name__ == "__main__":
    unittest.main()
