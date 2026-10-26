#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct LocalClassTypeParameterTests {
    private func context(_ source: String) throws -> CompilationContext {
        var result: CompilationContext?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            result = ctx
        }
        return try #require(result)
    }

    @Test
    func registersLocalClassTypeParametersForHeadersAndConstructors() throws {
        let ctx = try context("""
        open class Base
        class Child : Base()
        interface Source<out T>

        fun <Outer> make(outer: Outer): Source<Base> {
            class Local<out T : Base>(val value: T, val outer: Outer) : Source<T> {
                fun identity(other: T): T = other
                fun capture(): Outer = outer
            }
            val narrow: Local<Child> = Local(Child(), outer)
            val child: Child = narrow.identity(Child())
            val captured: Outer = narrow.capture()
            val widened: Source<Base> = narrow
            return widened
        }
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let local = try #require(sema.symbols.allSymbols().first {
            $0.kind == .class && $0.name == ctx.interner.intern("Local")
        })
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: local.id)
        #expect(typeParameters.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: local.id) == [.out])

        let constructor = try #require(sema.symbols.lookupAll(
            fqName: local.fqName + [ctx.interner.intern("<init>")]
        ).first { sema.symbols.symbol($0)?.kind == .constructor })
        let signature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(signature.typeParameterSymbols == typeParameters)
        #expect(signature.classTypeParameterCount == 1)
        #expect(signature.parameterTypes.count == 2)

        let outer = try #require(sema.symbols.allSymbols().first {
            $0.kind == .typeParameter && $0.name == ctx.interner.intern("Outer")
        })
        #expect(sema.types.kind(of: signature.parameterTypes[1]) == .typeParam(TypeParamType(
            symbol: outer.id, nullability: .nonNull
        )))
    }

    @Test
    func preservesLocalNongenericAndTopLevelGenericClasses() throws {
        let ctx = try context("""
        class TopLevel<T>(val value: T)

        fun make(input: String): String {
            class Local(val value: String)
            val local = Local(input)
            val topLevel: TopLevel<String> = TopLevel(local.value)
            return topLevel.value
        }
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        """
        class Base
        class Unrelated
        fun sample() {
            class Local<T : Base>(val value: T)
            val invalid: Local<Unrelated> = Local(Unrelated())
        }
        """,
        """
        open class Base
        class Child : Base()
        fun sample() {
            class Local<out T : Base>(val value: T)
            val broad: Local<Base> = Local(Base())
            val invalid: Local<Child> = broad
        }
        """,
    ])
    func rejectsLocalClassBoundAndVarianceViolations(_ source: String) throws {
        let ctx = try context(source)
        #expect(ctx.diagnostics.hasError, "Expected the invalid local generic use to be rejected.")
    }

    @Test
    func keepsCapturedOuterTypeParametersLexical() throws {
        let ctx = try context("""
        fun <Outer> make(outer: Outer): Outer {
            class Local<T>(val value: T, val captured: Outer) {
                fun capture(): Outer = captured
            }
            return Local("local", outer).capture()
        }

        val leak: Outer? = null
        """)
        let unresolved = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0025" }
        #expect(unresolved.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(unresolved.first?.message == "Unresolved type 'Outer'.")
    }

    @Test
    func infersLocalConstructorReferenceThroughGenericHigherOrderCall() throws {
        let ctx = try context("""
        open class Base<T>(val value: T)

        fun <T1, T2, R> apply(first: T1, second: T2, make: (T1, T2) -> R): R = make(first, second)

        fun <Outer> create(value: Outer): Base<Outer> {
            class Local<T>(item: T, val captured: Outer) : Base<T>(item)
            return apply(value, value, ::Local)
        }
        """)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
