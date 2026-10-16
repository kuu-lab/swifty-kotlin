#if canImport(Testing)
import Foundation
@testable import CompilerCore
import Testing

@Suite
struct GenericCallExpectedReturnNestedArgumentTests {
    private let declarations = """
    package sample

    class Marker
    class Input
    class Other
    interface List<out E>
    interface MutableCollection<in E>
    interface Iterable<out E>
    class ArrayList<E> : List<E>, MutableCollection<E> { constructor() }
    class ReadOnlyList<E> : List<E> { constructor() }
    class Pair<out A, out B>
    class Result<out V, out E>

    fun <T, E, C1 : MutableCollection<in T>, C2 : MutableCollection<in T>>
        tryPartitionTo(
            first: C1,
            second: C2,
            predicate: (T) -> Result<Marker, E>
        ): Result<Pair<C1, C2>, E> = Result()
    """

    @Test
    func expectedReturnTypeFlowsThroughNestedCovariantTypes() throws {
        let source = declarations + """

        fun <T, E> Iterable<T>.partition(
            predicate: (T) -> Result<Marker, E>
        ): Result<Pair<List<T>, List<T>>, E> =
            tryPartitionTo(ArrayList(), ArrayList(), predicate)

        fun <T, E> Iterable<T>.partitionWithTypedConstructors(
            predicate: (T) -> Result<Marker, E>
        ): Result<Pair<List<T>, List<T>>, E> =
            tryPartitionTo(ArrayList<T>(), ArrayList<T>(), predicate)

        fun <T, E> Iterable<T>.partitionWithExplicitTypeArguments(
            predicate: (T) -> Result<Marker, E>
        ): Result<Pair<List<T>, List<T>>, E> =
            tryPartitionTo<T, E, ArrayList<T>, ArrayList<T>>(
                ArrayList(), ArrayList(), predicate
            )

        fun <T, E> Iterable<T>.partitionWithInferredReturnType(
            predicate: (T) -> Result<Marker, E>
        ) = tryPartitionTo(ArrayList<T>(), ArrayList<T>(), predicate)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [
        "tryPartitionTo(ArrayList<Other>(), ArrayList(), predicate)",
        "tryPartitionTo(ReadOnlyList<Input>(), ArrayList(), predicate)",
    ])
    func incompatibleDestinationDoesNotSatisfyMutableElementBound(call: String) throws {
        let source = declarations + """

        fun <E> invalid(
            predicate: (Input) -> Result<Marker, E>
        ): Result<Pair<List<Input>, List<Input>>, E> =
            \(call)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }
}
#endif
