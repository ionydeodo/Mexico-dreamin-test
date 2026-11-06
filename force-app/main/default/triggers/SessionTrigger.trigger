trigger SessionTrigger on Session__c(before insert, before update, after update) {
    switch on Trigger.operationType {
        when BEFORE_INSERT {
            SessionTriggerHandler.beforeInsert(Trigger.new);
        }
        when BEFORE_UPDATE {
            SessionTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
        when AFTER_UPDATE {
            SessionTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
