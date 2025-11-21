// Import the functions you need from the SDKs you need
import { initializeApp } from "firebase/app";
import { getAnalytics } from "firebase/analytics";
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
  apiKey: "AIzaSyD3Md8vlOQDg4QoTRJuwNmrv3mg11WMDss",
  authDomain: "worldofnads-1afcf.firebaseapp.com",
  databaseURL: "https://worldofnads-1afcf-default-rtdb.firebaseio.com",
  projectId: "worldofnads-1afcf",
  storageBucket: "worldofnads-1afcf.firebasestorage.app",
  messagingSenderId: "129481786742",
  appId: "1:129481786742:web:4bf0e136f1a6e9a72fa657",
  measurementId: "G-QP22W5T17Z"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const analytics = getAnalytics(app);