import numpy as np
import pytest

from conftest import FIXTURES
from scanlab.core import mesh_io


def test_reads_golden_chunk_written_for_swift():
    c = mesh_io.read_chunk((FIXTURES / "chunk_v1.bin").read_bytes())
    assert str(c.id) == "00112233-4455-6677-8899-aabbccddeeff"
    assert c.version == 7
    assert c.indices.tolist() == [[0, 2, 1], [0, 3, 2]]
    assert c.classifications.tolist() == [2, 2]
    np.testing.assert_allclose(c.world_vertices()[2], [2, 2, 4])  # (1,0,1) + (1,2,3)


@pytest.mark.parametrize("cut", [0, 10, 100, 181])
def test_truncated_chunk_raises(cut):
    data = (FIXTURES / "chunk_v1.bin").read_bytes()[:cut]
    with pytest.raises(mesh_io.ChunkFormatError):
        mesh_io.read_chunk(data)


def test_import_chunks_converts_to_mm_and_welds(tmp_path):
    golden = (FIXTURES / "chunk_v1.bin").read_bytes()
    (tmp_path / "a.bin").write_bytes(golden)
    # Second chunk: same quad shifted +1 m in x with 2 mm jitter → shares an edge after a 5 mm weld.
    shifted = bytearray(golden)
    import struct
    struct.pack_into("<f", shifted, 4 + 2 + 2 + 16 + 8 + 12 * 4, 2.002)  # column 3, x
    (tmp_path / "b.bin").write_bytes(bytes(shifted))
    mesh = mesh_io.import_chunks(tmp_path, weld_mm=5)
    assert len(mesh.faces) == 4
    assert len(mesh.vertices) == 6
    np.testing.assert_allclose(mesh.bounds, [[1000, 2000, 3000], [3002, 2000, 4000]], atol=1e-3)


def test_unit_scaling(ws):
    import trimesh

    trimesh.creation.box((0.02, 0.02, 0.01)).export(ws.inbox / "m.stl")
    mesh = mesh_io.load_mesh(ws.inbox / "m.stl", unit="m")
    np.testing.assert_allclose(mesh.extents, [20, 20, 10], atol=1e-6)
