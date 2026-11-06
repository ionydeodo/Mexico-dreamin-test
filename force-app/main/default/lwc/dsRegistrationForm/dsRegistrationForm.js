import { LightningElement, api } from 'lwc';
import register from '@salesforce/apex/PublicSiteController.register';
import { formatSchedule, isValidEmail, reduceError } from 'c/dsUtils';

/** Resultados que vuelven a consultar los cupos del catálogo. */
const REFRESH_CODES = new Set(['SESSION_FULL', 'SESSION_CANCELLED', 'NOT_FOUND']);

/**
 * Formulario de inscripción (HU-02).
 */
export default class DsRegistrationForm extends LightningElement {
    @api session;

    fullName = '';
    email = '';
    company = '';
    jobTitle = '';
    errors = {};
    serverError;
    serverErrorCode;
    submitting = false;
    result;

    renderedOnce = false;
    previousFocus;

    connectedCallback() {
        this.previousFocus = document.activeElement;
    }

    renderedCallback() {
        if (!this.renderedOnce) {
            this.renderedOnce = true;
            const first = this.template.querySelector('#ds-name') || this.template.querySelector('input');
            if (first) {
                first.focus();
            }
        }
    }

    disconnectedCallback() {
        if (this.previousFocus && typeof this.previousFocus.focus === 'function') {
            this.previousFocus.focus();
        }
    }

    // ------------------------------------------------------------ getters

    get schedule() {
        return formatSchedule(this.session.startTime, this.session.endTime);
    }

    get nameInvalid() {
        return this.errors.fullName ? 'true' : 'false';
    }

    get emailInvalid() {
        return this.errors.email ? 'true' : 'false';
    }

    get companyInvalid() {
        return this.errors.company ? 'true' : 'false';
    }

    get submitDisabled() {
        return this.submitting;
    }

    get submitLabel() {
        return this.submitting ? 'Enviando…' : 'Confirmar inscripción';
    }

    get serverErrorClass() {
        return this.serverErrorCode === 'ALREADY_REGISTERED' ? 'alert alert_info' : 'alert';
    }

    get isPending() {
        return this.result && this.result.status === 'Pending';
    }

    get successIcon() {
        return this.isPending ? '⏳' : '🎉';
    }

    get successTitle() {
        return this.isPending ? 'Recibimos tu inscripción' : '¡Listo, tu lugar está confirmado!';
    }

    get successMessage() {
        return this.isPending
            ? 'Quedó Pendiente de aprobación. Tu lugar está apartado mientras el equipo organizador la revisa.'
            : 'Te esperamos en la sala unos minutos antes del inicio.';
    }

    // ------------------------------------------------------------ handlers

    handleInput(event) {
        const { name, value } = event.target;
        this[name] = value;
        if (this.errors[name]) {
            this.errors = { ...this.errors, [name]: undefined };
        }
    }

    validate() {
        const errors = {};
        if (!this.fullName.trim()) {
            errors.fullName = 'Escribe tu nombre completo.';
        }
        if (!this.email.trim()) {
            errors.email = 'Escribe tu email.';
        } else if (!isValidEmail(this.email)) {
            errors.email = 'Escribe un email con formato válido.';
        }
        if (!this.company.trim()) {
            errors.company = 'Escribe tu empresa.';
        }
        this.errors = errors;
        const firstInvalid = Object.keys(errors)[0];
        if (firstInvalid) {
            const input = this.template.querySelector(`input[name="${firstInvalid}"]`);
            if (input) {
                input.focus();
            }
            return false;
        }
        return true;
    }

    async handleSubmit(event) {
        event.preventDefault();
        if (this.submitting) {
            return;
        }
        this.serverError = undefined;
        this.serverErrorCode = undefined;
        if (!this.validate()) {
            return;
        }
        this.submitting = true;
        try {
            const res = await register({
                sessionId: this.session.id,
                fullName: this.fullName,
                email: this.email,
                company: this.company,
                jobTitle: this.jobTitle
            });
            if (res && res.success) {
                this.result = res;
                this.notifyChanged();
            } else {
                this.serverErrorCode = res ? res.resultCode : 'ERROR';
                this.serverError = res && res.message ? res.message : reduceError();
                if (REFRESH_CODES.has(this.serverErrorCode)) {
                    // CA-02.8: la sesión se llenó mientras llenaba el formulario.
                    this.notifyChanged();
                }
            }
        } catch (e) {
            this.serverError = reduceError(e);
        } finally {
            this.submitting = false;
        }
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.close();
        }
    }

    handleBackdrop() {
        if (!this.submitting) {
            this.close();
        }
    }

    notifyChanged() {
        this.dispatchEvent(new CustomEvent('changed'));
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}
