import { LightningElement } from 'lwc';
import trackShipments from '@salesforce/apex/ShipmentTrackingController.track';
import getDeliveryDetail from '@salesforce/apex/ShipmentTrackingController.getDeliveryDetail';
import getProof from '@salesforce/apex/ShipmentTrackingController.getProof';
import reschedule from '@salesforce/apex/ShipmentTrackingController.reschedule';
import { countValues, errorMessage, formatIsoDate, sortResults, statusClass } from './utils';

const MAX_VALUES = 10;

export default class RutaCargoTracker extends LightningElement {
    mode = 'trackingNumber';
    rawValues = '';
    searching = false;
    searchError;
    results;
    sortBy = 'input';

    // Detalle de entrega (REQ-002 / REQ-003)
    openKey; // fila donde el destinatario está capturando su código postal
    postalCode = '';
    verifying = false;
    verifyError;
    detail;
    verifiedPostalCode;
    proofLoading = false;
    proofError;
    newDate;
    newInstructions;
    saving = false;
    rescheduleError;
    rescheduleSuccess;

    // ------------------------------------------------------------- getters

    get modeOptions() {
        return [
            { label: 'Número de guía', value: 'trackingNumber' },
            { label: 'Referencia del pedido', value: 'reference' }
        ];
    }

    get sortOptions() {
        return [
            { label: 'Como los escribí', value: 'input' },
            { label: 'Estado', value: 'status' },
            { label: 'Fecha estimada de entrega', value: 'date' }
        ];
    }

    get inputLabel() {
        return this.mode === 'trackingNumber' ? 'Números de guía' : 'Referencias del pedido';
    }

    get placeholder() {
        return this.mode === 'trackingNumber' ? 'RC000001042, RC000001043' : 'PED-2026-0001';
    }

    get valueCount() {
        return countValues(this.rawValues);
    }

    get counterText() {
        return `${this.valueCount} de ${MAX_VALUES}`;
    }

    get counterClass() {
        return this.valueCount > MAX_VALUES ? 'counter counter_over' : 'counter';
    }

    get searchDisabled() {
        return this.searching || this.valueCount === 0 || this.valueCount > MAX_VALUES;
    }

    get showSearch() {
        return !this.detail;
    }

    get hasResults() {
        return Array.isArray(this.results) && this.results.length > 0;
    }

    get resultSummary() {
        if (!this.hasResults) {
            return '';
        }
        const found = this.results.filter((r) => r.found).length;
        return found === 1 ? '1 envío encontrado' : `${found} envíos encontrados`;
    }

    get viewResults() {
        if (!this.hasResults) {
            return [];
        }
        return sortResults(this.results, this.sortBy).map((r) => ({
            ...r,
            statusClass: statusClass(r.status),
            estimatedLabel: formatIsoDate(r.estimatedDelivery),
            lastUpdateLabel: r.lastUpdate || '—',
            isOpen: r.key === this.openKey
        }));
    }

    get detailEstimatedLabel() {
        return this.detail ? formatIsoDate(this.detail.estimatedDelivery) : '';
    }

    get detailStatusClass() {
        return this.detail ? statusClass(this.detail.status) : '';
    }

    get rescheduleRangeText() {
        if (!this.detail || !this.detail.canReschedule) {
            return '';
        }
        return `Elige una fecha entre ${formatIsoDate(this.detail.minRescheduleDate)} y ${formatIsoDate(
            this.detail.maxRescheduleDate
        )}. Te quedan ${this.detail.reschedulesLeft} cambio(s).`;
    }

    get saveDisabled() {
        return this.saving || !this.newDate;
    }

    // ------------------------------------------------------------- búsqueda (REQ-001)

    handleModeChange(event) {
        this.mode = event.detail.value;
        this.results = undefined;
        this.searchError = undefined;
    }

    handleValuesChange(event) {
        this.rawValues = event.detail.value;
    }

    handleSortChange(event) {
        this.sortBy = event.detail.value;
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && (event.metaKey || event.ctrlKey) && !this.searchDisabled) {
            this.handleSearch();
        }
    }

    async handleSearch() {
        this.searching = true;
        this.searchError = undefined;
        this.closeVerification();
        try {
            this.results = await trackShipments({ mode: this.mode, rawValues: this.rawValues });
        } catch (e) {
            this.results = undefined;
            this.searchError = errorMessage(e);
        } finally {
            this.searching = false;
        }
    }

    // ------------------------------------------------------------- detalle (REQ-002)

    handleOpenVerification(event) {
        this.openKey = event.currentTarget.dataset.key;
        this.postalCode = '';
        this.verifyError = undefined;
    }

    handleCancelVerification() {
        this.closeVerification();
    }

    closeVerification() {
        this.openKey = undefined;
        this.postalCode = '';
        this.verifyError = undefined;
    }

    handlePostalCodeChange(event) {
        this.postalCode = event.detail.value;
    }

    async handleVerify(event) {
        event.preventDefault();
        const trackingNumber = event.currentTarget.dataset.tracking;
        if (!this.postalCode || !this.postalCode.trim()) {
            this.verifyError = 'Escribe el código postal de destino.';
            return;
        }
        this.verifying = true;
        this.verifyError = undefined;
        try {
            const detail = await getDeliveryDetail({ trackingNumber, postalCode: this.postalCode });
            this.verifiedPostalCode = this.postalCode;
            this.showDetail(detail);
            this.closeVerification();
        } catch (e) {
            this.verifyError = errorMessage(e);
        } finally {
            this.verifying = false;
        }
    }

    showDetail(detail) {
        this.detail = detail;
        this.newDate = undefined;
        this.newInstructions = detail.deliveryInstructions || '';
        this.proofError = undefined;
        this.rescheduleError = undefined;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => window.scrollTo({ top: 0, behavior: 'smooth' }));
    }

    handleBack() {
        this.detail = undefined;
        this.verifiedPostalCode = undefined;
        this.rescheduleSuccess = undefined;
        // Refresca la lista para reflejar una posible reprogramación.
        if (this.hasResults) {
            this.handleSearch();
        }
    }

    async handleDownloadProof() {
        this.proofLoading = true;
        this.proofError = undefined;
        try {
            const proof = await getProof({
                trackingNumber: this.detail.trackingNumber,
                postalCode: this.verifiedPostalCode
            });
            this.downloadPdf(proof);
        } catch (e) {
            this.proofError = errorMessage(e);
        } finally {
            this.proofLoading = false;
        }
    }

    downloadPdf(proof) {
        const bytes = atob(proof.pdfBase64);
        const buffer = new Uint8Array(bytes.length);
        for (let i = 0; i < bytes.length; i++) {
            buffer[i] = bytes.charCodeAt(i);
        }
        const url = URL.createObjectURL(new Blob([buffer], { type: proof.contentType || 'application/pdf' }));
        const link = document.createElement('a');
        link.href = url;
        link.download = proof.fileName || `comprobante-${this.detail.trackingNumber}.pdf`;
        link.rel = 'noopener';
        this.template.querySelector('.download-anchor').appendChild(link);
        link.click();
        link.remove();
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => URL.revokeObjectURL(url), 10000);
    }

    // ------------------------------------------------------------- reprogramar (REQ-003)

    handleDateChange(event) {
        this.newDate = event.detail.value;
        this.rescheduleError = undefined;
    }

    handleInstructionsChange(event) {
        this.newInstructions = event.detail.value;
    }

    async handleReschedule(event) {
        event.preventDefault();
        const dateInput = this.template.querySelector('lightning-input[data-id="newDate"]');
        if (dateInput && !dateInput.reportValidity()) {
            return;
        }
        this.saving = true;
        this.rescheduleError = undefined;
        this.rescheduleSuccess = undefined;
        try {
            const updated = await reschedule({
                trackingNumber: this.detail.trackingNumber,
                postalCode: this.verifiedPostalCode,
                newDate: this.newDate,
                instructions: this.newInstructions
            });
            this.showDetail(updated);
            this.rescheduleSuccess = `Listo. Tu nueva fecha de entrega es ${formatIsoDate(updated.estimatedDelivery)}.`;
        } catch (e) {
            this.rescheduleError = errorMessage(e);
        } finally {
            this.saving = false;
        }
    }
}
