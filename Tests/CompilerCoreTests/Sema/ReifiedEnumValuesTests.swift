@testable import CompilerCore
import Testing

@Suite
struct ReifiedEnumValuesTests {
    @Test
    func acceptsReifiedSelfBoundAndPreservesElementType() throws {
        let fixture = SemaFixture(surface: "reified enumValues")
        let (sema, _) = try fixture.make(source: """
        enum class E { A, B }
        inline fun <reified T : Enum<T>> values(): List<T> = enumValues<T>().toList()
        inline fun <reified T> whereValues(): Array<T> where T : Enum<T> = enumValues<T>()
        """)
        let calls = sema.bindings.callBindings.filter {
            sema.bindings.stdlibSpecialCallKind(for: $0.key) == .enumValues
                && $0.value.substitutedTypeArguments.contains { type in
                    if case .typeParam = sema.types.kind(of: type) { return true }
                    return false
                }
        }
        #expect(calls.count == 2)
        for (expr, binding) in calls {
            let result = try #require(sema.bindings.exprTypes[expr])
            guard case let .classType(array) = sema.types.kind(of: result) else {
                Issue.record("Expected Array<T>")
                continue
            }
            #expect(array.args == [.invariant(binding.substitutedTypeArguments[0])])
        }
    }

    @Test(arguments: [
        "fun <T : Enum<T>> bad() = enumValues<T>()",
        "inline fun <reified T> bad() = enumValues<T>()",
        "inline fun <reified T : Enum<T>> bad() = enumValues<T?>()",
        "fun bad() = enumValues<String>()",
    ])
    func rejectsInvalidTypeArguments(source: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-0002" && $0.message.contains("non-nullable enum")
            })
        }
    }
}
