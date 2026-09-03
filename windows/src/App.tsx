import React, { useState, useEffect } from 'react';
import { TabBar, AppTab } from './components/TabBar';
import { ToastBanner } from './components/ToastBanner';
import { ContactFooter } from './components/ContactFooter';
import { GetMusicView } from './views/GetMusicView';
import { PlaylistsView } from './views/PlaylistsView';
import { PreferencesView } from './views/PreferencesView';
import { HelpView } from './views/HelpView';
import { appStore } from './services/appStore';
import { downloadService } from './services/downloadService';

export const App: React.FC = () => {
  const [selectedTab, setSelectedTab] = useState<AppTab>('getMusic');
  const [tabBadge, setTabBadge] = useState(downloadService.tabBadge);
  const [toastMessage, setToastMessage] = useState(downloadService.toastMessage);
  const [toastVisible, setToastVisible] = useState(downloadService.toastVisible);

  useEffect(() => {
    appStore.init();

    const unsubDownload = downloadService.subscribe(() => {
      setTabBadge(downloadService.tabBadge);
      setToastMessage(downloadService.toastMessage);
      setToastVisible(downloadService.toastVisible);

      if (downloadService.requestShowGetMusic) {
        setSelectedTab('getMusic');
        downloadService.requestShowGetMusic = false;
      }
    });

    return unsubDownload;
  }, []);

  const handleSelectTab = (tab: AppTab) => {
    setSelectedTab(tab);
    if (tab === 'getMusic') {
      downloadService.clearTabBadge();
    }
  };

  return (
    <div className="flex flex-col h-screen w-screen bg-[#1c1c1e] text-[#f2f2f7] overflow-hidden select-none">
      {/* Tab Bar */}
      <TabBar
        selectedTab={selectedTab}
        onSelectTab={handleSelectTab}
        badge={tabBadge}
      />

      {/* Main View Container */}
      <main className="flex-1 flex overflow-hidden">
        {selectedTab === 'getMusic' && <GetMusicView />}
        {selectedTab === 'playlists' && <PlaylistsView />}
        {selectedTab === 'preferences' && <PreferencesView />}
        {selectedTab === 'help' && <HelpView />}
      </main>

      {/* Floating Toast Notification */}
      <ToastBanner message={toastMessage} visible={toastVisible} />

      {/* Persistent Contact Footer */}
      <ContactFooter />
    </div>
  );
};
