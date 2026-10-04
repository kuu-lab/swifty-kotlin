@testable import CompilerCore
import Testing

@Suite
struct MutableSetBulkDispatchContractTests {
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
