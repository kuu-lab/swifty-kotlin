@testable import CompilerCore
import Testing

@Suite
struct MemberExtensionMutationTests {
    @Test
    func tokenHandlerResolvesReceiverMutationAndCalls() throws {
        let ctx = makeContextFromSource("""
        class B { var seconds: Int = 0 }
        class P {
            fun B.handleToken(chunk: String) { seconds = chunk.toInt() }
            fun go(b: B) = b.handleToken("5")
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let handler = try findKIRFunction(named: "handleToken", in: module, interner: ctx.interner)
        #expect(handler.params.count == 3)
        let caller = try findKIRFunction(named: "go", in: module, interner: ctx.interner)
        #expect(caller.body.contains { instruction in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction else { return false }
            return symbol == handler.symbol && arguments.count == 3
        })
    }

    @Test(arguments: ["val seconds: Int = 0", "private var seconds: Int = 0"], ["=", "+="])
    func receiverMutationRejectsImmutableOrPrivateProperties(property: String, operation: String) throws {
        let source = """
        class B { \(property) }
        class P {
            fun B.handleToken() { seconds \(operation) 5 }
            fun go(b: B) = b.handleToken()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let code = property.hasPrefix("val") ? "KSWIFTK-SEMA-0014" : "KSWIFTK-SEMA-0040"
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == code })
        }
    }

    @Test
    func privateReceiverMutationIsAllowedInsideItsOwner() throws {
        let source = """
        class B {
            private var seconds: Int = 0
            fun B.update() {
                seconds = 5
                seconds += 2
            }
            fun go(b: B) = b.update()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToKIR(ctx)
            #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)
        }
    }

    @Test
    func memberExtensionRequiresDispatchReceiverInScope() throws {
        let source = """
        class B { var seconds: Int = 0 }
        class P {
            fun B.handleToken() { seconds = 5 }
        }
        fun outside(b: B) = b.handleToken()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
        }
    }
}
