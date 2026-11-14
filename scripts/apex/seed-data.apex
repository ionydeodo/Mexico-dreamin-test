// Datos de prueba reproducibles (sección "Datos de prueba y definición de terminado").
// 2 empresas remitentes y 120 envíos ficticios: RC000001001-RC000001060 (Abarrotes Acme)
// y RC000001061-RC000001120 (Globex Farma). Ejecutar en un org recién creado:
//   sf apex run --file scripts/apex/seed-data.apex
// Es determinista: mismos datos en cada org. Las fechas son relativas a "hoy".

if ([SELECT COUNT() FROM Shipment__c] > 0) {
    throw new IllegalArgumentException('El org ya tiene envíos; los datos de prueba solo se cargan en un org vacío.');
}

Account acme = new Account(Name = 'Abarrotes Acme', Credit_Risk__c = 'Bajo', Credit_Limit__c = 500000);
Account globex = new Account(Name = 'Globex Farma', Credit_Risk__c = 'Alto', Credit_Limit__c = 150000);
insert new List<Account>{ acme, globex };

List<String> statuses = new List<String>{ 'Recolectado', 'En tránsito', 'En reparto', 'Entregado', 'Incidencia' };
// [ciudad, estado abreviado, código postal, colonia, calle, centro de distribución]
List<List<String>> places = new List<List<String>>{
    new List<String>{ 'Ciudad de México', 'CDMX', '06700', 'Roma Norte', 'Calle Orizaba', 'CEDIS Vallejo' },
    new List<String>{ 'Guadalajara', 'Jal.', '44160', 'Americana', 'Av. Chapultepec', 'CEDIS El Salto' },
    new List<String>{ 'Monterrey', 'NL', '64000', 'Centro', 'Calle Padre Mier', 'CEDIS Apodaca' },
    new List<String>{ 'Puebla', 'Pue.', '72000', 'Centro Histórico', 'Av. Reforma', 'CEDIS Cuautlancingo' },
    new List<String>{ 'Querétaro', 'Qro.', '76000', 'Centro', 'Calle Madero', 'CEDIS El Marqués' },
    new List<String>{ 'Mérida', 'Yuc.', '97000', 'Centro', 'Calle 60', 'CEDIS Umán' },
    new List<String>{ 'Tijuana', 'BC', '22000', 'Zona Centro', 'Av. Revolución', 'CEDIS Otay' },
    new List<String>{ 'León', 'Gto.', '37000', 'Centro', 'Calle Hidalgo', 'CEDIS Silao' },
    new List<String>{ 'Toluca', 'Edo. Méx.', '50000', 'Centro', 'Av. Hidalgo', 'CEDIS Lerma' },
    new List<String>{ 'Oaxaca', 'Oax.', '68000', 'Centro', 'Calle Macedonio Alcalá', 'CEDIS Santa Lucía' },
    new List<String>{ 'Veracruz', 'Ver.', '91700', 'Centro', 'Av. Independencia', 'CEDIS Puerto' },
    new List<String>{ 'Cancún', 'Q. Roo', '77500', 'Supermanzana 22', 'Av. Tulum', 'CEDIS Cancún' }
};
List<String> firstNames = new List<String>{ 'Ana', 'Luis', 'María', 'Jorge', 'Sofía', 'Carlos', 'Valeria', 'Diego', 'Fernanda', 'Ricardo', 'Lucía', 'Andrés' };
List<String> lastNames = new List<String>{ 'Hernández', 'García', 'Martínez', 'López', 'González', 'Pérez', 'Rodríguez', 'Sánchez', 'Ramírez', 'Torres', 'Flores', 'Rivera' };
List<String> instructions = new List<String>{
    'Dejar con el portero.',
    'Tocar el timbre dos veces.',
    'Entregar de 9 a 14 h.',
    'Llamar antes de llegar.',
    null
};
List<String> notes = new List<String>{
    'Cliente pide factura al recibir.',
    'Revisar empaque: frágil.',
    'Ruta con acceso restringido por obras.',
    'Prioridad por campaña de temporada.'
};

Date today = Date.valueOf(Datetime.now().format('yyyy-MM-dd', 'America/Mexico_City'));
Datetime now = Datetime.now();
List<Shipment__c> rows = new List<Shipment__c>();

for (Integer i = 0; i < 120; i++) {
    Boolean isAcme = i < 60;
    Integer n = Math.mod(i, 60);
    String status = statuses[Math.mod(n, 5)];
    List<String> origin = places[Math.mod(i * 7 + 3, places.size())];
    List<String> dest = places[Math.mod(i * 5, places.size())];
    if (origin[0] == dest[0]) {
        origin = places[Math.mod(i * 5 + 1, places.size())];
    }
    Integer hoursAgo = 2 + Math.mod(i * 13, 70);
    Datetime lastUpdate = now.addHours(-hoursAgo);
    Date eta;
    String lastLocation;
    if (status == 'Recolectado') {
        eta = today.addDays(3 + Math.mod(i, 4));
        lastLocation = origin[5] + ', ' + origin[0];
    } else if (status == 'En tránsito') {
        eta = today.addDays(1 + Math.mod(i, 4));
        lastLocation = 'En ruta hacia ' + dest[0] + ', ' + dest[1];
    } else if (status == 'En reparto') {
        eta = today;
        lastLocation = dest[5] + ', ' + dest[0];
    } else if (status == 'Entregado') {
        eta = today.addDays(-1 - Math.mod(i, 5));
        lastLocation = dest[0] + ', ' + dest[1];
    } else {
        eta = today.addDays(2);
        lastLocation = dest[5] + ', ' + dest[0] + ' (dirección incompleta)';
    }
    Decimal weight = 0.5 + Math.mod(i * 37, 300) / 10.0;
    Decimal price = (120 + weight * 18).setScale(2);
    Decimal cost = (price * (isAcme ? 0.62 : 0.71)).setScale(2);
    String first = firstNames[Math.mod(i * 5 + 1, firstNames.size())];
    String last = lastNames[Math.mod(i * 7 + 2, lastNames.size())] + ' ' + lastNames[Math.mod(i * 3 + 5, lastNames.size())];

    Shipment__c s = new Shipment__c(
        Account__c = isAcme ? acme.Id : globex.Id,
        Customer_Reference__c = (isAcme ? 'ACME-' : 'GLX-') + String.valueOf(2026000 + n + 1),
        Status__c = status,
        Origin_City__c = origin[0] + ', ' + origin[1],
        Destination_City__c = dest[0] + ', ' + dest[1],
        Last_Location__c = lastLocation,
        Last_Update__c = lastUpdate,
        Estimated_Delivery__c = eta,
        Reschedule_Count__c = Math.mod(i, 17) == 0 ? 1 : 0,
        Recipient_Name__c = first + ' ' + last,
        Recipient_Address__c = dest[4] + ' ' + (100 + Math.mod(i * 29, 800)) + ', Col. ' + dest[3] + ', ' + dest[0] + ', ' + dest[1],
        Destination_Postal_Code__c = dest[2],
        Recipient_Phone__c = '+52 55 5' + String.valueOf(1000000 + i * 7919).right(3) + ' ' + String.valueOf(1000 + i).right(4),
        Recipient_Email__c = first.toLowerCase().replace('í', 'i').replace('á', 'a').replace('é', 'e') + '.' + i + '@example.com',
        Delivery_Instructions__c = instructions[Math.mod(i, instructions.size())],
        Weight_Kg__c = weight,
        Price__c = price,
        Carrier_Cost__c = cost,
        Internal_Notes__c = notes[Math.mod(i, notes.size())]
    );
    if (status == 'Entregado') {
        s.Delivered_At__c = lastUpdate;
        s.Proof_Id__c = 'PRF-' + String.valueOf(88000 + i);
    }
    rows.add(s);
}
insert rows;

List<Shipment__c> saved = [SELECT Name, Status__c, Destination_Postal_Code__c FROM Shipment__c ORDER BY Name];
System.debug(LoggingLevel.ERROR, 'Envíos creados: ' + saved.size() + ' (' + saved[0].Name + ' a ' + saved[saved.size() - 1].Name + ')');
for (Integer i = 0; i < 5; i++) {
    System.debug(LoggingLevel.ERROR, 'Ejemplo: ' + saved[i].Name + ' · ' + saved[i].Status__c + ' · CP ' + saved[i].Destination_Postal_Code__c);
}
