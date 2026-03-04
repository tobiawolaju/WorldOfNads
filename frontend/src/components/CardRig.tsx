import React, { ReactNode, useRef } from "react";
import { useThree, useFrame } from "@react-three/fiber";
import * as THREE from "three";

interface Props {
  children: ReactNode;
}

export default function CardRig({ children }: Props) {
  const { camera } = useThree();
  const group = useRef<THREE.Group>(null!);

  useFrame(() => {
    const factor = 0.01; // 10% motion — adjust if needed

    group.current.rotation.x = camera.rotation.x * factor;
    group.current.rotation.y = camera.rotation.y * factor;
    group.current.rotation.z = 0;
  });

  return <group ref={group}>{children}</group>;
}