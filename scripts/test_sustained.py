"""Regression for PostgreSQL timestamps encountered by the load observer."""
from datetime import datetime, timezone
import unittest

from sustained import database_timestamp


class DatabaseClockTest(unittest.TestCase):
    def test_zero_to_six_fraction_digits(self):
        epoch = datetime(2026, 11, 22, 19, 31, tzinfo=timezone.utc).timestamp()
        for fraction in ('', '.1', '.12', '.123', '.1234', '.12345', '.123456'):
            with self.subTest(fraction=fraction):
                actual = database_timestamp('2026-11-22T19:31:00' + fraction + '+00:00')
                self.assertAlmostEqual(actual - epoch, float('0' + fraction), places=6)

    def test_preserves_offset_and_rejects_naive_or_invalid_time(self):
        self.assertEqual(database_timestamp('2026-11-22T19:31:00.12345Z'),
                         database_timestamp('2026-11-22T14:31:00.12345-05:00'))
        for value in ('2026-11-22T19:31:00', 'invalid'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                database_timestamp(value)


if __name__ == '__main__':
    unittest.main()
