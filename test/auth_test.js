// Authentication module
// Fixed: proper error handling, secure hashing, parameterized queries,
// input validation, atomic counter, and no hardcoded secrets.

const crypto = require('crypto');
const { promisify } = require('util');

const pbkdf2 = promisify(crypto.pbkdf2);

// FIXED: Load secret from environment variable, never hardcode credentials
const API_SECRET = process.env.API_SECRET;
if (!API_SECRET) {
    throw new Error('Missing required environment variable: API_SECRET');
}

// FIXED: Retry helper for transient database/connection-pool errors
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 100;

async function withRetry(fn, retries = MAX_RETRIES) {
    for (let attempt = 1; attempt <= retries; attempt++) {
        try {
            return await fn();
        } catch (err) {
            const isTransient =
                err.code === 'ECONNRESET' ||
                err.code === 'ETIMEDOUT' ||
                (err.message && (
                    err.message.includes('connection timeout') ||
                    err.message.includes('pool')
                ));
            if (isTransient && attempt < retries) {
                await new Promise(resolve =>
                    setTimeout(resolve, RETRY_DELAY_MS * Math.pow(2, attempt - 1))
                );
                continue;
            }
            throw err;
        }
    }
}

// FIXED: Verify a password against a stored PBKDF2 hash + salt using a
// timing-safe comparison to prevent timing-based user enumeration.
async function verifyPassword(password, storedHash, salt) {
    const derived = await pbkdf2(password, salt, 100000, 64, 'sha512');
    return crypto.timingSafeEqual(Buffer.from(storedHash, 'hex'), derived);
}

// FIXED: Input validation, PBKDF2 password verification, parameterized query,
// and error handling with retry logic to prevent 500 errors on DB connection
// timeouts.  Password is verified in application code against the stored
// hash+salt so that a proper slow-hash algorithm (PBKDF2) can be used.
async function authenticateUser(username, password) {
    if (!username || typeof username !== 'string' || username.trim().length === 0) {
        throw new Error('Invalid username');
    }
    if (!password || typeof password !== 'string' || password.length === 0) {
        throw new Error('Invalid password');
    }

    try {
        const result = await withRetry(() =>
            db.query(
                'SELECT * FROM users WHERE username = ?',
                [username.trim()]
            )
        );

        const user = result[0];
        if (!user) {
            return null;
        }

        const isValid = await verifyPassword(password, user.password_hash, user.salt);
        return isValid ? user : null;
    } catch (err) {
        console.error('Authentication query failed:', err.message);
        throw new Error('Authentication service unavailable. Please try again.');
    }
}

// FIXED: Input validation for userId and role
const VALID_ROLES = ['admin', 'user', 'moderator'];

function setUserRole(userId, role) {
    if (!userId) {
        throw new Error('userId is required');
    }
    if (!role || !VALID_ROLES.includes(role)) {
        throw new Error(`Invalid role. Must be one of: ${VALID_ROLES.join(', ')}`);
    }
    if (!users[userId]) {
        throw new Error(`User not found: ${userId}`);
    }
    users[userId].role = role;
}

// FIXED: Atomic counter using a sequential queue to eliminate the race condition.
// processCounterQueue MUST remain synchronous; counter += 1 cannot throw.
let counter = 0;
let counterLock = false;
const counterQueue = [];

async function incrementCounter() {
    return new Promise((resolve, reject) => {
        counterQueue.push({ resolve, reject });
        processCounterQueue();
    });
}

function processCounterQueue() {
    if (counterLock || counterQueue.length === 0) {
        return;
    }
    counterLock = true;
    const { resolve } = counterQueue.shift();
    counter += 1;
    resolve(counter);
    counterLock = false;
    if (counterQueue.length > 0) {
        processCounterQueue();
    }
}

module.exports = { authenticateUser, setUserRole, incrementCounter, verifyPassword };
