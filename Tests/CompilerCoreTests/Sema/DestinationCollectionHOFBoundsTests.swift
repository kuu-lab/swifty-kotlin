@testable import CompilerCore
import Testing

/// KUU-834: destination HOF specials must enforce their MutableCollection and
/// MutableMap bounds before assigning contextual types to the lambda.
@Suite
struct DestinationCollectionHOFBoundsTests {
    @Test
    func rejectsDestinationsOutsideTheRequiredNominalFamily() throws {
        let ctx = makeContextFromSource("""
        fun invalidDestinations() {
            listOf(1, 2).filterTo(emptyList()) { it > 0 }
            listOf(1, 2).associateTo(mutableListOf()) { it to it * 3 }
            listOf(1, 2).filterTo(mutableMapOf<Int, Int>()) { it > 0 }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 3, "Expected one destination-bound error per invalid call, got: \(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-TYPE-0001" })
        #expect(errors.allSatisfy { $0.message.contains("destination has type") })
    }

    @Test
    func acceptsCollectionAndMapDestinationsForTheirOverloads() throws {
        let ctx = makeContextFromSource("""
        fun validDestinations() {
            listOf(1, 2).filterTo(mutableListOf()) { it > 0 }
            listOf(1, 2).associateTo(mutableMapOf<Int, Int>()) { it to it * 3 }
            mapOf(1 to 2).filterTo(mutableMapOf<Int, Int>()) { it.value > 0 }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected valid destination overloads to type-check, got: \(errors)")
    }
}
