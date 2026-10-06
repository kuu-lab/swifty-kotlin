#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ImportedImplicitReceiverExtensionTests {
    @Test
    func issueMinimalReproducerWithUnitBuilder() throws {
        let ctx = makeContextFromSources([
            """
            package lib
            class Sink
            class Source
            fun Sink.writePacket(p: Source) {}
            fun buildP(b: Sink.() -> Unit) {}
            """,
            """
            package app
            import lib.*
            class BWC
            fun BWC.writePacket(p: Source) {}
            fun main() { buildP { writePacket(Source()) } }
            """,
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        try expectImportedInnerReceiverCall(in: ctx)
    }

    @Test(arguments: ["import lib.*", "import lib.Sink\nimport lib.Source\nimport lib.buildP\nimport lib.writePacket"])
    func incompatiblePackageExtensionDoesNotHideImportedExtension(imports: String) throws {
        let ctx = makeContextFromSources([
            """
            package lib
            class Sink
            class Source
            fun Sink.writePacket(p: Source): Int = 7
            fun buildP(b: Sink.() -> Int): Int = Sink().b()
            """,
            """
            package app
            \(imports)
            class BWC
            fun BWC.writePacket(p: Source): Int = 9
            fun use(): Int = buildP { writePacket(Source()) }
            """,
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        try expectImportedInnerReceiverCall(in: ctx)
    }

    @Test(arguments: [true, false])
    func applicablePackageExtensionKeepsPrecedence(importExtension: Bool) throws {
        let ctx = makeContextFromSources([
            """
            package lib
            class Sink
            class Source
            fun Sink.writePacket(p: Source): Int = 7
            fun buildP(b: Sink.() -> Int): Int = Sink().b()
            """,
            """
            package app
            \(importExtension ? "import lib.*" : "import lib.Sink\nimport lib.Source\nimport lib.buildP")
            fun Sink.writePacket(p: Source): Int = 9
            fun use(): Int = buildP { writePacket(Source()) }
            """,
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let local = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("app"), ctx.interner.intern("writePacket")]))
        #expect(sema.bindings.callBindings.values.contains { $0.chosenCallee == local })
    }

    @Test(arguments: ["writePacket(Source())", "this.writePacket(Source())"])
    func unimportedExtensionRemainsUnavailable(call: String) throws {
        let ctx = makeContextFromSources([
            """
            package lib
            class Sink
            class Source
            fun Sink.writePacket(p: Source): Int = 7
            fun buildP(b: Sink.() -> Int): Int = Sink().b()
            """,
            """
            package app
            import lib.Sink
            import lib.Source
            import lib.buildP
            class BWC
            fun BWC.writePacket(p: Source): Int = 9
            fun use(): Int = buildP { \(call) }
            """,
        ])
        try runSema(ctx)
        let expectedDiagnostic = call.hasPrefix("this.") ? "KSWIFTK-SEMA-0024" : "KSWIFTK-SEMA-0002"
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == expectedDiagnostic }, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let imported = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("lib"), ctx.interner.intern("writePacket")]))
        #expect(!sema.bindings.callBindings.values.contains { $0.chosenCallee == imported })
    }

    @Test
    func importedInnerReceiverExtensionWinsOverPackageOuterReceiver() throws {
        let ctx = makeContextFromSources([
            """
            package lib
            class Sink
            class Source
            fun Sink.writePacket(p: Source): Int = 7
            fun buildP(b: Sink.() -> Int): Int = Sink().b()
            """,
            """
            package app
            import lib.*
            class BWC
            fun BWC.writePacket(p: Source): Int = 9
            fun BWC.use(): Int = buildP { writePacket(Source()) }
            """,
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        try expectImportedInnerReceiverCall(in: ctx)
    }

    @Test
    func importedExtensionContextualizesLambdaBeforeArgumentInference() throws {
        let ctx = makeContextFromSources([
            """
            package lib
            class Sink
            fun Sink.writePacket(b: (Int) -> Int): Int = b(7)
            fun buildP(b: Sink.() -> Int): Int = Sink().b()
            """,
            """
            package app
            import lib.*
            class BWC
            fun BWC.writePacket(b: (String) -> Int): Int = b("wrong")
            fun use(): Int = buildP { writePacket { it + 1 } }
            """,
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        try expectImportedInnerReceiverCall(in: ctx)
    }

    private func expectImportedInnerReceiverCall(in ctx: CompilationContext) throws {
        let sema = try #require(ctx.sema)
        let imported = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("lib"), ctx.interner.intern("writePacket"),
        ]))
        let call = try #require(sema.bindings.callBindings.first { $0.value.chosenCallee == imported }?.key)
        #expect(sema.bindings.implicitReceiverMemberNames[call] == ctx.interner.intern("writePacket"))
        #expect(sema.bindings.implicitReceiverOuterReceiver(for: call) == nil)
    }
}
#endif
