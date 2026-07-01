import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import Dashboard from './pages/Dashboard';
import ChildrenPage from './pages/Children';
import RewardPage from './pages/Reward';
import TransactionsPage from './pages/Transactions';
import RulesPage from './pages/Rules';
import StatsPage from './pages/Stats';
import SettingsPage from './pages/Settings';
import Layout from './components/Layout';
import './styles/global.css';

export default function App() {
  return (
    <BrowserRouter>
      <Layout>
        <Routes>
          <Route path="/" element={<Navigate to="/dashboard" replace />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/children" element={<ChildrenPage />} />
          <Route path="/reward" element={<RewardPage />} />
          <Route path="/transactions" element={<TransactionsPage />} />
          <Route path="/rules" element={<RulesPage />} />
          <Route path="/stats" element={<StatsPage />} />
          <Route path="/settings" element={<SettingsPage />} />
        </Routes>
      </Layout>
    </BrowserRouter>
  );
}
