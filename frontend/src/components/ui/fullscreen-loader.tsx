import React, { useEffect, useState } from 'react';

type FullScreenLoaderProps = {
  visible?: boolean;
};

export const FullScreenLoader = ({ visible = true }: FullScreenLoaderProps) => {
  const [shouldRender, setShouldRender] = useState(visible);

  useEffect(() => {
    if (visible) {
      setShouldRender(true);
      return;
    }

    const timeoutId = window.setTimeout(() => {
      setShouldRender(false);
    }, 280);

    return () => window.clearTimeout(timeoutId);
  }, [visible]);

  if (!shouldRender) return null;

  return (
    <>
      <style>
        {`
          :root {
            --loader-shadow: 0 16px 40px rgba(0, 0, 0, 0.12);
          }

          @media (prefers-color-scheme: dark) {
            :root {
              --loader-shadow: 0 16px 40px rgba(0, 0, 0, 0.28);
            }
          }

          .loader-overlay {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100vh;
            background-color: var(--background);
            color: var(--foreground);
            display: flex;
            justify-content: center;
            align-items: center;
            z-index: 9999;
            opacity: 0;
            transform: scale(0.99);
            transition: opacity 280ms ease, transform 280ms ease;
            pointer-events: auto;
          }

          .loader-overlay[data-visible="true"] {
            opacity: 1;
            transform: scale(1);
          }

          @keyframes fadeInOut {
            0% { opacity: 0.3; transform: scale(0.95); }
            50% { opacity: 1; transform: scale(1); }
            100% { opacity: 0.3; transform: scale(0.95); }
          }

          .loader-logo {
            animation: fadeInOut 2s infinite ease-in-out;
            object-fit: contain;
            width: 20vw;
            height: auto;
            filter: drop-shadow(var(--loader-shadow));
          }

          @media (min-width: 768px) {
            .loader-logo {
              width: auto;
              height: 20vh;
            }
          }
        `}
      </style>

      <div className="loader-overlay" data-visible={visible ? "true" : "false"}>
        <img 
          src="/logo.jpg" 
          alt="Loading..." 
          className="loader-logo"
        />
      </div>
    </>
  );
};
