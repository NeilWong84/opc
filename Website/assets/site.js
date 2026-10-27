/* Native interactions; public marketing pages never read business sessions. */
document.querySelectorAll('[data-locale]').forEach(link => {
  if (link.tagName !== 'A') return;
  link.addEventListener('click', () => {
    try { localStorage.setItem('opc.site.locale', link.dataset.locale); } catch { /* Storage is optional. */ }
  });
});

const menu = document.querySelector('.menu-toggle');
const navigation = document.getElementById('mobile-nav');
function closeMenu() { if (!menu) return; menu.setAttribute('aria-expanded', 'false'); navigation.hidden = true; }
menu?.addEventListener('click', () => {
  const open = menu.getAttribute('aria-expanded') !== 'true';
  menu.setAttribute('aria-expanded', String(open)); navigation.hidden = !open;
});
navigation?.querySelectorAll('a').forEach(link => link.addEventListener('click', closeMenu));
document.addEventListener('keydown', event => { if (event.key === 'Escape') { closeMenu(); if (navigation?.contains(document.activeElement)) menu.focus(); } });
matchMedia('(min-width: 961px)').addEventListener('change', closeMenu);

const reduced = matchMedia('(prefers-reduced-motion: reduce)');
if ('IntersectionObserver' in window && !reduced.matches) {
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => { if (entry.isIntersecting) { entry.target.classList.add('visible'); observer.unobserve(entry.target); } });
  }, { threshold: 0.08 });
  document.querySelectorAll('.reveal').forEach(element => observer.observe(element));
  document.documentElement.classList.add('motion-ready');
}
document.querySelectorAll('[data-screen]').forEach(button => button.addEventListener('click', () => {
  document.querySelectorAll('[data-screen]').forEach(item => {
    const active = item === button; item.classList.toggle('active', active); item.setAttribute('aria-pressed', String(active));
  });
  document.querySelectorAll('[data-shot]').forEach(shot => { shot.hidden = shot.dataset.shot !== button.dataset.screen; });
}));
document.querySelector('[data-copy]')?.addEventListener('click', async event => {
  const button = event.currentTarget;
  const field = document.getElementById(button.dataset.copy);
  const status = document.querySelector('.copy-status');
  try {
    await navigator.clipboard.writeText(field.value);
    status.textContent = button.dataset.copied;
  } catch {
    field.focus(); field.select(); status.textContent = button.dataset.error;
  }
});
