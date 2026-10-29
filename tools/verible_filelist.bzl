load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")

def _verible_filelist_impl(ctx):
    infos = depset(
        [dep[VerilogInfo] for dep in ctx.attr.deps],
        order = "postorder",
        transitive = [dep[VerilogInfo].deps for dep in ctx.attr.deps],
    )
    paths = []
    seen = {}
    for info in infos.to_list():
        for src in info.srcs.to_list():
            if src.short_path.startswith("../") or src.short_path in seen:
                continue
            seen[src.short_path] = True
            paths.append(src.short_path)
    out = ctx.actions.declare_file(ctx.label.name + ".filelist")
    ctx.actions.write(out, "\n".join(paths) + "\n")
    return [DefaultInfo(files = depset([out]))]

verible_filelist = rule(
    implementation = _verible_filelist_impl,
    attrs = {
        "deps": attr.label_list(providers = [VerilogInfo]),
    },
)
