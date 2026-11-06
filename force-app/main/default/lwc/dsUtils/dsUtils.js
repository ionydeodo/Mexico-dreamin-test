/**
 * Utilidades compartidas del sitio público de DevSummit CDMX.
 */

/** RN-06: todos los horarios se muestran en hora de Ciudad de México. */
export const EVENT_TIME_ZONE = 'America/Mexico_City';

const dayFormat = new Intl.DateTimeFormat('es-MX', {
    timeZone: EVENT_TIME_ZONE,
    weekday: 'short',
    day: 'numeric',
    month: 'short'
});
const timeFormat = new Intl.DateTimeFormat('es-MX', {
    timeZone: EVENT_TIME_ZONE,
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
});

/** "jue, 20 nov · 10:00–11:30" en hora de Ciudad de México. */
export function formatSchedule(start, end) {
    if (!start) {
        return '';
    }
    const startDate = new Date(start);
    const day = dayFormat.format(startDate);
    const from = timeFormat.format(startDate);
    const to = end ? timeFormat.format(new Date(end)) : '';
    return to ? `${day} · ${from}–${to}` : `${day} · ${from}`;
}

/** Validación de formato en el navegador; el servidor vuelve a validar (CA-02.1). */
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
export function isValidEmail(value) {
    return EMAIL_PATTERN.test((value || '').trim());
}

export const GENERIC_ERROR = 'No pudimos completar la operación. Intenta de nuevo.';

/** Mensaje legible de un error de Apex o de red. */
export function reduceError(error) {
    if (!error) {
        return GENERIC_ERROR;
    }
    if (error.body && typeof error.body.message === 'string' && error.body.message) {
        return error.body.message;
    }
    return GENERIC_ERROR;
}
