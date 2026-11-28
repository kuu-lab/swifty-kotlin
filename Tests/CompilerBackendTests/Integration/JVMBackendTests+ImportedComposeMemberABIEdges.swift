#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedComposableMemberBindsEmptyMultiMaskAndVarargCallbacks() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let runtime = try composeJVMFixture(root, stdlib: stdlib)
            let methods = try #require(Data(base64Encoded: """
            yv66vgAAADQAMQEAGWZpeHR1cmUvQ29tcG9zYWJsZU1ldGhvZHMHAAEBABBqYXZhL2xhbmcvT2JqZWN0BwADAQAFZW1wdHkBACco
            TGFuZHJvaWR4L2NvbXBvc2UvcnVudGltZS9Db21wb3NlcjtJKVYBACVMYW5kcm9pZHgvY29tcG9zZS9ydW50aW1lL0NvbXBvc2Fi
            bGU7AQAkTG9yZy9qZXRicmFpbnMvYW5ub3RhdGlvbnMvTnVsbGFibGU7AQAEbWFueQEAMyhJSUlJSUlJSUlJSUxhbmRyb2lkeC9j
            b21wb3NlL3J1bnRpbWUvQ29tcG9zZXI7SUkpVgEABnJlbmRlcgEAWihbTGphdmEvbGFuZy9TdHJpbmc7TGtvdGxpbi9qdm0vZnVu
            Y3Rpb25zL0Z1bmN0aW9uMjtMYW5kcm9pZHgvY29tcG9zZS9ydW50aW1lL0NvbXBvc2VyO0kpVgEAoShbTGphdmEvbGFuZy9TdHJp
            bmc7TGtvdGxpbi9qdm0vZnVuY3Rpb25zL0Z1bmN0aW9uMjwtTGFuZHJvaWR4L2NvbXBvc2UvcnVudGltZS9Db21wb3NlcjstTGph
            dmEvbGFuZy9JbnRlZ2VyO0xrb3RsaW4vVW5pdDs+O0xhbmRyb2lkeC9jb21wb3NlL3J1bnRpbWUvQ29tcG9zZXI7SSlWAQAjTG9y
            Zy9qZXRicmFpbnMvYW5ub3RhdGlvbnMvTm90TnVsbDsBABFMa290bGluL01ldGFkYXRhOwEAAm12AwAAAAIDAAAABAMAAAAAAQAB
            awMAAAABAQACeGkDAAAAMAEAAmQxAQEBwIAwCgIYAgoCEMCACsCACgIQAgrAgAoCGAIKAggCCgIQCAoCCA0KAhARCgIQDgrAgAoC
            GAIKwIAIZhjAgDICMAFKERACGgIwA0gnYgIIBcKiBgIQBEppEAYaAjADMgYQBxoCMAgyBhAJGgIwCDIGEAoaAjAIMgYQCxoCMAgy
            BhAMGgIwCDIGEA0aAjAIMgYQDhoCMAgyBhAPGgIwCDIGEBAaAjAIMgYQERoCMAgyBhASGgIwCEgnYgIIBcKiBgIQE0o4EBQaAjAD
            MhIQFRoKEgYIARICMBcwFiICMBcyERAYGg0SBBICMAMwGcKiBgIIBUgnYgIIBcKiBgIQGsOABgMBAAJkMgEAG0xmaXh0dXJlL0Nv
            bXBvc2FibGVNZXRob2RzOwEAAAEAAnAwAQACcDEBAAJwMgEAAnAzAQACcDQBAAJwNQEAAnA2AQACcDcBAAJwOAEAAnA5AQADcDEw
            AQAGbGFiZWxzAQAHY29udGVudAEAEkxrb3RsaW4vRnVuY3Rpb24wOwEAFENvbXBvc2FibGVNZXRob2RzLmt0AQAbUnVudGltZUlu
            dmlzaWJsZUFubm90YXRpb25zAQAkUnVudGltZUludmlzaWJsZVBhcmFtZXRlckFubm90YXRpb25zAQAJU2lnbmF0dXJlAQAKU291
            cmNlRmlsZQEAGVJ1bnRpbWVWaXNpYmxlQW5ub3RhdGlvbnMGAQACAAQAAAAAAAMEAQAFAAYAAgAsAAAABgABAAcAAAAtAAAACQIA
            AQAIAAAAAAQBAAkACgACACwAAAAGAAEABwAAAC0AAAAhDgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAIAAAAAAAABAEACwAMAAMA
            LgAAAAIADQAsAAAABgABAAcAAAAtAAAAFQQAAQAOAAAAAQAOAAAAAQAIAAAAAAACAC8AAAACACsAMAAAAHwAAQAPAAUAEFsAA0kA
            EUkAEkkAEwAUSQAVABZJABcAGFsAAXMAGQAaWwAbcwAbcwAccwAFcwAccwAGcwAHcwAJcwAdcwAccwAecwAfcwAgcwAhcwAicwAj
            cwAkcwAlcwAmcwAncwAKcwALcwAocwAccwAccwApcwAqcwAM
            """, options: .ignoreUnknownCharacters))
            let provider = root.appendingPathComponent("provider/fixture")
            try FileManager.default.createDirectory(at: provider, withIntermediateDirectories: true)
            try methods.write(to: provider.appendingPathComponent("ComposableMethods.class"))

            let consumer = """
            import androidx.compose.runtime.Composable
            import fixture.ComposableMethods

            @Composable fun Screen(panel: ComposableMethods) {
                panel.empty()
                panel.many(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
                panel.render("headline") { println("callback") }
            }
            """
            let classpath = [root.appendingPathComponent("provider").path, runtime.path, stdlib.path]
            let (app, exit, diagnostics) = try m22Build(
                root: root, sources: [("Screen.kt", consumer)], name: "app.jar", classpath: classpath
            )
            try #require(exit == 0, "\(diagnostics.map(\.message))")

            try """
            import androidx.compose.runtime.Composer;
            import fixture.Bridge;
            import fixture.ComposableMethods;
            import kotlin.jvm.functions.Function2;

            public final class Driver {
                private static final class Methods implements ComposableMethods {
                    private int emptyCalls;
                    private int manyCalls;
                    private int renderCalls;

                    public void empty(Composer composer, int changed) {
                        if (composer != Bridge.COMPOSER || changed != 0) throw new AssertionError("empty ABI");
                        emptyCalls++;
                    }
                    public void many(int p0, int p1, int p2, int p3, int p4, int p5,
                                     int p6, int p7, int p8, int p9, int p10,
                                     Composer composer, int changed0, int changed1) {
                        if (p0 != 0 || p1 != 1 || p2 != 2 || p3 != 3 || p4 != 4 || p5 != 5
                                || p6 != 6 || p7 != 7 || p8 != 8 || p9 != 9 || p10 != 10
                                || composer != Bridge.COMPOSER || changed0 != 0 || changed1 != 0)
                            throw new AssertionError("multi-mask ABI");
                        manyCalls++;
                    }
                    public void render(String[] labels, Function2 content, Composer composer, int changed) {
                        if (labels.length != 1 || !labels[0].equals("headline") || content == null
                                || composer != Bridge.COMPOSER || changed != 0)
                            throw new AssertionError("vararg callback ABI");
                        renderCalls++;
                        content.invoke(composer, Integer.valueOf(0));
                    }

                    public void verifyCalls() {
                        if (emptyCalls != 1 || manyCalls != 1 || renderCalls != 1)
                            throw new AssertionError("missing composable member call");
                    }
                }
                public static void main(String[] args) {
                    Methods methods = new Methods();
                    ScreenKt.Screen(methods, Bridge.COMPOSER, 0);
                    methods.verifyCalls();
                }
            }
            """.write(to: root.appendingPathComponent("Driver.java"), atomically: true, encoding: .utf8)
            let runClasspath = ([app.path] + classpath).joined(separator: ":")
            let compiled = try jvmTool("javac", ["-cp", runClasspath, "-d", "driver", "Driver.java"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let driver = root.appendingPathComponent("driver").path
            let run = try java(["-Xverify:all", "-cp", runClasspath + ":" + driver, "Driver"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "callback\n")
        }
    }

    @Test
    func composeMemberMetadataInfersReceiverAwareChangeAndDefaultMasks() {
        let owner = "fixture/MaskEdges"
        let index = JVMClasspathIndex()
        let composer = JVMCompose.composerType
        let annotation = JVMAnnotation(descriptor: "Landroidx/compose/runtime/Composable;", visible: false)

        func function(_ name: String, parameterCount: Int, hasDefault: Bool = false) -> JVMKotlinFunctionInfo {
            let parameters = (0..<parameterCount).map { index in
                JVMKotlinParameterInfo(
                    name: "p\(index)", type: .named("kotlin/Int", [], nullable: false), varargType: nil,
                    hasDefault: hasDefault && index == parameterCount - 1
                )
            }
            return JVMKotlinFunctionInfo(
                name: name, jvmName: name,
                descriptor: "(" + String(repeating: "I", count: parameterCount) + ")V", flags: 6,
                typeParameters: [], receiver: nil, parameters: parameters,
                result: .named("kotlin/Unit", [], nullable: false)
            )
        }

        func method(_ name: String, parameterCount: Int, changeMasks: Int, defaultMasks: Int = 0) -> JVMForeignMethod {
            let parameters = Array(repeating: JVMValueType.int, count: parameterCount)
                + [composer] + Array(repeating: JVMValueType.int, count: changeMasks + defaultMasks)
            let descriptor = "(" + parameters.map(\.descriptor).joined() + ")V"
            var method = JVMForeignMethod(
                owner: owner, name: name, descriptor: descriptor, parameters: parameters,
                result: .unit, isStatic: false, isInterface: true, isAbstract: true
            )
            method.annotations = [annotation]
            return method
        }

        func binds(_ method: JVMForeignMethod, to function: JVMKotlinFunctionInfo) -> Bool {
            index.classes[owner] = JVMClassInfo(
                name: owner, flags: 0x0200, superclass: "java/lang/Object", interfaces: [], methods: [method]
            )
            index.kotlinMetadataByClass[owner] = JVMKotlinClassMetadata(
                classFlags: 0, companion: nil, typeParameters: [], functions: [function],
                properties: [], typeAliases: [], isPackage: false
            )
            return index.kotlinFunction(method) != nil
        }

        let empty = function("empty", parameterCount: 0)
        #expect(binds(method("empty", parameterCount: 0, changeMasks: 1), to: empty))

        let ten = function("ten", parameterCount: 10)
        #expect(binds(method("ten", parameterCount: 10, changeMasks: 2), to: ten))
        #expect(!binds(method("ten", parameterCount: 10, changeMasks: 1), to: ten))

        let default32 = function("default32", parameterCount: 32, hasDefault: true)
        #expect(binds(method("default32", parameterCount: 32, changeMasks: 4, defaultMasks: 2), to: default32))
        #expect(!binds(method("default32", parameterCount: 32, changeMasks: 4, defaultMasks: 1), to: default32))
    }
}
#endif
