trigger RegistrationTrigger on Registration__c(before insert, after insert, before update, after update) {
    switch on Trigger.operationType {
        when BEFORE_INSERT {
            RegistrationTriggerHandler.beforeInsert(Trigger.new);
        }
        when AFTER_INSERT {
            RegistrationTriggerHandler.afterInsert(Trigger.new);
        }
        when BEFORE_UPDATE {
            RegistrationTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
        when AFTER_UPDATE {
            RegistrationTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
