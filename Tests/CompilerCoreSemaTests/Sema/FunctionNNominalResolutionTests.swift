#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite(.serialized)
struct FunctionNNominalResolutionTests {
    @Test
    func functionNTypesCanBeNamedAndImplemented() throws {
        let source = """
        val simple: Function1<Int, Int> = { it + 1 }
        val qualified: kotlin.Function1<Int, Int> = simple

        class Increment : Function1<Int, Int> {
            override fun invoke(value: Int): Int = value + 1
        }

        class Constant : Function0<Int> {
            override fun invoke(): Int = 42
            fun callSelf(): Int = this()
        }

        fun main() {
            println(simple(1))
            println(qualified(2))
            println(Increment()(3))
            println(Constant().callSelf())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path])
            try runSema(context)

            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, Comment(rawValue: "Unexpected diagnostics: \(errors)"))
        }
    }

    @Test
    func functionNTypesCanBeNamedThroughArity255() throws {
        let typeArguments = Array(repeating: "*", count: 256).joined(separator: ", ")
        let source = "fun matches(value: Any): Boolean = value is Function255<\(typeArguments)>"

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, Comment(rawValue: "Unexpected diagnostics: \(errors)"))

            let sema = try #require(context.sema)
            let function255 = try #require(sema.types.functionNInterfaceSymbols[255])
            #expect(sema.types.nominalFunctionInterfaceShape(of: function255)?.arity == 255)
            #expect(sema.types.functionNInterfaceSymbols[254] == nil)
        }
    }
}
#endif
