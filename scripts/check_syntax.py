"""Optional syntax check; pip install --target .validation tree-sitter tree-sitter-swift openstep-parser.
No type checking, macro expansion or Apple API validation is performed.
"""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / ".validation"))
from tree_sitter import Language, Parser
import tree_sitter_swift
from openstep_parser import OpenStepDecoder

parser = Parser(Language(tree_sitter_swift.language()))
failed = []
paths = list((root / "ClockWork").rglob("*.swift")) + list((root / "Tests").rglob("*.swift")) + [root / "Package.swift"]
for path in paths:
    tree = parser.parse(path.read_bytes())
    if tree.root_node.has_error:
        failed.append(path)
        def report(node):
            if node.type == "ERROR" or node.is_missing:
                print(f"{path.relative_to(root)}:{node.start_point.row + 1}: {node.type} {node.text[:160]!r}")
            for child in node.children: report(child)
        report(tree.root_node)
with (root / "ClockWork.xcodeproj/project.pbxproj").open(encoding="utf-8") as file:
    project = OpenStepDecoder.ParseFromFile(file)
assert project["rootObject"] in project["objects"]
if failed: raise SystemExit(f"Syntax errors in {len(failed)} file(s)")
print(f"PASS: syntax trees for {len(paths)} Swift files and OpenStep Xcode project. Not a compiler or XCTest run.")
