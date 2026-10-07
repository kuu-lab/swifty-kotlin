#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct FlowBuilderInferenceTests {
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
                return ctx.interner.resolve(name) == "flow"
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
                return ctx.interner.resolve(name) == "flow"
            }
            let call = try #require(calls.first)
            #expect(sema.bindings.flowElementType(forExpr: call) == sema.types.intType)
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
                return ctx.interner.resolve(name) == "flow"
            }
            let call = try #require(calls.first)
            #expect(sema.bindings.flowElementType(forExpr: call) == sema.types.intType)
        }
    }
}
#endif
