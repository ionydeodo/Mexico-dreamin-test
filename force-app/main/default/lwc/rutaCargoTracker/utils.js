export const STATUS_ORDER = ['Recolectado', 'En tránsito', 'En reparto', 'Entregado', 'Incidencia'];

const DATE_FORMAT = new Intl.DateTimeFormat('es-MX', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC'
});

/** 'yyyy-mm-dd' -> 'vie, 20 nov 2026'. Se formatea en UTC para no correr el día. */
export function formatIsoDate(iso) {
    if (!iso) {
        return '—';
    }
    const [y, m, d] = iso.split('-').map(Number);
    return DATE_FORMAT.format(new Date(Date.UTC(y, m - 1, d)));
}

/** Cuenta los valores no vacíos y únicos, igual que el servidor (CA-001.1, CA-001.5). */
export function countValues(raw) {
    if (!raw) {
        return 0;
    }
    const seen = new Set();
    raw.split(/[,\r\n]+/)
        .map((v) => v.trim().toUpperCase())
        .filter((v) => v)
        .forEach((v) => seen.add(v));
    return seen.size;
}

/** CA-001.4: ordena por estado (flujo logístico) o por fecha estimada. "No encontrado" al final. */
export function sortResults(rows, sortBy) {
    const rank = (r) => (r.found ? STATUS_ORDER.indexOf(r.status) : STATUS_ORDER.length + 1);
    const byDate = (a, b) => {
        if (!a.found || !b.found) {
            return (a.found ? 0 : 1) - (b.found ? 0 : 1);
        }
        return (a.estimatedDelivery || '9999').localeCompare(b.estimatedDelivery || '9999');
    };
    const copy = [...rows];
    if (sortBy === 'status') {
        copy.sort((a, b) => rank(a) - rank(b) || byDate(a, b));
    } else if (sortBy === 'date') {
        copy.sort((a, b) => byDate(a, b) || rank(a) - rank(b));
    }
    return copy;
}

export function statusClass(status) {
    const base = 'status';
    switch (status) {
        case 'Entregado':
            return `${base} status_ok`;
        case 'Incidencia':
            return `${base} status_error`;
        case 'En reparto':
            return `${base} status_active`;
        default:
            return `${base} status_neutral`;
    }
}

export function errorMessage(error) {
    if (!error) {
        return 'Ocurrió un error. Intenta de nuevo.';
    }
    if (error.body && error.body.message) {
        return error.body.message;
    }
    if (Array.isArray(error.body) && error.body.length) {
        return error.body[0].message;
    }
    return error.message || 'Ocurrió un error. Intenta de nuevo.';
}
