#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LibMetadataImportIntegrationTests {
    // MARK: - Manifest Schema Validation Tests
    // MARK: - Negative/warning manifest import scenarios

    @Test func testNegativeLibMetadataImportScenarios() throws {
        let fm = FileManager.default
        var searchPaths: [String] = []
        var sources: [String] = []

        do {
            // testManifestMissingFormatVersionEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "moduleName": "NoVersion",
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=nv.foo schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample0
            fun main() = 0
            """)
        }

        do {
            // testManifestUnsupportedFormatVersionEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 99,
              "moduleName": "BadVersion",
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=bv.bar schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample1
            fun main() = 0
            """)
        }

        do {
            // testManifestMissingModuleNameEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=nm.baz schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample2
            fun main() = 0
            """)
        }

        do {
            // testManifestEmptyModuleNameEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "",
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=em.qux schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample3
            fun main() = 0
            """)
        }

        do {
            // testManifestUnsupportedKotlinLanguageVersionEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "BadLang",
              "kotlinLanguageVersion": "1.9.0",
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=bl.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample4
            fun main() = 0
            """)
        }

        do {
            // testManifestIncompatibleTargetEmitsErrorAndSkipsLibrary
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "WrongTarget",
              "kotlinLanguageVersion": "2.3.10",
              "target": "fake-unknown-invalid",
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=wt.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample5
            fun main() = 0
            """)
        }

        do {
            // testManifestMissingMetadataFileEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
            let t = defaultTargetTriple()
            let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "NoMeta",
              "kotlinLanguageVersion": "2.3.10",
              "target": "\(targetStr)",
              "metadata": "nonexistent.bin"
            }
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample6
            fun main() = 0
            """)
        }

        do {
            // testManifestMissingObjectFileEmitsWarning
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
            let t = defaultTargetTriple()
            let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "MissingObj",
              "kotlinLanguageVersion": "2.3.10",
              "target": "\(targetStr)",
              "objects": ["objects/missing.o"],
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=mo.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample7
            fun main() = 0
            """)
        }

        do {
            // testManifestMissingInlineKIRDirEmitsWarning
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
            let t = defaultTargetTriple()
            let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "MissingInline",
              "kotlinLanguageVersion": "2.3.10",
              "target": "\(targetStr)",
              "metadata": "metadata.bin",
              "inlineKIRDir": "nonexistent-dir"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=mi.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample8
            fun main() = 0
            """)
        }

        do {
            // testInlineKIRArtifactWithExcessiveParameterCountEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            let inlineDir = libDir.appendingPathComponent("inline-kir")
            try fm.createDirectory(at: inlineDir, withIntermediateDirectories: true)
            let t = defaultTargetTriple()
            let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "HugeInline",
              "kotlinLanguageVersion": "2.3.10",
              "target": "\(targetStr)",
              "metadata": "metadata.bin",
              "inlineKIRDir": "inline-kir"
            }
            """
            let metadata = """
            symbols=1
            function HugeParams fq=lib.foo schema=v1 arity=0 suspend=0 inline=1
            """
            let kirbin = "params=2000000000\n"

            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            try kirbin.write(to: inlineDir.appendingPathComponent("HugeParams.kirbin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample9
            fun main() = 0
            """)
        }

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                moduleName: "NegativeImportApp",
                emit: .kirDump,
                searchPaths: searchPaths
            )
            try runToKIR(ctx)

            // testManifestMissingFormatVersionEmitsError
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0010", in: ctx)
                let noSymbols = ctx.sema?.symbols.allSymbols().contains { symbol in
                    symbol.fqName.map { ctx.interner.resolve($0) } == ["nv", "foo"] && symbol.flags.contains(.synthetic)
                }
                #expect(!(noSymbols ?? false))
            }

            // testManifestUnsupportedFormatVersionEmitsError
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0010", in: ctx)
            }

            // testManifestMissingModuleNameEmitsError
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0011", in: ctx)
            }

            // testManifestEmptyModuleNameEmitsError
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0011", in: ctx)
            }

            // testManifestUnsupportedKotlinLanguageVersionEmitsError
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0012", in: ctx)
            }

            // testManifestIncompatibleTargetEmitsErrorAndSkipsLibrary
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0013", in: ctx)
                let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                    symbol.fqName.map { ctx.interner.resolve($0) } == ["wt", "fn"] && symbol.flags.contains(.synthetic)
                }
                #expect(!(hasImported ?? false))
            }

            // testManifestMissingMetadataFileEmitsError
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0014", in: ctx)
            }

            // testManifestMissingObjectFileEmitsWarning
            do {

                let pathWarnings = ctx.diagnostics.diagnostics.filter {
                    $0.code == "KSWIFTK-LIB-0014" && $0.severity == .warning
                }
                #expect(!pathWarnings.isEmpty)
            }

            // testManifestMissingInlineKIRDirEmitsWarning
            do {

                let pathWarnings = ctx.diagnostics.diagnostics.filter {
                    $0.code == "KSWIFTK-LIB-0014" && $0.severity == .warning
                }
                #expect(!pathWarnings.isEmpty)
            }

            // testInlineKIRArtifactWithExcessiveParameterCountEmitsError
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0020", in: ctx)
            }

        }
    }

    // MARK: - Positive manifest import scenario

    @Test func testCompatibleTargetLibMetadataImportScenarios() throws {
        let fm = FileManager.default
        var searchPaths: [String] = []
        var sources: [String] = []

        do {
            // testManifestCompatibleTargetDoesNotEmitTargetError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
            let t = defaultTargetTriple()
            let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "GoodTarget",
              "kotlinLanguageVersion": "2.3.10",
              "target": "\(targetStr)",
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=gt.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample10
            fun main() = 0
            """)
        }

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                moduleName: "CompatibleTargetImportApp",
                emit: .kirDump,
                searchPaths: searchPaths
            )
            try runToKIR(ctx)

            // testManifestCompatibleTargetDoesNotEmitTargetError
            do {

                assertNoDiagnostic("KSWIFTK-LIB-0010", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0011", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0012", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0013", in: ctx)
            }

        }
    }

    // MARK: - Wildcard/default import resolution scenarios

    @Test func testWildcardDefaultLibMetadataImportScenarios() throws {
        let fm = FileManager.default
        var searchPaths: [String] = []
        var sources: [String] = []

        do {
            // testWildcardImportResolvesKklibSymbolInScope
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "ScopeLib",
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=3
            package _ fq=sc.util schema=v1
            function _ fq=sc.util.compute schema=v1 arity=1 sig=F1<I,I>
            class _ fq=sc.util.Engine schema=v1
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample11
            import sc.util.*
            fun main(): Int = compute(42)
            """)
        }

        do {
            // testDefaultImportResolvesKklibSymbolInScope
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "StdlibDefault",
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=3
            package _ fq=kotlin schema=v1
            package _ fq=kotlin.text schema=v1
            function _ fq=kotlin.text.isBlank schema=v1 arity=1 sig=F1<Lkotlin_String;,Z>
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample12
            fun main(): Boolean = isBlank("")
            """)
        }

        do {
            // testWildcardImportWithoutExplicitPackageRecordInMetadata
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "NoPackageRecord",
              "metadata": "metadata.bin"
            }
            """
            // Metadata has no explicit package records; packages should be synthesized
            let metadata = """
            symbols=2
            function _ fq=np.api.doWork schema=v1 arity=0
            class _ fq=np.api.Worker schema=v1
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample13
            import np.api.*
            fun main() = doWork()
            """)
        }

        do {
            // testMultipleKklibWildcardImportsCoexist

            // Create first library
            let baseDir1 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir1 = baseDir1.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir1, withIntermediateDirectories: true)

            let manifest1 = """
            {
              "formatVersion": 1,
              "moduleName": "LibA",
              "metadata": "metadata.bin"
            }
            """
            let metadata1 = """
            symbols=2
            package _ fq=lib.a schema=v1
            function _ fq=lib.a.funcA schema=v1 arity=0
            """
            try manifest1.write(to: libDir1.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata1.write(to: libDir1.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

            // Create second library
            let baseDir2 = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir2 = baseDir2.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir2, withIntermediateDirectories: true)

            let manifest2 = """
            {
              "formatVersion": 1,
              "moduleName": "LibB",
              "metadata": "metadata.bin"
            }
            """
            let metadata2 = """
            symbols=2
            package _ fq=lib.b schema=v1
            function _ fq=lib.b.funcB schema=v1 arity=0
            """
            try manifest2.write(to: libDir2.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata2.write(to: libDir2.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir1.path)
            searchPaths.append(libDir2.path)
            sources.append("""
            package sample14
            import lib.a.*
            import lib.b.*
            fun main() {
                funcA()
                funcB()
            }
            """)
        }

        do {
            // testPackageSymbolCreatedEvenWhenNonPackageSymbolExistsAtSamePath
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "CoexistLib",
              "metadata": "metadata.bin"
            }
            """
            // Library has both a class 'cx.util' and functions under package 'cx.util'
            let metadata = """
            symbols=3
            class _ fq=cx.util schema=v1
            function _ fq=cx.util.process schema=v1 arity=0
            function _ fq=cx.util.transform schema=v1 arity=1 sig=F1<I,I>
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample15
            import cx.util.*
            fun main() = process()
            """)
        }

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                moduleName: "WildcardDefaultImportApp",
                emit: .kirDump,
                searchPaths: searchPaths
            )
            try runToKIR(ctx)

            // testWildcardImportResolvesKklibSymbolInScope
            do {

                let sema = try #require(ctx.sema)

                // Verify the symbol is present
                let computeSymbol = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "compute" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic)
                }
                #expect(computeSymbol != nil, "Wildcard import should make library function 'compute' available")

                // Verify no SEMA/TYPE diagnostics (proves the symbol resolved in scope)
                let semaErrors = ctx.diagnostics.diagnostics.filter {
                    $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
                }
                let semaErrorsEmpty = semaErrors.isEmpty
                #expect(semaErrorsEmpty, "Wildcard import should resolve library function without errors: \(semaErrors.map(\.code))")
            }

            // testDefaultImportResolvesKklibSymbolInScope
            do {

                let sema = try #require(ctx.sema)
                let isBlankSymbol = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "isBlank" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic)
                }
                #expect(isBlankSymbol != nil, "Default import should make library function 'isBlank' from kotlin.text available")

                let semaErrors = ctx.diagnostics.diagnostics.filter {
                    $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
                }
                let semaErrorsEmpty = semaErrors.isEmpty
                #expect(semaErrorsEmpty, "Default import should resolve library function without errors: \(semaErrors.map(\.code))")
            }

            // testWildcardImportWithoutExplicitPackageRecordInMetadata
            do {

                let sema = try #require(ctx.sema)

                // Verify synthetic package was created
                let packageSymbol = sema.symbols.allSymbols().first { symbol in
                    symbol.kind == .package &&
                        symbol.fqName.map { ctx.interner.resolve($0) } == ["np", "api"]
                }
                #expect(packageSymbol != nil, "Synthetic package 'np.api' should be created even without explicit package record")

                let doWorkSymbol = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "doWork" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic)
                }
                #expect(doWorkSymbol != nil, "Wildcard import should resolve function from synthesized package")

                let semaErrors = ctx.diagnostics.diagnostics.filter {
                    $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
                }
                let semaErrorsEmpty = semaErrors.isEmpty
                #expect(semaErrorsEmpty, "No SEMA errors expected: \(semaErrors.map(\.code))")
            }

            // testMultipleKklibWildcardImportsCoexist
            do {

                let sema = try #require(ctx.sema)

                let funcA = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "funcA" && symbol.flags.contains(.synthetic)
                }
                let funcB = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "funcB" && symbol.flags.contains(.synthetic)
                }
                #expect(funcA != nil, "funcA from lib.a should be resolved via wildcard import")
                #expect(funcB != nil, "funcB from lib.b should be resolved via wildcard import")

                let semaErrors = ctx.diagnostics.diagnostics.filter {
                    $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
                }
                let semaErrorsEmpty = semaErrors.isEmpty
                #expect(semaErrorsEmpty, "No SEMA errors expected with multiple library wildcard imports: \(semaErrors.map(\.code))")
            }

            // testPackageSymbolCreatedEvenWhenNonPackageSymbolExistsAtSamePath
            do {

                let sema = try #require(ctx.sema)

                // Verify the package symbol was created despite the class 'cx.util' existing
                let packageSymbol = sema.symbols.allSymbols().first { symbol in
                    symbol.kind == .package &&
                        symbol.fqName.map { ctx.interner.resolve($0) } == ["cx", "util"]
                }
                #expect(packageSymbol != nil, "Package 'cx.util' should be created even when class 'cx.util' exists")

                let processSymbol = sema.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "process" &&
                        symbol.kind == .function &&
                        symbol.flags.contains(.synthetic)
                }
                #expect(processSymbol != nil, "Wildcard import should resolve 'process' even when non-package symbol coexists at package path")

                let semaErrors = ctx.diagnostics.diagnostics.filter {
                    $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
                }
                let semaErrorsEmpty = semaErrors.isEmpty
                #expect(semaErrorsEmpty, "No SEMA errors expected: \(semaErrors.map(\.code))")
            }

        }
    }

    // MARK: - Default import without bundled stdlib

    @Test func testDefaultImportFromMultipleStdlibPackagesInKklib() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "StdlibMulti",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=5
        package _ fq=kotlin schema=v1
        package _ fq=kotlin.collections schema=v1
        package _ fq=kotlin.text schema=v1
        function _ fq=kotlin.collections.listOf schema=v1 arity=0 sig=F0<A>
        function _ fq=kotlin.text.trim schema=v1 arity=1 sig=F1<Lkotlin_String;,Lkotlin_String;>
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try withTemporaryFile(contents: """
        package sample0
        fun main() {
            listOf()
            trim("")
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MultiStdlibApp",
                emit: .kirDump,
                searchPaths: [libDir.path],
                includeStdlib: false
            )
            try runToKIR(ctx)


            let sema = try #require(ctx.sema)

            let listOfSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "listOf" && symbol.flags.contains(.synthetic)
            }
            let trimSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "trim" && symbol.flags.contains(.synthetic)
            }
            #expect(listOfSymbol != nil, "Default import should resolve 'listOf' from kotlin.collections")
            #expect(trimSymbol != nil, "Default import should resolve 'trim' from kotlin.text")

            let semaErrors = ctx.diagnostics.diagnostics.filter {
                $0.code.hasPrefix("KSWIFTK-SEMA") || $0.code.hasPrefix("KSWIFTK-TYPE")
            }
            let semaErrorsEmpty = semaErrors.isEmpty
            #expect(semaErrorsEmpty, "No SEMA errors expected: \(semaErrors.map(\.code))")
        }
    }
}
#endif
