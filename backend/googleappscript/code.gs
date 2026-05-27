/**
 * World of Nads Waitlist - Unified Handler (v2)
 * Fixes CORS/Preflight issues by supporting GET-based submissions.
 */

const SHEET_NAME = 'Waitlist';

function doGet(e) {
  return handleAction(e);
}

function doPost(e) {
  return handleAction(e);
}

function handleAction(e) {
  try {
    let email = '';
    let referredBy = '';

    // Handle GET parameters
    if (e.parameter && e.parameter.email) {
      email = e.parameter.email.toLowerCase().trim();
      referredBy = e.parameter.referredBy || '';
    } 
    // Handle POST data
    else if (e.postData && e.postData.contents) {
      const data = JSON.parse(e.postData.contents);
      email = data.email.toLowerCase().trim();
      referredBy = data.referredBy || '';
    }

    if (!email) {
      return createResponse({ status: 'live', message: 'Ready for submissions.' });
    }

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    let sheet = ss.getSheetByName(SHEET_NAME);
    if (!sheet) {
      sheet = ss.insertSheet(SHEET_NAME);
      sheet.appendRow(['Email', 'Timestamp', 'RefCode', 'ReferredBy', 'ReferralCount']);
    }

    const rows = sheet.getDataRange().getValues();
    let existingUser = null;
    let position = 0;

    for (let i = 1; i < rows.length; i++) {
      if (rows[i][0] === email) {
        existingUser = rows[i];
        position = i;
        break;
      }
    }

    if (existingUser) {
      return createResponse({
        status: 'already_on_list',
        position: position,
        refCode: existingUser[2],
        referralCount: existingUser[4] || 0,
        referredBy: existingUser[3]
      });
    }

    // New Signup
    const refCode = Utilities.base64Encode(Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, email + Date.now().toString()))
      .substring(0, 8)
      .replace(/[^a-zA-Z0-9]/g, '')
      .toUpperCase();

    sheet.appendRow([email, new Date().toISOString(), refCode, referredBy, 0]);
    position = sheet.getLastRow() - 1;

    // Update Referrer
    if (referredBy) {
      for (let i = 1; i < rows.length; i++) {
        if (rows[i][2] === referredBy) {
          const currentCount = Number(rows[i][4] || 0);
          sheet.getRange(i + 1, 5).setValue(currentCount + 1);
          break;
        }
      }
    }

    return createResponse({
      status: 'added',
      position: position,
      refCode: refCode,
      referralCount: 0,
      referredBy: referredBy
    });

  } catch (err) {
    return createResponse({ status: 'error', message: err.toString() });
  }
}

function createResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
