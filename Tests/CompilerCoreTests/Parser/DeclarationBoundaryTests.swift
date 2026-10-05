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

    @Test(arguments: [
        "object Cast : Holder({ value -> calls += 1; value as? String })",
        "class Cast : Holder({ value -> calls += 1; value as? String })",
        "object Cast : Holder({ value -> calls += 1; value as? String }) { fun member() {} }",
        "class Cast : Holder(f = { value -> calls += 1; value as? String }) { fun member() {} }",
        "object Cast : Holder(listOf({ value -> calls += 1; value as? String })[0])",
        "class Cast : Holder({ value -> val copy = value; calls += 1; copy as? String }, 42)",
    ])
    func superConstructorLambdaSemicolonsStayInsideDeclaration(declaration: String) throws {
        let parsed = parse("\(declaration)\nfun after() {}")
        let declarationNode = try #require(parsed.arena.nodes.first {
            $0.kind == .classDecl || $0.kind == .objectDecl
        })

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(declarationNode.range.end.offset == declaration.utf8.count)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == (declaration.contains("member") ? 2 : 1))
    }

    @Test(arguments: ["super", "this"])
    func secondaryConstructorLambdaSemicolonsStayInsideDelegation(delegation: String) throws {
        let constructor = "constructor() : \(delegation)({ value -> calls += 1; value as? String }) {}"
        let prefix = "class Cast : Holder {\n    constructor(f: (Any) -> String?) : super(f)\n    "
        let source = prefix + constructor + "\n    fun member() {}\n}\nfun after() {}"
        let parsed = parse(source)
        let constructors = parsed.arena.nodes.filter { $0.kind == .constructorDecl }
        let lambdaConstructor = try #require(constructors.last)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(constructors.count == 2)
        #expect(lambdaConstructor.range.end.offset == prefix.utf8.count + constructor.utf8.count)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 2)
    }

    @Test
    func topLevelSemicolonStillSeparatesSuperConstructorDeclaration() {
        let declaration = "object Cast : Holder({ value -> calls += 1; value as? String });"
        let parsed = parse("\(declaration) fun after() {}")

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.first { $0.kind == .objectDecl }?.range.end.offset == declaration.utf8.count)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 1)
    }

    @Test(arguments: [
        "bytes[2].toInt()",
        "bytes[0]",
        "bytes.size",
        "bytes.copy().size",
        "copy(bytes).size",
    ])
    func pendingInfixAfterPostfixOperandContinuesDeclaration(operand: String) {
        let pending = lex("val result = 1 or \(operand) or").tokens.dropLast()
        let complete = lex("val result = 1 or \(operand)").tokens.dropLast()
        #expect(KotlinParser.endsWithPendingInfixOperator(pending))
        #expect(!KotlinParser.endsWithPendingInfixOperator(complete))
    }

    @Test(arguments: [
        "fun f(s: String?) = s!!.length",
        "val h = xs.scanReduce { acc, v -> acc + v }.size",
        "xs.scanReduce { acc, v -> acc + v }.size",
        "val complete = 1 or bytes.size",
    ])
    func qualifiedAndPostfixExpressionsDoNotEndWithPendingInfixOperator(expression: String) {
        let tokens = lex(expression).tokens.dropLast()
        #expect(!KotlinParser.endsWithPendingInfixOperator(tokens))
    }

    @Test
    func completeInfixWithCallOperandDoesNotAbsorbReturn() {
        let source = """
        fun code(): Int {
            val result = read() xor Int.MIN_VALUE
            return result
        }
        """
        #expect(blockChildCount(source, blockChildKind: .statement) == 1)
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

    @Test(arguments: [
        "listOf(object : J { override fun f() = 7; override fun g() = 8 })",
        "id(object : J { override fun f() = 7; override fun g() = 8 })",
        "(object : J { override fun f() = 7; override fun g() = 8 })",
        "listOf(listOf(object : J { override fun f() = 7; override fun g() = 8 }))",
        "listOf(object { val x = 7; val y = 8 })",
        "listOf(object : J { override fun f() = 7; override fun g() = 8; })",
        "object : J { override fun f() = 7; override fun g() = 8 }",
        "listOf(object : J { override fun f() = 7; override fun g() = 8 })[0]",
        "object : J { override fun f() = 7; override fun g() = 8 }.f()",
        "listOf(object : J { override fun f() = 7 })",
        "run { 1; 2 }",
        "run({ 1; 2 })",
    ])
    func nestedSemicolonsDoNotEndPropertyInitializer(initializer: String) throws {
        let source = """
        interface J { fun f() = 1; fun g(): Int }
        fun main() {
            val result = \(initializer)
            println(result)
        }
        """
        let parsed = parse(source)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).range.end.offset == source.utf8.count)
        let property = try #require(parsed.arena.nodes.first { $0.kind == .propertyDecl })
        let prefix = "interface J { fun f() = 1; fun g(): Int }\nfun main() {\n    val result = "
        #expect(property.range.end.offset == prefix.utf8.count + initializer.utf8.count)
    }

    @Test(arguments: ["val result", "fun result()"])
    func nestedSemicolonsDoNotEndTopLevelExpressionBody(declaration: String) throws {
        let source = """
        \(declaration) = listOf(object { val x = 7; val y = 8 })
        fun next() = 9
        """
        let parsed = parse(source)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        let first = try #require(parsed.arena.children(of: parsed.root).compactMap { child -> SyntaxNode? in
            guard case let .node(id) = child else { return nil }
            return parsed.arena.node(id)
        }.first)
        #expect(first.range.end.offset == source.split(separator: "\n")[0].utf8.count)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == (declaration == "val result" ? 1 : 2))
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

    @Test
    func valueKeywordExpressionBodyDoesNotConsumeFollowingDeclaration() throws {
        let source = """
        class Holder(var value: Int)

        fun Holder.read(): Int = value

        fun Holder.other(): Int = 0
        """
        let parsed = parse(source)
        let functions = parsed.arena.nodes.enumerated().filter { $0.element.kind == .funDecl }
        #expect(functions.count == 2)
        let read = try #require(functions.first)
        let other = try #require(functions.last)
        let readTokens = parsed.arena.children(of: NodeID(rawValue: Int32(read.offset))).compactMap {
            if case let .token(id) = $0 { return parsed.arena.token(id)?.kind }
            return nil
        }
        let otherTokens = parsed.arena.children(of: NodeID(rawValue: Int32(other.offset))).compactMap {
            if case let .token(id) = $0 { return parsed.arena.token(id)?.kind }
            return nil
        }
        #expect(readTokens.contains(.keyword(.value)))
        #expect(otherTokens.contains(.symbol(.assign)))
        #expect(!otherTokens.contains(.keyword(.value)))
    }

    @Test
    func valueKeywordAfterAssignmentNewlineStaysInExpressionBody() throws {
        let source = """
        class Holder(var value: Int)
        fun Holder.read(): Int =
            value
        fun Holder.other(): Int = 0
        """
        let parsed = parse(source)
        let functions = parsed.arena.nodes.enumerated().filter { $0.element.kind == .funDecl }
        #expect(functions.count == 2)
        let read = try #require(functions.first)
        let other = try #require(functions.last)
        let readTokens = parsed.arena.children(of: NodeID(rawValue: Int32(read.offset))).compactMap {
            if case let .token(id) = $0 { return parsed.arena.token(id)?.kind }
            return nil
        }
        let otherTokens = parsed.arena.children(of: NodeID(rawValue: Int32(other.offset))).compactMap {
            if case let .token(id) = $0 { return parsed.arena.token(id)?.kind }
            return nil
        }
        #expect(readTokens.contains(.keyword(.value)))
        #expect(otherTokens.contains(.symbol(.assign)))
        #expect(!otherTokens.contains(.keyword(.value)))
    }

    @Test
    func valueKeywordExtensionPropertyDoesNotConsumeFollowingDeclaration() throws {
        let source = """
        class Holder(val base: Int)
        val Holder.value: Int get() = base

        fun Holder.other(): Int = 0
        """
        let parsed = parse(source)
        let properties = parsed.arena.nodes.enumerated().filter { $0.element.kind == .propertyDecl }
        #expect(properties.count == 1)
        let functions = parsed.arena.nodes.enumerated().filter { $0.element.kind == .funDecl }
        #expect(functions.count == 1)
        let other = try #require(functions.first)
        let otherTokens = parsed.arena.children(of: NodeID(rawValue: Int32(other.offset))).compactMap {
            if case let .token(id) = $0 { return parsed.arena.token(id)?.kind }
            return nil
        }
        #expect(otherTokens.contains(.symbol(.assign)))
    }

    @Test
    func valueClassModifierStillIntroducesClassDeclaration() {
        let source = """
        @JvmInline value class Wrapped(val value: Int)
        fun Wrapped.read(): Int = value
        """
        #expect(nodeCount(source, kind: .classDecl) == 1)
        #expect(nodeCount(source, kind: .funDecl) == 1)
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

    @Test
    func testAnnotationPrefixedEnumEntryIsNotParsedAsADeclaration() {
        let source = """
        enum class AnnotationTarget {
            CLASS,
            @SinceKotlin("1.1")
            TYPEALIAS
        }
        """
        #expect(nodeCount(source, kind: .enumEntry) == 2)
    }

    @Test
    func longModifierPrefixLookaheadIsBoundedAndRecovers() {
        let modifiers = Array(repeating: "suspend", count: 4_200).joined(separator: "\n")
        let source = "val answer = 42\n\(modifiers)\nnotADeclaration"
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0007" })
        #expect(parsed.arena.node(parsed.root).kind == .script)
    }

    @Test
    func longContextParameterPrefixLookaheadIsBoundedAndRecovers() {
        let parameters = (0..<2_100).map { "p\($0): Int" }.joined(separator: ",\n")
        let source = "val answer = 42\ncontext(\n\(parameters)\n)\nfun next() {}"
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0007" })
        #expect(parsed.arena.nodes.contains { $0.kind == .funDecl })
    }

    @Test
    func alternatingModifierAndContextPrefixUsesTheSameLookaheadBudget() {
        let prefixes = Array(repeating: "suspend\ncontext(x: Int)", count: 1_100)
            .joined(separator: "\n")
        let source = "val answer = 42\n\(prefixes)\nfun next() {}"
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0007" })
        #expect(parsed.arena.nodes.contains { $0.kind == .funDecl })
    }
}
#endif
