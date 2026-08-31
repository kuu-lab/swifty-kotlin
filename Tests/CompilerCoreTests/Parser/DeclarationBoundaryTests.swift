#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// BUG-208 (found while implementing KSP-614): a body-less top-level
/// declaration — such as the `external fun` bridges used by the bundled Kotlin
/// stdlib — used to absorb the following declaration when that declaration
/// started with a visibility/linkage modifier, because only `fun`/`val`/`class`
/// and friends were treated as statement boundaries.  The absorbed declaration
/// disappeared from the symbol table entirely (calls to it failed with
/// `KSWIFTK-SEMA-0002` / `KSWIFTK-SEMA-0023`).
@Suite
struct DeclarationBoundaryTests {
    private func funDeclCount(_ source: String) -> Int {
        nodeCount(source, kind: .funDecl)
    }

    private func nodeCount(_ source: String, kind: SyntaxKind) -> Int {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let lexer = KotlinLexer(
            file: FileID(rawValue: 0),
            source: Data(source.utf8),
            interner: interner,
            diagnostics: diagnostics
        )
        let parser = KotlinParser(tokens: lexer.lexAll(), interner: interner, diagnostics: diagnostics)
        let parsed = parser.parseFile()
        return parsed.arena.nodes.count { $0.kind == kind }
    }

    /// Direct `.node` children of kind `blockChildKind` inside the first
    /// `.block` node found anywhere in the file (i.e. a function/constructor
    /// body), skipping over unrelated sibling structure like a parameter list.
    /// Assumes `source` contains exactly one `{ ... }` block (single function);
    /// with more than one, this only inspects the first block encountered.
    private func blockChildCount(_ source: String, blockChildKind: SyntaxKind) -> Int {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let lexer = KotlinLexer(
            file: FileID(rawValue: 0),
            source: Data(source.utf8),
            interner: interner,
            diagnostics: diagnostics
        )
        let parser = KotlinParser(tokens: lexer.lexAll(), interner: interner, diagnostics: diagnostics)
        let parsed = parser.parseFile()
        guard let blockID = parsed.arena.nodes.indices.first(where: { parsed.arena.nodes[$0].kind == .block }) else {
            return 0
        }
        return parsed.arena.children(of: NodeID(rawValue: Int32(blockID))).count { child in
            guard case let .node(nodeID) = child else { return false }
            return parsed.arena.node(nodeID).kind == blockChildKind
        }
    }

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
        #expect(funDeclCount(source) == 3)
    }

    @Test
    func testExpressionBodiedPropertyDoesNotAbsorbFollowingModifiedDeclaration() {
        let source = """
        val answer = 42

        private fun helper(): Int = answer
        """
        #expect(funDeclCount(source) == 1)
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
        #expect(nodeCount(source, kind: .propertyDecl) == 1)
        #expect(funDeclCount(source) == 1)
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
}
#endif
