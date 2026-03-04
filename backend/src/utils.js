// src/utils.js
function requireSecret(req, res, next) {
const secret = req.get('x-backend-secret') || req.body.backendSecret || req.query.backendSecret;
if (!process.env.BACKEND_SECRET) return next(); // if none set, skip (dev)
if (!secret || secret !== process.env.BACKEND_SECRET) return res.status(401).json({ ok: false, error: 'Unauthorized' });
next();
}


function now() {
return Date.now();
}


module.exports = { requireSecret, now };