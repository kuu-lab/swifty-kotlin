@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ExtensionPropertyCompoundAssignTests {
    @Test
    func testCachedPostfixValueSurvivesASTSnapshot() throws {
        let ctx = makeContextFromSource("""
        class Box { var x: Int = 0 }
        var Box.y: Int
            get() = x
            set(v) { x = v }
        fun mutate(b: Box): Int = b.y++
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let snapshot = ast.arena.snapshot()
        #expect(snapshot.incrementDecrementCachedValues.count == 1)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ASTArenaSnapshot.self, from: data)
        let arena = ASTArena(snapshot: decoded)
        for (expression, cachedValue) in snapshot.incrementDecrementCachedValues {
            #expect(arena.isIncrementDecrement(expression))
            #expect(arena.incrementDecrementCachedValue(for: expression) == cachedValue)
        }
    }

    @Test
    func testExtensionPropertyCompoundAssignUsesRegisteredAccessors() throws {
        let ctx = makeContextFromSource("""
        class Box { var x: Int = 0 }
        var Box.y: Int
            get() = x
            set(v) { x = v }
        fun mutate(b: Box) {
            b.y += 2
            b.y -= 1
            b.y *= 3
            b.y /= 2
            b.y %= 5
            b.y++
            ++b.y
            b.y--
            --b.y
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let property = try #require(sema.symbols.lookupByShortName(ctx.interner.intern("y")).first {
            sema.symbols.extensionPropertyReceiverType(for: $0) != nil
        })
        let getter = try #require(sema.symbols.extensionPropertyGetterAccessor(for: property))
        let setter = try #require(sema.symbols.extensionPropertySetterAccessor(for: property))
        let body = try findKIRFunctionBody(named: "mutate", in: module, interner: ctx.interner)
        let accessorCalls = body.compactMap { instruction -> SymbolID? in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction else { return nil }
            if symbol == getter {
                #expect(arguments.count == 1)
                return getter
            }
            if symbol == setter {
                #expect(arguments.count == 2)
                return setter
            }
            return nil
        }
        #expect(accessorCalls == Array(repeating: [getter, setter], count: 6).flatMap { $0 }
            + [getter, setter, getter, getter, setter, getter, setter, getter])
        #expect(kirCalls(to: .arrayGetInbounds, in: body, interner: ctx.interner).isEmpty)
        #expect(kirCalls(to: .arraySet, in: body, interner: ctx.interner).isEmpty)
    }

    @Test(arguments: ["b.y += 1", "b.y++", "++b.y", "b.y--", "--b.y"])
    func testReadOnlyExtensionPropertyCannotBeReassigned(operation: String) throws {
        let ctx = makeContextFromSource("""
        class Box { val x: Int = 0 }
        val Box.y: Int get() = x
        fun mutate(b: Box) { \(operation) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0014" })
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0022" })
    }

    @Test
    func testReadOnlyExtensionPropertyPlusAssignDoesNotCallSetter() throws {
        let ctx = makeContextFromSource("""
        class Accumulator {
            var n: Int = 0
            operator fun plusAssign(x: Int) { n += x }
        }
        class Box(val item: Accumulator)
        val Box.y: Accumulator get() = item
        fun mutate(b: Box) { b.y += 3 }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "mutate", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.contains("get"))
        #expect(callees.contains("plusAssign"))
        #expect(!callees.contains("set"))
    }
}
