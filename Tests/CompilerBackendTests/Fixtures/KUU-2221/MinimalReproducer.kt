package mathematics

import java.security.InvalidParameterException

fun checked(n: Long): Long {
    if (n < 0L) throw InvalidParameterException("negative")
    return n
}
