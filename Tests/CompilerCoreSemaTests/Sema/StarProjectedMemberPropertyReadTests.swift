#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct StarProjectedMemberPropertyReadTests {
    @Test func boundedCovariantPropertyReadKeepsDeclaredUpperBound() throws {
        let ctx = makeContextWithoutStdlib("""
        open class LockFreeLinkedListNode(val s: String)
        private class SendBuffered(s: String) : LockFreeLinkedListNode(s)
        open class AddLastDesc2<out T : LockFreeLinkedListNode>(val node: T)
        typealias AddLastDesc<T> = AddLastDesc2<T>
        fun describeSendBuffered(): AddLastDesc<*> {
            return object : AddLastDesc<SendBuffered>(SendBuffered("OK")) {}
        }
        fun read(box: AddLastDesc<*>): String = box.node.s
        fun readConcrete(box: AddLastDesc<LockFreeLinkedListNode>): String = box.node.s
        fun <T : LockFreeLinkedListNode> readGeneric(box: AddLastDesc<T>): String = box.node.s
        fun readFixture(): String = describeSendBuffered().node.s
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let nodeAccess = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, name, _, args, _) = expr else { return false }
            return args.isEmpty && ctx.interner.resolve(name) == "node"
        })
        let nodeType = try #require(sema.bindings.exprType(for: nodeAccess))
        let upperBound = sema.types.capturedReadableUpperBound(of: nodeType)
        guard case let .classType(nodeClass) = sema.types.kind(of: upperBound),
              sema.symbols.symbol(nodeClass.classSymbol)?.fqName.last
                == ctx.interner.intern("LockFreeLinkedListNode")
        else {
            Issue.record(
                "expected AddLastDesc<*>.node to retain LockFreeLinkedListNode as its readable upper bound"
            )
            return
        }

        let propertyAccess = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, name, _, args, _) = expr else { return false }
            return args.isEmpty && ctx.interner.resolve(name) == "s"
        })
        #expect(sema.bindings.exprType(for: propertyAccess) == sema.types.stringType)
    }

    @Test func starProjectedPropertyReadKeepsIntersectionOfUpperBounds() throws {
        let ctx = makeContextWithoutStdlib("""
        interface Named { val label: Int }
        open class Node(val s: Int)
        class Box<out T>(val node: T) where T : Node, T : Named
        fun read(box: Box<*>): Int {
            val first: Int = box.node.s
            val second: Int = box.node.label
            return first
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let nodeAccess = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, name, _, args, _) = expr else { return false }
            return args.isEmpty && ctx.interner.resolve(name) == "node"
        })
        let nodeType = try #require(sema.bindings.exprType(for: nodeAccess))
        guard case let .intersection(parts) = sema.types.kind(of: sema.types.capturedReadableUpperBound(of: nodeType))
        else {
            Issue.record("expected Box<*>.node to retain an intersection readable upper bound")
            return
        }
        let boundNames = Set(parts.compactMap { part -> String? in
            guard case let .classType(classType) = sema.types.kind(of: part),
                  let name = sema.symbols.symbol(classType.classSymbol)?.fqName.last
            else { return nil }
            return ctx.interner.resolve(name)
        })
        #expect(boundNames.contains("Node"))
        #expect(boundNames.contains("Named"))
    }

    @Test func starProjectedPropertyStillRejectsWrites() throws {
        let ctx = makeContextWithoutStdlib("""
        open class Node(val s: Int)
        class Box<T : Node>(var node: T)
        fun writeConcrete(box: Box<Node>, value: Node) { box.node = value }
        fun writeStar(box: Box<*>, value: Node) { box.node = value }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Expected only the star-projected write to fail: \(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0002" || errors.first?.code == "KSWIFTK-TYPE-0001")
    }

    @Test func starProjectedReadDoesNotExposeUnrelatedOrNullableMembers() throws {
        let unrelated = makeContextWithoutStdlib("""
        open class Node(val s: Int)
        class Other(val unrelated: Int)
        class Box<out T : Node>(val node: T)
        fun read(box: Box<*>): Int = box.node.unrelated
        """)
        try runSema(unrelated)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: unrelated)

        let nullable = makeContextWithoutStdlib("""
        open class Node(val s: Int)
        class NullableBoundBox<T : Node?>(val node: T)
        class Box<out T : Node>(val node: T)
        fun readNullableBound(box: NullableBoundBox<*>): Int = box.node.s
        fun readNullableOwner(box: Box<*>?): Int = box.node.s
        """)
        try runSema(nullable)
        let nullableErrors = nullable.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(nullableErrors.count == 2, "Expected nullable bound and owner reads to fail: \(nullableErrors)")
        #expect(nullableErrors.allSatisfy { $0.code == "KSWIFTK-SEMA-0026" })
    }

    private func makeContextWithoutStdlib(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
