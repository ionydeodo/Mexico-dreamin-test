/**
 * Correos del evento (CA-02.6, CA-04.4, CA-06.1) usando las plantillas con marca del evento de la
 * carpeta "DevSummit CDMX". Las plantillas usan marcadores {{nombre}} que se combinan aquí; los
 * valores capturados por el asistente se escapan para que no puedan inyectar HTML en el correo.
 *
 * Un fallo al enviar (por ejemplo, el límite diario de correos del org) nunca revierte la inscripción.
 */
public without sharing class DevSummitEmailService {
    public static final String TPL_RECEIVED = 'DevSummit_Registration_Received';
    public static final String TPL_DECISION = 'DevSummit_Registration_Decision';
    public static final String TPL_SESSION_FULL = 'DevSummit_Session_Full';

    /** Mensajes construidos en la transacción actual (para pruebas y diagnóstico). */
    @TestVisible
    private static List<Messaging.SingleEmailMessage> outbox = new List<Messaging.SingleEmailMessage>();

    private static Map<String, EmailTemplate> templateCache;
    private static Id orgWideAddressId;
    private static Boolean orgWideLookedUp = false;

    // ------------------------------------------------------------------ API pública

    /** CA-02.6: código, datos de la sesión y estado de la inscripción recién creada. */
    public static void sendRegistrationReceived(Set<Id> registrationIds) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Registration__c r : queryRegistrations(registrationIds)) {
            Map<String, String> tokens = registrationTokens(r);
            tokens.put(
                'statusMessage',
                r.Status__c == DevSummit.REG_PENDING
                    ? 'Esta sesión es patrocinada, así que el equipo organizador revisará tu inscripción. Te avisaremos por correo en cuanto haya una decisión. Mientras tanto, tu lugar queda apartado.'
                    : '¡Tu lugar está confirmado! Te esperamos en la sala unos minutos antes del inicio.'
            );
            addIfBuilt(messages, build(TPL_RECEIVED, tokens, r.Attendee_Email__c));
        }
        send(messages);
    }

    /** CA-04.4: resultado de la aprobación o el rechazo. */
    public static void sendDecision(Set<Id> registrationIds) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Registration__c r : queryRegistrations(registrationIds)) {
            Map<String, String> tokens = registrationTokens(r);
            if (r.Status__c == DevSummit.REG_CONFIRMED) {
                tokens.put('decisionTitle', '¡Tu inscripción fue aprobada!');
                tokens.put('decisionMessage', 'Tu lugar está confirmado. Te esperamos en la sala unos minutos antes del inicio.');
            } else {
                tokens.put('decisionTitle', 'Tu inscripción no fue aprobada');
                tokens.put('decisionMessage', 'Motivo: ' + (r.Rejection_Reason__c == null ? '' : r.Rejection_Reason__c));
            }
            addIfBuilt(messages, build(TPL_DECISION, tokens, r.Attendee_Email__c));
        }
        send(messages);
    }

    /** CA-06.1: aviso a logística de que una sesión se llenó. */
    public static void sendSessionFull(List<Session__c> sessions) {
        String to = DevSummit.settings.Logistics_Email__c;
        if (String.isBlank(to)) {
            return;
        }
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Session__c s : sessions) {
            Map<String, String> tokens = new Map<String, String>{
                'sessionName' => s.Name,
                'sessionDate' => DevSummit.formatDateTime(s.Start__c) + ' – ' + (s.End__c == null ? '' : s.End__c.format('HH:mm', DevSummit.TIME_ZONE)),
                'room' => s.Room__c,
                'capacity' => s.Capacity__c == null ? '' : String.valueOf(s.Capacity__c.intValue())
            };
            addIfBuilt(messages, build(TPL_SESSION_FULL, tokens, to));
        }
        send(messages);
    }

    // ------------------------------------------------------------------ construcción

    private static List<Registration__c> queryRegistrations(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Registration__c>();
        }
        return [
            SELECT
                Id, Attendee_Name__c, Attendee_Email__c, Status__c, Confirmation_Code__c, Rejection_Reason__c,
                Session__r.Name, Session__r.Start__c, Session__r.End__c, Session__r.Room__c,
                Session__r.Speaker_Name__c, Session__r.Track__c
            FROM Registration__c
            WHERE Id IN :ids
        ];
    }

    private static Map<String, String> registrationTokens(Registration__c r) {
        Session__c s = r.Session__r;
        return new Map<String, String>{
            'attendeeName' => r.Attendee_Name__c,
            'confirmationCode' => r.Confirmation_Code__c,
            'statusLabel' => DevSummit.statusLabel(Registration__c.Status__c, r.Status__c),
            'sessionName' => s.Name,
            'sessionDate' => DevSummit.formatDateTime(s.Start__c) + ' – ' + (s.End__c == null ? '' : s.End__c.format('HH:mm', DevSummit.TIME_ZONE)),
            'room' => s.Room__c,
            'speaker' => s.Speaker_Name__c,
            'track' => s.Track__c
        };
    }

    @TestVisible
    private static Messaging.SingleEmailMessage build(String templateName, Map<String, String> tokens, String toAddress) {
        EmailTemplate tpl = templates().get(templateName);
        if (tpl == null || String.isBlank(toAddress)) {
            System.debug(LoggingLevel.ERROR, 'DevSummit: plantilla o destinatario faltante: ' + templateName);
            return null;
        }
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ toAddress });
        msg.setSubject(mergeTokens(tpl.Subject, tokens, false));
        if (String.isNotBlank(tpl.HtmlValue)) {
            msg.setHtmlBody(mergeTokens(tpl.HtmlValue, tokens, true));
        }
        if (String.isNotBlank(tpl.Body)) {
            msg.setPlainTextBody(mergeTokens(tpl.Body, tokens, false));
        }
        msg.setCharset('UTF-8');
        msg.setSaveAsActivity(false);
        msg.setUseSignature(false);
        applySender(msg);
        return msg;
    }

    @TestVisible
    private static String mergeTokens(String text, Map<String, String> tokens, Boolean html) {
        if (text == null) {
            return '';
        }
        String result = text;
        for (String key : tokens.keySet()) {
            String value = tokens.get(key) == null ? '' : tokens.get(key);
            result = result.replace('{{' + key + '}}', html ? value.escapeHtml4() : value);
        }
        return result;
    }

    /** RN-07: "DevSummit CDMX" &lt;no-reply@devsummit.example&gt;. */
    private static void applySender(Messaging.SingleEmailMessage msg) {
        DevSummit_Setting__mdt cfg = DevSummit.settings;
        if (!orgWideLookedUp) {
            orgWideLookedUp = true;
            List<OrgWideEmailAddress> owas = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE Address = :cfg.Sender_Address__c
                LIMIT 1
            ];
            orgWideAddressId = owas.isEmpty() ? null : owas[0].Id;
        }
        if (orgWideAddressId != null) {
            msg.setOrgWideEmailAddressId(orgWideAddressId);
        } else {
            // Sin dirección verificada, se usa el nombre del evento y la respuesta va al no-reply.
            msg.setSenderDisplayName(cfg.Sender_Name__c);
            if (String.isNotBlank(cfg.Sender_Address__c)) {
                msg.setReplyTo(cfg.Sender_Address__c);
            }
        }
    }

    private static Map<String, EmailTemplate> templates() {
        if (templateCache == null) {
            templateCache = new Map<String, EmailTemplate>();
            for (EmailTemplate t : [
                SELECT DeveloperName, Subject, HtmlValue, Body
                FROM EmailTemplate
                WHERE DeveloperName IN :new List<String>{ TPL_RECEIVED, TPL_DECISION, TPL_SESSION_FULL }
            ]) {
                templateCache.put(t.DeveloperName, t);
            }
        }
        return templateCache;
    }

    private static void addIfBuilt(List<Messaging.SingleEmailMessage> messages, Messaging.SingleEmailMessage msg) {
        if (msg != null) {
            messages.add(msg);
        }
    }

    private static void send(List<Messaging.SingleEmailMessage> messages) {
        if (messages.isEmpty()) {
            return;
        }
        outbox.addAll(messages);
        try {
            for (Messaging.SendEmailResult res : Messaging.sendEmail(messages, false)) {
                if (!res.isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'DevSummit: no se pudo enviar un correo: ' + res.getErrors());
                }
            }
        } catch (Exception e) {
            // Límite diario de correos, entregabilidad desactivada, etc. La inscripción sigue siendo válida.
            System.debug(LoggingLevel.ERROR, 'DevSummit: envío de correos falló: ' + e.getMessage());
        }
    }
}
