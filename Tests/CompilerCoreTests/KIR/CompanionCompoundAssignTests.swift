@testable import CompilerCore
import Testing

@Suite
struct CompanionCompoundAssignTests {
    @Test(arguments: ["Companion", "Registry"])
    func inferredCollectionUsesPlusAssignInEveryContext(companionName: String) throws {
        let ctx = makeContextFromSource("""
        class C {
            init { log += "i" }
            fun f() { log += "f" }
            companion object \(companionName) {
                val log = mutableListOf<String>()
                init { log += "ci" }
                fun g() { log += "g" }
            }
        }
        fun mutate() {
            C.log += "top"
            C.\(companionName).log += "explicit"
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let assignments = ast.arena.exprs.indices.filter { index in
            switch ast.arena.exprs[index] {
            case let .compoundAssign(_, name, _, _), let .memberCompoundAssign(_, _, name, _, _):
                name == ctx.interner.intern("log")
            default: false
            }
        }
        #expect(assignments.count == 6)
        for index in assignments {
            let binding = try #require(sema.bindings.callBinding(for: ExprID(rawValue: Int32(index))))
            #expect(sema.symbols.symbol(binding.chosenCallee)?.name == ctx.interner.intern("plusAssign"))
            #expect(sema.symbols.functionSignature(for: binding.chosenCallee)?.returnType == sema.types.unitType)
        }
        let module = try #require(ctx.kir)
        let property = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("C"), ctx.interner.intern(companionName), ctx.interner.intern("log"),
        ]))
        let companion = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("C"), ctx.interner.intern(companionName),
        ]))
        let guardName = "__companion_lazy_init_\(companion.rawValue)"
        for name in ["C", "f", "g", "mutate"] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
            let loadIndex = try #require(body.firstIndex {
                if case let .loadGlobal(_, symbol) = $0 { symbol == property } else { false }
            })
            let guardIndex = try #require(body.firstIndex {
                if case let .call(_, callee, _, _, _, _, _, _) = $0 {
                    ctx.interner.resolve(callee) == guardName
                } else { false }
            })
            #expect(guardIndex < loadIndex)
            #expect(!body.contains { if case let .storeGlobal(_, symbol) = $0 { symbol == property } else { false } })
            #expect(!body.contains {
                if case let .copy(_, target) = $0,
                   case let .symbolRef(symbol) = module.arena.expr(target)
                { symbol == property } else { false }
            })
        }
    }

    @Test
    func valWithOnlyBinaryOperatorStillCannotBeReassigned() throws {
        let ctx = makeContextFromSource("""
        class C {
            companion object {
                val log = listOf(1)
                init { log += 4 }
                fun g() { log += 5 }
            }
            fun f() { log += 2 }
        }
        fun mutate() { C.log += 3 }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 4)
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0014" })
    }

    @Test
    func classQualifierDoesNotSelectInstancePropertyOrBypassVisibility() throws {
        let ctx = makeContextFromSource("""
        class C {
            val item = mutableListOf<Int>()
            companion object { private val log = mutableListOf<Int>() }
        }
        fun mutate() {
            C.item += 1
            C.log += 2
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0022" })
        #expect(ctx.diagnostics.diagnostics.contains { $0.message.contains("private") })
    }

    @Test
    func localAndInstancePropertiesShadowCompanionProperty() throws {
        let ctx = makeContextFromSource("""
        class C {
            val log = mutableListOf<Int>()
            companion object { val log = mutableListOf<String>() }
            fun member() { log += 1 }
            fun local() {
                val log = mutableListOf<Boolean>()
                log += true
            }
        }
        fun mutate(c: C) {
            c.log += 2
            C.log += "companion"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func companionAndClassInferredMembersCanDependOnEachOther() throws {
        let ctx = makeContextFromSource("""
        class C {
            val item = mutableListOf<String>()
            fun size() = log.size
            companion object {
                val log = mutableListOf<String>()
                fun copy(c: C) { log += c.item }
                fun count(c: C) = c.size()
                init { log += "init" }
            }
        }
        fun use(c: C): Int = C.count(c)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
