#!/usr/bin/env python3
"""atlas-ts-helper — tree-sitter structure extractor for atlas.

The optional **parser ceiling** of atlas's hybrid extraction (design-v2
decision 22). atlas bundles no tree-sitter and runs fully on its regex floor;
this helper, when installed, raises edge precision by doing real scope
resolution — emitting a ``to`` target per call site that collapses a
corpus-ambiguous name to a ``resolved`` edge.

Contract (consumed by atlas ``run_ts_helper`` / ``symbols_from_helper`` /
``call_sites_from_helper`` in ``bin/atlas-cli``): read ``extract --root <root>``
with a NUL-free, newline-delimited list of repo-relative paths on **stdin**, and
emit on **stdout**::

    {"version": 1, "files": {"<repo-relative path>": {
        "symbols": [{"name","kind","start_line","end_line",
                     "signature","visibility","qualified_name"}],
        "calls":   [{"callee","line","to": {"file","start_line"}?}]}}}

Invariants the consumer relies on:

* ``version`` MUST stay ``1`` until atlas AND every deployed helper upgrade
  together — atlas silently rejects a ``version: 2`` payload and falls back to
  regex, so a lockstep bump is the only safe upgrade.
* ``start_line``/``end_line`` are 1-indexed, end inclusive. atlas recomputes
  ``span_hash`` from the **actual file bytes** between them, so the content
  address stays faithful regardless of backend — but it means a grammar upgrade
  that shifts a declaration's span boundaries re-hashes those symbols and
  re-judges their cells. **Pin the grammar** (see pyproject) and treat a bump
  like a generator-fingerprint bump.
* ``qualified_name`` stays the **bare** name (matching atlas's regex backend) so
  the ``path::qualified_name`` symbol id is identical across backends — judgment
  keys stay stable when you switch on the helper.
* A file the helper cannot parse (or whose language has no bundled grammar) is
  simply omitted; atlas falls back to regex for it. The helper may answer for
  fewer files than requested.

Currently parses **Swift**. Scope resolution tracks simple local-variable types
(``let x = Type()`` / ``let x: Type``) so a ``receiver.method()`` call resolves
to the right one of several same-named methods — the precision win the regex
floor cannot reach (it keeps such a name ``ambiguous``).
"""
import argparse
import json
import os
import sys

#: The structure-JSON contract version. Lockstep with atlas ``TS_HELPER_VERSION``.
HELPER_VERSION = 1

#: repo-relative file extension -> tree-sitter-language-pack language name.
#: Add a row (and a real test) to teach the helper another language.
LANG_BY_EXT = {"swift": "swift"}

#: Swift type-declaration node types. ``class_declaration`` is shared across
#: class/struct/actor/extension (disambiguated by the leading keyword token).
_TYPE_DECL_NODES = frozenset((
    "class_declaration", "enum_declaration", "protocol_declaration"))
_FUNC_DECL_NODE = "function_declaration"
_TYPE_KEYWORDS = frozenset((
    "class", "struct", "actor", "extension", "enum", "protocol"))


def _get_parser(lang):
    """A tree-sitter parser for ``lang``, or ``None`` if the grammar/dependency
    is absent — so a missing language-pack degrades to "the helper answers for
    no files" and atlas falls back to regex, never a hard error."""
    try:
        from tree_sitter_language_pack import get_parser
    except Exception:
        return None
    try:
        return get_parser(lang)
    except Exception:
        return None


def _text(src, node):
    return src[node.start_byte:node.end_byte].decode("utf-8", "replace")


def _line(node):
    return node.start_point[0] + 1


def _visibility(src, node):
    """``public``/``private``/``internal``/… read from a Swift ``modifiers``
    child. Swift's default access level is ``internal``."""
    for c in node.children:
        if c.type == "modifiers":
            for m in c.children:
                if m.type == "visibility_modifier":
                    return _text(src, m)
    return "internal"


def _decl_keyword(src, node):
    """The leading keyword token (class/struct/actor/extension/enum/protocol) —
    the atlas ``kind``. ``class_declaration`` covers several, so read the token
    rather than the node type."""
    for c in node.children:
        if not c.is_named and c.type in _TYPE_KEYWORDS:
            return c.type
    return {"enum_declaration": "enum",
            "protocol_declaration": "protocol"}.get(node.type, "class")


def _type_name_node(node):
    """The type-declaration's bare-name node. The ``name`` field is a
    ``type_identifier``, or a ``user_type`` wrapping one (extensions)."""
    name_node = node.child_by_field_name("name")
    if name_node is None:
        return None
    if name_node.type == "type_identifier":
        return name_node
    for c in name_node.children:
        if c.type == "type_identifier":
            return c
    return None


def _signature(src, node):
    """A declaration's first line, whitespace-collapsed and brace/where-trimmed
    — the same shape atlas's ``normalize_signature`` produces, so signatures
    read alike across backends."""
    line = _text(src, node).split("\n", 1)[0]
    for cut in (" where ", "{"):
        idx = line.find(cut)
        if idx >= 0:
            line = line[:idx]
    return " ".join(line.split()).rstrip("{ ").strip()


class _FileResult:
    __slots__ = ("symbols", "calls")

    def __init__(self):
        self.symbols = []
        self.calls = []


def _collect_symbols(src, root, relpath, result, type_members, free_funcs):
    """Walk every type/function declaration (nested included). Appends contract
    symbols and fills the two tables call resolution joins against:
    ``type_members[Type][method] = (file, start_line)`` for *enclosed* methods,
    and ``free_funcs[name] = [(file, start_line), …]`` for *top-level* functions
    only. A bare ``func()`` call must resolve to a free function, never a
    same-named *method* — otherwise a bare SwiftUI ``dismiss()`` (an
    ``@Environment(\\.dismiss)`` action) forges a false edge to some type's
    ``dismiss`` method. Both tables store ``_line(node)`` (the declaration's
    start line), matching the emitted symbol ``start_line`` so atlas's
    ``loc_to_id`` join lands even when a leading attribute/modifier sits on its
    own line."""
    def visit(node, enclosing_type):
        declared_type = None
        if node.type in _TYPE_DECL_NODES or node.type == "class_declaration":
            tn = _type_name_node(node)
            if tn is not None:
                declared_type = _text(src, tn)
                result.symbols.append({
                    "name": declared_type, "qualified_name": declared_type,
                    "kind": _decl_keyword(src, node),
                    "start_line": _line(node), "end_line": node.end_point[0] + 1,
                    "signature": _signature(src, node),
                    "visibility": _visibility(src, node)})
        elif node.type == _FUNC_DECL_NODE:
            name_node = node.child_by_field_name("name")
            if name_node is not None:
                fname = _text(src, name_node)
                result.symbols.append({
                    "name": fname, "qualified_name": fname, "kind": "func",
                    "start_line": _line(node), "end_line": node.end_point[0] + 1,
                    "signature": _signature(src, node),
                    "visibility": _visibility(src, node)})
                if enclosing_type is not None:
                    type_members.setdefault(enclosing_type, {}).setdefault(
                        fname, (relpath, _line(node)))
                else:
                    free_funcs.setdefault(fname, []).append(
                        (relpath, _line(node)))
        next_type = declared_type if declared_type is not None else enclosing_type
        for c in node.children:
            if c.is_named:
                visit(c, next_type)

    visit(root, None)


def _annotation_type(src, ann):
    """The bare type name from a ``: Type`` annotation (``user_type`` ->
    ``type_identifier``)."""
    if ann is None:
        return None
    for c in ann.children:
        if c.type == "user_type":
            for t in c.children:
                if t.type == "type_identifier":
                    return _text(src, t)
        if c.type == "type_identifier":
            return _text(src, c)
    return None


def _constructor_type(src, value):
    """``Type()`` -> ``"Type"``: a ``call_expression`` whose callee is a bare
    identifier. Resolution later only matches real type tables, so a false
    positive here costs nothing."""
    if value is None or value.type != "call_expression" or not value.children:
        return None
    callee = value.children[0]
    if callee.type == "simple_identifier":
        return _text(src, callee)
    return None


def _local_var_types(src, func_body):
    """``{var_name: TypeName}`` for ``let/var x = Type()`` and ``let x: Type``
    declared in one function body — the minimal type inference that lets
    ``x.method()`` resolve to a specific type's method."""
    types = {}

    def visit(node):
        if node.type == "property_declaration":
            name_node = node.child_by_field_name("name")
            var_name = None
            if name_node is not None and name_node.type == "pattern":
                ident = name_node.child_by_field_name("bound_identifier")
                var_name = _text(src, ident) if ident is not None else _text(src, name_node)
            if var_name:
                tname = _annotation_type(src, node.child_by_field_name("type"))
                if tname is None:
                    tname = _constructor_type(src, node.child_by_field_name("value"))
                if tname:
                    types[var_name] = tname
        for c in node.children:
            if c.is_named:
                visit(c)

    visit(func_body)
    return types


def _emit_call(src, relpath, node, result, type_members, free_funcs, local_types):
    """Append one call site for a ``call_expression``, resolving ``to`` when the
    callee binds to a known definition (see ``_collect_calls``)."""
    head = node.children[0] if node.children else None
    if head is None:
        return
    callee = None
    to = None
    if head.type == "navigation_expression":
        target = head.child_by_field_name("target")
        suffix = head.child_by_field_name("suffix")
        method = None
        if suffix is not None:
            mnode = suffix.child_by_field_name("suffix")
            method = _text(src, mnode) if mnode is not None else None
        if method is None:
            return
        callee = method
        recv_type = None
        if target is not None and target.type == "simple_identifier":
            recv = _text(src, target)
            # a locally-typed variable, or the type itself (a static call)
            recv_type = local_types.get(recv) or (recv if recv in type_members else None)
        if recv_type and method in type_members.get(recv_type, {}):
            f, ln = type_members[recv_type][method]
            to = {"file": f, "start_line": ln}
    elif head.type == "simple_identifier":
        callee = _text(src, head)
        cands = free_funcs.get(callee)
        if cands and len(cands) == 1:
            f, ln = cands[0]
            to = {"file": f, "start_line": ln}
    if not callee:
        return
    call = {"callee": callee, "line": _line(node)}
    if to is not None:
        call["to"] = to
    result.calls.append(call)


def _collect_calls(src, root, relpath, result, type_members, free_funcs):
    """Emit a call site per ``call_expression``, resolving ``to`` when possible:
      * ``receiver.method()`` with a locally-typed receiver -> that type's method
      * ``Type.method()`` (static)                          -> that type's method
      * bare ``func()``                                     -> the unique
        corpus-wide TOP-LEVEL free function of that name (never a same-named
        method — see ``_collect_symbols``)

    ``to`` is omitted when unresolved; atlas then resolves by name only to a
    TYPE (``resolved``), never to a bare func/method (dropped)."""
    def visit(node, local_types):
        if node.type == "function_body":
            local_types = dict(local_types)
            local_types.update(_local_var_types(src, node))
        if node.type == "call_expression":
            _emit_call(src, relpath, node, result, type_members,
                       free_funcs, local_types)
        for c in node.children:
            if c.is_named:
                visit(c, local_types)

    visit(root, {})


def extract(root, paths):
    """Two passes over the requested files: pass 1 parses each and builds the
    corpus-wide type-member and free-function tables; pass 2 resolves calls
    against them (resolution needs the whole corpus). Returns the contract dict.
    """
    parsed = {}        # relpath -> (src_bytes, tree)
    results = {}       # relpath -> _FileResult
    type_members = {}  # TypeName -> {method: (file, start_line)}
    free_funcs = {}    # name -> [(file, start_line), …]

    for relpath in paths:
        base = os.path.basename(relpath)
        ext = relpath.rsplit(".", 1)[-1].lower() if "." in base else ""
        lang = LANG_BY_EXT.get(ext)
        if not lang:
            continue
        parser = _get_parser(lang)
        if parser is None:
            continue
        try:
            with open(os.path.join(root, relpath), "rb") as f:
                src = f.read()
        except OSError:
            continue
        try:
            tree = parser.parse(src)
        except Exception:
            continue
        parsed[relpath] = (src, tree)
        results[relpath] = _FileResult()

    for relpath, (src, tree) in parsed.items():
        _collect_symbols(src, tree.root_node, relpath, results[relpath],
                         type_members, free_funcs)

    for relpath, (src, tree) in parsed.items():
        _collect_calls(src, tree.root_node, relpath, results[relpath],
                       type_members, free_funcs)

    return {"version": HELPER_VERSION,
            "files": {rp: {"symbols": r.symbols, "calls": r.calls}
                      for rp, r in results.items()}}


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="atlas-ts-helper",
        description="tree-sitter structure extractor for atlas (emits the v1 "
                    "structure-JSON contract on stdout).")
    sub = parser.add_subparsers(dest="cmd")
    ex = sub.add_parser("extract", help="emit the contract for the stdin path list")
    ex.add_argument("--root", default=".",
                    help="repo root the stdin paths are relative to")
    args = parser.parse_args(argv)
    if args.cmd != "extract":
        parser.print_help(sys.stderr)
        return 2
    paths = [p.strip() for p in sys.stdin.read().splitlines() if p.strip()]
    json.dump(extract(args.root, paths), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
