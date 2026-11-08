#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct OuterExtensionReceiverCallTests {
    @Test(arguments: ["expect abstract class", "class"])
    func extensionCallInsideBuildStringUsesOuterReceiver(declaration: String) throws {
        let ctx = makeContext("""
        class Source
        interface Appendable
        class StringBuilder : Appendable
        fun buildString(capacity: Int, block: StringBuilder.() -> Unit): String {
            StringBuilder().block()
            return ""
        }
        \(declaration) CD
        internal fun CD.decodeImpl(input: Source, out: Appendable, max: Int): Int = 0
        fun CD.decode2(input: Source, max: Int = 1): String = buildString(1) {
            decodeImpl(input, this, max)
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-MPP-UNRESOLVED" }, "Unexpected diagnostics: \(errors)")
        #expect(declaration.hasPrefix("expect") ? errors.count == 1 : errors.isEmpty)
        let sema = try #require(ctx.sema)
        let callee = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("decodeImpl")]))
        let call = try #require(sema.bindings.callBindings.first { $0.value.chosenCallee == callee }?.key)
        #expect(sema.bindings.implicitReceiverOuterReceiver(for: call) != nil)
    }

    @Test func nestedReceiverLambdaCapturesOuterExtensionReceiver() throws {
        let ctx = makeContext("""
        class Decoder(val value: Int)
        class Buffer
        fun withBuffer(block: Buffer.() -> Unit) { Buffer().block() }
        fun Buffer.nested(block: String.() -> Unit) { "inner".block() }
        fun Decoder.decodeImpl(max: Int): Int = value + max
        fun Decoder.decode(max: Int) = withBuffer {
            nested { decodeImpl(max) }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let callee = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("decodeImpl")]))
        let caller = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("decode")]))
        let call = try #require(sema.bindings.callBindings.first { $0.value.chosenCallee == callee }?.key)
        let receiver = try #require(sema.bindings.implicitReceiverOuterReceiver(for: call))
        #expect(receiver == SyntheticSymbolScheme.receiverParameterSymbol(for: caller))
        #expect(sema.bindings.captureSymbolsByExpr.values.contains { $0.contains(receiver) })
    }

    @Test func incompatibleOuterReceiverStillRejectsExtensionCall() throws {
        let ctx = makeContext("""
        class Decoder
        class Other
        class Buffer
        fun withBuffer(block: Buffer.() -> Int): Int = Buffer().block()
        fun Decoder.decodeImpl(max: Int): Int = max
        fun Other.decode(max: Int): Int = withBuffer { decodeImpl(max) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test func innermostApplicableReceiverKeepsPrecedence() throws {
        let ctx = makeContext("""
        class Decoder
        fun withString(block: String.() -> String): String = "inner".block()
        fun Decoder.decodeImpl(max: Int): Int = max
        fun String.decodeImpl(max: Int): String = this
        fun Decoder.decode(max: Int) = withString { decodeImpl(max) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let call = try #require(sema.bindings.callBindings.first {
            sema.symbols.symbol($0.value.chosenCallee)?.name == ctx.interner.intern("decodeImpl")
        })
        let signature = try #require(sema.symbols.functionSignature(for: call.value.chosenCallee))
        #expect(signature.returnType == sema.types.stringType)
        #expect(sema.bindings.implicitReceiverOuterReceiver(for: call.key) == nil)
    }

    @Test func loweredCallPassesCapturedDecoderReceiver() throws {
        let ctx = makeContext("""
        class Decoder(val value: Int)
        class Buffer
        fun withBuffer(block: Buffer.() -> Int): Int = Buffer().block()
        fun Decoder.decodeImpl(max: Int): Int = value + max
        fun Decoder.decode(max: Int): Int = withBuffer { decodeImpl(max) }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let decoder = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Decoder")]))
        let callee = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("decodeImpl")]))
        let calls = findAllKIRFunctions(in: module).flatMap(\.body).compactMap { instruction -> [KIRExprID]? in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                  symbol == callee else { return nil }
            return arguments
        }
        #expect(calls.count == 1)
        let arguments = try #require(calls.first)
        #expect(arguments.count == 2)
        let receiver = try #require(arguments.first)
        let receiverType = try #require(module.arena.exprType(receiver))
        #expect(sema.types.kind(of: receiverType) == .classType(ClassType(
            classSymbol: decoder, args: [], nullability: .nonNull
        )))
    }

    @Test func ambiguousOuterExtensionsRemainAmbiguous() throws {
        let ctx = makeContext("""
        interface Left
        interface Right
        class Decoder : Left, Right
        fun withString(block: String.() -> Int): Int = "inner".block()
        fun Left.decodeImpl(max: Int): Int = max
        fun Right.decodeImpl(max: Int): Int = max
        fun Decoder.decode(max: Int) = withString { decodeImpl(max) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0003" })
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test func dslMarkerHiddenOuterReceiverRemainsInaccessible() throws {
        let ctx = makeContext("""
        annotation class DslMarker
        @DslMarker annotation class Marker
        @Marker class Decoder
        @Marker class Buffer
        fun withBuffer(block: Buffer.() -> Int): Int = Buffer().block()
        private fun Decoder.decodeImpl(): Int = 1
        fun Decoder.decode(): Int = withBuffer { decodeImpl() }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "DSL-hidden receiver access must be rejected")
        let sema = try #require(ctx.sema)
        let callee = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("decodeImpl")]))
        #expect(!sema.bindings.callBindings.values.contains { $0.chosenCallee == callee })
    }

    @Test func equivalentInheritedMembersStillResolve() throws {
        let ctx = makeContext("""
        interface Left { fun decodeImpl(max: Int): Int }
        interface Right { fun decodeImpl(max: Int): Int }
        abstract class Decoder : Left, Right
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let decoder = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Decoder")]))
        let candidates = try ["Left", "Right"].map { owner in
            try #require(sema.symbols.lookup(fqName: [ctx.interner.intern(owner), ctx.interner.intern("decodeImpl")]))
        }
        let resolved = OverloadResolver().resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: makeRange(start: 0, end: 1),
                calleeName: ctx.interner.intern("decodeImpl"),
                args: [CallArg(type: sema.types.intType)]
            ),
            expectedType: nil,
            implicitReceiverType: sema.types.make(.classType(ClassType(
                classSymbol: decoder, args: [], nullability: .nonNull
            ))),
            ctx: sema
        )
        #expect(resolved.diagnostic == nil)
        #expect(resolved.chosenCallee != nil)
    }

    /// KUU-4495: a `with(null as String?)` receiver is nearer than the outer
    /// `String` extension receiver but cannot supply a `String` extension —
    /// Kotlin resolves the call on the outer receiver instead.
    @Test func nullableReceiverScopeFallsThroughToOuterExtensionReceiver() throws {
        let ctx = makeContext("""
        interface Reader { fun read(): Int }
        fun <T, R> scopeOf(receiver: T, block: T.() -> R): R = receiver.block()
        fun String.firstCode(): Int = 1
        fun String.viaNullable(): Int = scopeOf(null as String?) { firstCode() }
        fun String.viaObjectLiteral(): Reader = scopeOf(null as String?) {
            object : Reader {
                override fun read(): Int = firstCode()
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let callee = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("firstCode")]))
        let caller = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("viaNullable")]))
        let expectedReceiver = SyntheticSymbolScheme.receiverParameterSymbol(for: caller)
        #expect(sema.bindings.callBindings.contains { binding in
            binding.value.chosenCallee == callee
                && sema.bindings.implicitReceiverOuterReceiver(for: binding.key) == expectedReceiver
        })
    }

    /// The fall-through only rejects nullability mismatches: a nullable
    /// extension receiver is still supplied by a nullable implicit receiver.
    @Test func nullableReceiverStillMatchesNullableExtension() throws {
        let ctx = makeContext("""
        fun <T, R> scopeOf(receiver: T, block: T.() -> R): R = receiver.block()
        fun String?.firstCode(): Int = 1
        fun viaNullable(): Int = scopeOf(null as String?) { firstCode() }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    /// Qualified calls on a nullable receiver still require a safe call.
    @Test func explicitNullableReceiverStillRejectsNonNullExtension() throws {
        let ctx = makeContext("""
        fun String.firstCode(): Int = 1
        fun viaNullable(s: String?): Int = s.firstCode()
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    // These fixtures isolate receiver resolution; the diff case covers the full stdlib path.
    private func makeContext(_ source: String) -> CompilationContext {
        let path = "/virtual/outer-extension-receiver.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
