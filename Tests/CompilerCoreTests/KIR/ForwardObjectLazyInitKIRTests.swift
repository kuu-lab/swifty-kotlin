@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ForwardObjectLazyInitKIRTests {
    @Test(arguments: [false, true])
    func companionAccessToLaterObjectRetainsLazyInitGuard(topLevelAccess: Bool) throws {
        let source = """
        class Factory {
            companion object {
                fun value(): Int = Later.value
            }
        }
        \(topLevelAccess ? "val first = Later.value" : "")
        object Later { val value = 42 }
        fun main() { Factory.value() }
        """
        let path = "/virtual/forward-object.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let objectSymbol = try #require(ctx.sema?.symbols.lookup(fqName: [ctx.interner.intern("Later")]))
        let propertySymbol = try #require(ctx.sema?.symbols.lookup(fqName: ["Later", "value"].map(ctx.interner.intern)))
        let initializer = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "__object_lazy_init_\(objectSymbol.rawValue)"
        })
        for name in topLevelAccess ? ["value", "main"] : ["value"] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
            let guardIndex = try #require(body.firstIndex {
                if case let .call(symbol, _, _, _, _, _, _, _) = $0 { return symbol == initializer.symbol }
                return false
            })
            let loadIndex = try #require(body.firstIndex {
                if case let .loadGlobal(_, symbol) = $0 { return symbol == propertySymbol }
                return false
            })
            #expect(guardIndex < loadIndex)
        }
        // Pending guards use the object's name until the final module rewrite.
        for function in findAllKIRFunctions(in: module) {
            #expect(!kirCalls(in: function.body).contains { ctx.interner.resolve($0.callee) == "Later" })
        }
    }

    @Test
    func constPropertyReadEvaluatesExplicitExpressionReceiver() throws {
        let source = """
        object C {
            val initialized = 1
            const val x = 42
        }
        fun getC(): C = C
        fun main() {
            getC().x
            C.x
        }
        """
        let path = "/virtual/const-receiver.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let getC = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "getC"
        })
        let objectSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("C")]))
        let objectInit = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "__object_lazy_init_\(objectSymbol.rawValue)"
        })
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let getCBody = try findKIRFunctionBody(named: "getC", in: module, interner: ctx.interner)
        #expect(body.contains {
            if case let .call(symbol, _, _, _, _, _, _, _) = $0 {
                return symbol == getC.symbol
            }
            return false
        }, "the call receiver must remain in KIR after the const value is inlined")
        #expect(!body.contains {
            if case let .call(symbol, _, _, _, _, _, _, _) = $0 {
                return symbol == objectInit.symbol
            }
            return false
        }, "a nominal qualifier used only for a const read must not initialize its object")
        #expect(getCBody.contains {
            if case let .call(symbol, _, _, _, _, _, _, _) = $0 {
                return symbol == objectInit.symbol
            }
            return false
        }, "evaluating getC() must retain the object's normal lazy initialization")
        #expect(body.contains {
            if case .constValue(_, .intLiteral(42)) = $0 { return true }
            return false
        }, "the const value should still be inlined")
    }

    /// KUU-2945: `O.P` uses `O` as a pure namespace qualifier -- the enclosing
    /// object's lazy-init guard must not be emitted for the nested-object
    /// access itself, whether it appears as a delegated-property delegate or
    /// as a direct member path. `P`'s own guard is still required.
    @Test
    func nestedObjectAccessDoesNotEmitEnclosingObjectLazyInit() throws {
        let source = """
        object O {
            object P { val value = 42 }
            init {}
        }
        operator fun O.P.getValue(thisRef: Any?, property: Any?): Int = value
        val delegated by O.P
        fun readP(): Int = O.P.value
        fun main() { readP() }
        """
        let path = "/virtual/nested-object-delegate.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let oSymbol = try #require(ctx.sema?.symbols.lookup(fqName: [ctx.interner.intern("O")]))
        let pSymbol = try #require(ctx.sema?.symbols.lookup(fqName: ["O", "P"].map(ctx.interner.intern)))
        let oInitName = "__object_lazy_init_\(oSymbol.rawValue)"
        let pInitName = "__object_lazy_init_\(pSymbol.rawValue)"
        var sawPGuard = false
        for function in findAllKIRFunctions(in: module) {
            for call in kirCalls(in: function.body) {
                let callee = ctx.interner.resolve(call.callee)
                #expect(callee != oInitName)
                if callee == pInitName { sawPGuard = true }
            }
        }
        #expect(sawPGuard)
    }

    /// Control for the KUU-2945 guard refinement: a genuine member read
    /// (`O.x`) still observes `O`'s state, so the owner lazy-init guard is
    /// still emitted for non-nominal member targets.
    @Test
    func objectMemberReadStillEmitsOwnerLazyInit() throws {
        let source = """
        object O {
            val x = 7
            init {}
        }
        fun readX(): Int = O.x
        fun main() { readX() }
        """
        let path = "/virtual/object-member-read.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let oSymbol = try #require(ctx.sema?.symbols.lookup(fqName: [ctx.interner.intern("O")]))
        let initializer = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "__object_lazy_init_\(oSymbol.rawValue)"
        })
        let body = try findKIRFunctionBody(named: "readX", in: module, interner: ctx.interner)
        #expect(kirCalls(in: body).contains { $0.symbol == initializer.symbol })
    }
}
