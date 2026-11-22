#!/usr/bin/env python3
"""Split the test vectors of SPEC.md section 9 into vectors/Vnn.txt.

Each output file keeps the spec's own text: the '### Vnn.' title line, the
'World ...' start line, and the table rows (header included).
Usage: extract_vectors.py SPEC.md OUTDIR
"""
import os
import re
import sys


def main():
    spec, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    lines = open(spec, encoding="utf-8").read().splitlines()
    cur, buf, n = None, [], 0

    def flush():
        nonlocal n
        if cur and buf:
            with open(os.path.join(outdir, cur + ".txt"), "w") as f:
                f.write("\n".join(buf) + "\n")
            n += 1

    in_code = False
    for ln in lines:
        m = re.match(r"^### (V\d\d)\.", ln)
        if m:
            flush()
            cur, buf, in_code = m.group(1), [ln], False
            continue
        if cur is None:
            continue
        if ln.startswith("## "):
            flush()
            cur, buf = None, []
            continue
        if ln.startswith("World "):
            buf.append(ln)
        elif ln.startswith("```"):
            in_code = not in_code
        elif in_code and ln.strip():
            buf.append(ln)
    flush()
    print("wrote %d vectors" % n)


if __name__ == "__main__":
    main()
