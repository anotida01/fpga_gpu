import subprocess
import pytest
from pathlib import Path

# Target testcases in tests/testcases/
testcases = [
    "tc_axilfe_basic_wr_rd",
    "tc_axil_slave",
    "tc_axil_sys_access",
    "tc_axilfe_error",
    "tc_multiple_frames"
]

@pytest.mark.parametrize("test_name", testcases)
def test_run_sim(test_name):
    log_dir = Path("regression_logs")
    log_dir.mkdir(exist_ok=True)
    log_file = log_dir / f"{test_name}.log"

    with log_file.open("w") as log:
        result = subprocess.run(
            ["bash", "do_run_sim.sh", "gpu_dut_snap", test_name],
            stdout=log,
            stderr=subprocess.STDOUT
        )

    assert result.returncode == 0, f"Test {test_name} failed (see {log_file})"
