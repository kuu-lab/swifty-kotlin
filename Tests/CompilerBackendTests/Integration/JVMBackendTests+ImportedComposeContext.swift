#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedTopLevelComposablePreservesContextReceiver() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root)
            let classBytes = try #require(Data(base64Encoded: """
            yv66vgAAADQAPAEAFGZpeHR1cmUvQ29udGV4dEFwaUt0BwABAQAQamF2YS9sYW5nL09iamVjdAcAAwEABWxhYmVsAQBHKExmaXh0
            dXJlL1Rva2VuO0xhbmRyb2lkeC9jb21wb3NlL3J1bnRpbWUvQ29tcG9zZXI7SSlMamF2YS9sYW5nL1N0cmluZzsBACVMYW5kcm9p
            ZHgvY29tcG9zZS9ydW50aW1lL0NvbXBvc2FibGU7AQAjTG9yZy9qZXRicmFpbnMvYW5ub3RhdGlvbnMvTm90TnVsbDsBACRMb3Jn
            L2pldGJyYWlucy9hbm5vdGF0aW9ucy9OdWxsYWJsZTsBAAV0b2tlbggACgEAHmtvdGxpbi9qdm0vaW50ZXJuYWwvSW50cmluc2lj
            cwcADAEAFWNoZWNrTm90TnVsbFBhcmFtZXRlcgEAJyhMamF2YS9sYW5nL09iamVjdDtMamF2YS9sYW5nL1N0cmluZzspVgwADgAP
            CgANABADp91FLgEAIWFuZHJvaWR4L2NvbXBvc2UvcnVudGltZS9Db21wb3NlcgcAEwEAFXN0YXJ0UmVwbGFjZWFibGVHcm91cAEA
            BChJKVYMABUAFgsAFAAXAQANZml4dHVyZS9Ub2tlbgcAGQEACGdldFZhbHVlAQAUKClMamF2YS9sYW5nL1N0cmluZzsMABsAHAoA
            GgAdAQATZW5kUmVwbGFjZWFibGVHcm91cAEAAygpVgwAHwAgCwAUACEBAA9MZml4dHVyZS9Ub2tlbjsBAAkkY29tcG9zZXIBACNM
            YW5kcm9pZHgvY29tcG9zZS9ydW50aW1lL0NvbXBvc2VyOwEACCRjaGFuZ2VkAQABSQEAEUxrb3RsaW4vTWV0YWRhdGE7AQACbXYD
            AAAAAgMAAAAEAwAAAAABAAFrAQACeGkDAAAAMAEAAmQxAQA3wIASCsCACgIQDgoCGAIKAggCCgIYAhodEMCAGgIwAUgHUgIwAmIC
            CAVqBhADGgIwAsKiBgIQBAEAAmQyAQAAAQANQ29udGV4dEFwaS5rdAEABENvZGUBAA9MaW5lTnVtYmVyVGFibGUBABJMb2NhbFZh
            cmlhYmxlVGFibGUBABtSdW50aW1lSW52aXNpYmxlQW5ub3RhdGlvbnMBACRSdW50aW1lSW52aXNpYmxlUGFyYW1ldGVyQW5ub3Rh
            dGlvbnMBAApTb3VyY2VGaWxlAQAZUnVudGltZVZpc2libGVBbm5vdGF0aW9ucwAxAAIABAAAAAAAAQAZAAUABgADADUAAABZAAIA
            BAAAABsqEgu4ABErEhK5ABgCACq2AB5OK7kAIgEALbAAAAACADYAAAAGAAEABgAIADcAAAAgAAMAAAAbAAoAIwAAAAAAGwAkACUA
            AQAAABsAJgAnAAIAOAAAAAoAAgAHAAAACAAAADkAAAAPAwABAAgAAAABAAkAAAAAAAIAOgAAAAIANAA7AAAAPQABACgABQApWwAD
            SQAqSQArSQAsAC1JACoALkkALwAwWwABcwAxADJbAAZzAAVzADNzACNzAApzAAZzAAc=
            """, options: .ignoreUnknownCharacters))
            let provider = root.appendingPathComponent("provider/fixture")
            try FileManager.default.createDirectory(at: provider, withIntermediateDirectories: true)
            try classBytes.write(to: provider.appendingPathComponent("ContextApiKt.class"))
            try """
            package fixture;
            public final class Token {
                private final String value;
                public Token(String value) { this.value = value; }
                public String getValue() { return value; }
            }
            """.write(to: root.appendingPathComponent("Token.java"), atomically: true, encoding: .utf8)
            let tokenBuild = try jvmTool("javac", ["--release", "8", "-d", "provider", "Token.java"], root: root)
            try #require(tokenBuild.exitCode == 0, "\(tokenBuild.stderr)")

            let consumer = """
            import androidx.compose.runtime.Composable
            import fixture.Token
            import fixture.label

            context(token: Token)
            @Composable fun Screen(): String = label()
            """
            let classpath = [root.appendingPathComponent("provider").path, runtime.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Screen.kt", consumer)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")

            try """
            import fixture.Bridge;
            import fixture.Token;
            public final class Driver {
                public static void main(String[] args) {
                    System.out.println(ScreenKt.Screen(new Token("context-value"), Bridge.COMPOSER, 0));
                }
            }
            """.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let runClasspath = ([app.path] + classpath).joined(separator: ":")
            let compiled = try jvmTool("javac", ["-cp", runClasspath, "-d", "driver", "Driver.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let driver = root.appendingPathComponent("driver").path
            let run = try java(["-Xverify:all", "-cp", runClasspath + ":" + driver, "Driver"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "context-value\n")
        }
    }
}
#endif
