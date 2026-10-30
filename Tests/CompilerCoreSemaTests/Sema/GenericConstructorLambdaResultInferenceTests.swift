#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-2318: generic constructor result parameters are inferred from the
/// concrete return type of a function-typed lambda argument.
@Suite
struct GenericConstructorLambdaResultInferenceTests {
    @Test
    func infersGenericConstructorResultFromGeneratedTupleLambdaReturns() throws {
        let ctx = try makeTestContext(Self.generatedSources)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test
    func rejectsAnInputOnlyConstructorTypeParameterWithoutEvidence() throws {
        let ctx = try makeTestContext([
            """
            package kuu2318.uninferred
            class Holder<T>(val action: (T) -> Unit)
            fun sample() { val holder = Holder { value -> Unit } }
            """,
        ])
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-INFER" })
    }

    private static let generatedSources = [generatedSource(arity: 3)]

    private static func generatedSource(arity: Int) -> String {
        let typeParameters = (0..<arity).map { "T\($0)" }
        let tuple2Parameters = Array(typeParameters.prefix(2))
        let tupleArguments = typeParameters.joined(separator: ", ")
        let tupleProperties = typeParameters.enumerated().map { index, type in
            "val value\(index): \(type)"
        }.joined(separator: ", ")
        let reifiedParameters = typeParameters.map { "reified \($0)" }.joined(separator: ", ")
        let casts = typeParameters.enumerated().map { index, type in
            "it[\(index)] as \(type)"
        }.joined(separator: ", ")
        let lastTypeParameter = typeParameters[arity - 1]

        return """
        package kuu2318.arity\(arity)

        data class Tuple2<\(tuple2Parameters.joined(separator: ", "))>(\(tuple2Parameters.enumerated().map { "val value\($0.offset): \($0.element)" }.joined(separator: ", ")))
        data class Tuple\(arity)<\(tupleArguments)>(\(tupleProperties))
        interface Parser<T>
        interface Items<T> {
            operator fun <U> plus(element: U): Items<T>
            operator fun get(index: Int): T
        }
        class AndCombinator<out R>(
            val consumersImpl: Items<Any?>,
            val transform: (Items<Any?>) -> R
        )

        inline fun <\(reifiedParameters)>
            AndCombinator<Tuple2<\(tuple2Parameters.joined(separator: ", "))>>.and\(arity)(p\(arity): Parser<\(lastTypeParameter)>) =
            AndCombinator(consumersImpl + p\(arity), {
                Tuple\(arity)(\(casts))
            })
        """
    }

    private func makeTestContext(_ sources: [String]) throws -> CompilationContext {
        var result: CompilationContext?
        try withTemporaryFiles(contents: sources + ["package kotlin\nobject Unit"]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            result = ctx
        }
        return try #require(result)
    }
}
#endif
