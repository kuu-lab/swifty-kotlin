#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExplicitGenericSubtypeArgumentTests {
    @Test(arguments: [false, true])
    func subclassAndObjectArgumentsPreserveGenericWrapper(useCache: Bool) throws {
        let source = """
        abstract class ArgType<T : Any>(val hasParameter: kotlin.Boolean)
        open class Impl : ArgType<kotlin.Boolean>(false)
        object Bool2 : ArgType<Boolean>(false)
        object QualifiedBool : ArgType<kotlin.Boolean>(false)
        open class Forward<T : Any> : ArgType<T>(false)
        class Indirect : Forward<kotlin.Boolean>()
        class Opt1<T : Any>(val type: ArgType<T>)
        fun <T : Any> take(t: ArgType<T>) {}

        val inferred = Opt1(Impl())
        val explicit = Opt1<Boolean>(Impl())
        val singleton = Opt1<Boolean>(Bool2)
        val cast = Opt1<Boolean>(Bool2 as ArgType<Boolean>)
        val function = take<Boolean>(Impl())
        val objectFunction = take<Boolean>(Bool2)
        val qualifiedObject = Opt1<Boolean>(QualifiedBool)
        val indirect = Opt1<Boolean>(Indirect())
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], frontendFlags: useCache ? ["sema-cache"] : [], includeStdlib: false
            )
            try runSema(ctx)
            let hasError = ctx.diagnostics.hasError
            #expect(!hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
            let sema = try #require(ctx.sema)
            let argType = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("ArgType")]))
            for name in ["Impl", "Bool2", "QualifiedBool", "Indirect"] {
                let symbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern(name)]))
                let arguments = sema.types.liftedNominalSupertypeArgs(from: symbol, childArgs: [], to: argType)
                #expect(arguments == [.invariant(sema.types.booleanType)])
            }
        }
    }

    @Test(arguments: ["Opt1<Boolean>(Impl())", "take<Boolean>(Impl())",
                      "Opt1<Boolean>(Bool2)", "take<Boolean>(Bool2)"])
    func incompatibleInheritedTypeArgumentRemainsRejected(call: String) throws {
        let source = """
        abstract class ArgType<T : Any>(val hasParameter: kotlin.Boolean)
        class Impl : ArgType<String>(false)
        object Bool2 : ArgType<String>(false)
        class Opt1<T : Any>(val type: ArgType<T>)
        fun <T : Any> take(t: ArgType<T>) {}
        val result = \(call)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "\(errors.map { $0.message })")
        }
    }
}
#endif
