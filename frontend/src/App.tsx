import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import Dashboard from './pages/Dashboard';
import ChildrenPage from './pages/Children';
import FamilyGroupsPage from './pages/FamilyGroups';
import RewardPage from './pages/Reward';
import TransactionsPage from './pages/Transactions';
import RulesPage from './pages/Rules';
import StatsPage from './pages/Stats';
import SettingsPage from './pages/Settings';
import AssistantPage from './pages/Assistant';
import IdentityPage from './pages/Identity';
import VirtualWatchPage from './pages/VirtualWatch';
import WatchReleasePage from './pages/WatchRelease';
import IdentityGate from './components/IdentityGate';
import Layout from './components/Layout';
import ProtectedRoute from './components/ProtectedRoute';
import { AuthProvider } from './contexts/AuthContext';
import { FamilyGroupProvider } from './contexts/FamilyGroupContext';
import './styles/global.css';

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route
            path="/identity"
            element={
              <ProtectedRoute>
                <IdentityPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/*"
            element={
              <ProtectedRoute>
                <IdentityGate>
                  <FamilyGroupProvider>
                    <Layout>
                      <Routes>
                        <Route path="/" element={<Navigate to="/dashboard" replace />} />
                        <Route path="/dashboard" element={<Dashboard />} />
                        <Route path="/family-groups" element={<FamilyGroupsPage />} />
                        <Route path="/children" element={<ChildrenPage />} />
                        <Route path="/reward" element={<RewardPage />} />
                        <Route path="/transactions" element={<TransactionsPage />} />
                        <Route path="/rules" element={<RulesPage />} />
                        <Route path="/stats" element={<StatsPage />} />
                        <Route path="/settings" element={<SettingsPage />} />
                        <Route path="/virtual-watch" element={<VirtualWatchPage />} />
                        <Route path="/watch-release" element={<WatchReleasePage />} />
                        <Route path="/assistant/*" element={<AssistantPage />} />
                      </Routes>
                    </Layout>
                  </FamilyGroupProvider>
                </IdentityGate>
              </ProtectedRoute>
            }
          />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
