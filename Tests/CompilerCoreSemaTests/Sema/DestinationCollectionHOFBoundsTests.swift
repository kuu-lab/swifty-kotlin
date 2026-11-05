@testable import CompilerCore
import Foundation
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
        let boundErrors = errors.filter { $0.code == "KSWIFTK-SEMA-0473" }
        #expect(boundErrors.count == 3, "Expected one destination-bound error per invalid call, got: \(errors)")
        #expect(boundErrors.allSatisfy { $0.message.contains("destination has type") })
        // KUU-4002: the two bare factories (`emptyList()`, `mutableListOf()`)
        // carry no inference evidence, so they also report
        // KSWIFTK-SEMA-INFER — kotlinc emits the matching "cannot infer type
        // for type parameter" next to each destination mismatch.
        let inferErrors = errors.filter { $0.code == "KSWIFTK-SEMA-INFER" }
        #expect(inferErrors.count == 2, "Expected inference errors only for the bare factories, got: \(errors)")
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

    /// KUU-3917: `ArrayList(capacity)` has no argument that mentions its element
    /// type parameter, so the standalone pass fixed `E := Any`. The destination
    /// bound `C : MutableCollection<in T>` has to steer it back to
    /// `ArrayList<String>` — kotlinc keeps `E` in the enclosing constraint set
    /// instead, where `ArrayList<E> <: MutableCollection<in String>`
    /// contributes `String <: E`. The `values[entry.key] = list` assignment
    /// below only type-checks when `list` is `MutableList<String>`.
    @Test
    func capacityConstructorDestinationBindsElementThroughContravariantBound() throws {
        try withTemporaryFile(contents: """
        fun filter(entries: Set<Map.Entry<String, List<String>>>,
                   keepEmpty: Boolean,
                   predicate: (String, String) -> Boolean) {
            val values: MutableMap<String, MutableList<String>> = LinkedHashMap(entries.size)
            entries.forEach { entry ->
                val list = entry.value.filterTo(ArrayList(entry.value.size)) { predicate(entry.key, it) }
                if (keepEmpty || list.isNotEmpty()) {
                    values[entry.key] = list
                }
            }
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected the KUU-3917 reproducer to type-check, got: \(errors)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let callID = try #require(memberCallExprIDs(
                named: "filterTo",
                in: ast,
                path: path,
                ctx: ctx,
                interner: ctx.interner
            ).first)
            let resultType = try #require(sema.bindings.exprType(for: callID))
            guard case let .classType(classType) = sema.types.kind(of: resultType) else {
                Issue.record("Expected filterTo to return a class type, got \(sema.types.renderType(resultType))")
                return
            }
            #expect(
                classType.args == [.invariant(sema.types.stringType)],
                "Expected filterTo destination to infer ArrayList<String>, got \(sema.types.renderType(resultType))"
            )
        }
    }

    /// The declared-type expectation participates in steering too: with the
    /// call's result contexted as `MutableCollection<Any>`, `E` is free to
    /// collapse to `Any` the same way kotlinc resolves it.
    @Test
    func declaredExpectedTypeSteersCapacityConstructorDestination() throws {
        try withTemporaryFile(contents: """
        fun loose() {
            val anyDestination: MutableCollection<Any> =
                listOf("a", "b").filterTo(ArrayList(1)) { it.isNotEmpty() }
        }

        fun strict() {
            val stringDestination: MutableCollection<String> =
                listOf("a", "b").filterTo(ArrayList(1)) { it.isNotEmpty() }
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected declared-type steering to type-check, got: \(errors)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let calls = memberCallExprIDs(named: "filterTo", in: ast, path: path, ctx: ctx, interner: ctx.interner)
            #expect(calls.count == 2)
            let expectedArgs: [[TypeArg]] = [
                [.invariant(sema.types.anyType)],
                [.invariant(sema.types.stringType)],
            ]
            for (callID, args) in zip(calls, expectedArgs) {
                let resultType = try #require(sema.bindings.exprType(for: callID))
                guard case let .classType(classType) = sema.types.kind(of: resultType) else {
                    Issue.record("Expected class type, got \(sema.types.renderType(resultType))")
                    continue
                }
                #expect(
                    classType.args == args,
                    "Unexpected inferred destination, got \(sema.types.renderType(resultType))"
                )
            }
        }
    }

    /// KUU-4292: the aggregate destination HOFs (`associateByTo`,
    /// `associateWithTo`, `groupByTo`) bound their destination as
    /// `M : MutableMap<in K, in V>` / `M : MutableMap<in K, MutableList<V>>`,
    /// so a destination outside the `MutableMap` family or whose key/value
    /// types are not supertypes of the produced types must diagnose instead
    /// of reaching lowering.
    @Test
    func aggregateDestinationHOFsRejectInvalidDestinations() throws {
        let ctx = makeContextFromSource("""
        data class User(val name: String, val age: Int)
        fun violations(users: List<User>) {
            users.associateByTo(mutableListOf<String>()) { it.name }
            users.associateByTo(mutableMapOf<String, Int>()) { it.name }
            users.associateWithTo(mutableMapOf<String, String>()) { it.name }
            users.groupByTo(mutableListOf<String>()) { it.name }
            users.groupByTo(mutableMapOf<String, List<User>>()) { it.name }
            users.groupByTo(mutableMapOf<String, ArrayList<User>>()) { it.name }
            users.groupByTo(mutableMapOf<String, MutableList<String>>(), { it.name }, { it.age })
        }
        """)
        try runSema(ctx)

        let boundErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.message.contains("destination has type")
        }
        #expect(boundErrors.count == 7, "Expected one destination-bound error per invalid call, got: \(boundErrors)")
        #expect(boundErrors.allSatisfy { $0.code == "KSWIFTK-SEMA-0473" || $0.code == "KSWIFTK-TYPE-0001" })
    }

    /// KUU-4292: valid `MutableMap` destinations — including supertyped key
    /// and value arguments, `LinkedHashMap`, deferred `mutableMapOf()`
    /// factories, and `groupByTo`'s invariant `MutableList<V>` value slot —
    /// still satisfy the aggregate destination bounds.
    @Test
    func aggregateDestinationHOFsAcceptValidDestinations() throws {
        let ctx = makeContextFromSource("""
        data class User(val name: String, val age: Int)
        fun valid(users: List<User>) {
            users.associateByTo(mutableMapOf<String, Any>()) { it.name }
            users.associateByTo(mutableMapOf<Any, User>()) { it.name }
            users.associateByTo(mutableMapOf<String, Int>(), { it.name }, { it.age })
            users.associateByTo(mutableMapOf<String, Number>(), { it.name }, { it.age })
            users.associateWithTo(mutableMapOf<User, String>()) { it.name }
            users.associateWithTo(mutableMapOf<Any, Any>()) { it.name }
            users.groupByTo(mutableMapOf<String, MutableList<User>>()) { it.name }
            users.groupByTo(mutableMapOf<String, MutableList<Int>>(), { it.name }, { it.age })
            users.groupByTo(mutableMapOf<String, MutableList<Int?>>(), { it.name }, { it.age })
            users.associateByTo(mutableMapOf()) { it.name }
            users.associateByTo(mutableMapOf(), { it.name }, { it.age })
            users.associateWithTo(mutableMapOf()) { it.name }
            users.groupByTo(mutableMapOf()) { it.name }
            users.groupByTo(mutableMapOf(), { it.name }, { it.age })
            users.associateByTo(LinkedHashMap<String, Any>()) { it.name }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected valid aggregate destinations to type-check, got: \(errors)")
    }

    /// KUU-4292: bare `mutableListOf()`/`mutableMapOf()` destination factories
    /// are re-inferred under the destination bound, so the first pass's
    /// `KSWIFTK-SEMA-INFER` must not survive a successful re-inference —
    /// kotlinc accepts every call below.
    @Test
    func deferredDestinationFactoriesDoNotReportStaleInferenceErrors() throws {
        let ctx = makeContextFromSource("""
        data class User(val name: String, val age: Int)
        fun deferred(users: List<User>) {
            users.mapTo(mutableListOf()) { it.name }
            users.mapIndexedTo(mutableListOf()) { _, u -> u.name }
            users.mapNotNullTo(mutableListOf()) { it.name }
            users.filterTo(mutableListOf()) { it.age > 20 }
            users.associateTo(mutableMapOf()) { it.name to it.age }
            val scores = mapOf("a" to 1, "b" to 2)
            scores.mapKeysTo(mutableMapOf()) { it.key + "!" }
            scores.mapValuesTo(mutableMapOf()) { it.value * 2 }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected deferred destination factories to type-check, got: \(errors)")
    }

    /// The nested-constructor reinference only loosens the destination argument;
    /// the predicate keeps its declared `(T) -> Boolean` shape so the generated
    /// call still consumes a primitive Boolean (the boxed `Any?` result used to
    /// compare `!= false` as a reference and made `filterTo` retain everything).
    @Test
    func destinationPredicateKeepsBooleanReturnType() throws {
        try withTemporaryFile(contents: """
        fun pick() {
            listOf("a", "b").filterTo(ArrayList(1)) { it.length > 1 }
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected filterTo with ArrayList destination to type-check, got: \(errors)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let lambdaID = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                if case .lambdaLiteral = expr { return true }
                return false
            })
            let lambdaType = try #require(sema.bindings.exprType(for: lambdaID))
            guard case let .functionType(functionType) = sema.types.kind(of: lambdaType) else {
                Issue.record("Expected the filterTo predicate to stay a function type, got \(sema.types.renderType(lambdaType))")
                return
            }
            #expect(
                functionType.returnType == sema.types.booleanType,
                "Expected predicate return Boolean, got \(sema.types.renderType(functionType.returnType))"
            )
            #expect(
                functionType.params == [sema.types.stringType],
                "Expected predicate param String, got \(functionType.params.map { sema.types.renderType($0) })"
            )
        }
    }
}
