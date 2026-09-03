import React from 'react';
import { ArrowDownCircle, Music2, Settings, HelpCircle } from 'lucide-react';
import { DownloadTabBadge } from '../types/models';

export type AppTab = 'getMusic' | 'playlists' | 'preferences' | 'help';

interface TabBarProps {
  selectedTab: AppTab;
  onSelectTab: (tab: AppTab) => void;
  badge: DownloadTabBadge;
}

export const TabBar: React.FC<TabBarProps> = ({ selectedTab, onSelectTab, badge }) => {
  const tabs = [
    { id: 'getMusic' as AppTab, title: 'Get Music', icon: ArrowDownCircle },
    { id: 'playlists' as AppTab, title: 'My Playlists', icon: Music2 },
    { id: 'preferences' as AppTab, title: 'Preferences', icon: Settings },
    { id: 'help' as AppTab, title: 'Help', icon: HelpCircle },
  ];

  const getBadgeColor = () => {
    if (selectedTab === 'getMusic') return null;
    switch (badge) {
      case 'inProgress': return 'bg-yellow-400';
      case 'success': return 'bg-green-500';
      case 'failure': return 'bg-red-500';
      default: return null;
    }
  };

  const badgeColor = getBadgeColor();

  return (
    <div className="flex justify-center pt-2.5 pb-2 select-none">
      <div className="inline-flex p-1 bg-[#2c2c2e]/60 backdrop-blur-md rounded-xl border border-white/10 shadow-sm">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const isSelected = selectedTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => onSelectTab(tab.id)}
              className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg text-sm font-medium transition-all duration-150 ${
                isSelected
                  ? 'bg-[#3a3a3c]/80 text-white shadow-sm font-semibold'
                  : 'text-neutral-400 hover:text-neutral-200 hover:bg-white/5'
              }`}
            >
              <Icon className="w-4 h-4" />
              <span>{tab.title}</span>
              {tab.id === 'getMusic' && badgeColor && (
                <span className={`w-2 h-2 rounded-full ${badgeColor} animate-pulse`} />
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
};
