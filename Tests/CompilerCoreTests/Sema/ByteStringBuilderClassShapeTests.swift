#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct ByteStringBuilderClassShapeTests {
    private func context(_ source: String, useLibrary: Bool) throws -> CompilationContext {
        if useLibrary { TestStdlibCache.shared.prepare() }
        let library = useLibrary ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let ctx = makeContextFromSource(source, allowDefaultStdlibLibrary: useLibrary)
        #expect(ctx.options.stdlibLibraryPath == library)
        #expect(ctx.options.includeStdlib == !useLibrary)
        return ctx
    }

    @Test(arguments: [false, true])
    func byteStringBuilderIsPublicFinalClass(useLibrary: Bool) throws {
        let ctx = try context("""
        package io.gate
        import kotlinx.io.bytestring.ByteStringBuilder
        fun retainType(value: ByteStringBuilder): ByteStringBuilder = value
        """, useLibrary: useLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let components = "kotlinx.io.bytestring.ByteStringBuilder".split(separator: ".")
            .map { ctx.interner.intern(String($0)) }
        let id = try #require(sema.symbols.lookupAll(fqName: components).first {
            sema.symbols.symbol($0)?.kind == .class
        })
        let symbol = try #require(sema.symbols.symbol(id))
        #expect(symbol.visibility == .public)
        #expect(!symbol.flags.contains(.openType), "Kotlin classes are final by default")
        #expect(symbol.flags.contains(.importedLibrary) == useLibrary)
        let superNames = sema.symbols.directSupertypes(for: id).compactMap {
            sema.symbols.symbol($0)?.fqName.map(ctx.interner.resolve).joined(separator: ".")
        }
        #expect(superNames == ["kotlin.Any"])
    }

    @Test(arguments: [false, true])
    func byteStringBuilderRejectsSubclassing(useLibrary: Bool) throws {
        let ctx = try context("""
        package io.gate
        import kotlinx.io.bytestring.ByteStringBuilder
        class ForbiddenByteStringBuilderSubclass : ByteStringBuilder()
        """, useLibrary: useLibrary)
        try runSema(ctx)
        let finalityErrors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-FINAL" && $0.message.contains("kotlinx.io.bytestring.ByteStringBuilder")
        }
        #expect(finalityErrors.count == 1, "Expected the final-class boundary in this mode: \(ctx.diagnostics.diagnostics)")
        #expect(ctx.sema != nil)
    }
}
#endif
