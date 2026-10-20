#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m12GenericValueClassesAndBounds(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            @JvmInline value class Box<T>(val value: T) {
                fun get(): T = value
                fun <R> replace(other: R): Box<R> = Box(other)
            }
            @JvmInline value class NonNull<T: Any>(val value: T)
            @JvmInline value class Numeric<T: Number>(val value: T)
            @JvmInline value class Text<T: String>(val value: T)
            fun echo(v: Box<Int>): Box<Int> = v
            fun optional(v: Box<Int>?): Box<Int>? = v
            fun nonNull(v: NonNull<String>?): NonNull<String>? = v
            fun number(v: Numeric<Int>?): Numeric<Int>? = v
            fun text(v: Text<String>?): Text<String>? = v
            fun <T> identity(v: Box<T>): Box<T> = v
            fun main() {
                val box = Box(21)
                println(echo(box).value); println(box.get()); println(box.replace("text"))
                println(Box<String?>(null)); println(optional(null)); println(optional(box))
                println(nonNull(null)); println(nonNull(NonNull("nonnull")))
                println(number(null)); println(number(Numeric(42)))
                println(text(null)); println(text(Text("bounded")))
                val any: Any = box; println(any); println(any == Box(21)); println(box.hashCode())
                val list = listOf(box); println(list[0].value); println(identity(Box(9L)).value)
                val array = Box(intArrayOf(4, 5)); val raw: IntArray = array.value; println(raw[1])
                val read = { box.value }; println(read())
            }
            """, expected: "21\n21\nBox(value=text)\nBox(value=null)\nnull\nBox(value=21)\nnull\nNonNull(value=nonnull)\nnull\nNumeric(value=42)\nnull\nText(value=bounded)\nBox(value=21)\ntrue\n21\n21\n9\n5\n21\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m12RepeatableAnnotationsAndReflection(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.reflect.full.findAnnotations
            @Repeatable annotation class Tag(val value: String)
            @Tag("one") @Tag("two") class Marked {
                @get:Tag("get1") @get:Tag("get2") var value = 1
            }
            @Tag("fun1") @Tag("fun2") fun tagged(@Tag("p1") @Tag("p2") value: Int): Int = value
            @Target(AnnotationTarget.PROPERTY) @Repeatable annotation class PropertyTag(val value: Int)
            @PropertyTag(3) @PropertyTag(4) val top = 1
            @Tag("single") class Single
            fun main() {
                val tags = Marked::class.findAnnotations<Tag>()
                println(tags.size); println(tags[0].value); println(tags[1].value)
                println(Marked::class.annotations.size)
                println(Marked::class.java.getAnnotationsByType(Tag::class.java).size)
                val f = ::tagged; println(f.findAnnotations<Tag>()[1].value)
                println(f.parameters[0].findAnnotations<Tag>()[0].value)
                println(::top.findAnnotations<PropertyTag>()[1].value)
                println(Single::class.findAnnotations<Tag>()[0].value)
            }
            """, expected: "2\none\ntwo\n2\n2\nfun2\np1\n4\nsingle\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m12ExplicitRepeatableContainer(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.jvm.JvmRepeatable
            import kotlin.reflect.full.findAnnotations
            @Target(AnnotationTarget.CLASS) annotation class Tags(val value: Array<Tag>, val note: String = "custom")
            @Target(AnnotationTarget.CLASS) @Repeatable @JvmRepeatable(Tags::class) annotation class Tag(val value: Int)
            @Tag(1) @Tag(2) class Marked
            @Target(AnnotationTarget.ANNOTATION_CLASS) annotation class MetaTags(val value: Array<MetaTag>)
            @Target(AnnotationTarget.CLASS) @JvmRepeatable(MetaTags::class) annotation class MetaTag
            @MetaTag @MetaTag annotation class MetaMarked
            fun main() {
                val tags = Marked::class.findAnnotations<Tag>()
                println(tags.size); println(tags[0].value); println(tags[1].value)
                val javaTags = Marked::class.java.getAnnotationsByType(Tag::class.java)
                println(javaTags.size); println(javaTags[1].value)
            }
            """, expected: "2\n1\n2\n2\n2\n", mode: mode, root: root)
        }
    }

    @Test
    func m12JavaAndKotlinGenericValueABIConsumers() throws {
        try withWorkspace { root in
            let result = try compile("""
            package abi
            @JvmInline value class Box<T>(val value: T) { fun get(): T = value; fun <R> replace(other: R): Box<R> = Box(other) }
            @JvmInline value class NonNull<T: Any>(val value: T)
            @JvmInline value class Numeric<T: Number>(val value: T)
            @JvmInline value class Values<T>(val value: List<T>) { fun first(): T = value[0] }
            @JvmName("javaValues") fun javaValues(v: Values<String>): Values<String> = v
            class TT
            @JvmInline value class Fixed<T>(val value: TT)
            @JvmName("javaFixed") fun javaFixed(v: Fixed<String>): Fixed<String> = v
            fun echo(v: Box<Int>): Box<Int> = v
            fun <T> identity(v: Box<T>): Box<T> = v
            fun optional(v: Box<String>?): Box<String>? = v
            fun nonNull(v: NonNull<String>?): NonNull<String>? = v
            fun numeric(v: Numeric<Int>?): Numeric<Int>? = v
            @JvmName("javaEcho") fun javaEcho(v: Box<String>): Box<String> = v
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try """
            import abi.*
            fun main() {
                val v = Box(21); println(echo(v).value); println(identity(Box("text")).value)
                println(v.get()); println(v.replace(3L)); println(optional(null)); println(optional(Box("value")))
                println(nonNull(NonNull("nonnull"))); println(numeric(Numeric(42)))
                println(javaEcho(Box("java"))); println(Box::class.isValue)
                println(Box::class.constructors.first().call("reflect"))
                val f: (Box<Int>) -> Box<Int> = ::echo; println(f(v))
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "ConsumerKt"]).stdout == "21\ntext\n21\nBox(value=3)\nnull\nBox(value=value)\nNonNull(value=nonnull)\nNumeric(value=42)\nBox(value=java)\ntrue\nBox(value=reflect)\nBox(value=21)\n")
            }
            try """
            public class GenericConsumer {
                public static void main(String[] args) throws Exception {
                    System.out.println(abi.HelloKt.javaEcho("java"));
                    System.out.println(abi.HelloKt.class.getMethod("javaFixed", abi.TT.class).getGenericReturnType().getTypeName());
                    java.lang.reflect.Method values = abi.HelloKt.class.getMethod("javaValues", java.util.List.class);
                    System.out.println(values.getGenericParameterTypes()[0].getTypeName());
                    System.out.println(values.getGenericReturnType().getTypeName());
                    java.lang.reflect.Method listCtor = abi.Values.class.getMethod("constructor-impl", java.util.List.class);
                    System.out.println(listCtor.getGenericParameterTypes()[0].getTypeName());
                    System.out.println(listCtor.getGenericReturnType().getTypeName());
                    System.out.println(abi.Values.class.getMethod("first-impl", java.util.List.class).getGenericParameterTypes()[0].getTypeName());
                    System.out.println(abi.Box.class.getTypeParameters()[0].getName());
                    System.out.println(abi.Box.class.getDeclaredField("value").getGenericType().getTypeName());
                    System.out.println(abi.Box.class.getMethod("getValue").getGenericReturnType().getTypeName());
                    java.lang.reflect.Method ctor = abi.Box.class.getMethod("constructor-impl", Object.class);
                    System.out.println(ctor.getTypeParameters()[0].getName());
                    System.out.println(ctor.getGenericParameterTypes()[0].getTypeName());
                    Object boxed = abi.Box.class.getMethod("box-impl", Object.class).invoke(null, "boxed");
                    System.out.println(boxed);
                    System.out.println(abi.Box.class.getMethod("unbox-impl").invoke(boxed));
                }
            }
            """.write(to: root.appendingPathComponent("GenericConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "GenericConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "GenericConsumer"]).stdout == "java\nabi.TT\njava.util.List<java.lang.String>\njava.util.List<java.lang.String>\njava.util.List<? extends T>\njava.util.List<T>\njava.util.List<? extends T>\nT\nT\nT\nT\nT\nBox(value=boxed)\nboxed\n")
        }
    }

    @Test
    func m12RepeatablePoliciesAndExternalConsumers() throws {
        try withWorkspace { root in
            let result = try compile("""
            package ann
            @Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION, AnnotationTarget.VALUE_PARAMETER, AnnotationTarget.FIELD, AnnotationTarget.PROPERTY_GETTER)
            @Retention(AnnotationRetention.RUNTIME) @MustBeDocumented @Repeatable annotation class Tag(val value: String)
            @Retention(AnnotationRetention.BINARY) @Repeatable annotation class Binary(val n: Int)
            @Retention(AnnotationRetention.SOURCE) @Repeatable annotation class Source(val n: Int)
            @Tag("one") @Tag("two") @Binary(1) @Binary(2) @Source(1) @Source(2)
            class Marked { @get:Tag("g1") @get:Tag("g2") @field:Tag("f1") @field:Tag("f2") val value = 1 }
            @Tag("fun1") @Tag("fun2") fun tagged(@Tag("p1") @Tag("p2") n: Int): Int = n
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try """
            import ann.*
            import kotlin.reflect.full.findAnnotations
            @Tag("new1") @Tag("new2") class NewClass
            fun main() {
                println(Marked::class.findAnnotations<Tag>().map { it.value }.joinToString(","))
                println(Marked::class.annotations.filterIsInstance<Tag>().size)
                println(NewClass::class.findAnnotations<Tag>().map { it.value }.joinToString(","))
                println(::tagged.findAnnotations<Tag>()[1].value)
                println(::tagged.parameters[0].findAnnotations<Tag>()[1].value)
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + jar + ":" + runtime, "ConsumerKt"]).stdout == "one,two\n2\nnew1,new2\nfun2\np2\n")
            try """
            @ann.Tag("java1") @ann.Tag("java2")
            public class RepeatConsumer {
                public static void main(String[] args) throws Exception {
                    System.out.println(ann.Marked.class.getAnnotationsByType(ann.Tag.class).length);
                    System.out.println(RepeatConsumer.class.getAnnotationsByType(ann.Tag.class)[1].value());
                    System.out.println(ann.Marked.class.getDeclaredField("value").getAnnotationsByType(ann.Tag.class)[1].value());
                    System.out.println(ann.Marked.class.getMethod("getValue").getAnnotationsByType(ann.Tag.class)[0].value());
                    Class<?> container = ann.Tag.class.getAnnotation(java.lang.annotation.Repeatable.class).value();
                    System.out.println(container.isAnnotation()); System.out.println(container.getSimpleName());
                    System.out.println(ann.Tag.class.getDeclaredClasses()[0] == container);
                    System.out.println(container.getAnnotation(java.lang.annotation.Documented.class) != null);
                }
            }
            """.write(to: root.appendingPathComponent("RepeatConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "RepeatConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "RepeatConsumer"]).stdout == "2\njava2\nf2\ng1\ntrue\nContainer\ntrue\ntrue\n")
            let bytecode = try jvmTool("javap", ["-v", "-cp", jar, "ann.Marked"], root: root).stdout
            #expect(bytecode.contains("RuntimeInvisibleAnnotations")); #expect(bytecode.contains("ann.Binary$Container")); #expect(!bytecode.contains("ann.Source"))
        }
    }

    @Test(arguments: [
        "annotation class Tag; @Tag @Tag class Marked",
        "@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION) annotation class Tags(val value: Array<Tag>); @Target(AnnotationTarget.CLASS) @kotlin.jvm.JvmRepeatable(Tags::class) annotation class Tag",
        "@Repeatable class Invalid",
        "@Target(AnnotationTarget.TYPEALIAS) annotation class Tags(val value: Array<Tag>); @kotlin.jvm.JvmRepeatable(Tags::class) annotation class Tag",
        "@Repeatable annotation class Tag { class Container }",
        "annotation class Tags(val value: Int); @kotlin.jvm.JvmRepeatable(Tags::class) annotation class Tag",
        "@Retention(AnnotationRetention.SOURCE) annotation class Tags(val value: Array<Tag>); @kotlin.jvm.JvmRepeatable(Tags::class) annotation class Tag"
    ])
    func m12InvalidRepeatableShapesAreDiagnosed(source: String) throws {
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 != 0)
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }
}
#endif
