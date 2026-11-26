#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct WasmLibraryBodyImportTests {
    @Test
    func nonVirtualMemberBodyShipsInWasmLibraryAndMaterializesInConsumer() throws {
        let libraryPath = try compileWasmLibrary(
            moduleName: "BoxLib",
            source: """
            package test

            class Box {
                companion object {
                    fun parse(value: String): String = value + "!"
                }
            }
            """
        )
        defer { try? FileManager.default.removeItem(atPath: libraryPath) }

        let metadata = try Data(contentsOf: URL(fileURLWithPath: libraryPath + "/metadata.bin"))
        let parseRecord = try #require(MetadataDecoder().decode(metadata).first {
            $0.kind == .function && $0.fqName == "test.Box.Companion.parse"
        })
        let linkName = try #require(parseRecord.externalLinkName)
        let kirPath = libraryPath + "/inline-kir/" + MetadataEncoder.inlineKIRFileName(for: linkName)
        #expect(FileManager.default.fileExists(atPath: kirPath))

        let wasm = try compileWasmConsumer(
            moduleName: "BoxConsumer",
            source: """
            import test.Box

            fun main() {
                val x = Box.parse("x")
            }
            """,
            libraryPath: libraryPath
        )
        #expect(wasm.range(of: Data("$stub_\(linkName)".utf8)) == nil)
    }

    @Test
    func initTransitiveDependencyIncludesDefaultArgumentStub() throws {
        let libraryPath = try compileWasmLibrary(
            moduleName: "ClosureLib",
            source: """
            package test

            class Box {
                companion object {
                    private fun helper(value: String = "x"): String = value
                    fun parse(): String = helper()
                }
            }

            object Registry {
                val value: String = Box.parse()
            }
            """
        )
        defer { try? FileManager.default.removeItem(atPath: libraryPath) }

        let wasm = try compileWasmConsumer(
            moduleName: "ClosureConsumer",
            source: """
            import test.Registry

            fun main() {
                val x = Registry.value
            }
            """,
            libraryPath: libraryPath
        )
        #expect(wasm.range(of: Data("$stub_kk_fn_helper".utf8)) == nil)
        #expect(wasm.range(of: Data("kk_fn_helper_default".utf8)) != nil)
    }

    @Test
    func initTransitiveClosureDoesNotShipVirtualMemberBodies() throws {
        let libraryPath = try compileWasmLibrary(
            moduleName: "VirtualLib",
            source: """
            package test

            open class Base {
                open fun value(): String = "B"
            }

            object Registry {
                val value: String = Base().value()
            }
            """
        )
        defer { try? FileManager.default.removeItem(atPath: libraryPath) }

        let metadata = try Data(contentsOf: URL(fileURLWithPath: libraryPath + "/metadata.bin"))
        let valueRecord = try #require(MetadataDecoder().decode(metadata).first {
            $0.kind == .function && $0.fqName == "test.Base.value"
        })
        let linkName = try #require(valueRecord.externalLinkName)
        let kirPath = libraryPath + "/inline-kir/" + MetadataEncoder.inlineKIRFileName(for: linkName)
        #expect(!FileManager.default.fileExists(atPath: kirPath))
    }

    @Test
    func superCallDependencyShipsDespiteOpenModality() throws {
        let libraryPath = try compileWasmLibrary(
            moduleName: "SuperLib",
            source: """
            package test

            open class Base {
                open fun value(): String = "B"
            }

            class Child : Base() {
                override fun value(): String = "C"
                fun readSuper(): String = super.value()
            }
            """
        )
        defer { try? FileManager.default.removeItem(atPath: libraryPath) }

        let metadata = try Data(contentsOf: URL(fileURLWithPath: libraryPath + "/metadata.bin"))
        let valueRecord = try #require(MetadataDecoder().decode(metadata).first {
            $0.kind == .function && $0.fqName == "test.Base.value"
        })
        let linkName = try #require(valueRecord.externalLinkName)
        let kirPath = libraryPath + "/inline-kir/" + MetadataEncoder.inlineKIRFileName(for: linkName)
        #expect(FileManager.default.fileExists(atPath: kirPath))

        let wasm = try compileWasmConsumer(
            moduleName: "SuperConsumer",
            source: """
            import test.Child

            fun main() {
                val x = Child().readSuper()
            }
            """,
            libraryPath: libraryPath
        )
        #expect(wasm.range(of: Data("$stub_value".utf8)) == nil)
    }

    @Test
    func sameNamedPrivateMemberBodiesRemainDistinct() throws {
        let libraryPath = try compileWasmLibrary(
            moduleName: "CollisionLib",
            source: """
            package test

            class Left {
                private fun value(): String = "L"
                fun read(): String = value()
            }

            class Right {
                private fun value(): String = "R"
                fun read(): String = value()
            }
            """
        )
        defer { try? FileManager.default.removeItem(atPath: libraryPath) }

        let wasm = try compileWasmConsumer(
            moduleName: "CollisionConsumer",
            source: """
            import test.Left
            import test.Right

            fun main() {
                val l = Left().read()
                val r = Right().read()
            }
            """,
            libraryPath: libraryPath
        )
        #expect(wasm.range(of: Data("$stub_kk_fn_value".utf8)) == nil)
    }

    private func compileWasmLibrary(moduleName: String, source: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourcePath = directory.appendingPathComponent("Library.kt")
        try source.write(to: sourcePath, atomically: true, encoding: .utf8)
        let libraryBase = directory.appendingPathComponent(moduleName)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: moduleName,
            inputs: [sourcePath.path],
            outputPath: libraryBase.path,
            emit: .library,
            target: .wasmWASI,
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )))
        let persistedPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(moduleName)-\(UUID().uuidString).kklib")
        try FileManager.default.moveItem(
            at: libraryBase.appendingPathExtension("kklib"),
            to: persistedPath
        )
        return persistedPath.path
    }

    private func compileWasmConsumer(moduleName: String, source: String, libraryPath: String) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourcePath = directory.appendingPathComponent("Main.kt")
        try source.write(to: sourcePath, atomically: true, encoding: .utf8)
        let wasmPath = directory.appendingPathComponent("main.wasm")
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: moduleName,
            inputs: [sourcePath.path],
            outputPath: wasmPath.path,
            emit: .executable,
            searchPaths: [libraryPath],
            target: .wasmWASI,
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )))
        return try Data(contentsOf: wasmPath)
    }
}
#endif
