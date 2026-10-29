"""Exposes a locally installed Questa as Bazel targets, located via $QUESTA_HOME.

Questa is licensed and can't be fetched, so each tool is a wrapper script that
execs the real binary from the local install. When QUESTA_HOME is unset the
wrappers fail with a clear message at test time instead of breaking analysis,
so machines without Questa can still build and run Verilator tests.
"""

_TOOLS = ["vcom", "vlib", "vlog", "vsim"]

def _questa_local_impl(rctx):
    questa_home = rctx.getenv("QUESTA_HOME")

    build = ['load("@bazel_skylib//rules:native_binary.bzl", "native_binary")', ""]
    for tool in _TOOLS:
        if questa_home:
            script = '#!/bin/sh\nexec "{}/bin/{}" "$@"\n'.format(questa_home, tool)
        else:
            script = (
                "#!/bin/sh\n" +
                "echo 'ERROR: {} requested but QUESTA_HOME is not set. " +
                "Export QUESTA_HOME to your Questa install root (the dir containing bin/vsim).' >&2\n" +
                "exit 1\n"
            ).format(tool)
        rctx.file(tool + ".sh", script, executable = True)
        build.append(
            'native_binary(name = "{0}", src = "{0}.sh", out = "{0}", visibility = ["//visibility:public"])'.format(tool),
        )

    rctx.file("BUILD.bazel", "\n".join(build) + "\n")

questa_local = repository_rule(
    implementation = _questa_local_impl,
    local = True,
)
