"""
Testes de caracterização para analyzer.process/9.

Não existia nenhuma cobertura direta desta função antes (ver CLAUDE.md,
seção "Próximos passos de legibilidade"). Estes testes gravam um vídeo
sintético e determinístico (sem depender de nenhum vídeo real commitado,
mesmo estilo de test_equivalence.py) e fixam os valores de retorno de
`process/9` como baseline — servem de rede de segurança para o refactor
interno da função, não como spec do algoritmo em si.
"""

import sys
from pathlib import Path

import cv2
import numpy as np
import pytest

sys.path.append(str(Path(__file__).resolve().parents[3]))

from priv.python import analyzer, detector, metrics

FRAME_SIZE = 200
SQUARE_SIZE = 16
STEP = 5
N_FRAMES = 25
FPS = 10

VALID_REGION = (0, 0, FRAME_SIZE, FRAME_SIZE)
CIRCLE_ROI = (150, 150, 30)
RECT_ROI = (10, 10, 40, 40)
POLYGON_ROI = [80, 80, 120, 80, 120, 120, 80, 120]
ROIS = [CIRCLE_ROI, RECT_ROI, POLYGON_ROI]


def _make_synthetic_video(path):
    """Grava um quadrado branco se deslocando em diagonal sobre fundo preto —
    garante exatamente 1 contorno detectável por frame, com posição conhecida."""
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(path), fourcc, FPS, (FRAME_SIZE, FRAME_SIZE))
    for i in range(N_FRAMES):
        frame = np.zeros((FRAME_SIZE, FRAME_SIZE, 3), dtype=np.uint8)
        top_left = 20 + i * STEP
        frame[top_left:top_left + SQUARE_SIZE, top_left:top_left + SQUARE_SIZE] = 255
        writer.write(frame)
    writer.release()


def _run_process(video_path, **overrides):
    vs = cv2.VideoCapture(str(video_path))
    bg = detector.get_background(np.zeros((FRAME_SIZE, FRAME_SIZE, 3), dtype=np.uint8))
    zone = metrics.get_central_zone_rectangular(VALID_REGION)

    kwargs = dict(
        vs=vs,
        bg=bg,
        valid_region=VALID_REGION,
        threshold=80,
        min_area=30,
        rois=ROIS,
        len_frames=0,
        headless=True,
        progress_every=1000,
        thigmotaxis_zone=zone,
    )
    kwargs.update(overrides)

    result = analyzer.process(**kwargs)
    vs.release()
    return result


@pytest.fixture(scope="module")
def synthetic_video(tmp_path_factory):
    video_path = tmp_path_factory.mktemp("analyzer") / "synthetic.mp4"
    _make_synthetic_video(video_path)
    assert video_path.exists()
    return video_path


def test_process_returns_expected_shape(synthetic_video):
    result = _run_process(synthetic_video)
    assert len(result) == 9

    heatmap, dist_total, nframe_into_roi, speeds, initial_pos, final_pos, nframe_peripheral, nframe_detected, positions = result

    assert heatmap.shape == (FRAME_SIZE, FRAME_SIZE)
    assert len(nframe_into_roi) == len(ROIS)
    assert isinstance(speeds, list)
    assert initial_pos is not None
    assert final_pos is not None
    assert isinstance(positions, list)


def test_process_pinned_baseline(synthetic_video):
    """Valores capturados rodando o `process/9` atual (pré-refactor) contra o
    vídeo sintético acima — golden baseline, não uma verdade matemática
    derivada à mão. Qualquer refactor interno tem que preservar esta tupla."""
    heatmap, dist_total, nframe_into_roi, speeds, initial_pos, final_pos, nframe_peripheral, nframe_detected, positions = (
        _run_process(synthetic_video)
    )

    assert dist_total == pytest.approx(141.4213562373095)
    assert nframe_into_roi == [4, 5, 8]
    assert speeds == pytest.approx([63.63961030678928, 70.71067811865476])
    assert initial_pos == pytest.approx((28.0, 28.0))
    assert final_pos == pytest.approx((148.0, 148.0))
    assert nframe_peripheral == 3
    assert nframe_detected == 25
    assert float(heatmap.sum()) == pytest.approx(20400.0)
    assert positions == pytest.approx([(28.0, 28.0), (73.0, 73.0), (123.0, 123.0)])
