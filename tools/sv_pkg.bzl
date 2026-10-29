"""Macro that regenerates a Python mirror of an SV package via gen_sv_pkg_py.py.

The .sv package is the source of truth; the generated .py is produced fresh
in bazel-out on every build, never committed. See tools/gen_sv_pkg_py.py.
"""

load("@rules_python//python:defs.bzl", "py_library")
load("@rules_verilog//verilog:defs.bzl", "verilog_library")

def sv_pkg_py(name, sv_file, package_name, visibility = None):
    """Generates a py_library mirroring an SV package's localparams/structs.

    Args:
        name: name of the resulting py_library.
        sv_file: label of the .sv file containing the package.
        package_name: the SV package's name (as declared by `package <name>;`).
        visibility: visibility of the resulting py_library.
    """
    out = package_name + ".py"
    native.genrule(
        name = name + "_gen",
        srcs = [sv_file],
        outs = [out],
        cmd = "$(location //tools:gen_sv_pkg_py) $(location %s) %s -o $@" % (sv_file, package_name),
        tools = ["//tools:gen_sv_pkg_py"],
    )
    py_library(
        name = name,
        srcs = [out],
        visibility = visibility,
    )

def sv_pkg(name, src = None, package_name = None, deps = [], visibility = None):
    src = src or name + ".sv"
    verilog_library(
        name = name,
        srcs = [src],
        deps = deps,
        visibility = visibility,
    )
    sv_pkg_py(
        name = name + "_py",
        sv_file = src,
        package_name = package_name or name,
        visibility = visibility,
    )
