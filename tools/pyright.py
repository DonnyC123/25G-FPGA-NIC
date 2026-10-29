import os
import subprocess
import sys

PYRIGHT = "pyright@1.1.400"


def main() -> int:
    workspace = os.environ["BUILD_WORKSPACE_DIRECTORY"]
    cmd = ["npx", "-y", PYRIGHT, "--pythonpath", sys.executable, *sys.argv[1:]]
    return subprocess.call(cmd, cwd=workspace)


if __name__ == "__main__":
    sys.exit(main())
