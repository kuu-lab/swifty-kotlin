@testable import CompilerCore
import Testing

@Suite
struct MutableListDispatchContractTests {
    @Test
    func sourceMembersKeepStableBridgeSlots() throws {
        let ctx = makeContextFromSource("fun probe(list: MutableList<Int>) = list.listIterator()")
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "collections", "MutableList"].map(ctx.interner.intern)
        let owner = try #require(sema.symbols.lookup(fqName: fqName))
        let layout = try #require(sema.symbols.nominalLayout(for: owner))
        let slots: [(String, Int)] = [
            ("subList", 2), ("set", 2), ("add", 1), ("add", 2),
            ("addAll", 1), ("addAll", 2), ("removeAt", 1), ("remove", 1),
            ("clear", 0), ("removeAll", 1), ("retainAll", 1),
            ("listIterator", 0), ("listIterator", 1),
        ]
        for (slot, (name, arity)) in slots.enumerated() {
            let member = try #require(sema.symbols.lookupAll(fqName: fqName + [ctx.interner.intern(name)]).first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes.count == arity
            })
            #expect(sema.symbols.isSourceBackedSymbol(member))
            #expect(sema.symbols.symbol(member)?.flags.contains(.synthetic) == false)
            #expect(layout.vtableSlots[member] == slot, "\(name)/\(arity) must use slot \(slot)")
        }
    }

    @Test
    func removeUsesOrdinaryMemberAndExtensionSelection() throws {
        let ctx = makeContextFromSource("""
        @file:Suppress("DEPRECATION_ERROR")
        abstract class ThrowingList : AbstractMutableList<Int>() {
            override fun remove(element: Int): Boolean { throw IllegalStateException("remove") }
        }
        fun probe(list: MutableList<Int>, array: ArrayList<Int>, custom: ThrowingList) {
            list.remove(1)
            list.remove(index = 1)
            list.removeAll { it == 1 }
            list.retainAll { it == 1 }
            array.remove(1)
            custom.remove(1)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let expectedOwners = [
            "list.remove(1)": "kotlin.collections.MutableList",
            "list.remove(index = 1)": "kotlin.collections",
            "list.removeAll { it == 1 }": "kotlin.collections",
            "list.retainAll { it == 1 }": "kotlin.collections",
            "array.remove(1)": "kotlin.collections.ArrayList",
            "custom.remove(1)": "ThrowingList",
        ]
        var checked = Set<String>()
        for (index, expr) in ast.arena.exprs.enumerated() {
            guard case .memberCall = expr else { continue }
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id) else { continue }
            let source = String(ctx.sourceManager.slice(range))
            guard let expectedOwner = expectedOwners[source] else { continue }
            let binding = try #require(sema.bindings.callBinding(for: id))
            let callee = try #require(sema.symbols.symbol(binding.chosenCallee))
            let owner = callee.fqName.dropLast().map(ctx.interner.resolve).joined(separator: ".")
            #expect(owner == expectedOwner)
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            checked.insert(source)
        }
        #expect(checked == Set(expectedOwners.keys))
    }
}
