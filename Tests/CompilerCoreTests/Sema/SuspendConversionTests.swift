#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SuspendConversionTests {
    @Test func memberOverloadKeepsSuspendFunctionCandidateForRegularFunctionValue() throws {
        let source = """
        fun interface FlowCollector<T> { suspend fun emit(value: T) }
        interface Flow<T> {
            suspend fun collect(action: suspend (T) -> Unit)
            suspend fun collect(action: FlowCollector<T>)
        }
        fun forward(source: Flow<Int>, action: (Int) -> Unit) {
            source.collect(action)
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let binding = try #require(sema.bindings.callBindings.values.first { binding in
                sema.symbols.symbol(binding.chosenCallee).map { ctx.interner.resolve($0.name) == "collect" } == true
            })
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            guard case let .functionType(functionType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                Issue.record("The regular function value must select the suspend function overload.")
                return
            }
            #expect(functionType.isSuspend)
        }
    }

    @Test func acceptsFunctionValuesAndInfersGenericSignature() throws {
        let source = """
        fun consume(action: suspend (Int) -> Unit) {}
        fun <T, R> generic(value: T, fallback: R, action: suspend (T) -> R): R = fallback
        fun forward(action: (Int) -> Unit, transform: (Int) -> String) {
            consume(action)
            val result: String = generic(3, "unused", transform)
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
        }
    }

    @Test func acceptsCallableReferencesForSuspendConversionAndUnitCoercion() throws {
        let source = """
        fun consume(action: suspend () -> Unit) {}
        fun regularUnit() {}
        fun regularString(): String = "ignored"
        fun forward() {
            consume(::regularUnit)
            consume(::regularString)
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
        }
    }

    @Test func rejectsSuspendCallableReferenceForRegularFunctionType() throws {
        let source = """
        fun consume(action: () -> Unit) {}
        suspend fun suspended() {}
        fun forward() { consume(::suspended) }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test func acceptsDirectlyTypedSuspendCallableReferences() throws {
        let source = """
        fun regular(value: Int = 42): Int = value
        fun identity(value: Int): Int = value
        fun forward() {
            val defaulted: suspend () -> Int = ::regular
            val direct: suspend (Int) -> Int = ::identity
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
        }
    }

    @Test(arguments: [
        "fun bad(action: (String) -> Unit) { consume(action) }",
        "fun number(action: suspend (Int) -> Int) {}\nfun bad(action: (Int) -> String) { number(action) }",
        "fun bad(action: (Int, Int) -> Unit) { consume(action) }",
        "fun bad(action: ((Int) -> Unit)?) { consume(action) }",
        "fun ordinary(action: (Int) -> Unit) {}\nfun bad(action: suspend (Int) -> Unit) { ordinary(action) }",
        "fun bad(action: (Int) -> Unit) { val stored: suspend (Int) -> Unit = action }",
    ])
    func rejectsIncompatibleArgumentsAndImplicitSubtyping(declaration: String) throws {
        try withTemporaryFiles(contents: ["fun consume(action: suspend (Int) -> Unit) {}\n" + declaration]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test func conversionDoesNotChangeOrdinarySubtyping() {
        let types = TypeSystem()
        let regular = types.make(.functionType(FunctionType(params: [types.intType], returnType: types.unitType)))
        let suspended = types.make(.functionType(FunctionType(params: [types.intType], returnType: types.unitType, isSuspend: true)))
        #expect(!types.isSubtype(regular, suspended))
        #expect(!types.isSubtype(suspended, regular))
        #expect(types.suspendConversionType(from: regular, to: suspended) == suspended)
        #expect(types.suspendConversionType(from: suspended, to: regular) == nil)
    }
}
#endif
