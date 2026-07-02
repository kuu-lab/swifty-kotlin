@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KsSymbolNameSemaTests {
    @Test func bundledKsSymbolNameSetsExternalLinkNameAndKIRCallCallee() throws {
        let bundledSource = """
        package bridge

        import kotlin.internal.KsSymbolName

        @KsSymbolName("kk_bridge_identity")
        external fun bridgeIdentity(value: Int): Int
        """
        let userSource = """
        import bridge.bridgeIdentity

        fun main(): Int = bridgeIdentity(7)
        """

        try withTemporaryFile(contents: userSource) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .library)
            _ = ctx.sourceManager.addFile(
                path: "__bundled_bridge_identity.kt",
                contents: Data(bundledSource.utf8)
            )

            try runToKIR(ctx)

            let sema = try #require(ctx.sema)
            let bridgeFQName = ["bridge", "bridgeIdentity"].map { ctx.interner.intern($0) }
            let bridgeSymbol = try #require(sema.symbols.lookup(fqName: bridgeFQName))
            #expect(sema.symbols.externalLinkName(for: bridgeSymbol) == "kk_bridge_identity")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            #expect(extractCallees(from: body, interner: ctx.interner).contains("kk_bridge_identity"))
            assertNoDiagnostic("KSWIFTK-SEMA-0007", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0008", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0009", in: ctx)
        }
    }

    @Test func userKsSymbolNameAnnotationIsRejected() throws {
        let source = """
        import kotlin.internal.KsSymbolName

        @KsSymbolName("kk_user_bridge")
        fun userBridge(value: Int): Int = value
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0007", in: ctx)
        }
    }

    @Test func userExternalFunctionIsRejectedWithoutBodylessDiagnostic() throws {
        let source = """
        external fun userBridge(value: Int): Int
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0008", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0009", in: ctx)
        }
    }

    @Test func nonExternalBodylessFunctionStillRequiresBody() throws {
        let source = """
        fun missingBody(): Int
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0009", in: ctx)
        }
    }

    @Test func interfaceBodylessFunctionDoesNotRequireBody() throws {
        let source = """
        interface Shape {
            fun area(): Int
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0009", in: ctx)
        }
    }
}
