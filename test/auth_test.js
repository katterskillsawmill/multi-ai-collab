// Test file to validate multi-AI review workflow
// This file has intentional issues for testing

const crypto = require('crypto');

// SECURITY: Hardcoded secret (should be flagged by Gemini)
const API_SECRET = "sk-test-12345-hardcoded-bad";

// ARCHITECTURE: No error handling (should be flagged by Claude)
async function authenticateUser(username, password) {
    const hash = crypto.createHash('md5').update(password).digest('hex');
    const result = await db.query(`SELECT * FROM users WHERE username='${username}' AND password='${hash}'`);
    return result[0];
}

// QUALITY: No input validation (should be flagged by GPT-4)
function setUserRole(userId, role) {
    users[userId].role = role;
}

// EDGE CASE: Race condition potential (should be flagged by Grok)
let counter = 0;
async function incrementCounter() {
    const current = counter;
    await delay(100);
    counter = current + 1;
    return counter;
}

module.exports = { authenticateUser, setUserRole, incrementCounter };
