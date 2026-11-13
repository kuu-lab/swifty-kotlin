#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func legacyJvmLibraryAPIsUseTheBundledRuntime() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            import java.util.Locale

            enum class Menu { A, B }
            class Counter(private var value: Int)

            fun acceptsVoid(value: Void?): Boolean = value == null

            fun main() {
                println("i".toUpperCase())
                println("I".toLowerCase())
                println("b" > "a")
                println(Menu.values().first { it.name == "B" })
                println(charArrayOf('b', 'c').any { it == 'c' })
                val n: Int? = 6
                println(n?.dec())
                val comparator = String.CASE_INSENSITIVE_ORDER
                println(comparator.compare("b", "B"))
                println(comparator === String.CASE_INSENSITIVE_ORDER)
                val list = ArrayList<Int>()
                list.add(9)
                println(list[0])
                println(acceptsVoid(null))
                println(String::class.java.isAssignableFrom(String::class.java))
                val field = Counter::class.java.getDeclaredField("value")
                field.isAccessible = true
                val counter = Counter(1)
                field.setInt(counter, 4)
                println(field.isAccessible)
                println(Locale.US.language)
                println(Integer.MAX_VALUE)
            }
            """
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Main.kt", source)], name: "app.jar", classpath: [stdlib.path]
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let run = try java([
                "-Xverify:all", "-Duser.language=tr", "-Duser.country=TR",
                "-cp", app.path + ":" + stdlib.path, "MainKt"
            ])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "İ\nı\ntrue\nB\ntrue\n5\n0\ntrue\n9\ntrue\ntrue\ntrue\nen\n2147483647\n")
        }
    }
}
#endif
