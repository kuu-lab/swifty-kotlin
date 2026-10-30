#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct CollectionBuilderExpectedTypeTests {
    private func bfsSource(builder: String) -> String {
        """
        data class Point(val x:Int,val y:Int)
        fun map():Map<Point,Int> = \(builder) {val queue=ArrayDeque<Pair<Point,Int>>().apply {add(Point(0,0) to 0)};while(queue.isNotEmpty()){queue.removeFirst().let {(location,distance)->if(location !in this){this[location]=distance}}}}
        fun main(){println(map().values)}
        """
    }

    // KUU-1912: retain the map receiver across apply's receiver and let's
    // ordinary, destructured parameter scope, including Unit coercion.
    @Test(arguments: ["buildMap", "buildMap<Point,Int>"])
    func bfsRetainsExpectedMapTypeAndNestedScopes(builder: String) throws {
        try withTemporaryFile(contents: bfsSource(builder: builder)) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let point = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Point")]))
            let pointType = sema.types.make(.classType(ClassType(
                classSymbol: point, args: [], nullability: .nonNull
            )))
            let call = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "buildMap"
            })
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(binding.substitutedTypeArguments == [pointType, sema.types.intType])

            // Inspect typechecked operations; normalization also leaves unused
            // copies of the destructured lambda's operations in the arena.
            let operations = allExprIDs(in: ast, path: path, ctx: ctx) { exprID, expr in
                guard sema.bindings.exprType(for: exprID) != nil else { return false }
                switch expr {
                case let .notInExpr(_, receiver, _), let .indexedAssign(receiver, _, _, _):
                    if case .thisRef = ast.arena.expr(receiver) { return true }
                    return false
                default:
                    return false
                }
            }
            var receivers: [ExprID] = []
            var components: [ExprID] = []
            for operation in operations {
                switch ast.arena.expr(operation) {
                case let .notInExpr(location, receiver, _):
                    receivers.append(receiver)
                    components.append(location)
                case let .indexedAssign(receiver, indices, distance, _):
                    receivers.append(receiver)
                    components.append(contentsOf: indices + [distance])
                default:
                    break
                }
            }
            #expect(receivers.count == 2)
            for receiver in receivers {
                let type = try #require(sema.bindings.exprType(for: receiver))
                guard case let .classType(map) = sema.types.kind(of: type) else {
                    Issue.record("Expected the buildMap receiver inside let")
                    continue
                }
                #expect(sema.symbols.symbol(map.classSymbol)?.fqName.last == ctx.interner.intern("MutableMap"))
                #expect(map.args == [.invariant(pointType), .invariant(sema.types.intType)])
            }

            #expect(components.count == 3)
            for component in components {
                guard case let .nameRef(name, _) = ast.arena.expr(component) else { continue }
                let expected = ctx.interner.resolve(name) == "location" ? pointType : sema.types.intType
                #expect(sema.bindings.exprType(for: component) == expected)
            }
        }
    }

    @Test(arguments: [
        "fun values(): Map<String,Int> = buildMap {}",
        "fun values(): Map<String,Int> = buildMap<String,Int> {}",
        "fun values(): Map<String,Int> = buildMap { val key = \"key\"; put(key, 1) }",
        "fun values(): List<String> = buildList { mutableListOf<Int>().apply { add(1) } }",
        "fun values(): Set<String> = buildSet<String> { mutableListOf<Int>().apply { add(1) } }",
    ])
    func fixedTypesSurviveEmptyOrUnrelatedMutationScan(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "this[\"wrong\"] = distance",
        "this[location] = \"wrong\"",
        "val wrong: String = distance",
    ])
    func bfsStillRejectsIncompatibleKeysValuesAndComponents(statement: String) throws {
        let source = bfsSource(builder: "buildMap<Point,Int>")
            .replacingOccurrences(of: "this[location]=distance", with: statement)
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [[], ["new-inference"]])
    func contextualTypeCannotReplaceExplicitInvariantKey(flags: [String]) throws {
        let ctx = makeContextFromSource("""
        fun invalid(): Map<Any,Int> = buildMap<String,Int> { put("key", 1) }
        """, frontendFlags: flags)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test(arguments: [[], ["new-inference"]])
    func ordinaryUnitExpectedTypeInfersBuilderResult(flags: [String]) throws {
        let ctx = makeContextFromSource("""
        fun <T> produce(block: MutableList<T>.() -> Unit): T = TODO()
        fun result(): Unit = produce {}
        """, frontendFlags: flags)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: ["Int", "Any", "String"])
    func contextualInferenceChecksGenericUpperBound(element: String) throws {
        let value = element == "String" ? "\"wrong\"" : "1"
        let ctx = makeContextFromSource("""
        fun <T : Number> bounded(action: MutableList<T>.() -> Unit): List<T> = TODO()
        fun bounded(n: Int) {}
        fun result(): List<\(element)> = bounded { while (false) { add(\(value)) } }
        """)
        try runSema(ctx)
        if element != "String" {
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        } else {
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test
    func contextualInferenceFollowsDependentUpperBounds() throws {
        let ctx = makeContextFromSource("""
        fun <N : Number, T : N> bounded(action: MutableList<T>.() -> Unit): List<T> = TODO()
        fun bounded(n: Int) {}
        fun result(): List<Any> = bounded { while (false) { add(1) } }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    /// `MutableList`/`ArrayList` are invariant, so the target's element type
    /// must win over the lub of the arguments whenever every argument conforms
    /// to it; `mutableListOf`/`arrayListOf` used to infer `Int` here.
    @Test(arguments: [
        "val xs: MutableList<Number> = mutableListOf(77)",
        "val xs: MutableList<Any> = mutableListOf(1)",
        "val xs: MutableList<Any?> = mutableListOf(1, \"s\")",
        "val xs: ArrayList<Any> = arrayListOf(1)",
        "val xs: MutableList<Number> = mutableListOf(1, 2L)",
    ])
    func mutableListFactoriesAdoptConformingInvariantTargetElementType(declaration: String) throws {
        let ctx = makeContextFromSource("fun probe() { \(declaration) }")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(declaration): \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "val xs: MutableList<String> = mutableListOf(1)",
        "val xs: ArrayList<String> = arrayListOf(1, \"s\")",
    ])
    func mutableListFactoriesStillRejectNonConformingTargetElementType(declaration: String) throws {
        let ctx = makeContextFromSource("fun probe() { \(declaration) }")
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "\(declaration) must stay a type error")
    }
}
#endif
