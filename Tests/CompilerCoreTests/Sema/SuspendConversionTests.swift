#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SuspendConversionTests {
    @Test func acceptsFunctionValuesAndInfersGenericSignature() throws {
        let source = """
        fun consume(action: suspend (Int) -> Unit) {}
        fun <T, R> generic(value: T, action: suspend (T) -> R): R = TODO()
        fun forward(action: (Int) -> Unit, transform: (Int) -> String) {
            consume(action)
            val result: String = generic(3, transform)
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
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
            let ctx = makeCompilationContext(inputs: paths)
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
