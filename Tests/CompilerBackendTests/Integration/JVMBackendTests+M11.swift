#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    func m11Runtime() throws -> String {
        let compiler = URL(fileURLWithPath: CommandRunner.resolveExecutable("kotlinc", fallback: "/usr/bin/kotlinc")).resolvingSymlinksInPath()
        let home = compiler.deletingLastPathComponent().deletingLastPathComponent()
        let lib = [home.appendingPathComponent("lib"), home.appendingPathComponent("libexec/lib")].first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("kotlin-reflect.jar").path) } ?? home.appendingPathComponent("lib")
        let paths = ["kotlin-stdlib.jar", "kotlin-reflect.jar"].map { lib.appendingPathComponent($0).path }
        for path in paths { try #require(FileManager.default.fileExists(atPath: path), "Missing official Kotlin runtime: \(path)") }
        return paths.joined(separator: ":")
    }
    func runM11(_ source: String, expected: String, mode: EmitMode, root: URL) throws {
        let compiled = try compile(source, root: root, mode: mode)
        let diagnostics = compiled.1.map { diagnostic in
            let range = diagnostic.primaryRange.map { "\($0.start.offset)..<\($0.end.offset)" } ?? "unknown"
            return "\(range): \(diagnostic.message)"
        }
        try #require(compiled.0 == 0, "\(diagnostics)")
        let runtime = try m11Runtime()
        let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
        let generated = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
        #expect(generated.stdout == expected)
        #expect(generated.stderr.isEmpty)
        _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
        let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
        #expect(reference.stdout == expected)
        #expect(reference.stderr.isEmpty)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11ValueClassesBoxingDispatchAndDefaults(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            var creations = 0
            interface Measure { fun add(other: Meter): Meter }
            @JvmInline value class Meter(val value: Int): Measure {
                init { creations += 1 }
                override fun add(other: Meter): Meter = Meter(value + other.value)
                fun step(n: Int = 1): Meter = Meter(value + n)
            }
            class Box(val meter: Meter)
            fun twice(m: Meter = Meter(5)): Meter = Meter(m.value * 2)
            fun identity(m: Meter?): Meter? = m
            fun <T> same(value: T): T = value
            fun main() {
                val m = Meter(20)
                val boxed: Any = m
                println(creations); println(boxed); println(creations)
                val list = listOf(m); println(list[0].value); println(same(m).value)
                println(twice(m)); println(twice()); println(m.step()); println(m.step(3))
                val target: Measure = m
                println(target.add(Meter(2))); println(Box(m).meter.value)
                println(identity(null)); println(identity(m)); println(m == Meter(20)); println(m.hashCode())
                val capture = { m.value }; println(capture())
                val holder = object { fun read(): Int = m.value }; println(holder.read())
            }
            """, expected: "1\nMeter(value=20)\n1\n20\n20\nMeter(value=40)\nMeter(value=10)\nMeter(value=21)\nMeter(value=23)\nMeter(value=22)\n20\nnull\nMeter(value=20)\ntrue\n20\n20\n20\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11ReferenceAndWideValueClasses(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            @JvmInline value class Text(val value: String)
            @JvmInline value class OptionalText(val value: String?)
            @JvmInline value class Wide(val value: Long)
            @JvmInline value class Real(val value: Double)
            fun text(v: Text?): Text? = v
            fun optional(v: OptionalText?): OptionalText? = v
            fun wide(v: Wide): Wide = Wide(v.value + 1L)
            fun real(v: Real): Real = v
            fun main() {
                println(text(null)); println(text(Text("hello")))
                println(optional(null)); println(optional(OptionalText(null)))
                println(wide(Wide(9000000000L))); println(real(Real(2.5)))
                val nan = Real(0.0 / 0.0)
                println(nan == Real(0.0 / 0.0)); println(Real(0.0) == Real(-0.0))
                println(Text::class.isValue); println(Wide::class.simpleName)
            }
            """, expected: "null\nText(value=hello)\nnull\nOptionalText(value=null)\nWide(value=9000000001)\nReal(value=2.5)\ntrue\nfalse\ntrue\nWide\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11AliasesAndCallableReflection(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            typealias Count = Int
            typealias Numbers<T> = List<T>
            var top: Count = 2
            class Box(var value: Count) { fun add(n: Count): Count = value + n }
            fun twice(n: Count): Count = n * 2
            fun main() {
                println(Box::class.simpleName); println(Box::class.qualifiedName)
                val b = Box(20); println(b::class.isInstance(b))
                val f = ::twice; println(f.name); println(f(21)); println(f.call(3))
                val bound = b::add; println(bound(4)); println(bound.parameters.size)
                val p = Box::value; println(p.name); println(p.get(b)); p.set(b, 30)
                val bp = b::value; println(bp.get()); bp.set(40); println(b.value)
                val t = ::top; println(t.get()); t.set(5); println(top)
                val ctor = ::Box; println(ctor(7).value)
                val numbers: Numbers<Count> = listOf(1, 2); println(numbers.size)
                println(Int::class.simpleName); println(Box::class.java.name)
            }
            """, expected: "Box\nBox\ntrue\ntwice\n42\n6\n24\n1\nvalue\n20\n30\n40\n2\n5\n7\n2\nInt\nBox\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11MapEntryDestructuringIteration(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val m = mapOf("b" to 2, "a" to 1)
                for ((k, v) in m) print("$k$v ")
                println()
            }
            """, expected: "b2 a1 \n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11AnnotationConstantsAndReflection(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.reflect.KClass
            import kotlin.reflect.full.findAnnotation
            import kotlin.reflect.full.memberProperties
            @Retention(AnnotationRetention.RUNTIME)
            @Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION, AnnotationTarget.FIELD, AnnotationTarget.PROPERTY_GETTER, AnnotationTarget.VALUE_PARAMETER)
            annotation class Label(val text: String, val count: Int = 2 * 3)
            enum class Kind { ONE, TWO }
            annotation class Details(val label: Label, val kind: Kind, val numbers: IntArray, val type: KClass<*>, val types: Array<KClass<*>>)
            @Label("box", 42)
            @Details(Label("nested"), Kind.TWO, [1, 2, 3], Box::class, [Int::class, Box::class])
            class Box(@field:Label("field") @get:Label("getter") var value: Int)
            @Label("function") fun tagged(@Label("parameter") n: Int): Int = n
            fun main() {
                println(Box::class.annotations.size)
                val label = Box::class.findAnnotation<Label>()!!
                println(label.text); println(label.count)
                val details = Box::class.findAnnotation<Details>()!!
                println(details.label.text); println(details.kind); println(details.numbers[1]); println(details.type.simpleName); println(details.types[0].simpleName)
                println(Box::class.memberProperties.size)
                println(::tagged.annotations.size)
                println(Box::class.java.getAnnotation(Label::class.java)!!.text)
            }
            """, expected: "2\nbox\n42\nnested\nTWO\n2\nBox\nInt\n1\n1\nbox\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11LoweredCallableSignaturesAndClassInitialization(mode: EmitMode) throws {
        try withWorkspace { root in
            let parameters = (0..<32).map { "p\($0): Int = \($0)" }.joined(separator: ", ")
            try runM11("""
            @JvmInline value class Token(val n: Int)
            abstract class Base { abstract fun echo(v: Token): Token }
            class Impl: Base() { override fun echo(v: Token): Token = v }
            class Cold { companion object { init { println("INIT") } } }
            fun echo(v: Token): Token = v
            fun Token.many(\(parameters)): Token = Token(n + p31)
            @JvmName("renamed") fun named(n: Int): Int = n + 1
            fun main() {
                println(Cold::class.simpleName)
                val f = ::echo; println(f(Token(3))); println(f.call(Token(4)))
                val ctor = ::Token; println(ctor.name); println(ctor(5)); println(ctor.call(6))
                val renamed = ::named; println(renamed(8)); println(renamed.name)
                val base: Base = Impl(); println(base.echo(Token(7))); println(Token(1).many())
            }
            """, expected: "Cold\nToken(n=3)\nToken(n=4)\n<init>\nToken(n=5)\nToken(n=6)\n9\nnamed\nToken(n=7)\nToken(n=32)\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m11PropertyAnnotationsAndVarargs(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.reflect.full.findAnnotation
            @Target(AnnotationTarget.PROPERTY) annotation class PropertyTag(val name: String)
            annotation class Tags(vararg val names: String = ["default"])
            @Tags class DefaultMarked
            object Constants { init { println("UNEXPECTED INIT") }; const val NUMBER = 42 }
            @PropertyTag("top") val top = 1
            class Box { @PropertyTag("member") var value = 2 }
            @Tags(names = ["one", "two"]) class Marked
            fun main() {
                println(::top.findAnnotation<PropertyTag>()!!.name)
                println(Box::value.findAnnotation<PropertyTag>()!!.name)
                val tags = Marked::class.findAnnotation<Tags>()!!
                println(tags.names.size); println(tags.names[0]); println(tags.names[1])
                println(DefaultMarked::class.findAnnotation<Tags>()!!.names[0]); println(Constants.NUMBER)
            }
            """, expected: "top\nmember\n2\none\ntwo\ndefault\n42\n", mode: mode, root: root)
        }
    }

    @Test
    func m11JavaAndKotlinConsumersUseMetadataAndValueABI() throws {
        try withWorkspace { root in
            let source = """
            package abi
            typealias Count = Int
            typealias Values<T> = List<T>
            @Retention(AnnotationRetention.RUNTIME) annotation class Label(val text: String = "default")
            @Label("meter") @JvmInline value class Meter(val value: Count) {
                fun add(other: Meter): Meter = Meter(value + other.value)
            }
            @Label("box") class Box @Label("ctor") constructor(@Label("parameter") val meter: Meter)
            fun twice(m: Meter = Meter(5)): Meter = Meter(m.value * 2)
            class Nested { @JvmInline value class Code(val n: Int) }
            fun nested(v: Nested.Code): Nested.Code = v
            @JvmName("plusMeter") fun plus(a: Meter, b: Meter): Meter = Meter(a.value + b.value)
            """
            let result = try compile(source, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let runtime = try m11Runtime(), jar = root.appendingPathComponent("hello.jar").path
            try """
            import abi.*
            fun main() {
                val n: Count = 20; val values: Values<Count> = listOf(n)
                val m = Meter(values[0]); println(twice(m)); println(twice()); println(m.add(Meter(2)))
                println(plus(m, Meter(3))); println(Box(m).meter.value); println(nested(Nested.Code(9)).n)
                println(Meter::class.isValue); println(Meter::class.constructors.first().call(7))
                println(Box::class.annotations.filterIsInstance<Label>().first().text)
                println(Box::class.constructors.first().annotations.filterIsInstance<Label>().first().text)
                println(Box::class.constructors.first().parameters[0].annotations.filterIsInstance<Label>().first().text)
                println(Label::class.constructors.first().callBy(emptyMap()).text)
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            let consumer = root.appendingPathComponent("consumer.jar").path
            for cp in [consumer + ":" + jar + ":" + runtime, runtime + ":" + jar + ":" + consumer] {
                #expect(try java(["-cp", cp, "ConsumerKt"]).stdout == "Meter(value=40)\nMeter(value=10)\nMeter(value=22)\nMeter(value=23)\n20\n9\ntrue\nMeter(value=7)\nbox\nctor\nparameter\ndefault\n")
            }
            try """
            public class JavaConsumer {
                public static void main(String[] args) throws Exception {
                    System.out.println(abi.Box.class.getAnnotation(abi.Label.class).text());
                    Class<?> meter = abi.Meter.class;
                    Object boxed = meter.getMethod("box-impl", int.class).invoke(null, 7);
                    System.out.println(boxed);
                    System.out.println(meter.getMethod("unbox-impl").invoke(boxed));
                    System.out.println(abi.HelloKt.plusMeter(20, 3));
                    System.out.println(meter.getMethod("equals-impl0", int.class, int.class).invoke(null, 4, 4));
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "box\nMeter(value=7)\n7\n23\ntrue\n")
        }
    }

    @Test
    func m11RetentionTargetsParametersAndConstantValues() throws {
        try withWorkspace { root in
            let result = try compile("""
            package attrs
            import kotlin.reflect.KClass
            @Retention(AnnotationRetention.RUNTIME)
            @Target(AnnotationTarget.CLASS, AnnotationTarget.VALUE_PARAMETER, AnnotationTarget.FIELD, AnnotationTarget.PROPERTY_GETTER, AnnotationTarget.PROPERTY_SETTER, AnnotationTarget.CONSTRUCTOR)
            annotation class Mark(val n: Int = 1)
            @Target(AnnotationTarget.FIELD) annotation class FieldOnly
            @Retention(AnnotationRetention.BINARY) annotation class Binary
            @Retention(AnnotationRetention.SOURCE) annotation class Source
            annotation class Tags(vararg val names: String)
            @FieldOnly const val NUMBER: Int = 6 * 7
            object Constants { const val TEXT: String = "const" }
            @Binary @Source @Mark(NUMBER) class Box @Mark(8) constructor(@param:Mark(2) @field:Mark(3) @get:Mark(4) @set:Mark(5) @setparam:Mark(6) var value: Int)
            fun tagged(@Mark(7) n: Int): Int = n
            fun String.ext(@Mark(9) n: Int): Int = n
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try """
            import attrs.*
            @Tags("a", "b") class FromKotlin
            fun main() {
                println(NUMBER); println(Constants.TEXT)
                println(Box::class.constructors.first().annotations.filterIsInstance<Mark>().first().n)
                println(Box::class.constructors.first().parameters[0].annotations.filterIsInstance<Mark>().first().n)
                println(::tagged.parameters[0].annotations.filterIsInstance<Mark>().first().n)
                println(String::ext.parameters[1].annotations.filterIsInstance<Mark>().first().n)
                println(FromKotlin::class.annotations.filterIsInstance<Tags>().first().names.size)
                println(Mark::class.annotations.filterIsInstance<kotlin.annotation.Retention>().first().value)
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + jar + ":" + runtime, "ConsumerKt"]).stdout == "42\nconst\n8\n2\n7\n9\n2\nRUNTIME\n")
            try """
            public class Attributes {
                public static void main(String[] args) throws Exception {
                    System.out.println(attrs.Box.class.getAnnotation(attrs.Mark.class).n());
                    System.out.println(attrs.Box.class.getAnnotation(attrs.Binary.class) == null);
                    System.out.println(attrs.Box.class.getAnnotation(attrs.Source.class) == null);
                    System.out.println(attrs.Box.class.getDeclaredField("value").getAnnotation(attrs.Mark.class).n());
                    System.out.println(attrs.Box.class.getMethod("getValue").getAnnotation(attrs.Mark.class).n());
                    System.out.println(attrs.Box.class.getMethod("setValue", int.class).getAnnotation(attrs.Mark.class).n());
                    System.out.println(((attrs.Mark)attrs.Box.class.getMethod("setValue", int.class).getParameterAnnotations()[0][0]).n());
                    System.out.println(((attrs.Mark)attrs.HelloKt.class.getMethod("ext", String.class, int.class).getParameterAnnotations()[1][0]).n());
                    System.out.println(attrs.Mark.class.getAnnotation(kotlin.annotation.Target.class).allowedTargets().length);
                    System.out.println(attrs.HelloKt.class.getField("NUMBER").isAnnotationPresent(attrs.FieldOnly.class));
                    System.out.println(attrs.HelloKt.NUMBER);
                    System.out.println(attrs.Constants.TEXT);
                }
            }
            """.write(to: root.appendingPathComponent("Attributes.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "Attributes.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "Attributes"]).stdout == "42\ntrue\ntrue\n3\n4\n5\n6\n9\n6\ntrue\n42\nconst\n")
            let bytecode = try jvmTool("javap", ["-v", "-cp", jar, "attrs.Box"], root: root).stdout
            #expect(bytecode.contains("RuntimeInvisibleAnnotations"))
            #expect(!bytecode.contains("attrs.Source"))
        }
    }

    @Test(arguments: [
        "@file:JvmName(\"Ignored\")\nfun main() {}",
        "annotation class Number(val n: Int); fun bad(@Number(\"wrong\") n: Int): Int = n",
        "annotation class Number(val n: Int); fun bad(@Number(4294967296) n: Int): Int = n",
        "@JvmName(\"second\") fun first(): Int = 1; fun second(): Int = 2"
    ])
    func m11UnsupportedShapesFailBeforeEmission(source: String) throws {
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 != 0)
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }
}
#endif
