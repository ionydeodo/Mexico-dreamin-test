/**
 * Datos de prueba para las pruebas de DevSummit.
 */
@IsTest
public class DevSummitTestFactory {
    /** Fija la configuración del evento para que las pruebas no dependan del Custom Metadata del org. */
    public static void useDefaultSettings() {
        DevSummit.settingsOverride = new DevSummit_Setting__mdt(
            Sender_Name__c = 'DevSummit CDMX',
            Sender_Address__c = 'no-reply@devsummit.example',
            Logistics_Email__c = 'logistica@devsummit.example'
        );
    }

    public static Session__c session(String name, Integer capacity, Boolean sponsored) {
        Datetime start = Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0); // 10:00 CDMX
        return new Session__c(
            Name = name,
            Track__c = 'Apex',
            Start__c = start,
            End__c = start.addMinutes(90),
            Room__c = 'Sala A',
            Capacity__c = capacity,
            Speaker_Name__c = 'Laura Méndez',
            Speaker_Email__c = 'laura.mendez@speakers.example',
            Speaker_Phone__c = '+52 55 0000 0001',
            Is_Sponsored__c = sponsored,
            Sponsor_Name__c = sponsored ? 'Nube Andina' : null,
            Sponsor_Fee__c = sponsored ? 45000 : null,
            Internal_Notes__c = 'Nota interna confidencial'
        );
    }

    public static Session__c insertSession(String name, Integer capacity, Boolean sponsored) {
        Session__c s = session(name, capacity, sponsored);
        insert s;
        return s;
    }

    public static Registration__c registration(Id sessionId, String email) {
        return new Registration__c(
            Session__c = sessionId,
            Attendee_Name__c = 'Ana López',
            Attendee_Email__c = email,
            Company__c = 'Nube Andina',
            Job_Title__c = 'Developer'
        );
    }

    /** Usuario interno con el permission set de organizador (incluye Approve_Registrations). */
    public static User organizer() {
        return userWith('DevSummit_Organizer', 'org');
    }

    /** Usuario interno sin el permiso personalizado de aprobación. */
    public static User nonOrganizer() {
        return userWith(null, 'std');
    }

    private static User userWith(String permissionSetName, String prefix) {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE UserLicense.Name = 'Salesforce' AND PermissionsModifyAllData = FALSE AND UserType = 'Standard'
            ORDER BY CreatedDate
            LIMIT 1
        ];
        String unique = prefix + String.valueOf(Crypto.getRandomInteger()).replace('-', 'n');
        User u = new User(
            ProfileId = p.Id,
            Username = unique + '@devsummit.test',
            Email = unique + '@devsummit.test',
            LastName = 'Prueba',
            FirstName = prefix,
            Alias = unique.left(8),
            TimeZoneSidKey = 'America/Mexico_City',
            LocaleSidKey = 'es_MX',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'es_MX'
        );
        // runAs evita MIXED_DML_OPERATION al combinar objetos de setup con datos de negocio.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            if (permissionSetName != null) {
                PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName];
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
            }
        }
        return u;
    }
}
