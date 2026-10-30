@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct UsePinnedNonLocalReturnTests {
    @Test(arguments: [false, true])
    func bundledUsePinnedRetainsItsInlineBoundary(fromArtifact: Bool) throws {
        if fromArtifact {
            TestStdlibCache.shared.prepare()
            _ = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        let statements: [(String, Bool)] = [
            ("bytes.usePinned { return bytes[0] }", false),
            ("plain { bytes.usePinned { return bytes[0] } }", true),
            ("bytes.usePinned { plain { return bytes[0] } }", true),
            ("Box().usePinned { return bytes[0] }", true),
        ]
        for (statement, shouldFail) in statements {
            let ctx = makeContextFromSource("""
            @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
            import kotlinx.cinterop.usePinned
            fun plain(block: () -> Unit) { block() }
            class Box { fun usePinned(block: () -> Unit) { block() } }
            fun first(bytes: ByteArray): Byte {
                \(statement)
                return 0.toByte()
            }
            """, emit: .executable, allowDefaultStdlibLibrary: fromArtifact)
            try runSema(ctx)
            if shouldFail {
                assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
            } else {
                #expect(!ctx.diagnostics.hasError,
                        Comment(rawValue: ctx.diagnostics.diagnostics.map(\.message).joined(separator: "\n")))
            }
        }
    }

    @Test(arguments: [false, true])
    func capturedReturnIsExpandedThroughUnpin(nested: Bool) throws {
        let statement = nested
            ? "bytes.usePinned { bytes.usePinned { return bytes[0] } }"
            : "bytes.usePinned { return bytes[0] }"
        let ctx = Self.makeContext("""
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlinx.cinterop.usePinned
        fun first(bytes: ByteArray): Byte {
            \(statement)
        }
        """)
        try runToKIR(ctx)
        let kir = try #require(ctx.kir)
        #expect(kir.arena.declarations.contains {
            guard case let .function(function) = $0 else { return false }
            return function.isInline && function.isInlineOnly
        })
        try LoweringPhase().run(ctx)
        let first = try #require(kir.arena.declarations.compactMap { declaration -> KIRFunction? in
            guard case let .function(function) = declaration,
                  function.name == ctx.interner.intern("first") else { return nil }
            return function
        }.first)
        let unpin = try #require(first.body.firstIndex {
            guard case let .call(_, callee, _, _, _, _, _, _) = $0 else { return false }
            return ctx.interner.resolve(callee) == "kk_unpin_object"
        })
        #expect(first.body.enumerated().contains { index, instruction in
            if case .returnValue = instruction { return index > unpin }
            return false
        })
        #expect(!first.body.contains {
            guard case let .call(_, callee, _, _, _, _, _, _) = $0 else { return false }
            return ctx.interner.resolve(callee).hasPrefix("kk_lambda_")
        })
    }

    @Test(arguments: [
        "bytes.usePinned { return bytes[0] }",
        "return bytes.usePinned { bytes[0] }",
        "bytes.usePinned { pinned -> return pinned.get()[0] }",
        "bytes?.usePinned { return it.get()[0] }; return 0.toByte()",
    ])
    func acceptsInlineReturns(statement: String) throws {
        let nullable = statement.contains("bytes?") ? "?" : ""
        let ctx = Self.makeContext("""
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlinx.cinterop.usePinned
        fun first(bytes: ByteArray\(nullable)): Byte {
            \(statement)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, Comment(rawValue: ctx.diagnostics.diagnostics.map(\.message).joined(separator: "\n")))
        let sema = try #require(ctx.sema)
        let call = try #require(sema.bindings.scopeFunctionKinds.first { $0.value == .scopeUsePinned }?.key)
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.flags.contains(.inlineFunction) == true)
        #expect(binding.parameterMapping == [0: 0])
    }

    @Test(arguments: [
        "plain { bytes.usePinned { return bytes[0] } }",
        "cross { bytes.usePinned { return bytes[0] } }",
        "no { bytes.usePinned { return bytes[0] } }",
        "bytes.usePinned { plain { return bytes[0] } }",
        "bytes.usePinned { cross { return bytes[0] } }",
        "bytes.usePinned { no { return bytes[0] } }",
    ])
    func rejectsInterveningNonInlineBoundaries(statement: String) throws {
        let ctx = Self.makeContext("""
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlinx.cinterop.usePinned
        fun plain(block: () -> Unit) { block() }
        inline fun cross(crossinline block: () -> Unit) { block() }
        inline fun no(noinline block: () -> Unit) { block() }
        fun first(bytes: ByteArray): Byte {
            \(statement)
            return 0.toByte()
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
    }

    @Test(arguments: ["", "inline ", "inline crossinline", "inline noinline"])
    func userMemberKeepsItsOwnInlineContract(modifiers: String) throws {
        let inline = modifiers.contains("inline") ? "inline " : ""
        let parameter = modifiers.contains("crossinline") ? "crossinline "
            : modifiers.contains("noinline") ? "noinline " : ""
        let ctx = Self.makeContext("""
        @file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
        import kotlinx.cinterop.usePinned
        class Box {
            \(inline)fun usePinned(\(parameter)block: () -> Int): Int = block()
        }
        fun first(box: Box): Int {
            box.usePinned { return 7 }
            return 0
        }
        """)
        try runSema(ctx)
        if inline.isEmpty || !parameter.isEmpty {
            assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
        } else {
            #expect(!ctx.diagnostics.hasError, Comment(rawValue: ctx.diagnostics.diagnostics.map(\.message).joined(separator: "\n")))
        }
        let sema = try #require(ctx.sema)
        #expect(!sema.bindings.scopeFunctionKinds.values.contains(.scopeUsePinned))
    }

    // Synthetic cinterop declarations own the inline contract. The backend
    // matrix separately covers bundled sources and real library artifacts.
    private static func makeContext(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
