# CDN Vendor Fallbacks

`files/www/a/vendor/` directory holds **local, size-reduced** copies of the
third-party assets that the Web UI normally loads from a CDN.
They are served automatically when the CDN is unreachable (isolated/offline mode).

The build system (`apply_cdn_fallback.py`) rewrites every HTML page at build
time to add `onerror=` fallback attributes to CDN `<link>` and `<script>` tags
that redirect to these files.  CDN is still preferred when network is available.

## Required files

Place your reduced/minified local copies here following this layout:

```
vendor/
├── bootstrap.min.css          # Bootstrap CSS (trimmed or full minified)
├── bootstrap.bundle.min.js    # Bootstrap JS bundle (trimmed or full minified)
├── bootstrap-icons.min.css    # Bootstrap Icons CSS
├── montserrat.css             # @font-face CSS pointing to fonts/ below
└── fonts/
    ├── bootstrap-icons.woff2  # Bootstrap Icons webfont
    ├── bootstrap-icons.woff   # Bootstrap Icons webfont (legacy)
    ├── montserrat-400.woff2
    ├── montserrat-500.woff2
    ├── montserrat-600.woff2
    └── montserrat-700.woff2
```

## montserrat.css format

`montserrat.css` must use relative paths (relative to `/a/vendor/`) so the
browser can find the font files:

```css
@font-face {
  font-family: 'Montserrat';
  font-style: normal;
  font-weight: 400;
  src: url('/a/vendor/fonts/montserrat-400.woff2') format('woff2');
}
@font-face {
  font-family: 'Montserrat';
  font-style: normal;
  font-weight: 500;
  src: url('/a/vendor/fonts/montserrat-500.woff2') format('woff2');
}
/* …repeat for 600 and 700 */
```

## bootstrap-icons.min.css adjustment

If the Bootstrap Icons CSS references fonts with a relative path (e.g.
`url("../fonts/bootstrap-icons.woff2")`), update those paths to
`url("/a/vendor/fonts/bootstrap-icons.woff2")` so they resolve correctly
under `/a/vendor/`.

## Notes

- Files in this directory are installed to `/var/www/a/vendor/` on the device.
- This README is **not** installed to the firmware image.
- Re-run the build after adding or updating vendor files.
