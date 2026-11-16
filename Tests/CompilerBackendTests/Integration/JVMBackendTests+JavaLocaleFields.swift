#if canImport(Testing)
import Testing

extension JVMBackendTests {
    @Test
    func javaLocaleExposesEnglishAndJapaneseFields() throws {
        try withWorkspace { root in
            let (app, status, diagnostics) = try m22Build(
                root: root,
                sources: [("Main.kt", """
                import java.util.Locale
                fun main() {
                    println(Locale.ENGLISH.language)
                    println(Locale.JAPANESE.language)
                    println(Locale.JAPAN.language)
                }
                """)],
                name: "app.jar", classpath: []
            )
            try #require(status == 0, "\(diagnostics.map(\.message))")
            let run = try java(["-Xverify:all", "-cp", app.path, "MainKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "en\nja\nja\n")
        }
    }
}
#endif
