import sys
from pathlib import Path
import pytest
import numpy as np

# Adicionar a raiz do repo ao path para poder importar priv.mouse_tracker
sys.path.append(str(Path(__file__).resolve().parents[3]))

# Importar o original e o novo modular
import priv.mouse_tracker as original
import priv.python.metrics as new_metrics
import priv.python.detector as new_detector


def test_distance():
    # Teste de equivalência para cálculo de distância
    pt1 = (10.0, 20.0)
    pt2 = (15.0, 32.5)
    
    orig_dist = original.distance(pt1, pt2)
    new_dist = new_metrics.distance(pt1, pt2)
    
    assert orig_dist == new_dist
    assert new_dist == pytest.approx(13.4629, abs=1e-4)


def test_is_pt_into_roi():
    # Teste de equivalência para pontos dentro do ROI
    roi = (50, 50, 100, 100) # x, y, w, h
    
    pt_inside = (75, 75)
    pt_outside = (200, 200)
    
    assert original.is_pt_into_roi(pt_inside, roi) == new_metrics.is_pt_into_roi(pt_inside, roi)
    assert original.is_pt_into_roi(pt_outside, roi) == new_metrics.is_pt_into_roi(pt_outside, roi)


def test_detector_get_background():
    # Teste com uma imagem mockada
    mock_frame = np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8)
    
    orig_bg = original.get_background(mock_frame)
    new_bg = new_detector.get_background(mock_frame)
    
    assert np.array_equal(orig_bg, new_bg)


def test_detector_exclude_invalid_region():
    # Teste de exclusão de região válida/inválida
    mock_frame = np.ones((100, 100), dtype=np.uint8) * 255
    valid_region = (10, 10, 50, 50)
    
    orig_masked = original.exclude_invalid_region(mock_frame.copy(), valid_region)
    new_masked = new_detector.exclude_invalid_region(mock_frame.copy(), valid_region)
    
    assert np.array_equal(orig_masked, new_masked)
    
    # Conferir se fora da região válida virou zero
    assert orig_masked[0, 0] == 0
    # E dentro da região válida manteve o valor
    assert orig_masked[15, 15] == 255


def test_detector_apply_threshold():
    # Teste de threshold
    mock_delta = np.zeros((100, 100), dtype=np.uint8)
    mock_delta[30:50, 30:50] = 100 # Valor acima do threshold de 80
    
    orig_thresh = original.apply_threshold(mock_delta.copy(), 80)
    new_thresh = new_detector.apply_threshold(mock_delta.copy(), 80)
    
    assert np.array_equal(orig_thresh, new_thresh)
