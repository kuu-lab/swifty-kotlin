@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite(.serialized)
struct ExperimentalPropertyTypeUsageTests {
    @Test(arguments: [false, true])
    func originalReproducerRequiresOptIn(usingKklib: Bool) throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/reference_cases/experimental_property_type_optin_invalid.kt")
        let source = try String(contentsOf: fixture, encoding: .utf8)
        let context = try check(source, usingKklib: usingKklib)
        let diagnostics = context.diagnostics.diagnostics
        #expect(diagnostics.count == 1, "\(diagnostics)")
        #expect(diagnostics.allSatisfy { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error })
        let start = try #require(source.range(of: "holder.value")).lowerBound
        #expect(try diagnosticOffsets(diagnostics) == [source[..<start].utf8.count])
    }

    @Test(arguments: [false, true], ["WARNING", "ERROR"])
    func propertyReadsRequireTypeMarkers(usingKklib: Bool, level: String) throws {
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.\(level))
        annotation class Gate
        @Gate class Experimental
        @OptIn(Gate::class)
        open class Holder(val value: Experimental) {
            fun implicit() { value }
        }
        @OptIn(Gate::class) class Derived(value: Experimental) : Holder(value)
        fun inferred(holder: Holder) = holder.value
        fun explicit(holder: Holder): Experimental = holder.value
        fun unit(holder: Holder) { holder.value }
        fun safe(holder: Holder?) = holder?.value
        fun inherited(holder: Derived) { holder.value }
        @OptIn(Gate::class) fun accepted(holder: Holder) = holder.value
        @Gate fun propagated(holder: Holder) = holder.value
        """
        let context = try check(source, usingKklib: usingKklib)
        let diagnostics = context.diagnostics.diagnostics
        #expect(diagnostics.count == 6, "\(diagnostics)")
        #expect(diagnostics.allSatisfy {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("'Gate'")
                && $0.severity == (level == "ERROR" ? .error : .warning)
        })
        let sites = try diagnosticOffsets(diagnostics)
        let expected = try [
            ("fun explicit", "fun explicit"), ("fun inferred", "holder.value"),
            ("fun explicit", "holder.value"), ("fun unit", "holder.value"),
            ("fun safe", "holder?.value"), ("fun inherited", "holder.value"),
        ].map { declaration, token in
            let start = try #require(source.range(of: declaration)).lowerBound
            let line = source[start...].prefix { $0 != "\n" }
            let tokenStart = try #require(line.range(of: token)).lowerBound
            return source[..<tokenStart].utf8.count
        }
        #expect(sites.sorted() == expected.sorted(), "\(diagnostics)")
    }

    @Test(arguments: [false, true])
    func directAndNestedTypeMarkersAreDeduplicatedPerUsage(usingKklib: Bool) throws {
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR) annotation class Gate
        @RequiresOptIn(level = RequiresOptIn.Level.WARNING) annotation class OtherGate
        @Gate @OtherGate class Experimental
        class Box<T>
        @OptIn(Gate::class, OtherGate::class)
        class Holder(@property:Gate val value: Box<Experimental>, var mutable: Experimental?)
        fun read(holder: Holder) { holder.value; holder.value; holder.mutable = null }
        @OptIn(Gate::class) fun partial(holder: Holder) { holder.value }
        @OptIn(Gate::class, OtherGate::class) fun accepted(holder: Holder) { holder.value }
        """
        let context = try check(source, usingKklib: usingKklib)
        let diagnostics = context.diagnostics.diagnostics
        #expect(diagnostics.count == 7, "\(diagnostics)")
        #expect(diagnostics.filter { $0.severity == .error }.count == 3)
        #expect(diagnostics.filter { $0.severity == .warning }.count == 4)
        #expect(diagnostics.allSatisfy { $0.code == "KSWIFTK-SEMA-OPT-IN" })
    }

    @Test(arguments: [false, true])
    func inferredProducerRequirementIsVisibleToForwardCallers(usingKklib: Bool) throws {
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR) annotation class Gate
        @Gate class Experimental
        @OptIn(Gate::class) class Holder(val value: Experimental)
        fun caller(holder: Holder) { producer(holder) }
        @OptIn(Gate::class) fun producer(holder: Holder) = holder.value
        @OptIn(Gate::class) val top = producerValue()
        @OptIn(Gate::class) fun producerValue() = Experimental()
        fun read() { top }
        @OptIn(Gate::class) fun accepted(holder: Holder) { producer(holder); top }
        """
        let context = try check(source, usingKklib: usingKklib)
        let diagnostics = context.diagnostics.diagnostics
        #expect(diagnostics.count == 2, "\(diagnostics)")
        #expect(diagnostics.allSatisfy { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error })
    }

    @Test
    func producerMetadataRetainsRequirementsWithoutConsent() throws {
        let producer = try check("""
        package library
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR) annotation class Gate
        @Gate class Experimental
        @OptIn(Gate::class) class Holder(val value: Experimental)
        @OptIn(Gate::class) fun producer(holder: Holder) = holder.value
        """, usingKklib: false)
        #expect(producer.diagnostics.diagnostics.isEmpty, "\(producer.diagnostics.diagnostics)")
        let sema = try #require(producer.sema)
        let encoder = MetadataEncoder()
        let records = encoder.buildRecords(
            symbols: sema.symbols, types: sema.types, moduleName: "Producer",
            interner: producer.interner, functionLinkNames: [:]
        ).filter { $0.fqName == "library" || $0.fqName.hasPrefix("library.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kklib")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = defaultTargetTriple()
        let manifest = """
        {"formatVersion":1,"moduleName":"Producer","kotlinLanguageVersion":"2.3.10",
         "target":"\(target.arch)-\(target.vendor)-\(target.os)","metadata":"metadata.bin"}
        """
        try manifest
            .write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try encoder.serializeIndexed(records)
            .write(to: directory.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let source = """
        import library.*
        fun read(holder: Holder) { holder.value; producer(holder) }
        @OptIn(Gate::class) fun accepted(holder: Holder) { holder.value; producer(holder) }
        """
        let path = directory.appendingPathComponent("consumer.kt").path
        let consumer = makeCompilationContext(inputs: [path], searchPaths: [directory.path], includeStdlib: false)
        _ = consumer.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(consumer)
        let diagnostics = consumer.diagnostics.diagnostics
        #expect(diagnostics.count == 2, "\(diagnostics)")
        #expect(diagnostics.allSatisfy { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error })
    }

    @Test(arguments: [false, true])
    func compoundAssignAndDiscardedPostfixRequireTypeMarkers(usingKklib: Bool) throws {
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR) annotation class Gate
        @Gate class Experimental {
            operator fun plus(other: Experimental) = this
            operator fun dec() = this
        }
        @OptIn(Gate::class) class Holder(var value: Experimental, var count: Int) {
            fun implicit() { value-- }
            @OptIn(Gate::class) fun accepted() { value-- }
        }
        fun compound(holder: Holder) { holder.value += holder.value }
        fun postfix(holder: Holder) { holder.value-- }
        fun plain(holder: Holder) { holder.count += 1; holder.count-- }
        @OptIn(Gate::class) fun accepted(holder: Holder) { holder.value += holder.value; holder.value-- }
        """
        let context = try check(source, usingKklib: usingKklib)
        let diagnostics = context.diagnostics.diagnostics
        #expect(diagnostics.allSatisfy { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error })
        let lines = try diagnostics.map { diagnostic -> Int in
            let offset = try #require(diagnostic.primaryRange).start.offset
            return source.utf8.prefix(offset).filter { $0 == UInt8(ascii: "\n") }.count + 1
        }
        // opted-in class body (7) is accepted; compound (10: write + read), postfix (11)
        #expect(lines.sorted() == [10, 10, 11], "\(diagnostics)")
    }

    private func diagnosticOffsets(_ diagnostics: [Diagnostic]) throws -> [Int] {
        try diagnostics.map { try #require($0.primaryRange).start.offset }
    }

    private func check(_ source: String, usingKklib: Bool) throws -> CompilationContext {
        if usingKklib {
            TestStdlibCache.shared.prepare()
            let artifact = try #require(CompilerOptions.defaultStdlibLibraryPath)
            try #require(FileManager.default.fileExists(atPath: artifact + "/manifest.json"))
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(
            inputs: [path], includeStdlib: usingKklib, allowDefaultStdlibLibrary: usingKklib
        )
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(context)
        return context
    }
}
