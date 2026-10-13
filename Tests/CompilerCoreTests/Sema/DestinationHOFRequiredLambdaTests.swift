@testable import CompilerCore
import Foundation
import Testing

/// KUU-1432: every destination HOF takes exactly two arguments (destination +
/// predicate/transform lambda). The collection fast path only handled the
/// arity-2 shape, so a call at any other arity bound a result type with no
/// callee and lowered to a phantom `_filterTo`-style symbol (LINK-0001)
/// instead of reporting the missing lambda at compile time like kotlinc's
/// "no value passed for parameter". Pin that these calls now reach regular
/// overload resolution and reject at compile time.
@Suite
struct DestinationHOFRequiredLambdaTests {
    /// `call` must reject with a compile-time arity/unresolved diagnostic
    /// rather than binding a phantom callee.
    @Test(arguments: [
        "l.filterTo(mutableListOf())",
        "l.filterNotTo(mutableListOf())",
        "l.filterIndexedTo(mutableListOf())",
        "l.mapTo(mutableListOf())",
        "l.mapNotNullTo(mutableListOf())",
        "l.mapIndexedTo(mutableListOf())",
        "l.mapIndexedNotNullTo(mutableListOf())",
        "l.flatMapTo(mutableListOf())",
        "l.flatMapIndexedTo(mutableListOf())",
        "l.associateTo(mutableMapOf<Int, Int>())",
        "s.filterTo(mutableListOf())",
        "s.mapTo(mutableListOf())",
        "c.filterNotTo(mutableListOf())",
        "c.associateTo(mutableMapOf<Int, Int>())",
        "i.filterTo(mutableListOf())",
        "i.filterNotTo(mutableListOf())",
        "i.filterIndexedTo(mutableListOf())",
        "seq.filterTo(mutableListOf())",
        "seq.filterNotTo(mutableListOf())",
        "seq.filterIndexedTo(mutableListOf())",
        "seq.mapTo(mutableListOf())",
        "seq.mapNotNullTo(mutableListOf())",
        "seq.mapIndexedTo(mutableListOf())",
        "seq.mapIndexedNotNullTo(mutableListOf())",
        "seq.flatMapTo(mutableListOf())",
        "seq.flatMapIndexedTo(mutableListOf())",
        "seq.associateTo(mutableMapOf<Int, Int>())",
        "m.filterTo(mutableListOf())",
        "m.filterNotTo(mutableListOf())",
        "m.mapTo(mutableListOf())",
        "m.mapNotNullTo(mutableListOf())",
        "m.mapKeysTo(mutableMapOf<Int, Int>())",
        "m.mapValuesTo(mutableMapOf<Int, Int>())",
        "l.mapKeysTo(mutableMapOf<Int, Int>())",
        "l.mapValuesTo(mutableMapOf<Int, Int>())",
    ])
    func missingLambdaArgumentIsRejected(call: String) throws {
        let source = """
        fun probe(l: List<Int>, s: Set<Int>, c: Collection<Int>, i: Iterable<Int>, seq: Sequence<Int>, m: Map<Int, String>) {
            \(call)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.count == 1, "Expected exactly one rejection for \(call), got \(errors)")
            // SEMA-0002 when same-named overloads exist but none accepts the
            // arity; SEMA-0024 when the name does not exist on the receiver
            // at all (e.g. mapKeysTo on List — kotlinc: unresolved reference).
            #expect(
                ["KSWIFTK-SEMA-0002", "KSWIFTK-SEMA-0024"].contains(errors.first?.code),
                "Expected a compile-time rejection for \(call), got \(errors)"
            )
        }
    }

    /// `filterTo()` and 3-argument destination calls are equally invalid
    /// Kotlin (arity is exactly 2 for every destination HOF); they must
    /// reject through the same path rather than lowering to a phantom callee.
    @Test
    func zeroAndThreeArgumentCallsAreRejected() throws {
        let source = """
        fun probe(l: List<Int>) {
            l.filterTo()
            l.filterNotTo(mutableListOf(), { it > 0 }, 5)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(!errors.isEmpty, "Expected bad-arity destination calls to be rejected")
            #expect(
                errors.contains { ["KSWIFTK-SEMA-0002", "KSWIFTK-SEMA-0024"].contains($0.code) },
                "Expected an overload rejection, got \(errors)"
            )
        }
    }

    /// The arity gate must not swallow legitimate calls: two-argument
    /// destination HOFs still bind, and `filterNotNullTo` (a real one-argument
    /// destination HOF outside `destinationCollectionHOFs`) keeps working.
    @Test
    func wellFormedDestinationCallsStillTypeCheck() throws {
        let source = """
        fun probe(l: List<Int>, ln: List<Int?>, m: Map<Int, String>) {
            l.filterTo(mutableListOf()) { it > 0 }
            l.filterNotTo(mutableListOf()) { it > 0 }
            l.filterIndexedTo(mutableListOf()) { index, _ -> index > 0 }
            l.mapTo(mutableListOf()) { it }
            l.associateTo(mutableMapOf()) { it to it }
            m.filterTo(mutableMapOf()) { it.key > 0 }
            m.mapKeysTo(mutableMapOf()) { it.key }
            ln.filterNotNullTo(mutableListOf())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected well-formed destination calls to type-check, got \(errors)")
        }
    }
}
