#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func primitiveFinalBoundsKeepKotlinDescriptors(mode: EmitMode) throws {
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let result = try compile("""
            fun <T: Double> echoDouble(v: T): T = v
            fun <T: Float> echoFloat(v: T): T = v
            fun <T: Int> echoInt(v: T): T = v
            fun <T: Long> echoLong(v: T): T = v
            fun <T: Byte> echoByte(v: T): T = v
            fun <T: Short> echoShort(v: T): T = v
            fun <T: Char> echoChar(v: T): T = v
            fun <T: Boolean> echoBoolean(v: T): T = v
            fun <T: Double?> nullableBound(v: T): T = v
            fun <T: Double> nullableUse(v: T?): T? = v
            fun <T: Number> number(v: T): T = v
            fun <T> identity(v: T): T = v
            fun <U: Double, T: U> chain(v: T): T = v
            fun <T: Double> arrayEcho(v: Array<T>): Array<T> = v
            fun <T: Double> count(vararg values: T): Int = values.size
            class BoundBox<T: Double>(val value: T)
            fun main() {
                println(echoDouble(2.0)); println(echoFloat(2.0f))
                println(echoInt(2)); println(echoLong(2L))
                println(echoByte(2.toByte())); println(echoShort(2.toShort()))
                println(echoChar('b')); println(echoBoolean(true))
                println(nullableBound<Double?>(null)); println(nullableUse<Double>(null))
                println(number(2)); println(identity("OK")); println(chain(2.0))
                println(arrayEcho(arrayOf(2.0))[0]); println(count(2.0, 3.0))
                println(BoundBox(2.0).value)
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let index = try JVMClasspathIndex.load([artifact.path])
            let facade = try #require(index.classes["HelloKt"])
            let descriptors = Dictionary(facade.methods.map { ($0.name, $0.descriptor) }, uniquingKeysWith: { first, _ in first })
            for (name, descriptor) in ["echoDouble": "(D)D", "echoFloat": "(F)F", "echoInt": "(I)I", "echoLong": "(J)J", "echoByte": "(B)B", "echoShort": "(S)S", "echoChar": "(C)C", "echoBoolean": "(Z)Z", "chain": "(D)D", "nullableBound": "(Ljava/lang/Double;)Ljava/lang/Double;", "nullableUse": "(Ljava/lang/Double;)Ljava/lang/Double;", "number": "(Ljava/lang/Number;)Ljava/lang/Number;", "identity": "(Ljava/lang/Object;)Ljava/lang/Object;", "arrayEcho": "([Ljava/lang/Double;)[Ljava/lang/Double;", "count": "([Ljava/lang/Double;)I"] {
                #expect(descriptors[name] == descriptor)
            }
            let execution = try java(["-cp", artifact.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "2.0\n2.0\n2\n2\n2\n2\nb\ntrue\nnull\nnull\n2\nOK\n2.0\n2.0\n2\n2.0\n")
            #expect(execution.stderr.isEmpty)
            let consumer = """
            public class Consumer {
                public static void main(String[] args) throws Exception {
                    Class<?> facade = Class.forName("HelloKt");
                    System.out.println(facade.getMethod("echoDouble", double.class).invoke(null, 2.0));
                    System.out.println(facade.getMethod("identity", Object.class).invoke(null, "OK"));
                    Class<?> boxType = Class.forName("BoundBox");
                    Object box = boxType.getConstructor(double.class).newInstance(3.0);
                    System.out.println(boxType.getMethod("getValue").invoke(box));
                }
            }
            """
            try consumer.write(to: root.appendingPathComponent("Consumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", artifact.path, "-d", root.path, "Consumer.java"], root: root)
            let javaConsumer = try java(["-cp", root.path + ":" + artifact.path + ":" + library.path, "Consumer"])
            #expect(javaConsumer.exitCode == 0)
            #expect(javaConsumer.stdout == "2.0\nOK\n3.0\n")
            #expect(javaConsumer.stderr.isEmpty)
        }
    }
}
#endif
