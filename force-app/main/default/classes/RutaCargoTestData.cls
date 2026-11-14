@IsTest
public class RutaCargoTestData {
    public static Account sender() {
        Account a = new Account(Name = 'Remitente Prueba', Credit_Limit__c = 100000, Credit_Risk__c = 'Bajo');
        insert a;
        return a;
    }

    /** Envío en memoria (sin insertar) con datos completos. */
    public static Shipment__c shipment(Id accountId, String status, String reference) {
        Date today = ShipmentTrackingController.todayInMexicoCity();
        return new Shipment__c(
            Account__c = accountId,
            Customer_Reference__c = reference,
            Status__c = status,
            Origin_City__c = 'Guadalajara, Jal.',
            Destination_City__c = 'Monterrey, NL',
            Last_Location__c = 'Centro de distribución Guadalajara',
            Last_Update__c = Datetime.newInstanceGmt(2026, 11, 10, 18, 30, 0),
            Estimated_Delivery__c = today.addDays(3),
            Reschedule_Count__c = 0,
            Recipient_Name__c = 'María Prueba',
            Recipient_Address__c = 'Av. Ficticia 123, Col. Centro',
            Destination_Postal_Code__c = '64000',
            Recipient_Phone__c = '+52 81 5555 0101',
            Recipient_Email__c = 'maria.prueba@example.com',
            Delivery_Instructions__c = 'Dejar en recepción',
            Weight_Kg__c = 2.5,
            Price__c = 250,
            Carrier_Cost__c = 150,
            Internal_Notes__c = 'Cliente frecuente'
        );
    }

    public static Shipment__c insertShipment(String status, String reference) {
        Shipment__c s = shipment(sender().Id, status, reference);
        insert s;
        return reload(s.Id);
    }

    public static Shipment__c reload(Id shipmentId) {
        return [
            SELECT Id, Name, Status__c, Last_Location__c, Last_Update__c, Estimated_Delivery__c,
                   Original_Estimated_Delivery__c, Delivery_Instructions__c, Reschedule_Count__c,
                   Delivered_At__c, Proof_Id__c, Destination_Postal_Code__c, Margin__c
            FROM Shipment__c
            WHERE Id = :shipmentId
        ];
    }
}
