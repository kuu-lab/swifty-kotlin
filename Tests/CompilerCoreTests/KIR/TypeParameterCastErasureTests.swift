#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

private struct TestFailure: Error {
    let message: String

    init(_ message: String) { self.message = message }
}

@Suite
struct TypeParameterCastErasureTests {
    private let source = """
        interface I1
        interface I2
        open class C
        class CI1I2 : C(), I1, I2

        fun <R : C> Any?.checked() where R : I1, R : I2 = this as R
        fun <R : C> Any?.safeCast() where R : I1, R : I2 = this as? R
        fun <R : C> Any?.nullableTarget() where R : I1, R : I2 = this as R?
        fun <S : C> Any?.singleBound() = this as S
        fun <U : C, T : U> Any?.transitiveBound() = this as T
        fun <T> Any?.unbounded() = this as T
        fun <T : Any> Any?.anyBound() = this as T
        """

    private func context() throws -> CompilationContext {
        let ctx = contextWithoutStdlib(source)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError)
        return ctx
    }

    private func contextWithoutStdlib(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    private func body(named name: String, in ctx: CompilationContext) throws -> [KIRInstruction] {
        try findKIRFunctionBody(named: name, in: try #require(ctx.kir), interner: ctx.interner)
    }

    private func castToken(
        named name: String, in ctx: CompilationContext,
        runtime: KIRRuntimeFunction
    ) throws -> Int64 {
        let calls = kirCalls(to: runtime, in: try body(named: name, in: ctx), interner: ctx.interner)
        #expect(calls.count == 1)
        let tokenExpr = try #require(calls.first?.arguments.last)
        guard case let .intLiteral(value) = try #require(ctx.kir).arena.expr(tokenExpr)
        else { throw TestFailure("expected literal runtime type token for \(name)") }
        return value
    }

    private func containsErasedCastFailure(
        in body: [KIRInstruction],
        context: CompilationContext
    ) -> Bool {
        body.contains { instruction in
            if case let .call(_, callee, _, _, canThrow, _, _, _) = instruction {
                return context.interner.resolve(callee) == "kk_op_cast_erased_return" && canThrow
            }
            return false
        }
    }

    private func nominalCToken(ctx: CompilationContext, nullable: Bool) throws -> Int64 {
        let sema = try #require(ctx.sema)
        let cSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("C")]))
        return RuntimeTypeCheckToken.encode(
            base: RuntimeTypeCheckToken.nominalBase,
            nullable: nullable,
            payload: RuntimeTypeCheckToken.stableNominalTypeID(symbol: cSymbol, sema: sema, interner: ctx.interner)
        )
    }

    @Test
    func checkedCastOnMultiBoundParameterChecksFirstUpperBound() throws {
        let ctx = try context()
        let token = try castToken(named: "checked", in: ctx, runtime: .opCast)
        #expect(token == (try nominalCToken(ctx: ctx, nullable: false)))
    }

    @Test
    func safeCastOnMultiBoundParameterChecksFirstUpperBound() throws {
        let ctx = try context()
        let token = try castToken(named: "safeCast", in: ctx, runtime: .opSafeCast)
        #expect(token == (try nominalCToken(ctx: ctx, nullable: false)))
    }

    @Test
    func checkedCastToNullableParameterTargetUsesNullableToken() throws {
        let ctx = try context()
        let token = try castToken(named: "nullableTarget", in: ctx, runtime: .opCast)
        #expect(token == (try nominalCToken(ctx: ctx, nullable: true)))
    }

    @Test
    func singleBoundParameterChecksTheBound() throws {
        let ctx = try context()
        let token = try castToken(named: "singleBound", in: ctx, runtime: .opCast)
        #expect(token == (try nominalCToken(ctx: ctx, nullable: false)))
    }

    @Test
    func transitiveParameterBoundResolvesToRuntimeCheckableBound() throws {
        let ctx = try context()
        let token = try castToken(named: "transitiveBound", in: ctx, runtime: .opCast)
        #expect(token == (try nominalCToken(ctx: ctx, nullable: false)))
    }

    @Test
    func unboundedParameterKeepsErasureCopy() throws {
        let ctx = try context()
        let fnBody = try body(named: "unbounded", in: ctx)
        #expect(kirCalls(to: .opCast, in: fnBody, interner: ctx.interner).isEmpty)
        #expect(kirCalls(to: .opSafeCast, in: fnBody, interner: ctx.interner).isEmpty)
        #expect(fnBody.contains { instruction in
            if case .nullAssert = instruction { return true }
            return false
        } == false)
    }

    @Test
    func anyBoundParameterUsesErasedCastFailure() throws {
        let ctx = try context()
        let fnBody = try body(named: "anyBound", in: ctx)
        #expect(kirCalls(to: .opCast, in: fnBody, interner: ctx.interner).isEmpty)
        #expect(kirCalls(to: .opSafeCast, in: fnBody, interner: ctx.interner).isEmpty)
        #expect(containsErasedCastFailure(in: fnBody, context: ctx))
    }

    @Test
    func definitelyNotNullArgumentUsesErasedCastFailure() throws {
        let source = """
            interface Param<T : Any>
            fun <T> queryParam(param: Param<T & Any>): T = null as T
            fun <T> queryNullable(param: Param<T & Any>): T? = null as T?
            """
        let ctx = contextWithoutStdlib(source)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError)

        let fnBody = try body(named: "queryParam", in: ctx)
        #expect(containsErasedCastFailure(in: fnBody, context: ctx))
    }

    @Test
    func definitelyNotNullArgumentDoesNotRejectNullableCastTarget() throws {
        let source = """
            interface Param<T : Any>
            fun <T> queryNullable(param: Param<T & Any>): T? = null as T?
            """
        let ctx = contextWithoutStdlib(source)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError)

        let fnBody = try body(named: "queryNullable", in: ctx)
        #expect(!fnBody.contains { instruction in
            if case .nullAssert = instruction { return true }
            return false
        })
    }
}
#endif
