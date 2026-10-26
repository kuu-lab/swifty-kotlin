@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct JavaLinkedListPlatformReturnTests {
    @Test
    func genericAndConcreteJavaReturnsAreAccepted() throws {
        let ctx = makeContextFromSource("""
        import java.util.LinkedList
        fun <T> tail(q: LinkedList<T>): T = q.peekLast()
        fun <T : Any> bounded(q: LinkedList<T>): T = q.peekLast()
        fun concrete(q: LinkedList<String>): String = q.peekLast()
        fun nullable(q: LinkedList<Int?>): Int? = q.peekLast()
        fun safe(q: LinkedList<String>?): String? = q?.peekLast()
        fun <T> identity(value: T): T = value
        fun ordinaryWhen(): Int = when (1) { identity(1) -> 3; else -> 4 }
        fun platformWhen(q: LinkedList<Boolean>): Int = when { q.peekLast() -> 1; else -> 0 }
        fun console(q: LinkedList<String>) { println(q.peekLast()); print(q.peekLast()) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let symbol = try #require(sema.symbols.lookup(
            fqName: ["java", "util", "LinkedList", "peekLast"].map(ctx.interner.intern)
        ))
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        #expect(sema.types.nullability(of: signature.returnType) == .platformType)
        let ast = try #require(ctx.ast)
        var consoleCalls = 0
        for (id, binding) in sema.bindings.callBindings where isUserSourceExpr(id, in: ctx) {
            guard case let .call(callee, _, args, _) = ast.arena.expr(id),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  ["print", "println"].map(ctx.interner.intern).contains(name)
            else { continue }
            consoleCalls += 1
            #expect(sema.symbols.functionSignature(for: binding.chosenCallee)?.parameterTypes == [sema.types.nullableAnyType])
            #expect(args.allSatisfy { sema.bindings.platformNullAssertionTypes[$0.expr] == nil })
        }
        #expect(consoleCalls == 2)
    }

    @Test
    func invalidNullableAndWrongElementReturnsStayRejected() throws {
        let sources = [
        "fun <T> bad(value: T?): T = value",
        "fun bad(value: Int?): Int = value",
        "fun bad(value: String?): String = value",
        "fun bad(q: LinkedList<Int?>): Int = q.peekLast()",
        "fun bad(q: LinkedList<String?>): String = q.peekLast()",
        "fun bad(q: LinkedList<Int>?): Int = q?.peekLast()",
        "fun bad(q: LinkedList<String>): Int = q.peekLast()",
        "class KotlinList<T> { fun peekLast(): T? = null }; fun <T> bad(q: KotlinList<T>): T = q.peekLast()",
        ]
        let source = sources.enumerated().map { index, source in
            source.replacingOccurrences(of: "bad(", with: "bad\(index)(")
        }.joined(separator: "\n")
        let ctx = makeContextFromSource("import java.util.LinkedList\n" + source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.filter { $0.code == "KSWIFTK-TYPE-0001" }.count == sources.count, "\(errors)")
    }

    @Test
    func booleanPlatformReturnIsNullCheckedBeforeUnaryNot() throws {
        let ctx = makeContextFromSource("""
        import java.util.LinkedList
        fun inverted(values: LinkedList<Boolean>): Boolean = !values.peekLast()
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let unary = try #require(ast.arena.exprs.enumerated().compactMap { index, expression -> (ExprID, ExprID)? in
            guard case let .unaryExpr(.not, operand, range) = expression,
                  isUserSourceRange(range, in: ctx)
            else { return nil }
            return (ExprID(rawValue: Int32(index)), operand)
        }.first)
        #expect(sema.types.nullability(of: try #require(sema.bindings.exprType(for: unary.1))) == .platformType)
        #expect(sema.bindings.platformNullAssertionTypes[unary.1] == sema.types.booleanType)
    }

    @Test
    func userJavaPackageDeclarationDoesNotAcquirePlatformContract() throws {
        try withTemporaryFile(contents: """
        package java.util
        class LinkedList<T> { fun peekLast(): T? = null }
        fun <T> bad(q: LinkedList<T>): T = q.peekLast()
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
        }
    }

    @Test
    func metadataKeepsPlatformNullabilityWithoutChangingLinkNames() throws {
        let types = TypeSystem()
        let symbols = SymbolTable()
        let interner = StringInterner()
        let name = interner.intern("platform")
        let function = symbols.define(kind: .function, name: name, fqName: [name],
                                      declSite: nil, visibility: .public)
        let platformInt = types.withNullability(.platformType, for: types.intType)
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: [], returnType: platformInt), for: function)
        let mangler = NameMangler()
        let symbol = try #require(symbols.symbol(function))
        #expect(mangler.mangledSignature(for: symbol, symbols: symbols, types: types) == "F0<Q<I>>")
        let records = MetadataEncoder().buildRecords(symbols: symbols, types: types,
            moduleName: "JavaContract", interner: interner, functionLinkNames: [:])
        let token = try #require(records.first { $0.fqName == "platform" }?.typeSignature)
        #expect(token == "F0<P<I>>")
        let imported = try #require(DataFlowSemaPhase().decodeImportedTypeSignature(
            token: token, symbols: symbols, types: types, interner: interner,
            diagnostics: DiagnosticEngine(), metadataPath: "platform.kklib", ownerFQName: [name]
        ))
        guard case let .functionType(signature) = types.kind(of: imported) else {
            Issue.record("Expected imported callable type")
            return
        }
        #expect(signature.returnType == platformInt)
    }
}
