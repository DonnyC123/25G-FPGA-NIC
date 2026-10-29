import os
import shutil
import sys


def main() -> int:
    src, dest = sys.argv[1:]
    shutil.copyfile(src, os.path.join(os.environ["BUILD_WORKSPACE_DIRECTORY"], dest))
    return 0


if __name__ == "__main__":
    sys.exit(main())
