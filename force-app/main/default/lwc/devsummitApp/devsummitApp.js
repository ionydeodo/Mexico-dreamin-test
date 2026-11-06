import { LightningElement } from 'lwc';
import getTracks from '@salesforce/apex/PublicSiteController.getTracks';
import searchSessions from '@salesforce/apex/PublicSiteController.searchSessions';
import { reduceError } from 'c/dsUtils';

const SEARCH_DELAY_MS = 300;
const ALL_TRACKS = '';

/**
 * Sitio público de inscripción a talleres (HU-01, HU-02, HU-03).
 */
export default class DevsummitApp extends LightningElement {
    activeTab = 'catalog';
    searchTerm = '';
    selectedTrack = ALL_TRACKS;
    tracks = [];
    sessions = [];
    loading = true;
    loaded = false;
    error;
    selectedSession;

    searchTimer;
    requestId = 0;

    connectedCallback() {
        this.loadTracks();
        this.loadSessions();
    }

    disconnectedCallback() {
        clearTimeout(this.searchTimer);
    }

    async loadTracks() {
        try {
            this.tracks = await getTracks();
        } catch (e) {
            // Sin tracks, la búsqueda sigue funcionando con "Todos".
            this.tracks = [];
        }
    }

    loadSessions = async () => {
        const requestId = ++this.requestId;
        this.loading = true;
        this.error = undefined;
        try {
            const result = await searchSessions({
                searchTerm: this.searchTerm,
                track: this.selectedTrack
            });
            // Ignora respuestas viejas si el usuario siguió escribiendo.
            if (requestId === this.requestId) {
                this.sessions = result || [];
            }
        } catch (e) {
            if (requestId === this.requestId) {
                this.sessions = [];
                this.error = reduceError(e);
            }
        } finally {
            if (requestId === this.requestId) {
                this.loading = false;
                this.loaded = true;
            }
        }
    };

    // ------------------------------------------------------------ getters

    get isCatalogSelected() {
        return this.activeTab === 'catalog';
    }

    get isMineSelected() {
        return this.activeTab === 'mine';
    }

    get catalogTabClass() {
        return this.isCatalogSelected ? 'ds-tab ds-tab_active' : 'ds-tab';
    }

    get mineTabClass() {
        return this.isMineSelected ? 'ds-tab ds-tab_active' : 'ds-tab';
    }

    get trackChips() {
        const options = [{ value: ALL_TRACKS, label: 'Todos' }, ...this.tracks];
        return options.map((t) => {
            const pressed = t.value === this.selectedTrack;
            return {
                value: t.value,
                label: t.label,
                pressed: pressed ? 'true' : 'false',
                cssClass: pressed ? 'ds-chip ds-chip_active' : 'ds-chip'
            };
        });
    }

    get hasSessions() {
        return this.sessions.length > 0;
    }

    get showEmpty() {
        return this.loaded && !this.error && this.sessions.length === 0;
    }

    get statusText() {
        if (this.loading || this.error) {
            return '';
        }
        const n = this.sessions.length;
        return n === 1 ? '1 sesión' : `${n} sesiones`;
    }

    // ------------------------------------------------------------ handlers

    handleTab(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        if (this.isCatalogSelected) {
            this.loadSessions();
        }
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this.searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = setTimeout(this.loadSessions, SEARCH_DELAY_MS);
    }

    handleTrack(event) {
        this.selectedTrack = event.currentTarget.dataset.value;
        this.loadSessions();
    }

    clearFilters() {
        this.searchTerm = '';
        this.selectedTrack = ALL_TRACKS;
        this.loadSessions();
    }

    handleRegister(event) {
        const id = event.detail.sessionId;
        this.selectedSession = this.sessions.find((s) => s.id === id);
    }

    handleCloseForm() {
        this.selectedSession = undefined;
    }

    /** Tras inscribirse (o si la sesión se llenó mientras tanto) se refrescan los cupos. */
    handleRegistrationChanged() {
        this.loadSessions();
    }
}
