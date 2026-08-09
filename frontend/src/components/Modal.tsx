import { type ReactNode } from 'react';

interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  footer?: ReactNode;
}

export function Modal({ isOpen, onClose, title, children, footer }: ModalProps) {
  if (!isOpen) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center p-2 sm:items-center sm:p-4">
      <div className="fixed inset-0 bg-black/50" onClick={onClose} />
      <div className="relative bg-white rounded-lg shadow-xl w-full max-w-md max-h-[90vh] overflow-auto">
        <div className="flex items-center justify-between p-4 sm:p-5 border-b border-gray-200">
          <h3 className="text-lg font-semibold text-gray-900">{title}</h3>
          <button onClick={onClose} className="p-1 rounded-lg hover:bg-gray-100 text-gray-400" aria-label="关闭">✕</button>
        </div>
        <div className="p-4 sm:p-5">{children}</div>
        {footer && (
          <div className="flex flex-col-reverse gap-2 p-4 border-t border-gray-200 sm:flex-row sm:items-center sm:justify-end sm:gap-3 sm:p-5">
            {footer}
          </div>
        )}
      </div>
    </div>
  );
}
