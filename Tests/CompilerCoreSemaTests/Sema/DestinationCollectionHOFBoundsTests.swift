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
