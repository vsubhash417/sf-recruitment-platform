/**
 * InterviewTriggerHandler
 *
 * Business rule: a Candidate cannot have two Interview records scheduled
 * within 60 minutes of each other. This is intentionally NOT a validation
 * rule, because validation rules can't easily query sibling records
 * (i.e. "other Interview rows for the same Candidate") — that requires Apex.
 *
 * Bulk-safe: handles 1 to 200 Interview records in a single trigger context
 * with exactly one SOQL query, regardless of how many records are being saved.
 */
public class InterviewTriggerHandler extends TriggerHandler {

    private static final Integer CONFLICT_WINDOW_MINUTES = 60;

    protected override void beforeInsert(List<SObject> newList) {
        checkForSchedulingConflicts((List<Interview__c>) newList, null);
    }

    protected override void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        checkForSchedulingConflicts((List<Interview__c>) newList, (Map<Id, Interview__c>) oldMap);
    }

    private void checkForSchedulingConflicts(List<Interview__c> newInterviews, Map<Id, Interview__c> oldMap) {
        // Collect the set of Candidate Ids we actually need to check.
        // On update, skip records where neither Candidate nor Interview_Date changed — saves a query.
        Set<Id> candidateIds = new Set<Id>();
        for (Interview__c interview : newInterviews) {
            if (interview.Candidate__c == null || interview.Interview_Date__c == null) {
                continue;
            }
            if (oldMap != null) {
                Interview__c oldRecord = oldMap.get(interview.Id);
                Boolean relevantFieldChanged =
                    interview.Candidate__c != oldRecord.Candidate__c ||
                    interview.Interview_Date__c != oldRecord.Interview_Date__c;
                if (!relevantFieldChanged) {
                    continue;
                }
            }
            candidateIds.add(interview.Candidate__c);
        }

        if (candidateIds.isEmpty()) {
            return;
        }

        // One query for the whole batch — never query inside a loop.
        Map<Id, List<Interview__c>> existingByCandidate = new Map<Id, List<Interview__c>>();
        for (Interview__c existing : [
            SELECT Id, Candidate__c, Interview_Date__c
            FROM Interview__c
            WHERE Candidate__c IN :candidateIds
        ]) {
            if (!existingByCandidate.containsKey(existing.Candidate__c)) {
                existingByCandidate.put(existing.Candidate__c, new List<Interview__c>());
            }
            existingByCandidate.get(existing.Candidate__c).add(existing);
        }

        Long conflictWindowMs = CONFLICT_WINDOW_MINUTES * 60 * 1000L;

        for (Interview__c interview : newInterviews) {
            if (interview.Candidate__c == null || interview.Interview_Date__c == null) {
                continue;
            }
            List<Interview__c> existingForCandidate = existingByCandidate.get(interview.Candidate__c);
            if (existingForCandidate == null) {
                continue;
            }
            for (Interview__c existing : existingForCandidate) {
                // Skip comparing a record to itself during an update
                if (existing.Id == interview.Id) {
                    continue;
                }
                Long diffMs = Math.abs(interview.Interview_Date__c.getTime() - existing.Interview_Date__c.getTime());
                if (diffMs < conflictWindowMs) {
                    interview.addError(
                        'This candidate already has an interview scheduled within ' +
                        CONFLICT_WINDOW_MINUTES + ' minutes of this time. Please choose a different slot.'
                    );
                    break;
                }
            }
        }
    }
}
