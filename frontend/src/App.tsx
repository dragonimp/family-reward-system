import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import Dashboard from './pages/Dashboard';
import ChildrenPage from './pages/Children';
import CreditPage from './pages/Credit';
import FamilyGroupsPage from './pages/FamilyGroups';
import GenealogyPage from './pages/Genealogy';
import GenealogyInvitationPage from './pages/GenealogyInvitation';
import DearSocialPage from './pages/DearSocial';
import RewardPage from './pages/Reward';
import TransactionsPage from './pages/Transactions';
import RulesPage from './pages/Rules';
import StatsPage from './pages/Stats';
import GrowthPage from './pages/Growth';
import FamilyConnectionsPage from './pages/FamilyConnections';
import SettingsPage from './pages/Settings';
import AssistantPage from './pages/Assistant';
import IdentityPage from './pages/Identity';
import VirtualWatchPage from './pages/VirtualWatch';
import XiaotiancaiDeviceTestApplicationPage from './pages/XiaotiancaiDeviceTestApplication';
import AdminPage from './pages/Admin';
import MySubscriptionPage from './pages/MySubscription';
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
          <Route path="/genealogy/invite/:token" element={<ProtectedRoute><GenealogyInvitationPage /></ProtectedRoute>} />
          <Route
            path="/dear"
            element={<ProtectedRoute><DearSocialPage /></ProtectedRoute>}
          />
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
                        <Route path="/genealogy" element={<GenealogyPage />} />
                        <Route path="/children" element={<ChildrenPage />} />
                        <Route path="/credit/:childId" element={<CreditPage />} />
                        <Route path="/reward" element={<RewardPage />} />
                        <Route path="/transactions" element={<TransactionsPage />} />
                        <Route path="/rules" element={<RulesPage />} />
                        <Route path="/stats" element={<StatsPage />} />
                        <Route path="/growth" element={<GrowthPage />} />
                        <Route path="/family-connections" element={<FamilyConnectionsPage />} />
                        <Route path="/settings" element={<SettingsPage />} />
                        <Route path="/virtual-watch" element={<VirtualWatchPage />} />
                        <Route path="/xiaotiancai-device-test" element={<XiaotiancaiDeviceTestApplicationPage />} />
                        <Route path="/admin" element={<AdminPage />} />
                        <Route path="/my-subscription" element={<MySubscriptionPage />} />
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
