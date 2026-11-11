#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func primitiveCompanionsExposeJvmSingletonsAndConstants() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
                import kotlin.jvm.internal.FloatCompanionObject;
                import kotlin.jvm.internal.IntCompanionObject;

                public final class Main {
                    public static void main(String[] args) throws Exception {
                        FloatCompanionObject companion = FloatCompanionObject.INSTANCE;
                        if (companion.getMIN_VALUE() != Float.MIN_VALUE ||
                            companion.getMAX_VALUE() != Float.MAX_VALUE ||
                            companion.getPOSITIVE_INFINITY() != Float.POSITIVE_INFINITY ||
                            companion.getNEGATIVE_INFINITY() != Float.NEGATIVE_INFINITY ||
                            !Float.isNaN(companion.getNaN())) {
                            throw new AssertionError("incorrect Float companion getters");
                        }
                        if (FloatCompanionObject.class.getField("MIN_VALUE").getFloat(null) != Float.MIN_VALUE ||
                            FloatCompanionObject.class.getField("SIZE_BITS").getInt(null) != Float.SIZE) {
                            throw new AssertionError("incorrect Float companion fields");
                        }
                        if (IntCompanionObject.INSTANCE == null ||
                            IntCompanionObject.class.getField("MIN_VALUE").getInt(null) != Integer.MIN_VALUE ||
                            IntCompanionObject.class.getField("MAX_VALUE").getInt(null) != Integer.MAX_VALUE ||
                            IntCompanionObject.class.getField("SIZE_BITS").getInt(null) != Integer.SIZE) {
                            throw new AssertionError("incorrect Int companion fields");
                        }
                    }
                }
                """
            try source.write(to: root.appendingPathComponent("Main.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["-cp", stdlib.path, "-d", ".", "Main.java"], root: root)
            let run = try java(["-Xverify:all", "-cp", root.path + ":" + stdlib.path, "Main"])
            #expect(run.exitCode == 0)
        }
    }
}
#endif
