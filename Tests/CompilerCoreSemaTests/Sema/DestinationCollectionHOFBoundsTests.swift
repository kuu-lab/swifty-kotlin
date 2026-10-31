@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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

    /// KUU-3955: the destination bound is contravariant
    /// (`C : MutableCollection<in T>` / `M : MutableMap<in K, in V>`), so a
    /// destination whose element type is not a *supertype* of the produced
    /// element must diagnose even though it is in the right nominal family.
    @Test
    func rejectsDestinationsViolatingTheContravariantBound() throws {
        let ctx = makeContextFromSource("""
        fun contravariantViolations() {
            listOf("a").filterTo(ArrayList<Int>(5)) { it.isNotEmpty() }
            listOf("a").mapTo(ArrayList<String>(5)) { it.length }
            mapOf(1 to "a").filterTo(mutableMapOf<Int, Int>()) { true }
        }
        """)
        try runSema(ctx)

        let boundErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.message.contains("destination has type")
        }
        #expect(boundErrors.count == 3, "Expected one contravariant bound error per call, got: \(boundErrors)")
        #expect(boundErrors.allSatisfy { $0.code == "KSWIFTK-TYPE-0001" })
        #expect(boundErrors[0].message.contains("MutableCollection<in String>"))
        #expect(boundErrors[1].message.contains("MutableCollection<in Int>"))
        #expect(boundErrors[2].message.contains("MutableMap<in Int, in String>"))
    }

    /// KUU-3955: destinations whose element types are supertypes of the
    /// produced element (incl. the `Any` top type and `Nothing`-seeded
    /// factories) still satisfy `MutableCollection<in T>` /
    /// `MutableMap<in K, in V>`.
    @Test
    func acceptsDestinationsWithSupertypeElements() throws {
        let ctx = makeContextFromSource("""
        fun supertypeDestinations() {
            listOf("a").filterTo(ArrayList<String>(5)) { it.isNotEmpty() }
            listOf("a").filterTo(ArrayList<CharSequence>(5)) { it.isNotEmpty() }
            listOf("a").filterTo(ArrayList<Any>(5)) { it.isNotEmpty() }
            listOf("a").mapTo(mutableListOf<Any>()) { it.length }
            mapOf(1 to "a").filterTo(mutableMapOf<Any, CharSequence>()) { true }
            listOf("a").associateTo(mutableMapOf<CharSequence, Number>()) { it to it.length }
            sequenceOf("x").filterNotTo(ArrayList<CharSequence>()) { true }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected supertype destinations to type-check, got: \(errors)")
    }

    /// KUU-3955: a generic `T` destination element cannot satisfy
    /// `MutableCollection<in T>` for an unrelated concrete element; the bound
    /// still applies under type parameters.
    @Test
    func rejectsContravariantViolationUnderTypeParameters() throws {
        let ctx = makeContextFromSource("""
        fun <T> genericViolation(list: List<T>, dest: ArrayList<Int>) {
            list.filterTo(dest) { true }
        }
        """)
        try runSema(ctx)

        let boundErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.message.contains("destination has type")
        }
        #expect(boundErrors.count == 1, "Expected one contravariant bound error, got: \(boundErrors)")
        #expect(boundErrors.allSatisfy { $0.code == "KSWIFTK-TYPE-0001" })
    }
}
