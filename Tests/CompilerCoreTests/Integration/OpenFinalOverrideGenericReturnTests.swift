import XCTest
@testable import CompilerCore

final class OpenFinalOverrideGenericReturnTests: XCTestCase {

    func testWidenedGenericListOverrideIsRejected() throws {
        let source = """
        open class ListProvider<T> {
            open fun items(): List<T> = emptyList()
        }
        class Widened : ListProvider<String>() {
            override fun items(): List<Any> = emptyList()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-RETURN", in: ctx)
    }

    func testCovariantGenericListOverrideIsAccepted() throws {
        let source = """
        open class ListProvider<T> {
            open fun items(): List<T> = emptyList()
        }
        class Narrowed : ListProvider<Number>() {
            override fun items(): List<Int> = emptyList()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-RETURN", in: ctx)
        XCTAssertFalse(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }))
    }

    func testWidenedTypeParameterReturnOverrideIsRejected() throws {
        let source = """
        open class ValueHolder<T> {
            open fun value(): T = throw RuntimeException()
        }
        class Widened : ValueHolder<String>() {
            override fun value(): Any = "x"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-RETURN", in: ctx)
    }
}
