@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// RF-TEST-001: fixture 駆動の Codegen 実行テストハーネス。
///
/// `Tests/CompilerBackendTests/Fixtures/` 以下を実行時に走査し、`expected.txt` を
/// 持つ各ディレクトリを 1 fixture として扱う。fixture は同ディレクトリ内の単一
/// `*.kt` を `kswiftc`（Codegen → Link）でコンパイル・実行し、stdout を
/// `expected.txt` と比較する。
///
/// 新しいケースは fixture ディレクトリ（`<領域>/<ケース名>/<ケース名>.kt` +
/// `expected.txt`）を追加するだけで自動検出され、テストクラスの編集は不要。
/// 詳細は `Tests/CompilerBackendTests/Fixtures/README.md` を参照。
final class CodegenBackendFixtureTests: CodegenBackendTestSupport {

    /// 全 fixture を検出して実行する単一エントリポイント。
    /// 各 fixture の失敗はケースの相対パス付きで報告され、1 件の失敗が他の
    /// fixture の実行を止めないようにする。
    func testCodegenFixturesMatchExpectedStdout() throws {
        let fixtures = try discoverFixtures()
        XCTAssertFalse(
            fixtures.isEmpty,
            "No fixtures discovered under \(Self.fixturesRoot.path); ハーネスのパス解決が壊れている可能性がある"
        )

        for fixture in fixtures {
            runFixture(fixture)
        }
    }

    // MARK: - Fixture discovery

    /// `expected.txt` を持つ fixture ディレクトリの記述子。
    private struct Fixture {
        /// 実行対象の Kotlin ソース（`fun main()` を持つ）。
        let sourcePath: String
        /// 期待する stdout。
        let expected: String
        /// `Fixtures/` からの相対パス（診断・モジュール名生成に使用）。
        let relativePath: String
    }

    /// テストソースの位置から `Fixtures/` ルートを解決する。
    /// SwiftPM のリソースバンドルに依存せず、`Scripts/diff_cases` を参照する
    /// 既存テストと同じ `#filePath` 相対方式を採る。
    private static let fixturesRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerBackendTests/
            .appendingPathComponent("Fixtures", isDirectory: true)
    }()

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

            guard ktFiles.count == 1 else {
                XCTFail(
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

    // MARK: - Fixture execution

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
            XCTAssertEqual(
                normalizedStdout,
                fixture.expected,
                "fixture \(fixture.relativePath) の stdout が expected.txt と一致しない"
            )
        } catch {
            XCTFail("fixture \(fixture.relativePath) の実行に失敗: \(error)")
        }
    }

    /// 相対パスから安定した識別子（モジュール名）を生成する。
    private static func moduleName(for relativePath: String) -> String {
        let sanitized = relativePath.map { char -> Character in
            char.isLetter || char.isNumber ? char : "_"
        }
        return "Fixture_" + String(sanitized)
    }
}
