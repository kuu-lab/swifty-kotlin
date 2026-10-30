#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct FlowBuilderInferenceTests {
    @Test(arguments: [false, true], [false, true])
    func explicitTransformBindsEmitAfterBuilderInference(fromSource: Bool, throwsAfterEmit: Bool) throws {
        let source = """
        import kotlinx.coroutines.flow.*
        fun demo(source: Flow<Int>): Flow<Int> = source.transform<Int, Int> {
            emit(it)
            \(throwsAfterEmit ? "throw RuntimeException(\"after-emit\")" : "Unit")
        }
        """
        if !fromSource { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                stdlibLibraryPath: fromSource ? nil : CompilerOptions.defaultStdlibLibraryPath,
                allowDefaultStdlibLibrary: !fromSource
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let emits = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "emit"
            }
            #expect(emits.count == 1)
            let emit = try #require(emits.first)
            let binding = try #require(sema.bindings.callBinding(for: emit))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(symbol.fqName.map(ctx.interner.resolve) == [
                "kotlinx", "coroutines", "flow", "FlowCollector", "emit",
            ])
        }
    }

    @Test
    func transformInfersOutputTypeFromCollectorEmit() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.flow.*

        fun demo() {
            val result = flowOf(1, 2).transform { emit(it) }
            val checked: Flow<Int> = result
        }
        """)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
        #expect(!ctx.diagnostics.hasError, "Diagnostics: \(diagnostics)")
    }

    @Test(arguments: [
        "flow { emit(1) }.collect { value -> accept(value) }",
        "val result = flow { val value = identity(1); emit(value); emit(2) }; result.collect { accept(it) }",
        "flow { if (true) emit(1) else emit(2) }.collect { accept(it) }",
        "flow { flowOf(1, 2).collect { emit(it) } }.collect { accept(it) }",
        "flow { emitAll(flowOf(1, 2)) }.collect { accept(it) }",
        "flow { val nested = flow { emit(\"nested\") }; emit(1) }.collect { accept(it) }",
        "val result: Flow<Int> = flow { emit(1) }; result.collect { accept(it) }",
        "flow<Int> { emit(1) }.collect { accept(it) }",
        "flow { with(Sink()) { emit(\"sink\") }; emit(1) }.collect { accept(it) }",
        "class S { fun emit(v: Int) {}; fun f() = flow { emit(1) } }; S().f().collect { accept(it) }",
    ])
    func infersIntForCollectorForwarding(_ statement: String) throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.flow.*
        import kotlinx.coroutines.runBlocking
        fun accept(value: Int) {}
        class Sink { fun emit(value: String) {} }
        fun <T> identity(value: T): T = value
        fun main() = runBlocking { \(statement) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func bindsInferredFlowElementType() throws {
        let source = """
        import kotlinx.coroutines.flow.*
        fun result() = flow { emit(1) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return name == KnownCompilerNames(interner: ctx.interner).flow
            }
            let call = try #require(calls.first)
            #expect(sema.bindings.flowElementType(forExpr: call) == sema.types.intType)
            let type = try #require(sema.bindings.exprType(for: call))
            guard case let .classType(classType) = sema.types.kind(of: type) else {
                Issue.record("Expected Flow<Int>, got \(sema.types.renderType(type))")
                return
            }
            #expect(classType.args == [.invariant(sema.types.intType)])
        }
    }

    @Test(arguments: [
        "flow { emit(\"value\") }.collect { acceptString(it) }",
        "flow { emit(null); emit(\"value\") }.collect { acceptNullableString(it) }",
        "flow { emit(1); emit(\"value\") }.collect { acceptAny(it) }",
    ])
    func infersNonIntAndNullableElements(_ statement: String) throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.flow.*
        import kotlinx.coroutines.runBlocking
        fun acceptString(value: String) {}
        fun acceptNullableString(value: String?) {}
        fun acceptAny(value: Any) {}
        fun main() = runBlocking { \(statement) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "flow<Int> { emit(\"wrong\") }",
        "val result: Flow<Int> = flow { emit(\"wrong\") }",
        "flow<Int> { emitAll(flowOf(\"wrong\")) }",
        "flow { emit(1); emit(null) }.collect { accept(it) }",
        "flow { emit(1); emit(\"wrong\") }.collect { accept(it) }",
    ])
    func rejectsIncompatibleElements(_ statement: String) throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.flow.*
        import kotlinx.coroutines.runBlocking
        fun accept(value: Int) {}
        fun main() = runBlocking { \(statement); Unit }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected incompatible Flow element diagnostic")
    }

    @Test
    func explicitElementTypeContextualizesIntegerLiteral() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.flow.*
        import kotlinx.coroutines.runBlocking
        fun accept(value: Long) {}
        fun main() = runBlocking {
            flow<Long> { emit(1) }.collect { accept(it) }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func classEmitMemberDoesNotShadowFlowCollectorEmit() throws {
        let source = """
        import kotlinx.coroutines.flow.*
        class S {
            val log = mutableListOf<Int>()
            fun emit(v: Int) { log.add(v) }
            fun f() = flow { emit(1) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return name == KnownCompilerNames(interner: ctx.interner).flow
            }
            let call = try #require(calls.first)
            #expect(sema.bindings.flowElementType(forExpr: call) == sema.types.intType)
        }
    }

    @Test
    func nestedReceiverEmitDoesNotChangeFlowElementType() throws {
        let source = """
        import kotlinx.coroutines.flow.*
        fun accept(value: Int) {}
        class Sink { fun emit(value: String) {} }
        suspend fun check() {
            val result = flow { with(Sink()) { emit("sink") }; emit(14) }
            val typed: Flow<Int> = result
            result.collect { accept(it) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let flowCalls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return name == KnownCompilerNames(interner: ctx.interner).flow
            }
            let flowCall = try #require(flowCalls.first)
            #expect(sema.bindings.flowElementType(forExpr: flowCall) == sema.types.intType)

            let emitCalls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "emit"
            }
            let owners = emitCalls.compactMap { call -> String? in
                guard let binding = sema.bindings.callBinding(for: call),
                      let symbol = sema.symbols.symbol(binding.chosenCallee)
                else { return nil }
                return symbol.fqName.dropLast().map(ctx.interner.resolve).joined(separator: ".")
            }
            #expect(owners == ["Sink"])
        }
    }

    @Test
    func classMemberEmitDoesNotShadowFlowCollectorEmit() throws {
        // The `this` local in scope at `flow { }` stays the enclosing class
        // receiver inside the builder lambda (`syncingImplicitReceiver`
        // restores it over the synthetic Any placeholder). Its `emit` member
        // must not shadow the FlowCollector emission, while `this@S.emit`
        // still reaches the class member.
        let source = """
        import kotlinx.coroutines.flow.*
        class S {
            fun emit(v: Int) {}
            fun f() = flow { emit(1); emit(2) }
            fun g() = flow { this@S.emit(100); emit(3) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let flowCalls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return name == KnownCompilerNames(interner: ctx.interner).flow
            }
            #expect(flowCalls.count == 2)
            for flowCall in flowCalls {
                #expect(sema.bindings.flowElementType(forExpr: flowCall) == sema.types.intType)
            }
            // Bare `emit` calls inside the builders are FlowCollector
            // emissions and carry no resolved callee; only the explicit
            // `this@S.emit` member call binds the class member.
            let bareEmitCalls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "emit"
            }
            #expect(bareEmitCalls.count == 3)
            for emitCall in bareEmitCalls {
                #expect(sema.bindings.callBinding(for: emitCall) == nil)
            }
        }
    }

    @Test
    func topLevelEmitDoesNotShadowFlowCollectorEmit() throws {
        let source = """
        import kotlinx.coroutines.flow.*
        fun emit(v: Int) {}
        fun f() = flow { emit(1) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return name == KnownCompilerNames(interner: ctx.interner).flow
            }
            let call = try #require(calls.first)
            #expect(sema.bindings.flowElementType(forExpr: call) == sema.types.intType)
        }
    }
}
#endif
