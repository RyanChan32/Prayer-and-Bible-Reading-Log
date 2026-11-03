// Login accounts through Supabase Auth. window.authService stays null when no
// project is configured, and the app then uses its browser-only accounts.
(function () {
  const cfg = window.ODC_CONFIG || {};
  window.authService = null;
  if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) return;

  // Read now: the Supabase client removes this from the URL as it starts up.
  const recoveryLink = location.hash.includes('type=recovery');
  const client = window.supabase ? window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey) : null;
  const unreachable = { message: "Couldn't reach the server. Check your connection and try again." };
  const safely = fn => async (...args) => {
    if (!client) return { data: {}, error: unreachable };
    try { return await fn(...args); } catch { return { data: {}, error: unreachable }; }
  };
  const returnUrl = () => location.href.split('#')[0];

  window.authService = {
    recoveryLink,
    signUp: safely((name, email, password) => client.auth.signUp({
      email, password, options: { data: { name }, emailRedirectTo: returnUrl() }
    })),
    signIn: safely((email, password) => client.auth.signInWithPassword({ email, password })),
    signOut: safely(() => client.auth.signOut()),
    requestPasswordReset: safely(email => client.auth.resetPasswordForEmail(email, { redirectTo: returnUrl() })),
    updatePassword: safely(password => client.auth.updateUser({ password })),
    getSession: safely(() => client.auth.getSession()),
    onChange(fn) { if (client) client.auth.onAuthStateChange(fn); }
  };
})();
