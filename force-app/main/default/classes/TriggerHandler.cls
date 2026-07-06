/**
 * TriggerHandler
 *
 * Base class for a bulkified, context-aware trigger handler framework.
 * Every object-specific handler (e.g. InterviewTriggerHandler) extends this
 * class and overrides only the context methods it actually needs.
 *
 * WHY THIS PATTERN:
 * - Keeps trigger files "thin" (1 line) — all logic lives in testable Apex classes
 * - Avoids duplicate trigger logic scattered across multiple triggers per object
 * - Naturally bulkified since it always operates on Trigger.new / Trigger.old (lists)
 * - Includes a recursion guard so the same handler can't accidentally loop forever
 */
public virtual class TriggerHandler {

    // Tracks how many times each handler type has run in this transaction,
    // so we can stop infinite recursion (e.g. a trigger updating its own object).
    private static Map<String, Integer> recursionMap = new Map<String, Integer>();

    public void run() {
        String handlerName = getHandlerName();

        if (!validateRun()) {
            return;
        }

        addToRecursionMap(handlerName);

        if (Trigger.isBefore) {
            if (Trigger.isInsert) beforeInsert(Trigger.new);
            if (Trigger.isUpdate) beforeUpdate(Trigger.new, Trigger.oldMap);
            if (Trigger.isDelete) beforeDelete(Trigger.old);
        } else if (Trigger.isAfter) {
            if (Trigger.isInsert) afterInsert(Trigger.new);
            if (Trigger.isUpdate) afterUpdate(Trigger.new, Trigger.oldMap);
            if (Trigger.isDelete) afterDelete(Trigger.old);
            if (Trigger.isUndelete) afterUndelete(Trigger.new);
        }
    }

    // ---- Override these in child handler classes as needed ----
    protected virtual void beforeInsert(List<SObject> newList) {}
    protected virtual void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {}
    protected virtual void beforeDelete(List<SObject> oldList) {}
    protected virtual void afterInsert(List<SObject> newList) {}
    protected virtual void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {}
    protected virtual void afterDelete(List<SObject> oldList) {}
    protected virtual void afterUndelete(List<SObject> newList) {}

    // ---- Recursion control ----
    private String getHandlerName() {
        return String.valueOf(this).substring(0, String.valueOf(this).indexOf(':'));
    }

    private Boolean validateRun() {
        if (!Trigger.isExecuting) {
            throw new TriggerHandlerException('TriggerHandler.run() can only be called from a trigger context.');
        }
        return true;
    }

    private void addToRecursionMap(String handlerName) {
        Integer count = recursionMap.containsKey(handlerName) ? recursionMap.get(handlerName) : 0;
        recursionMap.put(handlerName, count + 1);
    }

    // Call this from a handler if you need to guard against re-entrant recursion
    protected Boolean hasRunTooManyTimes(Integer maxAllowed) {
        String handlerName = getHandlerName();
        Integer count = recursionMap.containsKey(handlerName) ? recursionMap.get(handlerName) : 0;
        return count > maxAllowed;
    }

    public class TriggerHandlerException extends Exception {}
}
