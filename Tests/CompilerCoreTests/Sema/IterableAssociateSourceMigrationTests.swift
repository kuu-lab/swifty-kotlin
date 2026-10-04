#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-964: Iterable association functions are ordinary bundled Kotlin
/// declarations and must not replace the existing List association owner.
@Suite
struct IterableAssociateSourceMigrationTests {
    @Test(arguments: [
        ("Set<String>", "setOf(\"a\", \"bb\")", "kotlin.collections.Iterable"),
        ("MutableSet<String>", "mutableSetOf(\"a\", \"bb\")", "kotlin.collections.Iterable"),
        ("Iterable<String>", "listOf(\"a\", \"bb\").asIterable()", "kotlin.collections.Iterable"),
        ("Collection<String>", "setOf(\"a\", \"bb\")", "kotlin.collections.Iterable"),
        ("Set<String>", "mapOf(\"a\" to 1, \"bb\" to 2).keys", "kotlin.collections.Iterable"),
        ("Array<out String>", "arrayOf(\"a\", \"bb\")", "kotlin.Array"),
        ("List<String>", "listOf(\"a\", \"bb\")", "kotlin.collections.List"),
    ])
    func associationReceiversBindThroughKIR(receiverType: String, factory: String, owner: String) throws {
        let source = """
        fun probe(values: \(receiverType)) {
            val a: Map<String, String> = values.associate { it to it }
            val b: Map<String, String> = values.associateBy { it }
            val c: Map<String, Int> = values.associateBy({ it }, { it.length })
            val d: Map<String, Int> = values.associateWith { it.length }
            val e: MutableMap<String, String> = values.associateTo(mutableMapOf()) { it to it }
            val f: MutableMap<String, String> = values.associateByTo(mutableMapOf()) { it }
            val g: MutableMap<String, Int> = values.associateByTo(mutableMapOf(), { it }, { it.length })
            val h: MutableMap<String, Int> = values.associateWithTo(mutableMapOf()) { it.length }
        }
        fun main() {
            \(factory).associate { it to it }
            \(factory).associateBy { it }
            \(factory).associateBy({ it }, { it.length })
            \(factory).associateWith { it.length }
            \(factory).associateTo(mutableMapOf()) { it to it }
            \(factory).associateByTo(mutableMapOf()) { it }
            \(factory).associateByTo(mutableMapOf(), { it }, { it.length })
            \(factory).associateWithTo(mutableMapOf()) { it.length }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Association calls failed: \(ctx.diagnostics.diagnostics.map(\.message))")
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            var callCount = 0
            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, name, _, _, _) = ast.arena.expr(id),
                      ctx.interner.resolve(name).hasPrefix("associate") else { continue }
                callCount += 1
                let callee = try #require(sema.bindings.callBinding(for: id)?.chosenCallee)
                #expect(sema.symbols.isSourceBackedSymbol(callee))
                #expect(sema.symbols.externalLinkName(for: callee) == nil)
                let signature = try #require(sema.symbols.functionSignature(for: callee))
                let receiver = try #require(signature.receiverType)
                guard case let .classType(receiverClass) = sema.types.kind(of: sema.types.makeNonNullable(receiver)),
                      let symbol = sema.symbols.symbol(receiverClass.classSymbol) else {
                    Issue.record("Expected a nominal source extension receiver")
                    continue
                }
                #expect(symbol.fqName.map(ctx.interner.resolve).joined(separator: ".") == owner)
            }
            #expect(callCount == 16)
        }
    }

    @Test
    func iterableAssociationFamilyUsesBundledSourceAndPreservesListOwner() throws {
        let source = """
        fun probe(
            iterable: Iterable<String>,
            custom: Iterable<String>,
            list: List<String>,
            destination: MutableMap<Any?, Any?>
        ) {
            iterable.associate { Pair(it, it.length) }
            iterable.associateBy { it }
            iterable.associateBy({ it }, { it.length })
            iterable.associateByTo(destination) { it }
            iterable.associateByTo(destination, { it }, { it.length })
            iterable.associateTo(destination) { Pair(it, it.length) }
            iterable.associateWith { it.length }
            iterable.associateWithTo(destination) { it.length }
            custom.associate { Pair(it, it.length) }
            list.associate { Pair(it, it.length) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Iterable association calls to type-check cleanly, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let associationNames = Set([
                "associate", "associateBy", "associateByTo", "associateTo", "associateWith", "associateWithTo",
            ])
            let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(exprID),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, callee, _, _, _) = ast.arena.expr(exprID),
                      associationNames.contains(ctx.interner.resolve(callee))
                else {
                    return nil
                }
                return exprID
            }
            #expect(calls.count == 10)

            var owners: [String: Int] = [:]
            for call in calls {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: call)?.chosenCallee,
                    "Expected a Sema binding for Iterable association call"
                )
                #expect(sema.symbols.isSourceBackedSymbol(chosenCallee))
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                let receiverType = sema.types.makeNonNullable(try #require(signature.receiverType))
                guard case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                else {
                    Issue.record("Expected an association extension receiver")
                    continue
                }
                let owner = receiverSymbol.fqName.map(ctx.interner.resolve).joined(separator: ".")
                owners[owner, default: 0] += 1
            }

            #expect(owners["kotlin.collections.Iterable"] == 9)
            #expect(owners["kotlin.collections.List"] == 1)

            let expectedSourceCounts = [
                "associate": 1,
                "associateBy": 2,
                "associateByTo": 2,
                "associateTo": 1,
                "associateWith": 1,
                "associateWithTo": 1,
            ]
            for (name, expectedCount) in expectedSourceCounts {
                let fqName = ["kotlin", "collections", name].map(ctx.interner.intern)
                let iterableSources = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          sema.symbols.isSourceBackedSymbol(symbolID),
                          sema.symbols.externalLinkName(for: symbolID) == nil,
                          let fileID = sema.symbols.sourceFileID(for: symbolID),
                          ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/Iterables.kt",
                          let receiverType = sema.symbols.functionSignature(for: symbolID)?.receiverType,
                          case let .classType(receiverClass) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                          let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
                    else {
                        return false
                    }
                    return receiverSymbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "Iterable"]
                }
                #expect(iterableSources.count == expectedCount, "Unexpected Iterable.\(name) source overload count")
            }
        }
    }
}
#endif
