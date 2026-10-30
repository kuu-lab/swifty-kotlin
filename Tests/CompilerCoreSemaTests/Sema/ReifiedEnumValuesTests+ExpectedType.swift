@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension ReifiedEnumValuesTests {
    @Test
    func infersEnumValuesFromExpectedArrayAndStoresTypeArgument() throws {
        let ctx = try makeExpectedEnumValuesContext(sources: ["""
        enum class E { A, B }
        inline fun <reified T : Enum<T>> enumArray(): Array<T> = enumValues()
        inline fun <reified T : Enum<T>> projected(): Array<out T> = enumValues()
        inline fun <reified T> whereValues(): Array<T> where T : Enum<T> = enumValues()
        fun concrete(): Array<E> = enumValues()
        fun nullableArray(): Array<E>? = enumValues()
        fun projectedConcrete(): Array<out E> = enumValues()
        fun contravariantConcrete(): Array<in E> = enumValues()
        fun local(): Array<E> { val result: Array<E> = enumValues(); return result }
        class Adapter<T : Enum<T>>(val values: Array<out T>)
        inline fun <reified T : Enum<T>> adapter(): Adapter<T> = Adapter(enumValues())
        """])
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let calls = try userEnumValuesCalls(ctx)
        #expect(calls.count == 9)
        for (expr, binding) in calls {
            #expect(binding.substitutedTypeArguments.count == 1)
            let element = try #require(binding.substitutedTypeArguments.first)
            let result = try #require(sema.bindings.exprTypes[expr])
            guard case let .classType(array) = sema.types.kind(of: result) else {
                Issue.record("Expected Array<T>")
                continue
            }
            #expect(array.args == [.invariant(element)])
            #expect(array.nullability == .nonNull)
        }
    }

    @Test(arguments: [
        "fun invalid(): Array<String> = enumValues()",
        "fun <T : Enum<T>> invalid(): Array<T> = enumValues()",
        "inline fun <reified T> invalid(): Array<T> = enumValues()",
        "enum class E { A }; fun invalid(): Array<E?> = enumValues()",
        "fun invalid(): Array<*> = enumValues()",
        "fun invalid() = enumValues()",
        "enum class E { A }; fun invalid(): Array<E> = enumValues(1)",
        "enum class E { A }; fun invalid(): Array<E> = enumValues<E, E>()",
    ])
    func rejectsInvalidInferredEnumValues(source: String) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-0002"
            })
        }
    }

    @Test
    func explicitEnumValuesTypeArgumentWinsOverExpectedElement() throws {
        try withTemporaryFile(contents: """
        enum class E { A }
        enum class F { B }
        fun invalid(): Array<E> = enumValues<F>()
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let f = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("F")]))
            let calls = try userEnumValuesCalls(ctx)
            #expect(calls.count == 1)
            let binding = try #require(calls.first?.value)
            let type = try #require(binding.substitutedTypeArguments.first)
            guard case let .classType(element) = sema.types.kind(of: type) else {
                Issue.record("Expected explicit F type")
                return
            }
            #expect(element.classSymbol == f)
        }
    }

    @Test(arguments: ["import kotlin.enumValues", "import kotlin.enumValues as values"])
    func inferredEnumValuesPreservesExplicitImports(importLine: String) throws {
        let name = importLine.contains(" as ") ? "values" : "enumValues"
        let ctx = try makeExpectedEnumValuesContext(sources: ["""
        \(importLine)
        enum class E { A }
        fun enumValues(): String = "USER"
        fun result(): Array<E> = \(name)()
        """])
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let calls = try userEnumValuesCalls(ctx)
        #expect(calls.count == 1)
        #expect(calls.values.allSatisfy { $0.substitutedTypeArguments.count == 1 })
    }

    @Test
    func inferredEnumValuesPreservesUserAndLocalShadowing() throws {
        let ctx = try makeExpectedEnumValuesContext(sources: ["""
        enum class E { A }
        fun enumValues(): Array<E> = arrayOf(E.A)
        fun result(): Array<E> = enumValues()
        fun local(): Array<E> { val enumValues: () -> Array<E> = { arrayOf(E.A) }; return enumValues() }
        """])
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        #expect(try userEnumValuesCalls(ctx).isEmpty)
    }

    @Test
    func privateEnumValuesInAnotherFileDoesNotShadowIntrinsic() throws {
        let ctx = try makeExpectedEnumValuesContext(sources: [
            "package example; private fun enumValues(): String = \"USER\"",
            """
            package example
            inline fun <reified T : Enum<T>> values(): Array<T> = enumValues()
            inline fun <reified T : Enum<T>> explicit(): Array<T> = enumValues<T>()
            """,
        ])
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        #expect(try userEnumValuesCalls(ctx).count == 2)
    }
}

private func makeExpectedEnumValuesContext(sources: [String]) throws -> CompilationContext {
    var result: CompilationContext?
    try withTemporaryFiles(contents: sources) { paths in
        let ctx = makeCompilationContext(inputs: paths)
        try runSema(ctx)
        result = ctx
    }
    return try #require(result)
}

private func userEnumValuesCalls(_ ctx: CompilationContext) throws -> [ExprID: CallBinding] {
    let sema = try #require(ctx.sema)
    let ast = try #require(ctx.ast)
    let inputs = Set(ctx.options.inputs)
    return sema.bindings.callBindings.filter { id, _ in
        guard let range = ast.arena.exprRange(id),
              inputs.contains(ctx.sourceManager.path(of: range.start.file))
        else { return false }
        return sema.bindings.stdlibSpecialCallKind(for: id) == .enumValues
    }
}
