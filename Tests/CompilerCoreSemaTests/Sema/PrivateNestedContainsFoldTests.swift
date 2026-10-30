@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct PrivateNestedContainsFoldTests {
    @Test(arguments: ["{ 3L in it }", "{ range -> 3L in range }"])
    func cachedPredicateRetainsGenericReceiverSubstitution(predicate: String) throws {
        let source = """
        interface Values<T>
        interface SpecificValues<T> : Values<T>
        fun <T> SpecificValues<T>.firstOrNull(): T? = null
        fun <T> Values<T>.firstOrNull(predicate: (T) -> Boolean): T? = null
        class Solver {
            private class Range(val start: Long) {
                operator fun contains(n: Long) = n == start
                fun translate(n: Long) = n + 10L
            }
            private val ranges: SpecificValues<Range> = null!!
            fun solve(): Long = ranges.firstOrNull \(predicate)?.translate(3L) ?: 3L
        }
        """
        let path = "__cached_receiver_predicate.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        try expectPredicateBindings(in: ctx, nested: true)
    }

    @Test(arguments: [false, true], ["{ acc in it }", "{ range -> acc in range }", "{ it.contains(acc) }"])
    func nestedPredicatePreservesElementType(nested: Bool, predicate: String) throws {
        let ctx = makeContextFromSource(program(nested: nested, predicate: predicate))
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        try expectPredicateBindings(in: ctx, nested: nested)
    }

    @Test(arguments: [false, true])
    func emptySetRetainsPrivateNestedElementType(explicitPropertyType: Bool) throws {
        let source = program(nested: true, predicate: "{ acc in it }", elements: "emptySet<Range>()")
        let ctx = makeContextFromSource(explicitPropertyType
            ? source.replacingOccurrences(of: "private val maps=", with: "private val maps:List<Set<Range>> = ")
            : source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        try expectPredicateBindings(in: ctx, nested: true)
    }

    @Test(
        arguments: ["Int", "String", "Boolean"],
        [
            ("{ wrong in it }", "KSWIFTK-TYPE-0001"),
            ("{ it.contains(wrong) }", "KSWIFTK-SEMA-0002"),
        ]
    )
    func nonLongContainsArgumentsRemainRejected(
        argumentType: String,
        predicateCase: (predicate: String, expectedCode: String)
    ) throws {
        let (predicate, expectedCode) = predicateCase
        let source = program(nested: true, predicate: predicate)
            .replacingOccurrences(of: "fun solve():Long", with: "fun solve(wrong:\(argumentType)):Long")
            .replacingOccurrences(of: "fun main(){println(Solver().solve())}", with: "")
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1)
        #expect(errors.allSatisfy { $0.code == expectedCode },
                "Reject the contains operand after resolving the predicate parameter: \(errors)")
        try expectPredicateBindings(in: ctx, nested: true, containsIsValid: false)
    }

    private func program(nested: Bool, predicate: String, elements: String = "setOf(Range(3L))") -> String {
        let range = "private data class Range(val start:Long) { operator fun contains(n:Long)=n==start; fun translate(n:Long)=n+10L }"
        return """
        \(nested ? "class Solver { " + range : range + "\nclass Solver {")
        private val maps=listOf(\(elements))
        fun solve():Long=maps.fold(3L){acc,ranges->ranges.firstOrNull \(predicate)?.translate(acc) ?: acc} }
        fun main(){println(Solver().solve())}
        """
    }

    private func expectPredicateBindings(
        in ctx: CompilationContext, nested: Bool, containsIsValid: Bool = true
    ) throws {
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let ownerName = nested ? ["Solver", "Range"] : ["Range"]
        let rangeSymbol = try #require(sema.symbols.lookup(fqName: ownerName.map(ctx.interner.intern)))
        let rangeType = sema.types.make(.classType(ClassType(classSymbol: rangeSymbol)))
        var searchCalls = 0
        var containsCalls = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let sourceRange = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: sourceRange.start.file) == .user,
                  let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee)
            else { continue }
            if ctx.interner.resolve(symbol.name) == "firstOrNull" {
                let resultType = sema.bindings.exprType(for: id)
                let expectedType = sema.types.makeNullable(rangeType)
                #expect(resultType == expectedType)
                #expect(binding.substitutedTypeArguments == [rangeType])
                searchCalls += 1
            } else if ctx.interner.resolve(symbol.name) == "contains" {
                #expect(symbol.fqName.map(ctx.interner.resolve) == ownerName + ["contains"])
                containsCalls += 1
            }
        }
        #expect(searchCalls == 1)
        #expect(containsCalls == (containsIsValid ? 1 : 0))
    }
}
