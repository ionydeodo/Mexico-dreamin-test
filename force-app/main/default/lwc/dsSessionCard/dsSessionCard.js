import { LightningElement, api } from 'lwc';
import { formatSchedule } from 'c/dsUtils';

const FEW_SEATS = 5;

/**
 * Tarjeta de sesión (CA-01.4, CA-01.5).
 */
export default class DsSessionCard extends LightningElement {
    @api session;

    get titleId() {
        return `ds-title-${this.session.id}`;
    }

    get schedule() {
        return formatSchedule(this.session.startTime, this.session.endTime);
    }

    get cardClass() {
        return this.session.isFull ? 'card card_full' : 'card';
    }

    get seatsText() {
        const n = this.session.availableSeats;
        return n === 1 ? '1 cupo disponible' : `${n} cupos disponibles`;
    }

    get seatsClass() {
        return this.session.availableSeats <= FEW_SEATS ? 'seats seats_few' : 'seats';
    }

    get buttonLabel() {
        return `Inscribirme a ${this.session.title}`;
    }

    handleRegister() {
        this.dispatchEvent(new CustomEvent('register', { detail: { sessionId: this.session.id } }));
    }
}
