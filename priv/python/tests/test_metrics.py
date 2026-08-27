"""
Testes unitários para funções puras de priv/python/metrics.py.
"""

import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parents[3]))

from priv.python import metrics


def test_immobility_ignores_isolated_blip_below_min_bout():
    # 1 segundo abaixo do limiar, cercado de movimento normal — não deve contar.
    speeds = [10.0, 10.0, 0.5, 10.0, 10.0]
    assert metrics.compute_immobility_seconds(speeds, threshold_cm=2.0) == 0.0


def test_immobility_counts_run_at_least_min_bout():
    # 2 segundos consecutivos abaixo do limiar (== default min_bout_s) contam.
    speeds = [10.0, 0.5, 0.5, 10.0]
    assert metrics.compute_immobility_seconds(speeds, threshold_cm=2.0) == 2.0


def test_immobility_sums_multiple_qualifying_runs():
    speeds = [0.5, 0.5, 10.0, 0.1, 0.1, 0.1, 10.0]
    assert metrics.compute_immobility_seconds(speeds, threshold_cm=2.0) == 5.0


def test_immobility_qualifying_run_at_end_of_series_counts():
    speeds = [10.0, 10.0, 0.5, 0.5]
    assert metrics.compute_immobility_seconds(speeds, threshold_cm=2.0) == 2.0


def test_immobility_min_bout_s_is_configurable():
    speeds = [0.5, 0.5, 10.0]
    assert metrics.compute_immobility_seconds(speeds, threshold_cm=2.0, min_bout_s=3) == 0.0
    assert metrics.compute_immobility_seconds(speeds, threshold_cm=2.0, min_bout_s=1) == 2.0


def test_immobility_empty_input():
    assert metrics.compute_immobility_seconds([], threshold_cm=2.0) == 0.0
