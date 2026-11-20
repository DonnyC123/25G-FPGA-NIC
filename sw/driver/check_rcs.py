import re
import sys
from pathlib import Path

TAB_WIDTH = 8
STATEMENT_WORDS = {"return", "goto", "case", "else", "do", "break", "continue", "sizeof", "if", "while", "for", "switch"}
QUALIFIERS = r"(?:(?:const|static|volatile|unsigned|signed|struct|union|enum)\s+)*"
DECLARATION = re.compile(QUALIFIERS + r"([A-Za-z_]\w*)[\s*]+\**[A-Za-z_]\w*\s*(?:\[[^\]]*\])?\s*(?:=|;|,)")
TYPE_BODY = re.compile(r"(=\s*\{|\b(?:struct|union|enum)\s+\w*\s*\{)\s*$")


def is_declaration(text: str) -> bool:
    match = DECLARATION.match(text)
    return bool(match) and match.group(1) not in STATEMENT_WORDS


def declaration_end(lines: list[str], start: int) -> int:
    depth = 0
    for i in range(start, len(lines)):
        depth += lines[i].count("{") + lines[i].count("(") - lines[i].count("}") - lines[i].count(")")
        if depth <= 0 and lines[i].rstrip().endswith(";"):
            return i
    return len(lines) - 1


def check_file(path: Path) -> list[str]:
    lines = path.read_text().splitlines()
    errors = []
    for opener, line in enumerate(lines):
        if not line.rstrip().endswith("{") or TYPE_BODY.search(line) or line.lstrip().startswith("//"):
            continue
        previous = None
        i = opener + 1
        while i < len(lines):
            text = lines[i].strip()
            if text.startswith("//"):
                i += 1
                continue
            if not text or not is_declaration(text):
                break
            width = len(lines[i].rstrip().expandtabs(TAB_WIDTH))
            if previous is not None and width > previous:
                errors.append(f"{path.name}:{i + 1}: declaration is longer than the one above ({width} > {previous})")
            previous = width
            i = declaration_end(lines, i) + 1
    return errors


def driver_files(driver_dir: Path) -> list[Path]:
    ignore_file = driver_dir / ".clang-format-ignore"
    ignored = set(ignore_file.read_text().split()) if ignore_file.exists() else set()
    sources = sorted(driver_dir.glob("*.c")) + sorted(driver_dir.glob("*.h"))
    return [path for path in sources if path.name not in ignored]


def main() -> int:
    paths = [Path(arg) for arg in sys.argv[1:]] or driver_files(Path(__file__).absolute().parent)
    errors = [error for path in paths for error in check_file(path)]
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
