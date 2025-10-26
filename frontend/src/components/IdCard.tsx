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
  <group position={[0, -3, 2.5]} rotation={[0, 0, 0]}>
    
    {/* === GLASS BODY (3D OBJECT) === */}
    <mesh>
      <boxGeometry args={[7, 9, 0.12]} />
      <meshPhysicalMaterial
        color="#ffffff"
        transparent
        opacity={0.25}
        roughness={0.05}
        metalness={0.5}
        transmission={0.9}
        thickness={0.4}
        clearcoat={1}
        clearcoatRoughness={0.05}
      />
    </mesh>

    {/* Soft backing plane */}
    <mesh position={[0, 0, -0.07]}>
      <planeGeometry args={[7, 9]} />
      <meshPhysicalMaterial
        color="#ffffff"
        transparent
        opacity={0.15}
        roughness={0.1}
        metalness={0.2}
        transmission={0.85}
        thickness={0.2}
      />
    </mesh>

    {/* === UI LAYER === */}
    <Html
      transform
						center
      occlude
      position={[0, 0, 0.07]}
      zIndexRange={[0, 0]}
      style={{
        width: "280px",
        height: "320px",
        userSelect: "none",
      }}
    >
      <div className="id-card-container">
        <div className="id-card-inner">

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
      </div>
    </Html>
  </group>
);