#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericGetterNullableTraversalTests {
    @Test
    func inferredNestedNodeReturnPreservesNullableGetterTraversal() throws {
        let ctx = makeContextFromSource("""
        class Chain<T>(private var head:Node<T>?) {
        val list:List<T> get(){val nodes=mutableListOf<T>();var node=head;while(node!=null){val value=node.value();if(value!=null)nodes.add(value);node=node.next()};return nodes}
        class Node<T>(private var value:T?=null,private var previous:Node<T>?=null,private var next:Node<T>?=null){fun next()=next;fun previous()=previous;fun value()=value}}
        fun main(){val tail=Chain.Node(value=2);val head=Chain.Node(value=1,next=tail);println(Chain(head).list)}
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let chainSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Chain")]))
        let chainParameter = try #require(sema.types.nominalTypeParameterSymbols(for: chainSymbol).first)
        let nodeSymbol = try #require(sema.symbols.lookup(fqName: ["Chain", "Node"].map(ctx.interner.intern)))
        let nodeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: nodeSymbol).first)
        let nodeArgument = sema.types.make(.typeParam(TypeParamType(symbol: nodeParameter)))
        let chainArgument = sema.types.make(.typeParam(TypeParamType(symbol: chainParameter)))

        for method in ["next", "previous"] {
            let symbol = try #require(sema.symbols.lookupAll(
                fqName: ["Chain", "Node", method].map(ctx.interner.intern)
            ).first { sema.symbols.functionSignature(for: $0) != nil })
            let returnType = try #require(sema.symbols.functionSignature(for: symbol)?.returnType)
            #expect(sema.types.nullability(of: returnType) == .nullable)
            guard case let .classType(nodeType) = sema.types.kind(of: returnType) else {
                Issue.record("Expected the inferred return type to remain Node<T>?")
                continue
            }
            #expect(nodeType.classSymbol == nodeSymbol)
            #expect(nodeType.args == [.invariant(nodeArgument)])
        }

        let calls = memberCallExprIDs(named: "next", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 1)
        for call in calls {
            let type = try #require(sema.bindings.exprType(for: call))
            #expect(sema.types.nullability(of: type) == .nullable)
            guard case let .classType(nodeType) = sema.types.kind(of: type) else {
                Issue.record("Expected the getter call to resolve to Node<T>?")
                continue
            }
            #expect(nodeType.classSymbol == nodeSymbol)
            #expect(nodeType.args == [.invariant(chainArgument)])
        }
        let locals = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .localDecl(name, _, _, _, _, _, _) = ast.arena.expr(id),
                  ctx.interner.resolve(name) == "node", isUserSourceExpr(id, in: ctx)
            else { return nil }
            return id
        }
        #expect(locals.count == 1)
        for local in locals {
            let symbol = try #require(sema.bindings.identifierSymbol(for: local))
            let type = try #require(sema.symbols.propertyType(for: symbol))
            #expect(sema.types.nullability(of: type) == .nullable)
        }
    }

    @Test(arguments: [false, true])
    func forwardAndBackwardGettersAcceptNullableReassignment(explicitReturn: Bool) throws {
        let annotation = explicitReturn ? ": Node<T>?" : ""
        let ctx = contextWithoutStdlib("""
        class Chain<T>(private var head: Node<T>?) {
            val count: Int get() {
                var node = head
                var count = 0
                while (node != null) { count++; node = node.next() }
                return count
            }
            val reversedCount: Int get() {
                var node = head
                var count = 0
                while (node != null) { count++; node = node.previous() }
                return count
            }
            fun count(): Int {
                var node = head
                var count = 0
                while (node != null) { count++; node = node.next() }
                return count
            }
            class Node<T>(private var next: Node<T>?, private var previous: Node<T>?) {
                fun next()\(annotation) = next
                fun previous()\(annotation) = previous
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        ("node = node.next(); node.next()", "KSWIFTK-SEMA-0002"),
        ("var required: Node<T> = node; required = node.next()", "KSWIFTK-SEMA-0470"),
        ("val fixed = node; fixed = node.next()", "KSWIFTK-SEMA-0014"),
    ])
    func getterStillRejectsInvalidAssignmentsAndNullableReads(body: String, expected: String) throws {
        let ctx = contextWithoutStdlib("""
        class Chain<T>(private var head: Node<T>?) {
            val count: Int get() {
                var node = head
                while (node != null) { \(body); node = null }
                return 0
            }
            class Node<T>(private var next: Node<T>?) { fun next() = next }
        }
        """)
        try? runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == expected || $0.message.contains(expected) }, "\(errors)")
    }

    @Test
    func getterAndInitializerErrorsRemainAuthoritative() throws {
        let ctx = contextWithoutStdlib("""
        class Chain<T>(private var head: Node<T>?) {
            val wrongInitializer: Int = "wrong"
            val wrongGetter: Int get() = "wrong"
            val wrongReturn: Node<T> get() {
                var node = head
                while (node != null) { return node.next() }
                return head!!
            }
            class Node<T>(private var next: Node<T>?) { fun next() = next }
        }
        """)
        try? runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let errorLines = Set(errors.compactMap { diagnostic in
            diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line }
        })
        #expect(errorLines.contains(2), "\(errors)")
        #expect(errorLines.contains(3), "\(errors)")
        #expect(errorLines.contains(6), "\(errors)")
    }

    private func contextWithoutStdlib(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
