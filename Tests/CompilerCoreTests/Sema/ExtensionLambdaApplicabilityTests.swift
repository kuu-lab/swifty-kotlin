@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ExtensionLambdaApplicabilityTests {
    @Test
    func genericIterableOnEachTrailingLambdaUsesReceiverElementType() throws {
        try withTemporaryFile(contents: """
        package fixture
        class Outcome<V, E>(val value: V, val error: E?)

        fun <V, E> Iterable<Outcome<V, E>>.simpleEach(
            action: (Outcome<V, E>) -> Unit
        ): Iterable<Outcome<V, E>> = onEach { item -> action(item) }

        fun <V, E> iterableOnEach(
            values: Iterable<Outcome<V, E>>,
            action: (Outcome<V, E>) -> Unit
        ): Iterable<Outcome<V, E>> {
            values.onEach { item: Outcome<V, E> -> action(item) }
            values.onEach(action)
            values.forEach(action)
            return values
        }

        fun <V, E> iterableOnEachIndexed(
            values: Iterable<Outcome<V, E>>
        ): Iterable<Outcome<V, E>> = values.onEachIndexed { index, item ->
            val value: V = item.value
            val error: E? = item.error
            print(index)
        }

        fun listOnEach(
            values: List<Outcome<Int, String>>
        ): List<Outcome<Int, String>> = values.onEach { item -> print(item.value) }

        fun stringOnEach(value: String): String = value.onEach { char: Char -> print(char) }
        """) { path in
            let ctx = try context(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [true, false])
    func iterableAggregateSurvivesInapplicableListOverload(includeListOverload: Bool) throws {
        let source = """
        package fixture
        fun <S, T : S> Iterable<T>.aggregate(operation: (S, T) -> S): S = iterator().next()
        \(includeListOverload ? "fun List<Int>.aggregate(marker: String): String = marker" : "")
        fun result(values: List<Int>): Int =
            values.aggregate<Int, Int> { acc, item -> acc + item }
        """
        try assertAccepted([source], receiver: "Iterable")
    }

    @Test(arguments: [
        "fun List<Int>.aggregate(marker: String): String = marker",
        "fun <S, T : S> List<T>.aggregate(operation: (S) -> S): S = operation(iterator().next())",
        "fun <U> List<Int>.aggregate(operation: (Int, Int) -> Int): Int = operation(9, 9)",
    ])
    func lambdaShapeAndTypeArgumentArityPrecedeSpecificity(overload: String) throws {
        try assertAccepted(["""
        package fixture
        fun <S, T : S> Iterable<T>.aggregate(operation: (S, T) -> S): S = iterator().next()
        \(overload)
        fun result(values: List<Int>): Int = values.aggregate<Int, Int> { acc, item -> acc + item }
        """], receiver: "Iterable")
    }

    @Test
    func inferredAndNamedLambdasSurviveNonCallableOverload() throws {
        // Dependent accumulator inference without explicit types is KUU-2155.
        try assertAccepted(["""
        package fixture
        fun Iterable<Int>.aggregate(operation: (Int, Int) -> Int): Int = operation(iterator().next(), 0)
        fun List<Int>.aggregate(marker: String): String = marker
        fun result(values: List<Int>): Int = values.aggregate { acc, item -> acc + item }
        fun named(values: List<Int>): Int = values.aggregate(operation = { acc, item -> acc + item })
        """], receiver: "Iterable")
    }

    @Test
    func applicableListOverloadRetainsSpecificity() throws {
        try assertAccepted(["""
        package fixture
        fun Iterable<Int>.aggregate(operation: (Int, Int) -> Int): Int = operation(1, 2)
        fun List<Int>.aggregate(operation: (Int, Int) -> Int): Int = operation(3, 4)
        fun result(values: List<Int>): Int = values.aggregate { acc, item -> acc + item }
        """], receiver: "List")
    }

    @Test(arguments: [true, false])
    func nearerScopeFallsBackOnlyWhenInapplicable(applicable: Bool) throws {
        try assertAccepted(["""
        package fixture
        fun <S, T : S> List<T>.aggregate(operation: (S, T) -> S): S = iterator().next()
        fun result(values: List<Int>): Int {
            \(applicable
                ? "fun <S, T : S> Iterable<T>.aggregate(operation: (S, T) -> S): S = iterator().next()"
                : "fun List<Int>.aggregate(marker: String): String = marker")
            return values.aggregate<Int, Int> { acc, item -> acc + item }
        }
        """], receiver: applicable ? "Iterable" : "List")
    }

    @Test
    func inapplicableLocalFunctionOverloadDoesNotHideOuterExtension() throws {
        try assertAccepted(["""
        package fixture
        fun <S, T : S> Iterable<T>.aggregate(operation: (S, T) -> S): S = iterator().next()
        fun result(values: List<Int>): Int {
            fun List<Int>.aggregate(marker: String): String = marker
            return values.aggregate<Int, Int> { acc, item -> acc + item }
        }
        """], receiver: "Iterable")
    }

    @Test
    func inaccessibleOverloadDoesNotHideVisibleExtension() throws {
        try assertAccepted(["""
        package fixture
        private fun List<Int>.aggregate(operation: (Int, Int) -> Int): Int = operation(9, 9)
        """, """
        package fixture
        fun Iterable<Int>.aggregate(operation: (Int, Int) -> Int): Int = operation(1, 2)
        fun result(values: List<Int>): Int = values.aggregate { acc, item -> acc + item }
        """], receiver: "Iterable")
    }

    @Test(arguments: ["private ", ""])
    func fallbackDoesNotAdmitInvisibleOrUnimportedExtensions(visibility: String) throws {
        try withTemporaryFiles(contents: ["""
        package other
        \(visibility)fun <S, T : S> Iterable<T>.aggregate(operation: (S, T) -> S): S = iterator().next()
        """, """
        package fixture
        fun List<Int>.aggregate(marker: String): String = marker
        fun result(values: List<Int>): Int = values.aggregate<Int, Int> { acc, item -> acc + item }
        """]) { paths in
            let ctx = try context(inputs: paths)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test(arguments: [
        "values.aggregate<Int> { acc, item -> acc + item }",
        "values.aggregate<Int, Int, Int> { acc, item -> acc + item }",
        "values.aggregate<Int, Int> { acc, item -> true }",
    ])
    func invalidTypeArgumentsAndLambdaReturnRemainRejected(expression: String) throws {
        try withTemporaryFile(contents: """
        package fixture
        fun <S, T : S> Iterable<T>.aggregate(operation: (S, T) -> S): S = iterator().next()
        fun List<Int>.aggregate(marker: String): String = marker
        fun result(values: List<Int>): Int = \(expression)
        """) { path in
            let ctx = try context(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    private func assertAccepted(_ sources: [String], receiver: String) throws {
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = try context(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let calls = sema.bindings.callBindings.values.filter {
                sema.symbols.symbol($0.chosenCallee)?.name == ctx.interner.intern("aggregate")
            }
            #expect(!calls.isEmpty)
            for call in calls {
                let type = try #require(sema.symbols.functionSignature(for: call.chosenCallee)?.receiverType)
                guard case let .classType(nominal) = sema.types.kind(of: type) else {
                    Issue.record("Expected nominal extension receiver")
                    continue
                }
                #expect(sema.symbols.symbol(nominal.classSymbol)?.name == ctx.interner.intern(receiver))
            }
        }
    }

    private func context(inputs: [String]) throws -> CompilationContext {
        TestStdlibCache.shared.prepare()
        let artifact = try #require(CompilerOptions.defaultStdlibLibraryPath)
        return makeCompilationContext(inputs: inputs, includeStdlib: false, stdlibLibraryPath: artifact)
    }
}
