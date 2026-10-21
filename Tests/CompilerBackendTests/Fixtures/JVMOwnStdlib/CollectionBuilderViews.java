import java.util.*;
import java.io.*;
public class CollectionBuilderViews {
    interface CheckedAction { void run() throws Exception; }
    static void attempt(String label, CheckedAction operation) {
        try { operation.run(); System.out.println(label + "=OK"); }
        catch (Throwable failure) { System.out.println(label + "=" + failure.getClass().getSimpleName()); }
    }
    static Object serialized(Object value) throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        new ObjectOutputStream(bytes).writeObject(value);
        return new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray())).readObject();
    }
    public static void main(String[] args) throws Exception {
        try { kotlin.collections.CollectionsKt.createListBuilder(-1); } catch (Throwable failure) { System.out.println("list.capacity=" + failure.getMessage()); }
        try { kotlin.collections.MapsKt.createMapBuilder(-1); } catch (Throwable failure) { System.out.println("map.capacity=" + failure.getMessage()); }
        List<Integer> list = kotlin.collections.CollectionsKt.createListBuilder(2);
        list.add(1); list.add(2); list.add(3);
        List<Integer> sub = list.subList(1, 3);
        ListIterator<Integer> iterator = list.listIterator(); iterator.next();
        attempt("list.serializeBuilding", () -> serialized(list));
        List<Integer> built = kotlin.collections.CollectionsKt.build(list);
        System.out.println(built); System.out.println(built instanceof RandomAccess); System.out.println(built instanceof Serializable);
        attempt("list.addAll0", () -> list.addAll(Collections.emptyList()));
        attempt("list.removeAll0", () -> list.removeAll(Collections.emptyList()));
        attempt("list.retainAll", () -> list.retainAll(list));
        attempt("list.addIndex", () -> list.add(0, 4));
        attempt("list.removeIndex", () -> list.remove(0));
        attempt("list.iteratorRemove", iterator::remove);
        attempt("list.iteratorSet", () -> iterator.set(4));
        attempt("list.iteratorAdd", () -> iterator.add(4));
        attempt("list.subClear", sub::clear);
        attempt("list.subAdd0", () -> sub.addAll(Collections.emptyList()));
        attempt("list.postSubSet", () -> list.subList(0, 1).set(0, 4));
        attempt("list.replaceAll", () -> list.replaceAll(x -> x + 1));
        attempt("list.sort", () -> list.sort(Comparator.reverseOrder()));
        System.out.println(built); System.out.println(serialized(built)); System.out.println(serialized(sub));
        List<Integer> empty = kotlin.collections.CollectionsKt.createListBuilder();
        List<Integer> emptyBuilt = kotlin.collections.CollectionsKt.build(empty);
        System.out.println(emptyBuilt == empty);
        System.out.println(kotlin.jvm.internal.TypeIntrinsics.isMutableList(emptyBuilt));
        attempt("empty.clear", empty::clear);
        Map<Integer, String> map = kotlin.collections.MapsKt.createMapBuilder(2);
        map.put(1, "one"); map.put(2, "two"); map.put(1, "ONE");
        Set<Integer> keys = map.keySet(); Collection<String> values = map.values();
        Set<Map.Entry<Integer, String>> entries = map.entrySet();
        Iterator<Integer> keyIterator = keys.iterator(); keyIterator.next();
        Iterator<String> valueIterator = values.iterator(); valueIterator.next();
        Iterator<Map.Entry<Integer, String>> entryIterator = entries.iterator(); Map.Entry<Integer, String> entry = entryIterator.next();
        attempt("map.serializeBuilding", () -> serialized(map));
        Map<Integer, String> mapped = kotlin.collections.MapsKt.build(map);
        System.out.println(mapped); System.out.println(mapped instanceof Serializable);
        attempt("map.putAll0", () -> map.putAll(Collections.emptyMap()));
        attempt("map.removeMissing", () -> map.remove(99));
        attempt("map.keyRemoveMissing", () -> keys.remove(99));
        attempt("map.keysRemoveAll0", () -> keys.removeAll(Collections.emptyList()));
        attempt("map.valuesClear", values::clear);
        attempt("map.keyIterator", keyIterator::remove);
        attempt("map.valueIterator", valueIterator::remove);
        attempt("map.entryIterator", entryIterator::remove);
        attempt("map.entrySetValue", () -> entry.setValue("changed"));
        attempt("map.newEntrySetValue", () -> map.entrySet().iterator().next().setValue("changed"));
        attempt("map.replaceAll", () -> map.replaceAll((key, value) -> "changed"));
        System.out.println(mapped); System.out.println(serialized(mapped));
        Map<Integer, String> growing = kotlin.collections.MapsKt.createMapBuilder();
        attempt("building.keysAddAll0", () -> growing.keySet().addAll(Collections.emptySet()));
        attempt("building.valuesAddAll0", () -> growing.values().addAll(Collections.emptyList()));
        attempt("building.entriesAddAll0", () -> growing.entrySet().addAll(Collections.emptySet()));
        List<Integer> beforeNext = kotlin.collections.CollectionsKt.createListBuilder(); beforeNext.add(1);
        ListIterator<Integer> noNext = beforeNext.listIterator(); Iterator<Integer> noNextIterator = beforeNext.iterator();
        kotlin.collections.CollectionsKt.build(beforeNext);
        attempt("frozen.iteratorSetBeforeNext", () -> noNext.set(2));
        attempt("frozen.iteratorRemoveBeforeNext", noNext::remove);
        attempt("frozen.removeBeforeNext", noNextIterator::remove);
        Map<Integer, String> beforeKey = kotlin.collections.MapsKt.createMapBuilder(); beforeKey.put(1, "a");
        Iterator<Integer> noKey = beforeKey.keySet().iterator(); kotlin.collections.MapsKt.build(beforeKey);
        attempt("frozen.keyRemoveBeforeNext", noKey::remove);
        List<Integer> changed = kotlin.collections.CollectionsKt.createListBuilder(); changed.add(1);
        ListIterator<Integer> stale = changed.listIterator(); stale.next(); changed.add(2);
        kotlin.collections.CollectionsKt.build(changed);
        attempt("frozen.staleSet", () -> stale.set(3));
        attempt("frozen.staleRemove", stale::remove);
        attempt("frozen.staleAdd", () -> stale.add(3));
        Map<Integer, String> changedMap = kotlin.collections.MapsKt.createMapBuilder(); changedMap.put(1, "a");
        Iterator<Integer> staleKey = changedMap.keySet().iterator(); staleKey.next(); changedMap.put(2, "b");
        kotlin.collections.MapsKt.build(changedMap); attempt("frozen.staleKeyRemove", staleKey::remove);
        Map<Integer, String> entryMap = kotlin.collections.MapsKt.createMapBuilder(); entryMap.put(1, "a");
        Map.Entry<Integer, String> staleEntry = entryMap.entrySet().iterator().next(); entryMap.put(2, "b");
        kotlin.collections.MapsKt.build(entryMap);
        attempt("frozen.staleEntryKey", staleEntry::getKey);
        attempt("frozen.staleEntryValue", staleEntry::getValue);
        attempt("frozen.staleEntrySet", () -> staleEntry.setValue("x"));
        attempt("frozen.staleEntryHash", staleEntry::hashCode);
        attempt("frozen.staleEntryString", staleEntry::toString);
        attempt("frozen.staleEntryEquals", () -> staleEntry.equals(new AbstractMap.SimpleEntry<>(1, "a")));
        System.out.println("staleEntry.equalsNull=" + staleEntry.equals(null));
        Map<Integer, String> replacedMap = kotlin.collections.MapsKt.createMapBuilder(); replacedMap.put(1, "a");
        Map.Entry<Integer, String> replacedEntry = replacedMap.entrySet().iterator().next(); replacedMap.put(1, "b");
        kotlin.collections.MapsKt.build(replacedMap); System.out.println(replacedEntry.getKey() + "=" + replacedEntry.getValue());
        attempt("frozen.replacedEntrySet", () -> replacedEntry.setValue("x"));
        List<Integer> removed = kotlin.collections.CollectionsKt.createListBuilder(); removed.add(1);
        ListIterator<Integer> removedIterator = removed.listIterator(); removedIterator.next(); removedIterator.remove();
        kotlin.collections.CollectionsKt.build(removed);
        attempt("frozen.iteratorSetAfterRemove", () -> removedIterator.set(2));
        attempt("frozen.iteratorRemoveTwice", removedIterator::remove);
        List<Integer> inserted = kotlin.collections.CollectionsKt.createListBuilder(); inserted.add(1);
        ListIterator<Integer> insertedIterator = inserted.listIterator(); insertedIterator.next(); insertedIterator.add(2);
        kotlin.collections.CollectionsKt.build(inserted);
        attempt("frozen.iteratorSetAfterAdd", () -> insertedIterator.set(3));
        attempt("frozen.iteratorRemoveAfterAdd", insertedIterator::remove);
        List<Integer> replacement = kotlin.collections.CollectionsKt.createListBuilder(); replacement.add(1);
        ListIterator<Integer> replacementIterator = replacement.listIterator(); replacementIterator.next(); replacement.set(0, 2);
        kotlin.collections.CollectionsKt.build(replacement); attempt("frozen.iteratorSetAfterReplace", () -> replacementIterator.set(3));
        Map<Integer, String> emptyMap = kotlin.collections.MapsKt.createMapBuilder();
        Map<Integer, String> emptyMapped = kotlin.collections.MapsKt.build(emptyMap);
        System.out.println(emptyMapped == emptyMap);
        System.out.println(kotlin.jvm.internal.TypeIntrinsics.isMutableMap(emptyMapped));
        attempt("emptyMap.clear", emptyMap::clear);
    }
}
