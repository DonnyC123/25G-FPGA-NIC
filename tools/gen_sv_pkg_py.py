"""Generate a Python mirror of a SystemVerilog package's constants and structs.

The SV package is the single source of truth; this script parses it with
pyslang and emits a matching .py module so testbench code never hand-copies
localparam values (which silently drifts, e.g. alignment_finder_sequence.py
once had CTRL_HDR/DATA_HDR backwards relative to common/pkg/pcs_pkg.sv).

Usage:
    python tools/gen_sv_pkg_py.py <sv_file> <package_name> -o <output.py>

Regenerate whenever the source .sv package changes — this is not run
automatically as part of the build.
"""

import argparse
from pathlib import Path

import pyslang


def _format_int(value: int, width: int, sv_type: str) -> str:
    if not sv_type.startswith("logic"):
        return str(value)
    if width <= 3:
        return f"0b{value:0{width}b}"
    hex_digits = (width + 3) // 4
    return f"0x{value:0{hex_digits}X}"


def _gather_params(pkg) -> list[tuple[str, int, int, str]]:
    params = []
    for member in pkg:
        if type(member).__name__ != "ParameterSymbol":
            continue
        if not member.isValue:
            continue
        width = member.type.bitWidth if hasattr(member.type, "bitWidth") else None
        if width is None:
            continue
        value = int(member.value.value)
        params.append((member.name, value, width, str(member.type)))
    return params


def _gather_structs(pkg) -> list[tuple[str, list[tuple[str, int]]]]:
    structs = []
    for member in pkg:
        if type(member).__name__ != "TypeAliasType":
            continue
        target = member.targetType.type
        if type(target).__name__ != "PackedStructType":
            continue
        fields = [
            (field.name, field.type.bitWidth)
            for field in target
            if type(field).__name__ == "FieldSymbol"
        ]
        structs.append((member.name, fields))
    return structs


def generate(sv_file: Path, package_name: str) -> str:
    tree = pyslang.syntax.SyntaxTree.fromFile(str(sv_file))
    compilation = pyslang.ast.Compilation()
    compilation.addSyntaxTree(tree)

    diags = compilation.getAllDiagnostics()
    fatal = [d for d in diags if d.isError()]
    if fatal:
        raise SystemExit(
            f"pyslang reported {len(fatal)} error(s) parsing {sv_file}; "
            "fix the SV source before regenerating."
        )

    pkg = compilation.getPackage(package_name)
    if pkg is None:
        raise SystemExit(f"package '{package_name}' not found in {sv_file}")

    params = _gather_params(pkg)
    structs = _gather_structs(pkg)

    lines = [
        f'"""Generated from {sv_file.as_posix()} (package {package_name}) by',
        f"{Path(__file__).name} -- DO NOT EDIT BY HAND.",
        "",
        "Re-run the generator after changing the SV source:",
        (
            f"    python {Path(__file__).as_posix()} {sv_file.as_posix()} {package_name} "
            f"-o <this file>"
        ),
        '"""',
        "",
        "from dataclasses import dataclass",
        "",
    ]

    for name, value, width, sv_type in params:
        lines.append(f"{name} = {_format_int(value, width, sv_type)}  # {sv_type}")

    for struct_name, fields in structs:
        lines.append("")
        lines.append("")
        lines.append("@dataclass")
        lines.append(f"class {struct_name}:")
        if not fields:
            lines.append("    pass")
        for field_name, field_width in fields:
            lines.append(f"    {field_name}: int  # [{field_width - 1}:0]")

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sv_file", type=Path)
    parser.add_argument("package_name")
    parser.add_argument("-o", "--output", type=Path, required=True)
    args = parser.parse_args()

    output_text = generate(args.sv_file, args.package_name)
    args.output.write_text(output_text)
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
