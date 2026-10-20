package kotlinx.io;

public final class SourcesKt {
    public static long lastToIndex = Long.MIN_VALUE;

    public static long indexOf(Source source, byte value, long fromIndex, long toIndex) {
        lastToIndex = toIndex;
        long end = Math.min(toIndex, source.getBuffer().getSize());
        for (long index = fromIndex; index < end; index++) {
            if (source.getBuffer().get(index) == value) return index;
        }
        return -1L;
    }
}
