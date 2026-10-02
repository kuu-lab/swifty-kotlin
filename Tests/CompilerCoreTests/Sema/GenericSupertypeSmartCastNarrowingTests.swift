#if canImport(Testing)
@testable import CompilerCore
import Testing

/// `this is List` (no explicit type argument) on a value already known to be
/// `Iterable<T>` must narrow to `List<T>`, not an under-specified `List` with
/// no type arguments -- List's declared path to Iterable
/// (`List<out E> : Collection<E>`, `Collection<E> : Iterable<E>`) passes the
/// same type parameter straight through, so a value that is both `Iterable<T>`
/// and a `List` can only be a `List<T>`.
///
/// Without this, a generic extension like `fun <T> Iterable<T>.elementAt(...):
/// T { if (this is List) { val list = this; return list[index] } ... }`
/// infers `list[index]`'s type as `Any` instead of `T`, which used to go
/// unnoticed only because a plain top-level `return` was never checked
/// against its function's declared return type unless it sat inside a lambda.
@Suite
struct GenericSupertypeSmartCastNarrowingTests {
    @Test func testSmartCastToUnparameterizedSubtypePreservesSharedTypeParameter() throws {
        let ctx = makeContextFromSources([
            """
            package sample0
            fun <T> myElementAt(iterable: Iterable<T>, index: Int): T {
                if (iterable is List) {
                    val list = iterable
                    return list[index]
                }
                throw NoSuchElementException()
            }
            fun main() {
                println(myElementAt(listOf(1, 2, 3), 1))
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    /// Same gap, surfacing through a `when`-subject `is` check instead of a
    /// plain `if`: `fun <T> Iterable<T>.single(): T { when (this) { is List
    /// -> return this.single() ... } }` is the exact shape the bundled
    /// stdlib uses, and it is handled by a separate code path
    /// (narrowedStateForIsCheck/narrowedStateForConditionSymbol in
    /// Analysis.swift) from the plain `if (x is List)` case above.
    @Test func testWhenSubjectIsCheckPreservesSharedTypeParameter() throws {
        let ctx = makeContextFromSources([
            """
            package sample2
            fun <T> myFirst(iterable: Iterable<T>): T {
                when (iterable) {
                    is List -> return iterable[0]
                    else -> throw NoSuchElementException()
                }
            }
            fun main() {
                println(myFirst(listOf(1, 2, 3)))
            }
            """
        ])
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testOrdinaryUnrelatedIsCheckStillNarrowsWithoutTypeArgs() throws {
        // A non-generic `is` check (no shared type parameter to recover)
        // must keep behaving exactly as before: narrow to the plain target
        // type, uninfluenced by this fix.
        let ctx = makeContextFromSources([
            """
            package sample1
            fun describe(x: Any): String {
                if (x is String) {
                    return x.length.toString()
                }
                return "?"
            }
            fun main() {
                println(describe("hi"))
            }
            """
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
