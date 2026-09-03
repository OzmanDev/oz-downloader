import React from 'react';
import { CheckCircle2, AlertTriangle, Copy, ArrowDownCircle, UserCheck } from 'lucide-react';

interface ToastBannerProps {
  message: string;
  visible: boolean;
}

export const ToastBanner: React.FC<ToastBannerProps> = ({ message, visible }) => {
  if (!visible || !message) return null;

  const getIcon = () => {
    const msg = message.toLowerCase();
    if (msg.includes('copied')) return Copy;
    if (msg.includes('failed') || msg.includes('error') || msg.includes('couldn’t') || msg.includes("couldn't")) {
      return AlertTriangle;
    }
    if (msg.includes('saved') || msg.includes('completed')) return CheckCircle2;
    if (msg.includes('sign')) return UserCheck;
    return ArrowDownCircle;
  };

  const Icon = getIcon();

  return (
    <div className="fixed top-12 left-1/2 -translate-x-1/2 z-50 animate-in fade-in duration-150">
      <div className="flex items-center gap-2.5 px-4 py-2.5 rounded-xl bg-[#2c2c2e]/95 border border-white/10 shadow-2xl text-sm font-medium text-white backdrop-blur-md">
        <Icon className="w-4 h-4 text-sky-400" />
        <span>{message}</span>
      </div>
    </div>
  );
};
