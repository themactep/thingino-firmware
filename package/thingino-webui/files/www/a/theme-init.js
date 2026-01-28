// Inline theme initializer - apply theme before page renders
(function() {
  try {
    const theme = localStorage.getItem('thingino-theme-active') || 'dark';
    let resolvedTheme = theme;

    // Resolve 'auto' based on time of day
    if (theme === 'auto') {
      const hour = new Date().getHours();
      resolvedTheme = hour >= 8 && hour < 20 ? 'light' : 'dark';
    }

    document.documentElement.setAttribute('data-bs-theme', resolvedTheme);
  } catch (e) {
    // localStorage not available, use default dark theme
    document.documentElement.setAttribute('data-bs-theme', 'dark');
  }
})();
