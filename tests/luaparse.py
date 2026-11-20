"""Small Luau syntax checker: a real parse plus a list of undefined globals."""
import re, sys

KEYWORDS = {"and", "break", "continue", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
            "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}
OPS = ["...", "..=", "==", "~=", "<=", ">=", "..", "+=", "-=", "*=", "/=", "%=", "^=", "//", "::",
       "+", "-", "*", "/", "%", "^", "#", "<", ">", "=", "(", ")", "{", "}", "[", "]", ";", ":", ",", ".", "?"]


class Tok:
    __slots__ = ("k", "v", "line")
    def __init__(s, k, v, line): s.k, s.v, s.line = k, v, line
    def __repr__(s): return f"{s.k}:{s.v!r}@{s.line}"


def lex(src):
    i, n, line, out = 0, len(src), 1, []
    while i < n:
        c = src[i]
        if c == "\n": line += 1; i += 1; continue
        if c in " \t\r": i += 1; continue
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i)
                if j < 0: raise SyntaxError(f"line {line}: unclosed long comment")
                line += src[i:j].count("\n"); i = j + len(close)
            else:
                j = src.find("\n", i); i = n if j < 0 else j
            continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            j = src.find(close, i)
            if j < 0: raise SyntaxError(f"line {line}: unclosed long string")
            out.append(Tok("str", src[i:j], line)); line += src[i:j].count("\n"); i = j + len(close); continue
        if c in "\"'":
            j = i + 1
            while True:
                if j >= n: raise SyntaxError(f"line {line}: unclosed string")
                ch = src[j]
                if ch == "\\":
                    if src[j + 1] == "\n": line += 1
                    j += 2; continue
                if ch == "\n": raise SyntaxError(f"line {line}: newline in string")
                if ch == c: break
                j += 1
            out.append(Tok("str", src[i + 1:j], line)); i = j + 1; continue
        m = re.match(r"0[xX][0-9a-fA-F_]+|0[bB][01_]+|(\d[\d_]*\.?[\d_]*|\.\d[\d_]*)([eE][+-]?\d+)?", src[i:])
        if m and m.group(0):
            out.append(Tok("num", m.group(0), line)); i += len(m.group(0)); continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[i:])
        if m:
            w = m.group(0)
            out.append(Tok("kw" if w in KEYWORDS else "name", w, line)); i += len(w); continue
        for op in OPS:
            if src.startswith(op, i):
                out.append(Tok("op", op, line)); i += len(op); break
        else:
            raise SyntaxError(f"line {line}: unexpected char {c!r}")
    out.append(Tok("eof", None, line))
    return out


BINPRI = {"or": (1, 1), "and": (2, 2), "<": (3, 3), ">": (3, 3), "<=": (3, 3), ">=": (3, 3), "~=": (3, 3), "==": (3, 3),
          "..": (5, 4), "+": (6, 6), "-": (6, 6), "*": (7, 7), "/": (7, 7), "//": (7, 7), "%": (7, 7), "^": (10, 9)}
UNARY_PRI = 8


class Parser:
    def __init__(s, toks):
        s.t, s.p = toks, 0
        s.scopes = [set()]
        s.globals_used = {}
        s.globals_set = set()
        s.loop_depth = [0]

    # helpers
    def cur(s): return s.t[s.p]
    def peek(s, o=1): return s.t[s.p + o]
    def check(s, k, v=None):
        t = s.cur(); return t.k == k and (v is None or t.v == v)
    def accept(s, k, v=None):
        if s.check(k, v): s.p += 1; return True
        return False
    def expect(s, k, v=None):
        t = s.cur()
        if not s.check(k, v): raise SyntaxError(f"line {t.line}: expected {v or k}, got {t.v!r}")
        s.p += 1; return t
    def declare(s, name): s.scopes[-1].add(name)
    def resolve(s, name, line, assign=False):
        for sc in reversed(s.scopes):
            if name in sc: return
        if assign: s.globals_set.add(name)
        else: s.globals_used.setdefault(name, line)

    def block(s, terminators):
        s.scopes.append(set())
        while not (s.cur().k == "kw" and s.cur().v in terminators) and not s.check("eof"):
            if s.check("kw", "return"):
                s.p += 1
                if not (s.cur().k == "kw" and s.cur().v in terminators) and not s.check("eof") and not s.check("op", ";"):
                    s.exprlist()
                s.accept("op", ";")
                break
            s.statement()
        s.scopes.pop()

    def statement(s):
        t = s.cur()
        if s.accept("op", ";"): return
        if t.k == "kw":
            v = t.v
            if v == "local":
                s.p += 1
                if s.accept("kw", "function"):
                    name = s.expect("name").v; s.declare(name); s.funcbody(); return
                names = [s.expect("name").v]
                s.attrib()
                while s.accept("op", ","):
                    names.append(s.expect("name").v); s.attrib()
                if s.accept("op", "="): s.exprlist()
                for nme in names: s.declare(nme)
                return
            if v == "function":
                s.p += 1
                n = s.expect("name"); s.resolve(n.v, n.line, assign=True)
                method = False
                while s.accept("op", "."): s.expect("name")
                if s.accept("op", ":"): s.expect("name"); method = True
                s.funcbody(method); return
            if v == "if":
                s.p += 1; s.expr(); s.expect("kw", "then"); s.block({"elseif", "else", "end"})
                while s.accept("kw", "elseif"):
                    s.expr(); s.expect("kw", "then"); s.block({"elseif", "else", "end"})
                if s.accept("kw", "else"): s.block({"end"})
                s.expect("kw", "end"); return
            if v == "while":
                s.p += 1; s.expr(); s.expect("kw", "do"); s.loop(lambda: s.block({"end"})); s.expect("kw", "end"); return
            if v == "do":
                s.p += 1; s.block({"end"}); s.expect("kw", "end"); return
            if v == "repeat":
                s.p += 1
                s.scopes.append(set())
                s.loop_depth[-1] += 1
                while not s.check("kw", "until") and not s.check("eof"):
                    if s.check("kw", "return"):
                        s.p += 1
                        if not s.check("kw", "until"): s.exprlist()
                        break
                    s.statement()
                s.loop_depth[-1] -= 1
                s.expect("kw", "until"); s.expr(); s.scopes.pop(); return
            if v == "for":
                s.p += 1
                n1 = s.expect("name").v
                if s.accept("op", "="):
                    s.expr(); s.expect("op", ","); s.expr()
                    if s.accept("op", ","): s.expr()
                    names = [n1]
                else:
                    names = [n1]
                    while s.accept("op", ","): names.append(s.expect("name").v)
                    s.expect("kw", "in"); s.exprlist()
                s.expect("kw", "do")
                s.scopes.append(set(names))
                s.loop(lambda: s.block({"end"}))
                s.scopes.pop()
                s.expect("kw", "end"); return
            if v == "break" or v == "continue":
                if s.loop_depth[-1] <= 0: raise SyntaxError(f"line {t.line}: {v} outside loop")
                s.p += 1; return
            if v == "return":
                raise SyntaxError(f"line {t.line}: return must be last statement in block")
            raise SyntaxError(f"line {t.line}: unexpected keyword {v}")
        # continue as identifier (Luau) handled above; expression statement
        targets = [s.suffixedexp(stmt=True)]
        if s.check("op", "=") or s.check("op", ","):
            while s.accept("op", ","): targets.append(s.suffixedexp(stmt=True))
            s.expect("op", "=")
            s.exprlist()
            for tg in targets:
                if tg[0] == "call": raise SyntaxError(f"line {t.line}: cannot assign to call")
                if tg[0] == "name": s.resolve(tg[1], t.line, assign=True)
            return
        if s.cur().k == "op" and s.cur().v in ("+=", "-=", "*=", "/=", "%=", "^=", "..="):
            if targets[0][0] == "call": raise SyntaxError(f"line {t.line}: cannot assign to call")
            if targets[0][0] == "name": s.resolve(targets[0][1], t.line)
            s.p += 1; s.expr(); return
        if targets[0][0] != "call": raise SyntaxError(f"line {t.line}: syntax error near {s.cur().v!r} (expression is not a statement)")

    def loop(s, fn):
        s.loop_depth[-1] += 1; fn(); s.loop_depth[-1] -= 1

    def attrib(s):
        if s.accept("op", "<"): s.expect("name"); s.expect("op", ">")

    def funcbody(s, method=False):
        s.expect("op", "(")
        params = set(["self"]) if method else set()
        if not s.check("op", ")"):
            while True:
                if s.accept("op", "..."): params.add("..."); break
                params.add(s.expect("name").v)
                if not s.accept("op", ","): break
        s.expect("op", ")")
        s.scopes.append(params)
        s.loop_depth.append(0)
        s.block({"end"})
        s.loop_depth.pop()
        s.scopes.pop()
        s.expect("kw", "end")

    def exprlist(s):
        s.expr()
        while s.accept("op", ","): s.expr()

    def primaryexp(s):
        t = s.cur()
        if s.accept("name"):
            return ("name", t.v)
        if s.accept("op", "("):
            s.expr(); s.expect("op", ")"); return ("paren", None)
        raise SyntaxError(f"line {t.line}: unexpected {t.v!r}")

    def suffixedexp(s, stmt=False):
        start = s.cur()
        e = s.primaryexp()
        if e[0] == "name": s._pending = (e[1], start.line)
        first = True
        kind = e
        while True:
            if s.accept("op", "."): s.expect("name"); kind = ("index", None)
            elif s.accept("op", "["): s.expr(); s.expect("op", "]"); kind = ("index", None)
            elif s.accept("op", ":"): s.expect("name"); s.callargs(); kind = ("call", None)
            elif s.check("op", "(") or s.check("str") or s.check("op", "{"):
                if s.check("op", "(") and s.cur().line != s.t[s.p - 1].line and stmt:
                    pass
                s.callargs(); kind = ("call", None)
            else: break
            if first and e[0] == "name":
                s.resolve(e[1], start.line)
                first = False
        if first and e[0] == "name" and not stmt:
            s.resolve(e[1], start.line)
        if first and e[0] == "name" and stmt:
            return ("name", e[1])
        return kind

    def callargs(s):
        if s.accept("str"): return
        if s.check("op", "{"): s.table(); return
        s.expect("op", "(")
        if not s.check("op", ")"): s.exprlist()
        s.expect("op", ")")

    def table(s):
        s.expect("op", "{")
        while not s.check("op", "}"):
            if s.accept("op", "["):
                s.expr(); s.expect("op", "]"); s.expect("op", "="); s.expr()
            elif s.check("name") and s.peek().k == "op" and s.peek().v == "=":
                s.p += 2; s.expr()
            else:
                s.expr()
            if not (s.accept("op", ",") or s.accept("op", ";")): break
        s.expect("op", "}")

    def simpleexp(s):
        t = s.cur()
        if t.k in ("num", "str"): s.p += 1; return
        if t.k == "kw" and t.v in ("nil", "true", "false"): s.p += 1; return
        if s.accept("op", "..."):
            for sc in reversed(s.scopes):
                if "..." in sc: return
            raise SyntaxError(f"line {t.line}: '...' outside vararg function")
        if s.check("op", "{"): s.table(); return
        if s.accept("kw", "function"): s.funcbody(); return
        if s.accept("kw", "if"):
            s.expr(); s.expect("kw", "then"); s.expr()
            while s.accept("kw", "elseif"): s.expr(); s.expect("kw", "then"); s.expr()
            s.expect("kw", "else"); s.expr(); return
        s.suffixedexp()

    def expr(s, limit=0):
        t = s.cur()
        if (t.k == "kw" and t.v == "not") or (t.k == "op" and t.v in ("-", "#")):
            s.p += 1; s.expr(UNARY_PRI)
        else:
            s.simpleexp()
        while True:
            t = s.cur()
            op = t.v if (t.k == "op" or (t.k == "kw" and t.v in ("and", "or"))) else None
            if op in BINPRI and BINPRI[op][0] > limit:
                s.p += 1; s.expr(BINPRI[op][1])
            else: break


def check(path):
    src = open(path, encoding="utf-8").read()
    toks = lex(src)
    p = Parser(toks)
    p.scopes[0].add("...")
    p.block(set())
    if not p.check("eof"): raise SyntaxError(f"line {p.cur().line}: unexpected {p.cur().v!r} (extra 'end'?)")
    return p


ROBLOX = set("""game workspace script Instance Vector2 Vector3 CFrame Color3 UDim UDim2 Rect Enum Ray RaycastParams TweenInfo
NumberRange NumberSequence ColorSequence BrickColor math string table os task coroutine typeof type tostring tonumber pairs ipairs next
select unpack print warn error pcall xpcall setmetatable getmetatable rawget rawset rawequal require tick wait spawn delay utf8 bit32
debug buffer Random DateTime PhysicalProperties Axes Faces Region3 loadstring shared _G _VERSION newproxy gcinfo elapsedTime
getgenv gethui cloneref hookmetamethod getnamecallmethod checkcaller newcclosure Drawing protectgui syn queue_on_teleport fluxus
setclipboard writefile readfile isfile isfolder makefolder fireclickdetector request http_request""".split())


if __name__ == "__main__":
    for path in sys.argv[1:]:
        try:
            p = check(path)
        except SyntaxError as e:
            print(f"{path}: SYNTAX ERROR {e}"); continue
        unknown = {k: v for k, v in p.globals_used.items() if k not in ROBLOX and k not in p.globals_set}
        print(f"{path}: OK" + (f"  · undefined globals: {unknown}" if unknown else ""))
        if p.globals_set: print("   globals assigned:", sorted(p.globals_set))
