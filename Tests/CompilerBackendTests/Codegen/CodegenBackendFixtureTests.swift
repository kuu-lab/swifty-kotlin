#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendFixtureTests {

    @Test
    func testCodegenFixturesMatchExpectedStdout() throws {
        let fixtures = try discoverFixtures()
        #expect(
            !fixtures.isEmpty,
            "No fixtures discovered under \(Self.fixturesRoot.path); ハーネスのパス解決が壊れている可能性がある"
        )

        for fixture in fixtures {
            runFixture(fixture)
        }
    }

    @Test
    func kuu2925NestedGenericCallInBuilderInferenceLambda() {
        let relativePath = "inference/pcla_builder_nested_generic_call"
        let fixtureDirectory = Self.fixturesRoot.appendingPathComponent(relativePath, isDirectory: true)
        runFixture(Fixture(
            sourcePath: fixtureDirectory.appendingPathComponent("pcla_builder_nested_generic_call.kt").path,
            expected: "OK\n",
            relativePath: relativePath
        ))
    }

    @Test
    func kuu2925CallableReferenceInSafeBuilderCall() {
        let relativePath = "inference/pcla_builder_callable_reference_safe_call"
        let fixtureDirectory = Self.fixturesRoot.appendingPathComponent(relativePath, isDirectory: true)
        runFixture(Fixture(
            sourcePath: fixtureDirectory.appendingPathComponent("pcla_builder_callable_reference_safe_call.kt").path,
            expected: "OK\n",
            relativePath: relativePath
        ))
    }

    @Test
    func kuu3297NativeClassCastExceptionMessages() {
        let relativePath = "Exceptions/kuu3297"
        let fixtureDirectory = Self.fixturesRoot.appendingPathComponent(relativePath, isDirectory: true)
        runFixture(Fixture(
            sourcePath: fixtureDirectory.appendingPathComponent("class_cast_exception_messages.kt").path,
            expected: "OK\n",
            relativePath: relativePath
        ))
    }

    @Test
    func kuu2925AdditionalPclaInferenceCases() {
        for name in [
            "pcla_source_sink_generic_function_call",
            "pcla_type_info_source_builder_parameters",
            "pcla_type_info_source_builder_receivers",
        ] {
            let relativePath = "inference/\(name)"
            let fixtureDirectory = Self.fixturesRoot.appendingPathComponent(relativePath, isDirectory: true)
            runFixture(Fixture(
                sourcePath: fixtureDirectory.appendingPathComponent("\(name).kt").path,
                expected: "OK\n",
                relativePath: relativePath
            ))
        }
    }

    private struct Fixture {
        let sourcePath: String
        let expected: String
        let relativePath: String
    }

    private static let fixturesRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }()

    private static let diffCasesRoot: URL = fixturesRoot
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Scripts/diff_cases", isDirectory: true)

    private func discoverFixtures() throws -> [Fixture] {
        let fm = FileManager.default
        let root = Self.fixturesRoot
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var fixtures: [Fixture] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            let expectedURL = url.appendingPathComponent("expected.txt")
            guard fm.fileExists(atPath: expectedURL.path) else { continue }

            let ktFiles = try fm.contentsOfDirectory(atPath: url.path)
                .filter { $0.hasSuffix(".kt") }
                .sorted()
            let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")

            let diffCaseURL = url.appendingPathComponent("diff_case.txt")
            if ktFiles.isEmpty, fm.fileExists(atPath: diffCaseURL.path) {
                let name = try String(contentsOf: diffCaseURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let expected = try String(contentsOf: expectedURL, encoding: .utf8)
                    .replacingOccurrences(of: "\r\n", with: "\n")
                fixtures.append(
                    Fixture(
                        sourcePath: Self.diffCasesRoot.appendingPathComponent(name).path,
                        expected: expected,
                        relativePath: relativePath
                    )
                )
                continue
            }

            guard ktFiles.count == 1 else {
                Issue.record(
                    "fixture \(relativePath) は .kt を 1 つだけ含む必要がある（検出: \(ktFiles)）"
                )
                continue
            }

            let expected = try String(contentsOf: expectedURL, encoding: .utf8)
                .replacingOccurrences(of: "\r\n", with: "\n")
            fixtures.append(
                Fixture(
                    sourcePath: url.appendingPathComponent(ktFiles[0]).path,
                    expected: expected,
                    relativePath: relativePath
                )
            )
        }
        return fixtures.sorted { $0.relativePath < $1.relativePath }
    }

    private func runFixture(_ fixture: Fixture) {
        do {
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: fixture.sourcePath,
                moduleName: Self.moduleName(for: fixture.relativePath),
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout == fixture.expected,
                "fixture \(fixture.relativePath) の stdout が expected.txt と一致しない"
            )
        } catch {
            Issue.record("fixture \(fixture.relativePath) の実行に失敗: \(error)")
        }
    }

    private static func moduleName(for relativePath: String) -> String {
        let sanitized = relativePath.map { char -> Character in
            char.isLetter || char.isNumber ? char : "_"
        }
        return "Fixture_" + String(sanitized)
    }
}
#endif
