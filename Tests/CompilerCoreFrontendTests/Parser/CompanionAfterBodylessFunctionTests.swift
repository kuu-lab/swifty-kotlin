@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct CompanionAfterBodylessFunctionTests {
    @Test(arguments: [
        ("abstract class Host", "abstract fun dropAll()", "companion object"),
        ("abstract class Host", "abstract fun dropAll()", "companion object Named"),
        ("abstract class Host", "abstract fun dropAll()", "companion\nobject"),
        ("abstract class Host", "abstract fun dropAll(): Unit", "companion object"),
        ("interface Host", "fun dropAll()", "companion object"),
        ("interface Host", "fun dropAll(): Unit", "companion object Named"),
    ])
    func bodylessFunctionKeepsFollowingCompanion(owner: String, function: String, header: String) throws {
        let source = """
        \(owner) {
            \(function)
            \(header) { const val ERROR_SEPARATOR = 7 }
        }
        """
        let parsed = parse(source)
        let functionNode = try #require(parsed.arena.nodes.first { $0.kind == .funDecl })
        let objectNode = try #require(parsed.arena.nodes.first { $0.kind == .objectDecl })
        #expect(parsed.diagnostics.diagnostics.isEmpty, "\(parsed.diagnostics.diagnostics)")
        #expect(functionNode.range.end.offset <= objectNode.range.start.offset)

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let host = try #require(sema.symbols.lookup(fqName: [context.interner.intern("Host")]))
            let companion = try #require(sema.symbols.companionObjectSymbol(for: host))
            let companionName = try #require(sema.symbols.symbol(companion)).fqName
            let property = sema.symbols.lookup(fqName: companionName + [context.interner.intern("ERROR_SEPARATOR")])
            #expect(property != nil)
            let method = try #require(sema.symbols.lookup(fqName: ["Host", "dropAll"].map(context.interner.intern)))
            #expect(sema.symbols.functionSignature(for: method)?.returnType == sema.types.unitType)
        }
    }

    @Test(arguments: [
        "fun companion(): Int = 4\nfun call(): Int = companion()",
        "fun companion(): Int = 4\nfun call(): Int {\n return companion()\n}",
        "fun companion(): Int = 4\nfun call(): Int =\n companion()",
        "fun companion(): Int = 4\nfun call(): Int = if (true)\n companion()\nelse 0",
    ])
    func companionIdentifierCallsRemainExpressions(source: String) throws {
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let ast = try #require(context.ast)
            #expect(!ast.arena.decls.contains { declaration in
                if case .objectDecl = declaration { return true }
                return false
            })
        }
    }

    @Test(arguments: [
        "abstract fun dropAll()", "abstract fun dropAll(): Unit",
        "abstract fun <T> dropAll() where T: Any",
    ])
    func sameLineCompanionTerminatesFunctionHeader(function: String) throws {
        let source = "abstract class Host { \(function) companion object { const val ERROR_SEPARATOR = 7 } }"
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            #expect(sema.symbols.lookup(fqName: ["Host", "Companion", "ERROR_SEPARATOR"].map(context.interner.intern)) != nil)
        }
    }

    @Test(arguments: ["companion", "@Mark companion", "Outer.companion", "@Mark Outer.companion"])
    func companionTypeNameRemainsInFunctionSignature(type: String) throws {
        let parsed = parse("""
        class companion
        class Outer { class companion }
        annotation class Mark
        abstract class Host {
            abstract fun value(): \(type)
            object Token
        }
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty, "\(parsed.diagnostics.diagnostics)")
        let index = try #require(parsed.arena.nodes.firstIndex { $0.kind == .funDecl })
        let tokens = parsed.arena.children(of: NodeID(rawValue: Int32(index))).compactMap { child -> TokenKind? in
            guard case let .token(id) = child else { return nil }
            return parsed.arena.token(id)?.kind
        }
        #expect(tokens.contains(.keyword(.companion)))
        let objectIndex = try #require(parsed.arena.nodes.firstIndex { $0.kind == .objectDecl })
        let objectTokens = parsed.arena.children(of: NodeID(rawValue: Int32(objectIndex))).compactMap { child -> TokenKind? in
            guard case let .token(id) = child else { return nil }
            return parsed.arena.token(id)?.kind
        }
        #expect(!objectTokens.contains(.keyword(.companion)))
    }

    @Test
    func infixCompanionWithObjectArgumentRemainsExpression() throws {
        let source = """
        infix fun Int.companion(other: Any): Int = this
        fun call(): Int = 1 companion object {}
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    @Test
    func expectActualFactoryPreservesCompanionConstant() throws {
        try withTemporaryFiles(contents: [
            """
            expect open class Lockable()
            abstract class Factory : Lockable() {
                abstract fun dropAll()
                companion object { const val ERROR_SEPARATOR = 7 }
            }
            """,
            "actual open class Lockable actual constructor()",
        ]) { paths in
            let context = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            #expect(sema.symbols.lookup(fqName: ["Factory", "Companion", "ERROR_SEPARATOR"].map(context.interner.intern)) != nil)
        }
    }
}
