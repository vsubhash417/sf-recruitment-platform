@isTest
private class InterviewTriggerHandlerTest {

    // Shared setup data used by multiple test methods
    @testSetup
    static void setupData() {
        Candidate__c candidate = new Candidate__c(
            Name = 'Test Candidate',
            Email__c = 'test.candidate@example.com',
            Source__c = 'LinkedIn'
        );
        insert candidate;

        Job_Requisition__c requisition = new Job_Requisition__c(
            Name = 'Salesforce Developer',
            Department__c = 'Engineering',
            Status__c = 'Open',
            Openings__c = 2
        );
        insert requisition;
    }

    @isTest
    static void testSingleInterviewInsertsSuccessfully() {
        Candidate__c candidate = [SELECT Id FROM Candidate__c LIMIT 1];
        Job_Requisition__c requisition = [SELECT Id FROM Job_Requisition__c LIMIT 1];

        Interview__c interview = new Interview__c(
            Candidate__c = candidate.Id,
            Job_Requisition__c = requisition.Id,
            Interview_Date__c = DateTime.now().addDays(2),
            Stage__c = 'Screening'
        );

        Test.startTest();
        insert interview;
        Test.stopTest();

        List<Interview__c> results = [SELECT Id, Stage__c FROM Interview__c WHERE Id = :interview.Id];
        System.assertEquals(1, results.size(), 'Interview should have been inserted');
        System.assertEquals('Screening', results[0].Stage__c);
    }

    @isTest
    static void testConflictingInterviewIsBlocked() {
        Candidate__c candidate = [SELECT Id FROM Candidate__c LIMIT 1];
        Job_Requisition__c requisition = [SELECT Id FROM Job_Requisition__c LIMIT 1];

        DateTime slot = DateTime.now().addDays(3);

        Interview__c firstInterview = new Interview__c(
            Candidate__c = candidate.Id,
            Job_Requisition__c = requisition.Id,
            Interview_Date__c = slot,
            Stage__c = 'Screening'
        );
        insert firstInterview;

        // Attempt to book a second interview only 30 minutes later — should be blocked
        Interview__c conflictingInterview = new Interview__c(
            Candidate__c = candidate.Id,
            Job_Requisition__c = requisition.Id,
            Interview_Date__c = slot.addMinutes(30),
            Stage__c = 'Technical Round'
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(conflictingInterview, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Conflicting interview should have failed to insert');
        System.assert(
            result.getErrors()[0].getMessage().contains('already has an interview scheduled'),
            'Error message should explain the scheduling conflict'
        );
    }

    @isTest
    static void testNonConflictingInterviewOutsideWindowSucceeds() {
        Candidate__c candidate = [SELECT Id FROM Candidate__c LIMIT 1];
        Job_Requisition__c requisition = [SELECT Id FROM Job_Requisition__c LIMIT 1];

        DateTime slot = DateTime.now().addDays(4);

        Interview__c firstInterview = new Interview__c(
            Candidate__c = candidate.Id,
            Job_Requisition__c = requisition.Id,
            Interview_Date__c = slot,
            Stage__c = 'Screening'
        );
        insert firstInterview;

        // 3 hours later — well outside the 60-minute conflict window
        Interview__c laterInterview = new Interview__c(
            Candidate__c = candidate.Id,
            Job_Requisition__c = requisition.Id,
            Interview_Date__c = slot.addHours(3),
            Stage__c = 'Technical Round'
        );

        Test.startTest();
        insert laterInterview;
        Test.stopTest();

        System.assertNotEquals(null, laterInterview.Id, 'Non-conflicting interview should insert successfully');
    }

    @isTest
    static void testBulkInsertOfTwoHundredInterviewsAcrossDifferentCandidates() {
        Job_Requisition__c requisition = [SELECT Id FROM Job_Requisition__c LIMIT 1];

        // Create 200 distinct candidates so none of them conflict with each other
        List<Candidate__c> candidates = new List<Candidate__c>();
        for (Integer i = 0; i < 200; i++) {
            candidates.add(new Candidate__c(
                Name = 'Bulk Candidate ' + i,
                Email__c = 'bulk' + i + '@example.com',
                Source__c = 'Job Board'
            ));
        }
        insert candidates;

        List<Interview__c> interviews = new List<Interview__c>();
        for (Candidate__c c : candidates) {
            interviews.add(new Interview__c(
                Candidate__c = c.Id,
                Job_Requisition__c = requisition.Id,
                Interview_Date__c = DateTime.now().addDays(5),
                Stage__c = 'Screening'
            ));
        }

        Test.startTest();
        insert interviews;
        Test.stopTest();

        System.assertEquals(
            200,
            [SELECT COUNT() FROM Interview__c WHERE Stage__c = 'Screening'],
            'All 200 interviews across distinct candidates should insert without governor limit issues'
        );
    }

    @isTest
    static void testUpdatingUnrelatedFieldDoesNotTriggerConflictCheck() {
        Candidate__c candidate = [SELECT Id FROM Candidate__c LIMIT 1];
        Job_Requisition__c requisition = [SELECT Id FROM Job_Requisition__c LIMIT 1];

        Interview__c interview = new Interview__c(
            Candidate__c = candidate.Id,
            Job_Requisition__c = requisition.Id,
            Interview_Date__c = DateTime.now().addDays(6),
            Stage__c = 'Screening'
        );
        insert interview;

        interview.Feedback__c = 'Strong communication skills.';

        Test.startTest();
        update interview;
        Test.stopTest();

        Interview__c updated = [SELECT Feedback__c FROM Interview__c WHERE Id = :interview.Id];
        System.assertEquals('Strong communication skills.', updated.Feedback__c);
    }
}
