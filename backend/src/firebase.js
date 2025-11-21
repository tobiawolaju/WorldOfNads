// src/firebase.js
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
require('dotenv').config();


const SERVICE_ACCOUNT_PATH = process.env.SERVICE_ACCOUNT_PATH || './serviceAccount.json';
const DB_URL = process.env.FIREBASE_DB_URL;


if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
console.warn('WARNING: service account JSON not found at', SERVICE_ACCOUNT_PATH);
}


const serviceAccount = fs.existsSync(SERVICE_ACCOUNT_PATH)
? require(path.resolve(SERVICE_ACCOUNT_PATH))
: null;


if (!admin.apps.length) {
admin.initializeApp({
credential: serviceAccount ? admin.credential.cert(serviceAccount) : admin.credential.applicationDefault(),
databaseURL: DB_URL,
});
}


const db = admin.database();


module.exports = { admin, db };