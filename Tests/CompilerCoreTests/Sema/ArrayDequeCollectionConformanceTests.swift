import Testing
@testable import CompilerCore

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
                ("empty", "__kk_arraydeque_new"),
                ("capacity", "__kk_arraydeque_new_with_capacity"),
                ("copy", "__kk_arraydeque_new_from_collection"),
            ] {
                let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
                let calls = extractCallees(from: body, interner: ctx.interner)
                #expect(calls.contains(factory))
                #expect(calls.contains("kk_object_register_vtable_method"))
                #expect(!calls.contains("kk_object_new"))
            }
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
            for (member, link) in [("iterator", "kk_list_iterator"), ("subList", "kk_list_subList")] {
                let symbol = try #require(sema.symbols.lookup(fqName: collections + [ctx.interner.intern("ArrayDeque"), ctx.interner.intern(member)]))
                #expect(sema.symbols.externalLinkName(for: symbol) == link)
            }
        }
    }
}
