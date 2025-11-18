import React, { useState } from "react";
import { LineChart, Line, ResponsiveContainer, Tooltip } from "recharts";
import "./Leaderboard.css";

interface Project {
  name: string;
  interactions: number;
  trend: number[];
  logo: string;
}

interface User {
  username: string;
  won: number;
  project: string;
  pfp: string;
}

const Leaderboard: React.FC = () => {
  const projects: Project[] = [
    { name: "Monad", interactions: 185, trend: [120, 140, 150, 160, 170, 180, 185], logo: "https://pbs.twimg.com/profile_images/1861739634428174336/26FzLLyr.jpg" },
    { name: "LootGO", interactions: 260, trend: [180, 190, 210, 230, 240, 255, 260], logo: "https://pbs.twimg.com/profile_images/1947490514921488384/TLSJg7Z5.jpg" },
    { name: "Nad.fun", interactions: 300, trend: [200, 220, 240, 260, 280, 290, 300], logo: "https://pbs.twimg.com/profile_images/1827607782356619264/Owr-840k.jpg" },
    { name: "Kizzy Mobile", interactions: 155, trend: [90, 100, 110, 120, 135, 145, 155], logo: "https://pbs.twimg.com/profile_images/1889975983941591040/NeddfENS.jpg" },
    { name: "Kuru Exchange", interactions: 130, trend: [70, 80, 95, 105, 115, 125, 130], logo: "https://pbs.twimg.com/profile_images/1950962142917619714/R7Cj_qk7.jpg" },
    { name: "Lumiterra", interactions: 175, trend: [110, 120, 130, 145, 155, 165, 175], logo: "https://pbs.twimg.com/profile_images/1667436896480563200/8YPmbLbv.png" },
    { name: "Levr Bet", interactions: 90, trend: [50, 60, 65, 70, 75, 85, 90], logo: "https://pbs.twimg.com/profile_images/1836024387042004992/YKdDMkOG.jpg" },
    { name: "Drake Exchange", interactions: 210, trend: [150, 160, 170, 180, 190, 200, 210], logo: "https://pbs.twimg.com/profile_images/1974759389354491904/2vcC-dd4.jpg" },
    { name: "Omnia Explorer", interactions: 140, trend: [80, 90, 95, 110, 120, 135, 140], logo: "https://pbs.twimg.com/profile_images/1796709016808394752/C91LWB9H.jpg" },
    { name: "SeerTrade", interactions: 125, trend: [70, 75, 85, 95, 105, 115, 125], logo: "https://pbs.twimg.com/profile_images/1957497669959761920/IMS0lJhe.jpg" },
    { name: "Monday Trade", interactions: 105, trend: [60, 70, 75, 85, 90, 95, 105], logo: "https://pbs.twimg.com/profile_images/1973421191202209797/qRXSiR5e.jpg" },
    { name: "Symphony", interactions: 170, trend: [110, 125, 130, 145, 150, 160, 170], logo: "https://pbs.twimg.com/profile_images/1893386930605211648/-APwnLNM.jpg" },
    { name: "Kinetik AI", interactions: 190, trend: [120, 130, 140, 155, 165, 175, 190], logo: "https://pbs.twimg.com/profile_images/1947607859702673408/hpZ89aya.jpg" },
    { name: "TeleMafia", interactions: 160, trend: [95, 110, 120, 130, 140, 150, 160], logo: "https://pbs.twimg.com/profile_images/1967887075316994050/STzEqU1y.jpg" },
    { name: "Fluffle World", interactions: 210, trend: [140, 150, 165, 175, 185, 200, 210], logo: "https://pbs.twimg.com/profile_images/1972672305336569856/JLjBcagi.jpg" },
    { name: "BRO.fun", interactions: 135, trend: [75, 85, 95, 110, 120, 130, 135], logo: "https://pbs.twimg.com/profile_images/1983519855279042560/ntgzrOaU.jpg" },
    { name: "RareBet Sports", interactions: 250, trend: [180, 190, 200, 210, 220, 235, 250], logo: "https://pbs.twimg.com/profile_images/1802788848956506112/KJnlcaQj.jpg" }
  ];



  const allUsers: User[] = [
    { username: "0xSolarKnight", won: 870, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/11.jpg" },
    { username: "0xPrimeSeeker", won: 860, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/32.jpg" },
    { username: "0xApexSpectral", won: 855, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/44.jpg" },
    { username: "0xNovaWarden", won: 845, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/women/22.jpg" },
    { username: "0xQuantumPulse", won: 842, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/53.jpg" },

    { username: "0xDriftCipher", won: 835, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/73.jpg" },
    { username: "0xEchoHarbinger", won: 830, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/65.jpg" },
    { username: "0xSilentNova", won: 824, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/77.jpg" },
    { username: "0xRiftSentinel", won: 821, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/women/81.jpg" },
    { username: "0xStormDriller", won: 818, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/83.jpg" },

    { username: "0xNightVigil", won: 810, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/57.jpg" },
    { username: "0xFuryVector", won: 808, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/85.jpg" },
    { username: "0xIronSpectre", won: 805, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/45.jpg" },
    { username: "0xDripSamurai", won: 801, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/39.jpg" },
    { username: "0xProxyTitan", won: 798, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/51.jpg" },

    { username: "0xGhostCipher", won: 795, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/23.jpg" },
    { username: "0xLoneCycler", won: 791, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/13.jpg" },
    { username: "0xChainFrost", won: 789, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/19.jpg" },
    { username: "0xHyperFlux", won: 785, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/28.jpg" },
    { username: "0xVortexCraze", won: 783, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/29.jpg" },

    { username: "0xStaticWolf", won: 780, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/58.jpg" },
    { username: "0xThetaBreaker", won: 778, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/55.jpg" },
    { username: "0xPolarMist", won: 775, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/46.jpg" },
    { username: "0xHellionArc", won: 772, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/24.jpg" },
    { username: "0xOrbWeaver", won: 770, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/74.jpg" },

    { username: "0xNeutronWisp", won: 768, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/16.jpg" },
    { username: "0xRogueBinary", won: 765, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/59.jpg" },
    { username: "0xSpectralNova", won: 762, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/69.jpg" },
    { username: "0xShadowPulse", won: 760, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/31.jpg" },
    { username: "0xCoreBreaker", won: 758, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/80.jpg" },

    { username: "0xCrimsonFold", won: 756, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/18.jpg" },
    { username: "0xChaosRider", won: 753, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/29.jpg" },
    { username: "0xRuneSpectre", won: 750, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/14.jpg" },
    { username: "0xAlphaCircuit", won: 748, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/36.jpg" },
    { username: "0xNebulaLock", won: 745, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/37.jpg" },

    { username: "0xRiftOrigin", won: 742, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/34.jpg" },
    { username: "0xPulseVector", won: 740, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/70.jpg" },
    { username: "0xDuskBreaker", won: 738, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/67.jpg" },
    { username: "0xSnowCrank", won: 736, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/53.jpg" },
    { username: "0xZenithBolt", won: 733, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/56.jpg" },

    { username: "0xJadeQuiver", won: 730, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/48.jpg" },
    { username: "0xThunderHelix", won: 728, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/41.jpg" },
    { username: "0xLunarFrost", won: 725, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/women/60.jpg" },
    { username: "0xTidalBreaker", won: 723, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/20.jpg" },
    { username: "0xSilentReign", won: 720, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/27.jpg" },
    { username: "0xHexVandal", won: 718, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/21.jpg" },
    { username: "0xFrostRanger", won: 716, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/49.jpg" },
    { username: "0xNeonHarvester", won: 714, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/84.jpg" },
    { username: "0xDataWraith", won: 712, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/31.jpg" },
    { username: "0xNovaGlyph", won: 710, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/43.jpg" },

    { username: "0xPhantomDrill", won: 708, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/33.jpg" },
    { username: "0xZenProxy", won: 706, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/women/24.jpg" },
    { username: "0xViperCrank", won: 704, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/30.jpg" },
    { username: "0xPulseReaver", won: 703, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/76.jpg" },
    { username: "0xShadowHelix", won: 701, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/14.jpg" },

    { username: "0xPrimeHarbor", won: 699, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/91.jpg" },
    { username: "0xEtherStrider", won: 698, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/40.jpg" },
    { username: "0xStormGlyph", won: 696, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/20.jpg" },
    { username: "0xMechaOrbit", won: 694, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/42.jpg" },
    { username: "0xVantaRogue", won: 693, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/72.jpg" },

    { username: "0xSolarCrypt", won: 692, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/36.jpg" },
    { username: "0xBinaryPhantom", won: 690, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/79.jpg" },
    { username: "0xCinderSpectre", won: 688, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/99.jpg" },
    { username: "0xDriftQuantum", won: 687, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/32.jpg" },
    { username: "0xThetaRanger", won: 685, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/47.jpg" },

    { username: "0xSilentHex", won: 684, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/54.jpg" },
    { username: "0xIronWhisper", won: 682, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/16.jpg" },
    { username: "0xFrostVector", won: 680, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/48.jpg" },
    { username: "0xCryptoNomad", won: 678, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/10.jpg" },
    { username: "0xNightGlyph", won: 676, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/25.jpg" },

    { username: "0xTitanCircuit", won: 675, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/11.jpg" },
    { username: "0xEclipseForge", won: 673, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/27.jpg" },
    { username: "0xIonBreaker", won: 671, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/26.jpg" },
    { username: "0xFeralNova", won: 670, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/women/46.jpg" },
    { username: "0xDriftWisp", won: 668, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/82.jpg" },

    { username: "0xBlitzCipher", won: 667, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/30.jpg" },
    { username: "0xNovaHarbinger", won: 665, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/38.jpg" },
    { username: "0xGhostHelix", won: 663, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/15.jpg" },
    { username: "0xOmegaRift", won: 662, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/98.jpg" },
    { username: "0xVantaSpectral", won: 660, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/women/12.jpg" },

    { username: "0xFrostHarbor", won: 658, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/15.jpg" },
    { username: "0xShadowBreaker", won: 657, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/17.jpg" },
    { username: "0xIronFractal", won: 656, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/women/78.jpg" },
    { username: "0xCircuitPhantom", won: 654, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/26.jpg" },
    { username: "0xNeonRiptide", won: 653, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/19.jpg" },

    { username: "0xThermalPulse", won: 652, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/86.jpg" },
    { username: "0xDriftEclipse", won: 651, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/52.jpg" },
    { username: "0xCryptFurion", won: 649, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/39.jpg" },
    { username: "0xLunarHelix", won: 648, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/92.jpg" },
    { username: "0xFluxReaver", won: 647, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/37.jpg" },

    { username: "0xSilentBolt", won: 646, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/50.jpg" },
    { username: "0xShadowCrank", won: 644, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/71.jpg" },
    { username: "0xNovaSpectral", won: 642, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/18.jpg" },
    { username: "0xTundraCipher", won: 641, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/43.jpg" },
    { username: "0xArcWarden", won: 640, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/women/25.jpg" },

    { username: "0xCircuitNimbus", won: 639, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/79.jpg" },
    { username: "0xPhantomGlyph", won: 638, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/54.jpg" },
    { username: "0xVoltHarbinger", won: 637, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/22.jpg" },
    { username: "0xDataRift", won: 636, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/13.jpg" },
    { username: "0xPulseZen", won: 635, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/12.jpg" },

    { username: "0xFuryCircuit", won: 633, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/91.jpg" },
    { username: "0xNightSentinel", won: 632, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/77.jpg" },
    { username: "0xFractalNomad", won: 631, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/35.jpg" },
    { username: "0xNullSpectre", won: 630, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/55.jpg" },
    { username: "0xLunarBreaker", won: 628, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/women/75.jpg" },

    { username: "0xStormEclipse", won: 627, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/69.jpg" },
    { username: "0xGlitchRunner", won: 626, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/90.jpg" },
    { username: "0xVoidHarbinger", won: 625, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/61.jpg" },
    { username: "0xHexBreaker", won: 624, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/63.jpg" },
    { username: "0xCircuitNova", won: 623, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/41.jpg" },

    { username: "0xNebulaCrafter", won: 622, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/60.jpg" },
    { username: "0xAlphaGhost", won: 621, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/women/81.jpg" },
    { username: "0xSolarWisp", won: 620, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/49.jpg" },
    { username: "0xTerraDrift", won: 619, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/62.jpg" },
    { username: "0xStormCircuit", won: 618, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/66.jpg" },

    { username: "0xCyberMarauder", won: 617, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/75.jpg" },
    { username: "0xZenithShade", won: 616, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/59.jpg" },
    { username: "0xGlitchNova", won: 615, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/87.jpg" },
    { username: "0xCoreSpectre", won: 614, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/51.jpg" },
    { username: "0xIronGlyph", won: 613, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/78.jpg" },

    { username: "0xZenHarbinger", won: 612, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/women/42.jpg" },
    { username: "0xNightOrbit", won: 611, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/64.jpg" },
    { username: "0xProxyRift", won: 609, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/80.jpg" },
    { username: "0xFluxBreaker", won: 608, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/62.jpg" },
    { username: "0xSpectralPulse", won: 607, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/17.jpg" },

    { username: "0xLunarWarden", won: 606, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/95.jpg" },
    { username: "0xDuskHarbinger", won: 605, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/45.jpg" },
    { username: "0xShadowVector", won: 603, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/women/28.jpg" },
    { username: "0xViperEclipse", won: 602, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/57.jpg" },
    { username: "0xThetaCrafter", won: 601, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/35.jpg" },
    { username: "0xGrinder1", won: 500, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "LootGO", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Lumiterra", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Levr Bet", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Drake Exchange", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Omnia Explorer", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "SeerTrade", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Monday Trade", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Symphony", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Kinetik AI", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "TeleMafia", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "Fluffle World", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "BRO.fun", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },
  { username: "0xGrinder1", won: 500, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/1.jpg" },

  // User 2
  { username: "0xGrinder2", won: 495, project: "Monad", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "LootGO", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Lumiterra", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Levr Bet", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Drake Exchange", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Omnia Explorer", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "SeerTrade", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Monday Trade", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Symphony", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Kinetik AI", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "TeleMafia", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "Fluffle World", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "BRO.fun", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },
  { username: "0xGrinder2", won: 495, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/women/2.jpg" },

  // User 3
  { username: "0xGrinder3", won: 490, project: "Monad", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "LootGO", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Nad.fun", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Kizzy Mobile", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Kuru Exchange", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Lumiterra", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Levr Bet", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Drake Exchange", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Omnia Explorer", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "SeerTrade", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Monday Trade", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Symphony", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Kinetik AI", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "TeleMafia", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "Fluffle World", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "BRO.fun", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },
  { username: "0xGrinder3", won: 490, project: "RareBet Sports", pfp: "https://randomuser.me/api/portraits/men/3.jpg" },


  ];



  const [selectedProject, setSelectedProject] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState("");

  const filteredProjects = projects.filter((p) =>
    p.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const filteredUsers = selectedProject
    ? allUsers.filter((u) => u.project === selectedProject)
    : allUsers;

  const maxInteractions = Math.max(...projects.map((p) => p.interactions));
  const minInteractions = Math.min(...projects.map((p) => p.interactions));

  const getColor = (val: number): string => {
    const ratio = (val - minInteractions) / (maxInteractions - minInteractions);
    const r = Math.round(100 + 100 * ratio);
    const g = Math.round(0 + 40 * ratio);
    const b = Math.round(180 + 60 * ratio);
    const a = 0.4 + 0.6 * ratio;
    return `rgba(${r}, ${g}, ${b}, ${a})`;
  };

  const handleProjectClick = (projName: string): void => {
    setSelectedProject(selectedProject === projName ? null : projName);
  };

  return (
    <div className="leaderboard-container">
      <div style={{ height: "60px" }} />

      {/* Search Bar */}
      <div className="search-wrapper">
        <input
          type="text"
          placeholder="Search for a project..."
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
          className="partner-search"
        />
      </div>

      <div className="leaderboard-content">
        {/* Left side */}
        <div className="interaction-grid">
          {filteredProjects.length > 0 ? (
            filteredProjects.map((proj, i) => {
              const color = getColor(proj.interactions);
              const isActive = selectedProject === proj.name;
              const chartData = proj.trend.map((val, idx) => ({
                day: idx + 1,
                value: val,
              }));

              return (
                <div
                  key={i}
                  className={`interaction-rect ${isActive ? "active" : ""}`}
                  style={{
                    flexGrow: proj.interactions / 10,
                    backgroundColor: color,
                    opacity: selectedProject && !isActive ? 0.5 : 1,
                    border: "2px solid white",
                    cursor: "pointer",
                    position: "relative",
                  }}
                  onClick={() => handleProjectClick(proj.name)}
                >
                  <div className="mini-chart">
                    <ResponsiveContainer width="100%" height={50}>
                      <LineChart data={chartData}>
                        <Line
                          type="monotone"
                          dataKey="value"
                          stroke="#ffd700"
                          strokeWidth={2}
                          dot={false}
                          isAnimationActive={true}
                        />
                        <Tooltip
                          contentStyle={{
                            background: "rgba(255,255,255,0.8)",
                            borderRadius: "6px",
                            color: "#000",
                          }}
                        />
                      </LineChart>
                    </ResponsiveContainer>
                  </div>
                  <div className="rect-label">
                    <img
                      src={proj.logo}
                      alt={proj.name}
                      className="proj-logo"
                    />
                    <span className="proj-name">{proj.name}</span>
                    <span className="proj-interactions">
                      {proj.interactions} interactions
                    </span>
                  </div>
                </div>
              );
            })
          ) : (
            <p style={{ color: "#fff", textAlign: "center", width: "100%" }}>
              No matching projects found.
            </p>
          )}
        </div>

        {/* Right side leaderboard */}
        <div className="user-leaderboard">
          <h2>
            {selectedProject
              ? `${selectedProject} Top Users`
              : "Global Rankings"}
          </h2>
          <ul>
            {filteredUsers.map((user, i) => (
              <li key={i} className="user-entry">
                <span className="rank">#{i + 1}</span>
                <div className="user-info">
                  <img src={user.pfp} alt={user.username} className="user-pfp" />
                  <span className="username">{user.username}</span>
                </div>
                <span className="won">{user.won} WON</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
};

export default Leaderboard;
