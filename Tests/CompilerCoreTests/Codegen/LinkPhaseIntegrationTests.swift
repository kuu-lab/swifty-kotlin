@testable import CompilerCore
import Foundation
import XCTest

// CI 時間の観点: `LinkPhase().run` と `emit: .executable` は CodegenBackendIntegrationTests+*.swift と
// Lowering/Delegate KIR テストにも多数ある。リンクが本質でないケースは `.object` / `.llvmIR` への置き換えを検討。

final class LinkPhaseIntegrationTests: XCTestCase {
    private func repoKotlinStdlibSourcePaths() throws -> [String] {
        let stdlibDir = URL(fileURLWithPath: "Stdlib")
            .standardizedFileURL
        let stdlibPaths = FileManager.default.enumerator(
            at: stdlibDir,
            includingPropertiesForKeys: nil
        )?
        .compactMap { entry -> String? in
            guard let url = entry as? URL, url.pathExtension == "kt" else {
                return nil
            }
            return url.path
        }
        .sorted() ?? []
        XCTAssertTrue(
            !stdlibPaths.isEmpty,
            "Expected repo-local Kotlin stdlib sources under \(stdlibDir.path)"
        )
        return stdlibPaths
    }

    func testStdlibSearchPathAutoLinksKotlinStdlibLibraryObject() throws {
        let stdlibSource = """
        package kotlin.stdlibmigration
        fun migratedMarker(v: Int) = v + 2
        """
        try withTemporaryFile(contents: stdlibSource) { stdlibPath in
            let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let stdlibCtx = makeCompilationContext(
                inputs: [stdlibPath],
                moduleName: "KotlinStdlibMigration",
                emit: .library,
                outputPath: stdlibBase
            )
            try runToKIR(stdlibCtx)
            try LoweringPhase().run(stdlibCtx)
            try CodegenPhase().run(stdlibCtx)

            let appSource = """
            import kotlin.stdlibmigration.migratedMarker
            fun main() = migratedMarker(40)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .path
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "StdlibMigrationApp",
                    emit: .executable,
                    outputPath: outputPath,
                    stdlibSearchPaths: [stdlibBase + ".kklib"]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)
                try CodegenPhase().run(appCtx)
                assertLinkSucceeds(appCtx)

                XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
                do {
                    _ = try CommandRunner.run(executable: outputPath, arguments: [])
                    XCTFail("Expected non-zero exit")
                    return
                } catch let CommandRunnerError.nonZeroExit(failed) {
                    XCTAssertEqual(failed.exitCode, 42)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testStdlibSearchPathAutoLinksKotlinStdlibRuntimeBridge() throws {
        let stdlibSource = """
        package kotlin.stdlibmigration
        import kswiftk.internal.KSwiftKRuntimeName

        @KSwiftKRuntimeName("kk_char_isDigit")
        external fun runtimeIsDigit(ch: Char): Boolean

        fun migratedDigitScore(): Int = if (runtimeIsDigit('7')) 42 else 1
        """
        try withTemporaryFile(contents: stdlibSource) { stdlibPath in
            let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let stdlibCtx = makeCompilationContext(
                inputs: [stdlibPath],
                moduleName: "KotlinStdlibRuntimeBridge",
                emit: .library,
                outputPath: stdlibBase
            )
            try runToKIR(stdlibCtx)
            try LoweringPhase().run(stdlibCtx)
            try CodegenPhase().run(stdlibCtx)

            let appSource = """
            import kotlin.stdlibmigration.migratedDigitScore
            fun main() = migratedDigitScore()
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .path
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "StdlibRuntimeBridgeApp",
                    emit: .executable,
                    outputPath: outputPath,
                    stdlibSearchPaths: [stdlibBase + ".kklib"]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)
                try CodegenPhase().run(appCtx)
                assertLinkSucceeds(appCtx)

                XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
                do {
                    _ = try CommandRunner.run(executable: outputPath, arguments: [])
                    XCTFail("Expected non-zero exit")
                    return
                } catch let CommandRunnerError.nonZeroExit(failed) {
                    XCTAssertEqual(failed.exitCode, 42)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinScopeFunctionSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()

        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let appSource = """
        fun main(): Int {
            val letValue = "abcd".let { it.length }
            val runValue = "abc".run { length }
            val topRunValue = run { 5 }
            val alsoValue = 6.also { it + 1 }
            val applyValue = 7.apply { }
            val withValue = with("abcdefgh") { length }
            var repeatValue = 0
            repeat(3) { repeatValue = repeatValue + it }
            if (42.takeIf { it > 0 } == null) return 1
            if (42.takeUnless { it < 0 } == null) return 2
            return letValue + runValue + topRunValue + alsoValue + applyValue + withValue + repeatValue + 6
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibScopeFunctionApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)

            let sema = try XCTUnwrap(appCtx.sema)
            func importedInlineCount(_ fqName: [String]) -> Int {
                let interned = fqName.map { appCtx.interner.intern($0) }
                return sema.symbols.lookupAll(fqName: interned).filter {
                    sema.importedInlineFunctions[$0] != nil
                }.count
            }

            for name in ["let", "also", "apply", "with", "takeIf", "takeUnless", "repeat"] {
                let interned = ["kotlin", name].map { appCtx.interner.intern($0) }
                let details = sema.symbols.lookupAll(fqName: interned).map { symbolID in
                    "\(symbolID.rawValue):\(sema.importedInlineFunctions[symbolID] != nil)"
                }.joined(separator: ",")
                XCTAssertGreaterThanOrEqual(
                    importedInlineCount(["kotlin", name]),
                    1,
                    "Expected kotlin.\(name) to be loaded from stdlib inline KIR; candidates=[\(details)]"
                )
            }
            XCTAssertGreaterThanOrEqual(
                importedInlineCount(["kotlin", "run"]),
                2,
                "Expected both kotlin.run overloads to be loaded from stdlib inline KIR"
            )

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinStringPredicateSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        func functionRecords(for fqName: String) -> [MetadataRecord] {
            records.filter { $0.kind == .function && $0.fqName == fqName }
        }
        func sourceLinks(for fqName: String) -> Set<String> {
            Set(functionRecords(for: fqName).compactMap(\.externalLinkName))
        }

        for name in ["isEmpty", "isNotEmpty", "isBlank", "isNotBlank", "isNullOrEmpty", "isNullOrBlank"] {
            let publicLinks = sourceLinks(for: "kotlin.text.\(name)")
            XCTAssertEqual(
                publicLinks.count,
                1,
                "Expected source stdlib to export kotlin.text.\(name) as a real source-backed function"
            )
            XCTAssertTrue(
                publicLinks.allSatisfy { $0.hasPrefix("kk_fn_") },
                "Public kotlin.text.\(name) should link to its generated source function, got \(publicLinks)"
            )
            XCTAssertFalse(
                publicLinks.contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") },
                "Public kotlin.text.\(name) should stay source-backed; only the internal bridge should expose a runtime link"
            )
        }
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_isEmpty_flat"), ["kk_string_isEmpty_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_isNotEmpty_flat"), ["kk_string_isNotEmpty_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_isBlank_flat"), ["kk_string_isBlank_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_isNotBlank_flat"), ["kk_string_isNotBlank_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_isNullOrEmpty_flat"), ["kk_string_isNullOrEmpty_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_isNullOrBlank_flat"), ["kk_string_isNullOrBlank_flat"])
        for name in ["equals", "contentEquals"] {
            let publicLinks = sourceLinks(for: "kotlin.text.\(name)")
            XCTAssertEqual(
                publicLinks.count,
                2,
                "Expected source stdlib to export both kotlin.text.\(name) overloads"
            )
            XCTAssertTrue(
                publicLinks.allSatisfy { $0.hasPrefix("kk_fn_") },
                "Public kotlin.text.\(name) should stay source-backed, got \(publicLinks)"
            )
            XCTAssertFalse(
                publicLinks.contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") },
                "Public kotlin.text.\(name) should not expose the runtime bridge directly"
            )
        }
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_equals_flat"), ["kk_string_equals_flat"])
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_equalsIgnoreCase_flat"),
            ["kk_string_equalsIgnoreCase_flat"]
        )
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_contentEquals_flat"),
            ["kk_string_contentEquals_flat"]
        )
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_contentEquals_ignoreCase_flat"),
            ["kk_string_contentEquals_ignoreCase_flat"]
        )
        for name in ["count", "any", "all", "none", "indexOfFirst", "indexOfLast"] {
            let publicRecords = functionRecords(for: "kotlin.text.\(name)")
            XCTAssertEqual(
                publicRecords.count,
                2,
                "Expected source stdlib to export both String and CharSequence kotlin.text.\(name) overloads"
            )
            XCTAssertTrue(
                publicRecords.allSatisfy(\.isInline),
                "Public kotlin.text.\(name) HOF wrappers should be imported as inline source KIR"
            )
            XCTAssertFalse(
                publicRecords.contains { ($0.externalLinkName ?? "").hasPrefix("kk_") },
                "Public kotlin.text.\(name) should not expose the runtime bridge directly"
            )
        }
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_count_flat"), ["kk_string_count_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_any_flat"), ["kk_string_any_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_all_flat"), ["kk_string_all_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_none_flat"), ["kk_string_none_flat"])
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_indexOfFirst_flat"),
            ["kk_string_indexOfFirst_flat"]
        )
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_indexOfLast_flat"),
            ["kk_string_indexOfLast_flat"]
        )

        let appSource = """
        fun main(): Int {
            val empty = ""
            val blank = "   "
            val text = "abc"
            val charSequence: CharSequence = text
            val nullableNull: String? = null
            val nullableEmpty: String? = ""
            val nullableBlank: String? = "   "
            val nullableText: String? = text
            val nullableUpper: String? = "ABC"

            if (!empty.isEmpty()) return 1
            if (text.isEmpty()) return 2
            if (!text.isNotEmpty()) return 3
            if (empty.isNotEmpty()) return 4
            if (!blank.isBlank()) return 5
            if (text.isBlank()) return 6
            if (!text.isNotBlank()) return 7
            if (blank.isNotBlank()) return 8
            if (!nullableNull.isNullOrEmpty()) return 9
            if (!nullableNull.isNullOrBlank()) return 10
            if (!nullableEmpty.isNullOrEmpty()) return 11
            if (!nullableEmpty.isNullOrBlank()) return 12
            if (nullableBlank.isNullOrEmpty()) return 13
            if (!nullableBlank.isNullOrBlank()) return 14
            if (!text.equals("abc")) return 15
            if (text.equals("ABC")) return 16
            if (!text.equals("ABC", true)) return 17
            if (text.equals(null)) return 18
            if (!nullableNull.contentEquals(null)) return 19
            if (nullableNull.contentEquals(nullableText)) return 20
            if (nullableText.contentEquals(nullableUpper)) return 21
            if (!nullableText.contentEquals(nullableUpper, true)) return 22
            if (nullableText.contentEquals(nullableUpper, false)) return 23
            if (text.count { it == 'a' } != 1) return 24
            if (charSequence.count { it > 'a' } != 2) return 25
            if (!text.any { it == 'b' }) return 26
            if (charSequence.any { it == 'z' }) return 27
            if (!text.all { it >= 'a' && it <= 'z' }) return 28
            if (!charSequence.none { it == 'z' }) return 29
            if (text.indexOfFirst { it == 'c' } != 2) return 30
            if (charSequence.indexOfLast { it == 'a' } != 0) return 31
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibStringPredicateApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)
            let sema = try XCTUnwrap(appCtx.sema)
            func importedInlineCount(_ fqName: [String]) -> Int {
                let interned = fqName.map { appCtx.interner.intern($0) }
                return sema.symbols.lookupAll(fqName: interned).filter {
                    sema.importedInlineFunctions[$0] != nil
                }.count
            }
            func nonImportedLinks(_ fqName: [String]) -> Set<String> {
                let interned = fqName.map { appCtx.interner.intern($0) }
                return Set(sema.symbols.lookupAll(fqName: interned).compactMap { symbolID in
                    guard sema.symbols.symbol(symbolID)?.flags.contains(.importedLibrary) != true else {
                        return nil
                    }
                    return sema.symbols.externalLinkName(for: symbolID)
                })
            }
            for name in ["count", "any", "all", "none", "indexOfFirst", "indexOfLast"] {
                XCTAssertEqual(
                    importedInlineCount(["kotlin", "text", name]),
                    2,
                    "Expected both String and CharSequence kotlin.text.\(name) overloads to load from inline KIR"
                )
            }
            let hofRuntimeLinks = [
                "count": "kk_string_count_flat",
                "any": "kk_string_any_flat",
                "all": "kk_string_all_flat",
                "none": "kk_string_none_flat",
                "indexOfFirst": "kk_string_indexOfFirst_flat",
                "indexOfLast": "kk_string_indexOfLast_flat",
            ]
            for (name, link) in hofRuntimeLinks {
                XCTAssertFalse(
                    nonImportedLinks(["kotlin", "text", name]).contains(link),
                    "Source stdlib import should suppress the synthetic public \(name) runtime fallback"
                )
            }
            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinStringConversionSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        func sourceLinks(for fqName: String) -> Set<String> {
            Set(records.filter { $0.kind == .function && $0.fqName == fqName }
                .compactMap(\.externalLinkName))
        }

        for name in [
            "toInt", "toIntOrNull", "toLong", "toLongOrNull", "toFloat", "toFloatOrNull",
            "toDouble", "toDoubleOrNull", "toShort", "toShortOrNull", "toByte", "toByteOrNull",
            "toUByteOrNull", "toUShortOrNull", "toUIntOrNull", "toULongOrNull",
            "toBoolean", "toBooleanStrict", "toBooleanStrictOrNull",
        ] {
            let publicLinks = sourceLinks(for: "kotlin.text.\(name)")
            XCTAssertFalse(publicLinks.isEmpty, "Expected source stdlib to export kotlin.text.\(name)")
            XCTAssertTrue(
                publicLinks.allSatisfy { $0.hasPrefix("kk_fn_") },
                "Public kotlin.text.\(name) should stay source-backed, got \(publicLinks)"
            )
            XCTAssertFalse(
                publicLinks.contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") },
                "Public kotlin.text.\(name) should not expose the runtime bridge directly"
            )
        }

        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toInt_flat"), ["kk_string_toInt_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toInt_radix_flat"), ["kk_string_toInt_radix_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toIntOrNull_flat"), ["kk_string_toIntOrNull_flat"])
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_toIntOrNull_radix_flat"),
            ["kk_string_toIntOrNull_radix_flat"]
        )
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toLong_flat"), ["kk_string_toLong_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toLongOrNull_flat"), ["kk_string_toLongOrNull_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toFloat_flat"), ["kk_string_toFloat_flat"])
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_toFloatOrNull_flat"),
            ["kk_string_toFloatOrNull_flat"]
        )
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toDouble_flat"), ["kk_string_toDouble_flat"])
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_toDoubleOrNull_flat"),
            ["kk_string_toDoubleOrNull_flat"]
        )
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toShort_flat"), ["kk_string_toShort_flat"])
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_toShortOrNull_flat"),
            ["kk_string_toShortOrNull_flat"]
        )
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toByte_flat"), ["kk_string_toByte_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toByte_radix_flat"), ["kk_string_toByte_radix_flat"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toByteOrNull_flat"), ["kk_string_toByteOrNull_flat"])
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_toUByteOrNull_radix_flat"),
            ["kk_string_toUByteOrNull_radix_flat"]
        )
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_toUShortOrNull_radix_flat"),
            ["kk_string_toUShortOrNull_radix_flat"]
        )
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_toUIntOrNull_radix_flat"),
            ["kk_string_toUIntOrNull_radix_flat"]
        )
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_toULongOrNull_radix_flat"),
            ["kk_string_toULongOrNull_radix_flat"]
        )
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__string_toBoolean_flat"), ["kk_string_toBoolean_flat"])
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_toBooleanStrict_flat"),
            ["kk_string_toBooleanStrict_flat"]
        )
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__string_toBooleanStrictOrNull_flat"),
            ["kk_string_toBooleanStrictOrNull_flat"]
        )

        let appSource = """
        fun main(): Int {
            if ("42".toInt() != 42) return 1
            if ("ff".toInt(16) != 255) return 2
            if ("bad".toIntOrNull() != null) return 3
            if ("42".toLong() != 42L) return 4
            if ("3.5".toDouble().toInt() != 3) return 5
            if ("3.5".toFloat().toInt() != 3) return 6
            if ("127".toByte().toInt() != 127) return 7
            if ("32767".toShort().toInt() != 32767) return 8
            if ("200".toByteOrNull() != null) return 9
            if ("true".toBooleanStrictOrNull() != true) return 10
            if ("True".toBooleanStrictOrNull() != null) return 11
            if (!"True".toBoolean()) return 12
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibStringConversionApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)
            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinPreconditionSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        func sourceLinks(for fqName: String) -> Set<String> {
            Set(records.filter { $0.kind == .function && $0.fqName == fqName }
                .compactMap(\.externalLinkName))
        }

        XCTAssertFalse(sourceLinks(for: "kotlin.require").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.check").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.assert").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.error").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.TODO").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__require"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__requireLazy"), ["kk_require_lazy"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__check"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__checkLazy"), ["kk_check_lazy"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__assert"), ["kk_precondition_assert"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__assertLazy"), ["kk_precondition_assert_lazy"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__error"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__todo"), ["kk_todo", "kk_todo_noarg"])

        let appSource = """
        fun pendingA(): Nothing = TODO()
        fun pendingB(): Nothing = TODO("skip")

        fun main(): Int {
            require(true)
            require(true) { "unused" }
            check(true)
            check(true) { "unused" }
            assert(true)
            assert(true) { "unused" }
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibPreconditionApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)

            let sema = try XCTUnwrap(appCtx.sema)
            func importedLinks(for name: String) -> Set<String> {
                let fqName = ["kotlin", name].map { appCtx.interner.intern($0) }
                return Set(sema.symbols.lookupAll(fqName: fqName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) })
            }

            XCTAssertFalse(importedLinks(for: "require").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "check").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "assert").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "error").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "TODO").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinIOSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        func sourceLinks(for fqName: String) -> Set<String> {
            Set(records.filter { $0.kind == .function && $0.fqName == fqName }
                .compactMap(\.externalLinkName))
        }

        XCTAssertFalse(sourceLinks(for: "kotlin.io.println").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.io.print").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.io.readLine").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.io.readln").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.io.readlnOrNull").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__println"), ["kk_println_any", "kk_println_newline"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__print"), ["kk_print_any", "kk_print_noarg"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__readLine"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__readln"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__readlnOrNull"), ["kk_readlnOrNull"])
        XCTAssertTrue(records.contains { $0.kind == .property && $0.fqName == "kotlin.io.DEFAULT_BUFFER_SIZE" })

        let appSource = """
        import kotlin.io.DEFAULT_BUFFER_SIZE
        import kotlin.io.print
        import kotlin.io.println
        import kotlin.io.readLine
        import kotlin.io.readln
        import kotlin.io.readlnOrNull

        fun readA(): String? = readLine()
        fun readB(): String = readln()
        fun readC(): String? = readlnOrNull()

        fun main(): Int {
            print()
            print("x")
            println()
            println("y")
            return if (DEFAULT_BUFFER_SIZE == 8192) 42 else 1
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibIOApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)

            let sema = try XCTUnwrap(appCtx.sema)
            func importedLinks(for name: String) -> Set<String> {
                let fqName = ["kotlin", "io", name].map { appCtx.interner.intern($0) }
                return Set(sema.symbols.lookupAll(fqName: fqName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) })
            }

            XCTAssertFalse(importedLinks(for: "println").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "print").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "readLine").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "readln").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "readlnOrNull").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            let bufferSizeFQName = ["kotlin", "io", "DEFAULT_BUFFER_SIZE"].map { appCtx.interner.intern($0) }
            let bufferSize = try XCTUnwrap(sema.symbols.lookupAll(fqName: bufferSizeFQName).first { symbol in
                sema.symbols.symbol(symbol)?.kind == .property
            })
            XCTAssertEqual(sema.symbols.propertyType(for: bufferSize), sema.types.intType)
            XCTAssertNil(sema.symbols.externalLinkName(for: bufferSize))
            XCTAssertEqual(sema.symbols.constValueExprKind(for: bufferSize), .intLiteral(8192))

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
                XCTAssertEqual(failed.stdout, "x\ny\n")
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinSystemSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        func sourceLinks(for fqName: String) -> Set<String> {
            Set(records.filter { $0.kind == .function && $0.fqName == fqName }
                .compactMap(\.externalLinkName))
        }

        XCTAssertFalse(sourceLinks(for: "kotlin.system.exitProcess").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.system.getTimeMicros").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.system.getTimeMillis").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.system.getTimeNanos").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.system.measureTimeMicros").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.system.measureTimeMillis").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.system.measureNanoTime").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__exitProcess"), ["kk_system_exitProcess"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__getTimeMicros"), ["kk_system_getTimeMicros"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__getTimeMillis"), ["kk_system_getTimeMillis"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__getTimeNanos"), ["kk_system_getTimeNanos"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__measureTimeMicros"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__measureTimeMillis"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__measureNanoTime"), [])

        let appSource = """
        import kotlin.system.exitProcess
        import kotlin.system.getTimeMicros
        import kotlin.system.getTimeMillis
        import kotlin.system.getTimeNanos
        import kotlin.system.measureNanoTime
        import kotlin.system.measureTimeMicros
        import kotlin.system.measureTimeMillis

        fun terminate(): Nothing = exitProcess(7)

        fun main(): Int {
            val micros = getTimeMicros()
            val millis = getTimeMillis()
            val nanos = getTimeNanos()
            val measuredMicros = measureTimeMicros { }
            val measuredMillis = measureTimeMillis { }
            val measuredNanos = measureNanoTime { }
            if (micros < 0L) return 1
            if (millis < 0L) return 2
            if (nanos < 0L) return 3
            if (measuredMicros < 0L) return 4
            if (measuredMillis < 0L) return 5
            if (measuredNanos < 0L) return 6
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibSystemApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)

            let sema = try XCTUnwrap(appCtx.sema)
            func importedLinks(for name: String) -> Set<String> {
                let fqName = ["kotlin", "system", name].map { appCtx.interner.intern($0) }
                return Set(sema.symbols.lookupAll(fqName: fqName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) })
            }

            XCTAssertFalse(importedLinks(for: "exitProcess").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "getTimeMicros").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "getTimeMillis").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "getTimeNanos").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "measureTimeMicros").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "measureTimeMillis").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "measureNanoTime").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinSynchronizedSource() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        let sourceLinks = Set(records.filter { $0.kind == .function && $0.fqName == "kotlin.synchronized" }
            .compactMap(\.externalLinkName))
        let primitiveLinks = Set(records.filter {
            $0.kind == .function && $0.fqName == "kswiftk.internal.__synchronized"
        }.compactMap(\.externalLinkName))
        XCTAssertFalse(sourceLinks.contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertEqual(primitiveLinks, ["kk_synchronized"])

        let appSource = """
        fun main(): Int {
            val result = synchronized("lock") { "value" }
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibSynchronizedApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)

            let sema = try XCTUnwrap(appCtx.sema)
            let fqName = ["kotlin", "synchronized"].map { appCtx.interner.intern($0) }
            let importedLinks = Set(sema.symbols.lookupAll(fqName: fqName)
                .compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertFalse(importedLinks.contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinTestAssertionSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        func sourceLinks(for fqName: String) -> Set<String> {
            Set(records.filter { $0.kind == .function && $0.fqName == fqName }
                .compactMap(\.externalLinkName))
        }

        XCTAssertFalse(sourceLinks(for: "kotlin.test.assertEquals").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.test.assertTrue").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.test.assertNull").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__testAssertEquals"), ["kk_test_assertEquals"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__testAssertEqualsMessage"), ["kk_test_assertEquals_message"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__testAssertTrue"), ["kk_test_assertTrue"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__testAssertTrueMessage"), ["kk_test_assertTrue_message"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__testAssertNull"), ["kk_test_assertNull"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__testAssertNullMessage"), ["kk_test_assertNull_message"])

        let appSource = """
        import kotlin.test.assertEquals
        import kotlin.test.assertNull
        import kotlin.test.assertTrue

        fun main(): Int {
            assertEquals(1, 1)
            assertEquals("x", "x", "message")
            assertTrue(true)
            assertTrue(true, "message")
            assertNull(null)
            assertNull(null, "message")
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibTestAssertionsApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)

            let sema = try XCTUnwrap(appCtx.sema)
            func importedLinks(for name: String) -> Set<String> {
                let fqName = ["kotlin", "test", name].map { appCtx.interner.intern($0) }
                return Set(sema.symbols.lookupAll(fqName: fqName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) })
            }
            XCTAssertFalse(importedLinks(for: "assertEquals").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "assertTrue").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "assertNull").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinNumericBitsSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        let sourceLinks = Set(records.filter { $0.kind == .function && $0.fqName == "kotlin.fromBits" }
            .compactMap(\.externalLinkName))
        let doublePrimitiveLinks = Set(records.filter {
            $0.kind == .function && $0.fqName == "kswiftk.internal.__doubleFromBits"
        }.compactMap(\.externalLinkName))
        let floatPrimitiveLinks = Set(records.filter {
            $0.kind == .function && $0.fqName == "kswiftk.internal.__floatFromBits"
        }.compactMap(\.externalLinkName))
        XCTAssertFalse(sourceLinks.contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertEqual(doublePrimitiveLinks, ["kk_double_fromBits"])
        XCTAssertEqual(floatPrimitiveLinks, ["kk_float_fromBits"])

        let appSource = """
        fun main(): Int {
            val doubleValue = Double.fromBits(0L)
            val floatValue = Float.fromBits(0)
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibNumericBitsApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)

            let sema = try XCTUnwrap(appCtx.sema)
            let fqName = ["kotlin", "fromBits"].map { appCtx.interner.intern($0) }
            let importedLinks = Set(sema.symbols.lookupAll(fqName: fqName)
                .compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertFalse(importedLinks.contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinFloatingPointSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        func sourceLinks(for fqName: String) -> Set<String> {
            Set(records.filter { $0.kind == .function && $0.fqName == fqName }
                .compactMap(\.externalLinkName))
        }

        XCTAssertFalse(sourceLinks(for: "kotlin.isNaN").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.isInfinite").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.isFinite").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.toBits").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.toRawBits").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__doubleIsNaN"), ["kk_double_isNaN"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__floatIsNaN"), ["kk_float_isNaN"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__doubleIsInfinite"), ["kk_double_isInfinite"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__floatIsInfinite"), ["kk_float_isInfinite"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__doubleIsFinite"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__floatIsFinite"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__doubleToBits"), ["kk_double_toBits"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__floatToBits"), ["kk_float_toBits"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__doubleToRawBits"), ["kk_double_toRawBits"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__floatToRawBits"), ["kk_float_toRawBits"])

        let appSource = """
        fun main(): Int {
            val doubleNaN = 1.0.isNaN()
            val doubleInfinite = 1.0.isInfinite()
            val doubleFinite = 1.0.isFinite()
            val floatNaN = 1.0f.isNaN()
            val floatInfinite = 1.0f.isInfinite()
            val floatFinite = 1.0f.isFinite()
            val doubleBits = 1.0.toBits()
            val doubleRawBits = 1.0.toRawBits()
            val floatBits = 1.0f.toBits()
            val floatRawBits = 1.0f.toRawBits()
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibFloatingPointApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)

            let sema = try XCTUnwrap(appCtx.sema)
            func importedLinks(for name: String) -> Set<String> {
                let fqName = ["kotlin", name].map { appCtx.interner.intern($0) }
                return Set(sema.symbols.lookupAll(fqName: fqName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) })
            }
            XCTAssertFalse(importedLinks(for: "isNaN").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "isInfinite").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "isFinite").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "toBits").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "toRawBits").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinBitOperationSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        func sourceLinks(for fqName: String) -> Set<String> {
            Set(records.filter { $0.kind == .function && $0.fqName == fqName }
                .compactMap(\.externalLinkName))
        }

        XCTAssertFalse(sourceLinks(for: "kotlin.countOneBits").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.countLeadingZeroBits").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.countTrailingZeroBits").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.highestOneBit").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.lowestOneBit").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.takeHighestOneBit").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.takeLowestOneBit").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.rotateLeft").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.rotateRight").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__intCountOneBits"), ["kk_int_countOneBits"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__intCountLeadingZeroBits"), ["kk_int_countLeadingZeroBits"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__intCountTrailingZeroBits"), ["kk_int_countTrailingZeroBits"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__intHighestOneBit"), ["kk_int_highestOneBit"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__longHighestOneBit"), ["kk_long_highestOneBit"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__intLowestOneBit"), ["kk_int_lowestOneBit"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__longLowestOneBit"), ["kk_long_lowestOneBit"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__intTakeHighestOneBit"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__longTakeHighestOneBit"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__intTakeLowestOneBit"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__longTakeLowestOneBit"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__intRotateLeft"), ["kk_int_rotateLeft"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__longRotateLeft"), ["kk_long_rotateLeft"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__intRotateRight"), ["kk_int_rotateRight"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__longRotateRight"), ["kk_long_rotateRight"])

        let appSource = """
        fun main(): Int {
            val intValue = 16
            val longValue = 16L
            val intCount = intValue.countOneBits()
            val intLeading = intValue.countLeadingZeroBits()
            val intTrailing = intValue.countTrailingZeroBits()
            val intHighest = intValue.highestOneBit()
            val intLowest = intValue.lowestOneBit()
            val intTakeHighest = intValue.takeHighestOneBit()
            val intTakeLowest = intValue.takeLowestOneBit()
            val intRotateLeft = intValue.rotateLeft(1)
            val intRotateRight = intValue.rotateRight(1)
            val longHighest = longValue.highestOneBit()
            val longLowest = longValue.lowestOneBit()
            val longTakeHighest = longValue.takeHighestOneBit()
            val longTakeLowest = longValue.takeLowestOneBit()
            val longRotateLeft = longValue.rotateLeft(1)
            val longRotateRight = longValue.rotateRight(1)
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibBitOperationApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)

            let sema = try XCTUnwrap(appCtx.sema)
            func importedLinks(for name: String) -> Set<String> {
                let fqName = ["kotlin", name].map { appCtx.interner.intern($0) }
                return Set(sema.symbols.lookupAll(fqName: fqName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) })
            }
            XCTAssertFalse(importedLinks(for: "countOneBits").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "countLeadingZeroBits").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "countTrailingZeroBits").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "highestOneBit").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "lowestOneBit").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "takeHighestOneBit").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "takeLowestOneBit").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "rotateLeft").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "rotateRight").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinMathExtensionSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        func sourceLinks(for fqName: String) -> Set<String> {
            Set(records.filter { $0.kind == .function && $0.fqName == fqName }
                .compactMap(\.externalLinkName))
        }

        XCTAssertFalse(sourceLinks(for: "kotlin.math.pow").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.math.roundToInt").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.math.roundToLong").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__mathPow"),
            ["kk_math_pow", "kk_math_pow_float"]
        )
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__doubleRoundToInt"), ["kk_double_roundToInt"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__floatRoundToInt"), ["kk_float_roundToInt"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__doubleRoundToLong"), ["kk_double_roundToLong"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__floatRoundToLong"), ["kk_float_roundToLong"])

        let appSource = """
        import kotlin.math.pow
        import kotlin.math.roundToInt
        import kotlin.math.roundToLong

        fun main(): Int {
            val doublePow = 2.0.pow(3.0)
            val doublePowInt = 2.0.pow(3)
            val floatPow = 2.0f.pow(3.0f)
            val floatPowInt = 2.0f.pow(3)
            val doubleRoundInt = 2.4.roundToInt()
            val floatRoundInt = 2.4f.roundToInt()
            val doubleRoundLong = 2.4.roundToLong()
            val floatRoundLong = 2.4f.roundToLong()
            if (doublePow != 8.0) return 1
            if (doublePowInt != 8.0) return 2
            if (2.0.pow(-2) != 0.25) return 3
            if (floatPow != 8.0f) return 4
            if (floatPowInt != 8.0f) return 5
            if (2.0f.pow(-2) != 0.25f) return 6
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibMathExtensionsApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"]
            )
            try runToKIR(appCtx)

            let sema = try XCTUnwrap(appCtx.sema)
            func importedLinks(for name: String) -> Set<String> {
                let fqName = ["kotlin", "math", name].map { appCtx.interner.intern($0) }
                return Set(sema.symbols.lookupAll(fqName: fqName)
                    .compactMap { sema.symbols.externalLinkName(for: $0) })
            }
            XCTAssertFalse(importedLinks(for: "pow").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "roundToInt").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
            XCTAssertFalse(importedLinks(for: "roundToLong").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStdlibSearchPathUsesRepoKotlinMathTopLevelSources() throws {
        let stdlibPaths = try repoKotlinStdlibSourcePaths()
        let stdlibBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let stdlibCtx = makeCompilationContext(
            inputs: stdlibPaths,
            moduleName: "KotlinStdlib",
            emit: .library,
            outputPath: stdlibBase,
            includeStdlib: false
        )
        try runToKIR(stdlibCtx)
        try LoweringPhase().run(stdlibCtx)
        try CodegenPhase().run(stdlibCtx)

        let metadataPath = URL(fileURLWithPath: stdlibBase + ".kklib")
            .appendingPathComponent("metadata.bin")
            .path
        let metadata = try String(contentsOfFile: metadataPath, encoding: .utf8)
        let records = MetadataDecoder().decode(metadata)
        func sourceLinks(for fqName: String) -> Set<String> {
            Set(records.filter { $0.kind == .function && $0.fqName == fqName }
                .compactMap(\.externalLinkName))
        }

        XCTAssertFalse(sourceLinks(for: "kotlin.math.abs").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.math.sqrt").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.math.sin").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.math.atan2").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.math.log").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.math.max").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.math.min").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertFalse(sourceLinks(for: "kotlin.math.nextUp").contains { $0.hasPrefix("kk_") && !$0.hasPrefix("kk_fn_") })
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__mathAbs"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__mathSqrt"), ["kk_math_sqrt", "kk_math_sqrt_float"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__mathSin"), ["kk_math_sin", "kk_math_sin_float"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__mathAtan2"), ["kk_math_atan2", "kk_math_atan2_float"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__mathLog"), [])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__mathSign"), [])
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__mathMax"),
            ["kk_math_max", "kk_math_max_float"]
        )
        XCTAssertEqual(
            sourceLinks(for: "kswiftk.internal.__mathMin"),
            ["kk_math_min", "kk_math_min_float"]
        )
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__doubleNextUp"), ["kk_double_nextUp"])
        XCTAssertEqual(sourceLinks(for: "kswiftk.internal.__floatNextUp"), ["kk_float_nextUp"])

        let appSource = """
        import kotlin.math.abs
        import kotlin.math.acos
        import kotlin.math.acosh
        import kotlin.math.asin
        import kotlin.math.asinh
        import kotlin.math.atan
        import kotlin.math.atan2
        import kotlin.math.atanh
        import kotlin.math.cbrt
        import kotlin.math.ceil
        import kotlin.math.cos
        import kotlin.math.cosh
        import kotlin.math.exp
        import kotlin.math.expm1
        import kotlin.math.floor
        import kotlin.math.hypot
        import kotlin.math.ln
        import kotlin.math.ln1p
        import kotlin.math.log
        import kotlin.math.log10
        import kotlin.math.log2
        import kotlin.math.max
        import kotlin.math.min
        import kotlin.math.nextDown
        import kotlin.math.nextUp
        import kotlin.math.round
        import kotlin.math.roundToInt
        import kotlin.math.roundToLong
        import kotlin.math.sign
        import kotlin.math.sin
        import kotlin.math.sinh
        import kotlin.math.sqrt
        import kotlin.math.tan
        import kotlin.math.tanh
        import kotlin.math.truncate
        import kotlin.math.ulp

        fun main(): Int {
            val absInt = abs(-3)
            val absLong = abs(-3L)
            val absDouble = abs(-3.0)
            val absFloat = abs(-3.0f)
            if (absDouble != 3.0) return 1
            if (absFloat != 3.0f) return 2
            if (1.0 / abs(-0.0) < 0.0) return 3
            val sqrtDouble = sqrt(4.0)
            val sqrtFloat = sqrt(4.0f)
            val ceilDouble = ceil(1.2)
            val ceilFloat = ceil(1.2f)
            val floorDouble = floor(1.8)
            val floorFloat = floor(1.8f)
            val roundDouble = round(1.2)
            val roundFloat = round(1.2f)
            val truncateDouble = truncate(1.8)
            val truncateFloat = truncate(1.8f)
            val sinDouble = sin(0.0)
            val sinFloat = sin(0.0f)
            val cosDouble = cos(0.0)
            val cosFloat = cos(0.0f)
            val tanDouble = tan(0.0)
            val tanFloat = tan(0.0f)
            val asinDouble = asin(0.5)
            val asinFloat = asin(0.5f)
            val acosDouble = acos(0.5)
            val acosFloat = acos(0.5f)
            val atanDouble = atan(0.5)
            val atanFloat = atan(0.5f)
            val atan2Double = atan2(1.0, 2.0)
            val atan2Float = atan2(1.0f, 2.0f)
            val expDouble = exp(1.0)
            val expFloat = exp(1.0f)
            val expm1Double = expm1(1.0)
            val expm1Float = expm1(1.0f)
            val lnDouble = ln(2.0)
            val lnFloat = ln(2.0f)
            val ln1pDouble = ln1p(1.0)
            val ln1pFloat = ln1p(1.0f)
            val log2Double = log2(2.0)
            val log2Float = log2(2.0f)
            val log10Double = log10(10.0)
            val log10Float = log10(10.0f)
            val logDouble = log(8.0, 2.0)
            val logFloat = log(8.0f, 2.0f)
            if (logDouble < 2.99 || logDouble > 3.01) return 4
            if (logFloat < 2.99f || logFloat > 3.01f) return 5
            val sinhDouble = sinh(1.0)
            val sinhFloat = sinh(1.0f)
            val coshDouble = cosh(1.0)
            val coshFloat = cosh(1.0f)
            val tanhDouble = tanh(0.5)
            val tanhFloat = tanh(0.5f)
            val cbrtDouble = cbrt(8.0)
            val cbrtFloat = cbrt(8.0f)
            val acoshDouble = acosh(2.0)
            val acoshFloat = acosh(2.0f)
            val asinhDouble = asinh(1.0)
            val asinhFloat = asinh(1.0f)
            val atanhDouble = atanh(0.5)
            val atanhFloat = atanh(0.5f)
            val signDouble = sign(-1.0)
            val signFloat = sign(-1.0f)
            if (signDouble != -1.0) return 6
            if (signFloat != -1.0f) return 7
            if (sign(0.0) != 0.0) return 8
            val hypotDouble = hypot(3.0, 4.0)
            val hypotFloat = hypot(3.0f, 4.0f)
            val ulpDouble = ulp(1.0)
            val ulpFloat = ulp(1.0f)
            val nextUpDouble = nextUp(1.0)
            val nextUpFloat = nextUp(1.0f)
            val nextDownDouble = nextDown(1.0)
            val nextDownFloat = nextDown(1.0f)
            val roundToIntDouble = roundToInt(2.4)
            val roundToIntFloat = roundToInt(2.4f)
            val roundToLongDouble = roundToLong(2.4)
            val roundToLongFloat = roundToLong(2.4f)
            val maxDouble = max(1.0, 2.0)
            val maxFloat = max(1.0f, 2.0f)
            val maxInt = max(1, 2)
            val maxLong = max(1L, 2L)
            val minDouble = min(1.0, 2.0)
            val minFloat = min(1.0f, 2.0f)
            val minInt = min(1, 2)
            val minLong = min(1L, 2L)
            return 42
        }
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "StdlibMathTopLevelApp",
                emit: .executable,
                outputPath: outputPath,
                stdlibSearchPaths: [stdlibBase + ".kklib"],
                includeStdlib: false
            )
            try runToKIR(appCtx)

            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLinkPhaseAutoLinksKotlinLibraryObjectForCrossModuleCall() throws {
        let librarySource = """
        package extdemo
        fun plus(v: Int) = v + 1
        """
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.plus
            fun main() = plus(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .path
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "CrossModuleApp",
                    emit: .executable,
                    outputPath: outputPath,
                    searchPaths: [libraryBase + ".kklib"]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)
                try CodegenPhase().run(appCtx)
                assertLinkSucceeds(appCtx)

                XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
                do {
                    _ = try CommandRunner.run(executable: outputPath, arguments: [])
                    XCTFail("Expected non-zero exit")
                    return
                } catch let CommandRunnerError.nonZeroExit(failed) {
                    XCTAssertEqual(failed.exitCode, 42)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testLinkPhaseReportsMissingMainAndCanLinkExecutable() throws {
        try withTemporaryFile(contents: "fun notMain() = 0") { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NoMain", emit: .executable, outputPath: out)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            XCTAssertThrowsError(try LinkPhase().run(ctx))
            XCTAssertTrue(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LINK-0002" })
        }

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "HasMain",
                inputs: [path],
                outputPath: out,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            assertLinkSucceeds(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: out))
        }
    }

    func testLinkPhaseWrapperReportsTopLevelThrownException() throws {
        let source = """
        fun main(): Any? {
            val arr = IntArray(1)
            return arr[2]
        }
        """
        try withTemporaryFile(contents: source) { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(inputs: [path], moduleName: "TopLevelThrow", emit: .executable, outputPath: out)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            assertLinkSucceeds(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: out))

            let result: CommandResult
            do {
                result = try CommandRunner.run(executable: out, arguments: [])
                XCTFail("Expected executable to fail on unhandled top-level exception.")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                result = failed
            } catch {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.stderr.contains("KSWIFTK-LINK-0003"))
            XCTAssertTrue(result.stderr.contains("KSwiftK panic"))
        }
    }

    func testLinkPhaseAutoLinksKklibManifestObjectsAndDeduplicates() throws {
        let fm = FileManager.default
        let workspaceDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspaceDir) }

        let libraryDir = workspaceDir.appendingPathComponent("NativePlus.kklib")
        let objectsDir = libraryDir.appendingPathComponent("objects")
        try fm.createDirectory(at: objectsDir, withIntermediateDirectories: true)

        let cSource = """
        #include <stdint.h>
        intptr_t plus(intptr_t value, intptr_t* outThrown) {
            (void)outThrown;
            return value + 1;
        }
        """
        let cSourceURL = workspaceDir.appendingPathComponent("native_plus.c")
        try cSource.write(to: cSourceURL, atomically: true, encoding: .utf8)

        let objectURL = objectsDir.appendingPathComponent("native_plus.o")
        let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
        _ = try CommandRunner.run(
            executable: clangPath,
            arguments: ["-c", cSourceURL.path, "-o", objectURL.path]
        )

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NativePlus",
          "kotlinLanguageVersion": "2.3.10",
          "compilerVersion": "0.1.0",
          "target": "arm64-apple-macosx",
          "objects": ["objects/native_plus.o", "objects/native_plus.o"],
          "metadata": "metadata.bin"
        }
        """
        try manifest.write(
            to: libraryDir.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try "symbols=0\n".write(
            to: libraryDir.appendingPathComponent("metadata.bin"),
            atomically: true,
            encoding: .utf8
        )

        let appSource = """
        fun main() = plus(41)
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = workspaceDir.appendingPathComponent("AppExecutable").path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "App",
                emit: .executable,
                outputPath: outputPath,
                searchPaths: [libraryDir.path, workspaceDir.path]
            )
            try runToKIR(appCtx)
            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            assertLinkSucceeds(appCtx)

            XCTAssertTrue(fm.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLinkPhaseSkipsForObjectEmitMode() throws {
        let objectCtx = makeCompilationContext(inputs: [], moduleName: "SkipLink", emit: .object)
        XCTAssertNoThrow(try LinkPhase().run(objectCtx))
    }

    func testLinkPhaseFailsWhenObjectIsMissingForExecutable() throws {
        let missingObjectCtx = makeCompilationContext(inputs: [], moduleName: "MissingObj", emit: .executable)
        XCTAssertThrowsError(try LinkPhase().run(missingObjectCtx))
    }

    func testLinkPhaseFailsWhenKIRModuleIsMissing() throws {
        let tempObjectURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        try Data().write(to: tempObjectURL)

        let noKirCtx = makeCompilationContext(inputs: [], moduleName: "NoKir", emit: .executable)
        noKirCtx.generatedObjectPath = tempObjectURL.path
        XCTAssertThrowsError(try LinkPhase().run(noKirCtx))
    }

    func testLinkPhasePassesDebugFlagToExecutableLink() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "DebugLink",
                inputs: [path],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                debugInfo: true
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            assertLinkSucceeds(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
        }
    }

    func testLinkerDriverArgsDisablePieForLinuxTargets() {
        let linuxTarget = TargetTriple(arch: "x86_64", vendor: "unknown", os: "linux-gnu", osVersion: nil)
        let args = LinkPhase().linkerDriverArgs(for: linuxTarget)

        XCTAssertEqual(Array(args.prefix(2)), ["-target", "x86_64-unknown-linux-gnu"])
        XCTAssertTrue(args.contains("-no-pie"))
    }

    func testLinuxAutolinkStubIsRewrittenWhenCorrupted() throws {
        // Use a test-only triple so this corruption check never races with regular link tests
        // that share the default Linux autolink stub path.
        let linuxTarget = TargetTriple(arch: "x86_64", vendor: "kswiftkstubtest", os: "linux-gnu", osVersion: nil)
        let linkPhase = LinkPhase()

        let stubPath = try XCTUnwrap(linkPhase.emitSwiftAutolinkStubIfNeeded(target: linuxTarget))
        try "corrupted".write(toFile: stubPath, atomically: true, encoding: .utf8)

        let repairedPath = try XCTUnwrap(linkPhase.emitSwiftAutolinkStubIfNeeded(target: linuxTarget))
        XCTAssertEqual(repairedPath, stubPath)

        let contents = try String(contentsOfFile: repairedPath, encoding: .utf8)
        XCTAssertNotEqual(contents, "corrupted")
        XCTAssertTrue(contents.contains("_kswiftkRuntimeAutolinkAnchor"))
        XCTAssertTrue(contents.contains("NSLock()"))
        XCTAssertTrue(contents.contains("DispatchQueue.global"))
        XCTAssertTrue(contents.contains("DispatchSemaphore(value: 0)"))
    }

    func testExecutableEmissionWithOutputExtensionUsesSeparateObjectPath() throws {
        let source = """
        fun main() {
            println("%b %B".format(true, false))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("out")
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ExtensionOutput",
                emit: .executable,
                outputPath: outputPath
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            XCTAssertEqual(ctx.generatedObjectPath, outputPath + ".o")
            XCTAssertNotEqual(ctx.generatedObjectPath, outputPath)

            assertLinkSucceeds(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "true FALSE")
        }
    }

    func testExecutableEmissionWithObjectOutputPathUsesSeparateIntermediateObjectPath() throws {
        let source = """
        fun main() {
            println(42)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("o")
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ObjectSuffixOutput",
                emit: .executable,
                outputPath: outputPath
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            XCTAssertEqual(
                ctx.generatedObjectPath,
                URL(fileURLWithPath: outputPath)
                    .deletingPathExtension()
                    .appendingPathExtension("executable")
                    .appendingPathExtension("o")
                    .path
            )
            XCTAssertNotEqual(ctx.generatedObjectPath, outputPath)

            assertLinkSucceeds(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "42")
        }
    }

    func testExecutableStringFormatHandlesBoxedScalarsInRuntimeObjects() throws {
        let source = """
        fun main() {
            val big: Any? = 9223372036854775807L
            val fp: Any? = 2.5
            val ch: Any? = 'A'
            val flag: Any? = true
            println("%d %x %s %s %s".format(big, big, fp, ch, flag))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "StringFormatBoxes",
                emit: .executable,
                outputPath: outputPath
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            XCTAssertEqual(
                result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                "9223372036854775807 7fffffffffffffff 2.5 A true"
            )
        }
    }

    func testExecutableStringFormatSupportsScientificNotation() throws {
        let source = """
        fun main() {
            println("%.2e".format(1234.5))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "StringFormatScientific",
                emit: .executable,
                outputPath: outputPath
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            assertLinkSucceeds(ctx)

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "1.23e+03")
        }
    }

    func testLinkPhaseReportsDiagnosticForUnsupportedTargetArchitecture() throws {
        let tempObjectURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        try Data().write(to: tempObjectURL)

        let interner = StringInterner()
        let arena = KIRArena()
        let mainSym = SymbolID(rawValue: 99)
        let mainDecl = arena.appendDecl(.function(KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDecl])], arena: arena)

        let badTargetOptions = CompilerOptions(
            moduleName: "BadTarget",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .executable,
            target: TargetTriple(arch: "definitely-bad-arch", vendor: "apple", os: "macosx", osVersion: nil)
        )
        let badTargetCtx = CompilationContext(
            options: badTargetOptions,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        badTargetCtx.generatedObjectPath = tempObjectURL.path
        badTargetCtx.kir = module

        XCTAssertThrowsError(try LinkPhase().run(badTargetCtx))
        XCTAssertTrue(badTargetCtx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LINK-0001" })
    }

    #if os(macOS)
        func testRuntimeObjectPathsBuildForAlternateAppleArchitecture() throws {
            let hostTarget = TargetTriple.hostDefault()
            let alternateArch = hostTarget.arch == "arm64" ? "x86_64" : "arm64"
            let alternateTarget = TargetTriple(
                arch: alternateArch,
                vendor: hostTarget.vendor,
                os: hostTarget.os,
                osVersion: hostTarget.osVersion
            )

            let runtimeObjects = try CodegenRuntimeSupport.runtimeObjectPaths(target: alternateTarget)

            XCTAssertFalse(runtimeObjects.isEmpty)
            XCTAssertTrue(runtimeObjects.allSatisfy { FileManager.default.fileExists(atPath: $0) })
            XCTAssertTrue(runtimeObjects.allSatisfy { $0.contains("\(alternateArch)-apple-macosx") })
        }
    #endif
}

private func assertLinkSucceeds(
    _ ctx: CompilationContext,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        try LinkPhase().run(ctx)
    } catch {
        let diagnostics = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: "\n")
        let diagnosticSummary = diagnostics.isEmpty ? "No diagnostics were recorded." : diagnostics
        XCTFail(
            """
            LinkPhase failed with error: \(error)
            Diagnostics:
            \(diagnosticSummary)
            """,
            file: file,
            line: line
        )
    }
}
