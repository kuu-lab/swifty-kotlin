#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AccessorBodiedInferredPropertyPrecheckTests {
    // KUU-3800: `internal var node = set.node` on PersistentHashSetBuilder
    // declares a custom setter body. The inferred member property kept its
    // header-registered Any? placeholder until the builder's own source-order
    // pass ran, so PersistentHashSet.containsAll — checked earlier — read
    // `elements.node` as Any? and failed the TrieNode<E> argument constraint
    // with KSWIFTK-TYPE-0001. Publishing the safe initializer's type ahead of
    // the accessor bodies lets the earlier reader see TrieNode<E>; the
    // accessor bodies themselves still run in source order.
    @Test
    func customSetterInferredMemberPublishesTypeForEarlierReader() throws {
        let source = """
        class TrieNode<E> {
            fun containsAll(otherNode: TrieNode<E>, shift: Int): Boolean = true
        }
        class PersistentHashSet<E>(val node: TrieNode<E>) : HashSet<E>() {
            override fun containsAll(elements: Collection<E>): Boolean {
                if (elements is PersistentHashSetBuilder) {
                    return node.containsAll(elements.node, 0)
                }
                return false
            }
        }
        class PersistentHashSetBuilder<E>(set: PersistentHashSet<E>) : HashSet<E>() {
            var node = set.node
                private set(value) { field = value }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected the earlier member reader to see TrieNode<E>, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let node = try #require(sema.symbols.lookup(
            fqName: ["PersistentHashSetBuilder", "node"].map(interner.intern)
        ))
        let trieNode = try #require(sema.symbols.lookup(
            fqName: ["TrieNode"].map(interner.intern)
        ))
        guard case let .classType(classType) = sema.types.kind(of: sema.symbols.propertyType(for: node) ?? sema.types.errorType) else {
            Issue.record("Expected PersistentHashSetBuilder.node to keep a nominal TrieNode type")
            return
        }
        #expect(classType.classSymbol == trieNode)
    }

    @Test
    func customGetterInferredMemberPublishesTypeForEarlierReader() throws {
        let source = """
        class TrieNode<E> {
            fun containsAll(otherNode: TrieNode<E>, shift: Int): Boolean = true
        }
        class PersistentHashSet<E>(val node: TrieNode<E>) : HashSet<E>() {
            override fun containsAll(elements: Collection<E>): Boolean {
                if (elements is PersistentHashSetBuilder) {
                    return node.containsAll(elements.node, 0)
                }
                return false
            }
        }
        class PersistentHashSetBuilder<E>(set: PersistentHashSet<E>) : HashSet<E>() {
            var node = set.node
                get() = field
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected the earlier member reader to see TrieNode<E>, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func topLevelAccessorBodiedInferredPropertyPublishesType() throws {
        let source = """
        class Holder(val x: Int)
        fun read(): Int = node.x
        var node = Holder(42)
            set(value) { field = value }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected the earlier top-level reader to see Holder, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func accessorBodiesStillReportTheirOwnDiagnostics() throws {
        // The type-only publish must not swallow accessor-body diagnostics:
        // the property is re-checked in source order, so a genuinely
        // unresolved setter-body reference still reports its error.
        let source = """
        class Box(val value: Int)
        class Bag(set: Box) {
            var node = set
                set(value) { missingCall() }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(ctx.diagnostics.diagnostics.contains { $0.severity == .error })
    }
}
#endif
