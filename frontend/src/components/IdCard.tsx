import React from "react";
import { Html } from "@react-three/drei";

interface Twitter {
  profilePictureUrl?: string;
  name?: string;
  username?: string;
}

interface Wallet {
  address: string;
}

interface IdCardProps {
  twitter: Twitter | undefined;
  wallets: Wallet[];
  earned: number;
  onLogout: () => void;
}

export const IdCard: React.FC<IdCardProps> = ({ twitter, wallets, earned, onLogout }) => (
  <mesh rotation={[-0.5, 0, 0.3]}>
    <boxGeometry args={[4, 2.5, 0.1]} />
    <meshStandardMaterial transparent opacity={0} />
    <Html
      transform
      occlude
      position={[0, -5, 5]}
      style={{
        width: "300px",
        userSelect: "none",
      }}
    >
      <div className="id-card-container">
        <img src={twitter?.profilePictureUrl || "/default-avatar.png"} className="id-card-avatar" alt="Avatar" />
        <div className="id-card-name">{twitter?.name || "Player"}</div>
        <div className="id-card-handle">@{twitter?.username}</div>
        <div className="id-card-wallets">
          {wallets.map((w, i) => (
            <div key={i}>{w.address.slice(0, 6)}...{w.address.slice(-4)}</div>
          ))}
        </div>
        <div className="id-card-earned">{earned.toLocaleString()} WONs Earned</div>

        <button className="id-card-logout-button" onClick={onLogout}>
          Logout
        </button>
      </div>
    </Html>
  </mesh>
);
