@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testStackTraceRecoverableCopy(useArtifact: Bool) throws {
        let source = try diffCaseSource("coroutine_stack_trace_recoverable.kt")
        try compileAndRunKotlin(
            source,
            expectedOutput: "42\nnull\n",
            moduleName: "StackTraceRecoverable",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(arguments: [false, true])
    func testStackTraceRecoverableSignatureAndOptIn(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let context = try semaContext(
            from: """
            import kotlin.coroutines.debug.StackTraceRecoverable

            fun copyWithoutOptIn(value: StackTraceRecoverable<*>): Throwable? =
                value.copyForStackTraceRecovery()
            """,
            expecting: [
                .error(
                    "KSWIFTK-SEMA-OPT-IN",
                    containing: "kotlin.coroutines.ExperimentalStdlibCoroutineSupportApi",
                    count: 2
                )
            ],
            includeStdlib: !useArtifact,
            stdlibLibraryPath: artifactPath
        )

        let sema = try #require(context.sema)
        let recoverableName = ["kotlin", "coroutines", "debug", "StackTraceRecoverable"].map(context.interner.intern)
        let recoverable = try #require(sema.symbols.lookup(fqName: recoverableName))
        let parameter = try #require(sema.types.nominalTypeParameterSymbols(for: recoverable).first)
        let throwableName = ["kotlin", "Throwable"].map(context.interner.intern)
        let throwable = try #require(sema.symbols.lookup(fqName: throwableName))
        let parameterType = sema.types.make(.typeParam(TypeParamType(symbol: parameter)))
        let throwableBound = sema.types.make(.classType(ClassType(classSymbol: throwable)))
        let recursiveBound = sema.types.make(.classType(ClassType(
            classSymbol: recoverable, args: [.invariant(parameterType)]
        )))
        #expect(sema.types.declaredUpperBounds(for: parameter) == [throwableBound, recursiveBound])

        let copyName = recoverableName + [context.interner.intern("copyForStackTraceRecovery")]
        let copy = try #require(sema.symbols.lookup(fqName: copyName))
        let signature = try #require(sema.symbols.functionSignature(for: copy))
        let nullableParameter = sema.types.make(.typeParam(TypeParamType(symbol: parameter, nullability: .nullable)))
        #expect(signature.returnType == nullableParameter)
    }
}
