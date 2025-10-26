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
  <group
    position={[0, 0, 5]}
    rotation={[-0.5, 0.5, -0.25]} // ✅ rotate the card
  >
    <mesh>
      <boxGeometry args={[7, 8, 0.12]} />
      <meshStandardMaterial
        color="#5a00a6"
        roughness={0.35}
        metalness={0.25}
      />
    </mesh>

    <mesh position={[0, 0, -0.07]}>
      <planeGeometry args={[7, 8]} />
      <meshStandardMaterial color="#1f0034" />
    </mesh>

    <Html
      transform
      occlude
      position={[0, 0, 0.07]}
      style={{
        width: "280px",
        height: "320px",
        userSelect: "none",
      }}
    >
      <div className="id-card-container">
        <button className="id-card-logout-button" onClick={onLogout}>
          Logout
        </button>

        <img
          src={twitter?.profilePictureUrl || "/default-avatar.png"}
          className="id-card-avatar"
          alt="Avatar"
        />

        <div className="id-card-name">{twitter?.name || "Player"}</div>
        <div className="id-card-handle">@{twitter?.username}</div>

        <div className="id-card-wallets">
          {wallets.map((w, i) => (
            <div key={i}>
              {w.address.slice(0, 6)}...{w.address.slice(-4)}
            </div>
          ))}
        </div>

        <div className="id-card-earned">
          {earned.toLocaleString()} MON Earned
        </div>
      </div>
    </Html>
  </group>
);
