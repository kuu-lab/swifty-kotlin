import TestStdlibCache
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testBufferOutputStreamDefaultBridges(useStdlibArtifact: Bool, optimization: Int) throws {
        if useStdlibArtifact { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_io_buffer_outputstream_default_bridges.kt", file: #filePath),
            expectedOutput: """
            copy-all=abcdef
            copy-all-size=6
            copy-start=cdef
            copy-start-size=6
            copy-end=abc
            copy-end-size=6
            copy-empty=
            copy-empty-size=0
            read-all=uvwxyz
            read-all-size=0
            read-zero=
            read-zero-size=3
            read-negative=IllegalArgumentException
            read-oversized=IllegalArgumentException
            copy-negative-start=IndexOutOfBoundsException
            copy-oversized-end=IndexOutOfBoundsException
            copy-reversed-range=IllegalArgumentException
            """ + "\n",
            moduleName: "KUU2637BufferOutputStreamDefaultBridges",
            allowDefaultStdlibLibrary: useStdlibArtifact,
            optLevel: optimization == 2 ? .O2 : .O0
        )
    }
}
