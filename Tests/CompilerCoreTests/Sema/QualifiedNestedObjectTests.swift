@testable import CompilerCore
import Foundation
import Testing

@Suite
struct QualifiedNestedObjectTests {
    @Test(arguments: ["class", "interface"])
    func resolvesNestedSingletonThroughPackage(ownerKind: String) throws {
        try withTemporaryFile(contents: """
        package sample
        \(ownerKind) Holder { object Nested { fun run() {} } }
        fun use() { sample.Holder.Nested.run() }
        """) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let ast = try #require(context.ast)
            let sema = try #require(context.sema)
            let nested = try #require(sema.symbols.lookup(fqName: ["sample", "Holder", "Nested"].map(context.interner.intern)))
            let accesses = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, name, _, _, _) = ast.arena.expr(id),
                      name == context.interner.intern("Nested") else { return nil }
                return id
            }
            #expect(accesses.count == 1)
            #expect(accesses.allSatisfy { sema.bindings.identifierSymbol(for: $0) == nested && sema.bindings.isFQNQualifiedValueExpr($0) })
        }
    }

    @Test
    func anObjectShadowingTheRootPackageKeepsItsReceiver() throws {
        let sources = [
            "/tmp/qualified-nested-library.kt": "package library\ninterface Holder { object Nested { fun run() {} } }",
            "/tmp/qualified-nested-client.kt": """
            package client
            class Item { fun run() {} }
            class Container { val Nested = Item() }
            object library { val Holder = Container() }
            fun use() { library.Holder.Nested.run() }
            """,
        ]
        let options = CompilerOptions(moduleName: "Shadow", inputs: sources.keys.sorted(), outputPath: "/tmp/unused-qualified-nested",
                                      emit: .kirDump, target: defaultTargetTriple(), includeStdlib: false)
        let context = CompilerDriver().runFrontend(options: options, inMemorySources: sources.mapValues { Data($0.utf8) }).context
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        let ast = try #require(context.ast)
        let sema = try #require(context.sema)
        let expected = try #require(sema.symbols.lookup(fqName: ["client", "Item", "run"].map(context.interner.intern)))
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, name, _, _, _) = ast.arena.expr(id),
                  name == context.interner.intern("run") else { return nil }
            return id
        }
        #expect(calls.count == 1)
        #expect(calls.allSatisfy { sema.bindings.callBinding(for: $0)?.chosenCallee == expected })
    }

    @Test
    func aGlobalValueShadowingThePackageKeepsItsReceiver() throws {
        try withTemporaryFile(contents: """
        package sample
        interface Holder { object Nested { fun run() {} } }
        class Item { fun run() {} }
        class Container { val Nested = Item() }
        class Receiver { val Holder = Container() }
        val sample = Receiver()
        fun use() { sample.Holder.Nested.run() }
        """) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let ast = try #require(context.ast)
            let sema = try #require(context.sema)
            let expected = try #require(sema.symbols.lookup(fqName: ["sample", "Item", "run"].map(context.interner.intern)))
            let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let id = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, name, _, _, _) = ast.arena.expr(id),
                      name == context.interner.intern("run") else { return nil }
                return id
            }
            #expect(calls.count == 1)
            #expect(calls.allSatisfy { sema.bindings.callBinding(for: $0)?.chosenCallee == expected })
        }
    }

    @Test
    func privateIntermediateOwnerRemainsInaccessible() throws {
        try withTemporaryFile(contents: """
        package sample
        class Holder { private class Hidden { object Nested { fun run() {} } } }
        fun use() { sample.Holder.Hidden.Nested.run() }
        """) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(context.diagnostics.hasError)
        }
    }

    @Test
    func privateNestedSingletonRemainsInaccessible() throws {
        try withTemporaryFile(contents: """
        package sample
        interface Holder { private object Nested { fun run() {} } }
        fun use() { sample.Holder.Nested.run() }
        """) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(context.diagnostics.hasError)
        }
    }
}
