import React, { useMemo, useRef } from "react";
import { Html } from "@react-three/drei";
import { useFrame } from "@react-three/fiber";
import * as THREE from "three";

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

export const IdCard: React.FC<IdCardProps> = ({ twitter, wallets, earned, onLogout }) => {
  const shaderRef = useRef<THREE.ShaderMaterial>(null);

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

  return (
    <group position={[0, 0, 0]} rotation={[0, 0, 0]}>
      
      {/* === GLASS BODY WITH SHADER === */}
      <mesh>
        <boxGeometry args={[7, 9, 0.12]} />
        {/* Apply the custom shader material */}
        <primitive object={bubbleMaterial} ref={shaderRef} attach="material" />
      </mesh>

      {/* Soft backing plane (unchanged) */}
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

      {/* === UI LAYER (UNCHANGED) === */}
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
};