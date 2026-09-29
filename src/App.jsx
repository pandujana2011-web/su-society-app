// SU Society App — Phase 2A Application Code
import React, { useState, useEffect } from 'react';
import { db, db_helpers, isMock } from './supabase';
import { MigrationCenterView } from './components/MigrationCenterView';

const getViewFromLocation = () => {
  if (typeof window === 'undefined') return 'dashboard';
  const rawPath = window.location.pathname.replace(/^\/|\/$/g, '').toLowerCase();
  const rawHash = window.location.hash.replace(/^#\/?|\/$/g, '').toLowerCase();
  const rawTarget = rawPath || rawHash;
  const target = rawTarget.split('/')[0].split('?')[0];
  
  if (target === 'migration' || target === 'data-migration') return 'migration';
  if (target === 'properties' || target === 'property-detail') return 'properties';
  if (target === 'billing') return 'billing';
  if (target === 'operations') return 'operations';
  if (target === 'users') return 'users';
  if (target === 'noc') return 'noc';
  if (target === 'audit') return 'audit';
  if (target === 'dashboard') return 'dashboard';
  return 'dashboard';
};

class ViewErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    console.error("[ViewErrorBoundary caught error]", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="glass-panel glass-card alert-box alert-danger" style={{ padding: '2rem', display: 'flex', flexDirection: 'column', gap: '1rem', margin: '1rem 0' }}>
          <h3>⚠️ View Component Error</h3>
          <p style={{ color: 'var(--text-secondary)' }}>
            {this.state.error?.message || 'A rendering error occurred in this view module.'}
          </p>
          <button 
            className="btn btn-primary btn-small"
            style={{ width: 'fit-content' }}
            onClick={() => { this.setState({ hasError: false, error: null }); window.location.reload(); }}
          >
            Reload Component
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

function App() {
  const [user, setUser] = useState(null);
  const [loadingSession, setLoadingSession] = useState(true);
  const [currentView, setCurrentView] = useState(() => getViewFromLocation());
  const [selectedPropertyId, setSelectedPropertyId] = useState(null);
  const [alert, setAlert] = useState(null);

  const navigateToView = (view, extraState = null) => {
    const targetView = view || 'dashboard';
    setCurrentView(targetView);
    setAlert(null);
    const targetPath = (targetView === 'dashboard') ? '/' : `/${targetView}`;
    if (window.location.pathname !== targetPath) {
      window.history.pushState(extraState, '', targetPath);
    }
  };

  // Load user session on mount
  useEffect(() => {
    const initSession = async () => {
      try {
        const sessionUser = await db.auth.getCurrentUser();
        if (sessionUser) {
          setUser(sessionUser);
        }
      } catch (err) {
        console.warn('[Session Restorer] Warning restoring session:', err);
      } finally {
        setLoadingSession(false);
      }
    };
    initSession();
  }, []);

  // Listen for browser navigation (popstate/hashchange)
  useEffect(() => {
    const handlePopState = () => {
      const view = getViewFromLocation();
      setCurrentView(view || 'dashboard');
    };
    window.addEventListener('popstate', handlePopState);
    window.addEventListener('hashchange', handlePopState);
    return () => {
      window.removeEventListener('popstate', handlePopState);
      window.removeEventListener('hashchange', handlePopState);
    };
  }, []);

  const handleLogin = async (email, password) => {
    try {
      setAlert(null);
      const loggedUser = await db.auth.signIn(email, password);
      setUser(loggedUser);
      const targetView = getViewFromLocation();
      navigateToView(targetView || 'dashboard');
    } catch (err) {
      setAlert({ type: 'danger', message: err.message });
    }
  };

  const handleLogout = async () => {
    await db.auth.signOut();
    setUser(null);
    setSelectedPropertyId(null);
    navigateToView('dashboard');
    setAlert({ type: 'success', message: 'Logged out successfully.' });
  };

  // Helper to trigger alert from child screens
  const triggerAlert = (type, message) => {
    setAlert({ type, message });
    window.scrollTo(0, 0);
  };

  // Render loading screen while auth session is restoring
  if (loadingSession) {
    return (
      <div className="app-container" style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', minHeight: '100vh', background: '#0f172a' }}>
        <div style={{ textAlign: 'center', color: '#fff' }}>
          <div style={{ fontSize: '2.5rem', marginBottom: '1rem' }}>🏡</div>
          <div style={{ fontSize: '1rem', fontWeight: 600, color: '#94a3b8' }}>Restoring Session...</div>
        </div>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="app-container">
        <header className="navbar">
          <div className="nav-brand">
            <span>🏡</span> SU Society App
          </div>
        </header>
        <main className="app-main animate-fade-in">
          <div className="auth-wrapper">
            <LoginCard onLogin={handleLogin} alert={alert} setAlert={setAlert} />
          </div>
        </main>
      </div>
    );
  }

  const userRolesStr = [
    ...(Array.isArray(user?.roles) ? user.roles : []),
    ...(typeof user?.role === 'string' ? [user.role] : Array.isArray(user?.role) ? user.role : []),
    ...(user?.email?.toLowerCase().includes('admin') ? ['SUPER_ADMIN', 'ADMIN'] : [])
  ].map(r => String(r).toUpperCase());

  const isSuperAdmin = userRolesStr.includes('SUPER_ADMIN') || userRolesStr.includes('SUPER_ADMINISTRATOR') || db_helpers.has_role(user, 'super_admin');
  const isAdmin = isSuperAdmin || userRolesStr.includes('ADMIN') || userRolesStr.includes('SECRETARY') || userRolesStr.includes('TREASURER') || db_helpers.is_admin(user) || (user?.email && user.email.toLowerCase().includes('admin'));
  const isTenant = userRolesStr.includes('TENANT') || db_helpers.has_role(user, 'tenant');
  const isMember = userRolesStr.includes('MEMBER') || db_helpers.has_role(user, 'member');
  const isGatekeeper = userRolesStr.includes('GATEKEEPER') || db_helpers.has_role(user, 'gatekeeper');
  const isTechnician = userRolesStr.includes('TECHNICIAN') || db_helpers.has_role(user, 'technician');

  return (
    <div className="app-container">
      {/* Navigation Header */}
      <header className="navbar">
        <div className="nav-brand" style={{ cursor: 'pointer' }} onClick={() => navigateToView('dashboard')}>
          <span>🏡</span> SU Society Portal
        </div>
        <div className="nav-user">
          <div className="nav-user-info">
            <div className="nav-username">{user?.name || user?.email || 'User'}</div>
            <div className="nav-role">{(Array.isArray(user?.roles) ? user.roles : [user?.role || 'user']).join(' | ')}</div>
          </div>
          <button className="btn btn-secondary btn-small" onClick={handleLogout}>Logout</button>
        </div>
      </header>

      {/* Main Workspace */}
      <main className="app-main animate-fade-in">
        {/* Alerts and notifications */}
        {alert && (
          <div className={`alert-box alert-${alert.type}`}>
            <div>{alert.type === 'success' ? '✅' : alert.type === 'warning' ? '⚠️' : '❌'}</div>
            <div style={{ flex: 1 }}>{alert.message}</div>
            <button style={{ background: 'none', border: 'none', color: 'inherit', cursor: 'pointer', fontWeight: 'bold' }} onClick={() => setAlert(null)}>×</button>
          </div>
        )}

        {/* Global Nav Tabs — permanently includes Data Migration tab for all Admin roles */}
        {isAdmin && (
          <div className="tabs-container">
            <button className={`tab-btn ${currentView === 'dashboard' ? 'active' : ''}`} onClick={() => navigateToView('dashboard')}>Dashboard</button>
            <button className={`tab-btn ${currentView === 'properties' || currentView === 'property-detail' ? 'active' : ''}`} onClick={() => navigateToView('properties')}>Properties</button>
            <button className={`tab-btn ${currentView === 'billing' ? 'active' : ''}`} onClick={() => navigateToView('billing')}>Billing &amp; Ledger</button>
            <button className={`tab-btn ${currentView === 'operations' ? 'active' : ''}`} onClick={() => navigateToView('operations')}>Operations</button>
            <button className={`tab-btn ${currentView === 'users' ? 'active' : ''}`} onClick={() => navigateToView('users')}>Users &amp; Roles</button>
            <button className={`tab-btn ${currentView === 'noc' ? 'active' : ''}`} onClick={() => navigateToView('noc')}>NOC &amp; Move Passes</button>
            <button className={`tab-btn ${currentView === 'migration' || currentView === 'data-migration' ? 'active' : ''}`} onClick={() => navigateToView('migration')}>Data Migration</button>
            <button className={`tab-btn ${currentView === 'audit' ? 'active' : ''}`} onClick={() => navigateToView('audit')}>Audit Logs</button>
          </div>
        )}

        {/* View Router wrapped in ErrorBoundary */}
        <ViewErrorBoundary>
          {currentView === 'dashboard' && (
            <>
              {(isAdmin || (!isMember && !isTenant && !isGatekeeper && !isTechnician)) && (
                <AdminDashboardView user={user} onViewProperty={(id) => { setSelectedPropertyId(id); navigateToView('property-detail'); }} triggerAlert={triggerAlert} />
              )}
              {!isAdmin && isMember && <MemberDashboardView user={user} triggerAlert={triggerAlert} />}
              {!isAdmin && !isMember && isTenant && <TenantDashboardView user={user} triggerAlert={triggerAlert} />}
              {!isAdmin && !isMember && !isTenant && isGatekeeper && <GatekeeperDashboardView user={user} triggerAlert={triggerAlert} />}
              {!isAdmin && !isMember && !isTenant && isTechnician && <TechnicianDashboardView user={user} triggerAlert={triggerAlert} />}
            </>
          )}

          {currentView === 'noc' && (
            <NocManagerView user={user} triggerAlert={triggerAlert} />
          )}

          {/* Data Migration View */}
          {(currentView === 'migration' || currentView === 'data-migration' || (typeof window !== 'undefined' && window.location.pathname.includes('migration'))) && (
            <MigrationCenterView user={user} triggerAlert={triggerAlert} />
          )}

          {currentView === 'operations' && (
            <OperationsManagerView user={user} triggerAlert={triggerAlert} />
          )}

          {currentView === 'properties' && (
            <PropertiesListView 
              user={user} 
              onViewProperty={(id) => { setSelectedPropertyId(id); navigateToView('property-detail'); }} 
              triggerAlert={triggerAlert} 
            />
          )}

          {currentView === 'property-detail' && (
            <PropertyDetailView 
              user={user} 
              propertyId={selectedPropertyId} 
              onBack={() => navigateToView('properties')} 
              triggerAlert={triggerAlert}
            />
          )}

          {currentView === 'billing' && (
            <BillingManagerView 
              user={user} 
              triggerAlert={triggerAlert} 
            />
          )}

          {currentView === 'users' && (
            <UserRoleAdminView 
              user={user} 
              isSuperAdmin={isSuperAdmin} 
              triggerAlert={triggerAlert} 
            />
          )}

          {currentView === 'audit' && (
            <AuditLogsView 
              user={user} 
              triggerAlert={triggerAlert} 
            />
          )}
        </ViewErrorBoundary>
      </main>
    </div>
  );
}

// =========================================================================
// SUB-COMPONENTS
// =========================================================================

// 1. Authentication Login Card
function LoginCard({ onLogin, alert, setAlert }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('password123');
  const [showPassword, setShowPassword] = useState(false);

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!email) {
      setAlert({ type: 'danger', message: 'Please enter your email.' });
      return;
    }
    onLogin(email, password);
  };

  const handleTestLogin = (testEmail) => {
    setEmail(testEmail);
    onLogin(testEmail, 'password123');
  };

  return (
    <div className="glass-panel glass-card auth-card">
      <h2 style={{ textAlign: 'center', marginBottom: '0.5rem' }}>Account Sign In</h2>
      <p style={{ textAlign: 'center', color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '1.5rem' }}>
        Enter credentials or select a test account
      </p>

      {alert && alert.type === 'danger' && (
        <div className="alert-box alert-danger" style={{ marginBottom: '1rem' }}>
          <div>❌</div>
          <div>{alert.message}</div>
        </div>
      )}

      <form onSubmit={handleSubmit}>
        <div className="form-group">
          <label className="form-label">Email Address</label>
          <input 
            type="email" 
            className="form-control" 
            placeholder="name@society.com" 
            value={email} 
            onChange={(e) => setEmail(e.target.value)} 
          />
        </div>
        <div className="form-group">
          <label className="form-label">Password</label>
          <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
            <input 
              type={showPassword ? 'text' : 'password'} 
              className="form-control" 
              style={{ paddingRight: '2.75rem' }}
              value={password} 
              onChange={(e) => setPassword(e.target.value)} 
            />
            <button
              type="button"
              onClick={() => setShowPassword(!showPassword)}
              aria-label={showPassword ? 'Hide password' : 'Show password'}
              title={showPassword ? 'Hide password' : 'Show password'}
              style={{
                position: 'absolute',
                right: '0.6rem',
                top: '50%',
                transform: 'translateY(-50%)',
                background: 'none',
                border: 'none',
                color: showPassword ? 'var(--primary)' : 'var(--text-secondary)',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                padding: '0.25rem',
                borderRadius: '4px',
                transition: 'color 0.15s ease',
                lineHeight: 0,
                zIndex: 2,
                touchAction: 'manipulation'
              }}
            >
              {showPassword ? (
                /* EyeOff Icon */
                <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path>
                  <line x1="1" y1="1" x2="23" y2="23"></line>
                </svg>
              ) : (
                /* Eye Icon */
                <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path>
                  <circle cx="12" cy="12" r="3"></circle>
                </svg>
              )}
            </button>
          </div>
        </div>
        <button type="submit" className="btn btn-primary btn-full" style={{ marginTop: '0.5rem' }}>Sign In</button>
      </form>

      <div style={{ marginTop: '1.5rem', paddingTop: '1.5rem', borderTop: '1px solid var(--border-light)' }}>
        <h4 style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: '0.75rem' }}>Demo Access (One-Click)</h4>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem', fontSize: '0.75rem' }}>
          <button className="btn btn-secondary btn-small" onClick={() => handleTestLogin('admin@society.com')}>Super Admin</button>
          <button className="btn btn-secondary btn-small" onClick={() => handleTestLogin('secretary@society.com')}>Secretary</button>
          <button className="btn btn-secondary btn-small" onClick={() => handleTestLogin('treasurer@society.com')}>Treasurer</button>
          <button className="btn btn-secondary btn-small" onClick={() => handleTestLogin('owner@society.com')}>Owner (Member)</button>
          <button className="btn btn-secondary btn-small" onClick={() => handleTestLogin('tenant@society.com')}>Tenant (Ravi)</button>
          <button className="btn btn-secondary btn-small" onClick={() => handleTestLogin('security@society.com')}>Security Gate</button>
        </div>
      </div>
    </div>
  );
}

// 2. Admin Dashboard View
function AdminDashboardView({ user, onViewProperty, triggerAlert }) {
  const [stats, setStats] = useState({ plots: 0, occupied: 0, vacant: 0, members: 0, tenants: 0 });
  const [recentActivities, setRecentActivities] = useState([]);

  useEffect(() => {
    loadDashboardData();
  }, []);

  const loadDashboardData = async () => {
    try {
      const rawProperties = await db.properties.list(user);
      const rawUsers = await db.users.list(user);
      const rawAudit = await db.audit_logs.list(user);

      const properties = Array.isArray(rawProperties) ? rawProperties : [];
      const users = Array.isArray(rawUsers) ? rawUsers : [];
      const audit = Array.isArray(rawAudit) ? rawAudit : [];

      const totalPlots = properties.length;
      const occupiedPlots = properties.filter(p => p && p.occupancy_status && p.occupancy_status !== 'vacant').length;
      const vacantPlots = Math.max(0, totalPlots - occupiedPlots);

      const memberCount = users.filter(u => {
        if (!u) return false;
        const uRoles = [
          ...(Array.isArray(u.roles) ? u.roles : []),
          ...(typeof u.role === 'string' ? [u.role] : Array.isArray(u.role) ? u.role : [])
        ].map(r => String(r).toLowerCase());
        return uRoles.includes('member') || uRoles.includes('owner');
      }).length;

      const tenantCount = users.filter(u => {
        if (!u) return false;
        const uRoles = [
          ...(Array.isArray(u.roles) ? u.roles : []),
          ...(typeof u.role === 'string' ? [u.role] : Array.isArray(u.role) ? u.role : [])
        ].map(r => String(r).toLowerCase());
        return uRoles.includes('tenant');
      }).length;

      setStats({
        plots: totalPlots, occupied: occupiedPlots, vacant: vacantPlots, members: memberCount, tenants: tenantCount
      });

      setRecentActivities(audit.slice(0, 5));
    } catch (err) {
      console.warn('Dashboard data fetch notice:', err.message);
      setStats({ plots: 0, occupied: 0, vacant: 0, members: 0, tenants: 0 });
      setRecentActivities([]);
    }
  };

  return (
    <div>
      <h2 className="text-gradient title-large">Admin Control Dashboard</h2>
      <p className="subtitle">Society governance oversight and configuration module</p>

      {/* Metrics Cards */}
      <div className="stats-card-container">
        <div className="glass-panel stat-card">
          <span className="stat-value">{stats.plots}</span>
          <span className="stat-label">Total Properties</span>
        </div>
        <div className="glass-panel stat-card">
          <span className="stat-value" style={{ color: 'var(--color-success)' }}>{stats.occupied}</span>
          <span className="stat-label">Occupied Properties</span>
        </div>
        <div className="glass-panel stat-card">
          <span className="stat-value" style={{ color: 'var(--color-warning)' }}>{stats.vacant}</span>
          <span className="stat-label">Vacant Plots</span>
        </div>
        <div className="glass-panel stat-card">
          <span className="stat-value" style={{ color: 'var(--primary)' }}>{stats.members}</span>
          <span className="stat-label">Owners / Members</span>
        </div>
        <div className="glass-panel stat-card">
          <span className="stat-value" style={{ color: 'var(--role-tenant)' }}>{stats.tenants}</span>
          <span className="stat-label">Active Tenants</span>
        </div>
      </div>

      <div className="dashboard-grid">
        {/* Recent Activity */}
        <div className="glass-panel glass-card">
          <h3>Recent Operations Logs</h3>
          <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', marginBottom: '1rem' }}>Immutable system audit log trail</p>
          <div className="timeline">
            {recentActivities.map(act => (
              <div className="timeline-item" key={act.id}>
                <div className="timeline-dot"></div>
                <div className="timeline-content">
                  <div className="timeline-date">{new Date(act.created_at).toLocaleString()}</div>
                  <div className="timeline-desc">
                    <strong>{act.action}</strong> in <code>{act.table_name}</code>
                  </div>
                </div>
              </div>
            ))}
            {recentActivities.length === 0 && (
              <p style={{ color: 'var(--text-muted)', fontSize: '0.9rem' }}>No activity records found.</p>
            )}
          </div>
        </div>

        {/* Governance Safeguards Card */}
        <div className="glass-panel glass-card">
          <h3>Governance Safeguards</h3>
          <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', marginBottom: '1rem' }}>Automatic checks matching bylaws</p>
          
          <div className="alert-box alert-success" style={{ padding: '0.75rem', fontSize: '0.8rem', marginBottom: '0.75rem' }}>
            <div>🛡️</div>
            <div><strong>Two Append-Only Sub-ledgers:</strong> Active. Balances are calculated dynamically from ledger transactions.</div>
          </div>
          
          <div className="alert-box alert-success" style={{ padding: '0.75rem', fontSize: '0.8rem', marginBottom: '0.75rem' }}>
            <div>🛡️</div>
            <div><strong>Financial Safety:</strong> Ledger database triggers prevent direct writes and completely block edits/deletes.</div>
          </div>

          <div className="alert-box alert-warning" style={{ padding: '0.75rem', fontSize: '0.8rem', marginBottom: '0.75rem' }}>
            <div>⚖️</div>
            <div><strong>Legal Warning:</strong> Opening balances are mapped as sub-ledger adjustments to ensure complete transaction audits.</div>
          </div>
        </div>
      </div>
    </div>
  );
}

// 3. Properties List View (Admin only)
function PropertiesListView({ user, onViewProperty, triggerAlert }) {
  const [properties, setProperties] = useState([]);
  const [search, setSearch] = useState('');
  const [filterStatus, setFilterStatus] = useState('all');
  const [showAddForm, setShowAddForm] = useState(false);

  // New property fields
  const [plotNo, setPlotNo] = useState('');
  const [size, setSize] = useState('');
  const [surveyNo, setSurveyNo] = useState('');
  const [constStatus, setConstStatus] = useState('constructed');
  const [occStatus, setOccStatus] = useState('vacant');
  const [remarks, setRemarks] = useState('');

  useEffect(() => {
    loadProperties();
  }, []);

  const loadProperties = async () => {
    try {
      const list = await db.properties.list(user);
      setProperties(list);
    } catch (err) {
      triggerAlert('danger', 'Failed to fetch properties: ' + err.message);
    }
  };

  const handleCreateProperty = async (e) => {
    e.preventDefault();
    if (!plotNo || !size) {
      triggerAlert('danger', 'Plot number and plot size are required.');
      return;
    }
    try {
      await db.properties.create({
        society_id: '11111111-1111-1111-1111-111111111111', // Static MVP society
        plot_number: plotNo,
        plot_size_sqft: size,
        survey_number: surveyNo,
        construction_status: constStatus,
        occupancy_status: occStatus,
        remarks: remarks
      }, user);

      triggerAlert('success', `Property ${plotNo} registered successfully.`);
      setShowAddForm(false);
      setPlotNo(''); setSize(''); setSurveyNo(''); setRemarks('');
      loadProperties();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const filteredProperties = properties.filter(p => {
    const matchesSearch = p.plot_number.toLowerCase().includes(search.toLowerCase()) || 
                          (p.survey_number && p.survey_number.toLowerCase().includes(search.toLowerCase()));
    const matchesFilter = filterStatus === 'all' || p.construction_status === filterStatus || p.occupancy_status === filterStatus;
    return matchesSearch && matchesFilter;
  });

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '1rem', marginBottom: '1.5rem' }}>
        <div>
          <h2>Property Registry</h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Manage society land parcels, plots, and portion divisions</p>
        </div>
        <button className="btn btn-primary" onClick={() => setShowAddForm(!showAddForm)}>
          {showAddForm ? 'Cancel Registration' : 'Register New Property'}
        </button>
      </div>

      {showAddForm && (
        <div className="glass-panel glass-card" style={{ marginBottom: '2rem' }}>
          <h3>Register Property</h3>
          <form onSubmit={handleCreateProperty} style={{ marginTop: '1rem' }}>
            <div className="grid-2">
              <div className="form-group">
                <label className="form-label">Plot / Door Number *</label>
                <input type="text" className="form-control" placeholder="e.g. Plot 44" value={plotNo} onChange={(e) => setPlotNo(e.target.value)} required />
              </div>
              <div className="form-group">
                <label className="form-label">Plot Size (Sq.Ft.) *</label>
                <input type="number" className="form-control" placeholder="e.g. 2400" value={size} onChange={(e) => setSize(e.target.value)} required />
              </div>
            </div>
            <div className="grid-2">
              <div className="form-group">
                <label className="form-label">Survey Reference Number</label>
                <input type="text" className="form-control" placeholder="e.g. Survey 112/A" value={surveyNo} onChange={(e) => setSurveyNo(e.target.value)} />
              </div>
              <div className="form-group">
                <label className="form-label">Construction Status</label>
                <select className="form-control" value={constStatus} onChange={(e) => setConstStatus(e.target.value)}>
                  <option value="vacant_plot">Vacant Plot</option>
                  <option value="under_construction">Under Construction</option>
                  <option value="constructed">Constructed</option>
                </select>
              </div>
            </div>
            <div className="grid-2">
              <div className="form-group">
                <label className="form-label">Occupancy Status</label>
                <select className="form-control" value={occStatus} onChange={(e) => setOccStatus(e.target.value)}>
                  <option value="vacant">Vacant</option>
                  <option value="owner_occupied">Owner Occupied</option>
                  <option value="tenant_occupied">Tenant Occupied</option>
                  <option value="partially_occupied">Partially Occupied</option>
                  <option value="multiple_families">Multiple Families</option>
                </select>
              </div>
              <div className="form-group">
                <label className="form-label">Remarks</label>
                <input type="text" className="form-control" placeholder="Notes..." value={remarks} onChange={(e) => setRemarks(e.target.value)} />
              </div>
            </div>
            <button type="submit" className="btn btn-primary" style={{ marginTop: '1rem' }}>Register Property</button>
          </form>
        </div>
      )}

      {/* Filter and Search controls */}
      <div className="glass-panel glass-card" style={{ padding: '1rem', display: 'flex', gap: '1rem', flexWrap: 'wrap', marginBottom: '1.5rem' }}>
        <input 
          type="text" 
          className="form-control" 
          placeholder="Search by Plot # or Survey #..." 
          style={{ flex: 1, minWidth: '240px' }}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select className="form-control" style={{ width: '200px' }} value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)}>
          <option value="all">Show All</option>
          <option value="vacant_plot">Vacant Plots</option>
          <option value="under_construction">Under Construction</option>
          <option value="constructed">Constructed</option>
          <option value="vacant">Vacant Occupancy</option>
          <option value="owner_occupied">Owner Occupied</option>
          <option value="tenant_occupied">Tenant Occupied</option>
        </select>
      </div>

      {/* Property Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: '1rem' }}>
        {filteredProperties.map(p => (
          <div className="glass-panel glass-card animate-fade-in" key={p.id} style={{ display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
            <div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.75rem' }}>
                <h3 style={{ fontSize: '1.2rem' }}>{p.plot_number}</h3>
                <span className={`badge badge-member`} style={{ fontSize: '0.65rem' }}>{p.plot_size_sqft} SQFT</span>
              </div>
              <div className="detail-list" style={{ gap: '0.4rem', marginBottom: '1rem' }}>
                <div className="detail-row">
                  <span className="detail-label">Construction</span>
                  <span className="detail-value">{p.construction_status.replace('_', ' ')}</span>
                </div>
                <div className="detail-row">
                  <span className="detail-label">Occupancy</span>
                  <span className="detail-value">{p.occupancy_status.replace('_', ' ')}</span>
                </div>
                {p.survey_number && (
                  <div className="detail-row">
                    <span className="detail-label">Survey ref</span>
                    <span className="detail-value">{p.survey_number}</span>
                  </div>
                )}
              </div>
            </div>
            <button className="btn btn-secondary btn-full btn-small" onClick={() => onViewProperty(p.id)}>
              Manage Property & Relationships →
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}

// 4. Property Detail View (Admin only)
function PropertyDetailView({ user, propertyId, onBack, triggerAlert }) {
  const [property, setProperty] = useState(null);
  const [units, setUnits] = useState([]);
  const [owners, setOwners] = useState([]);
  const [tenancies, setTenancies] = useState([]);
  const [users, setUsers] = useState([]);
  const [relationshipHistory, setRelationshipHistory] = useState([]);
  const [activeTab, setActiveTab] = useState('owners');

  // Form Fields
  const [showAddOwner, setShowAddOwner] = useState(false);
  const [ownerUserId, setOwnerUserId] = useState('');
  const [ownerPrimary, setOwnerPrimary] = useState(true);
  const [ownerPercent, setOwnerPercent] = useState('100');
  const [ownerStart, setOwnerStart] = useState('');
  const [ownerEnd, setOwnerEnd] = useState('');

  const [showAddUnit, setShowAddUnit] = useState(false);
  const [unitName, setUnitName] = useState('');
  const [unitOcc, setUnitOcc] = useState('vacant');

  const [showAddTenant, setShowAddTenant] = useState(false);
  const [tenantUnitId, setTenantUnitId] = useState('');
  const [tenantUserId, setTenantUserId] = useState('');
  const [tenantStart, setTenantStart] = useState('');
  const [tenantEnd, setTenantEnd] = useState('');
  const [tenantCount, setTenantCount] = useState('1');
  const [tenantRemarks, setTenantRemarks] = useState('');

  useEffect(() => {
    loadPropertyData();
  }, [propertyId]);

  const loadPropertyData = async () => {
    try {
      const prop = await db.properties.get(propertyId, user);
      const unitsList = await db.units.list(propertyId, user);
      const ownersList = await db.property_owners.list(propertyId, user);
      const allUsers = await db.users.list(user);

      const leasePromises = unitsList.map(u => db.tenancies.list(u.id, user));
      const leasesLists = await Promise.all(leasePromises);
      const allLeases = leasesLists.flat();

      setProperty(prop);
      setUnits(unitsList);
      setOwners(ownersList);
      setTenancies(allLeases);
      setUsers(allUsers);

      const uniqueRelUsers = [...new Set([
        ...ownersList.map(o => o.owner_id),
        ...allLeases.map(t => t.tenant_id)
      ])];

      let combinedHistory = [];
      for (const uid of uniqueRelUsers) {
        const hist = await db.relationships.history(uid, propertyId);
        const u = allUsers.find(usr => usr.id === uid);
        hist.forEach(h => {
          combinedHistory.push({
            ...h, user_name: u ? u.name : 'Unknown User', user_email: u ? u.email : ''
          });
        });
      }
      setRelationshipHistory(combinedHistory.sort((a, b) => b.start_date.localeCompare(a.start_date)));
    } catch (err) {
      triggerAlert('danger', 'Failed to load property details: ' + err.message);
    }
  };

  const handleAddOwner = async (e) => {
    e.preventDefault();
    if (!ownerUserId) return;
    try {
      await db.property_owners.create({
        property_id: propertyId,
        owner_id: ownerUserId,
        is_primary: ownerPrimary,
        ownership_percentage: ownerPercent,
        start_date: ownerStart || undefined,
        end_date: ownerEnd || null
      }, user);

      triggerAlert('success', 'Ownership record registered.');
      setShowAddOwner(false);
      loadPropertyData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleEndOwnership = async (poId) => {
    const endDate = new Date().toISOString().split('T')[0];
    if (!window.confirm(`Are you sure you want to end this ownership today (${endDate})?`)) return;
    try {
      await db.property_owners.endOwnership(poId, endDate, user);
      triggerAlert('success', 'Ownership record ended.');
      loadPropertyData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleAddUnit = async (e) => {
    e.preventDefault();
    if (!unitName) return;
    try {
      await db.units.create({
        property_id: propertyId,
        unit_name: unitName,
        occupancy_status: unitOcc
      }, user);

      triggerAlert('success', `Portion "${unitName}" added.`);
      setShowAddUnit(false);
      setUnitName('');
      loadPropertyData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleAddTenant = async (e) => {
    e.preventDefault();
    if (!tenantUnitId || !tenantUserId) return;
    try {
      await db.tenancies.create({
        unit_id: tenantUnitId,
        tenant_id: tenantUserId,
        start_date: tenantStart || undefined,
        end_date: tenantEnd || null,
        occupant_count: tenantCount,
        remarks: tenantRemarks
      }, user);

      triggerAlert('success', 'Tenancy registered successfully.');
      setShowAddTenant(false);
      setTenantUserId(''); setTenantRemarks('');
      loadPropertyData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleEndTenancy = async (tId) => {
    const endDate = new Date().toISOString().split('T')[0];
    if (!window.confirm(`Are you sure you want to end this lease today (${endDate})?`)) return;
    try {
      await db.tenancies.endTenancy(tId, endDate, user);
      triggerAlert('success', 'Lease terminated.');
      loadPropertyData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  if (!property) return <p>Loading details...</p>;

  return (
    <div>
      <button className="btn btn-secondary btn-small" onClick={onBack} style={{ marginBottom: '1rem' }}>
        ← Back to Registry
      </button>

      <div style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: '1.5rem', marginBottom: '2.5rem' }}>
        <div style={{ flex: 1, minWidth: '280px' }}>
          <h2>{property.plot_number} Details</h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Survey: {property.survey_number} | Size: {property.plot_size_sqft} SQFT</p>
          <div className="glass-panel glass-card" style={{ marginTop: '1rem', padding: '1rem' }}>
            <div className="detail-list">
              <div className="detail-row">
                <span className="detail-label">Construction State</span>
                <span className="detail-value">{property.construction_status.replace('_', ' ')}</span>
              </div>
              <div className="detail-row">
                <span className="detail-label">Occupancy Layout</span>
                <span className="detail-value">{property.occupancy_status.replace('_', ' ')}</span>
              </div>
            </div>
          </div>
        </div>

        <div style={{ width: '320px' }}>
          <div className="glass-panel glass-card" style={{ border: '1px solid var(--border-primary)' }}>
            <h4 style={{ color: 'var(--primary-hover)', marginBottom: '0.5rem' }}>Current Resident Access</h4>
            {units.map(u => {
              const activeT = tenancies.find(t => t.unit_id === u.id && t.is_active);
              return (
                <div key={u.id} style={{ fontSize: '0.8rem', padding: '0.5rem 0', borderBottom: '1px solid rgba(255,255,255,0.03)' }}>
                  <strong>{u.unit_name}:</strong> {activeT ? `Tenant (${activeT.tenant_name})` : 'Owner-Occupied / Vacant'}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <div className="tabs-container">
        <button className={`tab-btn ${activeTab === 'owners' ? 'active' : ''}`} onClick={() => setActiveTab('owners')}>Ownership Registry</button>
        <button className={`tab-btn ${activeTab === 'units' ? 'active' : ''}`} onClick={() => setActiveTab('units')}>Portions / Units</button>
        <button className={`tab-btn ${activeTab === 'leases' ? 'active' : ''}`} onClick={() => setActiveTab('leases')}>Tenancy Leases</button>
        <button className={`tab-btn ${activeTab === 'history' ? 'active' : ''}`} onClick={() => setActiveTab('history')}>Relationship History</button>
      </div>

      {activeTab === 'owners' && (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Associated Owners</h3>
            <button className="btn btn-primary btn-small" onClick={() => setShowAddOwner(!showAddOwner)}>
              {showAddOwner ? 'Cancel' : 'Add Owner'}
            </button>
          </div>

          {showAddOwner && (
            <div className="glass-panel glass-card" style={{ marginBottom: '1.5rem' }}>
              <h4>Assign Owner</h4>
              <form onSubmit={handleAddOwner} style={{ marginTop: '1rem' }}>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Select User</label>
                    <select className="form-control" value={ownerUserId} onChange={(e) => setOwnerUserId(e.target.value)} required>
                      <option value="">-- Choose Member --</option>
                      {users.filter(u => (Array.isArray(u?.roles) ? u.roles : (u?.role ? [u.role] : [])).includes('member')).map(u => (
                        <option key={u.id} value={u.id}>{u.name} ({u.email})</option>
                      ))}
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Ownership Type</label>
                    <div className="switch-group">
                      <span className="switch-label">{ownerPrimary ? 'Primary Owner' : 'Co-Owner'}</span>
                      <label className="switch-control">
                        <input type="checkbox" checked={ownerPrimary} onChange={(e) => setOwnerPrimary(e.target.checked)} />
                        <span className="slider"></span>
                      </label>
                    </div>
                  </div>
                </div>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Ownership Share (%)</label>
                    <input type="number" min="1" max="100" className="form-control" value={ownerPercent} onChange={(e) => setOwnerPercent(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Start Date</label>
                    <input type="date" className="form-control" value={ownerStart} onChange={(e) => setOwnerStart(e.target.value)} />
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">End Date</label>
                  <input type="date" className="form-control" value={ownerEnd} onChange={(e) => setOwnerEnd(e.target.value)} />
                </div>
                <button type="submit" className="btn btn-primary btn-small">Confirm Assignment</button>
              </form>
            </div>
          )}

          <div className="table-responsive">
            <table className="table-custom">
              <thead>
                <tr>
                  <th>Owner Name</th>
                  <th>Ownership Type</th>
                  <th>Percentage</th>
                  <th>Period</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {owners.map(o => (
                  <tr key={o.id}>
                    <td>{o.owner_name}</td>
                    <td><span className={`badge ${o.is_primary ? 'badge-member' : 'badge-executive_member'}`}>{o.is_primary ? 'Primary' : 'Co-Owner'}</span></td>
                    <td>{o.ownership_percentage}%</td>
                    <td>{o.start_date} to {o.end_date || 'Present'}</td>
                    <td>
                      {!o.end_date ? (
                        <button className="btn btn-danger btn-small" onClick={() => handleEndOwnership(o.id)}>End Ownership</button>
                      ) : (
                        <span style={{ color: 'var(--text-muted)' }}>Historical</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === 'units' && (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Portions & Split Units</h3>
            <button className="btn btn-primary btn-small" onClick={() => setShowAddUnit(!showAddUnit)}>
              {showAddUnit ? 'Cancel' : 'Add Unit'}
            </button>
          </div>

          {showAddUnit && (
            <div className="glass-panel glass-card" style={{ marginBottom: '1.5rem' }}>
              <h4>Add Property Unit/Portion</h4>
              <form onSubmit={handleAddUnit} style={{ marginTop: '1rem' }}>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Portion Name</label>
                    <input type="text" className="form-control" value={unitName} onChange={(e) => setUnitName(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Occupancy Status</label>
                    <select className="form-control" value={unitOcc} onChange={(e) => setUnitOcc(e.target.value)}>
                      <option value="vacant">Vacant</option>
                      <option value="owner_occupied">Owner Occupied</option>
                      <option value="tenant_occupied">Tenant Occupied</option>
                    </select>
                  </div>
                </div>
                <button type="submit" className="btn btn-primary btn-small">Add Portion</button>
              </form>
            </div>
          )}

          <div className="table-responsive">
            <table className="table-custom">
              <thead>
                <tr>
                  <th>Portion Name</th>
                  <th>Occupancy Status</th>
                  <th>Created At</th>
                </tr>
              </thead>
              <tbody>
                {units.map(u => (
                  <tr key={u.id}>
                    <td>{u.unit_name}</td>
                    <td>
                      <span className={`badge ${u.occupancy_status === 'vacant' ? 'badge-status-pending' : u.occupancy_status === 'owner_occupied' ? 'badge-member' : 'badge-tenant'}`}>
                        {u.occupancy_status}
                      </span>
                    </td>
                    <td>{new Date(u.created_at).toLocaleDateString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === 'leases' && (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Lease Tracker</h3>
            <button className="btn btn-primary btn-small" onClick={() => setShowAddTenant(!showAddTenant)}>
              {showAddTenant ? 'Cancel' : 'Register Tenancy'}
            </button>
          </div>

          {showAddTenant && (
            <div className="glass-panel glass-card" style={{ marginBottom: '1.5rem' }}>
              <h4>Register New Tenant</h4>
              <form onSubmit={handleAddTenant} style={{ marginTop: '1rem' }}>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Select Unit/Portion</label>
                    <select className="form-control" value={tenantUnitId} onChange={(e) => setTenantUnitId(e.target.value)} required>
                      <option value="">-- Choose Unit --</option>
                      {units.map(u => (
                        <option key={u.id} value={u.id}>{u.unit_name}</option>
                      ))}
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Select Tenant User</label>
                    <select className="form-control" value={tenantUserId} onChange={(e) => setTenantUserId(e.target.value)} required>
                      <option value="">-- Choose User --</option>
                      {users.filter(u => (Array.isArray(u?.roles) ? u.roles : (u?.role ? [u.role] : [])).includes('tenant')).map(u => (
                        <option key={u.id} value={u.id}>{u.name}</option>
                      ))}
                    </select>
                  </div>
                </div>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Lease Start Date</label>
                    <input type="date" className="form-control" value={tenantStart} onChange={(e) => setTenantStart(e.target.value)} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Lease End Date</label>
                    <input type="date" className="form-control" value={tenantEnd} onChange={(e) => setTenantEnd(e.target.value)} />
                  </div>
                </div>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Number of Occupants</label>
                    <input type="number" min="1" className="form-control" value={tenantCount} onChange={(e) => setTenantCount(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Remarks</label>
                    <input type="text" className="form-control" value={tenantRemarks} onChange={(e) => setTenantRemarks(e.target.value)} />
                  </div>
                </div>
                <button type="submit" className="btn btn-primary btn-small">Create Lease</button>
              </form>
            </div>
          )}

          <div className="table-responsive">
            <table className="table-custom">
              <thead>
                <tr>
                  <th>Unit</th>
                  <th>Tenant Name</th>
                  <th>Lease Period</th>
                  <th>Occupants</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {tenancies.map(t => {
                  const unit = units.find(u => u.id === t.unit_id);
                  return (
                    <tr key={t.id}>
                      <td>{unit ? unit.unit_name : 'Unknown Unit'}</td>
                      <td>{t.tenant_name}</td>
                      <td>{t.start_date} to {t.end_date || 'Active'}</td>
                      <td>{t.occupant_count} residents</td>
                      <td>
                        <span className={`badge ${t.is_active ? 'badge-status-active' : 'badge-status-inactive'}`}>
                          {t.is_active ? 'Active' : 'Closed'}
                        </span>
                      </td>
                      <td>
                        {t.is_active ? (
                          <button className="btn btn-danger btn-small" onClick={() => handleEndTenancy(t.id)}>Terminate Lease</button>
                        ) : (
                          <span style={{ color: 'var(--text-muted)' }}>Historical</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === 'history' && (
        <div>
          <h3>Combined Historical Relationship Log</h3>
          <div className="timeline">
            {relationshipHistory.map((h, i) => (
              <div className="timeline-item" key={i}>
                <div className="timeline-dot" style={{ backgroundColor: h.relationship_type === 'tenant' ? 'var(--role-tenant)' : 'var(--role-member)' }}></div>
                <div className="timeline-content">
                  <div className="timeline-date">{h.start_date} to {h.end_date || 'Present'}</div>
                  <div className="timeline-desc">
                    <strong>{h.user_name}</strong> - Resolved as <span className="badge-role-text">{h.relationship_type.toUpperCase()}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// 5. Billing Manager View (Admin only)
function BillingManagerView({ user, triggerAlert }) {
  const [activeSubTab, setActiveSubTab] = useState('policies'); // policies, generation, ledger, subjects, balances, payments, expenses, reconciliation
  const [policies, setPolicies] = useState([]);
  const [customSubjects, setCustomSubjects] = useState([]);
  const [ledgerTransactions, setLedgerTransactions] = useState([]);
  const [openingBalancesList, setOpeningBalancesList] = useState([]);
  const [propertiesList, setPropertiesList] = useState([]);
  const [usersList, setUsersList] = useState([]);
  
  // Phase 2B additions
  const [maintenanceCharges, setMaintenanceCharges] = useState([]);
  const [paymentsList, setPaymentsList] = useState([]);
  const [receiptsList, setReceiptsList] = useState([]);
  const [paymentAllocationsList, setPaymentAllocationsList] = useState([]);
  
  // Phase 2C additions
  const [expenseCategories, setExpenseCategories] = useState([]);
  const [expenseVouchers, setExpenseVouchers] = useState([]);
  const [budgets, setBudgets] = useState([]);
  const [bankReconciliations, setBankReconciliations] = useState([]);
  
  const [showAddCategory, setShowAddCategory] = useState(false);
  const [categoryName, setCategoryName] = useState('');
  const [categoryDesc, setCategoryDesc] = useState('');

  const [showAddVoucher, setShowAddVoucher] = useState(false);
  const [vCategory, setVCategory] = useState('');
  const [vAmount, setVAmount] = useState('');
  const [vVendorId, setVVendorId] = useState('');
  const [vVendor, setVVendor] = useState('');
  const [vendorsList, setVendorsList] = useState([]);
  const [vInvoiceNum, setVInvoiceNum] = useState('');
  const [vInvoiceDate, setVInvoiceDate] = useState('');
  const [vPaymentMethod, setVPaymentMethod] = useState('upi');
  const [vRefNum, setVRefNum] = useState('');
  const [vDesc, setVDesc] = useState('');
  const [vAttachment, setVAttachment] = useState('');

  const [showAddBudget, setShowAddBudget] = useState(false);
  const [bCategory, setBCategory] = useState('');
  const [bAmount, setBAmount] = useState('');
  const [bStart, setBStart] = useState('');
  const [bEnd, setBEnd] = useState('');

  const [showAddRecon, setShowAddRecon] = useState(false);
  const [rDate, setRDate] = useState('');
  const [rOpenBal, setROpenBal] = useState('');
  const [rCloseBal, setRCloseBal] = useState('');

  const [selectedRecon, setSelectedRecon] = useState(null);
  const [reconcileTxSelection, setReconcileTxSelection] = useState([]); // Array of transaction IDs
  
  const [selectedPayment, setSelectedPayment] = useState(null);
  const [allocationInputs, setAllocationInputs] = useState({}); // charge_id -> amount
  const [showVerifyPanel, setShowVerifyPanel] = useState(false);
  const [showRejectPanel, setShowRejectPanel] = useState(false);
  const [rejectionReason, setRejectionReason] = useState('');
  const [selectedReceipt, setSelectedReceipt] = useState(null);

  // Forms State
  const [showAddPolicy, setShowAddPolicy] = useState(false);
  const [policyFormula, setPolicyFormula] = useState('fixed');
  const [policyRate, setPolicyRate] = useState('');
  const [policyDesc, setPolicyDesc] = useState('');
  const [policyStart, setPolicyStart] = useState('');

  const [billingPeriod, setBillingPeriod] = useState('2026-08');
  const [billingDueDate, setBillingDueDate] = useState('');

  const [showAddSubject, setShowAddSubject] = useState(false);
  const [subjName, setSubjName] = useState('');
  const [subjDesc, setSubjDesc] = useState('');
  const [subjCycle, setSubjCycle] = useState('one_time');
  const [subjAmount, setSubjAmount] = useState('');

  const [showAddResp, setShowAddResp] = useState(false);
  const [respSubjId, setRespSubjId] = useState('');
  const [respPropId, setRespPropId] = useState('');
  const [respUserId, setRespUserId] = useState('');
  const [respType, setRespType] = useState('percentage'); // percentage or amount
  const [respVal, setRespVal] = useState('');
  const [respStart, setRespStart] = useState('');

  const [showAddBalance, setShowAddBalance] = useState(false);
  const [balPropId, setBalPropId] = useState('');
  const [balUserId, setBalUserId] = useState('');
  const [balAmount, setBalAmount] = useState('');
  const [balDirection, setBalDirection] = useState('debit');
  const [balDate, setBalDate] = useState('');

  const [reversalReason, setReversalReason] = useState('');
  const [reversingTxId, setReversingTxId] = useState(null);

  useEffect(() => {
    loadBillingData();
  }, [activeSubTab]);

  const loadBillingData = async () => {
    try {
      if (activeSubTab === 'policies') {
        const list = await db.maintenance_policies.list(user);
        setPolicies(list);
      } else if (activeSubTab === 'generation') {
        const list = await db.maintenance_charges.list(user);
        setMaintenanceCharges(list);
        const props = await db.properties.list(user);
        setPropertiesList(props);
      } else if (activeSubTab === 'ledger') {
        const list = await db.ledger_transactions.list(user);
        const users = await db.users.list(user);
        const props = await db.properties.list(user);
        setLedgerTransactions(list);
        setUsersList(users);
        setPropertiesList(props);
      } else if (activeSubTab === 'subjects') {
        const list = await db.custom_billing_subjects.list(user);
        const props = await db.properties.list(user);
        const users = await db.users.list(user);
        setCustomSubjects(list);
        setPropertiesList(props);
        setUsersList(users);
      } else if (activeSubTab === 'balances') {
        const list = await db.opening_balances.list(user);
        const props = await db.properties.list(user);
        const users = await db.users.list(user);
        setOpeningBalancesList(list);
        setPropertiesList(props);
        setUsersList(users);
      } else if (activeSubTab === 'payments') {
        const pList = await db.payments.list(user);
        const cList = await db.maintenance_charges.list(user);
        const rList = await db.receipts.list(user);
        const uList = await db.users.list(user);
        const props = await db.properties.list(user);
        
        // Load allocations for all verified payments
        let allAllocations = [];
        for (const p of pList) {
          if (p.status === 'verified' || p.status === 'reversed') {
            try {
              const pAllocs = await db.payment_allocations.list(p.id, user);
              allAllocations = [...allAllocations, ...pAllocs];
            } catch (err) {
              // ignore
            }
          }
        }
        
        setPaymentsList(pList);
        setMaintenanceCharges(cList);
        setReceiptsList(rList);
        setPaymentAllocationsList(allAllocations);
        setUsersList(uList);
        setPropertiesList(props);
      } else if (activeSubTab === 'expenses') {
        const cats = await db.expense_categories.list(user);
        const vchs = await db.expense_vouchers.list(user);
        const bdgs = await db.budgets.list(user);
        const vnds = await db.vendors.list(user);
        setExpenseCategories(cats);
        setExpenseVouchers(vchs);
        setBudgets(bdgs);
        setVendorsList(vnds);
      } else if (activeSubTab === 'reconciliation') {
        const recons = await db.bank_reconciliations.list(user);
        const txs = await db.ledger_transactions.list(user);
        setBankReconciliations(recons);
        setLedgerTransactions(txs);
      }
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCreatePolicy = async (e) => {
    e.preventDefault();
    if (!policyRate) return;
    try {
      await db.maintenance_policies.create({
        formula_type: policyFormula,
        rate: policyRate,
        description: policyDesc,
        effective_from: policyStart || undefined
      }, user);
      triggerAlert('success', 'New active maintenance policy deployed.');
      setShowAddPolicy(false);
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleGenerateBills = async (e) => {
    e.preventDefault();
    if (!billingPeriod || !billingDueDate) return;
    try {
      const generated = await db.maintenance_charges.generate(billingPeriod, billingDueDate, user);
      triggerAlert('success', `Billing engine run complete. Generated ${generated} new maintenance bills (duplicates skipped).`);
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCreateSubject = async (e) => {
    e.preventDefault();
    if (!subjName) return;
    try {
      await db.custom_billing_subjects.create({
        name: subjName, description: subjDesc, billing_cycle: subjCycle, default_amount: subjAmount
      }, user);
      triggerAlert('success', 'Custom billing subject registered.');
      setShowAddSubject(false);
      setSubjName(''); setSubjDesc('');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCreateResp = async (e) => {
    e.preventDefault();
    if (!respSubjId || !respPropId || !respUserId || !respVal) return;
    try {
      await db.custom_billing_responsibilities.create({
        custom_subject_id: respSubjId,
        property_id: respPropId,
        user_id: respUserId,
        share_percentage: respType === 'percentage' ? respVal : null,
        share_amount: respType === 'amount' ? respVal : null,
        start_date: respStart || new Date().toISOString().split('T')[0]
      }, user);
      triggerAlert('success', 'Custom responsibility mapped.');
      setShowAddResp(false);
      setRespVal('');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleRecordBalance = async (e) => {
    e.preventDefault();
    if (!balPropId || !balUserId || !balAmount) return;
    try {
      await db.opening_balances.create({
        property_id: balPropId,
        user_id: balUserId,
        amount: balAmount,
        direction: balDirection,
        as_of_date: balDate || new Date().toISOString().split('T')[0]
      }, user);
      triggerAlert('success', 'Opening balance registered and booked in sub-ledger.');
      setShowAddBalance(false);
      setBalAmount('');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleReverseLedger = async (e) => {
    e.preventDefault();
    if (!reversingTxId || !reversalReason) return;
    try {
      await db.ledger_transactions.reverse(reversingTxId, reversalReason, user);
      triggerAlert('success', 'Ledger transaction successfully reversed.');
      setReversingTxId(null);
      setReversalReason('');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleAddCategory = async (e) => {
    e.preventDefault();
    if (!categoryName) return;
    try {
      await db.expense_categories.create({
        name: categoryName,
        description: categoryDesc,
        society_id: db_helpers.get_user_society_id(user)
      }, user);
      triggerAlert('success', 'Expense category added successfully.');
      setShowAddCategory(false);
      setCategoryName('');
      setCategoryDesc('');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleAddBudget = async (e) => {
    e.preventDefault();
    if (!bCategory || !bAmount || !bStart || !bEnd) return;
    try {
      await db.budgets.create({
        category_id: bCategory,
        allocated_amount: bAmount,
        start_date: bStart,
        end_date: bEnd,
        society_id: db_helpers.get_user_society_id(user)
      }, user);
      triggerAlert('success', 'Budget allocated successfully.');
      setShowAddBudget(false);
      setBCategory('');
      setBAmount('');
      setBStart('');
      setBEnd('');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleAddRecon = async (e) => {
    e.preventDefault();
    if (!rDate || rOpenBal === '' || rCloseBal === '') return;
    try {
      await db.bank_reconciliations.create({
        bank_statement_date: rDate,
        opening_balance: rOpenBal,
        closing_balance: rCloseBal,
        society_id: db_helpers.get_user_society_id(user)
      }, user);
      triggerAlert('success', 'Bank reconciliation statement created.');
      setShowAddRecon(false);
      setRDate('');
      setROpenBal('');
      setRCloseBal('');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCompleteRecon = async (reconId) => {
    if (!reconId || !selectedRecon) return;
    if (selectedRecon.id !== reconId) return;
    if (selectedRecon.status !== 'draft') {
      triggerAlert('danger', 'Cannot complete: Statement is not in draft status.');
      return;
    }
    if (user?.society_id && selectedRecon.society_id && selectedRecon.society_id !== user.society_id) {
      triggerAlert('danger', 'Access Denied: BRS statement belongs to another society.');
      return;
    }
    try {
      await db.bank_reconciliations.complete(reconId, user);
      triggerAlert('success', 'BRS statement completed and locked.');
      setSelectedRecon(prev => prev ? { ...prev, status: 'completed' } : null);
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleMatchTransactions = async (reconId) => {
    if (!reconId || !selectedRecon || reconcileTxSelection.length === 0) return;
    if (selectedRecon.status !== 'draft') {
      triggerAlert('danger', 'Cannot match transactions to a completed BRS statement.');
      return;
    }
    try {
      await db.bank_reconciliations.reconcile(reconId, reconcileTxSelection, user);
      triggerAlert('success', `${reconcileTxSelection.length} transaction(s) matched to BRS statement.`);
      setReconcileTxSelection([]);
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleAddVoucher = async (e) => {
    e.preventDefault();
    if (!vCategory || !vAmount || !vVendor) return;
    try {
      await db.expense_vouchers.create({
        category_id: vCategory,
        amount: vAmount,
        vendor_id: vVendorId || null,
        vendor_name: vVendor,
        invoice_number: vInvoiceNum,
        invoice_date: vInvoiceDate,
        payment_method: vPaymentMethod,
        reference_number: vRefNum,
        attachment_url: vAttachment,
        description: vDesc,
        society_id: db_helpers.get_user_society_id(user)
      }, user);
      triggerAlert('success', 'Expense voucher registered and queued for approval.');
      setShowAddVoucher(false);
      setVCategory(''); setVAmount(''); setVVendorId(''); setVVendor(''); setVInvoiceNum(''); setVInvoiceDate(''); setVRefNum(''); setVDesc(''); setVAttachment('');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleApproveVoucher = async (voucherId) => {
    try {
      await db.expense_vouchers.approve(voucherId, user);
      triggerAlert('success', 'Expense voucher approved successfully.');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleRejectVoucher = async (voucherId) => {
    const reason = window.prompt('Enter reason for rejecting this expense voucher:');
    if (!reason || !reason.trim()) return;
    try {
      await db.expense_vouchers.reject(voucherId, reason.trim(), user);
      triggerAlert('warning', 'Expense voucher rejected.');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handlePostVoucher = async (voucherId) => {
    try {
      await db.expense_vouchers.post(voucherId, user);
      triggerAlert('success', 'Expense voucher disbursed and posted to financial sub-ledger.');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleReverseExpenseVoucher = async (voucherId) => {
    const reason = window.prompt('Enter reason for reversing this expense voucher:');
    if (!reason || !reason.trim()) return;
    try {
      await db.expense_vouchers.reverse(voucherId, reason.trim(), user);
      triggerAlert('warning', 'Expense voucher reversed and compensating sub-ledger entry posted.');
      loadBillingData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  return (
    <div>
      <h2>Billing & Financial Sub-Ledger Manager</h2>
      <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '1.5rem' }}>
        Versioned maintenance policies, custom billing mappings, and two append-only sub-ledgers auditing
      </p>

      {/* Sub tabs */}
      <div className="tabs-container" style={{ gap: '1rem', borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
        <button className={`tab-btn ${activeSubTab === 'policies' ? 'active' : ''}`} style={{ fontSize: '0.9rem' }} onClick={() => setActiveSubTab('policies')}>Maintenance Policies</button>
        <button className={`tab-btn ${activeSubTab === 'generation' ? 'active' : ''}`} style={{ fontSize: '0.9rem' }} onClick={() => setActiveSubTab('generation')}>Billing Engine</button>
        <button className={`tab-btn ${activeSubTab === 'ledger' ? 'active' : ''}`} style={{ fontSize: '0.9rem' }} onClick={() => setActiveSubTab('ledger')}>General Ledgers</button>
        <button className={`tab-btn ${activeSubTab === 'subjects' ? 'active' : ''}`} style={{ fontSize: '0.9rem' }} onClick={() => setActiveSubTab('subjects')}>Custom Billing</button>
        <button className={`tab-btn ${activeSubTab === 'balances' ? 'active' : ''}`} style={{ fontSize: '0.9rem' }} onClick={() => setActiveSubTab('balances')}>Opening Balances</button>
        <button className={`tab-btn ${activeSubTab === 'payments' ? 'active' : ''}`} style={{ fontSize: '0.9rem' }} onClick={() => setActiveSubTab('payments')}>Payments Verification</button>
        <button className={`tab-btn ${activeSubTab === 'expenses' ? 'active' : ''}`} style={{ fontSize: '0.9rem' }} onClick={() => setActiveSubTab('expenses')}>Expense Manager</button>
        <button className={`tab-btn ${activeSubTab === 'reconciliation' ? 'active' : ''}`} style={{ fontSize: '0.9rem' }} onClick={() => setActiveSubTab('reconciliation')}>Bank Reconciliation (BRS)</button>
      </div>

      {/* Policies sub-tab */}
      {activeSubTab === 'policies' && (
        <div style={{ marginTop: '1.5rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Maintenance Policies Setup</h3>
            <button className="btn btn-primary btn-small" onClick={() => setShowAddPolicy(!showAddPolicy)}>
              {showAddPolicy ? 'Cancel' : 'Create Policy'}
            </button>
          </div>

          {showAddPolicy && (
            <div className="glass-panel glass-card" style={{ marginBottom: '1.5rem' }}>
              <h4>Deploy Maintenance Policy</h4>
              <form onSubmit={handleCreatePolicy} style={{ marginTop: '1rem' }}>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Billing Formula</label>
                    <select className="form-control" value={policyFormula} onChange={(e) => setPolicyFormula(e.target.value)}>
                      <option value="fixed">Fixed Flat Monthly Charge</option>
                      <option value="per_sqft">Rate per Plot Sq.Ft.</option>
                      <option value="per_plot">Flat Rate per Plot</option>
                      <option value="per_unit">Rate per portion/unit</option>
                      <option value="per_family">Rate per residing family</option>
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Rate / Charge Value (₹) *</label>
                    <input type="number" min="0" className="form-control" placeholder="e.g. 1500" value={policyRate} onChange={(e) => setPolicyRate(e.target.value)} required />
                  </div>
                </div>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Effective From Date</label>
                    <input type="date" className="form-control" value={policyStart} onChange={(e) => setPolicyStart(e.target.value)} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Description / Remarks</label>
                    <input type="text" className="form-control" placeholder="e.g. Standard 2026 tariff plan" value={policyDesc} onChange={(e) => setPolicyDesc(e.target.value)} />
                  </div>
                </div>
                <button type="submit" className="btn btn-primary btn-small" style={{ marginTop: '0.5rem' }}>Deploy Active Policy</button>
              </form>
            </div>
          )}

          <div className="table-responsive">
            <table className="table-custom">
              <thead>
                <tr>
                  <th>Version</th>
                  <th>Formula</th>
                  <th>Rate</th>
                  <th>Effective From</th>
                  <th>Status</th>
                  <th>Description</th>
                </tr>
              </thead>
              <tbody>
                {policies.map(p => (
                  <tr key={p.id}>
                    <td>v{p.version}</td>
                    <td><code>{p.formula_type.toUpperCase()}</code></td>
                    <td>₹{p.rate}</td>
                    <td>{p.effective_from}</td>
                    <td>
                      <span className={`badge ${p.is_active ? 'badge-status-active' : 'badge-status-inactive'}`}>
                        {p.is_active ? 'Active' : 'Superseded'}
                      </span>
                    </td>
                    <td>{p.description}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Billing engine runner */}
      {activeSubTab === 'generation' && (
        <div style={{ marginTop: '1.5rem' }}>
          <div className="glass-panel glass-card" style={{ marginBottom: '2.5rem' }}>
            <h3>Billing Engine / Charge Generator</h3>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.8rem', marginBottom: '1.25rem' }}>
              Run batch billing process to generate charges for all active properties and post entries to sub-ledgers.
            </p>

            <form onSubmit={handleGenerateBills} style={{ display: 'flex', gap: '1rem', alignItems: 'flex-end', flexWrap: 'wrap' }}>
              <div className="form-group" style={{ width: '180px' }}>
                <label className="form-label">Billing Period</label>
                <input type="text" className="form-control" placeholder="YYYY-MM (e.g. 2026-08)" value={billingPeriod} onChange={(e) => setBillingPeriod(e.target.value)} required />
              </div>
              <div className="form-group" style={{ width: '180px' }}>
                <label className="form-label">Due Date</label>
                <input type="date" className="form-control" value={billingDueDate} onChange={(e) => setBillingDueDate(e.target.value)} required />
              </div>
              <button type="submit" className="btn btn-primary" style={{ height: '42px', marginBottom: '1.25rem' }}>Run Charge Generator</button>
            </form>
          </div>

          <h3>Generated Dues / Maintenance Charges History</h3>
          <div className="table-responsive">
            <table className="table-custom">
              <thead>
                <tr>
                  <th>Property</th>
                  <th>Billing Subject</th>
                  <th>Period</th>
                  <th>Amount</th>
                  <th>Due Date</th>
                  <th>Billing Basis Snapshot</th>
                </tr>
              </thead>
              <tbody>
                {maintenanceCharges.map(mc => {
                  const prop = propertiesList.find(p => p.id === mc.property_id);
                  return (
                    <tr key={mc.id}>
                      <td><strong>{prop ? prop.plot_number : 'Unknown'}</strong></td>
                      <td><span className="badge badge-member">{mc.billing_subject_type}</span></td>
                      <td>{mc.billing_period}</td>
                      <td>₹{mc.amount}</td>
                      <td>{mc.due_date}</td>
                      <td style={{ fontSize: '0.75rem', fontFamily: 'monospace', color: 'var(--text-secondary)' }}>
                        {JSON.stringify(mc.billing_basis_snapshot)}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Ledger statement list */}
      {activeSubTab === 'ledger' && (
        <div style={{ marginTop: '1.5rem' }}>
          {reversingTxId && (
            <div className="glass-panel glass-card" style={{ marginBottom: '2rem', border: '1px solid var(--color-error)' }}>
              <h3 style={{ color: 'var(--color-error)' }}>Sub-ledger Reversal Action</h3>
              <form onSubmit={handleReverseLedger} style={{ marginTop: '1rem' }}>
                <p style={{ fontSize: '0.85rem', marginBottom: '1rem' }}>
                  You are reversing ledger transaction ID: <code>{reversingTxId}</code>. This will insert an opposite compensating transaction.
                </p>
                <div className="form-group">
                  <label className="form-label">Reason for Reversal *</label>
                  <input type="text" className="form-control" placeholder="e.g. Correcting error..." value={reversalReason} onChange={(e) => setReversalReason(e.target.value)} required />
                </div>
                <div style={{ display: 'flex', gap: '0.5rem' }}>
                  <button type="submit" className="btn btn-danger btn-small">Confirm Reversal</button>
                  <button type="button" className="btn btn-secondary btn-small" onClick={() => setReversingTxId(null)}>Cancel</button>
                </div>
              </form>
            </div>
          )}

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Welfare Association Ledgers Statement</h3>
            <span className="badge badge-treasurer">APPEND-ONLY SUB-LEDGERS</span>
          </div>

          <div className="table-responsive">
            <table className="table-custom">
              <thead>
                <tr>
                  <th>Timestamp</th>
                  <th>Sub-Ledger Scope</th>
                  <th>Member / Prop</th>
                  <th>Type</th>
                  <th>Debit (Dr)</th>
                  <th>Credit (Cr)</th>
                  <th>Description</th>
                  <th>Created By</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {ledgerTransactions.map(tx => {
                  const u = usersList.find(usr => usr.id === tx.user_id);
                  const prop = propertiesList.find(p => p.id === tx.property_id);
                  const creator = usersList.find(usr => usr.id === tx.created_by);
                  return (
                    <tr key={tx.id} style={{ borderLeft: tx.transaction_type === 'reversal' ? '3px solid var(--color-error)' : 'none' }}>
                      <td>{new Date(tx.created_at).toLocaleDateString()}</td>
                      <td><span className="badge badge-secondary" style={{ fontSize: '0.65rem' }}>{tx.scope === 'member' ? 'Member Subsidiary' : 'Society Cash/Bank'}</span></td>
                      <td>
                        {tx.scope === 'member' ? (
                          <div>
                            <strong>{prop ? prop.plot_number : ''}</strong>
                            <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>{u ? u.name : ''}</div>
                          </div>
                        ) : 'Society Pool'}
                      </td>
                      <td>
                        <span className={`badge ${tx.direction === 'debit' ? 'badge-super_admin' : 'badge-member'}`} style={{ fontSize: '0.65rem' }}>
                          {tx.transaction_type}
                        </span>
                      </td>
                      <td style={{ color: tx.direction === 'debit' ? 'var(--color-error)' : 'inherit', fontWeight: tx.direction === 'debit' ? 'bold' : 'normal' }}>
                        {tx.direction === 'debit' ? `₹${tx.amount}` : '-'}
                      </td>
                      <td style={{ color: tx.direction === 'credit' ? 'var(--color-success)' : 'inherit', fontWeight: tx.direction === 'credit' ? 'bold' : 'normal' }}>
                        {tx.direction === 'credit' ? `₹${tx.amount}` : '-'}
                      </td>
                      <td>{tx.description}</td>
                      <td>{creator ? creator.name.split(' ')[0] : 'Admin'}</td>
                      <td>
                        {tx.transaction_type !== 'reversal' && (
                          <button className="btn btn-danger btn-small" style={{ fontSize: '0.7rem', padding: '0.2rem 0.5rem' }} onClick={() => setReversingTxId(tx.id)}>
                            Reverse
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Custom billing */}
      {activeSubTab === 'subjects' && (
        <div style={{ marginTop: '1.5rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
            <h3>Custom Billing Subjects</h3>
            <button className="btn btn-primary btn-small" onClick={() => setShowAddSubject(!showAddSubject)}>
              {showAddSubject ? 'Cancel' : 'Create Billing Subject'}
            </button>
          </div>

          {showAddSubject && (
            <div className="glass-panel glass-card" style={{ marginBottom: '2rem' }}>
              <h4>Register Custom Subject</h4>
              <form onSubmit={handleCreateSubject} style={{ marginTop: '1rem' }}>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Subject Name *</label>
                    <input type="text" className="form-control" placeholder="e.g. Festival Contribution" value={subjName} onChange={(e) => setSubjName(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Billing Cycle</label>
                    <select className="form-control" value={subjCycle} onChange={(e) => setSubjCycle(e.target.value)}>
                      <option value="one_time">One-Time Dues</option>
                      <option value="monthly">Monthly Recurring</option>
                      <option value="annual">Annual Recurring</option>
                    </select>
                  </div>
                </div>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Default Amount (₹)</label>
                    <input type="number" className="form-control" placeholder="e.g. 1000" value={subjAmount} onChange={(e) => setSubjAmount(e.target.value)} />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Description / Remarks</label>
                    <input type="text" className="form-control" value={subjDesc} onChange={(e) => setSubjDesc(e.target.value)} />
                  </div>
                </div>
                <button type="submit" className="btn btn-primary btn-small" style={{ marginTop: '0.5rem' }}>Register Subject</button>
              </form>
            </div>
          )}

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '1rem' }}>
            {customSubjects.map(s => (
              <div className="glass-panel glass-card" key={s.id}>
                <h4 style={{ color: 'var(--primary-hover)' }}>{s.name}</h4>
                <div className="detail-list" style={{ marginTop: '0.5rem', marginBottom: '1rem', fontSize: '0.85rem' }}>
                  <div className="detail-row"><span className="detail-label">Cycle</span><span className="detail-value">{s.billing_cycle}</span></div>
                  <div className="detail-row"><span className="detail-label">Default Dues</span><span className="detail-value">₹{s.default_amount}</span></div>
                </div>
                <button className="btn btn-secondary btn-full btn-small" onClick={async () => {
                  setRespSubjId(s.id);
                  setShowAddResp(true);
                }}>
                  Map Custom Responsibility
                </button>
              </div>
            ))}
          </div>

          {showAddResp && (
            <div className="glass-panel glass-card" style={{ marginTop: '2rem' }}>
              <h4>Map Custom Billing Responsibility</h4>
              <form onSubmit={handleCreateResp} style={{ marginTop: '1.25rem' }}>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Billing Subject</label>
                    <select className="form-control" value={respSubjId} onChange={(e) => setRespSubjId(e.target.value)} required>
                      <option value="">-- Choose Subject --</option>
                      {customSubjects.map(s => <option key={s.id} value={s.id}>{s.name}</option>)}
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Property Plot</label>
                    <select className="form-control" value={respPropId} onChange={(e) => setRespPropId(e.target.value)} required>
                      <option value="">-- Choose Plot --</option>
                      {propertiesList.map(p => <option key={p.id} value={p.id}>{p.plot_number}</option>)}
                    </select>
                  </div>
                </div>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Responsible User</label>
                    <select className="form-control" value={respUserId} onChange={(e) => setRespUserId(e.target.value)} required>
                      <option value="">-- Choose User --</option>
                      {usersList.filter(u => (Array.isArray(u?.roles) ? u.roles : (u?.role ? [u.role] : [])).includes('member')).map(u => (
                        <option key={u.id} value={u.id}>{u.name}</option>
                      ))}
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Share Criteria Type</label>
                    <select className="form-control" value={respType} onChange={(e) => setRespType(e.target.value)}>
                      <option value="percentage">Percentage Share (%)</option>
                      <option value="amount">Flat Fixed Share Amount (₹)</option>
                    </select>
                  </div>
                </div>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Share Value *</label>
                    <input type="number" min="1" className="form-control" placeholder={respType === 'percentage' ? 'e.g. 100' : 'e.g. 500'} value={respVal} onChange={(e) => setRespVal(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Effective Start Date</label>
                    <input type="date" className="form-control" value={respStart} onChange={(e) => setRespStart(e.target.value)} />
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '0.5rem', marginTop: '1rem' }}>
                  <button type="submit" className="btn btn-primary btn-small">Save Mapping</button>
                  <button type="button" className="btn btn-secondary btn-small" onClick={() => setShowAddResp(false)}>Cancel</button>
                </div>
              </form>
            </div>
          )}
        </div>
      )}

      {/* Opening balances sub-tab */}
      {activeSubTab === 'balances' && (
        <div style={{ marginTop: '1.5rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Members Opening Balances Registry</h3>
            <button className="btn btn-primary btn-small" onClick={() => setShowAddBalance(!showAddBalance)}>
              {showAddBalance ? 'Cancel' : 'Record Opening Balance'}
            </button>
          </div>

          {showAddBalance && (
            <div className="glass-panel glass-card" style={{ marginBottom: '1.5rem' }}>
              <h4>Add Opening Balance</h4>
              <form onSubmit={handleRecordBalance} style={{ marginTop: '1rem' }}>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Select Plot</label>
                    <select className="form-control" value={balPropId} onChange={(e) => setBalPropId(e.target.value)} required>
                      <option value="">-- Choose Plot --</option>
                      {propertiesList.map(p => <option key={p.id} value={p.id}>{p.plot_number}</option>)}
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label">Select Member</label>
                    <select className="form-control" value={balUserId} onChange={(e) => setBalUserId(e.target.value)} required>
                      <option value="">-- Choose Member --</option>
                      {usersList.filter(u => (Array.isArray(u?.roles) ? u.roles : (u?.role ? [u.role] : [])).includes('member')).map(u => (
                        <option key={u.id} value={u.id}>{u.name}</option>
                      ))}
                    </select>
                  </div>
                </div>
                <div className="grid-2">
                  <div className="form-group">
                    <label className="form-label">Opening Amount (₹) *</label>
                    <input type="number" min="0" className="form-control" value={balAmount} onChange={(e) => setBalAmount(e.target.value)} required />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Balance Direction</label>
                    <select className="form-control" value={balDirection} onChange={(e) => setBalDirection(e.target.value)}>
                      <option value="debit">Debit (Member Owes Dues)</option>
                      <option value="credit">Credit (Member in Advance)</option>
                    </select>
                  </div>
                </div>
                <div className="form-group">
                  <label className="form-label">As of Date</label>
                  <input type="date" className="form-control" value={balDate} onChange={(e) => setBalDate(e.target.value)} />
                </div>
                <button type="submit" className="btn btn-primary btn-small">Confirm opening balance</button>
              </form>
            </div>
          )}

          <div className="table-responsive">
            <table className="table-custom">
              <thead>
                <tr>
                  <th>Property</th>
                  <th>Member Name</th>
                  <th>Amount</th>
                  <th>Balance State</th>
                  <th>As of Date</th>
                </tr>
              </thead>
              <tbody>
                {openingBalancesList.map(ob => {
                  const prop = propertiesList.find(p => p.id === ob.property_id);
                  const u = usersList.find(usr => usr.id === ob.user_id);
                  return (
                    <tr key={ob.id}>
                      <td><strong>{prop ? prop.plot_number : ''}</strong></td>
                      <td>{u ? u.name : ''}</td>
                      <td>₹{ob.amount}</td>
                      <td>
                        <span className={`badge ${ob.direction === 'debit' ? 'badge-super_admin' : 'badge-member'}`}>
                          {ob.direction === 'debit' ? 'OWES DUES (DR)' : 'IN ADVANCE (CR)'}
                        </span>
                      </td>
                      <td>{ob.as_of_date}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Payments Verification sub-tab */}
      {activeSubTab === 'payments' && (
        <div style={{ marginTop: '1.5rem' }}>
          <h3>Member Payments Verification Desk</h3>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '1.5rem' }}>
            Review, allocate, verify, reject, or reverse payment submissions from residential members.
          </p>

          {/* Pending Payment verification panel */}
          {showVerifyPanel && selectedPayment && (
            <div className="glass-panel glass-card animate-fade-in" style={{ marginBottom: '2rem', border: '1px solid var(--primary)', padding: '1.5rem' }}>
              <h3 style={{ color: 'var(--primary-hover)', marginBottom: '1rem' }}>Verify & Allocate Payment</h3>
              <div style={{ margin: '1rem 0', fontSize: '0.9rem' }}>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', background: 'rgba(255,255,255,0.02)', padding: '1rem', borderRadius: '4px' }}>
                  <div><strong>Plot/Property:</strong> {propertiesList.find(p => p.id === selectedPayment.property_id)?.plot_number}</div>
                  <div><strong>Payer Member:</strong> {usersList.find(u => u.id === selectedPayment.user_id)?.name}</div>
                  <div><strong>Amount Received:</strong> <span style={{ color: 'var(--color-success)', fontWeight: 'bold' }}>₹{selectedPayment.amount}</span></div>
                  <div><strong>Method & Ref:</strong> {selectedPayment.payment_method.toUpperCase()} ({selectedPayment.reference_number})</div>
                </div>
              </div>

              <h4>Select charges to allocate this payment against:</h4>
              <div className="table-responsive" style={{ margin: '1rem 0' }}>
                <table className="table-custom">
                  <thead>
                    <tr>
                      <th>Billing Period</th>
                      <th>Subject / Type</th>
                      <th>Total Charge</th>
                      <th>Outstanding Dues</th>
                      <th>Allocate Amount (₹)</th>
                    </tr>
                  </thead>
                  <tbody>
                    {maintenanceCharges
                      .filter(c => c.property_id === selectedPayment.property_id)
                      .map(c => {
                        const allocated = paymentAllocationsList
                          .filter(pa => pa.charge_id === c.id)
                          .reduce((sum, pa) => sum + pa.amount, 0);
                        const outstanding = c.amount - allocated;
                        
                        if (outstanding <= 0) return null;

                        return (
                          <tr key={c.id}>
                            <td>{c.billing_period}</td>
                            <td>{c.billing_subject_type.toUpperCase()}</td>
                            <td>₹{c.amount}</td>
                            <td><strong style={{ color: 'var(--color-error)' }}>₹{outstanding}</strong></td>
                            <td>
                              <input 
                                type="number" 
                                className="form-control" 
                                style={{ width: '120px', padding: '0.25rem' }}
                                min="0"
                                max={outstanding}
                                value={allocationInputs[c.id] || ''}
                                onChange={(e) => {
                                  const val = e.target.value === '' ? 0 : Number(e.target.value);
                                  setAllocationInputs({
                                    ...allocationInputs,
                                    [c.id]: Math.min(val, outstanding)
                                  });
                                }}
                              />
                            </td>
                          </tr>
                        );
                      })}
                  </tbody>
                </table>
              </div>

              {(() => {
                const totalAlloc = Object.values(allocationInputs).reduce((sum, v) => sum + (Number(v) || 0), 0);
                const advanceAmt = selectedPayment.amount - totalAlloc;
                return (
                  <div style={{ padding: '1rem', background: 'rgba(255,255,255,0.02)', borderRadius: '4px', marginBottom: '1.5rem' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.5rem' }}>
                      <span>Total Allocated:</span>
                      <strong>₹{totalAlloc}</strong>
                    </div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', color: advanceAmt >= 0 ? 'var(--color-success)' : 'var(--color-error)' }}>
                      <span>Remaining (credited as Member Advance):</span>
                      <strong>₹{advanceAmt >= 0 ? advanceAmt : 0}</strong>
                    </div>
                    {advanceAmt < 0 && (
                      <div style={{ color: 'var(--color-error)', fontSize: '0.8rem', marginTop: '0.5rem' }}>
                        ⚠️ Warning: Total allocations exceed the payment amount. Please reduce allocation inputs.
                      </div>
                    )}
                  </div>
                );
              })()}

              <div style={{ display: 'flex', gap: '0.5rem' }}>
                <button 
                  className="btn btn-primary" 
                  disabled={Object.values(allocationInputs).reduce((sum, v) => sum + (Number(v) || 0), 0) > selectedPayment.amount}
                  onClick={async () => {
                    try {
                      const payload = Object.entries(allocationInputs)
                        .filter(([_, amt]) => Number(amt) > 0)
                        .map(([cid, amt]) => ({ charge_id: cid, amount: Number(amt) }));
                      
                      await db.payments.verify(selectedPayment.id, payload, user);
                      triggerAlert('success', 'Payment verified successfully and ledger records posted.');
                      setShowVerifyPanel(false);
                      setSelectedPayment(null);
                      setAllocationInputs({});
                      loadBillingData();
                    } catch (err) {
                      triggerAlert('danger', err.message);
                    }
                  }}
                >
                  Confirm & Post Verification
                </button>
                <button className="btn btn-secondary" onClick={() => { setShowVerifyPanel(false); setSelectedPayment(null); setAllocationInputs({}); }}>
                  Cancel
                </button>
              </div>
            </div>
          )}

          {/* Rejection Panel */}
          {showRejectPanel && selectedPayment && (
            <div className="glass-panel glass-card animate-fade-in" style={{ marginBottom: '2rem', border: '1px solid var(--color-error)' }}>
              <h3 style={{ color: 'var(--color-error)' }}>Reject Member Payment Slip</h3>
              <form onSubmit={async (e) => {
                e.preventDefault();
                if (!rejectionReason) return;
                try {
                  await db.payments.reject(selectedPayment.id, rejectionReason, user);
                  triggerAlert('warning', 'Payment submission rejected. Notification sent to member.');
                  setShowRejectPanel(false);
                  setSelectedPayment(null);
                  setRejectionReason('');
                  loadBillingData();
                } catch (err) {
                  triggerAlert('danger', err.message);
                }
              }} style={{ marginTop: '1rem' }}>
                <div className="form-group">
                  <label className="form-label">Reason for Rejection *</label>
                  <input 
                    type="text" 
                    className="form-control" 
                    placeholder="e.g. Reference number doesn't match bank record..." 
                    value={rejectionReason}
                    onChange={(e) => setRejectionReason(e.target.value)}
                    required
                  />
                </div>
                <div style={{ display: 'flex', gap: '0.5rem' }}>
                  <button type="submit" className="btn btn-danger btn-small">Confirm Rejection</button>
                  <button type="button" className="btn btn-secondary btn-small" onClick={() => { setShowRejectPanel(false); setSelectedPayment(null); setRejectionReason(''); }}>Cancel</button>
                </div>
              </form>
            </div>
          )}

          {/* Reversal Panel */}
          {reversingTxId && selectedPayment && (
            <div className="glass-panel glass-card animate-fade-in" style={{ marginBottom: '2rem', border: '1px solid var(--color-error)' }}>
              <h3 style={{ color: 'var(--color-error)' }}>Reverse Processed Payment</h3>
              <form onSubmit={async (e) => {
                e.preventDefault();
                if (!reversalReason) return;
                try {
                  await db.payments.reverse(selectedPayment.id, reversalReason, user);
                  triggerAlert('success', 'Payment reversed. Compensating sub-ledger entries booked.');
                  setReversingTxId(null);
                  setSelectedPayment(null);
                  setReversalReason('');
                  loadBillingData();
                } catch (err) {
                  triggerAlert('danger', err.message);
                }
              }} style={{ marginTop: '1rem' }}>
                <div className="form-group">
                  <label className="form-label">Reason for Reversal *</label>
                  <input 
                    type="text" 
                    className="form-control" 
                    placeholder="e.g. Bank bounced payment, dispute..." 
                    value={reversalReason}
                    onChange={(e) => setReversalReason(e.target.value)}
                    required
                  />
                </div>
                <div style={{ display: 'flex', gap: '0.5rem' }}>
                  <button type="submit" className="btn btn-danger btn-small">Confirm Reversal</button>
                  <button type="button" className="btn btn-secondary btn-small" onClick={() => { setReversingTxId(null); setSelectedPayment(null); setReversalReason(''); }}>Cancel</button>
                </div>
              </form>
            </div>
          )}

          <div className="table-responsive">
            <table className="table-custom">
              <thead>
                <tr>
                  <th>Date</th>
                  <th>Plot</th>
                  <th>Payer</th>
                  <th>Method</th>
                  <th>Amount</th>
                  <th>Ref Number</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {paymentsList.map(p => {
                  const prop = propertiesList.find(pr => pr.id === p.property_id);
                  const u = usersList.find(usr => usr.id === p.user_id);
                  return (
                    <tr key={p.id}>
                      <td>{new Date(p.created_at).toLocaleDateString()}</td>
                      <td><strong>{prop ? prop.plot_number : 'Unknown'}</strong></td>
                      <td>{u ? u.name : 'Unknown'}</td>
                      <td><code>{p.payment_method.toUpperCase()}</code></td>
                      <td><span style={{ fontWeight: 'bold' }}>₹{p.amount}</span></td>
                      <td><code>{p.reference_number}</code></td>
                      <td>
                        <span className={`badge ${
                          p.status === 'pending_verification' ? 'badge-status-pending' :
                          p.status === 'verified' ? 'badge-status-active' :
                          p.status === 'rejected' ? 'badge-status-inactive' : 'badge-status-inactive'
                        }`} style={{ background: p.status === 'rejected' ? 'var(--color-error)' : p.status === 'reversed' ? 'rgba(255,255,255,0.1)' : '' }}>
                          {p.status.toUpperCase()}
                        </span>
                      </td>
                      <td>
                        <div style={{ display: 'flex', gap: '0.25rem' }}>
                          {p.status === 'pending_verification' && (
                            <>
                              <button 
                                className="btn btn-primary btn-small" 
                                style={{ padding: '0.2rem 0.5rem', fontSize: '0.7rem' }}
                                onClick={() => {
                                  setSelectedPayment(p);
                                  const propCharges = maintenanceCharges
                                    .filter(c => c.property_id === p.property_id)
                                    .sort((a, b) => a.due_date.localeCompare(b.due_date));
                                  
                                  let remaining = p.amount;
                                  const autoAllocs = {};
                                  for (const c of propCharges) {
                                    const allocated = paymentAllocationsList
                                      .filter(pa => pa.charge_id === c.id)
                                      .reduce((sum, pa) => sum + pa.amount, 0);
                                    const outstanding = c.amount - allocated;
                                    
                                    if (outstanding > 0) {
                                      const allocAmt = Math.min(remaining, outstanding);
                                      autoAllocs[c.id] = allocAmt;
                                      remaining -= allocAmt;
                                    }
                                  }
                                  setAllocationInputs(autoAllocs);
                                  setShowVerifyPanel(true);
                                  setShowRejectPanel(false);
                                  setReversingTxId(null);
                                }}
                              >
                                Verify
                              </button>
                              <button 
                                className="btn btn-secondary btn-small" 
                                style={{ padding: '0.2rem 0.5rem', fontSize: '0.7rem', color: 'var(--color-error)' }}
                                onClick={() => {
                                  setSelectedPayment(p);
                                  setShowRejectPanel(true);
                                  setShowVerifyPanel(false);
                                  setReversingTxId(null);
                                }}
                              >
                                Reject
                              </button>
                            </>
                          )}
                          {p.status === 'verified' && (
                            <>
                              <button 
                                className="btn btn-secondary btn-small" 
                                style={{ padding: '0.2rem 0.5rem', fontSize: '0.7rem' }}
                                onClick={() => {
                                  const rc = receiptsList.find(r => r.payment_id === p.id);
                                  if (rc) setSelectedReceipt(rc);
                                }}
                              >
                                View Receipt
                              </button>
                              <button 
                                className="btn btn-danger btn-small" 
                                style={{ padding: '0.2rem 0.5rem', fontSize: '0.7rem' }}
                                onClick={() => {
                                  setSelectedPayment(p);
                                  setReversingTxId(p.id);
                                  setShowVerifyPanel(false);
                                  setShowRejectPanel(false);
                                }}
                              >
                                Reverse
                              </button>
                            </>
                          )}
                          {p.status === 'reversed' && (
                            <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>Reversed</span>
                          )}
                          {p.status === 'rejected' && (
                            <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>Rejected</span>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
                {paymentsList.length === 0 && (
                  <tr><td colSpan="8" style={{ textAlign: 'center', color: 'var(--text-muted)' }}>No member payments submitted.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Receipts Modal Overlay */}
      {selectedReceipt && (
        <div className="modal-backdrop animate-fade-in" style={{ position: 'fixed', top: 0, left: 0, width: '100%', height: '100%', background: 'rgba(0,0,0,0.8)', display: 'flex', justifyContent: 'center', alignItems: 'center', zIndex: 1000, padding: '1rem' }}>
          <div className="glass-panel glass-card receipt-card" style={{ maxWidth: '500px', width: '100%', padding: '2rem', border: '1px solid var(--primary-hover)', position: 'relative' }}>
            <button 
              style={{ position: 'absolute', top: '1rem', right: '1rem', background: 'none', border: 'none', color: 'white', fontSize: '1.5rem', cursor: 'pointer' }}
              onClick={() => setSelectedReceipt(null)}
            >
              ×
            </button>
            <div style={{ textAlign: 'center', marginBottom: '1.5rem', borderBottom: '2px dashed rgba(255,255,255,0.1)', paddingBottom: '1rem' }}>
              <h2 style={{ fontSize: '1.25rem', color: 'var(--primary-hover)', margin: 0 }}>Green Meadows RWA</h2>
              <span style={{ fontSize: '0.7rem', color: 'var(--text-secondary)' }}>Reg No: RWA/HYD/2026/9876</span>
              <h3 style={{ fontSize: '1.5rem', marginTop: '1rem', color: 'white', letterSpacing: '1px' }}>OFFICIAL RECEIPT</h3>
              <div style={{ fontSize: '0.85rem', color: 'var(--color-success)', fontWeight: 'bold', marginTop: '0.25rem' }}>{selectedReceipt.receipt_number}</div>
            </div>

            <div className="detail-list" style={{ fontSize: '0.85rem', gap: '0.5rem', marginBottom: '1.5rem' }}>
              <div className="detail-row">
                <span className="detail-label">Date Generated:</span>
                <span className="detail-value">{new Date(selectedReceipt.generated_at || new Date()).toLocaleString()}</span>
              </div>
              <div className="detail-row">
                <span className="detail-label">Payer Plot:</span>
                <span className="detail-value">
                  {(() => {
                    const pay = (paymentsList || []).find(p => p.id === selectedReceipt.payment_id);
                    const prop = propertiesList.find(pr => pr.id === pay?.property_id);
                    return prop ? prop.plot_number : 'Plot Portfolio';
                  })()}
                </span>
              </div>
              <div className="detail-row">
                <span className="detail-label">Payment Amount:</span>
                <span className="detail-value" style={{ fontWeight: 'bold', color: 'var(--color-success)' }}>₹{selectedReceipt.details?.amount}</span>
              </div>
              <div className="detail-row">
                <span className="detail-label">Reference ID:</span>
                <span className="detail-value"><code>{selectedReceipt.details?.reference_number}</code></span>
              </div>
            </div>

            <div style={{ borderTop: '1px solid rgba(255,255,255,0.05)', paddingTop: '1rem', marginBottom: '1.5rem' }}>
              <h4 style={{ fontSize: '0.85rem', marginBottom: '0.5rem', color: 'var(--text-secondary)' }}>Dues Cleared & Allocations:</h4>
              <div style={{ fontSize: '0.8rem', display: 'flex', flexDirection: 'column', gap: '0.4rem' }}>
                {(selectedReceipt.details?.allocations || []).map((alloc, idx) => {
                  const chg = maintenanceCharges.find(c => c.id === alloc.charge_id);
                  return (
                    <div key={idx} style={{ display: 'flex', justifyContent: 'space-between' }}>
                      <span>• Period {chg ? chg.billing_period : 'Charge'} ({chg ? chg.billing_subject_type : 'due'})</span>
                      <strong>₹{alloc.amount}</strong>
                    </div>
                  );
                })}
                {selectedReceipt.details?.advance_credited > 0 && (
                  <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--color-success)' }}>
                    <span>• Credit loaded as Advance</span>
                    <strong>₹{selectedReceipt.details.advance_credited}</strong>
                  </div>
                )}
              </div>
            </div>

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '2rem' }}>
              <div style={{ textAlign: 'center', fontSize: '0.65rem', color: 'var(--text-secondary)', borderTop: '1px solid rgba(255,255,255,0.1)', width: '120px', paddingTop: '0.25rem' }}>
                Treasury Officer
              </div>
              <button className="btn btn-primary btn-small" onClick={() => window.print()}>
                🖨️ Print Receipt
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Expenses sub-tab */}
      {activeSubTab === 'expenses' && (
        <div style={{ marginTop: '1.5rem' }}>
          <div style={{ display: 'flex', gap: '1.5rem', flexWrap: 'wrap' }}>
            {/* Category / Budget Setup */}
            <div style={{ flex: 1, minWidth: '300px' }}>
              <div className="glass-panel glass-card" style={{ marginBottom: '1.5rem' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
                  <h3>Expense Categories</h3>
                  <button className="btn btn-primary btn-small" onClick={() => setShowAddCategory(!showAddCategory)}>
                    {showAddCategory ? 'Cancel' : 'Add Category'}
                  </button>
                </div>

                {showAddCategory && (
                  <form onSubmit={handleAddCategory} style={{ marginBottom: '1rem', borderBottom: '1px solid rgba(255,255,255,0.05)', paddingBottom: '1rem' }}>
                    <div className="form-group">
                      <label className="form-label">Category Name *</label>
                      <input type="text" className="form-control" placeholder="e.g. Security Services" value={categoryName} onChange={(e) => setCategoryName(e.target.value)} required />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Description</label>
                      <textarea className="form-control" placeholder="Details..." value={categoryDesc} onChange={(e) => setCategoryDesc(e.target.value)} />
                    </div>
                    <button type="submit" className="btn btn-primary btn-small">Save Category</button>
                  </form>
                )}

                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                  {(expenseCategories || []).map(c => (
                    <div key={c.id} style={{ fontSize: '0.85rem', padding: '0.5rem', background: 'rgba(255,255,255,0.01)', border: '1px solid rgba(255,255,255,0.03)', borderRadius: '4px' }}>
                      <strong>{c.name}</strong>
                      {c.description && <p style={{ margin: '0.25rem 0 0 0', fontSize: '0.75rem', color: 'var(--text-secondary)' }}>{c.description}</p>}
                    </div>
                  ))}
                  {(!expenseCategories || expenseCategories.length === 0) && <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>No categories configured yet.</p>}
                </div>
              </div>

              <div className="glass-panel glass-card">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
                  <h3>Allocated Budgets</h3>
                  <button className="btn btn-primary btn-small" onClick={() => setShowAddBudget(!showAddBudget)}>
                    {showAddBudget ? 'Cancel' : 'Allocate'}
                  </button>
                </div>

                {showAddBudget && (
                  <form onSubmit={handleAddBudget} style={{ marginBottom: '1rem', borderBottom: '1px solid rgba(255,255,255,0.05)', paddingBottom: '1rem' }}>
                    <div className="form-group">
                      <label className="form-label">Category *</label>
                      <select className="form-control" value={bCategory} onChange={(e) => setBCategory(e.target.value)} required>
                        <option value="">Select Category</option>
                        {(expenseCategories || []).map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                      </select>
                    </div>
                    <div className="form-group">
                      <label className="form-label">Allocated Amount (₹) *</label>
                      <input type="number" className="form-control" placeholder="e.g. 50000" value={bAmount} onChange={(e) => setBAmount(e.target.value)} required />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Start Date *</label>
                      <input type="date" className="form-control" value={bStart} onChange={(e) => setBStart(e.target.value)} required />
                    </div>
                    <div className="form-group">
                      <label className="form-label">End Date *</label>
                      <input type="date" className="form-control" value={bEnd} onChange={(e) => setBEnd(e.target.value)} required />
                    </div>
                    <button type="submit" className="btn btn-primary btn-small">Save Budget</button>
                  </form>
                )}

                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                  {(budgets || []).map(b => {
                    const cat = (expenseCategories || []).find(c => c.id === b.category_id);
                    return (
                      <div key={b.id} style={{ fontSize: '0.85rem', padding: '0.5rem', background: 'rgba(255,255,255,0.01)', border: '1px solid rgba(255,255,255,0.03)', borderRadius: '4px' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                          <span><strong>{cat ? cat.name : 'Unknown Category'}</strong></span>
                          <strong>₹{b.allocated_amount}</strong>
                        </div>
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: '0.25rem' }}>
                          {b.start_date ? new Date(b.start_date).toLocaleDateString() : 'N/A'} to {b.end_date ? new Date(b.end_date).toLocaleDateString() : 'N/A'}
                        </div>
                      </div>
                    );
                  })}
                  {(!budgets || budgets.length === 0) && <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>No budgets allocated yet.</p>}
                </div>
              </div>
            </div>

            {/* Expense Vouchers Panel */}
            <div style={{ flex: 2, minWidth: '400px' }}>
              <div className="glass-panel glass-card">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
                  <h3>Expense Vouchers</h3>
                  <button className="btn btn-primary btn-small" onClick={() => setShowAddVoucher(!showAddVoucher)}>
                    {showAddVoucher ? 'Cancel' : 'Create Voucher'}
                  </button>
                </div>

                {showAddVoucher && (
                  <form onSubmit={handleAddVoucher} style={{ marginBottom: '1.5rem', borderBottom: '1px solid rgba(255,255,255,0.05)', paddingBottom: '1rem' }}>
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem' }}>
                      <div className="form-group">
                        <label className="form-label">Category *</label>
                        <select className="form-control" value={vCategory} onChange={(e) => setVCategory(e.target.value)} required>
                          <option value="">Select Category</option>
                          {(expenseCategories || []).map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                        </select>
                      </div>
                      <div className="form-group">
                        <label className="form-label">Amount (₹) *</label>
                        <input type="number" className="form-control" placeholder="12500" value={vAmount} onChange={(e) => setVAmount(e.target.value)} required />
                      </div>
                      <div className="form-group">
                        <label className="form-label">Vendor *</label>
                        <select 
                          className="form-control" 
                          value={vVendorId} 
                          onChange={(e) => {
                            const selectedId = e.target.value;
                            setVVendorId(selectedId);
                            const sel = (vendorsList || []).find(v => v.id === selectedId);
                            setVVendor(sel ? sel.name : '');
                          }} 
                          required
                        >
                          <option value="">Select Active Registered Vendor</option>
                          {(vendorsList || []).map(vnd => (
                            <option key={vnd.id} value={vnd.id}>
                              {vnd.name} ({vnd.service_category || 'General'})
                            </option>
                          ))}
                        </select>
                      </div>
                      <div className="form-group">
                        <label className="form-label">Invoice Number</label>
                        <input type="text" className="form-control" placeholder="e.g. INV-10293" value={vInvoiceNum} onChange={(e) => setVInvoiceNum(e.target.value)} />
                      </div>
                      <div className="form-group">
                        <label className="form-label">Invoice Date *</label>
                        <input type="date" className="form-control" value={vInvoiceDate} onChange={(e) => setVInvoiceDate(e.target.value)} required />
                      </div>
                      <div className="form-group">
                        <label className="form-label">Payment Method *</label>
                        <select className="form-control" value={vPaymentMethod} onChange={(e) => setVPaymentMethod(e.target.value)} required>
                          <option value="upi">UPI / GPay</option>
                          <option value="bank_transfer">Bank Transfer</option>
                          <option value="cash">Cash Payment</option>
                          <option value="cheque">Cheque Deposit</option>
                        </select>
                      </div>
                      <div className="form-group">
                        <label className="form-label">Reference Number</label>
                        <input type="text" className="form-control" placeholder="e.g. Transaction ID / Cheque No" value={vRefNum} onChange={(e) => setVRefNum(e.target.value)} />
                      </div>
                      <div className="form-group">
                        <label className="form-label">Attachment URL</label>
                        <input type="text" className="form-control" placeholder="e.g. https://invoice-scan-url..." value={vAttachment} onChange={(e) => setVAttachment(e.target.value)} />
                      </div>
                    </div>
                    <div className="form-group">
                      <label className="form-label">Description / Remarks</label>
                      <textarea className="form-control" placeholder="e.g. Security guard monthly wages..." value={vDesc} onChange={(e) => setVDesc(e.target.value)} />
                    </div>
                    <button type="submit" className="btn btn-primary btn-small">Save Voucher</button>
                  </form>
                )}

                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                  {(expenseVouchers || []).map(v => {
                    const cat = (expenseCategories || []).find(c => c.id === v.category_id);
                    return (
                      <div key={v.id} className="glass-panel" style={{ padding: '1rem', background: 'rgba(255,255,255,0.01)', border: '1px solid rgba(255,255,255,0.03)' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                          <div>
                            <span className="badge badge-status-active" style={{ background: 'var(--primary-hover)', color: 'white', marginRight: '0.5rem', fontSize: '0.65rem' }}>
                              {cat ? cat.name : 'Expenses'}
                            </span>
                            <span className={`badge ${
                              v.status === 'pending_approval' ? 'badge-status-pending' :
                              v.status === 'approved' ? 'badge-status-active' :
                              v.status === 'posted' ? 'badge-status-active' :
                              v.status === 'rejected' ? 'badge-status-inactive' : 'badge-status-inactive'
                            }`} style={{ fontSize: '0.65rem' }}>
                              {v.status.toUpperCase()}
                            </span>
                            <div style={{ marginTop: '0.5rem' }}>
                              <strong style={{ fontSize: '1.1rem' }}>₹{v.amount}</strong> to <strong style={{ color: 'var(--primary-hover)' }}>{v.vendor_name}</strong>
                            </div>
                            <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: '0.25rem' }}>
                              Invoice: {v.invoice_number || 'N/A'} | Date: {v.invoice_date ? new Date(v.invoice_date).toLocaleDateString() : 'N/A'} | Method: {v.payment_method ? v.payment_method.toUpperCase() : 'N/A'}
                            </div>
                            {v.reference_number && (
                              <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>
                                Ref: <code>{v.reference_number}</code>
                              </div>
                            )}
                            {v.description && (
                              <div style={{ fontSize: '0.8rem', marginTop: '0.4rem', borderTop: '1px dashed rgba(255,255,255,0.03)', paddingTop: '0.4rem' }}>
                                💡 {v.description}
                              </div>
                            )}
                            {v.attachment_url && (
                              <div style={{ marginTop: '0.5rem' }}>
                                <a href={v.attachment_url} target="_blank" rel="noopener noreferrer" style={{ fontSize: '0.75rem', color: 'var(--primary-hover)' }}>
                                  📎 View Invoice File
                                </a>
                              </div>
                            )}
                          </div>

                          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                            {v.status === 'pending_approval' && (
                              <>
                                <button className="btn btn-primary btn-small" onClick={() => handleApproveVoucher(v.id)}>Approve</button>
                                <button className="btn btn-secondary btn-small" style={{ color: 'var(--color-error)' }} onClick={() => handleRejectVoucher(v.id)}>Reject</button>
                              </>
                            )}
                            {v.status === 'approved' && (
                              <>
                                <button className="btn btn-primary btn-small" onClick={() => handlePostVoucher(v.id)}>Disburse & Post</button>
                                <button className="btn btn-secondary btn-small" style={{ color: 'var(--color-error)' }} onClick={() => handleRejectVoucher(v.id)}>Reject</button>
                              </>
                            )}
                            {v.status === 'posted' && (
                              <button className="btn btn-secondary btn-small" style={{ color: 'var(--color-error)' }} onClick={() => handleReverseExpenseVoucher(v.id)}>Reverse Expense</button>
                            )}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                  {(!expenseVouchers || expenseVouchers.length === 0) && <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)', textAlign: 'center' }}>No expense vouchers registered yet.</p>}
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Reconciliation sub-tab */}
      {activeSubTab === 'reconciliation' && (
        <div style={{ marginTop: '1.5rem' }}>
          <div style={{ display: 'flex', gap: '1.5rem', flexWrap: 'wrap' }}>
            {/* Reconciliation sheets list */}
            <div style={{ width: '300px' }}>
              <div className="glass-panel glass-card">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
                  <h3>BRS Sheets</h3>
                  <button className="btn btn-primary btn-small" onClick={() => setShowAddRecon(!showAddRecon)}>
                    {showAddRecon ? 'Cancel' : 'Create'}
                  </button>
                </div>

                {showAddRecon && (
                  <form onSubmit={handleAddRecon} style={{ marginBottom: '1rem', borderBottom: '1px solid rgba(255,255,255,0.05)', paddingBottom: '1rem' }}>
                    <div className="form-group">
                      <label className="form-label">Statement Date *</label>
                      <input type="date" className="form-control" value={rDate} onChange={(e) => setRDate(e.target.value)} required />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Opening Balance (₹) *</label>
                      <input type="number" className="form-control" placeholder="0" value={rOpenBal} onChange={(e) => setROpenBal(e.target.value)} required />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Closing Balance (₹) *</label>
                      <input type="number" className="form-control" placeholder="0" value={rCloseBal} onChange={(e) => setRCloseBal(e.target.value)} required />
                    </div>
                    <button type="submit" className="btn btn-primary btn-small">Save Sheet</button>
                  </form>
                )}

                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                  {bankReconciliations.map(recon => (
                    <div 
                      key={recon.id} 
                      onClick={() => { setSelectedRecon(recon); setReconcileTxSelection([]); }}
                      style={{ 
                        fontSize: '0.85rem', 
                        padding: '0.75rem', 
                        background: selectedRecon?.id === recon.id ? 'rgba(255,255,255,0.05)' : 'rgba(255,255,255,0.01)', 
                        border: selectedRecon?.id === recon.id ? '1px solid var(--primary-hover)' : '1px solid rgba(255,255,255,0.03)', 
                        borderRadius: '4px',
                        cursor: 'pointer'
                      }}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <strong>{new Date(recon.bank_statement_date).toLocaleDateString()}</strong>
                        <span className={`badge ${recon.status === 'completed' ? 'badge-status-active' : 'badge-status-pending'}`}>
                          {recon.status.toUpperCase()}
                        </span>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: '0.4rem' }}>
                        <span>Open: ₹{recon.opening_balance}</span>
                        <span>Close: ₹{recon.closing_balance}</span>
                      </div>
                    </div>
                  ))}
                  {bankReconciliations.length === 0 && <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>No BRS sheets configured.</p>}
                </div>
              </div>
            </div>

            {/* Reconciliation matching panel */}
            <div style={{ flex: 1, minWidth: '400px' }}>
              {selectedRecon ? (
                <div className="glass-panel glass-card">
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
                    <h3>BRS Matching Details: {new Date(selectedRecon.bank_statement_date).toLocaleDateString()}</h3>
                    {selectedRecon.status === 'draft' && (
                      <button className="btn btn-secondary btn-small" style={{ color: 'var(--color-success)', border: '1px solid var(--color-success)' }} onClick={() => handleCompleteRecon(selectedRecon.id)}>
                        🔒 Complete & Lock Sheet
                      </button>
                    )}
                  </div>

                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '1rem', background: 'rgba(0,0,0,0.1)', padding: '0.75rem', borderRadius: '4px', marginBottom: '1.5rem', fontSize: '0.85rem' }}>
                    <div>Opening: <strong>₹{selectedRecon.opening_balance}</strong></div>
                    <div>Closing: <strong>₹{selectedRecon.closing_balance}</strong></div>
                    <div>Status: <strong style={{ color: selectedRecon.status === 'completed' ? 'var(--color-success)' : 'var(--primary-hover)' }}>{selectedRecon.status.toUpperCase()}</strong></div>
                  </div>

                  {selectedRecon.status === 'draft' && (
                    <div style={{ marginBottom: '1rem' }}>
                      <button 
                        className="btn btn-primary btn-small" 
                        disabled={reconcileTxSelection.length === 0} 
                        onClick={() => handleMatchTransactions(selectedRecon.id)}
                      >
                        Match Selected Transactions ({reconcileTxSelection.length})
                      </button>
                    </div>
                  )}

                  <h4>Society Sub-Ledger Transactions</h4>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', marginTop: '0.75rem' }}>
                    {ledgerTransactions.filter(t => t.scope === 'society').map(t => {
                      const isMatchedToThis = t.bank_reconciliation_id === selectedRecon.id;
                      const isMatchedToOther = t.bank_reconciliation_id && t.bank_reconciliation_id !== selectedRecon.id;
                      
                      return (
                        <div key={t.id} style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', fontSize: '0.85rem', padding: '0.5rem', background: 'rgba(255,255,255,0.01)', border: '1px solid rgba(255,255,255,0.03)', borderRadius: '4px' }}>
                          {selectedRecon.status === 'draft' && !t.bank_reconciliation_id && (
                            <input 
                              type="checkbox" 
                              checked={reconcileTxSelection.includes(t.id)} 
                              onChange={(e) => {
                                if (e.target.checked) {
                                  setReconcileTxSelection([...reconcileTxSelection, t.id]);
                                } else {
                                  setReconcileTxSelection(reconcileTxSelection.filter(id => id !== t.id));
                                }
                              }} 
                            />
                          )}
                          <div style={{ flex: 1, display: 'flex', justifyContent: 'space-between' }}>
                            <div>
                              <strong>{new Date(t.transaction_date).toLocaleDateString()}</strong> | {t.transaction_type.toUpperCase()}
                              <p style={{ margin: '0.25rem 0 0 0', fontSize: '0.75rem', color: 'var(--text-secondary)' }}>{t.description}</p>
                            </div>
                            <div style={{ textAlign: 'right' }}>
                              <strong style={{ color: t.direction === 'debit' ? 'var(--color-success)' : 'var(--color-error)' }}>
                                {t.direction === 'debit' ? '+' : '-'}₹{t.amount}
                              </strong>
                              <div style={{ marginTop: '0.25rem' }}>
                                {isMatchedToThis && <span style={{ color: 'var(--color-success)', fontSize: '0.7rem' }}>✓ Matched Here</span>}
                                {isMatchedToOther && <span style={{ color: 'var(--text-muted)', fontSize: '0.7rem' }}>✓ Matched Elsewhere</span>}
                                {!t.bank_reconciliation_id && <span style={{ color: 'var(--primary-hover)', fontSize: '0.7rem' }}>Unreconciled</span>}
                              </div>
                            </div>
                          </div>
                        </div>
                      );
                    })}
                    {ledgerTransactions.filter(t => t.scope === 'society').length === 0 && <p style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>No society-level cash transactions booked.</p>}
                  </div>
                </div>
              ) : (
                <div className="glass-panel glass-card" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '200px', color: 'var(--text-muted)' }}>
                  Select a BRS statement sheet from the left panel to begin matching.
                </div>
              )}
            </div>
          </div>
        </div>
      )}
      
    </div>
  );
}

// 6. User Admin View
function UserRoleAdminView({ user, isSuperAdmin, triggerAlert }) {
  const [usersList, setUsersList] = useState([]);
  const [showAddUser, setShowAddUser] = useState(false);

  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const [mobile, setMobile] = useState('');
  const [role, setRole] = useState('member');
  const [password, setPassword] = useState('password123');

  useEffect(() => {
    loadUsers();
  }, []);

  const loadUsers = async () => {
    try {
      const list = await db.users.list(user);
      setUsersList(list);
    } catch (err) {
      triggerAlert('danger', 'Failed to fetch user list: ' + err.message);
    }
  };

  const handleRegisterUser = async (e) => {
    e.preventDefault();
    if (!email || !name) return;
    try {
      await db.users.create({
        email, name, mobile, role, password: password || 'password123', status: 'active'
      }, user);

      triggerAlert('success', `User account for ${name} registered with credentials.`);
      setShowAddUser(false);
      setEmail(''); setName(''); setMobile(''); setPassword('password123');
      loadUsers();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleToggleStatus = async (userId, currentStatus) => {
    const newStatus = currentStatus === 'active' ? 'inactive' : 'active';
    try {
      await db.users.updateStatus(userId, newStatus, user);
      triggerAlert('success', 'User activation status toggled.');
      loadUsers();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleRoleChange = async (userId, targetRole, alreadyHas) => {
    if (!isSuperAdmin) {
      triggerAlert('danger', 'Only Super Admin can edit roles.');
      return;
    }
    try {
      const targetUser = usersList.find(u => u.id === userId);
      const targetRoles = Array.isArray(targetUser?.roles) ? targetUser.roles : (targetUser?.role ? [targetUser.role] : []);
      let updatedRoles;
      if (alreadyHas) {
        if (targetRoles.length === 1) {
          triggerAlert('danger', 'User must retain at least one role.');
          return;
        }
        updatedRoles = targetRoles.filter(r => r !== targetRole);
      } else {
        updatedRoles = [...targetRoles, targetRole];
      }
      await db.users.updateRole(userId, updatedRoles, user);
      triggerAlert('success', 'User roles adjusted.');
      loadUsers();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <div>
          <h2>Account and Role Administration</h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Adjust site access, roles, and profile activations</p>
        </div>
        <button className="btn btn-primary" onClick={() => setShowAddUser(!showAddUser)}>
          {showAddUser ? 'Cancel' : 'Register User'}
        </button>
      </div>

      {showAddUser && (
        <div className="glass-panel glass-card" style={{ marginBottom: '2rem' }}>
          <h3>Register Member / Resident Profile</h3>
          <form onSubmit={handleRegisterUser} style={{ marginTop: '1rem' }}>
            <div className="grid-2">
              <div className="form-group">
                <label className="form-label">Full Name *</label>
                <input type="text" className="form-control" placeholder="e.g. Kalyan Reddy" value={name} onChange={(e) => setName(e.target.value)} required />
              </div>
              <div className="form-group">
                <label className="form-label">Email Address *</label>
                <input type="email" className="form-control" placeholder="e.g. kalyan@gmail.com" value={email} onChange={(e) => setEmail(e.target.value)} required />
              </div>
            </div>
            <div className="grid-2">
              <div className="form-group">
                <label className="form-label">Mobile Number</label>
                <input type="text" className="form-control" placeholder="e.g. +91 99999 99999" value={mobile} onChange={(e) => setMobile(e.target.value)} />
              </div>
              <div className="form-group">
                <label className="form-label">Assign Primary Role</label>
                <select className="form-control" value={role} onChange={(e) => setRole(e.target.value)}>
                  <option value="member">Property Owner (Member)</option>
                  <option value="tenant">Tenant</option>
                  <option value="secretary">Secretary (Committee)</option>
                  <option value="treasurer">Treasurer (Committee)</option>
                  <option value="executive_member">Executive Committee Member</option>
                  <option value="admin">Administrator</option>
                  <option value="gatekeeper">Gatekeeper (Security)</option>
                  <option value="technician">Technician</option>
                </select>
              </div>
            </div>
            <div className="form-group">
              <label className="form-label">Initial Login Password *</label>
              <input type="text" className="form-control" placeholder="password123" value={password} onChange={(e) => setPassword(e.target.value)} required />
              <small style={{ color: 'var(--text-secondary)', fontSize: '0.75rem', marginTop: '0.25rem', display: 'block' }}>
                Default: <code>password123</code>. User can sign in immediately with this credential.
              </small>
            </div>
            <button type="submit" className="btn btn-primary btn-small" style={{ marginTop: '1rem' }}>Create Account &amp; Credentials</button>
          </form>
        </div>
      )}

      <div className="table-responsive">
        <table className="table-custom">
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Status</th>
              <th>Assigned Roles</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {usersList.map(u => (
              <tr key={u.id}>
                <td>{u.name}</td>
                <td>{u.email}</td>
                <td>
                  <span className={`badge ${u.status === 'active' ? 'badge-status-active' : 'badge-status-inactive'}`}>
                    {u.status}
                  </span>
                </td>
                <td>
                  <div style={{ display: 'flex', gap: '0.25rem', flexWrap: 'wrap' }}>
                    {(Array.isArray(u?.roles) ? u.roles : (u?.role ? [u.role] : [])).map(r => (
                      <span key={r} className={`badge badge-${r}`}>{r}</span>
                    ))}
                  </div>
                </td>
                <td>
                  <div style={{ display: 'flex', gap: '0.5rem' }}>
                    <button className="btn btn-secondary btn-small" onClick={() => handleToggleStatus(u.id, u.status)}>
                      {u.status === 'active' ? 'Deactivate' : 'Activate'}
                    </button>
                    {isSuperAdmin && (() => {
                      const uRoles = Array.isArray(u?.roles) ? u.roles : (u?.role ? [u.role] : []);
                      return (
                        <select 
                          className="form-control btn-small" 
                          style={{ width: '150px', padding: '0.2rem 0.5rem', fontSize: '0.75rem' }} 
                          value="" 
                          onChange={(e) => {
                            const val = e.target.value;
                            if (val) handleRoleChange(u.id, val, uRoles.includes(val));
                          }}
                        >
                          <option value="">Role Editor...</option>
                          <option value="admin">{uRoles.includes('admin') ? '❌ Remove Admin' : '➕ Add Admin'}</option>
                          <option value="secretary">{uRoles.includes('secretary') ? '❌ Remove Secretary' : '➕ Add Secretary'}</option>
                          <option value="treasurer">{uRoles.includes('treasurer') ? '❌ Remove Treasurer' : '➕ Add Treasurer'}</option>
                          <option value="executive_member">{uRoles.includes('executive_member') ? '❌ Remove Exec Member' : '➕ Add Exec Member'}</option>
                          <option value="member">{uRoles.includes('member') ? '❌ Remove Owner (Member)' : '➕ Add Owner (Member)'}</option>
                          <option value="tenant">{uRoles.includes('tenant') ? '❌ Remove Tenant' : '➕ Add Tenant'}</option>
                          <option value="gatekeeper">{uRoles.includes('gatekeeper') ? '❌ Remove Gatekeeper' : '➕ Add Gatekeeper'}</option>
                          <option value="technician">{uRoles.includes('technician') ? '❌ Remove Technician' : '➕ Add Technician'}</option>
                        </select>
                      );
                    })()}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// 7. Security Audit Logs View
function AuditLogsView({ user, triggerAlert }) {
  const [logs, setLogs] = useState([]);

  useEffect(() => {
    loadLogs();
  }, []);

  const loadLogs = async () => {
    try {
      const list = await db.audit_logs.list(user);
      setLogs(list);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  return (
    <div>
      <h2>Security Audit Logs</h2>
      <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '1.5rem' }}>
        Read-only ledger of admin actions and property linkages.
      </p>

      <div className="table-responsive">
        <table className="table-custom">
          <thead>
            <tr>
              <th>Timestamp</th>
              <th>Action</th>
              <th>Target Table</th>
              <th>Old State</th>
              <th>New State</th>
            </tr>
          </thead>
          <tbody>
            {logs.map(log => (
              <tr key={log.id}>
                <td>{new Date(log.created_at).toLocaleString()}</td>
                <td><strong>{log.action}</strong></td>
                <td><code>{log.table_name}</code></td>
                <td style={{ fontSize: '0.8rem', fontFamily: 'monospace' }}>
                  {log.old_value ? JSON.stringify(log.old_value).substring(0, 50) + '...' : '-'}
                </td>
                <td style={{ fontSize: '0.8rem', fontFamily: 'monospace' }}>
                  {log.new_value ? JSON.stringify(log.new_value).substring(0, 50) + '...' : '-'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// 8. Member Dashboard View
function MemberDashboardView({ user, triggerAlert }) {
  const [myProperties, setMyProperties] = useState([]);
  const [selectedProp, setSelectedProp] = useState(null);
  const [units, setUnits] = useState([]);
  const [activeTab, setActiveTab] = useState('portions'); // portions, occupants, ledger, payments, rules, transparency
  const [familyGroups, setFamilyGroups] = useState([]);
  const [occupantsList, setOccupantsList] = useState([]);
  const [myLedger, setMyLedger] = useState([]);
  const [runningBalance, setRunningBalance] = useState(0);

  // Phase 2B additions
  const [paymentsList, setPaymentsList] = useState([]);
  const [receiptsList, setReceiptsList] = useState([]);
  const [notificationsList, setNotificationsList] = useState([]);

  // Phase 2C additions
  const [expenseCategories, setExpenseCategories] = useState([]);
  const [expenseVouchers, setExpenseVouchers] = useState([]);
  const [budgets, setBudgets] = useState([]);
  const [bankReconciliations, setBankReconciliations] = useState([]);

  const [showPaymentSlipForm, setShowPaymentSlipForm] = useState(false);
  const [payAmount, setPayAmount] = useState('');
  const [payMethod, setPayMethod] = useState('upi');
  const [payRef, setPayRef] = useState('');
  const [payDate, setPayDate] = useState('');
  const [selectedReceipt, setSelectedReceipt] = useState(null);

  // Forms
  const [showAddOccupant, setShowAddOccupant] = useState(false);
  const [occName, setOccName] = useState('');
  const [occRel, setOccRel] = useState('');
  const [occMob, setOccMob] = useState('');
  const [activeFamilyGroupId, setActiveFamilyGroupId] = useState('');

  useEffect(() => {
    loadMemberData();
  }, []);

  const loadMemberData = async () => {
    try {
      const allProps = await db.properties.list(user);
      const owned = [];
      for (const p of allProps) {
        const owners = await db.property_owners.list(p.id, user);
        const isMine = owners.some(o => o.owner_id === user.id && o.end_date === null);
        if (isMine) owned.push(p);
      }

      setMyProperties(owned);
      if (owned.length > 0) {
        handleSelectProperty(owned[0]);
      }

      // Fetch personal subsidiary ledger statement
      const ledger = await db.ledger_transactions.list(user);
      setMyLedger(ledger);

      let debits = 0;
      let credits = 0;
      ledger.forEach(tx => {
        if (tx.direction === 'debit') debits += Number(tx.amount);
        if (tx.direction === 'credit') credits += Number(tx.amount);
      });
      setRunningBalance(debits - credits);

      // Load Phase 2B data
      const payments = await db.payments.list(user);
      setPaymentsList(payments);
      const receipts = await db.receipts.list(user);
      setReceiptsList(receipts);
      const notifications = await db.notifications.list(user);
      setNotificationsList(notifications);

      // Load Phase 2C transparency data
      const cats = await db.expense_categories.list(user);
      setExpenseCategories(cats);
      const vchs = await db.expense_vouchers.list(user);
      setExpenseVouchers(vchs);
      const bdgs = await db.budgets.list(user);
      setBudgets(bdgs);
      const recons = await db.bank_reconciliations.list(user);
      setBankReconciliations(recons);
    } catch (err) {
      triggerAlert('danger', 'Failed to load member profile: ' + err.message);
    }
  };

  const handleSelectProperty = async (prop) => {
    setSelectedProp(prop);
    setShowAddOccupant(false);
    try {
      const listUnits = await db.units.list(prop.id, user);
      setUnits(listUnits);

      let consolidatedGroups = [];
      let consolidatedOccupants = [];

      for (const u of listUnits) {
        try {
          const groups = await db.family_groups.list(u.id, user);
          consolidatedGroups = [...consolidatedGroups, ...groups];

          for (const g of groups) {
            const occs = await db.occupants.list(g.id, user);
            consolidatedOccupants = [...consolidatedOccupants, ...occs.map(o => ({
              ...o, unit_name: u.unit_name, group_name: g.name
            }))];
          }
        } catch (err) {
          // Skip missing portions
        }
      }

      setFamilyGroups(consolidatedGroups);
      setOccupantsList(consolidatedOccupants);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleAddOccupant = async (e) => {
    e.preventDefault();
    if (!activeFamilyGroupId || !occName || !occRel) return;
    try {
      await db.occupants.create({
        family_group_id: activeFamilyGroupId, name: occName, relationship: occRel, mobile: occMob
      }, user);

      triggerAlert('success', 'Family occupant registered.');
      setShowAddOccupant(false);
      setOccName(''); setOccRel(''); setOccMob('');
      handleSelectProperty(selectedProp);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleRemoveOccupant = async (occId) => {
    if (!window.confirm('Remove this occupant?')) return;
    try {
      await db.occupants.update(occId, { is_active: false }, user);
      triggerAlert('success', 'Occupant removed.');
      handleSelectProperty(selectedProp);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  return (
    <div>
      <h2 className="text-gradient title-large">Member Portal</h2>
      <p className="subtitle">Manage household registry and monitor ownership credentials</p>

      {runningBalance !== 0 && (
        <div className={`alert-box ${runningBalance > 0 ? 'alert-danger' : 'alert-success'}`} style={{ marginBottom: '1.5rem' }}>
          <div>💰</div>
          <div style={{ flex: 1 }}>
            {runningBalance > 0 ? (
              <strong>Outstanding Dues: ₹{runningBalance} pending. Please submit verification slip.</strong>
            ) : (
              <strong>Advance Credit Balance: ₹{Math.abs(runningBalance)} loaded. Next cycles will consume credit.</strong>
            )}
          </div>
        </div>
      )}

      {myProperties.length > 1 && (
        <div className="glass-panel glass-card" style={{ padding: '1rem', marginBottom: '1.5rem', display: 'flex', alignItems: 'center', gap: '1rem' }}>
          <label style={{ fontWeight: 'bold' }}>Active Portfolio:</label>
          <select className="form-control" style={{ width: '220px' }} onChange={(e) => {
            const p = myProperties.find(prop => prop.id === e.target.value);
            if (p) handleSelectProperty(p);
          }}>
            {myProperties.map(p => <option key={p.id} value={p.id}>{p.plot_number}</option>)}
          </select>
        </div>
      )}

      {selectedProp ? (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: '1.5rem' }}>
          
          <div className="glass-panel glass-card">
            <h3>Property Profile: {selectedProp.plot_number}</h3>
            
            <div className="detail-list" style={{ marginTop: '1rem' }}>
              <div className="detail-row"><span className="detail-label">Plot Size</span><span className="detail-value">{selectedProp.plot_size_sqft} Sq.Ft.</span></div>
              <div className="detail-row"><span className="detail-label">Construction State</span><span className="detail-value">{selectedProp.construction_status}</span></div>
            </div>

            <div className="tabs-container" style={{ marginTop: '1.5rem' }}>
              <button className={`tab-btn ${activeTab === 'portions' ? 'active' : ''}`} onClick={() => setActiveTab('portions')}>Portions</button>
              <button className={`tab-btn ${activeTab === 'occupants' ? 'active' : ''}`} onClick={() => setActiveTab('occupants')}>Occupants</button>
              <button className={`tab-btn ${activeTab === 'ledger' ? 'active' : ''}`} onClick={() => setActiveTab('ledger')}>My Ledger</button>
              <button className={`tab-btn ${activeTab === 'payments' ? 'active' : ''}`} onClick={() => setActiveTab('payments')}>Payments & Receipts</button>
              <button className={`tab-btn ${activeTab === 'rules' ? 'active' : ''}`} onClick={() => setActiveTab('rules')}>Rules</button>
              <button className={`tab-btn ${activeTab === 'transparency' ? 'active' : ''}`} onClick={() => setActiveTab('transparency')}>Financial Transparency</button>
              <button className={`tab-btn ${activeTab === 'operations' ? 'active' : ''}`} onClick={() => setActiveTab('operations')}>Operations Portal</button>
            </div>

            {activeTab === 'portions' && (
              <div>
                {units.map(u => (
                  <div key={u.id} className="glass-panel" style={{ padding: '0.75rem 1rem', marginBottom: '0.75rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'rgba(255,255,255,0.02)' }}>
                    <div>
                      <strong style={{ fontSize: '0.9rem' }}>{u.unit_name}</strong>
                      <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>Status: {u.occupancy_status}</div>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {activeTab === 'occupants' && (
              <div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
                  <h4>Registered Occupants</h4>
                  {familyGroups.length > 0 && (
                    <button className="btn btn-primary btn-small" onClick={() => setShowAddOccupant(!showAddOccupant)}>
                      {showAddOccupant ? 'Cancel' : 'Add Occupant'}
                    </button>
                  )}
                </div>

                {showAddOccupant && (
                  <div className="glass-panel glass-card" style={{ marginBottom: '1.5rem', background: 'rgba(0,0,0,0.2)' }}>
                    <h5>Add Family Occupant</h5>
                    <form onSubmit={handleAddOccupant} style={{ marginTop: '0.75rem' }}>
                      <div className="form-group">
                        <label className="form-label">Choose Family Group</label>
                        <select className="form-control" value={activeFamilyGroupId} onChange={(e) => setActiveFamilyGroupId(e.target.value)} required>
                          <option value="">-- Choose Group --</option>
                          {familyGroups.map(fg => <option key={fg.id} value={fg.id}>{fg.name}</option>)}
                        </select>
                      </div>
                      <div className="form-group">
                        <label className="form-label">Full Name</label>
                        <input type="text" className="form-control" value={occName} onChange={(e) => setOccName(e.target.value)} required />
                      </div>
                      <div className="form-group">
                        <label className="form-label">Relationship</label>
                        <input type="text" className="form-control" value={occRel} onChange={(e) => setOccRel(e.target.value)} required />
                      </div>
                      <div className="form-group">
                        <label className="form-label">Mobile</label>
                        <input type="text" className="form-control" value={occMob} onChange={(e) => setOccMob(e.target.value)} />
                      </div>
                      <button type="submit" className="btn btn-primary btn-small">Confirm Add</button>
                    </form>
                  </div>
                )}

                {occupantsList.filter(o => o.is_active).map(occ => (
                  <div key={occ.id} className="glass-panel" style={{ padding: '0.75rem 1rem', marginBottom: '0.5rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'rgba(255,255,255,0.02)' }}>
                    <div>
                      <strong style={{ fontSize: '0.9rem' }}>{occ.name}</strong>
                      <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>{occ.relationship} | {occ.unit_name}</div>
                    </div>
                    <button className="btn btn-danger btn-small" style={{ padding: '0.2rem 0.5rem', fontSize: '0.7rem' }} onClick={() => handleRemoveOccupant(occ.id)}>Remove</button>
                  </div>
                ))}
              </div>
            )}

            {/* My Ledger statements (Phase 2A request) */}
            {activeTab === 'ledger' && (
              <div>
                <h4>Subsidiary Ledger Statement</h4>
                <div style={{ maxHeight: '300px', overflowY: 'auto', marginTop: '0.75rem' }}>
                  {myLedger.map(tx => (
                    <div key={tx.id} style={{ display: 'flex', justifyContent: 'space-between', padding: '0.5rem 0', borderBottom: '1px solid rgba(255,255,255,0.03)' }}>
                      <div>
                        <span style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>{tx.transaction_date}</span>
                        <div style={{ fontSize: '0.85rem' }}>{tx.description}</div>
                      </div>
                      <div style={{ textAlign: 'right', fontWeight: 'bold', color: tx.direction === 'debit' ? 'var(--color-error)' : 'var(--color-success)' }}>
                        {tx.direction === 'debit' ? `+ ₹${tx.amount} (Dr)` : `- ₹${tx.amount} (Cr)`}
                      </div>
                    </div>
                  ))}
                  {myLedger.length === 0 && (
                    <p style={{ color: 'var(--text-muted)', fontSize: '0.85rem' }}>No financial transactions booked yet.</p>
                  )}
                </div>
              </div>
            )}

            {/* Payments tab for member */}
            {activeTab === 'payments' && (
              <div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
                  <h4>Submit Payment Slip</h4>
                  <button className="btn btn-primary btn-small" onClick={() => setShowPaymentSlipForm(!showPaymentSlipForm)}>
                    {showPaymentSlipForm ? 'Hide Form' : 'Report Payment'}
                  </button>
                </div>

                {showPaymentSlipForm && (
                  <form onSubmit={async (e) => {
                    e.preventDefault();
                    if (!payAmount || !payRef) return;
                    try {
                      await db.payments.create({
                        society_id: '11111111-1111-1111-1111-111111111111', // MVP Society ID
                        property_id: selectedProp.id,
                        user_id: user.id,
                        amount: payAmount,
                        payment_method: payMethod,
                        reference_number: payRef,
                        payment_date: payDate || new Date().toISOString().split('T')[0]
                      }, user);
                      triggerAlert('success', 'Payment slip reported successfully. Pending treasurer review.');
                      setShowPaymentSlipForm(false);
                      setPayAmount(''); setPayRef('');
                      loadMemberData();
                    } catch (err) {
                      triggerAlert('danger', err.message);
                    }
                  }} className="glass-panel" style={{ padding: '1rem', background: 'rgba(0,0,0,0.2)', marginBottom: '1.5rem' }}>
                    <div className="form-group">
                      <label className="form-label">Payment Amount (₹) *</label>
                      <input type="number" className="form-control" placeholder="e.g. 1500" value={payAmount} onChange={(e) => setPayAmount(e.target.value)} required />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Payment Method</label>
                      <select className="form-control" value={payMethod} onChange={(e) => setPayMethod(e.target.value)}>
                        <option value="upi">UPI / GPay / PhonePe</option>
                        <option value="bank_transfer">Net Banking / NEFT / IMPS</option>
                        <option value="cash">Cash Payment</option>
                        <option value="cheque">Cheque Deposit</option>
                        <option value="other">Other Method</option>
                      </select>
                    </div>
                    <div className="form-group">
                      <label className="form-label">Transaction Reference Number *</label>
                      <input type="text" className="form-control" placeholder="e.g. UPI Ref, Bank UTR..." value={payRef} onChange={(e) => setPayRef(e.target.value)} required />
                    </div>
                    <div className="form-group">
                      <label className="form-label">Payment Date</label>
                      <input type="date" className="form-control" value={payDate} onChange={(e) => setPayDate(e.target.value)} />
                    </div>
                    <button type="submit" className="btn btn-primary btn-small">Submit Payment Slip</button>
                  </form>
                )}

                <h4>My Submitted Payment Slips</h4>
                <div style={{ maxHeight: '300px', overflowY: 'auto', marginTop: '0.75rem' }}>
                  {paymentsList.map(p => (
                    <div key={p.id} className="glass-panel" style={{ padding: '0.75rem', marginBottom: '0.5rem', background: 'rgba(255,255,255,0.01)', border: '1px solid rgba(255,255,255,0.03)' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <div>
                          <strong style={{ fontSize: '0.9rem' }}>₹{p.amount}</strong> via <code style={{ fontSize: '0.75rem' }}>{p.payment_method.toUpperCase()}</code>
                          <div style={{ fontSize: '0.7rem', color: 'var(--text-secondary)' }}>Ref: {p.reference_number} | Date: {p.payment_date || new Date(p.created_at).toLocaleDateString()}</div>
                          {p.verification_reason && (
                            <div style={{ fontSize: '0.7rem', color: 'var(--color-error)', marginTop: '0.25rem' }}>Reason: {p.verification_reason}</div>
                          )}
                        </div>
                        <div>
                          <span className={`badge ${
                            p.status === 'pending_verification' ? 'badge-status-pending' :
                            p.status === 'verified' ? 'badge-status-active' :
                            p.status === 'rejected' ? 'badge-status-inactive' : 'badge-status-inactive'
                          }`} style={{ fontSize: '0.65rem', marginRight: '0.5rem', background: p.status === 'rejected' ? 'var(--color-error)' : '' }}>
                            {p.status.toUpperCase()}
                          </span>
                          {p.status === 'verified' && (
                            <button 
                              className="btn btn-secondary btn-small"
                              style={{ fontSize: '0.65rem', padding: '0.15rem 0.4rem' }}
                              onClick={() => {
                                const rc = receiptsList.find(r => r.payment_id === p.id);
                                if (rc) setSelectedReceipt(rc);
                              }}
                            >
                              Receipt
                            </button>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
                  {paymentsList.length === 0 && (
                    <p style={{ color: 'var(--text-muted)', fontSize: '0.85rem' }}>No payment slips submitted yet.</p>
                  )}
                </div>
              </div>
            )}

            {activeTab === 'rules' && (
              <div>
                <h4>RWA General Rules & Bylaws</h4>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem', marginTop: '0.75rem', fontSize: '0.85rem' }}>
                  <p>1. Maintenance charges are computed based on active AGM approved rates.</p>
                  <p>2. Silent hours are enforced from 10 PM to 6 AM.</p>
                </div>
              </div>
            )}

            {activeTab === 'transparency' && (
              <div>
                <h4>Society Financial Transparency</h4>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '1.25rem' }}>
                  Real-time society expense tracking, allocated budget status, and audited BRS records.
                </p>

                {/* Metrics */}
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem', marginBottom: '1.5rem' }}>
                  <div className="glass-panel" style={{ padding: '0.75rem', background: 'rgba(0,0,0,0.1)' }}>
                    <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>Total Expenditure</div>
                    <div style={{ fontSize: '1.2rem', fontWeight: 'bold', color: 'var(--color-error)' }}>
                      ₹{(expenseVouchers || []).filter(v => v.status === 'posted').reduce((acc, curr) => acc + Number(curr.amount), 0)}
                    </div>
                  </div>
                  <div className="glass-panel" style={{ padding: '0.75rem', background: 'rgba(0,0,0,0.1)' }}>
                    <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>Active Budgets Count</div>
                    <div style={{ fontSize: '1.2rem', fontWeight: 'bold', color: 'var(--primary-hover)' }}>
                      {(budgets || []).length} Categories
                    </div>
                  </div>
                </div>

                {/* Budget vs Actual */}
                <h5 style={{ marginBottom: '0.5rem' }}>Budget vs Actual Spend</h5>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', marginBottom: '1.5rem' }}>
                  {(budgets || []).map(b => {
                    const cat = (expenseCategories || []).find(c => c.id === b.category_id);
                    const actual = (expenseVouchers || [])
                      .filter(v => v.category_id === b.category_id && v.status === 'posted')
                      .reduce((sum, v) => sum + Number(v.amount), 0);
                    const percent = b.allocated_amount > 0 ? Math.min(100, Math.round((actual / b.allocated_amount) * 100)) : 0;
                    
                    return (
                      <div key={b.id} style={{ fontSize: '0.8rem', padding: '0.5rem', background: 'rgba(255,255,255,0.01)', border: '1px solid rgba(255,255,255,0.03)', borderRadius: '4px' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.25rem' }}>
                          <span><strong>{cat ? cat.name : 'Category'}</strong></span>
                          <span>₹{actual} / ₹{b.allocated_amount} ({percent}%)</span>
                        </div>
                        <div style={{ width: '100%', height: '6px', background: 'rgba(255,255,255,0.1)', borderRadius: '3px', overflow: 'hidden' }}>
                          <div style={{ width: `${percent}%`, height: '100%', background: percent > 100 ? 'var(--color-error)' : 'var(--color-success)' }} />
                        </div>
                      </div>
                    );
                  })}
                  {(!budgets || budgets.length === 0) && <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>No budget allocation records available.</p>}
                </div>

                {/* Expense List */}
                <h5 style={{ marginBottom: '0.5rem' }}>Recent Expenses</h5>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', maxHeight: '200px', overflowY: 'auto', marginBottom: '1.5rem' }}>
                  {(expenseVouchers || []).map(v => {
                    const cat = (expenseCategories || []).find(c => c.id === v.category_id);
                    return (
                      <div key={v.id} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', padding: '0.4rem', borderBottom: '1px solid rgba(255,255,255,0.03)' }}>
                        <div>
                          <strong>{v.vendor_name}</strong> ({cat ? cat.name : 'Expense'})
                          <div style={{ fontSize: '0.7rem', color: 'var(--text-secondary)' }}>Invoice: {v.invoice_number || 'N/A'} | {v.invoice_date ? new Date(v.invoice_date).toLocaleDateString() : 'N/A'}</div>
                        </div>
                        <div style={{ textAlign: 'right' }}>
                          <strong>₹{v.amount}</strong>
                          <div><span className="badge" style={{ fontSize: '0.6rem', padding: '0.1rem 0.25rem' }}>{v.status ? v.status.toUpperCase() : 'N/A'}</span></div>
                        </div>
                      </div>
                    );
                  })}
                  {(!expenseVouchers || expenseVouchers.length === 0) && <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>No expenses recorded.</p>}
                </div>

                {/* Audited Reconciliation Statements */}
                <h5>Audited Reconciliation Statements</h5>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                  {(bankReconciliations || []).map(recon => (
                    <div key={recon.id} style={{ fontSize: '0.8rem', padding: '0.5rem', background: 'rgba(255,255,255,0.01)', border: '1px solid rgba(255,255,255,0.03)', borderRadius: '4px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <strong>As of {recon.bank_statement_date ? new Date(recon.bank_statement_date).toLocaleDateString() : 'N/A'}</strong>
                        <span className="badge badge-status-active" style={{ fontSize: '0.65rem' }}>AUDITED</span>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: '0.25rem' }}>
                        <span>Opening: ₹{recon.opening_balance}</span>
                        <span>Closing: ₹{recon.closing_balance}</span>
                      </div>
                    </div>
                  ))}
                  {(!bankReconciliations || bankReconciliations.length === 0) && <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>No audited BRS statements available.</p>}
                </div>
              </div>
            )}

            {activeTab === 'operations' && (
              <ResidentOperationsWidget user={user} triggerAlert={triggerAlert} />
            )}
          </div>

          <div className="glass-panel glass-card" style={{ height: 'max-content' }}>
            <h3>Privacy Guard</h3>
            <div className="alert-box alert-success" style={{ fontSize: '0.8rem', marginBottom: '1.5rem' }}>
              <div>🔒</div>
              <div><strong>Protected Personal Data:</strong> Only your verified property allocations are shown to you. Other member contacts, disputes, or private data are invisible.</div>
            </div>

            <h3>Notifications Inbox</h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', maxHeight: '350px', overflowY: 'auto' }}>
              {notificationsList.map(n => (
                <div key={n.id} className="glass-panel" style={{ padding: '0.75rem', background: n.is_read ? 'rgba(255,255,255,0.01)' : 'rgba(var(--primary-rgb), 0.05)', borderLeft: n.is_read ? 'none' : '3px solid var(--primary)', fontSize: '0.8rem' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.25rem' }}>
                    <strong style={{ color: 'white' }}>{n.title}</strong>
                    {!n.is_read && (
                      <button 
                        style={{ background: 'none', border: 'none', color: 'var(--primary)', cursor: 'pointer', fontSize: '0.7rem', padding: 0 }}
                        onClick={async () => {
                          await db.notifications.markRead(n.id, user);
                          loadMemberData();
                        }}
                      >
                        Mark read
                      </button>
                    )}
                  </div>
                  <div style={{ color: 'var(--text-secondary)' }}>{n.body}</div>
                  <div style={{ fontSize: '0.65rem', color: 'var(--text-muted)', marginTop: '0.25rem' }}>{new Date(n.created_at).toLocaleString()}</div>
                </div>
              ))}
              {notificationsList.length === 0 && (
                <p style={{ color: 'var(--text-muted)', fontSize: '0.8rem' }}>No notifications in your inbox.</p>
              )}
            </div>
          </div>

          {/* Member Receipt Modal Overlay */}
      {selectedReceipt && (
            <div className="modal-backdrop animate-fade-in" style={{ position: 'fixed', top: 0, left: 0, width: '100%', height: '100%', background: 'rgba(0,0,0,0.8)', display: 'flex', justifyContent: 'center', alignItems: 'center', zIndex: 1000, padding: '1rem' }}>
              <div className="glass-panel glass-card receipt-card" style={{ maxWidth: '500px', width: '100%', padding: '2rem', border: '1px solid var(--primary-hover)', position: 'relative' }}>
                <button 
                  style={{ position: 'absolute', top: '1rem', right: '1rem', background: 'none', border: 'none', color: 'white', fontSize: '1.5rem', cursor: 'pointer' }}
                  onClick={() => setSelectedReceipt(null)}
                >
                  ×
                </button>
                <div style={{ textAlign: 'center', marginBottom: '1.5rem', borderBottom: '2px dashed rgba(255,255,255,0.1)', paddingBottom: '1rem' }}>
                  <h2 style={{ fontSize: '1.25rem', color: 'var(--primary-hover)', margin: 0 }}>Green Meadows RWA</h2>
                  <span style={{ fontSize: '0.7rem', color: 'var(--text-secondary)' }}>Reg No: RWA/HYD/2026/9876</span>
                  <h3 style={{ fontSize: '1.5rem', marginTop: '1rem', color: 'white', letterSpacing: '1px' }}>OFFICIAL RECEIPT</h3>
                  <div style={{ fontSize: '0.85rem', color: 'var(--color-success)', fontWeight: 'bold', marginTop: '0.25rem' }}>{selectedReceipt.receipt_number}</div>
                </div>

                <div className="detail-list" style={{ fontSize: '0.85rem', gap: '0.5rem', marginBottom: '1.5rem' }}>
                  <div className="detail-row">
                    <span className="detail-label">Date Generated:</span>
                    <span className="detail-value">{new Date(selectedReceipt.generated_at || new Date()).toLocaleString()}</span>
                  </div>
                  <div className="detail-row">
                    <span className="detail-label">Payer Plot:</span>
                    <span className="detail-value">{selectedProp.plot_number}</span>
                  </div>
                  <div className="detail-row">
                    <span className="detail-label">Payment Amount:</span>
                    <span className="detail-value" style={{ fontWeight: 'bold', color: 'var(--color-success)' }}>₹{selectedReceipt.details?.amount}</span>
                  </div>
                  <div className="detail-row">
                    <span className="detail-label">Reference ID:</span>
                    <span className="detail-value"><code>{selectedReceipt.details?.reference_number}</code></span>
                  </div>
                </div>

                <div style={{ borderTop: '1px solid rgba(255,255,255,0.05)', paddingTop: '1rem', marginBottom: '1.5rem' }}>
                  <h4 style={{ fontSize: '0.85rem', marginBottom: '0.5rem', color: 'var(--text-secondary)' }}>Dues Cleared & Allocations:</h4>
                  <div style={{ fontSize: '0.8rem', display: 'flex', flexDirection: 'column', gap: '0.4rem' }}>
                    {(selectedReceipt.details?.allocations || []).map((alloc, idx) => {
                      const chg = maintenanceCharges.find(c => c.id === alloc.charge_id);
                      return (
                        <div key={idx} style={{ display: 'flex', justifyContent: 'space-between' }}>
                          <span>• Period {chg ? chg.billing_period : 'Charge'} ({chg ? chg.billing_subject_type : 'due'})</span>
                          <strong>₹{alloc.amount}</strong>
                        </div>
                      );
                    })}
                    {selectedReceipt.details?.advance_credited > 0 && (
                      <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--color-success)' }}>
                        <span>• Credit loaded as Advance</span>
                        <strong>₹{selectedReceipt.details.advance_credited}</strong>
                      </div>
                    )}
                  </div>
                </div>

                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '2rem' }}>
                  <div style={{ textAlign: 'center', fontSize: '0.65rem', color: 'var(--text-secondary)', borderTop: '1px solid rgba(255,255,255,0.1)', width: '120px', paddingTop: '0.25rem' }}>
                    Treasury Officer
                  </div>
                  <button className="btn btn-primary btn-small" onClick={() => window.print()}>
                    🖨️ Print Receipt
                  </button>
                </div>
              </div>
            </div>
          )}

        </div>
      ) : (
        <div className="glass-panel glass-card" style={{ textAlign: 'center', padding: '3rem' }}>
          <p style={{ color: 'var(--text-secondary)' }}>You are registered as a member but no active properties are assigned to your profile in the database.</p>
        </div>
      )}
    </div>
  );
}

// 9. Tenant Dashboard View
function TenantDashboardView({ user, triggerAlert }) {
  const [tenancies, setTenancies] = useState([]);
  const [landlord, setLandlord] = useState(null);
  const [activeTab, setActiveTab] = useState('lease'); // lease, operations

  useEffect(() => {
    loadTenantData();
  }, []);

  const loadTenantData = async () => {
    try {
      const dbInstance = JSON.parse(localStorage.getItem('su_society_db'));
      if (!dbInstance) return;

      const activeLeases = dbInstance.tenancies.filter(t => t.tenant_id === user.id && t.is_active);
      setTenancies(activeLeases);

      if (activeLeases.length > 0) {
        const unit = dbInstance.units.find(u => u.id === activeLeases[0].unit_id);
        if (unit) {
          const ownerLink = dbInstance.property_owners.find(po => po.property_id === unit.property_id && po.end_date === null);
          if (ownerLink) {
            const lUser = dbInstance.users.find(u => u.id === ownerLink.owner_id);
            setLandlord(lUser);
          }
        }
      }
    } catch (err) {
      triggerAlert('danger', 'Failed to load tenant lease: ' + err.message);
    }
  };

  return (
    <div>
      <h2 className="text-gradient title-large">Tenant Portal</h2>
      <p className="subtitle">Review your active lease terms and community guidelines</p>

      <div className="tabs-container" style={{ marginBottom: '1.5rem' }}>
        <button className={`tab-btn ${activeTab === 'lease' ? 'active' : ''}`} onClick={() => setActiveTab('lease')}>Lease Agreement</button>
        <button className={`tab-btn ${activeTab === 'operations' ? 'active' : ''}`} onClick={() => setActiveTab('operations')}>Operations Portal</button>
      </div>

      {activeTab === 'lease' && (
        <>
          {tenancies.length > 0 ? (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))', gap: '1.5rem' }}>
              
              <div className="glass-panel glass-card">
                <h3>Your Lease Agreement</h3>
                <div className="detail-list" style={{ marginBottom: '1.5rem', marginTop: '1rem' }}>
                  <div className="detail-row"><span className="detail-label">Start Date</span><span className="detail-value">{tenancies[0].start_date}</span></div>
                  <div className="detail-row"><span className="detail-label">Registered Occupants</span><span className="detail-value">{tenancies[0].occupant_count} residents</span></div>
                </div>

                {landlord && (
                  <div style={{ borderTop: '1px solid var(--border-light)', paddingTop: '1.25rem' }}>
                    <h4>Property Owner (Landlord)</h4>
                    <div className="detail-list" style={{ marginTop: '0.5rem' }}>
                      <div className="detail-row"><span className="detail-label">Name</span><span className="detail-value">{landlord.name}</span></div>
                      <div className="detail-row"><span className="detail-label">Contact</span><span className="detail-value">{landlord.mobile || 'Restricted'}</span></div>
                    </div>
                  </div>
                )}
              </div>

              <div className="glass-panel glass-card">
                <h3>Community Rules</h3>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem', fontSize: '0.85rem' }}>
                  <p>Tenants hold access rights to common parks and general bulletin boards, but do not retain AGM voting credentials.</p>
                </div>
              </div>

            </div>
          ) : (
            <div className="glass-panel glass-card" style={{ textAlign: 'center', padding: '3rem' }}>
              <p style={{ color: 'var(--text-secondary)' }}>You are registered in the portal with a Tenant Role, but no active tenancy leases are mapped to your user ID.</p>
            </div>
          )}
        </>
      )}

      {activeTab === 'operations' && (
        <ResidentOperationsWidget user={user} triggerAlert={triggerAlert} />
      )}
    </div>
  );
}

// =========================================================================
// PHASE 3A OPERATIONAL VIEWS
// =========================================================================

function GatekeeperDashboardView({ user, triggerAlert }) {
  const [visitorName, setVisitorName] = useState('');
  const [visitorMobile, setVisitorMobile] = useState('');
  const [purpose, setPurpose] = useState('guest');
  const [preAuthCode, setPreAuthCode] = useState('');
  const [vehicleNumber, setVehicleNumber] = useState('');
  const [selectedUnit, setSelectedUnit] = useState('');
  const [logs, setLogs] = useState([]);
  const [units, setUnits] = useState([]);

  useEffect(() => {
    loadLogs();
    loadUnits();
  }, []);

  const loadLogs = async () => {
    try {
      const data = await db.visitor_logs.list(user);
      setLogs(data);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const loadUnits = () => {
    const dbInstance = JSON.parse(localStorage.getItem('su_society_db'));
    if (dbInstance && dbInstance.units) {
      setUnits(dbInstance.units);
      if (dbInstance.units.length > 0) {
        setSelectedUnit(dbInstance.units[0].id);
      }
    }
  };

  const handleCheckIn = async (e) => {
    e.preventDefault();
    try {
      await db.visitor_logs.create({
        unit_id: selectedUnit,
        visitor_name: visitorName,
        visitor_mobile: visitorMobile,
        purpose,
        pre_auth_code: preAuthCode || null,
        vehicle_number: vehicleNumber
      }, user);
      triggerAlert('success', 'Visitor checked in successfully.');
      setVisitorName('');
      setVisitorMobile('');
      setPreAuthCode('');
      setVehicleNumber('');
      loadLogs();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCheckOut = async (logId) => {
    try {
      await db.visitor_logs.checkout(logId, user);
      triggerAlert('success', 'Visitor checked out successfully.');
      loadLogs();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  return (
    <div className="glass-panel glass-card" style={{ padding: '2rem' }}>
      <h2 className="text-gradient">Gatekeeper Terminal</h2>
      <p className="subtitle">Secure visitor verification & gate logs</p>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 2fr', gap: '2rem', marginTop: '2rem' }}>
        <form onSubmit={handleCheckIn} className="glass-panel" style={{ padding: '1.5rem', background: 'rgba(255,255,255,0.01)' }}>
          <h3 style={{ marginBottom: '1rem' }}>Register Visitor</h3>
          
          <div className="form-group">
            <label>Portion / Unit</label>
            <select className="form-control" value={selectedUnit} onChange={(e) => setSelectedUnit(e.target.value)}>
              {units.map(u => (
                <option key={u.id} value={u.id}>{u.unit_name} (Plot {u.property_id.substring(0, 5)})</option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label>Visitor Name</label>
            <input type="text" className="form-control" value={visitorName} onChange={(e) => setVisitorName(e.target.value)} required />
          </div>

          <div className="form-group">
            <label>Mobile Number</label>
            <input type="text" className="form-control" value={visitorMobile} onChange={(e) => setVisitorMobile(e.target.value)} />
          </div>

          <div className="form-group">
            <label>Purpose</label>
            <select className="form-control" value={purpose} onChange={(e) => setPurpose(e.target.value)}>
              <option value="guest">Guest</option>
              <option value="delivery">Delivery</option>
              <option value="maintenance">Maintenance</option>
              <option value="other">Other</option>
            </select>
          </div>

          <div className="form-group">
            <label>Pre-Auth Code (6 digits, optional)</label>
            <input type="text" className="form-control" placeholder="123456" maxLength={6} value={preAuthCode} onChange={(e) => setPreAuthCode(e.target.value)} />
          </div>

          <div className="form-group">
            <label>Vehicle Number (optional)</label>
            <input type="text" className="form-control" placeholder="MH-12-AB-1234" value={vehicleNumber} onChange={(e) => setVehicleNumber(e.target.value)} />
          </div>

          <button type="submit" className="btn btn-primary" style={{ width: '100%', marginTop: '1rem' }}>Check In Visitor</button>
        </form>

        <div className="glass-panel" style={{ padding: '1.5rem', background: 'rgba(255,255,255,0.01)' }}>
          <h3 style={{ marginBottom: '1.5rem' }}>Active Visitor Logs</h3>
          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Visitor</th>
                  <th>Unit</th>
                  <th>Vehicle</th>
                  <th>Check In</th>
                  <th>Status</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {logs.length === 0 ? (
                  <tr>
                    <td colSpan={6} style={{ textAlign: 'center', color: 'var(--text-secondary)' }}>No visitors checked in today.</td>
                  </tr>
                ) : (
                  logs.map(log => {
                    const unit = units.find(u => u.id === log.unit_id);
                    return (
                      <tr key={log.id}>
                        <td>
                          <strong>{log.visitor_name}</strong>
                          <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>{log.visitor_mobile || 'No Mobile'} ({log.purpose})</div>
                        </td>
                        <td>{unit ? unit.unit_name : 'Unknown'}</td>
                        <td>{log.vehicle_number || 'N/A'}</td>
                        <td>{new Date(log.check_in).toLocaleTimeString()}</td>
                        <td>
                          {log.check_out ? (
                            <span className="badge badge-secondary">Checked Out</span>
                          ) : (
                            <span className="badge badge-success">In Society</span>
                          )}
                        </td>
                        <td>
                          {!log.check_out && (
                            <button className="btn btn-small btn-secondary" onClick={() => handleCheckOut(log.id)}>Check Out</button>
                          )}
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}

function TechnicianDashboardView({ user, triggerAlert }) {
  const [tickets, setTickets] = useState([]);
  const [selectedTicket, setSelectedTicket] = useState(null);
  const [comments, setComments] = useState([]);
  const [newComment, setNewComment] = useState('');

  useEffect(() => {
    loadTickets();
  }, []);

  const loadTickets = async () => {
    try {
      const data = await db.helpdesk_tickets.list(user);
      setTickets(data);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleSelectTicket = async (ticket) => {
    setSelectedTicket(ticket);
    try {
      const cms = await db.ticket_comments.list(ticket.id, user);
      setComments(cms);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleAddComment = async (e) => {
    e.preventDefault();
    if (!newComment.trim()) return;
    try {
      await db.ticket_comments.create({
        ticket_id: selectedTicket.id,
        comment_text: newComment
      }, user);
      setNewComment('');
      const cms = await db.ticket_comments.list(selectedTicket.id, user);
      setComments(cms);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleResolve = async (ticketId) => {
    try {
      await db.helpdesk_tickets.resolve(ticketId, user);
      triggerAlert('success', 'Ticket marked as resolved.');
      loadTickets();
      setSelectedTicket(null);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  return (
    <div className="glass-panel glass-card" style={{ padding: '2rem' }}>
      <h2 className="text-gradient">Technician Dashboard</h2>
      <p className="subtitle">Manage assigned maintenance tasks</p>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '2rem', marginTop: '2rem' }}>
        <div className="glass-panel" style={{ padding: '1.5rem', background: 'rgba(255,255,255,0.01)' }}>
          <h3 style={{ marginBottom: '1rem' }}>Assigned Jobs</h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
            {tickets.length === 0 ? (
              <p style={{ color: 'var(--text-secondary)' }}>No jobs currently assigned to you.</p>
            ) : (
              tickets.map(t => (
                <div key={t.id} 
                     onClick={() => handleSelectTicket(t)}
                     className={`glass-panel ${selectedTicket?.id === t.id ? 'active-border' : ''}`} 
                     style={{ padding: '1rem', cursor: 'pointer', background: 'rgba(255,255,255,0.02)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <strong>{t.title}</strong>
                    <span className={`badge ${t.priority === 'emergency' ? 'badge-danger' : 'badge-warning'}`}>{t.priority}</span>
                  </div>
                  <p style={{ fontSize: '0.8rem', margin: '0.5rem 0', color: 'var(--text-secondary)' }}>{t.description}</p>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.75rem' }}>
                    <span>Category: {t.category}</span>
                    <span className="badge badge-info">{t.status}</span>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        {selectedTicket && (
          <div className="glass-panel" style={{ padding: '1.5rem', background: 'rgba(255,255,255,0.01)' }}>
            <h3>Job Details: {selectedTicket.title}</h3>
            <p style={{ marginTop: '0.5rem', fontSize: '0.85rem' }}>{selectedTicket.description}</p>

            <div style={{ marginTop: '1.5rem' }}>
              {selectedTicket.status !== 'resolved' && selectedTicket.status !== 'closed' && (
                <button className="btn btn-primary" onClick={() => handleResolve(selectedTicket.id)}>Mark Resolved</button>
              )}
            </div>

            <div style={{ marginTop: '2rem', borderTop: '1px solid rgba(255,255,255,0.05)', paddingTop: '1rem' }}>
              <h4>Communications Log</h4>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', margin: '1rem 0', maxHeight: '150px', overflowY: 'auto' }}>
                {comments.map(c => (
                  <div key={c.id} style={{ fontSize: '0.8rem', background: 'rgba(255,255,255,0.02)', padding: '0.5rem', borderRadius: '4px' }}>
                    <strong>{c.author_id.substring(0, 5)}:</strong> {c.comment_text}
                  </div>
                ))}
              </div>
              <form onSubmit={handleAddComment} style={{ display: 'flex', gap: '0.5rem' }}>
                <input type="text" className="form-control" placeholder="Type a message..." value={newComment} onChange={(e) => setNewComment(e.target.value)} required />
                <button type="submit" className="btn btn-secondary">Send</button>
              </form>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function OperationsManagerView({ user, triggerAlert }) {
  const [activeTab, setActiveTab] = useState('bookings');
  const [amenities, setAmenities] = useState([]);
  const [bookings, setBookings] = useState([]);
  const [tickets, setTickets] = useState([]);
  const [visitorLogs, setVisitorLogs] = useState([]);
  const [users, setUsers] = useState([]);
  
  // Slice 26 state additions
  const [assetsList, setAssetsList] = useState([]);
  const [vendorsList, setVendorsList] = useState([]);
  const [amcList, setAmcList] = useState([]);
  const [maintenanceLogsList, setMaintenanceLogsList] = useState([]);

  const [showAddAsset, setShowAddAsset] = useState(false);
  const [asName, setAsName] = useState('');
  const [asCode, setAsCode] = useState('');
  const [asCost, setAsCost] = useState('');
  const [asSerial, setAsSerial] = useState('');
  const [asStatus, setAsStatus] = useState('active');

  const [showAddVendor, setShowAddVendor] = useState(false);
  const [vndName, setVndName] = useState('');
  const [vndCat, setVndCat] = useState('General Maintenance');
  const [vndPhone, setVndPhone] = useState('');
  const [vndEmail, setVndEmail] = useState('');

  const [showAddAmc, setShowAddAmc] = useState(false);
  const [amcAssetId, setAmcAssetId] = useState('');
  const [amcVendorId, setAmcVendorId] = useState('');
  const [amcStart, setAmcStart] = useState('');
  const [amcEnd, setAmcEnd] = useState('');
  const [amcCost, setAmcCost] = useState('');

  const [showRenewModal, setShowRenewModal] = useState(false);
  const [renewAmcId, setRenewAmcId] = useState('');
  const [renewEndDate, setRenewEndDate] = useState('');
  const [renewCost, setRenewCost] = useState('');

  const [showLogModal, setShowLogModal] = useState(false);
  const [logAssetId, setLogAssetId] = useState('');
  const [logVendorId, setLogVendorId] = useState('');
  const [logDate, setLogDate] = useState('');
  const [logDesc, setLogDesc] = useState('');
  const [logCost, setLogCost] = useState('');
  const [logBy, setLogBy] = useState('');
  
  const [showAddAmenity, setShowAddAmenity] = useState(false);
  const [aName, setAName] = useState('');
  const [aDesc, setADesc] = useState('');
  const [aRate, setARate] = useState('');
  const [aType, setAType] = useState('slot_based');

  useEffect(() => {
    loadAllData();
  }, [activeTab]);

  const loadAllData = async () => {
    try {
      const allUsers = await db.users.list(user);
      setUsers(allUsers || []);

      if (activeTab === 'amenities' || activeTab === 'bookings') {
        const ams = await db.amenities.list(user);
        setAmenities(ams);
        const bks = await db.amenity_bookings.list(user);
        setBookings(bks);
      } else if (activeTab === 'helpdesk') {
        const tks = await db.helpdesk_tickets.list(user);
        setTickets(tks);
      } else if (activeTab === 'visitors') {
        const vls = await db.visitor_logs.list(user);
        setVisitorLogs(vls);
      } else if (activeTab === 'assets') {
        const asts = await db.assets.list(user);
        setAssetsList(asts);
      } else if (activeTab === 'vendors') {
        const vnds = await db.vendors.listAll(user);
        setVendorsList(vnds);
      } else if (activeTab === 'amc') {
        const amcs = await db.asset_amc.list(user);
        const asts = await db.assets.list(user);
        const vnds = await db.vendors.listAll(user);
        setAmcList(amcs);
        setAssetsList(asts);
        setVendorsList(vnds);
      } else if (activeTab === 'logs') {
        const logs = await db.asset_maintenance_logs.list(null, user);
        const asts = await db.assets.list(user);
        const vnds = await db.vendors.listAll(user);
        setMaintenanceLogsList(logs);
        setAssetsList(asts);
        setVendorsList(vnds);
      }
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCreateAmenity = async (e) => {
    e.preventDefault();
    try {
      await db.amenities.create({
        name: aName,
        description: aDesc,
        hourly_rate: Number(aRate),
        booking_type: aType
      }, user);
      triggerAlert('success', 'Amenity created successfully.');
      setAName('');
      setADesc('');
      setARate('');
      setShowAddAmenity(false);
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleApproveBooking = async (id) => {
    try {
      await db.amenity_bookings.approve(id, user);
      triggerAlert('success', 'Booking approved.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCancelBooking = async (id) => {
    try {
      await db.amenity_bookings.cancel(id, user);
      triggerAlert('success', 'Booking cancelled and charges reversed.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleRejectBooking = async (id) => {
    try {
      await db.amenity_bookings.reject(id, 'Rejected by manager', user);
      triggerAlert('success', 'Booking rejected.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCompleteBooking = async (id) => {
    try {
      await db.amenity_bookings.complete(id, user);
      triggerAlert('success', 'Booking completed.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleAssignTicket = async (ticketId, technicianId) => {
    try {
      await db.helpdesk_tickets.assign(ticketId, technicianId, user);
      triggerAlert('success', 'Ticket assigned successfully.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleStartTicket = async (ticketId) => {
    try {
      await db.helpdesk_tickets.start(ticketId, user);
      triggerAlert('success', 'Ticket in progress.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleResolveTicket = async (ticketId) => {
    try {
      await db.helpdesk_tickets.resolve(ticketId, user);
      triggerAlert('success', 'Ticket resolved.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCloseTicket = async (ticketId) => {
    try {
      await db.helpdesk_tickets.close(ticketId, user);
      triggerAlert('success', 'Ticket closed.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleReopenTicket = async (ticketId) => {
    try {
      await db.helpdesk_tickets.reopen(ticketId, 'Reopened by manager', user);
      triggerAlert('success', 'Ticket reopened.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCheckoutVisitor = async (logId) => {
    try {
      await db.visitor_logs.checkout(logId, user);
      triggerAlert('success', 'Visitor checked out.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCreateAsset = async (e) => {
    e.preventDefault();
    try {
      await db.assets.create({ name: asName, asset_code: asCode, purchase_cost: asCost, serial_number: asSerial, status: asStatus }, user);
      triggerAlert('success', 'Asset created successfully.');
      setAsName(''); setAsCode(''); setAsCost(''); setAsSerial(''); setShowAddAsset(false);
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleToggleAssetStatus = async (assetId, currentStatus) => {
    try {
      const nextStatus = currentStatus === 'active' ? 'maintenance' : currentStatus === 'maintenance' ? 'retired' : 'active';
      await db.assets.updateStatus(assetId, nextStatus, user);
      triggerAlert('success', `Asset status updated to ${nextStatus}.`);
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCreateVendor = async (e) => {
    e.preventDefault();
    try {
      await db.vendors.create({ name: vndName, service_category: vndCat, phone: vndPhone, email: vndEmail }, user);
      triggerAlert('success', 'Vendor registered successfully.');
      setVndName(''); setVndCat(''); setVndPhone(''); setVndEmail(''); setShowAddVendor(false);
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleToggleVendorStatus = async (vendorId) => {
    try {
      await db.vendors.toggleStatus(vendorId, user);
      triggerAlert('success', 'Vendor status toggled.');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCreateAmc = async (e) => {
    e.preventDefault();
    try {
      await db.asset_amc.create({ asset_id: amcAssetId, vendor_id: amcVendorId, start_date: amcStart, end_date: amcEnd, cost: amcCost }, user);
      triggerAlert('success', 'AMC contract registered.');
      setAmcAssetId(''); setAmcVendorId(''); setAmcStart(''); setAmcEnd(''); setAmcCost(''); setShowAddAmc(false);
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleRenewAmcSubmit = async (e) => {
    e.preventDefault();
    try {
      await db.asset_amc.renew(renewAmcId, renewEndDate, renewCost, user);
      triggerAlert('success', 'AMC contract renewed via renew_amc() RPC.');
      setShowRenewModal(false); setRenewAmcId(''); setRenewEndDate(''); setRenewCost('');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleLogServiceSubmit = async (e) => {
    e.preventDefault();
    try {
      await db.asset_maintenance_logs.logService({
        asset_id: logAssetId,
        vendor_id: logVendorId || null,
        service_date: logDate || new Date().toISOString().split('T')[0],
        description: logDesc,
        cost: logCost,
        performed_by: logBy || user.name || 'Staff'
      }, user);
      triggerAlert('success', 'Asset maintenance service logged via log_asset_service() RPC.');
      setShowLogModal(false); setLogAssetId(''); setLogVendorId(''); setLogDate(''); setLogDesc(''); setLogCost(''); setLogBy('');
      loadAllData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  return (
    <div className="glass-panel glass-card animate-fade-in" style={{ padding: '2rem' }}>
      <h2 className="text-gradient">Society Operations</h2>
      <p className="subtitle">Manage amenities, resident helpdesk tickets, and gate logs</p>

      <div className="tabs-container" style={{ marginTop: '1.5rem', marginBottom: '1.5rem' }}>
        <button className={`tab-btn ${activeTab === 'bookings' ? 'active' : ''}`} onClick={() => setActiveTab('bookings')}>Booking Requests</button>
        <button className={`tab-btn ${activeTab === 'amenities' ? 'active' : ''}`} onClick={() => setActiveTab('amenities')}>Amenities Manager</button>
        <button className={`tab-btn ${activeTab === 'helpdesk' ? 'active' : ''}`} onClick={() => setActiveTab('helpdesk')}>Helpdesk Coordinator</button>
        <button className={`tab-btn ${activeTab === 'visitors' ? 'active' : ''}`} onClick={() => setActiveTab('visitors')}>Visitor Monitoring</button>
        <button className={`tab-btn ${activeTab === 'assets' ? 'active' : ''}`} onClick={() => setActiveTab('assets')}>Asset Inventory</button>
        <button className={`tab-btn ${activeTab === 'vendors' ? 'active' : ''}`} onClick={() => setActiveTab('vendors')}>Vendor Master</button>
        <button className={`tab-btn ${activeTab === 'amc' ? 'active' : ''}`} onClick={() => setActiveTab('amc')}>AMC Contracts</button>
        <button className={`tab-btn ${activeTab === 'logs' ? 'active' : ''}`} onClick={() => setActiveTab('logs')}>Maintenance Logs</button>
      </div>

      {activeTab === 'bookings' && (
        <div>
          <h3>Booking Registry</h3>
          <div className="table-responsive" style={{ marginTop: '1rem' }}>
            <table className="table">
              <thead>
                <tr>
                  <th>Amenity</th>
                  <th>Property</th>
                  <th>Resident</th>
                  <th>Duration</th>
                  <th>Charges</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {bookings.length === 0 ? (
                  <tr>
                    <td colSpan={7} style={{ textAlign: 'center', color: 'var(--text-secondary)' }}>No booking requests found.</td>
                  </tr>
                ) : (
                  bookings.map(b => {
                    const amenity = amenities.find(a => a.id === b.amenity_id);
                    const resUser = users.find(u => u.id === b.booked_by);
                    return (
                      <tr key={b.id}>
                        <td><strong>{amenity ? amenity.name : 'Unknown'}</strong></td>
                        <td>{b.property_id}</td>
                        <td>{resUser ? resUser.name : b.booked_by.substring(0, 8)}</td>
                        <td>{new Date(b.start_time).toLocaleString()} to {new Date(b.end_time).toLocaleTimeString()}</td>
                        <td>₹{b.total_charges}</td>
                        <td><span className={`badge badge-${b.status === 'approved' ? 'success' : b.status === 'pending_approval' ? 'warning' : 'secondary'}`}>{b.status}</span></td>
                        <td>
                          {b.status === 'pending_approval' && (
                            <>
                              <button className="btn btn-small btn-success" style={{ marginRight: '0.25rem' }} onClick={() => handleApproveBooking(b.id)}>Approve</button>
                              <button className="btn btn-small btn-danger" style={{ marginRight: '0.25rem' }} onClick={() => handleRejectBooking(b.id)}>Reject</button>
                            </>
                          )}
                          {b.status === 'approved' && (
                            <button className="btn btn-small btn-primary" style={{ marginRight: '0.25rem' }} onClick={() => handleCompleteBooking(b.id)}>Complete</button>
                          )}
                          {b.status !== 'cancelled' && b.status !== 'completed' && b.status !== 'rejected' && (
                            <button className="btn btn-small btn-secondary" onClick={() => handleCancelBooking(b.id)}>Cancel</button>
                          )}
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === 'amenities' && (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <h3>Amenities Registry</h3>
            <button className="btn btn-primary btn-small" onClick={() => setShowAddAmenity(!showAddAmenity)}>
              {showAddAmenity ? 'Cancel' : '+ Add Amenity'}
            </button>
          </div>

          {showAddAmenity && (
            <form onSubmit={handleCreateAmenity} className="glass-panel" style={{ padding: '1.5rem', marginTop: '1rem', maxWidth: '500px' }}>
              <h4>New Amenity</h4>
              <div className="form-group" style={{ marginTop: '1rem' }}>
                <label>Name</label>
                <input type="text" className="form-control" value={aName} onChange={(e) => setAName(e.target.value)} required />
              </div>
              <div className="form-group">
                <label>Description</label>
                <input type="text" className="form-control" value={aDesc} onChange={(e) => setADesc(e.target.value)} />
              </div>
              <div className="form-group">
                <label>Hourly Rate (₹)</label>
                <input type="number" className="form-control" value={aRate} onChange={(e) => setARate(e.target.value)} required />
              </div>
              <div className="form-group">
                <label>Booking Type</label>
                <select className="form-control" value={aType} onChange={(e) => setAType(e.target.value)}>
                  <option value="slot_based">Hourly Slots</option>
                  <option value="day_based">Full Day</option>
                </select>
              </div>
              <button type="submit" className="btn btn-primary" style={{ marginTop: '1rem' }}>Save Amenity</button>
            </form>
          )}

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: '1rem', marginTop: '1.5rem' }}>
            {amenities.map(a => (
              <div key={a.id} className="glass-panel" style={{ padding: '1.25rem', background: 'rgba(255,255,255,0.02)' }}>
                <strong>{a.name}</strong>
                <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', margin: '0.5rem 0' }}>{a.description || 'No description'}</p>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.85rem' }}>
                  <span>₹{a.hourly_rate} / hr ({a.booking_type})</span>
                  <span className={`badge ${a.is_active ? 'badge-success' : 'badge-danger'}`}>{a.is_active ? 'Active' : 'Inactive'}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {activeTab === 'helpdesk' && (
        <div>
          <h3>Helpdesk Ticket Operations</h3>
          <div className="table-responsive" style={{ marginTop: '1rem' }}>
            <table className="table">
              <thead>
                <tr>
                  <th>Ticket</th>
                  <th>Category</th>
                  <th>Priority</th>
                  <th>Status</th>
                  <th>Assigned Technician</th>
                </tr>
              </thead>
              <tbody>
                {tickets.length === 0 ? (
                  <tr>
                    <td colSpan={5} style={{ textAlign: 'center', color: 'var(--text-secondary)' }}>No helpdesk tickets filed.</td>
                  </tr>
                ) : (
                  tickets.map(t => {
                    const techList = users.filter(u => {
                      const rls = Array.isArray(u?.roles) ? u.roles : (Array.isArray(u?.user_roles) ? u.user_roles.map(r => r.role) : (u?.role ? [u.role] : []));
                      return rls.some(r => typeof r === 'string' && r.toLowerCase().trim() === 'technician');
                    });

                    // Fallback to ensure Suresh is listed if the tech list resolves to empty
                    if (techList.length === 0) {
                      techList.push({ id: 'd2222222-2222-2222-2222-222222222222', name: 'Suresh (Technician) - Auto Fallback' });
                    }

                    return (
                      <tr key={t.id}>
                        <td>
                          <strong>{t.title}</strong>
                          <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>{t.description}</div>
                        </td>
                        <td>{t.category}</td>
                        <td><span className={`badge ${t.priority === 'emergency' ? 'badge-danger' : 'badge-warning'}`}>{t.priority}</span></td>
                        <td><span className="badge badge-info">{t.status}</span></td>
                        <td>
                          <select className="form-control form-control-small" 
                                  value={t.assigned_to || ''} 
                                  onChange={(e) => handleAssignTicket(t.id, e.target.value)}>
                            <option value="">-- Unassigned --</option>
                            {techList.map(tech => (
                              <option key={tech.id} value={tech.id}>{tech.name}</option>
                            ))}
                          </select>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {activeTab === 'visitors' && (
        <div>
          <h3>Visitor Logs Registry</h3>
          <div className="table-responsive" style={{ marginTop: '1rem' }}>
            <table className="table">
              <thead>
                <tr>
                  <th>Visitor Details</th>
                  <th>Unit</th>
                  <th>Vehicle</th>
                  <th>Purpose</th>
                  <th>Time Windows</th>
                </tr>
              </thead>
              <tbody>
                {visitorLogs.length === 0 ? (
                  <tr>
                    <td colSpan={5} style={{ textAlign: 'center', color: 'var(--text-secondary)' }}>No visitor logs registered.</td>
                  </tr>
                ) : (
                  visitorLogs.map(v => (
                    <tr key={v.id}>
                      <td>
                        <strong>{v.visitor_name}</strong>
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>{v.visitor_mobile || 'No Mobile'}</div>
                      </td>
                      <td>{v.unit_id}</td>
                      <td><code>{v.vehicle_number || 'N/A'}</code></td>
                      <td>{v.purpose}</td>
                      <td>
                        <div style={{ fontSize: '0.8rem' }}>Check In: {new Date(v.check_in).toLocaleString()}</div>
                        {v.check_out && <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>Check Out: {new Date(v.check_out).toLocaleString()}</div>}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Assets Sub-Tab */}
      {activeTab === 'assets' && (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Society Asset Inventory</h3>
            <button className="btn btn-primary btn-small" onClick={() => setShowAddAsset(!showAddAsset)}>
              {showAddAsset ? 'Cancel' : '+ Register Asset'}
            </button>
          </div>

          {showAddAsset && (
            <form onSubmit={handleCreateAsset} className="glass-panel" style={{ padding: '1.5rem', marginBottom: '1.5rem', maxWidth: '600px' }}>
              <h4>Register New Asset</h4>
              <div className="form-group" style={{ marginTop: '1rem' }}>
                <label className="form-label">Asset Name *</label>
                <input type="text" className="form-control" placeholder="e.g. Main Gate Generator 125kVA" value={asName} onChange={(e) => setAsName(e.target.value)} required />
              </div>
              <div className="grid-2">
                <div className="form-group">
                  <label className="form-label">Asset Code *</label>
                  <input type="text" className="form-control" placeholder="e.g. AST-DG-001" value={asCode} onChange={(e) => setAsCode(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label className="form-label">Purchase Cost (₹)</label>
                  <input type="number" className="form-control" placeholder="450000" value={asCost} onChange={(e) => setAsCost(e.target.value)} />
                </div>
              </div>
              <div className="grid-2">
                <div className="form-group">
                  <label className="form-label">Serial Number</label>
                  <input type="text" className="form-control" placeholder="e.g. SN-998823" value={asSerial} onChange={(e) => setAsSerial(e.target.value)} />
                </div>
                <div className="form-group">
                  <label className="form-label">Initial Status</label>
                  <select className="form-control" value={asStatus} onChange={(e) => setAsStatus(e.target.value)}>
                    <option value="active">Active / Operational</option>
                    <option value="maintenance">Under Maintenance</option>
                    <option value="retired">Retired / Decommissioned</option>
                  </select>
                </div>
              </div>
              <button type="submit" className="btn btn-primary" style={{ marginTop: '1rem' }}>Save Asset Record</button>
            </form>
          )}

          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Asset Code</th>
                  <th>Asset Name</th>
                  <th>Serial Number</th>
                  <th>Purchase Cost</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {assetsList.length === 0 ? (
                  <tr><td colSpan="6" style={{ textAlign: 'center', color: 'var(--text-secondary)' }}>No assets registered yet.</td></tr>
                ) : (
                  assetsList.map(a => (
                    <tr key={a.id}>
                      <td><code>{a.asset_code}</code></td>
                      <td><strong>{a.name}</strong></td>
                      <td>{a.serial_number || 'N/A'}</td>
                      <td>₹{a.purchase_cost || 0}</td>
                      <td>
                        <span className={`badge ${a.status === 'active' ? 'badge-success' : a.status === 'maintenance' ? 'badge-warning' : 'badge-danger'}`}>
                          {a.status.toUpperCase()}
                        </span>
                      </td>
                      <td>
                        <button className="btn btn-small btn-secondary" onClick={() => handleToggleAssetStatus(a.id, a.status)}>
                          Toggle Status
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Vendors Sub-Tab */}
      {activeTab === 'vendors' && (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Vendor Master Directory</h3>
            <button className="btn btn-primary btn-small" onClick={() => setShowAddVendor(!showAddVendor)}>
              {showAddVendor ? 'Cancel' : '+ Register Vendor'}
            </button>
          </div>

          {showAddVendor && (
            <form onSubmit={handleCreateVendor} className="glass-panel" style={{ padding: '1.5rem', marginBottom: '1.5rem', maxWidth: '600px' }}>
              <h4>Register Vendor</h4>
              <div className="form-group" style={{ marginTop: '1rem' }}>
                <label className="form-label">Vendor Name *</label>
                <input type="text" className="form-control" placeholder="e.g. Apex Security Ltd" value={vndName} onChange={(e) => setVndName(e.target.value)} required />
              </div>
              <div className="form-group">
                <label className="form-label">Service Category</label>
                <input type="text" className="form-control" placeholder="e.g. Security Services / Elevator AMC" value={vndCat} onChange={(e) => setVndCat(e.target.value)} />
              </div>
              <div className="grid-2">
                <div className="form-group">
                  <label className="form-label">Phone Number</label>
                  <input type="text" className="form-control" placeholder="+91 9876543210" value={vndPhone} onChange={(e) => setVndPhone(e.target.value)} />
                </div>
                <div className="form-group">
                  <label className="form-label">Email Address</label>
                  <input type="email" className="form-control" placeholder="vendor@domain.com" value={vndEmail} onChange={(e) => setVndEmail(e.target.value)} />
                </div>
              </div>
              <button type="submit" className="btn btn-primary" style={{ marginTop: '1rem' }}>Register Vendor</button>
            </form>
          )}

          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Vendor Name</th>
                  <th>Service Category</th>
                  <th>Contact Info</th>
                  <th>Status</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {vendorsList.length === 0 ? (
                  <tr><td colSpan="5" style={{ textAlign: 'center', color: 'var(--text-secondary)' }}>No vendors registered yet.</td></tr>
                ) : (
                  vendorsList.map(v => (
                    <tr key={v.id}>
                      <td><strong>{v.name}</strong></td>
                      <td>{v.service_category || 'General'}</td>
                      <td>{v.phone} {v.email ? `| ${v.email}` : ''}</td>
                      <td>
                        <span className={`badge ${v.status === 'active' ? 'badge-success' : 'badge-danger'}`}>
                          {v.status.toUpperCase()}
                        </span>
                      </td>
                      <td>
                        <button className="btn btn-small btn-secondary" onClick={() => handleToggleVendorStatus(v.id)}>
                          Toggle Status
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* AMC Contracts Sub-Tab */}
      {activeTab === 'amc' && (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <h3>Annual Maintenance Contracts (AMC)</h3>
            <button className="btn btn-primary btn-small" onClick={() => setShowAddAmc(!showAddAmc)}>
              {showAddAmc ? 'Cancel' : '+ Add AMC Contract'}
            </button>
          </div>

          {showAddAmc && (
            <form onSubmit={handleCreateAmc} className="glass-panel" style={{ padding: '1.5rem', marginBottom: '1.5rem', maxWidth: '600px' }}>
              <h4>Register AMC Contract</h4>
              <div className="grid-2" style={{ marginTop: '1rem' }}>
                <div className="form-group">
                  <label className="form-label">Asset *</label>
                  <select className="form-control" value={amcAssetId} onChange={(e) => setAmcAssetId(e.target.value)} required>
                    <option value="">Select Asset</option>
                    {assetsList.map(a => <option key={a.id} value={a.id}>{a.name} ({a.asset_code})</option>)}
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Vendor *</label>
                  <select className="form-control" value={amcVendorId} onChange={(e) => setAmcVendorId(e.target.value)} required>
                    <option value="">Select Vendor</option>
                    {vendorsList.map(v => <option key={v.id} value={v.id}>{v.name}</option>)}
                  </select>
                </div>
              </div>
              <div className="grid-3">
                <div className="form-group">
                  <label className="form-label">Start Date *</label>
                  <input type="date" className="form-control" value={amcStart} onChange={(e) => setAmcStart(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label className="form-label">End Date *</label>
                  <input type="date" className="form-control" value={amcEnd} onChange={(e) => setAmcEnd(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label className="form-label">Contract Cost (₹) *</label>
                  <input type="number" className="form-control" placeholder="35000" value={amcCost} onChange={(e) => setAmcCost(e.target.value)} required />
                </div>
              </div>
              <button type="submit" className="btn btn-primary" style={{ marginTop: '1rem' }}>Save AMC Contract</button>
            </form>
          )}

          {showRenewModal && (
            <div className="glass-panel" style={{ padding: '1.5rem', marginBottom: '1.5rem', border: '1px solid var(--primary-hover)', maxWidth: '500px' }}>
              <h4>Renew AMC Contract (renew_amc RPC)</h4>
              <form onSubmit={handleRenewAmcSubmit} style={{ marginTop: '1rem' }}>
                <div className="form-group">
                  <label className="form-label">New End Date *</label>
                  <input type="date" className="form-control" value={renewEndDate} onChange={(e) => setRenewEndDate(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label className="form-label">New Contract Cost (₹) *</label>
                  <input type="number" className="form-control" placeholder="40000" value={renewCost} onChange={(e) => setRenewCost(e.target.value)} required />
                </div>
                <div style={{ display: 'flex', gap: '0.5rem', marginTop: '1rem' }}>
                  <button type="submit" className="btn btn-primary btn-small">Confirm Renewal (RPC)</button>
                  <button type="button" className="btn btn-secondary btn-small" onClick={() => setShowRenewModal(false)}>Cancel</button>
                </div>
              </form>
            </div>
          )}

          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Asset</th>
                  <th>Vendor</th>
                  <th>Contract Term</th>
                  <th>Annual Cost</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {amcList.length === 0 ? (
                  <tr><td colSpan="5" style={{ textAlign: 'center', color: 'var(--text-secondary)' }}>No AMC contracts registered.</td></tr>
                ) : (
                  amcList.map(a => {
                    const ast = assetsList.find(x => x.id === a.asset_id);
                    const vnd = vendorsList.find(x => x.id === a.vendor_id);
                    return (
                      <tr key={a.id}>
                        <td><strong>{ast ? ast.name : 'Unknown Asset'}</strong></td>
                        <td>{vnd ? vnd.name : 'Unknown Vendor'}</td>
                        <td>{new Date(a.start_date).toLocaleDateString()} to {new Date(a.end_date).toLocaleDateString()}</td>
                        <td>₹{a.cost}</td>
                        <td>
                          <button className="btn btn-small btn-primary" onClick={() => { setRenewAmcId(a.id); setShowRenewModal(true); }}>
                            Renew AMC (RPC)
                          </button>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Maintenance Service Logs Sub-Tab */}
      {activeTab === 'logs' && (
        <div>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
            <div>
              <h3>Asset Maintenance Service Logs</h3>
              <span style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>
                🔒 Audit Notice: Service logs are strictly append-only. Edits and deletions are prohibited by database security triggers.
              </span>
            </div>
            <button className="btn btn-primary btn-small" onClick={() => setShowLogModal(!showLogModal)}>
              {showLogModal ? 'Cancel' : '+ Log Service Event (RPC)'}
            </button>
          </div>

          {showLogModal && (
            <form onSubmit={handleLogServiceSubmit} className="glass-panel" style={{ padding: '1.5rem', marginBottom: '1.5rem', maxWidth: '600px' }}>
              <h4>Log Maintenance Service Event (log_asset_service RPC)</h4>
              <div className="grid-2" style={{ marginTop: '1rem' }}>
                <div className="form-group">
                  <label className="form-label">Asset *</label>
                  <select className="form-control" value={logAssetId} onChange={(e) => setLogAssetId(e.target.value)} required>
                    <option value="">Select Asset</option>
                    {assetsList.map(a => <option key={a.id} value={a.id}>{a.name} ({a.asset_code})</option>)}
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Servicing Vendor</label>
                  <select className="form-control" value={logVendorId} onChange={(e) => setLogVendorId(e.target.value)}>
                    <option value="">Select Vendor (Optional)</option>
                    {vendorsList.map(v => <option key={v.id} value={v.id}>{v.name}</option>)}
                  </select>
                </div>
              </div>
              <div className="grid-2">
                <div className="form-group">
                  <label className="form-label">Service Date *</label>
                  <input type="date" className="form-control" value={logDate} onChange={(e) => setLogDate(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label className="form-label">Service Cost (₹)</label>
                  <input type="number" className="form-control" placeholder="5000" value={logCost} onChange={(e) => setLogCost(e.target.value)} />
                </div>
              </div>
              <div className="form-group">
                <label className="form-label">Service Description / Work Summary *</label>
                <textarea className="form-control" placeholder="e.g. Engine oil replacement and filter cleaning..." value={logDesc} onChange={(e) => setLogDesc(e.target.value)} required />
              </div>
              <div className="form-group">
                <label className="form-label">Technician / Performed By</label>
                <input type="text" className="form-control" placeholder="e.g. Senior Tech Ramesh" value={logBy} onChange={(e) => setLogBy(e.target.value)} />
              </div>
              <button type="submit" className="btn btn-primary" style={{ marginTop: '1rem' }}>Submit & Write Log (RPC)</button>
            </form>
          )}

          <div className="table-responsive">
            <table className="table">
              <thead>
                <tr>
                  <th>Service Date</th>
                  <th>Asset Code & Name</th>
                  <th>Servicing Vendor</th>
                  <th>Service Description</th>
                  <th>Cost</th>
                  <th>Performed By</th>
                </tr>
              </thead>
              <tbody>
                {maintenanceLogsList.length === 0 ? (
                  <tr><td colSpan="6" style={{ textAlign: 'center', color: 'var(--text-secondary)' }}>No maintenance service events logged yet.</td></tr>
                ) : (
                  maintenanceLogsList.map(l => {
                    const ast = assetsList.find(x => x.id === l.asset_id);
                    const vnd = vendorsList.find(x => x.id === l.vendor_id);
                    return (
                      <tr key={l.id}>
                        <td>{new Date(l.service_date).toLocaleDateString()}</td>
                        <td><strong>{ast ? `${ast.name} (${ast.asset_code})` : l.asset_id}</strong></td>
                        <td>{vnd ? vnd.name : 'Internal / Direct'}</td>
                        <td>{l.description}</td>
                        <td>₹{l.cost || 0}</td>
                        <td>{l.performed_by || 'Staff'}</td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

function ResidentOperationsWidget({ user, triggerAlert }) {
  const [activeSubTab, setActiveSubTab] = useState('bookings');
  const [amenities, setAmenities] = useState([]);
  const [bookings, setBookings] = useState([]);
  const [tickets, setTickets] = useState([]);
  const [visitorLogs, setVisitorLogs] = useState([]);
  const [myUnits, setMyUnits] = useState([]);
  
  const [selectedAmenity, setSelectedAmenity] = useState('');
  const [selectedProperty, setSelectedProperty] = useState('');
  const [startTime, setStartTime] = useState('');
  const [endTime, setEndTime] = useState('');
  const [estimatedCharges, setEstimatedCharges] = useState(0);

  const [tCategory, setTCategory] = useState('plumbing');
  const [tPriority, setTPriority] = useState('medium');
  const [tTitle, setTTitle] = useState('');
  const [tDesc, setTDesc] = useState('');
  const [selectedUnit, setSelectedUnit] = useState('');

  const [selectedTicket, setSelectedTicket] = useState(null);
  const [comments, setComments] = useState([]);
  const [newComment, setNewComment] = useState('');

  const [preAuthCode, setPreAuthCode] = useState('');
  const [preAuthUnit, setPreAuthUnit] = useState('');

  useEffect(() => {
    loadResidentData();
  }, [activeSubTab]);

  useEffect(() => {
    calculateEstimatedCharges();
  }, [selectedAmenity, startTime, endTime]);

  const loadResidentData = async () => {
    try {
      const dbInstance = JSON.parse(localStorage.getItem('su_society_db')) || {};
      
      const ownedProps = dbInstance.property_owners.filter(po => po.owner_id === user.id && po.end_date === null).map(po => po.property_id);
      const leasedUnits = dbInstance.tenancies.filter(t => t.tenant_id === user.id && t.is_active).map(t => t.unit_id);
      const unitsList = dbInstance.units.filter(u => ownedProps.includes(u.property_id) || leasedUnits.includes(u.id));
      setMyUnits(unitsList);

      if (unitsList.length > 0) {
        if (!selectedUnit) setSelectedUnit(unitsList[0].id);
        if (!preAuthUnit) setPreAuthUnit(unitsList[0].id);
        const prop = dbInstance.properties.find(p => p.id === unitsList[0].property_id);
        if (prop && !selectedProperty) setSelectedProperty(prop.id);
      }

      if (activeSubTab === 'bookings') {
        const ams = await db.amenities.list(user);
        setAmenities(ams);
        if (ams.length > 0 && !selectedAmenity) setSelectedAmenity(ams[0].id);
        const bks = await db.amenity_bookings.list(user);
        setBookings(bks);
      } else if (activeSubTab === 'helpdesk') {
        const tks = await db.helpdesk_tickets.list(user);
        setTickets(tks);
      } else if (activeSubTab === 'visitors') {
        const vls = await db.visitor_logs.list(user);
        setVisitorLogs(vls);
      }
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const calculateEstimatedCharges = () => {
    if (!selectedAmenity || !startTime || !endTime) {
      setEstimatedCharges(0);
      return;
    }
    const amenity = amenities.find(a => a.id === selectedAmenity);
    if (!amenity) return;

    const start = new Date(startTime);
    const end = new Date(endTime);
    if (start >= end) {
      setEstimatedCharges(0);
      return;
    }

    const diffMs = end - start;
    if (amenity.booking_type === 'slot_based') {
      const diffHours = diffMs / 3600000;
      setEstimatedCharges(Math.round(diffHours * amenity.hourly_rate * 100) / 100);
    } else {
      const diffDays = Math.ceil(diffMs / 86400000);
      setEstimatedCharges(Math.round(diffDays * amenity.hourly_rate * 100) / 100);
    }
  };

  const handleBookAmenity = async (e) => {
    e.preventDefault();
    try {
      await db.amenity_bookings.create({
        amenity_id: selectedAmenity,
        property_id: selectedProperty,
        start_time: new Date(startTime).toISOString(),
        end_time: new Date(endTime).toISOString()
      }, user);
      triggerAlert('success', 'Booking submitted. Pending approval.');
      setStartTime('');
      setEndTime('');
      loadResidentData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCancelBooking = async (id) => {
    try {
      await db.amenity_bookings.cancel(id, user);
      triggerAlert('success', 'Booking cancelled.');
      loadResidentData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCreateTicket = async (e) => {
    e.preventDefault();
    try {
      await db.helpdesk_tickets.create({
        unit_id: selectedUnit,
        category: tCategory,
        priority: tPriority,
        title: tTitle,
        description: tDesc
      }, user);
      triggerAlert('success', 'Maintenance ticket logged.');
      setTTitle('');
      setTDesc('');
      loadResidentData();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleSelectTicket = async (ticket) => {
    setSelectedTicket(ticket);
    try {
      const cms = await db.ticket_comments.list(ticket.id, user);
      setComments(cms);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleAddComment = async (e) => {
    e.preventDefault();
    if (!newComment.trim()) return;
    try {
      await db.ticket_comments.create({
        ticket_id: selectedTicket.id,
        comment_text: newComment
      }, user);
      setNewComment('');
      const cms = await db.ticket_comments.list(selectedTicket.id, user);
      setComments(cms);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCloseTicket = async (ticketId) => {
    try {
      await db.helpdesk_tickets.close(ticketId, user);
      triggerAlert('success', 'Ticket closed.');
      loadResidentData();
      setSelectedTicket(null);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleReopenTicket = async (ticketId) => {
    try {
      await db.helpdesk_tickets.reopen(ticketId, user);
      triggerAlert('success', 'Ticket reopened.');
      loadResidentData();
      setSelectedTicket(null);
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleGeneratePreAuth = () => {
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    setPreAuthCode(code);
    
    const dbInstance = JSON.parse(localStorage.getItem('su_society_db'));
    if (dbInstance) {
      if (!dbInstance.pre_auth_codes) dbInstance.pre_auth_codes = [];
      dbInstance.pre_auth_codes.push({ code, unit_id: preAuthUnit, generated_by: user.id });
      localStorage.setItem('su_society_db', JSON.stringify(dbInstance));
    }
    triggerAlert('success', `Pre-authorization code ${code} generated successfully!`);
  };

  return (
    <div className="glass-panel" style={{ padding: '1.5rem', marginTop: '1.5rem', background: 'rgba(255,255,255,0.01)' }}>
      <h3 className="text-gradient">Operations Portal</h3>
      
      <div className="tabs-container" style={{ marginTop: '1rem', marginBottom: '1.25rem' }}>
        <button className={`tab-btn ${activeSubTab === 'bookings' ? 'active' : ''}`} onClick={() => setActiveSubTab('bookings')}>Book Amenities</button>
        <button className={`tab-btn ${activeSubTab === 'helpdesk' ? 'active' : ''}`} onClick={() => setActiveSubTab('helpdesk')}>Helpdesk Tickets</button>
        <button className={`tab-btn ${activeSubTab === 'visitors' ? 'active' : ''}`} onClick={() => setActiveSubTab('visitors')}>Pre-Auth Visitors</button>
      </div>

      {activeSubTab === 'bookings' && (
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 2fr', gap: '1.5rem' }}>
          <form onSubmit={handleBookAmenity} className="glass-panel" style={{ padding: '1rem', background: 'rgba(255,255,255,0.02)' }}>
            <h4>Request Slot</h4>
            <div className="form-group" style={{ marginTop: '1rem' }}>
              <label>Select Amenity</label>
              <select className="form-control" value={selectedAmenity} onChange={(e) => setSelectedAmenity(e.target.value)}>
                {amenities.map(a => (
                  <option key={a.id} value={a.id}>{a.name} (₹{a.hourly_rate}/hr)</option>
                ))}
              </select>
            </div>
            <div className="form-group">
              <label>Start Date & Time</label>
              <input type="datetime-local" className="form-control" value={startTime} onChange={(e) => setStartTime(e.target.value)} required />
            </div>
            <div className="form-group">
              <label>End Date & Time</label>
              <input type="datetime-local" className="form-control" value={endTime} onChange={(e) => setEndTime(e.target.value)} required />
            </div>

            <div style={{ marginTop: '1rem', padding: '0.75rem', background: 'rgba(255,255,255,0.05)', borderRadius: '4px' }}>
              <span>Estimated Charges: </span>
              <strong>₹{estimatedCharges}</strong>
            </div>

            <button type="submit" className="btn btn-primary" style={{ width: '100%', marginTop: '1rem' }}>Submit Booking</button>
          </form>

          <div>
            <h4>Your Bookings</h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem', marginTop: '1rem' }}>
              {bookings.length === 0 ? (
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>No booking requests submitted yet.</p>
              ) : (
                bookings.map(b => {
                  const am = amenities.find(a => a.id === b.amenity_id);
                  return (
                    <div key={b.id} className="glass-panel" style={{ padding: '0.75rem 1rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'rgba(255,255,255,0.02)' }}>
                      <div>
                        <strong>{am ? am.name : 'Amenity'}</strong>
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>{new Date(b.start_time).toLocaleString()} to {new Date(b.end_time).toLocaleTimeString()}</div>
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>Charges: ₹{b.total_charges}</div>
                      </div>
                      <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                        <span className={`badge badge-${b.status === 'approved' ? 'success' : b.status === 'pending_approval' ? 'warning' : 'secondary'}`}>{b.status}</span>
                        {b.status !== 'cancelled' && b.status !== 'completed' && (
                          <button className="btn btn-small btn-secondary" onClick={() => handleCancelBooking(b.id)}>Cancel</button>
                        )}
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </div>
      )}

      {activeSubTab === 'helpdesk' && (
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1.5rem' }}>
          <form onSubmit={handleCreateTicket} className="glass-panel" style={{ padding: '1rem', background: 'rgba(255,255,255,0.02)' }}>
            <h4>File Maintenance Ticket</h4>
            
            <div className="form-group" style={{ marginTop: '1rem' }}>
              <label>Select Unit</label>
              <select className="form-control" value={selectedUnit} onChange={(e) => setSelectedUnit(e.target.value)}>
                {myUnits.map(u => (
                  <option key={u.id} value={u.id}>{u.unit_name}</option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label>Category</label>
              <select className="form-control" value={tCategory} onChange={(e) => setTCategory(e.target.value)}>
                <option value="plumbing">Plumbing</option>
                <option value="electrical">Electrical</option>
                <option value="carpentry">Carpentry</option>
                <option value="security">Security</option>
                <option value="billing">Billing</option>
                <option value="other">Other</option>
              </select>
            </div>

            <div className="form-group">
              <label>Priority</label>
              <select className="form-control" value={tPriority} onChange={(e) => setTPriority(e.target.value)}>
                <option value="low">Low</option>
                <option value="medium">Medium</option>
                <option value="high">High</option>
                <option value="emergency">Emergency 🚨</option>
              </select>
            </div>

            <div className="form-group">
              <label>Subject</label>
              <input type="text" className="form-control" value={tTitle} onChange={(e) => setTTitle(e.target.value)} required />
            </div>

            <div className="form-group">
              <label>Details</label>
              <textarea className="form-control" rows={3} value={tDesc} onChange={(e) => setTDesc(e.target.value)} required />
            </div>

            <button type="submit" className="btn btn-primary" style={{ width: '100%', marginTop: '1rem' }}>Submit Ticket</button>
          </form>

          <div>
            <h4>Ticket Log</h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem', marginTop: '1rem', maxHeight: '300px', overflowY: 'auto' }}>
              {tickets.length === 0 ? (
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>No tickets filed yet.</p>
              ) : (
                tickets.map(t => (
                  <div key={t.id} 
                       onClick={() => handleSelectTicket(t)}
                       className={`glass-panel ${selectedTicket?.id === t.id ? 'active-border' : ''}`} 
                       style={{ padding: '0.75rem 1rem', cursor: 'pointer', background: 'rgba(255,255,255,0.02)' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                      <strong>{t.title}</strong>
                      <span className={`badge ${t.priority === 'emergency' ? 'badge-danger' : 'badge-warning'}`}>{t.priority}</span>
                    </div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: '0.25rem' }}>
                      <span>Status: {t.status}</span>
                      <span>{new Date(t.created_at).toLocaleDateString()}</span>
                    </div>
                  </div>
                ))
              )}
            </div>

            {selectedTicket && (
              <div className="glass-panel" style={{ padding: '1rem', marginTop: '1rem', background: 'rgba(255,255,255,0.03)' }}>
                <h5>Job Details: {selectedTicket.title}</h5>
                <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', margin: '0.5rem 0' }}>{selectedTicket.description}</p>
                <div style={{ display: 'flex', gap: '0.5rem' }}>
                  {selectedTicket.status === 'resolved' && (
                    <button className="btn btn-small btn-success" onClick={() => handleCloseTicket(selectedTicket.id)}>Close Ticket</button>
                  )}
                  {selectedTicket.status === 'closed' && (
                    <button className="btn btn-small btn-secondary" onClick={() => handleReopenTicket(selectedTicket.id)}>Reopen Ticket</button>
                  )}
                </div>

                <div style={{ marginTop: '1.5rem', borderTop: '1px solid rgba(255,255,255,0.05)', paddingTop: '0.5rem' }}>
                  <strong>Communications Log</strong>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', margin: '0.5rem 0', maxHeight: '100px', overflowY: 'auto' }}>
                    {comments.map(c => (
                      <div key={c.id} style={{ fontSize: '0.75rem', background: 'rgba(255,255,255,0.02)', padding: '0.3rem', borderRadius: '4px' }}>
                        {c.comment_text}
                      </div>
                    ))}
                  </div>
                  <form onSubmit={handleAddComment} style={{ display: 'flex', gap: '0.4rem' }}>
                    <input type="text" className="form-control form-control-small" placeholder="Add message..." value={newComment} onChange={(e) => setNewComment(e.target.value)} required />
                    <button type="submit" className="btn btn-secondary btn-small">Send</button>
                  </form>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {activeSubTab === 'visitors' && (
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1.5rem' }}>
          <div className="glass-panel" style={{ padding: '1rem', background: 'rgba(255,255,255,0.02)' }}>
            <h4>Generate Pre-Auth Code</h4>
            <div className="form-group" style={{ marginTop: '1rem' }}>
              <label>Select Unit</label>
              <select className="form-control" value={preAuthUnit} onChange={(e) => setPreAuthUnit(e.target.value)}>
                {myUnits.map(u => (
                  <option key={u.id} value={u.id}>{u.unit_name}</option>
                ))}
              </select>
            </div>
            
            <button className="btn btn-primary" style={{ width: '100%', marginTop: '1rem' }} onClick={handleGeneratePreAuth}>Generate 6-Digit Code</button>

            {preAuthCode && (
              <div style={{ marginTop: '1.5rem', textAlign: 'center', padding: '1rem', background: 'rgba(255,255,255,0.05)', border: '1px dashed var(--color-success)', borderRadius: '4px' }}>
                <span style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>Provide this code to your visitor:</span>
                <div style={{ fontSize: '2rem', fontWeight: 'bold', color: 'var(--color-success)', letterSpacing: '4px', marginTop: '0.5rem' }}>{preAuthCode}</div>
              </div>
            )}
          </div>

          <div>
            <h4>Visitor Activity Logs</h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem', marginTop: '1rem' }}>
              {visitorLogs.length === 0 ? (
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>No visitors registered for your unit.</p>
              ) : (
                visitorLogs.map(v => (
                  <div key={v.id} className="glass-panel" style={{ padding: '0.75rem 1rem', background: 'rgba(255,255,255,0.02)' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                      <strong>{v.visitor_name}</strong>
                      <span className={`badge ${v.check_out ? 'badge-secondary' : 'badge-success'}`}>{v.check_out ? 'Checked Out' : 'Active'}</span>
                    </div>
                    <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: '0.25rem' }}>
                      <span>Check In: {new Date(v.check_in).toLocaleString()}</span>
                      {v.check_out && <div>Check Out: {new Date(v.check_out).toLocaleString()}</div>}
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
// =========================================================================
// SLICE 20: NOC & MOVE PASS MANAGER VIEW
// =========================================================================
function NocManagerView({ user, triggerAlert }) {
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showApplyModal, setShowApplyModal] = useState(false);
  const [propertyId, setPropertyId] = useState('11111111-1111-1111-1111-111111111111');
  const [requestType, setRequestType] = useState('move_in');
  const [moveDate, setMoveDate] = useState(new Date().toISOString().split('T')[0]);
  const [reasonNotes, setReasonNotes] = useState('');

  // Gate Scanner state
  const [passCodeInput, setPassCodeInput] = useState('');
  const [vehicleInput, setVehicleInput] = useState('');
  const [moverInput, setMoverInput] = useState('');
  const [directionInput, setDirectionInput] = useState('out');
  const [generatedPasses, setGeneratedPasses] = useState({});

  const isAdmin = db_helpers.is_admin(user);
  const isGatekeeper = db_helpers.has_role(user, 'gatekeeper');

  const loadRequests = async () => {
    try {
      setLoading(true);
      const data = await db.noc.getRequests(user);
      setRequests(data);
    } catch (err) {
      triggerAlert('danger', err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadRequests();
  }, [user]);

  const handleApply = async (e) => {
    e.preventDefault();
    try {
      await db.noc.submitRequest(propertyId, requestType, moveDate, reasonNotes, user);
      triggerAlert('success', 'NOC request submitted successfully!');
      setShowApplyModal(false);
      loadRequests();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleDuesClearance = async (requestId) => {
    try {
      const res = await db.noc.performDuesClearance(requestId, user);
      triggerAlert('success', `Financial Dues Audit complete: ${res.remarks}`);
      loadRequests();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleUpdateChecklist = async (requestId, category, status) => {
    try {
      await db.noc.updateChecklistItem(requestId, category, status, 'Cleared by Admin', user);
      triggerAlert('success', `Checklist item ${category} updated to ${status}.`);
      loadRequests();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleApprove = async (requestId) => {
    try {
      await db.noc.approveRequest(requestId, user);
      triggerAlert('success', 'NOC request approved and digital certificate issued!');
      loadRequests();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleReject = async (requestId) => {
    const reason = prompt('Enter rejection reason:');
    if (!reason) return;
    try {
      await db.noc.rejectRequest(requestId, reason, user);
      triggerAlert('success', 'NOC request rejected.');
      loadRequests();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleCancel = async (requestId) => {
    if (!confirm('Are you sure you want to cancel this request?')) return;
    try {
      await db.noc.cancelRequest(requestId, user);
      triggerAlert('success', 'NOC request cancelled.');
      loadRequests();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleGeneratePass = async (requestId) => {
    try {
      const validFrom = new Date().toISOString();
      const validUntil = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
      const res = await db.noc.generateMovePass(requestId, validFrom, validUntil, 'MH-12-AB-1234', 'Express Logistics', user);
      setGeneratedPasses(prev => ({ ...prev, [requestId]: res.pass_code }));
      triggerAlert('success', `Move Pass Generated! 6-digit Code: ${res.pass_code}`);
      loadRequests();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  const handleVerifyPass = async (e) => {
    e.preventDefault();
    try {
      await db.noc.verifyMovePass(passCodeInput, vehicleInput, moverInput, directionInput, user);
      triggerAlert('success', 'Move Pass verified successfully at gate! Mover activity logged.');
      setPassCodeInput('');
      loadRequests();
    } catch (err) {
      triggerAlert('danger', err.message);
    }
  };

  return (
    <div className="glass-panel" style={{ padding: '1.5rem', marginTop: '1rem' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <div>
          <h2>📜 Digital NOC Clearance & Gate Move Passes</h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>
            Manage resident move-in, move-out, property sale NOCs, departmental sign-offs, and security gate move passes.
          </p>
        </div>
        <button className="btn btn-primary" onClick={() => setShowApplyModal(true)}>+ Apply for NOC</button>
      </div>

      {/* Gatekeeper Verification Panel */}
      {(isGatekeeper || isAdmin) && (
        <div className="glass-card" style={{ padding: '1rem', marginBottom: '1.5rem', borderLeft: '4px solid var(--color-primary)' }}>
          <h4>🛡️ Gatekeeper Move Pass Scanner</h4>
          <form onSubmit={handleVerifyPass} style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr auto', gap: '0.5rem', marginTop: '0.75rem', alignItems: 'center' }}>
            <input type="text" className="input-field" placeholder="Enter 6-digit Code" value={passCodeInput} onChange={e => setPassCodeInput(e.target.value)} required />
            <input type="text" className="input-field" placeholder="Vehicle Registration #" value={vehicleInput} onChange={e => setVehicleInput(e.target.value)} />
            <input type="text" className="input-field" placeholder="Mover Details" value={moverInput} onChange={e => setMoverInput(e.target.value)} />
            <select className="input-field" value={directionInput} onChange={e => setDirectionInput(e.target.value)}>
              <option value="out">Move-Out / Exit</option>
              <option value="in">Move-In / Entry</option>
            </select>
            <button type="submit" className="btn btn-success">Verify at Gate</button>
          </form>
        </div>
      )}

      {/* NOC Requests List */}
      {loading ? (
        <p>Loading NOC requests...</p>
      ) : requests.length === 0 ? (
        <p style={{ color: 'var(--text-secondary)', textAlign: 'center', padding: '2rem' }}>No NOC requests found.</p>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
          {requests.map(req => (
            <div key={req.id} className="glass-card" style={{ padding: '1.25rem' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                <div>
                  <span className={`badge ${req.request_type === 'move_in' ? 'badge-info' : req.request_type === 'move_out' ? 'badge-warning' : 'badge-primary'}`} style={{ marginRight: '0.5rem' }}>
                    {req.request_type.toUpperCase().replace('_', ' ')}
                  </span>
                  <span className={`badge ${req.status === 'approved' ? 'badge-success' : req.status === 'completed' ? 'badge-secondary' : req.status === 'rejected' ? 'badge-danger' : 'badge-warning'}`}>
                    {req.status.toUpperCase()}
                  </span>
                  <h4 style={{ marginTop: '0.5rem', marginBottom: '0.25rem' }}>NOC Request #{req.id.substring(0, 8)}</h4>
                  <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                    <span>Move Date: {req.move_date}</span> | <span>Submitted: {new Date(req.created_at).toLocaleDateString()}</span>
                  </div>
                  {req.reason_notes && <p style={{ fontSize: '0.85rem', marginTop: '0.5rem' }}><em>"{req.reason_notes}"</em></p>}
                </div>

                <div style={{ display: 'flex', gap: '0.5rem' }}>
                  {['submitted', 'dues_pending', 'clearance_in_progress'].includes(req.status) && (
                    <button className="btn btn-secondary btn-small" onClick={() => handleCancel(req.id)}>Cancel</button>
                  )}

                  {isAdmin && ['submitted', 'dues_pending', 'clearance_in_progress'].includes(req.status) && (
                    <>
                      <button className="btn btn-secondary btn-small" onClick={() => handleDuesClearance(req.id)}>Audit Dues</button>
                      <button className="btn btn-success btn-small" onClick={() => handleApprove(req.id)}>Approve NOC</button>
                      <button className="btn btn-danger btn-small" onClick={() => handleReject(req.id)}>Reject</button>
                    </>
                  )}

                  {req.status === 'approved' && (
                    <button className="btn btn-primary btn-small" onClick={() => handleGeneratePass(req.id)}>Generate Move Pass</button>
                  )}
                </div>
              </div>

              {/* Departmental Checklist Display */}
              <div style={{ marginTop: '1rem', paddingTop: '1rem', borderTop: '1px solid rgba(255,255,255,0.08)' }}>
                <h5 style={{ fontSize: '0.85rem', marginBottom: '0.5rem', color: 'var(--text-secondary)' }}>Departmental Clearance Checklist</h5>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '0.5rem' }}>
                  {(req.checklists || []).map(chk => (
                    <div key={chk.id} style={{ padding: '0.5rem 0.75rem', background: 'rgba(255,255,255,0.03)', borderRadius: '4px', border: '1px solid rgba(255,255,255,0.05)' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <strong style={{ fontSize: '0.75rem', textTransform: 'capitalize' }}>{chk.clearance_category.replace('_', ' ')}</strong>
                        <span className={`badge ${chk.status === 'cleared' ? 'badge-success' : chk.status === 'flagged' ? 'badge-danger' : 'badge-warning'}`} style={{ fontSize: '0.65rem' }}>
                          {chk.status}
                        </span>
                      </div>
                      {chk.remarks && <div style={{ fontSize: '0.7rem', color: 'var(--text-secondary)', marginTop: '0.25rem' }}>{chk.remarks}</div>}
                      {isAdmin && chk.status !== 'cleared' && chk.clearance_category !== 'financial_dues' && (
                        <button className="btn btn-secondary btn-small" style={{ fontSize: '0.65rem', marginTop: '0.4rem', padding: '0.1rem 0.4rem' }} onClick={() => handleUpdateChecklist(req.id, chk.clearance_category, 'cleared')}>
                          Mark Cleared
                        </button>
                      )}
                    </div>
                  ))}
                </div>
              </div>

              {/* Generated Pass Display */}
              {generatedPasses[req.id] && (
                <div style={{ marginTop: '0.75rem', padding: '0.75rem', background: 'rgba(0, 200, 100, 0.1)', border: '1px dashed var(--color-success)', borderRadius: '4px', textAlign: 'center' }}>
                  <span style={{ fontSize: '0.8rem' }}>One-Time Gate Move Pass Code:</span>
                  <div style={{ fontSize: '1.5rem', fontWeight: 'bold', color: 'var(--color-success)', letterSpacing: '4px' }}>{generatedPasses[req.id]}</div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Apply Modal */}
      {showApplyModal && (
        <div className="modal-backdrop" style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.7)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000 }}>
          <div className="glass-card" style={{ width: '450px', padding: '1.5rem' }}>
            <h3>Apply for Digital NOC</h3>
            <form onSubmit={handleApply} style={{ marginTop: '1rem', display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
              <div>
                <label style={{ fontSize: '0.8rem' }}>Request Type</label>
                <select className="input-field" value={requestType} onChange={e => setRequestType(e.target.value)}>
                  <option value="move_in">Move-In NOC</option>
                  <option value="move_out">Move-Out NOC</option>
                  <option value="property_sale_noc">Property Sale NOC</option>
                </select>
              </div>

              <div>
                <label style={{ fontSize: '0.8rem' }}>Move Date</label>
                <input type="date" className="input-field" value={moveDate} onChange={e => setMoveDate(e.target.value)} required />
              </div>

              <div>
                <label style={{ fontSize: '0.8rem' }}>Reason / Notes</label>
                <textarea className="input-field" rows="3" placeholder="Enter details or mover schedule..." value={reasonNotes} onChange={e => setReasonNotes(e.target.value)} />
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.5rem', marginTop: '1rem' }}>
                <button type="button" className="btn btn-secondary" onClick={() => setShowApplyModal(false)}>Cancel</button>
                <button type="submit" className="btn btn-primary">Submit NOC Request</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;

