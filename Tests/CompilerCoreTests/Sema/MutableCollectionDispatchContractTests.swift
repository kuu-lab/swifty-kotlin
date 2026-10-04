@testable import CompilerCore
import Testing

@Suite
struct MutableCollectionDispatchContractTests {
    @Test
    func sourceMutationMembersKeepBridgeSlotsAndBindings() throws {
        let ctx = makeContextFromSource("""
        fun probe(values: MutableCollection<Int>) {
            values.add(1)
            values.addAll(listOf(2))
            values.clear()
            values.remove(1)
            values.removeAll(listOf(2))
            values.retainAll(listOf(3))
            values.iterator()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let ownerFQName = ["kotlin", "collections", "MutableCollection"].map(ctx.interner.intern)
        let owner = try #require(sema.symbols.lookup(fqName: ownerFQName))
        let layout = try #require(sema.symbols.nominalLayout(for: owner))
        let members = ["add", "addAll", "clear", "remove", "removeAll", "retainAll"]
        for (slot, name) in members.enumerated() {
            let member = try #require(sema.symbols.lookup(fqName: ownerFQName + [ctx.interner.intern(name)]))
            #expect(sema.symbols.isSourceBackedSymbol(member))
            #expect(sema.symbols.symbol(member)?.flags.contains(.synthetic) == false)
            #expect(layout.vtableSlots[member] == slot)
            #expect(sema.symbols.externalLinkName(for: member) == "__kk_mutable_collection_\(name)")
        }
        let ast = try #require(ctx.ast)
        var bound = Set<String>()
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case let .memberCall(_, name, _, _, _) = expr,
                  members.contains(ctx.interner.resolve(name)),
                  let binding = sema.bindings.callBinding(for: ExprID(rawValue: Int32(index))),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  symbol.fqName.dropLast().elementsEqual(ownerFQName)
            else { continue }
            bound.insert(ctx.interner.resolve(name))
        }
        #expect(bound == Set(members))
    }
}
