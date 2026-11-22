"""Regressions for a sampled pass hiding a short spike and a weakened load gate."""
import unittest

from check_queue_run import assess


class QueueAcceptanceTest(unittest.TestCase):
    def test_rejects_between_sample_spike_despite_original_pass(self):
        self.assertFalse(assess({'passed': True, 'peak_received': 31}, {'peak_pending': 127})['passed'])

    def test_does_not_discard_original_throughput_or_integrity_gate(self):
        self.assertFalse(assess({'passed': False, 'peak_received': 3}, {'peak_pending': 9})['passed'])

    def test_requires_strictly_below_limit_for_both_measurements(self):
        self.assertTrue(assess({'passed': True, 'peak_received': 31}, {'peak_pending': 99})['passed'])
        self.assertFalse(assess({'passed': True, 'peak_received': 31}, {'peak_pending': 100})['passed'])
        self.assertFalse(assess({'passed': True, 'peak_received': 100}, {'peak_pending': 90})['passed'])


if __name__ == '__main__':
    unittest.main()
