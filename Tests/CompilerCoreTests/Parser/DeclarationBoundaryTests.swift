#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

/// Regression tests for parser declaration boundaries: where one top-level or
/// block-level declaration ends and the next begins, and how far a
/// declaration's CST range reaches.
@Suite
struct DeclarationBoundaryTests {
    @Test(arguments: [
        "fun f() = 8",
        "val k = 3; fun f() = k",
        "companion object { fun f() = 8 }",
    ])
    func sameLineMemberAfterInitBlockStartsNewDeclaration(member: String) {
        let parsed = parse("class D { init { } \(member) }")

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 1)
        #expect(nodeCount(in: parsed.arena, kind: .propertyDecl) == (member.contains("val") ? 1 : 0))
        #expect(nodeCount(in: parsed.arena, kind: .objectDecl) == (member.contains("companion") ? 1 : 0))
    }

    @Test
    func anonymousFunctionAtLambdaBlockStartIsAnExpression() {
        let parsed = parse("""
        fun host() {
            val maker: () -> (() -> Int) = { fun () = 1 }
            val named: () -> Int = {
                fun local() = 2
                local()
            }
        }
        """)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 2)
    }

    @Test(arguments: ["; ", "\n", ";\n", ";\n;"])
    func topLevelFunctionSeparatorsDoNotMakeFileAScript(separator: String) {
        let source = """
        fun interface Action { fun run(n: Int): Int }
        fun make(): (Int) -> Int = { it }\(separator)fun test(): Int = 1;
        """
        let parsed = parse(source)
        let root = parsed.arena.node(parsed.root)
        let kinds = parsed.arena.children(of: parsed.root).compactMap { child -> SyntaxKind? in
            guard case let .node(nodeID) = child else { return nil }
            return parsed.arena.node(nodeID).kind
        }

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(root.kind == .kotlinFile)
        #expect(kinds == [.interfaceDecl, .funDecl, .funDecl])
        #expect(root.range.end.offset == source.utf8.count)
        #expect(parsed.arena.tokens.count { $0.kind == .symbol(.semicolon) }
            == source.filter { $0 == ";" }.count)
    }

    @Test(arguments: ["fun before() {}", "fun before(): () -> Int = { 1 }", "class Before {}"])
    func semicolonAfterBracedDeclarationDoesNotMakeFileAScript(declaration: String) {
        let parsed = parse("\(declaration); fun after() = 2;")

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(rootChildCount(in: parsed.arena, root: parsed.root, kind: .statement) == 0)
    }

    @Test(arguments: ["; ", ";\n; ", ";\n"])
    func realStatementAfterFunctionSeparatorStillMakesScript(separator: String) {
        let parsed = parse("fun make(): () -> Int = { 1 }\(separator)make()")

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .script)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 1)
        #expect(rootChildCount(in: parsed.arena, root: parsed.root, kind: .callExpr) == 1)
    }

    @Test(arguments: [
        "class Derived(val value: Int)\n    : Value by Simple() { val other = 7 }",
        "class Derived\n    : Value by Simple() { val other = 7 }",
        "object Derived\n    : Value by Simple() { val other = 7 }",
        "interface Derived\n    : Value { val other: Int }",
    ])
    func supertypeColonContinuesNamedDeclaration(source: String) {
        let parsed = parse("""
        interface Value { val number: Int }
        class Simple : Value { override val number = 42 }
        \(source)
        fun after() = 3
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 1)
        #expect(nodeCount(in: parsed.arena, kind: .propertyDecl) == 3)
    }

    @Test(arguments: [
        "Base, Entry by delegate",
        "Base,\n    Entry by delegate",
        "Base, Entry\n    by delegate",
        "Base, Entry\n    by\n    delegate",
        "Base, Entry<String>\n    by delegate",
    ])
    func classSupertypeDelegationContinuesBeforeBy(supertypes: String) throws {
        let declaration = """
        class Target(private val delegate: Entry) : \(supertypes) {
            override fun base() {}
            override fun entry() {}
        }
        """
        let parsed = parse("\(declaration)\nfun after() = 3")
        let firstChild = try #require(parsed.arena.children(of: parsed.root).first)
        guard case let .node(classID) = firstChild else {
            Issue.record("Expected a class declaration")
            return
        }
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(parsed.arena.node(classID).kind == .classDecl)
        #expect(parsed.arena.node(classID).range.end.offset == declaration.utf8.count)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 3)
        #expect(rootChildCount(in: parsed.arena, root: parsed.root, kind: .funDecl) == 1)
    }

    @Test
    func namedObjectSupertypeDelegationContinuesBeforeBy() {
        let parsed = parse("""
        object Target : Entry
            by delegate {
            fun member() = 1
        }
        fun after() = 3
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(rootChildCount(in: parsed.arena, root: parsed.root, kind: .objectDecl) == 1)
        #expect(rootChildCount(in: parsed.arena, root: parsed.root, kind: .funDecl) == 1)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 2)
    }

    @Test(arguments: ["fun target(): Entry = delegate", "val target: Entry = delegate"])
    func newlineByExpressionRemainsOutsideCompletedDeclaration(declaration: String) throws {
        let parsed = parse("\(declaration)\nby(delegate)")
        let firstChild = try #require(parsed.arena.children(of: parsed.root).first)
        guard case let .node(firstID) = firstChild else {
            Issue.record("Expected a declaration")
            return
        }
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(firstID).range.end.offset == declaration.utf8.count)
        #expect(parsed.arena.children(of: parsed.root).count == 2)
    }

    @Test(arguments: ["Simple()", "(Simple())", "create()"])
    func classDelegationContinuesAfterNewline(expression: String) {
        let parsed = parse("""
        interface Value { val number: Int }
        class Simple : Value { override val number = 42 }
        fun create(): Value = Simple()
        class Delegated : Value by
            \(expression) {
            val other = 7
        }
        fun after() = 3
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .classDecl) == 2)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 2)
    }

    @Test(arguments: ["1", "fallback()"])
    func expressionBodyElseBranchCanStartOnTheNextLine(elseExpression: String) {
        let parsed = parse("""
        fun fallback(): Int = 1
        fun target(x: Boolean): Int = if (x) 0 else
            \(elseExpression)
        fun after(): Int = 2
        """)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 3)
        #expect(rootChildCount(in: parsed.arena, root: parsed.root, kind: .statement) == 0)
    }

    @Test(arguments: [
        "var count = 0\ncount = count + 1\ncount",
        "val count = 1\ncount",
        "fun local() = 1\nlocal()",
        "class Local\n1",
        "@Suppress(\"UNUSED_VARIABLE\")\nval count = 1\ncount",
        "run {\nval count = 1\ncount\n}",
        "listOf(1)[run {\nval index = 0\nindex\n}]",
    ])
    func multilineDefaultLambdaDoesNotEndParameterGroup(body: String) {
        let source = """
        fun before() = 0
        fun target(value: Int = run {
            \(body)
        }, other: Int = 2): Int = value + other
        fun after() = 3
        """
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 3)
        #expect(nodeCount(in: parsed.arena, kind: .propertyDecl) == 0)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
    }

    @Test
    func localPropertyCallInitializerStopsBeforeNextLabeledThisAssignment() {
        let source = """
        class Outer {
            var counter = 0
            fun greet(extra: Int) = extra
            fun show() {
                val greeting = this@Outer.greet(5)
                this@Outer.counter = 10
                this@Outer.counter += 1
            }
        }
        """
        let parsed = parse(source)
        let greetingStart = source.range(of: "val greeting =")!.lowerBound
        let greetingEnd = source.range(of: "this@Outer.greet(5)")!.upperBound
        let assignmentStart = source.range(of: "this@Outer.counter = 10")!.lowerBound

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.contains { node in
            node.kind == .propertyDecl
                && node.range.start.offset == source[..<greetingStart].utf8.count
                && node.range.end.offset == source[..<greetingEnd].utf8.count
        })
        #expect(parsed.arena.nodes.contains { node in
            node.kind == .statement && node.range.start.offset == source[..<assignmentStart].utf8.count
        })
    }

    @Test(arguments: [
        "class Target(value: Int = run {\nval count = 1\ncount\n})",
        "class Target {\nconstructor(value: Int = run {\nvar count = 1\ncount\n})\n}",
        "fun outer() {\nclass Target {\nfun next(value: Int = run {\nval count = 1\ncount\n}): Int = value\n}\n}",
        "fun target(action: () -> Int = {\nval count = 1\ncount\n}): Int = action()",
    ])
    func multilineLambdaInDifferentParameterListsParses(source: String) {
        #expect(parse(source).diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: ["", " = run {\nval count = 1\ncount\n}"])
    func unterminatedParameterGroupRecoversAfterBalancedLambda(defaultValue: String) {
        let parsed = parse("fun broken(value: Int\(defaultValue)\nfun after() = 3")

        #expect(parsed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0004"])
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 2)
    }

    @Test
    func multilineEnumPrimaryConstructorParametersDoNotEndDeclaration() {
        let parsed = parse("""
        enum class Spacing(
            val horizontal: Int,
            val vertical: Int
        ) {
            SINGLE(1, 1),
            DOUBLE(2, 2)
        }
        fun after() = 3
        """)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .enumEntry) == 2)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 1)
    }

    @Test
    func unterminatedMultilineEnumPrimaryConstructorRecoversAtNextDeclaration() {
        let parsed = parse("""
        enum class Broken(
            val value: Int
        fun after() = 3
        """)

        #expect(parsed.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0004"])
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 1)
    }

    @Test
    func multilineDefaultLambdaIssueReproductionParses() {
        let parsed = parse("""
        fun topRun(value: Int = run {
            var count = 0
            count = count + 1
            count
        }): Int = value
        fun main() {
            var count = 0
            class Counter {
                fun next(value: Int = run {
                    count = count + 1
                    count
                }): Int = value
            }
            println(topRun())
            println(Counter().next())
        }
        """)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 3)
        #expect(nodeCount(in: parsed.arena, kind: .classDecl) == 1)
    }

    private func nodeCount(in arena: SyntaxArena, kind: SyntaxKind) -> Int {
        arena.nodes.count { $0.kind == kind }
    }

    private func rootChildCount(in arena: SyntaxArena, root: NodeID, kind: SyntaxKind) -> Int {
        arena.children(of: root).count { child in
            guard case let .node(nodeID) = child else { return false }
            return arena.node(nodeID).kind == kind
        }
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
        ("object Cast : Holder({ value -> calls += 1; value as? String })", 1),
        ("class Cast : Holder({ value -> calls += 1; value as? String })", 1),
        ("object Cast : Holder({ value -> calls += 1; value as? String }) { fun member() {} }", 2),
        ("class Cast : Holder(f = { value -> calls += 1; value as? String }) { fun member() {} }", 2),
        ("object Cast : Holder(listOf({ value -> calls += 1; value as? String })[0])", 1),
        ("class Cast : Holder({ value -> val copy = value; calls += 1; copy as? String }, 42)", 1),
    ])
    func superConstructorLambdaSemicolonsStayInsideDeclaration(declaration: String, expectedFunCount: Int) throws {
        let parsed = parse("\(declaration)\nfun after() {}")
        let declarationNode = try #require(parsed.arena.nodes.first {
            $0.kind == .classDecl || $0.kind == .objectDecl
        })

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(declarationNode.range.end.offset == declaration.utf8.count)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == expectedFunCount)
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
    func functionDeclarationRejectsByDelegation() {
        let parsed = parse("""
        fun f() by lazy { 1 }
        fun main() {}
        """)

        #expect(parsed.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0006"
                && $0.message == "Unexpected 'by' after function signature."
        })
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 2)
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

    @Test(arguments: [
        ("val result", 1),
        ("fun result()", 2),
    ])
    func nestedSemicolonsDoNotEndTopLevelExpressionBody(declaration: String, expectedFunCount: Int) throws {
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
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == expectedFunCount)
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
        let source = KotlinSourceFixtures.valueKeywordExpressionBody
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
        let source = KotlinSourceFixtures.valueKeywordExpressionBodyAfterAssignmentNewline
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

    @Test(arguments: [
        "fun add(a: Long, b: Long): Long\n{\n    return a + b\n}",
        "class Calculator\n{\n    fun add(a: Long, b: Long): Long\n    {\n        return a + b\n    }\n}",
    ])
    func functionBlockOnNextLineBelongsToFunction(source: String) throws {
        let parsed = parse(source)
        let function = try #require(parsed.arena.nodes.enumerated().first { $0.element.kind == .funDecl })
        let functionID = NodeID(rawValue: Int32(function.offset))
        let hasDirectBlock = parsed.arena.children(of: functionID).contains { child in
            guard case let .node(nodeID) = child else { return false }
            return parsed.arena.node(nodeID).kind == .block
        }

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(hasDirectBlock)
    }

    @Test(arguments: [
        """
        fun <T : Any, B : UInt> sample(value: T): Int
            where B : Comparable<UInt> {
            return 1
        }
        fun after(): String = "OK"
        """,
        """
        fun <T : Any, B : UInt> sample(value: T): Int
            where
                B : Comparable<UInt>,
                T : Any
            = 1
        fun after(): String = "OK"
        """,
    ])
    func functionWhereClauseAfterReturnTypeNewlineStaysInHeader(source: String) throws {
        let parsed = parse(source)
        let functions = parsed.arena.nodes.enumerated().filter { $0.element.kind == .funDecl }
        let sample = try #require(functions.first)
        let sampleID = NodeID(rawValue: Int32(sample.offset))
        let sampleTokens = parsed.arena.children(of: sampleID).compactMap { child -> TokenKind? in
            guard case let .token(tokenID) = child else { return nil }
            return parsed.arena.token(tokenID)?.kind
        }

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(functions.count == 2)
        #expect(sampleTokens.contains(.softKeyword(.where)))
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
    func testParameterNamedContextOnNewlineDoesNotTerminateParameterList() {
        let source = """
        fun run(
            context: Any = 1,
            block: () -> Unit
        ): Unit {}
        """
        let parsed = parse(source)
        #expect(!parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0004" })
        #expect(nodeCount(source, kind: .funDecl) == 1)
    }

    @Test(arguments: [
        "val t2 = when (val y = peek()) { else -> y }",
        "val t2: Map<String, Int> = when (val y = peek()) { else -> y }",
    ])
    func nestedWhenSubjectVariableDoesNotTriggerUnterminatedGroupWarning(subject: String) {
        let source = """
        fun main() {
            when (
                \(subject)
            ) {
                else -> t2
            }
        }
        """
        let parsed = parse(source)

        #expect(!parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0004" },
                "\(parsed.diagnostics.diagnostics)")
    }

    @Test
    func contextParameterAndLocalMemberCallsAreNotParsedAsDeclarationPrefixes() {
        let parsed = parse("""
        class Box { fun put() {} }
        interface Handler { fun write(context: Box) }
        class Writer : Handler {
            override fun write(context: Box) {
                context.put()
            }
        }
        val context = Box()
        context.put()
        context(Box) fun withContextReceiver() {}
        """)

        #expect(parsed.diagnostics.diagnostics.isEmpty, "\(parsed.diagnostics.diagnostics)")
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 4)
        #expect(nodeCount(in: parsed.arena, kind: .classDecl) == 2)
        #expect(nodeCount(in: parsed.arena, kind: .interfaceDecl) == 1)
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
    func annotationArgumentLookaheadIsBoundedAndRecovers() {
        let arguments = Array(repeating: "1", count: 2_100).joined(separator: ",")
        let parsed = parse("fun broken() =\n @Tag(\(arguments)) 7\nfun after() = 9")

        #expect(parsed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0007" })
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 2)
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

    @Test(arguments: [4_095, 4_096, 12_300])
    func modifierPrefixBudgetBoundaryRecoversWithoutRepeatedDiagnostics(count: Int) {
        let modifiers = Array(repeating: "suspend", count: count).joined(separator: "\n")
        let source = "val answer = 42\n\(modifiers)\nfun next() {}"
        let parsed = parse(source)
        let exceedsBudget = count >= 4_096

        // Recovery also reports the skipped modifier tokens once.
        let expectedCodes = exceedsBudget ? ["KSWIFTK-PARSE-0007", "KSWIFTK-PARSE-0006"] : []
        let expectedRootKind: SyntaxKind = exceedsBudget ? .script : .kotlinFile
        #expect(parsed.diagnostics.diagnostics.map(\.code) == expectedCodes)
        #expect(parsed.arena.node(parsed.root).kind == expectedRootKind)
        #expect(parsed.arena.node(parsed.root).range.end.offset == source.utf8.count)
        #expect(nodeCount(in: parsed.arena, kind: .propertyDecl) == 1)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 1)
    }

    @Test(arguments: [
        "suspend fun next() {}",
        "private @Deprecated(\"old\") inline fun next() {}",
        "value @JvmInline class Next",
        "context(x: Int) suspend fun next() {}",
    ])
    func ordinaryDeclarationPrefixesRemainDeclarations(source: String) {
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(parsed.arena.children(of: parsed.root).count == 1)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) + nodeCount(in: parsed.arena, kind: .classDecl) == 1)
    }

    @Test(arguments: [
        ("suspend { 42 }", false),
        ("value.hashCode()", false),
        ("data = 1", false),
        ("context.put()", true),
        ("context = Box()", true),
        ("context(Box) { 42 }", true),
    ])
    func ordinaryPrefixExpressionsPreserveFollowingDeclaration(expression: String, isCall: Bool) throws {
        let parsed = parse("\(expression)\nfun next() {}")
        let firstChild = try #require(parsed.arena.children(of: parsed.root).first)
        guard case let .node(firstID) = firstChild else {
            Issue.record("Expected an expression or statement node")
            return
        }

        let expectedKind: SyntaxKind = isCall ? .callExpr : .statement
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(firstID).kind == expectedKind)
        #expect(parsed.arena.node(firstID).range.end.offset == expression.utf8.count)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 1)
    }

    @Test
    func bundledStdlibDeclarationPrefixesRemainWithinBudget() {
        let sources = BundledStdlib.bundledStdlibSources()
        #expect(!sources.isEmpty)
        for source in sources {
            let parsed = parse(String(decoding: source.contents, as: UTF8.self))
            #expect(parsed.diagnostics.diagnostics.isEmpty, "\(source.path): \(parsed.diagnostics.diagnostics)")
            #expect(parsed.arena.node(parsed.root).kind == .kotlinFile, "\(source.path)")
        }
    }

    // KUU-3025: the type-argument lookahead once required the token after `>`
    // to be a label name, so a bodiless generic class followed by a
    // hard-keyword declaration (`fun`, `val`, `class`, …) lost its
    // type-parameter list. The synthesized constructor then carried no type
    // parameters and calls such as `Box()`/`Box<Int>()` failed overload
    // resolution with KSWIFTK-SEMA-0002.

    @Test(arguments: [
        "fun after() {}",
        "val after = 1",
        "var after = 1",
        "class After",
        "interface After",
        "object After {}",
        "enum class After { A }",
        "typealias After = Int",
        "annotation class After",
        "private class After",
        "@Deprecated(\"x\") class After",
    ])
    func bodilessGenericClassKeepsTypeParametersBeforeNextDeclaration(next: String) {
        let parsed = parse("class Box<T>\n\(next)")

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .typeArgs) == 1)
    }

    @Test
    func bodilessGenericClassKeepsTypeParametersBeforeSemicolon() {
        let parsed = parse("class Box<T>;\nfun after() {}")

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .typeArgs) == 1)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 1)
    }

    @Test
    func bodilessGenericClassKeepsTypeParametersAcrossNewline() {
        let parsed = parse("class Box\n    <T>\nfun after() {}")

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .typeArgs) == 1)
    }

    @Test
    func nestedBodilessGenericClassKeepsTypeParametersBeforeMemberFunction() {
        let parsed = parse("""
        object Host {
            class Delegate<D, E, R>
            fun <D, E, R> delegate() = Delegate
        }
        """)

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .typeArgs) == 2)
        #expect(nodeCount(in: parsed.arena, kind: .funDecl) == 1)
    }

    @Test(arguments: [
        ("interface Box<T>", "fun after() {}"),
        ("typealias Box<T> = T", "fun after() {}"),
        ("fun <T> make(): T? = null", "class After"),
        ("class Box<T>", "enum class After { A }"),
    ])
    func genericDeclarationKeepsTypeParametersBeforeHardKeyword(
        declaration: String, next: String
    ) {
        let parsed = parse("\(declaration)\n\(next)")

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(nodeCount(in: parsed.arena, kind: .typeArgs) == 1)
    }
}
#endif
