#!/usr/bin/env python3
"""Luau → Lua 5.3 (texlua) converter: handles only the Luau extensions used by the hub.

- x += y / -= / *= / /= / ..=   →  x = x op (y)
- continue                       →  goto __continue  (a ::__continue:: label is added at the end of the loop)
Long strings ([==[ ... ]==]) and comments are left untouched.
"""
import re, sys

def segments(src):
    """(is_code, text) chunks: string and comment chunks are returned with False."""
    i, n, out, start = 0, len(src), [], 0
    def flush(j, code=True):
        nonlocal start
        if j > start: out.append((code, src[start:j]))
        start = j
    while i < n:
        c = src[i]
        if c == "-" and src.startswith("--", i):
            flush(i)
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                end = src.find("]" + m.group(1) + "]", i)
                j = n if end < 0 else end + len(m.group(1)) + 2
            else:
                j = src.find("\n", i); j = n if j < 0 else j
            flush(j, False); i = j; continue
        if c == "[":
            m = re.match(r"\[(=*)\[", src[i:])
            if m:
                flush(i)
                end = src.find("]" + m.group(1) + "]", i + 2)
                j = n if end < 0 else end + len(m.group(1)) + 2
                flush(j, False); i = j; continue
        if c in "\"'":
            flush(i)
            j = i + 1
            while j < n and src[j] != c:
                if src[j] == "\\": j += 1
                j += 1
            flush(j + 1, False); i = j + 1; continue
        i += 1
    flush(n)
    return out

COMPOUND = re.compile(r"([A-Za-z_][\w\.\[\]\"']*)\s*(\+|-|\*|/|\.\.)=(?!=)\s*")

def expr_end(code, k):
    """Where the expression starting at k ends: end of line, or 'end'/'else'/'elseif' at depth 0."""
    depth, i = 0, k
    while i < len(code):
        ch = code[i]
        if ch in "([{": depth += 1
        elif ch in ")]}":
            if depth == 0: return i
            depth -= 1
        elif ch == "\n" and depth == 0: return i
        elif depth == 0 and re.match(r"\b(end|else|elseif)\b", code[i:]) and (i == 0 or not (code[i-1].isalnum() or code[i-1] == "_")):
            return i
        i += 1
    return i

def compound(text):
    # replace strings and comments with placeholders, rewrite the expressions, then put them back
    segs = segments(text)
    keep, buf = [], []
    for code, t in segs:
        if code: buf.append(t)
        else:
            keep.append(t); buf.append("\x00%d\x00" % (len(keep) - 1))
    code = "".join(buf)
    out, pos = [], 0
    for m in COMPOUND.finditer(code):
        if m.start() < pos: continue
        before = code[max(0, m.start() - 1):m.start()]
        if before and (before.isalnum() or before in "_."): continue
        k = m.end(); e = expr_end(code, k)
        lhs, op, rhs = m.group(1), m.group(2), code[k:e].rstrip()
        out.append(code[pos:m.start()])
        out.append("%s = %s %s (%s) " % (lhs, lhs, op, rhs))
        pos = e
    out.append(code[pos:])
    code = "".join(out)
    return re.sub("\x00(\\d+)\x00", lambda m: keep[int(m.group(1))], code)

def main():
    src = open(sys.argv[1], encoding="utf-8").read()
    res = compound(src)
    if re.search(r"(?<![\w\"'])continue(?![\w\"'])", "".join(t for c, t in segments(res) if c)):
        sys.stderr.write("WARNING: 'continue' found, fix it by hand\n")
    open(sys.argv[2], "w", encoding="utf-8").write(res)

if __name__ == "__main__":
    main()
