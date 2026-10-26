@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct MutableSetBulkDispatchContractTests {
    @Test
    func iterableAndSequenceAddAllBindToSourceExtensions() throws {
        let ctx = makeContextFromSource("""
        fun probe(set: MutableSet<Int>, iterable: Iterable<Int>, sequence: Sequence<Int>) {
            set.addAll(iterable)
            set.addAll(sequence)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var checked = 0
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .memberCall(_, name, _, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  name == ctx.interner.intern("addAll")
            else { continue }
            let binding = try #require(sema.bindings.callBinding(for: ExprID(rawValue: Int32(index))))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "addAll"])
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            #expect(!symbol.flags.contains(.synthetic))
            #expect(sema.symbols.externalLinkName(for: binding.chosenCallee) == nil)
            checked += 1
        }
        #expect(checked == 2)
    }

    @Test
    func addAllExtensionsRejectWrongElementTypesAndProjections() throws {
        let ctx = makeContextFromSource("""
        fun wrongIterable(set: MutableSet<Int>, input: Iterable<String>) { set.addAll(input) }
        fun wrongSequence(set: MutableSet<Int>, input: Sequence<String>) { set.addAll(input) }
        fun projected(set: MutableSet<out Int>, input: Iterable<Int>) { set.addAll(input) }
        fun star(set: MutableSet<*>, input: Sequence<Int>) { set.addAll(input) }
        fun nullableElements(set: MutableSet<Int>, input: Iterable<Int?>) { set.addAll(input) }
        fun nullableInput(set: MutableSet<Int>, input: Sequence<Int>?) { set.addAll(input) }
        fun projectedHashSet(set: HashSet<out Int>, input: Iterable<Int>) { set.addAll(input) }
        fun starHashSet(set: HashSet<*>, input: Sequence<String>) { set.addAll(input) }
        fun nullableReceiver(set: MutableSet<Int>?, input: Iterable<Int>) { set.addAll(input) }
        """)
        try runSema(ctx)
        let hasError = ctx.diagnostics.hasError
        #expect(hasError)
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var checked = 0
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .memberCall(_, name, _, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  name == ctx.interner.intern("addAll")
            else { continue }
            #expect(sema.bindings.exprTypes[ExprID(rawValue: Int32(index))] == sema.types.errorType)
            checked += 1
        }
        #expect(checked == 9)
    }

    @Test
    func mutableSetSlotsPreserveExistingMutationAndBulkBridges() throws {
        let ctx = makeContextFromSource("""
        fun probe(set: MutableSet<Int>) {
            set.removeAll(listOf(1))
            set.retainAll(listOf(2))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "collections", "MutableSet"].map(ctx.interner.intern)
        let owner = try #require(sema.symbols.lookup(fqName: fqName))
        let layout = try #require(sema.symbols.nominalLayout(for: owner))
        for (slot, name) in ["add", "remove", "clear", "addAll", "removeAll", "retainAll"].enumerated() {
            let member = try #require(sema.symbols.lookup(fqName: fqName + [ctx.interner.intern(name)]))
            #expect(sema.symbols.isSourceBackedSymbol(member))
            #expect(sema.symbols.symbol(member)?.flags.contains(.synthetic) == false)
            #expect(layout.vtableSlots[member] == slot)
        }
        let ast = try #require(ctx.ast)
        var checked = Set<String>()
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .memberCall(_, name, _, _, range) = expr,
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  ["removeAll", "retainAll"].contains(ctx.interner.resolve(name))
            else { continue }
            let binding = try #require(sema.bindings.callBinding(for: ExprID(rawValue: Int32(index))))
            #expect(sema.symbols.parentSymbol(for: binding.chosenCallee) == owner)
            checked.insert(ctx.interner.resolve(name))
        }
        #expect(checked == ["removeAll", "retainAll"])
    }
}
