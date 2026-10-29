import React from "react";
import { toast } from "react-toastify";

type ToastVariant = "success" | "error";

interface CustomToastProps {
  message: string;
  variant?: ToastVariant;
}

export const CustomToast: React.FC<CustomToastProps & { closeToast?: () => void }> = ({
  message,
  variant = "success",
  closeToast,
}) => {
  const isError = variant === "error";

  const containerClasses = [
    "flex",
    "items-center",
    "gap-2.5",
    "min-w-0",
    "w-auto",
    "max-w-[340px]",
    "px-3.5",
    "py-2.5",
    "rounded-none",
    "border-2",
    "border-r-[3.5px]",
    "backdrop-blur-md",
    isError
      ? "bg-[#180914]/95 border-[#ff4757] text-[#ffe4e6] shadow-[0_6px_20px_rgba(0,0,0,0.6),0_0_12px_rgba(255,71,87,0.25)]"
      : "bg-[#130d24]/95 border-[#ff7ab6] text-white shadow-[0_6px_20px_rgba(0,0,0,0.6),0_0_12px_rgba(255,122,182,0.25)]",
  ].join(" ");

  const textClasses = [
    "text-xs",
    "sm:text-sm",
    "font-bold",
    "tracking-wide",
    "flex-1",
    "break-words",
    "overflow-hidden",
    "leading-snug",
  ].join(" ");

  return (
    <div className={containerClasses}>
      <div className="shrink-0 flex items-center justify-center w-5 h-5" aria-hidden>
        {isError ? (
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
            <path
              d="M12 8v5M12 16h.01M12 3l9 17H3L12 3z"
              stroke="#ff4757"
              strokeWidth="2.2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        ) : (
          <svg width="18" height="18" viewBox="0 0 20 20" fill="none">
            <path
              d="M16.5 5.5L7.5 14.5L3.5 10.5"
              stroke="#ff7ab6"
              strokeWidth="2.4"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        )}
      </div>
      <div className={textClasses}>{message}</div>
      <button
        type="button"
        aria-label="Close"
        className="flex h-5 w-5 items-center justify-center shrink-0 text-white/50 hover:text-white transition-colors"
        onClick={() => closeToast?.()}
      >
        <svg width="13" height="13" viewBox="0 0 16 16" fill="none">
          <path
            d="M12 4L4 12M4 4L12 12"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </button>
    </div>
  );
};

export const showSuccessToast = (message: string) => {
  toast(<CustomToast message={message} variant="success" />, {
    position: "top-center",
    autoClose: 3200,
    hideProgressBar: true,
    closeOnClick: false,
    pauseOnHover: true,
    draggable: false,
    closeButton: false,
    icon: false,
    className: "bg-transparent shadow-none p-0 m-0",
    style: {
      background: "transparent",
      boxShadow: "none",
      width: "auto",
      maxWidth: "340px",
      padding: 0,
    },
  });
};

export const showErrorToast = (message: string) => {
  toast(<CustomToast message={message} variant="error" />, {
    position: "top-center",
    autoClose: 3600,
    hideProgressBar: true,
    closeOnClick: false,
    pauseOnHover: true,
    draggable: false,
    closeButton: false,
    icon: false,
    className: "bg-transparent shadow-none p-0 m-0 mt-2",
    style: {
      background: "transparent",
      boxShadow: "none",
      width: "auto",
      maxWidth: "340px",
      padding: 0,
    },
  });
};

// Backwards compatible default
export const showCustomToast = (message: string) => showSuccessToast(message);
