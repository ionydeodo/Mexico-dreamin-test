import { LightningElement } from 'lwc';
import findMyRegistrations from '@salesforce/apex/PublicSiteController.findMyRegistrations';
import { formatSchedule, reduceError } from 'c/dsUtils';

const NOT_FOUND = 'No encontramos inscripciones con esos datos.';
const BADGES = {
    Confirmed: 'badge badge_ok',
    Pending: 'badge badge_pending',
    Rejected: 'badge badge_rejected'
};

/**
 * Consulta de inscripciones con email y código (HU-03).
 */
export default class DsMyRegistrations extends LightningElement {
    email = '';
    code = '';
    loading = false;
    message;
    registrations = [];

    get hasRegistrations() {
        return this.registrations.length > 0;
    }

    get buttonLabel() {
        return this.loading ? 'Buscando…' : 'Consultar';
    }

    handleInput(event) {
        const { name, value } = event.target;
        this[name] = name === 'code' ? value.toUpperCase() : value;
    }

    async handleSubmit(event) {
        event.preventDefault();
        this.message = undefined;
        this.registrations = [];
        if (!this.email.trim() || this.code.trim().length !== 6) {
            this.message = NOT_FOUND;
            return;
        }
        this.loading = true;
        try {
            const res = await findMyRegistrations({ email: this.email, confirmationCode: this.code });
            if (res && res.found) {
                this.registrations = res.registrations.map((r, i) => ({
                    ...r,
                    key: `${i}-${r.sessionTitle}`,
                    schedule: formatSchedule(r.startTime, r.endTime),
                    badgeClass: BADGES[r.status] || 'badge'
                }));
            } else {
                this.message = (res && res.message) || NOT_FOUND;
            }
        } catch (e) {
            this.message = reduceError(e);
        } finally {
            this.loading = false;
        }
    }
}
