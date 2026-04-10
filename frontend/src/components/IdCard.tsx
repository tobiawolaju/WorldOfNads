import React, { useEffect, useMemo, useRef, useState } from "react";
import { Html } from "@react-three/drei";
import { useFrame } from "@react-three/fiber";
import * as THREE from "three";
import { useNavigate } from "react-router-dom";
import { fetchUserRoles } from "../pages/firebaseClient";

// --- Prop and Type Interfaces ---
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
  username: string;
  onLogout: () => void;
}

// --- Shader Definition for Water Bubble Effect ---
const vertexShader = `
  varying vec3 vNormal;
  varying vec3 vViewPosition;
  void main() {
    vec4 modelViewPosition = modelViewMatrix * vec4(position, 1.0);
    vViewPosition = -modelViewPosition.xyz;
    vNormal = normalize(normalMatrix * normal);
    gl_Position = projectionMatrix * modelViewPosition;
  }
`;

const fragmentShader = `
  precision mediump float;
  uniform float uTime;
  varying vec3 vNormal;
  varying vec3 vViewPosition;
  void main() {
    vec3 viewDir = normalize(vViewPosition);
    float fresnel = 1.0 - dot(viewDir, vNormal);
    fresnel = pow(fresnel, 2.5); // Increase power for sharper edge
    
    // Rainbow color effect driven by fresnel and time
    vec3 color;
    color.r = sin(fresnel * 5.0 - uTime * 0.5) * 0.5 + 0.5;
    color.g = sin(fresnel * 5.0 - uTime * 0.5 + 2.094) * 0.5 + 0.5; // 120 degrees offset
    color.b = sin(fresnel * 5.0 - uTime * 0.5 + 4.188) * 0.5 + 0.5; // 240 degrees offset
    
    // Adjust alpha for the card to be slightly more opaque for readability
    gl_FragColor = vec4(color, fresnel * 0.8 + 0.1);
  }
`;

export const IdCard: React.FC<IdCardProps> = ({ twitter, wallets, earned, username, onLogout }) => {
  const shaderRef = useRef<THREE.ShaderMaterial>(null);
  const [copied, setCopied] = useState(false);
  const [roles, setRoles] = useState<string[]>([]);
  const navigate = useNavigate();

  useEffect(() => {
    let mounted = true;
    if (!username) return;
    fetchUserRoles(username)
      .then((data) => {
        if (mounted) setRoles(data || []);
      })
      .catch(() => {});
    return () => {
      mounted = false;
    };
  }, [username]);

  // Animate the shader's time uniform
  useFrame(({ clock }) => {
    if (shaderRef.current) {
      shaderRef.current.uniforms.uTime.value = clock.getElapsedTime();
    }
  });

  // Memoize the material to prevent it from being recreated on every render
  const bubbleMaterial = useMemo(() => new THREE.ShaderMaterial({
    uniforms: {
      uTime: { value: 0 },
    },
    vertexShader,
    fragmentShader,
    transparent: true,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
  }), []);

  // Cleanup effect for GPU memory
  useEffect(() => {
    return () => {
      bubbleMaterial.dispose();
    };
  }, [bubbleMaterial]);

  return (
    <group position={[0, 0, 0]} rotation={[0, 0, 0]}>

      {/* === GLASS BODY WITH SHADER === */}
      <mesh>
        <boxGeometry args={[9.5, 5.5, 0.12]} />
        {/* Apply the custom shader material */}
        <primitive object={bubbleMaterial} ref={shaderRef} attach="material" />
      </mesh>

      {/* Soft backing plane (unchanged) */}
      <mesh position={[0, 0, -0.07]}>
        <planeGeometry args={[9.5, 5.5]} />
        <meshPhysicalMaterial
          color="#ffd900"
          transparent
          opacity={1}
          roughness={0.1}
          metalness={0.2}
          transmission={0.85}
          thickness={0.2}
        />
      </mesh>

      {/* === UI LAYER (UNCHANGED) === */}
      <Html
        transform
        center
        occlude
        position={[0, 0, 0.07]}
        zIndexRange={[0, 0]}
        style={{
          width: "380px",
          height: "220px",
          userSelect: "none",
        }}
      >

        <div className="golden-ticket-container">
          <div className="ticket-main">
            <div className="ticket-header">
              <h1 className="ticket-title">WONs Ticket</h1>
            </div>

            <div className="ticket-content">
              <img
                src={twitter?.profilePictureUrl || "/default-avatar.png"}
                className="ticket-avatar"
                alt="Avatar"
              />

              <div className="ticket-info">
                <div className="ticket-name">{twitter?.name || "Player"}</div>
                <div className="ticket-handle">@{twitter?.username || "guest"}</div>
                <div className="ticket-wallets">
                  {wallets.length > 0 ? (
                    <div 
                      className="evm-address-container"
                      onClick={() => {
                        const addr = wallets[0].address;
                        navigator.clipboard.writeText(addr);
                        setCopied(true);
                        setTimeout(() => setCopied(false), 2000);
                      }}
                      style={{ 
                        cursor: "pointer", 
                        display: "flex", 
                        alignItems: "center", 
                        gap: "6px",
                        fontSize: "12px",
                        background: "rgba(255, 255, 255, 0.1)",
                        padding: "4px 10px",
                        borderRadius: "12px",
                        marginTop: "4px",
                        border: "1px solid rgba(255, 255, 255, 0.2)"
                      }}
                    >
                      <span>
                        {copied 
                          ? "Copied!" 
                          : `${wallets[0].address.slice(0, 6)}...${wallets[0].address.slice(-4)}`
                        }
                      </span>
                      {!copied && (
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                          <path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"></path>
                          <rect x="8" y="2" width="8" height="4" rx="1" ry="1"></rect>
                        </svg>
                      )}
                    </div>
                  ) : (
                    <div style={{ fontSize: "10px", opacity: 0.6 }}>No Wallet</div>
                  )}
                </div>
              </div>
            </div>


          </div>

          <div className="ticket-stub">
            <div className="stub-earned">
              {earned.toFixed(4)}
              <span>MON Balance</span>
            </div>
          </div>

        </div>
        <div className="ticket-action-bar">
          {roles.includes("admin") && (
            <>
              <button className="ticket-action-button" onClick={() => navigate("/admin/users")}>
                Admin Users
              </button>
              <button className="ticket-action-button" onClick={() => navigate("/admin/analytics")}>
                Analytics
              </button>
            </>
          )}
          {roles.includes("sponsor") && (
            <button className="ticket-action-button" onClick={() => navigate("/sponsor")}>
              Host Match
            </button>
          )}
          <button className="ticket-action-button" onClick={onLogout}>
            Logout
          </button>
        </div>


      </Html>
    </group>
  );
};
