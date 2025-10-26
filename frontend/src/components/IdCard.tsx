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
    position={[0, 0, 2.5]}
    rotation={[0, 0, 0]} // ✅ rotate the card
  >
    <mesh>
      <boxGeometry args={[7, 9, 0.12]} />
      <meshStandardMaterial
        color="#ffffff5d"
        roughness={0}
        metalness={0}
      />
    </mesh>

    <mesh position={[0, 0, -0.07]}>
      <planeGeometry args={[7, 9]} />
      <meshStandardMaterial color="#ffffff5d" />
    </mesh>

    <Html
  transform
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
        <div className="border">

     
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
