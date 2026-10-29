@testable import CompilerCore
import Testing

@Suite
struct ArrayWithIndexCodegenTests {
    @Test(arguments: [false, true], [0, 2])
    func indexedLoops(useArtifact: Bool, optimization: Int) throws {
        let optLevel: OptimizationLevel = optimization == 0 ? .O0 : .O2
        let source = try diffCaseSource("array_withindex_destructuring.kt", file: #filePath)
        try assertKotlinOutput(
            source, moduleName: "ArrayWithIndex", expected: """
            0:a;1:b;
            0:null;1:x;
            nested=0:3
            nested=1:4
            int=0:10
            int=1:20
            long=0:30
            long=1:40
            byte=0:-128
            byte=1:127
            short=0:-32768
            short=1:32767
            entry=0:9
            entry=1:2
            entry=2:3
            9;2;3;
            0;1;2;
            count=3
            control=0:1
            control=2:3
            -1
            false
            byte exhausted
            -2
            false
            short exhausted
            7
            indexed exhausted
            0:a;1:b;
            0:c;1:d;

            text=0:e

            """, optLevel: optLevel, allowDefaultStdlibLibrary: useArtifact
        )
    }
}
