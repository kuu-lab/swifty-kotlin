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
    func bulkOverridesMatchNestedGenericInterfaceParameters() throws {
        let ctx = makeContextFromSource("""
        abstract class BulkList : AbstractMutableList<Int>() {
            override fun addAll(elements: Collection<Int>): Boolean = true
            override fun addAll(index: Int, elements: Collection<Int>): Boolean = true
            override fun removeAll(elements: Collection<Int>): Boolean = true
            override fun retainAll(elements: Collection<Int>): Boolean = true
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let owner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("BulkList")]))
        let interfaceFQName = ["kotlin", "collections", "MutableList"].map(ctx.interner.intern)
        for (name, arity) in [("addAll", 1), ("addAll", 2), ("removeAll", 1), ("retainAll", 1)] {
            let interfaceMethod = try #require(sema.symbols.lookupAll(fqName: interfaceFQName + [ctx.interner.intern(name)]).first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes.count == arity
            })
            let implementation = try #require(kirFindOverrideMethod(
                for: interfaceMethod,
                in: owner,
                sema: sema,
                interner: ctx.interner
            ))
            #expect(sema.symbols.parentSymbol(for: implementation) == owner)
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
