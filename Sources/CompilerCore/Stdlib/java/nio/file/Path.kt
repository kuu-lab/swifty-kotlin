package java.nio.file

import java.io.File

/** Native path producer for Java-facing interoperability; no classfile facade. */
public class Path internal constructor(internal val text: String) {
    public fun toFile(): File = File(text)
    override fun toString(): String = text
}
public object Paths {
    public fun get(first: String, vararg more: String): Path {
        var path = first
        for (part in more) {
            if (part.isNotEmpty()) path = if (path.isEmpty()) part else path.trimEnd('/') + "/" + part
        }
        return Path(path)
    }
}
public interface OpenOption
public enum class StandardOpenOption : OpenOption {
    READ, WRITE, APPEND, TRUNCATE_EXISTING, CREATE, CREATE_NEW, DELETE_ON_CLOSE, SPARSE, SYNC, DSYNC
}
public enum class LinkOption : OpenOption { NOFOLLOW_LINKS }
