#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar], [false, true])
    func javaParameterReflection(mode: EmitMode, javaParameters: Bool) throws {
        try withWorkspace { root in
            let source = """
            fun measure(offset: Int, label: String) = label + offset
            fun Double.scaled(wide: Long, ratio: Double, `display label`: String) = `display label`
            fun preset(label: String = "default") = label
            fun empty() = 0

            class Meter(val offset: Long, val ratio: Double, val label: String) {
                constructor(label: String) : this(1L, 2.0, label)
                fun measure(wide: Long, ratio: Double, label: String) = label
                fun String.decorate(wide: Long, label: String) = label
            }
            class Outer { inner class Inner(val weight: Long) }
            enum class Scale(val factor: Double) { SMALL(0.5) }
            interface Measurement { fun compute(value: Long, ratio: Double): String }
            data class Reading(val label: String, val weight: Long)
            """
            let extraSource = ("More.kt", "fun more(second: Long) = second")
            let result = try compile(source, root: root, mode: mode, javaParameters: javaParameters, additionalSources: [extraSource])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let classpath = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let inspection = try javap(["-p", "-v", "-classpath", classpath, "HelloKt", "Meter", "MoreKt"])
            try #require(inspection.exitCode == 0, "\(inspection.stderr)")
            #expect(inspection.stdout.contains("\n    MethodParameters:\n") == javaParameters)

            let consumer = root.appendingPathComponent("ParameterConsumer.java")
            try """
            import java.lang.reflect.Executable;
            import java.lang.reflect.Parameter;

            public class ParameterConsumer {
                private static Parameter[] check(boolean named, Executable executable, String... names) {
                    Parameter[] parameters = executable.getParameters();
                    if (parameters.length != names.length) {
                        throw new AssertionError(executable + " has " + parameters.length + " parameters");
                    }
                    for (int i = 0; i < names.length; i++) {
                        String expected = named ? names[i] : "arg" + i;
                        Parameter parameter = parameters[i];
                        if (parameter.isNamePresent() != named || !parameter.getName().equals(expected)) {
                            throw new AssertionError(executable + " parameter " + i + ": " + parameter);
                        }
                    }
                    return parameters;
                }

                public static void main(String[] args) throws ReflectiveOperationException {
                    boolean named = Boolean.parseBoolean(args[0]);
                    check(named, HelloKt.class.getMethod("measure", int.class, String.class), "offset", "label");
                    check(named, HelloKt.class.getMethod("scaled", double.class, long.class, double.class, String.class),
                          "$this$scaled", "wide", "ratio", "display label");
                    check(named, HelloKt.class.getMethod("preset", String.class), "label");
                    check(named, HelloKt.class.getMethod("empty"));
                    check(named, MoreKt.class.getMethod("more", long.class), "second");
                    check(named, Meter.class.getConstructor(long.class, double.class, String.class), "offset", "ratio", "label");
                    check(named, Meter.class.getConstructor(String.class), "label");
                    check(named, Meter.class.getMethod("measure", long.class, double.class, String.class), "wide", "ratio", "label");
                    check(named, Meter.class.getMethod("decorate", String.class, long.class, String.class),
                          "$this$decorate", "wide", "label");
                    check(named, Measurement.class.getMethod("compute", long.class, double.class), "value", "ratio");
                    check(named, Reading.class.getMethod("copy", String.class, long.class), "label", "weight");
                    check(named, Reading.class.getMethod("equals", Object.class), "other");

                    Parameter[] inner = check(named, Outer.Inner.class.getDeclaredConstructor(Outer.class, long.class), "this$0", "weight");
                    Parameter[] scale = check(named, Scale.class.getDeclaredConstructor(String.class, int.class, double.class),
                                              "$enum$name", "$enum$ordinal", "factor");
                    if (inner[0].isImplicit() != named || scale[0].isSynthetic() != named || scale[1].isSynthetic() != named) {
                        throw new AssertionError("Hidden constructor parameter flags");
                    }
                    check(named, Scale.class.getMethod("valueOf", String.class), "value");

                    check(false, HelloKt.class.getDeclaredMethod("preset$default", String.class, int.class, Object.class),
                          "label", "mask", "marker");
                }
            }
            """.write(to: consumer, atomically: true, encoding: .utf8)
            let compilation = try javac(["-cp", classpath, "-d", root.path, consumer.path])
            try #require(compilation.exitCode == 0, "\(compilation.stderr)")
            let execution = try java(["-cp", classpath + ":" + root.path, "ParameterConsumer", String(javaParameters)])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
        }
    }
}
#endif
