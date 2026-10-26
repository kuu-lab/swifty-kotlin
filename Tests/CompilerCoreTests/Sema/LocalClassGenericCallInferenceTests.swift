#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct LocalClassGenericCallInferenceTests {
    @Test
    func localClassIsInferredAsGenericCallTypeArgument() throws {
        let source = """
        fun <T> identity(value: T): T = value

        fun box(): Any {
            class Local
            return identity(Local())
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)

        let sema = try #require(ctx.sema)
        let identityCall = try #require(sema.bindings.callBindings.values.first { binding in
            guard let function = sema.symbols.symbol(binding.chosenCallee) else {
                return false
            }
            return ctx.interner.resolve(function.name) == "identity"
        })
        let inferredType = try #require(identityCall.substitutedTypeArguments.first)
        guard case let .classType(classType) = sema.types.kind(of: inferredType),
              let classSymbol = sema.symbols.symbol(classType.classSymbol)
        else {
            Issue.record("Expected identity to infer the local class as its type argument.")
            return
        }
        #expect(ctx.interner.resolve(classSymbol.name) == "Local")
    }
}
#endif
