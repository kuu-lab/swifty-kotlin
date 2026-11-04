#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct NullableExpectedTypeBoundInferenceTests {
    @Test
    func nullableExpectedTypeInfersNonNullBoundedFactoryArgument() throws {
        let source = """
        fun <T : Any> materialize(): T = "OK" as T
        fun nullableResult(): String? = materialize()
        fun nonNullResult(): String = materialize()
        fun <T> nullableMaterialize(): T = "OK" as T
        fun unboundedNullableResult(): String? = nullableMaterialize()
        fun <T : Any> fromInput(value: T): T = value
        fun inputResult(): String? = fromInput("OK")
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            #expect(try callTypeArguments(named: "materialize", path: path, in: ctx) == [
                [sema.types.stringType], [sema.types.stringType],
            ])
            #expect(try callTypeArguments(named: "nullableMaterialize", path: path, in: ctx) == [
                [sema.types.makeNullable(sema.types.stringType)],
            ])
            #expect(try callTypeArguments(named: "fromInput", path: path, in: ctx) == [
                [sema.types.stringType],
            ])
        }
    }

    @Test
    func nullableExpectedTypeChecksEveryNonNullUpperBound() throws {
        let source = """
        interface Marker
        open class Base
        class Concrete : Base(), Marker

        fun <T> materializeWithBounds(): T where T : Base, T : Marker = "OK" as T
        fun nullableResult(): Concrete? = materializeWithBounds()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let concreteSymbol = try #require(ctx.sema?.symbols.lookup(fqName: [ctx.interner.intern("Concrete")]))
            let concreteType = sema.types.make(.classType(ClassType(
                classSymbol: concreteSymbol, nullability: .nonNull
            )))
            #expect(try callTypeArguments(named: "materializeWithBounds", path: path, in: ctx) == [[concreteType]])
        }
    }

    @Test
    func nullableExplicitTypeArgumentStillViolatesNonNullBound() throws {
        let source = """
        fun <T : Any> materialize(): T = "OK" as T
        fun invalid(): String? = materialize<String?>()
        """
        let ctx = makeContextWithoutStdlib(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-BOUND"
        }, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func incompatibleInputAndExpectedTypeAreRejected() throws {
        let source = """
        fun <T : Any> identity(value: T): T = value
        fun invalid(): String? = identity(1)
        """
        let ctx = makeContextWithoutStdlib(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0469"
        }, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func incompatibleNonGenericResultTypeIsStillRejected() throws {
        let ctx = makeContextWithoutStdlib("fun invalid(): Int? = \"OK\"")
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0469"
        }, "\(ctx.diagnostics.diagnostics)")
    }

    /// KUU-3976: a `C<T?>` extension receiver against `C<X?>` leaves `T`
    /// determined only up to `{X, X?}`. A `T : Any` bound makes `X` the unique
    /// solution, so the lambda's expected `() -> T` must become `() -> X`
    /// rather than `() -> X?`; `T : Any?` keeps the whole `X?` argument.
    @Test
    func nullableReceiverArgumentOwnsItsNullableMarker() throws {
        let source = """
        class Box<T>(var v: T)
        class Holder(val x: Int)

        fun <T : Any> Box<T?>.initAndGet(init: () -> T): T = init()
        fun <T : Any?> Box<T?>.initAndGetNullable(init: () -> T): T = init()
        fun <T : Any> Box<T?>.each(block: (T) -> Unit): T? = v

        fun useNonNull(): Int = Box<Holder?>(null).initAndGet { Holder(1) }.x
        fun useNullable(): Holder? = Box<Holder?>(null).initAndGetNullable { null }
        fun useInput(): Int? = Box<Int?>(2).each { val copy: Int = it }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let holderSymbol = try #require(ctx.sema?.symbols.lookup(fqName: [ctx.interner.intern("Holder")]))
            let holderType = sema.types.make(.classType(ClassType(
                classSymbol: holderSymbol, nullability: .nonNull
            )))
            let nullableHolderType = sema.types.make(.classType(ClassType(
                classSymbol: holderSymbol, nullability: .nullable
            )))
            #expect(try memberCallTypeArguments(named: "initAndGet", path: path, in: ctx) == [
                [holderType],
            ])
            #expect(try memberCallTypeArguments(named: "initAndGetNullable", path: path, in: ctx) == [
                [nullableHolderType],
            ])
            #expect(try memberCallTypeArguments(named: "each", path: path, in: ctx) == [
                [sema.types.intType],
            ])
        }
    }

    private func memberCallTypeArguments(
        named name: String,
        path: String,
        in ctx: CompilationContext
    ) throws -> [[TypeID]] {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(
            named: name, in: ast, path: path, ctx: ctx, interner: ctx.interner
        )
        return try calls.map { call in
            try #require(sema.bindings.callBinding(for: call)).substitutedTypeArguments
        }
    }

    private func callTypeArguments(
        named name: String,
        path: String,
        in ctx: CompilationContext
    ) throws -> [[TypeID]] {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .call(callee, _, _, _) = expr,
                  case let .nameRef(calleeName, _) = ast.arena.expr(callee)
            else {
                return false
            }
            return ctx.interner.resolve(calleeName) == name
        }
        return try calls.map { call in
            try #require(sema.bindings.callBinding(for: call)).substitutedTypeArguments
        }
    }

    private func makeContextWithoutStdlib(_ source: String) -> CompilationContext {
        let path = "/virtual/kuu-2453-\(UUID().uuidString).kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
