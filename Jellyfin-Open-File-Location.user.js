// ==UserScript==
// @name         Jellyfin - Open file location
// @namespace    local.jellyfin.open-file-location
// @version      0.5.1
// @description  Adds "Open file location" to Jellyfin item menus. Opens in Directory Opus when installed, otherwise Explorer.
// @homepageURL  https://github.com/juliekeygen-netizen/Jellyfin-Open-File-Location-Tampermonkey
// @downloadURL  https://raw.githubusercontent.com/juliekeygen-netizen/Jellyfin-Open-File-Location-Tampermonkey/main/Jellyfin-Open-File-Location.user.js
// @updateURL    https://raw.githubusercontent.com/juliekeygen-netizen/Jellyfin-Open-File-Location-Tampermonkey/main/Jellyfin-Open-File-Location.user.js
// @match        http://*/web/*
// @match        https://*/web/*
// @match        http://*/*/web/*
// @match        https://*/*/web/*
// @grant        none
// @sandbox      raw
// @run-at       document-start
// ==/UserScript==

(() => {
    'use strict';

    const VERSION = '0.5.1';

    // =====================================================================
    // EASY CONFIG
    // =====================================================================
    const CONFIG = {
        /*
         * MENU POSITION
         * -------------
         * 'last' = put "Open file location" after the final visible menu item.
         *
         * Or use a 1-based number:
         *   1 = first clickable Jellyfin item
         *   2 = second
         *   6 = sixth
         *
         * Divider lines are NOT counted.
         */
        menuPosition: 'last',

        /*
         * FILE MANAGER
         * ------------
         * 'auto'     = Directory Opus when installed; Explorer otherwise.
         * 'dopus'    = require Directory Opus.
         * 'explorer' = always use Windows Explorer.
         */
        fileManager: 'auto',

        /*
         * HELPER MODE
         * -----------
         * 'vbs'              = DEFAULT. Invisible; no terminal window.
         * 'powershell'       = hidden PowerShell.
         * 'powershell-debug' = visible PowerShell which stays open.
         */
        helperMode: 'vbs',

        /*
         * PROTOCOL LAUNCH
         * ---------------
         * 'iframe'   = DEFAULT. Keeps Jellyfin's top-level URL untouched.
         * 'location' = fallback only if your browser refuses iframe launching.
         */
        protocolLaunch: 'iframe',

        /*
         * CLOSE JELLYFIN MENU AFTER OPENING
         * ---------------------------------
         * false = DEFAULT / safest.
         *
         * v0.5 deliberately leaves the Jellyfin three-dot menu open after
         * launching Directory Opus / Explorer. This removes the last synthetic
         * Jellyfin event from the normal workflow.
         *
         * Click outside the menu when you return to Jellyfin.
         *
         * true = use Jellyfin's background-click close behavior automatically.
         */
        closeMenuAfterOpen: false,

        /*
         * DEBUG LOG
         */
        debugLog: false
    };
    // =====================================================================
    // END EASY CONFIG
    // =====================================================================

    const ID_RE = /^[0-9a-f]{32}$/i;
    const CONTEXT_TTL_MS = 5000;
    const GLOBAL_INSTANCE_KEY = '__JFOL_OPEN_FILE_LOCATION_INSTANCE__';
    const STYLE_ID = 'jfol-styles-v051';

    let lastMenuItemId = null;
    let lastMenuTriggerTime = 0;
    let observer = null;

    const documentListeners = [];

    const ITEM_MENU_COMMAND_IDS = new Set([
        'addtocollection',
        'addtoplaylist',
        'download',
        'copy-stream',
        'delete',
        'edit',
        'editimages',
        'editsubtitles',
        'identify',
        'moremediainfo',
        'refresh',
        'share',
        'album',
        'artist'
    ]);

    function log(...args) {
        if (CONFIG.debugLog) {
            console.log(`[JFOL ${VERSION}]`, ...args);
        }
    }

    function installStyles() {
        if (document.getElementById(STYLE_ID)) return;

        const style = document.createElement('style');
        style.id = STYLE_ID;
        style.textContent = `
            /*
             * Intentionally NOT:
             *   .actionSheetMenuItem
             *   .itemAction
             *   emby-button
             *   a native <button>
             */
            .jfol-menu-row {
                display: flex;
                align-items: center;
                width: 100%;
                box-sizing: border-box;
                flex-shrink: 0;
                border: 0;
                border-radius: 0;
                margin: 0;
                padding: 0;
                background: transparent;
                color: inherit;
                font: inherit;
                text-align: left;
                cursor: pointer;
                outline: none;
                min-height: 2.75em;
                user-select: none;
                -webkit-tap-highlight-color: transparent;
            }

            .jfol-menu-row:hover,
            .jfol-menu-row:focus-visible {
                background: rgba(255, 255, 255, 0.06);
            }

            .jfol-menu-row[aria-disabled="true"] {
                cursor: default;
                opacity: 0.55;
            }

            .jfol-menu-row .jfol-icon {
                padding: 0 !important;
                margin: 0 0.85em 0 0.45em !important;
                flex-shrink: 0;
            }

            [dir="rtl"] .jfol-menu-row .jfol-icon {
                margin: 0 0.45em 0 0.85em !important;
            }

            .jfol-menu-row .jfol-body {
                padding: 0.4em 1em 0.4em 0.6em !important;
                flex: 1 1 auto;
                min-width: 0;
            }

            [dir="rtl"] .jfol-menu-row .jfol-body {
                padding: 0.4em 0.6em 0.4em 1em !important;
            }

            .jfol-menu-row .jfol-text {
                white-space: nowrap;
                overflow: hidden;
                text-overflow: ellipsis;
                display: flex;
                justify-content: flex-start;
            }
        `;

        (document.head || document.documentElement).appendChild(style);
    }

    function removeOldArtifacts() {
        document.querySelectorAll('[data-jfol-button="1"]').forEach(node => node.remove());

        for (const style of document.querySelectorAll('[id^="jfol-styles"]')) {
            if (style.id !== STYLE_ID) style.remove();
        }

        document.querySelectorAll('.actionSheet[data-jfol-checked]').forEach(dialog => {
            dialog.removeAttribute('data-jfol-checked');
        });
    }

    function addManagedDocumentListener(type, listener, options = false) {
        document.addEventListener(type, listener, options);
        documentListeners.push([type, listener, options]);
    }

    function destroy() {
        log('destroy');

        if (observer) {
            observer.disconnect();
            observer = null;
        }

        for (const [type, listener, options] of documentListeners.splice(0)) {
            document.removeEventListener(type, listener, options);
        }

        document.querySelectorAll('[data-jfol-button="1"]').forEach(node => node.remove());

        const style = document.getElementById(STYLE_ID);
        if (style) style.remove();

        document.querySelectorAll('.actionSheet[data-jfol-checked]').forEach(dialog => {
            dialog.removeAttribute('data-jfol-checked');
        });
    }

    function getUrlItemId() {
        try {
            const url = new URL(window.location.href);
            const normalId = url.searchParams.get('id');

            if (normalId && ID_RE.test(normalId)) return normalId;

            const hash = window.location.hash || '';
            const q = hash.indexOf('?');

            if (q !== -1) {
                const params = new URLSearchParams(hash.slice(q + 1));
                const hashId = params.get('id');

                if (hashId && ID_RE.test(hashId)) return hashId;
            }

            const match = window.location.href.match(
                /[?&#]id=([0-9a-f]{32})(?:[&#]|$)/i
            );

            return match ? match[1] : null;
        } catch {
            return null;
        }
    }

    function findItemIdFromElement(element) {
        let el = element instanceof Element ? element : null;

        for (let i = 0; el && i < 12; i++, el = el.parentElement) {
            const candidates = [
                el.getAttribute('data-itemid'),
                el.getAttribute('data-item-id'),
                el.getAttribute('data-id')
            ];

            for (const value of candidates) {
                if (value && ID_RE.test(value)) return value;
            }
        }

        return null;
    }

    function looksLikeMenuTrigger(target) {
        if (!(target instanceof Element)) return false;

        return !!target.closest(
            '.btnMore, .btnCardOptions, [data-action="menu"], [data-action="Menu"], [title="More"]'
        );
    }

    function rememberMenuItem(target) {
        if (!looksLikeMenuTrigger(target)) return;

        const id = findItemIdFromElement(target) || getUrlItemId();

        if (id) {
            lastMenuItemId = id;
            lastMenuTriggerTime = Date.now();
            log('menu item', id);
        }
    }

    function isLikelyItemContextMenu(dialog) {
        const ids = [...dialog.querySelectorAll('.actionSheetMenuItem[data-id]')]
            .map(el => el.getAttribute('data-id'));

        let matches = 0;

        for (const id of ids) {
            if (ITEM_MENU_COMMAND_IDS.has(id)) matches++;
        }

        return matches >= 1 &&
            (Date.now() - lastMenuTriggerTime) <= CONTEXT_TTL_MS;
    }

    function getActiveItemId() {
        if (
            lastMenuItemId &&
            (Date.now() - lastMenuTriggerTime) <= CONTEXT_TTL_MS
        ) {
            return lastMenuItemId;
        }

        return getUrlItemId();
    }

    async function fetchItemPath(itemId) {
        /*
         * @sandbox raw means this script runs in the actual Jellyfin page world.
         * We therefore use Jellyfin's exact window.ApiClient directly.
         */
        const apiClient = window.ApiClient;

        if (!apiClient || typeof apiClient.getItem !== 'function') {
            throw new Error('Jellyfin ApiClient is not available.');
        }

        const userId = typeof apiClient.getCurrentUserId === 'function'
            ? apiClient.getCurrentUserId()
            : null;

        if (!userId) {
            throw new Error('Could not determine the current Jellyfin user.');
        }

        const item = await apiClient.getItem(userId, itemId);

        const path =
            item?.Path ||
            item?.MediaSources?.find(source => source?.Path)?.Path ||
            null;

        if (!path) {
            throw new Error('This Jellyfin item does not expose a filesystem path.');
        }

        return path;
    }

    function utf8ToBase64Url(text) {
        const bytes = new TextEncoder().encode(text);
        let binary = '';

        for (let i = 0; i < bytes.length; i += 0x8000) {
            const chunk = bytes.subarray(i, Math.min(i + 0x8000, bytes.length));
            binary += String.fromCharCode(...chunk);
        }

        return btoa(binary)
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=+$/g, '');
    }

    function getProtocolForMode() {
        if (CONFIG.helperMode === 'powershell') return 'jellyopen-ps';
        if (CONFIG.helperMode === 'powershell-debug') return 'jellyopen-psdebug';
        return 'jellyopen-vbs';
    }

    function getFileManagerMode() {
        const value = String(CONFIG.fileManager || 'auto').toLowerCase();

        return ['auto', 'dopus', 'explorer'].includes(value)
            ? value
            : 'auto';
    }

    function buildProtocolUri(path) {
        return `${getProtocolForMode()}://open?data=${utf8ToBase64Url(path)}&fm=${getFileManagerMode()}`;
    }

    function launchViaHiddenIframe(uri) {
        const iframe = document.createElement('iframe');

        iframe.setAttribute('aria-hidden', 'true');
        iframe.tabIndex = -1;
        iframe.style.cssText = [
            'position:fixed',
            'width:1px',
            'height:1px',
            'left:-10000px',
            'top:-10000px',
            'opacity:0',
            'pointer-events:none',
            'border:0'
        ].join(';');

        document.documentElement.appendChild(iframe);
        iframe.src = uri;

        window.setTimeout(() => iframe.remove(), 5000);
    }

    function launchPath(path) {
        const uri = buildProtocolUri(path);

        log('launch', path, CONFIG.fileManager);

        if (CONFIG.protocolLaunch === 'location') {
            window.location.href = uri;
        } else {
            launchViaHiddenIframe(uri);
        }
    }

    function closeThroughJellyfinBackground(row) {
        if (!CONFIG.closeMenuAfterOpen) return;

        const dialog = row.closest('.actionSheet');
        if (!dialog) return;

        const container = dialog.closest('.dialogContainer');
        if (!container) return;

        window.setTimeout(() => {
            if (!container.isConnected || !dialog.isConnected) return;

            container.dispatchEvent(new MouseEvent('mousedown', {
                bubbles: true,
                cancelable: true,
                view: window
            }));

            container.dispatchEvent(new MouseEvent('click', {
                bubbles: true,
                cancelable: true,
                view: window
            }));
        }, 30);
    }

    function makeMenuRow() {
        /*
         * Plain DIV: no Jellyfin/Emby button behavior at all.
         */
        const row = document.createElement('div');

        row.className = 'jfol-menu-row';
        row.setAttribute('data-jfol-button', '1');
        row.setAttribute('data-jfol-version', VERSION);
        row.setAttribute('role', 'button');
        row.setAttribute('tabindex', '0');
        row.setAttribute('aria-disabled', 'true');
        row.title = 'Loading media path…';

        const icon = document.createElement('span');
        icon.className =
            'jfol-icon listItemIcon listItemIcon-transparent material-icons folder_open';
        icon.setAttribute('aria-hidden', 'true');

        const body = document.createElement('div');
        body.className = 'jfol-body';

        const text = document.createElement('div');
        text.className = 'jfol-text';
        text.textContent = 'Open file location';

        body.appendChild(text);
        row.append(icon, body);

        return { row, text };
    }

    function blockEvent(event) {
        event.stopPropagation();
        event.stopImmediatePropagation();
    }

    function activateRow(row, event) {
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();

        if (row.getAttribute('aria-disabled') === 'true') return;

        const path = row.dataset.jfolPath;
        if (!path) return;

        launchPath(path);
        closeThroughJellyfinBackground(row);
    }

    function attachRowEvents(row) {
        for (const eventName of [
            'pointerdown',
            'pointerup',
            'mousedown',
            'mouseup',
            'touchstart',
            'touchend',
            'contextmenu'
        ]) {
            row.addEventListener(eventName, blockEvent, true);
        }

        row.addEventListener('click', event => {
            activateRow(row, event);
        }, true);

        row.addEventListener('keydown', event => {
            if (event.key === 'Enter' || event.key === ' ') {
                activateRow(row, event);
            }
        }, true);
    }

    function insertAtConfiguredPosition(scroller, row) {
        const position = CONFIG.menuPosition;

        if (position === 'last' || position == null) {
            scroller.appendChild(row);
            return;
        }

        const numericPosition = Number(position);

        if (!Number.isInteger(numericPosition) || numericPosition < 1) {
            scroller.appendChild(row);
            return;
        }

        const nativeItems = [
            ...scroller.querySelectorAll('.actionSheetMenuItem')
        ];

        const target = nativeItems[numericPosition - 1];

        if (target) {
            target.before(row);
        } else {
            scroller.appendChild(row);
        }
    }

    function injectIntoActionSheet(dialog) {
        if (!(dialog instanceof Element)) return;

        /*
         * Remove rows from any older JFOL version.
         */
        dialog.querySelectorAll('[data-jfol-button="1"]').forEach(node => {
            if (node.getAttribute('data-jfol-version') !== VERSION) {
                node.remove();
            }
        });

        if (dialog.querySelector(`[data-jfol-version="${VERSION}"]`)) return;
        if (!isLikelyItemContextMenu(dialog)) return;

        const itemId = getActiveItemId();
        if (!itemId) return;

        const scroller = dialog.querySelector('.actionSheetScroller');
        if (!scroller) return;

        const { row, text } = makeMenuRow();

        fetchItemPath(itemId).then(path => {
            row.dataset.jfolPath = path;
            row.setAttribute('aria-disabled', 'false');
            row.title = path;
        }).catch(error => {
            console.warn('[Jellyfin Open File Location]', error);
            text.textContent = 'Open file location (unavailable)';
            row.title = error?.message || String(error);
            row.setAttribute('aria-disabled', 'true');
        });

        attachRowEvents(row);
        insertAtConfiguredPosition(scroller, row);

        log('injected', itemId);
    }

    function scan(root = document) {
        if (root instanceof Element && root.matches('.actionSheet')) {
            injectIntoActionSheet(root);
        }

        root.querySelectorAll?.('.actionSheet').forEach(injectIntoActionSheet);
    }

    function start() {
        /*
         * Raw/page-world singleton. New runs explicitly destroy any previous
         * JFOL instance before installing listeners/observers.
         */
        const previous = window[GLOBAL_INSTANCE_KEY];

        if (previous && typeof previous.destroy === 'function') {
            try {
                previous.destroy();
            } catch (error) {
                console.warn(
                    '[Jellyfin Open File Location] Previous teardown failed:',
                    error
                );
            }
        }

        removeOldArtifacts();
        installStyles();

        window[GLOBAL_INSTANCE_KEY] = {
            version: VERSION,
            destroy
        };

        addManagedDocumentListener(
            'pointerdown',
            event => rememberMenuItem(event.target),
            true
        );

        addManagedDocumentListener(
            'click',
            event => rememberMenuItem(event.target),
            true
        );

        observer = new MutationObserver(mutations => {
            for (const mutation of mutations) {
                for (const node of mutation.addedNodes) {
                    if (!(node instanceof Element)) continue;

                    const parentDialog = node.closest?.('.actionSheet');
                    if (parentDialog) injectIntoActionSheet(parentDialog);

                    scan(node);
                }
            }
        });

        observer.observe(document.documentElement || document, {
            childList: true,
            subtree: true
        });

        scan();

        log('started', CONFIG);
    }

    if (document.documentElement) {
        start();
    } else {
        document.addEventListener('DOMContentLoaded', start, { once: true });
    }
})();
