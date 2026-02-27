/**
 * Thingino Web UI Simple Localization
 * Simple i18n system: one language file or hardcoded English
 * No real-time switching - language changes require page reload
 */

class ThinginoI18n {
    constructor() {
        this.currentLang = 'en';
        this.translations = null;  // Single translation object or null
        this.initialized = false;
    }

    /**
     * Initialize the localization system
     */
    async init() {
        try {
            // Get current language from server
            const response = await fetch('/lua/api/language/list');
            const data = await response.json();

            if (data.success) {
                this.currentLang = data.current || 'en';
                this.availableLanguages = data.available || ['en'];
                this.languageNames = data.names || {};
            }

            // Only load language pack if not English
            if (this.currentLang !== 'en') {
                await this.loadLanguagePack();
            }

            this.initialized = true;

            // Translate the page after a short delay to ensure DOM is ready
            setTimeout(() => {
                this.translatePage();
                // Show content after translation is complete
                document.body.classList.remove('i18n-loading');
                document.body.classList.add('i18n-ready');
            }, 100);
        } catch (error) {
            console.error('Failed to initialize i18n:', error);
            this.initialized = true; // Continue without translations
            // Show content even if i18n fails
            document.body.classList.remove('i18n-loading');
            document.body.classList.add('i18n-ready');
        }
    }

    /**
     * Load the single language pack from the server
     */
    async loadLanguagePack() {
        try {
            const response = await fetch('/lua/api/language/pack');
            if (response.ok) {
                const translations = await response.json();
                this.translations = translations;
                console.log('Loaded language pack');
            } else {
                console.warn('Language pack not found');
            }
        } catch (error) {
            console.error('Failed to load language pack:', error);
        }
    }

    /**
     * Get translation for a key
     */
    t(key, vars = {}) {
        if (!this.initialized) {
            return key; // Return key if not initialized
        }

        // If no translations loaded (English), return key as-is
        if (!this.translations) {
            let text = key;

            // Variable substitution for English
            if (vars && typeof vars === 'object') {
                for (const [varKey, varValue] of Object.entries(vars)) {
                    text = text.replace(new RegExp(`{{${varKey}}}`, 'g'), varValue);
                }
            }

            return text;
        }

        // Get translation or fallback to key
        let text = this.translations[key] || key;

        // Variable substitution
        if (vars && typeof vars === 'object') {
            for (const [varKey, varValue] of Object.entries(vars)) {
                text = text.replace(new RegExp(`{{${varKey}}}`, 'g'), varValue);
            }
        }

        return text;
    }

    /**
     * Translate all elements on the page
     */
    translatePage() {
        if (!this.initialized) {
            return; // Don't translate if not initialized
        }

        // For English (no translations), don't process translation attributes
        if (!this.translations) {
            return; // Leave original HTML content as-is
        }

        // Translate elements with data-i18n attribute
        document.querySelectorAll('[data-i18n]').forEach(element => {
            const key = element.getAttribute('data-i18n');
            const vars = this.parseDataVars(element.getAttribute('data-i18n-vars'));
            element.textContent = this.t(key, vars);
            // Add class to mark as successfully translated
            element.classList.add('i18n-translated');
        });

        // Translate elements with data-i18n-html attribute (for HTML content)
        document.querySelectorAll('[data-i18n-html]').forEach(element => {
            const key = element.getAttribute('data-i18n-html');
            const vars = this.parseDataVars(element.getAttribute('data-i18n-vars'));
            element.innerHTML = this.t(key, vars);
            // Add class to mark as successfully translated
            element.classList.add('i18n-translated');
        });

        // Translate placeholder attributes
        document.querySelectorAll('[data-i18n-placeholder]').forEach(element => {
            const key = element.getAttribute('data-i18n-placeholder');
            element.placeholder = this.t(key);
            // Add class to mark as successfully translated
            element.classList.add('i18n-translated');
        });

        // Translate title attributes
        document.querySelectorAll('[data-i18n-title]').forEach(element => {
            const key = element.getAttribute('data-i18n-title');
            element.title = this.t(key);
            // Add class to mark as successfully translated
            element.classList.add('i18n-translated');
        });

        // Process {{t:key}} patterns in text content
        this.processInlineTranslations();
    }

    /**
     * Process inline {{t:key}} patterns in the DOM
     * Converts them to spans with data-i18n attributes for dynamic language switching
     */
    processInlineTranslations() {
        if (!this.initialized || !this.translations) {
            return; // Skip processing for English (no translations)
        }

        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            node => {
                // Only process text nodes that contain translation patterns
                return node.textContent.includes('{{t:') ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            },
            false
        );

        const textNodes = [];
        let node;
        while (node = walker.nextNode()) {
            textNodes.push(node);
        }

        textNodes.forEach(textNode => {
            let content = textNode.textContent;
            let hasChanges = false;

            // Replace {{t:key:var1=value1,var2=value2}} patterns with spans
            content = content.replace(/\{\{t:([^:}]+):([^}]+)\}\}/g, (match, key, varsStr) => {
                const vars = {};
                varsStr.split(',').forEach(pair => {
                    const [varKey, varValue] = pair.split('=');
                    if (varKey && varValue) {
                        vars[varKey.trim()] = varValue.trim();
                    }
                });
                hasChanges = true;
                const spanId = 'i18n-' + Math.random().toString(36).substr(2, 9);
                const varsAttr = Object.keys(vars).length > 0 ? ` data-i18n-vars='${JSON.stringify(vars)}'` : '';
                return `<span id="${spanId}" data-i18n="${key.trim()}" class="i18n-translated"${varsAttr}>${this.t(key.trim(), vars)}</span>`;
            });

            // Replace simple {{t:key}} patterns with spans
            content = content.replace(/\{\{t:([^:}]+)\}\}/g, (match, key) => {
                hasChanges = true;
                const spanId = 'i18n-' + Math.random().toString(36).substr(2, 9);
                return `<span id="${spanId}" data-i18n="${key.trim()}" class="i18n-translated">${this.t(key.trim())}</span>`;
            });

            if (hasChanges) {
                // Replace the text node with HTML content
                const tempDiv = document.createElement('div');
                tempDiv.innerHTML = content;

                // Replace the text node with the new content
                const parent = textNode.parentNode;
                while (tempDiv.firstChild) {
                    parent.insertBefore(tempDiv.firstChild, textNode);
                }
                parent.removeChild(textNode);
            }
        });
    }

    /**
     * Parse data-i18n-vars attribute
     */
    parseDataVars(varsStr) {
        if (!varsStr) return {};

        try {
            // Handle JSON format first
            if (varsStr.startsWith('{')) {
                return JSON.parse(varsStr);
            }

            // Handle key=value,key2=value2 format
            const vars = {};
            varsStr.split(',').forEach(pair => {
                const [key, value] = pair.split('=');
                if (key && value) {
                    vars[key.trim()] = value.trim();
                }
            });
            return vars;
        } catch (e) {
            console.warn('Failed to parse i18n vars:', varsStr);
            return {};
        }
    }

    /**
     * Get current language info (for settings page)
     */
    async getLanguageInfo() {
        try {
            const response = await fetch('/lua/api/language/list');
            const data = await response.json();
            return data;
        } catch (error) {
            console.error('Error getting language info:', error);
            return null;
        }
    }

    /**
     * Get available languages
     */
    getAvailableLanguages() {
        return this.availableLanguages || ['en'];
    }

    /**
     * Get language display names
     */
    getLanguageNames() {
        return this.languageNames || { en: 'English' };
    }

    /**
     * Get current language
     */
    getCurrentLanguage() {
        return this.currentLang;
    }

    /**
     * Force retranslation of the page (useful for debugging)
     */
    retranslate() {
        this.translatePage();
    }

    /**
     * Switch to a different language
     */
    async switchLanguage(lang) {
        try {
            const response = await fetch('/lua/api/language/set', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: `lang=${encodeURIComponent(lang)}`
            });

            const data = await response.json();

            if (data.success) {
                // Show success message with proper language name
                alert(data.message || `Language switched to ${lang}`);
                return true;
            } else {
                // Show error message
                alert(data.error || 'Failed to switch language');
                return false;
            }
        } catch (error) {
            console.error('Error switching language:', error);
            alert('Failed to switch language');
            return false;
        }
    }

    /**
     * Debug function to show inline translation patterns
     */
    debugInlinePatterns() {
        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            null,
            false
        );

        const patterns = [];
        let node;
        while (node = walker.nextNode()) {
            if (node.textContent.includes('{{t:')) {
                patterns.push({
                    text: node.textContent,
                    parent: node.parentElement.tagName
                });
            }
        }

        console.log('Found inline translation patterns:', patterns);
        return patterns;
    }

    /**
     * Debug function to test variable substitution
     */
    debugVariableSubstitution() {
        console.log('Testing variable substitution:');

        // Test the translation key directly
        const key = 'error.template_not_found';
        const vars = { template: 'test.html' };

        console.log('Key:', key);
        console.log('Variables:', vars);
        console.log('Current language:', this.currentLang);
        console.log('Translation text:', this.translations[this.currentLang]?.[key]);
        console.log('Final result:', this.t(key, vars));

        // Test all spans with data-i18n-vars
        const spans = document.querySelectorAll('[data-i18n-vars]');
        console.log('Found spans with variables:', spans.length);

        spans.forEach((span, index) => {
            const spanKey = span.getAttribute('data-i18n');
            const varsStr = span.getAttribute('data-i18n-vars');
            const parsedVars = this.parseDataVars(varsStr);

            console.log(`Span ${index}:`, {
                key: spanKey,
                varsStr: varsStr,
                parsedVars: parsedVars,
                currentText: span.textContent,
                expectedText: this.t(spanKey, parsedVars)
            });
        });
    }

    /**
     * Debug function to check language initialization
     */
    debugLanguageInfo() {
        console.log('=== Language Debug Info ===');
        console.log('Initialized:', this.initialized);
        console.log('Current language:', this.currentLang);
        console.log('Available languages:', this.availableLanguages);
        console.log('Language names:', this.languageNames);
        console.log('Loaded translations:', Object.keys(this.translations));

        // Test the language list API
        fetch('/lua/api/language/list')
            .then(response => response.json())
            .then(data => {
                console.log('Language list API response:', data);
            })
            .catch(error => {
                console.error('Error fetching language list:', error);
            });
    }
}

// Create global instance
window.i18n = new ThinginoI18n();

// Auto-initialize when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => window.i18n.init());
} else {
    window.i18n.init();
}
