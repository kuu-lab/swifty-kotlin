#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Assert `data` starts with the native object-file magic number for the current OS
/// (ELF on Linux, Mach-O elsewhere).
func assertIsNativeObjectFile(
    _ data: Data,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    #expect(data.count >= 4, "Object file is too small to contain a valid header", sourceLocation: sourceLocation)
    #if os(Linux)
        // ELF magic number
        #expect(Array(data.prefix(4)) == [0x7F, 0x45, 0x4C, 0x46], sourceLocation: sourceLocation)
    #else
        // Mach-O magic number
        #expect(Array(data.prefix(4)) == [0xCF, 0xFA, 0xED, 0xFE], sourceLocation: sourceLocation)
    #endif
}

func assertHasDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    #expect(found, "Expected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))", sourceLocation: sourceLocation)
}

func assertNoDiagnostic(
    _ code: String,
    in ctx: CompilationContext,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) {
    let found = ctx.diagnostics.diagnostics.contains { $0.code == code }
    #expect(!found, "Unexpected diagnostic \(code), got: \(ctx.diagnostics.diagnostics.map(\.code))", sourceLocation: sourceLocation)
}
#endif
