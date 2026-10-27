// Keep older administrator bookmarks usable after moving operations to /admin/.
const legacyAdmin = /^#\/(login|dashboard|reviews|technical|publishing|projects|delivery|members|tickets|audit)(?:[/?]|$)/;
if (legacyAdmin.test(location.hash)) {
  const admin = document.documentElement.dataset.adminUrl;
  location.replace(admin.split('#')[0] + location.hash);
} else {
  let locale = 'ja';
  try { if (localStorage.getItem('opc.site.locale') === 'zh') locale = 'zh'; } catch { /* Japanese default. */ }
  location.replace(locale + '/' + location.search + location.hash);
}
