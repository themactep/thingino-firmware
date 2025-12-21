// i18n Debug Bookmarklet - Inject this into any page to highlight localization status
// Usage: Copy this code and create a bookmark with it as the URL (prefix with javascript:)

(function() {
    // Check if already loaded
    if (document.getElementById('i18nDebugPanel')) {
        document.getElementById('i18nDebugPanel').remove();
        return;
    }

    // Inject CSS
    const style = document.createElement('style');
    style.textContent = `
        .i18n-debug-highlight {
            outline: 2px solid #00ff00 !important;
            background-color: rgba(0, 255, 0, 0.1) !important;
            position: relative !important;
        }

        .i18n-debug-highlight::before {
            content: attr(data-i18n);
            position: absolute;
            top: -20px;
            left: 0;
            background: #00ff00;
            color: #000;
            padding: 2px 4px;
            font-size: 10px;
            font-family: monospace;
            border-radius: 2px;
            z-index: 10000;
            white-space: nowrap;
            max-width: 200px;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .i18n-debug-missing {
            outline: 2px solid #ff0000 !important;
            background-color: rgba(255, 0, 0, 0.1) !important;
            position: relative !important;
        }

        .i18n-debug-missing::after {
            content: "NEEDS i18n";
            position: absolute;
            top: -20px;
            right: 0;
            background: #ff0000;
            color: #fff;
            padding: 2px 4px;
            font-size: 10px;
            font-family: monospace;
            border-radius: 2px;
            z-index: 10000;
        }

        .i18n-debug-missing-translation {
            outline: 2px solid #ff6600 !important;
            background-color: rgba(255, 102, 0, 0.1) !important;
            position: relative !important;
        }

        .i18n-debug-missing-translation::after {
            content: "MISSING TRANSLATION";
            position: absolute;
            top: -20px;
            right: 0;
            background: #ff6600;
            color: #fff;
            padding: 2px 4px;
            font-size: 10px;
            font-family: monospace;
            border-radius: 2px;
            z-index: 10000;
        }

        .i18n-debug-placeholder {
            outline: 2px solid #0066ff !important;
            background-color: rgba(0, 102, 255, 0.1) !important;
        }

        .i18n-debug-title {
            outline: 2px solid #ff6600 !important;
            background-color: rgba(255, 102, 0, 0.1) !important;
        }

        #i18nDebugPanel {
            position: fixed;
            top: 10px;
            right: 10px;
            background: #000;
            color: #fff;
            padding: 15px;
            border-radius: 8px;
            border: 2px solid #333;
            z-index: 99999;
            font-family: monospace;
            font-size: 12px;
            max-width: 300px;
            box-shadow: 0 4px 8px rgba(0,0,0,0.5);
        }

        #i18nDebugPanel h3 {
            margin: 0 0 10px 0;
            color: #00ff00;
            font-size: 14px;
        }

        #i18nDebugPanel button {
            background: #333;
            color: #fff;
            border: 1px solid #666;
            padding: 5px 10px;
            margin: 2px;
            border-radius: 3px;
            cursor: pointer;
            font-size: 11px;
        }

        #i18nDebugPanel button:hover {
            background: #555;
        }

        #i18nDebugPanel button.active {
            background: #00ff00;
            color: #000;
        }

        .debug-stats {
            margin: 10px 0;
            padding: 8px;
            background: #222;
            border-radius: 4px;
        }

        .debug-legend {
            margin: 10px 0;
            font-size: 10px;
        }

        .debug-legend div {
            margin: 2px 0;
            padding: 2px 4px;
            border-radius: 2px;
        }

        .legend-localized { background: rgba(0, 255, 0, 0.3); }
        .legend-missing { background: rgba(255, 0, 0, 0.3); }
        .legend-placeholder { background: rgba(0, 102, 255, 0.3); }
        .legend-title { background: rgba(255, 102, 0, 0.3); }
    `;
    document.head.appendChild(style);

    // Create debug panel
    const panel = document.createElement('div');
    panel.id = 'i18nDebugPanel';
    panel.innerHTML = `
        <h3>🌍 i18n Debug Tool</h3>

        <div>
            <button id="toggleHighlight" onclick="window.i18nDebug.toggleHighlighting()">Enable Highlighting</button>
            <button id="toggleMissing" onclick="window.i18nDebug.toggleMissingDetection()">Find Missing</button>
            <button onclick="window.i18nDebug.exportReport()">Export Report</button>
        </div>

        <div>
            <button onclick="window.i18nDebug.reloadWithDebug()">Reload with Debug</button>
            <button onclick="window.i18nDebug.reloadWithoutDebug()">Clear Debug</button>
        </div>

        <div class="debug-stats" id="debugStats">
            <div>Localized: <span id="localizedCount">0</span></div>
            <div>Missing Translation: <span id="missingTranslationCount">0</span></div>
            <div>Missing i18n: <span id="missingCount">0</span></div>
            <div>Placeholders: <span id="placeholderCount">0</span></div>
            <div>Titles: <span id="titleCount">0</span></div>
        </div>

        <div class="debug-legend">
            <div class="legend-localized">🟢 data-i18n (localized)</div>
            <div class="legend-placeholder">🔵 data-i18n-placeholder</div>
            <div class="legend-title">🟠 data-i18n-title</div>
            <div class="legend-missing">🔴 Needs localization</div>
        </div>

        <div>
            <button onclick="window.i18nDebug.scrollToNext('localized')">Next Localized</button>
            <button onclick="window.i18nDebug.scrollToNext('missing')">Next Missing</button>
            <button onclick="document.getElementById('i18nDebugPanel').remove()">Close</button>
        </div>
    `;
    document.body.appendChild(panel);

    // Debug functionality
    window.i18nDebug = {
        highlightingEnabled: false,
        missingDetectionEnabled: false,
        currentScrollIndex: { localized: 0, missing: 0 },

        toggleHighlighting() {
            this.highlightingEnabled = !this.highlightingEnabled;
            const button = document.getElementById('toggleHighlight');

            if (this.highlightingEnabled) {
                button.textContent = 'Disable Highlighting';
                button.classList.add('active');
                this.highlightLocalizedElements();
            } else {
                button.textContent = 'Enable Highlighting';
                button.classList.remove('active');
                this.removeHighlighting();
            }

            this.updateStats();
        },

        toggleMissingDetection() {
            this.missingDetectionEnabled = !this.missingDetectionEnabled;
            const button = document.getElementById('toggleMissing');

            if (this.missingDetectionEnabled) {
                button.textContent = 'Hide Missing';
                button.classList.add('active');
                this.highlightMissingElements();
            } else {
                button.textContent = 'Find Missing';
                button.classList.remove('active');
                this.removeMissingHighlighting();
            }

            this.updateStats();
        },

        highlightLocalizedElements() {
            document.querySelectorAll('[data-i18n]').forEach(el => {
                el.classList.add('i18n-debug-highlight');
            });

            document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
                el.classList.add('i18n-debug-placeholder');
            });

            document.querySelectorAll('[data-i18n-title]').forEach(el => {
                el.classList.add('i18n-debug-title');
            });
        },

        highlightMissingElements() {
            // Method 1: Find elements with data-i18n but no i18n-translated class (missing translations)
            const missingTranslations = document.querySelectorAll('[data-i18n]:not(.i18n-translated), [data-i18n-placeholder]:not(.i18n-translated), [data-i18n-title]:not(.i18n-translated)');
            missingTranslations.forEach(el => {
                if (!el.closest('#i18nDebugPanel')) {
                    el.classList.add('i18n-debug-missing-translation');
                }
            });

            // Method 2: Find elements that might need localization but don't have data-i18n
            const potentialElements = document.querySelectorAll(`
                h1, h2, h3, h4, h5, h6,
                label:not([data-i18n]):not([data-i18n-placeholder]):not([data-i18n-title]),
                button:not([data-i18n]):not([data-i18n-placeholder]):not([data-i18n-title]),
                .btn:not([data-i18n]):not([data-i18n-placeholder]):not([data-i18n-title]),
                .form-label:not([data-i18n]),
                .form-text:not([data-i18n]),
                .card-title:not([data-i18n]),
                .nav-link:not([data-i18n]),
                .dropdown-item:not([data-i18n]),
                .alert:not([data-i18n]),
                th:not([data-i18n]),
                .badge:not([data-i18n])
            `);

            potentialElements.forEach(el => {
                if (el.closest('#i18nDebugPanel')) return;

                const text = el.textContent.trim();
                if (!text || text.length < 2 || /^[^\w\s]*$/.test(text)) return;
                if (/^\d+$/.test(text) || /^[0-9\.\-\+\%\$\€\£\¥]+$/.test(text)) return;
                if (text.match(/^(OK|404|500|200|GET|POST|PUT|DELETE|API|JSON|XML|HTML|CSS|JS)$/i)) return;
                if (text.startsWith('{{') || text.startsWith('${') || text.includes('()')) return;

                el.classList.add('i18n-debug-missing');
            });
        },

        removeHighlighting() {
            document.querySelectorAll('.i18n-debug-highlight, .i18n-debug-placeholder, .i18n-debug-title').forEach(el => {
                el.classList.remove('i18n-debug-highlight', 'i18n-debug-placeholder', 'i18n-debug-title');
            });
        },

        removeMissingHighlighting() {
            document.querySelectorAll('.i18n-debug-missing').forEach(el => {
                el.classList.remove('i18n-debug-missing');
            });
        },

        updateStats() {
            const localizedCount = document.querySelectorAll('.i18n-translated').length;
            const placeholderCount = document.querySelectorAll('[data-i18n-placeholder]').length;
            const titleCount = document.querySelectorAll('[data-i18n-title]').length;
            const missingTranslationCount = document.querySelectorAll('.i18n-debug-missing-translation').length;
            const missingCount = document.querySelectorAll('.i18n-debug-missing').length;

            document.getElementById('localizedCount').textContent = localizedCount;
            document.getElementById('placeholderCount').textContent = placeholderCount;
            document.getElementById('titleCount').textContent = titleCount;
            document.getElementById('missingTranslationCount').textContent = missingTranslationCount;
            document.getElementById('missingCount').textContent = missingCount;
        },

        scrollToNext(type) {
            let elements;

            if (type === 'localized') {
                elements = document.querySelectorAll('[data-i18n], [data-i18n-placeholder], [data-i18n-title]');
            } else if (type === 'missing') {
                elements = document.querySelectorAll('.i18n-debug-missing');
            }

            if (elements.length === 0) return;

            const currentIndex = this.currentScrollIndex[type];
            const element = elements[currentIndex];

            if (element) {
                element.scrollIntoView({ behavior: 'smooth', block: 'center' });

                const originalOutline = element.style.outline;
                element.style.outline = '4px solid #ffff00';
                setTimeout(() => {
                    element.style.outline = originalOutline;
                }, 2000);
            }

            this.currentScrollIndex[type] = (currentIndex + 1) % elements.length;
        },

        exportReport() {
            const localized = Array.from(document.querySelectorAll('[data-i18n]')).map(el => ({
                tag: el.tagName.toLowerCase(),
                key: el.getAttribute('data-i18n'),
                text: el.textContent.trim().substring(0, 50)
            }));

            const missing = Array.from(document.querySelectorAll('.i18n-debug-missing')).map(el => ({
                tag: el.tagName.toLowerCase(),
                text: el.textContent.trim().substring(0, 50)
            }));

            const report = {
                timestamp: new Date().toISOString(),
                url: window.location.href,
                stats: {
                    localized: localized.length,
                    missing: missing.length,
                    placeholders: document.querySelectorAll('[data-i18n-placeholder]').length,
                    titles: document.querySelectorAll('[data-i18n-title]').length
                },
                localized,
                missing
            };

            console.log('i18n Debug Report:', report);
            alert(`i18n Report generated! Check console for details.\n\nStats:\n- Localized: ${report.stats.localized}\n- Missing: ${report.stats.missing}\n- Placeholders: ${report.stats.placeholders}\n- Titles: ${report.stats.titles}`);
        },

        reloadWithDebug() {
            const url = new URL(window.location);

            // Add or update the debug_i18n parameter
            url.searchParams.set('debug_i18n', '1');

            // Reload the page with the debug parameter
            window.location.href = url.toString();
        },

        reloadWithoutDebug() {
            const url = new URL(window.location);

            // Remove the debug_i18n parameter
            url.searchParams.delete('debug_i18n');

            // Reload the page without the debug parameter
            window.location.href = url.toString();
        }
    };

    // Initialize
    window.i18nDebug.updateStats();

    console.log('🌍 i18n Debug Tool loaded! Use the panel in the top-right corner.');
})();
