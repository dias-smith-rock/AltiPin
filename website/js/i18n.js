/**
 * AltiPin website i18n engine.
 * Default locale: en
 */
(function () {
  'use strict';

  const STORAGE_KEY = 'altipin-lang';
  const DEFAULT_LOCALE = 'en';
  const SUPPORTED = ['en', 'zh-Hans', 'zh-Hant', 'es', 'pt-BR', 'ar', 'hi', 'fr'];
  const RTL = new Set(['ar']);

  const LOCALE_LABELS = {
    en: 'English',
    'zh-Hans': '简体中文',
    'zh-Hant': '繁體中文',
    es: 'Español',
    'pt-BR': 'Português (Brasil)',
    ar: 'العربية',
    hi: 'हिन्दी',
    fr: 'Français',
  };

  function normalizeLocale(raw) {
    if (!raw) return null;
    const tag = raw.trim().replace(/_/g, '-');
    if (SUPPORTED.includes(tag)) return tag;
    const lower = tag.toLowerCase();
    if (lower.startsWith('zh-hans') || lower === 'zh-cn') return 'zh-Hans';
    if (lower.startsWith('zh-hant') || lower === 'zh-tw' || lower === 'zh-hk') return 'zh-Hant';
    if (lower.startsWith('pt')) return 'pt-BR';
    const base = tag.split('-')[0].toLowerCase();
    const map = { en: 'en', es: 'es', ar: 'ar', hi: 'hi', fr: 'fr', zh: 'zh-Hans' };
    return map[base] ?? null;
  }

  function readUrlLocale() {
    return normalizeLocale(new URLSearchParams(window.location.search).get('lang'));
  }

  function readStoredLocale() {
    try {
      return normalizeLocale(localStorage.getItem(STORAGE_KEY));
    } catch {
      return null;
    }
  }

  function readBrowserLocale() {
    const langs = navigator.languages?.length ? navigator.languages : [navigator.language];
    for (const lang of langs) {
      const resolved = normalizeLocale(lang);
      if (resolved) return resolved;
    }
    return null;
  }

  function getLocale() {
    return readUrlLocale() || readStoredLocale() || readBrowserLocale() || DEFAULT_LOCALE;
  }

  function getMessages(locale) {
    const all = window.ALTIPIN_LOCALES || {};
    return all[locale] || all[DEFAULT_LOCALE] || {};
  }

  function translate(key, locale) {
    const messages = getMessages(locale);
    if (Object.prototype.hasOwnProperty.call(messages, key)) {
      return messages[key];
    }
    const fallback = getMessages(DEFAULT_LOCALE);
    return fallback[key] ?? key;
  }

  function applyToDocument(locale) {
    const messages = getMessages(locale);
    const page = document.body.dataset.page || 'home';
    const titleKey = `meta.title.${page}`;
    const descKey = `meta.description.${page}`;

    document.documentElement.lang = locale;
    document.documentElement.dir = RTL.has(locale) ? 'rtl' : 'ltr';

    if (messages[titleKey]) document.title = messages[titleKey];
    const metaDesc = document.querySelector('meta[name="description"]');
    if (metaDesc && messages[descKey]) metaDesc.setAttribute('content', messages[descKey]);

    document.querySelectorAll('[data-i18n]').forEach((el) => {
      const key = el.getAttribute('data-i18n');
      const value = translate(key, locale);
      if (el.getAttribute('data-i18n-html') === 'true' || el.hasAttribute('data-i18n-html') && el.getAttribute('data-i18n-html') !== 'false') {
        el.innerHTML = value;
      } else {
        el.textContent = value;
      }
    });

    document.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
      const key = el.getAttribute('data-i18n-placeholder');
      el.setAttribute('placeholder', translate(key, locale));
    });

    document.querySelectorAll('[data-i18n-aria]').forEach((el) => {
      const key = el.getAttribute('data-i18n-aria');
      el.setAttribute('aria-label', translate(key, locale));
    });

    const select = document.getElementById('lang-select');
    if (select) {
      select.value = locale;
    }

    try {
      localStorage.setItem(STORAGE_KEY, locale);
    } catch {
      /* ignore */
    }

    applySiteConfig();
  }

  function applySiteConfig() {
    const config = window.ALTIPIN_SITE;
    if (!config) return;

    const appStoreLink = document.getElementById('app-store-link');
    if (appStoreLink && config.appStoreURL) {
      appStoreLink.href = config.appStoreURL;
    }

    const contactLink = document.getElementById('contact-email-link');
    if (contactLink && config.contactEmail) {
      contactLink.href = `mailto:${config.contactEmail}`;
      contactLink.textContent = config.contactEmail;
    }
  }

  function buildLanguageSwitcher() {
    const nav = document.querySelector('.nav-links');
    if (!nav || document.getElementById('lang-select')) return;

    const li = document.createElement('li');
    li.className = 'lang-switcher-item';
    const select = document.createElement('select');
    select.id = 'lang-select';
    select.className = 'lang-select';
    select.setAttribute('data-i18n-aria', 'lang.label');

    SUPPORTED.forEach((code) => {
      const option = document.createElement('option');
      option.value = code;
      option.textContent = LOCALE_LABELS[code];
      select.appendChild(option);
    });

    select.addEventListener('change', () => {
      const next = normalizeLocale(select.value) || DEFAULT_LOCALE;
      applyToDocument(next);
      const url = new URL(window.location.href);
      url.searchParams.set('lang', next);
      window.history.replaceState({}, '', url);
    });

    li.appendChild(select);
    nav.appendChild(li);
  }

  function init() {
    buildLanguageSwitcher();
    const locale = getLocale();
    applyToDocument(locale);

    const urlLocale = readUrlLocale();
    if (!urlLocale) {
      const url = new URL(window.location.href);
      url.searchParams.set('lang', locale);
      window.history.replaceState({}, '', url);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.AltiPinI18n = { getLocale, applyToDocument, translate, SUPPORTED, DEFAULT_LOCALE };
})();
