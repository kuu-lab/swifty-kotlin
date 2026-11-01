import Testing
@testable import CompilerCore
@testable import CompilerTestSupport

@Suite
struct ArrayDequeCollectionConformanceTests {
    @Test
    func runtimeConstructorsRegisterSuperclassDispatch() throws {
        let source = """
        fun empty(): ArrayDeque<Int> = ArrayDeque<Int>()
        fun capacity(): ArrayDeque<Int> = ArrayDeque<Int>(8)
        fun copy(values: Collection<Int>): ArrayDeque<Int> = ArrayDeque<Int>(values)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)
            for (name, factory) in [
                ("empty", runtimeABIName(.arrayDequeNew)),
                ("capacity", runtimeABIName(.arrayDequeNewWithCapacity)),
                ("copy", runtimeABIName(.arrayDequeNewFromCollection)),
            ] {
                let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
                let calls = extractCallees(from: body, interner: ctx.interner)
                #expect(calls.contains(factory))
                #expect(calls.contains(runtimeABIName(.objectRegisterVtableMethod)))
                #expect(!calls.contains(runtimeABIName(.objectNew)))
            }
        }
    }

    /// KUU-4100: `toCollection`'s destination parameter is bounded by
    /// `C : MutableCollection<in T>`. An argument-less `ArrayDeque()` has no
    /// own argument to fix `E`, so the collection-flow special must hand the
    /// nested call the `MutableCollection<in E>` bound as its expected type —
    /// otherwise inference fails outright or silently collapses the element
    /// to `Nothing`/`Any` the way `mutableListOf()`/`ArrayList()` did.
    @Test
    func toCollectionDestinationInfersElementTypeFromReceiver() throws {
        let source = """
        fun destinations() {
            val deque: ArrayDeque<Int> = listOf(1, 2).toCollection(ArrayDeque())
            val capacity: ArrayDeque<Int> = listOf(1, 2).toCollection(ArrayDeque(4))
            val list: MutableList<Int> = listOf(1, 2).toCollection(mutableListOf())
            val arrayList: MutableList<Int> = listOf(1, 2).toCollection(ArrayList())
            val set: MutableSet<Int> = listOf(1, 2).toCollection(mutableSetOf())
            val chars: ArrayDeque<Char> = "ab".toCollection(ArrayDeque())
            val fromSequence = sequenceOf(1, 2).toCollection(ArrayDeque())
            fromSequence.add(3)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected toCollection destinations to infer cleanly, got: \(errors)")
        }
    }

    @Test
    func hierarchyAndCollectionExtensionsPreserveElementTypes() throws {
        let source = """
        fun <T> copy(values: Iterable<T>): List<T> = values.toList()
        fun inspect(d: ArrayDeque<Int>) {
            val l: List<Int> = d
            val m: MutableList<Int> = d
            val c: Collection<Int> = d
            val i: Iterable<Int> = d
            val a: AbstractMutableList<Int> = d
            val next: Int = d.iterator().next()
            val mapped: List<Int> = d.map { it * 2 }
            val filtered: List<Int> = d.filter { it > 0 }
            val element: Int = d.elementAt(0)
            val nullable: Int? = d.getOrNull(9)
            val fallback: Int = d.getOrElse(9) { 42 }
            val total: Int = d.sum()
            val copied: List<Int> = copy(d)
            d.iterator().remove()
            d.listIterator(1).set(3)
            d.subList(0, 1).add(4)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected ArrayDeque collection conformance, got: \(errors)")
            let sema = try #require(ctx.sema)
            let collections = ["kotlin", "collections"].map(ctx.interner.intern)
            let deque = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("ArrayDeque")]))
            let base = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("AbstractMutableList")]))
            #expect(sema.symbols.directSupertypes(for: deque).contains(base))
            #expect(sema.symbols.supertypeTypeArgs(for: deque, supertype: base).count == 1)
            #expect(sema.types.nominalTypeParameterVariances(for: deque) == [.invariant])
            let info = try #require(sema.symbols.symbol(deque))
            #expect(!info.flags.contains(.synthetic))
            for (member, link) in [("iterator", runtimeABIName(.listIterator)), ("subList", runtimeABIName(.listSubList))] {
                let symbol = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("ArrayDeque"), ctx.interner.intern(member)]))
                #expect(sema.symbols.externalLinkName(for: symbol) == link)
            }
        }
    }
}
