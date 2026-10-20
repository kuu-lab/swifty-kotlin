#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m17SignedNarrowTypesAndUnicode(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun read(c: Char, b: Byte, s: Short): Char { println(b); println(s); return c }
            fun <T> same(x: T): T = x
            fun main() {
                println(read('界', 127, -32768)); println('界'.code)
                println(255.toByte()); println(65535.toShort()); println(65535.toChar().code)
                val b: Byte = 100; val s: Short = 30000
                val number: Number = b; println(number.toByte()); println(number.toShort())
                println(b + b); println(s + s); println('Z' - 'A'); println('A' + 2)
                var byte: Byte = 127; byte++; println(byte); byte--; println(byte)
                var short: Short = 32767; short++; println(short)
                var char = '\\uffff'; char++; println(char.code)
                val nullable: Char? = '界'; println(nullable); println(nullable!!.code)
                val empty: Char? = null; println(empty)
                val boxed: Any = b; println(boxed is Byte); println(same(s))
                for (c in 'x'..'z') { println(c) }
                val chars = charArrayOf('A', '\\uffff'); chars[0] = '界'; println(chars[0]); println(chars[1].code)
                val bytes = ByteArray(2) { i -> (i + 127).toByte() }; println(bytes[1])
                val shorts = shortArrayOf(-32768, 32767); println(shorts[0]); println(shorts[1])
                println(Char(30028))
                try { Char(-1) } catch (e: IllegalArgumentException) { println(e.message) }
                try { Char(65536) } catch (e: IllegalArgumentException) { println(e.message) }
            }
            """, expected: "127\n-32768\n界\n30028\n-1\n-1\n65535\n100\n100\n200\n60000\n25\nC\n-128\n127\n-32768\n0\n界\n30028\nnull\ntrue\n30000\nx\ny\nz\n界\n65535\n-128\n-32768\n32767\n界\nInvalid Char code: -1\nInvalid Char code: 65536\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m17UnsignedArithmeticConversionsAndBits(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun main() {
                val u = UInt.MAX_VALUE; val w = ULong.MAX_VALUE
                println(u); println(w); println(UByte.MAX_VALUE); println(UShort.MAX_VALUE)
                println(u + 1u); println(w + 1uL); println(u / 2u); println(u % 7u)
                println(w / 2uL); println(w % 7uL); println(u > 1u); println(w > 1uL)
                println(u.toLong()); println(u.toULong()); println((-1).toByte().toUInt()); println((-1).toLong().toULong())
                val b = 255u.toUByte(); val s = 65535u.toUShort()
                println(b.toInt()); println(s.toLong()); println(b + b); println(s * s)
                var n = b; n++; println(n); n--; println(n)
                println(u shr 1); println(w shr 63); println(1u shl 31); println(1uL shl 63)
                println(u and 255u); println(255u xor 15u); println(0u.inv())
                println((-1.0).toUInt()); println((0.0 / 0.0).toULong()); println((1.0 / 0.0).toUInt())
                println((1.0 / 0.0).toULong()); println(4294967296.0.toUInt()); println(42.9.toULong())
                println(u.toDouble()); println(w.toDouble()); println(b.hashCode()); println(s.hashCode())
                println(b.compareTo(1u.toUByte())); println(u.compareTo(1u)); println(w.compareTo(1uL))
                for (i in 4294967294u..4294967295u) { println(i) }
            }
            """, expected: "4294967295\n18446744073709551615\n255\n65535\n0\n0\n2147483647\n3\n9223372036854775807\n1\ntrue\ntrue\n4294967295\n4294967295\n4294967295\n18446744073709551615\n255\n65535\n510\n4294836225\n0\n255\n2147483647\n1\n2147483648\n9223372036854775808\n255\n240\n4294967295\n0\n0\n4294967295\n18446744073709551615\n4294967295\n42\n4.294967295E9\n1.8446744073709552E19\n-1\n-1\n1\n1\n1\n4294967294\n4294967295\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m17UnsignedArraysBoxingGenericsAndCapture(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            fun <T> same(x: T): T = x
            inline fun <reified T> matches(x: Any): Boolean = x is T
            fun maybe(x: UInt?): UInt? = x
            fun unsignedIdentity(x: UInt): UInt = x
            fun arrayMaybe(x: UIntArray?): UIntArray? = x
            fun main() {
                val bytes = ubyteArrayOf(0u, 255u); bytes[0] = 254u; println(bytes[0]); println(bytes[1])
                val shorts = ushortArrayOf(65535u); println(shorts[0].toInt())
                val ints = UIntArray(2) { i -> i.toUInt() + 4294967294u }; println(ints[0]); println(ints[1])
                val longs = ulongArrayOf(18446744073709551615uL); println(longs[0] / 2uL)
                var total = 0u; for (item in bytes) { total += item }; println(total)
                println(ints.map { it.toLong() }); println(same(bytes)[1]); println(same(255u.toUByte()))
                val values = listOf(0u, 4294967295u); println(values); println(values[1] > values[0])
                println(maybe(null)); println(maybe(4294967295u)); println(maybe(2u)!! + 1u)
                println(arrayMaybe(null)); println(arrayMaybe(ints)!![1])
                val boxed: Any = 4294967295u; println(boxed is UInt); println(matches<UInt>(boxed)); println(matches<Int>(boxed))
                val c: Char = same('界'); val b: Byte = same(127.toByte()); println(c); println(b)
                var captured = 255u.toUByte(); val next = { captured++; captured }; println(next()); println(next())
                println(UInt::class.simpleName); println(Char::class.simpleName)
                val reference = ::unsignedIdentity; println(reference.name); println(reference(4294967295u))
            }
            """, expected: "254\n255\n65535\n4294967294\n4294967295\n9223372036854775807\n509\n[4294967294, 4294967295]\n255\n255\n[0, 4294967295]\ntrue\nnull\n4294967295\n3\nnull\n4294967295\ntrue\ntrue\nfalse\n界\n127\n0\n1\nUInt\nChar\nunsignedIdentity\n4294967295\n", mode: mode, root: root)
        }
    }
    @Test
    func m17JavaAndOfficialKotlinABI() throws {
        try withWorkspace { root in
            let result = try compile("""
            package api
            fun signed(c: Char, b: Byte, s: Short): Char { println(b); println(s); return c }
            fun pick(x: Int): String = "signed"
            fun pick(x: UInt): String = "unsigned"
            fun small(x: Byte): String = "byte"
            fun small(x: UByte): String = "ubyte"
            fun scale(x: UInt = 4294967295u, y: UByte = 2u): UInt = x / y
            @JvmName("javaUnsigned") fun exposed(x: UInt): UInt = x + 1u
            fun arrays(x: UByteArray): UByteArray = x
            interface Operation { fun transform(x: UInt): UInt }
            fun dispatch(op: Operation, x: UInt): UInt = op.transform(x)
            class Holder(var value: UInt, val letter: Char) {
                fun read(): UInt = value
            }
            inline fun apply(x: UInt, action: (UInt) -> UInt): UInt = action(x)
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try """
            package consumer
            import api.*
            fun main() {
                println(signed('界', -128, 32767)); println(pick(1)); println(pick(1u))
                println(small(1.toByte())); println(small(1u.toUByte())); println(scale()); println(scale(y = 4u))
                val h = Holder(4294967295u, '界'); println(h.value); println(h.read()); h.value = 3u; println(h.value); println(h.letter)
                println(arrays(ubyteArrayOf(255u))[0]); println(apply(4294967295u) { it / 2u })
                println(exposed(4294967295u))
                println(dispatch(object: Operation { override fun transform(x: UInt): UInt = x / 2u }, 4294967295u))
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "consumer.ConsumerKt"]).stdout == "-128\n32767\n界\nsigned\nunsigned\nbyte\nubyte\n2147483647\n1073741823\n4294967295\n4294967295\n3\n界\n255\n2147483647\n0\n2147483647\n")
            }
            try """
            public class JavaConsumer {
                public static void main(String[] args) {
                    System.out.println(api.HelloKt.signed('界', (byte)-128, (short)32767));
                    System.out.println(api.HelloKt.javaUnsigned(-1));
                    System.out.println(api.HelloKt.pick(1));
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "-128\n32767\n界\n0\nsigned\n")
            let abi = try jvmTool("javap", ["-s", "-p", "-classpath", jar, "api.HelloKt", "api.Holder"], root: root).stdout
            #expect(abi.contains("(CBS)C")); #expect(abi.contains("pick-WZ4Q5Ns")); #expect(abi.contains("getValue-pVg5ArA"))
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m17ImportsJavaNarrowDescriptors(mode: EmitMode) throws {
        try withWorkspace { root in
            try """
            public class Narrow {
                public static char letter(char c) { return (char)(c + 1); }
                public static byte small(byte b) { return (byte)(b + 1); }
                public static short medium(short s) { return (short)(s + 1); }
                public static byte[] bytes(byte[] a) { return a; }
                public static char[] chars(char[] a) { return a; }
                public short echo(short s) { return s; }
            }
            """.write(to: root.appendingPathComponent("Narrow.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["Narrow.java"], root: root)
            let result = try compile("""
            fun main() {
                println(Narrow.letter('A')); println(Narrow.small(127)); println(Narrow.medium(32767))
                println(Narrow.bytes(byteArrayOf(-128))[0]); println(Narrow.chars(charArrayOf('界'))[0]); println(Narrow().echo(-32768))
            }
            """, root: root, mode: mode, classpath: [root.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            #expect(try java(["-cp", artifact + ":" + root.path, "HelloKt"]).stdout == "B\n-128\n-32768\n-128\n界\n-32768\n")
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m17SuspendInlineAndValueClassCarriers(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.coroutines.*
            @JvmInline value class Token(val bits: UInt)
            class Gate {
                var pending: Continuation<UIntArray>? = null
                suspend fun await(): UIntArray = suspendCoroutine { pending = it }
                fun release() { pending!!.resume(uintArrayOf(4294967295u)) }
            }
            suspend fun byte(x: Byte): Byte = x
            suspend fun char(x: Char): Char = x
            suspend fun scalar(x: UInt = 4294967295u): UInt = x
            suspend fun array(x: UIntArray): UIntArray = x
            suspend fun nullableArray(x: UIntArray?): UIntArray? = x
            inline suspend fun forward(x: UInt, action: suspend (UInt) -> UInt): UInt = action(x)
            inline suspend fun forwardArray(x: UIntArray?): UIntArray? = nullableArray(x)
            fun main() {
                val gate = Gate()
                val work: suspend () -> UInt = {
                    println(byte(-128)); println(char('界')); println(scalar()); println(forward(4294967295u) { it / 2u })
                    println(array(uintArrayOf(4294967295u))[0]); println(forwardArray(null)); println(forwardArray(uintArrayOf(3u))!![0])
                    println(Token(4294967295u)); println(Token(4294967295u).hashCode())
                    val result = gate.await(); println(result[0]); result[0]
                }
                work.startCoroutine(object: Continuation<UInt> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<UInt>) { println(result.getOrThrow()) }
                })
                println("paused"); gate.release()
            }
            """, expected: "-128\n界\n4294967295\n2147483647\n4294967295\nnull\n3\nToken(bits=4294967295)\n-1\npaused\n4294967295\n4294967295\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m17NarrowAnnotationConstants(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            @Retention(AnnotationRetention.RUNTIME)
            annotation class Narrow(val c: Char = '界', val b: Byte = -128, val s: Short = 32767, val chars: CharArray = ['A', '界'])
            @Narrow class Sample
            const val LETTER: Char = '界'
            fun main() {
                val a = Sample::class.annotations[0] as Narrow
                println(a.c); println(a.b); println(a.s); println(a.chars[1]); println(LETTER)
            }
            """, expected: "界\n-128\n32767\n界\n界\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func m17NullableArrayTransportAndUnsignedConstructors(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.coroutines.*
            class Choice(val number: UInt, val bytes: UByteArray)
            class Gate {
                var pending: Continuation<UIntArray?>? = null
                suspend fun await(): UIntArray? = suspendCoroutine { pending = it }
                fun release() { pending!!.resume(null) }
            }
            data class Data(val values: UIntArray, val b: UByte, val s: Byte)
            @JvmInline value class Values(val value: UIntArray)
            suspend fun forward(gate: Gate): UIntArray? = gate.await()
            suspend fun returnsNull(gate: Gate): UIntArray? { gate.await(); return null }
            const val MAX: UInt = 4294967295u
            fun main() {
                val choice = Choice(4294967295u, ubyteArrayOf(255u)); println(choice.number); println(choice.bytes[0])
                val missing: UIntArray? = null; val erased: Any? = missing; println(erased == null)
                val list = listOf(missing); println(list[0] == null)
                val array = arrayOf<UIntArray?>(null); println(array[0] == null); array[0] = missing; println(array[0] == null)
                val gate = Gate()
                val first: suspend () -> UIntArray? = { forward(gate) }
                val second: suspend () -> UIntArray? = { returnsNull(gate) }
                val completion = object: Continuation<UIntArray?> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<UIntArray?>) { println(result.getOrThrow() == null) }
                }
                first.startCoroutine(completion); gate.release(); second.startCoroutine(completion); gate.release()
                val values = uintArrayOf(4294967295u, 1u)
                val data = Data(values, 255u, -1); println(data); println(data.hashCode())
                println(Values(values)); println(Values(values).hashCode())
                val small: UByte = 255u; println(small.hashCode()); println(MAX)
                try { missing!!; println("bad") } catch (e: NullPointerException) { println("null asserted") }
                val tiny: Byte? = -128; val medium: Short? = 32767; println(tiny); println(medium)
            }
            """, expected: "4294967295\n255\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\nData(values=UIntArray(storage=[-1, 1]), b=255, s=-1)\n894659\nValues(value=UIntArray(storage=[-1, 1]))\n931\n-1\n4294967295\nnull asserted\n-128\n32767\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [
        "fun main() { val b: Byte = 128; println(b) }",
        "fun main() { val s: Short = 32768; println(s) }",
        "fun main() { val u: UByte = 256u; println(u) }",
        "fun main() { val u: UShort = 65536u; println(u) }",
        "fun main() { println('😀') }",
        "fun main() { println(1u + 1) }",
        "class Clash { constructor(x: Int); constructor(x: UInt) }",
        "class Clash { constructor(x: IntArray); constructor(x: UIntArray) }",
    ])
    func m17InvalidScalarsPreserveOutput(source: String) throws {
        try withWorkspace { root in
            let output = root.appendingPathComponent("hello.jar"), sentinel = Data("previous jar".utf8)
            try sentinel.write(to: output)
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(try Data(contentsOf: output) == sentinel)
        }
    }

    @Test
    func m17OfficialKotlinConsumesUnsignedSuspend() throws {
        try withWorkspace { root in
            let result = try compile("""
            package api
            import kotlin.coroutines.*
            @JvmName("javaUInt") suspend fun scalar(x: UInt): UInt = x
            @JvmName("javaArray") suspend fun array(x: UIntArray?): UIntArray? = x
            inline suspend fun forward(x: UIntArray?): UIntArray? = array(x)
            class Gate {
                var pending: Continuation<UIntArray?>? = null
                suspend fun await(): UIntArray? = suspendCoroutine { pending = it }
                fun release() { pending!!.resume(null) }
            }
            inline suspend fun delayed(gate: Gate): UIntArray? = gate.await()
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path, runtime = try m11Runtime()
            try """
            package consumer
            import api.*
            import kotlin.coroutines.*
            fun main() {
                val gate = Gate()
                val work: suspend () -> UIntArray? = {
                    println(scalar(4294967295u)); println(array(null)); println(array(uintArrayOf(4294967295u))!![0])
                    println(forward(null)); println(forward(uintArrayOf(2u))!![0]); delayed(gate)
                }
                work.startCoroutine(object: Continuation<UIntArray?> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<UIntArray?>) { println(result.getOrThrow() == null) }
                })
                println("paused"); gate.release()
            }
            """.write(to: root.appendingPathComponent("consumer.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["consumer.kt", "-cp", jar + ":" + runtime, "-d", "consumer.jar"], root: root)
            for cp in [jar + ":" + runtime, runtime + ":" + jar] {
                #expect(try java(["-cp", root.appendingPathComponent("consumer.jar").path + ":" + cp, "consumer.ConsumerKt"]).stdout == "4294967295\nnull\n4294967295\nnull\n2\npaused\ntrue\n")
            }
            try """
            public class JavaConsumer {
                public static void main(String[] args) {
                    kotlin.coroutines.Continuation<Object> completion = new kotlin.coroutines.Continuation<Object>() {
                        public kotlin.coroutines.CoroutineContext getContext() { return kotlin.coroutines.EmptyCoroutineContext.INSTANCE; }
                        public void resumeWith(Object result) { throw new AssertionError("Unexpected suspension"); }
                    };
                    Object u = api.HelloKt.javaUInt(-1, completion);
                    System.out.println(u); System.out.println(u.getClass().getName());
                    Object array = api.HelloKt.javaArray(new int[] {-1}, completion);
                    System.out.println(((int[])array)[0]); System.out.println(api.HelloKt.javaArray(null, completion) == null);
                }
            }
            """.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", jar + ":" + runtime, "JavaConsumer.java"], root: root)
            #expect(try java(["-cp", root.path + ":" + jar + ":" + runtime, "JavaConsumer"]).stdout == "4294967295\nkotlin.UInt\n-1\ntrue\n")
            let abi = try jvmTool("javap", ["-v", "-classpath", jar, "api.HelloKt"], root: root).stdout
            #expect(abi.contains("Continuation<-Lkotlin/UInt;>")); #expect(abi.contains("Continuation<-Lkotlin/UIntArray;>"))
        }
    }

}
#endif
