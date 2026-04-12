/**
 * Google Apps Script for World of Nads Waitlist
 * 
 * SETUP INSTRUCTIONS:
 * 1. Create a new Google Sheet.
 * 2. Go to Extensions > Apps Script.
 * 3. Replace the code in the editor with this content.
 * 4. Deploy > New Deployment > Web App.
 * 5. Set "Execute as" to "Me" and "Who has access" to "Anyone".
 * 6. Copy the Web App URL and paste it into EmailCapture.tsx.
 */

const SHEET_NAME = 'Waitlist';

function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const email = data.email.toLowerCase().trim();
    const referredBy = data.referredBy || '';
    
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
        position = i; // Position is based on row index (1-based for data lines)
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
    // 1. Generate Ref Code (Simple random string)
    const refCode = Utilities.base64Encode(Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, email + Date.now().toString()))
      .substring(0, 8)
      .replace(/[^a-zA-Z0-9]/g, '')
      .toUpperCase();

    // 2. Append User
    sheet.appendRow([email, new Date().toISOString(), refCode, referredBy, 0]);
    position = sheet.getLastRow() - 1;

    // 3. Update Ref Count for the referrer if exists
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

// Simple GET test
function doGet(e) {
  return createResponse({ status: 'live', message: 'World of Nads Waitlist API is active.' });
}
