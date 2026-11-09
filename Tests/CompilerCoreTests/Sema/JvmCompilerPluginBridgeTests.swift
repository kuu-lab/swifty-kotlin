#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Tests dynamic loading and inspection of real kotlinc compiler plugin JARs
/// via `JvmPluginHostClient` and `JvmCompilerPlugin`.
@Suite
struct JvmCompilerPluginBridgeTests {

    private let allOpenJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/allopen-compiler-plugin.jar"
    private let noArgJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/noarg-compiler-plugin.jar"
    private let parcelizeJarPath = "/opt/homebrew/Cellar/kotlin/2.4.21/libexec/lib/parcelize-compiler.jar"

    @Test
    func testHostInspectsAllOpenJar() throws {
        guard FileManager.default.fileExists(atPath: allOpenJarPath) else {
            return
        }
        let result = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: allOpenJarPath)
        #expect(result.pluginId == "org.jetbrains.kotlin.allopen")
        #expect(result.commandLineProcessor == "org.jetbrains.kotlin.allopen.AllOpenCommandLineProcessor")
        #expect(result.registrar == "org.jetbrains.kotlin.allopen.AllOpenComponentRegistrar")

        let optionNames = Set(result.options.map(\.name))
        #expect(optionNames.contains("annotation"))
        #expect(optionNames.contains("preset"))
    }

    @Test
    func testHostInspectsNoArgJar() throws {
        guard FileManager.default.fileExists(atPath: noArgJarPath) else {
            return
        }
        let result = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: noArgJarPath)
        #expect(result.pluginId == "org.jetbrains.kotlin.noarg")
        #expect(result.commandLineProcessor == "org.jetbrains.kotlin.noarg.NoArgCommandLineProcessor")

        let optionNames = Set(result.options.map(\.name))
        #expect(optionNames.contains("annotation"))
        #expect(optionNames.contains("invokeInitializers"))
    }

    @Test
    func testHostInspectsParcelizeJar() throws {
        guard FileManager.default.fileExists(atPath: parcelizeJarPath) else {
            return
        }
        let result = try JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: parcelizeJarPath)
        #expect(result.pluginId == "org.jetbrains.kotlin.parcelize")

        let optionNames = Set(result.options.map(\.name))
        #expect(optionNames.contains("additionalAnnotation"))
    }

    @Test
    func testDynamicPluginWarnsOnUnknownOptionInSema() throws {
        guard FileManager.default.fileExists(atPath: allOpenJarPath) else {
            return
        }
        let source = """
        package com.example

        class Hello
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let flags = [
                "-Xplugin=\(allOpenJarPath)",
                "plugin:org.jetbrains.kotlin.allopen:unknownOption=value",
            ]
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: .kirDump,
                frontendFlags: flags
            )
            try runSema(ctx)
            let warnings = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-PLUGIN-0001" }
            #expect(!warnings.isEmpty, "expected warning KSWIFTK-PLUGIN-0001 for unknown option")
        }
    }
}
#endif
