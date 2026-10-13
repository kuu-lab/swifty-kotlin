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
}
