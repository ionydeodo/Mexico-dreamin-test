// Asigna el permission set del sitio al usuario invitado de "Rastreo RutaCargo".
List<User> guests = [
    SELECT Id, Username FROM User
    WHERE UserType = 'Guest' AND Profile.Name LIKE 'Rastreo RutaCargo%'
    LIMIT 1
];
if (guests.isEmpty()) {
    throw new IllegalArgumentException('Aún no existe el usuario invitado del sitio. Espera a que termine "sf community create".');
}
PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'RutaCargo_Guest_Site'];
if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :guests[0].Id AND PermissionSetId = :ps.Id] == 0) {
    insert new PermissionSetAssignment(AssigneeId = guests[0].Id, PermissionSetId = ps.Id);
}
System.debug(LoggingLevel.ERROR, 'Permission set asignado a ' + guests[0].Username);
