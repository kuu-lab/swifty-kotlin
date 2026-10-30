@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct LocalNestedInnerClassConstructorTests {
    private func context(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test
    func localOwnerInstanceResolvesInnerConstructor() throws {
        let ctx = context("""
        fun localInner(): Int {
            class Owner {
                inner class Child { fun value() = 1 }
            }
            return Owner().Child().value()
        }
        """)

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(named: "Child", in: ast, interner: ctx.interner).first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        let innerClass = try #require(sema.symbols.parentSymbol(for: binding.chosenCallee))

        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
        #expect(sema.symbols.symbol(innerClass)?.flags.contains(.innerClass) == true)
        #expect(!sema.bindings.isTypeQualifiedConstructorCallExpr(call))
    }

    @Test
    func localInnerClassInheritsMembersFromLocalSuperclass() throws {
        let ctx = context("""
        fun String.bar(): String {
            open class Local { fun result() = this@bar }
            class Owner { inner class Child : Local() }
            return Owner().Child().result()
        }
        """)

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let constructorCall = try #require(memberCallExprIDs(named: "Child", in: ast, interner: ctx.interner).first)
        let constructorBinding = try #require(sema.bindings.callBinding(for: constructorCall))
        let innerClass = try #require(sema.symbols.parentSymbol(for: constructorBinding.chosenCallee))
        #expect(sema.symbols.symbol(innerClass)?.flags.contains(.innerClass) == true)

        let inheritedCall = try #require(memberCallExprIDs(named: "result", in: ast, interner: ctx.interner).first)
        let inheritedBinding = try #require(sema.bindings.callBinding(for: inheritedCall))
        #expect(sema.symbols.symbol(inheritedBinding.chosenCallee)?.kind == .function)
        let inheritedOwner = try #require(sema.symbols.parentSymbol(for: inheritedBinding.chosenCallee))
        #expect(sema.symbols.symbol(inheritedOwner)?.name == ctx.interner.intern("Local"))
    }

    @Test
    func localInnerClassCapturesEnclosingMemberReceiver() throws {
        let ctx = context("""
        class Host {
            val a = 1
            fun calculate(): Int {
                class Owner {
                    val b = 2
                    inner class Child {
                        val c = 3
                        fun value() = this@Host.a + this@Owner.b + this.c
                    }
                }
                return Owner().Child().value()
            }
        }
        """)

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let host = try #require(sema.symbols.allSymbols().first {
            $0.kind == .class && $0.name == ctx.interner.intern("Host")
        })
        let owner = try #require(sema.symbols.allSymbols().first {
            $0.kind == .class && $0.name == ctx.interner.intern("Owner")
        })
        #expect(sema.bindings.objectLiteralCaptureSymbols(for: owner.id).contains(host.id))
    }

    @Test
    func localSubclassPropagatesSuperclassCaptures() throws {
        let ctx = context("""
        fun String.bar(): String {
            open class Local { fun result() = this@bar }
            class Owner { inner class Inner : Local() }
            return Owner().Inner().result()
        }
        """)

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let local = try #require(sema.symbols.allSymbols().first {
            $0.kind == .class && $0.name == ctx.interner.intern("Local")
        })
        let inner = try #require(sema.symbols.allSymbols().first {
            $0.kind == .class && $0.name == ctx.interner.intern("Inner")
        })
        let extensionFunction = try #require(sema.symbols.allSymbols().first {
            $0.kind == .function && $0.name == ctx.interner.intern("bar")
        })
        let receiver = SyntheticSymbolScheme.receiverParameterSymbol(for: extensionFunction.id)
        #expect(sema.bindings.objectLiteralCaptureSymbols(for: local.id).contains(receiver))
        #expect(sema.bindings.objectLiteralCaptureSymbols(for: inner.id).contains(receiver))
    }
}
