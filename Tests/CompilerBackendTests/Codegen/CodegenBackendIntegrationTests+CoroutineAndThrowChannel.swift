@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

class CodegenBackendTestSupport: XCTestCase {}

extension CodegenBackendTestSupport {

    func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        emit: EmitMode,
        outputPath: String,
        irFlags: [String] = []
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: emit,
            target: defaultTargetTriple(),
            irFlags: irFlags
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        if emit == .kirDump {
            guard let kir = ctx.kir else {
                throw CompilerPipelineError.invalidInput("KIR not available for dump.")
            }
            let path = outputPath + ".kir"
            let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
            try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        } else {
            try CodegenPhase().run(ctx)
        }
        return ctx
    }

    func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, expected, file: file, line: line)
        }
    }

    func assertDeterministicCodegenOutput(source: String, emit: EmitMode) throws {
        try withTemporaryFile(contents: source) { path in
            let fm = FileManager.default
            let workDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: workDir) }

            let artifactBase1 = workDir.appendingPathComponent("deterministic_1").path
            // Linux toolchains may still inject output-path metadata in object files.
            // Reuse the same output path to validate deterministic bytes per identical
            // input/configuration without being sensitive to path strings.
            let artifactBase2 = emit == .object
                ? artifactBase1
                : workDir.appendingPathComponent("deterministic_2").path
            var first = try readCodegenArtifact(inputPath: path, emit: emit, outputPath: artifactBase1)
            var second = try readCodegenArtifact(inputPath: path, emit: emit, outputPath: artifactBase2)
            if emit == .llvmIR {
                first = stripPathDependentLines(first)
                second = stripPathDependentLines(second)
            }
            if emit == .object {
                first = stripPathDependentBytes(first, outputPath: artifactBase1)
                second = stripPathDependentBytes(second, outputPath: artifactBase2)
            }
            XCTAssertEqual(first, second)
        }
    }

    func stripPathDependentBytes(_ data: Data, outputPath: String) -> Data {
        var result = data

        // LLVM embeds the output path itself in the object file
        //    (e.g. the basename "deterministic_1" in Mach-O STABS / ELF debug sections).
        //    Replace every occurrence of the output path with a fixed placeholder so that
        //    two compilations with different paths produce identical bytes.
        let outputBasename = (outputPath as NSString).lastPathComponent
        let placeholder = "deterministic_X"
        if outputBasename != placeholder,
           let pathData = outputBasename.data(using: .utf8),
           let fixedData = placeholder.data(using: .utf8)
        {
            var searchStart = result.startIndex
            while let range = result.range(of: pathData, in: searchStart ..< result.endIndex) {
                result.replaceSubrange(range, with: fixedData)
                searchStart = result.index(range.lowerBound, offsetBy: fixedData.count)
            }
        }

        return result
    }

    func stripPathDependentLines(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let filtered = text.components(separatedBy: "\n").filter { line in
            !line.hasPrefix("source_filename = ") && !line.hasPrefix("; ModuleID = ")
        }
        return Data(filtered.joined(separator: "\n").utf8)
    }

    func readCodegenArtifact(inputPath: String, emit: EmitMode, outputPath: String) throws -> Data {
        let ctx = try runCodegenPipeline(
            inputPath: inputPath,
            moduleName: "Determinism",
            emit: emit,
            outputPath: outputPath
        )

        let artifactPath: String
        switch emit {
        case .kirDump:
            artifactPath = outputPath + ".kir"
        case .llvmIR:
            artifactPath = try XCTUnwrap(ctx.generatedLLVMIRPath)
        case .object:
            artifactPath = try XCTUnwrap(ctx.generatedObjectPath)
        default:
            XCTFail("unsupported emit for determinism test: \(emit)")
            artifactPath = outputPath
        }
        return try Data(contentsOf: URL(fileURLWithPath: artifactPath))
    }
}
