import { type ReactNode } from 'react';

interface CardProps {
  children: ReactNode;
  className?: string;
}

interface StatCardProps {
  title: string;
  value: string | number;
  icon: string;
  color: 'blue' | 'green' | 'orange' | 'red' | 'purple';
  className?: string;
}

export function Card({ children, className = '' }: CardProps) {
  return (
    <div className={`bg-white rounded-lg shadow-sm border border-gray-100 ${className}`}>
      {children}
    </div>
  );
}

const colorMap: Record<string, string> = {
  blue: 'bg-[#4A90D9]/10 text-[#4A90D9]',
  green: 'bg-[#7ED321]/10 text-[#7ED321]',
  orange: 'bg-[#F5A623]/10 text-[#F5A623]',
  red: 'bg-[#E74C3C]/10 text-[#E74C3C]',
  purple: 'bg-purple-500/10 text-purple-500',
};

export function StatCard({ title, value, icon, color, className = '' }: StatCardProps) {
  return (
    <Card className={`p-4 sm:p-5 ${className}`}>
      <div className="flex items-center justify-between">
        <div>
          <p className="text-sm text-gray-500 mb-1">{title}</p>
          <p className="truncate text-xl font-bold text-gray-900 sm:text-2xl">{value}</p>
        </div>
        <div className={`w-10 h-10 rounded-lg flex items-center justify-center text-xl sm:h-12 sm:w-12 sm:text-2xl ${colorMap[color]}`}>
          {icon}
        </div>
      </div>
    </Card>
  );
}
