#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

/// KUU-1820: exercise the public kotlinx-io surface from an external consumer.
@Suite(.serialized)
struct KotlinxIOF01ContractTests {
    private func generatedConsumer(_ name: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository
                .appendingPathComponent("Scripts/io_api_inventory/f01_consumers")
                .appendingPathComponent(name),
            encoding: .utf8
        )
    }

    private func externalConsumer(_ source: String) throws -> CompilationContext {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource(
            source,
            moduleName: "KotlinxIoF01Consumer",
            emit: .executable,
            allowDefaultStdlibLibrary: true
        )
        #expect(context.options.stdlibLibraryPath != nil)
        try runSema(context)
        return context
    }

    private func probeSpans(_ source: String, prefix: String) -> [(start: Int, end: Int)] {
        let lines = source.components(separatedBy: "\n")
        return lines.enumerated().compactMap { index, line in
            guard line.contains("f01_\(prefix)_") else { return nil }
            let end = lines[(index + 1)...].firstIndex { $0.trimmingCharacters(in: .whitespaces) == "}" }
            return (index + 1, (end ?? index) + 1)
        }
    }

    private func diagnosticLines(_ diagnostics: [Diagnostic], in context: CompilationContext) -> Set<Int> {
        Set(
            diagnostics.compactMap { diagnostic in
                guard let range = diagnostic.primaryRange else { return nil }
                return context.sourceManager.lineColumn(of: range.start).line
            }
        )
    }

    @Test
    func everyCommonLedgerSignatureResolvesFromGeneratedConsumer() throws {
        let context = try externalConsumer(generatedConsumer("positive-common.kt"))
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "F01 public API consumer diagnostics: \(errors)")
    }

    @Test
    func publishedApiImplementationSignaturesStayInternal() throws {
        let source = try generatedConsumer("negative-internal.kt")
        #expect(source.components(separatedBy: "// Ledger internal-").count - 1 == 19)
        let context = try externalConsumer(source)
        let visibilityErrors = context.diagnostics.diagnostics.filter {
            $0.severity == .error
        }
        let spans = probeSpans(source, prefix: "internal")
        let errorLines = diagnosticLines(visibilityErrors, in: context)
        #expect(spans.count == 19, "Expected one generated user probe per @PublishedApi ledger row")
        #expect(
            spans.allSatisfy { span in errorLines.contains { span.start <= $0 && $0 <= span.end } },
            "Every @PublishedApi reference must fail in user scope: \(context.diagnostics.diagnostics)"
        )
    }

    @Test
    func ioOptInMarkersRetainWarningAndErrorLevels() throws {
        let negative = """
        import kotlinx.io.*
        import kotlinx.io.unsafe.UnsafeBufferOperations
        import kotlinx.io.bytestring.ByteString
        import kotlinx.io.bytestring.unsafe.UnsafeByteStringApi
        import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

        fun withoutOptIn(source: Source, sink: Sink, bytes: ByteArray) {
            source.buffer
            sink.buffer
            sink.hintEmit()
            Buffer().hintEmit()
            sink.writeToInternalBuffer { it.writeByte(1) }
            UnsafeBufferOperations.maxSafeWriteCapacity
            UnsafeByteStringOperations.wrapUnsafe(bytes)
        }
        """
        let context = try externalConsumer(negative)
        let optInDiagnostics = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }
        #expect(optInDiagnostics.contains { $0.severity == .warning }, "Expected DelicateIoApi and UnsafeIoApi warnings: \(optInDiagnostics)")
        #expect(optInDiagnostics.contains { $0.severity == .error }, "Expected InternalIoApi and UnsafeByteStringApi errors: \(optInDiagnostics)")

        let ledgerContext = try externalConsumer(generatedConsumer("negative-opt-in.kt"))
        let ledgerOptInDiagnostics = ledgerContext.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }
        let ledgerSource = try generatedConsumer("negative-opt-in.kt")
        let optInSpans = probeSpans(ledgerSource, prefix: "opt_in")
        let optInLines = diagnosticLines(ledgerOptInDiagnostics, in: ledgerContext)
        #expect(ledgerOptInDiagnostics.contains { $0.severity == .warning }, "Generated ledger references should retain warning markers: \(ledgerOptInDiagnostics)")
        #expect(ledgerOptInDiagnostics.contains { $0.severity == .error }, "Generated ledger references should retain error markers: \(ledgerOptInDiagnostics)")
        #expect(optInSpans.count == 12, "Expected every annotated public ledger row in the opt-in consumer")
        #expect(
            optInSpans.allSatisfy { span in optInLines.contains { span.start <= $0 && $0 <= span.end } },
            "Every opt-in marker row must report a diagnostic without @OptIn: \(ledgerOptInDiagnostics)"
        )

        let warningSource = try generatedConsumer("negative-opt-in-warning.kt")
        let warningContext = try externalConsumer(warningSource)
        let warningDiagnostics = warningContext.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }
        let warningLines = diagnosticLines(warningDiagnostics, in: warningContext)
        let warningSpans = probeSpans(warningSource, prefix: "opt_in")
        #expect(!warningDiagnostics.isEmpty, "WARNING opt-in markers should report diagnostics")
        #expect(warningDiagnostics.allSatisfy { $0.severity == .warning }, "DelicateIoApi and UnsafeIoApi should warn")
        #expect(
            warningSpans.allSatisfy { span in warningLines.contains { span.start <= $0 && $0 <= span.end } },
            "Every warning-level ledger row should report an opt-in warning"
        )

        let errorSource = try generatedConsumer("negative-opt-in-error.kt")
        let errorContext = try externalConsumer(errorSource)
        let errorDiagnostics = errorContext.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }
        let errorLines = diagnosticLines(errorDiagnostics, in: errorContext)
        let errorSpans = probeSpans(errorSource, prefix: "opt_in")
        #expect(!errorDiagnostics.isEmpty, "ERROR opt-in markers should report diagnostics")
        #expect(errorDiagnostics.allSatisfy { $0.severity == .error }, "InternalIoApi and UnsafeByteStringApi should fail")
        #expect(
            errorSpans.allSatisfy { span in errorLines.contains { span.start <= $0 && $0 <= span.end } },
            "Every error-level ledger row should report an opt-in error"
        )

        let positive = """
        import kotlinx.io.*
        import kotlinx.io.unsafe.UnsafeBufferOperations
        import kotlinx.io.bytestring.ByteString
        import kotlinx.io.bytestring.unsafe.UnsafeByteStringApi
        import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

        @OptIn(DelicateIoApi::class, InternalIoApi::class, UnsafeIoApi::class, UnsafeByteStringApi::class)
        fun withOptIn(source: Source, sink: Sink, bytes: ByteArray): ByteString {
            source.buffer
            sink.buffer
            sink.hintEmit()
            sink.writeToInternalBuffer { it.writeByte(1) }
            UnsafeBufferOperations.maxSafeWriteCapacity
            return UnsafeByteStringOperations.wrapUnsafe(bytes)
        }
        """
        let positiveContext = try externalConsumer(positive)
        #expect(
            !positiveContext.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" },
            "Explicit opt-in should accept the four IO marker families: \(positiveContext.diagnostics.diagnostics)"
        )
    }

    @Test
    func deprecatedPathExtensionsKeepErrorDiagnostics() throws {
        let context = try externalConsumer(generatedConsumer("negative-deprecated.kt"))
        let diagnostics = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-DEPRECATED"
        }
        #expect(diagnostics.count == 2, "Expected one error diagnostic per deprecated Path extension: \(context.diagnostics.diagnostics)")
        #expect(diagnostics.allSatisfy { $0.severity == .error }, "Path.source/sink deprecation is an error-level contract: \(diagnostics)")
    }

    @Test
    func generatedInvalidApiConsumerPreservesRejectedSurface() throws {
        let source = try generatedConsumer("negative-invalid.kt")
        let context = try externalConsumer(source)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        let errorLines = diagnosticLines(errors, in: context)
        let invalidCalls = [
            "bytes.hex()",
            "bytes.utf8()",
            "encodeToByteString()",
            "buffer.snapshot(2)",
            "select { }",
        ]
        let invalidCallLines = invalidCalls.compactMap { call in
            source.components(separatedBy: "\n").firstIndex { $0.contains(call) }.map { $0 + 1 }
        }
        #expect(invalidCallLines.count == invalidCalls.count)
        #expect(invalidCallLines.allSatisfy(errorLines.contains))
    }

    @Test
    func sourceAndSinkRemainSealedAtTheExternalLibraryBoundary() throws {
        let source = """
        package f01external
        import kotlinx.io.Source
        import kotlinx.io.Sink

        class ExternalSource : Source
        class ExternalSink : Sink
        """
        let context = try externalConsumer(source)
        let sealedErrors = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0070" && $0.message.contains("same module")
        }
        #expect(sealedErrors.count == 2, "Source and Sink are sealed upstream interfaces: \\(context.diagnostics.diagnostics)")
    }

    @Test
    func aliasesAndPackageImportsResolveByteStringExtensionAlongsideBufferMembers() throws {
        let source = """
        import kotlinx.io.*
        import kotlinx.io.bytestring.ByteString
        import kotlinx.io.bytestring.toHexString
        import kotlinx.io.write as writeByteString

        fun use(buffer: Buffer, bytes: ByteString): Int {
            buffer.write(bytes)
            buffer.writeByteString(bytes)
            val member = buffer.snapshot()
            val extension = bytes.toHexString()
            val extensionIndex = bytes.indexOf(byteArrayOf(1))
            return member.size + extension.length + extensionIndex
        }
        """
        let context = try externalConsumer(source)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Star, explicit, and alias imports should resolve the intended overloads: \(errors)")
    }
}
#endif
