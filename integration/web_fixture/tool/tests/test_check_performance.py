import unittest
from pathlib import Path

from check_performance import (
    check_gate,
    config_for,
    control_route,
    gate_failures,
    range_notes,
    recorded_manifest,
    scores_from_report,
)
from tests import recorded


def recorded_runs(manifest):
    routes = [entry["route"] for entry in manifest["routes"]]
    return [dict(zip(routes, run)) for run in zip(*(entry["scores"] for entry in manifest["routes"]))]


class ManifestTest(unittest.TestCase):
    def setUp(self):
        self.manifest = recorded.performance()
        self.control = control_route(self.manifest)

    def test_control_route_is_the_one_marked_control(self):
        self.assertEqual(self.control, "/perf/control")

    def test_margin_is_a_tenth_or_the_smallest_recorded_separation(self):
        smallest = min(
            round(run[self.control] - score, 4)
            for run in recorded_runs(self.manifest)
            for route, score in run.items()
            if route != self.control
        )
        self.assertEqual(self.manifest["margin"], min(0.1, smallest))

    def test_floor_is_below_every_recorded_score(self):
        lowest = min(score for entry in self.manifest["routes"] for score in entry["scores"])
        self.assertLess(self.manifest["floor"], lowest)

    def test_every_recorded_run_passes_the_gate(self):
        for run in recorded_runs(self.manifest):
            self.assertEqual(
                gate_failures(run, self.control, self.manifest["margin"], self.manifest["floor"]),
                [],
                run,
            )


class GateTest(unittest.TestCase):
    def setUp(self):
        self.control = "/perf/control"

    def failures(self, scores, margin=0.1, floor=0.25):
        return gate_failures(scores, self.control, margin, floor)

    def test_exactly_the_margin_below_the_control_passes(self):
        self.assertEqual(self.failures({"/perf/control": 0.7, "/perf/heavy": 0.6}), [])

    def test_less_than_the_margin_below_the_control_fails_naming_the_route(self):
        failures = self.failures({"/perf/control": 0.7, "/perf/heavy": 0.5, "/perf/janky": 0.6001})
        self.assertEqual(len(failures), 1)
        self.assertIn("/perf/janky", failures[0])

    def test_a_wrong_margin_fails_a_run_that_the_recorded_margin_passes(self):
        scores = {"/perf/control": 0.85, "/perf/heavy": 0.7, "/perf/janky": 0.6}
        self.assertEqual(self.failures(scores, margin=0.1), [])
        self.assertEqual(len(self.failures(scores, margin=0.2)), 1)

    def test_separation_is_relative_to_the_control_in_the_same_run(self):
        self.assertEqual(self.failures({"/perf/control": 0.95, "/perf/heavy": 0.84}), [])
        self.assertEqual(len(self.failures({"/perf/control": 0.6, "/perf/heavy": 0.55})), 1)

    def test_zero_margin_only_requires_a_score_no_higher(self):
        self.assertEqual(self.failures({"/perf/control": 0.7, "/perf/heavy": 0.7}, margin=0), [])
        self.assertEqual(len(self.failures({"/perf/control": 0.7, "/perf/heavy": 0.7001}, margin=0)), 1)

    def test_a_route_below_the_floor_fails_even_when_separated(self):
        failures = self.failures({"/perf/control": 0.7, "/perf/heavy": 0.2499, "/perf/janky": 0.25})
        self.assertEqual(len(failures), 1)
        self.assertIn("/perf/heavy", failures[0])
        self.assertIn("floor", failures[0])

    def test_a_broken_control_below_the_floor_fails(self):
        failures = self.failures({"/perf/control": 0.1, "/perf/heavy": 0.0, "/perf/janky": 0.0})
        self.assertTrue(any("/perf/control" in failure and "floor" in failure for failure in failures))

    def test_check_gate_exits_with_every_failure(self):
        manifest = {"margin": 0.1, "floor": 0.25}
        with self.assertRaises(SystemExit) as raised:
            check_gate({"/perf/control": 0.7, "/perf/heavy": 0.2, "/perf/janky": 0.65}, self.control, manifest)
        self.assertIn("/perf/heavy", str(raised.exception.code))
        self.assertIn("/perf/janky", str(raised.exception.code))


class RangeNotesTest(unittest.TestCase):
    def setUp(self):
        self.manifest = recorded.performance()

    def test_notes_place_each_score_against_its_recorded_range(self):
        scores = {"/perf/control": 0.9, "/perf/heavy": 0.3, "/perf/janky": 0.5}
        notes = range_notes(self.manifest, scores)
        self.assertEqual(
            [note.split(" recorded")[0] for note in notes],
            ["/perf/control: 0.9 above", "/perf/heavy: 0.3 below", "/perf/janky: 0.5 within"],
        )

    def test_a_score_above_its_recorded_max_does_not_fail_the_gate(self):
        scores = {"/perf/control": 0.95, "/perf/heavy": 0.8, "/perf/janky": 0.7}
        self.assertIn("above", range_notes(self.manifest, scores)[1])
        check_gate(scores, control_route(self.manifest), self.manifest)


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
        self.assertEqual(updated["margin"], manifest["margin"])
        self.assertEqual(updated["floor"], manifest["floor"])
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
