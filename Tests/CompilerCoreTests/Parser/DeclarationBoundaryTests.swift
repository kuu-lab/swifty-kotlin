#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Regression tests for parser declaration boundaries: where one top-level or
/// block-level declaration ends and the next begins, and how far a
/// declaration's CST range reaches.
@Suite
struct DeclarationBoundaryTests {
    private func nodeCount(in arena: SyntaxArena, kind: SyntaxKind) -> Int {
        arena.nodes.count { $0.kind == kind }
    }

    private func nodeCount(_ source: String, kind: SyntaxKind) -> Int {
        nodeCount(in: parse(source).arena, kind: kind)
    }

    /// Parses `source` and returns the CST range of the root (file) node,
    /// which is the accumulation of every top-level declaration's range.
    private func rootRange(_ source: String) -> SourceRange {
        let parsed = parse(source)
        return parsed.arena.node(parsed.root).range
    }

    /// Direct `.node` children of kind `blockChildKind` inside the first
    /// `.block` node found anywhere in the file (i.e. a function/constructor
    /// body), skipping over unrelated sibling structure like a parameter list.
    /// Assumes `source` contains exactly one `{ ... }` block (single function);
    /// with more than one, this only inspects the first block encountered.
    private func blockChildCount(_ source: String, blockChildKind: SyntaxKind) -> Int {
        let arena = parse(source).arena
        guard let blockIndex = arena.nodes.firstIndex(where: { $0.kind == .block }) else {
            return 0
        }
        return arena.children(of: NodeID(rawValue: Int32(blockIndex))).count { child in
            guard case let .node(nodeID) = child else { return false }
            return arena.node(nodeID).kind == blockChildKind
        }
    }

    // BUG-208 (found while implementing KSP-614): a body-less top-level
    // declaration — such as the `external fun` bridges used by the bundled
    // Kotlin stdlib — used to absorb the following declaration when that
    // declaration started with a visibility/linkage modifier, because only
    // `fun`/`val`/`class` and friends were treated as statement boundaries.
    // The absorbed declaration disappeared from the symbol table entirely
    // (calls to it failed with `KSWIFTK-SEMA-0002` / `KSWIFTK-SEMA-0023`).

    @Test
    func testBodylessFunctionDoesNotAbsorbFollowingModifiedDeclaration() {
        let source = """
        external fun bridge(message: Any?)

        public fun first() {
            bridge("first")
        }

        public fun second() {
            bridge("second")
        }
        """
        #expect(nodeCount(source, kind: .funDecl) == 3)
    }

    @Test
    func testExpressionBodiedPropertyDoesNotAbsorbFollowingModifiedDeclaration() {
        let source = """
        val answer = 42

        private fun helper(): Int = answer
        """
        #expect(nodeCount(source, kind: .funDecl) == 1)
    }

    // BUG-227 (found while auditing BuildASTPhase+ConstructorParsing.swift):
    // `parseBlock()` only routed a declaration-start token to `parseDeclaration()`
    // when it had a leading newline or was the very first token in the block.
    // A declaration placed after a `;`-terminated statement on the *same*
    // physical line satisfies neither condition, so it fell through to the
    // generic `parseStatement()` path instead — which has no notion of
    // annotations or declaration keywords and swallows everything (including a
    // nested constructor body) into one opaque `.statement` node. The fix adds
    // "previous consumed token was `;`" as a third way to recognize a fresh
    // statement boundary, alongside a leading newline and block-start.

    @Test
    func testAnnotatedSecondaryConstructorAfterSemicolonIsNotAbsorbed() {
        let source = """
        class Foo(val x: Int) { val y = 1; @CtorOnly constructor() : this(0) }
        """
        #expect(nodeCount(source, kind: .constructorDecl) == 1)
    }

    @Test
    func testBareSecondaryConstructorAfterSemicolonStillParses() {
        let source = """
        class Foo(val x: Int) { val y = 1; constructor() : this(0) }
        """
        #expect(nodeCount(source, kind: .constructorDecl) == 1)
    }

    @Test
    func testPropertyDeclarationAfterSemicolonOnSameLineIsNotAbsorbed() {
        let source = """
        class Foo { val y = 1; val z = 2 }
        """
        #expect(nodeCount(source, kind: .propertyDecl) == 2)
    }

    @Test
    func testAnnotatedFunctionAfterSemicolonOnSameLineIsNotAbsorbed() {
        let source = """
        class Foo { val y = 1; @Deprecated("old") fun z() {} }
        """
        let arena = parse(source).arena
        #expect(nodeCount(in: arena, kind: .propertyDecl) == 1)
        #expect(nodeCount(in: arena, kind: .funDecl) == 1)
    }

    // `value`/`data`/... lex as declaration-modifier keywords even when used
    // as a plain identifier (e.g. an assignment target). The widened gate
    // above now also routes such a token to `parseDeclaration()` when it
    // follows a `;` mid-line, same as it already did when the token had a
    // leading newline or was first in the block. `parseDeclaration()`'s
    // fallback for "consumed a modifier-looking token, nothing recognizable
    // followed" still produces one `.statement` node per assignment, so this
    // must not merge the two statements into one.
    @Test
    func testModifierKeywordIdentifierAssignmentAfterSemicolonIsNotMerged() {
        let source = """
        fun f() { value.hashCode(); value = 1 }
        """
        #expect(blockChildCount(source, blockChildKind: .statement) == 2)
    }

    // Found while investigating a `@file:Suppress` annotation that failed to
    // suppress a diagnostic raised deep inside a trailing function's block
    // body (PR #6562's KSP-1216 native concurrent top-level tests). The root
    // node's range is the accumulation of every top-level declaration's
    // range, and file-level `@Suppress` registers that whole range as the
    // suppression window. The `lBrace` branches of `parseFunctionDeclaration`,
    // `parseEnumDeclaration`, and `parsePropertyDeclaration` all appended
    // their `{ ... }` body node to `children` but never fed its range into
    // the `RangeAccumulator` (nor, for functions, the parameter list's) — so
    // a block-bodied declaration's own range stopped at its name, silently
    // truncating the root range whenever such a declaration was the last (or
    // only) top-level declaration, and making any diagnostic inside its body
    // fall outside every file-level `@Suppress`/`@OptIn` window. Pre-existing
    // (last touched in b1e9bcc283); KSP-1216's tests were simply the first to
    // combine a file-level `@Suppress` header with a trailing block-bodied
    // `fun main`.
    @Test
    func testBlockBodiedFunctionRangeIncludesParametersAndBody() {
        let source = """
        fun main() {
            println(1)
        }
        """
        #expect(rootRange(source).end.offset == source.utf8.count)
    }

    @Test
    func testRootRangeReachesTrailingBlockBodiedFunction() {
        let source = """
        fun oldFn(): Int = 1

        fun main() {
            println(oldFn())
        }
        """
        #expect(rootRange(source).end.offset == source.utf8.count)
    }

    @Test
    func testRootRangeReachesTrailingEnumBody() {
        let source = """
        enum class Color { RED, GREEN }
        """
        #expect(rootRange(source).end.offset == source.utf8.count)
    }
}
#endif
