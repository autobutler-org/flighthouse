import copy
import unittest
from pathlib import Path

from check_responsive import (
    config_for,
    difference,
    matches_recorded,
    mismatch_message,
    observation,
    overflowing_route,
    recorded_manifest,
    summary,
)
from tests import recorded


def observed_from(manifest):
    return {
        name: {**run, "lighthouse": manifest["recorded"]["lighthouse"]}
        for name, run in copy.deepcopy(manifest["observed"]).items()
    }


class ObservationTest(unittest.TestCase):
    def test_counts_findings_per_route_and_category_from_a_recorded_report(self):
        result = observation({"width": 1280}, recorded.e2e_report(), ["/", "/login"])
        self.assertEqual(
            result,
            {
                "width": 1280,
                "responsivenessScore": None,
                "findings": {
                    "/": {"a11y": 8, "perf": 2, "responsiveness": 0, "memory": 0, "best-practices": 1},
                    "/login": {"a11y": 0, "perf": 15, "responsiveness": 0, "memory": 0, "best-practices": 3},
                },
                "lighthouse": "13.5.0",
            },
        )


class DifferenceTest(unittest.TestCase):
    def setUp(self):
        self.manifest = recorded.responsive()

    def test_overflowing_route_is_the_one_marked_overflowing(self):
        self.assertEqual(overflowing_route(self.manifest), "/responsive/overflow")

    def test_recorded_observation_gives_the_recorded_difference(self):
        self.assertEqual(difference(self.manifest, observed_from(self.manifest)), self.manifest["difference"])

    def test_difference_is_narrow_minus_wide_on_the_overflowing_route(self):
        observed = observed_from(self.manifest)
        observed["narrow"]["findings"]["/responsive/overflow"]["responsiveness"] = 3
        observed["wide"]["findings"]["/responsive/overflow"]["responsiveness"] = 1
        observed["narrow"]["findings"]["/responsive/control"]["responsiveness"] = 9
        self.assertEqual(difference(self.manifest, observed), 2)


class MatchesRecordedTest(unittest.TestCase):
    def setUp(self):
        self.manifest = recorded.responsive()
        self.observed = observed_from(self.manifest)

    def test_recorded_observation_matches(self):
        self.assertTrue(matches_recorded(self.manifest, self.observed))

    def test_other_category_counts_do_not_matter(self):
        self.observed["narrow"]["findings"]["/responsive/overflow"]["a11y"] = 40
        self.observed["wide"]["lighthouse"] = "99.0.0"
        self.assertTrue(matches_recorded(self.manifest, self.observed))

    def test_a_new_responsiveness_finding_does_not_match(self):
        self.observed["narrow"]["findings"]["/responsive/overflow"]["responsiveness"] = 1
        self.assertFalse(matches_recorded(self.manifest, self.observed))

    def test_a_responsiveness_score_does_not_match(self):
        self.observed["wide"]["responsivenessScore"] = 1.0
        self.assertFalse(matches_recorded(self.manifest, self.observed))


class RecordTest(unittest.TestCase):
    def test_recording_drops_the_tool_version_from_each_run_and_keeps_the_gap(self):
        manifest = recorded.responsive()
        observed = observed_from(manifest)
        observed["narrow"]["findings"]["/responsive/overflow"]["responsiveness"] = 2
        stamp = {"date": "2026-10-13", "machine": "m", "lighthouse": "13.5.0"}
        updated = recorded_manifest(manifest, observed, stamp)
        self.assertEqual(updated["recorded"], stamp)
        self.assertEqual(updated["difference"], 2)
        self.assertEqual(updated["observed"], summary(observed))
        self.assertNotIn("lighthouse", updated["observed"]["wide"])
        self.assertEqual(updated["gap"], manifest["gap"])
        self.assertEqual(manifest, recorded.responsive())


class GapTest(unittest.TestCase):
    def test_gap_points_at_the_adr_that_leaves_layout_overflow_out_of_scope(self):
        self.assertEqual(
            recorded.responsive()["gap"],
            "https://github.com/autobutler-org/flighthouse/blob/main/docs/adr/0034-web-responsive-layout-out-of-scope.md",
        )

    def test_mismatch_message_cites_the_adr_and_its_decision(self):
        message = mismatch_message(recorded.responsive(), "responsive.json")
        self.assertIn("responsive.json", message)
        self.assertIn("ADR 0034", message)
        self.assertIn(recorded.responsive()["gap"], message)
        self.assertIn("out of scope", message)
        self.assertIn("widget tests", message)
        self.assertNotIn("issues/161", message)


class ConfigTest(unittest.TestCase):
    def test_each_viewport_gets_its_own_size_and_report_directory(self):
        manifest = recorded.responsive()
        routes = [entry["route"] for entry in manifest["routes"]]
        configs = [config_for(viewport, Path("/fixture"), Path("/work"), routes) for viewport in manifest["viewports"]]
        self.assertEqual([config["reportDir"] for config in configs], ["/work/wide", "/work/narrow"])
        self.assertEqual(
            [(config["web"]["viewport"]["width"], config["web"]["viewport"]["height"]) for config in configs],
            [(1280, 800), (360, 800)],
        )
        self.assertEqual(configs[0]["web"]["routes"], ["/responsive/control", "/responsive/overflow"])


if __name__ == "__main__":
    unittest.main()
