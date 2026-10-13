package java.nio.file

import java.io.File

/** Native path producer for Java-facing interoperability; no classfile facade. */
public class Path internal constructor(internal val text: String) {
    public fun toFile(): File = File(text)
    override fun toString(): String = text
    override fun hashCode(): Int = text.hashCode()
    override fun equals(other: Any?): Boolean = other is Path && text == other.text
}
public object Paths {
    public fun get(first: String, vararg more: String): Path {
        var joined = first
        for (part in more) {
            if (part.isNotEmpty()) {
                if (joined.isNotEmpty()) joined += "/"
                joined += part
            }
        }

        // POSIX paths collapse repeated separators and discard trailing ones;
        // dot and parent segments remain lexical until the filesystem resolves them.
        var normalized = ""
        var separator = false
        for (character in joined) {
            require(character != '\u0000') { "Nul character not allowed in path" }
            if (character != '/' || !separator) normalized += character
            separator = character == '/'
        }
        if (normalized.length > 1 && normalized.endsWith('/')) {
            normalized = normalized.substring(0, normalized.length - 1)
        }
        return Path(normalized)
    }
}

public interface OpenOption
public enum class StandardOpenOption : OpenOption {
    READ, WRITE, APPEND, TRUNCATE_EXISTING, CREATE, CREATE_NEW, DELETE_ON_CLOSE, SPARSE, SYNC, DSYNC
}
public enum class LinkOption : OpenOption { NOFOLLOW_LINKS }
