package kotlinx.io.files

import kotlinx.io.IOException
import kotlinx.io.RawSink

public class FileSystemFlagProbe : FileSystem by SystemFileSystem {
    public var sinkAppend: Boolean? = null
    public var deleteMustExist: Boolean? = null
    public var createDirectoriesMustCreate: Boolean? = null

    override fun sink(path: Path, append: Boolean): RawSink {
        sinkAppend = append
        throw IOException("sink flag probe")
    }

    override fun delete(path: Path, mustExist: Boolean) {
        deleteMustExist = mustExist
    }

    override fun createDirectories(path: Path, mustCreate: Boolean) {
        createDirectoriesMustCreate = mustCreate
    }
}
